-- ══════════════════════════════════════════════════════════════════════════════
-- ASOF-LEDGER-RECON-001 - Customer/Supplier Ledger and GL Reconciliation
-- (PXL-DA-013)
--
-- Proves period-end customer/supplier ledgers are cutoff-aware and reconcile to
-- configured AR/AP control accounts. Uses real posting RPCs so the assertions
-- exercise the same source documents and journal entries used by production.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111151',
        'authenticated', 'authenticated', 'harness-da013@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111151","role":"authenticated"}', true);

-- ── Company / branch / periods / COA / config / series / counterparties ───────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222251', 'corporation',
        'DA013 Ledger Test Corp', 'Software Services', '111-222-333-051',
        'vat', 'calendar',
        'Unit 51', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-da013@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333351',
        '22222222-2222-2222-2222-222222222251', 'HO', 'Head Office',
        'Unit 51', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444451',
        '22222222-2222-2222-2222-222222222251',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222251',
       '44444444-4444-4444-4444-444444444451',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000051', '22222222-2222-2222-2222-222222222251',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000052', '22222222-2222-2222-2222-222222222251',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000053', '22222222-2222-2222-2222-222222222251',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000054', '22222222-2222-2222-2222-222222222251',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000055', '22222222-2222-2222-2222-222222222251',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000056', '22222222-2222-2222-2222-222222222251',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000057', '22222222-2222-2222-2222-222222222251',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id, default_cash_account_id,
  ewt_payable_account_id, input_vat_account_id, created_by, updated_by
)
VALUES (
  '22222222-2222-2222-2222-222222222251',
  'aaaaaaaa-0000-0000-0000-000000000052',
  'aaaaaaaa-0000-0000-0000-000000000054',
  'aaaaaaaa-0000-0000-0000-000000000051',
  'aaaaaaaa-0000-0000-0000-000000000055',
  'aaaaaaaa-0000-0000-0000-000000000056',
  auth.uid(), auth.uid()
);

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222251',
       '33333333-3333-3333-3333-333333333351',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR', 'CM', 'VB', 'PV', 'VC');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555551',
        '22222222-2222-2222-2222-222222222251', 'CUST-DA013',
        'DA013 Customer Inc', '444-555-666-051',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666651',
        '22222222-2222-2222-2222-222222222251', 'SUPP-DA013',
        'DA013 Supplier Corp', '777-888-999-051',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ── AR: SI 10,000; future OR 4,000; future CM 1,000 ───────────────────────────
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222251',
    'branch_id',                 '33333333-3333-3333-3333-333333333351',
    'date',                      '2026-01-15',
    'due_date',                  '2026-01-30',
    'customer_id',               '55555555-5555-5555-5555-555555555551',
    'customer_name_snapshot',    'DA013 Customer Inc',
    'customer_tin_snapshot',     '444-555-666-051',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Exempt services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000053'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222251',
    'branch_id',              '33333333-3333-3333-3333-333333333351',
    'customer_id',            '55555555-5555-5555-5555-555555555551',
    'customer_name_snapshot', 'DA013 Customer Inc',
    'customer_tin_snapshot',  '444-555-666-051',
    'receipt_date',           '2026-02-15',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           4000,
    'total_cwt',              0
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key = 'si'),
    'payment_amount', 4000,
    'cwt_amount',     0
  )));

SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key = 'or'));

INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222251',
    'branch_id',              '33333333-3333-3333-3333-333333333351',
    'customer_id',            '55555555-5555-5555-5555-555555555551',
    'customer_name_snapshot', 'DA013 Customer Inc',
    'customer_tin_snapshot',  '444-555-666-051',
    'invoice_id',             (SELECT id FROM t_ctx WHERE key = 'si'),
    'cm_date',                '2026-02-20',
    'reason_code_id',         (SELECT id FROM ref_reason_codes WHERE code = 'CM_OTHER')
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Billing adjustment',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000053'
  )),
  'applied');

-- ── AP: VB 12,000; future PV 7,000 + EWT 1,000; VB 8,000; future VC 2,000 ─────
INSERT INTO t_ctx
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222251',
    'branch_id',               '33333333-3333-3333-3333-333333333351',
    'supplier_id',             '66666666-6666-6666-6666-666666666651',
    'supplier_name_snapshot',  'DA013 Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-051',
    'supplier_invoice_number', 'SUP-DA013-0001',
    'bill_date',               '2026-01-10',
    'due_date',                '2026-01-25'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional services',
    'quantity',           1,
    'unit_price',         12000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000057'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb1'));

INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222251',
    'branch_id',              '33333333-3333-3333-3333-333333333351',
    'supplier_id',            '66666666-6666-6666-6666-666666666651',
    'supplier_name_snapshot', 'DA013 Supplier Corp',
    'voucher_date',           '2026-02-10',
    'total_amount',           7000,
    'total_ewt',              1000
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key = 'vb1'),
    'payment_amount',    7000,
    'ewt_amount',        1000,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WI010'),
    'ewt_tax_base',      10000,
    'ewt_income_nature', 'Professional fees'
  )));

SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key = 'pv1'));

INSERT INTO t_ctx
SELECT 'vb2', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222251',
    'branch_id',               '33333333-3333-3333-3333-333333333351',
    'supplier_id',             '66666666-6666-6666-6666-666666666651',
    'supplier_name_snapshot',  'DA013 Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-051',
    'supplier_invoice_number', 'SUP-DA013-0002',
    'bill_date',               '2026-03-05'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional services',
    'quantity',           1,
    'unit_price',         8000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000057'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb2'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb2'));

