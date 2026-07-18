-- ══════════════════════════════════════════════════════════════════════════════
-- CAS-EXPORT-SNAP-001 - CAS DAT Export Snapshots (PXL-DA-015)
--
-- CAS DAT file generation must build its DAT payload server-side, gate on the
-- relevant reconciliation (VAT for SLSP/RELIEF, EWT payable for the alphalist,
-- debit=credit for the GL extract), create a versioned exported report
-- snapshot with a SHA-256 hash, and write the cas_export_log/artifact evidence
-- itself — direct client inserts into the log are blocked, and the rows/file
-- text the caller receives are exactly the frozen snapshot payload.
-- Exercises 20260703000008_report_snapshots_cas_exports.sql.
-- Follows the suite convention: FY2026 periods with CURRENT_DATE inside them.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(29);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111171',
        'authenticated', 'authenticated', 'harness-cassnap@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111171","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222270', 'corporation',
        'CAS Snapshot Test Corp', 'Software Services', '111-222-333-00017',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-cassnap@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333370',
        '22222222-2222-2222-2222-222222222270', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444470',
        '22222222-2222-2222-2222-222222222270',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222270',
       '44444444-4444-4444-4444-444444444470',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-0000000000c1', '22222222-2222-2222-2222-222222222270',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c2', '22222222-2222-2222-2222-222222222270',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c3', '22222222-2222-2222-2222-222222222270',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c4', '22222222-2222-2222-2222-222222222270',
   '1400', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c5', '22222222-2222-2222-2222-222222222270',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c6', '22222222-2222-2222-2222-222222222270',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c7', '22222222-2222-2222-2222-222222222270',
   '2200', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c8', '22222222-2222-2222-2222-222222222270',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c9', '22222222-2222-2222-2222-222222222270',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, ap_account_id, input_vat_account_id,
        ewt_withheld_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222270',
        'aaaaaaaa-0000-0000-0000-0000000000c2',
        'aaaaaaaa-0000-0000-0000-0000000000c6',
        'aaaaaaaa-0000-0000-0000-0000000000c1',
        'aaaaaaaa-0000-0000-0000-0000000000c5',
        'aaaaaaaa-0000-0000-0000-0000000000c3',
        'aaaaaaaa-0000-0000-0000-0000000000c4',
        'aaaaaaaa-0000-0000-0000-0000000000c7',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222270',
       '33333333-3333-3333-3333-333333333370',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'OR', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555571',
        '22222222-2222-2222-2222-222222222270', 'CUST-001',
        'CAS Snap Customer Inc', '444-555-666-00017',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666671',
        '22222222-2222-2222-2222-222222222270', 'SUPP-001',
        'CAS Snap Supplier Corp', '777-888-999-00017',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
CREATE TEMP TABLE t_res (key text PRIMARY KEY, val jsonb);
-- The denial test below runs under SET LOCAL ROLE authenticated.
GRANT SELECT ON t_ctx TO authenticated;
GRANT SELECT ON t_res TO authenticated;

-- ── February books: SI, OR with CWT, VB, PV with EWT ──────────────────────────
INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222270',
    'branch_id',                 '33333333-3333-3333-3333-333333333370',
    'date',                      '2026-02-10',
    'customer_id',               '55555555-5555-5555-5555-555555555571',
    'customer_name_snapshot',    'CAS Snap Customer Inc',
    'customer_tin_snapshot',     '444-555-666-00017',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000c8'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));

INSERT INTO t_ctx
SELECT 'or1', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222270',
    'branch_id',              '33333333-3333-3333-3333-333333333370',
    'customer_id',            '55555555-5555-5555-5555-555555555571',
    'customer_name_snapshot', 'CAS Snap Customer Inc',
    'customer_tin_snapshot',  '444-555-666-00017',
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
    'company_id',              '22222222-2222-2222-2222-222222222270',
    'branch_id',               '33333333-3333-3333-3333-333333333370',
    'supplier_id',             '66666666-6666-6666-6666-666666666671',
    'supplier_name_snapshot',  'CAS Snap Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-00017',
    'supplier_invoice_number', 'SUP-INV-0171',
    'bill_date',               '2026-02-12'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000c9'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));

INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222270',
    'branch_id',              '33333333-3333-3333-3333-333333333370',
    'supplier_id',            '66666666-6666-6666-6666-666666666671',
    'supplier_name_snapshot', 'CAS Snap Supplier Corp',
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

-- ── 1-3. SLSP DAT export: snapshot + server-attested log row ───────────────────
INSERT INTO t_res
SELECT 'slsp1', fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
  'slsp', 2026, 2, 'slsp-February-2026.dat');

SELECT results_eq(
  $q$SELECT snapshot_status, report_type, snapshot_version, period_start, period_end,
            source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('exported'::text, 'CAS_SLSP'::text, 1, '2026-02-01'::date, '2026-02-28'::date, 2, 64)$$,
  'SLSP DAT export creates an exported v1 snapshot with a SHA-256 hash');

SELECT results_eq(
  $q$SELECT export_type, report_name, period_year, period_month, row_count,
            (generated_by IS NOT NULL),
            (snapshot_id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid),
            (artifact_id IS NOT NULL),
            (file_sha256 = file_hash),
            layout_version
     FROM cas_export_log
     WHERE company_id = '22222222-2222-2222-2222-222222222270'
       AND file_name = 'slsp-February-2026.dat'$q$,
  $$VALUES ('dat_file'::text, 'SLSP (Sales & Purchases)'::text, 2026, 2, 2,
            true, true, true, true, 'PXL-CAS-DAT-1.0'::text)$$,
  'the RPC writes the cas_export_log evidence row linked to the snapshot and artifact');

SELECT is(
  (SELECT val -> 'rows' FROM t_res WHERE key='slsp1'),
  (SELECT source_payload -> 'export_rows' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid),
  'the rows returned to the caller are exactly the frozen snapshot rows');

SELECT is(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1'),
  (SELECT source_payload ->> 'export_file_text' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid),
  'the export text returned to the caller is exactly the frozen snapshot file text');

SELECT is(
  (SELECT source_payload ->> 'export_file_sha256' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid),
  (SELECT encode(extensions.digest(convert_to(source_payload ->> 'export_file_text', 'UTF8'), 'sha256'), 'hex')
   FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid),
  'the snapshot stores the SHA-256 of the exact exported file text');

SELECT results_eq(
  $q$SELECT
        cel.file_sha256 = rs.source_payload ->> 'export_file_sha256',
        cel.file_size_bytes = octet_length(convert_to(rs.source_payload ->> 'export_file_text', 'UTF8'))
      FROM cas_export_log cel
      JOIN report_snapshots rs ON rs.id = cel.snapshot_id
      WHERE cel.company_id = '22222222-2222-2222-2222-222222222270'
        AND cel.file_name = 'slsp-February-2026.dat'$q$,
  $$VALUES (true, true)$$,
  'cas_export_log mirrors the frozen file hash and byte size');

SELECT ok(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1')
    LIKE 'H|PXL-CAS-DAT-1.0|CAS_SLSP|11122233300017|2026-02-01|2026-02-28|1%',
  'SLSP DAT bytes start with the versioned header record');

