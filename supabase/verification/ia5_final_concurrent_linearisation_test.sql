-- IA5-IA6-GATE-ORDER-002
-- Verification only. Run on a freshly reset local database.
-- This script commits one isolated test company because autonomous dblink sessions
-- cannot see uncommitted fixtures. Reset the local database immediately afterward.
-- Never run against hosted or production data.

\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS dblink;

SELECT plan(10);

SELECT is(
  (SELECT count(*)::int FROM public.companies
   WHERE id='1a5f1000-0000-0000-0000-000000000101'),
  0,
  'concurrency evidence requires a clean local fixture'
);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '1a5f1000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'ia5-final-concurrent@test.local', '',
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
  '1a5f1000-0000-0000-0000-000000000101', 'corporation',
  'IA5 Final Concurrent Gate', 'Software', '950-100-000-00000',
  'vat', 'calendar', '1 Test', 'Building', 'Makati', 'Metro Manila', '1200',
  'ia5-final-concurrent@test.local', 'IA5 Owner', 'President',
  '1a5f1000-0000-0000-0000-000000000001',
  '1a5f1000-0000-0000-0000-000000000001', 'PHP', 'PHP'
);

INSERT INTO public.user_company_memberships (
  user_id, company_id, role, granted_by
) VALUES (
  '1a5f1000-0000-0000-0000-000000000001',
  '1a5f1000-0000-0000-0000-000000000101',
  'owner',
  '1a5f1000-0000-0000-0000-000000000001'
);

INSERT INTO public.branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '1a5f1000-0000-0000-0000-000000000201',
  '1a5f1000-0000-0000-0000-000000000101',
  'HO', 'Head Office', '1 Test', 'Building', 'Makati', 'Metro Manila', '1200',
  '1a5f1000-0000-0000-0000-000000000001',
  '1a5f1000-0000-0000-0000-000000000001'
);

INSERT INTO public.item_categories (
  id, company_id, category_code, category_name
) VALUES (
  '1a5f1000-0000-0000-0000-000000000301',
  '1a5f1000-0000-0000-0000-000000000101',
  'IA5FC', 'IA5 Final Concurrent'
);

INSERT INTO public.units_of_measure (
  id, company_id, uom_code, description
) VALUES (
  '1a5f1000-0000-0000-0000-000000000401',
  '1a5f1000-0000-0000-0000-000000000101',
  'EA', 'Each'
);

INSERT INTO public.warehouses (
  id, company_id, branch_id, warehouse_code, warehouse_name,
  created_by, updated_by
) VALUES (
  '1a5f1000-0000-0000-0000-000000000501',
  '1a5f1000-0000-0000-0000-000000000101',
  '1a5f1000-0000-0000-0000-000000000201',
  'MAIN', 'Main',
  '1a5f1000-0000-0000-0000-000000000001',
  '1a5f1000-0000-0000-0000-000000000001'
);

INSERT INTO public.items (
  id, company_id, item_code, description, item_type, category_id, uom_id,
  costing_method, created_by, updated_by
) VALUES (
  '1a5f1000-0000-0000-0000-000000000601',
  '1a5f1000-0000-0000-0000-000000000101',
  'IA5FC-ITEM', 'IA5 Final Concurrent Item', 'inventory_item',
  '1a5f1000-0000-0000-0000-000000000301',
  '1a5f1000-0000-0000-0000-000000000401',
  'weighted_average',
  '1a5f1000-0000-0000-0000-000000000001',
  '1a5f1000-0000-0000-0000-000000000001'
);

SELECT public.fn_ia5_create_dormant_policy_bundle(
  '1a5f1000-0000-0000-0000-000000000101',
  '1a5f1000-0000-0000-0000-000000000601',
  'warehouse', NULL,
  '1a5f1000-0000-0000-0000-000000000501',
  'moving_weighted_average', 6::smallint, 'PHP', 2::smallint,
  '2026-01-01', '2026-12-31',
  '1a5f1000-0000-0000-0000-000000000001'
);

