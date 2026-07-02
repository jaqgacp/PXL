-- ══════════════════════════════════════════════════════════════════════════════
-- TAX-LEDGER-VOID-001 - Void/Cancel/Bounce Counter-Entries (PXL-AUD-027)
--
-- Voiding a posted SI/VB, cancelling a posted PV, and bouncing a posted OR must
-- net the tax ledger with counter-rows (originals preserved), so
-- fn_vat_gl_reconciliation keeps reconciling per period exactly like the GL,
-- and cancelled withholding stops feeding vw_ewt_summary_ap / 2307 data.
-- Exercises 20260702000009_tax_ledger_void_reversal.sql.
-- Follows the suite convention: FY2026 periods with CURRENT_DATE inside them.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111141',
        'authenticated', 'authenticated', 'harness-voidtax@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111141","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222230', 'corporation',
        'Void Tax Test Corp', 'Software Services', '111-222-333-014',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-voidtax@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333350',
        '22222222-2222-2222-2222-222222222230', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444470',
        '22222222-2222-2222-2222-222222222230',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222230',
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
  ('aaaaaaaa-0000-0000-0000-0000000000a1', '22222222-2222-2222-2222-222222222230',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a2', '22222222-2222-2222-2222-222222222230',
   '1200', 'Accounts Receivable',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a3', '22222222-2222-2222-2222-222222222230',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a4', '22222222-2222-2222-2222-222222222230',
   '1400', 'CWT Receivable',            'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a5', '22222222-2222-2222-2222-222222222230',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a6', '22222222-2222-2222-2222-222222222230',
   '2100', 'Output VAT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a7', '22222222-2222-2222-2222-222222222230',
   '2200', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a8', '22222222-2222-2222-2222-222222222230',
   '4010', 'Service Revenue',           'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a9', '22222222-2222-2222-2222-222222222230',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        default_cash_account_id, ap_account_id, input_vat_account_id,
        ewt_withheld_account_id, ewt_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222230',
        'aaaaaaaa-0000-0000-0000-0000000000a2',
        'aaaaaaaa-0000-0000-0000-0000000000a6',
        'aaaaaaaa-0000-0000-0000-0000000000a1',
        'aaaaaaaa-0000-0000-0000-0000000000a5',
        'aaaaaaaa-0000-0000-0000-0000000000a3',
        'aaaaaaaa-0000-0000-0000-0000000000a4',
        'aaaaaaaa-0000-0000-0000-0000000000a7',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222230',
       '33333333-3333-3333-3333-333333333350',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'OR', 'PV');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555571',
        '22222222-2222-2222-2222-222222222230', 'CUST-001',
        'Void Test Customer Inc', '444-555-666-014',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666671',
        '22222222-2222-2222-2222-222222222230', 'SUPP-001',
        'Void Test Supplier Corp', '777-888-999-014',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ── Phase A: January books — SI 10,000 + 1,200 output; VB 5,000 + 600 input ────
INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222230',
    'branch_id',                 '33333333-3333-3333-3333-333333333350',
    'date',                      '2026-01-15',
    'customer_id',               '55555555-5555-5555-5555-555555555571',
    'customer_name_snapshot',    'Void Test Customer Inc',
    'customer_tin_snapshot',     '444-555-666-014',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000a8'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));

INSERT INTO t_ctx
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222230',
    'branch_id',               '33333333-3333-3333-3333-333333333350',
    'supplier_id',             '66666666-6666-6666-6666-666666666671',
    'supplier_name_snapshot',  'Void Test Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-014',
    'supplier_invoice_number', 'SUP-INV-0141',
    'bill_date',               '2026-01-20'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000a9'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'));

