-- ══════════════════════════════════════════════════════════════════════════════
-- 133 — A hand-typed invoice may not relieve delivered stock twice (Backlog 18b)
--
-- WHAT THIS GUARDS
--   `fn_post_sales_invoice` decides how to treat a stockable line by asking
--   whether it carries `source_document_type = 'DR'` and a costed
--   `source_line_id`. If it does, the cost already left inventory at delivery
--   and the invoice only clears Goods Delivered Not Invoiced. If it does not,
--   the invoice relieves the stock itself.
--
--   Nothing checked whether the goods on an UNLINKED line had already been
--   delivered. "Bill This Delivery" is the only path that creates the link, so
--   an invoice typed on the Sales Invoice screen for goods a delivery already
--   shipped took the second branch and relieved the stock a SECOND time.
--
--   It is silent: stock and the ledger move together on that second relief, so
--   the inventory-to-control reconciliation still ties at ₱0.00. What survives
--   is a Goods Delivered Not Invoiced balance that never clears, because the
--   delivery that created it was never billed against.
--
--   This file proves the guard refuses that invoice, names the delivery to bill
--   instead, and refuses nothing else.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Document Conversion (Delivery Plan Phase 5 item 5) is not built. The guard
--   refuses the unsafe act; it does not create the link. Nor does it match
--   quantity or price — a delivered-but-unbilled line for the same item is
--   enough to make a hand-typed invoice unsafe, and quantity matching belongs
--   with three-way match.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── The guard sits where BOTH approval and posting pass through ──────────────
SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'fn_validate_sales_invoice_accounting_ready')
    LIKE '%fn_assert_no_unlinked_delivered_stock%',
  'the readiness validator carries the delivered-stock guard'
);                                                                                  -- 1

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'fn_approve_sales_invoice')
    LIKE '%fn_validate_sales_invoice_accounting_ready%'
  AND (SELECT prosrc FROM pg_proc WHERE proname = 'fn_post_sales_invoice')
    LIKE '%fn_validate_sales_invoice_accounting_ready%',
  'so it gates approval as well as posting — the user is stopped early'
);                                                                                  -- 2

