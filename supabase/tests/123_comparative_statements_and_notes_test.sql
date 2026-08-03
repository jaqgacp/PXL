-- COMPARATIVE-FS-001 — Comparative financial statements and basic notes
--
-- Backlog 18e. Completes the reporting path: posted transactions → general
-- ledger → trial balance → current-period statements → comparative statements →
-- basic notes.
--
-- Section A is a regression, and it is the reason this file exists in this
-- shape. Period close (18d) shipped yesterday and, in doing so, silently broke
-- two of the four statements for any CLOSED year: the closing journal debits
-- revenue and credits expense, so the Statement of Comprehensive Income of a
-- closed year read as ALL ZEROES and the Statement of Cash Flows moved the
-- year's entire operating cash flow into financing. Nothing had ever closed a
-- year before, and comparatives are the first feature that reads a closed year
-- on purpose — a comparative column drawn from a closed prior year would have
-- been blank.
--
-- Sections B and C run the comparative itself over two fiscal years, the first
-- of them closed. Section D proves the drill-down adds up. Section E proves the
-- notes report configuration rather than assume it.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(33);

-- ── Fixture ────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111270',
        'authenticated', 'authenticated', 'harness-cmp@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111270","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, trade_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222270', 'corporation',
        'Comparative Statements Test Corp', 'CompStat', 'Trading', '111-222-333-070',
        'vat', 'calendar',
        'Unit 7', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-cmp@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333270',
        '22222222-2222-2222-2222-222222222270', 'HO', 'Head Office',
        'Unit 7', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               fs_group, is_cash_equivalent, cash_flow_category,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000701', '22222222-2222-2222-2222-222222222270',
   '1010', 'Cash in Bank', 'asset', 'debit', true, true, 'assets', true, 'operating', auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000702', '22222222-2222-2222-2222-222222222270',
   '1200', 'Accounts Receivable', 'asset', 'debit', true, true, 'assets', false, 'operating', auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000703', '22222222-2222-2222-2222-222222222270',
   '3200', 'Retained Earnings', 'equity', 'credit', true, true, 'equity', false, 'financing', auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000704', '22222222-2222-2222-2222-222222222270',
   '4010', 'Sales Revenue', 'revenue', 'credit', true, true, 'revenue', false, 'operating', auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000705', '22222222-2222-2222-2222-222222222270',
   '6010', 'Rent Expense', 'expense', 'debit', true, true, 'expenses', false, 'operating', auth.uid(), auth.uid());

SELECT fn_seed_company_fs_structure('22222222-2222-2222-2222-222222222270');
SELECT fn_map_company_fs_accounts('22222222-2222-2222-2222-222222222270');

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date,
                          is_calendar, retained_earnings_id)
VALUES ('44444444-4444-4444-4444-444444444270',
        '22222222-2222-2222-2222-222222222270',
        'FY2026', '2026-01-01', '2026-12-31', true,
        'aaaaaaaa-0000-0000-0000-000000000703');

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222270',
       '44444444-4444-4444-4444-444444444270',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

-- FY2026: revenue 100,000, rent 40,000 → net income 60,000.
SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222270', '33333333-3333-3333-3333-333333333270',
  '2026-04-10'::date, 'FY2026 sales', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000701","debit_amount":100000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000704","debit_amount":0,"credit_amount":100000}]'::jsonb);
SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222270', '33333333-3333-3333-3333-333333333270',
  '2026-07-15'::date, 'FY2026 rent', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000705","debit_amount":40000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000701","debit_amount":0,"credit_amount":40000}]'::jsonb);

-- Snapshot FY2026 as it reads while the year is still open.
CREATE TEMP TABLE t_open AS
SELECT 'is_rev' AS k, movement_amount AS v FROM fn_financial_statement_report(
  '22222222-2222-2222-2222-222222222270', 'income_statement', '2026-01-01', '2026-12-31')
WHERE line_code = 'IS-REV'
UNION ALL
SELECT 'cf_op', movement_amount FROM fn_financial_statement_report(
  '22222222-2222-2222-2222-222222222270', 'cash_flow', '2026-01-01', '2026-12-31')
WHERE line_code = 'CF-OP';

