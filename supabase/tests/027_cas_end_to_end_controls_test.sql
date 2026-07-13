-- CAS-NUMBERING-001 / CAS-DAT-GOLDEN-001 / CAS-E2E-001
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(30);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111127',
  'authenticated', 'authenticated', 'cas-e2e@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111127","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, cas_permit_no, cas_date_issued,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222227', 'corporation',
  'CAS E2E Test Corp', 'Software Services', '111-222-333-027',
  'vat', 'calendar', 'CAS-TEST-027', '2026-01-01',
  'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
  'cas-e2e@test.local', 'Juan Dela Cruz', 'President', auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name, cas_permit_no, cas_date_issued,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333327',
  '22222222-2222-2222-2222-222222222227', 'HO', 'Head Office',
  'CAS-TEST-027-HO', '2026-01-01',
  'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444427',
  '22222222-2222-2222-2222-222222222227',
  'FY2026', '2026-01-01', '2026-12-31', true
);
INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222227',
  '44444444-4444-4444-4444-444444444427',
  m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
  make_date(2026, m, 1),
  (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
  false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active,
  created_by, updated_by
) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000127', '22222222-2222-2222-2222-222222222227',
   '1010', 'Cash', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000227', '22222222-2222-2222-2222-222222222227',
   '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000327', '22222222-2222-2222-2222-222222222227',
   '2100', 'Output VAT', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000427', '22222222-2222-2222-2222-222222222227',
   '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, vat_payable_account_id, default_cash_account_id,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222227',
  'aaaaaaaa-0000-0000-0000-000000000227',
  'aaaaaaaa-0000-0000-0000-000000000327',
  'aaaaaaaa-0000-0000-0000-000000000127',
  auth.uid(), auth.uid()
);

INSERT INTO number_series (
  company_id, branch_id, document_type_id, prefix,
  number_length, starting_number, next_number,
  atp_series_start, atp_series_end,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222227',
  '33333333-3333-3333-3333-333333333327',
  id,
  CASE document_code WHEN 'SI' THEN 'SI-' ELSE 'FT-' END,
  6, 1, 1,
  CASE document_code WHEN 'SI' THEN 1 ELSE 10 END,
  CASE document_code WHEN 'SI' THEN 2 ELSE 11 END,
  true, auth.uid(), auth.uid()
FROM ref_document_types
WHERE document_code IN ('SI', 'FT');

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555527',
  '22222222-2222-2222-2222-222222222227', 'CUST-001',
  'CAS Customer Inc', '444-555-666-027',
  'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid()
);

CREATE TEMP TABLE t_ctx (key TEXT PRIMARY KEY, id UUID);
CREATE TEMP TABLE t_res (key TEXT PRIMARY KEY, value JSONB);
GRANT SELECT ON t_ctx, t_res TO authenticated;

INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222227',
    'branch_id', '33333333-3333-3333-3333-333333333327',
    'date', '2026-07-10',
    'customer_id', '55555555-5555-5555-5555-555555555527',
    'customer_name_snapshot', 'CAS Customer Inc',
    'customer_tin_snapshot', '444-555-666-027',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'CAS services 1', 'quantity', 1, 'unit_price', 10000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000427'
  ))
);

SELECT is(
  (SELECT si_number FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si1')),
  'SI-000001',
  'first ATP-controlled invoice receives sequence 1'
);
SELECT results_eq(
  $q$SELECT sequence_number, status, source_table, source_id
     FROM cas_document_number_issuances
     WHERE document_code = 'SI' AND document_number = 'SI-000001'$q$,
  $q$VALUES (1::bigint, 'issued'::text, 'sales_invoices'::text,
     (SELECT id FROM t_ctx WHERE key = 'si1'))$q$,
  'the number is atomically linked to its source document'
);

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si1'));
SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si1')),
  'posted',
  'first invoice posts before the void scenario'
);

SELECT throws_like(
  format($q$SELECT fn_void_sales_invoice(%L, NULL, NULL)$q$,
    (SELECT id FROM t_ctx WHERE key = 'si1')),
  '%void reason code or new void memo is required%',
  'a CAS document cannot be voided without a reason'
);
SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si1')),
  'posted',
  'failed reason validation rolls the reversal and status change back'
);

