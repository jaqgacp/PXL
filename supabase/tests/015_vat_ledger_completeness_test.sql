-- ══════════════════════════════════════════════════════════════════════════════
-- VAT-LEDGER-COMPLETE-001 - Per-VAT-Code Tax Ledger Rows (PXL-AUD-014)
--
-- Verifies the tax ledger now preserves classification bases: one output/input
-- VAT row per (document, vat_code), including zero-amount rows for zero-rated
-- and exempt activity; cash sales write output VAT + CWT rows and correct
-- classification header totals; cash purchases write input VAT rows; void
-- counter-entries net every per-code row; and the tax-ledger/GL reconciliation
-- is unaffected by the zero-amount rows.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111161',
        'authenticated', 'authenticated', 'vatc-owner@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  json_build_object('sub', '11111111-1111-1111-1111-111111111161',
                    'role', 'authenticated')::text, true);

-- ── VAT company with full posting setup ────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222260', 'corporation',
        'VAT Complete Corp', 'Software Services', '111-222-333-062',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'vatc-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333360',
        '22222222-2222-2222-2222-222222222260', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444480',
        '22222222-2222-2222-2222-222222222260',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222260',
       '44444444-4444-4444-4444-444444444480',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-0000000000b1', '22222222-2222-2222-2222-222222222260',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b2', '22222222-2222-2222-2222-222222222260',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b3', '22222222-2222-2222-2222-222222222260',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b4', '22222222-2222-2222-2222-222222222260',
   '1400', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b5', '22222222-2222-2222-2222-222222222260',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b6', '22222222-2222-2222-2222-222222222260',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b7', '22222222-2222-2222-2222-222222222260',
   '2200', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b8', '22222222-2222-2222-2222-222222222260',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b9', '22222222-2222-2222-2222-222222222260',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, ap_account_id, input_vat_account_id,
        ewt_withheld_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222260',
        'aaaaaaaa-0000-0000-0000-0000000000b2',
        'aaaaaaaa-0000-0000-0000-0000000000b6',
        'aaaaaaaa-0000-0000-0000-0000000000b1',
        'aaaaaaaa-0000-0000-0000-0000000000b5',
        'aaaaaaaa-0000-0000-0000-0000000000b3',
        'aaaaaaaa-0000-0000-0000-0000000000b4',
        'aaaaaaaa-0000-0000-0000-0000000000b7',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222260',
       '33333333-3333-3333-3333-333333333360',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'OR', 'CS', 'CP');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555591',
        '22222222-2222-2222-2222-222222222260', 'CUST-001',
        'Ledger Customer Inc', '444-555-666-062',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666681',
        '22222222-2222-2222-2222-222222222260', 'SUPP-001',
        'Ledger Supplier Corp', '777-888-999-062',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ── SI with regular, zero-rated, and exempt lines ──────────────────────────────
INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222260',
    'branch_id',                 '33333333-3333-3333-3333-333333333360',
    'date',                      '2026-03-10',
    'customer_id',               '55555555-5555-5555-5555-555555555591',
    'customer_name_snapshot',    'Ledger Customer Inc',
    'customer_tin_snapshot',     '444-555-666-062',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'description', 'Domestic consulting', 'quantity', 1, 'unit_price', 10000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8'),
    jsonb_build_object(
      'description', 'Export services', 'quantity', 1, 'unit_price', 5000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-0-EXPORT'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8'),
    jsonb_build_object(
      'description', 'Exempt training', 'quantity', 1, 'unit_price', 3000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8')
  ));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));

-- 1-2. One ledger row per VAT code with classification bases preserved
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type='SI' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='si1')
     AND tax_kind='output_vat' AND is_reversal=false),
  3, 'mixed SI writes one output VAT row per VAT code');

SELECT results_eq(
  $q$SELECT vc.vat_classification, t.tax_base, t.tax_amount
     FROM tax_detail_entries t JOIN vat_codes vc ON vc.id = t.vat_code_id
     WHERE t.source_doc_type='SI'
       AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='si1')
       AND t.tax_kind='output_vat' AND t.is_reversal=false
     ORDER BY vc.vat_classification$q$,
  $$VALUES ('exempt'::text,     3000.00::numeric(15,2), 0.00::numeric(15,2)),
           ('regular'::text,   10000.00::numeric(15,2), 1200.00::numeric(15,2)),
           ('zero_rated'::text, 5000.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'regular, zero-rated, and exempt bases are all preserved in the ledger');