-- Close FY2026. This posts the closing journal AND opens FY2027 with its periods.
SELECT fn_close_fiscal_year('22222222-2222-2222-2222-222222222270',
                            '44444444-4444-4444-4444-444444444270');

-- FY2027: revenue 150,000, rent 50,000 → net income 100,000.
SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222270', '33333333-3333-3333-3333-333333333270',
  '2027-03-20'::date, 'FY2027 sales', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000701","debit_amount":150000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000704","debit_amount":0,"credit_amount":150000}]'::jsonb);
SELECT fn_post_manual_je(
  '22222222-2222-2222-2222-222222222270', '33333333-3333-3333-3333-333333333270',
  '2027-08-05'::date, 'FY2027 rent', 'MANUAL', false,
  '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000705","debit_amount":50000,"credit_amount":0},
    {"account_id":"aaaaaaaa-0000-0000-0000-000000000701","debit_amount":0,"credit_amount":50000}]'::jsonb);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — A closed year still reports the year it had
-- ══════════════════════════════════════════════════════════════════════════════

SELECT is(
  (SELECT movement_amount FROM fn_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'income_statement', '2026-01-01', '2026-12-31')
   WHERE line_code = 'IS-REV'),
  (SELECT v FROM t_open WHERE k = 'is_rev'),
  'closing the year does not change the revenue it earned');                         -- 1

SELECT is(
  (SELECT movement_amount FROM fn_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'income_statement', '2026-01-01', '2026-12-31')
   WHERE line_code = 'IS-REV'),
  100000.00::numeric(18,2),
  'the closed year reports its 100,000 of revenue, not zero');                       -- 2

SELECT is(
  (SELECT movement_amount FROM fn_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'cash_flow', '2026-01-01', '2026-12-31')
   WHERE line_code = 'CF-OP'),
  (SELECT v FROM t_open WHERE k = 'cf_op'),
  'closing the year does not reclassify its operating cash flow');                   -- 3

SELECT is(
  (SELECT movement_amount FROM fn_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'cash_flow', '2026-01-01', '2026-12-31')
   WHERE line_code = 'CF-FIN'),
  0.00::numeric(18,2),
  'the close is not a financing activity');                                          -- 4

-- The position must still see the close: that is where retained earnings is.
SELECT is(
  (SELECT closing_amount FROM fn_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'balance_sheet', '2026-01-01', '2026-12-31')
   WHERE line_code = 'BS-E'),
  60000.00::numeric(18,2),
  'the closed year''s equity carries the 60,000 the close moved there');             -- 5

SELECT is(
  (SELECT closing_amount FROM fn_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'balance_sheet', '2026-01-01', '2026-12-31')
   WHERE line_role = 'current_year_earnings'),
  0.00::numeric(18,2),
  'and undistributed profit falls to zero once the year is closed');                 -- 6

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — Which period is the comparative
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TEMP VIEW cmp AS
SELECT fn_resolve_comparative_period(
  '22222222-2222-2222-2222-222222222270', '2027-01-01', '2027-12-31') AS j;

SELECT is((SELECT (j->>'available')::boolean FROM cmp), true,
  'FY2027 has a comparative period');                                                -- 7

SELECT is(
  (SELECT (j->>'prior_period_start') || '/' || (j->>'prior_period_end') FROM cmp),
  '2026-01-01/2026-12-31',
  'the comparative is the whole of the prior fiscal year');                          -- 8

SELECT is((SELECT j->>'prior_fiscal_year_name' FROM cmp), 'FY2026',
  'and it is named as the fiscal year it is');                                       -- 9

SELECT is((SELECT (j->>'prior_year_closed')::boolean FROM cmp), true,
  'the reader is told the comparative comes from closed books');                     -- 10

-- A part-year reads against the same part of the prior year, not the whole of it.
SELECT is(
  (SELECT (fn_resolve_comparative_period(
             '22222222-2222-2222-2222-222222222270', '2027-01-01', '2027-06-30')->>'prior_period_end')),
  '2026-06-30',
  'a half-year compares against the same half of the prior year');                   -- 11

-- The honest answers, returned as data rather than raised.
SELECT is(
  (fn_resolve_comparative_period(
     '22222222-2222-2222-2222-222222222270', '2026-01-01', '2026-12-31')->>'available')::boolean,
  false, 'the earliest fiscal year has no comparative');                             -- 12

