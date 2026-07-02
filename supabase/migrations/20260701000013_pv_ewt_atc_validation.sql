-- Validate payment voucher EWT against the selected ATC rate.
-- The current PV model stores net cash paid plus EWT withheld. The taxable base
-- used by the tax ledger is therefore payment_amount + ewt_amount.

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_line_ewt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_ewt_amount NUMERIC,
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
  v_expected NUMERIC(15,2);
  v_base NUMERIC(15,2);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_ewt_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Payment and EWT amounts cannot be negative.';
  END IF;

  IF COALESCE(p_ewt_amount, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when EWT amount is specified.';
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

  v_base := ROUND(COALESCE(p_payment_amount, 0) + COALESCE(p_ewt_amount, 0), 2);
  v_expected := ROUND(v_base * v_rate / 100.0, 2);

  IF ABS(v_expected - COALESCE(p_ewt_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'EWT amount % does not match ATC % rate %%% on taxable base %. Expected EWT is %.',
      p_ewt_amount, v_code, v_rate, v_base, v_expected;
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
    NEW.atc_code_id
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pvl_ewt_validation ON payment_voucher_lines;
CREATE TRIGGER trg_pvl_ewt_validation
  BEFORE INSERT OR UPDATE OF payment_amount, ewt_amount, atc_code_id, company_id
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
    SELECT company_id, payment_amount, ewt_amount, atc_code_id
    FROM payment_voucher_lines
    WHERE payment_voucher_id = p_voucher_id
  LOOP
    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.ewt_amount,
      v_line.atc_code_id
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_pv_ewt_ready_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted' THEN
    PERFORM fn_validate_payment_voucher_ewt_ready(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pv_ewt_ready_status ON payment_vouchers;
CREATE TRIGGER trg_pv_ewt_ready_status
  BEFORE INSERT OR UPDATE OF status, total_ewt
  ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_pv_ewt_ready_status();

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
    SELECT pvl.payment_amount, pvl.ewt_amount, pvl.atc_code_id, ac.rate AS ewt_rate
    FROM payment_voucher_lines pvl
    LEFT JOIN atc_codes ac ON ac.id = pvl.atc_code_id
    WHERE pvl.payment_voucher_id = p_voucher_id AND pvl.ewt_amount > 0
  LOOP
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id,
      'ewt_payable', v_pvl.atc_code_id,
      ROUND(v_pvl.payment_amount + v_pvl.ewt_amount, 2),
      v_pvl.ewt_rate, v_pvl.ewt_amount, v_fp_id,
      NOW()::DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID) TO authenticated;
