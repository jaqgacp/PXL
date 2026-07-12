-- POSTING-RUNTIME-REPAIRS-001
--
-- Regression coverage for runtime-only defects in the inventory and purchasing
-- posting paths:
--   * physical-count variance remains derived (line unit cost + immutable
--     inventory transaction), while stock and the governed JE post correctly;
--   * a transfer between differently-mapped warehouses draws its JE number from
--     the source warehouse branch but leaves the cross-warehouse JE unattributed;
--   * vendor bills may optionally retain a validated receiving-report link, and
--     a purchase return against the linked posted bill completes with a governed,
--     source-linked JE on the return date.
--
-- The fixture is self-contained and rolls back.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(49);

-- ---------------------------------------------------------------------------
-- Identity and company
-- ---------------------------------------------------------------------------

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111131',
  'authenticated', 'authenticated', 'posting-runtime@test.local', '',
  NOW(), NOW(), NOW(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111131","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222231', 'corporation',
  'Posting Runtime Test Corp', 'Trading', '111-222-333-031',
  'non_vat', 'calendar',
  'Unit 31', 'Runtime Bldg', 'Makati', 'Metro Manila', '1231',
  'posting-runtime@test.local', 'Test Signatory', 'President',
  auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES
  (
    '33333333-3333-3333-3333-333333333231',
    '22222222-2222-2222-2222-222222222231',
    'SRC', 'Source Branch', '1 Source St', '',
    'Makati', 'Metro Manila', '1231', auth.uid(), auth.uid()
  ),
  (
    '33333333-3333-3333-3333-333333333232',
    '22222222-2222-2222-2222-222222222231',
    'DST', 'Destination Branch', '2 Destination St', '',
    'Pasig', 'Metro Manila', '1232', auth.uid(), auth.uid()
  );

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
) VALUES (
  '44444444-4444-4444-4444-444444444431',
  '22222222-2222-2222-2222-222222222231',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222231',
  '44444444-4444-4444-4444-444444444431',
  m,
  to_char(make_date(2026, m, 1), 'Mon YYYY'),
  make_date(2026, m, 1),
  (make_date(2026, m, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE,
  false
FROM generate_series(1, 12) AS m;

-- ---------------------------------------------------------------------------
-- Accounting, inventory, and numbering fixtures
-- ---------------------------------------------------------------------------

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active,
  created_by, updated_by
) VALUES
  (
    'aaaaaaaa-0000-0000-0000-000000000531',
    '22222222-2222-2222-2222-222222222231',
    '1310-SRC', 'Inventory - Source', 'asset', 'debit', true, true,
    auth.uid(), auth.uid()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000631',
    '22222222-2222-2222-2222-222222222231',
    '1310-DST', 'Inventory - Destination', 'asset', 'debit', true, true,
    auth.uid(), auth.uid()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000731',
    '22222222-2222-2222-2222-222222222231',
    '5310', 'Inventory Count Variance', 'expense', 'debit', true, true,
    auth.uid(), auth.uid()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000831',
    '22222222-2222-2222-2222-222222222231',
    '2010', 'Accounts Payable', 'liability', 'credit', true, true,
    auth.uid(), auth.uid()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000931',
    '22222222-2222-2222-2222-222222222231',
    '5110', 'Purchases', 'expense', 'debit', true, true,
    auth.uid(), auth.uid()
  );

INSERT INTO company_accounting_config (
  company_id, ap_account_id, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222231',
  'aaaaaaaa-0000-0000-0000-000000000831',
  auth.uid(), auth.uid()
);

INSERT INTO item_categories (
  id, company_id, category_code, category_name,
  inventory_account_id, adj_account_id, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555531',
  '22222222-2222-2222-2222-222222222231',
  'RUNTIME', 'Runtime Inventory',
  'aaaaaaaa-0000-0000-0000-000000000531',
  'aaaaaaaa-0000-0000-0000-000000000731',
  auth.uid(), auth.uid()
);

INSERT INTO units_of_measure (
  id, company_id, uom_code, description, is_base_unit,
  created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555631',
  '22222222-2222-2222-2222-222222222231',
  'EA', 'Each', true, auth.uid(), auth.uid()
);

INSERT INTO items (
  id, company_id, item_code, description, item_type,
  category_id, uom_id, standard_cost,
  cogs_account_id, inventory_account_id, purchase_expense_account_id,
  costing_method, created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666631',
  '22222222-2222-2222-2222-222222222231',
  'RUNTIME-ITEM', 'Runtime Test Item', 'inventory_item',
  '55555555-5555-5555-5555-555555555531',
  '55555555-5555-5555-5555-555555555631',
  10,
  'aaaaaaaa-0000-0000-0000-000000000931',
  'aaaaaaaa-0000-0000-0000-000000000531',
  'aaaaaaaa-0000-0000-0000-000000000931',
  'weighted_average', auth.uid(), auth.uid()
);

INSERT INTO warehouses (
  id, company_id, branch_id, warehouse_code, warehouse_name,
  gl_inventory_account_id, gl_variance_account_id,
  created_by, updated_by
) VALUES
  (
    '77777777-7777-7777-7777-777777777731',
    '22222222-2222-2222-2222-222222222231',
    '33333333-3333-3333-3333-333333333231',
    'SRC-WH', 'Source Warehouse',
    'aaaaaaaa-0000-0000-0000-000000000531',
    'aaaaaaaa-0000-0000-0000-000000000731',
    auth.uid(), auth.uid()
  ),
  (
    '77777777-7777-7777-7777-777777777732',
    '22222222-2222-2222-2222-222222222231',
    '33333333-3333-3333-3333-333333333232',
    'DST-WH', 'Destination Warehouse',
    'aaaaaaaa-0000-0000-0000-000000000631',
    'aaaaaaaa-0000-0000-0000-000000000731',
    auth.uid(), auth.uid()
  );

INSERT INTO number_series (
  company_id, branch_id, document_type_id, document_code, prefix,
  number_length, padding, starting_number, next_number, current_sequence,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222231',
  '33333333-3333-3333-3333-333333333231',
  dt.id, dt.document_code,
  CASE dt.document_code
    WHEN 'JE' THEN 'SRC-JE-'
    WHEN 'VB' THEN 'VB-'
    WHEN 'PRT' THEN 'PRT-'
  END,
  6, 6, 1, 1, 0, true, auth.uid(), auth.uid()
FROM ref_document_types dt
WHERE dt.document_code IN ('JE', 'VB', 'PRT');

INSERT INTO number_series (
  company_id, branch_id, document_type_id, document_code, prefix,
  number_length, padding, starting_number, next_number, current_sequence,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222231',
  '33333333-3333-3333-3333-333333333232',
  dt.id, dt.document_code, 'DST-JE-',
  6, 6, 1, 1, 0, true, auth.uid(), auth.uid()
FROM ref_document_types dt
WHERE dt.document_code = 'JE';

INSERT INTO stock_balances (
  company_id, warehouse_id, item_id,
  qty_on_hand, qty_reserved, total_cost, wac_unit_cost
) VALUES
  (
    '22222222-2222-2222-2222-222222222231',
    '77777777-7777-7777-7777-777777777731',
    '66666666-6666-6666-6666-666666666631',
    10, 0, 100, 10
  ),
  (
    '22222222-2222-2222-2222-222222222231',
    '77777777-7777-7777-7777-777777777732',
    '66666666-6666-6666-6666-666666666631',
    0, 0, 0, 0
  );

CREATE TEMP TABLE t_runtime_ctx (
  key TEXT PRIMARY KEY,
  id UUID NOT NULL
);

-- The repair deliberately does not add a redundant variance-cost column.
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'physical_count_sheet_lines'
      AND column_name = 'variance_cost'
  ),
  'physical-count variance cost remains derived rather than duplicated on the count line'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'vendor_bills'
      AND column_name = 'rr_id'
  ),
  'vendor bills expose the repaired receiving-report link'
);

SELECT is(
  (SELECT is_nullable
   FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'vendor_bills'
     AND column_name = 'rr_id'),
  'YES',
  'the vendor-bill receiving-report link is optional'
);

-- ---------------------------------------------------------------------------
-- Physical count: +2 units at 10.00 = +20.00 derived variance
-- ---------------------------------------------------------------------------

INSERT INTO physical_count_sheets (
  id, company_id, branch_id, warehouse_id,
  count_number, count_date, status, created_by, updated_by
) VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0131',
  '22222222-2222-2222-2222-222222222231',
  '33333333-3333-3333-3333-333333333231',
  '77777777-7777-7777-7777-777777777731',
  'COUNT-RUNTIME-031', '2026-07-10', 'variance_review',
  auth.uid(), auth.uid()
);

