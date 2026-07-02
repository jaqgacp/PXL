-- ══════════════════════════════════════════════════════════════════════════════
-- PV-EWT-PARTIAL-001 - EWT on Partial Payments with Explicit Basis (PXL-AUD-007)
--
-- A VAT vendor bill of 11,200 (10,000 net + 1,200 input VAT) is settled with
-- two partial payment vouchers, each withholding 2% EWT on an explicit 5,000
-- net-of-VAT base. Asserts per-voucher tax detail rows, cumulative EWT of 200
-- on a cumulative base of 10,000, AP clearing across the partials, over-payment
-- rejection, and EWT/ATC rate validation (mismatch without a variance reason
-- rejected; authorized variance and expired ATC behavior).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111116',
        'authenticated', 'authenticated', 'harness-ewt@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111116","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222227', 'corporation',
        'EWT Partial Test Corp', 'Software Services', '111-222-333-005',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-ewt@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333338',
        '22222222-2222-2222-2222-222222222227', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444449',
        '22222222-2222-2222-2222-222222222227',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222227',
       '44444444-4444-4444-4444-444444444449',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000051', '22222222-2222-2222-2222-222222222227',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000052', '22222222-2222-2222-2222-222222222227',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000053', '22222222-2222-2222-2222-222222222227',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000054', '22222222-2222-2222-2222-222222222227',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000055', '22222222-2222-2222-2222-222222222227',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222227',
        'aaaaaaaa-0000-0000-0000-000000000052',
        'aaaaaaaa-0000-0000-0000-000000000051',
        'aaaaaaaa-0000-0000-0000-000000000053',
        'aaaaaaaa-0000-0000-0000-000000000054',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222227',
       '33333333-3333-3333-3333-333333333338',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666670',
        '22222222-2222-2222-2222-222222222227', 'SUPP-001',
        'Partial Payment Supplier Corp', '777-888-999-004',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── VB: 10,000 net + 1,200 input VAT = 11,200 ─────────────────────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222227',
    'branch_id',               '33333333-3333-3333-3333-333333333338',
    'supplier_id',             '66666666-6666-6666-6666-666666666670',
    'supplier_name_snapshot',  'Partial Payment Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-004',
    'supplier_invoice_number', 'SUP-INV-0001',
    'bill_date',               '2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000055'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

SELECT is((SELECT total_amount FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key='vb')),
  11200.00::numeric, 'VAT VB total is 11,200.00 (10,000 net + 1,200 input VAT)');

-- ── PV1: first half — cash 5,500 + EWT 100 (2% of explicit 5,000 base) ─────────
INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222227',
    'branch_id',              '33333333-3333-3333-3333-333333333338',
    'supplier_id',            '66666666-6666-6666-6666-666666666670',
    'supplier_name_snapshot', 'Partial Payment Supplier Corp',
    'voucher_date',           '2026-02-05',
    'total_amount',           5500,
    'total_ewt',              100
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb'),
    'payment_amount',    5500,
    'ewt_amount',        100,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',      5000,
    'ewt_income_nature', 'Contractor services'
  )));

SELECT lives_ok(
  format('SELECT fn_post_payment_voucher(%L)', (SELECT id FROM t_ctx WHERE key='pv1')),
  'first partial PV posts with EWT on the explicit net-of-VAT base');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222227', '2026-02-28')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb')),
  5600.00::numeric, 'bill outstanding is 5,600.00 after the first partial payment');

SELECT results_eq(
  format($q$SELECT tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'PV' AND source_doc_id = %L AND tax_kind = 'ewt_payable'$q$,
         (SELECT id FROM t_ctx WHERE key='pv1')),
  $$VALUES (5000.00::numeric, 100.00::numeric)$$,
  'first PV wrote one ewt_payable row: base 5,000.00, tax 100.00');