SELECT alike(
  (fn_resolve_comparative_period(
     '22222222-2222-2222-2222-222222222270', '2026-01-01', '2026-12-31')->>'reason'),
  '%earliest fiscal year%',
  'and says why, in words a user can act on');                                       -- 13

SELECT alike(
  (fn_resolve_comparative_period(
     '22222222-2222-2222-2222-222222222270', '2026-06-01', '2027-06-30')->>'reason'),
  '%crosses a fiscal-year boundary%',
  'a range spanning two fiscal years is refused with its own reason');               -- 14

SELECT throws_like($$
  SELECT * FROM fn_comparative_financial_statement_report(
    '22222222-2222-2222-2222-222222222270', 'income_statement', '2026-01-01', '2026-12-31')
$$, '%No comparative period is available%',
  'the comparative report fails clearly when there is nothing to compare');          -- 15

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — The four comparative statements
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TEMP VIEW c_is AS SELECT * FROM fn_comparative_financial_statement_report(
  '22222222-2222-2222-2222-222222222270', 'income_statement', '2027-01-01', '2027-12-31');
CREATE TEMP VIEW c_bs AS SELECT * FROM fn_comparative_financial_statement_report(
  '22222222-2222-2222-2222-222222222270', 'balance_sheet', '2027-01-01', '2027-12-31');
CREATE TEMP VIEW c_cf AS SELECT * FROM fn_comparative_financial_statement_report(
  '22222222-2222-2222-2222-222222222270', 'cash_flow', '2027-01-01', '2027-12-31');
CREATE TEMP VIEW c_eq AS SELECT * FROM fn_comparative_financial_statement_report(
  '22222222-2222-2222-2222-222222222270', 'equity_statement', '2027-01-01', '2027-12-31');

SELECT is(
  (SELECT current_amount || '/' || prior_amount || '/' || variance_amount || '/' || variance_percent
   FROM c_is WHERE line_code = 'IS-REV'),
  '150000.00/100000.00/50000.00/50.00',
  'comprehensive income: revenue 150,000 against 100,000 is +50,000, +50%');         -- 16

SELECT is(
  (SELECT current_amount || '/' || prior_amount || '/' || variance_amount || '/' || variance_percent
   FROM c_is WHERE line_code = 'IS-NI'),
  '100000.00/60000.00/40000.00/66.67',
  'net income 100,000 against 60,000 is +40,000, +66.67%');                          -- 17

SELECT is((SELECT DISTINCT comparison_basis FROM c_is), 'movement',
  'a performance statement compares movements');                                     -- 18

SELECT is((SELECT DISTINCT comparison_basis FROM c_bs), 'closing',
  'a position compares balances');                                                   -- 19

SELECT is(
  (SELECT current_amount || '/' || prior_amount FROM c_bs WHERE line_code = 'BS-A'),
  '160000.00/60000.00',
  'financial position: assets 160,000 against 60,000');                              -- 20

-- The comparative position must balance in BOTH columns, or it is not a
-- statement of financial position in either year.
SELECT is(
  (SELECT (a.current_amount - l.current_amount - e.current_amount)::numeric(18,2)
   FROM c_bs a, c_bs l, c_bs e
   WHERE a.line_code = 'BS-A' AND l.line_code = 'BS-L' AND e.line_code = 'BS-E'),
  0.00::numeric(18,2), 'the current column balances');                               -- 21

SELECT is(
  (SELECT (a.prior_amount - l.prior_amount - e.prior_amount)::numeric(18,2)
   FROM c_bs a, c_bs l, c_bs e
   WHERE a.line_code = 'BS-A' AND l.line_code = 'BS-L' AND e.line_code = 'BS-E'),
  0.00::numeric(18,2), 'and so does the comparative column');                        -- 22

SELECT is(
  (SELECT current_amount || '/' || prior_amount FROM c_cf WHERE line_code = 'CF-OP'),
  '100000.00/60000.00',
  'cash flows: operating 100,000 against 60,000');                                   -- 23

