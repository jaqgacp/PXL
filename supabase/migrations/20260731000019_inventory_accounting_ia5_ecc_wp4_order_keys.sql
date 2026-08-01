-- =============================================================================
-- IA-5 Economic Costing Chronology Hardening — Work Package 4 (M4)
-- Persisted ECC order key (dormant, additive, reversible)
--
-- Authority:
--   * ADR-C01 (frozen) — §3.2, §3.3, §6.2, §6.3: no database-allocated value may
--     order; canonical source identity is never DB-generated
--   * ECC-01 (accepted, owner approved) — §4.2 E1-E10 / X1-X4, §4.3, §6.1,
--     V-14/V-15, R-03
--   * IA-5 ECC Hardening Implementation Design §6.3, §15, §17 M4, §18, §19, §20,
--     §21, §23.3, §24 row 4, §25
--   * IA-5 WP-4 Detailed Order-Key Specification (EA-006/EA-007) §2, §3, §4, §5,
--     §6, §7
--   * WP-4 Authorisation Re-run (2026-07-31) — PASS / WP-4 AUTHORISED
--
-- Scope (WP-4 only): create exactly one dormant table and its authorised
-- controls. No component resolver, order-key writer, comparator, fingerprint,
-- boundary record, replay path, re-resolution procedure, costing, valuation, or
-- runtime consumer is created. Per specification §5.4, NO trigger is added to
-- inventory_events - the event-side 1:1 totality check belongs to M5, whose
-- writer is its precondition. M4 is therefore purely additive: inventory_events,
-- inventory_occurrences, the WP-1 tables, the WP-2 registry, the WP-3 stream
-- objects, Posting, and the Accounting Kernel are untouched.
--
-- Rollback (specification §6.3), in order:
--   step 1 - drop table public.inventory_event_order_keys
--   step 2 - drop function public.fn_ia5_guard_inventory_order_key_foundation()
-- The isolated rollback proof is test 110; its final transaction rollback
-- restores this M4-applied schema for subsequent work.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Mandatory fail-closed preconditions (specification §6.1). A failed
--    precondition is a governance stop, never permission to backfill, repair,
--    disable a trigger, or infer a value.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count BIGINT;
  v_table TEXT;
