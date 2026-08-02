-- Delivery Plan Phase 3 / PAD-002 proof on FRESH data.
--
-- This test does not trust or inspect the canonical/demo company. It creates a
-- new tenant, calendar, chart, mappings, parties, warehouse, item, and bank
-- account, then drives the current opening-balance production RPCs end to end.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(31);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111174',
        'authenticated', 'authenticated', 'opening-e2e@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111174","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-0000-0000-0000-000000000174', 'corporation',
        'Fresh Cutover Trading Inc', 'Wholesale Trading', '174-222-333-000',
        'vat', 'calendar', 'Unit 8 Fresh Building', '', 'Makati', 'Metro Manila', '1200',
        'opening-e2e@test.local', 'Ana Reyes', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('33333333-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174', 'HO', 'Head Office',
        'Unit 8 Fresh Building', '', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        'FY2025', '2025-01-01', '2025-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-0000-0000-0000-000000000174',
       '44444444-0000-0000-0000-000000000174', m,
       to_char(make_date(2025, m, 1), 'Mon YYYY'), make_date(2025, m, 1),
       (make_date(2025, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000174', '22222222-0000-0000-0000-000000000174',
   '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000175', '22222222-0000-0000-0000-000000000174',
   '1100', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000176', '22222222-0000-0000-0000-000000000174',
   '1200', 'Merchandise Inventory', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000177', '22222222-0000-0000-0000-000000000174',
   '1300', 'Prepaid Expenses', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000178', '22222222-0000-0000-0000-000000000174',
   '2010', 'Accounts Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000179', '22222222-0000-0000-0000-000000000174',
   '3010', 'Opening Equity', 'equity', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id, inventory_account_id,
  default_cash_account_id, created_by, updated_by
) VALUES (
  '22222222-0000-0000-0000-000000000174',
  'aaaaaaaa-0000-0000-0000-000000000175',
  'aaaaaaaa-0000-0000-0000-000000000178',
  'aaaaaaaa-0000-0000-0000-000000000176',
  'aaaaaaaa-0000-0000-0000-000000000174', auth.uid(), auth.uid()
);

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, default_tax_type, is_active,
                       created_by, updated_by)
VALUES ('55555555-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        'CUS-OPEN', 'Fresh Opening Customer Inc', '174-555-111-00000',
        'Makati, Metro Manila', 'Makati, Metro Manila', 'vat_registered', true, auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, default_tax_type, is_active,
                       created_by, updated_by)
VALUES ('66666666-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        'SUP-OPEN', 'Fresh Opening Supplier Inc', '174-666-111-00000',
        'Taguig, Metro Manila', 'vat_registered', true, auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        is_active, created_by, updated_by)
VALUES ('77777777-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        '33333333-0000-0000-0000-000000000174',
        'WH-OPEN', 'Opening Warehouse', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name,
                             is_active, created_by, updated_by)
VALUES ('88888888-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        'OPEN', 'Opening Goods', true, auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description,
                              is_active, created_by, updated_by)
VALUES ('99999999-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        'PC', 'Piece', true, auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type,
                   category_id, uom_id, costing_method, inventory_account_id,
                   is_active, created_by, updated_by)
VALUES ('bbbbbbbb-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        'OPEN-ITEM', 'Opening Inventory Item', 'inventory_item',
        '88888888-0000-0000-0000-000000000174',
        '99999999-0000-0000-0000-000000000174',
        'weighted_average', 'aaaaaaaa-0000-0000-0000-000000000176',
        true, auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, branch_id, bank_name, bank_branch,
                           account_number, account_name, account_type, gl_account_id,
                           opening_balance, is_active, created_by, updated_by)
VALUES ('cccccccc-0000-0000-0000-000000000174',
        '22222222-0000-0000-0000-000000000174',
        '33333333-0000-0000-0000-000000000174',
        'Fresh Bank', 'Makati', '000011112222', 'Fresh Cutover Trading Inc',
        'checking', 'aaaaaaaa-0000-0000-0000-000000000174', 0, true,
        auth.uid(), auth.uid());

SELECT is(
  (SELECT count(*)::int FROM account_mapping
   WHERE company_id = '22222222-0000-0000-0000-000000000174'
     AND key_code IN ('AR_TRADE', 'AP_TRADE', 'INVENTORY_CONTROL')),
  3,
  'E0: the fresh company projects all three governed subledger control mappings');

SELECT is(
  (SELECT count(*)::int FROM ref_posting_source_types
   WHERE document_type = 'OPENING' AND source_table = 'opening_balance_batches'::regclass
     AND is_active),
  1,
  'E1: OPENING is registered as a governed posting source');

SELECT fn_save_opening_balance(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-0000-0000-0000-000000000174',
    'branch_id', '33333333-0000-0000-0000-000000000174',
    'batch_number', 'OB-2025-001', 'cutover_date', '2025-12-31',
    'description', 'Fresh-company opening balances'
  ),
  jsonb_build_array(
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000177',
      'description', 'Prepaid expenses', 'debit_amount', 10000, 'credit_amount', 0),
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000179',
      'description', 'Opening equity', 'debit_amount', 0, 'credit_amount', 70000)
  ),
  jsonb_build_array(jsonb_build_object(
    'customer_id', '55555555-0000-0000-0000-000000000174',
    'legacy_invoice_number', 'LEG-SI-001', 'invoice_date', '2025-12-15',
    'due_date', '2026-01-15', 'original_amount', 20000
  )),
  jsonb_build_array(jsonb_build_object(
    'supplier_id', '66666666-0000-0000-0000-000000000174',
    'legacy_bill_number', 'LEG-VB-001', 'supplier_invoice_number', 'SUP-INV-001',
    'bill_date', '2025-12-10', 'due_date', '2026-01-10', 'original_amount', 40000
  )),
  jsonb_build_array(jsonb_build_object(
    'warehouse_id', '77777777-0000-0000-0000-000000000174',
    'item_id', 'bbbbbbbb-0000-0000-0000-000000000174',
    'quantity', 100, 'unit_cost', 300
  )),
  jsonb_build_array(jsonb_build_object(
    'bank_account_id', 'cccccccc-0000-0000-0000-000000000174', 'amount', 50000
  ))
) AS batch_id \gset

