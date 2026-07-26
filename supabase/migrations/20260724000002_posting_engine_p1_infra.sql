-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P1 (infrastructure only, ZERO accounting behavior change)
--
-- Implements the frozen Posting Engine architecture P1 scope
--   docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md  (§3.1, §3.2, §4.1/4.2,
--   §4.5, §4.7, §7 P1)
-- as NEW, INERT infrastructure placed ALONGSIDE the existing kernel. Nothing here
-- is wired into any existing posting function, no trigger is added, no existing
-- code path is removed or modified, and no existing journal is changed. Every
-- existing transaction continues to produce byte-for-byte identical journals.
--
-- Deliverables (all additive):
--   1. Additive metadata columns on journal_entries / journal_entry_lines (nullable).
--   2. fn_derive_journal_number      — single governed Option-B journal-number derivation.
--   3. fn_build_posting_context      — canonical Posting Context (JSONB).
--   4. fn_validate_posting_plan      — Posting Plan invariant validator (pure).
--   5. fn_posting_plan_fingerprint   — deterministic Plan fingerprint (pure).
--   6. fn_add_posting_line_push      — push-based line builder, ALONGSIDE fn_add_posting_line.
--
-- Explicitly NOT in P1: no Totality Guard, no posting-function migration, no COA
-- resolver adoption, no tax/dimension/subledger/audit changes, no backfill of the
-- new columns on historical rows.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Additive metadata columns (nullable, backward compatible) ────────────────
-- Nullable, no defaults that would rewrite existing rows; not referenced by any
-- existing function. Historical journals remain unchanged (all values NULL).
ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS posting_origin     TEXT,
  ADD COLUMN IF NOT EXISTS reversal_of_je_id  UUID REFERENCES journal_entries(id),
  ADD COLUMN IF NOT EXISTS posting_run_id     UUID,
  ADD COLUMN IF NOT EXISTS source_fingerprint TEXT;

ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS je_posting_origin_check;
ALTER TABLE journal_entries ADD  CONSTRAINT je_posting_origin_check
  CHECK (posting_origin IS NULL OR posting_origin IN ('system','manual'));

ALTER TABLE journal_entry_lines
  ADD COLUMN IF NOT EXISTS line_role      TEXT,
  ADD COLUMN IF NOT EXISTS source_line_id UUID;

ALTER TABLE journal_entry_lines DROP CONSTRAINT IF EXISTS jel_line_role_check;
ALTER TABLE journal_entry_lines ADD  CONSTRAINT jel_line_role_check
  CHECK (line_role IS NULL OR line_role IN ('base','tax','withholding','rounding','control','offset'));

COMMENT ON COLUMN journal_entries.posting_origin     IS 'Posting Engine P1 (additive): system|manual (invariant 13). Nullable; populated by the kernel from P2+; historical rows intentionally NULL.';
COMMENT ON COLUMN journal_entries.reversal_of_je_id  IS 'Posting Engine P1 (additive): structural reversal link (invariant 15), replacing the je_number LIKE ''%-REV-%'' convention. Populated from P7; historical rows intentionally NULL.';
COMMENT ON COLUMN journal_entries.posting_run_id     IS 'Posting Engine P1 (additive): correlates journals produced by one posting invocation/batch. Populated from P2+.';
COMMENT ON COLUMN journal_entries.source_fingerprint IS 'Posting Engine P1 (additive): md5 of the resolved Posting Plan (deterministic-replay + tamper evidence). Populated from P2+.';
COMMENT ON COLUMN journal_entry_lines.line_role      IS 'Posting Engine P1 (additive): base|tax|withholding|rounding|control|offset. Enables control/tax reconciliation. Populated from P2+; historical rows intentionally NULL.';
COMMENT ON COLUMN journal_entry_lines.source_line_id IS 'Posting Engine P1 (additive): traceability to the originating source-document line. Populated from P2+.';

-- ── 2. Central journal-number derivation — Option B (frozen §4.5) ────────────────
-- The single governed implementation of journal-number derivation. Source-numbered
-- documents produce JE-<TYPE>-<source#> byte-identically to the legacy scattered
-- concatenation (uppercase type literal + raw source number). Source-less journals
-- (MANUAL, REV, system/engine-generated) allocate from the certified Number Series
-- Engine (document code 'JE'). ADDITIVE: not yet called by any posting function;
-- adoption is P2/P3. Number Series owns sequence allocation; Posting owns identity
-- assembly (§4.5 ownership separation).
CREATE OR REPLACE FUNCTION fn_derive_journal_number(
  p_source_type   TEXT,
  p_source_number TEXT DEFAULT NULL,
  p_company_id    UUID DEFAULT NULL,
  p_branch_id     UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_source_type, '')));
