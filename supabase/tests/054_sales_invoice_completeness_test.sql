-- PXL-AUD-053
-- Sales Invoice completeness coverage:
--   * VAT-inclusive commercial prices are persisted and computed server-side.
--   * Supported operational dimensions are captured from master data.
--   * Inventory item lines post COGS and Inventory, reduce stock, and retain
--     authoritative inventory cost evidence.
--   * Service lines do not create inventory movements.
--   * Voiding a posted SI reverses accounting/tax and restores inventory stock.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(22);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111154',
  'authenticated', 'authenticated', 'aud053@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111154","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222154', 'corporation',
  'AUD053 Sales Invoice Corp', 'Trading', '111-222-333-00154',
  'vat', 'calendar', 'Unit 54', 'Audit Bldg', 'Makati', 'Metro Manila', '1254',
  'aud053@test.local', 'Audit Signatory', 'President', auth.uid(), auth.uid()
);

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES (
  '11111111-1111-1111-1111-111111111154',
  '22222222-2222-2222-2222-222222222154',
  'owner',
  '11111111-1111-1111-1111-111111111154'
)
ON CONFLICT DO NOTHING;

INSERT INTO branches (
  id, company_id, branch_code, branch_name, tin_branch_code,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333154',
  '22222222-2222-2222-2222-222222222154', 'HO', 'Head Office', '00154',
  'Unit 54', 'Audit Bldg', 'Makati', 'Metro Manila', '1254',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444154',
  '22222222-2222-2222-2222-222222222154',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222154',
  '44444444-4444-4444-4444-444444444154',
  m,
  to_char(make_date(2026, m, 1), 'Mon YYYY'),
  make_date(2026, m, 1),
  (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
  false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active,
  created_by, updated_by
) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000154', '22222222-2222-2222-2222-222222222154', '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000254', '22222222-2222-2222-2222-222222222154', '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000354', '22222222-2222-2222-2222-222222222154', '4010', 'Product Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000454', '22222222-2222-2222-2222-222222222154', '4020', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000554', '22222222-2222-2222-2222-222222222154', '1310', 'Inventory', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000654', '22222222-2222-2222-2222-222222222154', '5010', 'Cost of Goods Sold', 'expense', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000754', '22222222-2222-2222-2222-222222222154', '5090', 'Inventory Variance', 'expense', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, vat_payable_account_id, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222154',
  'aaaaaaaa-0000-0000-0000-000000000154',
  'aaaaaaaa-0000-0000-0000-000000000254',
  auth.uid(), auth.uid()
);

INSERT INTO departments (
  id, company_id, branch_id, department_code, department_name, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555154',
  '22222222-2222-2222-2222-222222222154',
  '33333333-3333-3333-3333-333333333154',
  'SALES', 'Sales Department', auth.uid(), auth.uid()
);

INSERT INTO cost_centers (
  id, company_id, branch_id, department_id, cost_center_code, cost_center_name, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555254',
  '22222222-2222-2222-2222-222222222154',
  '33333333-3333-3333-3333-333333333154',
  '55555555-5555-5555-5555-555555555154',
  'CC-SALES', 'Sales Cost Center', auth.uid(), auth.uid()
);

INSERT INTO employees (
  id, company_id, branch_id, employee_number, last_name, first_name,
  department_id, job_title, hire_date, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555354',
  '22222222-2222-2222-2222-222222222154',
  '33333333-3333-3333-3333-333333333154',
  'EMP-053', 'Owner', 'Account',
  '55555555-5555-5555-5555-555555555154',
  'Account Owner', '2026-01-01', auth.uid(), auth.uid()
);

INSERT INTO item_categories (
  id, company_id, category_code, category_name,
  inventory_account_id, adj_account_id, created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666154',
  '22222222-2222-2222-2222-222222222154',
  'AUD053', 'AUD053 Inventory',
  'aaaaaaaa-0000-0000-0000-000000000554',
  'aaaaaaaa-0000-0000-0000-000000000754',
  auth.uid(), auth.uid()
);

INSERT INTO units_of_measure (
  id, company_id, uom_code, description, is_base_unit, created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666254',
  '22222222-2222-2222-2222-222222222154',
  'EA', 'Each', true, auth.uid(), auth.uid()
);

