-- FINANCIAL-CLOSE-001 — JE classification, Trial Balance modes, and year-end close
--
-- PXL-AUD-013 + PXL-DA-014: journal entries carry an entry_class; the Trial
-- Balance is defined by mode (unadjusted = regular+opening, adjusted = +adjusting,
-- post-closing = +closing); and fn_close_fiscal_year posts one balanced closing
-- journal that zeroes revenue/expense and carries net income to retained earnings,
-- then locks the year. Direct-to-retained-earnings close per DEC-019.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- Identity
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111240',
        'authenticated', 'authenticated', 'harness-close@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111240","role":"authenticated"}', true);

-- Company (creator auto-becomes owner => can_admin_company = true)
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222240', 'corporation',
        'Close Readiness Test Corp', 'Trading', '111-222-333-040',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-close@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333240',
        '22222222-2222-2222-2222-222222222240', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

-- Chart of accounts (retained earnings is a postable equity account)
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000401', '22222222-2222-2222-2222-222222222240',
   '1010', 'Cash in Bank',      'asset',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000402', '22222222-2222-2222-2222-222222222240',
   '3200', 'Retained Earnings', 'equity',  'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000403', '22222222-2222-2222-2222-222222222240',
   '4010', 'Sales Revenue',     'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000404', '22222222-2222-2222-2222-222222222240',
   '5010', 'Rent Expense',      'expense', 'debit',  true, true, auth.uid(), auth.uid());

-- Fiscal year with retained earnings destination, plus 12 open periods
INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date,
                          is_calendar, retained_earnings_id)
VALUES ('44444444-4444-4444-4444-444444444240',
        '22222222-2222-2222-2222-222222222240',
        'FY2026', '2026-01-01', '2026-12-31', true,
        'aaaaaaaa-0000-0000-0000-000000000402');

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222240',
       '44444444-4444-4444-4444-444444444240',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

-- ── Post activity ──────────────────────────────────────────────────────────────
-- Regular: revenue 100,000 (Dr Cash / Cr Sales)
SELECT lives_ok($$
  SELECT fn_post_manual_je(
    '22222222-2222-2222-2222-222222222240', '33333333-3333-3333-3333-333333333240',
    '2026-03-15'::date, 'Sales for March', 'MANUAL', false,
    '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000401","debit_amount":100000,"credit_amount":0},
      {"account_id":"aaaaaaaa-0000-0000-0000-000000000403","debit_amount":0,"credit_amount":100000}]'::jsonb)
$$, 'regular revenue journal posts');

-- Regular: rent expense 30,000 (Dr Rent / Cr Cash)
SELECT lives_ok($$
  SELECT fn_post_manual_je(
    '22222222-2222-2222-2222-222222222240', '33333333-3333-3333-3333-333333333240',
    '2026-03-20'::date, 'March rent', 'MANUAL', false,
    '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000404","debit_amount":30000,"credit_amount":0},
      {"account_id":"aaaaaaaa-0000-0000-0000-000000000401","debit_amount":0,"credit_amount":30000}]'::jsonb)
$$, 'regular expense journal posts');

-- The default classification is 'regular'
SELECT is(
  (SELECT entry_class FROM journal_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND description = 'March rent'),
  'regular',
  'fn_post_manual_je defaults entry_class to regular');

-- Adjusting: additional 5,000 rent accrual, classified adjusting
SELECT lives_ok($$
  SELECT fn_post_manual_je(
    '22222222-2222-2222-2222-222222222240', '33333333-3333-3333-3333-333333333240',
    '2026-03-31'::date, 'Rent accrual adjustment', 'MANUAL', false,
    '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000404","debit_amount":5000,"credit_amount":0},
      {"account_id":"aaaaaaaa-0000-0000-0000-000000000401","debit_amount":0,"credit_amount":5000}]'::jsonb,
    'adjusting')
$$, 'adjusting journal posts with entry_class=adjusting');

