-- =============================================================================
-- IA-5 Economic Costing Chronology Hardening — Work Package 3 (M3)
-- Stream partition + stream-keyed accepted allocator (dormant, additive,
-- reversible)
--
-- Authority:
--   * ADR-C01 (frozen) — §5(3) accepted/economic authority separation; §6.3
--     prohibition on database-allocated ordering (satisfied by exclusion)
--   * ECC-01 (accepted, owner approved) — §15(2) accepted sequence preserved and
--     demoted; §15(4) partition key moves from scope version to scope key; V-11
--   * IA-5 ECC Hardening Implementation Design §6.2, §6.2.1, §17 M3, §18, §19,
--     §20, §21, §23.2, §24 WP-3, §25
--   * IA-5 WP-3 Detailed Stream and Allocator Specification (EA-003/EA-004/
--     EA-005) §2, §3, §4, §8, §9, §10
--   * WP-3 Final Authorisation Verdict (2026-07-30) — Outcome A
--
-- Scope (WP-3 only): create exactly two dormant tables and their authorised
-- controls. No stream resolver, allocator function, order key, comparator,
-- fingerprint, replay path, index on any ECC object, or runtime consumer is
-- created; inventory_events, inventory_valuation_scopes,
-- inventory_valuation_scope_sequences, ref_inventory_event_source_types, the
-- WP-1 tables, Posting, and the Accounting Kernel are untouched.
--
-- Rollback (spec §8.9), child before parent:
--   1. DROP TABLE public.inventory_valuation_stream_sequences
--   2. DROP TABLE public.inventory_valuation_streams
--   3. DROP FUNCTION public.fn_ia5_guard_inventory_stream_foundation()
-- The isolated rollback proof is test 108; its final transaction rollback
-- restores this M3-applied schema for subsequent work.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Mandatory fail-closed preconditions (spec §4.3). A failed precondition is
--    a governance stop, never permission to backfill, repair, or infer.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count BIGINT;
  v_table TEXT;
BEGIN
  -- (1) inventory_events exists and is empty.
  IF to_regclass('public.inventory_events') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 stop condition: public.inventory_events is absent.';
  END IF;

  SELECT count(*) INTO v_count FROM public.inventory_events;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 stop condition: inventory_events is non-zero (%); this is a governance stop, not a backfill.',
      v_count;
  END IF;

  -- (2) Neither WP-3 table already exists.
  IF to_regclass('public.inventory_valuation_streams') IS NOT NULL
     OR to_regclass('public.inventory_valuation_stream_sequences') IS NOT NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 stop condition: a WP-3 table already exists.';
  END IF;

  -- (3) WP-1's six policy/version tables exist, remain empty, and retain their
  --     RLS, dormancy, audit, and ENABLE ALWAYS immutability controls.
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
        'IA-5 ECC WP-3 stop condition: WP-1 dependency public.% is absent.',
        v_table;
    END IF;

    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3 stop condition: WP-1 table public.% contains % persistent row(s); certification fixtures must not persist.',
        v_table, v_count;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_table AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3 stop condition: RLS is not enabled on public.%.', v_table;
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
        'IA-5 ECC WP-3 stop condition: dormant activation CHECK is absent on public.%.',
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
        'IA-5 ECC WP-3 stop condition: ENABLE ALWAYS immutability is absent on public.%.',
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
      'IA-5 ECC WP-3 stop condition: the six WP-2 registry columns are not present (% found).',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.ref_inventory_event_source_types
  WHERE source_document_type = 'IA5_CERTIFICATION'
    AND is_certification_only
    AND NOT is_production_enabled;
  IF v_count <> 1
     OR (SELECT count(*) FROM public.ref_inventory_event_source_types) <> 1 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 stop condition: the registry is not the single exact IA5_CERTIFICATION authority row.';
  END IF;

  -- (5) The legacy scope objects exist and are untouched by this migration.
  IF to_regclass('public.inventory_valuation_scopes') IS NULL
     OR to_regclass('public.inventory_valuation_scope_sequences') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 stop condition: a legacy valuation-scope object is absent.';
  END IF;

  -- (6) Foreign-key targets exist.
  IF to_regclass('public.companies') IS NULL
     OR to_regclass('public.items') IS NULL
     OR to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 stop condition: a required foreign-key target is absent.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. The permanent partition identity (design §6.2; spec §8).
--    Immutable, dormancy-checked, company-scoped, version-free by construction.
-- ---------------------------------------------------------------------------
CREATE TABLE public.inventory_valuation_streams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  item_id UUID NOT NULL REFERENCES public.items(id),
  scope_code TEXT NOT NULL,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_valuation_streams_key_uq
    UNIQUE (company_id, item_id, scope_code)
);

