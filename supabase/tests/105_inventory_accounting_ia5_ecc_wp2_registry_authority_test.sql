-- =============================================================================
-- INVENTORY-IA5-ECC-WP2-001 — Dormant registry authority contract
--
-- Certifies the implementation surface of IA-5 ECC Hardening Work Package 2
-- (migration 20260729000017), without certifying WP-2 itself:
--   * exact six-column, six-constraint, no-default registry shape;
--   * exact IA5_CERTIFICATION authority values and retained dormancy;
--   * structural/fixture portions of T-04 Source order (E4/E5),
--     T-06 Transition order (E7), T-07 Effect order (E3), and T-27 Dormancy;
--   * E3/E4/E7 fixture data exists only in this transaction and is removed by
--     the final ROLLBACK;
--   * no event, runtime consumer, Posting object, or Kernel object is changed.
--
-- Runtime document/event/transition comparison remains later authorised work.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(48);

CREATE TEMP TABLE wp2_pre AS
SELECT
  (SELECT count(*)::int FROM public.inventory_events) AS event_rows,
  (SELECT count(*)::int FROM public.journal_entries) AS journal_rows;

-- ── A. Exact M2 registry shape ───────────────────────────────────────────────
SELECT set_eq(
  $$SELECT column_name::text
      FROM information_schema.columns
     WHERE table_schema='public'
       AND table_name='ref_inventory_event_source_types'
       AND column_name IN (
         'event_effect_map','document_order_key_algorithm','line_order_authority',
         'occurrence_semantics','same_time_class','correction_placement_class')$$,
  $$VALUES ('event_effect_map'),('document_order_key_algorithm'),
           ('line_order_authority'),('occurrence_semantics'),
           ('same_time_class'),('correction_placement_class')$$,
  'WP-2 installs exactly the six authorised registry columns');                         -- 1

SELECT is(
  (SELECT data_type FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
      AND column_name='event_effect_map'),
  'jsonb', 'event_effect_map has the governed jsonb type');                              -- 2

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
      AND column_name IN (
        'document_order_key_algorithm','line_order_authority',
        'occurrence_semantics','same_time_class','correction_placement_class')
      AND data_type='text' AND collation_name='C'),
  5, 'all five token columns use bytewise C collation');                                 -- 3

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
      AND column_name IN (
        'event_effect_map','document_order_key_algorithm','line_order_authority',
        'occurrence_semantics','same_time_class','correction_placement_class')
      AND is_nullable='NO'),
  6, 'all six WP-2 columns are NOT NULL');                                                -- 4

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
      AND column_name IN (
        'event_effect_map','document_order_key_algorithm','line_order_authority',
        'occurrence_semantics','same_time_class','correction_placement_class')
      AND column_default IS NULL),
  6, 'all migration-only defaults were removed before commit');                          -- 5

SELECT set_eq(
  $$SELECT conname::text FROM pg_constraint
     WHERE conrelid='public.ref_inventory_event_source_types'::regclass
       AND conname IN (
         'ref_inventory_event_source_types_event_effect_map_ck',
         'ref_inventory_event_source_types_doc_order_key_algorithm_ck',
         'ref_inventory_event_source_types_line_order_authority_ck',
         'ref_inventory_event_source_types_occurrence_semantics_ck',
         'ref_inventory_event_source_types_same_time_class_ck',
         'ref_inventory_event_source_types_correction_placement_class_ck')
       AND contype='c' AND convalidated$$,
  $$VALUES ('ref_inventory_event_source_types_event_effect_map_ck'),
           ('ref_inventory_event_source_types_doc_order_key_algorithm_ck'),
           ('ref_inventory_event_source_types_line_order_authority_ck'),
           ('ref_inventory_event_source_types_occurrence_semantics_ck'),
           ('ref_inventory_event_source_types_same_time_class_ck'),
           ('ref_inventory_event_source_types_correction_placement_class_ck')$$,
  'the six governed, validated CHECK constraints exist under their exact names');         -- 6

SELECT is(
  length('ref_inventory_event_source_types_doc_order_key_algorithm_ck'),
  59, 'EA-001 corrected document-order constraint identifier is exactly 59 bytes');       -- 7

