-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 4, Batch B (Manual Journal)
--
-- Isolated migration of fn_post_manual_je:
--   • header INSERT -> fn_create_posted_journal_entry
--   • line INSERTs  -> fn_add_posting_line_push
--
-- Every validator, message, ordering decision, period lookup, MJE numbering loop,
-- entry_class rule, auto_reverse value, line order, amount, dimension, and audit
-- effect remains in its established position.
--
-- SOURCE-VALIDATION ORDER
-- The raw header INSERT was followed by the existing deferred source-integrity
-- constraint trigger. The kernel normally performs the same source assertion
-- eagerly. That would move an invalid custom reference-type rejection ahead of
-- line persistence. A second defaulted capability flag therefore lets this writer
-- retain the deferred trigger as its source validator. It weakens nothing: the
-- same mandatory constraint trigger still runs at commit, while every existing
-- kernel caller continues to assert eagerly by default.
--
-- posting_origin intentionally remains NULL. Populating it here would change the
-- current journal header and violate the byte-for-byte contract; no historical or
-- ambiguous origin is inferred.
--
-- No classifier entry or whitelist exception is added. Guard enforcement remains
-- false.
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric,
  text, text, boolean, boolean
);

CREATE FUNCTION public.fn_create_posted_journal_entry(
  p_company_id         UUID,
  p_branch_id          UUID,
  p_je_number          TEXT,
  p_je_date            DATE,
  p_description        TEXT,
  p_reference_doc_type TEXT,
  p_reference_doc_id   UUID,
  p_fiscal_period_id   UUID    DEFAULT NULL,
  p_status             TEXT    DEFAULT 'posted',
  p_total_debit        NUMERIC DEFAULT 0,
  p_total_credit       NUMERIC DEFAULT 0,
  p_posting_origin     TEXT    DEFAULT NULL,
  p_entry_class        TEXT    DEFAULT 'regular',
  p_auto_reverse       BOOLEAN DEFAULT false,
  p_emit_origin_update BOOLEAN DEFAULT false,
  -- Defaults true, preserving every existing caller. A migrated direct writer
  -- may retain its established deferred constraint-trigger validation order.
  p_assert_source      BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_period_id UUID;
  v_je_id     UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF p_assert_source THEN
    PERFORM fn_assert_posting_source(
      p_reference_doc_type,
      p_reference_doc_id,
      p_company_id
    );
  END IF;

  IF p_fiscal_period_id IS NULL THEN
    v_period_id := fn_require_open_fiscal_period(p_company_id, p_je_date, true);
  ELSE
    v_period_id := p_fiscal_period_id;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, entry_class, auto_reverse,
    created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, p_je_date, v_period_id,
    p_description, UPPER(BTRIM(p_reference_doc_type)), p_reference_doc_id,
    COALESCE(p_status, 'posted'),
    COALESCE(p_total_debit, 0), COALESCE(p_total_credit, 0),
    CASE WHEN p_emit_origin_update THEN NULL ELSE p_posting_origin END,
    COALESCE(p_entry_class, 'regular'), COALESCE(p_auto_reverse, false),
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  IF p_emit_origin_update THEN
    UPDATE journal_entries
    SET posting_origin = p_posting_origin
    WHERE id = v_je_id;
  END IF;

  RETURN v_je_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric,
  text, text, boolean, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric,
  text, text, boolean, boolean, boolean
) TO service_role;

-- Exact, fail-closed replacement of the two persistence blocks only.
DO $migration$
DECLARE
  v_signature  REGPROCEDURE :=
    'public.fn_post_manual_je(uuid,uuid,date,text,text,boolean,jsonb,text)'::REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  SELECT pg_get_functiondef(v_signature) INTO v_definition;

  v_before := $old$  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status, entry_class,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID, v_je_number, p_je_date, v_fp_id,
    COALESCE(p_description, 'Manual Journal Entry'), v_ref_type, NULL, 'posted', v_entry_class,
    v_total_debit, v_total_credit, COALESCE(p_auto_reverse, false), false,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;$old$;

  v_after := $new$  v_je_id := fn_create_posted_journal_entry(
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID,
    v_je_number, p_je_date,
    COALESCE(p_description, 'Manual Journal Entry'),
    v_ref_type, NULL,
    v_fp_id, 'posted', v_total_debit, v_total_credit,
    NULL, v_entry_class, COALESCE(p_auto_reverse, false),
    false, false
  );$new$;

  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 4 source drift: manual journal header block';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := $old$    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, branch_id, department_id, cost_center_id,
      project_id, location_id, functional_entity_id,
      created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no,
      (v_line->>'account_id')::UUID,
      NULLIF(v_line->>'description', ''),
      COALESCE((v_line->>'debit_amount')::NUMERIC, 0),
      COALESCE((v_line->>'credit_amount')::NUMERIC, 0),
      NULLIF(v_line->>'branch_id', '')::UUID,
      NULLIF(v_line->>'department_id', '')::UUID,
      NULLIF(v_line->>'cost_center_id', '')::UUID,
      NULLIF(v_line->>'project_id', '')::UUID,
      NULLIF(v_line->>'location_id', '')::UUID,
      NULLIF(v_line->>'functional_entity_id', '')::UUID,
      auth.uid(), auth.uid()
    );$old$;

  v_after := $new$    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no,
      (v_line->>'account_id')::UUID,
      NULLIF(v_line->>'description', ''),
      COALESCE((v_line->>'debit_amount')::NUMERIC, 0),
      COALESCE((v_line->>'credit_amount')::NUMERIC, 0),
      NULL, NULL,
      NULLIF(v_line->>'branch_id', '')::UUID,
      NULLIF(v_line->>'department_id', '')::UUID,
      NULLIF(v_line->>'cost_center_id', '')::UUID,
      NULLIF(v_line->>'project_id', '')::UUID,
      NULLIF(v_line->>'location_id', '')::UUID,
      NULLIF(v_line->>'functional_entity_id', '')::UUID
    );$new$;

  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 4 source drift: manual journal line block';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

