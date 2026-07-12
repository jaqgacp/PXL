-- POSTING-RACE-001 (PXL-DA-007 closure evidence)
--
-- Genuine two-database-session posting race against one approved source.
-- pgTAP runs single-session, so this test opens two real extra sessions with
-- dblink through the same TCP endpoint the harness uses (the container
-- address from inet_server_addr(); loopback is trust-authenticated and dblink
-- refuses passwordless non-superuser connections). The fixtures those
-- sessions race over must be committed, so the test pre-cleans, builds, and
-- finally deletes its own committed fixture company. Local test harness
-- only (postgres/postgres); pgTAP tests are never run against hosted.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT plan(14);

CREATE TEMP TABLE t_ctx (key TEXT PRIMARY KEY, val TEXT);

INSERT INTO t_ctx VALUES ('conn', format(
  'host=%s port=%s dbname=%s user=postgres password=postgres',
  host(inet_server_addr()), inet_server_port(), current_database()
));

INSERT INTO t_ctx VALUES ('claims_sql',
  'DO $cl$ BEGIN PERFORM set_config(''request.jwt.claims'', ''{"sub":"11111111-1111-1111-1111-111111111129","role":"authenticated"}'', false); END $cl$;');

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111129","role":"authenticated"}',
  true
);

SELECT dblink_connect('setup', (SELECT val FROM t_ctx WHERE key = 'conn'));
SELECT dblink_exec('setup', (SELECT val FROM t_ctx WHERE key = 'claims_sql'));

-- Pre-clean committed leftovers from any earlier failed run, then build the
-- committed fixture company through one autonomous setup session.
SELECT dblink_exec('setup', 'SET session_replication_role = replica');
SELECT dblink_exec('setup', $preclean$
DO $do$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE n.nspname = 'public' AND c.relkind = 'r'
      AND a.attname = 'company_id' AND NOT a.attisdropped
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE company_id = %L',
      r.relname, '22222222-2222-2222-2222-222222222129'
    );
  END LOOP;
  DELETE FROM public.companies WHERE id = '22222222-2222-2222-2222-222222222129';
  DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111129';
END
$do$;
$preclean$);
SELECT dblink_exec('setup', 'SET session_replication_role = origin');

SELECT dblink_exec('setup', $fix$
DO $do$
BEGIN
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111129',
    'authenticated', 'authenticated', 'posting-race@test.local', '',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}', '{}'
  );

  INSERT INTO companies (
    id, entity_type, registered_name, line_of_business, tin,
    tax_registration, accounting_period,
    address_line_1, address_line_2, city, province, zip_code,
    email, signatory_name, signatory_position, created_by, updated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222129', 'corporation',
    'Posting Race Test Corp', 'Software Services', '111-222-333-029',
    'vat', 'calendar',
    'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
    'posting-race@test.local', 'Juan Dela Cruz', 'President',
    '11111111-1111-1111-1111-111111111129',
    '11111111-1111-1111-1111-111111111129'
  );

  INSERT INTO branches (
    id, company_id, branch_code, branch_name,
    address_line_1, address_line_2, city, province, zip_code,
    created_by, updated_by
  ) VALUES (
    '33333333-3333-3333-3333-333333333329',
    '22222222-2222-2222-2222-222222222129', 'HO', 'Head Office',
    'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
    '11111111-1111-1111-1111-111111111129',
    '11111111-1111-1111-1111-111111111129'
  );

  INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
  VALUES (
    '44444444-4444-4444-4444-444444444429',
    '22222222-2222-2222-2222-222222222129',
    'FY2026', '2026-01-01', '2026-12-31', true
  );

  INSERT INTO fiscal_periods (
    company_id, fiscal_year_id, period_number, period_name,
    start_date, end_date, is_locked
  )
  SELECT
    '22222222-2222-2222-2222-222222222129',
    '44444444-4444-4444-4444-444444444429',
    m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
    make_date(2026, m, 1),
    (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
    false
  FROM generate_series(1, 12) AS m;

  INSERT INTO chart_of_accounts (
    id, company_id, account_code, account_name,
    account_type, normal_balance, is_postable, is_active,
    created_by, updated_by
  ) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000129', '22222222-2222-2222-2222-222222222129',
     '1010', 'Cash', 'asset', 'debit', true, true,
     '11111111-1111-1111-1111-111111111129', '11111111-1111-1111-1111-111111111129'),
    ('aaaaaaaa-0000-0000-0000-000000000229', '22222222-2222-2222-2222-222222222129',
     '1200', 'Accounts Receivable', 'asset', 'debit', true, true,
     '11111111-1111-1111-1111-111111111129', '11111111-1111-1111-1111-111111111129'),
    ('aaaaaaaa-0000-0000-0000-000000000329', '22222222-2222-2222-2222-222222222129',
     '2100', 'Output VAT', 'liability', 'credit', true, true,
     '11111111-1111-1111-1111-111111111129', '11111111-1111-1111-1111-111111111129'),
    ('aaaaaaaa-0000-0000-0000-000000000429', '22222222-2222-2222-2222-222222222129',
     '4010', 'Service Revenue', 'revenue', 'credit', true, true,
     '11111111-1111-1111-1111-111111111129', '11111111-1111-1111-1111-111111111129');

  INSERT INTO company_accounting_config (
    company_id, ar_account_id, vat_payable_account_id, default_cash_account_id,
    created_by, updated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222129',
    'aaaaaaaa-0000-0000-0000-000000000229',
    'aaaaaaaa-0000-0000-0000-000000000329',
    'aaaaaaaa-0000-0000-0000-000000000129',
    '11111111-1111-1111-1111-111111111129',
    '11111111-1111-1111-1111-111111111129'
  );

  INSERT INTO number_series (
    company_id, branch_id, document_type_id, prefix,
    number_length, starting_number, next_number,
    is_active, created_by, updated_by
  )
  SELECT
    '22222222-2222-2222-2222-222222222129',
    '33333333-3333-3333-3333-333333333329',
    id, 'SI-', 6, 1, 1, true,
    '11111111-1111-1111-1111-111111111129',
    '11111111-1111-1111-1111-111111111129'
  FROM ref_document_types
  WHERE document_code = 'SI';

  INSERT INTO customers (
    id, company_id, customer_code, registered_name, tin,
    registered_address, delivery_address, created_by, updated_by
  ) VALUES (
    '55555555-5555-5555-5555-555555555529',
    '22222222-2222-2222-2222-222222222129', 'CUST-029',
    'Race Customer Inc', '444-555-666-029',
    'Customer HQ, Pasig', 'Customer HQ, Pasig',
    '11111111-1111-1111-1111-111111111129',
    '11111111-1111-1111-1111-111111111129'
  );

  -- Company creation may auto-grant the creator membership.
  INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
  VALUES (
    '11111111-1111-1111-1111-111111111129',
    '22222222-2222-2222-2222-222222222129',
    'owner',
    '11111111-1111-1111-1111-111111111129'
  )
  ON CONFLICT (user_id, company_id) DO NOTHING;
