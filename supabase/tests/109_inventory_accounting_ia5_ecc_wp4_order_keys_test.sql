-- =============================================================================
-- INVENTORY-IA5-ECC-WP4-001 — ECC order-key contract
--
-- Verifies the implementation surface of IA-5 ECC Hardening Work Package 4
-- (migration 20260731000019), without auditing or certifying WP-4 itself:
--   * exact 31-column shape, 24 governed keys/constraints, four indexes,
--     two triggers, RLS, policy, and grants;
--   * the deliberate mutability asymmetry — every economic, identity, and
--     version column is immutable, while resolution_state advances
--     current -> superseded once and only once;
--   * the per-event sidecar dormancy decision — no dormancy column, no blanket
--     immutability trigger, and no trigger added to inventory_events;
--   * the structural/fixture portions of T-03 Duplicate identity and
--     T-24 Immutability per design §23.3 and specification §7;
--   * fixture data exists only in this transaction and is removed by the final
--     ROLLBACK.
--
-- Comparators, ordering outcomes, tie-breaks, replay, fingerprints, costing,
-- re-resolution, and C-01 remain later authorised work and are NOT claimed.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(71);

CREATE TEMP TABLE wp4_pre AS
SELECT
  (SELECT count(*)::int FROM public.inventory_events) AS event_rows,
  (SELECT count(*)::int FROM public.journal_entries) AS journal_rows;

-- ── A. Exact M4 shape ───────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'),
  31, 'WP-4 installs exactly the 31 authorised order-key columns');            -- 1

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'
      AND is_nullable='NO'),
  30, 'exactly one column is nullable — correction_root_event_id');            -- 2

SELECT is(
  (SELECT column_name::text FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'
      AND is_nullable='YES'),
  'correction_root_event_id',
  'the sole nullable column is the correction root (null only at depth 0)');   -- 3

SELECT is(
  (SELECT string_agg(column_name||':'||data_type, ',' ORDER BY ordinal_position)
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'
      AND column_name IN ('economic_effect_rank','source_type_rank',
                          'transition_rank','occurrence_ordinal',
                          'event_ordinal','source_line_ordinal',
                          'correction_chain_depth')),
  'economic_effect_rank:smallint,source_type_rank:smallint,'
  || 'source_line_ordinal:integer,transition_rank:smallint,'
  || 'occurrence_ordinal:bigint,event_ordinal:integer,'
  || 'correction_chain_depth:integer',
  'ordinal and rank column types match the governing contract exactly');       -- 4

SELECT is(
  (SELECT string_agg(column_name, ',' ORDER BY column_name)
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'
      AND data_type='bytea'),
  'canonical_key_bytes,canonical_source_identity,correction_identity,'
  || 'document_order_key,ecc_key_digest',
  'the five bytea components are exactly the authorised ones');                -- 5