INSERT INTO physical_count_sheet_lines (
  id, count_sheet_id, company_id, item_id,
  system_qty, counted_qty, unit_cost, gl_variance_account_id
) VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0231',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0131',
  '22222222-2222-2222-2222-222222222231',
  '66666666-6666-6666-6666-666666666631',
  10, 12, 0,
  'aaaaaaaa-0000-0000-0000-000000000731'
);

SELECT lives_ok(
  $$INSERT INTO t_runtime_ctx (key, id)
    SELECT 'count_je', fn_post_physical_count(
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0131'::UUID
    )$$,
  'a physical count with a nonzero variance posts without referencing a missing column'
);

SELECT is(
  (SELECT unit_cost FROM physical_count_sheet_lines
   WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0231'),
  10::NUMERIC,
  'physical-count posting freezes the applied unit cost on the count line'
);

SELECT is(
  (SELECT total_cost FROM inventory_transactions
   WHERE reference_doc_type = 'INV_COUNT'
     AND reference_doc_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0131'),
  20::NUMERIC,
  'the immutable inventory transaction persists the derived +20.00 variance cost'
);

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
   WHERE warehouse_id = '77777777-7777-7777-7777-777777777731'
     AND item_id = '66666666-6666-6666-6666-666666666631'),
  12::NUMERIC,
  'the positive count variance raises source stock from 10 to 12 units'
);

