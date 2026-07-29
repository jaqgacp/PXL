-- =============================================================================
-- INVENTORY-IA5-ECC-WP1-001 — Order-policy and version foundation (dormant)
--
-- Certifies IA-5 ECC Hardening Work Package 1 (migration 20260726000016): the six
-- dormant version tables exist with the IA-5 guard / RLS / grant / audit /
-- ENABLE-ALWAYS-immutability / dormancy-CHECK controls applied unchanged; the
-- certification-only rank set (effect 10/20/30/40/50; IA5_CERTIFICATION source-type
-- and transition ranks) materialises and the version vector V resolves; nothing is
-- added to inventory_events; no write grant is exposed. Evidence families T-01
-- (deterministic tuple — structural at this stage) and T-27 (dormancy).
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

CREATE TEMP TABLE wp1_pre AS
SELECT
  (SELECT count(*)::int FROM public.inventory_events) AS event_rows,
  (SELECT count(*)::int FROM public.journal_entries) AS journal_rows;

-- ── A. Structure (T-01 structural) ───────────────────────────────────────────
SELECT set_eq(
  $$SELECT c.relname::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN (
       'inventory_event_order_policies','inventory_event_effect_ranks',
       'inventory_source_type_ranks','inventory_transition_ranks',
       'inventory_canonical_form_versions','inventory_correction_graph_versions')$$,
  $$VALUES ('inventory_event_order_policies'),('inventory_event_effect_ranks'),
           ('inventory_source_type_ranks'),('inventory_transition_ranks'),
           ('inventory_canonical_form_versions'),('inventory_correction_graph_versions')$$,
  'WP-1 installs exactly the six ECC order-policy/version tables');                       -- 1

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND column_name='company_id'
      AND table_name IN ('inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')),
  6, 'every WP-1 table carries company_id for RLS (design §19)');                         -- 2

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND column_name='activation_state'
      AND table_name IN ('inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')),
  6, 'every WP-1 table carries an activation_state dormancy column (design §21)');        -- 3

SELECT is(
  (SELECT count(*)::int FROM pg_constraint con
     JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND con.contype='c'
      AND pg_get_constraintdef(con.oid) ILIKE '%activation_state%dormant%'
      AND c.relname IN ('inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')),
  6, 'every WP-1 table CHECK-pins activation_state to dormant');                          -- 4

-- ── B. Dormancy / security (T-27) ────────────────────────────────────────────
SELECT is_empty(
  $$SELECT grantee||':'||privilege_type FROM information_schema.role_table_grants
     WHERE table_schema='public' AND privilege_type IN ('INSERT','UPDATE','DELETE')
       AND grantee IN ('anon','authenticated','service_role','PUBLIC')
       AND table_name IN ('inventory_event_order_policies','inventory_event_effect_ranks',
         'inventory_source_type_ranks','inventory_transition_ranks',
         'inventory_canonical_form_versions','inventory_correction_graph_versions')$$,
  'no client/service role holds INSERT/UPDATE/DELETE on any WP-1 table (no write surface)'); -- 5

SELECT is(
  (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relrowsecurity
      AND c.relname IN ('inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')),
  6, 'RLS is enabled on every WP-1 table');                                               -- 6

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND cmd='SELECT'
      AND tablename IN ('inventory_event_order_policies','inventory_event_effect_ranks',
        'inventory_source_type_ranks','inventory_transition_ranks',
        'inventory_canonical_form_versions','inventory_correction_graph_versions')),
  6, 'every WP-1 table has a membership-scoped SELECT policy');                           -- 7

SELECT is_empty(
  $$SELECT grantee FROM information_schema.role_routine_grants
     WHERE routine_schema='public'
       AND routine_name='fn_ia5_guard_inventory_order_policy_foundation'
       AND grantee IN ('anon','authenticated','service_role','PUBLIC')$$,
  'the WP-1 guard function is owner-mediated (no role EXECUTE grant)');                    -- 8

-- ── C. Fixture: two member companies (materialisation runs as superuser) ──────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
       email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000','1a5c0000-0000-0000-0000-000000000001',
   'authenticated','authenticated','ecc-wp1-a@test.local','',now(),now(),now(),
   '{"provider":"email","providers":["email"]}','{}'),
  ('00000000-0000-0000-0000-000000000000','1a5c0000-0000-0000-0000-000000000002',
   'authenticated','authenticated','ecc-wp1-b@test.local','',now(),now(),now(),
   '{"provider":"email","providers":["email"]}','{}');

