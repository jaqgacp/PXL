-- ══════════════════════════════════════════════════════════════════════════════
-- 119 — Cash Sale posting (Delivery Plan Phase 5 item 3)
--
-- WHAT THIS GUARDS
--   Cash Sale is the counter-sale path a retail pilot actually uses, and until
--   now it sold inventory without relieving it: revenue and output VAT posted,
--   the stock stayed on the books, and no `inventory_transactions` row existed.
--   Sales Invoice had done all three since PXL-AUD-053.
--
--   This file proves the closed capability from first principles on a company it
--   provisions itself through the current production RPC. It asserts the whole
--   business act, not a fragment: a walk-in sale of goods AND services, priced
--   VAT-inclusive, withheld under TWO different ATCs on the same document, that
--   relieves stock, posts COGS, balances, and leaves a tax ledger a 2307 could
--   be assembled from.
--
--   It never reads the canonical/demo seed, which was produced by the very logic
--   under test (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Percentage tax. A PT-registered company still computes no percentage tax on
--   a cash sale, because the PT liability posting line and the 2551Q artifact do
--   not exist and the chain ships whole or not at all.
--   Cash Sale remains save-and-post in one act; this file does not claim a
--   separate approval lifecycle it does not have.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(26);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11900000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'cash-sale-posting@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"11900000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000c1', 'corporation', 'Counter Sale Corp',
        'Retail and services', '399-000-001-00000', 'vat', 'calendar',
        'C St', 'C Bldg', 'Makati', 'Metro Manila', '1200',
        'cash-sale-posting@test.local', 'C Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000d1', '11900000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'C St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('11900000-0000-0000-0000-0000000000f1', '11900000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '11900000-0000-0000-0000-0000000000c1', '11900000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('11900000-0000-0000-0000-00000000a001', '11900000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',       'asset',         'debit',  true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a002', '11900000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable','asset',         'debit',  true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a003', '11900000-0000-0000-0000-0000000000c1', '1250', 'CWT Receivable',     'asset',         'debit',  true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a004', '11900000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory','asset',       'debit',  true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a005', '11900000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable', 'liability',     'credit', true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a006', '11900000-0000-0000-0000-0000000000c1', '4010', 'Merchandise Sales',  'revenue',       'credit', true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a007', '11900000-0000-0000-0000-0000000000c1', '4020', 'Service Revenue',    'revenue',       'credit', true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a008', '11900000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold', 'expense',       'debit',  true, true, auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-00000000a009', '11900000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance', 'expense',       'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        ewt_withheld_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000c1',
        '11900000-0000-0000-0000-00000000a002', '11900000-0000-0000-0000-00000000a005',
        '11900000-0000-0000-0000-00000000a003', '11900000-0000-0000-0000-00000000a001',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '11900000-0000-0000-0000-0000000000c1', '11900000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-119-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000e1', '11900000-0000-0000-0000-0000000000c1',
        'CUST-119', 'Top Withholding Agent Inc', '444-555-666-119',
        'Taguig', 'Taguig', auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000ab', '11900000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000ca', '11900000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_sales_vat_id,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES
  ('11900000-0000-0000-0000-0000000000bb', '11900000-0000-0000-0000-0000000000c1',
   'GOODS-119', 'Stocked Merchandise', 'inventory_item',
   '11900000-0000-0000-0000-0000000000ca', '11900000-0000-0000-0000-0000000000ab',
   1120, 600, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
   '11900000-0000-0000-0000-00000000a006', '11900000-0000-0000-0000-00000000a008',
   '11900000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid()),
  ('11900000-0000-0000-0000-0000000000bc', '11900000-0000-0000-0000-0000000000c1',
   'SVC-119', 'Installation Service', 'service',
   '11900000-0000-0000-0000-0000000000ca', '11900000-0000-0000-0000-0000000000ab',
   560, 0, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
   '11900000-0000-0000-0000-00000000a007', NULL, NULL, 'weighted_average',
   auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('11900000-0000-0000-0000-0000000000ba', '11900000-0000-0000-0000-0000000000c1',
        '11900000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
        '11900000-0000-0000-0000-00000000a004', '11900000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('11900000-0000-0000-0000-0000000000c1', '11900000-0000-0000-0000-0000000000ba',
        '11900000-0000-0000-0000-0000000000bb', 10, 6000, 600);

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — One counter sale: goods and services, two ATCs, VAT-exclusive
--
-- Goods   4 x 1,000 = 4,000 net, withheld under WC158 (Top Withholding Agent,
--         goods) at 1%  =  40.00
-- Service 1 x 3,000 = 3,000 net, withheld under WC160 (TWA, services) at 2%
--                                                     =  60.00
-- Output VAT 12% on 7,000                             = 840.00
-- Gross 7,840.00; CWT 100.00; cash received 7,740.00
-- COGS  4 x 600 (weighted average)                    = 2,400.00
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'sale1', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '11900000-0000-0000-0000-0000000000c1',
    'branch_id',              '11900000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-05',
    'customer_id',            '11900000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Top Withholding Agent Inc',
    'customer_tin_snapshot',  '444-555-666-119',
    'warehouse_id',           '11900000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'item_id',                 '11900000-0000-0000-0000-0000000000bb',
      'description',             'Stocked Merchandise',
      'quantity',                4,
      'unit_price',              1000,
      'vat_code_id',             (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code = 'WC158' AND is_active)
    ),
    jsonb_build_object(
      'item_id',                 '11900000-0000-0000-0000-0000000000bc',
      'description',             'Installation Service',
      'quantity',                1,
      'unit_price',              3000,
      'vat_code_id',             (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code = 'WC160' AND is_active)
    )
  ),
  0)->>'si_id')::uuid;

INSERT INTO t_ctx
SELECT 'sale1_or', r.id FROM receipts r
JOIN receipt_lines rl ON rl.receipt_id = r.id
WHERE rl.invoice_id = (SELECT id FROM t_ctx WHERE key = 'sale1');

SELECT results_eq(
  $q$SELECT total_taxable_amount, total_vat_amount, total_amount
       FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'sale1')$q$,
  $$VALUES (7000.00::numeric, 840.00::numeric, 7840.00::numeric)$$,
  'the cash sale totals 7,000 net + 840 output VAT = 7,840');                       -- 1