SELECT is(
  (SELECT total_cost FROM stock_balances
   WHERE warehouse_id = '77777777-7777-7777-7777-777777777731'
     AND item_id = '66666666-6666-6666-6666-666666666631'),
  120::NUMERIC,
  'the positive count variance raises source inventory cost from 100.00 to 120.00'
);

SELECT is(
  (SELECT status FROM physical_count_sheets
   WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0131'),
  'posted',
  'the physical count reaches posted status'
);

SELECT is(
  (SELECT je_number FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'count_je')),
  'SRC-JE-000001',
  'the physical-count JE draws the first governed source-branch JE number'
);

SELECT is(
  (SELECT total_debit FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'count_je')),
  20::NUMERIC,
  'the physical-count JE header records a 20.00 debit'
);

SELECT is(
  (SELECT total_credit FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'count_je')),
  20::NUMERIC,
  'the physical-count JE header records a matching 20.00 credit'
);

SELECT is(
  (SELECT debit_amount FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_runtime_ctx WHERE key = 'count_je')
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000531'),
  20::NUMERIC,
  'the physical-count JE debits inventory by the derived variance cost'
);

SELECT is(
  (SELECT credit_amount FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_runtime_ctx WHERE key = 'count_je')
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000731'),
  20::NUMERIC,
  'the physical-count JE credits the variance account by the derived variance cost'
);

-- ---------------------------------------------------------------------------
-- Stock transfer: 3 units at 10.00 from source to destination
-- ---------------------------------------------------------------------------

INSERT INTO stock_transfers (
  id, company_id, transfer_number, transfer_date,
  from_warehouse_id, to_warehouse_id, status,
  created_by, updated_by
) VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccc0131',
  '22222222-2222-2222-2222-222222222231',
  'STX-RUNTIME-031', '2026-07-11',
  '77777777-7777-7777-7777-777777777731',
  '77777777-7777-7777-7777-777777777732',
  'draft', auth.uid(), auth.uid()
);

INSERT INTO stock_transfer_lines (
  id, transfer_id, company_id, item_id, qty_transferred
) VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccc0231',
  'cccccccc-cccc-cccc-cccc-cccccccc0131',
  '22222222-2222-2222-2222-222222222231',
  '66666666-6666-6666-6666-666666666631',
  3
);

