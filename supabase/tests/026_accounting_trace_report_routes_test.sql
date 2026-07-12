-- ACCOUNTING-TRACE-REPORTS-001
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(29);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111126',
  'authenticated', 'authenticated', 'trace-reports@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111126","role":"authenticated"}',
  true
);

-- These are read-contract fixtures. Disable lifecycle/source triggers so the
-- test can deliberately create orphan and cross-company links that normal
-- writes reject, then prove the trace reader still fails closed.
SET LOCAL session_replication_role = replica;

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES
  (
    '22222222-2222-2222-2222-222222222126', 'corporation',
    'Trace Reports Test Corp', 'Software Services', '111-222-333-126',
    'vat', 'calendar', 'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
    'trace-reports@test.local', 'Juan Dela Cruz', 'President',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    '22222222-2222-2222-2222-222222222127', 'corporation',
    'Foreign Trace Test Corp', 'Trading', '111-222-333-127',
    'vat', 'calendar', 'Unit 2', 'Other Bldg', 'Taguig', 'Metro Manila', '1630',
    'foreign-trace@test.local', 'Maria Santos', 'President',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  );

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111126', '22222222-2222-2222-2222-222222222126', 'owner', '11111111-1111-1111-1111-111111111126'),
  ('11111111-1111-1111-1111-111111111126', '22222222-2222-2222-2222-222222222127', 'owner', '11111111-1111-1111-1111-111111111126');

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES
  (
    '33333333-3333-3333-3333-333333333126',
    '22222222-2222-2222-2222-222222222126', 'HO', 'Head Office',
    'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    '33333333-3333-3333-3333-333333333127',
    '22222222-2222-2222-2222-222222222127', 'HO', 'Foreign Head Office',
    'Unit 2', 'Other Bldg', 'Taguig', 'Metro Manila', '1630',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  );

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444126',
  '22222222-2222-2222-2222-222222222126',
  'FY2026', '2026-01-01', '2026-12-31', true
);
INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
) VALUES (
  '44444444-4444-4444-4444-444444444226',
  '22222222-2222-2222-2222-222222222126',
  '44444444-4444-4444-4444-444444444126',
  7, 'Jul 2026', '2026-07-01', '2026-07-31', false
);

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name, account_type,
  normal_balance, is_postable, is_active, created_by, updated_by
) VALUES
  (
    'aaaaaaaa-0000-0000-0000-000000000126',
    '22222222-2222-2222-2222-222222222126',
    '1010', 'Cash', 'asset', 'debit', true, true,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000226',
    '22222222-2222-2222-2222-222222222126',
    '4010', 'Revenue', 'revenue', 'credit', true, true,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  );

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
) VALUES
  (
    '55555555-5555-5555-5555-555555555126',
    '22222222-2222-2222-2222-222222222126', 'CUST-126',
    'Trace Customer Inc', '444-555-666-126',
    'Customer HQ', 'Customer HQ',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    '55555555-5555-5555-5555-555555555127',
    '22222222-2222-2222-2222-222222222127', 'CUST-127',
    'Foreign Customer Inc', '444-555-666-127',
    'Foreign HQ', 'Foreign HQ',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  );

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin,
  registered_address, created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666126',
  '22222222-2222-2222-2222-222222222126', 'SUP-126',
  'Trace Supplier Inc', '777-888-999-126', 'Supplier HQ',
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
);