CREATE TEMP TABLE gate_concurrency_context AS
SELECT
  id AS valuation_scope_id,
  format(
    'dbname=%s user=supabase_admin',
    current_database()
  ) AS connection_string
FROM public.inventory_valuation_scopes
WHERE company_id='1a5f1000-0000-0000-0000-000000000101';

CREATE TEMP TABLE gate_concurrency_result (
  scenario TEXT NOT NULL,
  worker TEXT NOT NULL,
  delay_seconds NUMERIC NOT NULL,
  result JSONB NOT NULL,
  PRIMARY KEY (scenario, worker)
);

CREATE FUNCTION pg_temp.gate_command_sql(
  p_scenario TEXT,
  p_worker TEXT,
  p_delay NUMERIC
)
RETURNS TEXT
LANGUAGE sql
AS $$
  SELECT format(
    $command$
    WITH waited AS MATERIALIZED (
      SELECT pg_sleep(%L)
    )
    SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a5f1000-0000-0000-0000-000000000101',
      'IA5_CERTIFICATION',
      %L::uuid,
      %L::uuid,
      'ACCEPTED',
      1,
      %L,
      %L,
      '2026-07-26T10:00:00Z',
      '1a5f1000-0000-0000-0000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'event_type', %L,
        'event_effect', %L,
        'event_sequence', 1,
        'effective_at', '2026-07-26T10:00:00Z',
        'accounting_date', '2026-07-26',
        'item_id', '1a5f1000-0000-0000-0000-000000000601',
        'valuation_scope_id', %L,
        'physical_warehouse_id',
          '1a5f1000-0000-0000-0000-000000000501',
        'source_uom_id', '1a5f1000-0000-0000-0000-000000000401',
        'base_uom_id', '1a5f1000-0000-0000-0000-000000000401',
        'source_quantity', %L,
        'base_quantity', %L,
        'uom_conversion_factor', '1.000000000000',
        'immutable_source_evidence', jsonb_build_object(
          'scenario', %L,
          'worker', %L,
          'delay_seconds', %L
        ),
        'source_evidence_fingerprint', %L,
        'reason_code', 'FINAL_CONCURRENT_GATE'
      ))
    )::text
    FROM waited
    $command$,
    p_delay,
    gen_random_uuid(),
    gen_random_uuid(),
    'ia5-final-concurrent-' || p_scenario || '-' || lower(p_worker),
    md5(p_scenario || ':' || p_worker) ||
      md5(p_scenario || ':' || p_worker || ':request'),
    'final_concurrent_' || lower(p_worker),
    CASE WHEN p_worker='A'
      THEN 'quantity_increase' ELSE 'quantity_decrease' END,
    (SELECT valuation_scope_id::text FROM gate_concurrency_context),
    CASE WHEN p_worker='A' THEN '10.000000' ELSE '-6.000000' END,
    CASE WHEN p_worker='A' THEN '10.000000' ELSE '-6.000000' END,
    p_scenario,
    p_worker,
    p_delay,
    md5(p_scenario || ':' || p_worker || ':evidence') ||
      md5(p_scenario || ':' || p_worker || ':evidence:2')
  )
$$;

SELECT dblink_connect(
  'gate_a',
  (SELECT connection_string FROM gate_concurrency_context) ||
  ' application_name=ia5_final_gate_a'
);
SELECT dblink_connect(
  'gate_b',
  (SELECT connection_string FROM gate_concurrency_context) ||
  ' application_name=ia5_final_gate_b'
);

-- Unbiased simultaneous submission.
SELECT dblink_send_query(
  'gate_a', pg_temp.gate_command_sql('simultaneous', 'A', 0)
);
SELECT dblink_send_query(
  'gate_b', pg_temp.gate_command_sql('simultaneous', 'B', 0)
);
INSERT INTO gate_concurrency_result
SELECT 'simultaneous', 'A', 0, result::jsonb
FROM dblink_get_result('gate_a') AS r(result TEXT);
INSERT INTO gate_concurrency_result
SELECT 'simultaneous', 'B', 0, result::jsonb
FROM dblink_get_result('gate_b') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_a') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_b') AS r(result TEXT);

