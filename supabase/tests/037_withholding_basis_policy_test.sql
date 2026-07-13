-- ══════════════════════════════════════════════════════════════════════════════
-- WHT-BASIS-001 - AP EWT source/accrual basis policy (PXL-AUD-037)
--
-- A supplier with a default EWT ATC creates a VAT vendor bill for 10,000 net
-- plus 1,200 input VAT.  Under the default accrual_at_source policy, the bill
-- accrues 200 EWT at VB posting, credits AP for the net payable 11,000, writes
-- VB-sourced EWT tax detail, rejects duplicate PV-level EWT, and allows the
-- cash-only PV to settle AP without adding another QAP/Form 2307 row.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111237',
        'authenticated', 'authenticated', 'harness-wht-basis@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111237","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222237', 'corporation',
        'WHT Basis Test Corp', 'Software Services', '111-222-333-037',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-wht-basis@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

SELECT is(
  (SELECT ap_ewt_recognition_policy FROM companies WHERE id = '22222222-2222-2222-2222-222222222237'),
  'accrual_at_source',
  'new companies default to source/accrual AP EWT recognition');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333237',
        '22222222-2222-2222-2222-222222222237', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444237',
        '22222222-2222-2222-2222-222222222237',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222237',
       '44444444-4444-4444-4444-444444444237',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000371', '22222222-2222-2222-2222-222222222237',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000372', '22222222-2222-2222-2222-222222222237',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000373', '22222222-2222-2222-2222-222222222237',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000374', '22222222-2222-2222-2222-222222222237',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000375', '22222222-2222-2222-2222-222222222237',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222237',
        'aaaaaaaa-0000-0000-0000-000000000372',
        'aaaaaaaa-0000-0000-0000-000000000371',
        'aaaaaaaa-0000-0000-0000-000000000373',
        'aaaaaaaa-0000-0000-0000-000000000374',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222237',
       '33333333-3333-3333-3333-333333333237',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666237',
        '22222222-2222-2222-2222-222222222237', 'SUPP-WB1',
        'Source Basis Supplier Corp', '777-888-999-037',
        'Supplier HQ, Pasig', true, (SELECT id FROM atc_codes WHERE code = 'WC140'),
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ── VB: 10,000 net + 1,200 input VAT, supplier default EWT WC140 2% ───────────
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222237',
    'branch_id',               '33333333-3333-3333-3333-333333333237',
    'supplier_id',             '66666666-6666-6666-6666-666666666237',
    'supplier_name_snapshot',  'Source Basis Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-037',
    'supplier_invoice_number', 'SUP-INV-0371',
    'bill_date',               '2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000375'
  )));

SELECT results_eq(
  format($q$SELECT vbl.ewt_tax_base, vbl.ewt_amount, ac.code
          FROM vendor_bill_lines vbl
          JOIN atc_codes ac ON ac.id = vbl.ewt_atc_code_id
          WHERE vbl.vendor_bill_id = %L$q$, (SELECT id FROM t_ctx WHERE key = 'vb')),
  $$VALUES (10000.00::numeric, 200.00::numeric, 'WC140'::text)$$,
  'vendor bill line derives EWT ATC, base, and amount from the supplier default');

SELECT is(
  (SELECT ewt_amount_expected FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb')),
  200.00::numeric,
  'vendor bill header expected EWT is derived from source-basis lines');

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'));

SELECT lives_ok(
  format('SELECT fn_post_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb')),
  'vendor bill posts with source-basis EWT');

