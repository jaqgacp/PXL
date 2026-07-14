-- FORM2307-RECEIVED-CLAIM-001 - governed received-certificate claims
--
-- PXL-AUD-047: received Form 2307 records are no longer direct CRUD. Receipt
-- certificates validate against the receipt-line CWT and unreversed CWT ledger,
-- claims carry an ITR quarter, claimed rows are locked, receipt bounce
-- invalidates linked evidence, and AP-side EWT reversals flag sent issued
-- certificates for supersede.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111247',
        'authenticated', 'authenticated', 'harness-2307-claim@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111247","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222247', 'corporation',
        'Form 2307 Claim Lifecycle Corp', 'Software Services', '111-222-333-247',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-2307-claim@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333347',
        '22222222-2222-2222-2222-222222222247', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444447',
        '22222222-2222-2222-2222-222222222247',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222247',
       '44444444-4444-4444-4444-444444444447',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000247', '22222222-2222-2222-2222-222222222247',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000248', '22222222-2222-2222-2222-222222222247',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000249', '22222222-2222-2222-2222-222222222247',
   '1250', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000250', '22222222-2222-2222-2222-222222222247',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000251', '22222222-2222-2222-2222-222222222247',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000252', '22222222-2222-2222-2222-222222222247',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000253', '22222222-2222-2222-2222-222222222247',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000254', '22222222-2222-2222-2222-222222222247',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000255', '22222222-2222-2222-2222-222222222247',
   '5010', 'Contractor Expense',        'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222247',
        'aaaaaaaa-0000-0000-0000-000000000248',
        'aaaaaaaa-0000-0000-0000-000000000250',
        'aaaaaaaa-0000-0000-0000-000000000251',
        'aaaaaaaa-0000-0000-0000-000000000253',
        'aaaaaaaa-0000-0000-0000-000000000249',
        'aaaaaaaa-0000-0000-0000-000000000252',
        'aaaaaaaa-0000-0000-0000-000000000247',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222247',
       '33333333-3333-3333-3333-333333333347',
       rdt.id, rdt.document_code || '-247-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR', 'VB', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555547',
        '22222222-2222-2222-2222-222222222247', 'CUST-247',
        'Claim Lifecycle Customer Inc', '444-555-666-247',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666747',
        '22222222-2222-2222-2222-222222222247', 'SUPP-247',
        'Claim Lifecycle Supplier Corp', '777-888-999-247',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT ON t_ctx TO authenticated;

-- AR/CWT source: SI 11,200 collected by OR with 11,000 cash + 200 CWT.
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222247',
    'branch_id',               '33333333-3333-3333-3333-333333333347',
    'date',                    '2026-01-15',
    'customer_id',             '55555555-5555-5555-5555-555555555547',
    'customer_name_snapshot',  'Claim Lifecycle Customer Inc',
    'customer_tin_snapshot',   '444-555-666-247',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000254'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222247',
    'branch_id',              '33333333-3333-3333-3333-333333333347',
    'customer_id',            '55555555-5555-5555-5555-555555555547',
    'customer_name_snapshot', 'Claim Lifecycle Customer Inc',
    'customer_tin_snapshot',  '444-555-666-247',
    'receipt_date',           '2026-01-20',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           11000,
    'total_cwt',              200
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key = 'si'),
    'payment_amount', 11000,
    'cwt_amount',     200,
    'atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'cwt_tax_base',   10000
  )));
SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key = 'or'));

INSERT INTO t_ctx
SELECT 'receipt_line', id
FROM receipt_lines
WHERE receipt_id = (SELECT id FROM t_ctx WHERE key = 'or');

SELECT throws_like(
  format($q$SELECT fn_record_form2307_received(%L, '2026-02-01', %L, 'Q1-2026', NULL, NULL, 201)$q$,
         (SELECT id FROM t_ctx WHERE key = 'receipt_line'),
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '%cannot exceed receipt line CWT%',
  'overstated received certificate amount is rejected against receipt-line CWT');

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  format($q$INSERT INTO form_2307_tracking
          (company_id, receipt_line_id, customer_id, cwt_amount_booked, status,
           date_received, atc_code_id, period_covered)
          VALUES (%L, %L, %L, 200, 'received', '2026-02-01', %L, 'Q1-2026')$q$,
         '22222222-2222-2222-2222-222222222247',
         (SELECT id FROM t_ctx WHERE key = 'receipt_line'),
         '55555555-5555-5555-5555-555555555547',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '42501', NULL,
  'authenticated callers cannot directly insert received-certificate rows');
RESET ROLE;

SELECT lives_ok(
  format($q$SELECT fn_record_form2307_received(%L, '2026-02-01', %L, 'Q1-2026', 'cert-247.pdf', 'matched certificate', NULL)$q$,
         (SELECT id FROM t_ctx WHERE key = 'receipt_line'),
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  'received certificate is recorded through the governed RPC');

INSERT INTO t_ctx
SELECT 'tracking', id
FROM form_2307_tracking
WHERE receipt_line_id = (SELECT id FROM t_ctx WHERE key = 'receipt_line');

SELECT results_eq(
  $$SELECT status, cwt_amount_booked, date_received, period_covered
    FROM form_2307_tracking
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'tracking')$$,
  $$VALUES ('received'::text, 200.00::numeric, '2026-02-01'::date, 'Q1-2026'::text)$$,
  'received row stores the exact claimable amount and received period');

SELECT throws_like(
  $$UPDATE form_2307_tracking
    SET cwt_amount_booked = 999
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'tracking')$$,
  '%cannot exceed receipt line CWT%',
  'owner-level direct overclaim update is blocked by the table guard');

