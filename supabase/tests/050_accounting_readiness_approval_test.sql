-- ACCOUNTING-READINESS-APPROVAL-001 - SI/VB approval readiness and EWT identity
--
-- PXL-AUD-009 / PXL-AUD-010 closure coverage:
-- - Sales invoices cannot be approved by RPC or direct status transition when
--   posting accounts/VAT codes are missing or no longer active.
-- - Vendor bills cannot be approved by RPC or direct status transition when
--   posting accounts/VAT codes are missing or no longer active.
-- - AP-side EWT documents default a valid supplier TIN snapshot before approval/post.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111250',
        'authenticated', 'authenticated', 'accounting-readiness@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111250","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222250', 'corporation',
        'Accounting Readiness Test Corp', 'Professional Services', '111-222-333-00250',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'accounting-readiness@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, is_active,
                                 created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222250', true, false, false, true,
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333250',
        '22222222-2222-2222-2222-222222222250', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444250',
        '22222222-2222-2222-2222-222222222250',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222250',
       '44444444-4444-4444-4444-444444444250',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000501', '22222222-2222-2222-2222-222222222250',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000502', '22222222-2222-2222-2222-222222222250',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000503', '22222222-2222-2222-2222-222222222250',
   '1250', 'CWT Receivable',            'asset',     'debit',  true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000504', '22222222-2222-2222-2222-222222222250',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000505', '22222222-2222-2222-2222-222222222250',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000506', '22222222-2222-2222-2222-222222222250',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000507', '22222222-2222-2222-2222-222222222250',
   '2150', 'EWT Payable',               'liability', 'credit', true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000508', '22222222-2222-2222-2222-222222222250',
   '1400', 'Supplier Down Payments',    'asset',     'debit',  true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000509', '22222222-2222-2222-2222-222222222250',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000510', '22222222-2222-2222-2222-222222222250',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true,  auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000511', '22222222-2222-2222-2222-222222222250',
   '4099', 'Inactive Revenue',          'revenue',   'credit', true, false, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000512', '22222222-2222-2222-2222-222222222250',
   '5099', 'Inactive Expense',          'expense',   'debit',  true, false, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        ewt_withheld_account_id, default_cash_account_id,
        ap_account_id, input_vat_account_id, ewt_payable_account_id,
        supplier_down_payments_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222250',
        'aaaaaaaa-0000-0000-0000-000000000502',
        'aaaaaaaa-0000-0000-0000-000000000505',
        'aaaaaaaa-0000-0000-0000-000000000503',
        'aaaaaaaa-0000-0000-0000-000000000501',
        'aaaaaaaa-0000-0000-0000-000000000504',
        'aaaaaaaa-0000-0000-0000-000000000506',
        'aaaaaaaa-0000-0000-0000-000000000507',
        'aaaaaaaa-0000-0000-0000-000000000508',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222250',
       '33333333-3333-3333-3333-333333333250',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555250',
        '22222222-2222-2222-2222-222222222250', 'CUST-READY',
        'Readiness Customer Inc', '444-555-666-00250',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES
  ('66666666-6666-6666-6666-666666666250',
   '22222222-2222-2222-2222-222222222250', 'SUPP-READY',
   'Readiness Supplier Corp', '777-888-999-00250',
   'Supplier HQ, Pasig', false, NULL,
   auth.uid(), auth.uid()),
  ('66666666-6666-6666-6666-666666666251',
   '22222222-2222-2222-2222-222222222250', 'SUPP-EWT',
   'EWT Supplier Corp', '777-888-999-00251',
   'Supplier HQ, Pasig', true, (SELECT id FROM atc_codes WHERE code = 'WC140'),
   auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si-missing-revenue', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',               '22222222-2222-2222-2222-222222222250',
    'branch_id',                '33333333-3333-3333-3333-333333333250',
    'date',                     '2026-05-10',
    'customer_id',              '55555555-5555-5555-5555-555555555250',
    'customer_name_snapshot',   'Readiness Customer Inc',
    'customer_tin_snapshot',    '444-555-666-00250',
    'customer_address_snapshot','Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Services without a revenue account',
    'quantity',    1,
    'unit_price',  1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
  )));