-- ── The capability this file exists for: inventory actually moved ─────────────
SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '11900000-0000-0000-0000-0000000000ba'
      AND item_id = '11900000-0000-0000-0000-0000000000bb'),
  6::numeric, 'the cash sale relieved 4 units — stock fell from 10 to 6');          -- 2

SELECT is(
  (SELECT total_cost FROM stock_balances
    WHERE warehouse_id = '11900000-0000-0000-0000-0000000000ba'
      AND item_id = '11900000-0000-0000-0000-0000000000bb'),
  3600.00::numeric, 'stock value fell by the 2,400 issued at weighted-average cost'); -- 3

SELECT results_eq(
  $q$SELECT it.transaction_type, it.qty, it.unit_cost, it.total_cost, it.reference_doc_type
       FROM inventory_transactions it
      WHERE it.reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'sale1')$q$,
  $$VALUES ('issue'::text, -4::numeric, 600.000000::numeric, -2400.00::numeric, 'SI'::text)$$,
  'the cash sale wrote exactly one inventory issue transaction');                   -- 4

SELECT is(
  (SELECT it.journal_entry_id FROM inventory_transactions it
    WHERE it.reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'sale1')),
  (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'sale1')),
  'the issue transaction carries the journal it was posted with');                  -- 5

SELECT is(
  (SELECT sil.inventory_transaction_id FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = (SELECT id FROM t_ctx WHERE key = 'sale1')
      AND sil.item_id = '11900000-0000-0000-0000-0000000000bb'),
  (SELECT it.id FROM inventory_transactions it
    WHERE it.reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'sale1')),
  'the sold line points back at its inventory movement');                           -- 6

