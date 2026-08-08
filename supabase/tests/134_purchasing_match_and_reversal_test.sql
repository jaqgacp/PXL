-- ══════════════════════════════════════════════════════════════════════════════
-- 134 — Three-way match and Receiving Report cancellation
--
-- WHAT THIS GUARDS
--   Two purchasing gaps closed together, because they are the same lifecycle.
--
--   **Three-way match.** Nothing checked that a receipt agreed with its order or
--   that a bill agreed with its receipt. A supplier could ship 500 against an
--   order for 100, and bill 500 against a receipt of 100, and every document
--   would post. Quantity is now controlled at the grain each relationship
--   supports: receipt against the ordered LINE (`receiving_report_lines.po_line_id`),
--   billing against the receipt per ITEM (`vendor_bills.rr_id`).
--
--   **Receipt cancellation.** A confirmed receipt increased stock and posted
--   DR Inventory / CR Goods Received Not Invoiced, and nothing reversed any of
--   it. A `cancelled` status existed with nothing able to reach it.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Price variance. No variance concept exists anywhere in the product — no
--   variance account key, no tolerance, no price variance reason — so quantity
--   matching ships and price matching is recorded as separate work rather than
--   invented here. Nor does it claim an over-receipt TOLERANCE: none is
--   governed, so both rules fail closed at the exact quantity.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(32);

-- ── The rules sit where approval and posting both pass through ───────────────
SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'fn_confirm_receiving_report')
    LIKE '%fn_assert_receipt_within_po%',
  'confirmation carries the over-receipt rule, before anything posts');            -- 1

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'fn_validate_vendor_bill_accounting_ready')
    LIKE '%fn_assert_bill_within_receipt%',
  'vendor-bill readiness carries the over-billing rule');                          -- 2

SELECT ok(
  (SELECT reloptions::text FROM pg_class WHERE relname = 'vw_po_line_receipt_progress')
    LIKE '%security_invoker%'
  AND (SELECT reloptions::text FROM pg_class WHERE relname = 'vw_rr_item_billing_progress')
    LIKE '%security_invoker%',
  'both progress views run as the invoker, so RLS still isolates companies');      -- 3

