-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 024: Banking & Treasury — Posting/Cancel Functions + Views
-- All SECURITY DEFINER, SET search_path = public. Every posting:
--   * validates company membership + status (no double-post)
--   * requires an OPEN (is_locked = false) fiscal period covering the doc date
--   * writes a balanced journal entry (total_debit = total_credit)
-- Every cancel creates a reversing JE (swap dr/cr) and marks original 'reversed'.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Shared helper: reversing JE for a posted banking document ──────────────────
CREATE OR REPLACE FUNCTION fn_bt_reverse_je(
  p_company_id   UUID,
  p_branch_id    UUID,
  p_orig_je_id   UUID,
  p_ref_type     TEXT,
  p_ref_id       UUID,
  p_je_number    TEXT,
  p_memo         TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_orig   journal_entries%ROWTYPE;
  v_rev_id UUID;
  v_line   RECORD;
  v_no     INT := 1;
BEGIN
  SELECT * INTO v_orig FROM journal_entries WHERE id = p_orig_je_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original journal entry not found for reversal'; END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, CURRENT_DATE,
    (SELECT id FROM fiscal_periods WHERE company_id = p_company_id
       AND start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1),
    'REVERSAL: ' || v_orig.description || COALESCE(' — ' || p_memo, ''),
    p_ref_type, p_ref_id, 'posted',
    v_orig.total_credit, v_orig.total_debit,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_rev_id;

  FOR v_line IN SELECT * FROM journal_entry_lines WHERE je_id = v_orig.id ORDER BY line_number LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_rev_id, p_company_id, v_no, v_line.account_id,
      'REVERSAL — ' || COALESCE(v_line.description, ''),
      v_line.credit_amount, v_line.debit_amount,
      auth.uid(), auth.uid()
    );
    v_no := v_no + 1;
  END LOOP;

  UPDATE journal_entries SET status = 'reversed', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_orig.id;

  RETURN v_rev_id;
END;
$$;

