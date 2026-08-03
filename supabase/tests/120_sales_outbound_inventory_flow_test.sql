-- ══════════════════════════════════════════════════════════════════════════════
-- 120 — Sales outbound inventory flow: Delivery Receipt → Sales Invoice → Return
--
-- WHAT THIS GUARDS
--   The two remaining ways stock could move without the ledger noticing.
--
--   A **Delivery Receipt** shipped goods and relieved nothing: the stock stayed
--   on the books at full cost until somebody invoiced it, so a count taken
--   between shipping and billing disagreed with the ledger and no account
--   explained the difference. A **Customer Return** credited the customer and
--   returned no stock, so gross margin stayed overstated by the cost of every
--   return ever processed.
--
--   This file walks the whole outbound act on a company it provisions itself:
--   deliver five units, bill the delivery, then take two back. It asserts that
--   cost leaves inventory exactly once — at delivery — reaches COGS exactly when
--   the revenue does, and comes back when the goods do. The clearing account
--   that holds it in between must net to zero once the invoice posts.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Financial statement presentation: `account_fs_map` still holds no row, so
--   "→ TB → FS" in the Delivery Plan's Sales flow is not proven here.
--   Quotation and Sales Order conversion: the Document Conversion engine is not
--   started; this file links the invoice to the delivery through the governed
--   `source_document_type` / `source_line_id` columns, which is what the
--   clearing consumption actually keys on.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'outbound-flow@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000c1', 'corporation', 'Outbound Flow Trading Corp',
        'Wholesale trading', '400-000-001-00000', 'vat', 'calendar',
        'O St', 'O Bldg', 'Makati', 'Metro Manila', '1200',
        'outbound-flow@test.local', 'O Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000d1', '12000000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'O St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12000000-0000-0000-0000-0000000000f1', '12000000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12000000-0000-0000-0000-0000000000c1', '12000000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12000000-0000-0000-0000-00000000a001', '12000000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a002', '12000000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a004', '12000000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory','asset',    'debit',  true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a010', '12000000-0000-0000-0000-0000000000c1', '1310', 'Goods Delivered Not Invoiced', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a005', '12000000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a006', '12000000-0000-0000-0000-0000000000c1', '4010', 'Merchandise Sales',   'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a008', '12000000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold',  'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('12000000-0000-0000-0000-00000000a009', '12000000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance',  'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, inventory_account_id, sales_delivery_clearing_account_id,
        created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000c1',
        '12000000-0000-0000-0000-00000000a002', '12000000-0000-0000-0000-00000000a005',
        '12000000-0000-0000-0000-00000000a001', '12000000-0000-0000-0000-00000000a004',
        '12000000-0000-0000-0000-00000000a010',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12000000-0000-0000-0000-0000000000c1', '12000000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-120-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('SI', 'DR', 'CM', 'OR');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000e1', '12000000-0000-0000-0000-0000000000c1',
        'CUST-120', 'Wholesale Buyer Inc', '444-555-666-120',
        'Pasig', 'Pasig', auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000ab', '12000000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000ca', '12000000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_sales_vat_id,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000bb', '12000000-0000-0000-0000-0000000000c1',
        'GOODS-120', 'Traded Merchandise', 'inventory_item',
        '12000000-0000-0000-0000-0000000000ca', '12000000-0000-0000-0000-0000000000ab',
        1000, 600, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
        '12000000-0000-0000-0000-00000000a006', '12000000-0000-0000-0000-00000000a008',
        '12000000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('12000000-0000-0000-0000-0000000000ba', '12000000-0000-0000-0000-0000000000c1',
        '12000000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
        '12000000-0000-0000-0000-00000000a004', '12000000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('12000000-0000-0000-0000-0000000000c1', '12000000-0000-0000-0000-0000000000ba',
        '12000000-0000-0000-0000-0000000000bb', 20, 12000, 600);

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1 — Deliver five units. Stock leaves; the sale is not yet recognised.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO delivery_receipts (id, company_id, branch_id, customer_id,
                               customer_name_snapshot, dr_number, dr_date,
                               delivery_address, status, delivered_at,
                               created_by, updated_by)