SELECT ok(
  NOT has_function_privilege('anon',
    'public.fn_void_receiving_report(uuid,uuid,text)', 'EXECUTE')
  AND NOT has_function_privilege('anon',
    'public.fn_validate_vendor_bill_accounting_ready(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.fn_assert_receipt_within_po(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.fn_assert_bill_within_receipt(uuid)', 'EXECUTE'),
  'destructive RPC is authenticated, and SECURITY DEFINER relationship helpers stay private'); -- 4

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '13400000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'match@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13400000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000c1', 'corporation', 'Three Way Corp',
        'Wholesale', '400-000-134-00000', 'vat', 'calendar',
        'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200',
        'match@test.local', 'M Owner', 'President',
        '13400000-0000-0000-0000-000000000001', '13400000-0000-0000-0000-000000000001');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000d1', '13400000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'M St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('13400000-0000-0000-0000-0000000000f1', '13400000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '13400000-0000-0000-0000-0000000000c1', '13400000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('13400000-0000-0000-0000-00000000a001', '13400000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13400000-0000-0000-0000-00000000a004', '13400000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory','asset',    'debit',  true, true, auth.uid(), auth.uid()),
  ('13400000-0000-0000-0000-00000000a007', '13400000-0000-0000-0000-0000000000c1', '1400', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13400000-0000-0000-0000-00000000a003', '13400000-0000-0000-0000-0000000000c1', '2000', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('13400000-0000-0000-0000-00000000a011', '13400000-0000-0000-0000-0000000000c1', '2015', 'Goods Received Not Invoiced', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('13400000-0000-0000-0000-00000000a008', '13400000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold', 'expense', 'debit', true, true, auth.uid(), auth.uid()),
  ('13400000-0000-0000-0000-00000000a009', '13400000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance',  'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id, input_vat_account_id,
        default_cash_account_id, inventory_account_id, purchase_clearing_account_id,
        created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000c1',
        '13400000-0000-0000-0000-00000000a003', '13400000-0000-0000-0000-00000000a007',
        '13400000-0000-0000-0000-00000000a001', '13400000-0000-0000-0000-00000000a004',
        '13400000-0000-0000-0000-00000000a011', auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '13400000-0000-0000-0000-0000000000c1', '13400000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-134-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('PO', 'RR', 'VB', 'PV');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000e1', '13400000-0000-0000-0000-0000000000c1',
        'SUPP-134', 'Match Vendor Inc', '777-888-999-134', 'Quezon City',
        auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000ab', '13400000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000ca', '13400000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_purchase_vat_id,
                   purchase_expense_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000bb', '13400000-0000-0000-0000-0000000000c1',
        'GOODS-134', 'Purchased Merchandise', 'inventory_item',
        '13400000-0000-0000-0000-0000000000ca', '13400000-0000-0000-0000-0000000000ab',
        1000, 600, (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
        '13400000-0000-0000-0000-00000000a008', '13400000-0000-0000-0000-00000000a008',
        '13400000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('13400000-0000-0000-0000-0000000000ba', '13400000-0000-0000-0000-0000000000c1',
        '13400000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
        '13400000-0000-0000-0000-00000000a004', '13400000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_m (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1 — Order 100 units.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_m
SELECT 'po', fn_save_purchase_order(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'supplier_id','13400000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot','Match Vendor Inc', 'po_date','2026-03-01'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise', 'quantity',100, 'unit_price',600,
    'uom_id','13400000-0000-0000-0000-0000000000ab')));

SELECT fn_approve_purchase_order((SELECT id FROM t_m WHERE key = 'po'));

SELECT is((SELECT ordered_qty FROM vw_po_line_receipt_progress
            WHERE po_id = (SELECT id FROM t_m WHERE key='po')),
  100::numeric, 'the order shows 100 ordered');                                    -- 4

SELECT is((SELECT remaining_qty FROM vw_po_line_receipt_progress
            WHERE po_id = (SELECT id FROM t_m WHERE key='po')),
  100::numeric, 'and 100 remaining, before anything is received');                 -- 5

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2 — Partial receipt of 60. Multiple receipts against one order.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_m
SELECT 'rr1', fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'warehouse_id','13400000-0000-0000-0000-0000000000ba',
    'po_id',(SELECT id FROM t_m WHERE key='po'),
    'rr_date','2026-03-05', 'supplier_dr_no','VDR-134-1'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id',(SELECT id FROM purchase_order_lines
                   WHERE po_id = (SELECT id FROM t_m WHERE key='po') LIMIT 1),
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise',
    'ordered_qty',100, 'received_qty',60, 'unit_price',600,
    'uom_id','13400000-0000-0000-0000-0000000000ab')));

SELECT lives_ok(format('SELECT fn_confirm_receiving_report(%L)',
  (SELECT id FROM t_m WHERE key='rr1')),
  'a partial receipt of 60 against an order for 100 is allowed');                  -- 6

SELECT is((SELECT received_qty FROM vw_po_line_receipt_progress
            WHERE po_id = (SELECT id FROM t_m WHERE key='po')),
  60::numeric, 'the order shows 60 received');                                     -- 7

SELECT is((SELECT remaining_qty FROM vw_po_line_receipt_progress
            WHERE po_id = (SELECT id FROM t_m WHERE key='po')),
  40::numeric, 'and 40 still open');                                               -- 8

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13400000-0000-0000-0000-0000000000bb'),
  60::numeric, 'stock rose to 60');                                                -- 9

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 3 — Over-receipt. A second receipt of 50 would take the total to 110.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_m
SELECT 'rr_over', fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'warehouse_id','13400000-0000-0000-0000-0000000000ba',
    'po_id',(SELECT id FROM t_m WHERE key='po'),
    'rr_date','2026-03-06', 'supplier_dr_no','VDR-134-OVER'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id',(SELECT id FROM purchase_order_lines
                   WHERE po_id = (SELECT id FROM t_m WHERE key='po') LIMIT 1),
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise',
    'ordered_qty',100, 'received_qty',50, 'unit_price',600,
    'uom_id','13400000-0000-0000-0000-0000000000ab')));

SELECT throws_ok(format('SELECT fn_confirm_receiving_report(%L)',
  (SELECT id FROM t_m WHERE key='rr_over')),
  '23514', NULL,
  'a second receipt taking the total to 110 against an order for 100 is refused'); -- 10

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13400000-0000-0000-0000-0000000000bb'),
  60::numeric, 'and no stock moved on the refused receipt');                       -- 11

SELECT is((SELECT COUNT(*)::int FROM vw_rr_item_billing_progress
            WHERE rr_id = (SELECT id FROM t_m WHERE key='rr_over')),
  0, 'a draft Receiving Report contributes no received quantity to billing progress');