SELECT is(
  (SELECT max(octet_length(conname))::int FROM pg_constraint
    WHERE conrelid='public.ref_inventory_event_source_types'::regclass
      AND conname LIKE 'ref_inventory_event_source_types_%_ck'),
  62, 'every governed WP-2 constraint identifier fits PostgreSQL 63-byte limit');          -- 8

SELECT is(
  (SELECT count(*)::int FROM pg_constraint
    WHERE conrelid='public.ref_inventory_event_source_types'::regclass
      AND conname='ref_inventory_event_source_types_document_order_key_algorithm_ck'),
  0, 'the superseded 64-byte identifier does not exist in the catalog');                  -- 9

-- ── B. Exact IA5_CERTIFICATION authority ─────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types),
  1, 'the registry remains a one-row certification registry');                           -- 10

SELECT is(
  (SELECT event_effect_map
     FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'),
  '{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}'::jsonb,
  'IA5_CERTIFICATION stores the exact governed event-effect map');                        -- 11

SELECT is(
  (SELECT document_order_key_algorithm||'|'||line_order_authority||'|'||
          occurrence_semantics||'|'||same_time_class||'|'||correction_placement_class
     FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'),
  'canonical_source_document_id|immutable_source_line_ordinal|explicit_partial_occurrences|event_effect_map|base',
  'IA5_CERTIFICATION stores all five exact governed token values');                       -- 12

SELECT is(
  (SELECT owner_engine||'|'||is_certification_only::text||'|'||
          is_production_enabled::text||'|'||removal_phase
     FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'),
  'Inventory|true|false|IA-6',
  'the pre-WP-2 certification-only, production-disabled row values are retained');        -- 13

-- ── C. Constraint rejection probes ──────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_EMPTY_MAP','Inventory',true,false,'IA-6','{}',
      'canonical_source_document_id','immutable_source_line_ordinal',
      'explicit_partial_occurrences','event_effect_map','base')$$,
  '23514', NULL, 'an empty event-effect map is rejected');                                -- 14

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_EXTRA_KEY','Inventory',true,false,'IA-6','{"receipt":"increase"}',
      'canonical_source_document_id','immutable_source_line_ordinal',
      'explicit_partial_occurrences','event_effect_map','base')$$,
  '23514', NULL, 'an ungoverned event-effect key is rejected');                           -- 15

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_BAD_PAIR','Inventory',true,false,'IA-6',
      '{"quantity_decrease":"increase"}','canonical_source_document_id',
      'immutable_source_line_ordinal','explicit_partial_occurrences',
      'event_effect_map','base')$$,
  '23514', NULL, 'an effect/class pair outside the governed matrix is rejected');          -- 16

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_JSON_NULL','Inventory',true,false,'IA-6',
      '{"quantity_increase":null}','canonical_source_document_id',
      'immutable_source_line_ordinal','explicit_partial_occurrences',
      'event_effect_map','base')$$,
  '23514', NULL, 'JSON null cannot satisfy the event-effect authority');                   -- 17

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_BAD_DOCUMENT','Inventory',true,false,'IA-6',
      '{"quantity_increase":"increase"}','arrival_order',
      'immutable_source_line_ordinal','explicit_partial_occurrences',
      'event_effect_map','base')$$,
  '23514', NULL, 'arrival order is rejected as a document-order algorithm');               -- 18

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_BAD_LINE','Inventory',true,false,'IA-6',
      '{"quantity_increase":"increase"}','canonical_source_document_id',
      'ui_line_order','explicit_partial_occurrences','event_effect_map','base')$$,
  '23514', NULL, 'UI line order is rejected as E6 authority');                            -- 19

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_BAD_OCCURRENCE','Inventory',true,false,'IA-6',
      '{"quantity_increase":"increase"}','canonical_source_document_id',
      'immutable_source_line_ordinal','retry_order','event_effect_map','base')$$,
  '23514', NULL, 'retry order is rejected as occurrence semantics');                      -- 20

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_BAD_SAME_TIME','Inventory',true,false,'IA-6',
      '{"quantity_increase":"increase"}','canonical_source_document_id',
      'immutable_source_line_ordinal','single_occurrence','arrival_class','base')$$,
  '23514', NULL, 'arrival class is rejected as same-time authority');                     -- 21

