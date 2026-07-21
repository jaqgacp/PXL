-- ══════════════════════════════════════════════════════════════════════════════
-- PXL-AUD-066 — Historical CAS evidence date semantics
--
-- Defect: `fn_snapshot_cas_audit_package` selected books/exports by their
-- DOCUMENT PERIOD (report_snapshots.period_start/period_end) but selected
-- number issuances by `allocated_at` and void events by `occurred_at` — i.e. by
-- the wall-clock time the evidence row was written. A package generated after
-- the fact for a historical accounting period therefore omitted every number
-- and void row whose evidence was created later, even though the underlying
-- documents belong to that period. Test 027 assertions 29-30 fail.
--
-- Fix (minimal, no schema change, no backfill — as the finding prescribes):
--   1. Add a governed source-document-date resolver, `fn_cas_issuance_document_date`,
--      that returns the accounting/document date of the source document an
--      issuance is bound to. It reads the immutable source row as JSONB and picks
--      the canonical transaction-date field, so it needs no per-table column
--      wiring and cannot error on tables that lack a given column. System
--      timestamps (created_at/updated_at) are intentionally NOT candidates, so a
--      later-created row can never be back-dated by this resolver.
--   2. Select number issuances by DOCUMENT PERIOD:
--        * bound rows  -> resolved source-document date within the range;
--        * unbound reservations (no source) -> keep allocation-time evidence
--          (their allocation IS the only date they have), so accountable gaps
--          still surface in the period they were reserved.
--   3. Select void events by `document_date` (the document's own period), with an
--      `occurred_at` fallback for rows that carry no document_date.
--
-- Books, exports, DAT artifacts, GL, and audit-log selection are already
-- document-period based and are left unchanged. Posting, audit, and immutability
-- behaviour is untouched: this migration only reads existing immutable evidence.
--
-- Idempotent (CREATE OR REPLACE), forward-only.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Governed source-document-date resolver ─────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cas_issuance_document_date(
  p_source_table TEXT,
  p_source_id    UUID
)
RETURNS DATE
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row  JSONB;
  v_col  TEXT;
  -- Canonical document/transaction-date fields, most specific first. These are
  -- the posting-relevant dates of the numbered source documents; audit/system
  -- timestamps are deliberately excluded so evidence cannot be back-dated.
  v_candidates TEXT[] := ARRAY[
    'date', 'bill_date', 'voucher_date', 'receipt_date', 'cm_date', 'dm_date',
    'credit_date', 'transfer_date', 'adjustment_date', 'transaction_date',
    'je_date', 'document_date', 'quotation_date', 'so_date', 'order_date',
    'dr_date', 'delivery_date', 'rr_date', 'return_date', 'sdm_date',
    'replenishment_date', 'sheet_date', 'count_date', 'acquisition_date'
  ];
BEGIN
  IF p_source_table IS NULL OR p_source_id IS NULL THEN
    RETURN NULL;
  END IF;
  -- Source table names come only from our own trigger-written evidence rows;
  -- still, validate against the catalog and quote as an identifier.
  IF to_regclass('public.' || p_source_table) IS NULL THEN
    RETURN NULL;
  END IF;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.id = $1', p_source_table)
  INTO v_row
  USING p_source_id;

  IF v_row IS NULL THEN
    RETURN NULL;
  END IF;

  FOREACH v_col IN ARRAY v_candidates LOOP
    IF (v_row ? v_col) AND NULLIF(v_row ->> v_col, '') IS NOT NULL THEN
      BEGIN
        RETURN (v_row ->> v_col)::DATE;
      EXCEPTION WHEN others THEN
        -- Field is present but not a valid date; keep looking.
        NULL;
      END;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

-- Internal helper: invoked only from the SECURITY DEFINER audit-package function
-- (which runs as the definer). Not granted to clients.
REVOKE ALL ON FUNCTION fn_cas_issuance_document_date(TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_cas_issuance_document_date(TEXT, UUID) TO service_role;

COMMENT ON FUNCTION fn_cas_issuance_document_date(TEXT, UUID) IS
  'Resolves the document/accounting date of the source document a CAS number issuance is bound to, so historical audit packages can select issuance evidence by document period rather than allocation time. Excludes system timestamps to prevent back-dating.';

-- ── 2. Document-period CAS audit package ──────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_snapshot_cas_audit_package(
  p_company_id UUID,
  p_date_from DATE,
  p_date_to DATE,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source_id UUID;
  v_version INTEGER;
  v_payload JSONB;
  v_checks JSONB;
  v_hash TEXT;
  v_snapshot_id UUID := gen_random_uuid();
  v_row_count INTEGER;
  v_debits NUMERIC(15,2);
  v_credits NUMERIC(15,2);
  v_books JSONB;
  v_books_count INTEGER;
  v_books_all_reconciled BOOLEAN;
  v_exports JSONB;
  v_export_count INTEGER;
  v_missing_export_hashes INTEGER;
  v_missing_dat_artifacts INTEGER;
  v_dat_artifacts JSONB;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid CAS audit package date range';
  END IF;

  IF NULLIF(btrim(COALESCE(p_file_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'CAS audit package file name is required';
  END IF;

  SELECT COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2),
         COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2)
  INTO v_debits, v_credits
  FROM vw_general_ledger
  WHERE company_id = p_company_id
    AND je_date BETWEEN p_date_from AND p_date_to;

  WITH book_snapshots AS (
    SELECT rs.id, rs.report_type, rs.period_start, rs.period_end,
           rs.snapshot_version, rs.source_hash, rs.source_row_count,
           rs.source_payload -> 'reconciliation' AS reconciliation,
           NOT EXISTS (
             SELECT 1
             FROM jsonb_array_elements(COALESCE(rs.source_payload -> 'reconciliation', '[]'::jsonb)) AS r(value)
             WHERE COALESCE((r.value ->> 'is_reconciled')::BOOLEAN, false) = false
           )
           AND jsonb_array_length(COALESCE(rs.source_payload -> 'reconciliation', '[]'::jsonb)) > 0
             AS is_reconciled
    FROM report_snapshots rs
    WHERE rs.company_id = p_company_id
      AND rs.snapshot_status = 'exported'
      AND rs.report_type LIKE 'BOOKS_%'
      AND rs.period_start >= p_date_from
      AND rs.period_end <= p_date_to
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(book_snapshots) ORDER BY report_type, period_start, snapshot_version), '[]'::jsonb),
         COUNT(*)::INTEGER,
         COALESCE(bool_and(is_reconciled), false)
  INTO v_books, v_books_count, v_books_all_reconciled
  FROM book_snapshots;

  WITH export_evidence AS (
    SELECT e.*, rs.period_start AS evidence_period_start,
           rs.period_end AS evidence_period_end,
           rs.report_type AS evidence_report_type
    FROM cas_export_log e
    LEFT JOIN report_snapshots rs ON rs.id = e.snapshot_id
    WHERE e.company_id = p_company_id
      AND e.export_type IN ('dat_file', 'csv_export')
      AND (
        (rs.id IS NOT NULL
         AND rs.period_start >= p_date_from
         AND rs.period_end <= p_date_to)
        OR
        (rs.id IS NULL AND e.generated_at::date BETWEEN p_date_from AND p_date_to)
      )
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.generated_at, e.id), '[]'::jsonb),
         COUNT(*)::INTEGER,
         (COUNT(*) FILTER (
           WHERE e.export_type IN ('dat_file', 'csv_export')
             AND (e.file_sha256 IS NULL OR e.file_size_bytes IS NULL)
         ))::INTEGER,
         (COUNT(*) FILTER (
           WHERE e.export_type = 'dat_file'
             AND (e.artifact_id IS NULL OR e.file_hash IS NULL OR e.layout_version IS NULL)
         ))::INTEGER
  INTO v_exports, v_export_count, v_missing_export_hashes, v_missing_dat_artifacts
  FROM export_evidence e;

  WITH dat_artifact_evidence AS (
    SELECT DISTINCT a.*
    FROM cas_export_artifacts a
    JOIN cas_export_log e ON e.artifact_id = a.id
    LEFT JOIN report_snapshots rs ON rs.id = e.snapshot_id
    WHERE e.company_id = p_company_id
      AND e.export_type = 'dat_file'
      AND (
        (rs.id IS NOT NULL
         AND rs.period_start >= p_date_from
         AND rs.period_end <= p_date_to)
        OR
        (rs.id IS NULL AND e.generated_at::date BETWEEN p_date_from AND p_date_to)
      )
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.generated_at, a.file_name), '[]'::jsonb)
  INTO v_dat_artifacts
  FROM dat_artifact_evidence a;

  v_checks := jsonb_build_array(
    jsonb_build_object(
      'check', 'gl_balance',
      'debits', v_debits,
      'credits', v_credits,
      'is_reconciled', ABS(v_debits - v_credits) <= 0.01
    ),
    jsonb_build_object(
      'check', 'books_reconciliation',
      'snapshot_count', v_books_count,
      'is_reconciled', v_books_count > 0 AND v_books_all_reconciled
    ),
    jsonb_build_object(
      'check', 'export_hash_evidence',
      'export_count', v_export_count,
      'missing_hashes', COALESCE(v_missing_export_hashes, 0),
      'missing_dat_artifacts', COALESCE(v_missing_dat_artifacts, 0),
      'is_reconciled', v_export_count > 0
        AND COALESCE(v_missing_export_hashes, 0) = 0
        AND COALESCE(v_missing_dat_artifacts, 0) = 0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_checks) AS c(value)
    WHERE COALESCE((c.value ->> 'is_reconciled')::BOOLEAN, false) = false
  ) THEN
    RAISE EXCEPTION 'CAS audit package % to % does not reconcile: %',
      p_date_from, p_date_to,
      (SELECT string_agg(c.value ->> 'check', ', ' ORDER BY c.ord)
       FROM jsonb_array_elements(v_checks) WITH ORDINALITY AS c(value, ord)
       WHERE COALESCE((c.value ->> 'is_reconciled')::BOOLEAN, false) = false);
  END IF;

  SELECT jsonb_build_object(
    'checks', v_checks,
    'gl_control', jsonb_build_object('total_debit', v_debits, 'total_credit', v_credits),
    'books_reconciliation', v_books,
    -- AUD-066: select number issuances by DOCUMENT PERIOD. Bound rows use the
    -- resolved source-document date; unbound reservations keep allocation-time
    -- evidence so accountable gaps still surface in the period they were reserved.
    'number_issuances', COALESCE((
      SELECT jsonb_agg(to_jsonb(i) ORDER BY i.document_code, i.document_number, i.allocated_at)
      FROM cas_document_number_issuances i
      WHERE i.company_id = p_company_id
        AND (
          (i.source_table IS NOT NULL
             AND fn_cas_issuance_document_date(i.source_table, i.source_id)
                 BETWEEN p_date_from AND p_date_to)
          OR
          (i.source_table IS NULL
             AND i.allocated_at::date BETWEEN p_date_from AND p_date_to)
        )
    ), '[]'::jsonb),
    -- AUD-066: select void events by the document's own period, falling back to
    -- the occurrence date only when no document_date was captured.
    'void_events', COALESCE((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY v.document_code, v.document_number, v.occurred_at)
      FROM cas_document_void_events v
      WHERE v.company_id = p_company_id
        AND COALESCE(v.document_date, v.occurred_at::date) BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'exports', v_exports,
    'dat_artifacts', v_dat_artifacts,
    'audit_events', COALESCE((
      SELECT jsonb_agg(to_jsonb(a) ORDER BY changed_at, id)
      FROM sys_audit_logs a
      WHERE a.company_id = p_company_id
        AND a.changed_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb)
  )
  INTO v_payload;

  v_row_count := jsonb_array_length(v_payload -> 'number_issuances')
               + jsonb_array_length(v_payload -> 'void_events')
               + jsonb_array_length(v_payload -> 'exports')
               + jsonb_array_length(v_payload -> 'dat_artifacts')
               + jsonb_array_length(v_payload -> 'audit_events')
               + jsonb_array_length(v_payload -> 'books_reconciliation');

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':CAS_AUDIT_PACKAGE:' || p_date_from || ':' || p_date_to
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_version
  FROM report_snapshots
  WHERE source_table = 'cas_audit_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count, generated_by
  ) VALUES (
    v_snapshot_id, p_company_id, 'CAS_AUDIT_PACKAGE', 'cas_audit_periods', v_source_id,
    'exported', v_version, p_date_from, p_date_to,
    jsonb_build_object('file_name', p_file_name, 'date_from', p_date_from, 'date_to', p_date_to),
    v_payload, v_hash, v_row_count, auth.uid()
  );

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year,
    file_name, row_count, generated_by, snapshot_id, remarks,
    file_sha256, file_size_bytes
  ) VALUES (
    p_company_id, 'audit_package', 'CAS Audit Support Package',
    EXTRACT(YEAR FROM p_date_from)::INTEGER,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id,
    p_date_from::text || '..' || p_date_to::text,
    v_hash, octet_length(convert_to(v_payload::text, 'UTF8'))
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_version,
    'source_hash', v_hash,
    'row_count', v_row_count,
    'checks', v_checks
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_cas_audit_package(UUID, DATE, DATE, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_snapshot_cas_audit_package(UUID, DATE, DATE, TEXT) IS
  'Creates a server-attested CAS audit package snapshot with numbering, void, export, artifact, GL, audit-log, and books-reconciliation evidence, selected consistently by document period (PXL-AUD-066).';
