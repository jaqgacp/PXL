-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 021: Wire CM/DM GL posting, PV void reversal, vendor credit apply
-- Fixes identified in Transaction Flow Audit
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. fn_save_credit_memo: wire GL posting when transitioning to 'applied' ───
-- When p_next_status = 'applied', save lines as 'approved' then call
-- fn_post_credit_memo which creates the journal entry and sets to 'applied'.

CREATE OR REPLACE FUNCTION fn_save_credit_memo(
  p_cm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_cm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  -- When applying, save data as 'approved' first, then let fn_post_credit_memo
  -- create the GL entry and set the final 'applied' status.
  v_effective_status := CASE WHEN p_next_status = 'applied' THEN 'approved' ELSE p_next_status END;

  IF p_cm_id IS NULL THEN
    v_cm_number := fn_next_document_number(v_company_id, v_branch_id, 'CM');

    INSERT INTO credit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      invoice_id, cm_number, cm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'invoice_id', '')::UUID,
      v_cm_number, (p_header->>'cm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0,
      v_effective_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_cm_id;

  ELSE
    SELECT id, status INTO v_cm_id, v_current_status
    FROM credit_memos WHERE id = p_cm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found or access denied'; END IF;

    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','applied','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','applied','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition credit memo from % to %', v_current_status, p_next_status;
    END IF;

    UPDATE credit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      invoice_id = NULLIF(p_header->>'invoice_id', '')::UUID,
      cm_date = (p_header->>'cm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  DELETE FROM credit_memo_lines WHERE credit_memo_id = v_cm_id;

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
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    v_total_net := v_total_net + v_net;
    v_total_vat := v_total_vat + v_vat_amt;
    v_total_amt := v_total_amt + v_total_line;

    INSERT INTO credit_memo_lines (
      credit_memo_id, company_id, line_number,
      invoice_line_id, item_id, description, quantity, unit_price,
      net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_cm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'invoice_line_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_qty, v_price,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE credit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    updated_at = NOW()
  WHERE id = v_cm_id;

  -- If the intent was 'applied', delegate to fn_post_credit_memo for GL + final status
  IF p_next_status = 'applied' THEN
    PERFORM fn_post_credit_memo(v_cm_id);
  END IF;

  RETURN v_cm_id;
END;
$$;

-- ── 2. fn_save_debit_memo: wire GL posting when transitioning to 'paid' ───────
-- When p_next_status = 'paid', save lines as 'approved' then call
-- fn_post_debit_memo which creates the journal entry and sets to 'paid'.

CREATE OR REPLACE FUNCTION fn_save_debit_memo(
  p_dm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_dm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_amount         NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF p_next_status NOT IN ('draft','approved','paid','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  -- When posting, save data as 'approved' first, then let fn_post_debit_memo
  -- create the GL entry and set the final 'paid' status.
  v_effective_status := CASE WHEN p_next_status = 'paid' THEN 'approved' ELSE p_next_status END;

  IF p_dm_id IS NULL THEN
    v_dm_number := fn_next_document_number(v_company_id, v_branch_id, 'DM-S');

    INSERT INTO debit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      source_doc_type, source_doc_id, dm_number, dm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'source_doc_type', ''),
      NULLIF(p_header->>'source_doc_id', '')::UUID,
      v_dm_number, (p_header->>'dm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0,
      v_effective_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_dm_id;

  ELSE
    SELECT id, status INTO v_dm_id, v_current_status
    FROM debit_memos WHERE id = p_dm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found or access denied'; END IF;

    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','paid','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','paid','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition debit memo from % to %', v_current_status, p_next_status;
    END IF;

    UPDATE debit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      source_doc_type = NULLIF(p_header->>'source_doc_type', ''),
      source_doc_id = NULLIF(p_header->>'source_doc_id', '')::UUID,
      dm_date = (p_header->>'dm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_dm_id;
  END IF;

  DELETE FROM debit_memo_lines WHERE debit_memo_id = v_dm_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_amount    := GREATEST(COALESCE((v_line->>'amount')::NUMERIC, 0), 0);
    v_vat_amt   := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_amount * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_amount + v_vat_amt;

    v_total_net := v_total_net + v_amount;
    v_total_vat := v_total_vat + v_vat_amt;
    v_total_amt := v_total_amt + v_total_line;

    INSERT INTO debit_memo_lines (
      debit_memo_id, company_id, line_number,
      account_id, item_id, description, amount,
      vat_code_id, vat_amount, total_amount,
      created_by, updated_by
    ) VALUES (
      v_dm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'account_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_amount,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE debit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    updated_at = NOW()
  WHERE id = v_dm_id;

  -- If the intent was 'paid', delegate to fn_post_debit_memo for GL + final status
  IF p_next_status = 'paid' THEN
    PERFORM fn_post_debit_memo(v_dm_id);
  END IF;

  RETURN v_dm_id;
END;
$$;

-- ── 3. fn_cancel_payment_voucher: void a posted PV with reversing JE ──────────

CREATE OR REPLACE FUNCTION fn_cancel_payment_voucher(
  p_voucher_id UUID,
  p_memo       TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_orig_je   journal_entries%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted payment vouchers can be voided (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_orig_je FROM journal_entries WHERE id = v_rec.journal_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original journal entry not found for this payment voucher'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for today. Create or unlock a fiscal period to process this void.';
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VOID-' || v_rec.voucher_number, CURRENT_DATE, v_fp_id,
    'VOID: ' || v_orig_je.description || COALESCE(' — ' || p_memo, ''),
    'PV', v_rec.id, 'posted',
    v_orig_je.total_debit, v_orig_je.total_credit,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_rev_je_id;

  FOR v_line IN
    SELECT * FROM journal_entry_lines WHERE je_id = v_orig_je.id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_rev_je_id, v_rec.company_id, v_line_no, v_line.account_id,
      'VOID — ' || v_line.description,
      v_line.credit_amount, v_line.debit_amount,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE journal_entries SET status = 'reversed', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_orig_je.id;

  UPDATE payment_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 4. fn_apply_vendor_credit: record credit application against a vendor bill ─
-- No new GL entry needed — the GL was already captured when the vendor credit was
-- posted (DR AP, CR Expense + Input VAT). This RPC tracks the allocation and
-- reduces the credit's remaining balance.

CREATE OR REPLACE FUNCTION fn_apply_vendor_credit(
  p_credit_id UUID,
  p_bill_id   UUID,
  p_amount    NUMERIC,
  p_date      DATE    DEFAULT CURRENT_DATE,
  p_remarks   TEXT    DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vc              vendor_credits%ROWTYPE;
  v_bill            vendor_bills%ROWTYPE;
  v_bill_paid       NUMERIC(15,2);
  v_bill_applied    NUMERIC(15,2);
  v_bill_outstanding NUMERIC(15,2);
  v_new_balance     NUMERIC(15,2);
  v_app_id          UUID;
BEGIN
  SELECT * INTO v_vc FROM vendor_credits WHERE id = p_credit_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor credit not found'; END IF;
  IF NOT is_company_member(v_vc.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_vc.status != 'open' THEN
    RAISE EXCEPTION 'Vendor credit must be in open status to apply (current: %)', v_vc.status;
  END IF;

  SELECT * INTO v_bill FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF v_bill.company_id != v_vc.company_id THEN
    RAISE EXCEPTION 'Credit and bill must belong to the same company';
  END IF;
  IF v_bill.supplier_id != v_vc.supplier_id THEN
    RAISE EXCEPTION 'Credit and bill must be for the same supplier';
  END IF;
  IF v_bill.status != 'posted' THEN
    RAISE EXCEPTION 'Vendor bill must be posted to apply credits (current: %)', v_bill.status;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Application amount must be greater than zero';
  END IF;
  IF p_amount > v_vc.remaining_balance THEN
    RAISE EXCEPTION 'Amount (%) exceeds vendor credit remaining balance (%)', p_amount, v_vc.remaining_balance;
  END IF;

  SELECT COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
  INTO v_bill_paid
  FROM payment_voucher_lines pvl
  JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
  WHERE pvl.vendor_bill_id = p_bill_id AND pv.status = 'posted';

  SELECT COALESCE(SUM(applied_amount), 0)
  INTO v_bill_applied
  FROM vendor_credit_applications
  WHERE vendor_bill_id = p_bill_id;

  v_bill_outstanding := v_bill.total_amount - v_bill_paid - v_bill_applied;

  IF v_bill_outstanding <= 0 THEN
    RAISE EXCEPTION 'Vendor bill has no outstanding balance';
  END IF;
  IF p_amount > v_bill_outstanding THEN
    RAISE EXCEPTION 'Amount (%) exceeds bill outstanding balance (%)', p_amount, v_bill_outstanding;
  END IF;

  INSERT INTO vendor_credit_applications (
    company_id, vendor_credit_id, vendor_bill_id, applied_amount, applied_date, applied_by, remarks
  ) VALUES (
    v_vc.company_id, p_credit_id, p_bill_id, p_amount, p_date, auth.uid(), p_remarks
  ) RETURNING id INTO v_app_id;

  v_new_balance := v_vc.remaining_balance - p_amount;
  UPDATE vendor_credits SET
    remaining_balance = v_new_balance,
    status = CASE WHEN v_new_balance = 0 THEN 'applied' ELSE status END,
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_credit_id;

  RETURN v_app_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_credit_memo(UUID, JSONB, JSONB, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_debit_memo(UUID, JSONB, JSONB, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_payment_voucher(UUID, TEXT)                   TO authenticated;
GRANT EXECUTE ON FUNCTION fn_apply_vendor_credit(UUID, UUID, NUMERIC, DATE, TEXT) TO authenticated;
