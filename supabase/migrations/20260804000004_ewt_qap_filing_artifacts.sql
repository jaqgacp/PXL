-- ═══════════════════════════════════════════════════════════════════════════
-- Backlog 8e (i) and (iii) — the 1601EQ and the QAP join the Filing Artifact
-- layer.
--
-- THE RULE THIS FILE OBEYS
--
--     The Filing Artifact is the system of record for compliance outputs.
--     Every UI, export, snapshot, API and integration CONSUMES it. None may
--     rebuild a compliance output from transactions, from the tax ledger, or in
--     a browser. One authoritative implementation per stage, per area; extra
--     faces are delegations.
--
-- THE TWO GAPS THIS CLOSES
--
--   (i) THE 1601EQ FILED WITHOUT LEAVING AN ARTIFACT.
--       The screen already *computed* through the governed engine —
--       `fn_compute_ewt_return` is a face of `fn_filing_reconciliation` — but it
--       then persisted `ewt_returns` by typed INSERT/UPDATE from the browser.
--       So an accountant could mark a 1601EQ filed and PXL would hold **no
--       filing artifact for it**: no working paper, no per-ATC schedule, nothing
--       to export, and nothing the export layer (8d) could consume. The 2550Q
--       and the 2551Q already had the projection shape; the 1601EQ is the third
--       instance of it and adds no new engine.
--
--  (iii) THE QAP WAS SUMMED IN A BROWSER AND REGISTERED NOWHERE.
--       `QAPPage` read `vw_ewt_summary_ap` and aggregated it per supplier and
--       ATC with a JavaScript loop. An alphalist computed on the client is not
--       an alphalist computed from the books: it could not tie to the 1601EQ it
--       is attached to, and it could not tie to the General Ledger at all.
--       Registering the QAP is what the filing engine promised it would be — a
--       seed row plus its tax kind, no function changes — and its working paper
--       is the same reader every other form uses, grouped per payee and ATC.
--
--       The QAP and the 1601EQ now read the *same* ledger population through the
--       *same* reader, so the alphalist adds up to the return it is attached to
--       by construction. It could not before: the browser read a view that
--       silently dropped reversal counter-rows, so a voided withholding left the
--       QAP and the 1601EQ disagreeing with no way to see it.
--
-- THE ORPHAN THIS RESOLVES
--   `fn_qap_2307_reconciliation` compares the QAP against the Form 2307
--   certificates actually issued. It was called from **nowhere** in `src/` and
--   read `vw_ewt_summary_ap` — a source view — for its QAP side. Resolved rather
--   than retired: the comparison is worth keeping, so its QAP side now reads the
--   artifact working paper and the function becomes a consumer of the filing
--   layer like everything else. Its signature and columns are unchanged, so
--   `fn_snapshot_wht_export` and its tests do not change.
--
--   Its granularity moves from supplier + ATC + nature + rate to supplier + ATC,
--   because that is the granularity at which the artifact states the alphalist.
--   The defect PXL-DA-009 fixed — one supplier's several ATCs collapsing into a
--   single row — stays fixed: ATC remains a grouping dimension. Nature of
--   payment and rate are properties of the ATC, and are reported, not grouped by.
--
-- WHAT THIS DOES NOT CHANGE
--   No posting function, no Accounting Kernel path, no journal shape, no tax
--   arithmetic. No tax-ledger row is written, moved or altered. `ewt_returns`
--   keeps its columns, its gates and its screens; it becomes a projection of the
--   artifact rather than a typed record. `fn_compute_ewt_return` keeps its exact
--   signature and answers exactly as before.
--
-- DELIBERATELY NOT DONE HERE
--   • The SLSP screen (8e ii) — it is monthly while its artifact is quarterly,
--     and re-keying `fn_snapshot_vat_export` is report-evidence work that waits
--     on 8c.
--   • Retiring `fn_snapshot_wht_export` and the legacy `compliance_*` working
--     papers (8f). Replacement is ordered: the governed path exists first, the
--     legacy path is removed after, and nothing is dropped while a test or a
--     screen still stands on it.
--   • Anything the 2550Q's stated figures would suggest. The 1601EQ has none:
--     `remitted_prior` is NOT the accountant's to state. PXL-AUD-041 already made
--     it a derived figure — the gate on `ewt_returns` refuses final or filed
--     unless it equals the posted 0619-E remittances for months 1 and 2 of the
--     quarter — so the projection reads `fn_compute_ewt_remitted_prior`, the
--     governed source, rather than accepting a number from a browser that the
--     gate would then reject. The screen's editable field is removed with it.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. THE 1601EQ IS PROJECTED FROM ITS ARTIFACT
--
-- The third instance of a shape written twice: generate the artifact, then
-- project it into the row the screen already reads. The screen types nothing.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_generate_ewt_return(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result    JSONB;
  v_return    ewt_returns%ROWTYPE;
  v_base      NUMERIC(15,2);
  v_withheld  NUMERIC(15,2);
  v_remitted  NUMERIC(15,2);
BEGIN
  -- One generator, one working paper, one reconciliation — the same three the
  -- 2550Q and the 2551Q use.
  v_result   := fn_generate_filing_artifact(p_company_id, '1601EQ', p_year, p_quarter);
  v_base     := (v_result->>'total_tax_base')::NUMERIC;
  v_withheld := (v_result->>'total_tax_amount')::NUMERIC;

  SELECT * INTO v_return FROM ewt_returns
  WHERE company_id = p_company_id
    AND period_year = p_year AND period_quarter = p_quarter;

  IF v_return.id IS NOT NULL AND v_return.status <> 'draft' THEN
    RAISE EXCEPTION 'The % Q% 1601EQ return is % and cannot be regenerated. Reopen it to draft first.',
      p_year, p_quarter, v_return.status;
  END IF;

  -- Derived, not stated. PXL-AUD-041 already made what was remitted a fact about
  -- posted 0619-E remittances, and the gate on this table refuses final or filed
  -- unless the return agrees with them. So the projection reads that governed
  -- source instead of carrying a figure a browser typed and the gate would then
  -- reject — the 1601EQ has no stated figure at all.
  v_remitted := fn_compute_ewt_remitted_prior(p_company_id, p_year, p_quarter);

  IF v_return.id IS NOT NULL THEN
    UPDATE ewt_returns SET
      total_tax_base     = v_base,
      total_ewt_withheld = v_withheld,
      remitted_prior     = v_remitted,
      still_due          = v_withheld - v_remitted,
      updated_by         = auth.uid(),
      updated_at         = now()
    WHERE id = v_return.id;
  ELSE
    INSERT INTO ewt_returns (
      company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due,
      status, created_by, updated_by)
    VALUES (
      p_company_id, p_year, p_quarter,
      v_base, v_withheld, v_remitted, v_withheld - v_remitted,
      'draft', auth.uid(), auth.uid())
    RETURNING * INTO v_return;
  END IF;

  RETURN v_result || jsonb_build_object(
    'ewt_return_id',      v_return.id,
    'total_tax_base',     v_base,
    'total_ewt_withheld', v_withheld,
    'remitted_prior',     v_remitted,
    'still_due',          v_withheld - v_remitted);
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_ewt_return(UUID, INTEGER, INTEGER) IS
  'Generates the 1601EQ through fn_generate_filing_artifact and projects it into ewt_returns for the screen that reads it. It computes no figure of its own: the withheld total comes from the artifact and what was already remitted from the posted 0619-E remittances.';

REVOKE ALL ON FUNCTION public.fn_generate_ewt_return(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_ewt_return(UUID, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE QAP IS REGISTERED — A SEED ROW, AS PROMISED
--
-- The alphalist behind the 1601EQ: the same tax kind, the same period, the same
-- reader, grouped per payee and ATC instead of summarised by ATC alone. It owes
-- nothing itself, so its tax kind carries no net sign.
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO ref_filing_artifact (
  form_code, form_name, artifact_kind, period_basis, group_dimensions,
  statutory_deadline_rule, statutory_basis)
VALUES
  ('QAP', 'Quarterly Alphalist of Payees', 'listing', 'quarterly',
   ARRAY['counterparty','atc'],
   'Attached to the 1601EQ, due the last day of the month following the close of the quarter',
   'RR 2-98 as amended')
ON CONFLICT (form_code) DO UPDATE
  SET form_name               = EXCLUDED.form_name,
      artifact_kind           = EXCLUDED.artifact_kind,
      period_basis            = EXCLUDED.period_basis,
      group_dimensions        = EXCLUDED.group_dimensions,
      statutory_deadline_rule = EXCLUDED.statutory_deadline_rule,
      statutory_basis         = EXCLUDED.statutory_basis,
      is_active               = true;

INSERT INTO ref_filing_artifact_kind (form_code, tax_kind, net_sign) VALUES
  ('QAP', 'ewt_payable', 0)
ON CONFLICT (form_code, tax_kind) DO UPDATE SET net_sign = EXCLUDED.net_sign;

-- ── An alphalist names the nature of the income payment ────────────────────
-- The BIR alphalist states the nature of payment beside the ATC. It is not a
-- figure and it is not aggregated: it is the governed description of the ATC the
-- artifact line already carries, resolved for display exactly as the company's
-- own name and TIN are. The constraint's purpose is unchanged and re-asserted:
-- no permitted source field reaches a transaction or the tax ledger.
ALTER TABLE ref_filing_export_column
  DROP CONSTRAINT IF EXISTS ref_filing_export_column_source_field_check;
ALTER TABLE ref_filing_export_column
  ADD CONSTRAINT ref_filing_export_column_source_field_check CHECK (source_field IN (
    'company_tin','company_name',
    'form_code','period_year','period_number','period_from','period_to',
    'total_tax_base','total_tax_amount','net_tax_payable',
    'filed_date','reference_no',
    'line_number','tax_kind','classification','tax_code','vat_code','atc_code',
    'atc_description',
    'counterparty_tin','counterparty_name',
    'tax_rate','tax_base','tax_amount','document_count'));

INSERT INTO ref_filing_export_column
  (form_code, export_format, column_order, column_header, source_field, value_kind)
VALUES
  -- QAP: the payee alphalist attached to the 1601EQ.
  ('QAP','csv',1,'TIN','counterparty_tin','text'),
  ('QAP','csv',2,'Registered Name','counterparty_name','text'),
  ('QAP','csv',3,'ATC','atc_code','text'),
  ('QAP','csv',4,'Nature of Payment','atc_description','text'),
  ('QAP','csv',5,'Rate','tax_rate','decimal'),
  ('QAP','csv',6,'Income Payments','tax_base','decimal'),
  ('QAP','csv',7,'Tax Withheld','tax_amount','decimal'),
  ('QAP','dat',1,'TIN','counterparty_tin','tin'),
  ('QAP','dat',2,'Registered Name','counterparty_name','text'),
  ('QAP','dat',3,'ATC','atc_code','text'),
  ('QAP','dat',4,'Income Payments','tax_base','decimal'),
  ('QAP','dat',5,'Tax Withheld','tax_amount','decimal')
ON CONFLICT (form_code, export_format, column_order) DO UPDATE
  SET column_header = EXCLUDED.column_header,
      source_field  = EXCLUDED.source_field,
      value_kind    = EXCLUDED.value_kind;

-- ── The one exporter learns one more artifact-resolved field ───────────────
-- Everything else about it is unchanged: one function, every form, both formats,
-- no dynamic SQL, and no read of a transaction, a tax-ledger row or a review
-- view. The ATC description is resolved by scalar subquery rather than a join so
-- that a code with more than one governed version cannot duplicate a cell.
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
        WHEN 'atc_description'   THEN (SELECT ac.description FROM atc_codes ac
                                        WHERE ac.code = l.atc_code AND ac.is_active
                                        ORDER BY ac.effective_from DESC, ac.id LIMIT 1)
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
-- 3. THE WITHHOLDING-AGENT GATE REACHES THE NEW PATH
--
-- A company that is not EWT-registered may not produce a QAP. That gate existed
-- for the legacy snapshot and keyed on its source table; migrating the screen
-- would have walked around it. It now keys on what the snapshot IS, so both the
-- legacy path and the artifact path are gated by the same rule.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_require_wht_export_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source_table IN ('wht_export_periods', 'filing_artifacts')
     AND upper(NEW.report_type) = 'QAP' THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'QAP export');
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_require_wht_export_profile() IS
  'A QAP may not be exported by a company that is not EWT-registered, whether it is produced by the legacy withholding snapshot or by the filing artifact export.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. THE QAP-TO-2307 COMPARISON BECOMES A CONSUMER OF THE ARTIFACT
--
-- Same signature, same columns, same meaning: does the alphalist we would file
-- agree with the certificates we actually issued? What changes is where the
-- alphalist side comes from — the governed working paper instead of a source
-- view — so the comparison is made against the figures that would actually be
-- filed, net of reversals, and tied to the General Ledger.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_qap_2307_reconciliation(
  p_company_id UUID,
  p_tax_year INT,
  p_tax_quarter INT
)
RETURNS TABLE (
  supplier_id UUID,
  supplier_tin TEXT,
  supplier_name TEXT,
  atc_code_id UUID,
  atc_code TEXT,
  nature_of_payment TEXT,
  tax_rate NUMERIC(5,2),
  qap_tax_base NUMERIC(15,2),
  qap_tax_withheld NUMERIC(15,2),
  form2307_tax_base NUMERIC(15,2),
  form2307_tax_withheld NUMERIC(15,2),
  base_variance NUMERIC(15,2),
  withheld_variance NUMERIC(15,2),
  form2307_status TEXT,
  form2307_version INT,
  is_reconciled BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tax_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid tax quarter: %', p_tax_quarter;
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  WITH qap AS (
    -- The alphalist as the artifact states it: one row per payee and ATC,
    -- already grouped by the one working-paper reader. Nothing is re-summed.
    SELECT
      w.counterparty_id AS supplier_id,
      COALESCE(w.counterparty_tin, '') AS supplier_tin,
      COALESCE(w.counterparty_name, 'Unknown') AS supplier_name,
      (SELECT ac.id FROM atc_codes ac
        WHERE ac.code = w.atc_code AND ac.is_active
        ORDER BY ac.id LIMIT 1) AS atc_code_id,
      COALESCE(w.atc_code, '') AS atc_code,
      COALESCE((SELECT ac.description FROM atc_codes ac
                 WHERE ac.code = w.atc_code AND ac.is_active
                 ORDER BY ac.effective_from DESC, ac.id LIMIT 1), '') AS nature_of_payment,
      COALESCE(w.tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
      w.tax_base   AS tax_base,
      w.tax_amount AS tax_withheld
    FROM fn_filing_working_paper(p_company_id, 'QAP', p_tax_year, p_tax_quarter) w
  ),
  cert AS (
    -- The certificates actually issued, aggregated to the granularity the
    -- artifact states the alphalist at: payee and ATC.
    SELECT
      f.supplier_id,
      COALESCE(s.tin, '') AS supplier_tin,
      COALESCE(s.registered_name, 'Unknown') AS supplier_name,
      -- `max(uuid)` does not exist; the id is reported, not grouped by.
      (array_agg(l.atc_code_id ORDER BY l.atc_code_id))[1] AS atc_code_id,
      COALESCE(l.atc_code, '') AS atc_code,
      COALESCE(MAX(l.nature_of_income), '') AS nature_of_payment,
      MAX(COALESCE(l.tax_rate, 0))::NUMERIC(5,2) AS tax_rate,
      SUM(COALESCE(l.tax_base, 0))::NUMERIC(15,2) AS tax_base,
      SUM(COALESCE(l.tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld,
      string_agg(DISTINCT f.status, ', ' ORDER BY f.status) AS status,
      MAX(f.version) AS version
    FROM form_2307_issuances f
    JOIN form_2307_issuance_lines l ON l.issuance_id = f.id
    LEFT JOIN suppliers s ON s.id = f.supplier_id
    WHERE f.company_id = p_company_id
      AND f.tax_year = p_tax_year
      AND f.tax_quarter = p_tax_quarter
      AND f.status <> 'superseded'
    GROUP BY
      f.supplier_id,
      COALESCE(s.tin, ''),
      COALESCE(s.registered_name, 'Unknown'),
      COALESCE(l.atc_code, '')
  )
  SELECT
    COALESCE(q.supplier_id, c.supplier_id),
    COALESCE(NULLIF(q.supplier_tin, ''), c.supplier_tin, '') AS supplier_tin,
    COALESCE(NULLIF(q.supplier_name, ''), c.supplier_name, 'Unknown') AS supplier_name,
    COALESCE(q.atc_code_id, c.atc_code_id),
    COALESCE(NULLIF(q.atc_code, ''), c.atc_code, '') AS atc_code,
    COALESCE(NULLIF(q.nature_of_payment, ''), c.nature_of_payment, '') AS nature_of_payment,
    COALESCE(q.tax_rate, c.tax_rate, 0)::NUMERIC(5,2),
    COALESCE(q.tax_base, 0)::NUMERIC(15,2),
    COALESCE(q.tax_withheld, 0)::NUMERIC(15,2),
    COALESCE(c.tax_base, 0)::NUMERIC(15,2),
    COALESCE(c.tax_withheld, 0)::NUMERIC(15,2),
    (COALESCE(q.tax_base, 0) - COALESCE(c.tax_base, 0))::NUMERIC(15,2),
    (COALESCE(q.tax_withheld, 0) - COALESCE(c.tax_withheld, 0))::NUMERIC(15,2),
    c.status,
    c.version,
    (
      q.supplier_id IS NOT NULL
      AND NULLIF(BTRIM(COALESCE(q.supplier_tin, '')), '') IS NOT NULL
      AND NULLIF(BTRIM(COALESCE(q.atc_code, '')), '') IS NOT NULL
      AND ABS(COALESCE(q.tax_base, 0) - COALESCE(c.tax_base, 0)) <= 0.01
      AND ABS(COALESCE(q.tax_withheld, 0) - COALESCE(c.tax_withheld, 0)) <= 0.01
    ) AS is_reconciled
  FROM qap q
  FULL OUTER JOIN cert c
    ON q.supplier_id IS NOT DISTINCT FROM c.supplier_id
   AND q.atc_code = c.atc_code
  ORDER BY
    COALESCE(NULLIF(q.supplier_name, ''), c.supplier_name, 'Unknown'),
    COALESCE(NULLIF(q.supplier_tin, ''), c.supplier_tin, ''),
    COALESCE(NULLIF(q.atc_code, ''), c.atc_code, '');
END;
$$;

COMMENT ON FUNCTION fn_qap_2307_reconciliation(UUID, INT, INT) IS
  'Compares the QAP filing artifact working paper to the active non-superseded Form 2307 issuance lines, per payee and ATC. It consumes the artifact layer and computes no alphalist of its own.';

GRANT EXECUTE ON FUNCTION fn_qap_2307_reconciliation(UUID, INT, INT) TO authenticated;