SELECT lives_ok(
  $$INSERT INTO t_runtime_ctx (key, id)
    SELECT 'transfer_je', fn_post_stock_transfer(
      'cccccccc-cccc-cccc-cccc-cccccccc0131'::UUID
    )$$,
  'a stock transfer with different warehouse GL accounts posts successfully'
);

SELECT is(
  (SELECT journal_entry_id FROM stock_transfers
   WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccc0131'),
  (SELECT id FROM t_runtime_ctx WHERE key = 'transfer_je'),
  'the stock transfer retains the JE returned by its posting RPC'
);

SELECT is(
  (SELECT je_number FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'transfer_je')),
  'SRC-JE-000002',
  'the transfer JE number comes from the source warehouse branch series'
);

SELECT is(
  (SELECT branch_id FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'transfer_je')),
  NULL::UUID,
  'the cross-warehouse transfer JE header remains intentionally unattributed'
);

SELECT is(
  (SELECT current_sequence FROM number_series
   WHERE company_id = '22222222-2222-2222-2222-222222222231'
     AND branch_id = '33333333-3333-3333-3333-333333333232'
     AND document_code = 'JE'),
  0::BIGINT,
  'the destination branch JE series is not consumed by the transfer'
);

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
   WHERE warehouse_id = '77777777-7777-7777-7777-777777777731'
     AND item_id = '66666666-6666-6666-6666-666666666631'),
  9::NUMERIC,
  'the transfer removes three units from the source warehouse'
);

SELECT is(
  (SELECT total_cost FROM stock_balances
   WHERE warehouse_id = '77777777-7777-7777-7777-777777777731'
     AND item_id = '66666666-6666-6666-6666-666666666631'),
  90::NUMERIC,
  'the transfer removes 30.00 of cost from the source warehouse'
);

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
   WHERE warehouse_id = '77777777-7777-7777-7777-777777777732'
     AND item_id = '66666666-6666-6666-6666-666666666631'),
  3::NUMERIC,
  'the transfer adds three units to the destination warehouse'
);

SELECT is(
  (SELECT total_cost FROM stock_balances
   WHERE warehouse_id = '77777777-7777-7777-7777-777777777732'
     AND item_id = '66666666-6666-6666-6666-666666666631'),
  30::NUMERIC,
  'the transfer adds 30.00 of cost to the destination warehouse'
);

SELECT is(
  (SELECT debit_amount FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_runtime_ctx WHERE key = 'transfer_je')
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000631'),
  30::NUMERIC,
  'the transfer JE debits the destination warehouse inventory account'
);

SELECT is(
  (SELECT credit_amount FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_runtime_ctx WHERE key = 'transfer_je')
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000531'),
  30::NUMERIC,
  'the transfer JE credits the source warehouse inventory account'
);

-- ---------------------------------------------------------------------------
-- Receiving report, optional vendor-bill link, and purchase return
-- ---------------------------------------------------------------------------

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin,
  registered_address, created_by, updated_by
) VALUES
  (
    '88888888-8888-8888-8888-888888888831',
    '22222222-2222-2222-2222-222222222231',
    'SUP-RUNTIME', 'Runtime Supplier', '777-888-999-031',
    'Supplier Address', auth.uid(), auth.uid()
  ),
  (
    '88888888-8888-8888-8888-888888888832',
    '22222222-2222-2222-2222-222222222231',
    'SUP-OTHER', 'Other Supplier', '777-888-999-032',
    'Other Supplier Address', auth.uid(), auth.uid()
  );

INSERT INTO purchase_orders (
  id, company_id, branch_id, po_number, po_date,
  supplier_id, supplier_name_snapshot, total_amount, status,
  created_by, updated_by
) VALUES (
  '99999999-9999-9999-9999-999999999931',
  '22222222-2222-2222-2222-222222222231',
  '33333333-3333-3333-3333-333333333231',
  'PO-RUNTIME-031', '2026-06-01',
  '88888888-8888-8888-8888-888888888831',
  'Runtime Supplier', 50, 'fully_received',
  auth.uid(), auth.uid()
);