INSERT INTO items (
  id, company_id, item_code, description, item_type,
  category_id, uom_id, standard_selling_price, standard_cost,
  default_sales_vat_id, sales_account_id, cogs_account_id,
  inventory_account_id, costing_method, created_by, updated_by
) VALUES
  (
    '66666666-6666-6666-6666-666666666354',
    '22222222-2222-2222-2222-222222222154',
    'INV-AUD053', 'Inventory Item', 'inventory_item',
    '66666666-6666-6666-6666-666666666154',
    '66666666-6666-6666-6666-666666666254',
    1120, 600,
    (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'aaaaaaaa-0000-0000-0000-000000000354',
    'aaaaaaaa-0000-0000-0000-000000000654',
    'aaaaaaaa-0000-0000-0000-000000000554',
    'weighted_average', auth.uid(), auth.uid()
  ),
  (
    '66666666-6666-6666-6666-666666666454',
    '22222222-2222-2222-2222-222222222154',
    'SVC-AUD053', 'Service Item', 'service',
    '66666666-6666-6666-6666-666666666154',
    '66666666-6666-6666-6666-666666666254',
    560, 0,
    (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'aaaaaaaa-0000-0000-0000-000000000454',
    NULL, NULL,
    NULL, auth.uid(), auth.uid()
  );

INSERT INTO warehouses (
  id, company_id, branch_id, warehouse_code, warehouse_name,
  gl_inventory_account_id, gl_variance_account_id, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777154',
  '22222222-2222-2222-2222-222222222154',
  '33333333-3333-3333-3333-333333333154',
  'MAIN', 'Main Warehouse',
  'aaaaaaaa-0000-0000-0000-000000000554',
  'aaaaaaaa-0000-0000-0000-000000000754',
  auth.uid(), auth.uid()
);

INSERT INTO stock_balances (
  company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost
) VALUES (
  '22222222-2222-2222-2222-222222222154',
  '77777777-7777-7777-7777-777777777154',
  '66666666-6666-6666-6666-666666666354',
  5, 3000, 600
);

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin, tin_branch_code,
  registered_address, delivery_address, created_by, updated_by
) VALUES (
  '88888888-8888-8888-8888-888888888154',
  '22222222-2222-2222-2222-222222222154', 'CUS-AUD053',
  'AUD053 Customer Inc', '444-555-666-00154', '00154',
  'Customer HQ', 'Customer HQ', auth.uid(), auth.uid()
);

INSERT INTO number_series (
  company_id, branch_id, document_type_id, document_code, prefix,
  number_length, padding, starting_number, next_number, current_sequence,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222154',
  '33333333-3333-3333-3333-333333333154',
  rdt.id, rdt.document_code,
  rdt.document_code || '-AUD053-',
  6, 6, 1, 1, 0, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'JE');

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222154',
    'branch_id', '33333333-3333-3333-3333-333333333154',
    'date', '2026-01-20',
    'customer_id', '88888888-8888-8888-8888-888888888154',
    'customer_name_snapshot', 'AUD053 Customer Inc',
    'customer_tin_snapshot', '444-555-666-00154',
    'customer_address_snapshot', 'Customer HQ',
    'vat_price_basis', 'inclusive',
    'department_id', '55555555-5555-5555-5555-555555555154',
    'cost_center_id', '55555555-5555-5555-5555-555555555254',
    'warehouse_id', '77777777-7777-7777-7777-777777777154',
    'salesperson_id', '55555555-5555-5555-5555-555555555354',
    'account_owner_id', '55555555-5555-5555-5555-555555555354'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'item_id', '66666666-6666-6666-6666-666666666354',
      'description', 'Inventory item sale',
      'quantity', 1,
      'unit_price', 1120,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
    ),
    jsonb_build_object(
      'item_id', '66666666-6666-6666-6666-666666666454',
      'description', 'Service item sale',
      'quantity', 1,
      'unit_price', 560,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
    )
  )
);

SELECT results_eq(
  $q$SELECT vat_price_basis, total_taxable_amount, total_vat_amount, total_amount
     FROM sales_invoices
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')$q$,
  $$VALUES ('inclusive'::text, 1500.00::numeric, 180.00::numeric, 1680.00::numeric)$$,
  'SI persists VAT-inclusive basis and computes net/VAT/gross from entered commercial prices'
);

SELECT results_eq(
  $q$SELECT line_number, net_amount, vat_amount, total_amount
     FROM sales_invoice_lines
     WHERE sales_invoice_id = (SELECT id FROM t_ctx WHERE key = 'si')
     ORDER BY line_number$q$,
  $$VALUES
      (1, 1000.00::numeric, 120.00::numeric, 1120.00::numeric),
      (2,  500.00::numeric,  60.00::numeric,  560.00::numeric)$$,
  'SI line totals are rebuilt by the authoritative server calculation'
);

