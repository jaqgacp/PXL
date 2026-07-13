-- WITHHOLDING-PROFILE-001 - Compliance profile gates EWT payable and TWA defaults
--
-- PXL-AUD-042: an active compliance profile with ewt_registered = false blocks
-- AP-side EWT payable on VB/PV/CV paths. Once the profile is EWT registered and
-- TWA auto-EWT is enabled, supplier-subject vendor-bill lines default to the
-- BIR TWA ATCs: WC158 at 1% for goods and WC160 at 2% for services.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- Identity
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111238',
        'authenticated', 'authenticated', 'harness-wht-profile@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111238","role":"authenticated"}', true);

-- Company + shared setup
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222238', 'corporation',
        'WHT Profile Test Corp', 'Trading', '111-222-333-038',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-wht-profile@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, is_active,
                                 created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222238', false, false, false, true,
        auth.uid(), auth.uid());

SELECT is(
  fn_company_ewt_payable_enabled('22222222-2222-2222-2222-222222222238'),
  false,
  'an active non-EWT compliance profile disables AP EWT payable');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333238',
        '22222222-2222-2222-2222-222222222238', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444238',
        '22222222-2222-2222-2222-222222222238',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222238',
       '44444444-4444-4444-4444-444444444238',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000381', '22222222-2222-2222-2222-222222222238',
   '1010', 'Cash in Bank',     'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000382', '22222222-2222-2222-2222-222222222238',
   '2010', 'Accounts Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000383', '22222222-2222-2222-2222-222222222238',
   '2150', 'EWT Payable',      'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000384', '22222222-2222-2222-2222-222222222238',
   '1300', 'Input VAT',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000385', '22222222-2222-2222-2222-222222222238',
   '5010', 'Purchases',        'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222238',
        'aaaaaaaa-0000-0000-0000-000000000382',
        'aaaaaaaa-0000-0000-0000-000000000381',
        'aaaaaaaa-0000-0000-0000-000000000383',
        'aaaaaaaa-0000-0000-0000-000000000384',
        auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           gl_account_id, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-777777777738',
        '22222222-2222-2222-2222-222222222238', 'BDO', '001122330038',
        'WHT Profile Test Corp', 'aaaaaaaa-0000-0000-0000-000000000381',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222238',
       '33333333-3333-3333-3333-333333333238',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES
  ('66666666-6666-6666-6666-666666666381',
   '22222222-2222-2222-2222-222222222238', 'SUPP-DEF',
   'Default EWT Supplier Corp', '777-888-999-381',
   'Supplier HQ, Pasig', true, (SELECT id FROM atc_codes WHERE code = 'WC140'),
   auth.uid(), auth.uid()),
  ('66666666-6666-6666-6666-666666666382',
   '22222222-2222-2222-2222-222222222238', 'SUPP-OPEN',
   'Open Supplier Corp', '777-888-999-382',
   'Supplier HQ, Pasig', false, NULL,
   auth.uid(), auth.uid()),
  ('66666666-6666-6666-6666-666666666383',
   '22222222-2222-2222-2222-222222222238', 'SUPP-TWA',
   'TWA Subject Supplier Corp', '777-888-999-383',
   'Supplier HQ, Pasig', true, NULL,
   auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

SELECT throws_like(
  $q$SELECT fn_save_vendor_bill(NULL,
    jsonb_build_object(
      'company_id',              '22222222-2222-2222-2222-222222222238',
      'branch_id',               '33333333-3333-3333-3333-333333333238',
      'supplier_id',             '66666666-6666-6666-6666-666666666381',
      'supplier_name_snapshot',  'Default EWT Supplier Corp',
      'supplier_tin_snapshot',   '777-888-999-381',
      'supplier_invoice_number', 'SUP-INV-0381',
      'bill_date',               '2026-01-10'
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Contractor services',
      'quantity',           1,
      'unit_price',         10000,
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000385'
    )))$q$,
  '%not EWT-registered%',
  'source-basis vendor bill EWT is blocked when the active profile is not EWT registered');

INSERT INTO t_ctx
SELECT 'vb-open', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222238',
    'branch_id',               '33333333-3333-3333-3333-333333333238',
    'supplier_id',             '66666666-6666-6666-6666-666666666382',
    'supplier_name_snapshot',  'Open Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-382',
    'supplier_invoice_number', 'SUP-INV-0382',
    'bill_date',               '2026-01-11'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Non-withheld services',
    'quantity',           1,
    'unit_price',         10000,
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000385'
  )));

SELECT is(
  (SELECT ewt_amount_expected FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb-open')),
  0.00::numeric,
  'non-EWT vendor bill remains allowed for a non-EWT profile');

SELECT throws_like(
  $q$SELECT fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222238',
      'branch_id',              '33333333-3333-3333-3333-333333333238',
      'supplier_id',            '66666666-6666-6666-6666-666666666382',
      'supplier_name_snapshot', 'Open Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-382',
      'voucher_date',           '2026-01-20'
    ),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key = 'vb-open'),
      'payment_amount',    9800,
      'ewt_amount',        200,
      'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',      10000,
      'ewt_income_nature', 'Contractor services'
    )))$q$,
  '%not EWT-registered%',
  'payment voucher EWT is blocked when the active profile is not EWT registered');