-- The cash flow statement's own proof, in the comparative column too.
SELECT is(
  (SELECT (n.prior_amount - c.prior_amount)::numeric(18,2)
   FROM c_cf n, c_cf c WHERE n.line_code = 'CF-NET' AND c.line_code = 'CF-CASH'),
  0.00::numeric(18,2),
  'the comparative cash flow still ties to the movement in cash');                   -- 24

SELECT is(
  (SELECT current_amount || '/' || prior_amount FROM c_eq WHERE line_code = 'EQ-TOT'),
  '160000.00/60000.00',
  'changes in equity: closing equity 160,000 against 60,000');                       -- 25

-- Equity must agree with the position it belongs to, in both columns.
SELECT is(
  (SELECT (q.prior_amount - b.prior_amount)::numeric(18,2)
   FROM c_eq q, c_bs b WHERE q.line_code = 'EQ-TOT' AND b.line_code = 'BS-E'),
  0.00::numeric(18,2),
  'and the comparative equity agrees with the comparative position');                -- 26

-- A percentage against a zero base is no percentage, not a large one.
SELECT is(
  (SELECT variance_percent FROM c_bs WHERE line_code = 'BS-L'),
  NULL::numeric(12,2),
  'no percentage is invented against a nil comparative');                            -- 27

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — The drill-down adds up, and re-presentation restates both columns
-- ══════════════════════════════════════════════════════════════════════════════

SELECT is(
  (SELECT current_amount || '/' || prior_amount
   FROM fn_financial_statement_line_accounts(
     '22222222-2222-2222-2222-222222222270', 'income_statement', 'IS-REV',
     '2027-01-01', '2027-12-31', '2026-01-01', '2026-12-31')
   WHERE account_code = '4010'),
  '150000.00/100000.00',
  'the revenue line opens to the account that produced it, both columns');           -- 28

SELECT is(
  (SELECT SUM(current_amount)::numeric(18,2)
   FROM fn_financial_statement_line_accounts(
     '22222222-2222-2222-2222-222222222270', 'balance_sheet', 'BS-A',
     '2027-01-01', '2027-12-31', '2026-01-01', '2026-12-31')),
  (SELECT current_amount FROM c_bs WHERE line_code = 'BS-A'),
  'the accounts behind a subtotal sum to the subtotal');                             -- 29

-- Re-presenting an account must move BOTH columns, or the comparative is being
-- read on two different structures and compares nothing.
UPDATE account_fs_map m
SET fs_structure_id = (SELECT f.id FROM fs_structure f
                        WHERE f.company_id = m.company_id
                          AND f.statement = 'balance_sheet' AND f.line_code = 'BS-A-NON')
WHERE m.company_id = '22222222-2222-2222-2222-222222222270'
  AND m.statement = 'balance_sheet'
  AND m.account_id = 'aaaaaaaa-0000-0000-0000-000000000701';

SELECT is(
  (SELECT current_amount || '/' || prior_amount
   FROM fn_comparative_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'balance_sheet', '2027-01-01', '2027-12-31')
   WHERE line_code = 'BS-A-NON'),
  '160000.00/60000.00',
  're-mapping cash moves the current AND the comparative column together');          -- 30

SELECT is(
  (SELECT current_amount || '/' || prior_amount
   FROM fn_comparative_financial_statement_report(
     '22222222-2222-2222-2222-222222222270', 'balance_sheet', '2027-01-01', '2027-12-31')
   WHERE line_code = 'BS-A'),
  '160000.00/60000.00',
  'and total assets are unchanged in both — presentation moved, the ledger did not'); -- 31

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — The notes report configuration; they do not assume it
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TEMP VIEW notes AS SELECT * FROM fn_financial_statement_notes(
  '22222222-2222-2222-2222-222222222270', '2027-01-01', '2027-12-31');

SELECT is(
  (SELECT item_value FROM notes WHERE note_code = 'NOTE-02' AND item_label = 'Comparative period'),
  '2026-01-01 to 2026-12-31',
  'the notes state the comparative period the statements actually used');            -- 32

SELECT is(
  (SELECT is_configured FROM notes
   WHERE note_code = 'NOTE-04' AND item_label = 'Inventory costing'),
  false,
  'an unconfigured policy is reported as unconfigured, not as a default');           -- 33

SELECT * FROM finish();
ROLLBACK;
