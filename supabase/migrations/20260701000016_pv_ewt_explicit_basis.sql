-- ══════════════════════════════════════════════════════════════════════════════
-- PAYMENT VOUCHER EWT: explicit taxable base, income nature, and variance reason
-- Finding coverage: PXL-AUD-007 / PXL-DA-009.
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE payment_voucher_lines
  ADD COLUMN IF NOT EXISTS ewt_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS ewt_income_nature TEXT,
  ADD COLUMN IF NOT EXISTS ewt_variance_reason TEXT;

ALTER TABLE tax_detail_entries
  ADD COLUMN IF NOT EXISTS income_nature TEXT;

UPDATE payment_voucher_lines
SET ewt_tax_base = ROUND(payment_amount + ewt_amount, 2)
WHERE ewt_amount > 0
  AND ewt_tax_base IS NULL;

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_line_ewt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_ewt_amount NUMERIC,
  p_atc_code_id UUID,
  p_ewt_tax_base NUMERIC DEFAULT NULL,
  p_ewt_variance_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate NUMERIC(8,4);
  v_code TEXT;
  v_expected NUMERIC(15,2);
  v_base NUMERIC(15,2);
  v_reason TEXT;
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_ewt_amount, 0) < 0 OR COALESCE(p_ewt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, EWT, and EWT taxable base cannot be negative.';
  END IF;

  IF COALESCE(p_ewt_amount, 0) = 0 AND COALESCE(p_ewt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when EWT amount or taxable base is specified.';
  END IF;

  SELECT code, rate INTO v_code, v_rate
  FROM atc_codes
  WHERE id = p_atc_code_id
    AND is_active = true
    AND tax_category = 'ewt';

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, missing, or not valid for EWT.';
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive EWT rate.', v_code;
  END IF;

  v_base := ROUND(COALESCE(p_ewt_tax_base, p_payment_amount + p_ewt_amount, 0), 2);
  IF v_base <= 0 THEN
    RAISE EXCEPTION 'EWT taxable base is required when EWT is withheld.';
  END IF;

  v_expected := ROUND(v_base * v_rate / 100.0, 2);
  IF ABS(v_expected - COALESCE(p_ewt_amount, 0)) <= 0.02 THEN
    RETURN;
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_ewt_variance_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'EWT amount % does not match ATC % rate %%% on taxable base %. Expected EWT is %. Select a variance reason to proceed.',
      p_ewt_amount, v_code, v_rate, v_base, v_expected;
  END IF;

  IF v_reason NOT IN ('rounding', 'partial_non_taxable', 'bir_ruling', 'supplier_exempt', 'other_authorized') THEN
    RAISE EXCEPTION 'Invalid EWT variance reason: %', v_reason;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_pvl_ewt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_validate_payment_voucher_line_ewt(
    NEW.company_id,
    NEW.payment_amount,
    NEW.ewt_amount,
    NEW.atc_code_id,
    NEW.ewt_tax_base,
    NEW.ewt_variance_reason
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pvl_ewt_validation ON payment_voucher_lines;
CREATE TRIGGER trg_pvl_ewt_validation
  BEFORE INSERT OR UPDATE OF payment_amount, ewt_amount, atc_code_id, company_id, ewt_tax_base, ewt_variance_reason
  ON payment_voucher_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_pvl_ewt_validation();

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_ewt_ready(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
  v_header_ewt NUMERIC(15,2);
  v_line_ewt NUMERIC(15,2);
BEGIN
  SELECT COALESCE(total_ewt, 0) INTO v_header_ewt
  FROM payment_vouchers
  WHERE id = p_voucher_id;

  IF v_header_ewt IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found.';
  END IF;

  SELECT COALESCE(SUM(ewt_amount), 0) INTO v_line_ewt
  FROM payment_voucher_lines
  WHERE payment_voucher_id = p_voucher_id;

  IF ABS(v_header_ewt - v_line_ewt) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total EWT % does not match line EWT total %.', v_header_ewt, v_line_ewt;
  END IF;

  FOR v_line IN
    SELECT company_id, payment_amount, ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
    FROM payment_voucher_lines
    WHERE payment_voucher_id = p_voucher_id
  LOOP
    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.ewt_amount,
      v_line.atc_code_id,
      v_line.ewt_tax_base,
      v_line.ewt_variance_reason
    );
  END LOOP;
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
  v_line           JSONB;
  v_bill_id        UUID;
  v_pay_amt        NUMERIC(15,2);
  v_ewt_amt        NUMERIC(15,2);
  v_ewt_base       NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

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
      NULLIF(v_line->>'ewt_variance_reason', '')
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
      v_voucher_number, (p_header->>'voucher_date')::DATE,
      NULLIF(p_header->>'payment_mode_id', '')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
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
      voucher_date = (p_header->>'voucher_date')::DATE,
      payment_mode_id = NULLIF(p_header->>'payment_mode_id', '')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_ewt = COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
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

  RETURN v_voucher_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ap_dr     NUMERIC(15,2);
  v_line_no   INT := 1;
  v_pvl       RECORD;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft vouchers can be posted (current: %)', v_rec.status;
  END IF;

  PERFORM fn_validate_payment_voucher_ewt_ready(p_voucher_id);

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_ewt > 0 AND v_cfg.ewt_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on voucher and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for voucher date %. Create or unlock a fiscal period first.', v_rec.voucher_date;
  END IF;

  v_ap_dr := v_rec.total_amount + v_rec.total_ewt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date, v_fp_id,
    'Payment Voucher ' || v_rec.voucher_number || ' - ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id, 'posted',
    v_ap_dr, v_ap_dr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP cleared - ' || v_rec.voucher_number, v_ap_dr, 0, auth.uid(), auth.uid());

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 2, v_cash_acct,
          'Cash paid - ' || v_rec.voucher_number, 0, v_rec.total_amount, auth.uid(), auth.uid());
  v_line_no := 3;

  IF v_rec.total_ewt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ewt_payable_account_id,
            'EWT withheld - ' || v_rec.voucher_number, 0, v_rec.total_ewt, auth.uid(), auth.uid());
  END IF;

  UPDATE payment_vouchers SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_pvl IN
    SELECT
      pvl.payment_amount, pvl.ewt_amount, pvl.atc_code_id,
      pvl.ewt_tax_base, pvl.ewt_income_nature, ac.rate AS ewt_rate
    FROM payment_voucher_lines pvl
    LEFT JOIN atc_codes ac ON ac.id = pvl.atc_code_id
    WHERE pvl.payment_voucher_id = p_voucher_id AND pvl.ewt_amount > 0
  LOOP
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name, income_nature
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id,
      'ewt_payable', v_pvl.atc_code_id,
      ROUND(COALESCE(v_pvl.ewt_tax_base, v_pvl.payment_amount + v_pvl.ewt_amount), 2),
      v_pvl.ewt_rate, v_pvl.ewt_amount, v_fp_id,
      NOW()::DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      NULLIF(v_pvl.ewt_income_nature, '')
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE VIEW vw_ewt_summary_ap AS
SELECT
  tde.source_doc_id     AS transaction_id,
  tde.company_id,
  tde.document_date     AS invoice_date,
  tde.counterparty_id   AS supplier_id,
  tde.counterparty_tin  AS supplier_tin,
  tde.counterparty_name AS supplier_name,
  tde.atc_code_id,
  ac.code               AS atc_code,
  COALESCE(NULLIF(tde.income_nature, ''), ac.description) AS nature_of_payment,
  tde.tax_rate,
  tde.tax_base,
  tde.tax_amount        AS tax_withheld
FROM tax_detail_entries tde
LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
WHERE tde.tax_kind = 'ewt_payable'
  AND tde.is_reversal = false;

GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_line_ewt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_ewt_ready(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_payment_voucher(UUID, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID) TO authenticated;
