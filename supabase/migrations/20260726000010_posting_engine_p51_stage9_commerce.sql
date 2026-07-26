-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 9 (Purchase Return + Cash Sale)
--
-- Completes the authoritative forward-writer migration surface. Purchase Return's
-- historical "no mapped expense account => discard provisional JE" sequence is
-- preserved exactly through an explicit default-off finalizer mode:
--   UPDATE header totals to 0/0 -> DELETE lines -> DELETE header.
-- Cash Sale retains its two journals, line roles/order, tax detail, document
-- lifecycle, calculations, source-derived numbering, and posting_origin='system'.
--
-- No Tax Engine change, no heuristic routing, no classifier growth, and no guard
-- enforcement.
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_finalize_journal_entry(
  uuid, numeric, numeric, boolean, text, uuid, boolean, uuid, boolean
);

CREATE FUNCTION public.fn_finalize_journal_entry(
  p_je_id                         UUID,
  p_total_debit                   NUMERIC DEFAULT NULL,
  p_total_credit                  NUMERIC DEFAULT NULL,
  p_persist_totals                BOOLEAN DEFAULT false,
  p_link_reference_doc_type       TEXT DEFAULT NULL,
  p_link_reference_doc_id         UUID DEFAULT NULL,
  p_link_source                   BOOLEAN DEFAULT false,
  p_auto_reversal_original_je_id  UUID DEFAULT NULL,
  p_mark_auto_reversal            BOOLEAN DEFAULT false,
  p_discard_journal               BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_je journal_entries%ROWTYPE;
  v_debit NUMERIC(15,2);
  v_credit NUMERIC(15,2);
  v_line_count INTEGER;
BEGIN
  IF p_discard_journal THEN
    UPDATE journal_entries
    SET total_debit = 0,
        total_credit = 0
    WHERE id = p_je_id;
    DELETE FROM journal_entry_lines WHERE je_id = p_je_id;
    DELETE FROM journal_entries WHERE id = p_je_id;
    RETURN;
  END IF;

  IF p_mark_auto_reversal THEN
    UPDATE journal_entries
    SET is_auto_reversal = true
    WHERE reference_doc_id = p_auto_reversal_original_je_id
      AND reference_doc_type = 'REV';
    RETURN;
  END IF;

  IF p_link_source THEN
    UPDATE journal_entries
    SET reference_doc_type = COALESCE(
          p_link_reference_doc_type, reference_doc_type
        ),
        reference_doc_id = p_link_reference_doc_id,
        updated_at = NOW()
    WHERE id = p_je_id
      AND (
        (p_link_reference_doc_type IS NOT NULL
          AND reference_doc_type IS DISTINCT FROM p_link_reference_doc_type)
        OR reference_doc_id IS DISTINCT FROM p_link_reference_doc_id
      );
    RETURN;
  END IF;

  IF p_persist_totals THEN
    UPDATE journal_entries
    SET total_debit = p_total_debit,
        total_credit = p_total_credit
    WHERE id = p_je_id;
    RETURN;
  END IF;

  SELECT * INTO v_je
  FROM journal_entries
  WHERE id = p_je_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Journal entry not found';
  END IF;

  SELECT
    COALESCE(ROUND(SUM(debit_amount), 2), 0),
    COALESCE(ROUND(SUM(credit_amount), 2), 0),
    COUNT(*)
  INTO v_debit, v_credit, v_line_count
  FROM journal_entry_lines
  WHERE je_id = p_je_id;

  IF v_line_count = 0 THEN
    IF v_je.reference_doc_type = 'INV_COUNT'
       AND COALESCE(v_je.total_debit, 0) = 0
       AND COALESCE(v_je.total_credit, 0) = 0 THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Posted journal entry % has no lines', v_je.je_number;
  END IF;

  IF ABS(v_debit - v_credit) > 0.01 THEN
    RAISE EXCEPTION 'Journal entry % is unbalanced: debit % <> credit %',
      v_je.je_number, v_debit, v_credit;
  END IF;

  IF v_debit <= 0 THEN
    RAISE EXCEPTION 'Journal entry % has no financial amount', v_je.je_number;
  END IF;

  IF COALESCE(v_je.total_debit, 0) <> v_debit
     OR COALESCE(v_je.total_credit, 0) <> v_credit THEN
    UPDATE journal_entries
    SET total_debit = v_debit,
        total_credit = v_credit,
        updated_at = NOW()
    WHERE id = p_je_id;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_finalize_journal_entry(
  uuid, numeric, numeric, boolean, text, uuid, boolean, uuid, boolean, boolean
) FROM PUBLIC;

DO $migration$
DECLARE
  v_signature  REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  -- ── Purchase Return ──────────────────────────────────────────────────────────
  v_signature :=
    'public.fn_complete_purchase_return_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$      INSERT INTO journal_entries (
        company_id, branch_id, je_number, je_date, fiscal_period_id,
        description, reference_doc_type, reference_doc_id, status,
        total_debit, total_credit, created_by, updated_by
      ) VALUES (
        v_rec.company_id, v_rec.branch_id,
        fn_next_document_number(v_rec.company_id, v_rec.branch_id, 'JE'),
        v_rec.return_date, v_fp_id,
        'Purchase Return ' || v_rec.return_number || ' — ' || v_rec.supplier_name_snapshot,
        'PR', v_rec.id, 'posted',
        v_ret_total, v_ret_total,
        auth.uid(), auth.uid()
      ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$      v_je_id := fn_create_posted_journal_entry(
        v_rec.company_id, v_rec.branch_id,
        fn_next_document_number(v_rec.company_id, v_rec.branch_id, 'JE'),
        v_rec.return_date,
        'Purchase Return ' || v_rec.return_number
          || ' — ' || v_rec.supplier_name_snapshot,
        'PR', v_rec.id,
        v_fp_id, 'posted', v_ret_total, v_ret_total,
        NULL, 'regular', false, false, false
      );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Purchase Return header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$      INSERT INTO journal_entry_lines (
        je_id, company_id, line_number, account_id, description,
        debit_amount, credit_amount, created_by, updated_by
      ) VALUES (
        v_je_id, v_rec.company_id, 1, v_ap,
        'AP reversal — ' || v_rec.return_number,
        v_ret_total, 0, auth.uid(), auth.uid()
      );$old$;
  v_after := $new$      PERFORM fn_add_posting_line_push(
        v_je_id, 1, v_ap,
        'AP reversal — ' || v_rec.return_number,
        v_ret_total, 0
      );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Purchase Return AP line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$        INSERT INTO journal_entry_lines (
          je_id, company_id, line_number, account_id, description,
          debit_amount, credit_amount, created_by, updated_by
        ) VALUES (
          v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
          'Return of: ' || v_line.ln_desc,
          0, v_line.rev_amount, auth.uid(), auth.uid()
        );$old$;
  v_after := $new$        PERFORM fn_add_posting_line_push(
          v_je_id, v_line_no, v_line.expense_account_id,
          'Return of: ' || v_line.ln_desc,
          0, v_line.rev_amount
        );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Purchase Return expense lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$        UPDATE journal_entries
        SET total_debit = 0, total_credit = 0
        WHERE id = v_je_id;
        DELETE FROM journal_entry_lines WHERE je_id = v_je_id;
        DELETE FROM journal_entries WHERE id = v_je_id;
        v_je_id := NULL;$old$;
  v_after := $new$        PERFORM fn_finalize_journal_entry(
          p_je_id => v_je_id,
          p_discard_journal => true
        );
        v_je_id := NULL;$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Purchase Return no-JE fallback';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Cash Sale: Sales Invoice header + lines ──────────────────────────────────
  v_signature := 'public.fn_save_cash_sale(jsonb,jsonb,numeric)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  -- Post SI JE: DR AR, CR Revenue lines, CR VAT Payable
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id, 'posted', v_grand_total, v_grand_total, 'system', auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_si_id;$old$;
  v_after := $new$  -- Post SI JE: DR AR, CR Revenue lines, CR VAT Payable
  v_je_si_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, (p_header->>'date')::DATE,
    'Cash Sale ' || v_si_number || ' — '
      || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id,
    v_fp_id, 'posted', v_grand_total, v_grand_total,
    'system', 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale SI header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_si_id, v_company_id, 1, v_ar, 'AR — ' || (p_header->>'customer_name_snapshot'), v_grand_total, 0, 'control', auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_si_id, 1, v_ar,
    'AR — ' || (p_header->>'customer_name_snapshot'),
    v_grand_total, 0, 'control'
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale SI control line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_rev_line.revenue_account_id, 'Revenue — ' || v_rev_line.ln_desc, 0, v_rev_line.net_sum, 'base', auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_rev_line_no, v_rev_line.revenue_account_id,
      'Revenue — ' || v_rev_line.ln_desc,
      0, v_rev_line.net_sum, 'base'
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale SI revenue lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_vat, 'Output VAT — ' || v_si_number, 0, v_total_vat, 'tax', auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_rev_line_no, v_vat,
      'Output VAT — ' || v_si_number,
      0, v_total_vat, 'tax'
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale SI VAT line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  -- Cash Sale: Receipt header + lines
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-OR-' || v_or_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id, 'posted', v_grand_total, v_grand_total, 'system', auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_or_id;$old$;
  v_after := $new$  v_je_or_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-OR-' || v_or_number, (p_header->>'date')::DATE,
    'Cash Receipt ' || v_or_number || ' — '
      || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id,
    v_fp_id, 'posted', v_grand_total, v_grand_total,
    'system', 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale OR header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  -- DR: Cash / Bank (net of CWT)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, 1, v_cash_acct, 'Cash received — ' || v_or_number, v_cash_received, 0, 'base', auth.uid(), auth.uid());$old$;
  v_after := $new$  -- DR: Cash / Bank (net of CWT)
  PERFORM fn_add_posting_line_push(
    v_je_or_id, 1, v_cash_acct,
    'Cash received — ' || v_or_number,
    v_cash_received, 0, 'base'
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale OR cash line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_or_id, v_company_id, 2, v_cwt, 'CWT receivable — ' || v_or_number, p_cwt_amount, 0, 'withholding', auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_or_id, 2, v_cwt,
      'CWT receivable — ' || v_or_number,
      p_cwt_amount, 0, 'withholding'
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale OR CWT line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_ar, 'AR cleared — ' || v_or_number, 0, v_grand_total, 'control', auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_or_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_ar, 'AR cleared — ' || v_or_number,
    0, v_grand_total, 'control'
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 9 source drift: Cash Sale OR control line';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

