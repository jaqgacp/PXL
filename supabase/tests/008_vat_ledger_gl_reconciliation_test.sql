-- ══════════════════════════════════════════════════════════════════════════════
-- VAT-RECON-001 - VAT Tax-Ledger-to-GL Reconciliation (PXL-AUD-014, PXL-DA-008)
--
-- fn_vat_gl_reconciliation must reconcile tax_detail_entries to the GL VAT
-- control accounts, and a VAT return must be blocked from final/filed while
-- the period is unreconciled or the return figures diverge from the tax
-- ledger. Exercises 20260702000004_vat_ledger_gl_reconciliation.sql.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(21);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111119',
        'authenticated', 'authenticated', 'harness-vatrecon@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111119","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222229', 'corporation',
        'VAT Recon Test Corp', 'Software Services', '111-222-333-009',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-vatrecon@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333339',
        '22222222-2222-2222-2222-222222222229', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444459',
        '22222222-2222-2222-2222-222222222229',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222229',
       '44444444-4444-4444-4444-444444444459',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000061', '22222222-2222-2222-2222-222222222229',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000062', '22222222-2222-2222-2222-222222222229',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000063', '22222222-2222-2222-2222-222222222229',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000064', '22222222-2222-2222-2222-222222222229',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000065', '22222222-2222-2222-2222-222222222229',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000066', '22222222-2222-2222-2222-222222222229',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000067', '22222222-2222-2222-2222-222222222229',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, ap_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222229',
        'aaaaaaaa-0000-0000-0000-000000000062',
        'aaaaaaaa-0000-0000-0000-000000000065',
        'aaaaaaaa-0000-0000-0000-000000000061',
        'aaaaaaaa-0000-0000-0000-000000000064',
        'aaaaaaaa-0000-0000-0000-000000000063',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222229',
       '33333333-3333-3333-3333-333333333339',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555559',
        '22222222-2222-2222-2222-222222222229', 'CUST-001',
        'Recon Customer Inc', '444-555-666-009',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666669',
        '22222222-2222-2222-2222-222222222229', 'SUPP-001',
        'Recon Supplier Corp', '777-888-999-009',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── January books: SI 10,000 + 1,200 output VAT; VB 5,000 + 600 input VAT ──────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222229',
    'branch_id',                 '33333333-3333-3333-3333-333333333339',
    'date',                      '2026-01-15',
    'customer_id',               '55555555-5555-5555-5555-555555555559',
    'customer_name_snapshot',    'Recon Customer Inc',
    'customer_tin_snapshot',     '444-555-666-009',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000066'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222229',
    'branch_id',               '33333333-3333-3333-3333-333333333339',
    'supplier_id',             '66666666-6666-6666-6666-666666666669',
    'supplier_name_snapshot',  'Recon Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-009',
    'supplier_invoice_number', 'SUP-INV-0009',
    'bill_date',               '2026-01-20'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000067'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

-- ── 1. January reconciles: ledger = GL for both VAT kinds ──────────────────────
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222229',
                                   '2026-01-01', '2026-01-31')$q$,
  $$VALUES ('input_vat'::text,  5000.00::numeric(15,2),  600.00::numeric(15,2),  600.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('output_vat'::text, 10000.00::numeric(15,2), 1200.00::numeric(15,2), 1200.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'January output/input VAT tax ledger reconciles to the GL control accounts');

-- ── 2-3. Reconciled + matching return can be saved and finalized ───────────────
SELECT lives_ok(
  $q$INSERT INTO vat_returns (company_id, return_type, period_year, period_month,
        output_taxable_sales, output_vat, input_taxable_purchases, input_vat,
        total_available_input_vat, net_vat_payable, status, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222229', '2550M', 2026, 1,
        10000.00, 1200.00, 5000.00, 600.00, 600.00, 600.00, 'draft', auth.uid(), auth.uid())$q$,
  'reconciled January draft return saves');

SELECT lives_ok(
  $q$UPDATE vat_returns SET status = 'final'
     WHERE company_id = '22222222-2222-2222-2222-222222222229'
       AND return_type = '2550M' AND period_year = 2026 AND period_month = 1$q$,
  'reconciled January return with matching figures can be marked final');

-- ── 4-7. Final/filed VAT returns create immutable source snapshots ────────────
SELECT results_eq(
  $q$SELECT snapshot_status, report_type, period_start, period_end,
            source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE source_table = 'vat_returns'
       AND source_id = (
         SELECT id FROM vat_returns
         WHERE company_id = '22222222-2222-2222-2222-222222222229'
           AND return_type = '2550M' AND period_year = 2026 AND period_month = 1
       )$q$,
  $$VALUES ('final'::text, '2550M'::text, '2026-01-01'::date, '2026-01-31'::date, 2, 64)$$,
  'marking a VAT return final creates an immutable source snapshot with a SHA-256 hash');

SELECT throws_like(
  $q$UPDATE vat_returns SET output_vat = 1199.00
     WHERE company_id = '22222222-2222-2222-2222-222222222229'
       AND return_type = '2550M' AND period_year = 2026 AND period_month = 1$q$,
  '%immutable report snapshot%',
  'snapshot-backed VAT return amount fields cannot be changed');

SELECT lives_ok(
  $q$UPDATE vat_returns
     SET status = 'filed', filed_date = '2026-02-20', reference_no = '2550M-JAN-2026'
     WHERE company_id = '22222222-2222-2222-2222-222222222229'
       AND return_type = '2550M' AND period_year = 2026 AND period_month = 1$q$,
  'final VAT return can still be marked filed with filing metadata');

SELECT results_eq(
  $q$SELECT snapshot_status, count(*)::int
     FROM report_snapshots
     WHERE source_table = 'vat_returns'
       AND source_id = (
         SELECT id FROM vat_returns
         WHERE company_id = '22222222-2222-2222-2222-222222222229'
           AND return_type = '2550M' AND period_year = 2026 AND period_month = 1
       )
     GROUP BY snapshot_status
     ORDER BY snapshot_status$q$,
  $$VALUES ('filed'::text, 1), ('final'::text, 1)$$,
  'filing a VAT return creates a separate filed snapshot without changing the final snapshot');

-- ── 8-14. SLSP/RELIEF exports create versioned immutable snapshots ───────────
SELECT lives_ok(
  $q$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222229',
        'SLSP', 2026, 1, 'sales')$q$,
  'SLSP sales export creates an exported snapshot for a reconciled period');

