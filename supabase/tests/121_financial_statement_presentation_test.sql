-- ══════════════════════════════════════════════════════════════════════════════
-- 121 — Financial statement presentation (Delivery Plan Phase 5.7)
--
-- WHAT THIS GUARDS
--   `fs_structure` and `account_fs_map` had existed since the schema was laid
--   down and had **never held a single row**. The trial balance was correct and
--   out of balance by ₱0.00 in every company, and PXL still could not produce a
--   statement an accountant could sign: the four Financial Statement screens
--   grouped postable accounts by `account_type` in the browser, with the layout
--   hardcoded in TSX.
--
--   This file proves the closed path on a company it provisions itself —
--   template chart of accounts, governed statement structure, a real posted
--   transaction — and then asserts the things that make a statement a statement:
--   it balances, it ties to the ledger it came from, its subtotals are the sum of
--   what sits under them, and its layout is CONFIGURATION, not code. The last
--   claim is asserted by re-mapping an account and watching the statement follow.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Period close. Revenue and expense balances are not rolled into retained
--   earnings by any process yet; the Statement of Financial Position balances
--   mid-year because the governed `current_year_earnings` line computes
--   undistributed profit, which is what it is for.
--   Comparative periods, note disclosures, and consolidation are not asserted.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

-- ── Fixture: a company with the standard chart, provisioned the normal way ───
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'fs-presentation@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12100000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12100000-0000-0000-0000-0000000000c1', 'corporation', 'Statement Trading Corp',
        'Wholesale trading', '401-000-001-00000', 'vat', 'calendar',
        'S St', 'S Bldg', 'Makati', 'Metro Manila', '1200',
        'fs-presentation@test.local', 'S Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12100000-0000-0000-0000-0000000000d1', '12100000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'S St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12100000-0000-0000-0000-0000000000f1', '12100000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12100000-0000-0000-0000-0000000000c1', '12100000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

-- The chart of accounts and its statement presentation are provisioned together.
SELECT is(fn_seed_company_coa('12100000-0000-0000-0000-0000000000c1'), 44,
  'the standard chart of accounts seeds 44 accounts');                              -- 1

-- Seeding the chart maps it: a company can never end up with accounts it cannot
-- present. Re-running the mapper therefore has nothing left to do, which is also
-- what makes an administrator's own re-mapping safe from re-provisioning.
SELECT is(fn_map_company_fs_accounts('12100000-0000-0000-0000-0000000000c1'), 0,
  'seeding the chart already bound every account — re-mapping is a no-op');         -- 2

CREATE TEMP VIEW acct AS
SELECT account_code, id FROM chart_of_accounts
WHERE company_id = '12100000-0000-0000-0000-0000000000c1';

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, inventory_account_id, created_by, updated_by)
SELECT '12100000-0000-0000-0000-0000000000c1',
       (SELECT id FROM acct WHERE account_code='1200'),
       (SELECT id FROM acct WHERE account_code='2100'),
       (SELECT id FROM acct WHERE account_code='1010'),
       (SELECT id FROM acct WHERE account_code='1300'),
       auth.uid(), auth.uid();

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12100000-0000-0000-0000-0000000000c1', '12100000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-121-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('CS', 'OR');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('12100000-0000-0000-0000-0000000000e1', '12100000-0000-0000-0000-0000000000c1',
        'CUST-121', 'Statement Buyer Inc', '444-555-666-121',
        'Pasig', 'Pasig', auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('12100000-0000-0000-0000-0000000000ab', '12100000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('12100000-0000-0000-0000-0000000000ca', '12100000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_sales_vat_id,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
SELECT '12100000-0000-0000-0000-0000000000bb', '12100000-0000-0000-0000-0000000000c1',
       'GOODS-121', 'Traded Merchandise', 'inventory_item',
       '12100000-0000-0000-0000-0000000000ca', '12100000-0000-0000-0000-0000000000ab',
       1000, 600, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
       (SELECT id FROM acct WHERE account_code='4010'),
       (SELECT id FROM acct WHERE account_code='5010'),
       (SELECT id FROM acct WHERE account_code='1300'),
       'weighted_average', auth.uid(), auth.uid();

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, created_by, updated_by)
SELECT '12100000-0000-0000-0000-0000000000ba', '12100000-0000-0000-0000-0000000000c1',
       '12100000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
       (SELECT id FROM acct WHERE account_code='1300'), auth.uid(), auth.uid();

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('12100000-0000-0000-0000-0000000000c1', '12100000-0000-0000-0000-0000000000ba',
        '12100000-0000-0000-0000-0000000000bb', 10, 6000, 600);

-- The opening position is journalised through the production cut-over RPC, so
-- every figure in every statement below comes from the posted ledger and not
-- from a table someone loaded directly.
SELECT fn_post_opening_balance(fn_save_opening_balance(
  NULL,
  jsonb_build_object(
    'company_id',   '12100000-0000-0000-0000-0000000000c1',
    'branch_id',    '12100000-0000-0000-0000-0000000000d1',
    'batch_number', 'OB-121-001', 'cutover_date', '2026-01-01',
    'description',  'Opening position for statement presentation'
  ),
  jsonb_build_array(
    jsonb_build_object('account_id', (SELECT id FROM acct WHERE account_code='1300'),
                       'description', 'Opening inventory', 'debit_amount', 6000, 'credit_amount', 0),
    jsonb_build_object('account_id', (SELECT id FROM acct WHERE account_code='3010'),
                       'description', 'Opening capital', 'debit_amount', 0, 'credit_amount', 6000)
  )));

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Presentation is configuration, and it exists
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT count(*) FROM fs_structure
    WHERE company_id = '12100000-0000-0000-0000-0000000000c1') >= 20,
  'fs_structure holds a governed line hierarchy — the table is no longer empty'); -- 3