-- B reaches the relevant sequence lock first.
SELECT dblink_send_query(
  'gate_a', pg_temp.gate_command_sql('b_first', 'A', 0.250)
);
SELECT dblink_send_query(
  'gate_b', pg_temp.gate_command_sql('b_first', 'B', 0)
);
INSERT INTO gate_concurrency_result
SELECT 'b_first', 'A', 0.250, result::jsonb
FROM dblink_get_result('gate_a') AS r(result TEXT);
INSERT INTO gate_concurrency_result
SELECT 'b_first', 'B', 0, result::jsonb
FROM dblink_get_result('gate_b') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_a') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_b') AS r(result TEXT);

-- A reaches the relevant sequence lock first.
SELECT dblink_send_query(
  'gate_a', pg_temp.gate_command_sql('a_first', 'A', 0)
);
SELECT dblink_send_query(
  'gate_b', pg_temp.gate_command_sql('a_first', 'B', 0.250)
);
INSERT INTO gate_concurrency_result
SELECT 'a_first', 'A', 0, result::jsonb
FROM dblink_get_result('gate_a') AS r(result TEXT);
INSERT INTO gate_concurrency_result
SELECT 'a_first', 'B', 0.250, result::jsonb
FROM dblink_get_result('gate_b') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_a') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_b') AS r(result TEXT);

-- A owns the row lock before B submits; B waits until A records and commits.
SELECT dblink_exec('gate_a', 'BEGIN');
SELECT dblink_exec(
  'gate_a',
  format(
    'UPDATE public.inventory_valuation_scope_sequences '
    'SET last_sequence=last_sequence WHERE valuation_scope_id=%L',
    (SELECT valuation_scope_id FROM gate_concurrency_context)
  )
);
SELECT dblink_send_query(
  'gate_b', pg_temp.gate_command_sql('locked_a_first', 'B', 0)
);

DO $$
DECLARE
  v_waiting BOOLEAN := false;
  i INTEGER;
BEGIN
  FOR i IN 1..200 LOOP
    SELECT COALESCE(bool_or(wait_event_type='Lock'), false)
    INTO v_waiting
    FROM pg_stat_activity
    WHERE application_name='ia5_final_gate_b';
    EXIT WHEN v_waiting;
    PERFORM pg_sleep(0.025);
  END LOOP;
  PERFORM set_config('pxl.ia5_final_b_waiting', v_waiting::text, false);
END
$$;

INSERT INTO gate_concurrency_result
SELECT 'locked_a_first', 'A', 0, result::jsonb
FROM dblink(
  'gate_a', pg_temp.gate_command_sql('locked_a_first', 'A', 0)
) AS r(result TEXT);
SELECT dblink_exec('gate_a', 'COMMIT');
INSERT INTO gate_concurrency_result
SELECT 'locked_a_first', 'B', 0, result::jsonb
FROM dblink_get_result('gate_b') AS r(result TEXT);
SELECT count(*) FROM dblink_get_result('gate_b') AS r(result TEXT);

-- Multiple randomized schedules. These record, rather than assume, lock order.
DO $$
DECLARE
  i INTEGER;
  v_scenario TEXT;
  v_delay_a NUMERIC;
  v_delay_b NUMERIC;
  v_result_a TEXT;
  v_result_b TEXT;
BEGIN
  FOR i IN 1..8 LOOP
    v_scenario := 'random_' || lpad(i::text, 2, '0');
    v_delay_a := round((random() * 0.080)::numeric, 3);
    v_delay_b := round((random() * 0.080)::numeric, 3);

    PERFORM dblink_send_query(
      'gate_a', pg_temp.gate_command_sql(v_scenario, 'A', v_delay_a)
    );
    PERFORM dblink_send_query(
      'gate_b', pg_temp.gate_command_sql(v_scenario, 'B', v_delay_b)
    );

    SELECT result INTO v_result_a
    FROM dblink_get_result('gate_a') AS r(result TEXT);
    SELECT result INTO v_result_b
    FROM dblink_get_result('gate_b') AS r(result TEXT);
    PERFORM result
    FROM dblink_get_result('gate_a') AS r(result TEXT);
    PERFORM result
    FROM dblink_get_result('gate_b') AS r(result TEXT);

    INSERT INTO gate_concurrency_result
    VALUES
      (v_scenario, 'A', v_delay_a, v_result_a::jsonb),
      (v_scenario, 'B', v_delay_b, v_result_b::jsonb);
  END LOOP;
