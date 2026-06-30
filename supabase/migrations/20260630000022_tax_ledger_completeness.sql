-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 022: Tax ledger completeness
-- • Add VAT breakdowns to credit_memos / debit_memos
-- • fn_save_credit_memo / fn_save_debit_memo: compute breakdown per line
-- • fn_post_credit_memo: populate negative output_vat in tax_detail_entries
-- • fn_post_debit_memo: populate positive output_vat in tax_detail_entries
-- • fn_post_vendor_credit: populate negative input_vat in tax_detail_entries
-- • fn_post_payment_voucher: per-line EWT with ATC, rate, correct tax_base
-- • vw_input_vat_review: add vendor credit negative rows
-- • vw_ewt_summary_ap: rebase on tax_detail_entries
-- • form_2307_issuance_lines: ATC-level certificate detail
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Schema: VAT breakdown columns ─────────────────────────────────────────────
ALTER TABLE credit_memos
  ADD COLUMN IF NOT EXISTS total_taxable_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_zero_rated_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_exempt_amount     NUMERIC(15,2) NOT NULL DEFAULT 0;

ALTER TABLE debit_memos
  ADD COLUMN IF NOT EXISTS total_taxable_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_zero_rated_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_exempt_amount     NUMERIC(15,2) NOT NULL DEFAULT 0;

