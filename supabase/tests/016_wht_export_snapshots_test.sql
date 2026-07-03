-- ══════════════════════════════════════════════════════════════════════════════
-- WHT-EXPORT-SNAP-001 - SAWT/QAP Export Snapshots (PXL-DA-015)
--
-- SAWT (CWT withheld by customers) and QAP (EWT withheld from suppliers)
-- exports must create append-only, versioned, hash-stamped report snapshots
-- from ledger-backed sources, and must be blocked while the report's own GL
-- withholding control account does not reconcile to the tax ledger.
-- Exercises 20260703000007_report_snapshots_wht_exports.sql.
-- Follows the suite convention: FY2026 periods with CURRENT_DATE inside them.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111161',
        'authenticated', 'authenticated', 'harness-whtsnap@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111161","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222260', 'corporation',
        'WHT Snapshot Test Corp', 'Software Services', '111-222-333-016',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-whtsnap@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333360',
        '22222222-2222-2222-2222-222222222260', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444460',
        '22222222-2222-2222-2222-222222222260',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222260',
       '44444444-4444-4444-4444-444444444460',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-0000000000b1', '22222222-2222-2222-2222-222222222260',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b2', '22222222-2222-2222-2222-222222222260',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b3', '22222222-2222-2222-2222-222222222260',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b4', '22222222-2222-2222-2222-222222222260',
   '1400', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b5', '22222222-2222-2222-2222-222222222260',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b6', '22222222-2222-2222-2222-222222222260',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b7', '22222222-2222-2222-2222-222222222260',
   '2200', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b8', '22222222-2222-2222-2222-222222222260',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000b9', '22222222-2222-2222-2222-222222222260',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, ap_account_id, input_vat_account_id,
        ewt_withheld_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222260',
        'aaaaaaaa-0000-0000-0000-0000000000b2',
        'aaaaaaaa-0000-0000-0000-0000000000b6',
        'aaaaaaaa-0000-0000-0000-0000000000b1',
        'aaaaaaaa-0000-0000-0000-0000000000b5',
        'aaaaaaaa-0000-0000-0000-0000000000b3',
        'aaaaaaaa-0000-0000-0000-0000000000b4',
        'aaaaaaaa-0000-0000-0000-0000000000b7',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222260',
       '33333333-3333-3333-3333-333333333360',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'OR', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555561',
        '22222222-2222-2222-2222-222222222260', 'CUST-001',
        'WHT Snap Customer Inc', '444-555-666-016',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666661',
        '22222222-2222-2222-2222-222222222260', 'SUPP-001',
        'WHT Snap Supplier Corp', '777-888-999-016',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
-- The denial tests below run under SET LOCAL ROLE authenticated and still need
-- to resolve ids captured in the harness context.
GRANT SELECT ON t_ctx TO authenticated;

-- ── Q1 books: SI + OR with CWT (SAWT side), VB + PV with EWT (QAP side) ────────
INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222260',
    'branch_id',                 '33333333-3333-3333-3333-333333333360',
    'date',                      '2026-02-10',
    'customer_id',               '55555555-5555-5555-5555-555555555561',
    'customer_name_snapshot',    'WHT Snap Customer Inc',
    'customer_tin_snapshot',     '444-555-666-016',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b8'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));

INSERT INTO t_ctx
SELECT 'or1', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222260',
    'branch_id',              '33333333-3333-3333-3333-333333333360',
    'customer_id',            '55555555-5555-5555-5555-555555555561',
    'customer_name_snapshot', 'WHT Snap Customer Inc',
    'customer_tin_snapshot',  '444-555-666-016',
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
    'company_id',              '22222222-2222-2222-2222-222222222260',
    'branch_id',               '33333333-3333-3333-3333-333333333360',
    'supplier_id',             '66666666-6666-6666-6666-666666666661',
    'supplier_name_snapshot',  'WHT Snap Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-016',
    'supplier_invoice_number', 'SUP-INV-0161',
    'bill_date',               '2026-02-12'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000b9'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));

INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222260',
    'branch_id',              '33333333-3333-3333-3333-333333333360',
    'supplier_id',            '66666666-6666-6666-6666-666666666661',
    'supplier_name_snapshot', 'WHT Snap Supplier Corp',
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

-- 1. Baseline: Q1 withholding reconciles for both kinds
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-222222222260',
                                   '2026-01-01', '2026-03-31')$q$,
  $$VALUES ('cwt_receivable'::text, 224.00::numeric(15,2), 224.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('ewt_payable'::text,    100.00::numeric(15,2), 100.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'baseline: Q1 CWT receivable and EWT payable reconcile to the GL');

-- 2. Ledger-backed SAWT source view shows the gross income payment
SELECT results_eq(
  $q$SELECT customer_tin, atc_code, income_payment, cwt_withheld
     FROM vw_cwt_summary_ar
     WHERE company_id = '22222222-2222-2222-2222-222222222260'$q$,
  $$VALUES ('444-555-666-016'::text, 'WC140'::text, 11200.00::numeric, 224.00::numeric)$$,
  'vw_cwt_summary_ar exposes the OR CWT row with the gross income payment');

-- 3-5. SAWT export creates a versioned exported snapshot with a SHA-256 hash
INSERT INTO t_ctx
SELECT 'sawt1', fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'SAWT', 2026, 1);