BEGIN
  IF v_type = '' THEN
    RAISE EXCEPTION 'fn_derive_journal_number: source type is required'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Source-numbered: keep the legacy JE-<TYPE>-<source#> shape, one governed place.
  IF COALESCE(p_source_number, '') <> '' THEN
    RETURN 'JE-' || v_type || '-' || p_source_number;
  END IF;

  -- Source-less: allocate from the certified Number Series Engine.
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'fn_derive_journal_number: company_id is required to allocate a source-less journal number for %', v_type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN fn_next_document_number(p_company_id, p_branch_id, 'JE');
END;
$$;

REVOKE ALL ON FUNCTION fn_derive_journal_number(TEXT, TEXT, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_derive_journal_number(TEXT, TEXT, UUID, UUID) TO authenticated, service_role;
COMMENT ON FUNCTION fn_derive_journal_number(TEXT, TEXT, UUID, UUID) IS
  'Posting Engine P1 (Option B, §4.5): single governed journal-number derivation. Source-numbered -> JE-<TYPE>-<source#> (byte-identical to legacy); source-less -> Number Series ''JE'' code. Additive; not wired into posting functions until P2+. Documented dependency: source-less allocation requires a provisioned ''JE'' number series (fails closed otherwise).';

-- ── 3. Posting Context — canonical execution context (frozen §3, §3.1) ───────────
-- Pure assembler of known inputs into the canonical shape. No business logic, no
-- resolution, no validation of source data. All keys always present (stable shape).
CREATE OR REPLACE FUNCTION fn_build_posting_context(
  p_company_id           UUID,
  p_branch_id            UUID,
  p_source_type          TEXT,
  p_source_id            UUID,
  p_source_number        TEXT,
  p_posting_date         DATE,
  p_as_of                DATE DEFAULT NULL,
  p_posting_origin       TEXT DEFAULT 'system',
  p_department_id        UUID DEFAULT NULL,
  p_cost_center_id       UUID DEFAULT NULL,
  p_project_id           UUID DEFAULT NULL,
  p_location_id          UUID DEFAULT NULL,
  p_functional_entity_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'company_id',    p_company_id,
    'branch_id',     p_branch_id,
    'source_type',   UPPER(BTRIM(COALESCE(p_source_type, ''))),
    'source_id',     p_source_id,
    'source_number', p_source_number,
    'posting_date',  p_posting_date,
    'as_of',         COALESCE(p_as_of, p_posting_date),
    'posting_origin', p_posting_origin,
    'actor',         auth.uid(),
    'dimensions', jsonb_build_object(
      'branch_id',            p_branch_id,
      'department_id',        p_department_id,
      'cost_center_id',       p_cost_center_id,
      'project_id',           p_project_id,
      'location_id',          p_location_id,
      'functional_entity_id', p_functional_entity_id
    )
  );
$$;

REVOKE ALL ON FUNCTION fn_build_posting_context(UUID,UUID,TEXT,UUID,TEXT,DATE,DATE,TEXT,UUID,UUID,UUID,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_build_posting_context(UUID,UUID,TEXT,UUID,TEXT,DATE,DATE,TEXT,UUID,UUID,UUID,UUID,UUID) TO authenticated, service_role;
COMMENT ON FUNCTION fn_build_posting_context(UUID,UUID,TEXT,UUID,TEXT,DATE,DATE,TEXT,UUID,UUID,UUID,UUID,UUID) IS
  'Posting Engine P1 (§3): canonical Posting Context assembler (JSONB, stable shape). Pure structure; no business logic. Additive; consumed by the kernel from P2+.';

-- ── 4. Posting Plan validator (frozen §3.1, invariant assertions) ────────────────
-- Pure validator of a Posting Plan JSONB: balance, sign discipline, account
-- presence, non-empty, company present. Raises on violation; no persistence.
CREATE OR REPLACE FUNCTION fn_validate_posting_plan(p_plan JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_line   JSONB;
  v_debit  NUMERIC := 0;
  v_credit NUMERIC := 0;
  v_n      INTEGER := 0;
  v_d      NUMERIC;
  v_c      NUMERIC;
BEGIN
  IF p_plan IS NULL OR jsonb_typeof(p_plan->'lines') <> 'array' THEN
    RAISE EXCEPTION 'posting plan: missing lines array' USING ERRCODE = 'check_violation';
  END IF;
  IF (p_plan->'header'->>'company_id') IS NULL THEN
    RAISE EXCEPTION 'posting plan: header.company_id is required' USING ERRCODE = 'check_violation';
  END IF;

  FOR v_line IN SELECT jsonb_array_elements(p_plan->'lines') LOOP
    v_n := v_n + 1;
    v_d := COALESCE((v_line->>'debit')::numeric, 0);
    v_c := COALESCE((v_line->>'credit')::numeric, 0);
    IF v_d < 0 OR v_c < 0 THEN
      RAISE EXCEPTION 'posting plan: line % has a negative amount', v_n USING ERRCODE = 'check_violation';
    END IF;
    IF v_d <> 0 AND v_c <> 0 THEN
      RAISE EXCEPTION 'posting plan: line % has both a debit and a credit', v_n USING ERRCODE = 'check_violation';
    END IF;
    IF (v_line->>'account_id') IS NULL THEN
      RAISE EXCEPTION 'posting plan: line % is missing account_id', v_n USING ERRCODE = 'check_violation';
    END IF;
    v_debit  := v_debit + v_d;
    v_credit := v_credit + v_c;
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'posting plan: no lines' USING ERRCODE = 'check_violation';
  END IF;
  IF round(v_debit, 2) <> round(v_credit, 2) THEN
    RAISE EXCEPTION 'posting plan: unbalanced (debit % <> credit %)', v_debit, v_credit
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION fn_validate_posting_plan(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_validate_posting_plan(JSONB) TO authenticated, service_role;
COMMENT ON FUNCTION fn_validate_posting_plan(JSONB) IS
  'Posting Engine P1 (§3.1): pure Posting Plan invariant validator (balance, sign, account presence, non-empty). No persistence. Additive; used by preview and the kernel from P2+.';

-- ── 5. Posting Plan fingerprint (frozen §3.1 deterministic replay) ───────────────
CREATE OR REPLACE FUNCTION fn_posting_plan_fingerprint(p_plan JSONB)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT md5(p_plan::text);
$$;

REVOKE ALL ON FUNCTION fn_posting_plan_fingerprint(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_posting_plan_fingerprint(JSONB) TO authenticated, service_role;
COMMENT ON FUNCTION fn_posting_plan_fingerprint(JSONB) IS
  'Posting Engine P1 (§3.1): deterministic md5 fingerprint of a Posting Plan (JSONB is key-sorted, so canonical). Equal inputs -> equal fingerprint (preview ≡ actual input check). Additive.';

-- ── 6. Push-based posting line builder (frozen §5.2, alongside fn_add_posting_line)
-- Receives dimensions PUSHED by the caller (no pull from source tables by document
-- type — the D3 fix) plus line_role and source_line_id. ADDITIVE: the existing
-- pull-based fn_add_posting_line is left completely untouched and is NOT removed.
CREATE OR REPLACE FUNCTION fn_add_posting_line_push(
  p_je_id                UUID,
  p_line_number          INTEGER,
  p_account_id           UUID,
  p_description          TEXT,
  p_debit                NUMERIC DEFAULT 0,
  p_credit               NUMERIC DEFAULT 0,
  p_line_role            TEXT DEFAULT NULL,
  p_source_line_id       UUID DEFAULT NULL,
  p_branch_id            UUID DEFAULT NULL,
  p_department_id        UUID DEFAULT NULL,
  p_cost_center_id       UUID DEFAULT NULL,
  p_project_id           UUID DEFAULT NULL,
  p_location_id          UUID DEFAULT NULL,
  p_functional_entity_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_line_id    UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM journal_entries WHERE id = p_je_id;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'fn_add_posting_line_push: journal entry % not found', p_je_id
      USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO journal_entry_lines (
    je_id, company_id, line_number, account_id, description,
    debit_amount, credit_amount, line_role, source_line_id,
    branch_id, department_id, cost_center_id, project_id, location_id, functional_entity_id,
    created_by, updated_by
  ) VALUES (
    p_je_id, v_company_id, p_line_number, p_account_id, p_description,
    COALESCE(p_debit, 0), COALESCE(p_credit, 0), p_line_role, p_source_line_id,
    p_branch_id, p_department_id, p_cost_center_id, p_project_id, p_location_id, p_functional_entity_id,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_line_id;

  RETURN v_line_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_add_posting_line_push(UUID,INTEGER,UUID,TEXT,NUMERIC,NUMERIC,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_add_posting_line_push(UUID,INTEGER,UUID,TEXT,NUMERIC,NUMERIC,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,UUID) TO service_role;
COMMENT ON FUNCTION fn_add_posting_line_push(UUID,INTEGER,UUID,TEXT,NUMERIC,NUMERIC,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,UUID) IS
  'Posting Engine P1 (§5.2): push-based journal line builder — dimensions supplied by the caller (no source-table pull), plus line_role/source_line_id. Additive, alongside the untouched pull-based fn_add_posting_line. Wired into posting from P3.';
