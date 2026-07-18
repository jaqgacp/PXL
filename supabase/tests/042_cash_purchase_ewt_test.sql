-- CASH-PURCHASE-EWT-001 - Cash purchase EWT at payment time
--
-- PXL-AUD-043 cash-purchase slice: cash purchases can carry AP-side EWT
-- ATC/base/amount, post EWT payable plus net cash, and write source-line
-- tax-detail rows for QAP/2307 evidence. Advance/down-payment withholding is
-- intentionally not covered here.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111242',
        'authenticated', 'authenticated', 'cp-ewt-owner@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111242","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222242', 'corporation',
        'Cash Purchase EWT Corp', 'Professional Services', '111-222-333-00242',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'cp-ewt-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, is_active,
                                 created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222242', false, false, false, true,
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333242',
        '22222222-2222-2222-2222-222222222242', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444242',
        '22222222-2222-2222-2222-222222222242',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222242',
       '44444444-4444-4444-4444-444444444242',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000421', '22222222-2222-2222-2222-222222222242',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000422', '22222222-2222-2222-2222-222222222242',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000423', '22222222-2222-2222-2222-222222222242',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000424', '22222222-2222-2222-2222-222222222242',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, default_cash_account_id,
        input_vat_account_id, ewt_payable_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222242',
        'aaaaaaaa-0000-0000-0000-000000000421',
        'aaaaaaaa-0000-0000-0000-000000000422',
        'aaaaaaaa-0000-0000-0000-000000000423',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222242',
       '33333333-3333-3333-3333-333333333242',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code = 'CP';

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666242',
        '22222222-2222-2222-2222-222222222242', 'SUPP-EWT',
        'Cash EWT Supplier Corp', '777-888-999-00242',
        'Supplier HQ, Pasig', true, (SELECT id FROM atc_codes WHERE code = 'WC140'),
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

SELECT throws_like(
  $q$SELECT fn_save_cash_purchase(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222242',
      'branch_id',              '33333333-3333-3333-3333-333333333242',
      'transaction_date',       '2026-03-10',
      'supplier_id',            '66666666-6666-6666-6666-666666666242',
      'supplier_name_snapshot', 'Cash EWT Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-00242'
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Professional fee',
      'quantity',           1,
      'unit_price',         10000,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000424',
      'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',       10000,
      'ewt_amount',         200,
      'ewt_income_nature',  'Professional fees'
    )))$q$,
  '%not EWT-registered%',
  'cash purchase EWT is blocked when the active compliance profile is not EWT registered');

UPDATE compliance_profiles
SET ewt_registered = true, updated_by = auth.uid(), updated_at = NOW()
WHERE company_id = '22222222-2222-2222-2222-222222222242';

INSERT INTO t_ctx
SELECT 'cp-ewt', fn_save_cash_purchase(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222242',
    'branch_id',              '33333333-3333-3333-3333-333333333242',
    'transaction_date',       '2026-03-10',
    'supplier_id',            '66666666-6666-6666-6666-666666666242',
    'supplier_name_snapshot', 'Cash EWT Supplier Corp',
    'supplier_tin_snapshot',  '777-888-999-00242'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional fee',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000424',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',       10000,
    'ewt_amount',         200,
    'ewt_income_nature',  'Professional fees'
  )));

SELECT results_eq(
  $q$SELECT total_taxable_amount, total_input_vat_amount, total_ewt_amount, total_amount
     FROM cash_purchases
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'cp-ewt')$q$,
  $$VALUES (10000.00::numeric(15,2), 1200.00::numeric(15,2),
            200.00::numeric(15,2), 11000.00::numeric(15,2))$$,
  'cash purchase header stores gross VAT totals, EWT, and net cash paid');

SELECT results_eq(
  $q$SELECT net_amount, input_vat_amount, ewt_tax_base, ewt_amount, total_amount
     FROM cash_purchase_lines
     WHERE cp_id = (SELECT id FROM t_ctx WHERE key = 'cp-ewt')$q$,
  $$VALUES (10000.00::numeric(15,2), 1200.00::numeric(15,2),
            10000.00::numeric(15,2), 200.00::numeric(15,2),
            11000.00::numeric(15,2))$$,
  'cash purchase line stores explicit EWT base/amount and net cash line total');

