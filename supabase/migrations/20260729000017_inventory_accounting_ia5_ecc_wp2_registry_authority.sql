-- =============================================================================
-- IA-5 Economic Costing Chronology Hardening — Work Package 2 (M2)
-- Dormant Event Source Registry authority extension
--
-- Authority:
--   * ADR-C01 (frozen)
--   * ECC-01 (accepted, owner approved)
--   * IA-5 ECC Hardening Implementation Design §17 M2 / §24 WP-2
--   * IA-5 WP-2 Detailed Registry Authority Specification, reconciled by
--     Engineering Amendments EA-001 and EA-002
--   * IA-5 ECC Hardening WP-2 Authorisation Report
--
-- Scope (WP-2 only): add six immutable, NOT NULL, no-persistent-default
-- authority columns and their governed CHECK constraints to the existing
-- one-row ref_inventory_event_source_types registry. Materialise only the
-- exact IA5_CERTIFICATION values. No table, function, event, policy/rank
-- fixture, runtime consumer, grant, Posting object, or Kernel object is added
-- or changed.
--
-- Rollback (while dormant and before any later dependency): acquire ACCESS
-- EXCLUSIVE, reassert the zero-event/single-certification-row preconditions,
-- and drop the six columns in reverse order:
--   correction_placement_class, same_time_class, occurrence_semantics,
--   line_order_authority, document_order_key_algorithm, event_effect_map.
-- The isolated rollback proof is test 106; its final transaction rollback
-- restores this M2-applied schema for subsequent work.
-- =============================================================================

BEGIN;

LOCK TABLE public.ref_inventory_event_source_types IN ACCESS EXCLUSIVE MODE;

-- ---------------------------------------------------------------------------
-- 1. Governance and dependency preconditions. A failure is a stop, never
--    permission to backfill, repair, delete, disable a trigger, or seed ranks.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count BIGINT;
  v_table TEXT;
BEGIN
  IF to_regclass('public.inventory_events') IS NULL THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: public.inventory_events is absent.';
  END IF;

  SELECT count(*) INTO v_count FROM public.inventory_events;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: inventory_events is non-zero (%); this is a governance stop, not a backfill.',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.ref_inventory_event_source_types;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: source registry row count must be 1, found %.',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.ref_inventory_event_source_types
  WHERE source_document_type = 'IA5_CERTIFICATION'
    AND owner_engine = 'Inventory'
    AND is_certification_only
    AND NOT is_production_enabled
    AND removal_phase = 'IA-6';
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: the sole registry row is not the exact retained IA5_CERTIFICATION authority.';
  END IF;

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
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: one or more WP-2 registry columns already exist (% found).',
      v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace pn ON pn.oid = p.pronamespace
    WHERE t.tgrelid = 'public.ref_inventory_event_source_types'::regclass
      AND t.tgname = 'zz_ref_inventory_event_source_types_immutable'
      AND NOT t.tgisinternal
      AND t.tgenabled = 'A'
      AND pn.nspname = 'public'
      AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: the registry ENABLE ALWAYS immutable trigger is absent or changed.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'ref_inventory_event_source_types'
      AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: registry RLS is not enabled.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'ref_inventory_event_source_types'
      AND policyname = 'ref_inventory_event_source_types_read'
      AND cmd = 'SELECT'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: registry read policy is absent or changed.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND table_name = 'ref_inventory_event_source_types'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 stop condition: registry has an unauthorised client/service write privilege.';
  END IF;

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
        'IA-5 ECC WP-2 stop condition: WP-1 dependency public.% is absent.',
        v_table;
    END IF;

    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: WP-1 table public.% contains % persistent row(s); certification fixtures must not persist.',
        v_table, v_count;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = v_table
        AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: RLS is not enabled on public.%.',
        v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = v_table
        AND column_name = 'activation_state'
        AND is_nullable = 'NO'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: dormant activation_state is absent on public.%.',
        v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = v_table
        AND con.contype = 'c'
        AND con.convalidated
        AND pg_get_constraintdef(con.oid) ILIKE '%activation_state%dormant%'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: dormant activation CHECK is absent on public.%.',
        v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_namespace pn ON pn.oid = p.pronamespace
      WHERE t.tgrelid = to_regclass('public.' || v_table)
        AND NOT t.tgisinternal
        AND t.tgenabled = 'A'
        AND pn.nspname = 'public'
        AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: ENABLE ALWAYS immutability is absent on public.%.',
        v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_namespace pn ON pn.oid = p.pronamespace
      WHERE t.tgrelid = to_regclass('public.' || v_table)
        AND NOT t.tgisinternal
        AND pn.nspname = 'public'
        AND p.proname = 'fn_audit_trigger'
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: insert audit trigger is absent on public.%.',
        v_table;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM information_schema.role_table_grants
      WHERE table_schema = 'public'
        AND table_name = v_table
        AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
        AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
    ) THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 stop condition: public.% has an unauthorised client/service write privilege.',
        v_table;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Add the six governed attributes. Constant defaults are migration-only