BEGIN
  -- (1) inventory_events exists and is empty.
  IF to_regclass('public.inventory_events') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: public.inventory_events is absent.';
  END IF;

  SELECT count(*) INTO v_count FROM public.inventory_events;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: inventory_events is non-zero (%); this is a governance stop, not a backfill.',
      v_count;
  END IF;

  -- (2) The WP-4 table does not already exist.
  IF to_regclass('public.inventory_event_order_keys') IS NOT NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: inventory_event_order_keys already exists.';
  END IF;

  -- (3) WP-1's six policy/version tables exist, remain empty, and retain their
  --     RLS, audit, immutability, and dormancy controls.
  FOREACH v_table IN ARRAY ARRAY[
    'inventory_event_order_policies',
    'inventory_event_effect_ranks',
    'inventory_source_type_ranks',
    'inventory_transition_ranks',
    'inventory_canonical_form_versions',
    'inventory_correction_graph_versions'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4 stop condition: WP-1 dependency public.% is absent.',
        v_table;
    END IF;

    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4 stop condition: WP-1 table public.% contains % persistent row(s); certification fixtures must not persist.',
        v_table, v_count;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_table AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4 stop condition: RLS is not enabled on public.%.', v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_table
        AND con.contype = 'c' AND con.convalidated
        AND pg_get_constraintdef(con.oid) ILIKE '%activation_state%dormant%'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4 stop condition: dormant activation CHECK is absent on public.%.',
        v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_namespace pn ON pn.oid = p.pronamespace
      WHERE t.tgrelid = to_regclass('public.' || v_table)
        AND NOT t.tgisinternal AND t.tgenabled = 'A'
        AND pn.nspname = 'public'
        AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4 stop condition: ENABLE ALWAYS immutability is absent on public.%.',
        v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_namespace pn ON pn.oid = p.pronamespace
      WHERE t.tgrelid = to_regclass('public.' || v_table)
        AND NOT t.tgisinternal
        AND pn.nspname = 'public' AND p.proname = 'fn_audit_trigger'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4 stop condition: the audit control is absent on public.%.',
        v_table;
    END IF;
  END LOOP;

  -- (4) WP-2's six registry columns exist with the exact certification row.
  SELECT count(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'ref_inventory_event_source_types'
    AND column_name IN (
      'event_effect_map',
      'document_order_key_algorithm',
      'line_order_authority',
      'occurrence_semantics',
      'same_time_class',
      'correction_placement_class'
    );
  IF v_count <> 6 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: the six WP-2 registry columns are not present (% found).',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.ref_inventory_event_source_types
  WHERE source_document_type = 'IA5_CERTIFICATION'
    AND owner_engine = 'Inventory'
    AND is_certification_only
    AND NOT is_production_enabled
    AND removal_phase = 'IA-6'
    AND event_effect_map =
      '{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}'::jsonb
    AND document_order_key_algorithm = 'canonical_source_document_id'
    AND line_order_authority = 'immutable_source_line_ordinal'
    AND occurrence_semantics = 'explicit_partial_occurrences'
    AND same_time_class = 'event_effect_map'
    AND correction_placement_class = 'base';
  IF v_count <> 1
     OR (SELECT count(*) FROM public.ref_inventory_event_source_types) <> 1 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: the registry is not the single exact IA5_CERTIFICATION authority row.';
  END IF;

  -- (5) WP-3's stream objects exist, remain empty, and retain their controls.
  IF to_regclass('public.inventory_valuation_streams') IS NULL
     OR to_regclass('public.inventory_valuation_stream_sequences') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: a WP-3 stream object is absent.';
  END IF;

  IF (SELECT count(*) FROM public.inventory_valuation_streams) <> 0
     OR (SELECT count(*) FROM public.inventory_valuation_stream_sequences) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: a WP-3 stream object contains persistent rows.';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c
  WHERE c.oid IN (
      'public.inventory_valuation_streams'::regclass,
      'public.inventory_valuation_stream_sequences'::regclass
    )
    AND c.relrowsecurity;
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: RLS is not retained on both WP-3 stream objects (% found).',
      v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.inventory_valuation_streams'::regclass
      AND conname = 'inventory_valuation_streams_activation_state_check'
      AND contype = 'c' AND convalidated
      AND pg_get_constraintdef(oid) ILIKE '%activation_state%dormant%'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: WP-3 stream dormancy control is absent or changed.';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND (
      (tablename = 'inventory_valuation_streams'
       AND policyname = 'inventory_valuation_streams_read')
      OR
      (tablename = 'inventory_valuation_stream_sequences'
       AND policyname = 'inventory_valuation_stream_sequences_read')
    )
    AND cmd = 'SELECT'
    AND roles::text = '{authenticated}'
    AND qual = 'is_company_member(company_id)';
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: a WP-3 stream read policy is absent or changed (% found).',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace pn ON pn.oid = p.pronamespace
  WHERE NOT t.tgisinternal
    AND pn.nspname = 'public'
    AND (
      (t.tgrelid = 'public.inventory_valuation_streams'::regclass
       AND t.tgname = 'aa_inventory_valuation_streams_guard'
       AND p.proname = 'fn_ia5_guard_inventory_stream_foundation'
       AND t.tgenabled = 'O' AND t.tgtype = 23)
      OR
      (t.tgrelid = 'public.inventory_valuation_streams'::regclass
       AND t.tgname = 'trg_inventory_valuation_streams_audit'
       AND p.proname = 'fn_audit_trigger'
       AND t.tgenabled = 'O' AND t.tgtype = 5)
      OR
      (t.tgrelid = 'public.inventory_valuation_streams'::regclass
       AND t.tgname = 'zz_inventory_valuation_streams_immutable'
       AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
       AND t.tgenabled = 'A' AND t.tgtype = 27)
      OR
      (t.tgrelid = 'public.inventory_valuation_stream_sequences'::regclass
       AND t.tgname = 'aa_inventory_valuation_stream_sequences_guard'
       AND p.proname = 'fn_ia5_guard_inventory_stream_foundation'
       AND t.tgenabled = 'A' AND t.tgtype = 31)
      OR
      (t.tgrelid = 'public.inventory_valuation_stream_sequences'::regclass
       AND t.tgname = 'trg_inventory_valuation_stream_sequences_audit'
       AND p.proname = 'fn_audit_trigger'
       AND t.tgenabled = 'O' AND t.tgtype = 5)
    );
  IF v_count <> 5 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: the WP-3 stream trigger controls are absent or changed (% found).',
      v_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND table_name IN (
        'inventory_valuation_streams',
        'inventory_valuation_stream_sequences'
      )
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: a WP-3 stream object exposes a client/service write privilege.';
  END IF;

  -- (6) Every foreign-key target exists.
  IF to_regclass('public.companies') IS NULL
     OR to_regclass('auth.users') IS NULL
     OR to_regclass('public.inventory_events') IS NULL
     OR to_regclass('public.inventory_valuation_streams') IS NULL
     OR to_regclass('public.inventory_event_order_policies') IS NULL
     OR to_regclass('public.ref_inventory_event_source_types') IS NULL
     OR to_regclass('public.inventory_canonical_form_versions') IS NULL
     OR to_regclass('public.inventory_valuation_scopes') IS NULL
     OR to_regclass('public.inventory_correction_graph_versions') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 stop condition: a required foreign-key target is absent.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. The persisted ECC order key (design §6.3; specification §2).
--    Thirty-one columns. Immutable in every economic, identity, and version
--    column; only resolution_state may change, and only current -> superseded
--    (specification §3). No dormancy column: this is a per-event sidecar and
--    inherits dormancy from inventory_events (specification §4).
-- ---------------------------------------------------------------------------
CREATE TABLE public.inventory_event_order_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_event_id UUID NOT NULL
    REFERENCES public.inventory_events(id),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  valuation_stream_id UUID NOT NULL
    REFERENCES public.inventory_valuation_streams(id),

  -- E1, E3-E10 ordering components.
  economic_effective_at TIMESTAMPTZ NOT NULL,
  source_precision_code TEXT NOT NULL,
  economic_effect_class TEXT NOT NULL,
  economic_effect_rank SMALLINT NOT NULL,
  source_type_rank SMALLINT NOT NULL,
  document_order_key BYTEA NOT NULL,
  source_line_ordinal INTEGER NOT NULL,
  transition_rank SMALLINT NOT NULL,
  occurrence_ordinal BIGINT NOT NULL,
  event_ordinal INTEGER NOT NULL,
  canonical_source_identity BYTEA NOT NULL,

  -- X1-X4 correction components.
  correction_placement_class TEXT NOT NULL,
  correction_chain_depth INTEGER NOT NULL,
  correction_effective_at TIMESTAMPTZ NOT NULL,
  correction_approved_at TIMESTAMPTZ NOT NULL,
  correction_identity BYTEA NOT NULL,
  correction_root_event_id UUID
    REFERENCES public.inventory_events(id),

  -- The version vector V (P-06). Element 2 is the registry's real key
  -- (specification §2.5): ref_inventory_event_source_types is keyed by
  -- source_document_type TEXT and carries no uuid version identifier.
  order_policy_version_id UUID NOT NULL
    REFERENCES public.inventory_event_order_policies(id),
  registry_source_document_type TEXT NOT NULL
    REFERENCES public.ref_inventory_event_source_types(source_document_type),
  canonical_form_version_id UUID NOT NULL
    REFERENCES public.inventory_canonical_form_versions(id),
  scope_resolution_version_id UUID NOT NULL
    REFERENCES public.inventory_valuation_scopes(id),
  correction_graph_version_id UUID NOT NULL
    REFERENCES public.inventory_correction_graph_versions(id),

  -- Canonical serialisation and its digest. Deliberately NOT generated:
  -- ADR-C01 §6.3 bars database-derived ordering inputs, so the M5 resolver
  -- supplies both and only the digest length is constrained here.
  canonical_key_bytes BYTEA NOT NULL,
  ecc_key_digest BYTEA NOT NULL,

  -- The one mutable column (specification §3).
  resolution_state TEXT NOT NULL DEFAULT 'current',

  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

  CONSTRAINT inventory_event_order_keys_identity_uq
    UNIQUE (valuation_stream_id, canonical_key_bytes),
  CONSTRAINT inventory_event_order_keys_economic_effect_class_check
    CHECK (economic_effect_class = ANY (ARRAY[
      'opening', 'increase', 'value_only', 'decrease', 'allowance'])),
  CONSTRAINT inventory_event_order_keys_economic_effect_rank_check
    CHECK (economic_effect_rank > 0),
  CONSTRAINT inventory_event_order_keys_source_type_rank_check
    CHECK (source_type_rank > 0),
  CONSTRAINT inventory_event_order_keys_source_line_ordinal_check
    CHECK (source_line_ordinal > 0),
  CONSTRAINT inventory_event_order_keys_transition_rank_check
    CHECK (transition_rank > 0),
  CONSTRAINT inventory_event_order_keys_occurrence_ordinal_check
    CHECK (occurrence_ordinal > 0),
  CONSTRAINT inventory_event_order_keys_event_ordinal_check
    CHECK (event_ordinal > 0),
  CONSTRAINT inventory_event_order_keys_correction_placement_class_check
    CHECK (correction_placement_class = ANY (ARRAY[
      'base', 'anchored', 'independent', 'counterfactual_only'])),
  CONSTRAINT inventory_event_order_keys_correction_chain_depth_check
    CHECK (correction_chain_depth >= 0),
  CONSTRAINT inventory_event_order_keys_correction_root_check
    CHECK ((correction_chain_depth = 0 AND correction_root_event_id IS NULL)
        OR (correction_chain_depth > 0 AND correction_root_event_id IS NOT NULL)),
  CONSTRAINT inventory_event_order_keys_ecc_key_digest_check
    CHECK (octet_length(ecc_key_digest) = 32),
  CONSTRAINT inventory_event_order_keys_resolution_state_check
    CHECK (resolution_state = ANY (ARRAY['current', 'superseded']))
);