SELECT lives_ok(
  format($q$SELECT fn_void_sales_invoice(%L, NULL, 'Customer billing correction')$q$,
    (SELECT id FROM t_ctx WHERE key = 'si1')),
  'invoice void with a reason succeeds'
);
SELECT results_eq(
  $q$SELECT terminal_status, reason_text, document_date, (voided_by = auth.uid())
     FROM cas_document_void_events
     WHERE source_table = 'sales_invoices' AND source_id = (SELECT id FROM t_ctx WHERE key = 'si1')$q$,
  $$VALUES ('cancelled'::text, 'Customer billing correction'::text, '2026-07-10'::date, true)$$,
  'void event preserves terminal status, reason, original date, and actor'
);
SELECT ok(
  (SELECT reversal_journal_entry_id IS NOT NULL
   FROM cas_document_void_events
   WHERE source_table = 'sales_invoices' AND source_id = (SELECT id FROM t_ctx WHERE key = 'si1')),
  'void event links the reversing journal entry'
);
SELECT is(
  (SELECT status FROM cas_document_number_issuances
   WHERE source_table = 'sales_invoices' AND source_id = (SELECT id FROM t_ctx WHERE key = 'si1')),
  'voided',
  'the immutable number history records the voided state'
);

INSERT INTO t_ctx
SELECT 'si2', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222227',
    'branch_id', '33333333-3333-3333-3333-333333333327',
    'date', '2026-07-10',
    'customer_id', '55555555-5555-5555-5555-555555555527',
    'customer_name_snapshot', 'CAS Customer Inc',
    'customer_tin_snapshot', '444-555-666-027',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'CAS services 2', 'quantity', 1, 'unit_price', 5000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000427'
  ))
);
SELECT is(
  (SELECT si_number FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si2')),
  'SI-000002',
  'the next invoice advances to sequence 2 and never reuses the voided number'
);
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si2'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si2'));
SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si2')),
  'posted',
  'the second controlled invoice posts'
);