INSERT INTO sales_invoices (
  id, company_id, branch_id, si_number, date, fiscal_period_id,
  customer_id, customer_name_snapshot, customer_tin_snapshot,
  customer_address_snapshot, total_taxable_amount, total_vat_amount,
  total_amount, status, created_by, updated_by
) VALUES
  (
    '77777777-7777-7777-7777-777777777126',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'SI-TRACE-126', '2026-07-10', '44444444-4444-4444-4444-444444444226',
    '55555555-5555-5555-5555-555555555126',
    'Trace Customer Inc', '444-555-666-126', 'Customer HQ',
    100, 12, 112, 'posted',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    '77777777-7777-7777-7777-777777777127',
    '22222222-2222-2222-2222-222222222127',
    '33333333-3333-3333-3333-333333333127',
    'SI-FOREIGN-127', '2026-07-10', NULL,
    '55555555-5555-5555-5555-555555555127',
    'Foreign Customer Inc', '444-555-666-127', 'Foreign HQ',
    50, 6, 56, 'posted',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    -- Unlinked same-company source for the normal-trigger positive control.
    '77777777-7777-7777-7777-777777777128',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'SI-TRACE-128', '2026-07-10', '44444444-4444-4444-4444-444444444226',
    '55555555-5555-5555-5555-555555555126',
    'Trace Customer Inc', '444-555-666-126', 'Customer HQ',
    100, 12, 112, 'posted',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    -- Unlinked foreign-company source for the normal-trigger cross-company negative.
    '77777777-7777-7777-7777-777777777129',
    '22222222-2222-2222-2222-222222222127',
    '33333333-3333-3333-3333-333333333127',
    'SI-FOREIGN-129', '2026-07-10', NULL,
    '55555555-5555-5555-5555-555555555127',
    'Foreign Customer Inc', '444-555-666-127', 'Foreign HQ',
    50, 6, 56, 'posted',
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  );

INSERT INTO payment_vouchers (
  id, company_id, branch_id, supplier_id,
  supplier_name_snapshot, supplier_tin_snapshot,
  voucher_number, voucher_date, total_amount, total_ewt,
  status, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777226',
  '22222222-2222-2222-2222-222222222126',
  '33333333-3333-3333-3333-333333333126',
  '66666666-6666-6666-6666-666666666126',
  'Trace Supplier Inc', '777-888-999-126',
  'PV-TRACE-126', '2026-07-15', 98, 2, 'posted',
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
);

INSERT INTO receipts (
  id, company_id, branch_id, customer_id,
  customer_name_snapshot, customer_tin_snapshot,
  receipt_number, receipt_date, payment_mode_id,
  total_amount, total_cwt, status, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777326',
  '22222222-2222-2222-2222-222222222126',
  '33333333-3333-3333-3333-333333333126',
  '55555555-5555-5555-5555-555555555126',
  'Trace Customer Inc', '444-555-666-126',
  'OR-TRACE-126', '2026-07-20',
  (SELECT id FROM ref_payment_modes WHERE code = 'CASH'),
  110, 2, 'posted',
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
);

INSERT INTO receipt_lines (
  id, receipt_id, company_id, invoice_id,
  payment_amount, cwt_amount, created_by, updated_by
) VALUES (
  '99999999-9999-9999-9999-999999999126',
  '77777777-7777-7777-7777-777777777326',
  '22222222-2222-2222-2222-222222222126',
  '77777777-7777-7777-7777-777777777126',
  110, 2,
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
);

INSERT INTO journal_entries (
  id, company_id, branch_id, je_number, je_date, fiscal_period_id,
  description, reference_doc_type, reference_doc_id, status,
  total_debit, total_credit, created_by, updated_by
) VALUES
  (
    '88888888-8888-8888-8888-888888888126',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-SI-TRACE-126', '2026-07-10', '44444444-4444-4444-4444-444444444226',
    'Sales trace fixture', 'SI', '77777777-7777-7777-7777-777777777126',
    'posted', 112, 112,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    '88888888-8888-8888-8888-888888888226',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-PV-TRACE-126', '2026-07-15', '44444444-4444-4444-4444-444444444226',
    'Payment trace fixture', 'PV', '77777777-7777-7777-7777-777777777226',
    'posted', 100, 100,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    '88888888-8888-8888-8888-888888888326',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-OR-TRACE-126', '2026-07-20', '44444444-4444-4444-4444-444444444226',
    'Receipt trace fixture', 'OR', '77777777-7777-7777-7777-777777777326',
    'posted', 112, 112,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    -- Deliberately forged: A-company JE points at a B-company source.
    '88888888-8888-8888-8888-888888888426',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-CROSS-TRACE-126', '2026-07-21', '44444444-4444-4444-4444-444444444226',
    'Cross-company trace fixture', 'SI', '77777777-7777-7777-7777-777777777127',
    'posted', 1, 1,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  ),
  (
    -- Deliberately forged: governed type with no physical source row.
    '88888888-8888-8888-8888-888888888526',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-ORPHAN-TRACE-126', '2026-07-22', '44444444-4444-4444-4444-444444444226',
    'Orphan trace fixture', 'SI', '77777777-7777-7777-7777-777777777999',
    'posted', 1, 1,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  );