INSERT INTO purchase_order_lines (
  id, po_id, company_id, line_number, item_id,
  description, quantity, uom_id, unit_price, total_amount, created_by
) VALUES (
  '99999999-9999-9999-9999-999999999932',
  '99999999-9999-9999-9999-999999999931',
  '22222222-2222-2222-2222-222222222231',
  1, '66666666-6666-6666-6666-666666666631',
  'Runtime Test Item', 5,
  '55555555-5555-5555-5555-555555555631',
  10, 50, auth.uid()
);

INSERT INTO receiving_reports (
  id, company_id, branch_id, rr_number, rr_date, po_id,
  supplier_id, supplier_name_snapshot, status,
  confirmed_by, confirmed_at, created_by, updated_by
) VALUES
  (
    '99999999-9999-9999-9999-999999999933',
    '22222222-2222-2222-2222-222222222231',
    '33333333-3333-3333-3333-333333333231',
    'RR-RECEIVED-031', '2026-06-05',
    '99999999-9999-9999-9999-999999999931',
    '88888888-8888-8888-8888-888888888831',
    'Runtime Supplier', 'received', auth.uid(), NOW(), auth.uid(), auth.uid()
  ),
  (
    '99999999-9999-9999-9999-999999999935',
    '22222222-2222-2222-2222-222222222231',
    '33333333-3333-3333-3333-333333333231',
    'RR-DRAFT-031', '2026-06-06',
    '99999999-9999-9999-9999-999999999931',
    '88888888-8888-8888-8888-888888888831',
    'Runtime Supplier', 'draft', NULL, NULL, auth.uid(), auth.uid()
  ),
  (
    '99999999-9999-9999-9999-999999999936',
    '22222222-2222-2222-2222-222222222231',
    '33333333-3333-3333-3333-333333333231',
    'RR-NO-BILL-031', '2026-06-07',
    '99999999-9999-9999-9999-999999999931',
    '88888888-8888-8888-8888-888888888831',
    'Runtime Supplier', 'received', auth.uid(), NOW(), auth.uid(), auth.uid()
  );

INSERT INTO receiving_report_lines (
  id, rr_id, company_id, po_line_id, line_number, item_id,
  description, ordered_qty, received_qty, reject_qty,
  uom_id, unit_price, created_by
) VALUES
  (
    '99999999-9999-9999-9999-999999999934',
    '99999999-9999-9999-9999-999999999933',
    '22222222-2222-2222-2222-222222222231',
    '99999999-9999-9999-9999-999999999932',
    1, '66666666-6666-6666-6666-666666666631',
    'Runtime Test Item', 5, 5, 0,
    '55555555-5555-5555-5555-555555555631',
    10, auth.uid()
  ),
  (
    '99999999-9999-9999-9999-999999999937',
    '99999999-9999-9999-9999-999999999936',
    '22222222-2222-2222-2222-222222222231',
    '99999999-9999-9999-9999-999999999932',
    1, '66666666-6666-6666-6666-666666666631',
    'Runtime Test Item', 5, 5, 0,
    '55555555-5555-5555-5555-555555555631',
    10, auth.uid()
  );

SELECT throws_like(
  $$SELECT fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', '22222222-2222-2222-2222-222222222231',
        'branch_id', '33333333-3333-3333-3333-333333333231',
        'supplier_id', '88888888-8888-8888-8888-888888888831',
        'supplier_name_snapshot', 'Runtime Supplier',
        'supplier_invoice_number', 'DRAFT-RR-REJECT',
        'bill_date', '2026-06-10',
        'rr_id', '99999999-9999-9999-9999-999999999935'
      ),
      jsonb_build_array(jsonb_build_object(
        'description', 'Runtime Test Item',
        'item_id', '66666666-6666-6666-6666-666666666631',
        'quantity', 1, 'unit_price', 10,
        'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
        'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000931'
      ))
    )$$,
  '%must be received and belong to the same company and supplier%',
  'fn_save_vendor_bill rejects an RR that is not received'
);

