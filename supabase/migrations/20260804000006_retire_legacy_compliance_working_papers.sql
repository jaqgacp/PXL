-- ═══════════════════════════════════════════════════════════════════════════
-- Backlog 8f, stage 2 — retiring the second compliance architecture.
--
-- ORDERED REPLACEMENT, NOT DELETION
--   Owner rule: migrate the consumers onto the governed implementation first,
--   verify no dependency remains, and only then retire the legacy objects. That
--   order is why this file comes fourth and not first:
--
--     8d  gave every artifact an export.
--     8e  put the 1601EQ and the QAP on the artifact layer.
--     8f/1 gave the manual capability a governed home (the Reconciling Item)
--          and closed the role gate the artifact never had.
--     8f/2 (this file) removes what is now genuinely unreachable.
--
--   Before this file, `src/pages/FilingWorkingPapersPage.tsx` replaced the four
--   hand-keyed screens with one face of the governed pipeline, and the four
--   routes were repointed at it. Nothing dropped here has a consumer left.
--
-- WHAT IS RETIRED
--   • The legacy PT working-paper write inside `fn_generate_pt_return`. It was
--     the **only** function writing any legacy working-paper table.
--   • Eight tables: the VAT, EWT, 1601EQ and PT working-paper header/line pairs.
--   • `fn_snapshot_wht_export` and `wht_export_periods` — the SAWT/QAP evidence
--     snapshot that read source views. Since item 8e both screens export through
--     `fn_snapshot_filing_artifact_export`, which is keyed to the artifact's own
--     id, so this had become an orphan with only its own test as a consumer.
--
-- WHAT IS DELIBERATELY NOT RETIRED
--   `compliance_fwt_working_papers_*` and `compliance_1601fq_working_papers_*`,
--   and their two screens. **FWT is not a tax kind**: the `tax_detail_entries`
--   CHECK admits five kinds and FWT is not among them, so FWT never reaches the
--   tax ledger and no filing artifact can be generated for it. Removing those
--   surfaces would delete functionality with no governed equivalent, which the
--   ordered-replacement rule forbids. They are retired by **Backlog 22**, which
--   must give FWT the same pipeline as VAT, PT and EWT rather than a special
--   case. This is the single documented exception, and it is asserted as such by
--   test `129` so it cannot be quietly forgotten.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. THE 2551Q STOPS WRITING A SECOND WORKING PAPER
--
-- `fn_generate_pt_return` generated the artifact and then *also* wrote the
-- legacy PT working paper for the screen that read it. That screen is now a face
-- of the governed working paper, so the second write has no reader. What it
-- reported as `working_paper_lines` is the artifact's own line count, which the
-- generator already returns as `line_count`.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_generate_pt_return(
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
  v_result     JSONB;
  v_base       NUMERIC(15,2);
  v_due        NUMERIC(15,2);
  v_rate       NUMERIC(5,2);
  v_rate_count INTEGER;
  v_from       DATE;
  v_to         DATE;
  v_return     pt_returns%ROWTYPE;
  v_paid_prior NUMERIC(15,2) := 0;
BEGIN
  -- One generator, one working paper, one reconciliation — the same three the
  -- 2550Q and the 1601EQ use.
  v_result := fn_generate_filing_artifact(p_company_id, '2551Q', p_year, p_quarter);
  v_base   := (v_result->>'total_tax_base')::NUMERIC;
  v_due    := (v_result->>'total_tax_amount')::NUMERIC;
  v_from   := (v_result->>'period_from')::DATE;
  v_to     := (v_result->>'period_to')::DATE;

  SELECT COUNT(DISTINCT tde.tax_rate) INTO v_rate_count
  FROM tax_detail_entries tde
  WHERE tde.company_id = p_company_id
    AND tde.tax_kind = 'percentage_tax'
    AND tde.document_date BETWEEN v_from AND v_to;

  IF v_rate_count = 1 THEN
    SELECT MAX(tde.tax_rate)::NUMERIC(5,2) INTO v_rate
    FROM tax_detail_entries tde
    WHERE tde.company_id = p_company_id
      AND tde.tax_kind = 'percentage_tax'
      AND tde.document_date BETWEEN v_from AND v_to;
  ELSIF v_base <> 0 THEN
    v_rate := ROUND(v_due / v_base * 100, 2);
  ELSE
    v_rate := 0;
  END IF;

  -- `pt_returns` is the record the PT screens read. It is a projection of the
  -- artifact above, never a second computation.
  SELECT * INTO v_return FROM pt_returns
  WHERE company_id = p_company_id AND period_year = p_year AND period_quarter = p_quarter;

  IF v_return.id IS NOT NULL AND v_return.status <> 'draft' THEN
    RAISE EXCEPTION 'The % Q% percentage tax return is % and cannot be regenerated. Reopen it to draft first.',
      p_year, p_quarter, v_return.status;
  END IF;

  v_paid_prior := COALESCE(v_return.pt_paid_prior_quarters, 0);

  IF v_return.id IS NOT NULL THEN
    UPDATE pt_returns SET
      gross_sales_exempt     = 0,
      gross_sales_zero_rated = 0,
      taxable_base           = v_base,
      pt_rate                = v_rate,
      pt_due                 = v_due,
      pt_still_due           = v_due - v_paid_prior,
      updated_by             = auth.uid(),
      updated_at             = now()
    WHERE id = v_return.id;
  ELSE
    INSERT INTO pt_returns (
      company_id, period_year, period_quarter,
      gross_sales_exempt, gross_sales_zero_rated,
      taxable_base, pt_rate, pt_due, pt_paid_prior_quarters, pt_still_due,
      status, created_by, updated_by
    ) VALUES (
      p_company_id, p_year, p_quarter,
      0, 0, v_base, v_rate, v_due, 0, v_due,
      'draft', auth.uid(), auth.uid()
    ) RETURNING * INTO v_return;
  END IF;

  RETURN v_result || jsonb_build_object(
    'pt_return_id',  v_return.id,
    'taxable_base',  v_base,
    'pt_rate',       v_rate,
    'pt_due',        v_due,
    'pt_still_due',  v_due - v_paid_prior);
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) IS
  'Generates the 2551Q through fn_generate_filing_artifact and projects it into pt_returns for the screens that read it. It computes no figure of its own and writes no second working paper.';

