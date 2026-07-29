-- =============================================================================
-- INVENTORY-IA5-ECC-WP2-002 — Fixture-residue and structural rollback proof
--
-- Runs after test 105. It first proves that test 105's certification-only
-- company/user/policy/rank/audit fixture did not survive its final ROLLBACK.
-- It then performs the governed WP-2 rollback inside this isolated test
-- transaction: ACCESS EXCLUSIVE, reasserted dormancy, reverse-order removal of
-- exactly the six columns, and verification of the pre-M2 registry shape and
-- controls. This file's final ROLLBACK restores the M2-applied schema.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

CREATE TEMP TABLE wp2_rollback_pre AS
SELECT (SELECT count(*)::int FROM public.journal_entries) AS journal_rows;

-- ── A. Post-test-105 fixture residue proof ──────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
      AND column_name IN (
        'event_effect_map','document_order_key_algorithm','line_order_authority',
        'occurrence_semantics','same_time_class','correction_placement_class')),
  6, 'M2 is installed before the isolated rollback proof');                              -- 1

SELECT is(
  (
    (SELECT count(*) FROM public.inventory_event_order_policies) +
    (SELECT count(*) FROM public.inventory_event_effect_ranks) +
    (SELECT count(*) FROM public.inventory_source_type_ranks) +
    (SELECT count(*) FROM public.inventory_transition_ranks) +
    (SELECT count(*) FROM public.inventory_canonical_form_versions) +
    (SELECT count(*) FROM public.inventory_correction_graph_versions)
  )::int,
  0, 'test 105 left no persistent WP-1 policy, rank, or version fixture row');             -- 2

SELECT is(
  (SELECT count(*)::int FROM auth.users
    WHERE id='1a5c0000-0000-0000-0000-000000000105'),
  0, 'test 105 fixture user did not survive rollback');                                  -- 3

SELECT is(
  (SELECT count(*)::int FROM public.companies
    WHERE id='1a5c0000-0000-0000-0000-0000000002a5'),
  0, 'test 105 fixture company did not survive rollback');                               -- 4

SELECT is(
  (SELECT count(*)::int FROM public.user_company_memberships
    WHERE user_id='1a5c0000-0000-0000-0000-000000000105'
       OR company_id='1a5c0000-0000-0000-0000-0000000002a5'),
  0, 'test 105 fixture membership did not survive rollback');                            -- 5

SELECT is(
  (SELECT count(*)::int FROM public.sys_audit_logs
    WHERE company_id='1a5c0000-0000-0000-0000-0000000002a5'
       OR COALESCE(new_data::text,'') LIKE '%1a5c0000-0000-0000-0000-0000000002a5%'),
  0, 'test 105 fixture audit rows did not survive rollback');                            -- 6

SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'
      AND owner_engine='Inventory'
      AND is_certification_only
      AND NOT is_production_enabled
      AND removal_phase='IA-6'
      AND event_effect_map =
        '{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}'::jsonb
      AND document_order_key_algorithm='canonical_source_document_id'
      AND line_order_authority='immutable_source_line_ordinal'
      AND occurrence_semantics='explicit_partial_occurrences'
      AND same_time_class='event_effect_map'
      AND correction_placement_class='base'),
  1, 'the exact persistent IA5_CERTIFICATION row remains before rollback');               -- 7

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'rollback precondition: inventory_events remains empty');                           -- 8

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.ref_inventory_event_source_types'::regclass
      AND tgname='zz_ref_inventory_event_source_types_immutable'
      AND NOT tgisinternal AND tgenabled='A'),
  1, 'rollback precondition: registry immutability remains ENABLE ALWAYS');               -- 9

SELECT ok(
  (SELECT relrowsecurity FROM pg_class
    WHERE oid='public.ref_inventory_event_source_types'::regclass),
  'rollback precondition: registry RLS remains enabled');                                -- 10

SELECT is_empty(
  $$SELECT grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')
       AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')$$,
  'rollback precondition: registry has no client/service write privilege');               -- 11

-- ── B. Governed reverse-order structural rollback ───────────────────────────
LOCK TABLE public.ref_inventory_event_source_types IN ACCESS EXCLUSIVE MODE;

ALTER TABLE public.ref_inventory_event_source_types
  DROP COLUMN correction_placement_class,
  DROP COLUMN same_time_class,
  DROP COLUMN occurrence_semantics,
  DROP COLUMN line_order_authority,
  DROP COLUMN document_order_key_algorithm,
  DROP COLUMN event_effect_map;

SELECT set_eq(
  $$SELECT column_name::text
      FROM information_schema.columns
     WHERE table_schema='public'
       AND table_name='ref_inventory_event_source_types'$$,
  $$VALUES ('source_document_type'),('owner_engine'),('is_certification_only'),
           ('is_production_enabled'),('removal_phase'),('created_at')$$,
  'rollback restores the exact pre-M2 six-column registry shape');                        -- 12

SELECT is(
  (SELECT count(*)::int FROM pg_constraint
    WHERE conrelid='public.ref_inventory_event_source_types'::regclass
      AND conname IN (
        'ref_inventory_event_source_types_event_effect_map_ck',
        'ref_inventory_event_source_types_doc_order_key_algorithm_ck',
        'ref_inventory_event_source_types_line_order_authority_ck',
        'ref_inventory_event_source_types_occurrence_semantics_ck',
        'ref_inventory_event_source_types_same_time_class_ck',
        'ref_inventory_event_source_types_correction_placement_class_ck')),
  0, 'rollback removes all six attached WP-2 constraints');                              -- 13

SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'
      AND owner_engine='Inventory'
      AND is_certification_only
      AND NOT is_production_enabled
      AND removal_phase='IA-6'),
  1, 'rollback retains the exact pre-WP-2 certification row');                           -- 14

SELECT is(
  (SELECT count(*)::int FROM pg_trigger t
    JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='public.ref_inventory_event_source_types'::regclass
      AND t.tgname='zz_ref_inventory_event_source_types_immutable'
      AND NOT t.tgisinternal AND t.tgenabled='A'
      AND p.proname='fn_ia5_reject_immutable_inventory_fact'),
  1, 'rollback preserves the original ENABLE ALWAYS immutable trigger');                  -- 15

SELECT ok(
  (SELECT relrowsecurity FROM pg_class
    WHERE oid='public.ref_inventory_event_source_types'::regclass),
  'rollback preserves registry RLS');                                                     -- 16

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='ref_inventory_event_source_types'
      AND policyname='ref_inventory_event_source_types_read' AND cmd='SELECT'),
  1, 'rollback preserves the original registry SELECT policy');                          -- 17

SELECT is_empty(
  $$SELECT grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')
       AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')$$,
  'rollback preserves the no-write-grant boundary');                                     -- 18

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'rollback creates, changes, or deletes no inventory event');                         -- 19

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp2_rollback_pre),
  'rollback creates, changes, or deletes no journal entry');                             -- 20

SELECT * FROM finish();
ROLLBACK;
