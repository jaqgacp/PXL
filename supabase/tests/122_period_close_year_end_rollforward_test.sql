-- PERIOD-CLOSE-001 — Period close, year-end close, and retained-earnings roll-forward
--
-- Delivery Plan Phase 6 (Backlog 18d). The accounting cycle now runs to the end:
-- transaction → posting → general ledger → trial balance → statements → period
-- close → year-end close → retained earnings → next fiscal year.
--
-- Section A pins the governance: the lock is not a column anyone can write, the
-- register is not a table anyone can author, and readiness is stated as data.
-- Section B runs the monthly and quarterly close and the reopen rules.
-- Section C runs the year-end close and, critically, forces the DEFERRED source
-- constraint that a rolled-back test can never see — the defect this phase found
-- was a close that passed every assertion and could not commit.
-- Section D proves the close is repeatable: reopen, re-close, and net income
-- lands in retained earnings once, not twice.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(34);

-- ── Fixture ────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111260',
        'authenticated', 'authenticated', 'harness-close6@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111260","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222260', 'corporation',
        'Period Close Test Corp', 'Trading', '111-222-333-060',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-close6@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333260',
        '22222222-2222-2222-2222-222222222260', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000601', '22222222-2222-2222-2222-222222222260',
   '1010', 'Cash in Bank',      'asset',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000602', '22222222-2222-2222-2222-222222222260',
   '3200', 'Retained Earnings', 'equity',  'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000603', '22222222-2222-2222-2222-222222222260',
   '4010', 'Sales Revenue',     'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000604', '22222222-2222-2222-2222-222222222260',
   '5010', 'Rent Expense',      'expense', 'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date,
                          is_calendar, retained_earnings_id)
VALUES ('44444444-4444-4444-4444-444444444260',
        '22222222-2222-2222-2222-222222222260',
        'FY2026', '2026-01-01', '2026-12-31', true,
        'aaaaaaaa-0000-0000-0000-000000000602');

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222260',
       '44444444-4444-4444-4444-444444444260',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

CREATE TEMP VIEW v_period AS
SELECT period_number, id FROM fiscal_periods
WHERE fiscal_year_id = '44444444-4444-4444-4444-444444444260';

-- Activity: revenue 100,000, expenses 25,000, so net income is 75,000.
SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222260', '33333333-3333-3333-3333-333333333260',
  '2026-01-15'::date, 'January sales', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000601","debit_amount":60000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000603","debit_amount":0,"credit_amount":60000}]'::jsonb);

SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222260', '33333333-3333-3333-3333-333333333260',
  '2026-01-20'::date, 'January rent', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000604","debit_amount":10000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000601","debit_amount":0,"credit_amount":10000}]'::jsonb);

SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222260', '33333333-3333-3333-3333-333333333260',
  '2026-02-10'::date, 'February sales', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000601","debit_amount":40000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000603","debit_amount":0,"credit_amount":40000}]'::jsonb);

SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222260', '33333333-3333-3333-3333-333333333260',
  '2026-03-05'::date, 'March rent', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000604","debit_amount":15000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000601","debit_amount":0,"credit_amount":15000}]'::jsonb);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — The lock and the register are governed, not writable
-- ══════════════════════════════════════════════════════════════════════════════

-- The whole point of a close engine is that the lock cannot be flipped around it.
SELECT throws_like($$
  UPDATE fiscal_periods SET is_locked = true
  WHERE fiscal_year_id = '44444444-4444-4444-4444-444444444260' AND period_number = 1
$$, '%Period locking is governed%',
  'a direct write to fiscal_periods.is_locked is refused');                          -- 1

SELECT throws_like($$
  UPDATE fiscal_years SET status = 'closed'
  WHERE id = '44444444-4444-4444-4444-444444444260'
$$, '%Period locking is governed%',
  'a direct write to fiscal_years.status is refused');                               -- 2

SELECT is(
  (SELECT count(*)::int FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'fiscal_close_runs'
     AND cmd <> 'SELECT' AND COALESCE(qual, with_check) = 'false'),
  3, 'the close register denies every direct write from authenticated');             -- 3

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.fiscal_close_runs'::regclass),
  'the close register enforces row-level security');                                 -- 4

-- Readiness is data, so the screen and the engine cannot disagree.
SELECT is(
  (fn_period_close_readiness('22222222-2222-2222-2222-222222222260',
                             (SELECT id FROM v_period WHERE period_number = 1))->>'ready')::boolean,
  true, 'the first period is ready to close');                                       -- 5

SELECT is(
  (fn_period_close_readiness('22222222-2222-2222-2222-222222222260',
                             (SELECT id FROM v_period WHERE period_number = 3))->>'ready')::boolean,
  false, 'a later period is not ready while an earlier one is open');                -- 6

