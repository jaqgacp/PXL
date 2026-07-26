-- IA5-CONCURRENCY-001
-- Local-only, destructive-reset-bounded certification.
--
-- Prerequisite: run on a freshly reset local database. This script commits one
-- isolated test company because two autonomous sessions cannot observe an
-- uncommitted fixture. Run `supabase db reset --local --no-seed` immediately
-- after the script. It must never be run against hosted or production data.

\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS dblink;

SELECT plan(7);

SELECT is(
  (SELECT count(*)::int
     FROM public.companies
    WHERE id = '1a5c0000-0000-0000-0000-000000000101'),
  0,
  'concurrency fixture requires a fresh local database'
);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '1a5c0000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'ia5-concurrency@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

INSERT INTO public.companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by,
  functional_currency_code, reporting_currency_code
) VALUES (
  '1a5c0000-0000-0000-0000-000000000101', 'corporation',
  'IA5 Concurrency Certification', 'Software', '500-005-000-00000',
  'vat', 'calendar', '1 Test', 'Building', 'Makati', 'Metro Manila', '1200',
  'ia5-concurrency@test.local', 'IA5 Owner', 'President',
  '1a5c0000-0000-0000-0000-000000000001',
  '1a5c0000-0000-0000-0000-000000000001', 'PHP', 'PHP'
);

INSERT INTO public.user_company_memberships (
  user_id, company_id, role, granted_by
) VALUES (
  '1a5c0000-0000-0000-0000-000000000001',
  '1a5c0000-0000-0000-0000-000000000101',
  'owner',
  '1a5c0000-0000-0000-0000-000000000001'
) ON CONFLICT (user_id, company_id) DO NOTHING;

INSERT INTO public.branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '1a5c0000-0000-0000-0000-000000000201',
  '1a5c0000-0000-0000-0000-000000000101',
  'HO', 'Head Office', '1 Test', 'Building', 'Makati', 'Metro Manila', '1200',
  '1a5c0000-0000-0000-0000-000000000001',
  '1a5c0000-0000-0000-0000-000000000001'
);

INSERT INTO public.item_categories (id, company_id, category_code, category_name)
VALUES (
  '1a5c0000-0000-0000-0000-000000000301',
  '1a5c0000-0000-0000-0000-000000000101',
  'IA5C', 'IA5 Concurrency'
);

INSERT INTO public.units_of_measure (id, company_id, uom_code, description)
VALUES (
  '1a5c0000-0000-0000-0000-000000000401',
  '1a5c0000-0000-0000-0000-000000000101',
  'EA', 'Each'
);

INSERT INTO public.warehouses (
  id, company_id, branch_id, warehouse_code, warehouse_name,
  created_by, updated_by
) VALUES (
  '1a5c0000-0000-0000-0000-000000000501',
  '1a5c0000-0000-0000-0000-000000000101',
  '1a5c0000-0000-0000-0000-000000000201',
  'MAIN', 'Main',
  '1a5c0000-0000-0000-0000-000000000001',
  '1a5c0000-0000-0000-0000-000000000001'
);

INSERT INTO public.items (
  id, company_id, item_code, description, item_type, category_id, uom_id,
  costing_method, created_by, updated_by
) VALUES (
  '1a5c0000-0000-0000-0000-000000000601',
  '1a5c0000-0000-0000-0000-000000000101',
  'IA5C-ITEM', 'IA5 Concurrency Item', 'inventory_item',
  '1a5c0000-0000-0000-0000-000000000301',
  '1a5c0000-0000-0000-0000-000000000401',
  'weighted_average',
  '1a5c0000-0000-0000-0000-000000000001',
  '1a5c0000-0000-0000-0000-000000000001'
);

SELECT public.fn_ia5_create_dormant_policy_bundle(
  '1a5c0000-0000-0000-0000-000000000101',
  '1a5c0000-0000-0000-0000-000000000601',
  'warehouse',
  NULL,
  '1a5c0000-0000-0000-0000-000000000501',
  'moving_weighted_average',
  6::smallint,
  'PHP',
  2::smallint,
  '2026-01-01',
  '2026-12-31',
  '1a5c0000-0000-0000-0000-000000000001'
);

