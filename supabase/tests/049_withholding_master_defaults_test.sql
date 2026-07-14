-- WHT-MASTER-DEFAULTS-001 - Supplier/Customer withholding default flows
-- PXL-AUD-008
--
-- Proves the current single-master withholding defaults are executable evidence:
-- supplier AP EWT defaults derive source-basis VB EWT and Form 2307 issued
-- lines, while customer CWT defaults feed receipt-line CWT tax detail and the
-- Form 2307 received lifecycle. Also guards that defaults cannot point at FWT
-- ATCs.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(15);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111149',
  'authenticated', 'authenticated', 'aud008@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111149","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222149', 'corporation',
  'AUD008 Defaults Corp', 'Services', '111-222-333-149',
  'vat', 'calendar', 'Unit 1', 'Defaults Bldg', 'Makati', 'Metro Manila', '1200',
  'aud008@test.local', 'Default Signatory', 'President', auth.uid(), auth.uid()
);

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES (
  '11111111-1111-1111-1111-111111111149',
  '22222222-2222-2222-2222-222222222149',
  'owner',
  '11111111-1111-1111-1111-111111111149'
)
ON CONFLICT DO NOTHING;

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333149',
  '22222222-2222-2222-2222-222222222149', 'HO', 'Head Office',
  'Unit 1', 'Defaults Bldg', 'Makati', 'Metro Manila', '1200',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444149',
  '22222222-2222-2222-2222-222222222149',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222149',
  '44444444-4444-4444-4444-444444444149',
  m,
  to_char(make_date(2026, m, 1), 'Mon YYYY'),
  make_date(2026, m, 1),
  (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
  false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active,
  created_by, updated_by
) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000149', '22222222-2222-2222-2222-222222222149', '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000249', '22222222-2222-2222-2222-222222222149', '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000349', '22222222-2222-2222-2222-222222222149', '1250', 'CWT Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000449', '22222222-2222-2222-2222-222222222149', '1300', 'Input VAT', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000549', '22222222-2222-2222-2222-222222222149', '2010', 'Accounts Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000649', '22222222-2222-2222-2222-222222222149', '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000749', '22222222-2222-2222-2222-222222222149', '2150', 'EWT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000849', '22222222-2222-2222-2222-222222222149', '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000949', '22222222-2222-2222-2222-222222222149', '5010', 'Professional Fees Expense', 'expense', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id,
  default_cash_account_id, vat_payable_account_id,
  input_vat_account_id, ewt_payable_account_id, ewt_withheld_account_id,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222149',
  'aaaaaaaa-0000-0000-0000-000000000249',
  'aaaaaaaa-0000-0000-0000-000000000549',
  'aaaaaaaa-0000-0000-0000-000000000149',
  'aaaaaaaa-0000-0000-0000-000000000649',
  'aaaaaaaa-0000-0000-0000-000000000449',
  'aaaaaaaa-0000-0000-0000-000000000749',
  'aaaaaaaa-0000-0000-0000-000000000349',
  auth.uid(), auth.uid()
);

INSERT INTO number_series (
  company_id, branch_id, document_type_id, prefix,
  number_length, starting_number, next_number,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222149',
  '33333333-3333-3333-3333-333333333149',
  rdt.id, rdt.document_code || '-AUD008-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR', 'VB');

SELECT throws_like(
  $q$INSERT INTO suppliers (
       company_id, supplier_code, registered_name, tin, registered_address,
       is_subject_to_ewt, default_atc_code_id, created_by, updated_by
     ) VALUES (
       '22222222-2222-2222-2222-222222222149', 'SUP-FWT',
       'Invalid FWT Supplier', '777-888-999-149', 'Supplier HQ',
       true, (SELECT id FROM atc_codes WHERE code = 'WC001' LIMIT 1),
       auth.uid(), auth.uid()
     )$q$,
  '%Default supplier EWT ATC must be an active, current EWT ATC code%',
  'supplier default rejects a current FWT ATC'
);