-- ── PV2: second half — cash 5,500 + EWT 100 ────────────────────────────────────
INSERT INTO t_ctx
SELECT 'pv2', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222227',
    'branch_id',              '33333333-3333-3333-3333-333333333338',
    'supplier_id',            '66666666-6666-6666-6666-666666666670',
    'supplier_name_snapshot', 'Partial Payment Supplier Corp',
    'voucher_date',           '2026-03-05',
    'total_amount',           5500,
    'total_ewt',              100
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb'),
    'payment_amount',    5500,
    'ewt_amount',        100,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',      5000,
    'ewt_income_nature', 'Contractor services'
  )));

SELECT lives_ok(
  format('SELECT fn_post_payment_voucher(%L)', (SELECT id FROM t_ctx WHERE key='pv2')),
  'second partial PV posts');

SELECT is(
  (SELECT COALESCE(sum(balance_due), 0) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222227', '2026-03-31')),
  0.00::numeric, 'bill is fully settled after both partial payments');

SELECT is(
  (SELECT sum(tax_amount) FROM tax_detail_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222227'
     AND tax_kind = 'ewt_payable'),
  200.00::numeric, 'cumulative EWT withheld across partial payments is 200.00');

SELECT is(
  (SELECT sum(tax_base) FROM tax_detail_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222227'
     AND tax_kind = 'ewt_payable'),
  10000.00::numeric, 'cumulative EWT base equals the 10,000.00 net-of-VAT bill amount');

SELECT is(
  (SELECT sum(jel.credit_amount) FROM journal_entry_lines jel
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222227'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000053'),
  200.00::numeric, 'EWT payable GL account accumulated 200.00 across both vouchers');

-- ── Negative: a third payment would exceed the outstanding balance ─────────────
SELECT throws_like(
  $q$SELECT fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222227',
      'branch_id',              '33333333-3333-3333-3333-333333333338',
      'supplier_id',            '66666666-6666-6666-6666-666666666670',
      'supplier_name_snapshot', 'Partial Payment Supplier Corp',
      'voucher_date',           '2026-04-05',
      'total_amount',           100,
      'total_ewt',              0
    ),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id', (SELECT id FROM vendor_bills
                         WHERE company_id = '22222222-2222-2222-2222-222222222227' LIMIT 1),
      'payment_amount', 100,
      'ewt_amount',     0
    )))$q$,
  '%exceeds outstanding AP balance%',
  'payment beyond the settled bill balance is rejected');

-- ── EWT/ATC rate validation ────────────────────────────────────────────────────
SELECT throws_like(
  format($q$SELECT fn_validate_payment_voucher_line_ewt(%L, 5350, 150, %L, 5000, NULL)$q$,
         '22222222-2222-2222-2222-222222222227',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '%Select a variance reason%',
  'EWT not matching the ATC rate on the explicit base is rejected without a variance reason');

SELECT lives_ok(
  format($q$SELECT fn_validate_payment_voucher_line_ewt(%L, 5350, 150, %L, 5000, 'other_authorized')$q$,
         '22222222-2222-2222-2222-222222222227',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  'the same variance passes with an authorized variance reason');

SELECT throws_like(
  format($q$SELECT fn_validate_payment_voucher_line_ewt(%L, 5350, 150, %L, 5000, 'because')$q$,
         '22222222-2222-2222-2222-222222222227',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '%Invalid EWT variance reason%',
  'an unrecognized variance reason is rejected');

-- Expired ATC: governance columns make it invalid for new withholding
INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active,
                       effective_from, effective_to)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001', 'WTEST-EXP',
        'Expired test ATC', 'ewt', 2.00, true, '2020-01-01', '2020-12-31');

SELECT throws_like(
  format($q$SELECT fn_validate_payment_voucher_line_ewt(%L, 4900, 100, %L, 5000, NULL)$q$,
         '22222222-2222-2222-2222-222222222227',
         'bbbbbbbb-0000-0000-0000-000000000001'),
  '%inactive, expired, deprecated%',
  'an expired ATC cannot be used for new EWT withholding');

SELECT * FROM finish();
ROLLBACK;