INSERT INTO public.companies (id, entity_type, registered_name, line_of_business, tin,
       tax_registration, accounting_period, address_line_1, address_line_2, city,
       province, zip_code, email, signatory_name, signatory_position,
       created_by, updated_by, functional_currency_code, reporting_currency_code)
VALUES
  ('1a5c0000-0000-0000-0000-0000000000a1','corporation','ECC WP1 Alpha','Trading',
   '510-000-001-00000','vat','calendar','A','B','Makati','Metro Manila','1200',
   'ecc-wp1-a@test.local','A','President','1a5c0000-0000-0000-0000-000000000001',
   '1a5c0000-0000-0000-0000-000000000001','PHP','PHP'),
  ('1a5c0000-0000-0000-0000-0000000000b1','corporation','ECC WP1 Beta','Trading',
   '510-000-002-00000','vat','calendar','A','B','Makati','Metro Manila','1200',
   'ecc-wp1-b@test.local','B','President','1a5c0000-0000-0000-0000-000000000002',
   '1a5c0000-0000-0000-0000-000000000002','PHP','PHP');

INSERT INTO public.user_company_memberships (user_id, company_id, role, granted_by) VALUES
  ('1a5c0000-0000-0000-0000-000000000001','1a5c0000-0000-0000-0000-0000000000a1','owner','1a5c0000-0000-0000-0000-000000000001'),
  ('1a5c0000-0000-0000-0000-000000000002','1a5c0000-0000-0000-0000-0000000000b1','owner','1a5c0000-0000-0000-0000-000000000002')
ON CONFLICT (user_id, company_id) DO NOTHING;

-- ── D. Materialise the certification-only version set + rank set for company A ──
INSERT INTO public.inventory_canonical_form_versions
  (id, company_id, version_code, activated_from, created_by)
VALUES ('1a5c0000-0000-0000-0000-0000000000f1','1a5c0000-0000-0000-0000-0000000000a1',
        'IA5_CERTIFICATION','2026-01-01','1a5c0000-0000-0000-0000-000000000001');

INSERT INTO public.inventory_correction_graph_versions
  (id, company_id, version_no, effective_from, created_by)
VALUES ('1a5c0000-0000-0000-0000-0000000000f2','1a5c0000-0000-0000-0000-0000000000a1',
        1,'2026-01-01','1a5c0000-0000-0000-0000-000000000001');

INSERT INTO public.inventory_event_order_policies
  (id, company_id, policy_code, version_no, effective_from, created_by)
VALUES ('1a5c0000-0000-0000-0000-0000000000f3','1a5c0000-0000-0000-0000-0000000000a1',
        'IA5_CERTIFICATION',1,'2026-01-01','1a5c0000-0000-0000-0000-000000000001');

INSERT INTO public.inventory_event_effect_ranks
  (company_id, order_policy_id, effect_class, effect_rank, created_by)
VALUES
  ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3','opening',   10,'1a5c0000-0000-0000-0000-000000000001'),
  ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3','increase',  20,'1a5c0000-0000-0000-0000-000000000001'),
  ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3','value_only',30,'1a5c0000-0000-0000-0000-000000000001'),
  ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3','decrease',  40,'1a5c0000-0000-0000-0000-000000000001'),
  ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3','allowance', 50,'1a5c0000-0000-0000-0000-000000000001');

INSERT INTO public.inventory_source_type_ranks
  (company_id, order_policy_id, source_document_type, source_type_rank, created_by)
VALUES ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3',
        'IA5_CERTIFICATION',100,'1a5c0000-0000-0000-0000-000000000001');

INSERT INTO public.inventory_transition_ranks
  (company_id, order_policy_id, source_document_type, source_transition, transition_rank, created_by)
VALUES ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3',
        'IA5_CERTIFICATION','ACCEPTED',100,'1a5c0000-0000-0000-0000-000000000001');

