-- ══════════════════════════════════════════════════════════════════════════════
-- PXL Critical Flow Seeded Test (PXL-AUD-001 first slice)
--
-- Journey: company → branch → fiscal periods → COA → GL posting config →
-- number series → customer/supplier → SI save/approve/post → OR post (with CWT)
-- → VB save/approve/post → PV post (with EWT).
--
-- Asserts: balanced journal entries, correct debit/credit accounts and amounts,
-- AR/AP clearing, tax_detail_entries rows (output VAT, CWT receivable, input
-- VAT, EWT payable), and posted-line immutability.
--
-- Runs as postgres superuser: RLS is NOT exercised here (role-based RLS tests
-- are a separate finding). auth.uid() is simulated via request.jwt.claims so
-- SECURITY DEFINER RPC membership/admin checks behave as a real owner session.
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(41);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111111',
        'authenticated', 'authenticated', 'harness@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

SELECT is(auth.uid(), '11111111-1111-1111-1111-111111111111'::uuid,
  'auth.uid() is simulated for the harness user');

-- ── Company + owner membership ─────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222222', 'corporation',
        'Harness Test Corp', 'Software Services', '111-222-333-000',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

SELECT is(
  (SELECT role FROM user_company_memberships
   WHERE user_id = auth.uid()
     AND company_id = '22222222-2222-2222-2222-222222222222'),
  'owner',
  'company creator was granted owner membership by trigger');

-- ── Branch ─────────────────────────────────────────────────────────────────────
INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333333',
        '22222222-2222-2222-2222-222222222222', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

-- ── Fiscal year 2026 with 12 open monthly periods ──────────────────────────────
INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444444',
        '22222222-2222-2222-2222-222222222222',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222222',
       '44444444-4444-4444-4444-444444444444',
       m,
       to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

-- ── Chart of accounts ──────────────────────────────────────────────────────────
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222',
   '1250', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000006', '22222222-2222-2222-2222-222222222222',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000007', '22222222-2222-2222-2222-222222222222',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000008', '22222222-2222-2222-2222-222222222222',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000009', '22222222-2222-2222-2222-222222222222',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

-- ── GL posting configuration ───────────────────────────────────────────────────
INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        ewt_withheld_account_id, default_cash_account_id,
        ap_account_id, input_vat_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222222',
        'aaaaaaaa-0000-0000-0000-000000000002',  -- AR
        'aaaaaaaa-0000-0000-0000-000000000006',  -- Output VAT
        'aaaaaaaa-0000-0000-0000-000000000003',  -- CWT receivable
        'aaaaaaaa-0000-0000-0000-000000000001',  -- Cash
        'aaaaaaaa-0000-0000-0000-000000000005',  -- AP
        'aaaaaaaa-0000-0000-0000-000000000004',  -- Input VAT
        'aaaaaaaa-0000-0000-0000-000000000007',  -- EWT payable
        auth.uid(), auth.uid());

-- ── Number series (legacy UI shape; sync trigger must derive document_code) ────
INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222222',
       '33333333-3333-3333-3333-333333333333',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR', 'VB', 'PV');

SELECT is(
  (SELECT count(*)::int FROM number_series
   WHERE company_id = '22222222-2222-2222-2222-222222222222'
     AND document_code IN ('SI','OR','VB','PV')),
  4,
  'legacy-shape number series rows were given document_code by the sync trigger');

-- ── Customer and supplier ──────────────────────────────────────────────────────
INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555555',
        '22222222-2222-2222-2222-222222222222', 'CUST-001',
        'Withholding Agent Customer Inc', '444-555-666-000',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666666',
        '22222222-2222-2222-2222-222222222222', 'SUPP-001',
        'Contractor Supplier Corp', '777-888-999-000',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ════════════════════════════════════════════════════════════════════════════════
-- 1. SALES INVOICE: 10,000 net + 1,200 output VAT = 11,200
-- ════════════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222222',
    'branch_id',               '33333333-3333-3333-3333-333333333333',
    'date',                    current_date::text,
    'customer_id',             '55555555-5555-5555-5555-555555555555',
    'customer_name_snapshot',  'Withholding Agent Customer Inc',
    'customer_tin_snapshot',   '444-555-666-000',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000008'
  )));

