-- ═══════════════════════════════════════════════════════════════════════════
-- Backlog 8f, stage 1 — the governed Reconciling Item, and the role gate the
-- filing artifact never had.
--
-- WHY THIS EXISTS BEFORE ANYTHING IS RETIRED
--   8f's objective is to eliminate the second compliance architecture, not to
--   delete six screens. Owner rule, 2026-08-04: **never remove functionality
--   simply to satisfy the architecture** — if a manual capability has no governed
--   equivalent, migrate the capability first and retire the legacy
--   implementation after.
--
--   The six legacy `compliance_*` working-paper screens provide exactly one real
--   capability. Their "Generate" button is a stub that says so in its own words
--   ("Manual entry only — GL-backed generation requires the General Ledger
--   module"). What they actually let an accountant do is **key a line that no
--   ledger backs**: a reference, an amount, a remark. That is the capability
--   this file migrates, and it is the only one they have.
--
-- WHAT A RECONCILING ITEM IS (owner decision, 2026-08-04)
--   It documents a legitimate reconciliation difference. It never becomes one.
--
--     • manual and typed;                • never creates a journal entry;
--     • excluded from tax calculation;   • never changes a computed amount;
--     • excluded from working-paper and  • visible on the working paper and the
--       filing-artifact totals;            CSV export as a note only;
--     • excluded from GL reconciliation; • frozen once the artifact leaves draft.
--
--   Every item records reason, reference, amount, remarks, user and timestamp,
--   and is fully audited.
--
-- HOW THE EXCLUSIONS ARE ENFORCED
--   Not by remembering to filter. A reconciling item's amount lives in
--   `reconciling_amount`, a column **no computation in PXL reads**, and a CHECK
--   constraint forces its `tax_base`, `tax_amount` and `document_count` to zero.
--   So every existing total, reconciliation and export — including ones written
--   before this file and ones not yet written — excludes it *structurally*. The
--   proof is that the assertions written yesterday over `SUM(tax_amount)` keep
--   passing untouched with reconciling items present.
--
--   This is one working paper with two kinds of line, not a second working-paper
--   store beside it. `filing_artifact_lines` remains the only one.
--
-- THE CONTROL REGRESSION THIS ALSO CLOSES
--   `pt_returns`, `vat_returns` and `ewt_returns` all gate final/filed behind
--   owner/admin (`pxl_lifecycle_trigger`, 2026-07-01), and so do all twelve
--   legacy working-paper tables. **`filing_artifacts` gates nothing**: its RLS
--   UPDATE policy is `is_company_member` and its guard checks reconciliation and
--   immutability but never role. Any company member could mark a 2550Q filed.
--   The governed pipeline was weaker than the architecture it replaces; that is
--   fixed here rather than inherited into the retirement.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. A LINE THAT EXPLAINS, BESIDE A LINE THAT STATES
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE filing_artifact_lines
  ADD COLUMN IF NOT EXISTS line_kind TEXT NOT NULL DEFAULT 'generated'
    CHECK (line_kind IN ('generated', 'reconciling_item')),
  ADD COLUMN IF NOT EXISTS reason             TEXT,
  ADD COLUMN IF NOT EXISTS reference          TEXT,
  ADD COLUMN IF NOT EXISTS remarks            TEXT,
  -- The amount of a reconciling item lives here and nowhere else. No total, no
  -- reconciliation, no export figure column and no tax calculation reads this
  -- column; that is the whole point of it being a separate one.
  ADD COLUMN IF NOT EXISTS reconciling_amount NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS created_by         UUID,
  ADD COLUMN IF NOT EXISTS updated_by         UUID,
  ADD COLUMN IF NOT EXISTS updated_at         TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON COLUMN filing_artifact_lines.line_kind IS
  'generated: read from the posted ledger by fn_filing_working_paper, and it sums to the artifact total. reconciling_item: keyed by an accountant to explain a difference, and it sums to nothing.';
COMMENT ON COLUMN filing_artifact_lines.reconciling_amount IS
  'The amount a reconciling item explains. Deliberately not tax_amount: no total, reconciliation, tax calculation or export figure reads this column, so a reconciling item cannot move a compliance figure even by accident.';

-- A generated line states a figure and explains nothing; a reconciling item
-- explains a difference and states no figure. Neither can be the other.
ALTER TABLE filing_artifact_lines
  DROP CONSTRAINT IF EXISTS filing_artifact_lines_kind_shape_chk;
ALTER TABLE filing_artifact_lines
  ADD CONSTRAINT filing_artifact_lines_kind_shape_chk CHECK (
    (line_kind = 'generated'
      AND reason IS NULL AND reference IS NULL AND remarks IS NULL
      AND reconciling_amount IS NULL)
    OR
    (line_kind = 'reconciling_item'
      -- Recorded, all of it, or the row does not exist.
      AND BTRIM(COALESCE(reason, ''))    <> ''
      AND BTRIM(COALESCE(reference, '')) <> ''
      AND BTRIM(COALESCE(remarks, ''))   <> ''
      AND reconciling_amount IS NOT NULL
      AND created_by IS NOT NULL
      -- Excluded from every figure the artifact states, structurally.
      AND tax_base = 0 AND tax_amount = 0 AND document_count = 0
      AND tax_rate IS NULL)
  );

-- Each kind numbers its own lines: regenerating the ledger side must not have to
-- know how many notes an accountant has written, or renumber them.
ALTER TABLE filing_artifact_lines
  DROP CONSTRAINT IF EXISTS filing_artifact_lines_artifact_id_line_number_key;
ALTER TABLE filing_artifact_lines
  DROP CONSTRAINT IF EXISTS filing_artifact_lines_artifact_kind_line_key;
ALTER TABLE filing_artifact_lines
  ADD CONSTRAINT filing_artifact_lines_artifact_kind_line_key
    UNIQUE (artifact_id, line_kind, line_number);

-- ── Frozen once the artifact leaves draft; audited always ──────────────────
CREATE OR REPLACE FUNCTION public.fn_guard_filing_artifact_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row filing_artifacts%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM filing_artifacts
  WHERE id = COALESCE(NEW.artifact_id, OLD.artifact_id);

  -- A settled artifact is evidence. Its working paper — the figures and the
  -- notes that explain them — settles with it.
  IF v_row.status IS NOT NULL AND v_row.status <> 'draft' THEN
    RAISE EXCEPTION 'The % % period % artifact is %; its working paper and reconciling items are frozen. Reopen it to draft first.',
      v_row.period_year, v_row.form_code, v_row.period_number, v_row.status;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.line_kind IS DISTINCT FROM OLD.line_kind THEN
    RAISE EXCEPTION 'A working-paper line cannot change kind. A generated figure never becomes a note, and a note never becomes a figure.';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_filing_artifact_line_guard ON filing_artifact_lines;
CREATE TRIGGER trg_filing_artifact_line_guard
  BEFORE INSERT OR UPDATE OR DELETE ON filing_artifact_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_filing_artifact_line();

DROP TRIGGER IF EXISTS trg_audit_filing_artifact_lines ON filing_artifact_lines;
CREATE TRIGGER trg_audit_filing_artifact_lines
  AFTER INSERT OR UPDATE OR DELETE ON filing_artifact_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

REVOKE ALL ON FUNCTION public.fn_guard_filing_artifact_line() FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE ROLE GATE THE ARTIFACT NEVER HAD
--
-- Every projection of an artifact already requires owner/admin to declare a
-- return final or filed. The artifact itself did not.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_guard_filing_artifact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ledger_base NUMERIC(15,2);
  v_ledger_tax  NUMERIC(15,2);
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'A % filing artifact cannot be deleted. Reopen it to draft first.', OLD.status;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'filed' AND NEW.status = 'filed'
       AND (NEW.total_tax_amount IS DISTINCT FROM OLD.total_tax_amount
            OR NEW.total_tax_base IS DISTINCT FROM OLD.total_tax_base
            OR NEW.period_from IS DISTINCT FROM OLD.period_from
            OR NEW.period_to IS DISTINCT FROM OLD.period_to) THEN
      RAISE EXCEPTION 'A filed % return is immutable. File an amended return instead.', OLD.form_code;
    END IF;

    -- Declaring an artifact final or filed is an accounting lifecycle act, and
    -- every other compliance record in PXL already restricts it to owner/admin
    -- (pxl_lifecycle_trigger, 2026-07-01). This one did not.
    IF NEW.status IS DISTINCT FROM OLD.status
       AND NEW.status IN ('final', 'filed')
       AND NOT can_admin_company(NEW.company_id) THEN
      RAISE EXCEPTION 'Access denied: owner/admin role required to mark a % artifact %.',
        NEW.form_code, NEW.status;
    END IF;
  END IF;

  -- Leaving draft is the claim that this artifact IS the ledger for its period.
  IF NEW.status <> 'draft' THEN
    SELECT COALESCE(SUM(r.ledger_tax_base), 0), COALESCE(SUM(r.ledger_tax_amount), 0)
      INTO v_ledger_base, v_ledger_tax
    FROM fn_filing_reconciliation(NEW.company_id, NEW.form_code,
                                  NEW.period_year, NEW.period_number) r;

    IF ABS(COALESCE(NEW.total_tax_amount, 0) - v_ledger_tax) > 0.01
       OR ABS(COALESCE(NEW.total_tax_base, 0) - v_ledger_base) > 0.01 THEN
      RAISE EXCEPTION '% for % period % does not reconcile to the posted ledger (artifact base %, tax %; ledger base %, tax %). Regenerate it before marking it %.',
        NEW.form_code, NEW.period_year, NEW.period_number,
        NEW.total_tax_base, NEW.total_tax_amount, v_ledger_base, v_ledger_tax,
        NEW.status;
    END IF;

    IF EXISTS (
      SELECT 1 FROM fn_filing_reconciliation(NEW.company_id, NEW.form_code,
                                             NEW.period_year, NEW.period_number) r
      WHERE NOT r.is_reconciled
    ) THEN
      RAISE EXCEPTION '% for % period % cannot be marked % while its tax ledger does not tie to the General Ledger.',
        NEW.form_code, NEW.period_year, NEW.period_number, NEW.status;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_guard_filing_artifact() FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RECORDING ONE
--
-- There is no INSERT policy on `filing_artifact_lines`, so a reconciling item
-- cannot be typed into the table directly from a browser: it exists only through
-- this RPC, which is what makes "reason, reference, amount, remarks, user and
-- timestamp, always" enforceable rather than hoped for.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_add_filing_reconciling_item(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER,
  p_reason     TEXT,
  p_reference  TEXT,
  p_amount     NUMERIC,
  p_remarks    TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_form     TEXT := upper(BTRIM(p_form_code));
  v_artifact filing_artifacts%ROWTYPE;
  v_next     INTEGER;
  v_id       UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  IF BTRIM(COALESCE(p_reason, ''))    = ''
     OR BTRIM(COALESCE(p_reference, '')) = ''
     OR BTRIM(COALESCE(p_remarks, ''))   = ''
     OR p_amount IS NULL THEN
    RAISE EXCEPTION 'A reconciling item must record a reason, a reference, an amount and remarks. It is evidence of why the books and the form differ, and evidence without those is not evidence.';
  END IF;

  SELECT * INTO v_artifact FROM filing_artifacts
  WHERE company_id = p_company_id AND form_code = v_form
    AND period_year = p_year AND period_number = p_period;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No % artifact exists for % period %. Generate it first — a reconciling item explains a difference against a working paper that exists.',
      v_form, p_year, p_period;
  END IF;

  -- Explain the difference before declaring the figure; the guard on the line
  -- table enforces the same rule for updates and deletes.
  IF v_artifact.status <> 'draft' THEN
    RAISE EXCEPTION 'The % % period % artifact is % and its reconciling items are frozen. Reopen it to draft first.',
      p_year, v_form, p_period, v_artifact.status;
  END IF;

  SELECT COALESCE(MAX(l.line_number), 0) + 1 INTO v_next
  FROM filing_artifact_lines l
  WHERE l.artifact_id = v_artifact.id AND l.line_kind = 'reconciling_item';

  INSERT INTO filing_artifact_lines (
    artifact_id, line_number, line_kind,
    reason, reference, reconciling_amount, remarks,
    tax_base, tax_amount, document_count, created_by, updated_by)
  VALUES (
    v_artifact.id, v_next, 'reconciling_item',
    BTRIM(p_reason), BTRIM(p_reference), p_amount, BTRIM(p_remarks),
    0, 0, 0, auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_add_filing_reconciling_item(UUID, TEXT, INTEGER, INTEGER, TEXT, TEXT, NUMERIC, TEXT) IS
  'Records a governed reconciling item against a draft filing artifact. It explains a difference and never creates one: the amount is held in reconciling_amount, which no total, reconciliation, tax calculation or export figure reads.';

REVOKE ALL ON FUNCTION public.fn_add_filing_reconciling_item(UUID, TEXT, INTEGER, INTEGER, TEXT, TEXT, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_add_filing_reconciling_item(UUID, TEXT, INTEGER, INTEGER, TEXT, TEXT, NUMERIC, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_delete_filing_reconciling_item(p_item_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_company UUID;
  v_kind    TEXT;
BEGIN
  SELECT a.company_id, l.line_kind INTO v_company, v_kind
  FROM filing_artifact_lines l
  JOIN filing_artifacts a ON a.id = l.artifact_id
  WHERE l.id = p_item_id;

  IF v_company IS NULL THEN
    RAISE EXCEPTION 'No such working-paper line %', p_item_id;
  END IF;
  IF NOT is_company_member(v_company) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', v_company;
  END IF;
  IF v_kind <> 'reconciling_item' THEN
    RAISE EXCEPTION 'A generated working-paper line is not deletable: it is what the posted ledger says. Regenerate the artifact instead.';
  END IF;

  -- The guard refuses this if the artifact has left draft.
  DELETE FROM filing_artifact_lines WHERE id = p_item_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_delete_filing_reconciling_item(UUID) IS
  'Removes a reconciling item from a draft filing artifact. A generated line is never deletable through it.';

REVOKE ALL ON FUNCTION public.fn_delete_filing_reconciling_item(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_delete_filing_reconciling_item(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_filing_reconciling_items(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER
)
RETURNS TABLE (
  id          UUID,
  line_number INTEGER,
  reason      TEXT,
  reference   TEXT,
  amount      NUMERIC(15,2),
  remarks     TEXT,
  created_by  UUID,
  created_at  TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.id, l.line_number, l.reason, l.reference, l.reconciling_amount,
         l.remarks, l.created_by, l.created_at
  FROM filing_artifact_lines l
  JOIN filing_artifacts a ON a.id = l.artifact_id
  WHERE a.company_id = p_company_id
    AND a.form_code = upper(BTRIM(p_form_code))
    AND a.period_year = p_year
    AND a.period_number = p_period
    AND l.line_kind = 'reconciling_item'
    AND is_company_member(a.company_id)
  ORDER BY l.line_number;
$$;

COMMENT ON FUNCTION public.fn_filing_reconciling_items(UUID, TEXT, INTEGER, INTEGER) IS
  'The reconciling items recorded against one filing artifact, for the working-paper screen that shows them beside the generated figures.';

REVOKE ALL ON FUNCTION public.fn_filing_reconciling_items(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_filing_reconciling_items(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. REGENERATION REPLACES THE LEDGER SIDE AND LEAVES THE NOTES ALONE
--
-- The only change: the delete that precedes a regeneration is scoped to
-- generated lines. An accountant's explanation of a difference survives the
-- restatement of the figures it explains — which is the entire point of it.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_generate_filing_artifact(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_artifact  ref_filing_artifact%ROWTYPE;
  v_from      DATE;
  v_to        DATE;
  v_row       filing_artifacts%ROWTYPE;
  v_id        UUID;
  v_base      NUMERIC(15,2) := 0;
  v_tax       NUMERIC(15,2) := 0;
  v_net       NUMERIC(15,2);
  v_summary   JSONB := '{}'::JSONB;
  v_lines     INTEGER := 0;
  v_reconciled BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_artifact FROM ref_filing_artifact
  WHERE form_code = UPPER(BTRIM(p_form_code)) AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or inactive filing artifact %', p_form_code;
  END IF;

  SELECT b.date_from, b.date_to INTO v_from, v_to
  FROM fn_filing_period_bounds(v_artifact.period_basis, p_year, p_period) b;

  SELECT * INTO v_row FROM filing_artifacts
  WHERE company_id = p_company_id AND form_code = v_artifact.form_code
    AND period_year = p_year AND period_number = p_period;

  IF FOUND AND v_row.status <> 'draft' THEN
    RAISE EXCEPTION 'The % % period % artifact is % and cannot be regenerated. Reopen it to draft first.',
      p_year, v_artifact.form_code, p_period, v_row.status;
  END IF;

  -- Totals and the per-kind summary come from the reconciliation, which reads
  -- the same ledger the working paper does. One read, one truth. A reconciling
  -- item cannot reach either: it holds no tax figure at all.
  SELECT COALESCE(SUM(r.ledger_tax_base), 0),
         COALESCE(SUM(r.ledger_tax_amount), 0),
         bool_and(r.is_reconciled),
         COALESCE(jsonb_object_agg(r.tax_kind, jsonb_build_object(
           'tax_base', r.ledger_tax_base,
           'tax_amount', r.ledger_tax_amount,
           'gl_amount', r.gl_amount,
           'variance', r.variance,
           'is_reconciled', r.is_reconciled)), '{}'::JSONB)
    INTO v_base, v_tax, v_reconciled, v_summary
  FROM fn_filing_reconciliation(p_company_id, v_artifact.form_code, p_year, p_period) r;

  IF v_artifact.artifact_kind = 'return' THEN
    SELECT COALESCE(SUM(r.ledger_tax_amount * fak.net_sign), 0)
      INTO v_net
    FROM fn_filing_reconciliation(p_company_id, v_artifact.form_code, p_year, p_period) r
    JOIN ref_filing_artifact_kind fak
      ON fak.form_code = v_artifact.form_code AND fak.tax_kind = r.tax_kind;
  ELSE
    v_net := NULL;
  END IF;

  -- `v_row.id` is the only reliable test here: the aggregate reads above have
  -- long since reset FOUND, and an aggregate always finds its one row.
  IF v_row.id IS NOT NULL THEN
    UPDATE filing_artifacts SET
      period_from = v_from, period_to = v_to,
      total_tax_base = v_base, total_tax_amount = v_tax,
      net_tax_payable = v_net, summary = v_summary,
      generated_at = now(), updated_by = auth.uid(), updated_at = now()
    WHERE id = v_row.id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO filing_artifacts (
      company_id, form_code, period_year, period_number, period_from, period_to,
      total_tax_base, total_tax_amount, net_tax_payable, summary,
      status, created_by, updated_by)
    VALUES (
      p_company_id, v_artifact.form_code, p_year, p_period, v_from, v_to,
      v_base, v_tax, v_net, v_summary, 'draft', auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  END IF;

  -- Scoped to the ledger side: a reconciling item explains a difference that
  -- restating the figures does not resolve, so it survives the restatement.
  DELETE FROM filing_artifact_lines
  WHERE artifact_id = v_id AND line_kind = 'generated';

  INSERT INTO filing_artifact_lines (
    artifact_id, line_number, line_kind, tax_kind, classification, tax_code,
    vat_code, atc_code, counterparty_id, counterparty_tin, counterparty_name,
    tax_rate, tax_base, tax_amount, document_count)
  SELECT v_id, ROW_NUMBER() OVER (), 'generated',
         w.tax_kind, w.classification, w.tax_code, w.vat_code, w.atc_code,
         w.counterparty_id, w.counterparty_tin, w.counterparty_name, w.tax_rate,
         w.tax_base, w.tax_amount, w.document_count
  FROM fn_filing_working_paper(p_company_id, v_artifact.form_code, p_year, p_period) w;

  GET DIAGNOSTICS v_lines = ROW_COUNT;

  RETURN jsonb_build_object(
    'artifact_id',      v_id,
    'form_code',        v_artifact.form_code,
    'form_name',        v_artifact.form_name,
    'artifact_kind',    v_artifact.artifact_kind,
    'period_year',      p_year,
    'period_number',    p_period,
    'period_from',      v_from,
    'period_to',        v_to,
    'total_tax_base',   v_base,
    'total_tax_amount', v_tax,
    'net_tax_payable',  v_net,
    'is_reconciled',    COALESCE(v_reconciled, true),
    'summary',          v_summary,
    'line_count',       v_lines,
    'deadline_rule',    v_artifact.statutory_deadline_rule);
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_filing_artifact(UUID, TEXT, INTEGER, INTEGER) IS
  'Generates any registered BIR filing artifact and its working paper from the posted tax ledger. The only writer of filing_artifacts; refuses to regenerate one that is already final or filed; replaces the generated lines and leaves an accountant''s reconciling items in place.';

REVOKE ALL ON FUNCTION public.fn_generate_filing_artifact(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_filing_artifact(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. THE EXPORT CARRIES THE NOTES, AND ONLY AS NOTES
--
-- CSV gets a trailing note block: an accountant's attachment should carry the
-- explanation with the figures. DAT does **not** — it is the machine-readable
-- alphalist the Bureau ingests, and a note row in it is a corrupt file. That is
-- the one place where "visible on the export" is answered with "not there".
--
-- The note rows are numbered from 1,000,000 so they sort after any body without
-- the exporter having to aggregate anything to find out how long the body is.
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
      AND l.line_kind = 'generated'
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
  ),
  notes AS (
    SELECT 1000000 + l.line_number AS ln,
           fn_export_csv_line(ARRAY[
             'RECONCILING ITEM', l.reason, l.reference,
             fn_export_decimal(l.reconciling_amount), l.remarks]) AS content
    FROM filing_artifact_lines l
    WHERE l.artifact_id = v_artifact.id
      AND l.line_kind = 'reconciling_item'
      AND v_format = 'csv'
  )
  -- Row 0 is the header for CSV. A DAT file carries no header row.
  SELECT 0,
         fn_export_csv_line(array_agg(c.column_header ORDER BY c.column_order))
  FROM ref_filing_export_column c
  WHERE c.form_code = v_form AND c.export_format = v_format AND v_format = 'csv'
  HAVING COUNT(*) > 0
  UNION ALL
  SELECT b.ln, b.content FROM body b
  UNION ALL
  SELECT n.ln, n.content FROM notes n
  ORDER BY 1;
END;
$function$;

COMMENT ON FUNCTION public.fn_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'The one export reader for every BIR filing artifact and both formats. Reads filing_artifacts and filing_artifact_lines only — never a transaction, a tax-ledger row or a review view — and computes no figure of its own. Reconciling items appear as trailing notes in CSV and never in DAT, which the Bureau ingests.';

REVOKE ALL ON FUNCTION public.fn_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_filing_artifact_export(UUID, TEXT, INTEGER, INTEGER, TEXT) TO authenticated;