-- ── E. Seeded certification rank set + V resolvable ───────────────────────────
SELECT is(
  (SELECT string_agg(effect_class||'='||effect_rank, ',' ORDER BY effect_rank)
     FROM public.inventory_event_effect_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000000f3'),
  'opening=10,increase=20,value_only=30,decrease=40,allowance=50',
  'E3 effect ranks are the frozen sparse convention 10/20/30/40/50');                     -- 9

SELECT is(
  (SELECT source_type_rank FROM public.inventory_source_type_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000000f3'
      AND source_document_type='IA5_CERTIFICATION'),
  100::smallint, 'E4 source-type rank seeded for IA5_CERTIFICATION (sparse)');            -- 10

SELECT is(
  (SELECT source_transition||':'||transition_rank FROM public.inventory_transition_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000000f3'
      AND source_document_type='IA5_CERTIFICATION'),
  'ACCEPTED:100', 'E7 transition rank seeded for the certification transition');          -- 11

-- Version vector V resolves: order policy + canonical form + correction graph
-- all present and company-consistent for the certification set.
SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_event_order_policies op
     JOIN public.inventory_canonical_form_versions cf ON cf.company_id=op.company_id
     JOIN public.inventory_correction_graph_versions cg ON cg.company_id=op.company_id
    WHERE op.company_id='1a5c0000-0000-0000-0000-0000000000a1'
      AND op.policy_code='IA5_CERTIFICATION'
      AND cf.version_code='IA5_CERTIFICATION'
      AND cg.version_no=1),
  1, 'the certification version vector V (order policy + canonical form + correction graph) resolves'); -- 12

SELECT is(
  (SELECT digest_algorithm FROM public.inventory_canonical_form_versions
    WHERE id='1a5c0000-0000-0000-0000-0000000000f1'),
  'sha256', 'canonical-form version pins the sha256 digest identity (built-in, no extension)'); -- 13

-- ── F. Immutability (ENABLE ALWAYS) ───────────────────────────────────────────
SELECT throws_like(
  $$UPDATE public.inventory_event_effect_ranks SET effect_rank=99
     WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000000f3' AND effect_class='opening'$$,
  '%immutable Inventory authority rejects%', 'UPDATE on a WP-1 rank row is rejected');    -- 14
SELECT throws_like(
  $$DELETE FROM public.inventory_event_order_policies WHERE id='1a5c0000-0000-0000-0000-0000000000f3'$$,
  '%immutable Inventory authority rejects%', 'DELETE on a WP-1 order policy is rejected'); -- 15

-- ── G. Guard behaviour ────────────────────────────────────────────────────────
SELECT throws_like(
  $$INSERT INTO public.inventory_event_effect_ranks
      (company_id, order_policy_id, effect_class, effect_rank, created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000000b1','1a5c0000-0000-0000-0000-0000000000f3',
            'opening',10,'1a5c0000-0000-0000-0000-000000000002')$$,
  '%does not match its order policy company%',
  'a rank whose company differs from its order policy is rejected (P-02)');               -- 16
SELECT throws_like(
  $$INSERT INTO public.inventory_event_order_policies
      (company_id, policy_code, version_no, effective_from, created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000000a1','IA5_CERTIFICATION',2,'2026-06-01',
            '1a5c0000-0000-0000-0000-000000000001')$$,
  '%Overlapping%', 'an overlapping order-policy version for one code is rejected');        -- 17
SELECT throws_ok(
  $$INSERT INTO public.inventory_event_effect_ranks
      (company_id, order_policy_id, effect_class, effect_rank, created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3',
            'opening',11,'1a5c0000-0000-0000-0000-000000000001')$$,
  '23505');                                                                                -- 18
SELECT throws_ok(
  $$INSERT INTO public.inventory_source_type_ranks
      (company_id, order_policy_id, source_document_type, source_type_rank, created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3',
           'IA5_CERTIFICATION',101,'1a5c0000-0000-0000-0000-000000000001')$$,
  '23505');                                                                                -- 19
-- Dormancy CHECK probed on a table with no overlap guard so the CHECK is reached.
SELECT throws_ok(
  $$INSERT INTO public.inventory_transition_ranks
      (company_id, order_policy_id, source_document_type, source_transition, transition_rank, activation_state, created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000000a1','1a5c0000-0000-0000-0000-0000000000f3',
            'IA5_CERTIFICATION','PROBE',200,'active','1a5c0000-0000-0000-0000-000000000001')$$,
  '23514');                                                                                -- 20

-- ── H. Posting/event boundary unchanged (design §22) ──────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  (SELECT event_rows FROM wp1_pre),
  'WP-1 adds nothing to inventory_events');                                               -- 21
SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp1_pre),
  'WP-1 writes no journal entry');                                                        -- 22

SELECT * FROM finish();
ROLLBACK;