VALUES ('12000000-0000-0000-0000-00000000d100', '12000000-0000-0000-0000-0000000000c1',
        '12000000-0000-0000-0000-0000000000d1', '12000000-0000-0000-0000-0000000000e1',
        'Wholesale Buyer Inc', 'DR-120-000001', '2026-03-05',
        'Pasig', 'delivered', NOW(), auth.uid(), auth.uid());

INSERT INTO delivery_receipt_lines (id, dr_id, company_id, line_number, item_id,
                                    description, quantity, uom_id, warehouse_id,
                                    created_by, updated_by)
VALUES ('12000000-0000-0000-0000-00000000d101', '12000000-0000-0000-0000-00000000d100',
        '12000000-0000-0000-0000-0000000000c1', 1, '12000000-0000-0000-0000-0000000000bb',
        'Traded Merchandise', 5, '12000000-0000-0000-0000-0000000000ab',
        '12000000-0000-0000-0000-0000000000ba', auth.uid(), auth.uid());

SELECT lives_ok(
  $$SELECT fn_post_delivery_receipt('12000000-0000-0000-0000-00000000d100')$$,
  'a delivered delivery receipt posts');                                            -- 1

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '12000000-0000-0000-0000-0000000000ba'
      AND item_id = '12000000-0000-0000-0000-0000000000bb'),
  15::numeric, 'delivery relieved 5 units — stock fell from 20 to 15');             -- 2

SELECT is(
  (SELECT total_cost FROM stock_balances
    WHERE warehouse_id = '12000000-0000-0000-0000-0000000000ba'
      AND item_id = '12000000-0000-0000-0000-0000000000bb'),
  9000.00::numeric, 'and stock value fell by the 3,000 shipped');                   -- 3

SELECT results_eq(
  $q$SELECT it.transaction_type, it.qty, it.total_cost, it.reference_doc_type
       FROM inventory_transactions it
      WHERE it.reference_doc_id = '12000000-0000-0000-0000-00000000d100'$q$,
  $$VALUES ('issue'::text, -5::numeric, -3000.00::numeric, 'DR'::text)$$,
  'the delivery wrote one inventory issue transaction against the DR');             -- 4

SELECT results_eq(
  $q$SELECT jel.account_id, jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel
       JOIN delivery_receipts dr ON dr.journal_entry_id = jel.je_id
      WHERE dr.id = '12000000-0000-0000-0000-00000000d100'
      ORDER BY jel.line_number$q$,
  $$VALUES ('12000000-0000-0000-0000-00000000a010'::uuid, 3000.00::numeric, 0.00::numeric),
           ('12000000-0000-0000-0000-00000000a004'::uuid, 0.00::numeric, 3000.00::numeric)$$,
  'the delivery journal is DR Goods Delivered Not Invoiced / CR Inventory');        -- 5

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines jel
    JOIN delivery_receipts dr ON dr.journal_entry_id = jel.je_id
    WHERE dr.id = '12000000-0000-0000-0000-00000000d100'
      AND jel.account_id = '12000000-0000-0000-0000-00000000a008'),
  0, 'no COGS is recognised at delivery — the sale has not happened yet');          -- 6