INSERT INTO t_ctx
SELECT 'vc1', fn_save_vendor_credit(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222251',
    'branch_id',              '33333333-3333-3333-3333-333333333351',
    'supplier_id',            '66666666-6666-6666-6666-666666666651',
    'supplier_name_snapshot', 'DA013 Supplier Corp',
    'supplier_tin_snapshot',  '777-888-999-051',
    'credit_date',            '2026-03-20'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Service credit',
    'quantity',           1,
    'unit_price',         2000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000057'
  )));

SELECT fn_post_vendor_credit((SELECT id FROM t_ctx WHERE key = 'vc1'));

INSERT INTO t_ctx
SELECT 'vca1', fn_apply_vendor_credit(
  (SELECT id FROM t_ctx WHERE key = 'vc1'),
  (SELECT id FROM t_ctx WHERE key = 'vb2'),
  2000, '2026-03-20'::date, 'Applied per ASOF-LEDGER-RECON-001');

-- ── Customer ledger assertions ────────────────────────────────────────────────
SELECT is(
  (SELECT COUNT(*) FROM fn_customer_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-01-31')),
  1::BIGINT, 'customer ledger as of 2026-01-31 includes only the posted SI');

SELECT is(
  (SELECT SUM(debit_amount - credit_amount) FROM fn_customer_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-01-31')),
  10000.00::NUMERIC, 'customer ledger as of 2026-01-31 excludes future OR/CM');

SELECT is(
  (SELECT COUNT(*) FROM fn_customer_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-02-19')),
  2::BIGINT, 'customer ledger as of 2026-02-19 includes SI and OR only');

SELECT is(
  (SELECT running_balance FROM fn_customer_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-02-19')
   ORDER BY transaction_date DESC, created_at DESC, source_doc_id DESC LIMIT 1),
  6000.00::NUMERIC, 'customer ledger running balance before the CM is 6,000.00');

SELECT is(
  (SELECT string_agg(source_doc_type, ',' ORDER BY transaction_date, created_at, source_doc_type)
   FROM fn_customer_ledger_asof('22222222-2222-2222-2222-222222222251', '2026-02-28')),
  'SI,OR,CM', 'customer ledger as of 2026-02-28 orders SI, OR, and CM cutoff rows');

SELECT is(
  (SELECT subledger_balance FROM fn_ar_subledger_gl_reconciliation_asof(
     '22222222-2222-2222-2222-222222222251', '2026-02-28')),
  5000.00::NUMERIC, 'AR reconciliation reports a 5,000.00 subledger balance');

SELECT is(
  (SELECT variance FROM fn_ar_subledger_gl_reconciliation_asof(
     '22222222-2222-2222-2222-222222222251', '2026-02-28')),
  0.00::NUMERIC, 'AR reconciliation variance is zero at period end');

SELECT ok(
  (SELECT is_reconciled FROM fn_ar_subledger_gl_reconciliation_asof(
     '22222222-2222-2222-2222-222222222251', '2026-02-28')),
  'AR reconciliation is marked reconciled');

-- ── Supplier ledger assertions ────────────────────────────────────────────────
SELECT is(
  (SELECT COUNT(*) FROM fn_supplier_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-01-31')),
  1::BIGINT, 'supplier ledger as of 2026-01-31 includes only the posted VB');

SELECT is(
  (SELECT SUM(credit_amount - debit_amount) FROM fn_supplier_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-01-31')),
  12000.00::NUMERIC, 'supplier ledger as of 2026-01-31 excludes future PV/VC');

SELECT is(
  (SELECT running_balance FROM fn_supplier_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-02-28')
   ORDER BY transaction_date DESC, created_at DESC, source_doc_id DESC LIMIT 1),
  4000.00::NUMERIC, 'supplier ledger running balance after PV cash plus EWT is 4,000.00');

SELECT is(
  (SELECT string_agg(source_doc_type, ',' ORDER BY transaction_date, created_at, source_doc_type)
   FROM fn_supplier_ledger_asof('22222222-2222-2222-2222-222222222251', '2026-03-31')),
  'VB,PV,VB,VC', 'supplier ledger as of 2026-03-31 orders VB, PV, VB, and VC rows');

SELECT is(
  (SELECT SUM(credit_amount - debit_amount) FROM fn_supplier_ledger_asof(
     '22222222-2222-2222-2222-222222222251', '2026-03-19')),
  12000.00::NUMERIC, 'supplier ledger as of 2026-03-19 excludes the future vendor credit');

SELECT is(
  (SELECT subledger_balance FROM fn_ap_subledger_gl_reconciliation_asof(
     '22222222-2222-2222-2222-222222222251', '2026-03-31')),
  10000.00::NUMERIC, 'AP reconciliation reports a 10,000.00 subledger balance');

SELECT is(
  (SELECT variance FROM fn_ap_subledger_gl_reconciliation_asof(
     '22222222-2222-2222-2222-222222222251', '2026-03-31')),
  0.00::NUMERIC, 'AP reconciliation variance is zero at period end');

SELECT ok(
  (SELECT is_reconciled FROM fn_ap_subledger_gl_reconciliation_asof(
     '22222222-2222-2222-2222-222222222251', '2026-03-31')),
  'AP reconciliation is marked reconciled');

SELECT * FROM finish();
ROLLBACK;