SELECT set_eq(
  $$SELECT DISTINCT statement::text FROM fs_structure
     WHERE company_id = '12100000-0000-0000-0000-0000000000c1'$$,
  $$VALUES ('balance_sheet'), ('income_statement'), ('cash_flow'), ('equity_statement')$$,
  'all four statements have a structure');                                          -- 4

-- The governing rule: one account, one line, per statement.
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT account_id, statement FROM account_fs_map
      WHERE company_id = '12100000-0000-0000-0000-0000000000c1' AND effective_to IS NULL
      GROUP BY account_id, statement HAVING count(*) > 1) x),
  0, 'no account maps to more than one line of the same statement');                -- 5

SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts c
    WHERE c.company_id = '12100000-0000-0000-0000-0000000000c1' AND c.is_postable
      AND NOT EXISTS (SELECT 1 FROM account_fs_map m
                       WHERE m.account_id = c.id AND m.effective_to IS NULL
                         AND m.statement = c.fs_statement)),
  0, 'every postable account reaches a position or income-statement line');         -- 6

SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts c
    WHERE c.company_id = '12100000-0000-0000-0000-0000000000c1' AND c.is_postable
      AND NOT EXISTS (SELECT 1 FROM account_fs_map m
                       WHERE m.account_id = c.id AND m.effective_to IS NULL
                         AND m.statement = 'cash_flow')),
  0, 'and every postable account is classified for the cash flow statement');       -- 7

SELECT ok(
  (SELECT count(*) FROM chart_of_accounts
    WHERE company_id = '12100000-0000-0000-0000-0000000000c1' AND is_cash_equivalent) = 2,
  'the two cash accounts are marked as what the cash flow reconciles to');          -- 8

SELECT is(
  (SELECT count(*)::int FROM account_fs_map m
    JOIN fs_structure f ON f.id = m.fs_structure_id
   WHERE m.company_id = '12100000-0000-0000-0000-0000000000c1'
     AND f.line_role IN ('subtotal', 'current_year_earnings')),
  0, 'no account is mapped to a subtotal or to current-year earnings');             -- 9

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — A real transaction reaches the statements
--
-- One cash sale: 4 units at 1,000 = 4,000 revenue, 480 output VAT, 4,480 gross
-- collected in cash, 2,400 of inventory relieved to COGS.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '12100000-0000-0000-0000-0000000000c1',
    'branch_id',              '12100000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-05',
    'customer_id',            '12100000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Statement Buyer Inc',
    'warehouse_id',           '12100000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',     '12100000-0000-0000-0000-0000000000bb',
    'description', 'Traded Merchandise',
    'quantity',    4,
    'unit_price',  1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
  )),
  0);

CREATE TEMP VIEW bs AS
SELECT * FROM fn_financial_statement_report(
  '12100000-0000-0000-0000-0000000000c1', 'balance_sheet', '2026-01-01', '2026-12-31');
CREATE TEMP VIEW is_ AS
SELECT * FROM fn_financial_statement_report(
  '12100000-0000-0000-0000-0000000000c1', 'income_statement', '2026-01-01', '2026-12-31');
CREATE TEMP VIEW cf AS
SELECT * FROM fn_financial_statement_report(
  '12100000-0000-0000-0000-0000000000c1', 'cash_flow', '2026-01-01', '2026-12-31');
CREATE TEMP VIEW eq AS
SELECT * FROM fn_financial_statement_report(
  '12100000-0000-0000-0000-0000000000c1', 'equity_statement', '2026-01-01', '2026-12-31');

-- ── Statement of Comprehensive Income ────────────────────────────────────────
SELECT is((SELECT movement_amount FROM is_ WHERE line_code = 'IS-REV'),
  4000.00::numeric(18,2), 'income statement: revenue is 4,000');                    -- 10

SELECT is((SELECT movement_amount FROM is_ WHERE line_code = 'IS-COS'),
  -2400.00::numeric(18,2), 'cost of sales is shown as a 2,400 deduction');          -- 11

SELECT is((SELECT movement_amount FROM is_ WHERE line_code = 'IS-GP'),
  1600.00::numeric(18,2), 'gross profit rolls up from its children — 1,600');       -- 12