SELECT results_eq(
  $q$SELECT department_id, cost_center_id, warehouse_id, salesperson_id, account_owner_id
     FROM sales_invoices
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')$q$,
  $$VALUES (
      '55555555-5555-5555-5555-555555555154'::uuid,
      '55555555-5555-5555-5555-555555555254'::uuid,
      '77777777-7777-7777-7777-777777777154'::uuid,
      '55555555-5555-5555-5555-555555555354'::uuid,
      '55555555-5555-5555-5555-555555555354'::uuid
  )$$,
  'SI header stores supported operational dimensions from master data'
);

SELECT results_eq(
  $q$SELECT line_number, warehouse_id, department_id, cost_center_id, salesperson_id
     FROM sales_invoice_lines
     WHERE sales_invoice_id = (SELECT id FROM t_ctx WHERE key = 'si')
     ORDER BY line_number$q$,
  $$VALUES
      (1, '77777777-7777-7777-7777-777777777154'::uuid, '55555555-5555-5555-5555-555555555154'::uuid, '55555555-5555-5555-5555-555555555254'::uuid, '55555555-5555-5555-5555-555555555354'::uuid),
      (2, NULL::uuid, '55555555-5555-5555-5555-555555555154'::uuid, '55555555-5555-5555-5555-555555555254'::uuid, '55555555-5555-5555-5555-555555555354'::uuid)$$,
  'Inventory lines inherit header warehouse while service lines avoid automatic warehouse context'
);

SELECT results_eq(
  $q$SELECT account_id, debit, credit
     FROM jsonb_to_recordset(
       fn_preview_gl_impact('SI', (SELECT id FROM t_ctx WHERE key = 'si'))->'lines'
     ) AS x(account_id uuid, debit numeric, credit numeric)
     ORDER BY debit DESC, credit DESC, account_id$q$,
  $$VALUES
      ('aaaaaaaa-0000-0000-0000-000000000154'::uuid, 1680.00::numeric,    0.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000654'::uuid,  600.00::numeric,    0.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000354'::uuid,    0.00::numeric, 1000.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000554'::uuid,    0.00::numeric,  600.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000454'::uuid,    0.00::numeric,  500.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000254'::uuid,    0.00::numeric,  180.00::numeric)$$,
  'draft SI GL preview includes estimated COGS and inventory lines'
);

SELECT is(
  (SELECT COUNT(*)::integer
   FROM inventory_transactions
   WHERE reference_doc_type = 'SI'
     AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')),
  0,
  'draft SI GL preview does not create inventory transactions'
);

SELECT results_eq(
  $q$SELECT impact_group, SUM(debit)::numeric, SUM(credit)::numeric
     FROM jsonb_to_recordset(
       fn_preview_gl_impact('SI', (SELECT id FROM t_ctx WHERE key = 'si'))->'lines'
     ) AS x(impact_group text, debit numeric, credit numeric)
     GROUP BY impact_group
     ORDER BY impact_group$q$,
  $$VALUES
      ('COMMERCIAL'::text, 1680.00::numeric, 1680.00::numeric),
      ('INVENTORY'::text,   600.00::numeric,  600.00::numeric)$$,
  'draft SI GL preview separates balanced commercial and inventory impact groups'
);

SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si')),
  'complete Sales Invoice approves'
);

SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si')),
  'complete Sales Invoice posts'
);

SELECT results_eq(
  $q$SELECT account_id, debit_amount, credit_amount
     FROM journal_entry_lines
     WHERE je_id = (
       SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')
     )
     ORDER BY line_number$q$,
  $$VALUES
      ('aaaaaaaa-0000-0000-0000-000000000154'::uuid, 1680.00::numeric,    0.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000354'::uuid,    0.00::numeric, 1000.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000454'::uuid,    0.00::numeric,  500.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000254'::uuid,    0.00::numeric,  180.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000654'::uuid,  600.00::numeric,    0.00::numeric),
      ('aaaaaaaa-0000-0000-0000-000000000554'::uuid,    0.00::numeric,  600.00::numeric)$$,
  'SI GL impact includes AR, revenue, output VAT, COGS, and inventory'
);

SELECT results_eq(
  $q$SELECT payload.mode, impact_group, accounting_effect, inventory_movement_id IS NOT NULL
     FROM jsonb_to_recordset(
       fn_preview_gl_impact('SI', (SELECT id FROM t_ctx WHERE key = 'si'))->'lines'
     ) AS x(
       impact_group text,
       accounting_effect text,
       inventory_movement_id uuid
     )
     CROSS JOIN LATERAL (
       SELECT fn_preview_gl_impact('SI', (SELECT id FROM t_ctx WHERE key = 'si'))->>'mode' AS mode
     ) payload
     WHERE impact_group = 'INVENTORY'
     ORDER BY accounting_effect$q$,
  $$VALUES
      ('posted'::text, 'INVENTORY'::text, 'COGS'::text, true),
      ('posted'::text, 'INVENTORY'::text, 'INVENTORY'::text, true)$$,
  'posted SI GL impact keeps inventory/cost classification and movement traceability'
);

