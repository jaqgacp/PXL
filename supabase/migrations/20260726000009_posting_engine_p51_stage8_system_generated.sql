-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 8 (Recurring + Fiscal Close)
--
-- Persistence-only migration of the two system-generated writers. Recurring
-- auto-reversal retains its post-reversal is_auto_reversal UPDATE and audit event
-- through an explicit default-off finalizer mode. Validator order, messages,
-- numbering loops, entry_class, line order, period/year lifecycle, and reversal
-- orchestration are unchanged.
--
-- No classifier growth. Guard remains observe-only.
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_finalize_journal_entry(
  uuid, numeric, numeric, boolean, text, uuid, boolean
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
  p_mark_auto_reversal            BOOLEAN DEFAULT false
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
  uuid, numeric, numeric, boolean, text, uuid, boolean, uuid, boolean
) FROM PUBLIC;

DO $migration$
DECLARE
  v_signature  REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  -- ── Recurring Journal ────────────────────────────────────────────────────────
  v_signature :=
    'public.fn_execute_recurring_template_source_locked_impl(uuid,date)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    v_tpl.company_id, v_tpl.branch_id, v_je_number, p_je_date, v_fp_id,
    COALESCE(v_tpl.description, v_tpl.template_name), 'RECURRING', v_tpl.id, 'posted',
    v_total_debit, v_total_credit, v_tpl.auto_reverse, false,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_tpl.company_id, v_tpl.branch_id,
    v_je_number, p_je_date,
    COALESCE(v_tpl.description, v_tpl.template_name),
    'RECURRING', v_tpl.id,
    v_fp_id, 'posted', v_total_debit, v_total_credit,
    NULL, 'regular', v_tpl.auto_reverse, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 8 source drift: Recurring header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, v_tpl.company_id, v_line.line_number, v_line.account_id,
      v_line.description, v_line.debit_amount, v_line.credit_amount, auth.uid(), auth.uid()
    );$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line.line_number, v_line.account_id,
      v_line.description, v_line.debit_amount, v_line.credit_amount
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 8 source drift: Recurring lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    PERFORM fn_reverse_je(v_je_id, (date_trunc('month', p_je_date) + INTERVAL '1 month')::DATE);
    UPDATE journal_entries SET is_auto_reversal = true
    WHERE reference_doc_id = v_je_id AND reference_doc_type = 'REV';$old$;
  v_after := $new$    PERFORM fn_reverse_je(
      v_je_id, (date_trunc('month', p_je_date) + INTERVAL '1 month')::DATE
    );
    PERFORM fn_finalize_journal_entry(
      p_je_id => v_je_id,
      p_auto_reversal_original_je_id => v_je_id,
      p_mark_auto_reversal => true
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 8 source drift: Recurring auto-reversal marker';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Fiscal Close ─────────────────────────────────────────────────────────────
  v_signature := 'public.fn_close_fiscal_year(uuid,uuid,date)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status, entry_class,
    total_debit, total_credit, auto_reverse, is_auto_reversal, created_by, updated_by
  ) VALUES (
    p_company_id, NULL, v_je_number, v_close_date, v_fp_id,
    'Year-end closing of ' || v_year.year_name, 'CLOSE', NULL, 'posted', 'closing',
    v_total_debit, v_total_credit, false, false, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    p_company_id, NULL,
    v_je_number, v_close_date,
    'Year-end closing of ' || v_year.year_name,
    'CLOSE', NULL,
    v_fp_id, 'posted', v_total_debit, v_total_credit,
    NULL, 'closing', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 8 source drift: Fiscal Close header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no, r.account_id, 'Year-end close',
      CASE WHEN r.net_dr < 0 THEN -r.net_dr ELSE 0 END,
      CASE WHEN r.net_dr > 0 THEN  r.net_dr ELSE 0 END,
      auth.uid(), auth.uid()
    );$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, r.account_id, 'Year-end close',
      CASE WHEN r.net_dr < 0 THEN -r.net_dr ELSE 0 END,
      CASE WHEN r.net_dr > 0 THEN  r.net_dr ELSE 0 END
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 8 source drift: Fiscal Close P&L lines';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no, v_re_id,
      CASE WHEN v_net_income >= 0 THEN 'Net income to retained earnings' ELSE 'Net loss to retained earnings' END,
      v_re_debit, v_re_credit, auth.uid(), auth.uid()
    );$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_re_id,
      CASE WHEN v_net_income >= 0
        THEN 'Net income to retained earnings'
        ELSE 'Net loss to retained earnings'
      END,
      v_re_debit, v_re_credit
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 8 source drift: Fiscal Close retained-earnings line';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