-- ── form_2307_issuance_lines: ATC-level certificate detail ────────────────────
CREATE TABLE IF NOT EXISTS form_2307_issuance_lines (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  issuance_id      UUID          NOT NULL REFERENCES form_2307_issuances(id) ON DELETE CASCADE,
  company_id       UUID          NOT NULL REFERENCES companies(id),
  atc_code_id      UUID          REFERENCES atc_codes(id),
  atc_code         TEXT          NOT NULL,
  nature_of_income TEXT          NOT NULL DEFAULT '',
  tax_base         NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_rate         NUMERIC(5,2),
  tax_withheld     NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_f2307l_issuance ON form_2307_issuance_lines (issuance_id);

ALTER TABLE form_2307_issuance_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "f2307l_read"   ON form_2307_issuance_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "f2307l_insert" ON form_2307_issuance_lines FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "f2307l_delete" ON form_2307_issuance_lines FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── fn_save_credit_memo: compute taxable/zero_rated/exempt breakdown ──────────
CREATE OR REPLACE FUNCTION fn_save_credit_memo(
  p_cm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
  v_total_taxable  NUMERIC(15,2) := 0;
  v_total_zero     NUMERIC(15,2) := 0;
  v_total_exempt   NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  v_effective_status := CASE WHEN p_next_status = 'applied' THEN 'approved' ELSE p_next_status END;

  IF p_cm_id IS NULL THEN
    v_cm_number := fn_next_document_number(v_company_id, v_branch_id, 'CM');
    INSERT INTO credit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      invoice_id, cm_number, cm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'invoice_id', '')::UUID,
      v_cm_number, (p_header->>'cm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      v_effective_status, auth.uid(), auth.uid()
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
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  DELETE FROM credit_memo_lines WHERE credit_memo_id = v_cm_id;
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;
    v_total_net  := v_total_net + v_net;
    v_total_vat  := v_total_vat + v_vat_amt;
    v_total_amt  := v_total_amt + v_total_line;
    IF    v_vat_class = 'regular'   THEN v_total_taxable := v_total_taxable + v_net;
    ELSIF v_vat_class = 'zero_rated' THEN v_total_zero   := v_total_zero    + v_net;
    ELSE                                  v_total_exempt  := v_total_exempt  + v_net;
    END IF;
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
    total_taxable_amount = v_total_taxable, total_zero_rated_amount = v_total_zero,
    total_exempt_amount = v_total_exempt,
    updated_at = NOW()
  WHERE id = v_cm_id;

  IF p_next_status = 'applied' THEN
    PERFORM fn_post_credit_memo(v_cm_id);
  END IF;
  RETURN v_cm_id;
END;
$$;

-- ── fn_save_debit_memo: compute taxable/zero_rated/exempt breakdown ───────────
CREATE OR REPLACE FUNCTION fn_save_debit_memo(
  p_dm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
  v_total_taxable  NUMERIC(15,2) := 0;
  v_total_zero     NUMERIC(15,2) := 0;
  v_total_exempt   NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;
  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_next_status NOT IN ('draft','approved','paid','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;
  v_effective_status := CASE WHEN p_next_status = 'paid' THEN 'approved' ELSE p_next_status END;

  IF p_dm_id IS NULL THEN
    v_dm_number := fn_next_document_number(v_company_id, v_branch_id, 'DM-S');
    INSERT INTO debit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      source_doc_type, source_doc_id, dm_number, dm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'source_doc_type', ''),
      NULLIF(p_header->>'source_doc_id', '')::UUID,
      v_dm_number, (p_header->>'dm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      v_effective_status, auth.uid(), auth.uid()
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
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_dm_id;
  END IF;

  DELETE FROM debit_memo_lines WHERE debit_memo_id = v_dm_id;
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_amount    := GREATEST(COALESCE((v_line->>'amount')::NUMERIC, 0), 0);
    v_vat_amt   := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_amount * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_amount + v_vat_amt;
    v_total_net  := v_total_net + v_amount;
    v_total_vat  := v_total_vat + v_vat_amt;
    v_total_amt  := v_total_amt + v_total_line;
    IF    v_vat_class = 'regular'    THEN v_total_taxable := v_total_taxable + v_amount;
    ELSIF v_vat_class = 'zero_rated' THEN v_total_zero   := v_total_zero    + v_amount;
    ELSE                                  v_total_exempt  := v_total_exempt  + v_amount;
    END IF;
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
    total_taxable_amount = v_total_taxable, total_zero_rated_amount = v_total_zero,
    total_exempt_amount = v_total_exempt,
    updated_at = NOW()
  WHERE id = v_dm_id;

  IF p_next_status = 'paid' THEN
    PERFORM fn_post_debit_memo(v_dm_id);
  END IF;
  RETURN v_dm_id;
END;
$$;

-- ── fn_post_credit_memo: add negative output_vat to tax_detail_entries ─────────
CREATE OR REPLACE FUNCTION fn_post_credit_memo(p_cm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       credit_memos%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM credit_memos WHERE id = p_cm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Credit memo cannot be posted in status: %', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date, v_fp_id,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id,
            'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id,
            'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ar_account_id,
          'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;

  -- Negative output VAT in tax ledger (reversal of original SI output VAT)
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CM', v_rec.id,
      'output_vat', -v_rec.total_taxable_amount, -v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.cm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      true
    );
  END IF;
END;
$$;

-- ── fn_post_debit_memo: add positive output_vat to tax_detail_entries ──────────
CREATE OR REPLACE FUNCTION fn_post_debit_memo(p_dm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       debit_memos%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 2;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM debit_memos WHERE id = p_dm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Debit memo cannot be posted in status: %', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.dm_date
    AND end_date >= v_rec.dm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for DM date %. Create or unlock a fiscal period first.', v_rec.dm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-DM-' || v_rec.dm_number, v_rec.dm_date, v_fp_id,
    'Debit Memo ' || v_rec.dm_number || ' — ' || v_rec.customer_name_snapshot,
    'DM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id,
          'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  FOR v_line IN
    SELECT account_id, SUM(amount) AS amt_sum, description AS ln_desc
    FROM debit_memo_lines
    WHERE debit_memo_id = v_rec.id AND account_id IS NOT NULL
    GROUP BY account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.account_id,
            'DM charge — ' || v_line.ln_desc, 0, v_line.amt_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.amt_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id,
            'Output VAT — ' || v_rec.dm_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'DM journal entry unbalanced: DR=% CR=%. Ensure all DM lines have GL accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE debit_memos SET
    status = 'paid', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_dm_id;

  -- Positive output VAT in tax ledger
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'DM', v_rec.id,
      'output_vat', v_rec.total_taxable_amount, v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.dm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      false
    );
  END IF;
END;
$$;

-- ── fn_post_vendor_credit: add negative input_vat to tax_detail_entries ────────
CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.credit_date
    AND end_date >= v_rec.credit_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for credit date %. Create or unlock a fiscal period first.', v_rec.credit_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date, v_fp_id,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'VC', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Negative input VAT in tax ledger (reversal of original bill input VAT)
  IF v_rec.total_input_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'VC', v_rec.id,
      'input_vat', -v_rec.total_taxable_amount, -v_rec.total_input_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.credit_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      true
    );
  END IF;
END;
$$;

-- ── fn_post_payment_voucher: per-line EWT with ATC, rate, and correct tax_base ─
CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  FOR v_pvl IN
    SELECT id, ewt_amount, atc_code_id FROM payment_voucher_lines
    WHERE payment_voucher_id = p_voucher_id AND ewt_amount > 0
  LOOP
    IF v_pvl.atc_code_id IS NULL THEN
      RAISE EXCEPTION 'ATC code is required on payment voucher line when EWT amount is specified. Set the ATC code before posting.';
    END IF;
  END LOOP;

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
    'Payment Voucher ' || v_rec.voucher_number || ' — ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id, 'posted',
    v_ap_dr, v_ap_dr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP cleared — ' || v_rec.voucher_number, v_ap_dr, 0, auth.uid(), auth.uid());

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 2, v_cash_acct,
          'Cash paid — ' || v_rec.voucher_number, 0, v_rec.total_amount, auth.uid(), auth.uid());
  v_line_no := 3;

  IF v_rec.total_ewt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ewt_payable_account_id,
            'EWT withheld — ' || v_rec.voucher_number, 0, v_rec.total_ewt, auth.uid(), auth.uid());
  END IF;

  UPDATE payment_vouchers SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Per-line EWT tax ledger: accurate tax_base = payment_amount + ewt_amount
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
      v_pvl.payment_amount + v_pvl.ewt_amount,
      v_pvl.ewt_rate, v_pvl.ewt_amount, v_fp_id,
      NOW()::DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END LOOP;
END;
$$;

-- ── vw_input_vat_review: add vendor credits as negative rows ──────────────────
DROP VIEW IF EXISTS vw_input_vat_review;
CREATE OR REPLACE VIEW vw_input_vat_review AS
-- Vendor bills
SELECT
  vb.id                   AS transaction_id,
  'vendor_bill'           AS source_module,
  vb.company_id,
  vb.bill_date            AS invoice_date,
  vb.supplier_tin_snapshot AS supplier_tin,
  vb.supplier_name_snapshot AS supplier_name,
  ''                      AS supplier_address,
  vb.supplier_invoice_number AS invoice_no,
  vb.bill_number          AS system_no,
  vb.total_amount         AS gross_purchases,
  vb.total_exempt_amount  AS exempt_purchases,
  vb.total_zero_rated_amount AS zero_rated,
  vb.total_taxable_amount AS taxable_base,
  vb.total_input_vat_amount AS input_vat
FROM vendor_bills vb
WHERE vb.status = 'posted'

UNION ALL

-- Cash purchases
SELECT
  cp.id                   AS transaction_id,
  'cash_purchase'         AS source_module,
  cp.company_id,
  cp.transaction_date     AS invoice_date,
  cp.supplier_tin_snapshot AS supplier_tin,
  COALESCE(cp.supplier_name_snapshot, 'Cash Purchase') AS supplier_name,
  ''                      AS supplier_address,
  cp.reference_number     AS invoice_no,
  cp.cp_number            AS system_no,
  COALESCE(SUM(cpl.net_amount + cpl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'exempt'    THEN cpl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'zero_rated' THEN cpl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'regular'   THEN cpl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(cpl.input_vat_amount), 0) AS input_vat
FROM cash_purchases cp
JOIN cash_purchase_lines cpl ON cpl.cp_id = cp.id
LEFT JOIN vat_codes vc3 ON vc3.id = cpl.vat_code_id
WHERE cp.status = 'posted'
GROUP BY cp.id, cp.company_id, cp.transaction_date, cp.supplier_tin_snapshot,
         cp.supplier_name_snapshot, cp.reference_number, cp.cp_number

UNION ALL

-- Vendor credits: negative rows to reduce claimable input VAT
SELECT
  vc.id                   AS transaction_id,
  'vendor_credit'         AS source_module,
  vc.company_id,
  vc.credit_date          AS invoice_date,
  vc.supplier_tin_snapshot AS supplier_tin,
  vc.supplier_name_snapshot AS supplier_name,
  ''                      AS supplier_address,
  vc.supplier_cm_no       AS invoice_no,
  vc.vc_number            AS system_no,
  -COALESCE(SUM(vcl.net_amount + vcl.input_vat_amount), 0) AS gross_purchases,
  -COALESCE(SUM(CASE WHEN vc4.vat_classification = 'exempt'    THEN vcl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  -COALESCE(SUM(CASE WHEN vc4.vat_classification = 'zero_rated' THEN vcl.net_amount ELSE 0 END), 0) AS zero_rated,
  -COALESCE(SUM(CASE WHEN vc4.vat_classification = 'regular'   THEN vcl.net_amount ELSE 0 END), 0) AS taxable_base,
  -COALESCE(SUM(vcl.input_vat_amount), 0) AS input_vat
FROM vendor_credits vc
JOIN vendor_credit_lines vcl ON vcl.vc_id = vc.id
LEFT JOIN vat_codes vc4 ON vc4.id = vcl.vat_code_id
WHERE vc.status IN ('open', 'applied')
GROUP BY vc.id, vc.company_id, vc.credit_date, vc.supplier_tin_snapshot,
         vc.supplier_name_snapshot, vc.supplier_cm_no, vc.vc_number;

-- ── vw_ewt_summary_ap: rebase on tax_detail_entries ───────────────────────────
-- Eliminates reverse-derived tax base; uses actual stored base, rate, and ATC.
CREATE OR REPLACE VIEW vw_ewt_summary_ap AS
SELECT
  tde.source_doc_id    AS transaction_id,
  tde.company_id,
  tde.document_date    AS invoice_date,
  tde.counterparty_id  AS supplier_id,
  tde.counterparty_tin AS supplier_tin,
  tde.counterparty_name AS supplier_name,
  tde.atc_code_id,
  ac.code              AS atc_code,
  ac.description       AS nature_of_payment,
  tde.tax_rate,
  tde.tax_base,
  tde.tax_amount       AS tax_withheld
FROM tax_detail_entries tde
LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
WHERE tde.tax_kind = 'ewt_payable'
  AND tde.is_reversal = false;

GRANT EXECUTE ON FUNCTION fn_save_credit_memo(UUID, JSONB, JSONB, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_debit_memo(UUID, JSONB, JSONB, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_credit_memo(UUID)                               TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_debit_memo(UUID)                                TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID)                             TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID)                           TO authenticated;