SELECT lives_ok(
  $$SELECT fn_post_delivery_receipt('12000000-0000-0000-0000-00000000d100')$$,
  'posting the same delivery twice is a no-op, not a second relief');               -- 7

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '12000000-0000-0000-0000-0000000000ba'
      AND item_id = '12000000-0000-0000-0000-0000000000bb'),
  15::numeric, 'and stock is still 15 after the repeat call');                      -- 8

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2 — Bill the delivery. Revenue is recognised; the cost moves from the
-- clearing account to COGS. Stock must NOT move again.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',             '12000000-0000-0000-0000-0000000000c1',
    'branch_id',              '12000000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-06',
    'customer_id',            '12000000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Wholesale Buyer Inc',
    'customer_tin_snapshot',  '444-555-666-120',
    'customer_address_snapshot', 'Pasig',
    'warehouse_id',           '12000000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',              '12000000-0000-0000-0000-0000000000bb',
    'description',          'Traded Merchandise',
    'quantity',             5,
    'unit_price',           1000,
    'vat_code_id',          (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id',   '12000000-0000-0000-0000-00000000a006',
    'warehouse_id',         '12000000-0000-0000-0000-0000000000ba',
    'source_document_type', 'DR',
    'source_line_id',       '12000000-0000-0000-0000-00000000d101'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '12000000-0000-0000-0000-0000000000ba'
      AND item_id = '12000000-0000-0000-0000-0000000000bb'),
  15::numeric,
  'billing the delivery moved NO stock — it left at delivery, and only once');      -- 9

SELECT is(
  (SELECT count(*)::int FROM inventory_transactions
    WHERE reference_doc_id = (SELECT id FROM t_ctx WHERE key='si')),
  0, 'and the invoice wrote no inventory transaction of its own');                  -- 10

SELECT is(
  (SELECT SUM(jel.debit_amount) FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si'))
      AND jel.account_id = '12000000-0000-0000-0000-00000000a008'),
  3000.00::numeric, 'the invoice recognises the 3,000 of COGS');                    -- 11

SELECT is(
  (SELECT SUM(jel.credit_amount) FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si'))
      AND jel.account_id = '12000000-0000-0000-0000-00000000a010'),
  3000.00::numeric, 'by clearing Goods Delivered Not Invoiced, not by touching stock'); -- 12

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel
    WHERE jel.company_id = '12000000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '12000000-0000-0000-0000-00000000a010'),
  0.00::numeric, 'Goods Delivered Not Invoiced nets to zero once the delivery is billed'); -- 13

SELECT results_eq(
  $q$SELECT total_taxable_amount, total_vat_amount, total_amount
       FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  $$VALUES (5000.00::numeric, 600.00::numeric, 5600.00::numeric)$$,
  'the invoice bills 5,000 net + 600 output VAT');                                  -- 14

SELECT is(
  (SELECT tde.tax_amount FROM tax_detail_entries tde
    WHERE tde.source_doc_id = (SELECT id FROM t_ctx WHERE key='si')
      AND tde.tax_kind = 'output_vat'),
  600.00::numeric, 'and the output VAT reaches the tax ledger');                    -- 15

-- The same delivery line cannot be billed a second time.
SELECT throws_like(
  format($q$SELECT fn_save_sales_invoice(NULL,
    jsonb_build_object(
      'company_id','12000000-0000-0000-0000-0000000000c1',
      'branch_id','12000000-0000-0000-0000-0000000000d1',
      'date','2026-03-07',
      'customer_id','12000000-0000-0000-0000-0000000000e1',
      'customer_name_snapshot','Wholesale Buyer Inc',
      'customer_address_snapshot','Pasig'),
    jsonb_build_array(jsonb_build_object(
      'item_id','12000000-0000-0000-0000-0000000000bb',
      'description','Traded Merchandise','quantity',5,'unit_price',1000,
      'vat_code_id',%L,
      'revenue_account_id','12000000-0000-0000-0000-00000000a006',
      'warehouse_id','12000000-0000-0000-0000-0000000000ba',
      'source_document_type','DR',
      'source_line_id','12000000-0000-0000-0000-00000000d101')))$q$,
    (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')),
  '%uq_sil_delivery_source%',
  'a delivery line cannot be billed twice');                                        -- 16

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 3 — The customer returns two units. Stock and cost both come back.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id',             '12000000-0000-0000-0000-0000000000c1',
    'branch_id',              '12000000-0000-0000-0000-0000000000d1',
    'customer_id',            '12000000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Wholesale Buyer Inc',
    'customer_tin_snapshot',  '444-555-666-120',
    'cm_date',                '2026-03-10',
    'reason_code_id',         (SELECT id FROM ref_reason_codes
                                WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1)::text,
    'warehouse_id',           '12000000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',            '12000000-0000-0000-0000-0000000000bb',
    'description',        'Traded Merchandise returned',
    'quantity',           2,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', '12000000-0000-0000-0000-00000000a006',
    'invoice_line_id',    (SELECT id FROM sales_invoice_lines
                            WHERE sales_invoice_id = (SELECT id FROM t_ctx WHERE key='si'))::text
  )),
  'draft');

