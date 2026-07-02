-- ══════════════════════════════════════════════════════════════════════════════
-- CUSTOMER CWT DEFAULTS: default ATC, receipt validation, and CWT tax detail
-- Finding coverage: PXL-AUD-008 / PXL-DA-009.
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS is_subject_to_cwt BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS default_cwt_atc_code_id UUID REFERENCES atc_codes(id);

CREATE OR REPLACE FUNCTION fn_require_customer_cwt_default()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_valid BOOLEAN;
BEGIN
  IF NEW.default_cwt_atc_code_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM atc_codes
      WHERE id = NEW.default_cwt_atc_code_id
        AND is_active = true
        AND tax_category = 'ewt'
    ) INTO v_valid;

    IF NOT v_valid THEN
      RAISE EXCEPTION 'Default customer CWT ATC must be an active withholding ATC code.';
    END IF;

    NEW.is_subject_to_cwt := true;
  END IF;

  IF COALESCE(NEW.is_subject_to_cwt, false) = false THEN
    NEW.default_cwt_atc_code_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customer_cwt_default ON customers;
CREATE TRIGGER trg_customer_cwt_default
  BEFORE INSERT OR UPDATE OF is_subject_to_cwt, default_cwt_atc_code_id
  ON customers
  FOR EACH ROW EXECUTE FUNCTION fn_require_customer_cwt_default();

CREATE OR REPLACE FUNCTION fn_validate_receipt_line_cwt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_cwt_amount NUMERIC,
  p_atc_code_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate NUMERIC(8,4);
  v_code TEXT;
  v_base NUMERIC(15,2);
  v_expected NUMERIC(15,2);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_cwt_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Payment and CWT amounts cannot be negative.';
  END IF;

  IF COALESCE(p_cwt_amount, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when CWT amount is specified.';
  END IF;

  SELECT code, rate INTO v_code, v_rate
  FROM atc_codes
  WHERE id = p_atc_code_id
    AND is_active = true
    AND tax_category = 'ewt';

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, missing, or not valid for withholding.';
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive withholding rate.', v_code;
  END IF;

  v_base := ROUND(COALESCE(p_payment_amount, 0) + COALESCE(p_cwt_amount, 0), 2);
  IF v_base <= 0 THEN
    RAISE EXCEPTION 'CWT taxable base is required when CWT is recorded.';
  END IF;

  v_expected := ROUND(v_base * v_rate / 100.0, 2);
  IF ABS(v_expected - COALESCE(p_cwt_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'CWT amount % does not match ATC % rate %%% on taxable base %. Expected CWT is %.',
      p_cwt_amount, v_code, v_rate, v_base, v_expected;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_receipt_line_cwt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_validate_receipt_line_cwt(
    NEW.company_id,
    NEW.payment_amount,
    NEW.cwt_amount,
    NEW.atc_code_id
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_receipt_line_cwt_validation ON receipt_lines;
CREATE TRIGGER trg_receipt_line_cwt_validation
  BEFORE INSERT OR UPDATE OF company_id, payment_amount, cwt_amount, atc_code_id
  ON receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_receipt_line_cwt_validation();

CREATE OR REPLACE FUNCTION fn_validate_receipt_cwt_ready(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_header_cwt NUMERIC(15,2);
  v_line_cwt NUMERIC(15,2);
  v_line RECORD;
BEGIN
  SELECT COALESCE(total_cwt, 0) INTO v_header_cwt
  FROM receipts
  WHERE id = p_receipt_id;

  IF v_header_cwt IS NULL THEN
    RAISE EXCEPTION 'Receipt not found.';
  END IF;

  SELECT COALESCE(SUM(cwt_amount), 0) INTO v_line_cwt
  FROM receipt_lines
  WHERE receipt_id = p_receipt_id;

  IF ABS(v_header_cwt - v_line_cwt) > 0.02 THEN
    RAISE EXCEPTION 'Receipt total CWT % does not match line CWT total %.', v_header_cwt, v_line_cwt;
  END IF;

  FOR v_line IN
    SELECT company_id, payment_amount, cwt_amount, atc_code_id
    FROM receipt_lines
    WHERE receipt_id = p_receipt_id
  LOOP
    PERFORM fn_validate_receipt_line_cwt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.cwt_amount,
      v_line.atc_code_id
    );
  END LOOP;
END;
$$;

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
  v_line           JSONB;
  v_inv_id         UUID;
  v_pay_amt        NUMERIC(15,2);
  v_cwt_amt        NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;

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
    CONTINUE WHEN v_inv_id IS NULL OR (v_pay_amt + v_cwt_amt) <= 0;

    IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE id = v_inv_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
    END IF;

    PERFORM fn_validate_receipt_line_cwt(
      v_company_id,
      v_pay_amt,
      v_cwt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID
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
      v_receipt_number, (p_header->>'receipt_date')::DATE,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''), NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
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
      receipt_date = (p_header->>'receipt_date')::DATE,
      payment_mode_id = (p_header->>'payment_mode_id')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount,
    forex_adjustment, atc_code_id, created_by, updated_by
  )
  SELECT
    v_receipt_id, v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0
     OR COALESCE((l->>'cwt_amount')::NUMERIC, 0) != 0;

  RETURN v_receipt_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       receipts%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ar_cr     NUMERIC(15,2);
  v_rl        RECORD;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  PERFORM fn_validate_receipt_cwt_ready(p_receipt_id);

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_cwt > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.receipt_date AND end_date >= v_rec.receipt_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for receipt date %. Create or unlock a fiscal period first.', v_rec.receipt_date;
  END IF;

  v_ar_cr := v_rec.total_amount + v_rec.total_cwt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date, v_fp_id,
    'Official Receipt ' || v_rec.receipt_number || ' - ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id, 'posted',
    v_ar_cr, v_ar_cr,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cash_acct, 'Cash received - ' || v_rec.receipt_number, v_rec.total_amount, 0, auth.uid(), auth.uid());

  IF v_rec.total_cwt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 2, v_cfg.ewt_withheld_account_id, 'CWT receivable - ' || v_rec.receipt_number, v_rec.total_cwt, 0, auth.uid(), auth.uid());
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
          v_cfg.ar_account_id, 'AR cleared - ' || v_rec.receipt_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_rl IN
    SELECT rl.payment_amount, rl.cwt_amount, rl.atc_code_id, ac.rate AS cwt_rate
    FROM receipt_lines rl
    LEFT JOIN atc_codes ac ON ac.id = rl.atc_code_id
    WHERE rl.receipt_id = p_receipt_id
      AND rl.cwt_amount > 0
  LOOP
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'OR', v_rec.id,
      'cwt_receivable', v_rl.atc_code_id,
      ROUND(v_rl.payment_amount + v_rl.cwt_amount, 2),
      v_rl.cwt_rate, v_rl.cwt_amount, v_fp_id,
      NOW()::DATE, v_rec.receipt_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_validate_receipt_line_cwt(UUID, NUMERIC, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_receipt_cwt_ready(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID) TO authenticated;
