-- CASH-SALE-RECEIPT-TOTAL-001 - cash-sale OR header semantics
--
-- PXL-AUD-046: receipts.total_amount means cash received for standard ORs and
-- cash-sale ORs. A cash sale with 11,200 gross and 200 CWT should store
-- total_amount = 11,000 and total_cwt = 200; bouncing it must reverse the
-- original 11,200 JE exactly, not an overstated gross + CWT amount.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111246',
        'authenticated', 'authenticated', 'harness-cash-sale-total@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111246","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222246', 'corporation',
        'Cash Sale Receipt Total Corp', 'Retail services', '111-222-333-246',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-cash-sale-total@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333346',
        '22222222-2222-2222-2222-222222222246', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444446',
        '22222222-2222-2222-2222-222222222246',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222246',
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
  ('aaaaaaaa-0000-0000-0000-000000000246', '22222222-2222-2222-2222-222222222246',
   '1010', 'Cash in Bank',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000247', '22222222-2222-2222-2222-222222222246',
   '1200', 'Accounts Receivable','asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000248', '22222222-2222-2222-2222-222222222246',
   '1250', 'CWT Receivable',     'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000249', '22222222-2222-2222-2222-222222222246',
   '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000250', '22222222-2222-2222-2222-222222222246',
   '4010', 'Service Revenue',    'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        ewt_withheld_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222246',
        'aaaaaaaa-0000-0000-0000-000000000247',
        'aaaaaaaa-0000-0000-0000-000000000249',
        'aaaaaaaa-0000-0000-0000-000000000248',
        'aaaaaaaa-0000-0000-0000-000000000246',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222246',
       '33333333-3333-3333-3333-333333333346',
       rdt.id, rdt.document_code || '-246-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('OR', 'CS');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555546',
        '22222222-2222-2222-2222-222222222246', 'CUST-246',
        'Cash Sale Customer Inc', '444-555-666-246',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'cash_sale_receipt', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222246',
    'branch_id',              '33333333-3333-3333-3333-333333333346',
    'date',                   '2026-03-05',
    'customer_id',            '55555555-5555-5555-5555-555555555546',
    'customer_name_snapshot', 'Cash Sale Customer Inc',
    'customer_tin_snapshot',  '444-555-666-246',
    'cwt_atc_id',             (SELECT id FROM atc_codes WHERE code = 'WC140')::text
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Walk-in service',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000250'
  )),
  200)->>'receipt_id')::uuid;

INSERT INTO t_ctx
SELECT 'cash_sale_invoice', invoice_id
FROM receipt_lines
WHERE receipt_id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt');

INSERT INTO t_ctx
SELECT 'original_or_je', journal_entry_id
FROM receipts
WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt');

SELECT results_eq(
  $$SELECT total_amount, total_cwt, total_amount + total_cwt
    FROM receipts
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt')$$,
  $$VALUES (11000.00::numeric, 200.00::numeric, 11200.00::numeric)$$,
  'cash-sale receipt header stores cash received, CWT, and gross clearance separately');

SELECT results_eq(
  $$SELECT SUM(payment_amount)::numeric, SUM(cwt_amount)::numeric,
           SUM(payment_amount + cwt_amount)::numeric
    FROM receipt_lines
    WHERE receipt_id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt')$$,
  $$VALUES (11000.00::numeric, 200.00::numeric, 11200.00::numeric)$$,
  'cash-sale receipt lines carry the same cash/CWT/gross split');

SELECT is(
  (SELECT total_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_invoice')),
  11200.00::numeric,
  'cash-sale invoice remains gross 11,200.00');

SELECT results_eq(
  $$SELECT total_debit, total_credit
    FROM journal_entries
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'original_or_je')$$,
  $$VALUES (11200.00::numeric, 11200.00::numeric)$$,
  'original cash-sale OR JE totals equal the gross amount cleared from AR');

SELECT results_eq(
  $$SELECT SUM(debit_amount)::numeric, SUM(credit_amount)::numeric
    FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'original_or_je')$$,
  $$VALUES (11200.00::numeric, 11200.00::numeric)$$,
  'original cash-sale OR JE header equals its line sums');

SELECT lives_ok(
  format('SELECT fn_bounce_receipt(%L)', (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt')),
  'bouncing the cash-sale receipt succeeds');

INSERT INTO t_ctx
SELECT 'reversal_or_je', reversed_by_je_id
FROM journal_entries
WHERE id = (SELECT id FROM t_ctx WHERE key = 'original_or_je');

SELECT is(
  (SELECT status FROM receipts WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt')),
  'bounced',
  'cash-sale receipt is marked bounced');

SELECT ok(
  (SELECT id FROM t_ctx WHERE key = 'reversal_or_je') IS NOT NULL,
  'bounce creates a reversal JE linked from the original JE');

SELECT results_eq(
  $$SELECT total_debit, total_credit
    FROM journal_entries
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'reversal_or_je')$$,
  $$VALUES (11200.00::numeric, 11200.00::numeric)$$,
  'reversal JE totals equal gross 11,200.00, not gross plus CWT');

SELECT isnt(
  (SELECT total_debit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key = 'reversal_or_je')),
  11400.00::numeric,
  'reversal JE is not overstated to 11,400.00');

SELECT results_eq(
  $$SELECT SUM(debit_amount)::numeric, SUM(credit_amount)::numeric
    FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'reversal_or_je')$$,
  $$VALUES (11200.00::numeric, 11200.00::numeric)$$,
  'reversal JE header equals its line sums');

SELECT is(
  (SELECT COALESCE(SUM(tax_amount), 0)::numeric
   FROM tax_detail_entries
   WHERE source_doc_type = 'OR'
     AND source_doc_id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt')
     AND tax_kind = 'cwt_receivable'),
  0.00::numeric,
  'bounced cash-sale receipt CWT tax detail nets to zero');

SELECT results_eq(
  $$SELECT total_amount, total_cwt, total_amount + total_cwt
    FROM receipts
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale_receipt')$$,
  $$VALUES (11000.00::numeric, 200.00::numeric, 11200.00::numeric)$$,
  'bounce preserves the corrected cash/CWT/gross receipt header split');

SELECT * FROM finish();
ROLLBACK;