SELECT results_eq(
  $q$SELECT snapshot_status, report_type, snapshot_version, period_start, period_end,
            source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE id = (SELECT id FROM t_ctx WHERE key='sawt1')$q$,
  $$VALUES ('exported'::text, 'SAWT'::text, 1, '2026-01-01'::date, '2026-03-31'::date, 1, 64)$$,
  'SAWT export creates an exported v1 snapshot with a SHA-256 hash');

SELECT is(
  (SELECT (source_payload -> 'payer_summary_rows' -> 0 ->> 'income_payments')::numeric
   FROM report_snapshots WHERE id = (SELECT id FROM t_ctx WHERE key='sawt1')),
  11200.00::numeric,
  'SAWT snapshot payload freezes the per-customer gross income payments');

SELECT is(
  (SELECT (source_payload -> 'payer_summary_rows' -> 0 ->> 'cwt_withheld')::numeric
   FROM report_snapshots WHERE id = (SELECT id FROM t_ctx WHERE key='sawt1')),
  224.00::numeric,
  'SAWT snapshot payload freezes the per-customer CWT withheld');

-- 6-7. QAP export creates its own snapshot with frozen payee totals
INSERT INTO t_ctx
SELECT 'qap1', fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'QAP', 2026, 1);

SELECT results_eq(
  $q$SELECT snapshot_status, report_type, snapshot_version, source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE id = (SELECT id FROM t_ctx WHERE key='qap1')$q$,
  $$VALUES ('exported'::text, 'QAP'::text, 1, 1, 64)$$,
  'QAP export creates an exported v1 snapshot with a SHA-256 hash');

SELECT is(
  (SELECT (source_payload -> 'payee_summary_rows' -> 0 ->> 'tax_withheld')::numeric
   FROM report_snapshots WHERE id = (SELECT id FROM t_ctx WHERE key='qap1')),
  100.00::numeric,
  'QAP snapshot payload freezes the per-supplier tax withheld');

-- 8. Re-export increments the version on the same logical source
INSERT INTO t_ctx
SELECT 'qap2', fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'QAP', 2026, 1);

SELECT results_eq(
  $q$SELECT s2.snapshot_version, (s2.source_id = s1.source_id)
     FROM report_snapshots s1, report_snapshots s2
     WHERE s1.id = (SELECT id FROM t_ctx WHERE key='qap1')
       AND s2.id = (SELECT id FROM t_ctx WHERE key='qap2')$q$,
  $$VALUES (2, true)$$,
  're-exporting QAP for the same quarter creates v2 on the same logical source');

-- 9-10. Snapshots are append-only for authenticated users: direct inserts are
-- rejected, and update/delete policies filter every row (statements no-op).
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $q$INSERT INTO report_snapshots (company_id, report_type, source_table, source_id,
       snapshot_status, snapshot_version, period_start, period_end,
       report_payload, source_payload, source_hash)
     VALUES ('22222222-2222-2222-2222-222222222260', 'QAP', 'wht_export_periods',
       gen_random_uuid(), 'exported', 99, '2026-01-01', '2026-03-31',
       '{}'::jsonb, '{}'::jsonb, repeat('0', 64))$q$,
  '42501', NULL,
  'authenticated users cannot insert a report snapshot directly');

UPDATE report_snapshots SET source_hash = repeat('0', 64)
WHERE id = (SELECT id FROM t_ctx WHERE key='qap1');
DELETE FROM report_snapshots
WHERE id = (SELECT id FROM t_ctx WHERE key='qap1');
RESET ROLE;

SELECT isnt(
  (SELECT source_hash FROM report_snapshots
   WHERE id = (SELECT id FROM t_ctx WHERE key='qap1')),
  repeat('0', 64),
  'authenticated update/delete statements leave the snapshot row untouched');

-- 11. Unsupported report types are rejected
SELECT throws_like(
  $q$SELECT fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'ALPHALIST', 2026, 1)$q$,
  '%Unsupported withholding export report type%',
  'unknown withholding report types are rejected');

-- 12. Invalid quarters are rejected
SELECT throws_like(
  $q$SELECT fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'QAP', 2026, 5)$q$,
  '%Invalid withholding export quarter%',
  'quarters outside 1-4 are rejected');

-- ── Manual JE on the EWT payable control account without tax detail ────────────
SELECT fn_post_manual_je('22222222-2222-2222-2222-222222222260',
  '33333333-3333-3333-3333-333333333360', '2026-03-05',
  'Unsupported manual EWT adjustment', 'MANUAL', false,
  jsonb_build_array(
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-0000000000b9', 'debit_amount', 50),
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-0000000000b7', 'credit_amount', 50)
  ));

-- 13. QAP export is blocked while EWT payable does not reconcile
SELECT throws_like(
  $q$SELECT fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'QAP', 2026, 1)$q$,
  '%does not reconcile to GL account%',
  'QAP export is blocked while the EWT payable control account is unreconciled');

-- 14. SAWT export still works: its own control account still reconciles
SELECT lives_ok(
  $q$SELECT fn_snapshot_wht_export('22222222-2222-2222-2222-222222222260', 'SAWT', 2026, 1)$q$,
  'SAWT export still succeeds while only the EWT payable side is unreconciled');

SELECT * FROM finish();
ROLLBACK;
