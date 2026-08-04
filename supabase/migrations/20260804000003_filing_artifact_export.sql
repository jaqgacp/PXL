-- ═══════════════════════════════════════════════════════════════════════════
-- Backlog 8d — Filing Artifact Export.
--
-- THE RULE THIS FILE OBEYS
--
--     The Filing Artifact is the system of record for compliance outputs.
--     Every UI, export, snapshot, API and integration CONSUMES it. None may
--     rebuild a compliance report from transactions, from the tax ledger, or
--     in a browser.
--
--   So this file adds an export layer that is **another consumer of filing
--   artifacts, not another computation engine**. It reads `filing_artifacts`
--   and `filing_artifact_lines` and nothing else — no `tax_detail_entries`, no
--   `journal_entries`, no review views. It sums nothing that the artifact did
--   not already state.
--
-- THE GAP
--   An accountant could generate a fully reconciled 2550Q, 2551Q, 1601EQ, SLSP
--   or SAWT and had **no way to get it out of PXL** to key into eFPS or
--   eBIRForms. The filing chain ended one link short of being usable.
--
--   The three existing snapshot functions (`fn_snapshot_vat_export`,
--   `fn_snapshot_wht_export`, `fn_snapshot_books_export`) predate the artifact
--   layer and read **source views**. They are non-conforming under the rule
--   above and are migrated by Backlog 8e/8f — deliberately NOT touched here, so
--   that this change adds a governed path without disturbing the evidence trail
--   those functions already produced.
--
-- WHAT THIS ADDS
--   1. `ref_filing_export_column` — the export layout as **configuration**:
--      per form, per format, an ordered list of columns, each naming one field
--      of the artifact or its line and how to render it. Giving a form an
--      export is a **seed row**, exactly as registering the form was.
--   2. `fn_filing_artifact_export(company, form, year, period, format)` — the
--      one exporter, for every form and both formats. No dynamic SQL: the
--      registry's `source_field` is resolved by a governed CASE, the same
--      discipline `fn_filing_working_paper` uses for its dimensions.
--   3. `fn_snapshot_filing_artifact_export(...)` — the governed evidence
--      record, written to `report_snapshots` with `source_table =
--      'filing_artifacts'` and `source_id` = **the artifact's own id**. The
--      older exports had to synthesise a key because they had no artifact to
--      point at; this one points at the record itself.
--
-- WHAT IT REFUSES
--   A draft artifact cannot be exported — an export is evidence of a return the
--   accountant has settled, and a draft is still moving. An artifact whose
--   ledger no longer ties to the General Ledger cannot be exported either, even
--   if it was final when generated, because the books may have moved underneath
--   it. Both refusals are the artifact's own guarantees, re-asserted at the
--   moment the figures leave the system.
--
-- FORMATS
--   `csv` (opens in Excel, which is what "Excel" means for these attachments)
--   and `dat` (the fixed BIR alphalist shape), both built from the existing
--   `fn_export_csv_line` / `fn_export_dat_cell` / `fn_export_dat_tin` /
--   `fn_export_decimal` primitives. No second formatter was written.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. THE EXPORT LAYOUT, AS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS ref_filing_export_column (
  form_code     TEXT NOT NULL REFERENCES ref_filing_artifact(form_code) ON DELETE CASCADE,
  export_format TEXT NOT NULL CHECK (export_format IN ('csv','dat')),
  column_order  INTEGER NOT NULL,
  column_header TEXT NOT NULL,
  -- The governed set of things an export column may show. Every one of these
  -- resolves against the artifact, its line, or the filing company — never
  -- against a transaction or a tax-ledger row.
  source_field  TEXT NOT NULL CHECK (source_field IN (
    'company_tin','company_name',
    'form_code','period_year','period_number','period_from','period_to',
    'total_tax_base','total_tax_amount','net_tax_payable',
    'filed_date','reference_no',
    'line_number','tax_kind','classification','tax_code','vat_code','atc_code',
    'counterparty_tin','counterparty_name',
    'tax_rate','tax_base','tax_amount','document_count')),
  value_kind    TEXT NOT NULL DEFAULT 'text'
                CHECK (value_kind IN ('text','decimal','tin','date','integer')),
  PRIMARY KEY (form_code, export_format, column_order)
);

COMMENT ON TABLE ref_filing_export_column IS
  'Filing export engine: the column layout of each artifact export, per form and format. Giving a form an export is a seed row here; no function changes.';