SELECT is(
  (SELECT column_default FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'
      AND column_name='resolution_state'),
  '''current''::text', 'resolution_state defaults to current');                -- 6

SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_order_keys'
      AND column_name IN ('activation_state','foundation_state')),
  0, 'the order key carries NO dormancy column — it is a per-event sidecar');  -- 7

-- ── B. Governed keys and constraints ────────────────────────────────────────
SELECT set_eq(
  $$SELECT conname::text FROM pg_constraint
     WHERE conrelid='public.inventory_event_order_keys'::regclass$$,
  $$VALUES ('inventory_event_order_keys_pkey'),
           ('inventory_event_order_keys_identity_uq'),
           ('inventory_event_order_keys_inventory_event_id_fkey'),
           ('inventory_event_order_keys_company_id_fkey'),
           ('inventory_event_order_keys_valuation_stream_id_fkey'),
           ('inventory_event_order_keys_correction_root_event_id_fkey'),
           ('inventory_event_order_keys_order_policy_version_id_fkey'),
           ('inventory_event_order_keys_registry_source_document_type_fkey'),
           ('inventory_event_order_keys_canonical_form_version_id_fkey'),
           ('inventory_event_order_keys_scope_resolution_version_id_fkey'),
           ('inventory_event_order_keys_correction_graph_version_id_fkey'),
           ('inventory_event_order_keys_created_by_fkey'),
           ('inventory_event_order_keys_economic_effect_class_check'),
           ('inventory_event_order_keys_economic_effect_rank_check'),
           ('inventory_event_order_keys_source_type_rank_check'),
           ('inventory_event_order_keys_source_line_ordinal_check'),
           ('inventory_event_order_keys_transition_rank_check'),
           ('inventory_event_order_keys_occurrence_ordinal_check'),
           ('inventory_event_order_keys_event_ordinal_check'),
           ('inventory_event_order_keys_correction_placement_class_check'),
           ('inventory_event_order_keys_correction_chain_depth_check'),
           ('inventory_event_order_keys_correction_root_check'),
           ('inventory_event_order_keys_ecc_key_digest_check'),
           ('inventory_event_order_keys_resolution_state_check')$$,
  'exactly the 24 governed keys and constraints exist under their exact names');-- 8

SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname='inventory_event_order_keys_pkey'),
  'PRIMARY KEY (id)',
  'the primary key is the surrogate id — superseded resolutions are retained'); -- 9

SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname='inventory_event_order_keys_identity_uq'),
  'UNIQUE (valuation_stream_id, canonical_key_bytes)',
  'V-14/V-15 identity uniqueness is stream-scoped');                          -- 10

SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname='inventory_event_order_keys_correction_root_check'),
  'CHECK ((((correction_chain_depth = 0) AND (correction_root_event_id IS NULL))'
  || ' OR ((correction_chain_depth > 0) AND (correction_root_event_id IS NOT NULL))))',
  'depth 0 and a null correction root are mutually implied');                 -- 11

SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname='inventory_event_order_keys_registry_source_document_type_fkey'),
  'FOREIGN KEY (registry_source_document_type) REFERENCES '
  || 'ref_inventory_event_source_types(source_document_type)',
  'the registry element of V references the registry''s real key');           -- 12

SELECT cmp_ok(
  (SELECT max(octet_length(conname))::int FROM pg_constraint
    WHERE conrelid='public.inventory_event_order_keys'::regclass),
  '<=', 63,
  'every WP-4 constraint identifier fits the PostgreSQL 63-byte limit');      -- 13

-- ── C. Indexes ──────────────────────────────────────────────────────────────
SELECT set_eq(
  $$SELECT indexname::text FROM pg_indexes
     WHERE schemaname='public' AND tablename='inventory_event_order_keys'$$,
  $$VALUES ('inventory_event_order_keys_pkey'),
           ('inventory_event_order_keys_identity_uq'),
           ('inventory_event_order_keys_ecc_idx'),
           ('inventory_event_order_keys_event_current_uq'),
           ('inventory_event_order_keys_anchor_idx'),
           ('inventory_event_order_keys_version_idx')$$,
  'exactly the governed index set exists (four indexes plus two constraint-backed)');
                                                                              -- 14

SELECT alike(
  (SELECT indexdef FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='inventory_event_order_keys_event_current_uq'),
  '%UNIQUE%(inventory_event_id)%WHERE (resolution_state = ''current''::text)%',
  '1:1 per current resolution is a PARTIAL unique index');                    -- 15

SELECT unalike(
  (SELECT indexdef FROM pg_indexes
    WHERE schemaname='public' AND indexname='inventory_event_order_keys_ecc_idx'),
  '%causal%',
  'E2 is intentionally absent from the ECC scan index');                      -- 16

-- ── D. Trigger strategy and the mutability asymmetry ────────────────────────
SELECT set_eq(
  $$SELECT t.tgname||'|'||p.proname||'|'||t.tgenabled::text||'|'||t.tgtype::text
      FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
     WHERE t.tgrelid='public.inventory_event_order_keys'::regclass
       AND NOT t.tgisinternal$$,
  $$VALUES ('aa_inventory_event_order_keys_guard|fn_ia5_guard_inventory_order_key_foundation|A|31'),
           ('trg_inventory_event_order_keys_audit|fn_audit_trigger|O|5')$$,
  'the two authorised triggers have exact timing, events, functions, and enablement'); -- 17

SELECT is(
  (SELECT count(*)::int FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='public.inventory_event_order_keys'::regclass
      AND NOT t.tgisinternal
      AND p.proname='fn_ia5_reject_immutable_inventory_fact'),
  0, 'the order key carries NO blanket immutability trigger — §3.2');         -- 18

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_events'::regclass AND NOT tgisinternal),
  3, 'WP-4 added NO trigger to inventory_events — its set is still exactly 3'); -- 19

-- ── E. Security boundary ────────────────────────────────────────────────────
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
    WHERE oid='public.inventory_event_order_keys'::regclass),
  'RLS is enabled on the order-key table');                                   -- 20

SELECT set_eq(
  $$SELECT policyname||'|'||cmd||'|'||roles::text||'|'||qual FROM pg_policies
     WHERE schemaname='public' AND tablename='inventory_event_order_keys'$$,
  $$VALUES ('inventory_event_order_keys_read|SELECT|{authenticated}|is_company_member(company_id)')$$,
  'exactly one governed member-gated SELECT policy exists');                  -- 21

SELECT set_eq(
  $$SELECT grantee||':'||privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name='inventory_event_order_keys'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')$$,
  $$VALUES ('authenticated:SELECT'), ('service_role:SELECT')$$,
  'authenticated and service_role hold SELECT only; no client write grant exists'); -- 22

SELECT is_empty(
  $$SELECT grantee::text FROM information_schema.role_routine_grants
     WHERE routine_schema='public'
       AND routine_name='fn_ia5_guard_inventory_order_key_foundation'
       AND grantee IN ('PUBLIC','anon','authenticated','service_role')$$,
  'the WP-4 guard function is owner-mediated with no client EXECUTE');        -- 23

-- ── F. Dormancy and migration boundary ──────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.inventory_event_order_keys),
  0, 'the order-key table is created empty');                                 -- 24

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events),
  0, 'inventory_events remains empty');                                       -- 25

SELECT is(
  (
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prokind IN ('f','p')
        AND p.proname <> 'fn_ia5_guard_inventory_order_key_foundation'
        AND pg_get_functiondef(p.oid) ~ 'inventory_event_order_keys')
    +
    (SELECT count(*) FROM pg_views WHERE schemaname='public'
       AND definition ~ 'inventory_event_order_keys')
  )::int,
  0, 'no runtime function or view consumes the order-key table');             -- 26

-- ── G. Certification-only fixture ───────────────────────────────────────────
INSERT INTO auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '1a5d0000-0000-0000-0000-000000000109',
  'authenticated','authenticated','ecc-wp4@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}'
);

INSERT INTO public.companies (
  id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
  signatory_name,signatory_position,created_by,updated_by,
  functional_currency_code,reporting_currency_code
) VALUES
  ('1a5d0000-0000-0000-0000-0000000004a1','corporation','ECC WP4 Company A',
   'Trading','520-000-109-00001','vat','calendar','A','B','Makati',
   'Metro Manila','1200','ecc-wp4a@test.local','WP4','President',
   '1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-000000000109',
   'PHP','PHP'),
  ('1a5d0000-0000-0000-0000-0000000004a2','corporation','ECC WP4 Company B',
   'Trading','520-000-109-00002','vat','calendar','A','B','Makati',
   'Metro Manila','1200','ecc-wp4b@test.local','WP4','President',
   '1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-000000000109',
   'PHP','PHP');

INSERT INTO public.user_company_memberships (user_id,company_id,role,granted_by)
VALUES
  ('1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-0000000004a1',
   'owner','1a5d0000-0000-0000-0000-000000000109'),
  ('1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-0000000004a2',
   'owner','1a5d0000-0000-0000-0000-000000000109')
ON CONFLICT DO NOTHING;

INSERT INTO public.branches (
  id,company_id,branch_code,branch_name,
  address_line_1,address_line_2,city,province,zip_code,created_by,updated_by
) VALUES
  ('1a5d0000-0000-0000-0000-0000000004b1','1a5d0000-0000-0000-0000-0000000004a1',
   'HO','Head Office','1 Test','Bldg','Makati','Metro Manila','1200',
   '1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-000000000109'),
  ('1a5d0000-0000-0000-0000-0000000004b2','1a5d0000-0000-0000-0000-0000000004a2',
   'HO','Head Office','2 Test','Bldg','Makati','Metro Manila','1200',
   '1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-000000000109');

INSERT INTO public.item_categories (id,company_id,category_code,category_name)
VALUES
  ('1a5d0000-0000-0000-0000-0000000004c1','1a5d0000-0000-0000-0000-0000000004a1','WP4','WP4'),
  ('1a5d0000-0000-0000-0000-0000000004c2','1a5d0000-0000-0000-0000-0000000004a2','WP4','WP4');

INSERT INTO public.units_of_measure (id,company_id,uom_code,description)
VALUES
  ('1a5d0000-0000-0000-0000-0000000004d1','1a5d0000-0000-0000-0000-0000000004a1','EA','Each'),
  ('1a5d0000-0000-0000-0000-0000000004d2','1a5d0000-0000-0000-0000-0000000004a2','EA','Each');

INSERT INTO public.warehouses (
  id,company_id,branch_id,warehouse_code,warehouse_name,created_by,updated_by
) VALUES
  ('1a5d0000-0000-0000-0000-0000000004e1','1a5d0000-0000-0000-0000-0000000004a1',
   '1a5d0000-0000-0000-0000-0000000004b1','MAIN','Main',
   '1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-000000000109'),
  ('1a5d0000-0000-0000-0000-0000000004e2','1a5d0000-0000-0000-0000-0000000004a2',
   '1a5d0000-0000-0000-0000-0000000004b2','MAIN','Main',
   '1a5d0000-0000-0000-0000-000000000109','1a5d0000-0000-0000-0000-000000000109');

INSERT INTO public.items (
  id,company_id,item_code,description,item_type,category_id,uom_id,
  costing_method,created_by,updated_by
) VALUES
  ('1a5d0000-0000-0000-0000-0000000004f1','1a5d0000-0000-0000-0000-0000000004a1',
   'WP4-ITEM-A','WP4 Item A','inventory_item',
   '1a5d0000-0000-0000-0000-0000000004c1','1a5d0000-0000-0000-0000-0000000004d1',
   'weighted_average','1a5d0000-0000-0000-0000-000000000109',
   '1a5d0000-0000-0000-0000-000000000109'),
  ('1a5d0000-0000-0000-0000-0000000004f2','1a5d0000-0000-0000-0000-0000000004a2',
   'WP4-ITEM-B','WP4 Item B','inventory_item',
   '1a5d0000-0000-0000-0000-0000000004c2','1a5d0000-0000-0000-0000-0000000004d2',
   'weighted_average','1a5d0000-0000-0000-0000-000000000109',
   '1a5d0000-0000-0000-0000-000000000109');

-- The sanctioned owner-mediated bundle builds each company's dormant policy /
-- profile / cost-formula / scope chain.
CREATE TEMP TABLE wp4_bundle AS
SELECT 'A'::text AS side,
  '1a5d0000-0000-0000-0000-0000000004a1'::uuid AS company_id,
  '1a5d0000-0000-0000-0000-0000000004f1'::uuid AS item_id,
  public.fn_ia5_create_dormant_policy_bundle(
    '1a5d0000-0000-0000-0000-0000000004a1','1a5d0000-0000-0000-0000-0000000004f1',
    'warehouse',NULL,'1a5d0000-0000-0000-0000-0000000004e1',
    'moving_weighted_average',6::smallint,'PHP',2::smallint,
    '2026-01-01',NULL,'1a5d0000-0000-0000-0000-000000000109') AS bundle
UNION ALL
SELECT 'B'::text,
  '1a5d0000-0000-0000-0000-0000000004a2'::uuid,
  '1a5d0000-0000-0000-0000-0000000004f2'::uuid,
  public.fn_ia5_create_dormant_policy_bundle(
    '1a5d0000-0000-0000-0000-0000000004a2','1a5d0000-0000-0000-0000-0000000004f2',
    'warehouse',NULL,'1a5d0000-0000-0000-0000-0000000004e2',
    'moving_weighted_average',6::smallint,'PHP',2::smallint,
    '2026-01-01',NULL,'1a5d0000-0000-0000-0000-000000000109');

-- One WP-3 stream per company, resolving the same scope_code for its own item.
INSERT INTO public.inventory_valuation_streams
  (id,company_id,item_id,scope_code,created_by)
SELECT
  CASE side WHEN 'A' THEN '1a5d0000-0000-0000-0000-000000000501'::uuid
            ELSE '1a5d0000-0000-0000-0000-000000000502'::uuid END,
  company_id, item_id,
  (SELECT s.scope_code FROM public.inventory_valuation_scopes s
    WHERE s.id = (wp4_bundle.bundle->>'valuation_scope_id')::uuid),
  '1a5d0000-0000-0000-0000-000000000109'
FROM wp4_bundle;

-- Two admitted events per company via the certified occurrence path.
CREATE TEMP TABLE wp4_occ AS
SELECT 'A'::text AS side, public.fn_ia5_record_dormant_inventory_occurrence(
  '1a5d0000-0000-0000-0000-0000000004a1','IA5_CERTIFICATION',
  '1a5d0000-0000-0000-0000-000000000511','1a5d0000-0000-0000-0000-000000000521',
  'ACCEPTED',1,'wp4-idempotency-key-a-0001',repeat('a',64),
  '2026-06-30T10:00:00Z','1a5d0000-0000-0000-0000-000000000109',
  jsonb_build_array(jsonb_build_object(
    'valuation_scope_id',(SELECT bundle->>'valuation_scope_id' FROM wp4_bundle WHERE side='A'),
    'event_type','foundation_receipt','event_effect','quantity_increase',
    'event_sequence',1,'effective_at','2026-06-30T10:00:00Z',
    'accounting_date','2026-06-30','item_id','1a5d0000-0000-0000-0000-0000000004f1',
    'physical_warehouse_id','1a5d0000-0000-0000-0000-0000000004e1',
    'source_uom_id','1a5d0000-0000-0000-0000-0000000004d1',
    'base_uom_id','1a5d0000-0000-0000-0000-0000000004d1',
    'source_quantity','2.000000','base_quantity','2.000000',
    'uom_conversion_factor','1.000000000000',
    'immutable_source_evidence',jsonb_build_object('certification_case','wp4-a'),
    'source_evidence_fingerprint',repeat('b',64),'reason_code','IA5_CERTIFICATION',
    'value',jsonb_build_object(
      'value_role','inventory_value',
      'authoritative_transaction_amount','100.00000000',
      'authoritative_functional_amount','100.00000000',
      'gl_basis_amount','100.00000000',
      'derived_unit_rate','50.000000000000',
      'residual_units',0,
      'calculation_evidence',jsonb_build_object('authority','WP-4 fixture'))))
) AS result
UNION ALL
SELECT 'B'::text, public.fn_ia5_record_dormant_inventory_occurrence(
  '1a5d0000-0000-0000-0000-0000000004a2','IA5_CERTIFICATION',
  '1a5d0000-0000-0000-0000-000000000512','1a5d0000-0000-0000-0000-000000000522',
  'ACCEPTED',1,'wp4-idempotency-key-b-0001',repeat('c',64),
  '2026-06-30T10:00:00Z','1a5d0000-0000-0000-0000-000000000109',
  jsonb_build_array(jsonb_build_object(
    'valuation_scope_id',(SELECT bundle->>'valuation_scope_id' FROM wp4_bundle WHERE side='B'),
    'event_type','foundation_receipt','event_effect','quantity_increase',
    'event_sequence',1,'effective_at','2026-06-30T10:00:00Z',
    'accounting_date','2026-06-30','item_id','1a5d0000-0000-0000-0000-0000000004f2',
    'physical_warehouse_id','1a5d0000-0000-0000-0000-0000000004e2',
    'source_uom_id','1a5d0000-0000-0000-0000-0000000004d2',
    'base_uom_id','1a5d0000-0000-0000-0000-0000000004d2',
    'source_quantity','2.000000','base_quantity','2.000000',
    'uom_conversion_factor','1.000000000000',
    'immutable_source_evidence',jsonb_build_object('certification_case','wp4-b'),
    'source_evidence_fingerprint',repeat('d',64),'reason_code','IA5_CERTIFICATION',
    'value',jsonb_build_object(
      'value_role','inventory_value',
      'authoritative_transaction_amount','100.00000000',
      'authoritative_functional_amount','100.00000000',
      'gl_basis_amount','100.00000000',
      'derived_unit_rate','50.000000000000',
      'residual_units',0,
      'calculation_evidence',jsonb_build_object('authority','WP-4 fixture'))))
);

CREATE TEMP TABLE wp4_ref AS
SELECT
  e.id AS event_id, e.company_id,
  (SELECT g.id FROM public.inventory_valuation_streams g
    WHERE g.company_id = e.company_id) AS stream_id,
  e.valuation_scope_id,
  (SELECT p.id FROM public.inventory_event_order_policies p LIMIT 1) AS policy_id,
  (SELECT c.id FROM public.inventory_canonical_form_versions c LIMIT 1) AS form_id,
  (SELECT r.id FROM public.inventory_correction_graph_versions r LIMIT 1) AS graph_id,
  CASE WHEN e.company_id='1a5d0000-0000-0000-0000-0000000004a1' THEN 'A' ELSE 'B' END AS side
FROM public.inventory_events e;

SELECT is((SELECT count(*)::int FROM wp4_ref), 2,
  'the fixture admitted exactly two events, one per company');                -- 27

-- The version vector needs one policy/form/graph version; WP-1 tables are
-- empty by governance, so the fixture supplies them inside this transaction.
INSERT INTO public.inventory_event_order_policies
  (id,company_id,policy_code,version_no,effective_from,created_by)
VALUES ('1a5d0000-0000-0000-0000-000000000531',
        '1a5d0000-0000-0000-0000-0000000004a1','WP4_POLICY',1,'2026-01-01',
        '1a5d0000-0000-0000-0000-000000000109');

INSERT INTO public.inventory_canonical_form_versions
  (id,company_id,version_code,activated_from,created_by)
VALUES ('1a5d0000-0000-0000-0000-000000000532',
        '1a5d0000-0000-0000-0000-0000000004a1','WP4_FORM','2026-01-01',
        '1a5d0000-0000-0000-0000-000000000109');

INSERT INTO public.inventory_correction_graph_versions
  (id,company_id,version_no,effective_from,created_by)
VALUES ('1a5d0000-0000-0000-0000-000000000533',
        '1a5d0000-0000-0000-0000-0000000004a1',1,'2026-01-01',
        '1a5d0000-0000-0000-0000-000000000109');

-- One current order key for company A's event.
INSERT INTO public.inventory_event_order_keys (
  id, inventory_event_id, company_id, valuation_stream_id,
  economic_effective_at, source_precision_code, economic_effect_class,
  economic_effect_rank, source_type_rank, document_order_key,
  source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
  canonical_source_identity, correction_placement_class, correction_chain_depth,
  correction_effective_at, correction_approved_at, correction_identity,
  correction_root_event_id, order_policy_version_id,
  registry_source_document_type, canonical_form_version_id,
  scope_resolution_version_id, correction_graph_version_id,
  canonical_key_bytes, ecc_key_digest, created_by
)
SELECT
  '1a5d0000-0000-0000-0000-000000000541',
  r.event_id, r.company_id, r.stream_id,
  '2026-06-30T10:00:00Z', 'IA5_EXACT', 'increase',
  20::smallint, 10::smallint, '\x0001'::bytea,
  1, 10::smallint, 1::bigint, 1,
  '\x0002'::bytea, 'base', 0,
  '-infinity'::timestamptz, '-infinity'::timestamptz, '\x00'::bytea,
  NULL,
  (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
  'IA5_CERTIFICATION',
  (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
  r.valuation_scope_id,
  (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
  '\x1001'::bytea, decode(repeat('ab',32),'hex'),
  '1a5d0000-0000-0000-0000-000000000109'
FROM wp4_ref r WHERE r.side='A';

SELECT is(
  (SELECT resolution_state FROM public.inventory_event_order_keys
    WHERE id='1a5d0000-0000-0000-0000-000000000541'),
  'current', 'a new order key is born in the current resolution');            -- 28

-- ── H. T-03 duplicate identity ──────────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.inventory_event_order_keys (
      inventory_event_id, company_id, valuation_stream_id,
      economic_effective_at, source_precision_code, economic_effect_class,
      economic_effect_rank, source_type_rank, document_order_key,
      source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
      canonical_source_identity, correction_placement_class,
      correction_chain_depth, correction_effective_at, correction_approved_at,
      correction_identity, order_policy_version_id,
      registry_source_document_type, canonical_form_version_id,
      scope_resolution_version_id, correction_graph_version_id,
      canonical_key_bytes, ecc_key_digest, created_by, resolution_state)
    SELECT r.event_id, r.company_id, r.stream_id,
      '2026-06-30T11:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
      '\x0003'::bytea,2,10::smallint,2::bigint,2,'\x0004'::bytea,'base',0,
      '-infinity'::timestamptz,'-infinity'::timestamptz,'\x00'::bytea,
      (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
      'IA5_CERTIFICATION',
      (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
      r.valuation_scope_id,
      (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
      '\x1001'::bytea, decode(repeat('cd',32),'hex'),
      '1a5d0000-0000-0000-0000-000000000109','superseded'
    FROM wp4_ref r WHERE r.side='A'$$,
  '23505', NULL,
  'T-03: a duplicate (valuation_stream_id, canonical_key_bytes) is rejected'); -- 29

SELECT throws_ok(
  $$INSERT INTO public.inventory_event_order_keys (
      inventory_event_id, company_id, valuation_stream_id,
      economic_effective_at, source_precision_code, economic_effect_class,
      economic_effect_rank, source_type_rank, document_order_key,
      source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
      canonical_source_identity, correction_placement_class,
      correction_chain_depth, correction_effective_at, correction_approved_at,
      correction_identity, order_policy_version_id,
      registry_source_document_type, canonical_form_version_id,
      scope_resolution_version_id, correction_graph_version_id,
      canonical_key_bytes, ecc_key_digest, created_by)
    SELECT r.event_id, r.company_id, r.stream_id,
      '2026-06-30T12:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
      '\x0005'::bytea,3,10::smallint,3::bigint,3,'\x0006'::bytea,'base',0,
      '-infinity'::timestamptz,'-infinity'::timestamptz,'\x00'::bytea,
      (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
      'IA5_CERTIFICATION',
      (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
      r.valuation_scope_id,
      (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
      '\x2002'::bytea, decode(repeat('ef',32),'hex'),
      '1a5d0000-0000-0000-0000-000000000109'
    FROM wp4_ref r WHERE r.side='A'$$,
  '23505', NULL,
  'T-03: a second CURRENT resolution for one event is rejected');             -- 30

-- ── I. T-24 immutability and the governed supersession ──────────────────────
SELECT throws_ok(
  $$DELETE FROM public.inventory_event_order_keys
     WHERE id='1a5d0000-0000-0000-0000-000000000541'$$,
  '23514',
  'IA-5 ECC WP-4: order keys are permanent evidence; DELETE is rejected',
  'T-24: DELETE is rejected — an issued order key is permanent');             -- 31

-- Exercise every one of the 30 non-state columns. Each statement supplies a
-- distinct replacement that would otherwise be valid enough to reach the
-- BEFORE guard; a missed comparison is therefore observable rather than
-- hidden behind a no-op UPDATE.
SELECT throws_ok(
  format(
    'UPDATE public.inventory_event_order_keys SET %I = %s '
    || 'WHERE id = ''1a5d0000-0000-0000-0000-000000000541''',
    column_name, replacement_sql
  ),
  '23514',
  'IA-5 ECC WP-4: order-key components are immutable; only resolution_state may change',
  'T-24: ' || column_name || ' is immutable'
)
FROM (VALUES
  ('id', '''1a5d0000-0000-0000-0000-000000000549''::uuid'),
  ('inventory_event_id', '(SELECT event_id FROM wp4_ref WHERE side=''B'')'),
  ('company_id', '''1a5d0000-0000-0000-0000-0000000004a2''::uuid'),
  ('valuation_stream_id', '(SELECT stream_id FROM wp4_ref WHERE side=''B'')'),
  ('economic_effective_at', '''2026-06-30T10:00:01Z''::timestamptz'),
  ('source_precision_code', '''IA5_MICROSECOND''::text'),
  ('economic_effect_class', '''decrease''::text'),
  ('economic_effect_rank', '21::smallint'),
  ('source_type_rank', '11::smallint'),
  ('document_order_key', '''\x0101''::bytea'),
  ('source_line_ordinal', '2::integer'),
  ('transition_rank', '11::smallint'),
  ('occurrence_ordinal', '2::bigint'),
  ('event_ordinal', '2::integer'),
  ('canonical_source_identity', '''\x0202''::bytea'),
  ('correction_placement_class', '''independent''::text'),
  ('correction_chain_depth', '1::integer'),
  ('correction_effective_at', '''2026-06-30T10:00:00Z''::timestamptz'),
  ('correction_approved_at', '''2026-06-30T10:00:00Z''::timestamptz'),
  ('correction_identity', '''\x0303''::bytea'),
  ('correction_root_event_id', '(SELECT event_id FROM wp4_ref WHERE side=''A'')'),
  ('order_policy_version_id', 'gen_random_uuid()'),
  ('registry_source_document_type', '''NOT_AUTHORISED''::text'),
  ('canonical_form_version_id', 'gen_random_uuid()'),
  ('scope_resolution_version_id', '(SELECT valuation_scope_id FROM wp4_ref WHERE side=''B'')'),
  ('correction_graph_version_id', 'gen_random_uuid()'),
  ('canonical_key_bytes', '''\x0404''::bytea'),
  ('ecc_key_digest', 'decode(repeat(''cd'',32),''hex'')'),
  ('created_by', 'gen_random_uuid()'),
  ('created_at', '''2026-06-30T10:00:01Z''::timestamptz')
) AS immutable_columns(column_name, replacement_sql);                         -- 32-61

-- The one governed mutation.
UPDATE public.inventory_event_order_keys
   SET resolution_state = 'superseded'
 WHERE id='1a5d0000-0000-0000-0000-000000000541';

SELECT is(
  (SELECT resolution_state FROM public.inventory_event_order_keys
    WHERE id='1a5d0000-0000-0000-0000-000000000541'),
  'superseded',
  'current -> superseded is the one permitted mutation (V-35 re-resolution)'); -- 62

SELECT throws_ok(
  $$UPDATE public.inventory_event_order_keys
       SET resolution_state = 'current'
     WHERE id='1a5d0000-0000-0000-0000-000000000541'$$,
  '23514',
  'IA-5 ECC WP-4: resolution_state may only move from current to superseded',
  'T-24: superseded -> current is rejected — history is never revived');      -- 63

SELECT throws_ok(
  $$INSERT INTO public.inventory_event_order_keys (
      inventory_event_id, company_id, valuation_stream_id,
      economic_effective_at, source_precision_code, economic_effect_class,
      economic_effect_rank, source_type_rank, document_order_key,
      source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
      canonical_source_identity, correction_placement_class,
      correction_chain_depth, correction_effective_at, correction_approved_at,
      correction_identity, order_policy_version_id,
      registry_source_document_type, canonical_form_version_id,
      scope_resolution_version_id, correction_graph_version_id,
      canonical_key_bytes, ecc_key_digest, created_by, resolution_state)
    SELECT r.event_id, r.company_id, r.stream_id,
      '2026-06-30T10:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
      '\x00f1'::bytea,1,10::smallint,1::bigint,1,'\x00f2'::bytea,'base',0,
      '-infinity'::timestamptz,'-infinity'::timestamptz,'\x00'::bytea,
      (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
      'IA5_CERTIFICATION',
      (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
      r.valuation_scope_id,
      (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
      '\xf00f'::bytea, decode(repeat('9a',32),'hex'),
      '1a5d0000-0000-0000-0000-000000000109','archived'
    FROM wp4_ref r WHERE r.side='B'$$,
  '23514', NULL,
  'an unlisted resolution_state is rejected by the domain CHECK');            -- 64

-- With the prior row demoted, a successor CURRENT resolution now coexists.
INSERT INTO public.inventory_event_order_keys (
  id, inventory_event_id, company_id, valuation_stream_id,
  economic_effective_at, source_precision_code, economic_effect_class,
  economic_effect_rank, source_type_rank, document_order_key,
  source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
  canonical_source_identity, correction_placement_class, correction_chain_depth,
  correction_effective_at, correction_approved_at, correction_identity,
  order_policy_version_id, registry_source_document_type,
  canonical_form_version_id, scope_resolution_version_id,
  correction_graph_version_id, canonical_key_bytes, ecc_key_digest, created_by
)
SELECT
  '1a5d0000-0000-0000-0000-000000000542',
  r.event_id, r.company_id, r.stream_id,
  '2026-06-30T10:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
  '\x0001'::bytea,1,10::smallint,1::bigint,1,'\x0002'::bytea,'base',0,
  '-infinity'::timestamptz,'-infinity'::timestamptz,'\x00'::bytea,
  (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
  'IA5_CERTIFICATION',
  (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
  r.valuation_scope_id,
  (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
  '\x3003'::bytea, decode(repeat('12',32),'hex'),
  '1a5d0000-0000-0000-0000-000000000109'
FROM wp4_ref r WHERE r.side='A';

SELECT is(
  (SELECT count(*)::int FROM public.inventory_event_order_keys
    WHERE inventory_event_id=(SELECT event_id FROM wp4_ref WHERE side='A')),
  2, 'one event retains a superseded resolution alongside its current one');  -- 65

SELECT is(
  (SELECT count(*)::int FROM public.inventory_event_order_keys
    WHERE inventory_event_id=(SELECT event_id FROM wp4_ref WHERE side='A')
      AND resolution_state='current'),
  1, 'exactly one CURRENT resolution survives per event');                    -- 66

-- ── J. Company isolation (guard rules 4-6) ─────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.inventory_event_order_keys (
      inventory_event_id, company_id, valuation_stream_id,
      economic_effective_at, source_precision_code, economic_effect_class,
      economic_effect_rank, source_type_rank, document_order_key,
      source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
      canonical_source_identity, correction_placement_class,
      correction_chain_depth, correction_effective_at, correction_approved_at,
      correction_identity, order_policy_version_id,
      registry_source_document_type, canonical_form_version_id,
      scope_resolution_version_id, correction_graph_version_id,
      canonical_key_bytes, ecc_key_digest, created_by)
    SELECT (SELECT event_id FROM wp4_ref WHERE side='B'),
      '1a5d0000-0000-0000-0000-0000000004a1',
      (SELECT stream_id FROM wp4_ref WHERE side='A'),
      '2026-06-30T10:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
      '\x0007'::bytea,1,10::smallint,1::bigint,1,'\x0008'::bytea,'base',0,
      '-infinity'::timestamptz,'-infinity'::timestamptz,'\x00'::bytea,
      (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
      'IA5_CERTIFICATION',
      (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
      (SELECT valuation_scope_id FROM wp4_ref WHERE side='A'),
      (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
      '\x4004'::bytea, decode(repeat('34',32),'hex'),
      '1a5d0000-0000-0000-0000-000000000109'$$,
  '23514',
  'IA-5 ECC WP-4: order-key company 1a5d0000-0000-0000-0000-0000000004a1 does not match its event company 1a5d0000-0000-0000-0000-0000000004a2',
  'an order key naming another company''s event is rejected');                -- 67

SELECT throws_ok(
  $$INSERT INTO public.inventory_event_order_keys (
      inventory_event_id, company_id, valuation_stream_id,
      economic_effective_at, source_precision_code, economic_effect_class,
      economic_effect_rank, source_type_rank, document_order_key,
      source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
      canonical_source_identity, correction_placement_class,
      correction_chain_depth, correction_effective_at, correction_approved_at,
      correction_identity, order_policy_version_id,
      registry_source_document_type, canonical_form_version_id,
      scope_resolution_version_id, correction_graph_version_id,
      canonical_key_bytes, ecc_key_digest, created_by)
    SELECT (SELECT event_id FROM wp4_ref WHERE side='B'),
      '1a5d0000-0000-0000-0000-0000000004a2',
      (SELECT stream_id FROM wp4_ref WHERE side='A'),
      '2026-06-30T10:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
      '\x0009'::bytea,1,10::smallint,1::bigint,1,'\x000a'::bytea,'base',0,
      '-infinity'::timestamptz,'-infinity'::timestamptz,'\x00'::bytea,
      (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
      'IA5_CERTIFICATION',
      (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
      (SELECT valuation_scope_id FROM wp4_ref WHERE side='B'),
      (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
      '\x5005'::bytea, decode(repeat('56',32),'hex'),
      '1a5d0000-0000-0000-0000-000000000109'$$,
  '23514',
  'IA-5 ECC WP-4: order-key company 1a5d0000-0000-0000-0000-0000000004a2 does not match its stream company 1a5d0000-0000-0000-0000-0000000004a1',
  'an order key naming another company''s stream is rejected');               -- 68

SELECT throws_ok(
  $$INSERT INTO public.inventory_event_order_keys (
      inventory_event_id, company_id, valuation_stream_id,
      economic_effective_at, source_precision_code, economic_effect_class,
      economic_effect_rank, source_type_rank, document_order_key,
      source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal,
      canonical_source_identity, correction_placement_class,
      correction_chain_depth, correction_effective_at, correction_approved_at,
      correction_identity, correction_root_event_id, order_policy_version_id,
      registry_source_document_type, canonical_form_version_id,
      scope_resolution_version_id, correction_graph_version_id,
      canonical_key_bytes, ecc_key_digest, created_by)
    SELECT (SELECT event_id FROM wp4_ref WHERE side='B'),
      '1a5d0000-0000-0000-0000-0000000004a2',
      (SELECT stream_id FROM wp4_ref WHERE side='B'),
      '2026-06-30T10:00:00Z','IA5_EXACT','increase',20::smallint,10::smallint,
      '\x000b'::bytea,1,10::smallint,1::bigint,1,'\x000c'::bytea,'anchored',1,
      '2026-06-30T10:00:00Z'::timestamptz,
      '2026-06-30T10:00:01Z'::timestamptz,'\x00'::bytea,
      (SELECT event_id FROM wp4_ref WHERE side='A'),
      (SELECT id FROM public.inventory_event_order_policies LIMIT 1),
      'IA5_CERTIFICATION',
      (SELECT id FROM public.inventory_canonical_form_versions LIMIT 1),
      (SELECT valuation_scope_id FROM wp4_ref WHERE side='B'),
      (SELECT id FROM public.inventory_correction_graph_versions LIMIT 1),
      '\x6006'::bytea, decode(repeat('78',32),'hex'),
      '1a5d0000-0000-0000-0000-000000000109'$$,
  '23514',
  'IA-5 ECC WP-4: correction root event belongs to company 1a5d0000-0000-0000-0000-0000000004a1, not company 1a5d0000-0000-0000-0000-0000000004a2',
  'an anchored key naming another company''s correction root is rejected');  -- 69

-- ── K. Boundaries hold through the fixture ─────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows FROM wp4_pre),
  'the WP-4 fixture creates no journal entry');                               -- 70

SELECT is(
  (SELECT count(*)::int FROM pg_trigger
    WHERE tgrelid='public.inventory_events'::regclass AND NOT tgisinternal),
  3, 'the inventory_events trigger set is unchanged through the fixture');    -- 71

SELECT * FROM finish();
ROLLBACK;
