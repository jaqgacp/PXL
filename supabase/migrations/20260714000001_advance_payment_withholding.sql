-- PXL-AUD-043: customer advances with CWT and supplier down-payments with EWT.
--
-- Cash-purchase EWT was completed in 20260713000015. This slice keeps OR/PV as
-- the controlled payment documents, but classifies invoice-less settlement
-- lines explicitly so they post to advance balance-sheet accounts instead of
-- incorrectly clearing AR/AP.

ALTER TABLE company_accounting_config
  ADD COLUMN IF NOT EXISTS customer_advances_account_id UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS supplier_down_payments_account_id UUID REFERENCES chart_of_accounts(id);

ALTER TABLE receipt_lines
  ALTER COLUMN invoice_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS line_type TEXT NOT NULL DEFAULT 'invoice_application';

ALTER TABLE payment_voucher_lines
  ADD COLUMN IF NOT EXISTS line_type TEXT NOT NULL DEFAULT 'bill_application';

UPDATE receipt_lines
SET line_type = CASE WHEN invoice_id IS NULL THEN 'customer_advance' ELSE 'invoice_application' END
WHERE line_type IS NULL
   OR line_type NOT IN ('invoice_application', 'customer_advance');

UPDATE payment_voucher_lines
SET line_type = CASE WHEN vendor_bill_id IS NULL THEN 'supplier_down_payment' ELSE 'bill_application' END
WHERE line_type IS NULL
   OR line_type NOT IN ('bill_application', 'supplier_down_payment');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'receipt_lines_line_type_check'
  ) THEN
    ALTER TABLE receipt_lines
      ADD CONSTRAINT receipt_lines_line_type_check
      CHECK (line_type IN ('invoice_application', 'customer_advance'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'receipt_lines_line_type_invoice_consistency'
  ) THEN
    ALTER TABLE receipt_lines
      ADD CONSTRAINT receipt_lines_line_type_invoice_consistency
      CHECK (
        (line_type = 'invoice_application' AND invoice_id IS NOT NULL)
        OR (line_type = 'customer_advance' AND invoice_id IS NULL)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'payment_voucher_lines_line_type_check'
  ) THEN
    ALTER TABLE payment_voucher_lines
      ADD CONSTRAINT payment_voucher_lines_line_type_check
      CHECK (line_type IN ('bill_application', 'supplier_down_payment'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'payment_voucher_lines_line_type_bill_consistency'
  ) THEN
    ALTER TABLE payment_voucher_lines
      ADD CONSTRAINT payment_voucher_lines_line_type_bill_consistency
      CHECK (
        (line_type = 'bill_application' AND vendor_bill_id IS NOT NULL)
        OR (line_type = 'supplier_down_payment' AND vendor_bill_id IS NULL)
      );
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_receipt_lines_advance
  ON receipt_lines (receipt_id)
  WHERE line_type = 'customer_advance';

CREATE INDEX IF NOT EXISTS idx_pvl_down_payment
  ON payment_voucher_lines (payment_voucher_id)
  WHERE line_type = 'supplier_down_payment';

CREATE OR REPLACE FUNCTION fn_save_receipt(
  p_receipt_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_receipt_number TEXT;
  v_current_status TEXT;
  v_document_date  DATE;
  v_line           JSONB;
  v_line_type      TEXT;
  v_inv_id         UUID;
  v_pay_amt        NUMERIC(15,2);
  v_cwt_amt        NUMERIC(15,2);
  v_cwt_base       NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;
  v_document_date := (p_header->>'receipt_date')::DATE;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_inv_id := NULLIF(v_line->>'invoice_id', '')::UUID;
    v_line_type := COALESCE(
      NULLIF(v_line->>'line_type', ''),
      CASE WHEN v_inv_id IS NULL THEN 'customer_advance' ELSE 'invoice_application' END
    );
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_cwt_amt := COALESCE((v_line->>'cwt_amount')::NUMERIC, 0);
    v_cwt_base := NULLIF(v_line->>'cwt_tax_base', '')::NUMERIC;
    CONTINUE WHEN (v_pay_amt + v_cwt_amt) <= 0;

    IF v_line_type NOT IN ('invoice_application', 'customer_advance') THEN
      RAISE EXCEPTION 'Unsupported receipt line type: %', v_line_type;
    END IF;
    IF v_line_type = 'invoice_application' AND v_inv_id IS NULL THEN
      RAISE EXCEPTION 'Invoice application receipt lines require an invoice.';
    END IF;
    IF v_line_type = 'customer_advance' AND v_inv_id IS NOT NULL THEN
      RAISE EXCEPTION 'Customer advance receipt lines must not reference an invoice.';
    END IF;

    IF v_line_type = 'invoice_application' THEN
      IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE id = v_inv_id AND company_id = v_company_id) THEN
        RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
      END IF;
    END IF;

    PERFORM fn_validate_receipt_line_cwt(
      v_company_id,
      v_pay_amt,
      v_cwt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      v_cwt_base,
      NULLIF(v_line->>'cwt_variance_reason', ''),
      v_document_date
    );

    IF v_line_type = 'invoice_application' THEN
      SELECT si.total_amount
           - COALESCE((
               SELECT SUM(rl.payment_amount + rl.cwt_amount)
               FROM receipt_lines rl
               JOIN receipts r ON r.id = rl.receipt_id
               WHERE rl.invoice_id = si.id
                 AND rl.line_type = 'invoice_application'
                 AND r.status != 'bounced'
                 AND rl.receipt_id != COALESCE(p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID)
             ), 0)
           - COALESCE((
               SELECT SUM(c.total_amount)
               FROM credit_memos c
               WHERE c.invoice_id = si.id
                 AND c.status = 'applied'
             ), 0)
      INTO v_outstanding
      FROM sales_invoices si
      WHERE si.id = v_inv_id;

      IF v_pay_amt + v_cwt_amt > COALESCE(v_outstanding, 0) + 0.02 THEN
        RAISE EXCEPTION 'Payment of % plus CWT % exceeds outstanding balance of % for invoice',
          v_pay_amt, v_cwt_amt, COALESCE(v_outstanding, 0);
      END IF;
    END IF;
  END LOOP;

  IF p_receipt_id IS NULL THEN
    v_receipt_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

    INSERT INTO receipts (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      receipt_number, receipt_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_cwt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number, v_document_date,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''), NULLIF(p_header->>'bank_account_id', '')::UUID,
      0, 0,
      NULLIF(p_header->>'remarks', ''), 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_receipt_id;
  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts WHERE id = p_receipt_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id = v_branch_id, customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date = v_document_date,
      payment_mode_id = (p_header->>'payment_mode_id')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, line_type, payment_amount, cwt_amount,
    forex_adjustment, atc_code_id, cwt_tax_base, cwt_variance_reason,
    created_by, updated_by
  )
  SELECT
    v_receipt_id, v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE(
      NULLIF(l->>'line_type', ''),
      CASE WHEN NULLIF(l->>'invoice_id', '') IS NULL THEN 'customer_advance' ELSE 'invoice_application' END
    ),
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    NULLIF(l->>'cwt_tax_base', '')::NUMERIC,
    NULLIF(l->>'cwt_variance_reason', ''),
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) > 0
     OR COALESCE((l->>'cwt_amount')::NUMERIC, 0) > 0;

  UPDATE receipts r SET
    total_amount = COALESCE((SELECT SUM(payment_amount) FROM receipt_lines WHERE receipt_id = v_receipt_id), 0),
    total_cwt    = COALESCE((SELECT SUM(cwt_amount)     FROM receipt_lines WHERE receipt_id = v_receipt_id), 0),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE r.id = v_receipt_id;

  RETURN v_receipt_id;
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
  v_line_type      TEXT;
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
    v_line_type := COALESCE(
      NULLIF(v_line->>'line_type', ''),
      CASE WHEN v_bill_id IS NULL THEN 'supplier_down_payment' ELSE 'bill_application' END
    );
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_ewt_amt := COALESCE((v_line->>'ewt_amount')::NUMERIC, 0);
    v_ewt_base := NULLIF(v_line->>'ewt_tax_base', '')::NUMERIC;
    CONTINUE WHEN (v_pay_amt + v_ewt_amt) <= 0;

    IF v_line_type NOT IN ('bill_application', 'supplier_down_payment') THEN
      RAISE EXCEPTION 'Unsupported payment voucher line type: %', v_line_type;
    END IF;
    IF v_line_type = 'bill_application' AND v_bill_id IS NULL THEN
      RAISE EXCEPTION 'Bill application payment-voucher lines require a vendor bill.';
    END IF;
    IF v_line_type = 'supplier_down_payment' AND v_bill_id IS NOT NULL THEN
      RAISE EXCEPTION 'Supplier down-payment lines must not reference a vendor bill.';
    END IF;

    IF v_line_type = 'bill_application' THEN
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
    ELSE
      v_accrued_ewt := 0;
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

    IF v_line_type = 'bill_application' THEN
      SELECT vb.total_amount
           - v_accrued_ewt
           - COALESCE((
               SELECT SUM(pvl.payment_amount + CASE WHEN v_accrued_ewt > 0 THEN 0 ELSE pvl.ewt_amount END)
               FROM payment_voucher_lines pvl
               JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
               WHERE pvl.vendor_bill_id = vb.id
                 AND pvl.line_type = 'bill_application'
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
    payment_voucher_id, company_id, vendor_bill_id, line_type, payment_amount, ewt_amount,
    atc_code_id, ewt_tax_base, ewt_income_nature, ewt_variance_reason,
    created_by, updated_by
  )
  SELECT
    v_voucher_id, v_company_id,
    NULLIF(l->>'vendor_bill_id', '')::UUID,
    COALESCE(
      NULLIF(l->>'line_type', ''),
      CASE WHEN NULLIF(l->>'vendor_bill_id', '') IS NULL THEN 'supplier_down_payment' ELSE 'bill_application' END
    ),
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

    IF EXISTS (
      SELECT 1 FROM receipt_lines
      WHERE receipt_id = p_source_id
        AND (
          (line_type = 'invoice_application' AND invoice_id IS NULL)
          OR (line_type = 'customer_advance' AND invoice_id IS NOT NULL)
        )
    ) THEN
      RAISE EXCEPTION 'Receipt line type and invoice reference are inconsistent';
    END IF;

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
        AND rl.line_type = 'invoice_application'
        AND (rl.company_id IS DISTINCT FROM v_company_id
             OR si.company_id IS DISTINCT FROM v_company_id
             OR si.customer_id IS DISTINCT FROM v_counterparty_id)
    ) THEN
      RAISE EXCEPTION 'Receipt application belongs to another company or customer';
    END IF;

    FOR v_application IN
      SELECT invoice_id, SUM(payment_amount + cwt_amount) AS applied
      FROM receipt_lines
      WHERE receipt_id = p_source_id
        AND line_type = 'invoice_application'
        AND invoice_id IS NOT NULL
      GROUP BY invoice_id
    LOOP
      SELECT total_amount INTO v_document_total
      FROM sales_invoices WHERE id = v_application.invoice_id;
      SELECT COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
      INTO v_other_applied
      FROM receipt_lines rl
      JOIN receipts r ON r.id = rl.receipt_id
      WHERE rl.invoice_id = v_application.invoice_id
        AND rl.line_type = 'invoice_application'
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

    IF EXISTS (
      SELECT 1 FROM payment_voucher_lines
      WHERE payment_voucher_id = p_source_id
        AND (
          (line_type = 'bill_application' AND vendor_bill_id IS NULL)
          OR (line_type = 'supplier_down_payment' AND vendor_bill_id IS NOT NULL)
        )
    ) THEN
      RAISE EXCEPTION 'Payment-voucher line type and bill reference are inconsistent';
    END IF;

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
        AND pvl.line_type = 'bill_application'
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
        AND pvl.line_type = 'bill_application'
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
        AND pvl.line_type = 'bill_application'
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
        AND pvl.line_type = 'bill_application'
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

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec receipts%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_cash_account UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_ar_credit NUMERIC(15,2);
  v_advance_credit NUMERIC(15,2);
  v_line_no INTEGER := 1;
  v_line RECORD;