REVOKE ALL ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE LEGACY WITHHOLDING EXPORT GOES WITH ITS LAST CONSUMER
--
-- `fn_snapshot_wht_export` built the SAWT and QAP from `vw_ewt_summary_ap` and
-- `vw_cwt_summary_ar` — source views — and wrote an evidence row keyed to a
-- synthesised `wht_export_periods` id because there was no artifact to point at.
-- Both screens now export through `fn_snapshot_filing_artifact_export`, keyed to
-- the artifact itself, so this path had no consumer left but its own test.
--
-- The withholding-agent gate keeps working: it now keys only on the artifact
-- path, which is the only path.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_require_wht_export_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source_table = 'filing_artifacts' AND upper(NEW.report_type) = 'QAP' THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'QAP export');
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_require_wht_export_profile() IS
  'A QAP may not be exported by a company that is not EWT-registered. Since Backlog 8f the filing artifact export is the only path that can produce one.';

DROP FUNCTION IF EXISTS fn_snapshot_wht_export(UUID, TEXT, INTEGER, INTEGER);
DROP TABLE IF EXISTS wht_export_periods CASCADE;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. THE EIGHT TABLES
--
-- Every one of these is now unreachable: no function writes or reads them (the
-- last writer was removed in section 1), no RPC returns them, and no routed
-- screen touches them — the four that did were replaced by one face of the
-- governed working paper before this migration was written.
--
-- The FWT pair and the 1601FQ pair are **not** here. See the header.
-- ═══════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS compliance_vat_working_papers_lines    CASCADE;
DROP TABLE IF EXISTS compliance_vat_working_papers_headers  CASCADE;
DROP TABLE IF EXISTS compliance_ewt_working_papers_lines    CASCADE;
DROP TABLE IF EXISTS compliance_ewt_working_papers_headers  CASCADE;
DROP TABLE IF EXISTS compliance_1601eq_working_papers_lines   CASCADE;
DROP TABLE IF EXISTS compliance_1601eq_working_papers_headers CASCADE;
DROP TABLE IF EXISTS compliance_pt_working_papers_lines     CASCADE;
DROP TABLE IF EXISTS compliance_pt_working_papers_headers   CASCADE;
