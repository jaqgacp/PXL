-- =============================================================================
-- INVENTORY-IA5-ECC-WP3-002 — Fixture-residue and structural rollback proof
--
-- Runs after test 107. It first proves that test 107's certification-only
-- company/user/item/policy/scope/stream/allocator fixture did not survive its
-- final ROLLBACK. It then performs the governed WP-3 rollback inside this
-- isolated test transaction: reasserted preconditions including exact total row
-- counts, rollback of the downstream empty M4 sidecar before its WP-3 parent,
-- removal of both WP-3 tables in foreign-key order (child before parent),
-- removal of the WP-3 guard function, and verification of the exact pre-M3
-- state and unchanged controls. This file's final ROLLBACK restores the full
-- M4-applied schema.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

CREATE TEMP TABLE wp3_rollback_pre AS
SELECT
  (SELECT count(*)::int FROM public.journal_entries) AS journal_rows,
  (SELECT count(*)::int FROM public.inventory_valuation_scopes) AS scope_rows,
  (SELECT count(*)::int FROM public.inventory_valuation_scope_sequences) AS legacy_rows;

-- ── A. Post-test-107 fixture residue proof ─────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name IN ('inventory_valuation_streams',
                         'inventory_valuation_stream_sequences')),
  2, 'M3 is installed before the isolated rollback proof');                            -- 1

SELECT is(
  (SELECT count(*)::int FROM auth.users
    WHERE id='1a5c0000-0000-0000-0000-000000000107'),
  0, 'test 107 fixture user did not survive rollback');                                -- 2

SELECT is(
  (SELECT count(*)::int FROM public.companies
    WHERE id IN ('1a5c0000-0000-0000-0000-0000000003a1',
                 '1a5c0000-0000-0000-0000-0000000003a2')),
  0, 'test 107 fixture companies did not survive rollback');                           -- 3

SELECT is(
  (SELECT count(*)::int FROM public.items
    WHERE id IN ('1a5c0000-0000-0000-0000-0000000003d1',
                 '1a5c0000-0000-0000-0000-0000000003d2')),
  0, 'test 107 fixture items did not survive rollback');                               -- 4

SELECT is(
  (
    (SELECT count(*) FROM public.inventory_precision_policies) +
    (SELECT count(*) FROM public.inventory_accounting_profiles) +
    (SELECT count(*) FROM public.inventory_cost_formula_policies) +
    (SELECT count(*) FROM public.inventory_valuation_scopes)
  )::int,
  0, 'test 107 policy/scope bundle did not survive rollback');                         -- 5

SELECT is(
  (SELECT count(*)::int FROM public.sys_audit_logs
    WHERE company_id IN ('1a5c0000-0000-0000-0000-0000000003a1',
                         '1a5c0000-0000-0000-0000-0000000003a2')),
  0, 'test 107 fixture audit rows did not survive rollback');                          -- 6

-- ── B. Reasserted rollback preconditions (exact totals, fail-closed) ───────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_streams),
  0, 'rollback precondition: the stream table contains exactly zero rows');            -- 7

SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_stream_sequences),
  0, 'rollback precondition: the allocator contains exactly zero rows');               -- 8

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'rollback precondition: inventory_events remains empty');                         -- 9

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_valuation_streams'::regclass
      AND tgname='zz_inventory_valuation_streams_immutable'
      AND NOT tgisinternal AND tgenabled='A'),
  1, 'rollback precondition: stream immutability remains ENABLE ALWAYS');              -- 10

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_ia5_guard_inventory_stream_foundation'),
  1, 'rollback precondition: the WP-3 guard function is present');                     -- 11

SELECT is_empty(
  $$SELECT table_name||':'||grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public'
       AND table_name IN ('inventory_valuation_streams',
                          'inventory_valuation_stream_sequences')
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')
       AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')$$,
  'rollback precondition: no client/service write privilege exists');                  -- 12

-- ── C. Governed rollback: downstream M4, then M3 child/parent/function ──────
DROP TABLE public.inventory_event_order_keys;
DROP FUNCTION public.fn_ia5_guard_inventory_order_key_foundation();

DROP TABLE public.inventory_valuation_stream_sequences;
DROP TABLE public.inventory_valuation_streams;
DROP FUNCTION public.fn_ia5_guard_inventory_stream_foundation();

SELECT is(
  (SELECT count(*)::int FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name IN ('inventory_valuation_streams',
                         'inventory_valuation_stream_sequences')),
  0, 'rollback removes both WP-3 tables');                                             -- 13

SELECT is(
  (SELECT count(*)::int FROM pg_constraint
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
      'inventory_valuation_stream_sequences_valuation_stream_id_fkey')),
  0, 'rollback removes all ten attached WP-3 keys and constraints');                   -- 14

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_ia5_guard_inventory_stream_foundation'),
  0, 'rollback removes the WP-3 guard function');                                      -- 15

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('inventory_valuation_streams',
                        'inventory_valuation_stream_sequences')),
  0, 'rollback removes both WP-3 read policies');                                      -- 16

-- ── D. The pre-M3 state and every existing control are unchanged ──────────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_scope_sequences),
  (SELECT legacy_rows FROM wp3_rollback_pre),
  'rollback leaves the legacy scope allocator untouched');                             -- 17

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_valuation_scope_sequences'::regclass
      AND NOT tgisinternal),
  0, 'the legacy scope allocator still carries no trigger — nothing was altered');     -- 18

SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_scopes),
  (SELECT scope_rows FROM wp3_rollback_pre),
  'rollback changes no valuation scope');                                              -- 19

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_ia5_guard_inventory_policy_foundation',
                        'fn_ia5_guard_inventory_order_policy_foundation',
                        'fn_ia5_reject_immutable_inventory_fact',
                        'fn_audit_trigger')),
  4, 'rollback preserves every pre-existing IA-5 guard and shared engine function'); -- 20

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'rollback creates, changes, or deletes no inventory event');                      -- 21

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp3_rollback_pre),
  'rollback creates, changes, or deletes no journal entry');                           -- 22

SELECT * FROM finish();
ROLLBACK;