SELECT lives_ok(
  $q$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222229',
        'SLSP', 2026, 1, 'purchases')$q$,
  'SLSP purchases export creates an exported snapshot for a reconciled period');

SELECT results_eq(
  $q$SELECT report_payload->>'export_part', snapshot_status, snapshot_version,
            source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE source_table = 'vat_export_periods'
       AND report_type = 'SLSP'
       AND company_id = '22222222-2222-2222-2222-222222222229'
     ORDER BY report_payload->>'export_part'$q$,
  $$VALUES ('purchases'::text, 'exported'::text, 1, 1, 64),
           ('sales'::text,     'exported'::text, 1, 1, 64)$$,
  'SLSP export snapshots are separated by export part with one source row each');

SELECT lives_ok(
  $q$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222229',
        'RELIEF', 2026, 1, 'all')$q$,
  'RELIEF export creates an exported snapshot for a reconciled period');

SELECT results_eq(
  $q$SELECT report_type, report_payload->>'export_part', snapshot_status,
            snapshot_version, source_row_count, length(source_hash)
     FROM report_snapshots
     WHERE source_table = 'vat_export_periods'
       AND report_type = 'RELIEF'
       AND company_id = '22222222-2222-2222-2222-222222222229'$q$,
  $$VALUES ('RELIEF'::text, 'all'::text, 'exported'::text, 1, 2, 64)$$,
  'RELIEF all export snapshot captures sales and purchases detail rows');

SELECT lives_ok(
  $q$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222229',
        'RELIEF', 2026, 1, 'all')$q$,
  're-exporting the same RELIEF period creates a new export history version');

SELECT results_eq(
  $q$SELECT snapshot_version
     FROM report_snapshots
     WHERE source_table = 'vat_export_periods'
       AND report_type = 'RELIEF'
       AND company_id = '22222222-2222-2222-2222-222222222229'
     ORDER BY snapshot_version$q$,
  $$VALUES (1), (2)$$,
  'repeated RELIEF exports keep versioned history for the same period');

-- ── 15. Return figures that diverge from the tax ledger are blocked ───────────
SELECT throws_like(
  $q$INSERT INTO vat_returns (company_id, return_type, period_year, period_month,
        output_taxable_sales, output_vat, input_taxable_purchases, input_vat,
        total_available_input_vat, net_vat_payable, status, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222229', '2550M', 2026, 3,
        0, 999.00, 0, 0, 0, 999.00, 'final', auth.uid(), auth.uid())$q$,
  '%does not match the tax ledger%',
  'final return whose output VAT diverges from the tax ledger is rejected');

-- ── 16. Manual JE on the VAT control account without tax detail → variance ────
SELECT lives_ok(
  $q$SELECT fn_post_manual_je('22222222-2222-2222-2222-222222222229',
        '33333333-3333-3333-3333-333333333339', '2026-02-10',
        'Unsupported manual VAT adjustment', 'MANUAL', false,
        jsonb_build_array(
          jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000067', 'debit_amount', 500),
          jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000065', 'credit_amount', 500)
        ))$q$,
  'manual JE hitting the output VAT control account posts');

SELECT results_eq(
  $q$SELECT ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222229',
                                   '2026-02-01', '2026-02-28')
     WHERE tax_kind = 'output_vat'$q$,
  $$VALUES (0.00::numeric(15,2), 500.00::numeric(15,2), -500.00::numeric(15,2), false)$$,
  'February output VAT shows a -500.00 GL variance with no tax ledger support');

-- ── 17-19. Unreconciled period: draft allowed, final/filed blocked ────────────
SELECT lives_ok(
  $q$INSERT INTO vat_returns (company_id, return_type, period_year, period_month,
        output_taxable_sales, output_vat, input_taxable_purchases, input_vat,
        total_available_input_vat, net_vat_payable, status, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222229', '2550M', 2026, 2,
        0, 0, 0, 0, 0, 0, 'draft', auth.uid(), auth.uid())$q$,
  'draft return for the unreconciled period still saves');

SELECT throws_like(
  $q$UPDATE vat_returns SET status = 'final'
     WHERE company_id = '22222222-2222-2222-2222-222222222229'
       AND return_type = '2550M' AND period_year = 2026 AND period_month = 2$q$,
  '%does not reconcile to GL account%',
  'unreconciled period blocks marking the return final');

SELECT throws_like(
  $q$UPDATE vat_returns SET status = 'filed', filed_date = '2026-03-20'
     WHERE company_id = '22222222-2222-2222-2222-222222222229'
       AND return_type = '2550M' AND period_year = 2026 AND period_month = 2$q$,
  '%does not reconcile to GL account%',
  'unreconciled period blocks marking the return filed');

-- ── 20. Unreconciled period: export snapshot blocked ──────────────────────────
SELECT throws_like(
  $q$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222229',
        'RELIEF', 2026, 2, 'all')$q$,
  '%does not reconcile to GL account%',
  'unreconciled period blocks VAT export snapshot creation');

SELECT * FROM finish();
ROLLBACK;