SELECT throws_like(
  $$SELECT fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', '22222222-2222-2222-2222-222222222231',
        'branch_id', '33333333-3333-3333-3333-333333333231',
        'supplier_id', '88888888-8888-8888-8888-888888888832',
        'supplier_name_snapshot', 'Other Supplier',
        'supplier_invoice_number', 'WRONG-SUPPLIER-REJECT',
        'bill_date', '2026-06-10',
        'rr_id', '99999999-9999-9999-9999-999999999933'
      ),
      jsonb_build_array(jsonb_build_object(
        'description', 'Runtime Test Item',
        'item_id', '66666666-6666-6666-6666-666666666631',
        'quantity', 1, 'unit_price', 10,
        'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
        'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000931'
      ))
    )$$,
  '%must be received and belong to the same company and supplier%',
  'fn_save_vendor_bill rejects an RR belonging to another supplier'
);

SELECT lives_ok(
  $$INSERT INTO t_runtime_ctx (key, id)
    SELECT 'unlinked_vb', fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', '22222222-2222-2222-2222-222222222231',
        'branch_id', '33333333-3333-3333-3333-333333333231',
        'supplier_id', '88888888-8888-8888-8888-888888888831',
        'supplier_name_snapshot', 'Runtime Supplier',
        'supplier_invoice_number', 'UNLINKED-VB-031',
        'bill_date', '2026-06-10'
      ),
      jsonb_build_array(jsonb_build_object(
        'description', 'Unlinked purchase',
        'item_id', '66666666-6666-6666-6666-666666666631',
        'quantity', 1, 'unit_price', 10,
        'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
        'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000931'
      ))
    )$$,
  'fn_save_vendor_bill still accepts a bill without an RR link'
);

SELECT is(
  (SELECT rr_id FROM vendor_bills
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'unlinked_vb')),
  NULL::UUID,
  'an omitted optional RR remains NULL on the saved vendor bill'
);

SELECT lives_ok(
  $$INSERT INTO t_runtime_ctx (key, id)
    SELECT 'linked_vb', fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', '22222222-2222-2222-2222-222222222231',
        'branch_id', '33333333-3333-3333-3333-333333333231',
        'supplier_id', '88888888-8888-8888-8888-888888888831',
        'supplier_name_snapshot', 'Runtime Supplier',
        'supplier_tin_snapshot', '777-888-999-031',
        'supplier_invoice_number', 'LINKED-VB-031',
        'bill_date', '2026-06-10',
        'rr_id', '99999999-9999-9999-9999-999999999933'
      ),
      jsonb_build_array(jsonb_build_object(
        'description', 'Runtime Test Item',
        'item_id', '66666666-6666-6666-6666-666666666631',
        'uom_id', '55555555-5555-5555-5555-555555555631',
        'quantity', 5, 'unit_price', 10,
        'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
        'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000931'
      ))
    )$$,
  'fn_save_vendor_bill accepts a received RR for the same company and supplier'
);

SELECT is(
  (SELECT rr_id FROM vendor_bills
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'linked_vb')),
  '99999999-9999-9999-9999-999999999933'::UUID,
  'the validated RR link is persisted on vendor-bill insert'
);

SELECT lives_ok(
  format(
    'SELECT fn_approve_vendor_bill(%L); SELECT fn_post_vendor_bill(%L)',
    (SELECT id FROM t_runtime_ctx WHERE key = 'linked_vb'),
    (SELECT id FROM t_runtime_ctx WHERE key = 'linked_vb')
  ),
  'the RR-linked vendor bill approves and posts'
);

SELECT is(
  (SELECT rr_id FROM vendor_bills
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'linked_vb')),
  '99999999-9999-9999-9999-999999999933'::UUID,
  'the RR link remains durable after vendor-bill posting'
);

SELECT is(
  (SELECT status FROM vendor_bills
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'linked_vb')),
  'posted',
  'the linked vendor bill is available as the posted purchase-return source'
);

INSERT INTO purchase_returns (
  id, company_id, branch_id, return_number, return_date,
  rr_id, supplier_id, supplier_name_snapshot, status,
  created_by, updated_by
) VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddd0131',
  '22222222-2222-2222-2222-222222222231',
  '33333333-3333-3333-3333-333333333231',
  'PR-NO-BILL-031', '2026-06-19',
  '99999999-9999-9999-9999-999999999936',
  '88888888-8888-8888-8888-888888888831',
  'Runtime Supplier', 'shipped', auth.uid(), auth.uid()
);

