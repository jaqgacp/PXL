-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 6 (Treasury writers)
--
-- GL-persistence-only migration of Bank Adjustment, Fund Transfer, Inter-Branch
-- Transfer, Petty Cash Voucher approval, Petty Cash Replenishment, and Check
-- Voucher. All validations, messages, period lookup, source-derived numbering,
-- tax detail, document lifecycle, and line ordering are unchanged.
--
-- No new helper or classifier entry; guard remains observe-only.
-- ══════════════════════════════════════════════════════════════════════════════
DO $migration$
DECLARE
  v_signature  REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  -- ── Bank Adjustment ──────────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_bank_adjustment_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-BADJ-' || v_rec.ba_number, v_rec.adjustment_date, v_fp_id,
    'Bank Adj ' || v_rec.ba_number || ' — ' || v_rec.description,
    'BADJ', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-BADJ-' || v_rec.ba_number, v_rec.adjustment_date,
    'Bank Adj ' || v_rec.ba_number || ' — ' || v_rec.description,
    'BADJ', v_rec.id,
    v_fp_id, 'posted', v_rec.amount, v_rec.amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Bank Adjustment header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 1, v_bank_gl,          v_rec.description, v_rec.amount, 0, auth.uid(), auth.uid()),
           (v_je_id, v_rec.company_id, 2, v_rec.gl_account_id, v_rec.description, 0, v_rec.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, 1, v_bank_gl, v_rec.description, v_rec.amount, 0
    );
    PERFORM fn_add_posting_line_push(
      v_je_id, 2, v_rec.gl_account_id, v_rec.description, 0, v_rec.amount
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Bank Adjustment credit lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 1, v_rec.gl_account_id, v_rec.description, v_rec.amount, 0, auth.uid(), auth.uid()),
           (v_je_id, v_rec.company_id, 2, v_bank_gl,          v_rec.description, 0, v_rec.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, 1, v_rec.gl_account_id, v_rec.description, v_rec.amount, 0
    );
    PERFORM fn_add_posting_line_push(
      v_je_id, 2, v_bank_gl, v_rec.description, 0, v_rec.amount
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Bank Adjustment debit lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Fund Transfer ────────────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_fund_transfer_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-FT-' || v_rec.ft_number, v_rec.transfer_date, v_fp_id,
    'Fund Transfer ' || v_rec.ft_number || ' — ' || v_from_name || ' → ' || v_to_name,
    'FT', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-FT-' || v_rec.ft_number, v_rec.transfer_date,
    'Fund Transfer ' || v_rec.ft_number || ' — ' || v_from_name || ' → ' || v_to_name,
    'FT', v_rec.id,
    v_fp_id, 'posted', v_rec.amount, v_rec.amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Fund Transfer header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_to_gl,   'Transfer in — ' || v_to_name,    v_rec.amount, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_from_gl, 'Transfer out — ' || v_from_name, 0, v_rec.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_to_gl, 'Transfer in — ' || v_to_name, v_rec.amount, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_from_gl, 'Transfer out — ' || v_from_name, 0, v_rec.amount
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Fund Transfer lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Inter-Branch Transfer ─────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_inter_branch_transfer_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.to_branch_id, 'JE-IBT-' || v_rec.ibt_number, v_rec.transfer_date, v_fp_id,
    'Inter-Branch Transfer ' || v_rec.ibt_number,
    'IBT', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.to_branch_id,
    'JE-IBT-' || v_rec.ibt_number, v_rec.transfer_date,
    'Inter-Branch Transfer ' || v_rec.ibt_number,
    'IBT', v_rec.id,
    v_fp_id, 'posted', v_rec.amount, v_rec.amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Inter-Branch Transfer header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_to_gl,   'IBT in — '  || v_rec.ibt_number, v_rec.amount, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_from_gl, 'IBT out — ' || v_rec.ibt_number, 0, v_rec.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_to_gl, 'IBT in — ' || v_rec.ibt_number, v_rec.amount, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_from_gl, 'IBT out — ' || v_rec.ibt_number, 0, v_rec.amount
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Inter-Branch Transfer lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Petty Cash Voucher ───────────────────────────────────────────────────────
  v_signature :=
    'public.fn_approve_petty_cash_voucher_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-PCV-' || v_rec.pcv_number, v_rec.voucher_date, v_fp_id,
    'Petty Cash Voucher ' || v_rec.pcv_number || ' — ' || v_rec.payee,
    'PCV', v_rec.id, 'posted', v_rec.amount, v_rec.amount, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-PCV-' || v_rec.pcv_number, v_rec.voucher_date,
    'Petty Cash Voucher ' || v_rec.pcv_number || ' — ' || v_rec.payee,
    'PCV', v_rec.id,
    v_fp_id, 'posted', v_rec.amount, v_rec.amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Petty Cash Voucher header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_rec.expense_account_id, v_rec.purpose, v_rec.amount, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_pcf_gl, 'Petty cash — ' || v_rec.pcv_number, 0, v_rec.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_rec.expense_account_id, v_rec.purpose, v_rec.amount, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_pcf_gl, 'Petty cash — ' || v_rec.pcv_number, 0, v_rec.amount
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Petty Cash Voucher lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Petty Cash Replenishment ─────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_petty_cash_replenishment_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-PCR-' || v_rec.pcr_number, v_rec.replenishment_date, v_fp_id,
    'Petty Cash Replenishment ' || v_rec.pcr_number,
    'PCR', v_rec.id, 'posted', v_sum, v_sum, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-PCR-' || v_rec.pcr_number, v_rec.replenishment_date,
    'Petty Cash Replenishment ' || v_rec.pcr_number,
    'PCR', v_rec.id,
    v_fp_id, 'posted', v_sum, v_sum,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Petty Cash Replenishment header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_pcf_gl,  'Replenish petty cash — ' || v_rec.pcr_number, v_sum, 0, auth.uid(), auth.uid()),
         (v_je_id, v_rec.company_id, 2, v_bank_gl, 'Bank disbursement — ' || v_rec.pcr_number, 0, v_sum, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_pcf_gl, 'Replenish petty cash — ' || v_rec.pcr_number,
    v_sum, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_bank_gl, 'Bank disbursement — ' || v_rec.pcr_number,
    0, v_sum
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Petty Cash Replenishment lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Check Voucher ────────────────────────────────────────────────────────────
  v_signature := 'public.fn_post_check_voucher(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-CV-' || v_rec.cv_number, v_rec.voucher_date, v_fp_id,
    'Check Voucher ' || v_rec.cv_number || ' — ' || v_rec.payee,
    'CV', v_rec.id, 'posted', v_gross, v_gross, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-CV-' || v_rec.cv_number, v_rec.voucher_date,
    'Check Voucher ' || v_rec.cv_number || ' — ' || v_rec.payee,
    'CV', v_rec.id,
    v_fp_id, 'posted', v_gross, v_gross,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Check Voucher header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_line.expense_account_id, v_rec.particulars, v_line.amt, 0, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_no, v_line.expense_account_id,
      v_rec.particulars, v_line.amt, 0
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Check Voucher expense lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_no, v_bank_gl, 'Check ' || v_rec.check_number || ' — ' || v_rec.payee, 0, v_net, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, v_no, v_bank_gl,
    'Check ' || v_rec.check_number || ' — ' || v_rec.payee, 0, v_net
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Check Voucher bank line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_ewt, 'EWT withheld — ' || v_rec.cv_number, 0, v_rec.total_ewt_amount, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_no, v_ewt,
      'EWT withheld — ' || v_rec.cv_number, 0, v_rec.total_ewt_amount
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 6 source drift: Check Voucher EWT line';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