--    materialisation values for the sole existing row; they are removed below
--    before commit. No UPDATE is issued and the immutable trigger stays enabled.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ref_inventory_event_source_types
  ADD COLUMN event_effect_map JSONB NOT NULL
    DEFAULT '{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}'::jsonb,
  ADD COLUMN document_order_key_algorithm TEXT COLLATE "C" NOT NULL
    DEFAULT 'canonical_source_document_id',
  ADD COLUMN line_order_authority TEXT COLLATE "C" NOT NULL
    DEFAULT 'immutable_source_line_ordinal',
  ADD COLUMN occurrence_semantics TEXT COLLATE "C" NOT NULL
    DEFAULT 'explicit_partial_occurrences',
  ADD COLUMN same_time_class TEXT COLLATE "C" NOT NULL
    DEFAULT 'event_effect_map',
  ADD COLUMN correction_placement_class TEXT COLLATE "C" NOT NULL
    DEFAULT 'base',
  ADD CONSTRAINT ref_inventory_event_source_types_event_effect_map_ck
    CHECK (
      jsonb_typeof(event_effect_map) = 'object'
      AND event_effect_map <> '{}'::jsonb
      AND event_effect_map
            - ARRAY['quantity_increase', 'quantity_decrease', 'value_only']::text[]
          = '{}'::jsonb
      AND (
        NOT (event_effect_map ? 'quantity_increase')
        OR (
          jsonb_typeof(event_effect_map -> 'quantity_increase') = 'string'
          AND event_effect_map ->> 'quantity_increase' IN ('opening', 'increase')
        )
      )
      AND (
        NOT (event_effect_map ? 'quantity_decrease')
        OR (
          jsonb_typeof(event_effect_map -> 'quantity_decrease') = 'string'
          AND event_effect_map ->> 'quantity_decrease' = 'decrease'
        )
      )
      AND (
        NOT (event_effect_map ? 'value_only')
        OR (
          jsonb_typeof(event_effect_map -> 'value_only') = 'string'
          AND event_effect_map ->> 'value_only' IN ('value_only', 'allowance')
        )
      )
    ),
  ADD CONSTRAINT ref_inventory_event_source_types_doc_order_key_algorithm_ck
    CHECK (
      document_order_key_algorithm IN (
        'governed_business_sequence',
        'canonical_source_document_id'
      )
    ),
  ADD CONSTRAINT ref_inventory_event_source_types_line_order_authority_ck
    CHECK (line_order_authority = 'immutable_source_line_ordinal'),
  ADD CONSTRAINT ref_inventory_event_source_types_occurrence_semantics_ck
    CHECK (
      occurrence_semantics IN (
        'single_occurrence',
        'explicit_partial_occurrences'
      )
    ),
  ADD CONSTRAINT ref_inventory_event_source_types_same_time_class_ck
    CHECK (same_time_class = 'event_effect_map'),
  ADD CONSTRAINT ref_inventory_event_source_types_correction_placement_class_ck
    CHECK (
      correction_placement_class IN (
        'base',
        'anchored',
        'independent',
        'counterfactual_only'
      )
    );

ALTER TABLE public.ref_inventory_event_source_types
  ALTER COLUMN event_effect_map DROP DEFAULT,
  ALTER COLUMN document_order_key_algorithm DROP DEFAULT,
  ALTER COLUMN line_order_authority DROP DEFAULT,
  ALTER COLUMN occurrence_semantics DROP DEFAULT,
  ALTER COLUMN same_time_class DROP DEFAULT,
  ALTER COLUMN correction_placement_class DROP DEFAULT;

COMMENT ON COLUMN public.ref_inventory_event_source_types.event_effect_map IS
  'Dormant WP-2 Event Source Registry E3 effect-to-same-time-class authority.';