-- A bill may not turn that draft quantity into an AP liability.
SELECT throws_ok(format(
  'SELECT fn_save_vendor_bill(NULL, %L::jsonb, %L::jsonb)',
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'supplier_id','13400000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot','Match Vendor Inc',
    'supplier_tin_snapshot','777-888-999-134',
    'supplier_invoice_number','VINV-134-DRAFT-RR',
    'rr_id',(SELECT id FROM t_m WHERE key='rr_over'),
    'bill_date','2026-03-06'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise', 'quantity',1, 'unit_price',600,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','13400000-0000-0000-0000-00000000a008'))),
  'P0001', NULL,
  'a Vendor Bill cannot even be saved against an unconfirmed Receiving Report');

-- A crafted line cannot borrow quantity from another Purchase Order, even in
-- the same company. The header PO is the relationship authority.
INSERT INTO t_m
SELECT 'po_other', fn_save_purchase_order(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'supplier_id','13400000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot','Match Vendor Inc', 'po_date','2026-03-01'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise', 'quantity',200, 'unit_price',600,
    'uom_id','13400000-0000-0000-0000-0000000000ab')));
SELECT fn_approve_purchase_order((SELECT id FROM t_m WHERE key='po_other'));

INSERT INTO t_m
SELECT 'rr_wrong_po_line', fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'warehouse_id','13400000-0000-0000-0000-0000000000ba',
    'po_id',(SELECT id FROM t_m WHERE key='po'),
    'rr_date','2026-03-06', 'supplier_dr_no','VDR-134-WRONG-LINE'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id',(SELECT id FROM purchase_order_lines
                   WHERE po_id = (SELECT id FROM t_m WHERE key='po_other') LIMIT 1),
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise',
    'ordered_qty',200, 'received_qty',1, 'unit_price',600,
    'uom_id','13400000-0000-0000-0000-0000000000ab')));

SELECT throws_ok(format('SELECT fn_confirm_receiving_report(%L)',
  (SELECT id FROM t_m WHERE key='rr_wrong_po_line')),
  '23514', NULL,
  'a receipt line cannot borrow ordered quantity from another Purchase Order');

SELECT lives_ok(format('SELECT fn_void_receiving_report(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='rr_wrong_po_line'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'invalid draft abandoned'),
  'the invalid draft receipt can be cancelled without stock or journal effects');

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 4 — Bill the receipt. Partial billing, then over-billing.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_m
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'supplier_id','13400000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot','Match Vendor Inc',
    'supplier_tin_snapshot','777-888-999-134',
    'supplier_invoice_number','VINV-134-1',
    'rr_id',(SELECT id FROM t_m WHERE key='rr1'),
    'bill_date','2026-03-07'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise', 'quantity',40, 'unit_price',600,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','13400000-0000-0000-0000-00000000a008')));

SELECT lives_ok(format('SELECT fn_approve_vendor_bill(%L)',
  (SELECT id FROM t_m WHERE key='vb1')),
  'billing 40 of the 60 received is allowed — partial billing works');             -- 12

SELECT is((SELECT remaining_billable_qty FROM vw_rr_item_billing_progress
            WHERE rr_id = (SELECT id FROM t_m WHERE key='rr1')),
  20::numeric, 'the receipt shows 20 still billable');                             -- 13

-- A second bill for 30 would take the total billed to 70 against 60 received.
INSERT INTO t_m
SELECT 'vb_over', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'supplier_id','13400000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot','Match Vendor Inc',
    'supplier_tin_snapshot','777-888-999-134',
    'supplier_invoice_number','VINV-134-OVER',
    'rr_id',(SELECT id FROM t_m WHERE key='rr1'),
    'bill_date','2026-03-08'),
  jsonb_build_array(jsonb_build_object(
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise', 'quantity',30, 'unit_price',600,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','13400000-0000-0000-0000-00000000a008')));

SELECT throws_ok(format('SELECT fn_approve_vendor_bill(%L)',
  (SELECT id FROM t_m WHERE key='vb_over')),
  '23514', NULL,
  'a second bill taking billed to 70 against 60 received is refused');             -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 5 — Receipt cancellation, and the ordering rule that protects the bill.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_ok(format('SELECT fn_void_receiving_report(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='rr1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'wrong goods'),
  '23514', NULL,
  'the receipt cannot be cancelled while a live Vendor Bill claims it');           -- 15

-- Void the bill first, as the ordering rule requires.
SELECT lives_ok(format('SELECT fn_void_vendor_bill(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='vb1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'billed in error'),
  'the bill is voided first');                                                     -- 16

