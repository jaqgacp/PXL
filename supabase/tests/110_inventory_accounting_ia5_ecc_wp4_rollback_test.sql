-- =============================================================================
-- INVENTORY-IA5-ECC-WP4-002 — Fixture-residue and structural rollback proof
--
-- Runs after test 109. It first proves that test 109's certification-only
-- user/company/item/policy/scope/stream/event/order-key fixture did not survive
-- its final ROLLBACK. It then performs the governed WP-4 rollback inside this
-- isolated test transaction: reasserted preconditions including exact total row
-- counts, removal of the order-key table, removal of the WP-4 guard function,
-- and verification of the exact pre-M4 state and unchanged WP-1/WP-2/WP-3
-- controls. This file's final ROLLBACK restores the M4-applied schema.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(30);

CREATE TEMP TABLE wp4_rollback_pre AS
SELECT
  (SELECT count(*)::int FROM public.journal_entries) AS journal_rows,
  (SELECT count(*)::int FROM public.inventory_valuation_scopes) AS scope_rows,
  (SELECT count(*)::int FROM public.inventory_valuation_streams) AS stream_rows;

-- ── A. Post-test-109 fixture residue proof ─────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM information_schema.tables
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'),
  1, 'M4 is installed before the isolated rollback proof');                    -- 1

SELECT is(
  (SELECT count(*)::int FROM auth.users
    WHERE id='1a5d0000-0000-0000-0000-000000000109'),
  0, 'test 109 fixture user did not survive rollback');                        -- 2

SELECT is(
  (SELECT count(*)::int FROM public.companies
    WHERE id IN ('1a5d0000-0000-0000-0000-0000000004a1',
                 '1a5d0000-0000-0000-0000-0000000004a2')),
  0, 'test 109 fixture companies did not survive rollback');                   -- 3

SELECT is(
  (SELECT count(*)::int FROM public.items
    WHERE id IN ('1a5d0000-0000-0000-0000-0000000004f1',
                 '1a5d0000-0000-0000-0000-0000000004f2')),
  0, 'test 109 fixture items did not survive rollback');                       -- 4

SELECT is(
  (
    (SELECT count(*) FROM public.inventory_precision_policies) +
    (SELECT count(*) FROM public.inventory_accounting_profiles) +
    (SELECT count(*) FROM public.inventory_cost_formula_policies) +
    (SELECT count(*) FROM public.inventory_valuation_scopes) +
    (SELECT count(*) FROM public.inventory_valuation_scope_sequences) +
    (SELECT count(*) FROM public.inventory_event_order_policies) +
    (SELECT count(*) FROM public.inventory_event_effect_ranks) +
    (SELECT count(*) FROM public.inventory_source_type_ranks) +
    (SELECT count(*) FROM public.inventory_transition_ranks) +
    (SELECT count(*) FROM public.inventory_canonical_form_versions) +
    (SELECT count(*) FROM public.inventory_correction_graph_versions) +
    (SELECT count(*) FROM public.inventory_valuation_streams) +
    (SELECT count(*) FROM public.inventory_valuation_stream_sequences)
  )::int,
  0, 'test 109 policy/scope/version bundle did not survive rollback');         -- 5

SELECT is(
  (
    (SELECT count(*) FROM public.inventory_occurrences) +
    (SELECT count(*) FROM public.inventory_events) +
    (SELECT count(*) FROM public.inventory_event_values) +
    (SELECT count(*) FROM public.inventory_event_source_links) +
    (SELECT count(*) FROM public.inventory_event_allocations)
  )::int,
  0, 'test 109 occurrence and event fixture did not survive rollback');        -- 6

SELECT is(
  (SELECT count(*)::int FROM public.sys_audit_logs
    WHERE company_id IN ('1a5d0000-0000-0000-0000-0000000004a1',
                         '1a5d0000-0000-0000-0000-0000000004a2')),
  0, 'test 109 fixture audit rows did not survive rollback');                  -- 7

-- ── B. Reasserted rollback preconditions (exact totals, fail-closed) ───────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_event_order_keys),
  0, 'rollback precondition: the order-key table contains exactly zero rows');  -- 8

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'rollback precondition: inventory_events remains empty');                 -- 9

SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_streams),
  0, 'rollback precondition: the WP-3 stream table remains empty');           -- 10

SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types),
  1, 'rollback precondition: the WP-2 registry holds exactly one row');       -- 11

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_event_order_keys'::regclass
      AND tgname='aa_inventory_event_order_keys_guard'
      AND NOT tgisinternal AND tgenabled='A'),
  1, 'rollback precondition: the order-key guard remains ENABLE ALWAYS');     -- 12

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_ia5_guard_inventory_order_key_foundation'),
  1, 'rollback precondition: the WP-4 guard function is present');            -- 13

SELECT is_empty(
  $$SELECT grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name='inventory_event_order_keys'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')
       AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')$$,
  'rollback precondition: no client/service write privilege exists');         -- 14

-- ── C. Governed rollback: table, then the guard function ──────────────────
DROP TABLE public.inventory_event_order_keys;
DROP FUNCTION public.fn_ia5_guard_inventory_order_key_foundation();

SELECT is(
  (SELECT count(*)::int FROM information_schema.tables
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'),
  0, 'rollback removes the WP-4 table');                                      -- 15

SELECT is(
  (SELECT count(*)::int FROM pg_constraint
    WHERE conname IN (
      'inventory_event_order_keys_pkey',
      'inventory_event_order_keys_identity_uq',
      'inventory_event_order_keys_correction_root_check',
      'inventory_event_order_keys_resolution_state_check',
      'inventory_event_order_keys_registry_source_document_type_fkey')),
  0, 'rollback removes the attached WP-4 keys and constraints');              -- 16

SELECT is(
  (SELECT count(*)::int FROM pg_indexes
    WHERE schemaname='public' AND tablename='inventory_event_order_keys'),
  0, 'rollback removes all four WP-4 indexes');                               -- 17

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_ia5_guard_inventory_order_key_foundation'),
  0, 'rollback removes the WP-4 guard function');                             -- 18

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='inventory_event_order_keys'),
  0, 'rollback removes the WP-4 read policy');                                -- 19

-- ── D. The pre-M4 state and every existing control are unchanged ──────────
SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_events'::regclass AND NOT tgisinternal),
  3, 'inventory_events retains its exact certified trigger set — nothing was altered');
                                                                              -- 20

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_ia5_guard_inventory_policy_foundation',
                        'fn_ia5_guard_inventory_order_policy_foundation',
                        'fn_ia5_guard_inventory_stream_foundation',
                        'fn_ia5_reject_immutable_inventory_fact',
                        'fn_audit_trigger')),
  5, 'rollback preserves every pre-existing IA-5 guard and shared engine function');
                                                                              -- 21

SELECT is(
  (SELECT count(*)::int
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relrowsecurity
      AND c.relname IN (
        'inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')),
  6, 'rollback preserves RLS on all six WP-1 policy/version tables');          -- 22

SELECT is(
  (SELECT count(DISTINCT c.relname)::int
     FROM pg_constraint con
     JOIN pg_class c ON c.oid=con.conrelid
     JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relname IN (
        'inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')
      AND con.contype='c' AND con.convalidated
      AND pg_get_constraintdef(con.oid) ILIKE '%activation_state%dormant%'),
  6, 'rollback preserves the dormancy CHECK on every WP-1 table');             -- 23

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE NOT t.tgisinternal
      AND t.tgrelid IN (
        'public.inventory_event_order_policies'::regclass,
        'public.inventory_event_effect_ranks'::regclass,
        'public.inventory_source_type_ranks'::regclass,
        'public.inventory_transition_ranks'::regclass,
        'public.inventory_canonical_form_versions'::regclass,
        'public.inventory_correction_graph_versions'::regclass)
      AND ((p.proname='fn_ia5_reject_immutable_inventory_fact' AND t.tgenabled='A')
        OR (p.proname='fn_audit_trigger' AND t.tgenabled='O'))),
  12, 'rollback preserves WP-1 audit plus ENABLE ALWAYS immutability controls'); -- 24