BEGIN
  v_begin := fn_begin_source_posting(
    'OR', p_receipt_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM receipts WHERE id = p_receipt_id;
  PERFORM fn_validate_receipt_cwt_ready(p_receipt_id);
  PERFORM fn_validate_settlement_posting('OR', p_receipt_id);

  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  SELECT
    COALESCE(SUM(payment_amount + cwt_amount) FILTER (WHERE line_type = 'invoice_application'), 0),
    COALESCE(SUM(payment_amount + cwt_amount) FILTER (WHERE line_type = 'customer_advance'), 0)
  INTO v_ar_credit, v_advance_credit
  FROM receipt_lines
  WHERE receipt_id = v_rec.id;

  IF v_ar_credit > 0 AND (NOT FOUND OR v_cfg.ar_account_id IS NULL) THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_advance_credit > 0 AND (NOT FOUND OR v_cfg.customer_advances_account_id IS NULL) THEN
    RAISE EXCEPTION 'Customer advances account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_cwt > 0 AND (NOT FOUND OR v_cfg.ewt_withheld_account_id IS NULL) THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_account := COALESCE(v_rec.bank_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_rec.total_amount > 0 AND v_cash_account IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date,
    'Official Receipt ' || v_rec.receipt_number || ' - ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  IF v_rec.total_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cash_account,
      'Cash received - ' || v_rec.receipt_number,
      v_rec.total_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_rec.total_cwt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ewt_withheld_account_id,
      'CWT receivable - ' || v_rec.receipt_number,
      v_rec.total_cwt, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_ar_credit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ar_account_id,
      'AR cleared - ' || v_rec.receipt_number,
      0, v_ar_credit,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_advance_credit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.customer_advances_account_id,
      'Customer advance - ' || v_rec.receipt_number,
      0, v_advance_credit,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_line IN
    SELECT rl.id, rl.payment_amount, rl.cwt_amount, rl.atc_code_id,
           rl.cwt_tax_base, ac.rate AS cwt_rate
    FROM receipt_lines rl
    LEFT JOIN atc_codes ac ON ac.id = rl.atc_code_id
    WHERE rl.receipt_id = v_rec.id
      AND rl.cwt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'OR', v_rec.id, v_line.id,
      'cwt_receivable', NULL, NULL, v_line.atc_code_id,
      ROUND(COALESCE(v_line.cwt_tax_base,
        v_line.payment_amount + v_line.cwt_amount), 2),
      v_line.cwt_rate, v_line.cwt_amount, v_fp_id,
      CURRENT_DATE, v_rec.receipt_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'OR', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.receipt_date)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec payment_vouchers%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_cash_account UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_ap_debit NUMERIC(15,2);
  v_down_payment_debit NUMERIC(15,2);
  v_line_no INTEGER := 1;
  v_line RECORD;
