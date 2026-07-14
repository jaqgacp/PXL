-- PXL-AUD-045
-- Sales Invoice expected CWT is validated against the customer's default ATC
-- and carried into Official Receipt CWT evidence.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111153',
  'authenticated', 'authenticated', 'aud045@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111153","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222153', 'corporation',
  'AUD045 CWT Corp', 'Services', '111-222-333-153',
  'vat', 'calendar', 'Unit 1', 'CWT Bldg', 'Makati', 'Metro Manila', '1200',
  'aud045@test.local', 'CWT Signatory', 'President', auth.uid(), auth.uid()
);

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES (
  '11111111-1111-1111-1111-111111111153',
  '22222222-2222-2222-2222-222222222153',
  'owner',
  '11111111-1111-1111-1111-111111111153'
)
ON CONFLICT DO NOTHING;

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333153',
  '22222222-2222-2222-2222-222222222153', 'HO', 'Head Office',
  'Unit 1', 'CWT Bldg', 'Makati', 'Metro Manila', '1200',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444153',
  '22222222-2222-2222-2222-222222222153',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222153',
  '44444444-4444-4444-4444-444444444153',
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
  ('aaaaaaaa-0000-0000-0000-000000000153', '22222222-2222-2222-2222-222222222153', '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000253', '22222222-2222-2222-2222-222222222153', '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000353', '22222222-2222-2222-2222-222222222153', '1250', 'CWT Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000453', '22222222-2222-2222-2222-222222222153', '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000553', '22222222-2222-2222-2222-222222222153', '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, default_cash_account_id,
  vat_payable_account_id, ewt_withheld_account_id,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222153',
  'aaaaaaaa-0000-0000-0000-000000000253',
  'aaaaaaaa-0000-0000-0000-000000000153',
  'aaaaaaaa-0000-0000-0000-000000000453',
  'aaaaaaaa-0000-0000-0000-000000000353',
  auth.uid(), auth.uid()
);

INSERT INTO number_series (
  company_id, branch_id, document_type_id, prefix,
  number_length, starting_number, next_number,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222153',
  '33333333-3333-3333-3333-333333333153',
  rdt.id, rdt.document_code || '-AUD045-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR');

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address,
  is_subject_to_cwt, default_cwt_atc_code_id, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555153',
  '22222222-2222-2222-2222-222222222153', 'CUS-AUD045',
  'AUD045 Customer Inc', '444-555-666-153',
  'Customer HQ', 'Customer HQ',
  true, (SELECT id FROM atc_codes WHERE code = 'WC140' LIMIT 1),
  auth.uid(), auth.uid()
);

SELECT throws_like(
  $q$SELECT fn_save_sales_invoice(NULL,
    jsonb_build_object(
      'company_id', '22222222-2222-2222-2222-222222222153',
      'branch_id', '33333333-3333-3333-3333-333333333153',
      'date', '2026-01-15',
      'customer_id', '55555555-5555-5555-5555-555555555153',
      'customer_name_snapshot', 'AUD045 Customer Inc',
      'customer_tin_snapshot', '444-555-666-153',
      'customer_address_snapshot', 'Customer HQ',
      'cwt_amount_expected', 210
    ),
    jsonb_build_array(jsonb_build_object(
      'description', 'Consulting services',
      'quantity', 1,
      'unit_price', 10000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12' LIMIT 1),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000553'
    )))$q$,
  '%does not match customer ATC expected%',
  'SI expected CWT amount must match the customer default ATC rate'
);