-- ---------------------------------------------------------------------------
-- 3. Indexes (design §18; specification §2.6). E2 is intentionally absent from
--    the ECC scan: causal depth is population-derived and cannot be indexed.
-- ---------------------------------------------------------------------------
CREATE INDEX inventory_event_order_keys_ecc_idx
  ON public.inventory_event_order_keys (
    valuation_stream_id,
    economic_effective_at,
    economic_effect_rank,
    source_type_rank,
    document_order_key,
    source_line_ordinal,
    transition_rank,
    occurrence_ordinal,
    event_ordinal,
    canonical_source_identity,
    correction_chain_depth,
    correction_effective_at,
    correction_approved_at,
    correction_identity
  );

CREATE UNIQUE INDEX inventory_event_order_keys_event_current_uq
  ON public.inventory_event_order_keys (inventory_event_id)
  WHERE resolution_state = 'current';

CREATE INDEX inventory_event_order_keys_anchor_idx
  ON public.inventory_event_order_keys
     (correction_root_event_id, correction_chain_depth);

CREATE INDEX inventory_event_order_keys_version_idx
  ON public.inventory_event_order_keys
     (valuation_stream_id, order_policy_version_id, canonical_form_version_id);

-- ---------------------------------------------------------------------------
-- 4. The single new WP-4 guard function (specification §5.3). It must be a NEW
--    function, not an edit of an existing guard: the WP-1 and WP-3 precedent
--    preserving design §25 / risk R-15 ("nothing existing is altered").
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ia5_guard_inventory_order_key_foundation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_event_company UUID;
  v_stream_company UUID;
  v_root_company UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_company := OLD.company_id;
  ELSE
    v_company := NEW.company_id;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(TG_TABLE_NAME || ':' || v_company::text, 0)
  );

  -- §5.3 rule 1: an issued order key is permanent evidence.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4: order keys are permanent evidence; DELETE is rejected'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- §5.3 rule 2: every column except resolution_state is immutable.
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.inventory_event_id IS DISTINCT FROM OLD.inventory_event_id
       OR NEW.company_id IS DISTINCT FROM OLD.company_id
       OR NEW.valuation_stream_id IS DISTINCT FROM OLD.valuation_stream_id
       OR NEW.economic_effective_at IS DISTINCT FROM OLD.economic_effective_at
       OR NEW.source_precision_code IS DISTINCT FROM OLD.source_precision_code
       OR NEW.economic_effect_class IS DISTINCT FROM OLD.economic_effect_class
       OR NEW.economic_effect_rank IS DISTINCT FROM OLD.economic_effect_rank
       OR NEW.source_type_rank IS DISTINCT FROM OLD.source_type_rank
       OR NEW.document_order_key IS DISTINCT FROM OLD.document_order_key
       OR NEW.source_line_ordinal IS DISTINCT FROM OLD.source_line_ordinal
       OR NEW.transition_rank IS DISTINCT FROM OLD.transition_rank
       OR NEW.occurrence_ordinal IS DISTINCT FROM OLD.occurrence_ordinal
       OR NEW.event_ordinal IS DISTINCT FROM OLD.event_ordinal
       OR NEW.canonical_source_identity IS DISTINCT FROM OLD.canonical_source_identity
       OR NEW.correction_placement_class IS DISTINCT FROM OLD.correction_placement_class
       OR NEW.correction_chain_depth IS DISTINCT FROM OLD.correction_chain_depth
       OR NEW.correction_effective_at IS DISTINCT FROM OLD.correction_effective_at
       OR NEW.correction_approved_at IS DISTINCT FROM OLD.correction_approved_at
       OR NEW.correction_identity IS DISTINCT FROM OLD.correction_identity
       OR NEW.correction_root_event_id IS DISTINCT FROM OLD.correction_root_event_id
       OR NEW.order_policy_version_id IS DISTINCT FROM OLD.order_policy_version_id
       OR NEW.registry_source_document_type IS DISTINCT FROM OLD.registry_source_document_type
       OR NEW.canonical_form_version_id IS DISTINCT FROM OLD.canonical_form_version_id
       OR NEW.scope_resolution_version_id IS DISTINCT FROM OLD.scope_resolution_version_id
       OR NEW.correction_graph_version_id IS DISTINCT FROM OLD.correction_graph_version_id
       OR NEW.canonical_key_bytes IS DISTINCT FROM OLD.canonical_key_bytes
       OR NEW.ecc_key_digest IS DISTINCT FROM OLD.ecc_key_digest
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4: order-key components are immutable; only resolution_state may change'
        USING ERRCODE = '23514';
    END IF;

    -- §5.3 rule 3: the only permitted transition is current -> superseded.
    IF NEW.resolution_state IS DISTINCT FROM OLD.resolution_state
       AND NOT (OLD.resolution_state = 'current'
                AND NEW.resolution_state = 'superseded') THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4: resolution_state may only move from current to superseded'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  -- §5.3 rule 4: company consistency with the referenced event.
  SELECT e.company_id INTO v_event_company
  FROM public.inventory_events e WHERE e.id = NEW.inventory_event_id;
  IF v_event_company IS DISTINCT FROM NEW.company_id THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4: order-key company % does not match its event company %',
      NEW.company_id, v_event_company
      USING ERRCODE = '23514';
  END IF;

  -- §5.3 rule 5: company consistency with the referenced stream.
  SELECT s.company_id INTO v_stream_company
  FROM public.inventory_valuation_streams s
  WHERE s.id = NEW.valuation_stream_id;
  IF v_stream_company IS DISTINCT FROM NEW.company_id THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4: order-key company % does not match its stream company %',
      NEW.company_id, v_stream_company
      USING ERRCODE = '23514';
  END IF;

  -- §5.3 rule 6: an anchored correction root must be in the same company.
  IF NEW.correction_root_event_id IS NOT NULL THEN
    SELECT e.company_id INTO v_root_company
    FROM public.inventory_events e WHERE e.id = NEW.correction_root_event_id;
    IF v_root_company IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-4: correction root event belongs to company %, not company %',
        v_root_company, NEW.company_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Triggers (specification §5.2). Exactly two. The aa_/trg_ prefixes are
