-- ══════════════════════════════════════════════════════════════════════════════
-- HEAVY-REPORT-READINESS-001 - Server-side GL pagination and TB aggregation
-- (PXL-DA-018)
--
-- Proves high-growth GL reports can be read through paginated/aggregated RPCs:
-- general ledger row counts and totals, account-detail opening/running balances,
-- and Trial Balance mode filtering are computed by PostgreSQL instead of the UI.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111152',
        'authenticated', 'authenticated', 'harness-da018@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111152","role":"authenticated"}', true);

-- ── Company / branch / fiscal calendar / accounts ─────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222252', 'corporation',
        'DA018 Heavy Report Test Corp', 'Services', '111-222-333-052',
        'vat', 'calendar',
        'Unit 52', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-da018@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333352',
        '22222222-2222-2222-2222-222222222252', 'HO', 'Head Office',
        'Unit 52', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES
  ('44444444-4444-4444-4444-444444444451',
   '22222222-2222-2222-2222-222222222252',
   'FY2025', '2025-01-01', '2025-12-31', true),
  ('44444444-4444-4444-4444-444444444452',
   '22222222-2222-2222-2222-222222222252',
   'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (id, company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
VALUES
  ('45454545-4545-4545-4545-454545454412',
   '22222222-2222-2222-2222-222222222252',
   '44444444-4444-4444-4444-444444444451',
   12, 'Dec 2025', '2025-12-01', '2025-12-31', false),
  ('45454545-4545-4545-4545-454545454501',
   '22222222-2222-2222-2222-222222222252',
   '44444444-4444-4444-4444-444444444452',
   1, 'Jan 2026', '2026-01-01', '2026-01-31', false);

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000581', '22222222-2222-2222-2222-222222222252',
   '1010', 'Cash in Bank',      'asset',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000582', '22222222-2222-2222-2222-222222222252',
   '3200', 'Opening Equity',    'equity',  'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000583', '22222222-2222-2222-2222-222222222252',
   '4010', 'Service Revenue',   'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000584', '22222222-2222-2222-2222-222222222252',
   '5010', 'Adjustment Expense','expense', 'debit',  true, true, auth.uid(), auth.uid());

-- ── Opening balance before the report range ───────────────────────────────────
INSERT INTO journal_entries (id, company_id, branch_id, je_number, je_date,
                             fiscal_period_id, description, reference_doc_type, status,
                             total_debit, total_credit, entry_class,
                             created_by, updated_by)
VALUES ('99999999-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222252',
        '33333333-3333-3333-3333-333333333352',
        'JE-OPEN-001', '2025-12-31',
        '45454545-4545-4545-4545-454545454412',
        'Opening balance',
        'MANUAL', 'posted', 1000, 1000, 'opening',
        auth.uid(), auth.uid());

INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id,
                                 description, debit_amount, credit_amount,
                                 created_by, updated_by)
VALUES
  ('99999999-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222252', 1,
   'aaaaaaaa-0000-0000-0000-000000000581',
   'Opening cash', 1000, 0, auth.uid(), auth.uid()),
  ('99999999-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222252', 2,
   'aaaaaaaa-0000-0000-0000-000000000582',
   'Opening equity', 0, 1000, auth.uid(), auth.uid());

-- ── 25 regular revenue journals: Dr Cash 100 / Cr Revenue 100 ─────────────────
WITH seed AS (
  SELECT
    n,
    ('99999999-0000-0000-0000-' || lpad((100 + n)::text, 12, '0'))::uuid AS je_id,
    make_date(2026, 1, n)::date AS je_date
  FROM generate_series(1, 25) AS n
)
INSERT INTO journal_entries (id, company_id, branch_id, fiscal_period_id,
                             je_number, je_date, description, reference_doc_type,
                             status, total_debit, total_credit, entry_class,
                             created_by, updated_by)
SELECT je_id,
       '22222222-2222-2222-2222-222222222252',
       '33333333-3333-3333-3333-333333333352',
       '45454545-4545-4545-4545-454545454501',
       'JE-JAN-' || lpad(n::text, 3, '0'),
       je_date,
       'Regular revenue ' || n,
       'MANUAL',
       'posted',
       100,
       100,
       'regular',
       auth.uid(),
       auth.uid()
