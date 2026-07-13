-- ══════════════════════════════════════════════════════════════════════════════
-- BOOKS-EXPORT-SNAP-001 - BIR Books of Accounts Export Snapshots (PXL-DA-015)
--
-- The seven books exports (sales/purchase journals, cash receipts book, cash
-- disbursements book, general journal, cash sales/purchases journals) must
-- build their payloads server-side, freeze them in versioned exported report
-- snapshots with SHA-256 hashes, write server-attested cas_export_log rows,
-- reconcile source rows through linked balanced journal entries, feed the CAS
-- audit support package, and return exactly the frozen rows to the caller.
-- Exercises 20260703000009_report_snapshots_books_exports.sql.
-- Follows the suite convention: FY2026 periods with CURRENT_DATE inside them.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111181',
        'authenticated', 'authenticated', 'harness-bookssnap@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111181","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222280', 'corporation',
        'Books Snapshot Test Corp', 'Software Services', '111-222-333-018',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-bookssnap@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333380',
        '22222222-2222-2222-2222-222222222280', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444480',
        '22222222-2222-2222-2222-222222222280',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222280',
       '44444444-4444-4444-4444-444444444480',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-0000000000d1', '22222222-2222-2222-2222-222222222280',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d2', '22222222-2222-2222-2222-222222222280',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d3', '22222222-2222-2222-2222-222222222280',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d4', '22222222-2222-2222-2222-222222222280',
   '1400', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d5', '22222222-2222-2222-2222-222222222280',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d6', '22222222-2222-2222-2222-222222222280',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d7', '22222222-2222-2222-2222-222222222280',
   '2200', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d8', '22222222-2222-2222-2222-222222222280',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000d9', '22222222-2222-2222-2222-222222222280',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, ap_account_id, input_vat_account_id,
        ewt_withheld_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222280',
        'aaaaaaaa-0000-0000-0000-0000000000d2',
        'aaaaaaaa-0000-0000-0000-0000000000d6',
        'aaaaaaaa-0000-0000-0000-0000000000d1',
        'aaaaaaaa-0000-0000-0000-0000000000d5',
        'aaaaaaaa-0000-0000-0000-0000000000d3',
        'aaaaaaaa-0000-0000-0000-0000000000d4',
        'aaaaaaaa-0000-0000-0000-0000000000d7',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222280',
       '33333333-3333-3333-3333-333333333380',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'OR', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555581',
        '22222222-2222-2222-2222-222222222280', 'CUST-001',
        'Books Snap Customer Inc', '444-555-666-018',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666681',
        '22222222-2222-2222-2222-222222222280', 'SUPP-001',
        'Books Snap Supplier Corp', '777-888-999-018',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
CREATE TEMP TABLE t_res (key text PRIMARY KEY, val jsonb);

-- ── February books: SI, OR with CWT, VB, PV with EWT ──────────────────────────
INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222280',
    'branch_id',                 '33333333-3333-3333-3333-333333333380',
    'date',                      '2026-02-10',
    'customer_id',               '55555555-5555-5555-5555-555555555581',
    'customer_name_snapshot',    'Books Snap Customer Inc',
    'customer_tin_snapshot',     '444-555-666-018',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000d8'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));

INSERT INTO t_ctx
SELECT 'or1', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222280',
    'branch_id',              '33333333-3333-3333-3333-333333333380',
    'customer_id',            '55555555-5555-5555-5555-555555555581',
    'customer_name_snapshot', 'Books Snap Customer Inc',
    'customer_tin_snapshot',  '444-555-666-018',
    'receipt_date',           '2026-02-20',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           10976,
    'total_cwt',              224
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key='si1'),
    'payment_amount', 10976,
    'cwt_amount',     224,
    'atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140')
  )));
SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key='or1'));

INSERT INTO t_ctx
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222280',
    'branch_id',               '33333333-3333-3333-3333-333333333380',
    'supplier_id',             '66666666-6666-6666-6666-666666666681',
    'supplier_name_snapshot',  'Books Snap Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-018',
    'supplier_invoice_number', 'SUP-INV-0181',
    'bill_date',               '2026-02-12'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000d9'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));

INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222280',
    'branch_id',              '33333333-3333-3333-3333-333333333380',
    'supplier_id',            '66666666-6666-6666-6666-666666666681',
    'supplier_name_snapshot', 'Books Snap Supplier Corp',
    'voucher_date',           '2026-02-25',
    'total_amount',           5500,
    'total_ewt',              100
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb1'),
    'payment_amount',    5500,
    'ewt_amount',        100,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',      5000,
    'ewt_income_nature', 'Contractor services'
  )));
SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key='pv1'));

-- ── 1-3. Sales journal export: snapshot + server-attested log ──────────────────
INSERT INTO t_res
SELECT 'sj1', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'sales_journal', '2026-02-01', '2026-02-28', 'sales-journal-2026-02-01-to-2026-02-28.csv');

SELECT results_eq(
  $q$SELECT snapshot_status, report_type, snapshot_version, period_start, period_end,
            source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('exported'::text, 'BOOKS_SALES_JOURNAL'::text, 1, '2026-02-01'::date, '2026-02-28'::date, 1, 64)$$,
  'sales journal export creates an exported v1 snapshot with a SHA-256 hash');

SELECT is(
  (SELECT val -> 'rows' FROM t_res WHERE key='sj1'),
  (SELECT source_payload -> 'export_rows' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid),
  'the rows returned to the caller are exactly the frozen snapshot rows');

SELECT results_eq(
  $q$SELECT export_type, report_name, row_count, remarks,
            (snapshot_id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid)
     FROM cas_export_log
     WHERE company_id = '22222222-2222-2222-2222-222222222280'
       AND file_name = 'sales-journal-2026-02-01-to-2026-02-28.csv'$q$,
  $$VALUES ('csv_export'::text, 'Sales Journal'::text, 1, '2026-02-01..2026-02-28'::text, true)$$,
  'the RPC writes the cas_export_log evidence row with the exported range');

SELECT is(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='sj1'),
  (SELECT source_payload ->> 'export_file_text' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid),
  'the export text returned to the caller is exactly the frozen snapshot file text');

SELECT is(
  (SELECT source_payload ->> 'export_file_sha256' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid),
  (SELECT encode(extensions.digest(convert_to(source_payload ->> 'export_file_text', 'UTF8'), 'sha256'), 'hex')
   FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid),
  'the snapshot stores the SHA-256 of the exact exported file text');

SELECT results_eq(
  $q$SELECT
        cel.file_sha256 = rs.source_payload ->> 'export_file_sha256',
        cel.file_size_bytes = octet_length(convert_to(rs.source_payload ->> 'export_file_text', 'UTF8'))
      FROM cas_export_log cel
      JOIN report_snapshots rs ON rs.id = cel.snapshot_id
      WHERE cel.company_id = '22222222-2222-2222-2222-222222222280'
        AND cel.file_name = 'sales-journal-2026-02-01-to-2026-02-28.csv'$q$,
  $$VALUES (true, true)$$,
  'cas_export_log mirrors the frozen book file hash and byte size');

SELECT results_eq(
  $q$SELECT
        source_payload -> 'reconciliation' @> '[{"check":"books_source_to_export","book_type":"sales_journal","export_row_count":1,"source_row_count":1,"export_total":11200,"source_total":11200,"linked_journal_entries":1,"missing_journal_entries":0,"is_reconciled":true}]'::jsonb,
        source_payload -> 'reconciliation' @> '[{"check":"books_linked_gl_balance","book_type":"sales_journal","is_reconciled":true}]'::jsonb
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (true, true)$$,
  'sales journal stores source-to-export and linked-GL reconciliation evidence');

-- ── 4-6. Purchase journal, cash receipts, cash disbursements ───────────────────
INSERT INTO t_res
SELECT 'pj1', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'purchase_journal', '2026-02-01', '2026-02-28', 'purchase-journal.csv');