-- ── fn_post_fund_transfer ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_fund_transfer(p_ft_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       fund_transfers%ROWTYPE;
  v_from_gl   UUID; v_from_name TEXT;
  v_to_gl     UUID; v_to_name   TEXT;
  v_fp_id     UUID;
  v_je_id     UUID;
BEGIN
  SELECT * INTO v_rec FROM fund_transfers WHERE id = p_ft_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Fund transfer not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft fund transfers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT gl_account_id, bank_name || ' — ' || account_number INTO v_from_gl, v_from_name
  FROM bank_accounts WHERE id = v_rec.from_account_id;
  SELECT gl_account_id, bank_name || ' — ' || account_number INTO v_to_gl, v_to_name
  FROM bank_accounts WHERE id = v_rec.to_account_id;
  IF v_from_gl IS NULL OR v_to_gl IS NULL THEN
    RAISE EXCEPTION 'Both bank accounts must have a GL account configured';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.transfer_date
    AND end_date >= v_rec.transfer_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for transfer date %', v_rec.transfer_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-FT-' || v_rec.ft_number, v_rec.transfer_date, v_fp_id,
    'Fund Transfer ' || v_rec.ft_number || ' — ' || v_from_name || ' → ' || v_to_name,
    'FT', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_to_gl,   'Transfer in — ' || v_to_name,    v_rec.amount, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_from_gl, 'Transfer out — ' || v_from_name, 0, v_rec.amount, auth.uid(), auth.uid());

  UPDATE fund_transfers SET status = 'posted', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    posted_at = NOW(), posted_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_cancel_fund_transfer ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_fund_transfer(p_ft_id UUID, p_memo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec   fund_transfers%ROWTYPE;
  v_fp_id UUID;
BEGIN
  SELECT * INTO v_rec FROM fund_transfers WHERE id = p_ft_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Fund transfer not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted fund transfers can be cancelled (current: %)', v_rec.status;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for today to process this cancellation'; END IF;

  PERFORM fn_bt_reverse_je(v_rec.company_id, v_rec.branch_id, v_rec.journal_entry_id,
    'FT', v_rec.id, 'JE-FT-REV-' || v_rec.ft_number, p_memo);

  UPDATE fund_transfers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_post_inter_branch_transfer ─────────────────────────────────────────────
-- Branches share one company_id, so a single balanced JE moves cash between the
-- two branches' bank GL accounts: DR to_account GL, CR from_account GL.
CREATE OR REPLACE FUNCTION fn_post_inter_branch_transfer(p_ibt_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec     inter_branch_transfers%ROWTYPE;
  v_from_gl UUID; v_to_gl UUID;
  v_fp_id   UUID; v_je_id UUID;
BEGIN
  SELECT * INTO v_rec FROM inter_branch_transfers WHERE id = p_ibt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inter-branch transfer not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft inter-branch transfers can be posted (current: %)', v_rec.status;
  END IF;
  IF v_rec.from_account_id IS NULL OR v_rec.to_account_id IS NULL THEN
    RAISE EXCEPTION 'Both source and destination bank accounts are required to post';
  END IF;

  SELECT gl_account_id INTO v_from_gl FROM bank_accounts WHERE id = v_rec.from_account_id;
  SELECT gl_account_id INTO v_to_gl   FROM bank_accounts WHERE id = v_rec.to_account_id;
  IF v_from_gl IS NULL OR v_to_gl IS NULL THEN
    RAISE EXCEPTION 'Both bank accounts must have a GL account configured';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.transfer_date
    AND end_date >= v_rec.transfer_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for transfer date %', v_rec.transfer_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.to_branch_id, 'JE-IBT-' || v_rec.ibt_number, v_rec.transfer_date, v_fp_id,
    'Inter-Branch Transfer ' || v_rec.ibt_number,
    'IBT', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_to_gl,   'IBT in — '  || v_rec.ibt_number, v_rec.amount, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_from_gl, 'IBT out — ' || v_rec.ibt_number, 0, v_rec.amount, auth.uid(), auth.uid());

  UPDATE inter_branch_transfers SET status = 'posted', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    posted_at = NOW(), posted_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_cancel_inter_branch_transfer ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_inter_branch_transfer(p_ibt_id UUID, p_memo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec   inter_branch_transfers%ROWTYPE;
  v_fp_id UUID;
BEGIN
  SELECT * INTO v_rec FROM inter_branch_transfers WHERE id = p_ibt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inter-branch transfer not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted inter-branch transfers can be cancelled (current: %)', v_rec.status;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for today to process this cancellation'; END IF;

  PERFORM fn_bt_reverse_je(v_rec.company_id, v_rec.to_branch_id, v_rec.journal_entry_id,
    'IBT', v_rec.id, 'JE-IBT-REV-' || v_rec.ibt_number, p_memo);

  UPDATE inter_branch_transfers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_post_bank_adjustment ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_bank_adjustment(p_ba_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec     bank_adjustments%ROWTYPE;
  v_bank_gl UUID;
  v_fp_id   UUID; v_je_id UUID;
  v_is_credit BOOLEAN;
BEGIN
  SELECT * INTO v_rec FROM bank_adjustments WHERE id = p_ba_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bank adjustment not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft bank adjustments can be posted (current: %)', v_rec.status;
  END IF;

  SELECT gl_account_id INTO v_bank_gl FROM bank_accounts WHERE id = v_rec.bank_account_id;
  IF v_bank_gl IS NULL THEN RAISE EXCEPTION 'Bank account has no GL account configured'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.adjustment_date
    AND end_date >= v_rec.adjustment_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for adjustment date %', v_rec.adjustment_date;
  END IF;

  -- Credit-to-bank types increase cash (DR bank, CR other account)
  v_is_credit := v_rec.adjustment_type IN ('bank_credit_memo','interest_income','other_credit');

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-BADJ-' || v_rec.ba_number, v_rec.adjustment_date, v_fp_id,
    'Bank Adj ' || v_rec.ba_number || ' — ' || v_rec.description,
    'BADJ', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  IF v_is_credit THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 1, v_bank_gl,          v_rec.description, v_rec.amount, 0, auth.uid(), auth.uid()),
           (v_je_id, v_rec.company_id, 2, v_rec.gl_account_id, v_rec.description, 0, v_rec.amount, auth.uid(), auth.uid());
  ELSE
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 1, v_rec.gl_account_id, v_rec.description, v_rec.amount, 0, auth.uid(), auth.uid()),
           (v_je_id, v_rec.company_id, 2, v_bank_gl,          v_rec.description, 0, v_rec.amount, auth.uid(), auth.uid());
  END IF;

  UPDATE bank_adjustments SET status = 'posted', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    posted_at = NOW(), posted_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_cancel_bank_adjustment ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_bank_adjustment(p_ba_id UUID, p_memo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec   bank_adjustments%ROWTYPE;
  v_fp_id UUID;
BEGIN
  SELECT * INTO v_rec FROM bank_adjustments WHERE id = p_ba_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bank adjustment not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted bank adjustments can be cancelled (current: %)', v_rec.status;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for today to process this cancellation'; END IF;

  PERFORM fn_bt_reverse_je(v_rec.company_id, v_rec.branch_id, v_rec.journal_entry_id,
    'BADJ', v_rec.id, 'JE-BADJ-REV-' || v_rec.ba_number, p_memo);

  UPDATE bank_adjustments SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_approve_petty_cash_voucher ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_approve_petty_cash_voucher(p_pcv_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec    petty_cash_vouchers%ROWTYPE;
  v_pcf_gl UUID;
  v_fp_id  UUID; v_je_id UUID;
BEGIN
  SELECT * INTO v_rec FROM petty_cash_vouchers WHERE id = p_pcv_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Petty cash voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft petty cash vouchers can be approved (current: %)', v_rec.status;
  END IF;

  SELECT gl_account_id INTO v_pcf_gl FROM petty_cash_funds WHERE id = v_rec.fund_id;
  IF v_pcf_gl IS NULL THEN RAISE EXCEPTION 'Petty cash fund has no GL account configured'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for voucher date %', v_rec.voucher_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-PCV-' || v_rec.pcv_number, v_rec.voucher_date, v_fp_id,
    'Petty Cash Voucher ' || v_rec.pcv_number || ' — ' || v_rec.payee,
    'PCV', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_rec.expense_account_id, v_rec.purpose, v_rec.amount, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_pcf_gl, 'Petty cash — ' || v_rec.pcv_number, 0, v_rec.amount, auth.uid(), auth.uid());

  UPDATE petty_cash_vouchers SET status = 'approved', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    posted_at = NOW(), posted_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_cancel_petty_cash_voucher ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_petty_cash_voucher(p_pcv_id UUID, p_memo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec   petty_cash_vouchers%ROWTYPE;
  v_fp_id UUID;
BEGIN
  SELECT * INTO v_rec FROM petty_cash_vouchers WHERE id = p_pcv_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Petty cash voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'replenished' THEN
    RAISE EXCEPTION 'Cannot cancel a replenished petty cash voucher';
  END IF;
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Petty cash voucher is already cancelled';
  END IF;

  IF v_rec.status = 'draft' THEN
    UPDATE petty_cash_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_rec.id;
    RETURN;
  END IF;

  -- approved → reverse the GL entry
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for today to process this cancellation'; END IF;

  PERFORM fn_bt_reverse_je(v_rec.company_id, v_rec.branch_id, v_rec.journal_entry_id,
    'PCV', v_rec.id, 'JE-PCV-REV-' || v_rec.pcv_number, p_memo);

  UPDATE petty_cash_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_post_petty_cash_replenishment ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_petty_cash_replenishment(p_pcr_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec     petty_cash_replenishments%ROWTYPE;
  v_pcf_gl  UUID;
  v_bank_gl UUID;
  v_sum     NUMERIC(15,2);
  v_fp_id   UUID; v_je_id UUID;
BEGIN
  SELECT * INTO v_rec FROM petty_cash_replenishments WHERE id = p_pcr_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Replenishment not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft replenishments can be posted (current: %)', v_rec.status;
  END IF;
  IF v_rec.bank_account_id IS NULL THEN
    RAISE EXCEPTION 'A funding bank account is required to post the replenishment';
  END IF;

  SELECT gl_account_id INTO v_pcf_gl  FROM petty_cash_funds WHERE id = v_rec.fund_id;
  SELECT gl_account_id INTO v_bank_gl FROM bank_accounts    WHERE id = v_rec.bank_account_id;
  IF v_pcf_gl IS NULL OR v_bank_gl IS NULL THEN
    RAISE EXCEPTION 'Fund and bank account must both have GL accounts configured';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_sum
  FROM petty_cash_vouchers
  WHERE fund_id = v_rec.fund_id AND status = 'approved' AND replenishment_id IS NULL;

  IF v_sum <= 0 THEN
    RAISE EXCEPTION 'No approved unreplenished vouchers to replenish for this fund';
  END IF;
  IF ABS(v_rec.total_amount - v_sum) > 0.01 THEN
    RAISE EXCEPTION 'Replenishment total (%) does not match approved unreplenished vouchers (%)', v_rec.total_amount, v_sum;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.replenishment_date
    AND end_date >= v_rec.replenishment_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for replenishment date %', v_rec.replenishment_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-PCR-' || v_rec.pcr_number, v_rec.replenishment_date, v_fp_id,
    'Petty Cash Replenishment ' || v_rec.pcr_number,
    'PCR', v_rec.id, 'posted', v_sum, v_sum, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_pcf_gl,  'Replenish petty cash — ' || v_rec.pcr_number, v_sum, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_bank_gl, 'Bank disbursement — ' || v_rec.pcr_number, 0, v_sum, auth.uid(), auth.uid());

  UPDATE petty_cash_vouchers SET status = 'replenished', replenishment_id = v_rec.id,
    updated_by = auth.uid(), updated_at = NOW()
  WHERE fund_id = v_rec.fund_id AND status = 'approved' AND replenishment_id IS NULL;

  UPDATE petty_cash_replenishments SET status = 'posted', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    total_amount = v_sum, posted_at = NOW(), posted_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_post_check_voucher ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_check_voucher(p_cv_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec      check_vouchers%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_bank_gl  UUID;
  v_gross    NUMERIC(15,2);
  v_net      NUMERIC(15,2);
  v_fp_id    UUID; v_je_id UUID;
  v_line     RECORD;
  v_no       INT := 1;
BEGIN
  SELECT * INTO v_rec FROM check_vouchers WHERE id = p_cv_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Check voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft check vouchers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT gl_account_id INTO v_bank_gl FROM bank_accounts WHERE id = v_rec.bank_account_id;
  IF v_bank_gl IS NULL THEN RAISE EXCEPTION 'Bank account has no GL account configured'; END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_gross FROM check_voucher_lines WHERE cv_id = v_rec.id;
  IF v_gross <= 0 THEN RAISE EXCEPTION 'Check voucher must have at least one expense line'; END IF;

  IF v_rec.total_ewt_amount > 0 AND v_rec.atc_code_id IS NULL THEN
    RAISE EXCEPTION 'An ATC code is required when EWT is withheld';
  END IF;

  v_net := v_gross - v_rec.total_ewt_amount;
  IF v_net <= 0 THEN RAISE EXCEPTION 'Net check amount must be greater than zero'; END IF;

  IF v_rec.total_ewt_amount > 0 THEN
    SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
    IF NOT FOUND OR v_cfg.ewt_payable_account_id IS NULL THEN
      RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
    END IF;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for voucher date %', v_rec.voucher_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-CV-' || v_rec.cv_number, v_rec.voucher_date, v_fp_id,
    'Check Voucher ' || v_rec.cv_number || ' — ' || v_rec.payee,
    'CV', v_rec.id, 'posted', v_gross, v_gross, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR each distinct expense account
  FOR v_line IN
    SELECT expense_account_id, SUM(amount) AS amt
    FROM check_voucher_lines WHERE cv_id = v_rec.id
    GROUP BY expense_account_id
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_line.expense_account_id, v_rec.particulars, v_line.amt, 0, auth.uid(), auth.uid());
    v_no := v_no + 1;
  END LOOP;

  -- CR bank (net) + CR EWT payable (if any)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_no, v_bank_gl, 'Check ' || v_rec.check_number || ' — ' || v_rec.payee, 0, v_net, auth.uid(), auth.uid());
  v_no := v_no + 1;

  IF v_rec.total_ewt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_cfg.ewt_payable_account_id, 'EWT withheld — ' || v_rec.cv_number, 0, v_rec.total_ewt_amount, auth.uid(), auth.uid());

    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id, tax_kind, atc_code_id,
      tax_base, tax_rate, tax_amount, tax_period_id, posting_date, document_date,
      counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CV', v_rec.id, 'ewt_payable', v_rec.atc_code_id,
      v_gross, v_rec.ewt_rate, v_rec.total_ewt_amount, v_fp_id, NOW()::DATE, v_rec.voucher_date,
      v_rec.payee_tin, v_rec.payee
    );
  END IF;

  UPDATE check_vouchers SET status = 'posted', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    total_gross_amount = v_gross, posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_cancel_check_voucher ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_check_voucher(p_cv_id UUID, p_memo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec   check_vouchers%ROWTYPE;
  v_fp_id UUID;
BEGIN
  SELECT * INTO v_rec FROM check_vouchers WHERE id = p_cv_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Check voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('posted','released') THEN
    RAISE EXCEPTION 'Only posted or released check vouchers can be cancelled (current: %)', v_rec.status;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for today to process this cancellation'; END IF;

  PERFORM fn_bt_reverse_je(v_rec.company_id, v_rec.branch_id, v_rec.journal_entry_id,
    'CV', v_rec.id, 'JE-CV-REV-' || v_rec.cv_number, p_memo);

  -- Reverse EWT tax detail if present
  IF v_rec.total_ewt_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id, tax_kind, atc_code_id,
      tax_base, tax_rate, tax_amount, tax_period_id, posting_date, document_date,
      counterparty_tin, counterparty_name, is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CV', v_rec.id, 'ewt_payable', v_rec.atc_code_id,
      -v_rec.total_gross_amount, v_rec.ewt_rate, -v_rec.total_ewt_amount, v_fp_id, NOW()::DATE, v_rec.voucher_date,
      v_rec.payee_tin, v_rec.payee, true
    );
  END IF;

  UPDATE check_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── Views ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_outstanding_checks AS
