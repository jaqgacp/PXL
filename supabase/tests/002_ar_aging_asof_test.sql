-- ══════════════════════════════════════════════════════════════════════════════
-- AR-AGING-ASOF-001 - Future Receipt and Credit Memo Exclusion (PXL-AUD-011)
--
-- Test book scenario:
--   1. Posted SI 2026-01-15 for 10,000.00
--   2. Posted OR 2026-02-15 for 4,000.00
--   3. Applied CM 2026-02-20 for 1,000.00
-- Expected: aging as of 2026-01-31 shows 10,000 open; as of 2026-02-28 shows
-- 5,000 open; aging must reconcile to the GL AR control account as of each date.
--
-- Uses VAT-exempt lines so document totals equal the test book amounts.
-- Runs against fn_ar_aging_asof (server-side as-of implementation).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111112',
        'authenticated', 'authenticated', 'harness-ar@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111112","role":"authenticated"}', true);

-- ── Company / branch / periods / COA / config / series / customer ──────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222223', 'corporation',
        'AR Aging Test Corp', 'Software Services', '111-222-333-001',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-ar@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333334',
        '22222222-2222-2222-2222-222222222223', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444445',
        '22222222-2222-2222-2222-222222222223',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222223',
       '44444444-4444-4444-4444-444444444445',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000011', '22222222-2222-2222-2222-222222222223',
   '1010', 'Cash in Bank',        'asset',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000012', '22222222-2222-2222-2222-222222222223',
   '1200', 'Accounts Receivable', 'asset',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000013', '22222222-2222-2222-2222-222222222223',
   '4010', 'Service Revenue',     'revenue', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id,
        default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222223',
        'aaaaaaaa-0000-0000-0000-000000000012',
        'aaaaaaaa-0000-0000-0000-000000000011',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222223',
       '33333333-3333-3333-3333-333333333334',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR', 'CM');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555556',
        '22222222-2222-2222-2222-222222222223', 'CUST-001',
        'Aging Test Customer Inc', '444-555-666-001',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

-- ── Step 1: SI 2026-01-15 for 10,000 (exempt) ─────────────────────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222223',
    'branch_id',                 '33333333-3333-3333-3333-333333333334',
    'date',                      '2026-01-15',
    'due_date',                  '2026-01-30',
    'customer_id',               '55555555-5555-5555-5555-555555555556',
    'customer_name_snapshot',    'Aging Test Customer Inc',
    'customer_tin_snapshot',     '444-555-666-001',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Exempt services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000013'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

SELECT is((SELECT total_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  10000.00::numeric, 'exempt SI total is 10,000.00 with no VAT');

-- ── Step 2: OR 2026-02-15 for 4,000 ───────────────────────────────────────────
INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222223',
    'branch_id',              '33333333-3333-3333-3333-333333333334',
    'customer_id',            '55555555-5555-5555-5555-555555555556',
    'customer_name_snapshot', 'Aging Test Customer Inc',
    'customer_tin_snapshot',  '444-555-666-001',
    'receipt_date',           '2026-02-15',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           4000,
    'total_cwt',              0
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key='si'),
    'payment_amount', 4000,
    'cwt_amount',     0
  )));

SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key='or'));

-- ── Step 3: applied CM 2026-02-20 for 1,000 (exempt) ──────────────────────────
INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222223',
    'branch_id',              '33333333-3333-3333-3333-333333333334',
    'customer_id',            '55555555-5555-5555-5555-555555555556',
    'customer_name_snapshot', 'Aging Test Customer Inc',
    'customer_tin_snapshot',  '444-555-666-001',
    'invoice_id',             (SELECT id FROM t_ctx WHERE key='si'),
    'cm_date',                '2026-02-20',
    'reason_code_id',         (SELECT id FROM ref_reason_codes WHERE code = 'CM_OTHER')
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Billing adjustment',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000013'
  )),
  'applied');

SELECT is((SELECT status FROM credit_memos WHERE id = (SELECT id FROM t_ctx WHERE key='cm')),
  'applied', 'credit memo is applied with a posted JE');

-- ── Aging assertions ───────────────────────────────────────────────────────────
SELECT is(
  (SELECT COALESCE(sum(balance_due), 0) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-01-14')),
  0.00::numeric, 'aging as of 2026-01-14 (before the SI) is empty');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-01-31')),
  10000.00::numeric, 'aging as of 2026-01-31 shows 10,000.00 open — future OR/CM excluded');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-02-14')),
  10000.00::numeric, 'aging as of 2026-02-14 (day before the OR) still shows 10,000.00');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-02-19')),
  6000.00::numeric, 'aging as of 2026-02-19 (after OR, before CM) shows 6,000.00');

SELECT is(
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-02-28')),
  5000.00::numeric, 'aging as of 2026-02-28 shows 5,000.00 after the OR and applied CM');

SELECT is(
  (SELECT days_overdue FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-02-28') LIMIT 1),
  29, 'days overdue counts from the 2026-01-30 due date');

-- ── GL reconciliation: AR control equals aging total at each as-of date ────────
SELECT is(
  (SELECT sum(jel.debit_amount) - sum(jel.credit_amount)
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222223'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000012'
     AND je.je_date <= '2026-01-31'),
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-01-31')),
  'GL AR control as of 2026-01-31 reconciles to the aging total');

SELECT is(
  (SELECT sum(jel.debit_amount) - sum(jel.credit_amount)
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE jel.company_id = '22222222-2222-2222-2222-222222222223'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000012'
     AND je.je_date <= '2026-02-28'),
  (SELECT sum(balance_due) FROM fn_ar_aging_asof(
     '22222222-2222-2222-2222-222222222223', '2026-02-28')),
  'GL AR control as of 2026-02-28 reconciles to the aging total');

SELECT * FROM finish();
ROLLBACK;