SELECT is(
  (SELECT c->>'code'
   FROM jsonb_array_elements(
          fn_period_close_readiness('22222222-2222-2222-2222-222222222260',
            (SELECT id FROM v_period WHERE period_number = 3))->'checks') c
   WHERE c->>'severity' = 'blocking' AND (c->>'ok')::boolean = false),
  'prior_periods_closed',
  'the only blocking failure is the open earlier period');                           -- 7

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — Monthly and quarterly close, and the reopen rules
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TEMP TABLE t_run (label text, id uuid);

INSERT INTO t_run
SELECT 'p1', fn_close_accounting_period(
  '22222222-2222-2222-2222-222222222260',
  (SELECT id FROM v_period WHERE period_number = 1));

SELECT is(
  (SELECT is_locked FROM v_period p JOIN fiscal_periods f ON f.id = p.id
   WHERE p.period_number = 1),
  true, 'closing an accounting period locks it');                                    -- 8

SELECT is(
  (SELECT close_type || '/' || action FROM fiscal_close_runs
   WHERE id = (SELECT id FROM t_run WHERE label = 'p1')),
  'period/close', 'the close is recorded in the register');                          -- 9

-- The checks that admitted the close are kept with it, so the evidence outlives
-- the screen that showed it.
SELECT ok(
  (SELECT jsonb_array_length(checks) >= 4 FROM fiscal_close_runs
   WHERE id = (SELECT id FROM t_run WHERE label = 'p1')),
  'the register keeps the readiness evidence that admitted the close');              -- 10

SELECT throws_like(
  format($$SELECT fn_close_accounting_period('22222222-2222-2222-2222-222222222260', %L)$$,
         (SELECT id FROM v_period WHERE period_number = 1)),
  '%is already closed%', 'closing a closed period is refused');                      -- 11

SELECT throws_like($$
  SELECT fn_post_manual_je(
    '22222222-2222-2222-2222-222222222260', '33333333-3333-3333-3333-333333333260',
    '2026-01-25'::date, 'late January entry', 'MANUAL', false,
    '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000601","debit_amount":1,"credit_amount":0},
      {"account_id":"aaaaaaaa-0000-0000-0000-000000000603","debit_amount":0,"credit_amount":1}]'::jsonb)
$$, '%No open fiscal period%', 'a closed period refuses further posting');           -- 12

SELECT throws_like(
  format($$SELECT fn_close_accounting_period('22222222-2222-2222-2222-222222222260', %L)$$,
         (SELECT id FROM v_period WHERE period_number = 3)),
  '%is still open%', 'periods must close in date order');                            -- 13

-- A quarter is not a second closing concept: it is this same close, three times.
SELECT is(
  fn_close_accounting_quarter('22222222-2222-2222-2222-222222222260',
                              '44444444-4444-4444-4444-444444444260', 1),
  2, 'the quarterly close closes the quarter''s remaining periods');                 -- 14

SELECT is(
  (SELECT count(*)::int FROM v_period p JOIN fiscal_periods f ON f.id = p.id
   WHERE p.period_number <= 3 AND f.is_locked),
  3, 'all three periods of the first quarter are closed');                           -- 15

SELECT throws_like(
  format($$SELECT fn_reopen_accounting_period('22222222-2222-2222-2222-222222222260', %L, '  ')$$,
         (SELECT id FROM v_period WHERE period_number = 3)),
  '%reason is required%', 'reopening a period without a reason is refused');         -- 16

SELECT throws_like(
  format($$SELECT fn_reopen_accounting_period('22222222-2222-2222-2222-222222222260', %L, 'audit adjustment')$$,
         (SELECT id FROM v_period WHERE period_number = 2)),
  '%while the later period%', 'periods reopen last-in-first-out');                   -- 17

INSERT INTO t_run
SELECT 'r3', fn_reopen_accounting_period(
  '22222222-2222-2222-2222-222222222260',
  (SELECT id FROM v_period WHERE period_number = 3), 'audit adjustment');

SELECT is(
  (SELECT is_locked FROM v_period p JOIN fiscal_periods f ON f.id = p.id
   WHERE p.period_number = 3),
  false, 'the reopened period accepts postings again');                              -- 18

SELECT is(
  (SELECT superseded_by_id FROM fiscal_close_runs
   WHERE fiscal_period_id = (SELECT id FROM v_period WHERE period_number = 3)
     AND action = 'close'),
  (SELECT id FROM t_run WHERE label = 'r3'),
  'the reopen supersedes the close it undid rather than erasing it');                -- 19

SELECT throws_like($$
  DELETE FROM fiscal_close_runs
  WHERE company_id = '22222222-2222-2222-2222-222222222260'
$$, '%permanent evidence%', 'a recorded close cannot be deleted');                   -- 20

-- Close it again so the year starts from a fully closed first quarter.
SELECT lives_ok(
  format($$SELECT fn_close_accounting_period('22222222-2222-2222-2222-222222222260', %L)$$,
         (SELECT id FROM v_period WHERE period_number = 3)),
  'a reopened period can be closed again');                                          -- 21

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Year-end close and roll-forward
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TEMP TABLE t_close (label text, je_id uuid);