END
$do$;
$fix$);

-- Save + approve the raced invoice through the governed application writers.
INSERT INTO t_ctx
SELECT 'si', si_id::text FROM dblink('setup', $q$
  SELECT fn_save_sales_invoice(
    NULL,
    jsonb_build_object(
      'company_id', '22222222-2222-2222-2222-222222222129',
      'branch_id', '33333333-3333-3333-3333-333333333329',
      'date', '2026-07-10',
      'customer_id', '55555555-5555-5555-5555-555555555529',
      'customer_name_snapshot', 'Race Customer Inc',
      'customer_tin_snapshot', '444-555-666-029',
      'customer_address_snapshot', 'Customer HQ, Pasig'
    ),
    jsonb_build_array(jsonb_build_object(
      'description', 'Race services',
      'quantity', 1,
      'unit_price', 10000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000429'
    ))
  )
$q$) AS r(si_id UUID);

SELECT dblink_exec('setup', format(
  'DO $d$ BEGIN PERFORM fn_approve_sales_invoice(%L); END $d$;',
  (SELECT val FROM t_ctx WHERE key = 'si')
));

SELECT is(
  (SELECT status FROM sales_invoices
   WHERE id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')),
  'approved',
  'committed race fixture is a single approved sales invoice'
);

-- Session A: open transaction, post, and hold the source lock uncommitted.
SELECT dblink_connect('race_a', (SELECT val FROM t_ctx WHERE key = 'conn'));
SELECT dblink_exec('race_a', (SELECT val FROM t_ctx WHERE key = 'claims_sql'));
SELECT dblink_exec('race_a', 'BEGIN');
SELECT dblink_exec('race_a', format(
  'DO $d$ BEGIN PERFORM fn_post_sales_invoice(%L); END $d$;',
  (SELECT val FROM t_ctx WHERE key = 'si')
));

-- Session B: post the same source at the same time.
SELECT dblink_connect('race_b',
  (SELECT val FROM t_ctx WHERE key = 'conn') || ' application_name=pxl_race_b_029');
SELECT dblink_exec('race_b', (SELECT val FROM t_ctx WHERE key = 'claims_sql'));
SELECT dblink_exec('race_b', 'SET statement_timeout = ''30s''');
SELECT dblink_send_query('race_b', format(
  'DO $d$ BEGIN PERFORM fn_post_sales_invoice(%L); END $d$; SELECT ''race_b_done'';',
  (SELECT val FROM t_ctx WHERE key = 'si')
));

DO $poll$
DECLARE
  v_waiting BOOLEAN := false;
  i INTEGER;
BEGIN
  FOR i IN 1..200 LOOP
    SELECT COALESCE(bool_or(wait_event_type = 'Lock'), false)
    INTO v_waiting
    FROM pg_stat_activity
    WHERE application_name = 'pxl_race_b_029';
    EXIT WHEN v_waiting;
    PERFORM pg_sleep(0.05);
  END LOOP;
  PERFORM set_config('pxl.race_b_lock_wait', v_waiting::TEXT, true);
END
$poll$;

SELECT is(
  current_setting('pxl.race_b_lock_wait', true),
  'true',
  'second session post blocks on the governed FOR UPDATE source lock'
);

-- First session commits; the blocked session must resume without error and
-- without writing a second original JE or tax set.
SELECT dblink_exec('race_a', 'COMMIT');

SELECT lives_ok(
  $q$SELECT res FROM dblink_get_result('race_b') AS t(res TEXT)$q$,
  'blocked second-session post completes without a duplicate-posting error'
);
SELECT is(
  (SELECT res FROM dblink_get_result('race_b') AS t(res TEXT)),
  'race_b_done',
  'second session ran to the end of its raced batch'
);
SELECT dblink_disconnect('race_b');

SELECT is(
  (SELECT count(*)::int FROM journal_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222129'
     AND reference_doc_type = 'SI'
     AND reference_doc_id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')
     AND status IN ('posted', 'reversed')
     AND je_number NOT LIKE '%-REV-%'
     AND je_number NOT LIKE 'JE-VOID-%'),
  1,
  'the race produced exactly one original journal entry'
);
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222129'
     AND source_doc_type = 'SI'
     AND source_doc_id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')
     AND reverses_tax_detail_id IS NULL),
  1,
  'the race produced exactly one live output VAT tax set'
);
SELECT is(
  (SELECT status FROM sales_invoices
   WHERE id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')),
  'posted',
  'the raced source ends posted exactly once'
);
SELECT is(
  (SELECT journal_entry_id FROM sales_invoices
   WHERE id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')),
  (SELECT id FROM journal_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222129'
     AND reference_doc_type = 'SI'
     AND reference_doc_id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')
     AND status = 'posted'),
  'the raced source links the single surviving journal entry'
);

-- Sequential idempotence: a later same-source post is a governed no-op.
SELECT lives_ok(
  format(
    $q$SELECT dblink_exec('setup', %L)$q$,
    format(
      'DO $d$ BEGIN PERFORM fn_post_sales_invoice(%L); END $d$;',
      (SELECT val FROM t_ctx WHERE key = 'si')
    )
  ),
  'sequential same-source re-post is an idempotent no-op, not an error'
);
SELECT is(
  (SELECT count(*)::int FROM journal_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222129'
     AND reference_doc_type = 'SI'
     AND reference_doc_id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')),
  1,
  'sequential re-post writes no additional journal entry'
);
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222129'
     AND source_doc_type = 'SI'
     AND source_doc_id = (SELECT val::uuid FROM t_ctx WHERE key = 'si')),
  1,
  'sequential re-post writes no additional tax rows'
);

-- Structural backstops behind the lock protocol, exercised on the committed
-- race fixture: one-live-JE-per-source and one-live-VAT-row-per-source-code.
SELECT throws_like(
  format($q$
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      '22222222-2222-2222-2222-222222222129',
      '33333333-3333-3333-3333-333333333329',
      'JE-RACE-DUP-029', '2026-07-10',
      (SELECT id FROM fiscal_periods
       WHERE company_id = '22222222-2222-2222-2222-222222222129' AND period_number = 7),
      'Duplicate original', 'SI', %L, 'posted', 1, 1,
      '11111111-1111-1111-1111-111111111129',
      '11111111-1111-1111-1111-111111111129'
    )
  $q$, (SELECT val FROM t_ctx WHERE key = 'si')),
  '%ux_journal_entries_live_source%',
  'a second live original JE for the raced source is structurally impossible'
);
SELECT throws_like(
  format($q$
    SELECT fn_add_tax_detail(
      '22222222-2222-2222-2222-222222222129',
      '33333333-3333-3333-3333-333333333329',
      'SI', %L, NULL,
      'output_vat', NULL,
      (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'), NULL,
      100, NULL, 12,
      (SELECT id FROM fiscal_periods
       WHERE company_id = '22222222-2222-2222-2222-222222222129' AND period_number = 7),
      '2026-07-10', '2026-07-10',
      '55555555-5555-5555-5555-555555555529',
      '444-555-666-029', 'Race Customer Inc'
    )
  $q$, (SELECT val FROM t_ctx WHERE key = 'si')),
  '%ux_tde_vat_source_code%',
  'a second live VAT tax row for the raced source and code is structurally impossible'
);

-- Delete the committed fixture company and prove nothing is left behind.
SELECT dblink_exec('setup', 'SET session_replication_role = replica');
SELECT dblink_exec('setup', $clean$
DO $do$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE n.nspname = 'public' AND c.relkind = 'r'
      AND a.attname = 'company_id' AND NOT a.attisdropped
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE company_id = %L',
      r.relname, '22222222-2222-2222-2222-222222222129'
    );
  END LOOP;
  DELETE FROM public.companies WHERE id = '22222222-2222-2222-2222-222222222129';
  DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111129';
END
$do$;
$clean$);
SELECT dblink_exec('setup', 'SET session_replication_role = origin');
SELECT dblink_disconnect('race_a');
SELECT dblink_disconnect('setup');

SELECT is(
  (SELECT count(*)::int FROM companies
   WHERE id = '22222222-2222-2222-2222-222222222129'),
  0,
  'the committed race fixture company is fully cleaned up'
);

SELECT * FROM finish();
ROLLBACK;