-- The refused over-bill is still a DRAFT claiming this receipt, and a draft
-- claim counts: posting it later would find a receipt that no longer exists.
SELECT throws_ok(format('SELECT fn_void_receiving_report(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='rr1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'wrong goods'),
  '23514', NULL,
  'a DRAFT bill still claiming the receipt blocks it too');                        -- 17

SELECT lives_ok(format('SELECT fn_void_vendor_bill(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='vb_over'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'draft abandoned'),
  'the abandoned draft bill is voided');                                           -- 18

-- Even with the bills corrected, the receipt cannot remove more stock than is
-- still present. The refusal names the on-hand/needed shortfall.
UPDATE stock_balances
SET qty_on_hand = 59, total_cost = 35400, wac_unit_cost = 600
WHERE company_id = '13400000-0000-0000-0000-0000000000c1'
  AND warehouse_id = '13400000-0000-0000-0000-0000000000ba'
  AND item_id = '13400000-0000-0000-0000-0000000000bb';

SELECT throws_ok(format('SELECT fn_void_receiving_report(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='rr1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'wrong goods'),
  '23514', NULL,
  'receipt cancellation fails closed when one received unit has already moved onward');

UPDATE stock_balances
SET qty_on_hand = 60, total_cost = 36000, wac_unit_cost = 600
WHERE company_id = '13400000-0000-0000-0000-0000000000c1'
  AND warehouse_id = '13400000-0000-0000-0000-0000000000ba'
  AND item_id = '13400000-0000-0000-0000-0000000000bb';

SELECT lives_ok(format('SELECT fn_void_receiving_report(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='rr1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'wrong goods'),
  'and only then does the receipt cancel');                                        -- 19

SELECT is((SELECT status FROM receiving_reports WHERE id = (SELECT id FROM t_m WHERE key='rr1')),
  'cancelled', 'the receipt is cancelled');                                        -- 20

SELECT is((SELECT qty_on_hand FROM stock_balances
            WHERE item_id = '13400000-0000-0000-0000-0000000000bb'),
  0::numeric, 'the stock it brought in is gone again');                            -- 21

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13400000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13400000-0000-0000-0000-00000000a011'),
  0.00::numeric, 'Goods Received Not Invoiced nets to zero — nothing stranded');   -- 22

-- Cancelling releases the ordered quantity, so the order reopens.
SELECT is((SELECT remaining_qty FROM vw_po_line_receipt_progress
            WHERE po_id = (SELECT id FROM t_m WHERE key='po')),
  100::numeric, 'and the purchase order reopens to its full 100');                 -- 23

SELECT is((SELECT status FROM purchase_orders WHERE id = (SELECT id FROM t_m WHERE key='po')),
  'approved', 'the Purchase Order header is reopened, so a replacement receipt is reachable');

-- Cost-layered receipts are cancellable when their exact layer is still
-- untouched; the reversal retains the original layer as exhausted evidence.
UPDATE items
SET costing_method = 'fifo'
WHERE id = '13400000-0000-0000-0000-0000000000bb';

INSERT INTO t_m
SELECT 'rr_fifo', fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','13400000-0000-0000-0000-0000000000c1',
    'branch_id','13400000-0000-0000-0000-0000000000d1',
    'warehouse_id','13400000-0000-0000-0000-0000000000ba',
    'po_id',(SELECT id FROM t_m WHERE key='po'),
    'rr_date','2026-03-09', 'supplier_dr_no','VDR-134-FIFO'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id',(SELECT id FROM purchase_order_lines
                   WHERE po_id = (SELECT id FROM t_m WHERE key='po') LIMIT 1),
    'item_id','13400000-0000-0000-0000-0000000000bb',
    'description','Purchased Merchandise',
    'ordered_qty',100, 'received_qty',1, 'unit_price',600,
    'uom_id','13400000-0000-0000-0000-0000000000ab')));

SELECT lives_ok(format('SELECT fn_confirm_receiving_report(%L)',
  (SELECT id FROM t_m WHERE key='rr_fifo')),
  'a FIFO receipt can still be confirmed through the existing selectable method');

SELECT lives_ok(format('SELECT fn_void_receiving_report(%L, %L, %L)',
  (SELECT id FROM t_m WHERE key='rr_fifo'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),
  'FIFO receipt reversal'),
  'an untouched FIFO receipt cancels through exact layer reversal');

SELECT * FROM finish();
ROLLBACK;