SELECT ok(
  NOT has_function_privilege('anon',
    'public.fn_validate_sales_invoice_accounting_ready(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon',
    'public.fn_assert_no_unlinked_delivered_stock(uuid)', 'EXECUTE'),
  'the SECURITY DEFINER validator and its relationship helper are not anonymous probes'
);                                                                                  -- 3

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '13300000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'dr-guard@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13300000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000c1', 'corporation', 'Double Relief Corp',
        'Wholesale', '400-000-133-00000', 'vat', 'calendar',
        'D St', 'D Bldg', 'Makati', 'Metro Manila', '1200',
        'dr-guard@test.local', 'D Owner', 'President',
        '13300000-0000-0000-0000-000000000001', '13300000-0000-0000-0000-000000000001');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000d1', '13300000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'D St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('13300000-0000-0000-0000-0000000000f1', '13300000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '13300000-0000-0000-0000-0000000000c1', '13300000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('13300000-0000-0000-0000-00000000a001', '13300000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',         'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a002', '13300000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable',  'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a004', '13300000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory','asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a010', '13300000-0000-0000-0000-0000000000c1', '1310', 'Goods Delivered Not Invoiced', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a005', '13300000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',   'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a006', '13300000-0000-0000-0000-0000000000c1', '4010', 'Merchandise Sales',    'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a008', '13300000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold',   'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('13300000-0000-0000-0000-00000000a009', '13300000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, inventory_account_id, sales_delivery_clearing_account_id,
        created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000c1',
        '13300000-0000-0000-0000-00000000a002', '13300000-0000-0000-0000-00000000a005',
        '13300000-0000-0000-0000-00000000a001', '13300000-0000-0000-0000-00000000a004',
        '13300000-0000-0000-0000-00000000a010', auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '13300000-0000-0000-0000-0000000000c1', '13300000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-133-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('SI', 'DR', 'CM', 'OR');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000e1', '13300000-0000-0000-0000-0000000000c1',
        'CUST-133', 'Delivered Buyer Inc', '444-555-666-133', 'Pasig', 'Pasig',
        auth.uid(), auth.uid()),
       ('13300000-0000-0000-0000-0000000000e2', '13300000-0000-0000-0000-0000000000c1',
        'CUST-133B', 'Other Buyer Inc', '444-555-666-134', 'Taguig', 'Taguig',
        auth.uid(), auth.uid()),
       ('13300000-0000-0000-0000-0000000000e3', '13300000-0000-0000-0000-0000000000c1',
        'CUST-133C', 'Late Delivery Buyer Inc', '444-555-666-135', 'Ortigas', 'Ortigas',
        auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000ab', '13300000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000ca', '13300000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

-- A stockable item, and a service item that must never be caught by the guard.
INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_sales_vat_id,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000bb', '13300000-0000-0000-0000-0000000000c1',
        'GOODS-133', 'Traded Merchandise', 'inventory_item',
        '13300000-0000-0000-0000-0000000000ca', '13300000-0000-0000-0000-0000000000ab',
        1000, 600, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
        '13300000-0000-0000-0000-00000000a006', '13300000-0000-0000-0000-00000000a008',
        '13300000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid()),
       ('13300000-0000-0000-0000-0000000000bc', '13300000-0000-0000-0000-0000000000c1',
        'SVC-133', 'Delivery Service', 'service',
        '13300000-0000-0000-0000-0000000000ca', '13300000-0000-0000-0000-0000000000ab',
        500, 0, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
        '13300000-0000-0000-0000-00000000a006', NULL, NULL,
        'weighted_average', auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-0000000000ba', '13300000-0000-0000-0000-0000000000c1',
        '13300000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
        '13300000-0000-0000-0000-00000000a004', '13300000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('13300000-0000-0000-0000-0000000000c1', '13300000-0000-0000-0000-0000000000ba',
        '13300000-0000-0000-0000-0000000000bb', 50, 30000, 600);

CREATE TEMP TABLE t_g (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1 — Ten units leave the warehouse on a delivery, and are not yet billed.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO delivery_receipts (id, company_id, branch_id, customer_id,
                               customer_name_snapshot, dr_number, dr_date,
                               delivery_address, status, delivered_at, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-00000000d100', '13300000-0000-0000-0000-0000000000c1',
        '13300000-0000-0000-0000-0000000000d1', '13300000-0000-0000-0000-0000000000e1',
        'Delivered Buyer Inc', 'DR-133-000001', '2026-03-05', 'Pasig', 'delivered',
        NOW(), auth.uid(), auth.uid());

INSERT INTO delivery_receipt_lines (id, dr_id, company_id, line_number, item_id,
                                    description, quantity, uom_id, warehouse_id,
                                    created_by, updated_by)
VALUES ('13300000-0000-0000-0000-00000000d101', '13300000-0000-0000-0000-00000000d100',
        '13300000-0000-0000-0000-0000000000c1', 1, '13300000-0000-0000-0000-0000000000bb',
        'Traded Merchandise', 10, '13300000-0000-0000-0000-0000000000ab',
        '13300000-0000-0000-0000-0000000000ba', auth.uid(), auth.uid());

SELECT lives_ok(
  $$SELECT fn_post_delivery_receipt('13300000-0000-0000-0000-00000000d100')$$,
  'the delivery posts and relieves 10 units');                                      -- 3

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13300000-0000-0000-0000-0000000000bb'),
  40::numeric, 'stock fell from 50 to 40');                                         -- 4

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13300000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13300000-0000-0000-0000-00000000a010'),
  6000.00::numeric, 'and 6,000.00 is parked in Goods Delivered Not Invoiced');      -- 5

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2 — The user types an invoice for the same goods on the Sales Invoice
--          screen, carrying no delivery link. This is the unsafe act.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_g
SELECT 'si_bad', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','13300000-0000-0000-0000-0000000000c1',
    'branch_id','13300000-0000-0000-0000-0000000000d1',
    'customer_id','13300000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot','Delivered Buyer Inc',
    'customer_address_snapshot','Pasig', 'date','2026-03-06'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13300000-0000-0000-0000-0000000000bb',
    'description','Traded Merchandise', 'quantity',10, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','13300000-0000-0000-0000-00000000a006',
    'warehouse_id','13300000-0000-0000-0000-0000000000ba')));

-- Saving is still allowed: the user may be mid-thought. Approval is where the
-- product refuses, which is early enough to fix the document.
SELECT throws_ok(format(
  'SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_bad')),
  '23514', NULL,
  'APPROVAL is refused — the goods were already delivered and not billed');         -- 6

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13300000-0000-0000-0000-0000000000bb'),
  40::numeric, 'stock was NOT relieved a second time');                             -- 8

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13300000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13300000-0000-0000-0000-00000000a010'),
  6000.00::numeric,
  'and the clearing balance still stands, waiting for the delivery to be billed'); -- 9

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 3 — What the guard must NOT refuse.
-- ══════════════════════════════════════════════════════════════════════════════

-- (a) The linked path — billing the delivery — is the whole point and must work.
INSERT INTO t_g
SELECT 'si_good', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','13300000-0000-0000-0000-0000000000c1',
    'branch_id','13300000-0000-0000-0000-0000000000d1',
    'customer_id','13300000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot','Delivered Buyer Inc',
    'customer_address_snapshot','Pasig', 'date','2026-03-07'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13300000-0000-0000-0000-0000000000bb',
    'description','Traded Merchandise', 'quantity',10, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','13300000-0000-0000-0000-00000000a006',
    'warehouse_id','13300000-0000-0000-0000-0000000000ba',
    'source_document_type','DR',
    'source_line_id','13300000-0000-0000-0000-00000000d101')));