INSERT INTO purchase_return_lines (
  id, return_id, company_id, rr_line_id, line_number, item_id,
  description, max_qty, return_qty, uom_id, unit_price, reason, created_by
) VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddd0231',
  'dddddddd-dddd-dddd-dddd-dddddddd0131',
  '22222222-2222-2222-2222-222222222231',
  '99999999-9999-9999-9999-999999999937',
  1, '66666666-6666-6666-6666-666666666631',
  'Runtime Test Item', 5, 1,
  '55555555-5555-5555-5555-555555555631',
  10, 'No linked bill', auth.uid()
);

SELECT throws_like(
  $$SELECT fn_complete_purchase_return(
      'dddddddd-dddd-dddd-dddd-dddddddd0131'::UUID
    )$$,
  '%no linked posted vendor bill%',
  'purchase-return completion fails closed when the RR has no linked posted bill'
);

SELECT lives_ok(
  $$INSERT INTO t_runtime_ctx (key, id)
    SELECT 'purchase_return', fn_save_purchase_return(
      NULL,
      jsonb_build_object(
        'company_id', '22222222-2222-2222-2222-222222222231',
        'branch_id', '33333333-3333-3333-3333-333333333231',
        'rr_id', '99999999-9999-9999-9999-999999999933',
        'return_date', '2026-06-20',
        'remarks', 'Runtime repair regression'
      ),
      jsonb_build_array(jsonb_build_object(
        'rr_line_id', '99999999-9999-9999-9999-999999999934',
        'item_id', '66666666-6666-6666-6666-666666666631',
        'description', 'Runtime Test Item',
        'max_qty', 5,
        'return_qty', 2,
        'uom_id', '55555555-5555-5555-5555-555555555631',
        'unit_price', 10,
        'reason', 'Damaged'
      ))
    )$$,
  'a purchase return can be created from the received RR'
);

SELECT lives_ok(
  format(
    'SELECT fn_ship_purchase_return(%L)',
    (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return')
  ),
  'the purchase return can be shipped before completion'
);

SELECT lives_ok(
  format(
    'SELECT fn_complete_purchase_return(%L)',
    (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return')
  ),
  'purchase-return completion no longer errors on the restored vendor-bill RR link'
);

INSERT INTO t_runtime_ctx (key, id)
SELECT 'purchase_return_je', journal_entry_id
FROM purchase_returns
WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return');

SELECT is(
  (SELECT status FROM purchase_returns
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return')),
  'completed',
  'the shipped purchase return reaches completed status'
);

SELECT isnt(
  (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je'),
  NULL::UUID,
  'the completed return retains its reversing journal entry'
);

SELECT is(
  (SELECT je_number FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  'SRC-JE-000003',
  'the purchase-return JE uses the governed source-branch JE series'
);

SELECT is(
  (SELECT je_date FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  '2026-06-20'::DATE,
  'the purchase-return JE uses the return date instead of the execution date'
);

SELECT is(
  (SELECT fp.start_date
   FROM journal_entries je
   JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
   WHERE je.id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  '2026-06-01'::DATE,
  'the purchase-return JE resolves the fiscal period from the return date'
);

SELECT is(
  (SELECT reference_doc_type FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  'PR',
  'the purchase-return JE uses the governed PR source type'
);

SELECT is(
  (SELECT reference_doc_id FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return'),
  'the purchase-return JE links directly back to its source row'
);

SELECT is(
  (SELECT total_debit FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  20::NUMERIC,
  'the purchase-return JE header records the 20.00 reversal debit'
);

SELECT is(
  (SELECT total_credit FROM journal_entries
   WHERE id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')),
  20::NUMERIC,
  'the purchase-return JE header records the matching 20.00 reversal credit'
);

SELECT is(
  (SELECT debit_amount FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000831'),
  20::NUMERIC,
  'the purchase-return JE debits AP for the returned goods'
);

SELECT is(
  (SELECT credit_amount FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_runtime_ctx WHERE key = 'purchase_return_je')
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000931'),
  20::NUMERIC,
  'the purchase-return JE credits the matched purchase expense account'
);

SELECT * FROM finish();
ROLLBACK;