SELECT is(
  (SELECT ROUND(SUM(debit_amount - credit_amount), 2)
   FROM journal_entry_lines
   WHERE je_id = (
     SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')
   )),
  0.00::numeric,
  'SI journal entry remains balanced including COGS and inventory lines'
);

SELECT results_eq(
  $q$SELECT line_number, unit_cost, inventory_cost, inventory_transaction_id IS NOT NULL
     FROM sales_invoice_lines
     WHERE sales_invoice_id = (SELECT id FROM t_ctx WHERE key = 'si')
     ORDER BY line_number$q$,
  $$VALUES
      (1, 600.000000::numeric, 600.00::numeric, true),
      (2, NULL::numeric, NULL::numeric, false)$$,
  'Inventory posting evidence is stored only on the inventory line'
);

SELECT results_eq(
  $q$SELECT transaction_type, qty, unit_cost, total_cost, reference_doc_type, journal_entry_id IS NOT NULL
     FROM inventory_transactions
     WHERE reference_doc_type = 'SI'
       AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')$q$,
  $$VALUES ('issue'::text, -1.0000::numeric, 600.000000::numeric, -600.00::numeric, 'SI'::text, true)$$,
  'SI posting writes the authoritative inventory issue transaction'
);

SELECT results_eq(
  $q$SELECT qty_on_hand, total_cost, wac_unit_cost
     FROM stock_balances
     WHERE warehouse_id = '77777777-7777-7777-7777-777777777154'
       AND item_id = '66666666-6666-6666-6666-666666666354'$q$,
  $$VALUES (4.0000::numeric, 2400.00::numeric, 600.000000::numeric)$$,
  'SI posting reduces stock quantity and cost'
);

SELECT results_eq(
  $q$SELECT vc.vat_code, tax_base, tax_amount, counterparty_tin
     FROM tax_detail_entries t
     JOIN vat_codes vc ON vc.id = t.vat_code_id
     WHERE t.source_doc_type = 'SI'
       AND t.source_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')$q$,
  $$VALUES ('VAT-12'::text, 1500.00::numeric, 180.00::numeric, '444-555-666-00154'::text)$$,
  'SI tax ledger uses VAT-inclusive taxable base, VAT amount, and normalized customer TIN'
);

SELECT lives_ok(
  format(
    'SELECT fn_void_sales_invoice(%L, NULL, %L)',
    (SELECT id FROM t_ctx WHERE key = 'si'),
    'AUD053 void coverage'
  ),
  'posted Sales Invoice voids through the governed RPC'
);

SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
  'cancelled',
  'voided SI reaches the terminal cancelled status'
);

SELECT results_eq(
  $q$SELECT qty_on_hand, total_cost, wac_unit_cost
     FROM stock_balances
     WHERE warehouse_id = '77777777-7777-7777-7777-777777777154'
       AND item_id = '66666666-6666-6666-6666-666666666354'$q$,
  $$VALUES (5.0000::numeric, 3000.00::numeric, 600.000000::numeric)$$,
  'SI void restores stock quantity and cost'
);

SELECT results_eq(
  $q$SELECT transaction_type, qty, unit_cost, total_cost, reference_doc_type, journal_entry_id IS NOT NULL
     FROM inventory_transactions
     WHERE reference_doc_type = 'SI_VOID'
       AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')$q$,
  $$VALUES ('adjustment_in'::text, 1.0000::numeric, 600.000000::numeric, 600.00::numeric, 'SI_VOID'::text, true)$$,
  'SI void writes inventory restoration evidence linked to the reversal journal'
);

SELECT is(
  (SELECT COUNT(*)::integer
   FROM inventory_transactions
   WHERE reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')),
  2,
  'only inventory item activity creates SI inventory transactions'
);

SELECT isnt_empty(
  $q$SELECT 1
     FROM journal_entries original
     JOIN journal_entries reversal ON reversal.id = original.reversed_by_je_id
     WHERE original.id = (
       SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')
     )
       AND original.status = 'reversed'
       AND reversal.status = 'posted'$q$,
  'SI void creates a posted reversal journal and marks the original reversed'
);

SELECT * FROM finish();
ROLLBACK;