SELECT lives_ok(format(
  'SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_good')),
  'billing the delivery through the governed link is still allowed');               -- 10

SELECT lives_ok(format(
  'SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_good')),
  'and it posts');                                                                  -- 11

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13300000-0000-0000-0000-0000000000bb'),
  40::numeric, 'stock is untouched by the billing — the cost left at delivery');    -- 12

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13300000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13300000-0000-0000-0000-00000000a010'),
  0.00::numeric,
  'and Goods Delivered Not Invoiced clears to zero — the balance cannot strand'); -- 13

-- (b) A direct invoice for goods that were never delivered, plus a service line,
--     for a DIFFERENT customer. Neither may be caught by the guard.
INSERT INTO t_g
SELECT 'si_direct', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','13300000-0000-0000-0000-0000000000c1',
    'branch_id','13300000-0000-0000-0000-0000000000d1',
    'customer_id','13300000-0000-0000-0000-0000000000e2',
    'customer_name_snapshot','Other Buyer Inc',
    'customer_address_snapshot','Taguig', 'date','2026-03-08'),
  jsonb_build_array(
    jsonb_build_object(
      'item_id','13300000-0000-0000-0000-0000000000bb',
      'description','Traded Merchandise', 'quantity',5, 'unit_price',1000,
      'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
      'revenue_account_id','13300000-0000-0000-0000-00000000a006',
      'warehouse_id','13300000-0000-0000-0000-0000000000ba'),
    jsonb_build_object(
      'item_id','13300000-0000-0000-0000-0000000000bc',
      'description','Delivery Service', 'quantity',1, 'unit_price',500,
      'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
      'revenue_account_id','13300000-0000-0000-0000-00000000a006')));

SELECT lives_ok(format(
  'SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_direct')),
  'a direct sale of never-delivered goods, with a service line, still approves');
SELECT lives_ok(format(
  'SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_direct')),
  'and still posts — the guard refuses nothing it should not');                     -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 4 — The POSTING gate, which needs an invoice approved BEFORE the delivery
--          existed: the real sequence where a user approves, then the warehouse
--          ships separately, then the user posts.
-- ══════════════════════════════════════════════════════════════════════════════
-- A draft cannot post at all, so proving the POSTING gate needs an invoice that
-- was legitimately approved BEFORE the delivery existed — the real sequence in
-- which a user approves an invoice and the warehouse then ships separately.
INSERT INTO t_g
SELECT 'si_late', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','13300000-0000-0000-0000-0000000000c1',
    'branch_id','13300000-0000-0000-0000-0000000000d1',
    'customer_id','13300000-0000-0000-0000-0000000000e3',
    'customer_name_snapshot','Late Delivery Buyer Inc',
    'customer_address_snapshot','Ortigas', 'date','2026-03-06'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13300000-0000-0000-0000-0000000000bb',
    'description','Traded Merchandise', 'quantity',4, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','13300000-0000-0000-0000-00000000a006',
    'warehouse_id','13300000-0000-0000-0000-0000000000ba')));

SELECT lives_ok(format(
  'SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_late')),
  'it approves cleanly, because no delivery exists for it yet');

INSERT INTO delivery_receipts (id, company_id, branch_id, customer_id,
                               customer_name_snapshot, dr_number, dr_date,
                               delivery_address, status, delivered_at, created_by, updated_by)
VALUES ('13300000-0000-0000-0000-00000000d200', '13300000-0000-0000-0000-0000000000c1',
        '13300000-0000-0000-0000-0000000000d1', '13300000-0000-0000-0000-0000000000e3',
        'Late Delivery Buyer Inc', 'DR-133-000002', '2026-03-07', 'Ortigas', 'delivered',
        NOW(), auth.uid(), auth.uid());

INSERT INTO delivery_receipt_lines (id, dr_id, company_id, line_number, item_id,
                                    description, quantity, uom_id, warehouse_id,
                                    created_by, updated_by)
VALUES ('13300000-0000-0000-0000-00000000d201', '13300000-0000-0000-0000-00000000d200',
        '13300000-0000-0000-0000-0000000000c1', 1, '13300000-0000-0000-0000-0000000000bb',
        'Traded Merchandise', 4, '13300000-0000-0000-0000-0000000000ab',
        '13300000-0000-0000-0000-0000000000ba', auth.uid(), auth.uid());

SELECT lives_ok(
  $$SELECT fn_post_delivery_receipt('13300000-0000-0000-0000-00000000d200')$$,
  'the warehouse then ships those goods on its own delivery');

SELECT throws_ok(format(
  'SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_g WHERE key = 'si_late')),
  '23514', NULL,
  'POSTING the already-approved invoice is now refused — the authoritative gate'); -- 7


SELECT * FROM finish();
ROLLBACK;