-- ── All-exempt SI: previously wrote no ledger rows at all ──────────────────────
INSERT INTO t_ctx
SELECT 'si2', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222260',
    'branch_id',                 '33333333-3333-3333-3333-333333333360',
    'date',                      '2026-03-11',
    'customer_id',               '55555555-5555-5555-5555-555555555591',
    'customer_name_snapshot',    'Ledger Customer Inc',
    'customer_tin_snapshot',     '444-555-666-062',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Exempt seminar', 'quantity', 1, 'unit_price', 2000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8')));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si2'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si2'));

-- 3. Zero-VAT document of a VAT company now leaves ledger evidence
SELECT results_eq(
  $q$SELECT t.tax_base, t.tax_amount
     FROM tax_detail_entries t
     WHERE t.source_doc_type='SI'
       AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='si2')
       AND t.tax_kind='output_vat' AND t.is_reversal=false$q$,
  $$VALUES (2000.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'an all-exempt SI writes its base to the ledger with zero tax');

-- ── VB with regular and zero-rated lines ───────────────────────────────────────
INSERT INTO t_ctx
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222260',
    'branch_id',               '33333333-3333-3333-3333-333333333360',
    'supplier_id',             '66666666-6666-6666-6666-666666666681',
    'supplier_name_snapshot',  'Ledger Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-062',
    'supplier_invoice_number', 'SUP-INV-0621',
    'bill_date',               '2026-03-12'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'description', 'Contractor services', 'quantity', 1, 'unit_price', 4000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b9'),
    jsonb_build_object(
      'description', 'Zero-rated freight', 'quantity', 1, 'unit_price', 1500,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-0'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b9')
  ));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));

-- 4. Input side mirrors the per-code behavior
SELECT results_eq(
  $q$SELECT vc.vat_classification, t.tax_base, t.tax_amount
     FROM tax_detail_entries t JOIN vat_codes vc ON vc.id = t.vat_code_id
     WHERE t.source_doc_type='VB'
       AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='vb1')
       AND t.tax_kind='input_vat' AND t.is_reversal=false
     ORDER BY vc.vat_classification$q$,
  $$VALUES ('regular'::text,    4000.00::numeric(15,2), 480.00::numeric(15,2)),
           ('zero_rated'::text, 1500.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'VB writes per-code input VAT rows including the zero-rated base');