SELECT is(
  (SELECT status FROM opening_balance_batches WHERE id = :'batch_id'::uuid),
  'draft', 'E2: the production save RPC creates a draft cut-over document');

SELECT is(
  (SELECT (fn_opening_balance_summary(:'batch_id'::uuid)->>'variance')::numeric),
  0::numeric, 'E3: derived AR, AP, inventory, and bank controls balance by construction');

UPDATE opening_balance_gl_lines
SET account_id = 'aaaaaaaa-0000-0000-0000-000000000175'
WHERE batch_id = :'batch_id'::uuid AND credit_amount > 0;

SELECT throws_ok(
  $$SELECT fn_post_opening_balance('$$ || :'batch_id' || $$'::uuid)$$,
  'P0001',
  'AR, AP, inventory, and bank control accounts are derived from detail and cannot be entered as other GL lines',
  'E4: a manually entered control account cannot be posted');

-- Restore the intended equity line after proving the control-account guard.
UPDATE opening_balance_gl_lines
SET account_id = 'aaaaaaaa-0000-0000-0000-000000000179'
WHERE batch_id = :'batch_id'::uuid AND credit_amount > 0;

SELECT lives_ok(
  $$SELECT fn_post_opening_balance('$$ || :'batch_id' || $$'::uuid)$$,
  'E5: the production posting RPC accepts the balanced fresh-company cut-over');

SELECT is(
  (SELECT count(*)::int FROM journal_entries
   WHERE reference_doc_type = 'OPENING' AND reference_doc_id = :'batch_id'::uuid
     AND status = 'posted' AND entry_class = 'opening'),
  1, 'E6: the cut-over posts exactly one opening journal through the sealed doorway');

SELECT is(
  (SELECT total_debit FROM journal_entries WHERE id =
    (SELECT journal_entry_id FROM opening_balance_batches WHERE id = :'batch_id'::uuid)),
  110000.00::numeric, 'E7a: the opening journal debit total is exact');

SELECT is(
  (SELECT total_credit FROM journal_entries WHERE id =
    (SELECT journal_entry_id FROM opening_balance_batches WHERE id = :'batch_id'::uuid)),
  110000.00::numeric, 'E7b: the opening journal credit total is exact');

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
   WHERE je_id = (SELECT journal_entry_id FROM opening_balance_batches WHERE id = :'batch_id'::uuid)),
  6, 'E8: two other-GL lines plus four derived controls are persisted');

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
   WHERE warehouse_id = '77777777-0000-0000-0000-000000000174'
     AND item_id = 'bbbbbbbb-0000-0000-0000-000000000174'),
  100.0000::numeric, 'E9a: opening inventory quantity reaches the live stock subledger');

SELECT is(
  (SELECT total_cost FROM stock_balances
   WHERE warehouse_id = '77777777-0000-0000-0000-000000000174'
     AND item_id = 'bbbbbbbb-0000-0000-0000-000000000174'),
  30000.00::numeric, 'E9b: opening inventory value reaches the live stock subledger');

SELECT is(
  (SELECT round(
    (SELECT sum(total_cost) FROM stock_balances
      WHERE company_id = '22222222-0000-0000-0000-000000000174')
    - (SELECT sum(debit_amount - credit_amount) FROM journal_entry_lines
       WHERE company_id = '22222222-0000-0000-0000-000000000174'
         AND account_id = 'aaaaaaaa-0000-0000-0000-000000000176'), 2)),
  0.00::numeric, 'E10: inventory subledger ties to its control account at zero variance');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
    '22222222-0000-0000-0000-000000000174', '2025-12-31', NULL)),
  20000.00::numeric, 'E11a: opening invoices appear in AR aging');