SELECT ok(
  position(E'\r\n' in (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1')) > 0,
  'CAS DAT records use CRLF newlines');

SELECT ok(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1')
    LIKE '%D|S|2026-02-10|SI-%|44455566600017|CAS Snap Customer Inc|10000.00|1200.00|Customer HQ, Taguig|T%',
  'SLSP DAT bytes contain the statutory sales detail fields');

SELECT ok(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1')
    LIKE '%D|P|2026-02-12|SUP-INV-0171|77788899900017|CAS Snap Supplier Corp|5000.00|600.00|Supplier HQ, Pasig|T%',
  'SLSP DAT bytes contain the statutory purchases detail fields');

SELECT ok(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1')
    LIKE '%' || E'\r\n' || 'T|2|15000.00|1800.00' || E'\r\n',
  'SLSP DAT bytes end with the row-count and amount trailer');

SELECT results_eq(
  $q$SELECT source_payload ->> 'export_layout',
            source_payload ->> 'newline_style',
            report_payload ->> 'file_name'
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('PXL-CAS-DAT-1.0'::text, 'CRLF'::text, 'slsp-February-2026.dat'::text)$$,
  'the snapshot stamps the DAT layout version, newline convention, and normalized filename');

INSERT INTO t_res
SELECT 'slsp_artifact1', fn_render_cas_dat(
  ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid
);

SELECT is(
  (SELECT val ->> 'content' FROM t_res WHERE key='slsp_artifact1'),
  (SELECT val ->> 'export_text' FROM t_res WHERE key='slsp1'),
  'fn_render_cas_dat returns the same immutable DAT bytes as the snapshot RPC');

SELECT is(
  (SELECT val ->> 'file_hash' FROM t_res WHERE key='slsp_artifact1'),
  (SELECT val ->> 'export_sha256' FROM t_res WHERE key='slsp1'),
  'fn_render_cas_dat returns the same byte hash as the snapshot RPC');

SELECT results_eq(
  $q$SELECT
        cel.artifact_id = ((SELECT val FROM t_res WHERE key='slsp_artifact1') ->> 'artifact_id')::uuid,
        cel.file_hash = ((SELECT val FROM t_res WHERE key='slsp_artifact1') ->> 'file_hash'),
        cel.layout_version
      FROM cas_export_log cel
      WHERE cel.snapshot_id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (true, true, 'PXL-CAS-DAT-1.0'::text)$$,
  'the export log points at the immutable DAT artifact');

SELECT is(
  (fn_render_cas_dat(
    ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid
  ) ->> 'artifact_id')::uuid,
  ((SELECT val FROM t_res WHERE key='slsp_artifact1') ->> 'artifact_id')::uuid,
  're-rendering a CAS DAT snapshot returns the same artifact');

-- ── 4-5. RELIEF and alphalist exports ──────────────────────────────────────────
INSERT INTO t_res
SELECT 'relief1', fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
  'relief', 2026, 2, 'relief-February-2026.dat');

SELECT results_eq(
  $q$SELECT report_type, source_row_count,
            source_payload ->> 'export_layout',
            (source_payload -> 'export_rows' @> '[{"transaction_type":"S"}]'::jsonb),
            (source_payload -> 'export_rows' @> '[{"transaction_type":"P"}]'::jsonb)
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='relief1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('CAS_RELIEF'::text, 2, 'PXL-CAS-DAT-1.0'::text, true, true)$$,
  'RELIEF DAT export freezes both sales and purchases rows');

SELECT ok(
  (SELECT val ->> 'export_text' FROM t_res WHERE key='relief1')
    LIKE '%D|R|11122233300017|P|77788899900017|CAS Snap Supplier Corp|Supplier HQ, Pasig|SUP-INV-0171|2026-02-12|5000.00|0.00|0.00|5000.00|600.00|AT%',
  'RELIEF DAT bytes include the BIR counterparty and VAT classification fields');

INSERT INTO t_res
SELECT 'qap1', fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
  'alphalist_payees', 2026, 2, 'alphalist_payees-February-2026.dat');

SELECT results_eq(
  $q$SELECT report_type, source_row_count,
            (source_payload -> 'export_rows' -> 0 ->> 'tax_withheld')::numeric
     FROM report_snapshots
     WHERE id = ((SELECT val FROM t_res WHERE key='qap1') ->> 'snapshot_id')::uuid$q$,
  $$VALUES ('CAS_QAP'::text, 1, 100.00::numeric)$$,
  'alphalist DAT export freezes the PV EWT row');

