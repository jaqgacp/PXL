-- ══════════════════════════════════════════════════════════════════════════════
-- CREDIT MEMO AND DEBIT MEMO RPCS
-- fn_save_credit_memo, fn_save_debit_memo and their status transition RPCs.
-- Replaces multi-round-trip direct writes in CreditMemosPage/DebitMemosPage.
-- Server recomputes totals from line data; browser values not trusted.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── fn_save_credit_memo ───────────────────────────────────────────────────────
-- Atomically saves CM header + lines and transitions to p_next_status.
-- Status rules: draft → approved → applied; approved → draft (Return to Draft)
-- Returns CM UUID.

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
  -- Line computation
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  -- Totals
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- Validate status transition
  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

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
      p_next_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_cm_id;

  ELSE
    SELECT id, status INTO v_cm_id, v_current_status
    FROM credit_memos WHERE id = p_cm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found or access denied'; END IF;

    -- Validate allowed transitions
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
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0, -- recomputed below
      status = p_next_status,
      posted_at = CASE WHEN p_next_status = 'applied' AND v_current_status != 'applied' THEN NOW() ELSE posted_at END,
      posted_by = CASE WHEN p_next_status = 'applied' AND v_current_status != 'applied' THEN auth.uid() ELSE posted_by END,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  -- Replace lines with server-computed amounts
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

  RETURN v_cm_id;
END;
$$;

-- ── fn_save_debit_memo ────────────────────────────────────────────────────────
-- Atomically saves DM header + lines and transitions to p_next_status.
-- Status: draft → approved → paid; approved → draft (Return to Draft)

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
      p_next_status,
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
      status = p_next_status,
      posted_at = CASE WHEN p_next_status = 'paid' AND v_current_status != 'paid' THEN NOW() ELSE posted_at END,
      posted_by = CASE WHEN p_next_status = 'paid' AND v_current_status != 'paid' THEN auth.uid() ELSE posted_by END,
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

  RETURN v_dm_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_credit_memo(UUID, JSONB, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_debit_memo(UUID, JSONB, JSONB, TEXT)  TO authenticated;