SELECT is((SELECT total_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  11200.00::numeric, 'SI grand total is 11,200.00 (10,000 net + 1,200 VAT)');
SELECT is((SELECT total_vat_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  1200.00::numeric, 'SI output VAT is 1,200.00');
SELECT is((SELECT si_number FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  'SI-000001', 'SI number came from the aligned number series');

SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  'accounting-ready SI can be approved');
SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  'approved SI posts');

SELECT is((SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  'posted', 'SI status is posted');

INSERT INTO t_ctx
SELECT 'si_je', journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si');

SELECT ok((SELECT id FROM t_ctx WHERE key='si_je') IS NOT NULL, 'SI is linked to a journal entry');
SELECT is(
  (SELECT total_debit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')),
  (SELECT total_credit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')),
  'SI journal entry is balanced');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  11200.00::numeric, 'SI JE debits AR 11,200.00');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000008'),
  10000.00::numeric, 'SI JE credits revenue 10,000.00');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000006'),
  1200.00::numeric, 'SI JE credits output VAT 1,200.00');

SELECT results_eq(
  format($q$SELECT tax_kind, tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'SI' AND source_doc_id = %L$q$,
         (SELECT id FROM t_ctx WHERE key='si')),
  $$VALUES ('output_vat'::text, 10000.00::numeric, 1200.00::numeric)$$,
  'SI wrote one output VAT tax detail row: base 10,000.00, tax 1,200.00');

SELECT throws_like(
  format($q$UPDATE sales_invoice_lines SET unit_price = 999999
          WHERE sales_invoice_id = %L$q$, (SELECT id FROM t_ctx WHERE key='si')),
  '%cannot be changed%',
  'posted SI lines are immutable (database trigger)');

-- ════════════════════════════════════════════════════════════════════════════════
-- 2. OFFICIAL RECEIPT: cash 10,976 + CWT 224 (2% of 11,200 gross) clears the SI
-- ════════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222222',
    'branch_id',              '33333333-3333-3333-3333-333333333333',
    'customer_id',            '55555555-5555-5555-5555-555555555555',
    'customer_name_snapshot', 'Withholding Agent Customer Inc',
    'customer_tin_snapshot',  '444-555-666-000',
    'receipt_date',           current_date::text,
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           10976,
    'total_cwt',              224
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key='si'),
    'payment_amount', 10976,
    'cwt_amount',     224,
    'atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140')
  )));

SELECT lives_ok(
  format('SELECT fn_post_receipt(%L)', (SELECT id FROM t_ctx WHERE key='or')),
  'OR with rate-valid CWT posts');

INSERT INTO t_ctx
SELECT 'or_je', journal_entry_id FROM receipts WHERE id = (SELECT id FROM t_ctx WHERE key='or');

SELECT is(
  (SELECT total_debit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='or_je')),
  (SELECT total_credit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='or_je')),
  'OR journal entry is balanced');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='or_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  10976.00::numeric, 'OR JE debits cash 10,976.00');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='or_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  224.00::numeric, 'OR JE debits CWT receivable 224.00');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='or_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  11200.00::numeric, 'OR JE credits AR 11,200.00 — invoice fully cleared');

SELECT is(
  (SELECT (11200
    - COALESCE((SELECT sum(rl.payment_amount + rl.cwt_amount) FROM receipt_lines rl
                JOIN receipts r ON r.id = rl.receipt_id AND r.status = 'posted'
                WHERE rl.invoice_id = (SELECT id FROM t_ctx WHERE key='si')), 0))::numeric),
  0.00::numeric, 'AR subledger: SI outstanding balance is zero after the OR');

SELECT results_eq(
  format($q$SELECT tax_kind, tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'OR' AND source_doc_id = %L AND tax_kind = 'cwt_receivable'$q$,
         (SELECT id FROM t_ctx WHERE key='or')),
  $$VALUES ('cwt_receivable'::text, 11200.00::numeric, 224.00::numeric)$$,
  'OR wrote one CWT receivable tax detail row: base 11,200.00, tax 224.00');

-- ════════════════════════════════════════════════════════════════════════════════
-- 3. VENDOR BILL: 5,000 net + 600 input VAT = 5,600
-- ════════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222222',
    'branch_id',               '33333333-3333-3333-3333-333333333333',
    'supplier_id',             '66666666-6666-6666-6666-666666666666',
    'supplier_name_snapshot',  'Contractor Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-000',
    'supplier_invoice_number', 'SUP-INV-0001',
    'bill_date',               current_date::text
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000009'
  )));