COMMENT ON COLUMN ref_filing_export_column.source_field IS
  'Every permitted value resolves against the filing artifact, its line, or the filing company. There is deliberately no source field that reaches a transaction or the tax ledger.';

ALTER TABLE ref_filing_export_column ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ref_filing_export_column FROM PUBLIC;
GRANT SELECT ON ref_filing_export_column TO authenticated;
DROP POLICY IF EXISTS ref_filing_export_column_read ON ref_filing_export_column;
CREATE POLICY ref_filing_export_column_read ON ref_filing_export_column
  FOR SELECT TO authenticated USING (true);

-- ── The layouts for the five registered artifacts ──────────────────────────
INSERT INTO ref_filing_export_column
  (form_code, export_format, column_order, column_header, source_field, value_kind)
VALUES
  -- 2550Q: the VAT-code split behind the quarterly return.
  ('2550Q','csv',1,'Tax Kind','tax_kind','text'),
  ('2550Q','csv',2,'VAT Code','vat_code','text'),
  ('2550Q','csv',3,'Classification','classification','text'),
  ('2550Q','csv',4,'Taxable Base','tax_base','decimal'),
  ('2550Q','csv',5,'VAT Amount','tax_amount','decimal'),
  ('2550Q','csv',6,'Documents','document_count','integer'),

  -- 2551Q: filed on the ATC and the governed tax-code version.
  ('2551Q','csv',1,'ATC','atc_code','text'),
  ('2551Q','csv',2,'Tax Code','tax_code','text'),
  ('2551Q','csv',3,'Rate','tax_rate','decimal'),
  ('2551Q','csv',4,'Taxable Base','tax_base','decimal'),
  ('2551Q','csv',5,'Tax Due','tax_amount','decimal'),
  ('2551Q','csv',6,'Documents','document_count','integer'),

  -- 1601EQ: the expanded-withholding alphalist, by ATC.
  ('1601EQ','csv',1,'ATC','atc_code','text'),
  ('1601EQ','csv',2,'Rate','tax_rate','decimal'),
  ('1601EQ','csv',3,'Income Payment','tax_base','decimal'),
  ('1601EQ','csv',4,'Tax Withheld','tax_amount','decimal'),
  ('1601EQ','csv',5,'Documents','document_count','integer'),

  -- SLSP: per counterparty, sales and purchases together.
  ('SLSP','csv',1,'Tax Kind','tax_kind','text'),
  ('SLSP','csv',2,'TIN','counterparty_tin','text'),
  ('SLSP','csv',3,'Registered Name','counterparty_name','text'),
  ('SLSP','csv',4,'Taxable Base','tax_base','decimal'),
  ('SLSP','csv',5,'VAT Amount','tax_amount','decimal'),
  ('SLSP','dat',1,'TIN','counterparty_tin','tin'),
  ('SLSP','dat',2,'Registered Name','counterparty_name','text'),
  ('SLSP','dat',3,'Taxable Base','tax_base','decimal'),
  ('SLSP','dat',4,'VAT Amount','tax_amount','decimal'),

  -- SAWT: the tax withheld FROM this company, per payor and ATC.
  ('SAWT','csv',1,'Payor TIN','counterparty_tin','text'),
  ('SAWT','csv',2,'Payor Name','counterparty_name','text'),
  ('SAWT','csv',3,'ATC','atc_code','text'),
  ('SAWT','csv',4,'Income Payment','tax_base','decimal'),
  ('SAWT','csv',5,'Tax Withheld','tax_amount','decimal'),
  ('SAWT','dat',1,'Payor TIN','counterparty_tin','tin'),
  ('SAWT','dat',2,'Payor Name','counterparty_name','text'),
  ('SAWT','dat',3,'ATC','atc_code','text'),
  ('SAWT','dat',4,'Income Payment','tax_base','decimal'),
  ('SAWT','dat',5,'Tax Withheld','tax_amount','decimal')
ON CONFLICT (form_code, export_format, column_order) DO UPDATE
  SET column_header = EXCLUDED.column_header,
      source_field  = EXCLUDED.source_field,
      value_kind    = EXCLUDED.value_kind;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE ONE EXPORTER