SELECT throws_like(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si-missing-revenue')),
  '%Every sales invoice line must have a revenue account before approval or posting.%',
  'SI approval rejects a line with no revenue account');

SELECT throws_like(
  format('UPDATE sales_invoices SET status = ''approved'' WHERE id = %L',
         (SELECT id FROM t_ctx WHERE key = 'si-missing-revenue')),
  '%Every sales invoice line must have a revenue account before approval or posting.%',
  'SI direct approved-status transition also enforces revenue account readiness');

INSERT INTO t_ctx
SELECT 'si-inactive-revenue', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',               '22222222-2222-2222-2222-222222222250',
    'branch_id',                '33333333-3333-3333-3333-333333333250',
    'date',                     '2026-05-11',
    'customer_id',              '55555555-5555-5555-5555-555555555250',
    'customer_name_snapshot',   'Readiness Customer Inc',
    'customer_tin_snapshot',    '444-555-666-00250',
    'customer_address_snapshot','Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Services with inactive revenue account',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000511'
  )));

SELECT throws_like(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si-inactive-revenue')),
  '%Every sales invoice revenue account must be active, postable%',
  'SI approval rejects inactive revenue accounts');

INSERT INTO t_ctx
SELECT 'si-inactive-vat', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',               '22222222-2222-2222-2222-222222222250',
    'branch_id',                '33333333-3333-3333-3333-333333333250',
    'date',                     '2026-05-12',
    'customer_id',              '55555555-5555-5555-5555-555555555250',
    'customer_name_snapshot',   'Readiness Customer Inc',
    'customer_tin_snapshot',    '444-555-666-00250',
    'customer_address_snapshot','Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Services with VAT deactivated after draft',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000509'
  )));

UPDATE vat_codes SET is_active = false WHERE vat_code = 'VAT-12';

SELECT throws_like(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si-inactive-vat')),
  '%Every sales invoice VAT code must be active%',
  'SI approval rejects an output VAT code that was deactivated after draft');

UPDATE vat_codes SET is_active = true WHERE vat_code = 'VAT-12';

INSERT INTO t_ctx
SELECT 'si-valid', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',               '22222222-2222-2222-2222-222222222250',
    'branch_id',                '33333333-3333-3333-3333-333333333250',
    'date',                     '2026-05-13',
    'customer_id',              '55555555-5555-5555-5555-555555555250',
    'customer_name_snapshot',   'Readiness Customer Inc',
    'customer_tin_snapshot',    '444-555-666-00250',
    'customer_address_snapshot','Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Accounting-ready services',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000509'
  )));

SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si-valid')),
  'accounting-ready SI can be approved');

SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si-valid')),
  'accounting-ready approved SI can post');

SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si-valid')),
  'posted',
  'valid SI ends posted');

INSERT INTO t_ctx
SELECT 'vb-missing-expense', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222250',
    'branch_id',               '33333333-3333-3333-3333-333333333250',
    'supplier_id',             '66666666-6666-6666-6666-666666666250',
    'supplier_name_snapshot',  'Readiness Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-00250',
    'supplier_invoice_number', 'SUP-READY-001',
    'bill_date',               '2026-05-14'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Purchases without an expense account',
    'quantity',    1,
    'unit_price',  1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12')
  )));

SELECT throws_like(
  format('SELECT fn_approve_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb-missing-expense')),
  '%Every vendor bill line must have an expense account before approval or posting.%',
  'VB approval rejects a line with no expense account');

SELECT throws_like(
  format('UPDATE vendor_bills SET status = ''approved'' WHERE id = %L',
         (SELECT id FROM t_ctx WHERE key = 'vb-missing-expense')),
  '%Every vendor bill line must have an expense account before approval or posting.%',
  'VB direct approved-status transition also enforces expense account readiness');

