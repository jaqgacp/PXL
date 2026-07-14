-- WITHHOLDING-TRACE-DRILLDOWN-001
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111148',
  'authenticated', 'authenticated', 'aud049@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111148","role":"authenticated"}',
  true
);

SET LOCAL session_replication_role = replica;

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222148', 'corporation',
  'AUD049 Trace Corp', 'Services', '111-222-333-148',
  'vat', 'calendar', 'Unit 1', 'Trace Bldg', 'Makati', 'Metro Manila', '1200',
  'aud049@test.local', 'Trace Signatory', 'President',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES (
  '11111111-1111-1111-1111-111111111148',
  '22222222-2222-2222-2222-222222222148',
  'owner',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333148',
  '22222222-2222-2222-2222-222222222148', 'HO', 'Head Office',
  'Unit 1', 'Trace Bldg', 'Makati', 'Metro Manila', '1200',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin,
  registered_address, created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666148',
  '22222222-2222-2222-2222-222222222148', 'SUP-148',
  'AUD049 Supplier Inc', '777-888-999-148', 'Supplier HQ',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555148',
  '22222222-2222-2222-2222-222222222148', 'CUS-148',
  'AUD049 Customer Inc', '444-555-666-148',
  'Customer HQ', 'Customer HQ',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO payment_vouchers (
  id, company_id, branch_id, supplier_id,
  supplier_name_snapshot, supplier_tin_snapshot,
  voucher_number, voucher_date, total_amount, total_ewt,
  status, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777148',
  '22222222-2222-2222-2222-222222222148',
  '33333333-3333-3333-3333-333333333148',
  '66666666-6666-6666-6666-666666666148',
  'AUD049 Supplier Inc', '777-888-999-148',
  'PV-AUD049', '2026-07-10', 99, 1, 'posted',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO cash_purchases (
  id, company_id, branch_id, cp_number, transaction_date,
  supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
  payment_method, total_taxable_amount, total_input_vat_amount,
  total_ewt_amount, total_amount, status, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777248',
  '22222222-2222-2222-2222-222222222148',
  '33333333-3333-3333-3333-333333333148',
  'CP-AUD049', '2026-07-12',
  '66666666-6666-6666-6666-666666666148',
  'AUD049 Supplier Inc', '777-888-999-148',
  'cash', 200, 24, 4, 220, 'posted',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO check_vouchers (
  id, company_id, branch_id, cv_number, voucher_date,
  bank_account_id, check_number, check_date, payee, payee_tin,
  supplier_id, total_gross_amount, total_ewt_amount, atc_code_id,
  ewt_rate, ewt_tax_base, particulars, status, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777348',
  '22222222-2222-2222-2222-222222222148',
  '33333333-3333-3333-3333-333333333148',
  'CV-AUD049', '2026-07-14',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0148',
  'CHK-AUD049', '2026-07-14', 'AUD049 Supplier Inc', '777-888-999-148',
  '66666666-6666-6666-6666-666666666148',
  500, 5,
  (SELECT id FROM atc_codes WHERE code = 'WC158' ORDER BY effective_from NULLS FIRST LIMIT 1),
  1, 500, 'AUD049 trace check', 'posted',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO receipts (
  id, company_id, branch_id, customer_id,
  customer_name_snapshot, customer_tin_snapshot,
  receipt_number, receipt_date, payment_mode_id,
  total_amount, total_cwt, status, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777448',
  '22222222-2222-2222-2222-222222222148',
  '33333333-3333-3333-3333-333333333148',
  '55555555-5555-5555-5555-555555555148',
  'AUD049 Customer Inc', '444-555-666-148',
  'OR-AUD049', '2026-07-16',
  (SELECT id FROM ref_payment_modes WHERE code = 'CASH' LIMIT 1),
  297, 3, 'posted',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO tax_detail_entries (
  id, company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, atc_code_id, tax_base, tax_rate, tax_amount,
  posting_date, document_date,
  counterparty_id, counterparty_tin, counterparty_name, income_nature
) VALUES
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0148',
    '22222222-2222-2222-2222-222222222148',
    '33333333-3333-3333-3333-333333333148',
    'PV', '77777777-7777-7777-7777-777777777148',
    'ewt_payable',
    (SELECT id FROM atc_codes WHERE code = 'WC158' ORDER BY effective_from NULLS FIRST LIMIT 1),
    100, 1, 1, '2026-07-10', '2026-07-10',
    '66666666-6666-6666-6666-666666666148',
    '777-888-999-148', 'AUD049 Supplier Inc', 'Trace goods'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0248',
    '22222222-2222-2222-2222-222222222148',
    '33333333-3333-3333-3333-333333333148',
    'CP', '77777777-7777-7777-7777-777777777248',
    'ewt_payable',
    (SELECT id FROM atc_codes WHERE code = 'WC160' ORDER BY effective_from NULLS FIRST LIMIT 1),
    200, 2, 4, '2026-07-12', '2026-07-12',
    '66666666-6666-6666-6666-666666666148',
    '777-888-999-148', 'AUD049 Supplier Inc', 'Trace services'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0348',
    '22222222-2222-2222-2222-222222222148',
    '33333333-3333-3333-3333-333333333148',
    'CV', '77777777-7777-7777-7777-777777777348',
    'ewt_payable',
    (SELECT id FROM atc_codes WHERE code = 'WC158' ORDER BY effective_from NULLS FIRST LIMIT 1),
    500, 1, 5, '2026-07-14', '2026-07-14',
    '66666666-6666-6666-6666-666666666148',
    '777-888-999-148', 'AUD049 Supplier Inc', 'Trace goods'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0448',
    '22222222-2222-2222-2222-222222222148',
    '33333333-3333-3333-3333-333333333148',
    'OR', '77777777-7777-7777-7777-777777777448',
    'cwt_receivable',
    (SELECT id FROM atc_codes WHERE code = 'WC158' ORDER BY effective_from NULLS FIRST LIMIT 1),
    300, 1, 3, '2026-07-16', '2026-07-16',
    '55555555-5555-5555-5555-555555555148',
    '444-555-666-148', 'AUD049 Customer Inc', 'Trace customer CWT'
  );

INSERT INTO form_2307_issuances (
  id, company_id, supplier_id, tax_year, tax_quarter,
  total_tax_base, total_ewt, status, created_by, updated_by
) VALUES (
  '99999999-9999-9999-9999-999999999148',
  '22222222-2222-2222-2222-222222222148',
  '66666666-6666-6666-6666-666666666148',
  2026, 3, 800, 10, 'generated',
  '11111111-1111-1111-1111-111111111148',
  '11111111-1111-1111-1111-111111111148'
);

INSERT INTO form_2307_issuance_lines (
  id, issuance_id, company_id, atc_code_id, atc_code, nature_of_income,
  month_1_tax_base, month_1_tax_withheld,
  month_2_tax_base, month_2_tax_withheld,
  month_3_tax_base, month_3_tax_withheld,
  tax_base, tax_rate, tax_withheld
) VALUES
  (
    '99999999-9999-9999-9999-999999999248',
    '99999999-9999-9999-9999-999999999148',
    '22222222-2222-2222-2222-222222222148',
    (SELECT id FROM atc_codes WHERE code = 'WC158' ORDER BY effective_from NULLS FIRST LIMIT 1),
    'WC158', 'Trace goods',
    600, 6, 0, 0, 0, 0, 600, 1, 6
  ),
  (
    '99999999-9999-9999-9999-999999999348',
    '99999999-9999-9999-9999-999999999148',
    '22222222-2222-2222-2222-222222222148',
    (SELECT id FROM atc_codes WHERE code = 'WC160' ORDER BY effective_from NULLS FIRST LIMIT 1),
    'WC160', 'Trace services',
    200, 4, 0, 0, 0, 0, 200, 2, 4
  );

RESET session_replication_role;

SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'ewt_payable',
       'source_doc_type', 'CV',
       'source_doc_id', '77777777-7777-7777-7777-777777777348'
     )
   )
   WHERE trace_context->'tax_detail_ids' ? 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0348'),
  1,
  'CV EWT amount trace includes its exact tax_detail_entries row'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'ewt_payable',
       'source_doc_type', 'CV',
       'source_doc_id', '77777777-7777-7777-7777-777777777348'
     )
   )),
  1,
  'CV EWT amount trace resolves to its exact tax_detail_entries row'
);