-- ---------------------------------------------------------------------------
-- 3. The stream-keyed accepted allocator (design §6.2.1; spec §2, §3).
--    Partially mutable by design: last_sequence advances forward-only; identity
--    columns are frozen; DELETE is rejected. No dormancy CHECK and no
--    immutability trigger — both would break allocation (spec §3.2, §3.3).
-- ---------------------------------------------------------------------------
CREATE TABLE public.inventory_valuation_stream_sequences (
  valuation_stream_id UUID PRIMARY KEY
    REFERENCES public.inventory_valuation_streams(id),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  last_sequence BIGINT NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- ---------------------------------------------------------------------------
-- 4. The single new WP-3 guard function (spec §8.6). It must be a NEW function,
--    not an edit of an existing guard: WP-1 set that precedent to preserve
--    design §25 / risk R-15 ("nothing existing is altered").
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ia5_guard_inventory_stream_foundation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_item_company UUID;
  v_stream_company UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_company := OLD.company_id;
  ELSE
    v_company := NEW.company_id;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(TG_TABLE_NAME || ':' || v_company::text, 0)
  );

  IF TG_TABLE_NAME = 'inventory_valuation_streams' THEN
    -- spec §8.4(1) company exists
    IF NOT EXISTS (
      SELECT 1 FROM public.companies c WHERE c.id = NEW.company_id
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3: valuation stream company % does not exist',
        NEW.company_id;
    END IF;

    -- spec §8.4(2) company match with item
    SELECT i.company_id INTO v_item_company
    FROM public.items i WHERE i.id = NEW.item_id;
    IF v_item_company IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3: valuation stream item % belongs to company %, not company %',
        NEW.item_id, v_item_company, NEW.company_id;
    END IF;

    -- spec §8.4(3) scope_code resolves to at least one scope version
    IF NOT EXISTS (
      SELECT 1 FROM public.inventory_valuation_scopes s
      WHERE s.company_id = NEW.company_id
        AND s.item_id = NEW.item_id
        AND s.scope_code = NEW.scope_code
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3: valuation stream scope_code % resolves to no scope version for company %/item %',
        NEW.scope_code, NEW.company_id, NEW.item_id;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_valuation_stream_sequences' THEN
    -- spec §3.1 deletion is prohibited: a consumed accepted position must never
    -- become reissuable.
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3: accepted-sequence allocator rows are permanent; DELETE is rejected';
    END IF;

    IF TG_OP = 'UPDATE' THEN
      -- spec §3.1 identity columns are immutable
      IF NEW.valuation_stream_id IS DISTINCT FROM OLD.valuation_stream_id
         OR NEW.company_id IS DISTINCT FROM OLD.company_id THEN
        RAISE EXCEPTION
          'IA-5 ECC WP-3: allocator identity columns (valuation_stream_id, company_id) are immutable';
      END IF;

      -- spec §3.1 forward-only counter
      IF NEW.last_sequence < OLD.last_sequence THEN
        RAISE EXCEPTION
          'IA-5 ECC WP-3: accepted sequence counters cannot move backward; issued positions are never reusable';
      END IF;
    END IF;

    -- spec §3.4 company consistency with the referenced stream
    SELECT s.company_id INTO v_stream_company
    FROM public.inventory_valuation_streams s
    WHERE s.id = NEW.valuation_stream_id;
    IF v_stream_company IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-3: allocator company % does not match its stream company %',
        NEW.company_id, v_stream_company;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Triggers (spec §8.5 for the stream; §3.2 and §3.7 for the allocator).
--    aa_/trg_/zz_ prefixes are load-bearing: PostgreSQL fires triggers in name
--    order, so validation runs first and the immutability reject runs last.
-- ---------------------------------------------------------------------------
CREATE TRIGGER aa_inventory_valuation_streams_guard
  BEFORE INSERT OR UPDATE ON public.inventory_valuation_streams
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_ia5_guard_inventory_stream_foundation();

CREATE TRIGGER trg_inventory_valuation_streams_audit
  AFTER INSERT ON public.inventory_valuation_streams
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER zz_inventory_valuation_streams_immutable
  BEFORE UPDATE OR DELETE ON public.inventory_valuation_streams
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_ia5_reject_immutable_inventory_fact();
ALTER TABLE public.inventory_valuation_streams
  ENABLE ALWAYS TRIGGER zz_inventory_valuation_streams_immutable;

-- The allocator carries no immutability trigger (spec §3.2). Its dedicated
-- partial-mutability guard is ENABLE ALWAYS and covers DELETE.
CREATE TRIGGER aa_inventory_valuation_stream_sequences_guard
  BEFORE INSERT OR UPDATE OR DELETE
  ON public.inventory_valuation_stream_sequences
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_ia5_guard_inventory_stream_foundation();
ALTER TABLE public.inventory_valuation_stream_sequences
  ENABLE ALWAYS TRIGGER aa_inventory_valuation_stream_sequences_guard;

CREATE TRIGGER trg_inventory_valuation_stream_sequences_audit
  AFTER INSERT ON public.inventory_valuation_stream_sequences
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

-- ---------------------------------------------------------------------------
-- 6. RLS, policies, and privileges (design §19; spec §8.7, §3.6).
-- ---------------------------------------------------------------------------
ALTER TABLE public.inventory_valuation_streams ENABLE ROW LEVEL SECURITY;
CREATE POLICY inventory_valuation_streams_read
  ON public.inventory_valuation_streams
  FOR SELECT TO authenticated
  USING (public.is_company_member(company_id));
REVOKE ALL ON TABLE public.inventory_valuation_streams
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.inventory_valuation_streams
  TO authenticated, service_role;

ALTER TABLE public.inventory_valuation_stream_sequences
  ENABLE ROW LEVEL SECURITY;
CREATE POLICY inventory_valuation_stream_sequences_read
  ON public.inventory_valuation_stream_sequences
  FOR SELECT TO authenticated
  USING (public.is_company_member(company_id));
REVOKE ALL ON TABLE public.inventory_valuation_stream_sequences
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.inventory_valuation_stream_sequences
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_ia5_guard_inventory_stream_foundation()
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Dormancy documentation (design §21).
-- ---------------------------------------------------------------------------
COMMENT ON TABLE public.inventory_valuation_streams IS
  'Dormant IA-5 ECC valuation-stream partition identity (WP-3). One permanent '
  'partition per valuation-scope KEY so a scope re-version never splits or '
  'restarts a stream (ECC-01 §15(4), V-11). Immutable, dormancy-checked, '
  'created empty; no consumer and no write grant.';
COMMENT ON TABLE public.inventory_valuation_stream_sequences IS
  'Dormant IA-5 ECC stream-keyed accepted-sequence allocator (WP-3). Accepted '
  'Event Chronology counter only — contributes no ECC component (design §2.2, '
  '§7). Partially mutable by design: last_sequence advances forward-only, '
  'identity columns are frozen, DELETE is rejected. Created empty; the writer '
  'is M5/WP-5.';
COMMENT ON FUNCTION public.fn_ia5_guard_inventory_stream_foundation() IS
  'IA-5 ECC WP-3 foundation guard. Streams: company existence, item/company '
  'match, scope_code resolution. Allocator: DELETE rejection, identity '
  'immutability, forward-only counter, stream/company consistency.';

-- ---------------------------------------------------------------------------
-- 8. Persistent postconditions. Structural and registry-local only; all
--    cross-object fixture resolution belongs to rolled-back test evidence.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count BIGINT;
BEGIN
  -- Exact stream shape.
  SELECT count(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'inventory_valuation_streams';
  IF v_count <> 7 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: inventory_valuation_streams must have exactly 7 columns (% found).',
      v_count;
  END IF;

  -- Exact allocator shape.
  SELECT count(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'inventory_valuation_stream_sequences';
  IF v_count <> 4 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: inventory_valuation_stream_sequences must have exactly 4 columns (% found).',
      v_count;
  END IF;

  -- Governed constraint identifiers.
  SELECT count(*) INTO v_count
  FROM pg_constraint
  WHERE conname IN (
    'inventory_valuation_streams_pkey',
    'inventory_valuation_streams_key_uq',
    'inventory_valuation_streams_activation_state_check',
    'inventory_valuation_streams_company_id_fkey',
    'inventory_valuation_streams_item_id_fkey',
    'inventory_valuation_streams_created_by_fkey',
    'inventory_valuation_stream_sequences_pkey',
    'inventory_valuation_stream_sequences_last_sequence_check',
    'inventory_valuation_stream_sequences_company_id_fkey',
    'inventory_valuation_stream_sequences_valuation_stream_id_fkey'
  )
    AND conrelid IN (
      'public.inventory_valuation_streams'::regclass,
      'public.inventory_valuation_stream_sequences'::regclass
    );
  IF v_count <> 10 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: the ten governed keys/constraints are not all present (% found).',
      v_count;
  END IF;

  -- The allocator must NOT carry a dormancy CHECK or an immutability trigger.
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'inventory_valuation_stream_sequences'
      AND column_name = 'activation_state'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: the allocator must not carry activation_state (spec §3.3).';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.inventory_valuation_stream_sequences'::regclass
      AND NOT t.tgisinternal
      AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: the allocator must not carry the immutability trigger (spec §3.2).';
  END IF;

  -- Both tables created empty; inventory_events untouched.
  IF (SELECT count(*) FROM public.inventory_valuation_streams) <> 0
     OR (SELECT count(*) FROM public.inventory_valuation_stream_sequences) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: WP-3 tables must be created empty.';
  END IF;

  IF (SELECT count(*) FROM public.inventory_events) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: inventory_events changed.';
  END IF;

  -- No client/service write privilege on either table.
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
      'IA-5 ECC WP-3 postcondition failed: a WP-3 table exposes a client/service write privilege.';
  END IF;

  -- No runtime consumer of either WP-3 table.
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
      AND p.proname <> 'fn_ia5_guard_inventory_stream_foundation'
      AND pg_get_functiondef(p.oid) ~
        '(inventory_valuation_streams|inventory_valuation_stream_sequences)'
  ) OR EXISTS (
    SELECT 1 FROM pg_views
    WHERE schemaname = 'public'
      AND definition ~
        '(inventory_valuation_streams|inventory_valuation_stream_sequences)'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: a runtime function or view consumes a WP-3 table.';
  END IF;

  -- The legacy scope allocator is untouched (design §3.1 passive supersession).
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.inventory_valuation_scope_sequences'::regclass
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-3 postcondition failed: the legacy scope allocator was altered.';
  END IF;
END;
$$;

COMMIT;