-- ── Cash sale: output VAT + CWT rows, classified header totals ─────────────────
CREATE TEMP TABLE t_cs AS
SELECT fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222260',
    'branch_id',              '33333333-3333-3333-3333-333333333360',
    'date',                   '2026-03-13',
    'customer_id',            '55555555-5555-5555-5555-555555555591',
    'customer_name_snapshot', 'Ledger Customer Inc',
    'customer_tin_snapshot',  '444-555-666-062',
    'cwt_atc_id',             (SELECT id FROM atc_codes WHERE code = 'WC140')
  ),
  jsonb_build_array(
    jsonb_build_object(
      'description', 'Walk-in service', 'quantity', 1, 'unit_price', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8'),
    jsonb_build_object(
      'description', 'Exempt booklet', 'quantity', 1, 'unit_price', 500,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8')
  ),
  32.40) AS res;

-- 5. Header classification totals are now split correctly
SELECT results_eq(
  $q$SELECT total_taxable_amount, total_zero_rated_amount, total_exempt_amount, total_vat_amount
     FROM sales_invoices WHERE id = (SELECT (res->>'si_id')::uuid FROM t_cs)$q$,
  $$VALUES (1000.00::numeric(15,2), 0.00::numeric(15,2), 500.00::numeric(15,2), 120.00::numeric(15,2))$$,
  'cash sale header stores taxable/zero-rated/exempt totals by line classification');

-- 6. Cash sale SI writes per-code output rows (previously none)
SELECT results_eq(
  $q$SELECT vc.vat_classification, t.tax_base, t.tax_amount
     FROM tax_detail_entries t JOIN vat_codes vc ON vc.id = t.vat_code_id
     WHERE t.source_doc_type='SI'
       AND t.source_doc_id=(SELECT (res->>'si_id')::uuid FROM t_cs)
       AND t.tax_kind='output_vat' AND t.is_reversal=false
     ORDER BY vc.vat_classification$q$,
  $$VALUES ('exempt'::text,  500.00::numeric(15,2), 0.00::numeric(15,2)),
           ('regular'::text, 1000.00::numeric(15,2), 120.00::numeric(15,2))$$,
  'cash sale writes per-code output VAT rows');

-- 7. Cash sale receipt writes the CWT receivable row (previously none)
SELECT results_eq(
  $q$SELECT t.tax_base, t.tax_amount
     FROM tax_detail_entries t
     WHERE t.source_doc_type='OR'
       AND t.source_doc_id=(SELECT (res->>'receipt_id')::uuid FROM t_cs)
       AND t.tax_kind='cwt_receivable' AND t.is_reversal=false$q$,
  $$VALUES (1620.00::numeric(15,2), 32.40::numeric(15,2))$$,
  'cash sale receipt writes the CWT receivable ledger row');

-- ── Cash purchase: input VAT rows (previously none) ────────────────────────────
INSERT INTO cash_purchases (id, company_id, branch_id, supplier_id,
        supplier_name_snapshot, supplier_tin_snapshot, cp_number, transaction_date,
        payment_method, payment_account_id,
        total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
        total_input_vat_amount, total_amount, status, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-777777777791',
        '22222222-2222-2222-2222-222222222260', '33333333-3333-3333-3333-333333333360',
        '66666666-6666-6666-6666-666666666681',
        'Ledger Supplier Corp', '777-888-999-062', 'CP-TEST-1', '2026-03-14',
        'cash', 'aaaaaaaa-0000-0000-0000-0000000000b1',
        2000, 0, 0, 240, 2240, 'draft', auth.uid(), auth.uid());

INSERT INTO cash_purchase_lines (cp_id, company_id, line_number, description,
        quantity, unit_price, net_amount, vat_code_id, input_vat_amount,
        total_amount, expense_account_id, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-777777777791',
        '22222222-2222-2222-2222-222222222260', 1, 'Office supplies',
        1, 2000, 2000, (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'), 240,
        2240, 'aaaaaaaa-0000-0000-0000-0000000000b9', auth.uid(), auth.uid());

SELECT fn_post_cash_purchase('77777777-7777-7777-7777-777777777791');

-- 8. Cash purchase writes the input VAT row
SELECT results_eq(
  $q$SELECT t.tax_base, t.tax_amount
     FROM tax_detail_entries t
     WHERE t.source_doc_type='CP'
       AND t.source_doc_id='77777777-7777-7777-7777-777777777791'
       AND t.tax_kind='input_vat' AND t.is_reversal=false$q$,
  $$VALUES (2000.00::numeric(15,2), 240.00::numeric(15,2))$$,
  'cash purchase writes its input VAT ledger row');

-- ── March tax-ledger/GL reconciliation is exact despite zero-amount rows ───────
-- Output ledger: 1,200 (si1) + 0 (si2) + 120 (cash sale) = 1,320
-- Input ledger:  480 + 0 (vb1) + 240 (cash purchase)     = 720
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222260',
                                   '2026-03-01', '2026-03-31')$q$,
  $$VALUES ('input_vat'::text,  720.00::numeric(15,2),  720.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('output_vat'::text, 1320.00::numeric(15,2), 1320.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'March reconciles: zero-amount classification rows do not disturb the control');

-- ── Void: every per-code row is netted by a counter-row ────────────────────────
SELECT fn_void_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'), NULL, 'completeness void test');

-- 10. Three counter-rows, one per original per-code row
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type='SI' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='si1')
     AND tax_kind='output_vat' AND is_reversal=true),
  3, 'voiding the mixed SI writes one counter-row per VAT code');

-- 11. Per-code net is zero for base and amount alike
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT t.vat_code_id
     FROM tax_detail_entries t
     WHERE t.source_doc_type='SI'
       AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='si1')
       AND t.tax_kind='output_vat'
     GROUP BY t.vat_code_id
     HAVING SUM(t.tax_base) <> 0 OR SUM(t.tax_amount) <> 0) x),
  0, 'after void, every VAT code nets to zero base and zero tax');

-- 12. Zero-rated/exempt evidence survives the void as linked pairs
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries r
   JOIN tax_detail_entries o ON o.id = r.reverses_tax_detail_id
   WHERE r.source_doc_type='SI'
     AND r.source_doc_id=(SELECT id FROM t_ctx WHERE key='si1')
     AND r.is_reversal=true AND o.is_reversal=false
     AND r.vat_code_id = o.vat_code_id),
  3, 'each counter-row links to its original row with the same VAT code');

-- 13. si2 (untouched) still carries its exempt evidence
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type='SI' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='si2')
     AND is_reversal=false),
  1, 'unrelated zero-VAT evidence is untouched by the void');

SELECT * FROM finish();
ROLLBACK;
