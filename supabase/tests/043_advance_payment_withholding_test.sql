-- ADVANCE-PAYMENT-WHT-001 - OR/PV advance withholding policy
--
-- PXL-AUD-043 remaining slice: customer advances can record CWT on an
-- invoice-less OR line and supplier down-payments can record EWT on a bill-less
-- PV line. Both post to configured advance balance-sheet accounts and still
-- reconcile tax-detail rows to the GL withholding controls.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111243',
        'authenticated', 'authenticated', 'advance-wht-owner@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111243","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222243', 'corporation',
        'Advance WHT Corp', 'Professional Services', '111-222-333-243',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'advance-wht-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, is_active,
                                 created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222243', false, false, false, true,
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333243',
        '22222222-2222-2222-2222-222222222243', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444243',
        '22222222-2222-2222-2222-222222222243',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222243',
       '44444444-4444-4444-4444-444444444243',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000431', '22222222-2222-2222-2222-222222222243',
   '1010', 'Cash in Bank',             'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000432', '22222222-2222-2222-2222-222222222243',
   '1200', 'Accounts Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000433', '22222222-2222-2222-2222-222222222243',
   '1250', 'CWT Receivable',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000434', '22222222-2222-2222-2222-222222222243',
   '2000', 'Accounts Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000435', '22222222-2222-2222-2222-222222222243',
   '2150', 'EWT Payable',              'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000436', '22222222-2222-2222-2222-222222222243',
   '2300', 'Customer Advances',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000437', '22222222-2222-2222-2222-222222222243',
   '1400', 'Supplier Down Payments',   'asset',     'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id,
        ewt_withheld_account_id, default_cash_account_id,
        ap_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222243',
        'aaaaaaaa-0000-0000-0000-000000000432',
        'aaaaaaaa-0000-0000-0000-000000000433',
        'aaaaaaaa-0000-0000-0000-000000000431',
        'aaaaaaaa-0000-0000-0000-000000000434',
        'aaaaaaaa-0000-0000-0000-000000000435',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222243',
       '33333333-3333-3333-3333-333333333243',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('OR', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       tin_branch_code, registered_address, delivery_address,
                       is_subject_to_cwt, default_cwt_atc_code_id,
                       created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555243',
        '22222222-2222-2222-2222-222222222243', 'CUST-ADV',
        'Advance Customer Inc', '444-555-666', '243',
        'Customer HQ, Taguig', 'Customer HQ, Taguig',
        true, (SELECT id FROM atc_codes WHERE code = 'WC140'),
        auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666243',
        '22222222-2222-2222-2222-222222222243', 'SUPP-DP',
        'Down Payment Supplier Corp', '777-888-999-243',
        'Supplier HQ, Pasig', true, (SELECT id FROM atc_codes WHERE code = 'WC140'),
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'or-advance', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222243',
    'branch_id',              '33333333-3333-3333-3333-333333333243',
    'customer_id',            '55555555-5555-5555-5555-555555555243',
    'customer_name_snapshot', 'Advance Customer Inc',
    'customer_tin_snapshot',  '444-555-666-243',
    'receipt_date',           '2026-04-10',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type',       'customer_advance',
    'invoice_id',      NULL,
    'payment_amount',  49000,
    'cwt_amount',      1000,
    'atc_code_id',     (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'cwt_tax_base',    50000
  )));

SELECT results_eq(
  $q$SELECT line_type, invoice_id IS NULL, payment_amount, cwt_amount, cwt_tax_base
     FROM receipt_lines
     WHERE receipt_id = (SELECT id FROM t_ctx WHERE key = 'or-advance')$q$,
  $$VALUES ('customer_advance'::text, true, 49000.00::numeric(15,2),
            1000.00::numeric(15,2), 50000.00::numeric(15,2))$$,
  'customer advance OR line is explicitly invoice-less and keeps CWT base/amount');

SELECT throws_like(
  $$SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key = 'or-advance'))$$,
  '%Customer advances account not configured%',
  'customer advance posting requires a configured customer advances account');

UPDATE company_accounting_config
SET customer_advances_account_id = 'aaaaaaaa-0000-0000-0000-000000000436',
    updated_by = auth.uid(),
    updated_at = NOW()
WHERE company_id = '22222222-2222-2222-2222-222222222243';

SELECT lives_ok(
  $$SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key = 'or-advance'))$$,
  'customer advance with CWT posts successfully after advance account setup');

SELECT results_eq(
  $q$SELECT coa.account_code, jel.debit_amount, jel.credit_amount
     FROM journal_entry_lines jel
     JOIN chart_of_accounts coa ON coa.id = jel.account_id
     JOIN journal_entries je ON je.id = jel.je_id
     WHERE je.reference_doc_type = 'OR'
       AND je.reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'or-advance')
     ORDER BY jel.line_number$q$,
  $$VALUES ('1010'::text, 49000.00::numeric(15,2), 0.00::numeric(15,2)),
           ('1250'::text, 1000.00::numeric(15,2), 0.00::numeric(15,2)),
           ('2300'::text, 0.00::numeric(15,2), 50000.00::numeric(15,2))$$,
  'customer advance OR debits cash/CWT receivable and credits customer advances, not AR');