SELECT is(
  (SELECT SUM((trace_context->>'tax_amount')::NUMERIC)
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'ewt_payable',
       'source_doc_type', 'CV',
       'source_doc_id', '77777777-7777-7777-7777-777777777348'
     )
   )),
  5.00::NUMERIC,
  'CV EWT trace context exposes the withheld amount'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'ewt_payable',
       'counterparty_id', '66666666-6666-6666-6666-666666666148',
       'atc_code', 'WC158',
       'income_nature', 'Trace goods',
       'tax_rate', '1',
       'active_only', 'true',
       'date_from', '2026-07-01',
       'date_to', '2026-09-30'
     )
   )),
  2,
  'QAP payee/ATC/nature/rate trace resolves the two exact source rows'
);

SELECT is(
  (SELECT SUM((trace_context->>'tax_amount')::NUMERIC)
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'ewt_payable',
       'counterparty_id', '66666666-6666-6666-6666-666666666148',
       'atc_code', 'WC158',
       'income_nature', 'Trace goods',
       'tax_rate', '1',
       'active_only', 'true',
       'date_from', '2026-07-01',
       'date_to', '2026-09-30'
     )
   )),
  6.00::NUMERIC,
  'QAP exact trace totals match the visible QAP withholding row'
);

SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'form_2307_issued',
     jsonb_build_object(
       'record_id', '99999999-9999-9999-9999-999999999148',
       'atc_code', 'WC160',
       'income_nature', 'Trace services',
       'tax_rate', '2'
     )
   )),
  'CP',
  'Form 2307 line trace filters to the matching cash-purchase source'
);

SELECT is(
  (SELECT (trace_context->>'tax_withheld')::NUMERIC
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'form_2307_issued',
     jsonb_build_object(
       'record_id', '99999999-9999-9999-9999-999999999148',
       'atc_code', 'WC160',
       'income_nature', 'Trace services',
       'tax_rate', '2'
     )
   )),
  4.00::NUMERIC,
  'Form 2307 line trace context exposes the line withheld amount'
);

SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'cwt_receivable',
       'source_doc_type', 'OR',
       'source_doc_id', '77777777-7777-7777-7777-777777777448'
     )
   )),
  'OR',
  'Cash-sale CWT trace resolves through the linked official receipt'
);

SELECT is(
  (SELECT accounting_trace_route
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222148',
     'tax',
     jsonb_build_object(
       'tax_kind', 'ewt_payable',
       'source_doc_type', 'CP',
       'source_doc_id', '77777777-7777-7777-7777-777777777248'
     )
   )),
  '/accounting-trace?sourceType=CP&sourceId=77777777-7777-7777-7777-777777777248',
  'Tax trace rows expose the source accounting-trace route'
);

SELECT * FROM finish();
ROLLBACK;
