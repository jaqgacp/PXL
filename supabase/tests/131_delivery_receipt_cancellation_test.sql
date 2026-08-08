-- ══════════════════════════════════════════════════════════════════════════════
-- 131 — Delivery Receipt cancellation and reversal (Backlog 18c)
--
-- WHAT THIS GUARDS
--   A warehouse mis-ships. Before this, nothing could be done about it: a posted
--   delivery could be neither cancelled nor reversed, and the cost it parked in
--   Goods Delivered Not Invoiced could be released only by BILLING it — that is,
--   only by invoicing a customer who never received the goods. Test 120 walks
--   the happy path; this file walks the day a delivery is wrong.
--
--   The ordering rule is the substance: an invoice that already claims the
--   delivery must be voided FIRST. Reversing the clearing balance from underneath
--   a live invoice would leave that invoice taking a cost that no longer exists,
--   so the delivery refuses to cancel while any non-cancelled invoice — draft
--   included — bills it.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS ALSO GUARDS — the defect found while building the above
--   `delivery_receipts` became a posting document on 2026-08-03, but its status
--   guard still allowed only `delivered_at` to change once the row left draft.
--   The final statement of `fn_post_delivery_receipt`, which stamps
--   `journal_entry_id` / `posted_at` / `posted_by`, was therefore REFUSED
--   whenever the receipt had been marked delivered in an earlier transaction —
--   exactly what the screen does. No pgTAP file could see it, because pgTAP runs
--   inside one transaction and the guard's `same_txn` escape then applies.
--   Assertion 1 is structural for that reason: it asserts the guard now names the
--   posting stamps. The behavioural proof runs OUTSIDE a transaction, in
--   `scripts/verify_delivery_receipt_lifecycle.mjs`.
--
-- WHAT THIS DOES NOT CLAIM
--   Nothing about FIFO restock ordering: this company costs weighted-average, as
--   test 120 does. Nothing about Document Conversion, which is not started.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

-- ── The guard the posting path depends on ────────────────────────────────────
SELECT ok(
  pg_get_triggerdef(t.oid) LIKE '%journal_entry_id%'
  AND pg_get_triggerdef(t.oid) LIKE '%posted_at%'
  AND pg_get_triggerdef(t.oid) LIKE '%posted_by%',
  'the delivery-receipt header guard names the posting stamps its own posting function writes'
) FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
 WHERE c.relname = 'delivery_receipts'
   AND t.tgname = 'trg_guard_header_delivery_receipts';                             -- 1

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '13100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'dr-cancel@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13100000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000c1', 'corporation', 'Mis-ship Trading Corp',
        'Wholesale trading', '400-000-131-00000', 'vat', 'calendar',
        'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200',
        'dr-cancel@test.local', 'M Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000d1', '13100000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'M St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('13100000-0000-0000-0000-0000000000f1', '13100000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '13100000-0000-0000-0000-0000000000c1', '13100000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('13100000-0000-0000-0000-00000000a001', '13100000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a002', '13100000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a004', '13100000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory','asset',    'debit',  true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a010', '13100000-0000-0000-0000-0000000000c1', '1310', 'Goods Delivered Not Invoiced', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a005', '13100000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a006', '13100000-0000-0000-0000-0000000000c1', '4010', 'Merchandise Sales',   'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a008', '13100000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold',  'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('13100000-0000-0000-0000-00000000a009', '13100000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance',  'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, inventory_account_id, sales_delivery_clearing_account_id,
        created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000c1',
        '13100000-0000-0000-0000-00000000a002', '13100000-0000-0000-0000-00000000a005',
        '13100000-0000-0000-0000-00000000a001', '13100000-0000-0000-0000-00000000a004',
        '13100000-0000-0000-0000-00000000a010',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '13100000-0000-0000-0000-0000000000c1', '13100000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-131-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('SI', 'DR', 'CM', 'OR');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000e1', '13100000-0000-0000-0000-0000000000c1',
        'CUST-131', 'Wrong Address Inc', '444-555-666-131',
        'Pasig', 'Pasig', auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000ab', '13100000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000ca', '13100000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost, default_sales_vat_id,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000bb', '13100000-0000-0000-0000-0000000000c1',
        'GOODS-131', 'Traded Merchandise', 'inventory_item',
        '13100000-0000-0000-0000-0000000000ca', '13100000-0000-0000-0000-0000000000ab',
        1000, 600, (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
        '13100000-0000-0000-0000-00000000a006', '13100000-0000-0000-0000-00000000a008',
        '13100000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-0000000000ba', '13100000-0000-0000-0000-0000000000c1',
        '13100000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Warehouse',
        '13100000-0000-0000-0000-00000000a004', '13100000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('13100000-0000-0000-0000-0000000000c1', '13100000-0000-0000-0000-0000000000ba',
        '13100000-0000-0000-0000-0000000000bb', 20, 12000, 600);

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1 — Ship five units to the wrong address.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO delivery_receipts (id, company_id, branch_id, customer_id,
                               customer_name_snapshot, dr_number, dr_date,
                               delivery_address, status, delivered_at,
                               created_by, updated_by)
VALUES ('13100000-0000-0000-0000-00000000d100', '13100000-0000-0000-0000-0000000000c1',
        '13100000-0000-0000-0000-0000000000d1', '13100000-0000-0000-0000-0000000000e1',
        'Wrong Address Inc', 'DR-131-000001', '2026-03-05',
        'Pasig', 'delivered', NOW(), auth.uid(), auth.uid());

INSERT INTO delivery_receipt_lines (id, dr_id, company_id, line_number, item_id,
                                    description, quantity, uom_id, warehouse_id,
                                    created_by, updated_by)
VALUES ('13100000-0000-0000-0000-00000000d101', '13100000-0000-0000-0000-00000000d100',
        '13100000-0000-0000-0000-0000000000c1', 1, '13100000-0000-0000-0000-0000000000bb',
        'Traded Merchandise', 5, '13100000-0000-0000-0000-0000000000ab',
        '13100000-0000-0000-0000-0000000000ba', auth.uid(), auth.uid());

SELECT lives_ok(
  $$SELECT fn_post_delivery_receipt('13100000-0000-0000-0000-00000000d100')$$,
  'the mis-shipped delivery posts and relieves stock');                             -- 2

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '13100000-0000-0000-0000-0000000000ba'
      AND item_id = '13100000-0000-0000-0000-0000000000bb'),
  15::numeric, 'stock fell from 20 to 15');                                         -- 3

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2 — A reason is not optional, and neither is an invented one.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_ok(
  $q$SELECT fn_void_delivery_receipt('13100000-0000-0000-0000-00000000d100', NULL, NULL)$q$,
  NULL, 'A void reason is required',
  'cancelling without any reason is refused');                                      -- 4