SELECT is((SELECT total_amount FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key='vb')),
  5600.00::numeric, 'VB grand total is 5,600.00 (5,000 net + 600 input VAT)');

SELECT lives_ok(
  format('SELECT fn_approve_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key='vb')),
  'accounting-ready VB can be approved');
SELECT lives_ok(
  format('SELECT fn_post_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key='vb')),
  'approved VB posts');

INSERT INTO t_ctx
SELECT 'vb_je', journal_entry_id FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key='vb');

SELECT is(
  (SELECT total_debit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='vb_je')),
  (SELECT total_credit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='vb_je')),
  'VB journal entry is balanced');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='vb_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000009'),
  5000.00::numeric, 'VB JE debits expense 5,000.00');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='vb_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000004'),
  600.00::numeric, 'VB JE debits input VAT 600.00');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='vb_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000005'),
  5600.00::numeric, 'VB JE credits AP 5,600.00');

SELECT results_eq(
  format($q$SELECT tax_kind, tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'VB' AND source_doc_id = %L$q$,
         (SELECT id FROM t_ctx WHERE key='vb')),
  $$VALUES ('input_vat'::text, 5000.00::numeric, 600.00::numeric)$$,
  'VB wrote one input VAT tax detail row: base 5,000.00, tax 600.00');

-- ════════════════════════════════════════════════════════════════════════════════
-- 4. PAYMENT VOUCHER: cash 5,500 + EWT 100 (2% of 5,000 net) clears the VB
-- ════════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'pv', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222222',
    'branch_id',              '33333333-3333-3333-3333-333333333333',
    'supplier_id',            '66666666-6666-6666-6666-666666666666',
    'supplier_name_snapshot', 'Contractor Supplier Corp',
    'voucher_date',           current_date::text,
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
  format('SELECT fn_post_payment_voucher(%L)', (SELECT id FROM t_ctx WHERE key='pv')),
  'PV with explicit net-of-VAT EWT base posts');

INSERT INTO t_ctx
SELECT 'pv_je', journal_entry_id FROM payment_vouchers WHERE id = (SELECT id FROM t_ctx WHERE key='pv');

SELECT is(
  (SELECT total_debit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='pv_je')),
  (SELECT total_credit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='pv_je')),
  'PV journal entry is balanced');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='pv_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000005'),
  5600.00::numeric, 'PV JE debits AP 5,600.00 — bill fully cleared');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='pv_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  5500.00::numeric, 'PV JE credits cash 5,500.00');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='pv_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000007'),
  100.00::numeric, 'PV JE credits EWT payable 100.00');

SELECT is(
  (SELECT ((SELECT total_amount FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key='vb'))
    - COALESCE((SELECT sum(pvl.payment_amount + pvl.ewt_amount) FROM payment_voucher_lines pvl
                JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id AND pv.status = 'posted'
                WHERE pvl.vendor_bill_id = (SELECT id FROM t_ctx WHERE key='vb')), 0))::numeric),
  0.00::numeric, 'AP subledger: VB outstanding balance is zero after the PV');

SELECT results_eq(
  format($q$SELECT tax_kind, tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'PV' AND source_doc_id = %L AND tax_kind = 'ewt_payable'$q$,
         (SELECT id FROM t_ctx WHERE key='pv')),
  $$VALUES ('ewt_payable'::text, 5000.00::numeric, 100.00::numeric)$$,
  'PV wrote one EWT payable tax detail row: explicit base 5,000.00, tax 100.00');

-- ════════════════════════════════════════════════════════════════════════════════
-- 5. Whole-books invariant: GL nets to zero and controls equal subledger effects
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT sum(debit_amount) - sum(credit_amount) FROM journal_entry_lines
   WHERE company_id = '22222222-2222-2222-2222-222222222222'),
  0.00::numeric, 'all journal entry lines for the company net to zero');

SELECT is(
  (SELECT sum(debit_amount) - sum(credit_amount) FROM journal_entry_lines
   WHERE company_id = '22222222-2222-2222-2222-222222222222'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  0.00::numeric, 'AR control account nets to zero after SI + OR');

SELECT is(
  (SELECT sum(credit_amount) - sum(debit_amount) FROM journal_entry_lines
   WHERE company_id = '22222222-2222-2222-2222-222222222222'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000005'),
  0.00::numeric, 'AP control account nets to zero after VB + PV');

SELECT * FROM finish();
ROLLBACK;