SELECT throws_like(
  format($q$SELECT fn_claim_form2307_received(%L, 2026, 5, '2026-04-15')$q$,
         (SELECT id FROM t_ctx WHERE key = 'tracking')),
  '%Invalid claim tax quarter%',
  'claim RPC requires a valid ITR quarter');

SELECT lives_ok(
  format($q$SELECT fn_claim_form2307_received(%L, 2026, 1, '2026-04-15')$q$,
         (SELECT id FROM t_ctx WHERE key = 'tracking')),
  'received certificate can be claimed through the governed RPC');

SELECT results_eq(
  $$SELECT status, claim_tax_year, claim_tax_quarter, (claimed_at IS NOT NULL), (claimed_by IS NOT NULL)
    FROM form_2307_tracking
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'tracking')$$,
  $$VALUES ('claimed'::text, 2026, 1, true, true)$$,
  'claimed row records ITR period, timestamp, and actor');

SELECT throws_like(
  $$UPDATE form_2307_tracking
    SET remarks = 'tampered after claim'
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'tracking')$$,
  '%locked in status claimed%',
  'claimed received-certificate evidence is immutable to direct updates');

SELECT throws_like(
  format($q$SELECT fn_record_form2307_received(%L, '2026-02-02', %L, 'Q1-2026', NULL, NULL, NULL)$q$,
         (SELECT id FROM t_ctx WHERE key = 'receipt_line'),
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '%already claimed%',
  'claimed certificate cannot be edited through the received RPC');

SELECT lives_ok(
  format('SELECT fn_bounce_receipt(%L)', (SELECT id FROM t_ctx WHERE key = 'or')),
  'bouncing the receipt succeeds and invalidates linked 2307 evidence');

SELECT results_eq(
  $$SELECT status, (invalidated_at IS NOT NULL), (invalidated_reason LIKE 'Receipt OR-247-%')
    FROM form_2307_tracking
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'tracking')$$,
  $$VALUES ('invalidated'::text, true, true)$$,
  'bounced receipt marks linked received certificate invalidated');

SELECT is(
  (SELECT COALESCE(SUM(tax_amount), 0)::numeric
   FROM tax_detail_entries
   WHERE source_doc_type = 'OR'
     AND source_doc_id = (SELECT id FROM t_ctx WHERE key = 'or')
     AND tax_kind = 'cwt_receivable'),
  0.00::numeric,
  'bounced receipt CWT tax ledger nets to zero');

SELECT throws_like(
  format($q$SELECT fn_claim_form2307_received(%L, 2026, 1, '2026-04-16')$q$,
         (SELECT id FROM t_ctx WHERE key = 'tracking')),
  '%Only received Form 2307 records can be claimed%',
  'invalidated certificates cannot be claimed');

-- AP/EWT source: sent issued certificate gets flagged for supersede when the
-- source PV is reversed.
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222247',
    'branch_id',               '33333333-3333-3333-3333-333333333347',
    'supplier_id',             '66666666-6666-6666-6666-666666666747',
    'supplier_name_snapshot',  'Claim Lifecycle Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-247',
    'supplier_invoice_number', 'SUP-247-001',
    'bill_date',               '2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000255'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'));

INSERT INTO t_ctx
SELECT 'pv', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222247',
    'branch_id',              '33333333-3333-3333-3333-333333333347',
    'supplier_id',            '66666666-6666-6666-6666-666666666747',
    'supplier_name_snapshot', 'Claim Lifecycle Supplier Corp',
    'supplier_tin_snapshot',  '777-888-999-247',
    'voucher_date',           '2026-01-25',
    'total_amount',           5500,
    'total_ewt',              100
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key = 'vb'),
    'payment_amount',    5500,
    'ewt_amount',        100,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',      5000,
    'ewt_income_nature', 'Contractor services'
  )));
SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key = 'pv'));

SELECT lives_ok(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222247', 2026, 1)$$,
  'issued certificate is generated from posted EWT detail');

INSERT INTO t_ctx
SELECT 'issuance', id
FROM form_2307_issuances
WHERE company_id = '22222222-2222-2222-2222-222222222247'
  AND supplier_id = '66666666-6666-6666-6666-666666666747'
  AND tax_year = 2026
  AND tax_quarter = 1;

SELECT fn_update_form_2307_issued_status((SELECT id FROM t_ctx WHERE key = 'issuance'), 'sent', '2026-04-10');

SELECT results_eq(
  $$SELECT status, total_ewt, requires_supersede
    FROM form_2307_issuances
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'issuance')$$,
  $$VALUES ('sent'::text, 100.00::numeric, false)$$,
  'sent issued certificate is initially not flagged for supersede');

SELECT lives_ok(
  format($q$SELECT fn_cancel_payment_voucher(%L, 'cancel after sent certificate')$q$,
         (SELECT id FROM t_ctx WHERE key = 'pv')),
  'cancelling the EWT source succeeds');

SELECT results_eq(
  $$SELECT status, requires_supersede, (supersede_required_at IS NOT NULL),
           (supersede_reason LIKE 'EWT source PV reversed%')
    FROM form_2307_issuances
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'issuance')$$,
  $$VALUES ('sent'::text, true, true, true)$$,
  'EWT reversal leaves sent certificate intact but flags it for supersede');

SELECT * FROM finish();
ROLLBACK;
