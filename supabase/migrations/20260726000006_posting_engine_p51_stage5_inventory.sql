-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 5, Batch C (Inventory writers)
--
-- Migrates ONLY General Ledger persistence in the four frozen Inventory writers:
--   • Goods Issue
--   • Physical Count
--   • Stock Adjustment
--   • Stock Transfer
--
-- Inventory costing, quantity, layers, WAC, inventory transactions, source-line
-- updates, account ownership, validations, messages, and document lifecycle are
-- untouched. No Inventory Engine or COA redesign is required.
--
-- Goods Issue and Physical Count historically insert a 0/0 header and later issue
-- an explicit totals UPDATE. The existing finalizer is extended with an explicit,
-- default-off persistence mode which performs that same UPDATE without adding its
-- normal line validation. This preserves the UPDATE audit event and the physical
-- count zero-line carve-out exactly. All one-argument callers retain the certified
-- validation path.
--
-- No new sanctioned helper, classifier member, whitelist entry, mapping key,
-- warehouse qualifier, or routing heuristic is introduced. Guard remains observe.
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_finalize_journal_entry(uuid);

CREATE FUNCTION public.fn_finalize_journal_entry(
  p_je_id          UUID,
  p_total_debit    NUMERIC DEFAULT NULL,
  p_total_credit   NUMERIC DEFAULT NULL,
  p_persist_totals BOOLEAN DEFAULT false
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
  -- P5.1 Inventory: exact replacement for the writers' historical direct totals
  -- UPDATE. It intentionally performs no added validation and lets the same table
  -- triggers produce the same audit OLD/NEW images.
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
  uuid, numeric, numeric, boolean
) FROM PUBLIC;