FROM seed;

WITH seed AS (
  SELECT
    n,
    ('99999999-0000-0000-0000-' || lpad((100 + n)::text, 12, '0'))::uuid AS je_id
  FROM generate_series(1, 25) AS n
)
INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id,
                                 description, debit_amount, credit_amount,
                                 created_by, updated_by)
SELECT je_id,
       '22222222-2222-2222-2222-222222222252',
       line_number,
       account_id,
       description,
       debit_amount,
       credit_amount,
       auth.uid(),
       auth.uid()
FROM seed
CROSS JOIN LATERAL (
  VALUES
    (1, 'aaaaaaaa-0000-0000-0000-000000000581'::uuid, 'Cash receipt', 100::numeric, 0::numeric),
    (2, 'aaaaaaaa-0000-0000-0000-000000000583'::uuid, 'Service revenue', 0::numeric, 100::numeric)
) AS lines(line_number, account_id, description, debit_amount, credit_amount);

-- ── 5 adjusting expense journals: Dr Expense 10 / Cr Cash 10 ──────────────────
WITH seed AS (
  SELECT
    n,
    ('99999999-0000-0000-0000-' || lpad((200 + n)::text, 12, '0'))::uuid AS je_id,
    make_date(2026, 1, 25 + n)::date AS je_date
  FROM generate_series(1, 5) AS n
)
INSERT INTO journal_entries (id, company_id, branch_id, fiscal_period_id,
                             je_number, je_date, description, reference_doc_type,
                             status, total_debit, total_credit, entry_class,
                             created_by, updated_by)
SELECT je_id,
       '22222222-2222-2222-2222-222222222252',
       '33333333-3333-3333-3333-333333333352',
       '45454545-4545-4545-4545-454545454501',
       'JE-ADJ-' || lpad(n::text, 3, '0'),
       je_date,
       'Adjustment expense ' || n,
       'MANUAL',
       'posted',
       10,
       10,
       'adjusting',
       auth.uid(),
       auth.uid()
FROM seed;

WITH seed AS (
  SELECT
    n,
    ('99999999-0000-0000-0000-' || lpad((200 + n)::text, 12, '0'))::uuid AS je_id
  FROM generate_series(1, 5) AS n
)
INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id,
                                 description, debit_amount, credit_amount,
                                 created_by, updated_by)
SELECT je_id,
       '22222222-2222-2222-2222-222222222252',
       line_number,
       account_id,
       description,
       debit_amount,
       credit_amount,
       auth.uid(),
       auth.uid()
FROM seed
CROSS JOIN LATERAL (
  VALUES
    (1, 'aaaaaaaa-0000-0000-0000-000000000584'::uuid, 'Adjustment expense', 10::numeric, 0::numeric),
    (2, 'aaaaaaaa-0000-0000-0000-000000000581'::uuid, 'Cash adjustment', 0::numeric, 10::numeric)
) AS lines(line_number, account_id, description, debit_amount, credit_amount);

-- ── General Ledger report: server-side page + totals ──────────────────────────
SELECT is(
  (SELECT COUNT(*) FROM fn_general_ledger_report(
    '22222222-2222-2222-2222-222222222252', '2026-01-01', '2026-01-31',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 7, 0)),
  7::bigint,
  'general ledger report honors page size');

SELECT is(
  (SELECT total_rows FROM fn_general_ledger_report(
    '22222222-2222-2222-2222-222222222252', '2026-01-01', '2026-01-31',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 7, 0)
   LIMIT 1),
  60::bigint,
  'general ledger report returns total row count for the filtered period');

SELECT is(
  (SELECT period_debit FROM fn_general_ledger_report(
    '22222222-2222-2222-2222-222222222252', '2026-01-01', '2026-01-31',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 7, 0)
   LIMIT 1),
  2550::numeric,
  'general ledger report computes full filtered debit total independent of page');

SELECT is(
  (SELECT period_credit FROM fn_general_ledger_report(
    '22222222-2222-2222-2222-222222222252', '2026-01-01', '2026-01-31',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 7, 0)
   LIMIT 1),
  2550::numeric,
  'general ledger report computes full filtered credit total independent of page');