SELECT cv.id, cv.company_id, cv.cv_number, cv.voucher_date,
       cv.check_number, cv.check_date, cv.payee, cv.payee_tin,
       cv.net_check_amount, cv.status, cv.particulars,
       cv.bank_account_id,
       ba.bank_name, ba.account_number, ba.account_name,
       CURRENT_DATE - cv.check_date AS days_outstanding
FROM check_vouchers cv
JOIN bank_accounts ba ON ba.id = cv.bank_account_id
WHERE cv.status IN ('posted','released');

CREATE OR REPLACE VIEW vw_deposits_in_transit AS
SELECT bri.id, bri.reconciliation_id, bri.company_id,
       bri.description, bri.document_date, bri.amount, bri.reference_doc_type,
       br.recon_month, br.recon_year, br.bank_account_id,
       ba.bank_name, ba.account_number
FROM bank_recon_items bri
JOIN bank_reconciliations br ON br.id = bri.reconciliation_id
JOIN bank_accounts ba ON ba.id = br.bank_account_id
WHERE bri.item_type = 'deposit_in_transit';

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_bt_reverse_je(UUID, UUID, UUID, TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_fund_transfer(UUID)               TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_fund_transfer(UUID, TEXT)       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_inter_branch_transfer(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_inter_branch_transfer(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_bank_adjustment(UUID)             TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_bank_adjustment(UUID, TEXT)     TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_petty_cash_voucher(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_petty_cash_voucher(UUID, TEXT)  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_petty_cash_replenishment(UUID)    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_check_voucher(UUID)               TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_check_voucher(UUID, TEXT)       TO authenticated;
GRANT SELECT ON vw_outstanding_checks   TO authenticated;
GRANT SELECT ON vw_deposits_in_transit  TO authenticated;