-- 1. Baseline: January reconciles for both VAT kinds
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230',
                                   '2026-01-01', '2026-01-31')$q$,
  $$VALUES ('input_vat'::text,  600.00::numeric(15,2),  600.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('output_vat'::text, 1200.00::numeric(15,2), 1200.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'baseline: January output and input VAT reconcile');

-- ── Phase B: void the posted SI today ───────────────────────────────────────────
SELECT fn_void_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'), NULL, 'void test');

-- 2. Original ledger row is preserved, never mutated
SELECT results_eq(
  format($q$SELECT is_reversal, filing_status, tax_base, tax_amount
          FROM tax_detail_entries
          WHERE source_doc_type = 'SI' AND source_doc_id = %L
            AND reverses_tax_detail_id IS NULL$q$,
         (SELECT id FROM t_ctx WHERE key='si1')),
  $$VALUES (false, 'draft'::text, 10000.00::numeric, 1200.00::numeric)$$,
  'voided SI: original output VAT row is preserved untouched');

-- 3. Counter-row negates it, linked to the original
SELECT results_eq(
  format($q$SELECT t.is_reversal, t.tax_base, t.tax_amount,
                 (t.document_date = CURRENT_DATE),
                 (o.source_doc_id = t.source_doc_id)
          FROM tax_detail_entries t
          JOIN tax_detail_entries o ON o.id = t.reverses_tax_detail_id
          WHERE t.source_doc_type = 'SI' AND t.source_doc_id = %L
            AND t.reverses_tax_detail_id IS NOT NULL$q$,
         (SELECT id FROM t_ctx WHERE key='si1')),
  $$VALUES (true, -10000.00::numeric, -1200.00::numeric, true, true)$$,
  'voided SI: counter-row negates the original, dated on the void date');

-- 4. January still reconciles after the void (activity stays in its period)
SELECT results_eq(
  $q$SELECT ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230',
                                   '2026-01-01', '2026-01-31')
     WHERE tax_kind = 'output_vat'$q$,
  $$VALUES (1200.00::numeric(15,2), 1200.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'January output VAT still reconciles after a later void');

-- 5. The void month reconciles: ledger counter matches the reversal JE
SELECT results_eq(
  format($q$SELECT ledger_tax_amount, gl_amount, variance, is_reconciled
          FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230', %L, %L)
          WHERE tax_kind = 'output_vat'$q$,
         date_trunc('month', CURRENT_DATE)::date,
         (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date),
  $$VALUES (-1200.00::numeric(15,2), -1200.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'void month output VAT reconciles: counter-row matches the reversal JE');

-- ── Phase C: void the posted VB today ───────────────────────────────────────────
SELECT fn_void_vendor_bill((SELECT id FROM t_ctx WHERE key='vb1'), NULL, 'void test');

-- 6. No flag-flipped originals exist (old mutation behavior is gone)
SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type = 'VB'
     AND source_doc_id = (SELECT id FROM t_ctx WHERE key='vb1')
     AND is_reversal = true AND reverses_tax_detail_id IS NULL),
  0, 'voided VB: no original row was flag-flipped');

-- 7. VB counter-row exists and negates the input VAT
SELECT results_eq(
  format($q$SELECT tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'VB' AND source_doc_id = %L
            AND reverses_tax_detail_id IS NOT NULL$q$,
         (SELECT id FROM t_ctx WHERE key='vb1')),
  $$VALUES (-5000.00::numeric, -600.00::numeric)$$,
  'voided VB: counter-row negates the input VAT');

-- 8. Full-year VAT nets to zero and reconciles for both kinds
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230',
                                   '2026-01-01', '2026-12-31')$q$,
  $$VALUES ('input_vat'::text,  0.00::numeric(15,2), 0.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('output_vat'::text, 0.00::numeric(15,2), 0.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'full-year VAT nets to zero in both ledger and GL after the voids');

-- ── Phase D: OR with CWT, then bounce ───────────────────────────────────────────
INSERT INTO t_ctx
SELECT 'si2', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222230',
    'branch_id',                 '33333333-3333-3333-3333-333333333350',
    'date',                      '2026-02-15',
    'customer_id',               '55555555-5555-5555-5555-555555555571',
    'customer_name_snapshot',    'Void Test Customer Inc',
    'customer_tin_snapshot',     '444-555-666-014',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-0000000000a8'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si2'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si2'));

INSERT INTO t_ctx
SELECT 'or1', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222230',
    'branch_id',              '33333333-3333-3333-3333-333333333350',
    'customer_id',            '55555555-5555-5555-5555-555555555571',
    'customer_name_snapshot', 'Void Test Customer Inc',
    'customer_tin_snapshot',  '444-555-666-014',
    'receipt_date',           current_date::text,
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           10976,
    'total_cwt',              224
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key='si2'),
    'payment_amount', 10976,
    'cwt_amount',     224,
    'atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140')
  )));
SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key='or1'));

-- 9. Posted OR wrote its CWT receivable row
SELECT is(
  (SELECT sum(tax_amount)::numeric FROM tax_detail_entries
   WHERE source_doc_type = 'OR'
     AND source_doc_id = (SELECT id FROM t_ctx WHERE key='or1')
     AND tax_kind = 'cwt_receivable'),
  224.00::numeric, 'posted OR claims 224.00 CWT receivable in the tax ledger');

SELECT fn_bounce_receipt((SELECT id FROM t_ctx WHERE key='or1'));