--    load-bearing: PostgreSQL fires triggers in name order, so validation runs
--    before audit. No immutability trigger is attached - the guard discharges
--    that role and is stricter (specification §3.2).
-- ---------------------------------------------------------------------------
CREATE TRIGGER aa_inventory_event_order_keys_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.inventory_event_order_keys
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_ia5_guard_inventory_order_key_foundation();
ALTER TABLE public.inventory_event_order_keys
  ENABLE ALWAYS TRIGGER aa_inventory_event_order_keys_guard;

CREATE TRIGGER trg_inventory_event_order_keys_audit
  AFTER INSERT ON public.inventory_event_order_keys
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

-- ---------------------------------------------------------------------------
-- 6. RLS, policy, and privileges (design §19; specification §5.5).
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_event_order_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY inventory_event_order_keys_read
  ON public.inventory_event_order_keys
  FOR SELECT TO authenticated
  USING (public.is_company_member(company_id));
REVOKE ALL ON TABLE public.inventory_event_order_keys
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.inventory_event_order_keys
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_ia5_guard_inventory_order_key_foundation()
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Dormancy documentation (design §21; specification §4).
-- ---------------------------------------------------------------------------
COMMENT ON TABLE public.inventory_event_order_keys IS
  'Dormant IA-5 ECC order key (WP-4). Persists the 14 ordering components, '
  'their canonical serialisation, and its sha256 digest for one event under '
  'one resolution. Per-event sidecar: dormancy is inherited from '
  'inventory_events, so no dormancy column is carried - the certified '
  'inventory_event_values / inventory_event_source_links precedent. Immutable '
  'in every economic, identity, and version column; only resolution_state may '
  'change, and only current -> superseded. Created empty; no consumer and no '
  'write grant. The writer is M5/WP-5.';
