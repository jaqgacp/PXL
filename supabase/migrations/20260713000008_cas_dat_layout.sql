-- PXL-DA-019: versioned CAS DAT layout and immutable DAT artifacts.
--
-- The previous trusted slice proved the exact bytes downloaded by the user,
-- but the CAS export text was still CSV-shaped. This slice keeps the same
-- server-rendered byte evidence contract and changes CAS exports to a
-- versioned pipe-delimited DAT envelope:
--   H|PXL-CAS-DAT-1.0|<report>|<company tin>|<period start>|<period end>|<version>
--   D|... report-specific detail fields ...
--   T|<row count>|<total base/debit>|<total tax/credit>
-- Records are CRLF-delimited and stored byte-for-byte in both the report
-- snapshot payload and the immutable cas_export_artifacts table.

CREATE TABLE IF NOT EXISTS cas_export_artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  snapshot_id UUID NOT NULL UNIQUE REFERENCES report_snapshots(id),
  layout_version TEXT NOT NULL,
  encoding TEXT NOT NULL DEFAULT 'UTF-8',
  newline_style TEXT NOT NULL DEFAULT 'CRLF',
  mime_type TEXT NOT NULL DEFAULT 'text/plain',
  file_name TEXT NOT NULL,
  file_content TEXT NOT NULL,
  file_hash TEXT NOT NULL CHECK (length(file_hash) = 64),
  byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
  generated_by UUID,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE cas_export_artifacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cas_export_artifacts_read ON cas_export_artifacts;
CREATE POLICY cas_export_artifacts_read
  ON cas_export_artifacts FOR SELECT TO authenticated
  USING (is_company_member(company_id));
GRANT SELECT ON cas_export_artifacts TO authenticated;

ALTER TABLE cas_export_log
  ADD COLUMN IF NOT EXISTS artifact_id UUID,
  ADD COLUMN IF NOT EXISTS file_hash TEXT,
  ADD COLUMN IF NOT EXISTS layout_version TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'cas_export_log_artifact_id_fkey'
      AND conrelid = 'cas_export_log'::regclass
  ) THEN
    ALTER TABLE cas_export_log
      ADD CONSTRAINT cas_export_log_artifact_id_fkey
      FOREIGN KEY (artifact_id) REFERENCES cas_export_artifacts(id);
  END IF;
END;
$$;

ALTER TABLE cas_export_log
  DROP CONSTRAINT IF EXISTS cas_export_log_export_type_check,
  ADD CONSTRAINT cas_export_log_export_type_check
    CHECK (export_type IN ('dat_file', 'csv_export', 'report', 'audit_package'));

COMMENT ON TABLE cas_export_artifacts IS
  'Immutable exact UTF-8 DAT bytes rendered for a CAS export snapshot, with layout version and SHA-256 hash.';
COMMENT ON COLUMN cas_export_log.artifact_id IS
  'Immutable exact-file artifact generated for a CAS DAT snapshot.';
COMMENT ON COLUMN cas_export_log.file_hash IS
  'Compatibility alias for the exact exported file SHA-256; mirrors file_sha256 for CAS DAT artifacts.';
COMMENT ON COLUMN cas_export_log.layout_version IS
  'Version of the export byte layout used for the generated file.';

