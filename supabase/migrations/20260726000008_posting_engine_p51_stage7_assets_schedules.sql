-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 7 (Fixed Assets + Schedules)
--
-- Migrates GL persistence for acquisition, depreciation, disposal, impairment,
-- amortization, and revenue recognition. The established post-insert source-link
-- triggers are also routed through the already-sanctioned finalizer, preserving
-- their exact reference UPDATE and audit event without a classifier exception.
--
-- Calculation, schedules, asset lifecycle, dimensions, numbering, validation,
-- messages, and line order are untouched. Guard remains observe-only.
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_finalize_journal_entry(
  uuid, numeric, numeric, boolean
);

CREATE FUNCTION public.fn_finalize_journal_entry(
  p_je_id                   UUID,
  p_total_debit             NUMERIC DEFAULT NULL,
  p_total_credit            NUMERIC DEFAULT NULL,
  p_persist_totals          BOOLEAN DEFAULT false,
  p_link_reference_doc_type TEXT DEFAULT NULL,
  p_link_reference_doc_id   UUID DEFAULT NULL,
  p_link_source             BOOLEAN DEFAULT false
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
  uuid, numeric, numeric, boolean, text, uuid, boolean
) FROM PUBLIC;

-- Preserve the three post-insert linkage paths and the secondary-posting
-- normalizer, but move their exact UPDATE through the sanctioned finalizer.
CREATE OR REPLACE FUNCTION public.fn_link_fixed_asset_journal_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_je_id UUID;
BEGIN
  v_je_id := CASE TG_TABLE_NAME
    WHEN 'fixed_assets'
      THEN NULLIF(to_jsonb(NEW)->>'acquisition_je_id', '')::UUID
    WHEN 'asset_depreciation_entries'
      THEN NULLIF(to_jsonb(NEW)->>'journal_entry_id', '')::UUID
    WHEN 'asset_disposals'
      THEN NULLIF(to_jsonb(NEW)->>'journal_entry_id', '')::UUID
    WHEN 'asset_impairments'
      THEN NULLIF(to_jsonb(NEW)->>'journal_entry_id', '')::UUID
  END;

  IF v_je_id IS NOT NULL THEN
    PERFORM fn_finalize_journal_entry(
      p_je_id => v_je_id,
      p_link_reference_doc_id => NEW.id,
      p_link_source => true
    );
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_link_schedule_journal_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type TEXT;
BEGIN
  v_type := CASE TG_TABLE_NAME
    WHEN 'amortization_entries' THEN 'AMORT'
    WHEN 'revenue_recognition_entries' THEN 'REVREC'
  END;

  IF NEW.je_id IS NOT NULL THEN
    PERFORM fn_finalize_journal_entry(
      p_je_id => NEW.je_id,
      p_link_reference_doc_type => v_type,
      p_link_reference_doc_id => NEW.id,
      p_link_source => true
    );
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_link_purchase_return_journal_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.journal_entry_id IS NOT NULL THEN
    PERFORM fn_finalize_journal_entry(
      p_je_id => NEW.journal_entry_id,
      p_link_reference_doc_type => 'PR',
      p_link_reference_doc_id => NEW.id,
      p_link_source => true
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_complete_secondary_posting(
  p_document_type TEXT,
  p_source_id UUID,
  p_journal_entry_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_source JSONB;
  v_company_id UUID;
  v_je_id UUID := p_journal_entry_id;
BEGIN
  v_source := fn_resolve_posting_source(p_document_type, p_source_id, false);
  v_company_id := NULLIF(v_source->>'company_id', '')::UUID;

  IF v_je_id IS NULL THEN
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE company_id = v_company_id
      AND reference_doc_type = UPPER(BTRIM(p_document_type))
      AND reference_doc_id = p_source_id
      AND status IN ('posted', 'reversed')
      AND je_number NOT LIKE '%-REV-%'
      AND je_number NOT LIKE 'JE-VOID-%'
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    PERFORM fn_finalize_journal_entry(
      p_je_id => v_je_id,
      p_link_reference_doc_type => UPPER(BTRIM(p_document_type)),
      p_link_reference_doc_id => p_source_id,
      p_link_source => true
    );
    PERFORM fn_finalize_journal_entry(v_je_id);
  END IF;

  PERFORM fn_record_posting_event(
    v_company_id, p_document_type, p_source_id, 'POSTED', v_je_id,
    jsonb_build_object('writer_protocol', 'source_lock_wrapper')
  );
  RETURN v_je_id;
END;
$function$;

DO $migration$
DECLARE
  v_signature  REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  -- ── Depreciation ─────────────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_depreciation_entry_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_entry.company_id, v_asset.branch_id,
    fn_next_document_number(v_entry.company_id, v_asset.branch_id, 'JE'),
    v_entry.entry_date, v_fp_id,
    'Depreciation — ' || v_asset.asset_name || ' (Period ' || v_entry.period_number || ')',
    'FA_DEPR', v_entry.asset_id, 'posted',
    v_entry.depreciation_amount, v_entry.depreciation_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_entry.company_id, v_asset.branch_id,
    fn_next_document_number(v_entry.company_id, v_asset.branch_id, 'JE'),
    v_entry.entry_date,
    'Depreciation — ' || v_asset.asset_name || ' (Period ' || v_entry.period_number || ')',
    'FA_DEPR', v_entry.asset_id,
    v_fp_id, 'posted',
    v_entry.depreciation_amount, v_entry.depreciation_amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Depreciation header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                   department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
  VALUES
    (v_je_id, v_entry.company_id, 1, v_cat.gl_depr_expense_account_id,
     'Depr — ' || v_asset.asset_name, v_entry.depreciation_amount, 0,
     v_asset.department_id, v_asset.cost_center_id, v_asset.project_id, v_asset.location_id, v_asset.functional_entity_id, auth.uid(), auth.uid()),
    (v_je_id, v_entry.company_id, 2, v_cat.gl_accum_depr_account_id,
     'Accum Depr — ' || v_asset.asset_name, 0, v_entry.depreciation_amount,
     v_asset.department_id, v_asset.cost_center_id, v_asset.project_id, v_asset.location_id, v_asset.functional_entity_id, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_cat.gl_depr_expense_account_id,
    'Depr — ' || v_asset.asset_name, v_entry.depreciation_amount, 0,
    NULL, NULL, NULL,
    v_asset.department_id, v_asset.cost_center_id,
    v_asset.project_id, v_asset.location_id, v_asset.functional_entity_id
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_cat.gl_accum_depr_account_id,
    'Accum Depr — ' || v_asset.asset_name, 0, v_entry.depreciation_amount,
    NULL, NULL, NULL,
    v_asset.department_id, v_asset.cost_center_id,
    v_asset.project_id, v_asset.location_id, v_asset.functional_entity_id
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Depreciation lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Amortization ─────────────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_amortization_entry_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_sched.company_id, v_sched.branch_id, v_je_num, v_entry.entry_date, v_fp_id,
    COALESCE(v_sched.description, v_sched.schedule_name) || ' — Period ' || v_entry.period_number || '/' || v_sched.total_periods,
    'MANUAL', 'posted', v_entry.amount, v_entry.amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_sched.company_id, v_sched.branch_id,
    v_je_num, v_entry.entry_date,
    COALESCE(v_sched.description, v_sched.schedule_name)
      || ' — Period ' || v_entry.period_number || '/' || v_sched.total_periods,
    'MANUAL', NULL,
    v_fp_id, 'posted', v_entry.amount, v_entry.amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Amortization header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_sched.company_id, 1, v_sched.expense_account_id,
     v_sched.schedule_name || ' amortization — period ' || v_entry.period_number,
     v_entry.amount, 0, auth.uid(), auth.uid()),
    (v_je_id, v_sched.company_id, 2, v_sched.asset_account_id,
     v_sched.schedule_name || ' amortization — period ' || v_entry.period_number,
     0, v_entry.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_sched.expense_account_id,
    v_sched.schedule_name || ' amortization — period ' || v_entry.period_number,
    v_entry.amount, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_sched.asset_account_id,
    v_sched.schedule_name || ' amortization — period ' || v_entry.period_number,
    0, v_entry.amount
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Amortization lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Revenue Recognition ───────────────────────────────────────────────────────
  v_signature :=
    'public.fn_post_revenue_recognition_entry_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_sched.company_id, v_sched.branch_id, v_je_num, v_entry.entry_date, v_fp_id,
    COALESCE(v_sched.description, v_sched.schedule_name) || ' — Period ' || v_entry.period_number || '/' || v_sched.total_periods,
    'MANUAL', 'posted', v_entry.amount, v_entry.amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_sched.company_id, v_sched.branch_id,
    v_je_num, v_entry.entry_date,
    COALESCE(v_sched.description, v_sched.schedule_name)
      || ' — Period ' || v_entry.period_number || '/' || v_sched.total_periods,
    'MANUAL', NULL,
    v_fp_id, 'posted', v_entry.amount, v_entry.amount,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Revenue Recognition header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  -- DR Deferred Revenue, CR Revenue
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_sched.company_id, 1, v_sched.deferred_revenue_account_id,
     v_sched.schedule_name || ' recognition — period ' || v_entry.period_number,
     v_entry.amount, 0, auth.uid(), auth.uid()),
    (v_je_id, v_sched.company_id, 2, v_sched.revenue_account_id,
     v_sched.schedule_name || ' recognition — period ' || v_entry.period_number,
     0, v_entry.amount, auth.uid(), auth.uid());$old$;
  v_after := $new$  -- DR Deferred Revenue, CR Revenue
  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_sched.deferred_revenue_account_id,
    v_sched.schedule_name || ' recognition — period ' || v_entry.period_number,
    v_entry.amount, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_sched.revenue_account_id,
    v_sched.schedule_name || ' recognition — period ' || v_entry.period_number,
    0, v_entry.amount
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Revenue Recognition lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Fixed Asset acquisition ──────────────────────────────────────────────────
  v_signature := 'public.fn_register_fixed_asset(jsonb)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status, total_debit, total_credit,
      created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      fn_next_document_number(v_company_id, v_branch_id, 'JE'),
      v_acq_date, v_fp_id,
      'FA Acquisition: ' || (p_data->>'asset_name'),
      'FA', 'posted', v_cost, v_cost,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$    v_je_id := fn_create_posted_journal_entry(
      v_company_id, v_branch_id,
      fn_next_document_number(v_company_id, v_branch_id, 'JE'),
      v_acq_date,
      'FA Acquisition: ' || (p_data->>'asset_name'),
      'FA', NULL,
      v_fp_id, 'posted', v_cost, v_cost,
      NULL, 'regular', false, false, false
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Asset acquisition header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES
      (v_je_id, v_company_id, 1, v_cat.gl_asset_account_id, 'Acquisition — ' || (p_data->>'asset_name'), v_cost, 0,
         v_department_id, v_cost_center_id, v_project_id, v_location_id, v_functional_entity_id, auth.uid(), auth.uid()),
      (v_je_id, v_company_id, 2, v_credit_acct, 'Acquisition — ' || (p_data->>'asset_name'), 0, v_cost,
         v_department_id, v_cost_center_id, v_project_id, v_location_id, v_functional_entity_id, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, 1, v_cat.gl_asset_account_id,
      'Acquisition — ' || (p_data->>'asset_name'), v_cost, 0,
      NULL, NULL, NULL,
      v_department_id, v_cost_center_id,
      v_project_id, v_location_id, v_functional_entity_id
    );
    PERFORM fn_add_posting_line_push(
      v_je_id, 2, v_credit_acct,
      'Acquisition — ' || (p_data->>'asset_name'), 0, v_cost,
      NULL, NULL, NULL,
      v_department_id, v_cost_center_id,
      v_project_id, v_location_id, v_functional_entity_id
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Asset acquisition lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Fixed Asset disposal ─────────────────────────────────────────────────────
  v_signature := 'public.fn_dispose_fixed_asset(jsonb)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  -- Build disposal JE
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, v_asset.branch_id, 'JE'),
    v_disposal_date, v_fp_id,
    'FA Disposal: ' || v_asset.asset_name || ' (' || (p_data->>'disposal_type') || ')',
    'FA_DISP', 'posted',
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  -- Build disposal JE
  v_je_id := fn_create_posted_journal_entry(
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, v_asset.branch_id, 'JE'),
    v_disposal_date,
    'FA Disposal: ' || v_asset.asset_name || ' (' || (p_data->>'disposal_type') || ')',
    'FA_DISP', NULL,
    v_fp_id, 'posted',
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Asset disposal header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_accum_depr_account_id,
      'Accum Depr — ' || v_asset.asset_name, v_accum_depr, 0, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line, v_cat.gl_accum_depr_account_id,
      'Accum Depr — ' || v_asset.asset_name, v_accum_depr, 0,
      NULL, NULL, NULL, v_d, v_cc, v_prj, v_loc, v_fe
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: disposal accumulated depreciation line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_proceeds_acct,
      'Proceeds — ' || v_asset.asset_name, v_proceeds, 0, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line, v_proceeds_acct,
      'Proceeds — ' || v_asset.asset_name, v_proceeds, 0,
      NULL, NULL, NULL, v_d, v_cc, v_prj, v_loc, v_fe
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: disposal proceeds line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_loss_on_disposal_account_id,
      'Loss on Disposal — ' || v_asset.asset_name, ABS(v_gain_loss), 0, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line, v_cat.gl_loss_on_disposal_account_id,
      'Loss on Disposal — ' || v_asset.asset_name, ABS(v_gain_loss), 0,
      NULL, NULL, NULL, v_d, v_cc, v_prj, v_loc, v_fe
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: disposal loss line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                   department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
  VALUES (v_je_id, v_company_id, v_line, v_cat.gl_asset_account_id,
    'Asset Cost — ' || v_asset.asset_name, 0, v_asset.acquisition_cost, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, v_line, v_cat.gl_asset_account_id,
    'Asset Cost — ' || v_asset.asset_name, 0, v_asset.acquisition_cost,
    NULL, NULL, NULL, v_d, v_cc, v_prj, v_loc, v_fe
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: disposal asset-cost line';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_gain_on_disposal_account_id,
      'Gain on Disposal — ' || v_asset.asset_name, 0, v_gain_loss, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());$old$;
  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line, v_cat.gl_gain_on_disposal_account_id,
      'Gain on Disposal — ' || v_asset.asset_name, 0, v_gain_loss,
      NULL, NULL, NULL, v_d, v_cc, v_prj, v_loc, v_fe
    );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: disposal gain line';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- ── Fixed Asset impairment ───────────────────────────────────────────────────
  v_signature := 'public.fn_record_impairment(jsonb)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, v_asset.branch_id, 'JE'),
    v_imp_date, v_fp_id,
    'Impairment Loss — ' || v_asset.asset_name,
    'FA_IMP', 'posted', v_loss, v_loss,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;
  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, v_asset.branch_id, 'JE'),
    v_imp_date,
    'Impairment Loss — ' || v_asset.asset_name,
    'FA_IMP', NULL,
    v_fp_id, 'posted', v_loss, v_loss,
    NULL, 'regular', false, false, false
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Asset impairment header';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);
  v_before := $old$  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_company_id, 1, v_imp_loss_acct,  'Impairment Loss — ' || v_asset.asset_name, v_loss, 0, auth.uid(), auth.uid()),
    (v_je_id, v_company_id, 2, v_accum_imp_acct, 'Accum Impairment — ' || v_asset.asset_name, 0, v_loss, auth.uid(), auth.uid());$old$;
  v_after := $new$  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_imp_loss_acct,
    'Impairment Loss — ' || v_asset.asset_name, v_loss, 0
  );
  PERFORM fn_add_posting_line_push(
    v_je_id, 2, v_accum_imp_acct,
    'Accum Impairment — ' || v_asset.asset_name, 0, v_loss
  );$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 7 source drift: Asset impairment lines';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