SELECT is(
  (SELECT sil.unit_cost FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = (SELECT id FROM t_ctx WHERE key = 'sale1')
      AND sil.item_id = '11900000-0000-0000-0000-0000000000bb'),
  600.000000::numeric, 'the line keeps the unit cost it was actually relieved at'); -- 7

-- ── The general ledger ───────────────────────────────────────────────────────
SELECT is(
  (SELECT SUM(jel.debit_amount) FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='sale1'))
      AND jel.account_id = '11900000-0000-0000-0000-00000000a008'),
  2400.00::numeric, 'the sales journal debits COGS 2,400');                         -- 8

SELECT is(
  (SELECT SUM(jel.credit_amount) FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='sale1'))
      AND jel.account_id = '11900000-0000-0000-0000-00000000a004'),
  2400.00::numeric, 'and credits inventory by the same 2,400');                     -- 9

SELECT results_eq(
  $q$SELECT SUM(jel.debit_amount), SUM(jel.credit_amount)
       FROM journal_entry_lines jel
      WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices
                          WHERE id = (SELECT id FROM t_ctx WHERE key='sale1'))$q$,
  $$VALUES (10240.00::numeric, 10240.00::numeric)$$,
  'the sales journal balances at 7,840 revenue+VAT plus 2,400 of cost');            -- 10

SELECT is(
  (SELECT total_debit FROM journal_entries
    WHERE id = (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='sale1'))),
  10240.00::numeric, 'the journal header total includes the cost lines');           -- 11

-- Two revenue accounts, because goods and services do not share one.
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='sale1'))
      AND jel.account_id IN ('11900000-0000-0000-0000-00000000a006','11900000-0000-0000-0000-00000000a007')),
  2, 'goods and service revenue post to their own accounts');                       -- 12

-- ── Withholding: per line, per ATC, all the way to the tax ledger ────────────
SELECT results_eq(
  $q$SELECT ac.code, sil.withholding_tax_base, sil.withholding_tax_rate, sil.withholding_tax_amount
       FROM sales_invoice_lines sil
       JOIN atc_codes ac ON ac.id = sil.withholding_atc_code_id
      WHERE sil.sales_invoice_id = (SELECT id FROM t_ctx WHERE key='sale1')
      ORDER BY sil.line_number$q$,
  $$VALUES ('WC158'::text, 4000.00::numeric, 1.0000::numeric, 40.00::numeric),
           ('WC160'::text, 3000.00::numeric, 2.0000::numeric, 60.00::numeric)$$,
  'each line carries its own ATC, its own base and the rate it was withheld at'); -- 13

SELECT results_eq(
  $q$SELECT ac.code, tde.tax_base, tde.tax_rate, tde.tax_amount
       FROM tax_detail_entries tde
       JOIN atc_codes ac ON ac.id = tde.atc_code_id
      WHERE tde.source_doc_id = (SELECT id FROM t_ctx WHERE key='sale1_or')
        AND tde.tax_kind = 'cwt_receivable'
      ORDER BY ac.code$q$,
  $$VALUES ('WC158'::text, 4000.00::numeric, 1.0000::numeric, 40.00::numeric),
           ('WC160'::text, 3000.00::numeric, 2.0000::numeric, 60.00::numeric)$$,
  'the tax ledger carries one CWT row per ATC — what a 2307 is assembled from'); -- 14

SELECT is(
  (SELECT total_cwt FROM receipts WHERE id = (SELECT id FROM t_ctx WHERE key='sale1_or')),
  100.00::numeric, 'the receipt settles the 100.00 total withheld across both ATCs'); -- 15

SELECT results_eq(
  $q$SELECT cwt_source, atc_code_id, cwt_amount FROM receipt_lines
      WHERE invoice_id = (SELECT id FROM t_ctx WHERE key='sale1')$q$,
  $$VALUES ('invoice_lines'::text, NULL::uuid, 100.00::numeric)$$,
  'the receipt line declares that its withholding detail lives on the invoice lines'); -- 16

