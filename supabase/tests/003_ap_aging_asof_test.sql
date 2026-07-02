-- ══════════════════════════════════════════════════════════════════════════════
-- AP-AGING-ASOF-001 - Future Payment Voucher Exclusion (PXL-AUD-012)
-- AP-AGING-ASOF-002 - Vendor Credit Application Inclusion (PXL-AUD-019)
--
-- Test book scenarios:
--   001: VB 2026-01-10 for 12,000; PV 2026-02-10 cash 7,000 + EWT 1,000.
--        Aging as of 2026-01-31 shows 12,000; as of 2026-02-28 shows 4,000.
--   002: VB 2026-03-05 for 8,000; posted/applied VC 2026-03-20 for 2,000.
--        Aging as of 2026-03-31 shows 6,000 for that bill.
-- Both must reconcile to the GL AP control account as of each date.
--
-- Uses VAT-exempt lines so document totals equal the test book amounts.
-- PV EWT uses ATC WI010 (10%) on an explicit 10,000 base = 1,000 withheld.
-- Runs against fn_ap_aging_asof (server-side as-of implementation).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111113',
        'authenticated', 'authenticated', 'harness-ap@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111113","role":"authenticated"}', true);

-- ── Company / branch / periods / COA / config / series / supplier ──────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222224', 'corporation',
        'AP Aging Test Corp', 'Software Services', '111-222-333-002',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-ap@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333335',
        '22222222-2222-2222-2222-222222222224', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444446',
        '22222222-2222-2222-2222-222222222224',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222224',
       '44444444-4444-4444-4444-444444444446',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000021', '22222222-2222-2222-2222-222222222224',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000022', '22222222-2222-2222-2222-222222222224',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000023', '22222222-2222-2222-2222-222222222224',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000024', '22222222-2222-2222-2222-222222222224',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000025', '22222222-2222-2222-2222-222222222224',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222224',
        'aaaaaaaa-0000-0000-0000-000000000022',
        'aaaaaaaa-0000-0000-0000-000000000021',
        'aaaaaaaa-0000-0000-0000-000000000023',
        'aaaaaaaa-0000-0000-0000-000000000024',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222224',
       '33333333-3333-3333-3333-333333333335',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV', 'VC');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666667',
        '22222222-2222-2222-2222-222222222224', 'SUPP-001',
        'Aging Test Supplier Corp', '777-888-999-001',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── AP-AGING-ASOF-001 step 1: VB 2026-01-10 for 12,000 (exempt) ────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222224',
    'branch_id',               '33333333-3333-3333-3333-333333333335',
    'supplier_id',             '66666666-6666-6666-6666-666666666667',
    'supplier_name_snapshot',  'Aging Test Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-001',
    'supplier_invoice_number', 'SUP-INV-0001',
    'bill_date',               '2026-01-10',
    'due_date',                '2026-01-25'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional services',
    'quantity',           1,
    'unit_price',         12000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000025'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));

SELECT is((SELECT total_amount FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key='vb1')),
  12000.00::numeric, 'exempt VB total is 12,000.00 with no input VAT');

-- ── AP-AGING-ASOF-001 steps 2-3: PV 2026-02-10, cash 7,000 + EWT 1,000 ─────────
INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222224',
    'branch_id',              '33333333-3333-3333-3333-333333333335',
    'supplier_id',            '66666666-6666-6666-6666-666666666667',
    'supplier_name_snapshot', 'Aging Test Supplier Corp',
    'voucher_date',           '2026-02-10',
    'total_amount',           7000,
    'total_ewt',              1000
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb1'),
    'payment_amount',    7000,
    'ewt_amount',        1000,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WI010'),
    'ewt_tax_base',      10000,
    'ewt_income_nature', 'Professional fees'
  )));

SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key='pv1'));

-- ── AP-AGING-ASOF-001 assertions ───────────────────────────────────────────────
SELECT is(
  (SELECT COALESCE(sum(balance_due), 0) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-01-09')),
  0.00::numeric, 'aging as of 2026-01-09 (before the VB) is empty');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-01-31')),
  12000.00::numeric, 'aging as of 2026-01-31 shows 12,000.00 open — future PV excluded');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-02-09')),
  12000.00::numeric, 'aging as of 2026-02-09 (day before the PV) still shows 12,000.00');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-02-28')),
  4000.00::numeric, 'aging as of 2026-02-28 shows 4,000.00 after cash 7,000 + EWT 1,000');

-- ── AP-AGING-ASOF-002 step 1: VB 2026-03-05 for 8,000 (exempt) ─────────────────
INSERT INTO t_ctx
SELECT 'vb2', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222224',
    'branch_id',               '33333333-3333-3333-3333-333333333335',
    'supplier_id',             '66666666-6666-6666-6666-666666666667',
    'supplier_name_snapshot',  'Aging Test Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-001',
    'supplier_invoice_number', 'SUP-INV-0002',
    'bill_date',               '2026-03-05'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional services',
    'quantity',           1,
    'unit_price',         8000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000025'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb2'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb2'));

-- ── AP-AGING-ASOF-002 step 2: VC 2026-03-20 for 2,000, posted and applied ──────
INSERT INTO t_ctx
SELECT 'vc1', fn_save_vendor_credit(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222224',
    'branch_id',              '33333333-3333-3333-3333-333333333335',
    'supplier_id',            '66666666-6666-6666-6666-666666666667',
    'supplier_name_snapshot', 'Aging Test Supplier Corp',
    'supplier_tin_snapshot',  '777-888-999-001',
    'credit_date',            '2026-03-20'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Service credit',
    'quantity',           1,
    'unit_price',         2000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000025'
  )));

SELECT fn_post_vendor_credit((SELECT id FROM t_ctx WHERE key='vc1'));

INSERT INTO t_ctx
SELECT 'vca1', fn_apply_vendor_credit(
  (SELECT id FROM t_ctx WHERE key='vc1'),
  (SELECT id FROM t_ctx WHERE key='vb2'),
  2000, '2026-03-20'::date, 'Applied per test book AP-AGING-ASOF-002');

SELECT is((SELECT status FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc1')),
  'applied', 'fully applied vendor credit moves to applied status');

-- ── AP-AGING-ASOF-002 assertions ───────────────────────────────────────────────
SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-03-19')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb2')),
  8000.00::numeric, 'second bill shows 8,000.00 open before the credit application date');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-03-31')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb2')),
  6000.00::numeric, 'second bill shows 6,000.00 open as of 2026-03-31 after the applied credit');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-03-31')),
  10000.00::numeric, 'company aging total as of 2026-03-31 is 4,000 + 6,000');

-- ── GL reconciliation: AP control equals aging total at each as-of date ────────
SELECT is(
  (SELECT sum(jel.credit_amount) - sum(jel.debit_amount)
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222224'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000022'
     AND je.je_date <= '2026-01-31'),
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-01-31')),
  'GL AP control as of 2026-01-31 reconciles to the aging total');

SELECT is(
  (SELECT sum(jel.credit_amount) - sum(jel.debit_amount)
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222224'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000022'
     AND je.je_date <= '2026-02-28'),
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-02-28')),
  'GL AP control as of 2026-02-28 reconciles to the aging total');

SELECT is(
  (SELECT sum(jel.credit_amount) - sum(jel.debit_amount)
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222224'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000022'
     AND je.je_date <= '2026-03-31'),
  (SELECT sum(balance_due) FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222224', '2026-03-31')),
  'GL AP control as of 2026-03-31 reconciles to the aging total (VC JE dated on application date)');

SELECT * FROM finish();
ROLLBACK;
