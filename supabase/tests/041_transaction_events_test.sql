-- TRANSACTION-EVENTS-001 - Semantic lifecycle event stream (PXL-DA-016)
--
-- Verifies that transaction_events captures business lifecycle evidence with
-- actor/role, source, status, journal, approval, and export/file context while
-- preserving the older sys_audit_logs posting-event compatibility row.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111241',
   'authenticated', 'authenticated', 'transaction-events-owner@test.local', '',
   now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111242',
   'authenticated', 'authenticated', 'transaction-events-outsider@test.local', '',
   now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111241');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222241', 'corporation',
        'Transaction Events Test Corp', 'Services', '111-222-333-041',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'transaction-events@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333241',
        '22222222-2222-2222-2222-222222222241', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date,
                          is_calendar, retained_earnings_id)
VALUES ('44444444-4444-4444-4444-444444444241',
        '22222222-2222-2222-2222-222222222241',
        'FY2026', '2026-01-01', '2026-12-31', true, NULL);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222241',
       '44444444-4444-4444-4444-444444444241',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000411', '22222222-2222-2222-2222-222222222241',
   '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000412', '22222222-2222-2222-2222-222222222241',
   '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid());

CREATE TEMP TABLE t_event_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT, UPDATE ON t_event_ctx TO authenticated;

SELECT lives_ok($$
  INSERT INTO t_event_ctx
  SELECT 'manual_je',
         fn_post_manual_je(
           '22222222-2222-2222-2222-222222222241',
           '33333333-3333-3333-3333-333333333241',
           '2026-06-15'::date,
           'Transaction event test JE',
           'MANUAL',
           false,
           '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000411","debit_amount":1000,"credit_amount":0},
             {"account_id":"aaaaaaaa-0000-0000-0000-000000000412","debit_amount":0,"credit_amount":1000}]'::jsonb
         )
$$, 'manual JE posts');

SELECT is(
  (SELECT count(*)::int FROM transaction_events
   WHERE company_id = '22222222-2222-2222-2222-222222222241'
     AND source_doc_type = 'MANUAL'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'POSTED'),
  1, 'posted manual JE writes a semantic POSTED event');

SELECT is(
  (SELECT actor_id FROM transaction_events
   WHERE source_doc_type = 'MANUAL'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'POSTED'
   ORDER BY occurred_at DESC LIMIT 1),
  '11111111-1111-1111-1111-111111111241'::uuid,
  'transaction event stores the actor id');

SELECT is(
  (SELECT actor_role FROM transaction_events
   WHERE source_doc_type = 'MANUAL'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'POSTED'
   ORDER BY occurred_at DESC LIMIT 1),
  'authenticated',
  'transaction event stores the actor role');

SELECT ok(
  (SELECT source_document_no FROM transaction_events
   WHERE source_doc_type = 'MANUAL'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'POSTED'
   ORDER BY occurred_at DESC LIMIT 1) LIKE 'MJE-202606-%',
  'transaction event stores the source document number');

SET LOCAL ROLE authenticated;
SELECT throws_like($$
  INSERT INTO transaction_events (
    company_id, source_doc_type, source_doc_id, event_type
  ) VALUES (
    '22222222-2222-2222-2222-222222222241', 'MANUAL',
    (SELECT id FROM t_event_ctx WHERE key = 'manual_je'), 'POSTED'
  )
$$, '%permission denied%', 'authenticated clients cannot forge transaction events');
RESET ROLE;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111241');

SELECT lives_ok($$
  INSERT INTO t_event_ctx
  SELECT 'reversal_je',
         fn_reverse_je((SELECT id FROM t_event_ctx WHERE key = 'manual_je'), '2026-06-20'::date)
$$, 'manual JE reversal posts');

SELECT is(
  (SELECT count(*)::int FROM transaction_events
   WHERE company_id = '22222222-2222-2222-2222-222222222241'
     AND source_doc_type = 'REV'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'REVERSED'
     AND journal_entry_id = (SELECT id FROM t_event_ctx WHERE key = 'reversal_je')),
  1, 'fn_record_posting_event writes a semantic REVERSED event with the reversal JE');

SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE company_id = '22222222-2222-2222-2222-222222222241'
     AND table_name = 'posting_event'
     AND record_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND new_data->>'event_type' = 'REVERSED'
     AND (new_data->>'transaction_event_id') IS NOT NULL),
  1, 'legacy sys_audit_logs posting_event row is preserved and links to transaction_events');

INSERT INTO approval_workflows (id, company_id, workflow_name, module_type,
                                document_type, trigger_condition_type,
                                is_active, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666641',
        '22222222-2222-2222-2222-222222222241',
        'Manual JE approval', 'sales', 'Manual Journal',
        'always', true, auth.uid(), auth.uid());

INSERT INTO approval_instances (
  company_id, workflow_id, source_document_type, source_document_id,
  source_document_no, source_document_amount, step_sequence,
  required_approver_type, actual_approver_id, status, acted_at, created_by
) VALUES (
  '22222222-2222-2222-2222-222222222241',
  '66666666-6666-6666-6666-666666666641',
  'Manual Journal',
  (SELECT id FROM t_event_ctx WHERE key = 'manual_je'),
  (SELECT je_number FROM journal_entries WHERE id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')),
  1000, 1, 'role', auth.uid(), 'approved', now(), auth.uid()
);

SELECT is(
  (SELECT count(*)::int FROM transaction_events
   WHERE company_id = '22222222-2222-2222-2222-222222222241'
     AND source_doc_type = 'MANUAL JOURNAL'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'APPROVED'
     AND details->>'approval_instance_id' IS NOT NULL),
  1, 'approval instance trigger writes semantic APPROVED evidence');

SELECT lives_ok($$
  INSERT INTO report_snapshots (
    company_id, report_type, source_table, source_id, snapshot_status,
    snapshot_version, period_start, period_end, report_payload, source_payload,
    source_hash, source_row_count, generated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222241',
    'TEST_EXPORT',
    'journal_entries',
    (SELECT id FROM t_event_ctx WHERE key = 'manual_je'),
    'exported',
    1,
    '2026-06-01',
    '2026-06-30',
    '{"kind":"test"}'::jsonb,
    '{"rows":[]}'::jsonb,
    repeat('a', 64),
    0,
    auth.uid()
  )
$$, 'report snapshot insert succeeds');

SELECT is(
  (SELECT count(*)::int FROM transaction_events
   WHERE company_id = '22222222-2222-2222-2222-222222222241'
     AND source_doc_type = 'TEST_EXPORT'
     AND source_doc_id = (SELECT id FROM t_event_ctx WHERE key = 'manual_je')
     AND event_type = 'EXPORTED'
     AND details->>'source_hash' = repeat('a', 64)),
  1, 'report snapshot trigger writes semantic EXPORTED evidence');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111242');
SELECT is(
  (SELECT count(*)::int FROM transaction_events
   WHERE company_id = '22222222-2222-2222-2222-222222222241'),
  0, 'non-member cannot read another company transaction events through RLS');
RESET ROLE;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111241');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM transaction_events
    WHERE company_id = '22222222-2222-2222-2222-222222222241'
      AND event_type IN ('POSTED','REVERSED','APPROVED','EXPORTED')
  ),
  'semantic event stream contains posting, reversal, approval, and export evidence');

SELECT * FROM finish();
ROLLBACK;