SELECT throws_like(
  $$INSERT INTO check_vouchers (company_id, branch_id, cv_number, voucher_date,
      bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
      total_gross_amount, total_ewt_amount, atc_code_id, ewt_tax_base, particulars,
      status, created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222238', '33333333-3333-3333-3333-333333333238',
      'CV-WHT-038', '2026-01-20', '77777777-7777-7777-7777-777777777738', 'CHK-0038',
      '2026-01-20', 'Default EWT Supplier Corp', '777-888-999-381',
      '66666666-6666-6666-6666-666666666381',
      10000, 200, (SELECT id FROM atc_codes WHERE code = 'WC140'), 10000,
      'Check EWT gate', 'draft', auth.uid(), auth.uid())$$,
  '%not EWT-registered%',
  'check voucher EWT is blocked when the active profile is not EWT registered');

SELECT throws_like(
  $$INSERT INTO ewt_returns (company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due,
      status, created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222238', 2026, 1,
      0, 0, 0, 0, 'draft', auth.uid(), auth.uid())$$,
  '%not EWT-registered%',
  '1601EQ/EWT return rows are blocked when the active profile is not EWT registered');

SELECT throws_like(
  $$SELECT fn_snapshot_wht_export('22222222-2222-2222-2222-222222222238',
      'QAP', 2026, 1)$$,
  '%not EWT-registered%',
  'QAP export snapshots are blocked when the active profile is not EWT registered');

UPDATE compliance_profiles
SET ewt_registered = true,
    is_twa = true,
    twa_effective_date = DATE '2026-01-01',
    twa_auto_ewt_enabled = true,
    updated_by = auth.uid(),
    updated_at = NOW()
WHERE company_id = '22222222-2222-2222-2222-222222222238';

SELECT is(
  fn_company_twa_auto_ewt_enabled('22222222-2222-2222-2222-222222222238', DATE '2026-01-12'),
  true,
  'TWA auto-EWT is enabled only after the EWT-registered TWA profile is active');

SELECT is(
  (SELECT rate FROM atc_codes WHERE id = fn_twa_ewt_atc_asof('services', DATE '2026-01-12')),
  2.00::numeric,
  'TWA service default resolves WC160 at 2 percent');

INSERT INTO item_categories (
  id, company_id, category_code, category_name,
  inventory_account_id, adj_account_id, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555538',
  '22222222-2222-2222-2222-222222222238',
  'TWA', 'TWA Inventory',
  'aaaaaaaa-0000-0000-0000-000000000385',
  'aaaaaaaa-0000-0000-0000-000000000385',
  auth.uid(), auth.uid()
);

INSERT INTO units_of_measure (
  id, company_id, uom_code, description, is_base_unit,
  created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555638',
  '22222222-2222-2222-2222-222222222238',
  'EA', 'Each', true, auth.uid(), auth.uid()
);

INSERT INTO items (
  id, company_id, item_code, description, item_type,
  category_id, uom_id, standard_cost,
  inventory_account_id, purchase_expense_account_id, costing_method,
  created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666638',
  '22222222-2222-2222-2222-222222222238',
  'TWA-GOODS', 'TWA Goods Item', 'inventory_item',
  '55555555-5555-5555-5555-555555555538',
  '55555555-5555-5555-5555-555555555638',
  10,
  'aaaaaaaa-0000-0000-0000-000000000385',
  'aaaaaaaa-0000-0000-0000-000000000385',
  'weighted_average', auth.uid(), auth.uid()
);

INSERT INTO t_ctx
SELECT 'vb-twa', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222238',
    'branch_id',               '33333333-3333-3333-3333-333333333238',
    'supplier_id',             '66666666-6666-6666-6666-666666666383',
    'supplier_name_snapshot',  'TWA Subject Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-383',
    'supplier_invoice_number', 'SUP-INV-0383',
    'bill_date',               '2026-01-12'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'item_id',            '66666666-6666-6666-6666-666666666638',
      'description',        'Inventory goods',
      'quantity',           1,
      'unit_price',         10000,
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000385'
    ),
    jsonb_build_object(
      'description',        'Professional services',
      'quantity',           1,
      'unit_price',         10000,
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000385'
    )
  ));

SELECT results_eq(
  format($q$SELECT vbl.line_number, ac.code, vbl.ewt_tax_base, vbl.ewt_amount
          FROM vendor_bill_lines vbl
          JOIN atc_codes ac ON ac.id = vbl.ewt_atc_code_id
          WHERE vbl.vendor_bill_id = %L
          ORDER BY vbl.line_number$q$, (SELECT id FROM t_ctx WHERE key = 'vb-twa')),
  $$VALUES
      (1, 'WC158'::text, 10000.00::numeric, 100.00::numeric),
      (2, 'WC160'::text, 10000.00::numeric, 200.00::numeric)$$,
  'TWA auto-EWT defaults goods to WC158 1% and services to WC160 2%');

SELECT is(
  (SELECT ewt_amount_expected FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb-twa')),
  300.00::numeric,
  'vendor bill header expected EWT syncs to TWA auto-defaulted source lines');

SELECT * FROM finish();
ROLLBACK;