SELECT throws_like(
  $q$SELECT fn_save_sales_invoice(NULL,
    jsonb_build_object(
      'company_id', '22222222-2222-2222-2222-222222222153',
      'branch_id', '33333333-3333-3333-3333-333333333153',
      'date', '2026-01-15',
      'customer_id', '55555555-5555-5555-5555-555555555153',
      'customer_name_snapshot', 'AUD045 Customer Inc',
      'customer_tin_snapshot', '444-555-666-153',
      'customer_address_snapshot', 'Customer HQ',
      'cwt_amount_expected', 100,
      'cwt_atc_code_id', (SELECT id FROM atc_codes WHERE code = 'WC158' LIMIT 1),
      'cwt_tax_base', 10000
    ),
    jsonb_build_array(jsonb_build_object(
      'description', 'Consulting services',
      'quantity', 1,
      'unit_price', 10000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12' LIMIT 1),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000553'
    )))$q$,
  '%must match the customer default CWT ATC%',
  'SI expected CWT ATC must stay synchronized to the customer default ATC'
);

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222153',
    'branch_id', '33333333-3333-3333-3333-333333333153',
    'date', '2026-01-15',
    'customer_id', '55555555-5555-5555-5555-555555555153',
    'customer_name_snapshot', 'AUD045 Customer Inc',
    'customer_tin_snapshot', '444-555-666-153',
    'customer_address_snapshot', 'Customer HQ',
    'cwt_amount_expected', 200
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Consulting services',
    'quantity', 1,
    'unit_price', 10000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12' LIMIT 1),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000553'
  )));

SELECT results_eq(
  format($q$SELECT si.cwt_amount_expected, si.cwt_tax_base, ac.code
          FROM sales_invoices si
          JOIN atc_codes ac ON ac.id = si.cwt_atc_code_id
          WHERE si.id = %L$q$,
         (SELECT id FROM t_ctx WHERE key = 'si')),
  $$VALUES (200.00::numeric, 10000.00::numeric, 'WC140'::text)$$,
  'SI stores expected CWT with customer ATC and VAT-exclusive base'
);

SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si')),
  'SI with validated expected CWT approves'
);

SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key = 'si')),
  'SI with validated expected CWT posts'
);

INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222153',
    'branch_id', '33333333-3333-3333-3333-333333333153',
    'customer_id', '55555555-5555-5555-5555-555555555153',
    'customer_name_snapshot', 'AUD045 Customer Inc',
    'customer_tin_snapshot', '444-555-666-153',
    'receipt_date', '2026-01-16',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'CASH' LIMIT 1),
    'total_amount', 11000,
    'total_cwt', 200
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id', (SELECT id FROM t_ctx WHERE key = 'si'),
    'payment_amount', 11000,
    'cwt_amount', 200,
    'atc_code_id', (SELECT cwt_atc_code_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
    'cwt_tax_base', (SELECT cwt_tax_base FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si'))
  )));

SELECT results_eq(
  format($q$SELECT rl.cwt_amount, rl.cwt_tax_base, ac.code
          FROM receipt_lines rl
          JOIN atc_codes ac ON ac.id = rl.atc_code_id
          WHERE rl.receipt_id = %L$q$,
         (SELECT id FROM t_ctx WHERE key = 'or')),
  $$VALUES (200.00::numeric, 10000.00::numeric, 'WC140'::text)$$,
  'OR line carries the SI expected CWT amount, base, and ATC'
);

SELECT lives_ok(
  format('SELECT fn_post_receipt(%L)', (SELECT id FROM t_ctx WHERE key = 'or')),
  'OR with SI expected CWT posts'
);

SELECT results_eq(
  format($q$SELECT tax_kind, tax_base, tax_amount
          FROM tax_detail_entries
          WHERE source_doc_type = 'OR'
            AND source_doc_id = %L
            AND tax_kind = 'cwt_receivable'$q$,
         (SELECT id FROM t_ctx WHERE key = 'or')),
  $$VALUES ('cwt_receivable'::text, 10000.00::numeric, 200.00::numeric)$$,
  'OR tax detail records the SI expected CWT base and amount'
);

SELECT is(
  (SELECT (11200
    - COALESCE((SELECT sum(rl.payment_amount + rl.cwt_amount)
                FROM receipt_lines rl
                JOIN receipts r ON r.id = rl.receipt_id AND r.status = 'posted'
                WHERE rl.invoice_id = (SELECT id FROM t_ctx WHERE key = 'si')), 0))::numeric),
  0.00::numeric,
  'SI AR balance is cleared by cash plus expected CWT'
);

SELECT * FROM finish();
ROLLBACK;