END
$$;

CREATE TEMP TABLE gate_concurrency_observation AS
SELECT
  e.immutable_source_evidence->>'scenario' AS scenario,
  e.immutable_source_evidence->>'worker' AS worker,
  e.scope_sequence,
  e.effective_at,
  e.accounting_date,
  e.occurrence_date,
  e.source_occurrence_sequence,
  e.event_sequence,
  concat_ws('|',
    e.effective_at,
    e.accounting_date,
    e.occurrence_date,
    e.scope_sequence,
    e.source_occurrence_sequence,
    e.event_sequence
  ) AS economic_order_tuple
FROM public.inventory_events e
WHERE e.company_id='1a5f1000-0000-0000-0000-000000000101';

SELECT is(
  current_setting('pxl.ia5_final_b_waiting', true),
  'true',
  'competing command waits on the scope-sequence row lock'
);
SELECT is(
  (SELECT worker FROM gate_concurrency_observation
   WHERE scenario='b_first' ORDER BY scope_sequence LIMIT 1),
  'B',
  'delaying A before the lock makes B the economic first event'
);
SELECT is(
  (SELECT worker FROM gate_concurrency_observation
   WHERE scenario='a_first' ORDER BY scope_sequence LIMIT 1),
  'A',
  'delaying B before the lock makes A the economic first event'
);
SELECT is(
  (SELECT worker FROM gate_concurrency_observation
   WHERE scenario='locked_a_first' ORDER BY scope_sequence LIMIT 1),
  'A',
  'holding the scope row lock lets A establish economic priority'
);
SELECT is(
  (SELECT count(*)::int
   FROM gate_concurrency_observation
   WHERE scenario LIKE 'random_%'),
  16,
  'eight randomized two-command schedules admitted exactly sixteen events'
);
SELECT is(
  (SELECT count(*)::int
   FROM (
     SELECT scope_sequence
     FROM gate_concurrency_observation
     GROUP BY scope_sequence
     HAVING count(*) > 1
   ) duplicate_sequences),
  0,
  'scope sequence is unique under all concurrent schedules'
);
SELECT is(
  (SELECT count(DISTINCT first_worker)::int
   FROM (
     SELECT DISTINCT ON (scenario)
       scenario, worker AS first_worker
     FROM gate_concurrency_observation
     GROUP BY scenario, worker, scope_sequence
     ORDER BY scenario, scope_sequence
   ) firsts
   WHERE scenario IN ('a_first','b_first')),
  2,
  'the same economic command set can produce both A-first and B-first order'
);
SELECT ok(
  (SELECT worker FROM gate_concurrency_observation
   WHERE scenario='a_first' ORDER BY scope_sequence LIMIT 1)
  <>
  (SELECT worker FROM gate_concurrency_observation
   WHERE scenario='b_first' ORDER BY scope_sequence LIMIT 1),
  'lock acquisition schedule controls the first future FIFO/WAC input'
);
SELECT is(
  (SELECT count(*)::int FROM gate_concurrency_result),
  24,
  'all concurrent calls returned accepted occurrence evidence'
);

TABLE gate_concurrency_result;
TABLE gate_concurrency_observation;

SELECT dblink_disconnect('gate_a');
SELECT dblink_disconnect('gate_b');

SELECT * FROM finish();

\echo IA5-IA6-GATE-ORDER-002 committed an isolated local fixture.
\echo Reset the local database immediately; never run this script on hosted data.
