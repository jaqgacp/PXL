-- PXL-AUD-037: AP EWT timing follows source/accrual recognition by default.
-- RR 12-2001/RMC 10-2018 basis: withholding arises when income is paid,
-- payable, or accrued/recorded, whichever comes first.  Keep an explicit
-- company-level payment policy for legacy/payment-basis workflows.

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS ap_ewt_recognition_policy TEXT NOT NULL DEFAULT 'accrual_at_source';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'companies_ap_ewt_recognition_policy_chk'
  ) THEN
    ALTER TABLE companies
      ADD CONSTRAINT companies_ap_ewt_recognition_policy_chk
      CHECK (ap_ewt_recognition_policy IN ('accrual_at_source', 'payment'));
  END IF;
END;
$$;

COMMENT ON COLUMN companies.ap_ewt_recognition_policy IS
  'AP EWT recognition timing: accrual_at_source records EWT at vendor bill/source document; payment preserves legacy PV withholding.';

ALTER TABLE vendor_bill_lines
  ADD COLUMN IF NOT EXISTS ewt_atc_code_id UUID REFERENCES atc_codes(id),
  ADD COLUMN IF NOT EXISTS ewt_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS ewt_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ewt_income_nature TEXT,
  ADD COLUMN IF NOT EXISTS ewt_variance_reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vendor_bill_lines_ewt_base_nonnegative_chk'
  ) THEN
    ALTER TABLE vendor_bill_lines
      ADD CONSTRAINT vendor_bill_lines_ewt_base_nonnegative_chk
      CHECK (ewt_tax_base IS NULL OR ewt_tax_base >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vendor_bill_lines_ewt_amount_nonnegative_chk'
  ) THEN
    ALTER TABLE vendor_bill_lines
      ADD CONSTRAINT vendor_bill_lines_ewt_amount_nonnegative_chk
      CHECK (ewt_amount >= 0);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_vendor_bill_lines_ewt_atc
  ON vendor_bill_lines (company_id, ewt_atc_code_id)
  WHERE ewt_atc_code_id IS NOT NULL;

CREATE OR REPLACE FUNCTION fn_company_ap_ewt_policy(p_company_id UUID)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT c.ap_ewt_recognition_policy
     FROM companies c
     WHERE c.id = p_company_id),
    'accrual_at_source'
  );
$$;

CREATE OR REPLACE FUNCTION fn_vendor_bill_accrued_ewt_amount(p_bill_id UUID)
RETURNS NUMERIC
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH bill AS (
    SELECT vb.id, vb.company_id
    FROM vendor_bills vb
    WHERE vb.id = p_bill_id
      AND is_company_member(vb.company_id)
  ),
  posted_tax AS (
    SELECT COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS amount
    FROM tax_detail_entries tde
    JOIN bill b ON b.id = tde.source_doc_id
    WHERE tde.source_doc_type = 'VB'
      AND tde.tax_kind = 'ewt_payable'
      AND tde.is_reversal = false
      AND NOT EXISTS (
        SELECT 1
        FROM tax_detail_entries r
        WHERE r.reverses_tax_detail_id = tde.id
      )
  ),
  bill_lines AS (
    SELECT COALESCE(SUM(vbl.ewt_amount), 0)::NUMERIC(15,2) AS amount
    FROM vendor_bill_lines vbl
    JOIN bill b ON b.id = vbl.vendor_bill_id
    WHERE vbl.ewt_amount > 0
  )
  SELECT COALESCE(NULLIF((SELECT amount FROM posted_tax), 0), (SELECT amount FROM bill_lines), 0)::NUMERIC(15,2);
$$;