--
-- One function, every form, both formats. It joins the registry to the
-- artifact's own lines; the artifact decides what the rows are and the registry
-- decides which of their fields are shown and in what order.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_filing_artifact_export(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER,
  p_format     TEXT DEFAULT 'csv'
)
RETURNS TABLE (
  line_number INTEGER,
  content     TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_format   TEXT := lower(BTRIM(p_format));
  v_form     TEXT := upper(BTRIM(p_form_code));
  v_artifact filing_artifacts%ROWTYPE;
  v_company  companies%ROWTYPE;
  v_cols     INTEGER;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF v_format NOT IN ('csv','dat') THEN
    RAISE EXCEPTION 'Unsupported filing export format %. Use csv or dat.', p_format;
  END IF;

  SELECT * INTO v_artifact FROM filing_artifacts
  WHERE company_id = p_company_id AND form_code = v_form
    AND period_year = p_year AND period_number = p_period;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No % artifact exists for % period %. Generate it first.',
      v_form, p_year, p_period;
  END IF;

  -- An export is evidence of a return the accountant has settled. A draft is
  -- still moving, so it does not leave the system.
  IF v_artifact.status = 'draft' THEN
    RAISE EXCEPTION 'The % % period % artifact is still a draft and cannot be exported. Mark it final first.',
      p_year, v_form, p_period;
  END IF;

  SELECT COUNT(*) INTO v_cols FROM ref_filing_export_column
  WHERE form_code = v_form AND export_format = v_format;
  IF v_cols = 0 THEN
    RAISE EXCEPTION 'No % export layout is registered for %.', v_format, v_form;
  END IF;

  SELECT * INTO v_company FROM companies WHERE id = p_company_id;

  RETURN QUERY
  WITH cell AS (
    SELECT
      l.line_number AS ln,
      c.column_order,
      c.value_kind,
      CASE c.source_field
        WHEN 'company_tin'       THEN v_company.tin
        WHEN 'company_name'      THEN v_company.registered_name
        WHEN 'form_code'         THEN v_artifact.form_code
        WHEN 'period_year'       THEN v_artifact.period_year::TEXT
        WHEN 'period_number'     THEN v_artifact.period_number::TEXT
        WHEN 'period_from'       THEN v_artifact.period_from::TEXT
        WHEN 'period_to'         THEN v_artifact.period_to::TEXT
        WHEN 'total_tax_base'    THEN v_artifact.total_tax_base::TEXT
        WHEN 'total_tax_amount'  THEN v_artifact.total_tax_amount::TEXT
        WHEN 'net_tax_payable'   THEN v_artifact.net_tax_payable::TEXT
        WHEN 'filed_date'        THEN v_artifact.filed_date::TEXT
        WHEN 'reference_no'      THEN v_artifact.reference_no
        WHEN 'line_number'       THEN l.line_number::TEXT
        WHEN 'tax_kind'          THEN l.tax_kind
        WHEN 'classification'    THEN l.classification
        WHEN 'tax_code'          THEN l.tax_code
        WHEN 'vat_code'          THEN l.vat_code
        WHEN 'atc_code'          THEN l.atc_code
        WHEN 'counterparty_tin'  THEN l.counterparty_tin
        WHEN 'counterparty_name' THEN l.counterparty_name
        WHEN 'tax_rate'          THEN l.tax_rate::TEXT
        WHEN 'tax_base'          THEN l.tax_base::TEXT
        WHEN 'tax_amount'        THEN l.tax_amount::TEXT
        WHEN 'document_count'    THEN l.document_count::TEXT
      END AS raw_value
    FROM filing_artifact_lines l
    JOIN ref_filing_export_column c
      ON c.form_code = v_form AND c.export_format = v_format
    WHERE l.artifact_id = v_artifact.id
  ),
  rendered AS (
    SELECT
      cell.ln,
      cell.column_order,
      -- Rendering reuses the existing export primitives; this file defines no
      -- formatter of its own.
      CASE cell.value_kind
        WHEN 'decimal' THEN fn_export_decimal(COALESCE(cell.raw_value, '0')::NUMERIC)
        WHEN 'integer' THEN COALESCE(cell.raw_value, '0')
        WHEN 'tin'     THEN fn_export_dat_tin(COALESCE(cell.raw_value, ''))
        ELSE COALESCE(cell.raw_value, '')
      END AS value
    FROM cell
  ),
  body AS (
    SELECT r.ln,
           CASE WHEN v_format = 'csv'
                THEN fn_export_csv_line(array_agg(r.value ORDER BY r.column_order))
                ELSE array_to_string(
                       array_agg(fn_export_dat_cell(r.value) ORDER BY r.column_order), ',')
           END AS content
    FROM rendered r
    GROUP BY r.ln
  )
  -- Row 0 is the header for CSV. A DAT file carries no header row.
  SELECT 0,
         fn_export_csv_line(array_agg(c.column_header ORDER BY c.column_order))
  FROM ref_filing_export_column c
  WHERE c.form_code = v_form AND c.export_format = v_format AND v_format = 'csv'
  HAVING COUNT(*) > 0
  UNION ALL
  SELECT b.ln, b.content FROM body b
  ORDER BY 1;
END;
$function$;

COMMENT ON FUNCTION public.fn_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'The one export reader for every BIR filing artifact and both formats. Reads filing_artifacts and filing_artifact_lines only — never a transaction, a tax-ledger row or a review view — and computes no figure of its own.';

REVOKE ALL ON FUNCTION public.fn_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. THE GOVERNED EVIDENCE RECORD
--
-- The older exports had to synthesise a snapshot key because there was no
-- artifact to point at. This one points at the record itself: `source_table` is
-- `filing_artifacts` and `source_id` is the artifact's own id.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_snapshot_filing_artifact_export(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER,
  p_format     TEXT DEFAULT 'csv'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_form        TEXT := upper(BTRIM(p_form_code));
  v_format      TEXT := lower(BTRIM(p_format));
  v_artifact    filing_artifacts%ROWTYPE;
  v_snapshot_id UUID;
  v_version     INTEGER;
  v_content     TEXT;
  v_rows        INTEGER := 0;
  v_unreconciled TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_artifact FROM filing_artifacts
  WHERE company_id = p_company_id AND form_code = v_form
    AND period_year = p_year AND period_number = p_period;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No % artifact exists for % period %.', v_form, p_year, p_period;
  END IF;

  -- The artifact reconciled when it left draft. The books may have moved since,
  -- so the tie is re-asserted at the moment the figures leave the system.
  SELECT string_agg(r.tax_kind || ' variance ' || r.variance::TEXT, '; ' ORDER BY r.tax_kind)
    INTO v_unreconciled
  FROM fn_filing_reconciliation(p_company_id, v_form, p_year, p_period) r
  WHERE NOT r.is_reconciled;

  IF v_unreconciled IS NOT NULL THEN
    RAISE EXCEPTION '% for % period % no longer ties to the General Ledger and cannot be exported: %',
      v_form, p_year, p_period, v_unreconciled;
  END IF;

  SELECT string_agg(e.content, E'\n' ORDER BY e.line_number), COUNT(*)::INTEGER
    INTO v_content, v_rows
  FROM fn_filing_artifact_export(p_company_id, v_form, p_year, p_period, v_format) e;

  SELECT COALESCE(MAX(snapshot_version), 0) + 1 INTO v_version
  FROM report_snapshots
  WHERE source_table = 'filing_artifacts'
    AND source_id = v_artifact.id
    AND snapshot_status = 'exported';

  INSERT INTO report_snapshots (
    company_id, report_type, source_table, source_id, snapshot_status,
    snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count, generated_by)
  VALUES (
    p_company_id, v_form, 'filing_artifacts', v_artifact.id, 'exported',
    v_version, v_artifact.period_from, v_artifact.period_to,
    jsonb_build_object(
      'form_code', v_form, 'export_format', v_format,
      'period_year', p_year, 'period_number', p_period,
      'artifact_id', v_artifact.id, 'artifact_status', v_artifact.status,
      'total_tax_base', v_artifact.total_tax_base,
      'total_tax_amount', v_artifact.total_tax_amount,
      'net_tax_payable', v_artifact.net_tax_payable),
    jsonb_build_object('content', COALESCE(v_content, '')),
    -- Hashed exactly as every other report snapshot is, through the same
    -- schema-qualified primitive.
    encode(extensions.digest(convert_to(COALESCE(v_content, ''), 'UTF8'), 'sha256'), 'hex'),
    v_rows, auth.uid())
  RETURNING id INTO v_snapshot_id;

  RETURN v_snapshot_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_snapshot_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'Records a governed evidence snapshot of a filing artifact export, keyed to the artifact''s own id. Refuses an artifact whose tax ledger no longer ties to the General Ledger.';

REVOKE ALL ON FUNCTION public.fn_snapshot_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_snapshot_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) TO authenticated;
