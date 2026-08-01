-- =============================================================================
-- INVENTORY-IA5-ECC-WP3-001 — Stream partition and accepted-allocator contract
--
-- Certifies the implementation surface of IA-5 ECC Hardening Work Package 3
-- (migration 20260730000018), without certifying WP-3 itself:
--   * exact two-table shape, keys, constraints, triggers, RLS, and grants;
--   * the deliberate mutability asymmetry — the stream is fully immutable and
--     dormancy-checked; the allocator is partially mutable, forward-only, and
--     carries no dormancy CHECK and no immutability trigger;
--   * the structural/fixture portions of T-22 Multi-company isolation and
--     T-26 Migration/backfill per design §23.2 and specification §4;
--   * fixture data exists only in this transaction and is removed by the final
--     ROLLBACK.
--
-- Runtime ordering, comparators, order keys, fingerprints, replay, and C-01
-- remain later authorised work and are explicitly NOT claimed here.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(46);

CREATE TEMP TABLE wp3_pre AS
SELECT
  (SELECT count(*)::int FROM public.inventory_events) AS event_rows,
  (SELECT count(*)::int FROM public.journal_entries) AS journal_rows;

-- ── A. Exact M3 shape ───────────────────────────────────────────────────────
SELECT set_eq(
  $$SELECT column_name::text FROM information_schema.columns
     WHERE table_schema='public' AND table_name='inventory_valuation_streams'$$,
  $$VALUES ('id'),('company_id'),('item_id'),('scope_code'),
           ('activation_state'),('created_by'),('created_at')$$,
  'WP-3 installs exactly the seven authorised stream columns');                        -- 1

SELECT set_eq(
  $$SELECT column_name::text FROM information_schema.columns
     WHERE table_schema='public'
       AND table_name='inventory_valuation_stream_sequences'$$,
  $$VALUES ('valuation_stream_id'),('company_id'),('last_sequence'),('updated_at')$$,
  'WP-3 installs exactly the four authorised allocator columns');                      -- 2

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_valuation_streams'
      AND is_nullable='NO'),
  7, 'every stream column is NOT NULL');                                               -- 3

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_valuation_stream_sequences'
      AND is_nullable='NO'),
  4, 'every allocator column is NOT NULL');                                            -- 4