SELECT throws_ok(
  $$INSERT INTO public.ref_inventory_event_source_types
      (source_document_type,owner_engine,is_certification_only,is_production_enabled,
       removal_phase,event_effect_map,document_order_key_algorithm,line_order_authority,
       occurrence_semantics,same_time_class,correction_placement_class)
    VALUES ('WP2_BAD_PLACEMENT','Inventory',true,false,'IA-6',
      '{"quantity_increase":"increase"}','canonical_source_document_id',
      'immutable_source_line_ordinal','single_occurrence','event_effect_map',
      'lock_order')$$,
  '23514', NULL, 'an ungoverned correction-placement class is rejected');                 -- 22

-- ── D. Persistent security, immutability, and dormancy (T-27) ───────────────
SELECT ok(
  (SELECT c.relrowsecurity FROM pg_class c
    WHERE c.oid='public.ref_inventory_event_source_types'::regclass),
  'registry RLS remains enabled');                                                        -- 23

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='ref_inventory_event_source_types'
      AND policyname='ref_inventory_event_source_types_read' AND cmd='SELECT'),
  1, 'the original registry SELECT policy remains present');                              -- 24

SELECT is_empty(
  $$SELECT grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name='ref_inventory_event_source_types'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')
       AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')$$,
  'WP-2 exposes no registry write grant');                                                -- 25

SELECT is(
  (SELECT count(*)::int FROM pg_trigger t
    JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='public.ref_inventory_event_source_types'::regclass
      AND t.tgname='zz_ref_inventory_event_source_types_immutable'
      AND NOT t.tgisinternal AND t.tgenabled='A'
      AND p.proname='fn_ia5_reject_immutable_inventory_fact'),
  1, 'the original registry immutable trigger remains ENABLE ALWAYS');                    -- 26

SELECT throws_like(
  $$UPDATE public.ref_inventory_event_source_types
       SET same_time_class='event_effect_map'
     WHERE source_document_type='IA5_CERTIFICATION'$$,
  '%immutable Inventory authority rejects%',
  'UPDATE remains rejected across the six new attributes');                              -- 27

SELECT throws_like(
  $$DELETE FROM public.ref_inventory_event_source_types
     WHERE source_document_type='IA5_CERTIFICATION'$$,
  '%immutable Inventory authority rejects%',
  'DELETE remains rejected for the registry row');                                       -- 28

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'T-27: inventory_events remains empty');                                             -- 29

SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types
    WHERE is_production_enabled),
  0, 'T-27: no production event source is enabled');                                     -- 30

SELECT is(
  (
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prokind='f'
        AND pg_get_functiondef(p.oid) ~
          '(event_effect_map|document_order_key_algorithm|line_order_authority|occurrence_semantics|same_time_class|correction_placement_class)')
    +
    (SELECT count(*) FROM pg_views
      WHERE schemaname='public'
        AND definition ~
          '(event_effect_map|document_order_key_algorithm|line_order_authority|occurrence_semantics|same_time_class|correction_placement_class)')
  )::int,
  0, 'T-27: no runtime function or view consumes a WP-2 attribute');                      -- 31

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_events'),
  41, 'WP-2 does not alter the existing inventory_events shape');                         -- 32

SELECT is(
  (
    (SELECT count(*) FROM public.inventory_event_order_policies) +
    (SELECT count(*) FROM public.inventory_event_effect_ranks) +
    (SELECT count(*) FROM public.inventory_source_type_ranks) +
    (SELECT count(*) FROM public.inventory_transition_ranks) +
    (SELECT count(*) FROM public.inventory_canonical_form_versions) +
    (SELECT count(*) FROM public.inventory_correction_graph_versions)
  )::int,
  0, 'M2 persists no WP-1 policy, rank, or version fixture row');                         -- 33

-- ── E. Minimum certification-only E3/E4/E7 fixture ──────────────────────────
INSERT INTO auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '1a5c0000-0000-0000-0000-000000000105',
  'authenticated','authenticated','ecc-wp2@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}'
);

