-- Immutable report snapshots, fifth slice: CAS DAT file generation (PXL-DA-015).
--
-- The CAS DAT page previously assembled export files in the browser from live
-- views and self-reported cas_export_log rows through a direct client insert
-- (client-computed row counts, no payload hash, no reconciliation gate), so the
-- CAS export log was not trustworthy audit evidence. This migration:
--   1. Links cas_export_log rows to report_snapshots and closes the direct
--      client insert path — only fn_snapshot_cas_export writes the log.
--   2. Adds fn_snapshot_cas_export: builds each DAT payload server-side from
--      the same governed views the page displayed, gates on the relevant
--      reconciliation (VAT for SLSP/RELIEF, EWT payable for the alphalist,
--      debit=credit balance for the GL extract), creates the versioned
--      exported snapshot with a SHA-256 source hash, writes the log row, and
--      returns the frozen rows so the downloaded file is provably the hashed
--      payload.

-- ── 1. cas_export_log becomes RPC-only evidence ────────────────────────────────

ALTER TABLE cas_export_log
  ADD COLUMN IF NOT EXISTS snapshot_id UUID REFERENCES report_snapshots(id);

DROP POLICY IF EXISTS "cas_el_insert" ON cas_export_log;
CREATE POLICY "cas_el_no_direct_insert" ON cas_export_log
  FOR INSERT TO authenticated WITH CHECK (false);

COMMENT ON TABLE cas_export_log IS
  'CAS export evidence log. Written only by fn_snapshot_cas_export (SECURITY DEFINER); direct client inserts are blocked so row counts and periods are server-attested.';

-- ── 2. Server-side CAS DAT snapshot + payload ──────────────────────────────────

CREATE OR REPLACE FUNCTION fn_snapshot_cas_export(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_month INTEGER,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key TEXT := lower(p_report_type);
  v_report_type TEXT;
  v_report_name TEXT;
  v_start DATE;
  v_end DATE;
  v_source_id UUID;
  v_snapshot_id UUID;
  v_snapshot_version INTEGER;
  v_report_payload JSONB;
  v_rows JSONB;
  v_row_count INTEGER := 0;
  v_source_payload JSONB;
  v_source_hash TEXT;
  v_recon JSONB := '[]'::jsonb;
  v_recon_failures TEXT;
  v_debits NUMERIC(15,2);
  v_credits NUMERIC(15,2);
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF v_key NOT IN ('slsp', 'relief', 'general_ledger', 'alphalist_payees') THEN
    RAISE EXCEPTION 'Unsupported CAS export report type: %', p_report_type;
  END IF;

  IF p_month NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Invalid CAS export month: %', p_month;
  END IF;

  IF COALESCE(btrim(p_file_name), '') = '' THEN
    RAISE EXCEPTION 'CAS export file name is required';
  END IF;

  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  v_report_type := CASE v_key
    WHEN 'slsp' THEN 'CAS_SLSP'
    WHEN 'relief' THEN 'CAS_RELIEF'
    WHEN 'general_ledger' THEN 'CAS_GL'
    ELSE 'CAS_QAP'
  END;
  v_report_name := CASE v_key
    WHEN 'slsp' THEN 'SLSP (Sales & Purchases)'
    WHEN 'relief' THEN 'RELIEF Listing'
    WHEN 'general_ledger' THEN 'General Ledger'
    ELSE 'Alphalist of Payees (QAP)'
  END;

  -- Reconciliation gates: the export must match the books it claims to extract.
  IF v_key IN ('slsp', 'relief') THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb),
           string_agg(r.tax_kind || ' variance ' || r.variance::text, '; ' ORDER BY r.tax_kind)
             FILTER (WHERE NOT r.is_reconciled)
    INTO v_recon, v_recon_failures
    FROM fn_vat_gl_reconciliation(p_company_id, v_start, v_end) r;
  ELSIF v_key = 'alphalist_payees' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb),
           string_agg(r.tax_kind || ' variance ' || r.variance::text, '; ' ORDER BY r.tax_kind)
             FILTER (WHERE r.tax_kind = 'ewt_payable' AND NOT r.is_reconciled)
    INTO v_recon, v_recon_failures
    FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end) r;
  ELSE
    SELECT COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2),
           COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2)
    INTO v_debits, v_credits
    FROM vw_general_ledger
    WHERE company_id = p_company_id
      AND je_date BETWEEN v_start AND v_end;
    v_recon := jsonb_build_array(jsonb_build_object(
      'check', 'gl_balance', 'debits', v_debits, 'credits', v_credits,
      'is_reconciled', v_debits = v_credits));
    IF v_debits <> v_credits THEN
      v_recon_failures := format('GL debits %s <> credits %s', v_debits, v_credits);
    END IF;
  END IF;

  IF v_recon_failures IS NOT NULL THEN
    RAISE EXCEPTION 'CAS export % period % to % does not reconcile: %',
      v_report_name, v_start, v_end, v_recon_failures;
  END IF;

  -- Frozen export rows, deterministically ordered, matching the file layout.
  IF v_key = 'slsp' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.system_no, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, system_no, customer_tin, customer_name,
             taxable_base, output_vat
      FROM vw_output_vat_review
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;
  ELSIF v_key = 'relief' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.system_no, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, system_no, supplier_tin, supplier_name,
             taxable_base, input_vat
      FROM vw_input_vat_review
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;
  ELSIF v_key = 'general_ledger' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.je_date, s.je_number, s.line_number, s.line_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT line_id, je_id, je_date, je_number, je_status, line_number,
             account_code, account_name, debit_amount, credit_amount
      FROM vw_general_ledger
      WHERE company_id = p_company_id
        AND je_date BETWEEN v_start AND v_end
    ) s;
  ELSE
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, supplier_tin, supplier_name,
             atc_code, tax_base, tax_withheld
      FROM vw_ewt_summary_ap
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;
  END IF;

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'report_name', v_report_name,
    'period_year', p_year,
    'period_month', p_month,
    'file_name', p_file_name
  );

  v_source_payload := jsonb_build_object(
    'report', v_report_payload,
    'export_rows', v_rows,
    'reconciliation', v_recon
  );

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' || p_year::text || ':' || p_month::text
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'cas_export_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_source_hash := encode(extensions.digest(convert_to(v_source_payload::text, 'UTF8'), 'sha256'), 'hex');
  v_snapshot_id := gen_random_uuid();

  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count,
    generated_by
  )
  VALUES (
    v_snapshot_id, p_company_id, v_report_type, 'cas_export_periods', v_source_id,
    'exported', v_snapshot_version, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  );

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year, period_month,
    file_name, row_count, generated_by, snapshot_id
  )
  VALUES (
    p_company_id, 'dat_file', v_report_name, p_year, p_month,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_snapshot_version,
    'source_hash', v_source_hash,
    'row_count', v_row_count,
    'rows', v_rows
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_cas_export(UUID, TEXT, INTEGER, INTEGER, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_snapshot_cas_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'Builds a CAS DAT export payload server-side, gates on reconciliation, creates a versioned exported report snapshot with a SHA-256 hash, writes the cas_export_log evidence row, and returns the frozen rows for file generation.';