SELECT is(
  (SELECT entry_class FROM journal_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND description = 'Rent accrual adjustment'),
  'adjusting',
  'adjusting classification is stored');

-- Manual path cannot post a closing entry
SELECT throws_like($$
  SELECT fn_post_manual_je(
    '22222222-2222-2222-2222-222222222240', '33333333-3333-3333-3333-333333333240',
    '2026-04-01'::date, 'illegal close', 'MANUAL', false,
    '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000401","debit_amount":1,"credit_amount":0},
      {"account_id":"aaaaaaaa-0000-0000-0000-000000000403","debit_amount":0,"credit_amount":1}]'::jsonb,
    'closing')
$$, '%may only be classified regular, adjusting, or opening%',
   'manual JE rejects the closing classification');

-- ── Trial Balance modes ─────────────────────────────────────────────────────────
-- Unadjusted: rent expense excludes the adjusting entry (30,000)
SELECT is(
  (SELECT COALESCE(SUM(debit_amount - credit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000404'
     AND entry_class IN ('regular','opening'))::numeric,
  30000::numeric,
  'unadjusted TB rent expense excludes the adjusting entry');

-- Adjusted: rent expense includes the adjusting entry (35,000)
SELECT is(
  (SELECT COALESCE(SUM(debit_amount - credit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000404'
     AND entry_class IN ('regular','opening','adjusting'))::numeric,
  35000::numeric,
  'adjusted TB rent expense includes the adjusting entry');

-- Fiscal year is open before the close
SELECT is(
  (SELECT status FROM fiscal_years WHERE id = '44444444-4444-4444-4444-444444444240'),
  'open', 'fiscal year is open before close');

-- ── Year-end close ───────────────────────────────────────────────────────────────
CREATE TEMP TABLE t_close (je_id uuid);
INSERT INTO t_close
SELECT fn_close_fiscal_year('22222222-2222-2222-2222-222222222240',
                            '44444444-4444-4444-4444-444444444240');

SELECT isnt((SELECT je_id FROM t_close), NULL,
  'fn_close_fiscal_year posts a closing journal');

-- Closing journal is balanced and correctly classified
SELECT is(
  (SELECT (total_debit = total_credit AND entry_class = 'closing'
           AND reference_doc_type = 'CLOSE')
   FROM journal_entries WHERE id = (SELECT je_id FROM t_close)),
  true, 'closing journal is balanced, classified closing, sourced CLOSE');

-- Post-closing TB: revenue nets to zero
SELECT is(
  (SELECT COALESCE(SUM(credit_amount - debit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000403'
     AND entry_class IN ('regular','opening','adjusting','closing'))::numeric,
  0::numeric, 'post-closing revenue balance is zero');

-- Post-closing TB: expense nets to zero
SELECT is(
  (SELECT COALESCE(SUM(debit_amount - credit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000404'
     AND entry_class IN ('regular','opening','adjusting','closing'))::numeric,
  0::numeric, 'post-closing expense balance is zero');

-- Retained earnings carries net income = 100,000 - 35,000 = 65,000 (credit)
SELECT is(
  (SELECT COALESCE(SUM(credit_amount - debit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222240'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000402')::numeric,
  65000::numeric, 'retained earnings carries net income of 65,000');

-- Fiscal year is now closed and its periods locked
SELECT is(
  (SELECT status FROM fiscal_years WHERE id = '44444444-4444-4444-4444-444444444240'),
  'closed', 'fiscal year is marked closed');

SELECT is(
  (SELECT bool_and(is_locked) FROM fiscal_periods
   WHERE fiscal_year_id = '44444444-4444-4444-4444-444444444240'),
  true, 'all periods of the closed year are locked');

-- Re-closing a closed year is rejected
SELECT throws_like($$
  SELECT fn_close_fiscal_year('22222222-2222-2222-2222-222222222240',
                              '44444444-4444-4444-4444-444444444240')
$$, '%already closed%', 'closing an already-closed year is rejected');

SELECT * FROM finish();
ROLLBACK;