SELECT throws_like(
  $q$SELECT fn_save_cash_purchase(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222242',
      'branch_id',              '33333333-3333-3333-3333-333333333242',
      'transaction_date',       '2026-03-11',
      'supplier_id',            '66666666-6666-6666-6666-666666666242',
      'supplier_name_snapshot', 'Cash EWT Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-00242'
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Invalid EWT amount',
      'quantity',           1,
      'unit_price',         10000,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000424',
      'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',       10000,
      'ewt_amount',         300,
      'ewt_income_nature',  'Professional fees'
    )))$q$,
  '%does not match ATC%',
  'cash purchase EWT amount must match the ATC rate unless a variance reason is provided');

SELECT lives_ok(
  $$SELECT fn_post_cash_purchase((SELECT id FROM t_ctx WHERE key = 'cp-ewt'))$$,
  'cash purchase with EWT posts successfully');

SELECT results_eq(
  $q$SELECT total_debit, total_credit
     FROM journal_entries
     WHERE reference_doc_type = 'CP'
       AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'cp-ewt')$q$,
  $$VALUES (11200.00::numeric(15,2), 11200.00::numeric(15,2))$$,
  'posted cash purchase journal totals use gross purchase value');

SELECT results_eq(
  $q$SELECT coa.account_code, jel.debit_amount, jel.credit_amount
     FROM journal_entry_lines jel
     JOIN chart_of_accounts coa ON coa.id = jel.account_id
     JOIN journal_entries je ON je.id = jel.je_id
     WHERE je.reference_doc_type = 'CP'
       AND je.reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'cp-ewt')
     ORDER BY jel.line_number$q$,
  $$VALUES ('5010'::text, 10000.00::numeric(15,2), 0.00::numeric(15,2)),
           ('1300'::text, 1200.00::numeric(15,2), 0.00::numeric(15,2)),
           ('2150'::text, 0.00::numeric(15,2), 200.00::numeric(15,2)),
           ('1010'::text, 0.00::numeric(15,2), 11000.00::numeric(15,2))$$,
  'posting debits expense/input VAT and credits EWT payable plus net cash');

SELECT results_eq(
  $q$SELECT tax_base, tax_amount
     FROM tax_detail_entries
     WHERE source_doc_type = 'CP'
       AND source_doc_id = (SELECT id FROM t_ctx WHERE key = 'cp-ewt')
       AND tax_kind = 'input_vat'
       AND is_reversal = false$q$,
  $$VALUES (10000.00::numeric(15,2), 1200.00::numeric(15,2))$$,
  'cash purchase still writes its input VAT tax-detail row');

SELECT results_eq(
  $q$SELECT tde.source_line_id IS NOT NULL, ac.code, tde.tax_base, tde.tax_rate,
            tde.tax_amount, tde.counterparty_tin, tde.income_nature
     FROM tax_detail_entries tde
     JOIN atc_codes ac ON ac.id = tde.atc_code_id
     WHERE tde.source_doc_type = 'CP'
       AND tde.source_doc_id = (SELECT id FROM t_ctx WHERE key = 'cp-ewt')
       AND tde.tax_kind = 'ewt_payable'
       AND tde.is_reversal = false$q$,
  $$VALUES (true, 'WC140'::text, 10000.00::numeric(15,2), 2.00::numeric(5,2),
            200.00::numeric(15,2), '777-888-999-00242'::text, 'Professional fees'::text)$$,
  'cash purchase writes source-line EWT payable tax detail for QAP/2307 evidence');

SELECT results_eq(
  $q$SELECT ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_wht_gl_reconciliation(
       '22222222-2222-2222-2222-222222222242',
       DATE '2026-03-01',
       DATE '2026-03-31'
     )
     WHERE tax_kind = 'ewt_payable'$q$,
  $$VALUES (200.00::numeric(15,2), 200.00::numeric(15,2),
            0.00::numeric(15,2), true)$$,
  'cash purchase EWT reconciles tax detail to the EWT payable GL control');

SELECT * FROM finish();
ROLLBACK;