SELECT is(
  (SELECT round(
    (SELECT sum(balance_due) FROM fn_ar_aging_asof(
      '22222222-0000-0000-0000-000000000174', '2025-12-31', NULL))
    - (SELECT sum(debit_amount - credit_amount) FROM journal_entry_lines
       WHERE company_id = '22222222-0000-0000-0000-000000000174'
         AND account_id = 'aaaaaaaa-0000-0000-0000-000000000175'), 2)),
  0.00::numeric, 'E11b: opening AR ties to the AR control account at zero variance');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
    '22222222-0000-0000-0000-000000000174', '2025-12-31', NULL)),
  40000.00::numeric, 'E12a: opening bills appear in AP aging');

SELECT is(
  (SELECT round(
    (SELECT sum(balance_due) FROM fn_ap_aging_asof(
      '22222222-0000-0000-0000-000000000174', '2025-12-31', NULL))
    - (SELECT sum(credit_amount - debit_amount) FROM journal_entry_lines
       WHERE company_id = '22222222-0000-0000-0000-000000000174'
         AND account_id = 'aaaaaaaa-0000-0000-0000-000000000178'), 2)),
  0.00::numeric, 'E12b: opening AP ties to the AP control account at zero variance');

SELECT is(
  (SELECT round(
    (SELECT sum(amount) FROM opening_balance_bank_lines
      WHERE batch_id = :'batch_id'::uuid)
    - (SELECT sum(debit_amount - credit_amount) FROM journal_entry_lines
       WHERE company_id = '22222222-0000-0000-0000-000000000174'
         AND account_id = 'aaaaaaaa-0000-0000-0000-000000000174'), 2)),
  0.00::numeric, 'E13: opening bank detail ties to its mapped GL account at zero variance');

SELECT is(
  (SELECT count(*)::int FROM vw_customer_ledger
   WHERE company_id = '22222222-0000-0000-0000-000000000174'
     AND source_doc_type = 'OPENING'),
  1, 'E14a: the customer ledger exposes the opening invoice');

SELECT is(
  (SELECT count(*)::int FROM vw_supplier_ledger
   WHERE company_id = '22222222-0000-0000-0000-000000000174'
     AND source_doc_type = 'OPENING'),
  1, 'E14b: the supplier ledger exposes the opening bill');

SELECT is(
  (SELECT count(*)::int FROM inventory_events
   WHERE company_id = '22222222-0000-0000-0000-000000000174'),
  0, 'E15: dormant IA-5 remains untouched');

SELECT throws_ok(
  $$UPDATE opening_balance_gl_lines SET description = 'mutated'
    WHERE batch_id = '$$ || :'batch_id' || $$'::uuid$$,
  'P0001',
  'Posted opening-balance detail is immutable; reverse the batch instead',
  'E16: posted cut-over detail is immutable');

SELECT is(
  fn_post_opening_balance(:'batch_id'::uuid),
  (SELECT journal_entry_id FROM opening_balance_batches WHERE id = :'batch_id'::uuid),
  'E17: retrying post is idempotent');

SELECT lives_ok(
  $$SELECT fn_reverse_opening_balance('$$ || :'batch_id' || $$'::uuid, '2025-12-31',
    'Correct legacy cut-over before operations')$$,
  'E18: correction uses the explicit reversal RPC');

SELECT is(
  (SELECT status FROM opening_balance_batches WHERE id = :'batch_id'::uuid),
  'reversed', 'E19: the batch records the reversal rather than mutating posted facts');

SELECT is(
  (SELECT status FROM journal_entries WHERE id =
    (SELECT journal_entry_id FROM opening_balance_batches WHERE id = :'batch_id'::uuid)),
  'reversed', 'E20: the original opening journal is marked reversed');

SELECT is(
  (SELECT round(sum(debit_amount - credit_amount), 2) FROM journal_entry_lines
   WHERE company_id = '22222222-0000-0000-0000-000000000174'),
  0.00::numeric, 'E21: original and reversal journals net to zero');

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
   WHERE warehouse_id = '77777777-0000-0000-0000-000000000174'
     AND item_id = 'bbbbbbbb-0000-0000-0000-000000000174'),
  0.0000::numeric, 'E22: reversal removes the opening stock quantity');

SELECT is(
  (SELECT count(*)::int FROM fn_ar_aging_asof(
    '22222222-0000-0000-0000-000000000174', '2025-12-31', NULL)),
  0, 'E23a: reversed opening invoices leave AR aging');

SELECT is(
  (SELECT count(*)::int FROM fn_ap_aging_asof(
    '22222222-0000-0000-0000-000000000174', '2025-12-31', NULL)),
  0, 'E23b: reversed opening bills leave AP aging');

SELECT is(
  (SELECT count(*)::int FROM inventory_events
   WHERE company_id = '22222222-0000-0000-0000-000000000174'),
  0, 'E24: reversal also preserves IA-5 dormancy');

SELECT * FROM finish();
ROLLBACK;