INSERT INTO journal_entry_lines (
  je_id, company_id, line_number, account_id, description,
  debit_amount, credit_amount, created_by, updated_by
)
SELECT
  je.id, je.company_id, line_no,
  CASE WHEN line_no = 1 THEN 'aaaaaaaa-0000-0000-0000-000000000126'::UUID
       ELSE 'aaaaaaaa-0000-0000-0000-000000000226'::UUID END,
  'Trace line',
  CASE WHEN line_no = 1 THEN je.total_debit ELSE 0 END,
  CASE WHEN line_no = 2 THEN je.total_credit ELSE 0 END,
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
FROM journal_entries je
CROSS JOIN generate_series(1, 2) AS line_no
WHERE je.id IN (
  '88888888-8888-8888-8888-888888888126',
  '88888888-8888-8888-8888-888888888226',
  '88888888-8888-8888-8888-888888888326',
  '88888888-8888-8888-8888-888888888426',
  '88888888-8888-8888-8888-888888888526'
);

UPDATE sales_invoices
SET journal_entry_id = '88888888-8888-8888-8888-888888888126'
WHERE id = '77777777-7777-7777-7777-777777777126';
UPDATE payment_vouchers
SET journal_entry_id = '88888888-8888-8888-8888-888888888226'
WHERE id = '77777777-7777-7777-7777-777777777226';
UPDATE receipts
SET journal_entry_id = '88888888-8888-8888-8888-888888888326'
WHERE id = '77777777-7777-7777-7777-777777777326';

INSERT INTO tax_detail_entries (
  id, company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, tax_base, tax_rate, tax_amount,
  posting_date, document_date,
  counterparty_id, counterparty_tin, counterparty_name
) VALUES
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb126',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'SI', '77777777-7777-7777-7777-777777777126',
    'output_vat', 100, 12, 12, '2026-07-10', '2026-07-10',
    '55555555-5555-5555-5555-555555555126',
    '444-555-666-126', 'Trace Customer Inc'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb226',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'PV', '77777777-7777-7777-7777-777777777226',
    'ewt_payable', 100, 2, 2, '2026-07-15', '2026-07-15',
    '66666666-6666-6666-6666-666666666126',
    '777-888-999-126', 'Trace Supplier Inc'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb326',
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'OR', '77777777-7777-7777-7777-777777777326',
    'cwt_receivable', 100, 2, 2, '2026-07-20', '2026-07-20',
    '55555555-5555-5555-5555-555555555126',
    '444-555-666-126', 'Trace Customer Inc'
  );

INSERT INTO form_2307_issuances (
  id, company_id, supplier_id, tax_year, tax_quarter,
  total_tax_base, total_ewt, status, created_by, updated_by
) VALUES (
  '99999999-9999-9999-9999-999999999326',
  '22222222-2222-2222-2222-222222222126',
  '66666666-6666-6666-6666-666666666126',
  2026, 3, 100, 2, 'generated',
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
);