SELECT throws_ok(
  $q$SELECT fn_void_delivery_receipt('13100000-0000-0000-0000-00000000d100',
       '13100000-0000-0000-0000-00000000ffff', NULL)$q$,
  NULL, 'Invalid or inactive void reason',
  'cancelling with an unknown reason code is refused');                             -- 5

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 3 — An invoice already claims it. The ordering rule holds.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok($q$
  SELECT fn_save_sales_invoice(NULL, jsonb_build_object(
    'company_id', '13100000-0000-0000-0000-0000000000c1',
    'branch_id',  '13100000-0000-0000-0000-0000000000d1',
    'customer_id','13100000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Wrong Address Inc',
    'customer_address_snapshot', 'Pasig',
    'date', '2026-03-06', 'reference', 'DR-131-000001'),
    jsonb_build_array(jsonb_build_object(
      'item_id', '13100000-0000-0000-0000-0000000000bb',
      'description', 'Traded Merchandise', 'quantity', 5, 'unit_price', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', '13100000-0000-0000-0000-00000000a006',
      'warehouse_id', '13100000-0000-0000-0000-0000000000ba',
      'source_document_type', 'DR',
      'source_line_id', '13100000-0000-0000-0000-00000000d101')))
$q$, 'a draft invoice can be raised against the delivery');                         -- 6

