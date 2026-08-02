-- PXL-AUD-073 end-to-end proof on FRESH data.
--
-- WHY THIS EXISTS SEPARATELY FROM TEST 111
--   Test 111 asserts the inventory-to-GL invariant over whatever dataset is
--   loaded, which in practice is the canonical demo seed. That seed was produced
--   during early development by logic that was not always correct — it shipped an
--   opening journal ₱630 short of opening stock because it valued "opening"
--   inventory from a live stock_balances snapshot taken after later seed blocks
--   had already issued stock. Verifying a fix against data that may itself encode
--   the defect is circular.
--
--   This test therefore trusts nothing that already exists. It provisions its own
--   company, chart of accounts, fiscal calendar, masters and documents, and drives
--   the real purchase chain through the current production RPCs:
--
--       Purchase Order -> Receiving Report -> confirm -> Vendor Bill -> post
--
--   Then it proves the accounting from first principles.
--
-- WHAT IT PROVES
--   E1  Confirming a receipt posts a journal (the PXL-AUD-073 defect).
--   E2  The receipt journal is DR inventory control / CR purchase clearing.
--   E3  Stock quantity and value are what the receipt said they were.
--   E4  Inventory subledger equals the inventory control account exactly.
--   E5  Posting the vendor bill clears purchase clearing back to zero.
--   E6  After the full chain the books balance and the net position is
--       DR Inventory / DR Input VAT / CR Accounts Payable — i.e. goods received
--       and owed for, with no cost stranded in a clearing account.
--   E7  No cost layer is created for a weighted-average item.
--
-- Everything is created inside the transaction and rolled back.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ── Identity ────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111173',
        'authenticated', 'authenticated', 'e2e-purchase@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111173","role":"authenticated"}', true);

-- ── Company, branch, fiscal calendar ────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-0000-0000-0000-000000000173', 'corporation',
        'Fresh Data Trading Inc', 'Wholesale Trading', '173-222-333-000',
        'vat', 'calendar',
        'Unit 7', 'Fresh Bldg', 'Makati', 'Metro Manila', '1200',
        'e2e-purchase@test.local', 'Maria Santos', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173', 'HO', 'Head Office',
        'Unit 7', 'Fresh Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-0000-0000-0000-000000000173',
       '44444444-0000-0000-0000-000000000173', m,
       to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

-- ── Chart of accounts ───────────────────────────────────────────────────────
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('bbbbbbbb-0000-0000-0000-000000000173', '22222222-0000-0000-0000-000000000173',
   '1310', 'Merchandise Inventory',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('bbbbbbbb-0000-0000-0000-000000000174', '22222222-0000-0000-0000-000000000173',
   '2015', 'Goods Received Not Invoiced',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('bbbbbbbb-0000-0000-0000-000000000175', '22222222-0000-0000-0000-000000000173',
   '2010', 'Accounts Payable',             'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('bbbbbbbb-0000-0000-0000-000000000176', '22222222-0000-0000-0000-000000000173',
   '1400', 'Input VAT',                    'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('bbbbbbbb-0000-0000-0000-000000000177', '22222222-0000-0000-0000-000000000173',
   '1010', 'Cash in Bank',                 'asset',     'debit',  true, true, auth.uid(), auth.uid());

-- The two PXL-AUD-073 keys are configured, not assumed from an account code.
INSERT INTO company_accounting_config (
  company_id, ap_account_id, input_vat_account_id, default_cash_account_id,
  inventory_account_id, purchase_clearing_account_id, created_by, updated_by)
VALUES ('22222222-0000-0000-0000-000000000173',
        'bbbbbbbb-0000-0000-0000-000000000175',
        'bbbbbbbb-0000-0000-0000-000000000176',
        'bbbbbbbb-0000-0000-0000-000000000177',
        'bbbbbbbb-0000-0000-0000-000000000173',
        'bbbbbbbb-0000-0000-0000-000000000174',
        auth.uid(), auth.uid());

SELECT is(
  (SELECT count(*)::int FROM account_mapping
   WHERE company_id = '22222222-0000-0000-0000-000000000173'
     AND key_code IN ('INVENTORY_CONTROL', 'PURCHASE_CLEARING')),
  2,
  'E0: configuring the accounting config projects both governed inventory keys');

-- ── Number series ───────────────────────────────────────────────────────────
INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-0000-0000-0000-000000000173',
       '33333333-0000-0000-0000-000000000173',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('PO', 'RR', 'VB', 'JE');

-- ── Masters ─────────────────────────────────────────────────────────────────
INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        is_active, created_by, updated_by)
VALUES ('55555555-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173',
        '33333333-0000-0000-0000-000000000173',
        'WH-FRESH', 'Fresh Main Warehouse', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name,
                             is_active, created_by, updated_by)
VALUES ('66666666-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173',
        'GOODS', 'Trading Goods', true, auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description,
                              is_active, created_by, updated_by)
VALUES ('77777777-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173',
        'PC', 'Piece', true, auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type,
                   category_id, uom_id, costing_method, inventory_account_id,
                   is_active, created_by, updated_by)
VALUES ('88888888-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173',
        'FRESH-ITEM-001', 'Fresh Trading Item', 'inventory_item',
        '66666666-0000-0000-0000-000000000173',
        '77777777-0000-0000-0000-000000000173',
        'weighted_average', 'bbbbbbbb-0000-0000-0000-000000000173',
        true, auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, default_tax_type, is_active,
                       created_by, updated_by)
VALUES ('99999999-0000-0000-0000-000000000173',
        '22222222-0000-0000-0000-000000000173',
        'SUP-FRESH', 'Fresh Supplier Corporation', '173-999-888-00000',
        'Unit 9, Supplier Row, Makati, Metro Manila', 'vat_registered', true,
        auth.uid(), auth.uid());

-- ── Order then receive 100 units at ₱250.00 = ₱25,000.00 ────────────────────
SELECT fn_save_purchase_order(
  NULL,
  jsonb_build_object(
    'company_id',   '22222222-0000-0000-0000-000000000173',
    'branch_id',    '33333333-0000-0000-0000-000000000173',
    'po_date',      '2026-03-05',
    'supplier_id',  '99999999-0000-0000-0000-000000000173',
    'supplier_name_snapshot', 'Fresh Supplier Corporation',
    'supplier_tin_snapshot',  '173-999-888-00000',
    'expected_date', '2026-03-10',
    'notes',        'Fresh-data end-to-end purchase order'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',     '88888888-0000-0000-0000-000000000173',
    'description', 'Fresh Trading Item',
    'quantity',    100,
    'uom_id',      '77777777-0000-0000-0000-000000000173',
    'unit_price',  250
  ))
) AS po_id \gset