INSERT INTO form_2307_tracking (
  id, company_id, receipt_line_id, customer_id,
  cwt_amount_booked, status, date_received, period_covered,
  created_by, updated_by
) VALUES (
  '99999999-9999-9999-9999-999999999226',
  '22222222-2222-2222-2222-222222222126',
  '99999999-9999-9999-9999-999999999126',
  '55555555-5555-5555-5555-555555555126',
  2, 'received', '2026-07-25', 'Q3-2026',
  '11111111-1111-1111-1111-111111111126',
  '11111111-1111-1111-1111-111111111126'
);

INSERT INTO report_snapshots (
  id, company_id, report_type, source_table, source_id,
  snapshot_status, snapshot_version, period_start, period_end,
  report_payload, source_payload, source_hash, source_row_count,
  generated_by
) VALUES (
  'cccccccc-cccc-cccc-cccc-ccccccccc126',
  '22222222-2222-2222-2222-222222222126',
  'VAT_2550Q', 'legacy_trace_fixture',
  'cccccccc-cccc-cccc-cccc-ccccccccc226',
  'final', 1, '2026-07-01', '2026-09-30',
  '{"label":"legacy snapshot"}',
  jsonb_build_object(
    'output_vat', jsonb_build_array(jsonb_build_object(
      'transaction_id', '77777777-7777-7777-7777-777777777126',
      'source_module', 'sales_invoice',
      'taxable_base', 100,
      'output_vat', 12
    ))
  ),
  'legacy-hash-unchanged', 1,
  '11111111-1111-1111-1111-111111111126'
);

RESET session_replication_role;

-- Canonical keys exist without removing the legacy report columns.
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN (
        'vw_customer_ledger', 'vw_supplier_ledger',
        'vw_output_vat_review', 'vw_input_vat_review',
        'vw_ewt_summary_ap', 'vw_cwt_summary_ar'
      )
      AND column_name IN ('source_doc_type', 'source_doc_id')
  ),
  12,
  'all AR/AP and VAT/EWT/CWT views expose the canonical source key pair'
);

SELECT is(
  (SELECT source_doc_type || ':' || source_doc_id::TEXT
   FROM vw_customer_ledger
   WHERE source_doc_id = '77777777-7777-7777-7777-777777777126'),
  'SI:77777777-7777-7777-7777-777777777126',
  'AR ledger rows expose their sales-invoice source'
);
SELECT is(
  (SELECT source_doc_type || ':' || source_doc_id::TEXT
   FROM vw_supplier_ledger
   WHERE source_doc_id = '77777777-7777-7777-7777-777777777226'),
  'PV:77777777-7777-7777-7777-777777777226',
  'AP ledger rows map legacy document names to canonical source types'
);
SELECT is(
  (SELECT source_doc_type || ':' || source_doc_id::TEXT
   FROM vw_output_vat_review
   WHERE source_doc_id = '77777777-7777-7777-7777-777777777126'),
  'SI:77777777-7777-7777-7777-777777777126',
  'output VAT rows expose the underlying source rather than the display module'
);
SELECT is(
  (SELECT source_doc_type || ':' || source_doc_id::TEXT
   FROM vw_ewt_summary_ap
   WHERE source_doc_id = '77777777-7777-7777-7777-777777777226'),
  'PV:77777777-7777-7777-7777-777777777226',
  'EWT rows expose their PV/CV-capable canonical source type'
);
SELECT is(
  (SELECT source_doc_type || ':' || source_doc_id::TEXT
   FROM vw_cwt_summary_ar
   WHERE source_doc_id = '77777777-7777-7777-7777-777777777326'),
  'OR:77777777-7777-7777-7777-777777777326',
  'CWT rows preserve source type and add the canonical source id alias'
);

