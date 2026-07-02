-- ══════════════════════════════════════════════════════════════════════════════
-- NON-VAT-GATING-001 - VAT Registration Enforcement (PXL-AUD-006, PXL-AUD-014)
--
-- A non-VAT company must not be able to use VAT-bearing SI/VB codes or create
-- VAT returns, while exempt-code documents still flow through save/approve/post.
-- Exercises the database triggers from 20260701000012_vat_registration_enforcement.sql.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111115',
        'authenticated', 'authenticated', 'harness-nonvat@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111115","role":"authenticated"}', true);

-- ── Non-VAT company + setup ────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222226', 'sole_proprietor',
        'Non-VAT Test Trading', 'Retail', '111-222-333-004',
        'non_vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-nonvat@test.local', 'Juan Dela Cruz', 'Owner',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333337',
        '22222222-2222-2222-2222-222222222226', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444448',
        '22222222-2222-2222-2222-222222222226',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222226',
       '44444444-4444-4444-4444-444444444448',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000041', '22222222-2222-2222-2222-222222222226',
   '1010', 'Cash in Bank',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000042', '22222222-2222-2222-2222-222222222226',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000043', '22222222-2222-2222-2222-222222222226',
   '2010', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000044', '22222222-2222-2222-2222-222222222226',
   '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000045', '22222222-2222-2222-2222-222222222226',
   '5010', 'Purchases Expense',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222226',
        'aaaaaaaa-0000-0000-0000-000000000042',
        'aaaaaaaa-0000-0000-0000-000000000043',
        'aaaaaaaa-0000-0000-0000-000000000041',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222226',
       '33333333-3333-3333-3333-333333333337',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555557',
        '22222222-2222-2222-2222-222222222226', 'CUST-001',
        'Non-VAT Customer Inc', '444-555-666-002',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666669',
        '22222222-2222-2222-2222-222222222226', 'SUPP-001',
        'Non-VAT Supplier Corp', '777-888-999-003',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── Negative: VAT-bearing output code on SI line is blocked ────────────────────
SELECT throws_like(
  $q$SELECT fn_save_sales_invoice(NULL,
    jsonb_build_object(
      'company_id',                '22222222-2222-2222-2222-222222222226',
      'branch_id',                 '33333333-3333-3333-3333-333333333337',
      'date',                      '2026-01-15',
      'customer_id',               '55555555-5555-5555-5555-555555555557',
      'customer_name_snapshot',    'Non-VAT Customer Inc',
      'customer_tin_snapshot',     '444-555-666-002',
      'customer_address_snapshot', 'Customer HQ, Taguig'
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'VAT-bearing sale',
      'quantity',           1,
      'unit_price',         10000,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000044'
    )))$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT company cannot save an SI line with a VAT-bearing output code');

-- ── Positive: exempt SI saves, approves, posts with no VAT ─────────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222226',
    'branch_id',                 '33333333-3333-3333-3333-333333333337',
    'date',                      '2026-01-15',
    'customer_id',               '55555555-5555-5555-5555-555555555557',
    'customer_name_snapshot',    'Non-VAT Customer Inc',
    'customer_tin_snapshot',     '444-555-666-002',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Non-VAT sale',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000044'
  )));

SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  'exempt-code SI can be approved for a non-VAT company');
SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  'exempt-code SI posts for a non-VAT company');
SELECT is((SELECT total_vat_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  0.00::numeric, 'posted non-VAT SI carries zero output VAT');
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type = 'SI' AND source_doc_id = (SELECT id FROM t_ctx WHERE key='si')),
  0, 'no output VAT tax detail row is written for the exempt SI');

-- ── Negative: VAT-bearing input code on VB line is blocked ─────────────────────
SELECT throws_like(
  $q$SELECT fn_save_vendor_bill(NULL,
    jsonb_build_object(
      'company_id',              '22222222-2222-2222-2222-222222222226',
      'branch_id',               '33333333-3333-3333-3333-333333333337',
      'supplier_id',             '66666666-6666-6666-6666-666666666669',
      'supplier_name_snapshot',  'Non-VAT Supplier Corp',
      'supplier_tin_snapshot',   '777-888-999-003',
      'supplier_invoice_number', 'SUP-INV-0001',
      'bill_date',               '2026-01-20'
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'VAT-bearing purchase',
      'quantity',           1,
      'unit_price',         5000,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000045'
    )))$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT company cannot save a VB line with a VAT-bearing input code');

-- ── Positive: exempt VB approves and posts ─────────────────────────────────────
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222226',
    'branch_id',               '33333333-3333-3333-3333-333333333337',
    'supplier_id',             '66666666-6666-6666-6666-666666666669',
    'supplier_name_snapshot',  'Non-VAT Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-003',
    'supplier_invoice_number', 'SUP-INV-0002',
    'bill_date',               '2026-01-20'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Non-VAT purchase',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000045'
  )));

SELECT lives_ok(
  format('SELECT fn_approve_vendor_bill(%L); SELECT fn_post_vendor_bill(%L)',
         (SELECT id FROM t_ctx WHERE key='vb'), (SELECT id FROM t_ctx WHERE key='vb')),
  'exempt-code VB approves and posts for a non-VAT company');
SELECT is((SELECT total_input_vat_amount FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key='vb')),
  0.00::numeric, 'posted non-VAT VB carries zero input VAT');

-- ── Negative: VAT return creation is blocked ───────────────────────────────────
SELECT throws_like(
  $q$INSERT INTO vat_returns (company_id, return_type, period_year)
     VALUES ('22222222-2222-2222-2222-222222222226', '2550M', 2026)$q$,
  '%requires a VAT-registered company%',
  'non-VAT company cannot create a VAT return');

SELECT * FROM finish();
ROLLBACK;