SELECT throws_like(
  $q$SELECT fn_save_sales_invoice(
    NULL,
    jsonb_build_object(
      'company_id', '22222222-2222-2222-2222-222222222227',
      'branch_id', '33333333-3333-3333-3333-333333333327',
      'date', '2026-07-10',
      'customer_id', '55555555-5555-5555-5555-555555555527',
      'customer_name_snapshot', 'CAS Customer Inc'
    ),
    jsonb_build_array(jsonb_build_object(
      'description', 'Over ATP', 'quantity', 1, 'unit_price', 1,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000427'
    )
  )$q$,
  '%ATP range exhausted%',
  'ATP exhaustion blocks further issuance'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $q$SELECT fn_next_document_number(
    '22222222-2222-2222-2222-222222222227',
    '33333333-3333-3333-3333-333333333327', 'FT')$q$,
  '42501', NULL,
  'authenticated callers cannot invoke the internal allocator directly'
);

SELECT is(
  fn_reserve_document_number(
    '22222222-2222-2222-2222-222222222227',
    '33333333-3333-3333-3333-333333333327', 'FT'),
  'FT-000010',
  'legacy create pages use the audited reservation endpoint'
);
SELECT throws_like(
  $q$SELECT fn_reserve_document_number(
    '22222222-2222-2222-2222-222222222227',
    '33333333-3333-3333-3333-333333333327', 'FT')$q$,
  '%unresolved document-number reservation%',
  'a second reservation is blocked until the first is resolved'
);
SELECT fn_abandon_document_number(
  '22222222-2222-2222-2222-222222222227',
  '33333333-3333-3333-3333-333333333327', 'FT',
  'User cancelled before save'
);
SELECT is(
  (SELECT status FROM cas_document_number_issuances
   WHERE document_code = 'FT' AND document_number = 'FT-000010'),
  'abandoned',
  'abandoned reservations retain their number and reason evidence'
);
SELECT is(
  fn_reserve_document_number(
    '22222222-2222-2222-2222-222222222227',
    '33333333-3333-3333-3333-333333333327', 'FT'),
  'FT-000011',
  'the next reservation advances after an explained abandonment'
);
RESET ROLE;

INSERT INTO t_res
SELECT 'cas_snapshot', fn_snapshot_cas_export(
  '22222222-2222-2222-2222-222222222227',
  'slsp', 2026, 7, 'slsp-July-2026.dat'
);
INSERT INTO t_res
SELECT 'dat_artifact', fn_render_cas_dat(
  ((SELECT value FROM t_res WHERE key = 'cas_snapshot')->>'snapshot_id')::uuid
);

SELECT is(
  (SELECT value->>'file_name' FROM t_res WHERE key = 'dat_artifact'),
  'slsp-July-2026.dat',
  'server renderer emits a DAT filename'
);
SELECT like(
  (SELECT value->>'content' FROM t_res WHERE key = 'dat_artifact'),
  'H|PXL-CAS-DAT-1.0|CAS_SLSP|%',
  'DAT bytes start with the versioned header record'
);
SELECT ok(
  position(E'\r\n' in (SELECT value->>'content' FROM t_res WHERE key = 'dat_artifact')) > 0,
  'DAT artifact records use the declared CRLF newline convention'
);
SELECT like(
  (SELECT value->>'content' FROM t_res WHERE key = 'dat_artifact'),
  '%D|S|2026-07-10|SI-000002|444555666027|CAS Customer Inc|5000.00|600.00%',
  'DAT bytes contain the deterministic statutory sales detail record'
);
SELECT is(
  (SELECT value->>'file_hash' FROM t_res WHERE key = 'dat_artifact'),
  (SELECT encode(extensions.digest(
    convert_to(value->>'content', 'UTF8'), 'sha256'), 'hex')
   FROM t_res WHERE key = 'dat_artifact'),
  'logged SHA-256 is computed over the exact downloaded bytes'
);
SELECT is(
  (SELECT file_hash FROM cas_export_log
   WHERE snapshot_id = ((SELECT value FROM t_res WHERE key = 'cas_snapshot')->>'snapshot_id')::uuid),
  (SELECT value->>'file_hash' FROM t_res WHERE key = 'dat_artifact'),
  'CAS export history stores the exact artifact hash'
);
SELECT is(
  (fn_render_cas_dat(
    ((SELECT value FROM t_res WHERE key = 'cas_snapshot')->>'snapshot_id')::uuid
  )->>'artifact_id')::uuid,
  ((SELECT value FROM t_res WHERE key = 'dat_artifact')->>'artifact_id')::uuid,
  're-rendering returns the same immutable artifact'
);

SET LOCAL ROLE authenticated;
UPDATE cas_export_artifacts
SET file_hash = repeat('0', 64)
WHERE id = ((SELECT value FROM t_res WHERE key = 'dat_artifact')->>'artifact_id')::uuid;
RESET ROLE;
SELECT isnt(
  (SELECT file_hash FROM cas_export_artifacts
   WHERE id = ((SELECT value FROM t_res WHERE key = 'dat_artifact')->>'artifact_id')::uuid),
  repeat('0', 64),
  'authenticated callers cannot alter frozen DAT bytes or hash'
);

INSERT INTO t_res
SELECT 'books', fn_snapshot_books_export(
  '22222222-2222-2222-2222-222222222227',
  'general_journal', '2026-07-10', '2026-07-10', 'general-journal.csv'
);
SELECT cmp_ok(
  ((SELECT value FROM t_res WHERE key = 'books')->>'row_count')::int,
  '>=', 9,
  'general journal book preserves original, reversal, and replacement JE lines'
);

INSERT INTO t_res
SELECT 'audit_package', fn_snapshot_cas_audit_package(
  '22222222-2222-2222-2222-222222222227',
  '2026-07-10', '2026-07-10', 'cas-audit-package.json'
);
SELECT is(
  length((SELECT value->>'source_hash' FROM t_res WHERE key = 'audit_package')),
  64,
  'CAS audit package has a SHA-256 evidence hash'
);
SELECT is(
  (SELECT jsonb_array_length(source_payload->'void_events')
   FROM report_snapshots
   WHERE id = ((SELECT value FROM t_res WHERE key = 'audit_package')->>'snapshot_id')::uuid),
  1,
  'audit package contains the void event'
);
SELECT cmp_ok(
  (SELECT jsonb_array_length(source_payload->'number_issuances')
   FROM report_snapshots
   WHERE id = ((SELECT value FROM t_res WHERE key = 'audit_package')->>'snapshot_id')::uuid),
  '>=', 4,
  'audit package contains issued, voided, and abandoned number evidence'
);
SELECT cmp_ok(
  (SELECT jsonb_array_length(source_payload->'exports')
   FROM report_snapshots
   WHERE id = ((SELECT value FROM t_res WHERE key = 'audit_package')->>'snapshot_id')::uuid),
  '>=', 2,
  'audit package links DAT and books export history'
);

SELECT * FROM finish();
ROLLBACK;