CREATE OR REPLACE FUNCTION fn_export_dat_cell(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT btrim(regexp_replace(
    regexp_replace(COALESCE(p_value, ''), '[|\r\n\t]+', ' ', 'g'),
    '[[:space:]]+', ' ', 'g'
  ))
$$;

CREATE OR REPLACE FUNCTION fn_export_dat_tin(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(COALESCE(p_value, ''), '[^0-9]', '', 'g')
$$;

CREATE OR REPLACE FUNCTION fn_export_dat_numeric(p_value TEXT)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(NULLIF(p_value, '')::NUMERIC, 0)
$$;

CREATE OR REPLACE FUNCTION fn_export_dat_file_name(p_file_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_file_name TEXT := btrim(COALESCE(p_file_name, ''));
BEGIN
  IF v_file_name = '' THEN
    RETURN NULL;
  END IF;

  v_file_name := regexp_replace(v_file_name, '\.[^.]+$', '.dat');
  IF v_file_name !~* '\.dat$' THEN
    v_file_name := v_file_name || '.dat';
  END IF;

  RETURN v_file_name;
END;
$$;

CREATE OR REPLACE FUNCTION fn_render_cas_dat_text(
  p_report_type TEXT,
  p_company_tin TEXT,
  p_period_start DATE,
  p_period_end DATE,
  p_snapshot_version INTEGER,
  p_rows JSONB
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_layout CONSTANT TEXT := 'PXL-CAS-DAT-1.0';
  v_crlf CONSTANT TEXT := E'\r\n';
  v_rows JSONB := COALESCE(p_rows, '[]'::jsonb);
  v_row JSONB;
  v_content TEXT;
  v_line TEXT;
  v_count INTEGER := 0;
  v_total_a NUMERIC := 0;
  v_total_b NUMERIC := 0;
BEGIN
  IF p_report_type NOT IN ('CAS_SLSP', 'CAS_RELIEF', 'CAS_GL', 'CAS_QAP') THEN
    RAISE EXCEPTION 'Unsupported CAS DAT report type: %', p_report_type;
  END IF;

  IF jsonb_typeof(v_rows) <> 'array' THEN
    RAISE EXCEPTION 'CAS DAT rows must be a JSON array';
  END IF;

  v_content := concat_ws('|',
    'H',
    v_layout,
    COALESCE(p_report_type, ''),
    fn_export_dat_tin(p_company_tin),
    COALESCE(p_period_start::TEXT, ''),
    COALESCE(p_period_end::TEXT, ''),
    COALESCE(p_snapshot_version::TEXT, '')
  ) || v_crlf;

  FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows)
  LOOP
    v_count := v_count + 1;

    IF p_report_type = 'CAS_SLSP' THEN
      v_line := concat_ws('|',
        'D',
        fn_export_dat_cell(v_row ->> 'transaction_type'),
        COALESCE(v_row ->> 'document_date', ''),
        fn_export_dat_cell(v_row ->> 'document_number'),
        fn_export_dat_tin(v_row ->> 'counterparty_tin'),
        fn_export_dat_cell(v_row ->> 'counterparty_name'),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'gross_amount')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'vat_amount')),
        fn_export_dat_cell(v_row ->> 'counterparty_address'),
        fn_export_dat_cell(v_row ->> 'dat_classification_code')
      );
      v_total_a := v_total_a + fn_export_dat_numeric(v_row ->> 'gross_amount');
      v_total_b := v_total_b + fn_export_dat_numeric(v_row ->> 'vat_amount');
    ELSIF p_report_type = 'CAS_RELIEF' THEN
      v_line := concat_ws('|',
        'D',
        'R',
        fn_export_dat_tin(v_row ->> 'taxpayer_tin'),
        fn_export_dat_cell(v_row ->> 'transaction_type'),
        fn_export_dat_tin(v_row ->> 'counterparty_tin'),
        fn_export_dat_cell(v_row ->> 'counterparty_name'),
        fn_export_dat_cell(v_row ->> 'counterparty_address'),
        fn_export_dat_cell(v_row ->> 'document_number'),
        COALESCE(v_row ->> 'document_date', ''),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'gross_amount')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'exempt_amount')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'zero_rated_amount')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'taxable_amount')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'vat_amount')),
        fn_export_dat_cell(v_row ->> 'dat_classification_code')
      );
      v_total_a := v_total_a + fn_export_dat_numeric(v_row ->> 'gross_amount');
      v_total_b := v_total_b + fn_export_dat_numeric(v_row ->> 'vat_amount');
    ELSIF p_report_type = 'CAS_GL' THEN
      v_line := concat_ws('|',
        'D',
        'GL',
        COALESCE(v_row ->> 'je_date', ''),
        fn_export_dat_cell(v_row ->> 'je_number'),
        fn_export_dat_cell(v_row ->> 'line_number'),
        fn_export_dat_cell(v_row ->> 'account_code'),
        fn_export_dat_cell(v_row ->> 'account_name'),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'debit_amount')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'credit_amount')),
        fn_export_dat_cell(v_row ->> 'line_description')
      );
      v_total_a := v_total_a + fn_export_dat_numeric(v_row ->> 'debit_amount');
      v_total_b := v_total_b + fn_export_dat_numeric(v_row ->> 'credit_amount');
    ELSE
      v_line := concat_ws('|',
        'D',
        'QAP',
        COALESCE(v_row ->> 'invoice_date', ''),
        fn_export_dat_tin(v_row ->> 'supplier_tin'),
        fn_export_dat_cell(v_row ->> 'supplier_name'),
        fn_export_dat_cell(v_row ->> 'atc_code'),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'tax_base')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'tax_withheld')),
        fn_export_decimal(fn_export_dat_numeric(v_row ->> 'tax_rate')),
        fn_export_dat_cell(v_row ->> 'nature_of_payment')
      );
      v_total_a := v_total_a + fn_export_dat_numeric(v_row ->> 'tax_base');
      v_total_b := v_total_b + fn_export_dat_numeric(v_row ->> 'tax_withheld');
    END IF;

    v_content := v_content || v_line || v_crlf;
  END LOOP;

  v_content := v_content || concat_ws('|',
    'T',
    v_count::TEXT,
    fn_export_decimal(v_total_a),
    fn_export_decimal(v_total_b)
  ) || v_crlf;

  RETURN v_content;