CREATE TEMP TABLE ia5c_ctx (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TEMP TABLE ia5c_results (worker TEXT PRIMARY KEY, result JSONB NOT NULL);

INSERT INTO ia5c_ctx VALUES (
  'connection',
  format(
    'host=%s port=%s dbname=%s user=postgres password=postgres',
    host(inet_server_addr()), inet_server_port(), current_database()
  )
);

INSERT INTO ia5c_ctx VALUES (
  'request',
  $request$
    SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a5c0000-0000-0000-0000-000000000101',
      'IA5_CERTIFICATION',
      '1a5c0000-0000-0000-0000-000000000701',
      '1a5c0000-0000-0000-0000-000000000801',
      'ACCEPTED',
      1,
      'ia5-concurrent-key-00000001',
      repeat('c',64),
      '2026-07-26T10:00:00Z',
      '1a5c0000-0000-0000-0000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'event_type','certification_receipt',
        'event_effect','quantity_increase',
        'event_sequence',1,
        'item_id','1a5c0000-0000-0000-0000-000000000601',
        'valuation_scope_id',(
          SELECT id FROM public.inventory_valuation_scopes
           WHERE company_id='1a5c0000-0000-0000-0000-000000000101'
        ),
        'source_uom_id','1a5c0000-0000-0000-0000-000000000401',
        'base_uom_id','1a5c0000-0000-0000-0000-000000000401',
        'source_quantity','1.000000',
        'base_quantity','1.000000',
        'uom_conversion_factor','1.000000000000',
        'effective_at','2026-07-26T10:00:00Z',
        'accounting_date','2026-07-26',
        'reason_code','IA5_CONCURRENCY',
        'source_evidence_fingerprint',repeat('d',64),
        'immutable_source_evidence',jsonb_build_object(
          'certification','IA5-CONCURRENCY-001'
        )
      ))
    )::text
  $request$
);

SELECT dblink_connect(
  'ia5c_a',
  (SELECT value FROM ia5c_ctx WHERE key='connection') ||
  ' application_name=pxl_ia5_concurrency_a'
);
SELECT dblink_connect(
  'ia5c_b',
  (SELECT value FROM ia5c_ctx WHERE key='connection') ||
  ' application_name=pxl_ia5_concurrency_b'
);

SELECT dblink_exec('ia5c_a', 'BEGIN');
INSERT INTO ia5c_results
SELECT 'a', result::jsonb
FROM dblink(
  'ia5c_a',
  (SELECT value FROM ia5c_ctx WHERE key='request')
) AS r(result TEXT);

SELECT dblink_send_query(
  'ia5c_b',
  (SELECT value FROM ia5c_ctx WHERE key='request')
);

DO $poll$
DECLARE
  v_waiting BOOLEAN := false;
  i INTEGER;
BEGIN
  FOR i IN 1..200 LOOP
    SELECT COALESCE(bool_or(wait_event_type = 'Lock'), false)
      INTO v_waiting
      FROM pg_stat_activity
     WHERE application_name = 'pxl_ia5_concurrency_b';
    EXIT WHEN v_waiting;
    PERFORM pg_sleep(0.025);
  END LOOP;
  PERFORM set_config('pxl.ia5_concurrent_wait', v_waiting::text, false);
END
$poll$;

SELECT is(
  current_setting('pxl.ia5_concurrent_wait', true),
  'true',
  'concurrent duplicate waits on authoritative company/idempotency lock'
);

SELECT dblink_exec('ia5c_a', 'COMMIT');
INSERT INTO ia5c_results
SELECT 'b', result::jsonb
FROM dblink_get_result('ia5c_b') AS r(result TEXT);

SELECT is(
  (SELECT result->>'occurrence_id' FROM ia5c_results WHERE worker='a'),
  (SELECT result->>'occurrence_id' FROM ia5c_results WHERE worker='b'),
  'concurrent duplicate resolves to the original accepted occurrence'
);

SELECT is(
  (SELECT result->>'duplicate' FROM ia5c_results WHERE worker='a'),
  'false',
  'first concurrent request is the accepted authority'
);

SELECT is(
  (SELECT result->>'duplicate' FROM ia5c_results WHERE worker='b'),
  'true',
  'second concurrent request returns deterministic duplicate evidence'
);

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_occurrences
    WHERE company_id='1a5c0000-0000-0000-0000-000000000101'
      AND idempotency_key='ia5-concurrent-key-00000001'),
  1,
  'concurrent submissions create exactly one occurrence'
);

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events
    WHERE company_id='1a5c0000-0000-0000-0000-000000000101'),
  1,
  'concurrent submissions create exactly one event'
);

SELECT dblink_disconnect('ia5c_a');
SELECT dblink_disconnect('ia5c_b');

SELECT * FROM finish();

\echo IA5-CONCURRENCY-001 committed an isolated local fixture.
\echo Reset the local database immediately; do not use this script on hosted data.