SELECT is(
  (SELECT SUM(jel.credit_amount)
   FROM journal_entry_lines jel
   JOIN vendor_bills vb ON vb.journal_entry_id = jel.je_id
   WHERE vb.id = (SELECT id FROM t_ctx WHERE key = 'vb')
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000372'),
  11000.00::numeric,
  'VB posting credits AP for the net payable after source EWT');

SELECT is(
  (SELECT SUM(jel.credit_amount)
   FROM journal_entry_lines jel
   JOIN vendor_bills vb ON vb.journal_entry_id = jel.je_id
   WHERE vb.id = (SELECT id FROM t_ctx WHERE key = 'vb')
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000373'),
  200.00::numeric,
  'VB posting credits EWT Payable at source');

SELECT results_eq(
  format($q$SELECT source_doc_type, source_line_id IS NOT NULL, tax_base, tax_amount, document_date
          FROM tax_detail_entries
          WHERE source_doc_type = 'VB'
            AND source_doc_id = %L
            AND tax_kind = 'ewt_payable'$q$, (SELECT id FROM t_ctx WHERE key = 'vb')),
  $$VALUES ('VB'::text, true, 10000.00::numeric, 200.00::numeric, '2026-01-10'::date)$$,
  'VB source EWT writes a line-level ewt_payable tax-detail row');

SELECT is(
  (SELECT is_reconciled::text || '|' || ledger_tax_amount::text || '|' || gl_amount::text
   FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-222222222237',
                                 '2026-01-01', '2026-03-31')
   WHERE tax_kind = 'ewt_payable'),
  'true|200.00|200.00',
  'source-basis EWT reconciles tax detail to the EWT Payable GL control account');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222237', '2026-01-31')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key = 'vb')),
  11000.00::numeric,
  'AP aging shows only the net cash payable after source EWT');

SELECT throws_like(
  $q$SELECT fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222237',
      'branch_id',              '33333333-3333-3333-3333-333333333237',
      'supplier_id',            '66666666-6666-6666-6666-666666666237',
      'supplier_name_snapshot', 'Source Basis Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-037',
      'voucher_date',           '2026-02-05'
    ),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key = 'vb'),
      'payment_amount',    11000,
      'ewt_amount',        200,
      'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',      10000,
      'ewt_income_nature', 'Contractor services'
    )))$q$,
  '%already accrued EWT at source%',
  'duplicate PV-level EWT is rejected for a source-accrued vendor bill');

INSERT INTO t_ctx
SELECT 'pv', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222237',
    'branch_id',              '33333333-3333-3333-3333-333333333237',
    'supplier_id',            '66666666-6666-6666-6666-666666666237',
    'supplier_name_snapshot', 'Source Basis Supplier Corp',
    'supplier_tin_snapshot',  '777-888-999-037',
    'voucher_date',           '2026-02-05'
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id', (SELECT id FROM t_ctx WHERE key = 'vb'),
    'payment_amount', 11000,
    'ewt_amount',     0
  )));

SELECT is(
  (SELECT total_ewt FROM payment_vouchers WHERE id = (SELECT id FROM t_ctx WHERE key = 'pv')),
  0.00::numeric,
  'cash-only PV against a source-accrued bill carries no EWT total');

SELECT lives_ok(
  format('SELECT fn_post_payment_voucher(%L)', (SELECT id FROM t_ctx WHERE key = 'pv')),
  'cash-only PV settles the source-accrued bill');

SELECT is(
  (SELECT COUNT(*)::int FROM tax_detail_entries
   WHERE source_doc_type = 'PV'
     AND source_doc_id = (SELECT id FROM t_ctx WHERE key = 'pv')
     AND tax_kind = 'ewt_payable'),
  0,
  'PV writes no duplicate ewt_payable tax-detail rows');

SELECT is(
  (SELECT COALESCE(SUM(balance_due), 0) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222237', '2026-02-28')),
  0.00::numeric,
  'AP aging is fully settled after the cash-only PV');

SELECT is(
  (SELECT SUM(tax_amount) FROM tax_detail_entries
   WHERE company_id = '22222222-2222-2222-2222-222222222237'
     AND tax_kind = 'ewt_payable'),
  200.00::numeric,
  'EWT tax ledger remains the original VB source amount only');

SELECT is(
  (SELECT SUM(jel.credit_amount)
   FROM journal_entry_lines jel
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222237'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000373'),
  200.00::numeric,
  'EWT Payable GL credit remains the original VB source amount only');

SELECT * FROM finish();
ROLLBACK;
