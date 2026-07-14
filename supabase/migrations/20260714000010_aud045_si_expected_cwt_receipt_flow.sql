-- PXL-AUD-045
-- Sales Invoice expected CWT must be validated against the customer's active
-- default CWT ATC and persisted so Official Receipts can inherit the same ATC,
-- VAT-exclusive base, and expected withholding amount.

ALTER TABLE sales_invoices
  ADD COLUMN IF NOT EXISTS cwt_atc_code_id UUID REFERENCES atc_codes(id),
  ADD COLUMN IF NOT EXISTS cwt_tax_base NUMERIC(15,2);

COMMENT ON COLUMN sales_invoices.cwt_atc_code_id IS
  'Customer default CWT ATC used to validate the expected CWT amount on this sales invoice.';

COMMENT ON COLUMN sales_invoices.cwt_tax_base IS
  'VAT-exclusive taxable base used to validate sales_invoices.cwt_amount_expected.';

CREATE OR REPLACE FUNCTION fn_save_sales_invoice(
  p_invoice_id  UUID,
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_si_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_customer_id    UUID;
  v_invoice_date   DATE;
  v_si_number      TEXT;
  v_fiscal_period  UUID;
  v_current_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
  v_customer_cwt   BOOLEAN;
  v_customer_atc   UUID;
  v_cwt_amount     NUMERIC(15,2);
  v_cwt_atc        UUID;
  v_cwt_base       NUMERIC(15,2);
  v_cwt_rate       NUMERIC(9,4);
  v_cwt_expected   NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;
  v_customer_id := (p_header->>'customer_id')::UUID;
  v_invoice_date := (p_header->>'date')::DATE;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;

  SELECT is_subject_to_cwt, default_cwt_atc_code_id
    INTO v_customer_cwt, v_customer_atc
  FROM customers
  WHERE id = v_customer_id
    AND company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_invoice_date
    AND end_date   >= v_invoice_date
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_amount, cwt_amount_expected, cwt_atc_code_id, cwt_tax_base,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_si_number, v_invoice_date, v_fiscal_period,
      v_customer_id, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0, NULL, NULL, NULL,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_si_id;

  ELSE
    SELECT id, status INTO v_si_id, v_current_status
    FROM sales_invoices WHERE id = p_invoice_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sales invoice not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % sales invoice. Revert to draft first.', v_current_status;
    END IF;

    UPDATE sales_invoices SET
      branch_id = v_branch_id, date = v_invoice_date, fiscal_period_id = v_fiscal_period,
      customer_id = v_customer_id,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_vat_amount = 0, total_amount = 0,
      cwt_amount_expected = NULL, cwt_atc_code_id = NULL, cwt_tax_base = NULL,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_si_id;
  END IF;

  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    CASE v_vat_class
      WHEN 'regular' THEN v_taxable := v_taxable + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE v_exempt := v_exempt + v_net;
    END CASE;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number,
      item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, vat_amount, total_amount,
      revenue_account_id, created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID,
      v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0),
      v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line item is required';
  END IF;

  v_cwt_amount := NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC;
  IF COALESCE(v_cwt_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Expected CWT cannot be negative';
  END IF;

  IF COALESCE(v_cwt_amount, 0) > 0 THEN
    IF NOT COALESCE(v_customer_cwt, false) THEN
      RAISE EXCEPTION 'Expected CWT is only allowed when the customer is subject to CWT';
    END IF;
    IF v_customer_atc IS NULL THEN
      RAISE EXCEPTION 'Customer is subject to CWT but has no default CWT ATC';
    END IF;

    v_cwt_atc := COALESCE(NULLIF(p_header->>'cwt_atc_code_id', '')::UUID, v_customer_atc);
    IF v_cwt_atc <> v_customer_atc THEN
      RAISE EXCEPTION 'Sales invoice expected CWT ATC must match the customer default CWT ATC';
    END IF;
    IF NOT fn_atc_code_is_current(v_cwt_atc, 'ewt', v_invoice_date) THEN
      RAISE EXCEPTION 'Customer default CWT ATC is not active/current on the sales invoice date';
    END IF;

    SELECT rate INTO v_cwt_rate
    FROM atc_codes
    WHERE id = v_cwt_atc;

    v_cwt_base := COALESCE(
      NULLIF(p_header->>'cwt_tax_base', '')::NUMERIC,
      ROUND(v_taxable + v_zero_rated + v_exempt, 2)
    );
    IF COALESCE(v_cwt_base, 0) <= 0 THEN
      RAISE EXCEPTION 'Expected CWT taxable base must be positive when expected CWT is recorded';
    END IF;

    v_cwt_expected := ROUND(v_cwt_base * COALESCE(v_cwt_rate, 0) / 100, 2);
    IF ABS(v_cwt_expected - v_cwt_amount) > 0.02 THEN
      RAISE EXCEPTION 'Sales invoice expected CWT % does not match customer ATC expected % on base %',
        v_cwt_amount, v_cwt_expected, v_cwt_base;
    END IF;
  ELSE
    v_cwt_amount := NULL;
    v_cwt_atc := NULL;
    v_cwt_base := NULL;
  END IF;

  UPDATE sales_invoices SET
    total_taxable_amount    = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount     = v_exempt,
    total_vat_amount        = v_total_vat,
    total_amount            = v_grand_total,
    cwt_amount_expected     = v_cwt_amount,
    cwt_atc_code_id         = v_cwt_atc,
    cwt_tax_base            = v_cwt_base,
    updated_at              = NOW(),
    updated_by              = auth.uid()
  WHERE id = v_si_id;

  RETURN v_si_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_sales_invoice(UUID, JSONB, JSONB) TO authenticated;