SELECT is(
  (SELECT COUNT(*) FROM fn_general_ledger_report(
    '22222222-2222-2222-2222-222222222252', '2026-01-01', '2026-01-31',
    NULL, NULL, NULL, NULL, ARRAY['revenue'], NULL, NULL, NULL, ARRAY['regular'], 500, 0)),
  25::bigint,
  'general ledger report supports account-type and entry-class filters server-side');

SELECT is(
  (SELECT COUNT(*) FROM fn_general_ledger_report(
    '22222222-2222-2222-2222-222222222252', '2026-01-01', '2026-01-31',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0)),
  1::bigint,
  'general ledger report clamps invalid small limits to one row');

-- ── Account-detail ledger: opening, running balance, total rows ───────────────
SELECT is(
  (SELECT total_rows FROM fn_gl_account_ledger_summary(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL)),
  30::bigint,
  'account ledger summary counts all period movement rows');

SELECT is(
  (SELECT opening_balance FROM fn_gl_account_ledger_summary(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL)),
  1000::numeric,
  'account ledger summary computes debit-normal opening balance');

SELECT is(
  (SELECT period_debit FROM fn_gl_account_ledger_summary(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL)),
  2500::numeric,
  'account ledger summary computes period debit total');

SELECT is(
  (SELECT period_credit FROM fn_gl_account_ledger_summary(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL)),
  50::numeric,
  'account ledger summary computes period credit total');

SELECT is(
  (SELECT closing_balance FROM fn_gl_account_ledger_summary(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL)),
  3450::numeric,
  'account ledger summary computes closing balance');

SELECT is(
  (SELECT COUNT(*) FROM fn_gl_account_ledger_page(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL, 10, 10)),
  10::bigint,
  'account ledger page returns requested page size');

SELECT is(
  (SELECT running_balance FROM fn_gl_account_ledger_page(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31', NULL, 10, 10)
   ORDER BY je_date, je_number, line_number, line_id
   LIMIT 1),
  2100::numeric,
  'account ledger page running balance includes rows before the page offset');

SELECT is(
  (SELECT COUNT(*) FROM fn_gl_account_ledger_page(
    '22222222-2222-2222-2222-222222222252',
    'aaaaaaaa-0000-0000-0000-000000000581',
    '2026-01-01', '2026-01-31',
    '99999999-0000-0000-0000-000000000201', 10, 0)),
  1::bigint,
  'account ledger page supports JE drilldown filtering without loading the period');

-- ── Trial Balance report: aggregation and mode filtering ──────────────────────
SELECT is(
  (SELECT closing_net FROM fn_trial_balance_report(
    '22222222-2222-2222-2222-222222222252',
    '2026-01-01', '2026-01-31', ARRAY['regular','opening'], false, NULL)
   WHERE account_id = 'aaaaaaaa-0000-0000-0000-000000000581'),
  3500::numeric,
  'unadjusted TB excludes adjusting cash credits');

SELECT is(
  (SELECT closing_net FROM fn_trial_balance_report(
    '22222222-2222-2222-2222-222222222252',
    '2026-01-01', '2026-01-31', ARRAY['regular','opening','adjusting'], false, NULL)
   WHERE account_id = 'aaaaaaaa-0000-0000-0000-000000000581'),
  3450::numeric,
  'adjusted TB includes adjusting cash credits');

SELECT is(
  (SELECT closing_net FROM fn_trial_balance_report(
    '22222222-2222-2222-2222-222222222252',
    '2026-01-01', '2026-01-31', ARRAY['regular','opening','adjusting'], false, NULL)
   WHERE account_id = 'aaaaaaaa-0000-0000-0000-000000000584'),
  50::numeric,
  'adjusted TB includes adjusting expense');

SELECT is(
  (SELECT ROUND(SUM(closing_net), 2) FROM fn_trial_balance_report(
    '22222222-2222-2222-2222-222222222252',
    '2026-01-01', '2026-01-31', ARRAY['regular','opening','adjusting'], false, NULL)),
  0::numeric,
  'adjusted TB report remains balanced server-side');

SELECT * FROM finish();
ROLLBACK;
