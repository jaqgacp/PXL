-- ══════════════════════════════════════════════════════════════════════════════
-- 132 — Cash Sale void atomicity (PXL-AUD-076)
--
-- WHAT THIS GUARDS
--   A Cash Sale is ONE business event recorded as TWO documents: the sales
--   document (CS series) and the Official Receipt that collects it.
--   `fn_save_cash_sale` creates both in one act.
--
--   Voiding used to withdraw only the invoice half. Revenue, output VAT, COGS
--   and inventory all reversed correctly, and the receipt's `DR Cash / CR AR`
--   journal stayed posted — leaving cash OVERSTATED by the full sale and a
--   phantom credit sitting in Accounts Receivable for a customer who owes
--   nothing. The journal still balanced, so the trial balance could not see it.
--
--   This file asserts the whole event withdraws or none of it does: both
--   documents reach their terminal state, and every account the sale touched
--   returns to exactly where it was before the sale existed.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHY THE DELTA ASSERTIONS ARE ABSOLUTE HERE
--   The company is provisioned for this file alone and posts exactly one cash
--   sale, so "returns to the pre-sale position" and "nets to zero" are the same
--   statement. Assertions 8–13 are written as zero so a reader can see the
--   claim without reconstructing arithmetic.
--
-- WHAT THIS DOES NOT CLAIM
--   Nothing about percentage tax: this company is VAT-registered, and the
--   percentage-tax reversal path shares the same tax-ledger reversal
--   (`fn_reverse_tax_detail_entries`) already proven by tests `048` and `124`.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── The routing that makes the general Sales Invoice surface safe ─────────────
SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'fn_void_sales_invoice')
    LIKE '%fn_void_cash_sale%',
  'the Sales Invoice void routes a cash sale into the governed cash-sale path'
);                                                                                  -- 1

SELECT ok(
  NOT has_function_privilege('authenticated', 'public.fn_reverse_receipt_core(uuid,text,text)', 'EXECUTE'),
  'the receipt-reversal core is private — reachable only through a named business act'
);                                                                                  -- 2

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '13200000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'cs-void@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13200000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000c1', 'corporation', 'Counter Sale Corp',
        'Retail', '400-000-132-00000', 'vat', 'calendar',
        'C St', 'C Bldg', 'Makati', 'Metro Manila', '1200',
        'cs-void@test.local', 'C Owner', 'President',
        '13200000-0000-0000-0000-000000000001', '13200000-0000-0000-0000-000000000001');

-- `trg_company_creator_owner` grants the creator its membership; a second
-- explicit insert would collide with it.

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000d1', '13200000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'C St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('13200000-0000-0000-0000-0000000000f1', '13200000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '13200000-0000-0000-0000-0000000000c1', '13200000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('13200000-0000-0000-0000-00000000a001', '13200000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',         'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13200000-0000-0000-0000-00000000a002', '13200000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable',  'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13200000-0000-0000-0000-00000000a004', '13200000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory','asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13200000-0000-0000-0000-00000000a005', '13200000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',   'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('13200000-0000-0000-0000-00000000a006', '13200000-0000-0000-0000-0000000000c1', '4010', 'Merchandise Sales',    'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('13200000-0000-0000-0000-00000000a008', '13200000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold',   'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('13200000-0000-0000-0000-00000000a009', '13200000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, inventory_account_id, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000c1',
        '13200000-0000-0000-0000-00000000a002', '13200000-0000-0000-0000-00000000a005',
        '13200000-0000-0000-0000-00000000a001', '13200000-0000-0000-0000-00000000a004',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '13200000-0000-0000-0000-0000000000c1', '13200000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-132-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('SI', 'CS', 'OR', 'CM');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000e1', '13200000-0000-0000-0000-0000000000c1',
        'CUST-132', 'Walk-in Buyer Inc', '444-555-666-132',
        'Makati', 'Makati', auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000ab', '13200000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000ca', '13200000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_sales_vat_id,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000bb', '13200000-0000-0000-0000-0000000000c1',
        'GOODS-132', 'Counter Merchandise', 'inventory_item',
        '13200000-0000-0000-0000-0000000000ca', '13200000-0000-0000-0000-0000000000ab',
        1000, 600, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
        '13200000-0000-0000-0000-00000000a006', '13200000-0000-0000-0000-00000000a008',
        '13200000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('13200000-0000-0000-0000-0000000000ba', '13200000-0000-0000-0000-0000000000c1',
        '13200000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
        '13200000-0000-0000-0000-00000000a004', '13200000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('13200000-0000-0000-0000-0000000000c1', '13200000-0000-0000-0000-0000000000ba',
        '13200000-0000-0000-0000-0000000000bb', 20, 12000, 600);

CREATE TEMP TABLE t_cs (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1 — A counter sale: five units, collected on the spot.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_cs
SELECT 'si', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id','13200000-0000-0000-0000-0000000000c1',
    'branch_id','13200000-0000-0000-0000-0000000000d1',
    'date','2026-03-05',
    'customer_id','13200000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot','Walk-in Buyer Inc',
    'customer_tin_snapshot','444-555-666-132'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13200000-0000-0000-0000-0000000000bb',
    'description','Counter Merchandise', 'quantity',5, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','13200000-0000-0000-0000-00000000a006',
    'warehouse_id','13200000-0000-0000-0000-0000000000ba')),
  0) ->> 'si_id')::uuid;