SELECT lives_ok(
  $$SELECT fn_approve_purchase_order('$$ || :'po_id' || $$'::uuid)$$,
  'E0b: the purchase order approves through the production RPC');

SELECT fn_save_receiving_report(
  NULL,
  jsonb_build_object(
    'company_id',   '22222222-0000-0000-0000-000000000173',
    'branch_id',    '33333333-0000-0000-0000-000000000173',
    'warehouse_id', '55555555-0000-0000-0000-000000000173',
    'po_id',        :'po_id',
    'rr_date',      '2026-03-10',
    'supplier_dr_no', 'FRESH-DR-0001',
    'remarks',      'Fresh-data end-to-end goods receipt'
  ),
  jsonb_build_array(jsonb_build_object(
    'po_line_id',   (SELECT id FROM purchase_order_lines WHERE po_id = :'po_id'::uuid ORDER BY line_number LIMIT 1),
    'item_id',      '88888888-0000-0000-0000-000000000173',
    'description',  'Fresh Trading Item',
    'ordered_qty',  100,
    'received_qty', 100,
    'reject_qty',   0,
    'uom_id',       '77777777-0000-0000-0000-000000000173',
    'unit_price',   250
  ))
) AS rr_id \gset

SELECT lives_ok(
  $$SELECT fn_confirm_receiving_report('$$ || :'rr_id' || $$'::uuid)$$,
  'E1a: confirming the receipt succeeds through the production RPC');

SELECT is(
  (SELECT count(*)::int FROM journal_entries
    WHERE reference_doc_type = 'RR' AND reference_doc_id = :'rr_id'::uuid
      AND status = 'posted'),
  1,
  'E1: confirming a Receiving Report posts exactly one journal (the AUD-073 defect)');

SELECT is(
  (SELECT ROUND(SUM(jel.debit_amount), 2) FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE je.reference_doc_type = 'RR' AND je.reference_doc_id = :'rr_id'::uuid
     AND jel.account_id = 'bbbbbbbb-0000-0000-0000-000000000173'),
  25000.00,
  'E2a: the receipt debits inventory control for 100 x 250.00');

SELECT is(
  (SELECT ROUND(SUM(jel.credit_amount), 2) FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE je.reference_doc_type = 'RR' AND je.reference_doc_id = :'rr_id'::uuid
     AND jel.account_id = 'bbbbbbbb-0000-0000-0000-000000000174'),
  25000.00,
  'E2b: the receipt credits purchase clearing for the same amount');