SELECT results_eq(
  $q$SELECT report_type, source_row_count,
            (source_payload -> 'integrity' ->> 'total')::numeric
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='pj1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('BOOKS_PURCHASE_JOURNAL'::text, 1, 5600.00::numeric)$$,
  'purchase journal freezes the vendor bill with its gross total');

INSERT INTO t_res
SELECT 'crb1', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'cash_receipts', '2026-02-01', '2026-02-28', 'cash-receipts-book.csv');

SELECT results_eq(
  $q$SELECT source_row_count,
            source_payload -> 'export_rows' -> 0 ->> 'doc_type',
            (source_payload -> 'export_rows' -> 0 ->> 'amount')::numeric
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='crb1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (1, 'OR'::text, 11200.00::numeric)$$,
  'cash receipts book freezes the OR collection gross of CWT');

INSERT INTO t_res
SELECT 'cdb1', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'cash_disbursements', '2026-02-01', '2026-02-28', 'cash-disbursements-book.csv');

SELECT results_eq(
  $q$SELECT source_row_count,
            source_payload -> 'export_rows' -> 0 ->> 'doc_type',
            (source_payload -> 'export_rows' -> 0 ->> 'amount')::numeric
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='cdb1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (1, 'PV'::text, 5400.00::numeric)$$,
  'cash disbursements book freezes the PV payment net of EWT');

SELECT results_eq(
  $q$WITH snapshots AS (
        SELECT rs.report_type, rs.source_payload
        FROM report_snapshots rs
        WHERE rs.id IN (
          ((SELECT val FROM t_res WHERE key='pj1') ->> 'snapshot_id')::uuid,
          ((SELECT val FROM t_res WHERE key='crb1') ->> 'snapshot_id')::uuid,
          ((SELECT val FROM t_res WHERE key='cdb1') ->> 'snapshot_id')::uuid
        )
      )
      SELECT report_type,
             EXISTS (
               SELECT 1
               FROM jsonb_array_elements(source_payload -> 'reconciliation') AS r(value)
               WHERE r.value ->> 'check' = 'books_source_to_export'
                 AND (r.value ->> 'is_reconciled')::boolean
                 AND (r.value ->> 'source_row_count')::integer = 1
                 AND (r.value ->> 'missing_journal_entries')::integer = 0
             ) AS source_reconciled,
             EXISTS (
               SELECT 1
               FROM jsonb_array_elements(source_payload -> 'reconciliation') AS r(value)
               WHERE r.value ->> 'check' = 'books_linked_gl_balance'
                 AND (r.value ->> 'is_reconciled')::boolean
             ) AS linked_gl_reconciled
      FROM snapshots
      ORDER BY report_type$q$,
  $$VALUES
    ('BOOKS_CASH_DISBURSEMENTS'::text, true, true),
    ('BOOKS_CASH_RECEIPTS'::text, true, true),
    ('BOOKS_PURCHASE_JOURNAL'::text, true, true)$$,
  'source books store reconciled source rows and linked balanced GL evidence');

-- ── 7-8. General journal: complete and balance-stamped ─────────────────────────
INSERT INTO t_res
SELECT 'gj1', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'general_journal', '2026-02-01', '2026-02-28', 'general-journal.csv');

SELECT is(
  (SELECT source_row_count FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='gj1') ->> 'snapshot_id')::uuid),
  (SELECT count(*)::int FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222280'
     AND je_date BETWEEN '2026-02-01' AND '2026-02-28'),
  'general journal export freezes every GL line of the range');

SELECT is(
  (SELECT source_payload -> 'reconciliation' -> 0 ->> 'is_reconciled' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='gj1') ->> 'snapshot_id')::uuid),
  'true',
  'general journal export records the debit=credit balance check');

-- ── 9. An empty book still snapshots as evidence ───────────────────────────────
INSERT INTO t_res
SELECT 'csj1', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'cash_sales_journal', '2026-02-01', '2026-02-28', 'cash-sales-journal.csv');

SELECT results_eq(
  $q$SELECT source_row_count, jsonb_array_length(source_payload -> 'export_rows'),
            length(source_hash)
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='csj1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (0, 0, 64)$$,
  'an empty cash sales journal still produces hashed snapshot evidence');