COMMENT ON COLUMN public.ref_inventory_event_source_types.document_order_key_algorithm IS
  'Dormant WP-2 E5 document-order-key algorithm selector; no key is materialised in WP-2.';
COMMENT ON COLUMN public.ref_inventory_event_source_types.line_order_authority IS
  'Dormant WP-2 E6 immutable source-line ordering authority.';
COMMENT ON COLUMN public.ref_inventory_event_source_types.occurrence_semantics IS
  'Dormant WP-2 E8/E9 occurrence model selector.';
COMMENT ON COLUMN public.ref_inventory_event_source_types.same_time_class IS
  'Dormant WP-2 E3 classification mechanism; exact event_effect_map lookup.';
COMMENT ON COLUMN public.ref_inventory_event_source_types.correction_placement_class IS
  'Dormant WP-2 ECC correction placement selector; IA5_CERTIFICATION is base.';

-- ---------------------------------------------------------------------------
-- 3. Persistent postconditions. These prove only schema/registry-local state;
--    E3/E4/E7 rank resolution belongs exclusively to rolled-back test fixtures.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count BIGINT;
  v_table TEXT;
BEGIN
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
    )
    AND is_nullable = 'NO'
    AND column_default IS NULL;
  IF v_count <> 6 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: all six columns must be NOT NULL with no persistent default (% conform).',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'ref_inventory_event_source_types'
    AND (
      (column_name = 'event_effect_map' AND data_type = 'jsonb')
      OR (
        column_name IN (
          'document_order_key_algorithm',
          'line_order_authority',
          'occurrence_semantics',
          'same_time_class',
          'correction_placement_class'
        )
        AND data_type = 'text'
        AND collation_name = 'C'
      )
    );
  IF v_count <> 6 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: column types or bytewise text collation differ from authority (% conform).',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_constraint con
  WHERE con.conrelid = 'public.ref_inventory_event_source_types'::regclass
    AND con.conname IN (
      'ref_inventory_event_source_types_event_effect_map_ck',
      'ref_inventory_event_source_types_doc_order_key_algorithm_ck',
      'ref_inventory_event_source_types_line_order_authority_ck',
      'ref_inventory_event_source_types_occurrence_semantics_ck',
      'ref_inventory_event_source_types_same_time_class_ck',
      'ref_inventory_event_source_types_correction_placement_class_ck'
    )
    AND con.contype = 'c'
    AND con.convalidated;
  IF v_count <> 6 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: the six governed validated CHECK constraints are not present (% found).',
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
  IF v_count <> 1 OR
     (SELECT count(*) FROM public.ref_inventory_event_source_types) <> 1 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: exact IA5_CERTIFICATION registry authority was not materialised.';
  END IF;

  IF (SELECT count(*) FROM public.inventory_events) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: inventory_events changed.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace pn ON pn.oid = p.pronamespace
    WHERE t.tgrelid = 'public.ref_inventory_event_source_types'::regclass
      AND t.tgname = 'zz_ref_inventory_event_source_types_immutable'
      AND NOT t.tgisinternal
      AND t.tgenabled = 'A'
      AND pn.nspname = 'public'
      AND p.proname = 'fn_ia5_reject_immutable_inventory_fact'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: registry immutability changed.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'ref_inventory_event_source_types'
      AND c.relrowsecurity
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'ref_inventory_event_source_types'
      AND policyname = 'ref_inventory_event_source_types_read'
      AND cmd = 'SELECT'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: registry RLS or read policy changed.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND table_name = 'ref_inventory_event_source_types'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: registry write privilege changed.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ~
        '(event_effect_map|document_order_key_algorithm|line_order_authority|occurrence_semantics|same_time_class|correction_placement_class)'
  ) OR EXISTS (
    SELECT 1
    FROM pg_views
    WHERE schemaname = 'public'
      AND definition ~
        '(event_effect_map|document_order_key_algorithm|line_order_authority|occurrence_semantics|same_time_class|correction_placement_class)'
  ) THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-2 postcondition failed: a runtime function or view consumes WP-2 authority.';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'inventory_event_order_policies',
    'inventory_event_effect_ranks',
    'inventory_source_type_ranks',
    'inventory_transition_ranks',
    'inventory_canonical_form_versions',
    'inventory_correction_graph_versions'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'IA-5 ECC WP-2 postcondition failed: public.% contains % persistent fixture row(s).',
        v_table, v_count;
    END IF;
  END LOOP;
END;
$$;

COMMIT;