SELECT results_eq(
  $q$SELECT tde.source_line_id IS NOT NULL, ac.code, tde.tax_base, tde.tax_amount
     FROM tax_detail_entries tde
     JOIN atc_codes ac ON ac.id = tde.atc_code_id
     WHERE tde.source_doc_type = 'OR'
       AND tde.source_doc_id = (SELECT id FROM t_ctx WHERE key = 'or-advance')
       AND tde.tax_kind = 'cwt_receivable'
       AND tde.is_reversal = false$q$,
  $$VALUES (true, 'WC140'::text, 50000.00::numeric(15,2), 1000.00::numeric(15,2))$$,
  'customer advance OR writes source-line CWT tax detail');

SELECT results_eq(
  $q$SELECT ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_wht_gl_reconciliation(
       '22222222-2222-2222-2222-222222222243',
       DATE '2026-04-01',
       DATE '2026-04-30'
     )
     WHERE tax_kind = 'cwt_receivable'$q$,
  $$VALUES (1000.00::numeric(15,2), 1000.00::numeric(15,2),
            0.00::numeric(15,2), true)$$,
  'customer advance CWT reconciles tax detail to the CWT receivable GL control');

SELECT throws_like(
  $q$SELECT fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222243',
      'branch_id',              '33333333-3333-3333-3333-333333333243',
      'supplier_id',            '66666666-6666-6666-6666-666666666243',
      'supplier_name_snapshot', 'Down Payment Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-243',
      'voucher_date',           '2026-04-11',
      'payment_mode_id',        (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
    ),
    jsonb_build_array(jsonb_build_object(
      'line_type',         'supplier_down_payment',
      'vendor_bill_id',    NULL,
      'payment_amount',    9800,
      'ewt_amount',        200,
      'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',      10000,
      'ewt_income_nature', 'Professional fees'
    )))$q$,
  '%not EWT-registered%',
  'supplier down-payment EWT is blocked when the active profile is not EWT registered');

UPDATE compliance_profiles
SET ewt_registered = true, updated_by = auth.uid(), updated_at = NOW()
WHERE company_id = '22222222-2222-2222-2222-222222222243';

INSERT INTO t_ctx
SELECT 'pv-down-payment', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222243',
    'branch_id',              '33333333-3333-3333-3333-333333333243',
    'supplier_id',            '66666666-6666-6666-6666-666666666243',
    'supplier_name_snapshot', 'Down Payment Supplier Corp',
    'supplier_tin_snapshot',  '777-888-999-243',
    'voucher_date',           '2026-04-11',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
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

SELECT results_eq(
  $q$SELECT line_type, vendor_bill_id IS NULL, payment_amount, ewt_amount, ewt_tax_base
     FROM payment_voucher_lines
     WHERE payment_voucher_id = (SELECT id FROM t_ctx WHERE key = 'pv-down-payment')$q$,
  $$VALUES ('supplier_down_payment'::text, true, 9800.00::numeric(15,2),
            200.00::numeric(15,2), 10000.00::numeric(15,2))$$,
  'supplier down-payment PV line is explicitly bill-less and keeps EWT base/amount');

SELECT throws_like(
  $$SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key = 'pv-down-payment'))$$,
  '%Supplier down-payments account not configured%',
  'supplier down-payment posting requires a configured supplier down-payments account');

UPDATE company_accounting_config
SET supplier_down_payments_account_id = 'aaaaaaaa-0000-0000-0000-000000000437',
    updated_by = auth.uid(),
    updated_at = NOW()
WHERE company_id = '22222222-2222-2222-2222-222222222243';

SELECT lives_ok(
  $$SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key = 'pv-down-payment'))$$,
  'supplier down-payment with EWT posts successfully after advance account setup');

SELECT results_eq(
  $q$SELECT coa.account_code, jel.debit_amount, jel.credit_amount
     FROM journal_entry_lines jel
     JOIN chart_of_accounts coa ON coa.id = jel.account_id
     JOIN journal_entries je ON je.id = jel.je_id
     WHERE je.reference_doc_type = 'PV'
       AND je.reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'pv-down-payment')
     ORDER BY jel.line_number$q$,
  $$VALUES ('1400'::text, 10000.00::numeric(15,2), 0.00::numeric(15,2)),
           ('1010'::text, 0.00::numeric(15,2), 9800.00::numeric(15,2)),
           ('2150'::text, 0.00::numeric(15,2), 200.00::numeric(15,2))$$,
  'supplier down-payment PV debits supplier advances and credits cash/EWT payable, not AP');

SELECT results_eq(
  $q$SELECT tde.source_line_id IS NOT NULL, ac.code, tde.tax_base, tde.tax_amount, tde.income_nature
     FROM tax_detail_entries tde
     JOIN atc_codes ac ON ac.id = tde.atc_code_id
     WHERE tde.source_doc_type = 'PV'
       AND tde.source_doc_id = (SELECT id FROM t_ctx WHERE key = 'pv-down-payment')
       AND tde.tax_kind = 'ewt_payable'
       AND tde.is_reversal = false$q$,
  $$VALUES (true, 'WC140'::text, 10000.00::numeric(15,2),
            200.00::numeric(15,2), 'Professional fees'::text)$$,
  'supplier down-payment PV writes source-line EWT payable tax detail');

SELECT results_eq(
  $q$SELECT ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_wht_gl_reconciliation(
       '22222222-2222-2222-2222-222222222243',
       DATE '2026-04-01',
       DATE '2026-04-30'
     )
     WHERE tax_kind = 'ewt_payable'$q$,
  $$VALUES (200.00::numeric(15,2), 200.00::numeric(15,2),
            0.00::numeric(15,2), true)$$,
  'supplier down-payment EWT reconciles tax detail to the EWT payable GL control');

SELECT * FROM finish();
ROLLBACK;