SELECT is((SELECT movement_amount FROM is_ WHERE line_code = 'IS-NI'),
  1600.00::numeric(18,2), 'net income rolls up the whole statement');               -- 13

-- ── Statement of Financial Position ──────────────────────────────────────────
SELECT is((SELECT closing_amount FROM bs WHERE line_code = 'BS-A'),
  8080.00::numeric(18,2),
  'assets total 8,080 — 4,480 cash plus the 3,600 of stock left on hand');          -- 14

SELECT is((SELECT closing_amount FROM bs WHERE line_code = 'BS-L'),
  480.00::numeric(18,2), 'liabilities are the 480 of output VAT payable');          -- 15

SELECT is((SELECT closing_amount FROM bs WHERE line_code = 'BS-E-CYE'),
  1600.00::numeric(18,2),
  'current year earnings equals net income, without any closing entry');            -- 16

SELECT is(
  (SELECT closing_amount FROM bs WHERE line_code = 'BS-A')
  - (SELECT closing_amount FROM bs WHERE line_code = 'BS-L')
  - (SELECT closing_amount FROM bs WHERE line_code = 'BS-E'),
  0.00::numeric,
  'THE STATEMENT BALANCES: assets = liabilities + equity');                         -- 17

SELECT is(
  (SELECT closing_amount FROM bs WHERE line_code = 'BS-A')
  - (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
       FROM journal_entry_lines jel
       JOIN chart_of_accounts c ON c.id = jel.account_id
      WHERE jel.company_id = '12100000-0000-0000-0000-0000000000c1'
        AND c.account_type = 'asset'),
  0.00::numeric, 'the position ties to the general ledger it came from');           -- 18

-- ── Statement of Cash Flows ──────────────────────────────────────────────────
SELECT is((SELECT movement_amount FROM cf WHERE line_code = 'CF-CASH'),
  4480.00::numeric(18,2), 'cash moved by 4,480 in the period');                     -- 19

SELECT is(
  (SELECT movement_amount FROM cf WHERE line_code = 'CF-NET')
  - (SELECT movement_amount FROM cf WHERE line_code = 'CF-CASH'),
  0.00::numeric,
  'THE CASH FLOW TIES: operating + investing + financing equals the cash movement'); -- 20

-- The split is what the indirect method actually says: the period consumed
-- 1,520 of cash in operations (the sale generated 4,480 of gross but 6,000 of
-- stock was bought into it) and raised 6,000 from the owner.
SELECT results_eq(
  $q$SELECT line_code, movement_amount FROM cf
      WHERE line_code IN ('CF-OP','CF-INV','CF-FIN') ORDER BY line_code$q$,
  $$VALUES ('CF-FIN'::text, 6000.00::numeric(18,2)),
           ('CF-INV'::text, 0.00::numeric(18,2)),
           ('CF-OP'::text, -1520.00::numeric(18,2))$$,
  'operating, investing and financing are classified from the governed metadata'); -- 21

-- ── Statement of Changes in Equity ───────────────────────────────────────────
SELECT is(
  (SELECT opening_amount + movement_amount - closing_amount FROM eq WHERE line_code = 'EQ-TOT'),
  0.00::numeric, 'equity opening plus movement equals closing');                    -- 22

SELECT is((SELECT closing_amount FROM eq WHERE line_code = 'EQ-TOT'),
  (SELECT closing_amount FROM bs WHERE line_code = 'BS-E'),
  'and total equity agrees with the Statement of Financial Position');              -- 23

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — The layout is configuration, not code
--
-- Re-present the same posted numbers by moving one account to a different
-- governed line. Nothing is re-posted and no code changes; the statement follows
-- the configuration. This is what makes a future local-GAAP or IFRS presentation
-- change a data change rather than a release.
-- ══════════════════════════════════════════════════════════════════════════════
UPDATE account_fs_map m
SET fs_structure_id = (SELECT f.id FROM fs_structure f
                        WHERE f.company_id = m.company_id
                          AND f.statement = 'balance_sheet' AND f.line_code = 'BS-A-NON')
WHERE m.company_id = '12100000-0000-0000-0000-0000000000c1'
  AND m.statement = 'balance_sheet'
  AND m.account_id = (SELECT id FROM acct WHERE account_code = '1300');

SELECT is(
  (SELECT closing_amount FROM fn_financial_statement_report(
     '12100000-0000-0000-0000-0000000000c1', 'balance_sheet', '2026-01-01', '2026-12-31')
    WHERE line_code = 'BS-A-NON'),
  3600.00::numeric(18,2),
  're-mapping inventory moves it to non-current assets with no code change');       -- 24

SELECT is(
  (SELECT closing_amount FROM fn_financial_statement_report(
     '12100000-0000-0000-0000-0000000000c1', 'balance_sheet', '2026-01-01', '2026-12-31')
    WHERE line_code = 'BS-A'),
  8080.00::numeric(18,2),
  'and total assets are unchanged — presentation moved, the ledger did not');       -- 25

SELECT * FROM finish();
ROLLBACK;