CREATE OR REPLACE FUNCTION fn_vendor_bill_has_accrued_ewt(p_bill_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(fn_vendor_bill_accrued_ewt_amount(p_bill_id), 0) > 0;
$$;

CREATE OR REPLACE FUNCTION fn_require_pvl_ewt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_document_date DATE;
BEGIN
  SELECT voucher_date INTO v_document_date
  FROM payment_vouchers WHERE id = NEW.payment_voucher_id;

  IF NEW.vendor_bill_id IS NOT NULL
     AND fn_vendor_bill_has_accrued_ewt(NEW.vendor_bill_id)
     AND (
       COALESCE(NEW.ewt_amount, 0) > 0
       OR NEW.atc_code_id IS NOT NULL
       OR NEW.ewt_tax_base IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Vendor bill % already accrued EWT at source; do not withhold EWT again on the payment voucher.',
      NEW.vendor_bill_id;
  END IF;

  PERFORM fn_validate_payment_voucher_line_ewt(
    NEW.company_id,
    NEW.payment_amount,
    NEW.ewt_amount,
    NEW.atc_code_id,
    NEW.ewt_tax_base,
    NEW.ewt_variance_reason,
    v_document_date
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_ewt_ready(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line          RECORD;
  v_header_ewt    NUMERIC(15,2);
  v_line_ewt      NUMERIC(15,2);
  v_header_cash   NUMERIC(15,2);
  v_line_cash     NUMERIC(15,2);
  v_document_date DATE;
BEGIN
  SELECT COALESCE(total_ewt, 0), COALESCE(total_amount, 0), voucher_date
  INTO v_header_ewt, v_header_cash, v_document_date
  FROM payment_vouchers WHERE id = p_voucher_id;

  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found.';
  END IF;

  SELECT COALESCE(SUM(ewt_amount), 0), COALESCE(SUM(payment_amount), 0)
  INTO v_line_ewt, v_line_cash
  FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id;

  IF ABS(v_header_ewt - v_line_ewt) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total EWT % does not match line EWT total %.', v_header_ewt, v_line_ewt;
  END IF;

  IF ABS(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total amount % does not match line payment total %.', v_header_cash, v_line_cash;
  END IF;

  FOR v_line IN
    SELECT company_id, vendor_bill_id, payment_amount, ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
    FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id
  LOOP
    IF v_line.vendor_bill_id IS NOT NULL
       AND fn_vendor_bill_has_accrued_ewt(v_line.vendor_bill_id)
       AND (
         COALESCE(v_line.ewt_amount, 0) > 0
         OR v_line.atc_code_id IS NOT NULL
         OR v_line.ewt_tax_base IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Vendor bill % already accrued EWT at source; do not withhold EWT again on the payment voucher.',
        v_line.vendor_bill_id;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.ewt_amount,
      v_line.atc_code_id,
      v_line.ewt_tax_base,
      v_line.ewt_variance_reason,
      v_document_date
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_save_vendor_bill(
  p_bill_id UUID,
  p_header  JSONB,
  p_lines   JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_bill_id        UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_supplier_id    UUID;
  v_rr_id          UUID;
  v_bill_number    TEXT;
  v_current_status TEXT;
  v_fiscal_period  UUID;
  v_document_date  DATE;
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
  v_total_ewt      NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
  v_ewt_policy     TEXT;
  v_supplier_ewt   BOOLEAN := false;
  v_supplier_atc   UUID;
  v_line_ewt_atc   UUID;
  v_line_ewt_base  NUMERIC(15,2);
  v_line_ewt_amt   NUMERIC(15,2);
  v_line_ewt_rate  NUMERIC(8,4);
  v_line_ewt_desc  TEXT;
  v_line_ewt_nature TEXT;
  v_line_ewt_reason TEXT;
BEGIN
  v_company_id    := (p_header->>'company_id')::UUID;
  v_branch_id     := NULLIF(p_header->>'branch_id', '')::UUID;
  v_supplier_id   := NULLIF(p_header->>'supplier_id', '')::UUID;
  v_rr_id         := NULLIF(BTRIM(p_header->>'rr_id'), '')::UUID;
  v_document_date := (p_header->>'bill_date')::DATE;
  v_ewt_policy    := fn_company_ap_ewt_policy(v_company_id);

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  SELECT COALESCE(s.is_subject_to_ewt, false), s.default_atc_code_id
  INTO v_supplier_ewt, v_supplier_atc
  FROM suppliers s
  WHERE s.id = v_supplier_id
    AND s.company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF v_rr_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM receiving_reports rr
    WHERE rr.id = v_rr_id
      AND rr.company_id = v_company_id
      AND rr.supplier_id = v_supplier_id
      AND rr.status = 'received'
  ) THEN
    RAISE EXCEPTION 'Receiving report must be received and belong to the same company and supplier';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_document_date
    AND end_date >= v_document_date
    AND is_locked = false
  LIMIT 1;

  IF p_bill_id IS NULL THEN
    v_bill_number := fn_next_document_number(v_company_id, v_branch_id, 'VB');
    INSERT INTO vendor_bills (
      company_id, branch_id, supplier_id, rr_id,
      supplier_name_snapshot, supplier_tin_snapshot,
      bill_number, supplier_invoice_number, bill_date, due_date, fiscal_period_id,
      payment_terms_id, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_input_vat_amount, total_amount, ewt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_supplier_id, v_rr_id,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_bill_number, NULLIF(p_header->>'supplier_invoice_number', ''),
      v_document_date, NULLIF(p_header->>'due_date', '')::DATE,
      v_fiscal_period, NULLIF(p_header->>'payment_terms_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0,
      NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_bill_id;
  ELSE
    SELECT id, status INTO v_bill_id, v_current_status
    FROM vendor_bills
    WHERE id = p_bill_id
      AND company_id = v_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Vendor bill not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % vendor bill. Revert to draft first.', v_current_status;
    END IF;

    UPDATE vendor_bills SET
      branch_id = v_branch_id,
      supplier_id = v_supplier_id,
      rr_id = v_rr_id,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_invoice_number = NULLIF(p_header->>'supplier_invoice_number', ''),
      bill_date = v_document_date,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      fiscal_period_id = v_fiscal_period,
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''),
      memo = NULLIF(p_header->>'memo', ''),
      ewt_amount_expected = NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      total_taxable_amount = 0,
      total_zero_rated_amount = 0,
      total_exempt_amount = 0,
      total_input_vat_amount = 0,
      total_amount = 0,
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_bill_id;
  END IF;

  DELETE FROM vendor_bill_lines WHERE vendor_bill_id = v_bill_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc
    JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE
      WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2)
      ELSE 0
    END;
    v_total_line := v_net + v_vat_amt;

    v_line_ewt_atc := NULL;
    v_line_ewt_base := NULL;
    v_line_ewt_amt := 0;
    v_line_ewt_rate := NULL;
    v_line_ewt_desc := NULL;
    v_line_ewt_nature := NULL;
    v_line_ewt_reason := NULL;

    IF v_ewt_policy = 'accrual_at_source' THEN
      v_line_ewt_atc := COALESCE(
        NULLIF(BTRIM(v_line->>'ewt_atc_code_id'), '')::UUID,
        CASE WHEN v_supplier_ewt THEN v_supplier_atc ELSE NULL END
      );
      v_line_ewt_base := NULLIF(BTRIM(v_line->>'ewt_tax_base'), '')::NUMERIC;
      v_line_ewt_amt := COALESCE(NULLIF(BTRIM(v_line->>'ewt_amount'), '')::NUMERIC, 0);
      v_line_ewt_nature := NULLIF(BTRIM(v_line->>'ewt_income_nature'), '');
      v_line_ewt_reason := NULLIF(BTRIM(v_line->>'ewt_variance_reason'), '');

      IF v_line_ewt_atc IS NOT NULL THEN
        SELECT ac.rate, ac.description
        INTO v_line_ewt_rate, v_line_ewt_desc
        FROM atc_codes ac
        WHERE ac.id = v_line_ewt_atc
          AND ac.is_active = true
          AND ac.deprecated_at IS NULL
          AND ac.tax_category = 'ewt'
          AND ac.effective_from <= v_document_date
          AND (ac.effective_to IS NULL OR ac.effective_to >= v_document_date);

        IF v_line_ewt_rate IS NULL THEN
          RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on vendor bill date %. ', v_document_date;
        END IF;

        v_line_ewt_base := ROUND(COALESCE(v_line_ewt_base, v_net), 2);
        IF (NOT (v_line ? 'ewt_amount')) OR NULLIF(BTRIM(v_line->>'ewt_amount'), '') IS NULL THEN
          v_line_ewt_amt := ROUND(v_line_ewt_base * v_line_ewt_rate / 100.0, 2);
        END IF;
        v_line_ewt_nature := COALESCE(
          v_line_ewt_nature,
          NULLIF(BTRIM(v_line->>'description'), ''),
          v_line_ewt_desc
        );
      END IF;

      IF v_line_ewt_atc IS NOT NULL
         OR COALESCE(v_line_ewt_base, 0) > 0
         OR COALESCE(v_line_ewt_amt, 0) > 0 THEN
        PERFORM fn_validate_payment_voucher_line_ewt(
          v_company_id,
          0,
          v_line_ewt_amt,
          v_line_ewt_atc,
          v_line_ewt_base,
          v_line_ewt_reason,
          v_document_date
        );
      END IF;
    END IF;

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt + v_net;
    END CASE;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_total_ewt   := v_total_ewt + COALESCE(v_line_ewt_amt, 0);
    v_has_lines   := true;

    INSERT INTO vendor_bill_lines (
      vendor_bill_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, input_vat_amount, total_amount,
      expense_account_id, ewt_atc_code_id, ewt_tax_base, ewt_amount,
      ewt_income_nature, ewt_variance_reason, created_by, updated_by
    ) VALUES (
      v_bill_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      v_line_ewt_atc, v_line_ewt_base, COALESCE(v_line_ewt_amt, 0),
      v_line_ewt_nature, v_line_ewt_reason,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line is required';
  END IF;

  UPDATE vendor_bills SET
    total_taxable_amount = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt,
    total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total,
    ewt_amount_expected = CASE
      WHEN v_ewt_policy = 'accrual_at_source' THEN ROUND(v_total_ewt, 2)
      ELSE ewt_amount_expected
    END,
    updated_at = NOW()
  WHERE id = v_bill_id;

  RETURN v_bill_id;
END;
$function$;

CREATE OR REPLACE FUNCTION fn_post_vendor_bill(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec vendor_bills%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_tax RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
  v_accrued_ewt NUMERIC(15,2) := 0;
  v_ap_credit NUMERIC(15,2) := 0;
BEGIN
  v_begin := fn_begin_source_posting(
    'VB', p_bill_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM vendor_bills WHERE id = p_bill_id;
  PERFORM fn_validate_vendor_bill_accounting_ready(p_bill_id);
  PERFORM fn_validate_vendor_bill_vat_registration(p_bill_id);
  PERFORM fn_validate_invoice_posting_totals('VB', p_bill_id);
  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT COALESCE(SUM(vbl.ewt_amount), 0)::NUMERIC(15,2)
  INTO v_accrued_ewt
  FROM vendor_bill_lines vbl
  WHERE vbl.vendor_bill_id = v_rec.id;

  IF v_accrued_ewt > 0 AND v_cfg.ewt_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_ap_credit := ROUND(v_rec.total_amount - v_accrued_ewt, 2);
  IF v_ap_credit <= 0 THEN
    RAISE EXCEPTION 'Vendor bill source EWT % cannot equal or exceed bill total %.',
      v_accrued_ewt, v_rec.total_amount;
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date,
    'Vendor Bill ' || v_rec.bill_number || ' - ' || v_rec.supplier_name_snapshot,
    'VB', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  FOR v_line IN
    SELECT vbl.expense_account_id, SUM(vbl.net_amount) AS net_sum,
           vbl.description AS line_description
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.expense_account_id IS NOT NULL
    GROUP BY vbl.expense_account_id, vbl.description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.expense_account_id,
      'Expense - ' || v_line.line_description,
      v_line.net_sum, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_debit := v_total_debit + v_line.net_sum;
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.input_vat_account_id,
      'Input VAT - ' || v_rec.bill_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_debit := v_total_debit + v_rec.total_input_vat_amount;
    v_line_no := v_line_no + 1;
  END IF;

  PERFORM fn_add_posting_line(
    v_je_id, v_line_no, v_cfg.ap_account_id,
    'AP - ' || v_rec.supplier_name_snapshot,
    0, v_ap_credit,
    v_rec.branch_id, NULL, NULL
  );
  v_line_no := v_line_no + 1;

  IF v_accrued_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ewt_payable_account_id,
      'EWT accrued - ' || v_rec.bill_number,
      0, v_accrued_ewt,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  IF ABS((v_ap_credit + v_accrued_ewt) - v_total_debit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.',
      v_total_debit, v_ap_credit + v_accrued_ewt;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE vendor_bills
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT vbl.vat_code_id,
           SUM(vbl.net_amount) AS tax_base,
           COALESCE(SUM(vbl.input_vat_amount), 0) AS tax_amount
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY vbl.vat_code_id
    HAVING SUM(vbl.net_amount) <> 0 OR COALESCE(SUM(vbl.input_vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, NULL,
      'input_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END LOOP;

  FOR v_tax IN
    SELECT vbl.id, vbl.ewt_atc_code_id, vbl.ewt_tax_base, vbl.ewt_amount,
           vbl.ewt_income_nature, ac.rate AS ewt_rate
    FROM vendor_bill_lines vbl
    LEFT JOIN atc_codes ac ON ac.id = vbl.ewt_atc_code_id
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, v_tax.id,
      'ewt_payable', NULL, NULL, v_tax.ewt_atc_code_id,
      v_tax.ewt_tax_base, v_tax.ewt_rate, v_tax.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_tax.ewt_income_nature
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'VB', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.bill_date, 'ewt_recognition', 'accrual_at_source')
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_save_payment_voucher(
  p_voucher_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_voucher_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_voucher_number TEXT;
  v_current_status TEXT;
  v_document_date  DATE;
  v_line           JSONB;
  v_bill_id        UUID;
  v_pay_amt        NUMERIC(15,2);
  v_ewt_amt        NUMERIC(15,2);
  v_ewt_base       NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
  v_accrued_ewt    NUMERIC(15,2);
  v_line_settlement NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  v_document_date := (p_header->>'voucher_date')::DATE;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_bill_id := NULLIF(v_line->>'vendor_bill_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_ewt_amt := COALESCE((v_line->>'ewt_amount')::NUMERIC, 0);
    v_ewt_base := NULLIF(v_line->>'ewt_tax_base', '')::NUMERIC;
    CONTINUE WHEN v_bill_id IS NULL OR (v_pay_amt + v_ewt_amt) <= 0;

    IF NOT EXISTS (SELECT 1 FROM vendor_bills WHERE id = v_bill_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Vendor bill % does not belong to this company', v_bill_id;
    END IF;

    v_accrued_ewt := fn_vendor_bill_accrued_ewt_amount(v_bill_id);
    IF v_accrued_ewt > 0
       AND (
         v_ewt_amt > 0
         OR v_ewt_base IS NOT NULL
         OR NULLIF(v_line->>'atc_code_id', '') IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Vendor bill % already accrued EWT at source; do not withhold EWT again on the payment voucher.',
        v_bill_id;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_company_id,
      v_pay_amt,
      v_ewt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      v_ewt_base,
      NULLIF(v_line->>'ewt_variance_reason', ''),
      v_document_date
    );

    SELECT vb.total_amount
         - v_accrued_ewt
         - COALESCE((
             SELECT SUM(pvl.payment_amount + CASE WHEN v_accrued_ewt > 0 THEN 0 ELSE pvl.ewt_amount END)
             FROM payment_voucher_lines pvl
             JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
             WHERE pvl.vendor_bill_id = vb.id
               AND pv.status != 'cancelled'
               AND pvl.payment_voucher_id != COALESCE(p_voucher_id, '00000000-0000-0000-0000-000000000000'::UUID)
           ), 0)
         - COALESCE((
             SELECT SUM(vca.applied_amount)
             FROM vendor_credit_applications vca
             JOIN vendor_credits c ON c.id = vca.vendor_credit_id
             WHERE vca.vendor_bill_id = vb.id
               AND vca.reversed_at IS NULL
               AND c.status IN ('open', 'applied')
           ), 0)
    INTO v_outstanding
    FROM vendor_bills vb
    WHERE vb.id = v_bill_id;

    v_line_settlement := v_pay_amt + CASE WHEN v_accrued_ewt > 0 THEN 0 ELSE v_ewt_amt END;
    IF v_line_settlement > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % + EWT % exceeds outstanding AP balance of % for this bill',
        v_pay_amt, CASE WHEN v_accrued_ewt > 0 THEN 0 ELSE v_ewt_amt END, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_voucher_id IS NULL THEN
    v_voucher_number := fn_next_document_number(v_company_id, v_branch_id, 'PV');
    INSERT INTO payment_vouchers (
      company_id, branch_id, supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      voucher_number, voucher_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_ewt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'supplier_id')::UUID, p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_voucher_number, v_document_date,
      NULLIF(p_header->>'payment_mode_id', '')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      0, 0,
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_voucher_id;
  ELSE
    SELECT id, status INTO v_voucher_id, v_current_status
    FROM payment_vouchers WHERE id = p_voucher_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % payment voucher', v_current_status; END IF;
    UPDATE payment_vouchers SET
      branch_id = v_branch_id, supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      voucher_date = v_document_date,
      payment_mode_id = NULLIF(p_header->>'payment_mode_id', '')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_voucher_id;
  END IF;

  DELETE FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id;

  INSERT INTO payment_voucher_lines (
    payment_voucher_id, company_id, vendor_bill_id, payment_amount, ewt_amount,
    atc_code_id, ewt_tax_base, ewt_income_nature, ewt_variance_reason,
    created_by, updated_by
  )
  SELECT
    v_voucher_id, v_company_id,
    NULLIF(l->>'vendor_bill_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'ewt_amount')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    NULLIF(l->>'ewt_tax_base', '')::NUMERIC,
    NULLIF(l->>'ewt_income_nature', ''),
    NULLIF(l->>'ewt_variance_reason', ''),
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) > 0
     OR COALESCE((l->>'ewt_amount')::NUMERIC, 0) > 0;

  UPDATE payment_vouchers pv SET
    total_amount = COALESCE((SELECT SUM(payment_amount) FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id), 0),
    total_ewt    = COALESCE((SELECT SUM(ewt_amount)     FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id), 0),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE pv.id = v_voucher_id;

  RETURN v_voucher_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_settlement_posting(
  p_document_type TEXT,
  p_source_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_document_type, '')));
  v_company_id UUID;
  v_counterparty_id UUID;
  v_header_cash NUMERIC;
  v_header_tax NUMERIC;
  v_line_cash NUMERIC;
  v_line_tax NUMERIC;
  v_application RECORD;
  v_document_total NUMERIC;
  v_other_applied NUMERIC;
BEGIN
  IF v_type = 'OR' THEN
    SELECT company_id, customer_id, total_amount, total_cwt
    INTO v_company_id, v_counterparty_id, v_header_cash, v_header_tax
    FROM receipts
    WHERE id = p_source_id;

    SELECT COALESCE(SUM(payment_amount), 0), COALESCE(SUM(cwt_amount), 0)
    INTO v_line_cash, v_line_tax
    FROM receipt_lines
    WHERE receipt_id = p_source_id;

    PERFORM 1
    FROM sales_invoices si
    WHERE si.id IN (
      SELECT rl.invoice_id FROM receipt_lines rl
      WHERE rl.receipt_id = p_source_id AND rl.invoice_id IS NOT NULL
    )
    ORDER BY si.id
    FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM receipt_lines rl
      JOIN sales_invoices si ON si.id = rl.invoice_id
      WHERE rl.receipt_id = p_source_id
        AND (rl.company_id IS DISTINCT FROM v_company_id
             OR si.company_id IS DISTINCT FROM v_company_id
             OR si.customer_id IS DISTINCT FROM v_counterparty_id)
    ) THEN
      RAISE EXCEPTION 'Receipt application belongs to another company or customer';
    END IF;

    FOR v_application IN
      SELECT invoice_id, SUM(payment_amount + cwt_amount) AS applied
      FROM receipt_lines
      WHERE receipt_id = p_source_id AND invoice_id IS NOT NULL
      GROUP BY invoice_id
    LOOP
      SELECT total_amount INTO v_document_total
      FROM sales_invoices WHERE id = v_application.invoice_id;
      SELECT COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
      INTO v_other_applied
      FROM receipt_lines rl
      JOIN receipts r ON r.id = rl.receipt_id
      WHERE rl.invoice_id = v_application.invoice_id
        AND rl.receipt_id <> p_source_id
        AND r.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Receipt applications exceed invoice % outstanding balance',
          v_application.invoice_id;
      END IF;
    END LOOP;
  ELSIF v_type = 'PV' THEN
    SELECT company_id, supplier_id, total_amount, total_ewt
    INTO v_company_id, v_counterparty_id, v_header_cash, v_header_tax
    FROM payment_vouchers
    WHERE id = p_source_id;

    SELECT COALESCE(SUM(payment_amount), 0), COALESCE(SUM(ewt_amount), 0)
    INTO v_line_cash, v_line_tax
    FROM payment_voucher_lines
    WHERE payment_voucher_id = p_source_id;

    PERFORM 1
    FROM vendor_bills vb
    WHERE vb.id IN (
      SELECT pvl.vendor_bill_id FROM payment_voucher_lines pvl
      WHERE pvl.payment_voucher_id = p_source_id
        AND pvl.vendor_bill_id IS NOT NULL
    )
    ORDER BY vb.id
    FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM payment_voucher_lines pvl
      JOIN vendor_bills vb ON vb.id = pvl.vendor_bill_id
      WHERE pvl.payment_voucher_id = p_source_id
        AND (pvl.company_id IS DISTINCT FROM v_company_id
             OR vb.company_id IS DISTINCT FROM v_company_id
             OR vb.supplier_id IS DISTINCT FROM v_counterparty_id)
    ) THEN
      RAISE EXCEPTION 'Payment-voucher application belongs to another company or supplier';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM payment_voucher_lines pvl
      WHERE pvl.payment_voucher_id = p_source_id
        AND pvl.vendor_bill_id IS NOT NULL
        AND fn_vendor_bill_has_accrued_ewt(pvl.vendor_bill_id)
        AND (
          COALESCE(pvl.ewt_amount, 0) > 0
          OR pvl.atc_code_id IS NOT NULL
          OR pvl.ewt_tax_base IS NOT NULL
        )
    ) THEN
      RAISE EXCEPTION 'Payment voucher cannot withhold EWT for a vendor bill that already accrued EWT at source.';
    END IF;

    FOR v_application IN
      SELECT
        pvl.vendor_bill_id,
        SUM(pvl.payment_amount + CASE WHEN fn_vendor_bill_has_accrued_ewt(pvl.vendor_bill_id) THEN 0 ELSE pvl.ewt_amount END) AS applied
      FROM payment_voucher_lines pvl
      WHERE pvl.payment_voucher_id = p_source_id
        AND pvl.vendor_bill_id IS NOT NULL
      GROUP BY pvl.vendor_bill_id
    LOOP
      SELECT vb.total_amount - fn_vendor_bill_accrued_ewt_amount(vb.id)
      INTO v_document_total
      FROM vendor_bills vb WHERE vb.id = v_application.vendor_bill_id;

      SELECT COALESCE(SUM(pvl.payment_amount + CASE WHEN fn_vendor_bill_has_accrued_ewt(v_application.vendor_bill_id) THEN 0 ELSE pvl.ewt_amount END), 0)
      INTO v_other_applied
      FROM payment_voucher_lines pvl
      JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
      WHERE pvl.vendor_bill_id = v_application.vendor_bill_id
        AND pvl.payment_voucher_id <> p_source_id
        AND pv.status = 'posted';

      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Payment-voucher applications exceed bill % outstanding balance',
          v_application.vendor_bill_id;
      END IF;
    END LOOP;
  ELSE
    RAISE EXCEPTION 'Unsupported settlement posting type %', v_type;
  END IF;

  IF v_header_cash IS NULL THEN
    RAISE EXCEPTION 'Posting source %.% does not exist', v_type, p_source_id;
  END IF;
  IF ABS(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION '% header cash amount % does not match line amount %',
      v_type, v_header_cash, v_line_cash;
  END IF;
  IF ABS(COALESCE(v_header_tax, 0) - v_line_tax) > 0.02 THEN
    RAISE EXCEPTION '% header withholding % does not match line withholding %',
      v_type, COALESCE(v_header_tax, 0), v_line_tax;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_ap_aging_asof(
  p_company_id  UUID,
  p_as_of       DATE,
  p_supplier_id UUID DEFAULT NULL
)
RETURNS TABLE (
  bill_id         UUID,
  bill_number     TEXT,
  bill_date       DATE,
  due_date        DATE,
  supplier_id     UUID,
  supplier_name   TEXT,
  original_amount NUMERIC(15,2),
  balance_due     NUMERIC(15,2),
  days_overdue    INT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    vb.id,
    vb.bill_number,
    vb.bill_date,
    vb.due_date,
    vb.supplier_id,
    vb.supplier_name_snapshot,
    vb.total_amount,
    (vb.total_amount - COALESCE(accrued.ewt_amount, 0) - COALESCE(pay.applied, 0) - COALESCE(vc.applied, 0))::NUMERIC(15,2),
    COALESCE(p_as_of - vb.due_date, 0)
  FROM vendor_bills vb
  LEFT JOIN LATERAL (
    SELECT fn_vendor_bill_accrued_ewt_amount(vb.id) AS ewt_amount
  ) accrued ON true
  LEFT JOIN LATERAL (
    SELECT SUM(
      pvl.payment_amount
      + CASE WHEN COALESCE(accrued.ewt_amount, 0) > 0 THEN 0 ELSE pvl.ewt_amount END
    ) AS applied
    FROM payment_voucher_lines pvl
    JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.vendor_bill_id = vb.id
      AND pv.status = 'posted'
      AND pv.voucher_date <= p_as_of
  ) pay ON true
  LEFT JOIN LATERAL (
    SELECT SUM(vca.applied_amount) AS applied
    FROM vendor_credit_applications vca
    JOIN vendor_credits c ON c.id = vca.vendor_credit_id
    WHERE vca.vendor_bill_id = vb.id
      AND vca.reversed_at IS NULL
      AND vca.applied_date <= p_as_of
      AND c.status IN ('open', 'applied')
  ) vc ON true
  WHERE is_company_member(p_company_id)
    AND vb.company_id = p_company_id
    AND vb.status = 'posted'
    AND vb.bill_date <= p_as_of
    AND (p_supplier_id IS NULL OR vb.supplier_id = p_supplier_id)
    AND (vb.total_amount - COALESCE(accrued.ewt_amount, 0) - COALESCE(pay.applied, 0) - COALESCE(vc.applied, 0)) > 0.005
  ORDER BY vb.supplier_name_snapshot, vb.bill_date, vb.bill_number;
$$;

GRANT EXECUTE ON FUNCTION fn_company_ap_ewt_policy(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_vendor_bill_accrued_ewt_amount(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_vendor_bill_has_accrued_ewt(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_vendor_bill(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_vendor_bill(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_payment_voucher(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_ewt_ready(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_settlement_posting(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_ap_aging_asof(UUID, DATE, UUID) TO authenticated, service_role;