SELECT is(
  (SELECT SUM(jel.debit_amount) FROM journal_entry_lines jel
    JOIN receipts r ON r.journal_entry_id = jel.je_id
    WHERE r.id = (SELECT id FROM t_ctx WHERE key='sale1_or')
      AND jel.account_id = '11900000-0000-0000-0000-00000000a001'),
  7740.00::numeric, 'cash received is the gross less the 100.00 withheld');         -- 17

SELECT is(
  (SELECT SUM(jel.debit_amount) FROM journal_entry_lines jel
    JOIN receipts r ON r.journal_entry_id = jel.je_id
    WHERE r.id = (SELECT id FROM t_ctx WHERE key='sale1_or')
      AND jel.account_id = '11900000-0000-0000-0000-00000000a003'),
  100.00::numeric, 'CWT receivable is debited for the whole withheld amount');      -- 18

-- ── Inventory-to-control reconciliation for this company ─────────────────────
-- The opening 6,000 was loaded straight into stock_balances and never journalised,
-- so the reconciling claim is about the MOVEMENT: every peso the sale took out of
-- stock is a peso it took out of the inventory control account.
SELECT is(
  (6000.00 - (SELECT COALESCE(SUM(sb.total_cost), 0) FROM stock_balances sb
               WHERE sb.company_id = '11900000-0000-0000-0000-0000000000c1'))
  + (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
       FROM journal_entry_lines jel
      WHERE jel.company_id = '11900000-0000-0000-0000-0000000000c1'
        AND jel.account_id = '11900000-0000-0000-0000-00000000a004'),
  0.00::numeric,
  'the stock relieved and the inventory control credited move by exactly the same amount'); -- 19

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — VAT-inclusive counter pricing
--
-- A walk-in price of 1,120.00 tax-inclusive is 1,000.00 net + 120.00 VAT. Before
-- this work Cash Sale could not price inclusively at all: it asked the engine
-- without a price basis and always got the exclusive answer.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'sale2', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '11900000-0000-0000-0000-0000000000c1',
    'branch_id',              '11900000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-06',
    'customer_id',            '11900000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Top Withholding Agent Inc',
    'customer_tin_snapshot',  '444-555-666-119',
    'vat_price_basis',        'inclusive',
    'warehouse_id',           '11900000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',     '11900000-0000-0000-0000-0000000000bb',
    'description', 'Stocked Merchandise',
    'quantity',    1,
    'unit_price',  1120,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
  )),
  0)->>'si_id')::uuid;

SELECT results_eq(
  $q$SELECT vat_price_basis, total_taxable_amount, total_vat_amount, total_amount
       FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='sale2')$q$,
  $$VALUES ('inclusive'::text, 1000.00::numeric, 120.00::numeric, 1120.00::numeric)$$,
  'a 1,120 tax-inclusive counter price backs out to 1,000 net + 120 VAT');          -- 20

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '11900000-0000-0000-0000-0000000000ba'
      AND item_id = '11900000-0000-0000-0000-0000000000bb'),
  5::numeric, 'the inclusive-priced sale relieved its unit too');                   -- 21

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — The document-level convention still works, and the edges fail closed
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'sale3', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '11900000-0000-0000-0000-0000000000c1',
    'branch_id',              '11900000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-07',
    'customer_id',            '11900000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Top Withholding Agent Inc',
    'customer_tin_snapshot',  '444-555-666-119',
    'cwt_atc_id',             (SELECT id FROM atc_codes WHERE code = 'WC140' AND is_active)::text
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Over-the-counter service',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', '11900000-0000-0000-0000-00000000a007'
  )),
  200)->>'si_id')::uuid;

SELECT results_eq(
  $q$SELECT rl.cwt_source, rl.cwt_amount, rl.cwt_tax_base
       FROM receipt_lines rl
      WHERE rl.invoice_id = (SELECT id FROM t_ctx WHERE key='sale3')$q$,
  $$VALUES ('atc'::text, 200.00::numeric, 10000.00::numeric)$$,
  'a document-level ATC still withholds on the VAT-exclusive base, unchanged');     -- 22