INSERT INTO public.companies (
  id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
  signatory_name,signatory_position,created_by,updated_by,
  functional_currency_code,reporting_currency_code
) VALUES (
  '1a5c0000-0000-0000-0000-0000000002a5','corporation','ECC WP2 Fixture',
  'Trading','520-000-105-00000','vat','calendar','A','B','Makati',
  'Metro Manila','1200','ecc-wp2@test.local','WP2','President',
  '1a5c0000-0000-0000-0000-000000000105',
  '1a5c0000-0000-0000-0000-000000000105','PHP','PHP'
);

INSERT INTO public.user_company_memberships (user_id,company_id,role,granted_by)
VALUES (
  '1a5c0000-0000-0000-0000-000000000105',
  '1a5c0000-0000-0000-0000-0000000002a5',
  'owner',
  '1a5c0000-0000-0000-0000-000000000105'
);

INSERT INTO public.inventory_event_order_policies (
  id,company_id,policy_code,version_no,effective_from,created_by
) VALUES (
  '1a5c0000-0000-0000-0000-0000000002f3',
  '1a5c0000-0000-0000-0000-0000000002a5',
  'IA5_CERTIFICATION',1,'2026-01-01',
  '1a5c0000-0000-0000-0000-000000000105'
);

INSERT INTO public.inventory_event_effect_ranks (
  company_id,order_policy_id,effect_class,effect_rank,created_by
) VALUES
  ('1a5c0000-0000-0000-0000-0000000002a5','1a5c0000-0000-0000-0000-0000000002f3','opening',10,'1a5c0000-0000-0000-0000-000000000105'),
  ('1a5c0000-0000-0000-0000-0000000002a5','1a5c0000-0000-0000-0000-0000000002f3','increase',20,'1a5c0000-0000-0000-0000-000000000105'),
  ('1a5c0000-0000-0000-0000-0000000002a5','1a5c0000-0000-0000-0000-0000000002f3','value_only',30,'1a5c0000-0000-0000-0000-000000000105'),
  ('1a5c0000-0000-0000-0000-0000000002a5','1a5c0000-0000-0000-0000-0000000002f3','decrease',40,'1a5c0000-0000-0000-0000-000000000105'),
  ('1a5c0000-0000-0000-0000-0000000002a5','1a5c0000-0000-0000-0000-0000000002f3','allowance',50,'1a5c0000-0000-0000-0000-000000000105');

INSERT INTO public.inventory_source_type_ranks (
  company_id,order_policy_id,source_document_type,source_type_rank,created_by
) VALUES (
  '1a5c0000-0000-0000-0000-0000000002a5',
  '1a5c0000-0000-0000-0000-0000000002f3',
  'IA5_CERTIFICATION',100,
  '1a5c0000-0000-0000-0000-000000000105'
);

INSERT INTO public.inventory_transition_ranks (
  company_id,order_policy_id,source_document_type,source_transition,
  transition_rank,created_by
) VALUES (
  '1a5c0000-0000-0000-0000-0000000002a5',
  '1a5c0000-0000-0000-0000-0000000002f3',
  'IA5_CERTIFICATION','ACCEPTED',100,
  '1a5c0000-0000-0000-0000-000000000105'
);