SELECT is(
  (SELECT ROUND(qty_on_hand, 2) FROM stock_balances
    WHERE warehouse_id = '55555555-0000-0000-0000-000000000173'
      AND item_id = '88888888-0000-0000-0000-000000000173'),
  100.00,
  'E3a: stock on hand is exactly the quantity received');

SELECT is(
  (SELECT ROUND(total_cost, 2) FROM stock_balances
    WHERE warehouse_id = '55555555-0000-0000-0000-000000000173'
      AND item_id = '88888888-0000-0000-0000-000000000173'),
  25000.00,
  'E3b: stock value is exactly the value received');

-- The invariant the whole finding is about, proven on data this test created.
SELECT is(
  (SELECT ROUND(
     COALESCE((SELECT SUM(total_cost) FROM stock_balances
               WHERE company_id = '22222222-0000-0000-0000-000000000173'), 0)
   - COALESCE((SELECT SUM(jel.debit_amount - jel.credit_amount)
               FROM journal_entry_lines jel
               WHERE jel.company_id = '22222222-0000-0000-0000-000000000173'
                 AND jel.account_id = 'bbbbbbbb-0000-0000-0000-000000000173'), 0), 2)),
  0.00,
  'E4: inventory subledger equals the inventory control account exactly');

SELECT is(
  (SELECT count(*)::int FROM inventory_cost_layers
    WHERE company_id = '22222222-0000-0000-0000-000000000173'),
  0,
  'E7: no cost layer is created for a weighted-average item');

-- ── Bill the receipt: 25,000 net + 3,000 VAT = 28,000 payable ───────────────
SELECT fn_save_vendor_bill(
  NULL,
  jsonb_build_object(
    'company_id',  '22222222-0000-0000-0000-000000000173',
    'branch_id',   '33333333-0000-0000-0000-000000000173',
    'supplier_id', '99999999-0000-0000-0000-000000000173',
    'supplier_name_snapshot', 'Fresh Supplier Corporation',
    'supplier_tin_snapshot',  '173-999-888-00000',
    'rr_id',       :'rr_id',
    'bill_date',   '2026-03-12',
    'supplier_invoice_number', 'FRESH-SI-0001',
    'due_date',   '2026-03-27'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',            '88888888-0000-0000-0000-000000000173',
    'description',        'Fresh Trading Item',
    'quantity',           100,
    'unit_price',         250,
    'uom_id',             '77777777-0000-0000-0000-000000000173',
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'net_amount',         25000,
    'input_vat_amount',   3000,
    'total_amount',       28000,
    'expense_account_id', 'bbbbbbbb-0000-0000-0000-000000000174'
  ))
) AS bill_id \gset

SELECT lives_ok(
  $$SELECT fn_approve_vendor_bill('$$ || :'bill_id' || $$'::uuid);
    SELECT fn_post_vendor_bill('$$ || :'bill_id' || $$'::uuid)$$,
  'E5a: the vendor bill approves and posts through the production RPCs');

SELECT is(
  (SELECT ROUND(COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0), 2)
   FROM journal_entry_lines jel
   WHERE jel.company_id = '22222222-0000-0000-0000-000000000173'
     AND jel.account_id = 'bbbbbbbb-0000-0000-0000-000000000174'),
  0.00,
  'E5: billing the receipt clears purchase clearing back to zero — no stranded cost');

SELECT is(
  (SELECT ROUND(COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0), 2)
   FROM journal_entry_lines jel
   WHERE jel.company_id = '22222222-0000-0000-0000-000000000173'
     AND jel.account_id = 'bbbbbbbb-0000-0000-0000-000000000175'),
  28000.00,
  'E6a: accounts payable carries the full VAT-inclusive amount owed');

SELECT is(
  (SELECT ROUND(SUM(debit_amount) - SUM(credit_amount), 2)
   FROM journal_entry_lines
   WHERE company_id = '22222222-0000-0000-0000-000000000173'),
  0.00,
  'E6b: after the complete purchase chain the books balance exactly');

SELECT is(
  (SELECT ROUND(COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0), 2)
   FROM journal_entry_lines jel
   WHERE jel.company_id = '22222222-0000-0000-0000-000000000173'
     AND jel.account_id = 'bbbbbbbb-0000-0000-0000-000000000173'),
  25000.00,
  'E6c: the net position is inventory on hand at cost, matching the subledger');

SELECT * FROM finish();
ROLLBACK;