BEGIN
  v_begin := fn_begin_source_posting(
    'PV', p_voucher_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  PERFORM fn_validate_payment_voucher_ewt_ready(p_voucher_id);
  PERFORM fn_validate_settlement_posting('PV', p_voucher_id);

  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  SELECT
    COALESCE(SUM(payment_amount + ewt_amount) FILTER (WHERE line_type = 'bill_application'), 0),
    COALESCE(SUM(payment_amount + ewt_amount) FILTER (WHERE line_type = 'supplier_down_payment'), 0)
  INTO v_ap_debit, v_down_payment_debit
  FROM payment_voucher_lines
  WHERE payment_voucher_id = v_rec.id;

  IF v_ap_debit > 0 AND (NOT FOUND OR v_cfg.ap_account_id IS NULL) THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_down_payment_debit > 0 AND (NOT FOUND OR v_cfg.supplier_down_payments_account_id IS NULL) THEN
    RAISE EXCEPTION 'Supplier down-payments account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_ewt > 0 AND (NOT FOUND OR v_cfg.ewt_payable_account_id IS NULL) THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_account := COALESCE(v_rec.bank_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_rec.total_amount > 0 AND v_cash_account IS NULL THEN
    RAISE EXCEPTION 'No bank account on voucher and no default cash account configured.';
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date,
    'Payment Voucher ' || v_rec.voucher_number || ' - ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  IF v_ap_debit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ap_account_id,
      'AP cleared - ' || v_rec.voucher_number,
      v_ap_debit, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_down_payment_debit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.supplier_down_payments_account_id,
      'Supplier down-payment - ' || v_rec.voucher_number,
      v_down_payment_debit, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_rec.total_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cash_account,
      'Cash paid - ' || v_rec.voucher_number,
      0, v_rec.total_amount,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_rec.total_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ewt_payable_account_id,
      'EWT withheld - ' || v_rec.voucher_number,
      0, v_rec.total_ewt,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE payment_vouchers
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_line IN
    SELECT pvl.id, pvl.payment_amount, pvl.ewt_amount, pvl.atc_code_id,
           pvl.ewt_tax_base, pvl.ewt_income_nature,
           ac.rate AS ewt_rate
    FROM payment_voucher_lines pvl
    LEFT JOIN atc_codes ac ON ac.id = pvl.atc_code_id
    WHERE pvl.payment_voucher_id = v_rec.id
      AND pvl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id, v_line.id,
      'ewt_payable', NULL, NULL, v_line.atc_code_id,
      ROUND(COALESCE(v_line.ewt_tax_base,
        v_line.payment_amount + v_line.ewt_amount), 2),
      v_line.ewt_rate, v_line.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_line.ewt_income_nature
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'PV', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.voucher_date)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_gl_impact_payload(
  p_je_id UUID,
  p_mode TEXT DEFAULT 'posted',
  p_rule_explanation TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je journal_entries%ROWTYPE;
  v_lines JSONB;
  v_period_name TEXT;
  v_branch_name TEXT;
  v_source_route TEXT;
  v_display_name TEXT;
BEGIN
  SELECT * INTO v_je FROM journal_entries WHERE id = p_je_id;
  IF NOT FOUND OR NOT is_company_member(v_je.company_id) THEN
    RAISE EXCEPTION 'Journal entry not found or access denied';
  END IF;

  SELECT period_name INTO v_period_name FROM fiscal_periods WHERE id = v_je.fiscal_period_id;
  SELECT branch_name INTO v_branch_name FROM branches WHERE id = v_je.branch_id;
  SELECT route_path, display_name INTO v_source_route, v_display_name
  FROM ref_posting_source_types
  WHERE document_type = v_je.reference_doc_type;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'line_number', jel.line_number,
    'account_id', jel.account_id,
    'account_code', coa.account_code,
    'account_name', coa.account_name,
    'account_source', CASE
      WHEN jel.account_id = cfg.ar_account_id THEN 'company_accounting_config.ar_account_id'
      WHEN jel.account_id = cfg.ap_account_id THEN 'company_accounting_config.ap_account_id'
      WHEN jel.account_id = cfg.vat_payable_account_id THEN 'company_accounting_config.vat_payable_account_id'
      WHEN jel.account_id = cfg.input_vat_account_id THEN 'company_accounting_config.input_vat_account_id'
      WHEN jel.account_id = cfg.ewt_withheld_account_id THEN 'company_accounting_config.ewt_withheld_account_id'
      WHEN jel.account_id = cfg.ewt_payable_account_id THEN 'company_accounting_config.ewt_payable_account_id'
      WHEN jel.account_id = cfg.customer_advances_account_id THEN 'company_accounting_config.customer_advances_account_id'
      WHEN jel.account_id = cfg.supplier_down_payments_account_id THEN 'company_accounting_config.supplier_down_payments_account_id'
      WHEN jel.account_id = cfg.default_cash_account_id THEN 'company_accounting_config.default_cash_account_id'
      ELSE 'document or module posting rule'
    END,
    'description', jel.description,
    'debit', jel.debit_amount,
    'credit', jel.credit_amount,
    'branch_id', jel.branch_id,
    'department_id', jel.department_id,
    'cost_center_id', jel.cost_center_id
  ) ORDER BY jel.line_number), '[]'::jsonb)
  INTO v_lines
  FROM journal_entry_lines jel
  JOIN chart_of_accounts coa ON coa.id = jel.account_id
  LEFT JOIN company_accounting_config cfg ON cfg.company_id = v_je.company_id
  WHERE jel.je_id = v_je.id;

  RETURN jsonb_build_object(
    'mode', p_mode,
    'journal_entry_id', CASE WHEN p_mode = 'posted' THEN v_je.id ELSE NULL END,
    'je_number', CASE WHEN p_mode = 'posted' THEN v_je.je_number ELSE NULL END,
    'posting_date', v_je.je_date,
    'fiscal_period_id', v_je.fiscal_period_id,
    'fiscal_period_name', v_period_name,
    'branch_id', v_je.branch_id,
    'branch_name', v_branch_name,
    'source_doc_type', v_je.reference_doc_type,
    'source_doc_id', v_je.reference_doc_id,
    'source_display_name', v_display_name,
    'source_route', CASE WHEN v_source_route IS NOT NULL AND v_je.reference_doc_id IS NOT NULL
                         THEN v_source_route || '?id=' || v_je.reference_doc_id::text
                         ELSE v_source_route END,
    'rule_explanation', COALESCE(p_rule_explanation,
      'Posted journal lines are the authoritative accounting impact.'),
    'total_debit', v_je.total_debit,
    'total_credit', v_je.total_credit,
    'balanced', ABS(v_je.total_debit - v_je.total_credit) <= 0.01,
    'lines', v_lines
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_payment_voucher(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_settlement_posting(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_gl_impact_payload(UUID, TEXT, TEXT) TO authenticated, service_role;
