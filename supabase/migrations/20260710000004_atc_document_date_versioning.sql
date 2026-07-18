-- Historical compatibility migration for held-out draft 20260710000004.
--
-- The original draft implemented ATC document-date validation, ATC effective
-- versioning, and WHT export summary changes. It was held out, then superseded
-- by the trusted migrations:
--
--   20260713000002_atc_document_date_versioning.sql
--   20260713000006_qap_multi_atc_reconciliation.sql
--
-- Hosted migration history can therefore contain the July 13 replacements
-- before this older July 10 version is reconciled with --include-all. Replaying
-- the original draft after the replacement is unsafe: it would attempt to
-- replace public.fn_validate_payment_voucher_line_ewt(uuid,numeric,numeric,
-- uuid,numeric,text,date) without the three trailing defaults that the hosted
-- replacement already has. PostgreSQL correctly rejects that with SQLSTATE
-- 42P13 ("cannot remove parameter defaults from existing function"). Even if
-- that error were bypassed, the draft would overwrite newer trusted function
-- bodies.
--
-- Keep this migration in history, but leave schema unchanged. In a clean replay,
-- the trusted replacements later in the migration sequence install the intended
-- behavior. In a hosted reconciliation replay, this migration validates that the
-- replacement shape is already present and refuses to run against an unexpected
-- partial state.

DO $$
DECLARE
  v_has_atc_replacement BOOLEAN;
  v_has_qap_replacement BOOLEAN;
  v_validator_identity TEXT;
  v_validator_arguments TEXT;
  v_validator_default_count INTEGER;
  v_snapshot_export_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM supabase_migrations.schema_migrations
    WHERE version = '20260713000002'
  )
  INTO v_has_atc_replacement;

  SELECT EXISTS (
    SELECT 1
    FROM supabase_migrations.schema_migrations
    WHERE version = '20260713000006'
  )
  INTO v_has_qap_replacement;

  SELECT
    pg_get_function_identity_arguments(p.oid),
    pg_get_function_arguments(p.oid),
    p.pronargdefaults
  INTO
    v_validator_identity,
    v_validator_arguments,
    v_validator_default_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_validate_payment_voucher_line_ewt'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_company_id uuid, p_payment_amount numeric, p_ewt_amount numeric, p_atc_code_id uuid, p_ewt_tax_base numeric, p_ewt_variance_reason text, p_document_date date';

  SELECT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_snapshot_wht_export'
      AND pg_get_function_identity_arguments(p.oid) =
        'p_company_id uuid, p_report_type text, p_year integer, p_quarter integer'
  )
  INTO v_snapshot_export_exists;

  IF v_has_atc_replacement THEN
    IF v_validator_identity IS NULL THEN
      RAISE EXCEPTION
        '20260713000002 is recorded, but fn_validate_payment_voucher_line_ewt(uuid,numeric,numeric,uuid,numeric,text,date) is missing.';
    END IF;

    IF v_validator_default_count IS DISTINCT FROM 3 THEN
      RAISE EXCEPTION
        '20260713000002 is recorded, but fn_validate_payment_voucher_line_ewt has % defaults instead of 3. Arguments: %',
        COALESCE(v_validator_default_count, -1),
        v_validator_arguments;
    END IF;
  END IF;

  IF v_has_qap_replacement AND NOT v_snapshot_export_exists THEN
    RAISE EXCEPTION
      '20260713000006 is recorded, but fn_snapshot_wht_export(uuid,text,integer,integer) is missing.';
  END IF;

  IF v_has_atc_replacement OR v_has_qap_replacement THEN
    RAISE NOTICE
      '20260710000004 reconciled as historical compatibility migration; trusted replacements are already present.';
  ELSE
    RAISE NOTICE
      '20260710000004 recorded as historical compatibility migration; trusted replacements will run later in a clean replay.';
  END IF;
END;
$$;