SELECT throws_ok(
  $q$SELECT fn_void_delivery_receipt('13100000-0000-0000-0000-00000000d100',
       (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'), NULL)$q$,
  NULL, NULL,
  'a delivery a DRAFT invoice already bills cannot be cancelled');                  -- 7

SELECT is(
  (SELECT status FROM delivery_receipts WHERE id = '13100000-0000-0000-0000-00000000d100'),
  'delivered', 'and the refused cancellation left the delivery exactly as it was'); -- 8

SELECT lives_ok($q$
  SELECT fn_void_sales_invoice(
    (SELECT sil.sales_invoice_id FROM sales_invoice_lines sil
      WHERE sil.source_line_id = '13100000-0000-0000-0000-00000000d101'),
    (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'), 'wrong delivery')
$q$, 'the invoice is voided first, as the rule requires');                          -- 9

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 4 — Now the delivery cancels, and the goods come back.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok(
  $q$SELECT fn_void_delivery_receipt('13100000-0000-0000-0000-00000000d100',
       (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'),
       'shipped to the wrong address')$q$,
  'an unbilled posted delivery cancels');                                           -- 10

SELECT is(
  (SELECT status FROM delivery_receipts WHERE id = '13100000-0000-0000-0000-00000000d100'),
  'cancelled', 'the delivery is cancelled');                                        -- 11

SELECT is(
  (SELECT void_memo FROM delivery_receipts WHERE id = '13100000-0000-0000-0000-00000000d100'),
  'shipped to the wrong address', 'and it says why, on the document itself');       -- 12

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '13100000-0000-0000-0000-0000000000ba'
      AND item_id = '13100000-0000-0000-0000-0000000000bb'),
  20::numeric, 'the five units are back on hand');                                  -- 13

SELECT is(
  (SELECT total_cost FROM stock_balances
    WHERE warehouse_id = '13100000-0000-0000-0000-0000000000ba'
      AND item_id = '13100000-0000-0000-0000-0000000000bb'),
  12000.00::numeric, 'and stock value is back to where it started');                -- 14

SELECT is(
  (SELECT wac_unit_cost FROM stock_balances
    WHERE warehouse_id = '13100000-0000-0000-0000-0000000000ba'
      AND item_id = '13100000-0000-0000-0000-0000000000bb'),
  600.000000::numeric, 'the weighted-average cost is undisturbed');                 -- 15

SELECT results_eq(
  $q$SELECT it.transaction_type, it.qty, it.total_cost
       FROM inventory_transactions it
      WHERE it.reference_doc_type = 'DR_VOID'
        AND it.reference_doc_id = '13100000-0000-0000-0000-00000000d100'$q$,
  $$VALUES ('adjustment_in'::text, 5::numeric, 3000.00::numeric)$$,
  'the restock is its own inventory transaction, not an edit of the issue');        -- 16

-- The reversal is the mirror of the delivery journal, and the clearing account
-- that held the cost in between is empty again.
SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel
     JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13100000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13100000-0000-0000-0000-00000000a010'),
  0.00::numeric, 'Goods Delivered Not Invoiced nets to zero after the cancellation');-- 17

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
     FROM journal_entry_lines jel
     JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13100000-0000-0000-0000-0000000000c1'
      AND jel.account_id = '13100000-0000-0000-0000-00000000a004'),
  0.00::numeric, 'and inventory''s ledger balance is back to zero movement');       -- 18

SELECT is(
  (SELECT COALESCE(SUM(jel.debit_amount) - SUM(jel.credit_amount), 0)
     FROM journal_entry_lines jel
     JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '13100000-0000-0000-0000-0000000000c1'),
  0.00::numeric, 'every journal the company owns still balances');                  -- 19

SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
    WHERE table_name = 'posting_event'
      AND record_id = '13100000-0000-0000-0000-00000000d100'
      AND new_data->>'event_type' = 'VOIDED'
      AND new_data->>'source_doc_type' = 'DR'),
  1, 'the cancellation is recorded as a posting event');                            -- 20

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 5 — What a cancelled delivery no longer allows.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_ok(
  $q$SELECT fn_void_delivery_receipt('13100000-0000-0000-0000-00000000d100',
       (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'), NULL)$q$,
  NULL, 'Delivery receipt is already cancelled',
  'cancelling twice is refused — one reversal, not two');                           -- 21

SELECT throws_ok($q$
  SELECT fn_save_sales_invoice(NULL, jsonb_build_object(
    'company_id', '13100000-0000-0000-0000-0000000000c1',
    'branch_id',  '13100000-0000-0000-0000-0000000000d1',
    'customer_id','13100000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Wrong Address Inc',
    'customer_address_snapshot', 'Pasig',
    'date', '2026-03-07'),
    jsonb_build_array(jsonb_build_object(
      'item_id', '13100000-0000-0000-0000-0000000000bb',
      'description', 'Traded Merchandise', 'quantity', 5, 'unit_price', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', '13100000-0000-0000-0000-00000000a006',
      'warehouse_id', '13100000-0000-0000-0000-0000000000ba',
      'source_document_type', 'DR',
      'source_line_id', '13100000-0000-0000-0000-00000000d101')))
$q$, NULL, NULL, 'a cancelled delivery can no longer be billed');                   -- 22

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 6 — A delivery that never posted cancels without inventing a reversal.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO delivery_receipts (id, company_id, branch_id, customer_id,
                               customer_name_snapshot, dr_number, dr_date,
                               delivery_address, status, created_by, updated_by)
VALUES ('13100000-0000-0000-0000-00000000d200', '13100000-0000-0000-0000-0000000000c1',
        '13100000-0000-0000-0000-0000000000d1', '13100000-0000-0000-0000-0000000000e1',
        'Wrong Address Inc', 'DR-131-000002', '2026-03-08',
        'Pasig', 'draft', auth.uid(), auth.uid());

SELECT lives_ok(
  $q$SELECT fn_void_delivery_receipt('13100000-0000-0000-0000-00000000d200',
       (SELECT id FROM void_reason_codes WHERE code = 'CANCELLED_ORDER'), NULL)$q$,
  'a draft delivery cancels too');                                                  -- 23

SELECT is(
  (SELECT count(*)::int FROM journal_entries
    WHERE reference_doc_id = '13100000-0000-0000-0000-00000000d200'),
  0, 'and it wrote no journal, because it had moved nothing');                      -- 24

SELECT * FROM finish();
ROLLBACK;
