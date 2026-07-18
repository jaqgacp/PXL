-- Historical compatibility migration for held-out draft 20260710000005.
--
-- The original draft attempted an end-to-end CAS numbering, void, DAT, and
-- audit-package implementation. It was held out and later replaced by the
-- trusted CAS slices:
--
--   20260712000004_cas_numbering_void_evidence.sql
--   20260713000007_cas_export_file_hashes.sql
--   20260713000008_cas_dat_layout.sql
--   20260713000009_books_reconciliation_audit_package.sql
--
-- Hosted history can have those replacements before this older July 10 version
-- is reconciled with --include-all. Replaying the draft literally after the
-- replacements is unsafe because it tries to recreate existing CAS evidence
-- tables and would overwrite newer trusted function bodies. Keep this version
-- as an applied history record, but leave schema unchanged.

DO $$
DECLARE
  v_has_numbering_replacement BOOLEAN;
  v_has_export_hash_replacement BOOLEAN;
  v_has_dat_replacement BOOLEAN;
  v_has_books_replacement BOOLEAN;
  v_issuance_table REGCLASS;
  v_void_table REGCLASS;
  v_artifact_table REGCLASS;
  v_has_allocated_columns BOOLEAN;
  v_has_file_hash_columns BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM supabase_migrations.schema_migrations
    WHERE version = '20260712000004'
  )
  INTO v_has_numbering_replacement;

  SELECT EXISTS (
    SELECT 1
    FROM supabase_migrations.schema_migrations
    WHERE version = '20260713000007'
  )
  INTO v_has_export_hash_replacement;

  SELECT EXISTS (
    SELECT 1
    FROM supabase_migrations.schema_migrations
    WHERE version = '20260713000008'
  )
  INTO v_has_dat_replacement;

  SELECT EXISTS (
    SELECT 1
    FROM supabase_migrations.schema_migrations
    WHERE version = '20260713000009'
  )
  INTO v_has_books_replacement;

  SELECT to_regclass('public.cas_document_number_issuances')
  INTO v_issuance_table;

  SELECT to_regclass('public.cas_document_void_events')
  INTO v_void_table;

  SELECT to_regclass('public.cas_export_artifacts')
  INTO v_artifact_table;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cas_document_number_issuances'
      AND column_name IN ('allocated_by', 'allocated_at')
    GROUP BY table_schema, table_name
    HAVING COUNT(*) = 2
  )
  INTO v_has_allocated_columns;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cas_export_log'
      AND column_name IN ('file_sha256', 'file_size_bytes')
    GROUP BY table_schema, table_name
    HAVING COUNT(*) = 2
  )
  INTO v_has_file_hash_columns;

  IF v_has_numbering_replacement THEN
    IF v_issuance_table IS NULL THEN
      RAISE EXCEPTION
        '20260712000004 is recorded, but public.cas_document_number_issuances is missing.';
    END IF;

    IF v_void_table IS NULL THEN
      RAISE EXCEPTION
        '20260712000004 is recorded, but public.cas_document_void_events is missing.';
    END IF;

    IF NOT COALESCE(v_has_allocated_columns, false) THEN
      RAISE EXCEPTION
        '20260712000004 is recorded, but cas_document_number_issuances does not have allocated_by/allocated_at replacement columns.';
    END IF;
  END IF;

  IF v_has_export_hash_replacement AND NOT COALESCE(v_has_file_hash_columns, false) THEN
    RAISE EXCEPTION
      '20260713000007 is recorded, but cas_export_log file hash columns are missing.';
  END IF;

  IF v_has_dat_replacement AND v_artifact_table IS NULL THEN
    RAISE EXCEPTION
      '20260713000008 is recorded, but public.cas_export_artifacts is missing.';
  END IF;

  IF v_has_numbering_replacement
     OR v_has_export_hash_replacement
     OR v_has_dat_replacement
     OR v_has_books_replacement THEN
    RAISE NOTICE
      '20260710000005 reconciled as historical compatibility migration; trusted CAS replacements are already present.';
  ELSE
    RAISE NOTICE
      '20260710000005 recorded as historical compatibility migration; trusted CAS replacements will run later in a clean replay.';
  END IF;
END;
$$;