COMMENT ON FUNCTION public.fn_ia5_guard_inventory_order_key_foundation() IS
  'IA-5 ECC WP-4 order-key guard. Rejects DELETE; rejects any UPDATE touching a '
  'column other than resolution_state; permits only the current -> superseded '
  'transition; enforces company consistency with the referenced event, stream, '
  'and correction root.';

-- ---------------------------------------------------------------------------
-- 8. Persistent postconditions (specification §6.2). Structural and
--    registry-local only; all fixture resolution belongs to rolled-back tests.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count BIGINT;
BEGIN
  -- Exact shape.
  SELECT count(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'inventory_event_order_keys';
  IF v_count <> 31 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: inventory_event_order_keys must have exactly 31 columns (% found).',
      v_count;
  END IF;

  -- The table must NOT carry a dormancy column (specification §4).
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'inventory_event_order_keys'
      AND column_name IN ('activation_state', 'foundation_state')
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the order key must not carry a dormancy column (specification §4).';
  END IF;

  -- The 24 governed keys and constraints.
  SELECT count(*) INTO v_count
  FROM pg_constraint
  WHERE conrelid = 'public.inventory_event_order_keys'::regclass
    AND conname IN (
      'inventory_event_order_keys_pkey',
      'inventory_event_order_keys_identity_uq',
      'inventory_event_order_keys_inventory_event_id_fkey',
      'inventory_event_order_keys_company_id_fkey',
      'inventory_event_order_keys_valuation_stream_id_fkey',
      'inventory_event_order_keys_correction_root_event_id_fkey',
      'inventory_event_order_keys_order_policy_version_id_fkey',
      'inventory_event_order_keys_registry_source_document_type_fkey',
      'inventory_event_order_keys_canonical_form_version_id_fkey',
      'inventory_event_order_keys_scope_resolution_version_id_fkey',
      'inventory_event_order_keys_correction_graph_version_id_fkey',
      'inventory_event_order_keys_created_by_fkey',
      'inventory_event_order_keys_economic_effect_class_check',
      'inventory_event_order_keys_economic_effect_rank_check',
      'inventory_event_order_keys_source_type_rank_check',
      'inventory_event_order_keys_source_line_ordinal_check',
      'inventory_event_order_keys_transition_rank_check',
      'inventory_event_order_keys_occurrence_ordinal_check',
      'inventory_event_order_keys_event_ordinal_check',
      'inventory_event_order_keys_correction_placement_class_check',
      'inventory_event_order_keys_correction_chain_depth_check',
      'inventory_event_order_keys_correction_root_check',
      'inventory_event_order_keys_ecc_key_digest_check',
      'inventory_event_order_keys_resolution_state_check'
    );
  IF v_count <> 24 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the 24 governed keys/constraints are not all present (% found).',
      v_count;
  END IF;

  -- The four indexes plus the two constraint-backed unique indexes.
  SELECT count(*) INTO v_count
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND tablename = 'inventory_event_order_keys'
    AND indexname IN (
      'inventory_event_order_keys_ecc_idx',
      'inventory_event_order_keys_event_current_uq',
      'inventory_event_order_keys_anchor_idx',
      'inventory_event_order_keys_version_idx'
    );
  IF v_count <> 4 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the four governed indexes are not all present (% found).',
      v_count;
  END IF;

  -- Exactly two triggers, with the guard at ENABLE ALWAYS and no blanket
  -- immutability trigger (specification §3.2, §5.2).
  SELECT count(*) INTO v_count
  FROM pg_trigger
  WHERE tgrelid = 'public.inventory_event_order_keys'::regclass
    AND NOT tgisinternal;
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: exactly two triggers are authorised (% found).',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace pn ON pn.oid = p.pronamespace
  WHERE t.tgrelid = 'public.inventory_event_order_keys'::regclass
    AND NOT t.tgisinternal
    AND pn.nspname = 'public'
    AND (
      (t.tgname = 'aa_inventory_event_order_keys_guard'
       AND p.proname = 'fn_ia5_guard_inventory_order_key_foundation'
       AND t.tgenabled = 'A' AND t.tgtype = 31)
      OR
      (t.tgname = 'trg_inventory_event_order_keys_audit'
       AND p.proname = 'fn_audit_trigger'
       AND t.tgenabled = 'O' AND t.tgtype = 5)
    );
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the two governed triggers do not have their exact timing, events, functions, and enablement (% found).',
      v_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.inventory_event_order_keys'::regclass
      AND NOT t.tgisinternal
      AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the blanket immutability trigger must not be attached (specification §3.2).';
  END IF;

  -- Created empty; inventory_events untouched.
  IF (SELECT count(*) FROM public.inventory_event_order_keys) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the order-key table must be created empty.';
  END IF;

  IF (SELECT count(*) FROM public.inventory_events) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: inventory_events changed.';
  END IF;

  -- RLS, the single read policy, and SELECT-only client/service grants.
  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid = 'public.inventory_event_order_keys'::regclass
      AND relrowsecurity
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: RLS is not enabled on the order-key table.';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'inventory_event_order_keys';
  IF v_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'inventory_event_order_keys'
      AND policyname = 'inventory_event_order_keys_read'
      AND cmd = 'SELECT'
      AND roles::text = '{authenticated}'
      AND qual = 'is_company_member(company_id)'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the single governed read policy is absent or changed.';
  END IF;

  SELECT count(*) INTO v_count
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'inventory_event_order_keys'
    AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role');
  IF v_count <> 2
     OR NOT EXISTS (
       SELECT 1 FROM information_schema.role_table_grants
       WHERE table_schema = 'public'
         AND table_name = 'inventory_event_order_keys'
         AND grantee = 'authenticated' AND privilege_type = 'SELECT'
     )
     OR NOT EXISTS (
       SELECT 1 FROM information_schema.role_table_grants
       WHERE table_schema = 'public'
         AND table_name = 'inventory_event_order_keys'
         AND grantee = 'service_role' AND privilege_type = 'SELECT'
     ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: client/service table grants are not SELECT-only.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public'
      AND routine_name = 'fn_ia5_guard_inventory_order_key_foundation'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the guard function exposes EXECUTE.';
  END IF;

  -- No trigger was added to inventory_events (specification §5.4). The
  -- certified trigger set is exactly three.
  SELECT count(*) INTO v_count
  FROM pg_trigger
  WHERE tgrelid = 'public.inventory_events'::regclass AND NOT tgisinternal;
  IF v_count <> 3 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the inventory_events trigger set changed (% found, expected 3).',
      v_count;
  END IF;

  -- No client/service write privilege.
  IF EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND table_name = 'inventory_event_order_keys'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: the order key exposes a client/service write privilege.';
  END IF;

  -- No runtime consumer.
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
      AND p.proname <> 'fn_ia5_guard_inventory_order_key_foundation'
      AND pg_get_functiondef(p.oid) ~ 'inventory_event_order_keys'
  ) OR EXISTS (
    SELECT 1 FROM pg_views
    WHERE schemaname = 'public' AND definition ~ 'inventory_event_order_keys'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-4 postcondition failed: a runtime function or view consumes the order-key table.';
  END IF;
END;
$$;

COMMIT;