SELECT ok(
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
      AND column_name IN (
        'event_effect_map','document_order_key_algorithm','line_order_authority',
        'occurrence_semantics','same_time_class','correction_placement_class')) = 6
  AND (SELECT count(*) FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'
      AND owner_engine='Inventory' AND is_certification_only
      AND NOT is_production_enabled AND removal_phase='IA-6'
      AND event_effect_map =
        '{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}'::jsonb
      AND document_order_key_algorithm='canonical_source_document_id'
      AND line_order_authority='immutable_source_line_ordinal'
      AND occurrence_semantics='explicit_partial_occurrences'
      AND same_time_class='event_effect_map'
      AND correction_placement_class='base') = 1
  AND (SELECT count(*) FROM public.ref_inventory_event_source_types) = 1
  AND (SELECT relrowsecurity FROM pg_class
       WHERE oid='public.ref_inventory_event_source_types'::regclass)
  AND EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='public.ref_inventory_event_source_types'::regclass
      AND NOT t.tgisinternal AND t.tgenabled='A'
      AND p.proname='fn_ia5_reject_immutable_inventory_fact')
  AND EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ref_inventory_event_source_types'
      AND policyname='ref_inventory_event_source_types_read'
      AND cmd='SELECT' AND roles::text='{authenticated}' AND qual='true')
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema='public'
      AND table_name='ref_inventory_event_source_types'
      AND grantee IN ('PUBLIC','anon','authenticated','service_role')
      AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')),
  'rollback preserves the exact WP-2 authority row and its controls');         -- 25

SELECT set_eq(
  $$SELECT t.tgname||'|'||p.proname||'|'||t.tgenabled::text||'|'||t.tgtype::text
      FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
     WHERE t.tgrelid IN (
       'public.inventory_valuation_streams'::regclass,
       'public.inventory_valuation_stream_sequences'::regclass)
       AND NOT t.tgisinternal$$,
  $$VALUES
      ('aa_inventory_valuation_streams_guard|fn_ia5_guard_inventory_stream_foundation|O|23'),
      ('trg_inventory_valuation_streams_audit|fn_audit_trigger|O|5'),
      ('zz_inventory_valuation_streams_immutable|fn_ia5_reject_immutable_inventory_fact|A|27'),
      ('aa_inventory_valuation_stream_sequences_guard|fn_ia5_guard_inventory_stream_foundation|A|31'),
      ('trg_inventory_valuation_stream_sequences_audit|fn_audit_trigger|O|5')$$,
  'rollback preserves the exact WP-3 stream trigger controls');               -- 26

SELECT ok(
  (SELECT count(*) FROM pg_class
    WHERE oid IN ('public.inventory_valuation_streams'::regclass,
                  'public.inventory_valuation_stream_sequences'::regclass)
      AND relrowsecurity) = 2
  AND (SELECT count(*) FROM pg_policies
    WHERE schemaname='public'
      AND ((tablename='inventory_valuation_streams'
            AND policyname='inventory_valuation_streams_read')
        OR (tablename='inventory_valuation_stream_sequences'
            AND policyname='inventory_valuation_stream_sequences_read'))
      AND cmd='SELECT' AND roles::text='{authenticated}'
      AND qual='is_company_member(company_id)') = 2
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.inventory_valuation_streams'::regclass
      AND conname='inventory_valuation_streams_activation_state_check'
      AND contype='c' AND convalidated
      AND pg_get_constraintdef(oid) ILIKE '%activation_state%dormant%')
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema='public'
      AND table_name IN ('inventory_valuation_streams',
                         'inventory_valuation_stream_sequences')
      AND grantee IN ('PUBLIC','anon','authenticated','service_role')
      AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')),
  'rollback preserves WP-3 dormancy, RLS, read policies, and write denial');   -- 27

SELECT is(
  (SELECT (count(*)::text || '|' ||
           (SELECT count(*)::text FROM public.inventory_valuation_streams))
     FROM public.inventory_valuation_scopes),
  (SELECT scope_rows::text || '|' || stream_rows::text FROM wp4_rollback_pre),
  'rollback leaves the certified scope and WP-3 stream identities untouched'); -- 28

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'rollback creates, changes, or deletes no inventory event');             -- 29

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp4_rollback_pre),
  'rollback creates, changes, or deletes no journal entry');                  -- 30

SELECT * FROM finish();
ROLLBACK;