INSERT INTO t_cs
SELECT 'or', id FROM receipts WHERE company_id = '13200000-0000-0000-0000-0000000000c1';

SELECT is((SELECT count(*)::int FROM receipts WHERE company_id = '13200000-0000-0000-0000-0000000000c1'),
  1, 'the cash sale created its Official Receipt half');                            -- 3

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13200000-0000-0000-0000-0000000000bb'),
  15::numeric, 'stock fell from 20 to 15');                                         -- 4

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13200000-0000-0000-0000-00000000a001'),
  5600.00::numeric, 'cash was collected — 5,600.00 on hand');                       -- 5

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2 — Void it through the GENERAL Sales Invoice entry point.
--          This is the path the Sales Invoice list actually uses.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok(format(
  'SELECT fn_void_sales_invoice(%L, %L, %L)',
  (SELECT id FROM t_cs WHERE key = 'si'),
  (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'),
  'wrong item rung up'),
  'the cash sale voids through the general Sales Invoice entry point');             -- 6

-- ── Both documents reach their terminal state ────────────────────────────────
SELECT is((SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_cs WHERE key='si')),
  'cancelled', 'the cash sale document is cancelled');                              -- 7

SELECT is((SELECT status FROM receipts WHERE id = (SELECT id FROM t_cs WHERE key='or')),
  'cancelled', 'and its Official Receipt is cancelled with it — not left posted');  -- 8

-- ── Every account the sale touched is back where it started ──────────────────
SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13200000-0000-0000-0000-00000000a001'),
  0.00::numeric, 'CASH returns to zero — the defect this file exists for');         -- 9

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13200000-0000-0000-0000-00000000a002'),
  0.00::numeric, 'the AR bridge the cash-sale structure creates is fully cleared'); -- 10

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13200000-0000-0000-0000-00000000a006'),
  0.00::numeric, 'revenue returns to zero');                                        -- 11

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13200000-0000-0000-0000-00000000a005'),
  0.00::numeric, 'output VAT returns to zero');                                     -- 12

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13200000-0000-0000-0000-00000000a008'),
  0.00::numeric, 'COGS returns to zero');                                           -- 13

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13200000-0000-0000-0000-0000000000bb'),
  20::numeric, 'inventory is restored to the pre-sale position');                   -- 14

SELECT is((SELECT total_cost FROM stock_balances
            WHERE item_id = '13200000-0000-0000-0000-0000000000bb'),
  12000.00::numeric, 'at the governed original cost');                              -- 15

-- ── The tax ledger nets out, and the books still balance ─────────────────────
SELECT is(
  (SELECT COALESCE(SUM(tax_amount), 0) FROM tax_detail_entries
    WHERE company_id = '13200000-0000-0000-0000-0000000000c1'),
  0.00::numeric, 'the tax ledger nets to zero for the whole event');                -- 16

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount) - SUM(jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13200000-0000-0000-0000-0000000000c1'),
  0.00::numeric, 'the trial balance remains balanced');                             -- 17

-- ── Repeating the void cannot reverse a half twice ───────────────────────────
SELECT throws_ok(format(
  'SELECT fn_void_sales_invoice(%L, %L, %L)',
  (SELECT id FROM t_cs WHERE key = 'si'),
  (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'),
  'second attempt'),
  NULL, NULL,
  'voiding the same cash sale twice is refused — no half reverses twice');          -- 18

SELECT * FROM finish();
ROLLBACK;