INSERT INTO t_close
SELECT 'first', fn_close_fiscal_year('22222222-2222-2222-2222-222222222260',
                                     '44444444-4444-4444-4444-444444444260');

SELECT is(
  (SELECT (total_debit = total_credit AND entry_class = 'closing'
           AND reference_doc_type = 'CLOSE'
           AND reference_doc_id = '44444444-4444-4444-4444-444444444260')
   FROM journal_entries WHERE id = (SELECT je_id FROM t_close WHERE label = 'first')),
  true,
  'the closing journal is balanced, classified closing, and sourced on the fiscal year'); -- 22

-- The regression that this phase exists to prevent. The source-integrity trigger
-- is DEFERRED, so a test that only rolls back never checks it: before this work
-- the close posted a NULL source and could not have committed in a real database.
SELECT lives_ok($$
  SELECT fn_assert_posting_source(
    je.reference_doc_type, je.reference_doc_id, je.company_id)
  FROM journal_entries je
  WHERE je.id = (SELECT je_id FROM t_close WHERE label = 'first')
$$, 'the closing journal satisfies the deferred source-integrity constraint');      -- 23

SELECT is(
  (SELECT COALESCE(SUM(credit_amount - debit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222260'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000603')::numeric,
  0::numeric, 'revenue is zero after the close');                                    -- 24

SELECT is(
  (SELECT COALESCE(SUM(debit_amount - credit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222260'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000604')::numeric,
  0::numeric, 'expenses are zero after the close');                                  -- 25

SELECT is(
  (SELECT COALESCE(SUM(credit_amount - debit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222260'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000602')::numeric,
  75000::numeric, 'retained earnings carries the year''s net income of 75,000');     -- 26

SELECT is(
  (SELECT COALESCE(SUM(debit_amount - credit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222260')::numeric,
  0::numeric, 'the general ledger still balances after the close');                  -- 27

SELECT is(
  (SELECT status FROM fiscal_years WHERE id = '44444444-4444-4444-4444-444444444260')
  || '/' ||
  (SELECT bool_and(is_locked)::text FROM fiscal_periods
   WHERE fiscal_year_id = '44444444-4444-4444-4444-444444444260'),
  'closed/true', 'the year is closed and every period is locked');                   -- 28

-- Roll-forward: the next year exists, with its periods and the same retained
-- earnings destination, without a separate operator step.
SELECT is(
  (SELECT fy.start_date::text || '/' || count(fp.id)::text || '/'
          || (fy.retained_earnings_id = 'aaaaaaaa-0000-0000-0000-000000000602')::text
   FROM fiscal_years fy
   LEFT JOIN fiscal_periods fp ON fp.fiscal_year_id = fy.id
   WHERE fy.company_id = '22222222-2222-2222-2222-222222222260'
     AND fy.start_date = '2027-01-01'
   GROUP BY fy.id, fy.start_date, fy.retained_earnings_id),
  '2027-01-01/12/true',
  'the close opens the next fiscal year with twelve periods and the same retained earnings account'); -- 29

SELECT throws_like($$
  SELECT fn_close_fiscal_year('22222222-2222-2222-2222-222222222260',
                              '44444444-4444-4444-4444-444444444260')
$$, '%already closed%', 'closing an already-closed year is refused');                -- 30

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Reopen and re-close: the close is repeatable, not cumulative
-- ══════════════════════════════════════════════════════════════════════════════

SELECT throws_like($$
  SELECT fn_reopen_fiscal_year('22222222-2222-2222-2222-222222222260',
                               '44444444-4444-4444-4444-444444444260', '')
$$, '%reason is required%', 'reopening a year without a reason is refused');         -- 31

INSERT INTO t_close
SELECT 'reopen', fn_reopen_fiscal_year('22222222-2222-2222-2222-222222222260',
                                       '44444444-4444-4444-4444-444444444260',
                                       'prior-year audit adjustment');

SELECT is(
  (SELECT COALESCE(SUM(credit_amount - debit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222260'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000602')::numeric,
  0::numeric,
  'reopening takes the net income back out of retained earnings');                   -- 32

-- The counter entry is classified `closing`, which is exactly why the re-close
-- recomputes 75,000 instead of aggregating its own reversal into the next figure.
SELECT is(
  (SELECT entry_class FROM journal_entries
   WHERE id = (SELECT je_id FROM t_close WHERE label = 'reopen')),
  'closing', 'the reopening counter-journal is itself a closing entry');             -- 33

INSERT INTO t_close
SELECT 'second', fn_close_fiscal_year('22222222-2222-2222-2222-222222222260',
                                      '44444444-4444-4444-4444-444444444260');

SELECT is(
  (SELECT COALESCE(SUM(credit_amount - debit_amount), 0)
   FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222260'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000602')::numeric,
  75000::numeric,
  'closing the reopened year again lands 75,000 in retained earnings, not 150,000'); -- 34

SELECT * FROM finish();
ROLLBACK;