SELECT is(
  (SELECT string_agg(column_name||':'||data_type, ',' ORDER BY ordinal_position)
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_valuation_streams'),
  'id:uuid,company_id:uuid,item_id:uuid,scope_code:text,'
  || 'activation_state:text,created_by:uuid,created_at:timestamp with time zone',
  'stream column types match the governing contract exactly');                         -- 5

SELECT is(
  (SELECT string_agg(column_name||':'||data_type, ',' ORDER BY ordinal_position)
     FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_valuation_stream_sequences'),
  'valuation_stream_id:uuid,company_id:uuid,last_sequence:bigint,'
  || 'updated_at:timestamp with time zone',
  'allocator column types match the governing contract exactly');                      -- 6

SELECT is(
  (SELECT column_default FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_valuation_streams'
      AND column_name='activation_state'),
  '''dormant''::text', 'stream activation_state defaults to dormant');                 -- 7

SELECT is(
  (SELECT column_default FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_valuation_stream_sequences'
      AND column_name='last_sequence'),
  '0', 'allocator last_sequence defaults to the pre-allocation ground state');         -- 8

-- ── B. Governed keys and constraints ────────────────────────────────────────
SELECT set_eq(
  $$SELECT conname::text FROM pg_constraint
     WHERE conrelid IN ('public.inventory_valuation_streams'::regclass,
                        'public.inventory_valuation_stream_sequences'::regclass)$$,
  $$VALUES ('inventory_valuation_streams_pkey'),
           ('inventory_valuation_streams_key_uq'),
           ('inventory_valuation_streams_activation_state_check'),
           ('inventory_valuation_streams_company_id_fkey'),
           ('inventory_valuation_streams_item_id_fkey'),
           ('inventory_valuation_streams_created_by_fkey'),
           ('inventory_valuation_stream_sequences_pkey'),
           ('inventory_valuation_stream_sequences_last_sequence_check'),
           ('inventory_valuation_stream_sequences_company_id_fkey'),
           ('inventory_valuation_stream_sequences_valuation_stream_id_fkey')$$,
  'exactly the ten governed keys and constraints exist under their exact names'); -- 9

SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname='inventory_valuation_streams_key_uq'),
  'UNIQUE (company_id, item_id, scope_code)',
  'the ECC-01 §15(4) stream key is the scope KEY, never a scope version');             -- 10

SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname='inventory_valuation_stream_sequences_pkey'),
  'PRIMARY KEY (valuation_stream_id)',
  'the allocator is keyed on the stream, one row per stream');                         -- 11

SELECT cmp_ok(
  (SELECT max(octet_length(conname))::int FROM pg_constraint
    WHERE conrelid IN ('public.inventory_valuation_streams'::regclass,
                       'public.inventory_valuation_stream_sequences'::regclass)),
  '<=', 63,
  'every WP-3 constraint identifier fits the PostgreSQL 63-byte limit');               -- 12

-- ── C. Trigger strategy and the deliberate mutability asymmetry ─────────────
SELECT is(
  (SELECT t.tgenabled::text FROM pg_trigger t
    WHERE t.tgrelid='public.inventory_valuation_streams'::regclass
      AND t.tgname='zz_inventory_valuation_streams_immutable'),
  'A', 'the stream immutability trigger is ENABLE ALWAYS');                            -- 13

SELECT is(
  (SELECT t.tgenabled::text FROM pg_trigger t
    WHERE t.tgrelid='public.inventory_valuation_stream_sequences'::regclass
      AND t.tgname='aa_inventory_valuation_stream_sequences_guard'),
  'A', 'the allocator partial-mutability guard is ENABLE ALWAYS');                     -- 14

SELECT is(
  (SELECT count(*)::int FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='public.inventory_valuation_stream_sequences'::regclass
      AND NOT t.tgisinternal
      AND p.proname='fn_ia5_reject_immutable_inventory_fact'),
  0, 'the allocator carries NO immutability trigger — it must stay writable');         -- 15

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_valuation_stream_sequences'
      AND column_name='activation_state'),
  0, 'the allocator carries NO activation_state column');                              -- 16

SELECT is(
  (SELECT count(*)::int FROM pg_constraint
    WHERE conrelid='public.inventory_valuation_streams'::regclass
      AND contype='c' AND convalidated
      AND pg_get_constraintdef(oid) ILIKE '%activation_state%dormant%'),
  1, 'the stream carries the governed dormancy CHECK');                                -- 17

SELECT set_eq(
  $$SELECT c.relname||'|'||t.tgname||'|'||p.proname
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_proc p ON p.oid=t.tgfoid
     WHERE c.relname IN ('inventory_valuation_streams',
                         'inventory_valuation_stream_sequences')
       AND NOT t.tgisinternal$$,
  $$VALUES ('inventory_valuation_streams|aa_inventory_valuation_streams_guard|fn_ia5_guard_inventory_stream_foundation'),
           ('inventory_valuation_streams|trg_inventory_valuation_streams_audit|fn_audit_trigger'),
           ('inventory_valuation_streams|zz_inventory_valuation_streams_immutable|fn_ia5_reject_immutable_inventory_fact'),
           ('inventory_valuation_stream_sequences|aa_inventory_valuation_stream_sequences_guard|fn_ia5_guard_inventory_stream_foundation'),
           ('inventory_valuation_stream_sequences|trg_inventory_valuation_stream_sequences_audit|fn_audit_trigger')$$,
  'exactly the five authorised WP-3 triggers exist');                                  -- 18

-- ── D. Security boundary ────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM pg_class
    WHERE oid IN ('public.inventory_valuation_streams'::regclass,
                  'public.inventory_valuation_stream_sequences'::regclass)
      AND relrowsecurity),
  2, 'RLS is enabled on both WP-3 tables');                                            -- 19

SELECT set_eq(
  $$SELECT tablename||'|'||policyname||'|'||cmd FROM pg_policies
     WHERE schemaname='public'
       AND tablename IN ('inventory_valuation_streams',
                         'inventory_valuation_stream_sequences')$$,
  $$VALUES ('inventory_valuation_streams|inventory_valuation_streams_read|SELECT'),
           ('inventory_valuation_stream_sequences|inventory_valuation_stream_sequences_read|SELECT')$$,
  'each WP-3 table has exactly one governed SELECT policy');                           -- 20

SELECT is_empty(
  $$SELECT table_name||':'||grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public'
       AND table_name IN ('inventory_valuation_streams',
                          'inventory_valuation_stream_sequences')
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')
       AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')$$,
  'WP-3 exposes no client or service write grant');                                    -- 21

SELECT is_empty(
  $$SELECT grantee::text FROM information_schema.role_routine_grants
     WHERE routine_schema='public'
       AND routine_name='fn_ia5_guard_inventory_stream_foundation'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')$$,
  'the WP-3 guard function is owner-mediated with no client EXECUTE');                 -- 22

-- ── E. T-26 migration / backfill and T-27-class dormancy ───────────────────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_streams),
  0, 'T-26: the stream table is created empty');                                       -- 23

SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_stream_sequences),
  0, 'T-26: the allocator table is created empty');                                    -- 24

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'T-26: inventory_events remains empty');                                          -- 25

SELECT is(
  (
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prokind IN ('f','p')
        AND p.proname <> 'fn_ia5_guard_inventory_stream_foundation'
        AND p.proname <> 'fn_ia5_guard_inventory_order_key_foundation'
        AND pg_get_functiondef(p.oid) ~
          '(inventory_valuation_streams|inventory_valuation_stream_sequences)')
    +
    (SELECT count(*) FROM pg_views WHERE schemaname='public'
       AND definition ~
         '(inventory_valuation_streams|inventory_valuation_stream_sequences)')
  )::int,
  0, 'no runtime function or view consumes a WP-3 table');                             -- 26

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_valuation_scope_sequences'::regclass
      AND NOT tgisinternal),
  0, 'the legacy scope allocator is retained read-only and structurally untouched');   -- 27

-- ── F. Certification-only fixture (two companies, own items) ───────────────
INSERT INTO auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '1a5c0000-0000-0000-0000-000000000107',
  'authenticated','authenticated','ecc-wp3@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}'
);

INSERT INTO public.companies (
  id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
  signatory_name,signatory_position,created_by,updated_by,
  functional_currency_code,reporting_currency_code
) VALUES
  ('1a5c0000-0000-0000-0000-0000000003a1','corporation','ECC WP3 Company A',
   'Trading','520-000-107-00001','vat','calendar','A','B','Makati',
   'Metro Manila','1200','ecc-wp3a@test.local','WP3','President',
   '1a5c0000-0000-0000-0000-000000000107','1a5c0000-0000-0000-0000-000000000107',
   'PHP','PHP'),
  ('1a5c0000-0000-0000-0000-0000000003a2','corporation','ECC WP3 Company B',
   'Trading','520-000-107-00002','vat','calendar','A','B','Makati',
   'Metro Manila','1200','ecc-wp3b@test.local','WP3','President',
   '1a5c0000-0000-0000-0000-000000000107','1a5c0000-0000-0000-0000-000000000107',
   'PHP','PHP');

INSERT INTO public.user_company_memberships (user_id,company_id,role,granted_by)
VALUES
  ('1a5c0000-0000-0000-0000-000000000107','1a5c0000-0000-0000-0000-0000000003a1',
   'owner','1a5c0000-0000-0000-0000-000000000107'),
  ('1a5c0000-0000-0000-0000-000000000107','1a5c0000-0000-0000-0000-0000000003a2',
   'owner','1a5c0000-0000-0000-0000-000000000107')
ON CONFLICT DO NOTHING;

INSERT INTO public.item_categories (id,company_id,category_code,category_name)
VALUES
  ('1a5c0000-0000-0000-0000-0000000003b1','1a5c0000-0000-0000-0000-0000000003a1','WP3','WP3'),
  ('1a5c0000-0000-0000-0000-0000000003b2','1a5c0000-0000-0000-0000-0000000003a2','WP3','WP3');

INSERT INTO public.units_of_measure (id,company_id,uom_code,description)
VALUES
  ('1a5c0000-0000-0000-0000-0000000003c1','1a5c0000-0000-0000-0000-0000000003a1','EA','Each'),
  ('1a5c0000-0000-0000-0000-0000000003c2','1a5c0000-0000-0000-0000-0000000003a2','EA','Each');

INSERT INTO public.items (
  id,company_id,item_code,description,item_type,category_id,uom_id,
  costing_method,created_by,updated_by
) VALUES
  ('1a5c0000-0000-0000-0000-0000000003d1','1a5c0000-0000-0000-0000-0000000003a1',
   'WP3-ITEM-A','WP3 Item A','inventory_item',
   '1a5c0000-0000-0000-0000-0000000003b1','1a5c0000-0000-0000-0000-0000000003c1',
   'weighted_average','1a5c0000-0000-0000-0000-000000000107',
   '1a5c0000-0000-0000-0000-000000000107'),
  ('1a5c0000-0000-0000-0000-0000000003d2','1a5c0000-0000-0000-0000-0000000003a2',
   'WP3-ITEM-B','WP3 Item B','inventory_item',
   '1a5c0000-0000-0000-0000-0000000003b2','1a5c0000-0000-0000-0000-0000000003c2',
   'weighted_average','1a5c0000-0000-0000-0000-000000000107',
   '1a5c0000-0000-0000-0000-000000000107');

-- The sanctioned owner-mediated bundle builds each company's dormant
-- precision-policy / accounting-profile / cost-formula-policy / scope chain.
CREATE TEMP TABLE wp3_bundle AS
SELECT
  'A'::text AS side,
  public.fn_ia5_create_dormant_policy_bundle(
    '1a5c0000-0000-0000-0000-0000000003a1','1a5c0000-0000-0000-0000-0000000003d1',
    'company',NULL,NULL,'moving_weighted_average',6::smallint,'PHP',2::smallint,
    '2026-01-01',NULL,'1a5c0000-0000-0000-0000-000000000107') AS bundle
UNION ALL
SELECT
  'B'::text,
  public.fn_ia5_create_dormant_policy_bundle(
    '1a5c0000-0000-0000-0000-0000000003a2','1a5c0000-0000-0000-0000-0000000003d2',
    'company',NULL,NULL,'moving_weighted_average',6::smallint,'PHP',2::smallint,
    '2026-01-01',NULL,'1a5c0000-0000-0000-0000-000000000107');

-- One shared scope_code per company, for that company's own item. This is the
-- invariant T-22 proves: scope_code is not globally unique, and partition
-- identity is company-scoped.
INSERT INTO public.inventory_valuation_scopes (
  company_id,item_id,accounting_profile_id,cost_formula_policy_id,
  scope_code,scope_type,valuation_currency_code,effective_from,created_by
)
SELECT
  CASE side WHEN 'A' THEN '1a5c0000-0000-0000-0000-0000000003a1'::uuid
            ELSE '1a5c0000-0000-0000-0000-0000000003a2'::uuid END,
  CASE side WHEN 'A' THEN '1a5c0000-0000-0000-0000-0000000003d1'::uuid
            ELSE '1a5c0000-0000-0000-0000-0000000003d2'::uuid END,
  (bundle->>'accounting_profile_id')::uuid,
  (bundle->>'cost_formula_policy_id')::uuid,
  'WP3SHARED','company','PHP','2026-01-01',
  '1a5c0000-0000-0000-0000-000000000107'
FROM wp3_bundle;

INSERT INTO public.inventory_valuation_streams
  (id,company_id,item_id,scope_code,created_by)
VALUES
  ('1a5c0000-0000-0000-0000-0000000003e1','1a5c0000-0000-0000-0000-0000000003a1',
   '1a5c0000-0000-0000-0000-0000000003d1','WP3SHARED',
   '1a5c0000-0000-0000-0000-000000000107'),
  ('1a5c0000-0000-0000-0000-0000000003e2','1a5c0000-0000-0000-0000-0000000003a2',
   '1a5c0000-0000-0000-0000-0000000003d2','WP3SHARED',
   '1a5c0000-0000-0000-0000-000000000107');

-- ── G. T-22 multi-company isolation (fixture) ──────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_streams
    WHERE scope_code='WP3SHARED'),
  2, 'T-22: two companies each hold a stream with the same scope_code');               -- 28

SELECT is(
  (SELECT count(DISTINCT company_id)::int
     FROM public.inventory_valuation_streams WHERE scope_code='WP3SHARED'),
  2, 'T-22: those streams are company-scoped and do not collide');                     -- 29

SELECT throws_like(
  $$INSERT INTO public.inventory_valuation_streams
      (company_id,item_id,scope_code,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000003a2',
            '1a5c0000-0000-0000-0000-0000000003d1','WP3SHARED',
            '1a5c0000-0000-0000-0000-000000000107')$$,
  '%belongs to company%',
  'T-22: a stream naming another company''s item is rejected');                        -- 30

SELECT throws_ok(
  $$INSERT INTO public.inventory_valuation_streams
      (company_id,item_id,scope_code,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000003a1',
            '1a5c0000-0000-0000-0000-0000000003d1','WP3SHARED',
            '1a5c0000-0000-0000-0000-000000000107')$$,
  '23505', NULL,
  'T-22: a duplicate (company_id, item_id, scope_code) is rejected');                  -- 31

SELECT throws_like(
  $$INSERT INTO public.inventory_valuation_streams
      (company_id,item_id,scope_code,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000003a1',
            '1a5c0000-0000-0000-0000-0000000003d1','WP3UNKNOWN',
            '1a5c0000-0000-0000-0000-000000000107')$$,
  '%resolves to no scope version%',
  'a scope_code resolving to no scope version fails closed');                          -- 32

SELECT throws_ok(
  $$INSERT INTO public.inventory_valuation_streams
      (company_id,item_id,scope_code,activation_state,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000003a1',
            '1a5c0000-0000-0000-0000-0000000003d1','WP3SHARED','active',
            '1a5c0000-0000-0000-0000-000000000107')$$,
  '23514', NULL,
  'a non-dormant activation_state is rejected by the dormancy CHECK');                 -- 33

-- ── H. Stream immutability (§10) ───────────────────────────────────────────
SELECT throws_like(
  $$UPDATE public.inventory_valuation_streams
       SET activation_state='dormant'
     WHERE id='1a5c0000-0000-0000-0000-0000000003e1'$$,
  '%immutable Inventory authority rejects%',
  'the stream rejects UPDATE — it is fully immutable');                                -- 34

SELECT throws_like(
  $$DELETE FROM public.inventory_valuation_streams
     WHERE id='1a5c0000-0000-0000-0000-0000000003e1'$$,
  '%immutable Inventory authority rejects%',
  'the stream rejects DELETE');                                                        -- 35

-- ── I. Allocator partial mutability (§3.1) ─────────────────────────────────
INSERT INTO public.inventory_valuation_stream_sequences
  (valuation_stream_id,company_id)
VALUES ('1a5c0000-0000-0000-0000-0000000003e1',
        '1a5c0000-0000-0000-0000-0000000003a1');

SELECT is(
  (SELECT last_sequence::int FROM public.inventory_valuation_stream_sequences
    WHERE valuation_stream_id='1a5c0000-0000-0000-0000-0000000003e1'),
  0, 'a new allocator row starts at the pre-allocation ground state');                 -- 36

UPDATE public.inventory_valuation_stream_sequences
   SET last_sequence = 5, updated_at = clock_timestamp()
 WHERE valuation_stream_id='1a5c0000-0000-0000-0000-0000000003e1';

SELECT is(
  (SELECT last_sequence::int FROM public.inventory_valuation_stream_sequences
    WHERE valuation_stream_id='1a5c0000-0000-0000-0000-0000000003e1'),
  5, 'the allocator counter advances forward — it is mutable by design');              -- 37

SELECT throws_like(
  $$UPDATE public.inventory_valuation_stream_sequences
       SET last_sequence = 4
     WHERE valuation_stream_id='1a5c0000-0000-0000-0000-0000000003e1'$$,
  '%cannot move backward%',
  'the allocator counter cannot move backward; issued positions are never reused');    -- 38

SELECT throws_like(
  $$UPDATE public.inventory_valuation_stream_sequences
       SET company_id='1a5c0000-0000-0000-0000-0000000003a2'
     WHERE valuation_stream_id='1a5c0000-0000-0000-0000-0000000003e1'$$,
  '%identity columns%immutable%',
  'the allocator identity columns are immutable');                                     -- 39

SELECT throws_like(
  $$DELETE FROM public.inventory_valuation_stream_sequences
     WHERE valuation_stream_id='1a5c0000-0000-0000-0000-0000000003e1'$$,
  '%permanent; DELETE is rejected%',
  'the allocator rejects DELETE — a consumed position can never be reissued');         -- 40

SELECT throws_like(
  $$INSERT INTO public.inventory_valuation_stream_sequences
      (valuation_stream_id,company_id)
    VALUES ('1a5c0000-0000-0000-0000-0000000003e2',
            '1a5c0000-0000-0000-0000-0000000003a1')$$,
  '%does not match its stream company%',
  'T-22: an allocator row whose company differs from its stream is rejected');         -- 41

SELECT throws_ok(
  $$INSERT INTO public.inventory_valuation_stream_sequences
      (valuation_stream_id,company_id)
    VALUES ('1a5c0000-0000-0000-0000-0000000003e1',
            '1a5c0000-0000-0000-0000-0000000003a1')$$,
  '23505', NULL,
  'the allocator admits exactly one row per stream');                                  -- 42

SELECT throws_ok(
  $$INSERT INTO public.inventory_valuation_stream_sequences
      (valuation_stream_id,company_id,last_sequence)
    VALUES ('1a5c0000-0000-0000-0000-0000000003e2',
            '1a5c0000-0000-0000-0000-0000000003a2',-1)$$,
  '23514', NULL,
  'a negative accepted counter is rejected');                                          -- 43

-- ── J. Boundaries hold through the fixture ─────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  (SELECT event_rows FROM wp3_pre),
  'the WP-3 fixture creates no inventory event');                                      -- 44

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp3_pre),
  'the WP-3 fixture creates no journal entry');                                        -- 45

SELECT is(
  (SELECT count(*)::int FROM public.inventory_valuation_streams
    WHERE activation_state <> 'dormant'),
  0, 'every stream remains dormant through certification-fixture resolution');         -- 46

SELECT * FROM finish();
ROLLBACK;