-- ── 6-8. GL extract: complete, balanced, and reconciliation-stamped ────────────
INSERT INTO t_res
SELECT 'gl1', fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
  'general_ledger', 2026, 2, 'general_ledger-February-2026.dat');

SELECT is(
  (SELECT source_row_count FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='gl1') ->> 'snapshot_id')::uuid),
  (SELECT count(*)::int FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222270'
     AND je_date BETWEEN '2026-02-01' AND '2026-02-28'),
  'GL DAT export freezes every GL line of the period');

SELECT is(
  (SELECT source_payload -> 'reconciliation' -> 0 ->> 'is_reconciled' FROM report_snapshots
   WHERE id = ((SELECT val FROM t_res WHERE key='gl1') ->> 'snapshot_id')::uuid),
  'true',
  'GL DAT export records the debit=credit balance check in the snapshot');

SELECT is(
  (SELECT (val ->> 'row_count')::int FROM t_res WHERE key='gl1'),
  (SELECT jsonb_array_length(val -> 'rows') FROM t_res WHERE key='gl1'),
  'the returned row_count matches the returned rows');

-- ── 9. Re-export versions the same logical source ──────────────────────────────
INSERT INTO t_res
SELECT 'slsp2', fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
  'slsp', 2026, 2, 'slsp-February-2026.dat');

SELECT results_eq(
  $q$SELECT s2.snapshot_version, (s2.source_id = s1.source_id)
     FROM report_snapshots s1, report_snapshots s2
     WHERE s1.id = ((SELECT val FROM t_res WHERE key='slsp1') ->> 'snapshot_id')::uuid
       AND s2.id = ((SELECT val FROM t_res WHERE key='slsp2') ->> 'snapshot_id')::uuid$q$,
  $$VALUES (2, true)$$,
  're-exporting the same period creates v2 on the same logical source');

-- ── 10. The export log is RPC-only for authenticated users ─────────────────────
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $q$INSERT INTO cas_export_log (company_id, export_type, report_name,
       period_year, period_month, file_name, row_count)
     VALUES ('22222222-2222-2222-2222-222222222270', 'dat_file', 'Forged Log',
       2026, 2, 'forged.dat', 999)$q$,
  '42501', NULL,
  'authenticated users cannot insert cas_export_log rows directly');
RESET ROLE;

-- ── 11-12. Input validation ────────────────────────────────────────────────────
SELECT throws_like(
  $q$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
       'balance_sheet', 2026, 2, 'x.dat')$q$,
  '%Unsupported CAS export report type%',
  'unknown CAS report types are rejected');

SELECT throws_like(
  $q$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
       'slsp', 2026, 2, '   ')$q$,
  '%file name is required%',
  'a blank file name is rejected');

-- ── 13-15. Reconciliation gates are per-report ─────────────────────────────────
SELECT fn_post_manual_je('22222222-2222-2222-2222-222222222270',
  '33333333-3333-3333-3333-333333333370', '2026-02-27',
  'Unsupported manual VAT adjustment', 'MANUAL', false,
  jsonb_build_array(
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-0000000000c9', 'debit_amount', 500),
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-0000000000c6', 'credit_amount', 500)
  ));

SELECT throws_like(
  $q$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
       'slsp', 2026, 2, 'slsp-February-2026.dat')$q$,
  '%does not reconcile%',
  'SLSP DAT export is blocked while VAT does not reconcile to the GL');

SELECT lives_ok(
  $q$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
       'alphalist_payees', 2026, 2, 'alphalist_payees-February-2026.dat')$q$,
  'alphalist DAT export still succeeds: EWT payable is unaffected by the VAT variance');

SELECT lives_ok(
  $q$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222270',
       'general_ledger', 2026, 2, 'general_ledger-February-2026.dat')$q$,
  'GL DAT export still succeeds: the manual JE is balanced');

SELECT * FROM finish();
ROLLBACK;