-- ── F. T-04 / T-06 / T-07 fixture-level authority ───────────────────────────
SELECT is(
  (SELECT string_agg(effect_class||'='||effect_rank, ',' ORDER BY effect_rank)
     FROM public.inventory_event_effect_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'),
  'opening=10,increase=20,value_only=30,decrease=40,allowance=50',
  'T-07 fixture preserves the complete frozen E3 sparse rank set');                       -- 34

SELECT is(
  (SELECT r.document_order_key_algorithm||':'||s.source_type_rank
     FROM public.ref_inventory_event_source_types r
     JOIN public.inventory_source_type_ranks s
       ON s.source_document_type=r.source_document_type
    WHERE r.source_document_type='IA5_CERTIFICATION'
      AND s.order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'),
  'canonical_source_document_id:100',
  'T-04 resolves the persisted E5 selector and exactly one certification E4 rank');       -- 35

SELECT is(
  (SELECT source_transition||':'||transition_rank
     FROM public.inventory_transition_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'
      AND source_document_type='IA5_CERTIFICATION'),
  'ACCEPTED:100',
  'T-06 resolves exactly one ACCEPTED transition rank');                                 -- 36

SELECT is(
  (SELECT string_agg(m.key||'='||er.effect_rank, ',' ORDER BY m.key)
     FROM public.ref_inventory_event_source_types r
     CROSS JOIN LATERAL jsonb_each_text(r.event_effect_map) m
     JOIN public.inventory_event_effect_ranks er
       ON er.effect_class=m.value
      AND er.order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'
    WHERE r.source_document_type='IA5_CERTIFICATION'
      AND r.same_time_class='event_effect_map'),
  'quantity_decrease=40,quantity_increase=20,value_only=30',
  'T-07 resolves every certification effect through its exact E3 rank');                  -- 37

SELECT ok(
  (SELECT inc.effect_rank < dec.effect_rank
     FROM public.inventory_event_effect_ranks inc
     JOIN public.inventory_event_effect_ranks dec
       ON dec.order_policy_id=inc.order_policy_id
    WHERE inc.order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'
      AND inc.effect_class='increase'
      AND dec.effect_class='decrease'),
  'T-07 proves the frozen increase=20 before decrease=40 convention');                    -- 38

SELECT is(
  (SELECT count(*)::int FROM public.inventory_transition_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'
      AND source_document_type='IA5_CERTIFICATION'
      AND source_transition='REJECTED'),
  0, 'T-06 installs no fallback for a missing transition');                              -- 39

SELECT is(
  (SELECT count(*)::int FROM public.inventory_source_type_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'
      AND source_document_type='UNKNOWN_SOURCE'),
  0, 'T-04 installs no fallback for an unknown source type');                            -- 40

SELECT is(
  (SELECT count(*)::int FROM public.inventory_event_effect_ranks
    WHERE order_policy_id='1a5c0000-0000-0000-0000-0000000002f3'
      AND effect_class='unknown'),
  0, 'T-07 installs no fallback for an unknown effect class');                           -- 41

SELECT throws_ok(
  $$INSERT INTO public.inventory_event_effect_ranks
      (company_id,order_policy_id,effect_class,effect_rank,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000002a5',
      '1a5c0000-0000-0000-0000-0000000002f3','increase',21,
      '1a5c0000-0000-0000-0000-000000000105')$$,
  '23505', NULL,
  'a duplicate E3 class is rejected instead of ambiguously resolved');                    -- 42

SELECT throws_ok(
  $$INSERT INTO public.inventory_source_type_ranks
      (company_id,order_policy_id,source_document_type,source_type_rank,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000002a5',
      '1a5c0000-0000-0000-0000-0000000002f3','IA5_CERTIFICATION',101,
      '1a5c0000-0000-0000-0000-000000000105')$$,
  '23505', NULL, 'a duplicate E4 source authority is rejected');                         -- 43

SELECT throws_ok(
  $$INSERT INTO public.inventory_transition_ranks
      (company_id,order_policy_id,source_document_type,source_transition,
       transition_rank,created_by)
    VALUES ('1a5c0000-0000-0000-0000-0000000002a5',
      '1a5c0000-0000-0000-0000-0000000002f3','IA5_CERTIFICATION','ACCEPTED',101,
      '1a5c0000-0000-0000-0000-000000000105')$$,
  '23505', NULL, 'a duplicate E7 transition authority is rejected');                     -- 44

-- ── G. Boundaries remain unchanged before the final fixture rollback ─────────
SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types),
  1, 'the fixture reads but never extends or updates the persistent registry');           -- 45

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  (SELECT event_rows FROM wp2_pre),
  'WP-2 fixture creates no inventory event');                                             -- 46

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp2_pre),
  'WP-2 fixture creates no journal entry');                                               -- 47

SELECT is(
  (SELECT count(*)::int FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'
      AND is_certification_only AND NOT is_production_enabled),
  1, 'T-27 dormancy remains true through certification-fixture resolution');              -- 48

SELECT * FROM finish();
ROLLBACK;