-- 10. Bounced OR: CWT nets to zero in the ledger
SELECT is(
  (SELECT sum(tax_amount)::numeric FROM tax_detail_entries
   WHERE source_doc_type = 'OR'
     AND source_doc_id = (SELECT id FROM t_ctx WHERE key='or1')
     AND tax_kind = 'cwt_receivable'),
  0.00::numeric, 'bounced OR: CWT receivable nets to zero');

-- 11. The CWT counter-row is linked and dated on the bounce date
SELECT results_eq(
  format($q$SELECT is_reversal, (document_date = CURRENT_DATE),
                 (reverses_tax_detail_id IS NOT NULL)
          FROM tax_detail_entries
          WHERE source_doc_type = 'OR' AND source_doc_id = %L
            AND tax_kind = 'cwt_receivable' AND tax_amount < 0$q$,
         (SELECT id FROM t_ctx WHERE key='or1')),
  $$VALUES (true, true, true)$$,
  'bounced OR: CWT counter-row is linked and dated on the bounce date');

-- ── Phase E: PV with EWT, then cancel ───────────────────────────────────────────
INSERT INTO t_ctx
SELECT 'vb2', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222230',
    'branch_id',               '33333333-3333-3333-3333-333333333350',
    'supplier_id',             '66666666-6666-6666-6666-666666666671',
    'supplier_name_snapshot',  'Void Test Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-014',
    'supplier_invoice_number', 'SUP-INV-0142',
    'bill_date',               '2026-03-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         5000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-0000000000a9'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb2'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb2'));

INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222230',
    'branch_id',              '33333333-3333-3333-3333-333333333350',
    'supplier_id',            '66666666-6666-6666-6666-666666666671',
    'supplier_name_snapshot', 'Void Test Supplier Corp',
    'voucher_date',           current_date::text,
    'total_amount',           5500,
    'total_ewt',              100
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb2'),
    'payment_amount',    5500,
    'ewt_amount',        100,
    'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',      5000,
    'ewt_income_nature', 'Contractor services'
  )));
SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key='pv1'));

-- 12. Posted PV appears in the 2307 source view
SELECT is(
  (SELECT sum(tax_withheld)::numeric FROM vw_ewt_summary_ap
   WHERE transaction_id = (SELECT id FROM t_ctx WHERE key='pv1')),
  100.00::numeric, 'posted PV shows 100.00 EWT in vw_ewt_summary_ap');

SELECT fn_cancel_payment_voucher((SELECT id FROM t_ctx WHERE key='pv1'), 'cancel test');

-- 13. Cancelled PV vanishes from the 2307 source view entirely
SELECT is(
  (SELECT count(*)::int FROM vw_ewt_summary_ap
   WHERE transaction_id = (SELECT id FROM t_ctx WHERE key='pv1')),
  0, 'cancelled PV no longer appears in vw_ewt_summary_ap');

-- 14. But the raw ledger preserves both rows, netting to zero
SELECT results_eq(
  format($q$SELECT count(*)::int, sum(tax_amount)::numeric FROM tax_detail_entries
          WHERE source_doc_type = 'PV' AND source_doc_id = %L
            AND tax_kind = 'ewt_payable'$q$,
         (SELECT id FROM t_ctx WHERE key='pv1')),
  $$VALUES (2, 0.00::numeric)$$,
  'cancelled PV: original and counter-row both preserved, netting to zero');

-- 15. Whole-ledger integrity: every reversed pair nets exactly to zero
SELECT is(
  (SELECT COALESCE(sum(t.tax_amount + o.tax_amount), 0)::numeric
   FROM tax_detail_entries t
   JOIN tax_detail_entries o ON o.id = t.reverses_tax_detail_id
   WHERE t.company_id = '22222222-2222-2222-2222-222222222230'),
  0.00::numeric, 'every counter-row exactly negates the row it reverses');

-- 16. Status guards still hold: double void rejected
SELECT throws_like(
  format('SELECT fn_void_sales_invoice(%L, NULL, NULL)',
         (SELECT id FROM t_ctx WHERE key='si1')),
  '%already voided%',
  'voiding an already-voided SI is rejected');

-- 17. Final full-year reconciliation: only live documents remain
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230',
                                   '2026-01-01', '2026-12-31')$q$,
  $$VALUES ('input_vat'::text,  600.00::numeric(15,2),  600.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('output_vat'::text, 1200.00::numeric(15,2), 1200.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'final full-year reconciliation reflects only live SI2/VB2 activity');

SELECT * FROM finish();
ROLLBACK;