SELECT throws_like(
  $q$INSERT INTO customers (
       company_id, customer_code, registered_name, tin,
       registered_address, delivery_address,
       is_subject_to_cwt, default_cwt_atc_code_id, created_by, updated_by
     ) VALUES (
       '22222222-2222-2222-2222-222222222149', 'CUS-FWT',
       'Invalid FWT Customer', '444-555-666-149',
       'Customer HQ', 'Customer HQ',
       true, (SELECT id FROM atc_codes WHERE code = 'WC001' LIMIT 1),
       auth.uid(), auth.uid()
     )$q$,
  '%Default customer CWT ATC must be an active, current withholding ATC code%',
  'customer CWT default rejects a current FWT ATC'
);

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin, registered_address,
  is_subject_to_ewt, default_atc_code_id, created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666149',
  '22222222-2222-2222-2222-222222222149', 'SUP-AUD008',
  'AUD008 Supplier Inc', '777-888-999-008', 'Supplier HQ',
  false, (SELECT id FROM atc_codes WHERE code = 'WC140' LIMIT 1),
  auth.uid(), auth.uid()
);

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address,
  is_subject_to_cwt, default_cwt_atc_code_id, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555149',
  '22222222-2222-2222-2222-222222222149', 'CUS-AUD008',
  'AUD008 Customer Inc', '444-555-666-008',
  'Customer HQ', 'Customer HQ',
  false, (SELECT id FROM atc_codes WHERE code = 'WC140' LIMIT 1),
  auth.uid(), auth.uid()
);

SELECT results_eq(
  $$SELECT s.is_subject_to_ewt, ac.code
      FROM suppliers s
      JOIN atc_codes ac ON ac.id = s.default_atc_code_id
     WHERE s.id = '66666666-6666-6666-6666-666666666149'$$,
  $$VALUES (true, 'WC140'::text)$$,
  'supplier default ATC marks the supplier subject to AP EWT'
);

SELECT results_eq(
  $$SELECT c.is_subject_to_cwt, ac.code
      FROM customers c
      JOIN atc_codes ac ON ac.id = c.default_cwt_atc_code_id
     WHERE c.id = '55555555-5555-5555-5555-555555555149'$$,
  $$VALUES (true, 'WC140'::text)$$,
  'customer default CWT ATC marks the customer subject to CWT'
);

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222149',
    'branch_id', '33333333-3333-3333-3333-333333333149',
    'supplier_id', '66666666-6666-6666-6666-666666666149',
    'supplier_name_snapshot', 'AUD008 Supplier Inc',
    'supplier_tin_snapshot', '777-888-999-008',
    'supplier_invoice_number', 'SUP-AUD008-001',
    'bill_date', '2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Professional services',
    'quantity', 1,
    'unit_price', 10000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000949'
  )));

SELECT results_eq(
  format($q$SELECT vbl.ewt_tax_base, vbl.ewt_amount, ac.code
            FROM vendor_bill_lines vbl
            JOIN atc_codes ac ON ac.id = vbl.ewt_atc_code_id
           WHERE vbl.vendor_bill_id = %L$q$, (SELECT id FROM t_ctx WHERE key = 'vb')),
  $$VALUES (10000.00::numeric, 200.00::numeric, 'WC140'::text)$$,
  'vendor bill line derives EWT ATC, base, and amount from the supplier default'
);