INSERT INTO t_ctx
SELECT 'vb-inactive-expense', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222250',
    'branch_id',               '33333333-3333-3333-3333-333333333250',
    'supplier_id',             '66666666-6666-6666-6666-666666666250',
    'supplier_name_snapshot',  'Readiness Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-00250',
    'supplier_invoice_number', 'SUP-READY-002',
    'bill_date',               '2026-05-15'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Purchases with inactive expense account',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000512'
  )));

SELECT throws_like(
  format('SELECT fn_approve_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb-inactive-expense')),
  '%Every vendor bill expense account must be active, postable%',
  'VB approval rejects inactive expense accounts');

INSERT INTO t_ctx
SELECT 'vb-inactive-vat', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222250',
    'branch_id',               '33333333-3333-3333-3333-333333333250',
    'supplier_id',             '66666666-6666-6666-6666-666666666250',
    'supplier_name_snapshot',  'Readiness Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-00250',
    'supplier_invoice_number', 'SUP-READY-003',
    'bill_date',               '2026-05-16'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Purchases with VAT deactivated after draft',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000510'
  )));

UPDATE vat_codes SET is_active = false WHERE vat_code = 'IVAT-12';

SELECT throws_like(
  format('SELECT fn_approve_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb-inactive-vat')),
  '%Every vendor bill VAT code must be active%',
  'VB approval rejects an input VAT code that was deactivated after draft');

UPDATE vat_codes SET is_active = true WHERE vat_code = 'IVAT-12';

INSERT INTO t_ctx
SELECT 'vb-valid', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222250',
    'branch_id',               '33333333-3333-3333-3333-333333333250',
    'supplier_id',             '66666666-6666-6666-6666-666666666250',
    'supplier_name_snapshot',  'Readiness Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-00250',
    'supplier_invoice_number', 'SUP-READY-004',
    'bill_date',               '2026-05-17'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Accounting-ready purchases',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000510'
  )));

SELECT lives_ok(
  format('SELECT fn_approve_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb-valid')),
  'accounting-ready VB can be approved');

SELECT lives_ok(
  format('SELECT fn_post_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb-valid')),
  'accounting-ready approved VB can post');

SELECT is(
  (SELECT status FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb-valid')),
  'posted',
  'valid VB ends posted');

INSERT INTO t_ctx
SELECT 'vb-ewt-missing-tin', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222250',
    'branch_id',               '33333333-3333-3333-3333-333333333250',
    'supplier_id',             '66666666-6666-6666-6666-666666666251',
    'supplier_name_snapshot',  'EWT Supplier Corp',
    'supplier_tin_snapshot',   '',
    'supplier_invoice_number', 'SUP-EWT-001',
    'bill_date',               '2026-05-18'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Source-basis EWT purchase without TIN snapshot',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000510'
  )));

SELECT is(
  (SELECT supplier_tin_snapshot FROM vendor_bills
   WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb-ewt-missing-tin')),
  '777-888-999-00251',
  'source-basis EWT VB defaults the valid supplier master TIN snapshot');

SELECT lives_ok(
  format('SELECT fn_approve_vendor_bill(%L)',
         (SELECT id FROM t_ctx WHERE key = 'vb-ewt-missing-tin')),
  'source-basis EWT VB with a defaulted valid TIN can be approved');

INSERT INTO t_ctx
SELECT 'pv-ewt-missing-tin', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222250',
    'branch_id',              '33333333-3333-3333-3333-333333333250',
    'supplier_id',            '66666666-6666-6666-6666-666666666251',
    'supplier_name_snapshot', 'EWT Supplier Corp',
    'supplier_tin_snapshot',  '',
    'voucher_date',           '2026-05-19'
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type',         'supplier_down_payment',
    'vendor_bill_id',    NULL,
    'payment_amount',    9800,
    'ewt_amount',        200,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',      10000,
    'ewt_income_nature', 'Professional fees'
  )));

SELECT lives_ok(
  format('SELECT fn_post_payment_voucher(%L)',
         (SELECT id FROM t_ctx WHERE key = 'pv-ewt-missing-tin')),
  'PV with EWT posts after defaulting the valid supplier master TIN snapshot');

SELECT * FROM finish();
ROLLBACK;