SELECT is(
  fn_get_accounting_trace(
    'SI', '77777777-7777-7777-7777-777777777126', NULL
  )->>'source_route',
  '/accounting-source?sourceType=SI&sourceId=77777777-7777-7777-7777-777777777126',
  'single-source trace returns the working generic accounting-source route'
);
SELECT is(
  fn_get_accounting_trace(
    'SI', '77777777-7777-7777-7777-777777777126', NULL
  )->>'module_route',
  '/sales-invoices?id=77777777-7777-7777-7777-777777777126',
  'single-source trace retains the registered module route as a separate hint'
);
SELECT is(
  fn_get_accounting_trace(
    'SI', '77777777-7777-7777-7777-777777777126', NULL
  )->'source_record'->>'id',
  '77777777-7777-7777-7777-777777777126',
  'single-source trace returns the checked source record'
);
SELECT is(
  fn_get_accounting_trace(
    'SI', '77777777-7777-7777-7777-777777777126', NULL
  )->'source_record'->>'company_id',
  '22222222-2222-2222-2222-222222222126',
  'returned source record belongs to the authorized trace company'
);

SELECT throws_like(
  $q$SELECT fn_get_accounting_trace(
    'SI',
    '77777777-7777-7777-7777-777777777999',
    '88888888-8888-8888-8888-888888888526'
  )$q$,
  '%Accounting source not found or access denied%',
  'trace rejects a JE whose polymorphic source row is orphaned'
);
SELECT throws_like(
  $q$SELECT fn_get_accounting_trace(
    'SI',
    '77777777-7777-7777-7777-777777777326',
    '88888888-8888-8888-8888-888888888126'
  )$q$,
  '%source id does not match%',
  'trace rejects a caller-supplied source id that does not match the JE link'
);
SELECT throws_like(
  $q$SELECT fn_get_accounting_trace(
    'SI',
    '77777777-7777-7777-7777-777777777127',
    '88888888-8888-8888-8888-888888888426'
  )$q$,
  '%company does not match%',
  'trace rejects a cross-company JE/source pair even when the caller belongs to both companies'
);

SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'financial',
     jsonb_build_object(
       'account_id', 'aaaaaaaa-0000-0000-0000-000000000126',
       'date_from', '2026-07-10', 'date_to', '2026-07-10'
     )
   ) LIMIT 1),
  'SI',
  'financial account/date trace set resolves the contributing source'
);
SELECT is(
  (SELECT accounting_trace_route
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'financial',
     jsonb_build_object(
       'account_id', 'aaaaaaaa-0000-0000-0000-000000000126',
       'date_from', '2026-07-10', 'date_to', '2026-07-10'
     )
   ) LIMIT 1),
  '/accounting-trace?jeId=88888888-8888-8888-8888-888888888126',
  'financial trace rows expose the exact contributing JE route'
);
SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'subledger',
     jsonb_build_object(
       'ledger', 'AR',
       'counterparty_id', '55555555-5555-5555-5555-555555555126',
       'date_from', '2026-07-10', 'date_to', '2026-07-10'
     )
   ) LIMIT 1),
  'SI',
  'AR subledger/counterparty trace set resolves the invoice source'
);
SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'subledger',
     jsonb_build_object(
       'ledger', 'AP',
       'counterparty_id', '66666666-6666-6666-6666-666666666126',
       'date_from', '2026-07-15', 'date_to', '2026-07-15'
     )
   ) LIMIT 1),
  'PV',
  'AP subledger/counterparty trace set resolves the payment source'
);
SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'tax',
     jsonb_build_object(
       'tax_kind', 'output_vat',
       'date_from', '2026-07-10', 'date_to', '2026-07-10'
     )
   ) LIMIT 1),
  'SI',
  'tax trace set resolves a VAT row to its source'
);
SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'form_2307_issued',
     jsonb_build_object('record_id', '99999999-9999-9999-9999-999999999326')
   ) LIMIT 1),
  'PV',
  'Form 2307 issued trace set resolves the certificate source payment'
);
SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'form_2307_received',
     jsonb_build_object('record_id', '99999999-9999-9999-9999-999999999226')
   ) LIMIT 1),
  'OR',
  'Form 2307 received trace set resolves the tracked receipt source'
);

SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_snapshot_trace_links('cccccccc-cccc-cccc-cccc-ccccccccc126')
   LIMIT 1),
  'SI',
  'legacy snapshot payload derives its canonical source type without rewriting JSON'
);
SELECT is(
  (SELECT source_route
   FROM fn_get_report_snapshot_trace_links('cccccccc-cccc-cccc-cccc-ccccccccc126')
   LIMIT 1),
  '/accounting-source?sourceType=SI&sourceId=77777777-7777-7777-7777-777777777126',
  'legacy snapshot link uses the generic source route'
);
SELECT is(
  (SELECT source_doc_type
   FROM fn_get_report_trace_set(
     '22222222-2222-2222-2222-222222222126',
     'report_snapshot',
     jsonb_build_object('record_id', 'cccccccc-cccc-cccc-cccc-ccccccccc126')
   ) LIMIT 1),
  'SI',
  'report snapshot family delegates to the non-mutating link derivation contract'
);
SELECT is(
  (SELECT source_hash FROM report_snapshots
   WHERE id = 'cccccccc-cccc-cccc-cccc-ccccccccc126'),
  'legacy-hash-unchanged',
  'deriving legacy/new snapshot links preserves the immutable source hash'
);

-- ---------------------------------------------------------------------------
-- PXL-DA-005 closure evidence: writer-boundary negatives under NORMAL trigger
-- execution. The replica-mode fixtures above queued no constraint events, so
-- making the deferred source-integrity constraint immediate fires
-- fn_enforce_journal_entry_source for each statement below exactly as it does
-- at commit time in production.
-- ---------------------------------------------------------------------------
SET CONSTRAINTS trg_journal_entry_source_integrity IMMEDIATE;

SELECT lives_ok(
  $q$INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-LIVE-SOURCE-126', '2026-07-23', '44444444-4444-4444-4444-444444444226',
    'Live-source normal-trigger control', 'SI', '77777777-7777-7777-7777-777777777128',
    'posted', 1, 1,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  )$q$,
  'normal-trigger control: a posted JE with an existing same-company source is accepted'
);

SELECT throws_like(
  $q$INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-ORPHAN-LIVE-126', '2026-07-23', '44444444-4444-4444-4444-444444444226',
    'Orphan-source normal-trigger negative', 'SI', '77777777-7777-7777-7777-777777777998',
    'posted', 1, 1,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  )$q$,
  '%Posting source SI.% does not exist%',
  'normal trigger immediately rejects a posted JE whose governed source row does not exist'
);

SELECT throws_like(
  $q$INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222126',
    '33333333-3333-3333-3333-333333333126',
    'JE-CROSS-LIVE-126', '2026-07-23', '44444444-4444-4444-4444-444444444226',
    'Cross-company normal-trigger negative', 'SI', '77777777-7777-7777-7777-777777777129',
    'posted', 1, 1,
    '11111111-1111-1111-1111-111111111126',
    '11111111-1111-1111-1111-111111111126'
  )$q$,
  '%Posting source company % does not match journal company %',
  'normal trigger immediately rejects a posted JE linked to another company''s source'
);

-- Remove foreign-company membership and verify both aggregate and direct
-- source readers fail closed before returning any cross-tenant record.
DELETE FROM user_company_memberships
WHERE user_id = '11111111-1111-1111-1111-111111111126'
  AND company_id = '22222222-2222-2222-2222-222222222127';

SELECT throws_like(
  $q$SELECT * FROM fn_get_report_trace_set(
    '22222222-2222-2222-2222-222222222127',
    'subledger',
    jsonb_build_object(
      'ledger', 'AR',
      'counterparty_id', '55555555-5555-5555-5555-555555555127'
    )
  )$q$,
  '%Access denied: not a member of company%',
  'report trace set rejects a company outside the caller membership scope'
);
SELECT throws_like(
  $q$SELECT fn_get_accounting_trace(
    'SI', '77777777-7777-7777-7777-777777777127', NULL
  )$q$,
  '%not found or access denied%',
  'single-source trace does not return a foreign source record'
);

SELECT * FROM finish();
ROLLBACK;