SELECT is(
  (SELECT ewt_amount_expected FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb')),
  200.00::numeric,
  'vendor bill header expected EWT follows the supplier default'
);

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'));

SELECT lives_ok(
  format('SELECT fn_post_vendor_bill(%L)', (SELECT id FROM t_ctx WHERE key = 'vb')),
  'supplier-default vendor bill posts with source-basis EWT'
);

SELECT results_eq(
  format($q$SELECT source_doc_type, tax_base, tax_amount, counterparty_id
            FROM tax_detail_entries
           WHERE source_doc_type = 'VB'
             AND source_doc_id = %L
             AND tax_kind = 'ewt_payable'$q$, (SELECT id FROM t_ctx WHERE key = 'vb')),
  $$VALUES ('VB'::text, 10000.00::numeric, 200.00::numeric, '66666666-6666-6666-6666-666666666149'::uuid)$$,
  'supplier-default VB writes supplier-linked source EWT tax detail'
);

SELECT is(
  (fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222149', 2026, 1)->>'generated_count')::INT,
  1,
  'supplier-default EWT generates an issued Form 2307 certificate'
);

SELECT results_eq(
  $$SELECT l.atc_code, l.tax_base, l.tax_withheld, l.month_1_tax_withheld
      FROM form_2307_issuance_lines l
      JOIN form_2307_issuances i ON i.id = l.issuance_id
     WHERE i.company_id = '22222222-2222-2222-2222-222222222149'
       AND i.supplier_id = '66666666-6666-6666-6666-666666666149'
       AND i.tax_year = 2026
       AND i.tax_quarter = 1$$,
  $$VALUES ('WC140'::text, 10000.00::numeric, 200.00::numeric, 200.00::numeric)$$,
  'issued Form 2307 line preserves supplier default ATC and source-basis amount'
);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222149',
    'branch_id', '33333333-3333-3333-3333-333333333149',
    'date', '2026-02-10',
    'customer_id', '55555555-5555-5555-5555-555555555149',
    'customer_name_snapshot', 'AUD008 Customer Inc',
    'customer_tin_snapshot', '444-555-666-008',
    'customer_address_snapshot', 'Customer HQ'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Consulting services',
    'quantity', 1,
    'unit_price', 10000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000849'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

SELECT is(
  (SELECT total_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
  11200.00::numeric,
  'sales invoice total is 11,200.00 before customer-default CWT collection'
);

INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222149',
    'branch_id', '33333333-3333-3333-3333-333333333149',
    'customer_id', '55555555-5555-5555-5555-555555555149',
    'customer_name_snapshot', 'AUD008 Customer Inc',
    'customer_tin_snapshot', '444-555-666-008',
    'receipt_date', '2026-02-20',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'CASH' LIMIT 1)
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id', (SELECT id FROM t_ctx WHERE key = 'si'),
    'payment_amount', 11000,
    'cwt_amount', 200,
    'atc_code_id', (SELECT default_cwt_atc_code_id FROM customers WHERE id = '55555555-5555-5555-5555-555555555149'),
    'cwt_tax_base', 10000
  )));

SELECT results_eq(
  format($q$SELECT rl.cwt_tax_base, rl.cwt_amount, ac.code
            FROM receipt_lines rl
            JOIN atc_codes ac ON ac.id = rl.atc_code_id
           WHERE rl.receipt_id = %L$q$, (SELECT id FROM t_ctx WHERE key = 'or')),
  $$VALUES (10000.00::numeric, 200.00::numeric, 'WC140'::text)$$,
  'receipt line uses the customer default CWT ATC on the VAT-exclusive base'
);

SELECT lives_ok(
  format('SELECT fn_post_receipt(%L)', (SELECT id FROM t_ctx WHERE key = 'or')),
  'customer-default receipt posts with CWT'
);

SELECT results_eq(
  format($q$SELECT source_doc_type, tax_base, tax_amount, counterparty_id
            FROM tax_detail_entries
           WHERE source_doc_type = 'OR'
             AND source_doc_id = %L
             AND tax_kind = 'cwt_receivable'$q$, (SELECT id FROM t_ctx WHERE key = 'or')),
  $$VALUES ('OR'::text, 10000.00::numeric, 200.00::numeric, '55555555-5555-5555-5555-555555555149'::uuid)$$,
  'customer-default receipt writes customer-linked CWT tax detail'
);

INSERT INTO t_ctx
SELECT 'receipt_line', id FROM receipt_lines WHERE receipt_id = (SELECT id FROM t_ctx WHERE key = 'or');

INSERT INTO t_ctx
SELECT 'received_2307',
       fn_record_form2307_received(
         (SELECT id FROM t_ctx WHERE key = 'receipt_line'),
         '2026-03-01',
         (SELECT default_cwt_atc_code_id FROM customers WHERE id = '55555555-5555-5555-5555-555555555149'),
         'Q1-2026',
         NULL,
         'customer default CWT certificate',
         200
       );

SELECT results_eq(
  $$SELECT ft.status, ft.cwt_amount_booked, ac.code
      FROM form_2307_tracking ft
      JOIN atc_codes ac ON ac.id = ft.atc_code_id
     WHERE ft.id = (SELECT id FROM t_ctx WHERE key = 'received_2307')$$,
  $$VALUES ('received'::text, 200.00::numeric, 'WC140'::text)$$,
  'customer-default CWT evidence is claimable through the received Form 2307 RPC'
);

SELECT * FROM finish();
ROLLBACK;