SELECT fn_post_credit_memo((SELECT id FROM t_ctx WHERE key='cm'));

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '12000000-0000-0000-0000-0000000000ba'
      AND item_id = '12000000-0000-0000-0000-0000000000bb'),
  17::numeric, 'the return put 2 units back on hand — 15 to 17');                   -- 17

SELECT is(
  (SELECT total_cost FROM stock_balances
    WHERE warehouse_id = '12000000-0000-0000-0000-0000000000ba'
      AND item_id = '12000000-0000-0000-0000-0000000000bb'),
  10200.00::numeric, 'at the 600 per unit they were issued at, not a guessed cost'); -- 18

SELECT results_eq(
  $q$SELECT it.transaction_type, it.qty, it.unit_cost, it.reference_doc_type
       FROM inventory_transactions it
      WHERE it.reference_doc_id = (SELECT id FROM t_ctx WHERE key='cm')$q$,
  $$VALUES ('receipt'::text, 2::numeric, 600.000000::numeric, 'CM'::text)$$,
  'the return wrote a receipt transaction through the shared inbound path');        -- 19

SELECT is(
  (SELECT SUM(jel.credit_amount) FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM credit_memos WHERE id = (SELECT id FROM t_ctx WHERE key='cm'))
      AND jel.account_id = '12000000-0000-0000-0000-00000000a008'),
  1200.00::numeric, 'the credit memo reverses 1,200 of COGS');                      -- 20

SELECT is(
  (SELECT SUM(jel.debit_amount) FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT journal_entry_id FROM credit_memos WHERE id = (SELECT id FROM t_ctx WHERE key='cm'))
      AND jel.account_id = '12000000-0000-0000-0000-00000000a004'),
  1200.00::numeric, 'and puts the same 1,200 back into inventory');                 -- 21

SELECT is(
  (SELECT tde.tax_amount FROM tax_detail_entries tde
    WHERE tde.source_doc_id = (SELECT id FROM t_ctx WHERE key='cm')
      AND tde.tax_kind = 'output_vat'),
  -240.00::numeric, 'the return reverses 240 of output VAT in the tax ledger');     -- 22

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 4 — The whole flow reconciles
--
-- Opening stock 12,000 was loaded straight into stock_balances and never
-- journalised, so the claim is about the MOVEMENT: every peso that left or
-- re-entered stock is a peso the inventory control account moved by.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (12000.00 - (SELECT COALESCE(SUM(sb.total_cost), 0) FROM stock_balances sb
                WHERE sb.company_id = '12000000-0000-0000-0000-0000000000c1'))
  + (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
       FROM journal_entry_lines jel
      WHERE jel.company_id = '12000000-0000-0000-0000-0000000000c1'
        AND jel.account_id = '12000000-0000-0000-0000-00000000a004'),
  0.00::numeric,
  'inventory-to-control reconciles across delivery, invoice and return');           -- 23

-- Net COGS is the cost of the 3 units the customer kept.
SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel
    WHERE jel.company_id = '12000000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '12000000-0000-0000-0000-00000000a008'),
  1800.00::numeric,
  'net COGS is 1,800 — the three units the customer kept, at 600 each');            -- 24

SELECT * FROM finish();
ROLLBACK;
