-- ══════════════════════════════════════════════════════════════════════════════
-- SETTLEMENT TOTAL LINE AUTHORITY (PXL-AUD-038 / PXL-AUD-048)
--
-- PXL-AUD-038: fn_save_payment_voucher / fn_save_receipt accepted the header
-- cash total (payment_vouchers.total_amount / receipts.total_amount) from the
-- client and never compared it to SUM(line payment_amount). The post RPCs write
-- the JE from HEADER totals while application tracking, aging, and the tax
-- ledger use LINE amounts, so GL cash/AP/AR could diverge from the subledger by
-- any amount while every existing check passed. Only the EWT/CWT slice was
-- reconciled (±0.02).
--
-- PXL-AUD-048: because the header EWT/CWT figure (posted to the GL) was allowed
-- to differ from the line EWT/CWT sum (posted to the tax ledger) by up to 0.02,
-- a legitimately saved document could leave a permanent GL-to-ledger variance
-- that blocks SAWT/QAP/DAT exports (reconciled at 0.01).
--
-- Fix (the stronger, defense-in-depth form):
--   1. fn_save_payment_voucher / fn_save_receipt recompute the header totals
--      (total_amount and total_ewt / total_cwt) from the persisted lines and
--      ignore the client-supplied header figures. The header becomes a mirror
--      of the line sums, so GL == subledger == tax ledger by construction and
--      the 0.02 header/line EWT-CWT drift can no longer reach the GL.
--   2. The posting readiness validators additionally assert that the stored
--      header cash total equals SUM(line payment_amount) within 0.02, so any
--      header that reaches posting by another path (e.g. a tampered draft) is
--      rejected before a JE is written.
--
-- Cash sales (fn_save_cash_sale) post their own receipt JE and do not use these
-- save/post/ready paths, so their receipts.total_amount semantics (full invoice
-- incl. the CWT-withheld portion, PXL-AUD-046) are unchanged here.
-- ══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. fn_save_payment_voucher — header totals derived from lines
-- ─────────────────────────────────────────────────────────────────────────────
-- Body matches 20260713000002 (document-date threading) plus the trailing
-- server-side recompute of total_amount / total_ewt from the persisted lines.
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

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_company_id,
      v_pay_amt,
      v_ewt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      v_ewt_base,
      NULLIF(v_line->>'ewt_variance_reason', ''),
      v_document_date
    );

    SELECT vb.total_amount - COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
    INTO v_outstanding
    FROM vendor_bills vb
    LEFT JOIN payment_voucher_lines pvl ON pvl.vendor_bill_id = vb.id
      AND pvl.payment_voucher_id != COALESCE(p_voucher_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND pvl.payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE status != 'cancelled')
    WHERE vb.id = v_bill_id GROUP BY vb.total_amount;

    IF (v_pay_amt + v_ewt_amt) > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % + EWT % exceeds outstanding AP balance of % for this bill',
        v_pay_amt, v_ewt_amt, COALESCE(v_outstanding, 0);
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

  -- Header cash + EWT totals are DERIVED from the persisted lines; the
  -- client-supplied header figures are ignored (PXL-AUD-038 / PXL-AUD-048).
  UPDATE payment_vouchers pv SET
    total_amount = COALESCE((SELECT SUM(payment_amount) FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id), 0),
    total_ewt    = COALESCE((SELECT SUM(ewt_amount)     FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id), 0),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE pv.id = v_voucher_id;

  RETURN v_voucher_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_save_receipt — header totals derived from lines
-- ─────────────────────────────────────────────────────────────────────────────
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
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_cwt_amt := COALESCE((v_line->>'cwt_amount')::NUMERIC, 0);
    v_cwt_base := NULLIF(v_line->>'cwt_tax_base', '')::NUMERIC;
    CONTINUE WHEN v_inv_id IS NULL OR (v_pay_amt + v_cwt_amt) <= 0;

    IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE id = v_inv_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
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

    SELECT si.total_amount - COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
    INTO v_outstanding
    FROM sales_invoices si
    LEFT JOIN receipt_lines rl
      ON rl.invoice_id = si.id
      AND rl.receipt_id != COALESCE(p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND rl.receipt_id IN (SELECT id FROM receipts WHERE status != 'bounced')
    WHERE si.id = v_inv_id
    GROUP BY si.total_amount;

    IF v_pay_amt + v_cwt_amt > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % plus CWT % exceeds outstanding balance of % for invoice',
        v_pay_amt, v_cwt_amt, COALESCE(v_outstanding, 0);
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
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount,
    forex_adjustment, atc_code_id, cwt_tax_base, cwt_variance_reason,
    created_by, updated_by
  )
  SELECT
    v_receipt_id, v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    NULLIF(l->>'cwt_tax_base', '')::NUMERIC,
    NULLIF(l->>'cwt_variance_reason', ''),
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0
     OR COALESCE((l->>'cwt_amount')::NUMERIC, 0) != 0;

  -- Header cash + CWT totals are DERIVED from the persisted lines; the
  -- client-supplied header figures are ignored (PXL-AUD-038 / PXL-AUD-048).
  UPDATE receipts r SET
    total_amount = COALESCE((SELECT SUM(payment_amount) FROM receipt_lines WHERE receipt_id = v_receipt_id), 0),
    total_cwt    = COALESCE((SELECT SUM(cwt_amount)     FROM receipt_lines WHERE receipt_id = v_receipt_id), 0),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE r.id = v_receipt_id;

  RETURN v_receipt_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Posting readiness validators also reconcile the header cash total to lines
-- ─────────────────────────────────────────────────────────────────────────────
-- Body matches 20260713000002 (document-date threading) plus the header
-- total_amount vs SUM(line payment_amount) reconciliation, so any header that
-- reaches posting by another path is rejected before a JE is written.
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
    SELECT company_id, payment_amount, ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
    FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id
  LOOP
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

CREATE OR REPLACE FUNCTION fn_validate_receipt_cwt_ready(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_header_cwt    NUMERIC(15,2);
  v_line_cwt      NUMERIC(15,2);
  v_header_cash   NUMERIC(15,2);
  v_line_cash     NUMERIC(15,2);
  v_document_date DATE;
  v_line          RECORD;
BEGIN
  SELECT COALESCE(total_cwt, 0), COALESCE(total_amount, 0), receipt_date
  INTO v_header_cwt, v_header_cash, v_document_date
  FROM receipts WHERE id = p_receipt_id;

  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Receipt not found.';
  END IF;

  SELECT COALESCE(SUM(cwt_amount), 0), COALESCE(SUM(payment_amount), 0)
  INTO v_line_cwt, v_line_cash
  FROM receipt_lines WHERE receipt_id = p_receipt_id;

  IF ABS(v_header_cwt - v_line_cwt) > 0.02 THEN
    RAISE EXCEPTION 'Receipt total CWT % does not match line CWT total %.', v_header_cwt, v_line_cwt;
  END IF;

  IF ABS(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION 'Receipt total amount % does not match line payment total %.', v_header_cash, v_line_cash;
  END IF;

  FOR v_line IN
    SELECT company_id, payment_amount, cwt_amount, atc_code_id, cwt_tax_base, cwt_variance_reason
    FROM receipt_lines WHERE receipt_id = p_receipt_id
  LOOP
    PERFORM fn_validate_receipt_line_cwt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.cwt_amount,
      v_line.atc_code_id,
      v_line.cwt_tax_base,
      v_line.cwt_variance_reason,
      v_document_date
    );
  END LOOP;
END;
$$;