END;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_cas_export_unchecked(
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
  v_export_text TEXT;
  v_export_sha256 TEXT;
  v_export_size INTEGER;
  v_recon JSONB := '[]'::jsonb;
  v_recon_failures TEXT;
  v_debits NUMERIC(15,2);
  v_credits NUMERIC(15,2);
  v_company_tin TEXT;
  v_file_name TEXT;
  v_artifact_id UUID;
  v_layout CONSTANT TEXT := 'PXL-CAS-DAT-1.0';
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

  v_file_name := fn_export_dat_file_name(p_file_name);
  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  SELECT tin INTO v_company_tin
  FROM companies
  WHERE id = p_company_id;

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

  IF v_key = 'slsp' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.transaction_type, s.document_date, s.document_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT 'S'::TEXT AS transaction_type,
             ov.transaction_id,
             ov.invoice_date AS document_date,
             ov.system_no AS document_number,
             ov.customer_tin AS counterparty_tin,
             ov.customer_name AS counterparty_name,
             COALESCE(NULLIF(si.customer_address_snapshot, ''), c.registered_address, '') AS counterparty_address,
             (ov.taxable_base + ov.zero_rated_sales + ov.exempt_sales)::NUMERIC(15,2) AS gross_amount,
             ov.exempt_sales AS exempt_amount,
             ov.zero_rated_sales AS zero_rated_amount,
             ov.taxable_base AS taxable_amount,
             ov.output_vat AS vat_amount,
             CASE
               WHEN ov.taxable_base <> 0 THEN 'T'
               WHEN ov.zero_rated_sales <> 0 THEN 'Z'
               ELSE 'E'
             END AS dat_classification_code,
             ov.source_module,
             ov.source_doc_type,
             ov.source_doc_id
      FROM vw_output_vat_review ov
      LEFT JOIN sales_invoices si ON si.id = ov.transaction_id
      LEFT JOIN customers c ON c.id = si.customer_id
      WHERE ov.company_id = p_company_id
        AND ov.invoice_date BETWEEN v_start AND v_end
      UNION ALL
      SELECT 'P'::TEXT,
             iv.transaction_id,
             iv.invoice_date,
             COALESCE(NULLIF(iv.invoice_no, ''), iv.system_no),
             iv.supplier_tin,
             iv.supplier_name,
             iv.supplier_address,
             (iv.taxable_base + iv.zero_rated + iv.exempt_purchases)::NUMERIC(15,2),
             iv.exempt_purchases,
             iv.zero_rated,
             iv.taxable_base,
             iv.input_vat,
             CASE
               WHEN iv.taxable_base <> 0 THEN 'T'
               WHEN iv.zero_rated <> 0 THEN 'Z'
               ELSE 'E'
             END,
             iv.source_module,
             iv.source_doc_type,
             iv.source_doc_id
      FROM vw_input_vat_review iv
      WHERE iv.company_id = p_company_id
        AND iv.invoice_date BETWEEN v_start AND v_end
    ) s;
  ELSIF v_key = 'relief' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.transaction_type, s.document_date, s.document_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT fn_export_dat_tin(v_company_tin) AS taxpayer_tin,
             'S'::TEXT AS transaction_type,
             ov.transaction_id,
             ov.invoice_date AS document_date,
             ov.system_no AS document_number,
             ov.customer_tin AS counterparty_tin,
             ov.customer_name AS counterparty_name,
             COALESCE(NULLIF(si.customer_address_snapshot, ''), c.registered_address, '') AS counterparty_address,
             (ov.taxable_base + ov.zero_rated_sales + ov.exempt_sales)::NUMERIC(15,2) AS gross_amount,
             ov.exempt_sales AS exempt_amount,
             ov.zero_rated_sales AS zero_rated_amount,
             ov.taxable_base AS taxable_amount,
             ov.output_vat AS vat_amount,
             CASE
               WHEN ov.taxable_base <> 0 THEN 'AT'
               WHEN ov.zero_rated_sales <> 0 THEN 'AZ'
               ELSE 'AE'
             END AS dat_classification_code,
             ov.source_module,
             ov.source_doc_type,
             ov.source_doc_id
      FROM vw_output_vat_review ov
      LEFT JOIN sales_invoices si ON si.id = ov.transaction_id
      LEFT JOIN customers c ON c.id = si.customer_id
      WHERE ov.company_id = p_company_id
        AND ov.invoice_date BETWEEN v_start AND v_end
      UNION ALL
      SELECT fn_export_dat_tin(v_company_tin),
             'P'::TEXT,
             iv.transaction_id,
             iv.invoice_date,
             COALESCE(NULLIF(iv.invoice_no, ''), iv.system_no),
             iv.supplier_tin,
             iv.supplier_name,
             iv.supplier_address,
             (iv.taxable_base + iv.zero_rated + iv.exempt_purchases)::NUMERIC(15,2),
             iv.exempt_purchases,
             iv.zero_rated,
             iv.taxable_base,
             iv.input_vat,
             CASE
               WHEN iv.taxable_base <> 0 THEN 'AT'
               WHEN iv.zero_rated <> 0 THEN 'AZ'
               ELSE 'AE'
             END,
             iv.source_module,
             iv.source_doc_type,
             iv.source_doc_id
      FROM vw_input_vat_review iv
      WHERE iv.company_id = p_company_id
        AND iv.invoice_date BETWEEN v_start AND v_end
    ) s;
  ELSIF v_key = 'general_ledger' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.je_date, s.je_number, s.line_number, s.line_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT line_id, je_id, je_date, je_number, je_status, line_number,
             account_code, account_name, line_description,
             debit_amount, credit_amount, reference_doc_type, reference_doc_id
      FROM vw_general_ledger
      WHERE company_id = p_company_id
        AND je_date BETWEEN v_start AND v_end
    ) s;
  ELSE
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.supplier_tin, s.supplier_name, s.atc_code, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, supplier_tin, supplier_name,
             atc_code, nature_of_payment, tax_rate, tax_base, tax_withheld,
             source_doc_type, source_doc_id
      FROM vw_ewt_summary_ap
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;
  END IF;

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' || p_year::text || ':' || p_month::text
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'cas_export_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_export_text := fn_render_cas_dat_text(
    v_report_type, v_company_tin, v_start, v_end, v_snapshot_version, v_rows
  );
  v_export_sha256 := encode(extensions.digest(convert_to(v_export_text, 'UTF8'), 'sha256'), 'hex');
  v_export_size := octet_length(convert_to(v_export_text, 'UTF8'));

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'report_name', v_report_name,
    'period_year', p_year,
    'period_month', p_month,
    'file_name', v_file_name,
    'export_layout', v_layout,
    'newline_style', 'CRLF'
  );

  v_source_payload := jsonb_build_object(
    'report', v_report_payload,
    'export_rows', v_rows,
    'export_layout', v_layout,
    'newline_style', 'CRLF',
    'mime_type', 'text/plain',
    'export_file_text', v_export_text,
    'export_file_sha256', v_export_sha256,
    'export_file_size_bytes', v_export_size,
    'reconciliation', v_recon
  );

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

  INSERT INTO cas_export_artifacts (
    company_id, snapshot_id, layout_version, file_name, file_content,
    file_hash, byte_count, generated_by
  )
  VALUES (
    p_company_id, v_snapshot_id, v_layout, v_file_name, v_export_text,
    v_export_sha256, v_export_size, auth.uid()
  )
  RETURNING id INTO v_artifact_id;

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year, period_month,
    file_name, row_count, generated_by, snapshot_id, artifact_id,
    file_sha256, file_size_bytes, file_hash, layout_version
  )
  VALUES (
    p_company_id, 'dat_file', v_report_name, p_year, p_month,
    v_file_name, v_row_count, auth.uid(), v_snapshot_id, v_artifact_id,
    v_export_sha256, v_export_size, v_export_sha256, v_layout
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_snapshot_version,
    'source_hash', v_source_hash,
    'artifact_id', v_artifact_id,
    'file_name', v_file_name,
    'layout_version', v_layout,
    'export_sha256', v_export_sha256,
    'export_size_bytes', v_export_size,
    'export_text', v_export_text,
    'row_count', v_row_count,
    'rows', v_rows
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_render_cas_dat(p_snapshot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_snapshot report_snapshots%ROWTYPE;
  v_company_tin TEXT;
  v_content TEXT;
  v_file_hash TEXT;
  v_byte_count INTEGER;
  v_file_name TEXT;
  v_artifact_id UUID;
  v_layout CONSTANT TEXT := 'PXL-CAS-DAT-1.0';
BEGIN
  SELECT * INTO v_snapshot
  FROM report_snapshots
  WHERE id = p_snapshot_id;

  IF NOT FOUND
     OR v_snapshot.report_type NOT IN ('CAS_SLSP', 'CAS_RELIEF', 'CAS_GL', 'CAS_QAP')
     OR NOT is_company_member(v_snapshot.company_id) THEN
    RAISE EXCEPTION 'CAS export snapshot not found or access denied';
  END IF;

  SELECT tin INTO v_company_tin
  FROM companies
  WHERE id = v_snapshot.company_id;

  v_file_name := COALESCE(
    fn_export_dat_file_name(v_snapshot.report_payload ->> 'file_name'),
    lower(v_snapshot.report_type) || '.dat'
  );

  IF v_snapshot.source_payload ->> 'export_layout' = v_layout
     AND v_snapshot.source_payload ? 'export_file_text' THEN
    v_content := v_snapshot.source_payload ->> 'export_file_text';
  ELSE
    v_content := fn_render_cas_dat_text(
      v_snapshot.report_type,
      v_company_tin,
      v_snapshot.period_start,
      v_snapshot.period_end,
      v_snapshot.snapshot_version,
      v_snapshot.source_payload -> 'export_rows'
    );
  END IF;

  v_file_hash := encode(extensions.digest(convert_to(v_content, 'UTF8'), 'sha256'), 'hex');
  v_byte_count := octet_length(convert_to(v_content, 'UTF8'));

  INSERT INTO cas_export_artifacts (
    company_id, snapshot_id, layout_version, file_name, file_content,
    file_hash, byte_count, generated_by
  )
  VALUES (
    v_snapshot.company_id, v_snapshot.id, v_layout, v_file_name, v_content,
    v_file_hash, v_byte_count, auth.uid()
  )
  ON CONFLICT (snapshot_id) DO NOTHING
  RETURNING id INTO v_artifact_id;

  IF v_artifact_id IS NULL THEN
    SELECT id, file_content, file_hash, file_name, byte_count
    INTO v_artifact_id, v_content, v_file_hash, v_file_name, v_byte_count
    FROM cas_export_artifacts
    WHERE snapshot_id = v_snapshot.id;
  END IF;

  UPDATE cas_export_log
  SET artifact_id = v_artifact_id,
      file_hash = v_file_hash,
      file_sha256 = v_file_hash,
      file_size_bytes = v_byte_count,
      layout_version = v_layout,
      file_name = v_file_name
  WHERE snapshot_id = v_snapshot.id;

  RETURN jsonb_build_object(
    'artifact_id', v_artifact_id,
    'snapshot_id', v_snapshot.id,
    'file_name', v_file_name,
    'content', v_content,
    'export_text', v_content,
    'file_hash', v_file_hash,
    'export_sha256', v_file_hash,
    'byte_count', v_byte_count,
    'export_size_bytes', v_byte_count,
    'source_hash', v_snapshot.source_hash,
    'layout_version', v_layout,
    'encoding', 'UTF-8',
    'newline_style', 'CRLF',
    'mime_type', 'text/plain'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_render_cas_dat(UUID) TO authenticated;

COMMENT ON FUNCTION fn_render_cas_dat_text(TEXT, TEXT, DATE, DATE, INTEGER, JSONB) IS
  'Renders a versioned CRLF-delimited PXL CAS DAT file from frozen snapshot rows.';
COMMENT ON FUNCTION fn_snapshot_cas_export_unchecked(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'Builds a reconciled CAS export snapshot and exact PXL-CAS-DAT-1.0 file bytes server-side, stores immutable byte evidence, and returns the frozen DAT text for download.';
COMMENT ON FUNCTION fn_render_cas_dat(UUID) IS
  'Returns the immutable exact DAT artifact for a CAS export snapshot, creating it from frozen rows when needed.';