SELECT results_eq(
  $q$SELECT
        source_payload -> 'reconciliation' @> '[{"check":"books_source_to_export","export_row_count":0,"source_row_count":0,"linked_journal_entries":0,"missing_journal_entries":0,"is_reconciled":true}]'::jsonb,
        source_payload -> 'reconciliation' @> '[{"check":"books_linked_gl_balance","linked_gl_line_count":0,"is_reconciled":true}]'::jsonb
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='csj1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (true, true)$$,
  'an empty book still stores passing reconciliation evidence');

-- ── 10. Re-export versions the same logical source ─────────────────────────────
INSERT INTO t_res
SELECT 'sj2', fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
  'sales_journal', '2026-02-01', '2026-02-28', 'sales-journal-2026-02-01-to-2026-02-28.csv');

SELECT results_eq(
  $q$SELECT s2.snapshot_version, (s2.source_id = s1.source_id)
     FROM report_snapshots s1, report_snapshots s2
     WHERE s1.id = ((SELECT val FROM t_res WHERE key='sj1') ->> 'snapshot_id')::uuid
       AND s2.id = ((SELECT val FROM t_res WHERE key='sj2') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (2, true)$$,
  're-exporting the same book and range creates v2 on the same logical source');

-- ── 11-13. CAS audit support package ──────────────────────────────────────────
INSERT INTO t_res
SELECT 'audit_package1', fn_snapshot_cas_audit_package(
  '22222222-2222-2222-2222-222222222280',
  '2026-02-01', '2026-02-28', 'cas-audit-package-2026-02.json');

SELECT results_eq(
  $q$SELECT report_type, source_row_count > 0, length(source_hash),
            source_payload -> 'checks' @> '[{"check":"gl_balance","is_reconciled":true},{"check":"books_reconciliation","snapshot_count":7,"is_reconciled":true},{"check":"export_hash_evidence","export_count":7,"missing_hashes":0,"missing_dat_artifacts":0,"is_reconciled":true}]'::jsonb,
            jsonb_array_length(source_payload -> 'books_reconciliation'),
            jsonb_array_length(source_payload -> 'exports')
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='audit_package1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('CAS_AUDIT_PACKAGE'::text, true, 64, true, 7, 7)$$,
  'CAS audit package snapshots reconciled books and export hash evidence for the range');

SELECT results_eq(
  $q$SELECT cel.export_type, cel.report_name,
            cel.file_sha256 = rs.source_hash,
            cel.file_size_bytes = octet_length(convert_to(rs.source_payload::text, 'UTF8')),
            cel.row_count = rs.source_row_count
      FROM cas_export_log cel
      JOIN report_snapshots rs ON rs.id = cel.snapshot_id
      WHERE rs.id = ((SELECT val FROM t_res WHERE key='audit_package1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('audit_package'::text, 'CAS Audit Support Package'::text, true, true, true)$$,
  'CAS audit package writes a server-attested export log with the snapshot hash and byte size');

SELECT throws_like(
  $q$SELECT fn_snapshot_cas_audit_package('22222222-2222-2222-2222-222222222280',
       '2026-01-01', '2026-01-31', 'jan-audit-package.json')$q$,
  '%books_reconciliation%',
  'CAS audit package blocks periods without reconciled books snapshots');

-- ── 14-16. Input validation ───────────────────────────────────────────────────
SELECT throws_like(
  $q$SELECT fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
       'ledger_of_secrets', '2026-02-01', '2026-02-28', 'x.csv')$q$,
  '%Unsupported books export type%',
  'unknown book types are rejected');

SELECT throws_like(
  $q$SELECT fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
       'sales_journal', '2026-02-28', '2026-02-01', 'x.csv')$q$,
  '%Invalid books export date range%',
  'an inverted date range is rejected');

SELECT throws_like(
  $q$SELECT fn_snapshot_books_export('22222222-2222-2222-2222-222222222280',
       'sales_journal', '2026-02-01', '2026-02-28', '  ')$q$,
  '%file name is required%',
  'a blank file name is rejected');

SELECT * FROM finish();
ROLLBACK;