-- Exact, fail-closed persistence-only transformations.
DO $migration$
DECLARE
  v_signature  REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  -- ── Goods Issue: header ──────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_goods_issue_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  -- Create JE header
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_gi.company_id, v_gi.branch_id,
    fn_next_document_number(v_gi.company_id, v_gi.branch_id, 'JE'),
    v_gi.issue_date, v_fp_id,
    'Goods Issue: ' || v_gi.issue_number || COALESCE(' — ' || v_gi.purpose, ''),
    'INV_GI', p_issue_id, 'posted', 0, 0,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  -- Create JE header through the sanctioned kernel; values unchanged.
  v_je_id := fn_create_posted_journal_entry(
    v_gi.company_id, v_gi.branch_id,
    fn_next_document_number(v_gi.company_id, v_gi.branch_id, 'JE'),
    v_gi.issue_date,
    'Goods Issue: ' || v_gi.issue_number || COALESCE(' — ' || v_gi.purpose, ''),
    'INV_GI', p_issue_id,
    v_fp_id, 'posted', 0, 0, NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Goods Issue header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  -- Goods Issue: paired lines
  v_before := $old$        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                         department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
        VALUES
          (v_je_id, v_gi.company_id, v_line_no,     v_exp_acct, 'Goods issue — ' || v_item.description, v_total, 0,
             v_gi.department_id, v_gi.cost_center_id, v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id, auth.uid(), auth.uid()),
          (v_je_id, v_gi.company_id, v_line_no + 1, v_inv_acct, 'Goods issue — ' || v_item.description, 0,       v_total,
             v_gi.department_id, v_gi.cost_center_id, v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id, auth.uid(), auth.uid());$old$;
  v_after := $new$        PERFORM fn_add_posting_line_push(
          v_je_id, v_line_no, v_exp_acct,
          'Goods issue — ' || v_item.description, v_total, 0,
          NULL, NULL, NULL,
          v_gi.department_id, v_gi.cost_center_id,
          v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id
        );
        PERFORM fn_add_posting_line_push(
          v_je_id, v_line_no + 1, v_inv_acct,
          'Goods issue — ' || v_item.description, 0, v_total,
          NULL, NULL, NULL,
          v_gi.department_id, v_gi.cost_center_id,
          v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id
        );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Goods Issue lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  -- Update JE totals
  UPDATE journal_entries SET total_debit = v_je_total, total_credit = v_je_total WHERE id = v_je_id;$old$;
  v_after := $new$  -- Preserve the historical totals UPDATE and its audit event in-kernel.
  PERFORM fn_finalize_journal_entry(v_je_id, v_je_total, v_je_total, true);$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Goods Issue totals';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Physical Count: header ───────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_physical_count_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_cs.company_id, v_cs.branch_id,
    fn_next_document_number(v_cs.company_id, v_cs.branch_id, 'JE'),
    v_cs.count_date, v_fp_id,
    'Physical Count Variance: ' || v_cs.count_number,
    'INV_COUNT', p_sheet_id, 'posted', 0, 0,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_cs.company_id, v_cs.branch_id,
    fn_next_document_number(v_cs.company_id, v_cs.branch_id, 'JE'),
    v_cs.count_date,
    'Physical Count Variance: ' || v_cs.count_number,
    'INV_COUNT', p_sheet_id,
    v_fp_id, 'posted', 0, 0, NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Physical Count header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  -- Physical Count: paired lines
  v_before := $old$        INSERT INTO journal_entry_lines (
          je_id, company_id, line_number, account_id, description,
          debit_amount, credit_amount, created_by, updated_by
        ) VALUES
          (
            v_je_id, v_cs.company_id, v_line_no, v_inv_acct,
            'Count variance — ' || v_item.description,
            GREATEST(v_impact, 0), GREATEST(-v_impact, 0), auth.uid(), auth.uid()
          ),
          (
            v_je_id, v_cs.company_id, v_line_no + 1, v_var_acct,
            'Count variance — ' || v_item.description,
            GREATEST(-v_impact, 0), GREATEST(v_impact, 0), auth.uid(), auth.uid()
          );$old$;
  v_after := $new$        PERFORM fn_add_posting_line_push(
          v_je_id, v_line_no, v_inv_acct,
          'Count variance — ' || v_item.description,
          GREATEST(v_impact, 0), GREATEST(-v_impact, 0)
        );
        PERFORM fn_add_posting_line_push(
          v_je_id, v_line_no + 1, v_var_acct,
          'Count variance — ' || v_item.description,
          GREATEST(-v_impact, 0), GREATEST(v_impact, 0)
        );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Physical Count lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  UPDATE journal_entries
  SET total_debit = v_je_total,
      total_credit = v_je_total
  WHERE id = v_je_id;$old$;
  v_after := $new$  PERFORM fn_finalize_journal_entry(
    v_je_id, v_je_total, v_je_total, true
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Physical Count totals';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Stock Adjustment: header ─────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_stock_adjustment_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_adj.company_id, v_adj.branch_id,
      fn_next_document_number(v_adj.company_id, v_adj.branch_id, 'JE'),
      v_adj.adjustment_date, v_fp_id,
      'Stock Adjustment: ' || v_adj.adjustment_number || ' (' || v_adj.reason || ')',
      'INV_ADJ', p_adjustment_id, 'posted',
      GREATEST(v_total_impact, 0), GREATEST(-v_total_impact, 0),
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$    v_je_id := fn_create_posted_journal_entry(
      v_adj.company_id, v_adj.branch_id,
      fn_next_document_number(v_adj.company_id, v_adj.branch_id, 'JE'),
      v_adj.adjustment_date,
      'Stock Adjustment: ' || v_adj.adjustment_number || ' (' || v_adj.reason || ')',
      'INV_ADJ', p_adjustment_id,
      v_fp_id, 'posted',
      GREATEST(v_total_impact, 0), GREATEST(-v_total_impact, 0),
      NULL, 'regular', false, false, false
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Stock Adjustment header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  -- Stock Adjustment: paired lines
  v_before := $old$          INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
          VALUES
            (v_je_id, v_adj.company_id, v_line_no,     v_inv_acct, 'Inventory adj', GREATEST(v_impact,0), GREATEST(-v_impact,0), auth.uid(), auth.uid()),
            (v_je_id, v_adj.company_id, v_line_no + 1, v_off_acct, 'Adj offset',    GREATEST(-v_impact,0), GREATEST(v_impact,0), auth.uid(), auth.uid());$old$;
  v_after := $new$          PERFORM fn_add_posting_line_push(
            v_je_id, v_line_no, v_inv_acct, 'Inventory adj',
            GREATEST(v_impact,0), GREATEST(-v_impact,0)
          );
          PERFORM fn_add_posting_line_push(
            v_je_id, v_line_no + 1, v_off_acct, 'Adj offset',
            GREATEST(-v_impact,0), GREATEST(v_impact,0)
          );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Stock Adjustment lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Stock Transfer: conditional header ───────────────────────────────────────
  v_signature :=
    'public.fn_post_stock_transfer_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    INSERT INTO journal_entries (
      company_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_tx.company_id,
      fn_next_document_number(v_tx.company_id, v_from_wh.branch_id, 'JE'),
      v_tx.transfer_date, v_fp_id,
      'Stock Transfer: ' || v_tx.transfer_number,
      'INV_STX', p_transfer_id, 'posted', v_total, v_total,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$    v_je_id := fn_create_posted_journal_entry(
      v_tx.company_id, NULL,
      fn_next_document_number(v_tx.company_id, v_from_wh.branch_id, 'JE'),
      v_tx.transfer_date,
      'Stock Transfer: ' || v_tx.transfer_number,
      'INV_STX', p_transfer_id,
      v_fp_id, 'posted', v_total, v_total,
      NULL, 'regular', false, false, false
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Stock Transfer header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES
      (
        v_je_id, v_tx.company_id, 1, v_to_wh.gl_inventory_account_id,
        'Transfer in', v_total, 0, auth.uid(), auth.uid()
      ),
      (
        v_je_id, v_tx.company_id, 2, v_from_wh.gl_inventory_account_id,
        'Transfer out', 0, v_total, auth.uid(), auth.uid()
      );$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, 1, v_to_wh.gl_inventory_account_id,
      'Transfer in', v_total, 0
    );
    PERFORM fn_add_posting_line_push(
      v_je_id, 2, v_from_wh.gl_inventory_account_id,
      'Transfer out', 0, v_total
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 5 source drift: Stock Transfer lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