SELECT throws_like(
  $$SELECT fn_save_cash_sale(
      jsonb_build_object(
        'company_id','11900000-0000-0000-0000-0000000000c1',
        'branch_id','11900000-0000-0000-0000-0000000000d1',
        'date','2026-03-08',
        'customer_id','11900000-0000-0000-0000-0000000000e1',
        'customer_name_snapshot','Top Withholding Agent Inc',
        'cwt_atc_id',(SELECT id FROM atc_codes WHERE code='WC140' AND is_active)::text),
      jsonb_build_array(jsonb_build_object(
        'description','Mixed conventions', 'quantity',1, 'unit_price',1000,
        'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
        'revenue_account_id','11900000-0000-0000-0000-00000000a007',
        'withholding_atc_code_id',(SELECT id FROM atc_codes WHERE code='WC158' AND is_active))),
      0)$$,
  '%must not also carry a document-level ATC%',
  'a document cannot withhold per line and per document at the same time');         -- 23

SELECT throws_like(
  $$SELECT fn_save_cash_sale(
      jsonb_build_object(
        'company_id','11900000-0000-0000-0000-0000000000c1',
        'branch_id','11900000-0000-0000-0000-0000000000d1',
        'date','2026-03-08',
        'customer_id','11900000-0000-0000-0000-0000000000e1',
        'customer_name_snapshot','Top Withholding Agent Inc',
        'warehouse_id','11900000-0000-0000-0000-0000000000ba'),
      jsonb_build_array(jsonb_build_object(
        'item_id','11900000-0000-0000-0000-0000000000bb',
        'description','Stocked Merchandise', 'quantity',99, 'unit_price',1000,
        'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'))),
      0)$$,
  '%Insufficient stock%',
  'a counter sale cannot sell stock the warehouse does not hold');                  -- 24

SELECT throws_like(
  $$SELECT fn_save_cash_sale(
      jsonb_build_object(
        'company_id','11900000-0000-0000-0000-0000000000c1',
        'branch_id','11900000-0000-0000-0000-0000000000d1',
        'date','2026-03-08',
        'customer_id','11900000-0000-0000-0000-0000000000e1',
        'customer_name_snapshot','Top Withholding Agent Inc'),
      jsonb_build_array(jsonb_build_object(
        'item_id','11900000-0000-0000-0000-0000000000bb',
        'description','Stocked Merchandise', 'quantity',1, 'unit_price',1000,
        'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'))),
      0)$$,
  '%Warehouse is required for inventory item line%',
  'an inventory line with no warehouse is refused rather than sold from nowhere');  -- 25

-- The engine still governs the ATC version on the document date: a withholding
-- code outside its effective window does not resolve, and the line is refused
-- rather than silently withheld at nothing.
UPDATE atc_codes SET effective_to = '2026-02-28'
WHERE code = 'WC158' AND effective_to IS NULL;

SELECT throws_like(
  $$SELECT fn_save_cash_sale(
      jsonb_build_object(
        'company_id','11900000-0000-0000-0000-0000000000c1',
        'branch_id','11900000-0000-0000-0000-0000000000d1',
        'date','2026-03-09',
        'customer_id','11900000-0000-0000-0000-0000000000e1',
        'customer_name_snapshot','Top Withholding Agent Inc'),
      jsonb_build_array(jsonb_build_object(
        'description','Expired withholding code', 'quantity',1, 'unit_price',1000,
        'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
        'revenue_account_id','11900000-0000-0000-0000-00000000a007',
        'withholding_atc_code_id',(SELECT id FROM atc_codes WHERE code='WC158' AND effective_to='2026-02-28'))),
      0)$$,
  '%withholding tax code is inactive, deprecated, or not effective on 2026-03-09%',
  'a line withholding code outside its effective window is refused');               -- 26

SELECT * FROM finish();
ROLLBACK;
