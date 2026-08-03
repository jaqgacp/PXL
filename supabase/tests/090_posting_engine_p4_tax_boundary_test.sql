-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P4-001 — Tax Boundary Certification (frozen Posting Engine
-- specification §2.2 / §5.3, roadmap phase P4, re-scoped by architecture board
-- decision 2026-07-26)
--
-- WHAT THIS CERTIFIES
--   The ownership boundary between tax calculation, tax account resolution,
--   tax-line posting, and tax-ledger persistence:
--     • tax POLICY + CALCULATION  — owned by the Tax Engine, fn_calculate_tax
--     • tax ACCOUNT RESOLUTION    — owned by the certified COA Resolver
--     • tax LINE CONSTRUCTION     — owned by the Posting Engine
--     • tax DETAIL + REVERSAL     — owned by the Tax Ledger layer
--
-- UPDATED 2026-08-03 BY DELIVERY PLAN PHASE 4 (PAD-001)
--   This file previously certified the ENGINE'S ABSENCE and censused eleven
--   duplicated calculators as registered technical debt. The engine now exists,
--   so assertions 4-8, 16, 39, 44 and 48-49 were inverted: they assert that
--   exactly one function in the schema turns a rate into a tax amount, and that
--   nothing in the posting layer does.
--
--   The numbers did not move. Assertions 17-43, 45 and 46 — every stored tax
--   fact, every posted GL tax line, every tax-ledger row, both GL
--   reconciliations, reversal provenance under a changed rate, and the
--   100.05-at-12% rounding agreement across all five reachable document
--   calculators — passed UNCHANGED across the migration. That is the Phase 4
--   "every existing caller produces identical tax output" proof.
--
-- WHAT THIS STILL EXPLICITLY DOES NOT CLAIM
--   • Philippine tax function completeness is NOT claimed.
--   • Percentage tax is NOT calculated anywhere, by the engine or otherwise.
--     No document reaches it yet. See the Product Backlog.
--   • Filing capability is NOT claimed; that is Delivery Plan Phase 5.8.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(51);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Tax-aware posting-writer census (complete and pinned)
--
-- A "tax-aware posting writer" is a function that reaches the General Ledger
-- (directly, through the sanctioned kernels, through a posting-line helper, or
-- through a VAT lump poster) AND references VAT / EWT / CWT / withholding /
-- tax in its body. The predicate is evaluated against the live pg_proc
-- catalog, which is authoritative over any prose count.
-- ══════════════════════════════════════════════════════════════════════════════
CREATE TEMP VIEW v_gl_writer AS
SELECT p.oid, p.proname::text AS proname, p.prosrc
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND (p.prosrc ~ 'INSERT INTO\s+journal_entr'
    OR p.prosrc ~ 'fn_create_posted_journal_entry'
    OR p.prosrc ~ 'fn_add_posting_line'
    OR p.prosrc ~ 'fn_add_sales_invoice_posting_line'
    OR p.prosrc ~ 'fn_reverse_posted_journal_entry'
    OR p.prosrc ~ 'fn_bt_reverse_je\s*\('
    OR p.prosrc ~ 'fn_reverse_je\s*\('
    OR p.prosrc ~ 'fn_post_(credit_memo|debit_memo|vendor_credit)_vat_lump_impl')
  -- The P5.1 guard helpers NAME the kernels as match data; they write no ledger.
  AND p.proname NOT IN ('fn_posting_kernel_origin', 'fn_guard_journal_kernel_origin');

CREATE TEMP VIEW v_tax_writer AS
SELECT * FROM v_gl_writer WHERE prosrc ~* '(vat|ewt|cwt|withhold|tax)';

SELECT set_eq(
  $$SELECT proname FROM v_tax_writer$$,
  $$VALUES
     ('fn_post_sales_invoice'),
     ('fn_post_vendor_bill'),
     ('fn_post_cash_purchase_source_locked_impl'),
     ('fn_post_check_voucher'),
     ('fn_post_payment_voucher'),
     ('fn_post_receipt'),
     ('fn_post_withholding_remittance'),
     ('fn_post_credit_memo_source_locked_impl'),
     ('fn_post_credit_memo_vat_lump_impl'),
     ('fn_post_debit_memo_source_locked_impl'),
     ('fn_post_debit_memo_vat_lump_impl'),
     ('fn_post_vendor_credit_source_locked_impl'),
     ('fn_post_vendor_credit_vat_lump_impl'),
     ('fn_save_cash_sale'),
     ('fn_void_sales_invoice_aud053_core'),
     ('fn_void_vendor_bill'),
     ('fn_void_withholding_remittance'),
     ('fn_bounce_receipt'),
     ('fn_cancel_payment_voucher'),
     ('fn_cancel_check_voucher')$$,
  'the tax-aware posting-writer census is exactly the 20 censused writers');       -- 1

-- The census partitions the GL-writer population: every GL writer is either
-- tax-aware (20) or provably not (33). The obsolete P5.1 line helper was
-- removed after its callers had already moved to the six sanctioned functions.
-- PXL-AUD-073 added fn_post_receiving_report_source_locked_impl, which posts a
-- goods receipt at cost and computes no tax, so the non-tax partition grew by one.
-- PAD-002 adds the opening-balance post and reversal writers. Both use the
-- Accounting Kernel and neither calculates or persists tax.
-- fn_post_delivery_receipt joined on 2026-08-03 for the same reason: a delivery
-- moves cost from inventory to goods-delivered-not-invoiced and touches no tax.
-- Delivery Plan Phase 6 adds fn_reopen_fiscal_year, which counter-posts the
-- year-end closing journal through the Accounting Kernel. Closing and reopening
-- move revenue and expense balances to equity and touch no tax whatsoever, so
-- the non-tax partition grows by one and the tax census above is unchanged.
SELECT is(
  (SELECT count(*)::int FROM v_gl_writer)
    - (SELECT count(*)::int FROM v_tax_writer),
  35, 'the remaining GL writers are provably not tax-aware (census partition complete)'); -- 2

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (SELECT proname FROM v_tax_writer)
    GROUP BY p.proname HAVING count(*) > 1),
  NULL, 'no censused tax-aware posting writer is overloaded (unambiguous resolution)'); -- 3

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The Posting Engine determines no tax policy
--
-- Three independent structural proofs: no writer reads a VAT rate source, no
-- writer uses any rate in arithmetic, and the schema-wide census of tax
-- arithmetic lands entirely outside the posting layer save for the one
-- documented co-located writer.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM v_tax_writer
    WHERE prosrc ~ '\mvat_codes\M' OR prosrc ~ '\mtax_codes\M'),
  0, 'no posting writer reads the VAT rate source (vat_codes/tax_codes) at all');  -- 4

SELECT is(
  (SELECT count(*)::int FROM v_tax_writer
    WHERE prosrc ~ 'rate\s*[*/]' OR prosrc ~ '[*/]\s*[A-Za-z_.]*rate'),
  0, 'no posting writer uses a tax rate in multiplication or division — no exceptions remain'); -- 5

-- Schema-wide census of tax-rate arithmetic. This is the assertion the whole
-- phase exists for: ONE function in the entire schema turns a rate into a tax
-- amount. Before PAD-001 this list had eleven entries.
SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosrc ~ 'rate\s*/\s*100'$$,
  $$VALUES ('fn_calculate_tax')$$,
  'the schema-wide tax-arithmetic census is exactly one function: the Tax Engine'); -- 6

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosrc ~ 'rate\s*/\s*100'
      AND p.proname IN (SELECT proname FROM v_gl_writer)),
  0, 'no tax calculator writes the GL — calculation and posting are fully separated'); -- 7

-- The eleven duplicated calculators are gone. Every one of them now asks the
-- engine; none of them reads a VAT rate.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.prosrc ~ 'vat_codes' AND p.prosrc ~ 'rate\s*/\s*100'
      AND p.proname <> 'fn_calculate_tax'),
  0, 'no duplicated document-save VAT calculator survives');                       -- 8

SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND p.prosrc ~ '\mfn_calculate_tax\M' AND p.proname <> 'fn_calculate_tax'$$,
  $$VALUES
     ('fn_save_sales_invoice_aud053_core'),
     ('fn_save_vendor_bill_core_20260718'),
     ('fn_save_cash_purchase_core_20260718'),
     ('fn_save_credit_memo'),
     ('fn_save_debit_memo'),
     ('fn_save_vendor_credit'),
     ('fn_save_cash_sale'),
     ('fn_apply_vendor_bill_line_ewt_profile'),
     ('fn_apply_cash_purchase_line_ewt_profile'),
     ('fn_validate_payment_voucher_line_ewt'),
     ('fn_validate_receipt_line_cwt')$$,
  'all eleven former calculators now consume the engine, and they are exactly the eleven'); -- 8a

-- ── Tax ACCOUNT resolution is owned by the certified COA Resolver ─────────────
SELECT is(
  (SELECT count(*)::int FROM v_tax_writer WHERE prosrc ~ 'company_accounting_config'),
  0, 'no tax-aware posting writer reads company_accounting_config for an account'); -- 9

SELECT set_eq(
  $$SELECT DISTINCT m[1] FROM v_tax_writer,
      LATERAL regexp_matches(prosrc, '''(VAT_OUTPUT|VAT_INPUT|EWT_PAYABLE|EWT_WITHHELD)''', 'g') AS m$$,
  $$VALUES ('VAT_OUTPUT'),('VAT_INPUT'),('EWT_PAYABLE'),('EWT_WITHHELD')$$,
  'the tax account keys the posting layer consumes are exactly the four certified COA keys'); -- 10

SELECT is(
  (SELECT count(*)::int FROM v_tax_writer
    WHERE prosrc ~ '''(VAT_OUTPUT|VAT_INPUT|EWT_PAYABLE|EWT_WITHHELD)'''
      AND prosrc !~ 'fn_resolve_posting_account'),
  0, 'every posting writer naming a tax account key resolves it through the certified resolver'); -- 11

-- The ATC-rate readers stamp provenance only: the rate is read and handed
-- straight to the tax-detail row, never multiplied, divided, or compared.
-- fn_save_cash_sale left this list under PAD-001 — it no longer reads the ATC
-- master at all, it asks the engine.
SELECT set_eq(
  $$SELECT proname FROM v_tax_writer WHERE prosrc ~ '\matc_codes\M'$$,
  $$VALUES ('fn_post_vendor_bill'),('fn_post_cash_purchase_source_locked_impl'),
           ('fn_post_payment_voucher'),('fn_post_receipt'),('fn_post_check_voucher')$$,
  'exactly five posting writers read atc_codes, and all five read it for provenance only'); -- 12

SELECT is(
  (SELECT count(*)::int FROM v_tax_writer
    WHERE prosrc ~ '\matc_codes\M'
      AND (prosrc ~ 'rate\s*[*/]' OR prosrc ~ '[*/]\s*[A-Za-z_.]*rate'
        OR prosrc ~ 'rate\s*[<>=]' )),
  0, 'no ATC rate read by a posting writer feeds arithmetic or a policy comparison'); -- 13

-- ── Tax DETAIL persistence and reversal are owned by the Tax Ledger layer ─────
SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND p.prosrc ~ 'INSERT INTO\s+tax_detail_entries'$$,
  $$VALUES ('fn_add_tax_detail'),('fn_rebuild_document_vat_details'),
           ('fn_post_check_voucher'),('fn_post_cash_purchase_source_locked_impl'),
           ('fn_post_credit_memo_vat_lump_impl'),('fn_post_debit_memo_vat_lump_impl'),
           ('fn_post_vendor_credit_vat_lump_impl'),('fn_save_cash_sale')$$,
  'the tax-ledger writer census is exactly the eight censused functions');          -- 14

SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND p.prosrc ~ 'fn_reverse_tax_detail_entries'$$,
  $$VALUES ('fn_void_sales_invoice_aud053_core'),('fn_void_vendor_bill'),
           ('fn_bounce_receipt'),('fn_cancel_payment_voucher'),('fn_cancel_check_voucher')$$,
  'tax-detail reversal has one implementation, consumed by exactly the five correction writers'); -- 15

-- ── The Tax Engine exists, and there is exactly one of it ────────────────────
SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname ~* '(tax_engine|tax_component|compute_tax|calculate_tax|resolve_tax_rate)'$$,
  $$VALUES ('fn_calculate_tax')$$,
  'the live catalog holds exactly one central tax calculator, and it is the Tax Engine'); -- 16

-- ══════════════════════════════════════════════════════════════════════════════
-- Fixture — one VAT + EWT registered company exercising every supported
-- tax-bearing canonical transaction
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f400000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p4-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f400000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000b1', 'corporation', 'P4 Tax Boundary Corp',
        'Professional Services', '396-000-001-00000', 'vat', 'calendar',
        'P St', 'P Bldg', 'Makati', 'Metro Manila', '1200',
        'p4-owner@test.local', 'P Owner', 'President', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, is_active, created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000b1', true, false, false, true, auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000b2', '0f400000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'P St', 'P Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f400000-0000-0000-0000-0000000000f1', '0f400000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '0f400000-0000-0000-0000-0000000000b1', '0f400000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f400000-0000-0000-0000-0000000000a1', '0f400000-0000-0000-0000-0000000000b1', '1010', 'Cash in Bank',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a2', '0f400000-0000-0000-0000-0000000000b1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a3', '0f400000-0000-0000-0000-0000000000b1', '1300', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a4', '0f400000-0000-0000-0000-0000000000b1', '1310', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a5', '0f400000-0000-0000-0000-0000000000b1', '2010', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a6', '0f400000-0000-0000-0000-0000000000b1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a7', '0f400000-0000-0000-0000-0000000000b1', '2110', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a8', '0f400000-0000-0000-0000-0000000000b1', '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('0f400000-0000-0000-0000-0000000000a9', '0f400000-0000-0000-0000-0000000000b1', '5010', 'Professional Fees',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, default_cash_account_id,
        ewt_payable_account_id, ewt_withheld_account_id, created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000b1',
        '0f400000-0000-0000-0000-0000000000a2', '0f400000-0000-0000-0000-0000000000a5',
        '0f400000-0000-0000-0000-0000000000a6', '0f400000-0000-0000-0000-0000000000a3',
        '0f400000-0000-0000-0000-0000000000a1',
        '0f400000-0000-0000-0000-0000000000a7', '0f400000-0000-0000-0000-0000000000a4',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f400000-0000-0000-0000-0000000000b1', '0f400000-0000-0000-0000-0000000000b2',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI','VB','CP','OR','PV','CM','DM-S','VC','CS');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000c1', '0f400000-0000-0000-0000-0000000000b1', 'CUST-P4',
        'P4 Customer Inc', '395-000-001-00000', 'Customer HQ', 'Customer HQ', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000d1', '0f400000-0000-0000-0000-0000000000b1', 'SUPP-P4',
        'P4 Supplier Corp', '394-000-001-00000', 'Supplier HQ', true,
        (SELECT id FROM atc_codes WHERE code = 'WC140'), auth.uid(), auth.uid());

-- A second supplier NOT subject to source withholding, so the payment-time
-- withholding path can be exercised without double-accruing EWT.
INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, created_by, updated_by)
VALUES ('0f400000-0000-0000-0000-0000000000d2', '0f400000-0000-0000-0000-0000000000b1', 'SUPP-P4B',
        'P4 Payment-Withholding Corp', '393-000-001-00000', 'Supplier HQ 2', false,
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ── Sales Invoice, VAT-exclusive: net 10,000 + output VAT 1,200 ──────────────
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id', '0f400000-0000-0000-0000-0000000000b1',
    'branch_id',  '0f400000-0000-0000-0000-0000000000b2',
    'date',       '2026-01-15',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot',    'P4 Customer Inc',
    'customer_tin_snapshot',     '395-000-001-00000',
    'customer_address_snapshot', 'Customer HQ'),
  jsonb_build_array(jsonb_build_object(
    'description','Consulting services','quantity',1,'unit_price',10000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

-- ── Vendor Bill: net 5,000 + input VAT 600, EWT 100 accrued at source ────────
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'supplier_id','0f400000-0000-0000-0000-0000000000d1',
    'supplier_name_snapshot','P4 Supplier Corp',
    'supplier_tin_snapshot', '394-000-001-00000',
    'supplier_invoice_number','SUP-P4-001',
    'bill_date','2026-01-20'),
  jsonb_build_array(jsonb_build_object(
    'description','Contractor services','quantity',1,'unit_price',5000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9',
    'ewt_atc_code_id',(SELECT id FROM atc_codes WHERE code='WC140'),
    'ewt_tax_base',5000,'ewt_amount',100,
    'ewt_income_nature','Contractor services')));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

-- ── Cash Purchase: net 2,000 + input VAT 240 ─────────────────────────────────
INSERT INTO t_ctx
SELECT 'cp', fn_save_cash_purchase(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'transaction_date','2026-02-05',
    'supplier_id','0f400000-0000-0000-0000-0000000000d1',
    'supplier_name_snapshot','P4 Supplier Corp',
    'supplier_tin_snapshot','394-000-001-00000'),
  jsonb_build_array(jsonb_build_object(
    'description','Office supplies','quantity',1,'unit_price',2000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9')));
SELECT fn_post_cash_purchase((SELECT id FROM t_ctx WHERE key='cp'));

-- ── Second Vendor Bill, no source EWT: net 5,000 + input VAT 600 ─────────────
-- EWT on this one is withheld at PAYMENT time instead, so both governed
-- withholding-recognition points are exercised.
INSERT INTO t_ctx
SELECT 'vb2', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'supplier_id','0f400000-0000-0000-0000-0000000000d2',
    'supplier_name_snapshot','P4 Payment-Withholding Corp',
    'supplier_tin_snapshot', '393-000-001-00000',
    'supplier_invoice_number','SUP-P4-002',
    'bill_date','2026-01-25'),
  jsonb_build_array(jsonb_build_object(
    'description','Advisory services','quantity',1,'unit_price',5000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9')));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb2'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb2'));

-- ── Payment Voucher settling the second bill, withholding 100 EWT ────────────
INSERT INTO t_ctx
SELECT 'pv', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'supplier_id','0f400000-0000-0000-0000-0000000000d2',
    'supplier_name_snapshot','P4 Payment-Withholding Corp',
    'voucher_date','2026-02-10',
    'total_amount',5500,'total_ewt',100),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',(SELECT id FROM t_ctx WHERE key='vb2'),
    'payment_amount',5500,'ewt_amount',100,
    'atc_code_id',(SELECT id FROM atc_codes WHERE code='WC140'),
    'ewt_tax_base',5000,
    'ewt_income_nature','Contractor services')));
SELECT fn_post_payment_voucher((SELECT id FROM t_ctx WHERE key='pv'));

-- ── Official Receipt collecting the invoice, customer withholds 224 CWT ──────
INSERT INTO t_ctx
SELECT 'or', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc',
    'customer_tin_snapshot','395-000-001-00000',
    'receipt_date','2026-02-15',
    'payment_mode_id',(SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',10976,'total_cwt',224),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',(SELECT id FROM t_ctx WHERE key='si'),
    'payment_amount',10976,'cwt_amount',224,
    'atc_code_id',(SELECT id FROM atc_codes WHERE code='WC140'))));
SELECT fn_post_receipt((SELECT id FROM t_ctx WHERE key='or'));

-- ── Credit Memo: sales return net 1,000 + output VAT 120 reversed ────────────
INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc',
    'customer_tin_snapshot','395-000-001-00000',
    'cm_date','2026-02-20',
    'reason_code_id',(SELECT id FROM ref_reason_codes
                       WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1)),
  jsonb_build_array(jsonb_build_object(
    'description','Returned services','quantity',1,'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')),
  'draft');
SELECT fn_post_credit_memo((SELECT id FROM t_ctx WHERE key='cm'));

-- ── Vendor Credit: purchase return net 500 + input VAT 60 reversed ───────────
INSERT INTO t_ctx
SELECT 'vc', fn_save_vendor_credit(NULL,
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'supplier_id','0f400000-0000-0000-0000-0000000000d1',
    'supplier_name_snapshot','P4 Supplier Corp',
    'supplier_tin_snapshot','394-000-001-00000',
    'credit_date','2026-02-25'),
  jsonb_build_array(jsonb_build_object(
    'description','Returned supplies','quantity',1,'unit_price',500,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9')));
SELECT fn_post_vendor_credit((SELECT id FROM t_ctx WHERE key='vc'));

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Stored tax fact == posted GL tax line == tax-ledger entry
--
-- The Posting Engine consumes; it does not author. For every supported
-- canonical transaction the three values are compared as one triple.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $q$SELECT si.total_vat_amount,
            (SELECT jel.credit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = si.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a6'),
            (SELECT sum(t.tax_amount) FROM tax_detail_entries t
              WHERE t.source_doc_type='SI' AND t.source_doc_id = si.id
                AND t.tax_kind='output_vat')
       FROM sales_invoices si WHERE si.id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  $$VALUES (1200.00::numeric, 1200.00::numeric, 1200.00::numeric)$$,
  'Sales Invoice: stored output VAT == posted GL credit == tax-ledger amount');    -- 17

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices
                          WHERE id = (SELECT id FROM t_ctx WHERE key='si'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '1200'::text, 11200.00::numeric, 0.00::numeric),
           (2, '4010'::text, 0.00::numeric, 10000.00::numeric),
           (3, '2100'::text, 0.00::numeric, 1200.00::numeric)$$,
  'Sales Invoice journal: line order, tax account, and amounts are the certified output'); -- 18

SELECT results_eq(
  $q$SELECT vb.total_input_vat_amount,
            (SELECT jel.debit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = vb.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a3'),
            (SELECT sum(t.tax_amount) FROM tax_detail_entries t
              WHERE t.source_doc_type='VB' AND t.source_doc_id = vb.id
                AND t.tax_kind='input_vat')
       FROM vendor_bills vb WHERE vb.id = (SELECT id FROM t_ctx WHERE key='vb')$q$,
  $$VALUES (600.00::numeric, 600.00::numeric, 600.00::numeric)$$,
  'Vendor Bill: stored input VAT == posted GL debit == tax-ledger amount');        -- 19

-- EWT accrued at source: amount, ATC, rate, base, and income nature all travel
-- from the stored document line into the ledger. The rate is provenance the
-- writer copied, never a rate it selected.
SELECT results_eq(
  $q$SELECT (SELECT sum(vbl.ewt_amount) FROM vendor_bill_lines vbl
              WHERE vbl.vendor_bill_id = (SELECT id FROM t_ctx WHERE key='vb')),
            (SELECT jel.credit_amount FROM journal_entry_lines jel
              JOIN vendor_bills vb ON vb.id = (SELECT id FROM t_ctx WHERE key='vb')
              WHERE jel.je_id = vb.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a7'),
            t.tax_amount, t.tax_base, t.tax_rate, t.income_nature,
            (t.atc_code_id = (SELECT id FROM atc_codes WHERE code='WC140'))
       FROM tax_detail_entries t
      WHERE t.source_doc_type='VB' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='vb')
        AND t.tax_kind='ewt_payable'$q$,
  $$VALUES (100.00::numeric, 100.00::numeric, 100.00::numeric, 5000.00::numeric,
            2.00::numeric, 'Contractor services'::text, true)$$,
  'Vendor Bill EWT: stored amount == GL credit == ledger, with ATC/rate/base provenance'); -- 20

SELECT results_eq(
  $q$SELECT cp.total_input_vat_amount,
            (SELECT jel.debit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = cp.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a3'),
            (SELECT sum(t.tax_amount) FROM tax_detail_entries t
              WHERE t.source_doc_type='CP' AND t.source_doc_id = cp.id
                AND t.tax_kind='input_vat')
       FROM cash_purchases cp WHERE cp.id = (SELECT id FROM t_ctx WHERE key='cp')$q$,
  $$VALUES (240.00::numeric, 240.00::numeric, 240.00::numeric)$$,
  'Cash Purchase: stored input VAT == posted GL debit == tax-ledger amount');      -- 21

SELECT results_eq(
  $q$SELECT (SELECT sum(pvl.ewt_amount) FROM payment_voucher_lines pvl
              WHERE pvl.payment_voucher_id = (SELECT id FROM t_ctx WHERE key='pv')),
            (SELECT jel.credit_amount FROM journal_entry_lines jel
              JOIN payment_vouchers pv ON pv.id = (SELECT id FROM t_ctx WHERE key='pv')
              WHERE jel.je_id = pv.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a7'),
            t.tax_amount, t.tax_base, t.tax_rate
       FROM tax_detail_entries t
      WHERE t.source_doc_type='PV' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='pv')
        AND t.tax_kind='ewt_payable'$q$,
  $$VALUES (100.00::numeric, 100.00::numeric, 100.00::numeric, 5000.00::numeric, 2.00::numeric)$$,
  'Payment Voucher EWT: stored amount == GL credit == ledger, with base and rate provenance'); -- 22

SELECT results_eq(
  $q$SELECT (SELECT sum(rl.cwt_amount) FROM receipt_lines rl
              WHERE rl.receipt_id = (SELECT id FROM t_ctx WHERE key='or')),
            (SELECT jel.debit_amount FROM journal_entry_lines jel
              JOIN receipts r ON r.id = (SELECT id FROM t_ctx WHERE key='or')
              WHERE jel.je_id = r.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a4'),
            t.tax_amount, t.tax_rate
       FROM tax_detail_entries t
      WHERE t.source_doc_type='OR' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='or')
        AND t.tax_kind='cwt_receivable'$q$,
  $$VALUES (224.00::numeric, 224.00::numeric, 224.00::numeric, 2.00::numeric)$$,
  'Official Receipt CWT: stored amount == posted GL debit == tax-ledger amount');  -- 23

SELECT results_eq(
  $q$SELECT cm.total_vat_amount,
            (SELECT jel.debit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = cm.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a6'),
            (SELECT sum(t.tax_amount) FROM tax_detail_entries t
              WHERE t.source_doc_type='CM' AND t.source_doc_id = cm.id
                AND t.tax_kind='output_vat')
       FROM credit_memos cm WHERE cm.id = (SELECT id FROM t_ctx WHERE key='cm')$q$,
  $$VALUES (120.00::numeric, 120.00::numeric, -120.00::numeric)$$,
  'Credit Memo: stored VAT == posted GL debit; the ledger carries the signed reversal'); -- 24

SELECT results_eq(
  $q$SELECT vc.total_input_vat_amount,
            (SELECT jel.credit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = vc.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a3'),
            (SELECT sum(t.tax_amount) FROM tax_detail_entries t
              WHERE t.source_doc_type='VC' AND t.source_doc_id = vc.id
                AND t.tax_kind='input_vat')
       FROM vendor_credits vc WHERE vc.id = (SELECT id FROM t_ctx WHERE key='vc')$q$,
  $$VALUES (60.00::numeric, 60.00::numeric, -60.00::numeric)$$,
  'Vendor Credit: stored input VAT == posted GL credit; the ledger carries the signed reversal'); -- 25

-- ── The co-located writer: its POSTING half still consumes stored facts ──────
-- fn_save_cash_sale computes VAT, persists it to the document, and only then
-- posts. The posted journal and tax ledger must equal the persisted document —
-- which is exactly what a future Tax Engine migration has to preserve.
CREATE TEMP TABLE t_cs AS
SELECT fn_save_cash_sale(
  jsonb_build_object(
    'company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id', '0f400000-0000-0000-0000-0000000000b2',
    'date','2026-03-05',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc',
    'customer_tin_snapshot','395-000-001-00000',
    'bank_account_id','0f400000-0000-0000-0000-0000000000a1',
    'cwt_atc_id',(SELECT id FROM atc_codes WHERE code='WC140')),
  jsonb_build_array(jsonb_build_object(
    'description','Counter sale','quantity',1,'unit_price',3000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')),
  60) AS r;
INSERT INTO t_ctx SELECT 'cs',    (r->>'si_id')::uuid      FROM t_cs;
INSERT INTO t_ctx SELECT 'cs_or', (r->>'receipt_id')::uuid FROM t_cs;

SELECT results_eq(
  $q$SELECT si.total_vat_amount,
            (SELECT jel.credit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = si.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a6'),
            (SELECT sum(t.tax_amount) FROM tax_detail_entries t
              WHERE t.source_doc_type='SI' AND t.source_doc_id = si.id
                AND t.tax_kind='output_vat')
       FROM sales_invoices si WHERE si.id = (SELECT id FROM t_ctx WHERE key='cs')$q$,
  $$VALUES (360.00::numeric, 360.00::numeric, 360.00::numeric)$$,
  'Cash Sale: the posting half consumes the VAT its save half persisted (360.00 everywhere)'); -- 26

-- Its withholding is supplied by the caller and validated against the ATC rate;
-- the writer records it, it does not author it.
SELECT results_eq(
  $q$SELECT r.total_cwt,
            (SELECT jel.debit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = r.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a4'),
            (SELECT t.tax_amount FROM tax_detail_entries t
              WHERE t.source_doc_type='OR' AND t.source_doc_id = r.id
                AND t.tax_kind='cwt_receivable'),
            (SELECT t.tax_base FROM tax_detail_entries t
              WHERE t.source_doc_type='OR' AND t.source_doc_id = r.id
                AND t.tax_kind='cwt_receivable')
       FROM receipts r WHERE r.id = (SELECT id FROM t_ctx WHERE key='cs_or')$q$,
  $$VALUES (60.00::numeric, 60.00::numeric, 60.00::numeric, 3000.00::numeric)$$,
  'Cash Sale CWT: caller-supplied withholding is recorded identically in GL and ledger'); -- 27

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — GL-to-Tax-Ledger reconciliation is exactly zero-variance
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
       FROM fn_vat_gl_reconciliation('0f400000-0000-0000-0000-0000000000b1',
                                     '2026-01-01','2026-12-31')$q$,
  $$VALUES ('input_vat'::text,  1380.00::numeric(15,2), 1380.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('output_vat'::text, 1440.00::numeric(15,2), 1440.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'VAT ledger reconciles to the VAT GL accounts with exactly zero variance');      -- 28

SELECT results_eq(
  $q$SELECT tax_kind, ledger_tax_amount, gl_amount, variance, is_reconciled
       FROM fn_wht_gl_reconciliation('0f400000-0000-0000-0000-0000000000b1',
                                     '2026-01-01','2026-12-31')$q$,
  $$VALUES ('cwt_receivable'::text, 284.00::numeric(15,2), 284.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('ewt_payable'::text,    200.00::numeric(15,2), 200.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'withholding ledger reconciles to the withholding GL accounts with exactly zero variance'); -- 29

SELECT is(
  (SELECT count(*)::int FROM (
     SELECT variance FROM fn_vat_gl_reconciliation('0f400000-0000-0000-0000-0000000000b1','2026-01-01','2026-12-31')
     UNION ALL
     SELECT variance FROM fn_wht_gl_reconciliation('0f400000-0000-0000-0000-0000000000b1','2026-01-01','2026-12-31')
   ) v WHERE v.variance <> 0),
  0, 'no tax kind carries any variance at all — the tie-out is exact, not tolerance-based'); -- 30

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — Reversal preserves original provenance and never recomputes
--
-- Non-vacuity is engineered: the ATC rate in force on the reversal date is
-- deliberately made DIFFERENT from the rate the original document carried,
-- through the governed deprecate-and-succeed workflow. A reversal that
-- recomputed at the current rate would produce 250.00; the certified reversal
-- must reproduce the original 100.00 at the original 2.00 rate.
-- ══════════════════════════════════════════════════════════════════════════════
UPDATE atc_codes SET effective_to = '2026-02-28', updated_by = auth.uid(), updated_at = NOW()
WHERE code = 'WC140' AND effective_to IS NULL;

INSERT INTO atc_codes (id, code, description, tax_category, rate, effective_from,
                       is_active, supersedes_atc_code_id, created_by, updated_by)
SELECT '0f400000-0000-0000-0000-0000000000e1', a.code, a.description, a.tax_category,
       5.00, '2026-03-01', true, a.id, auth.uid(), auth.uid()
FROM atc_codes a WHERE a.code = 'WC140' AND a.effective_to = '2026-02-28';

SELECT is(
  (SELECT rate FROM atc_codes
    WHERE code='WC140' AND is_active
      AND CURRENT_DATE BETWEEN effective_from AND COALESCE(effective_to, DATE 'infinity')),
  5.00::numeric, 'the ATC version in force on the reversal date carries a DIFFERENT rate (non-vacuous)'); -- 31

SELECT fn_cancel_payment_voucher((SELECT id FROM t_ctx WHERE key='pv'), 'P4 provenance test');

SELECT results_eq(
  $q$SELECT t.is_reversal, t.tax_amount, t.tax_base, t.tax_rate,
            (t.atc_code_id = (SELECT id FROM atc_codes WHERE code='WC140' AND rate=2.00)),
            t.income_nature, (t.reverses_tax_detail_id IS NOT NULL)
       FROM tax_detail_entries t
      WHERE t.source_doc_type='PV' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='pv')
        AND t.reverses_tax_detail_id IS NOT NULL$q$,
  $$VALUES (true, -100.00::numeric, -5000.00::numeric, 2.00::numeric, true,
            'Contractor services'::text, true)$$,
  'the reversal copies the ORIGINAL rate, ATC version, base, and income nature'); -- 32

SELECT isnt(
  (SELECT t.tax_rate FROM tax_detail_entries t
    WHERE t.source_doc_type='PV' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='pv')
      AND t.reverses_tax_detail_id IS NOT NULL),
  (SELECT rate FROM atc_codes WHERE code='WC140' AND rate=5.00),
  'historical reversal did NOT adopt the current 5.00 rate');                     -- 33

SELECT isnt(
  (SELECT abs(t.tax_amount) FROM tax_detail_entries t
    WHERE t.source_doc_type='PV' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='pv')
      AND t.reverses_tax_detail_id IS NOT NULL),
  ROUND(5000.00 * 5.00 / 100, 2),
  'a current-rate recomputation would yield 250.00; the reversal reproduces the original 100.00'); -- 34

SELECT results_eq(
  $q$SELECT o.is_reversal, o.tax_amount, o.tax_base, o.tax_rate
       FROM tax_detail_entries o
      WHERE o.source_doc_type='PV' AND o.source_doc_id=(SELECT id FROM t_ctx WHERE key='pv')
        AND o.reverses_tax_detail_id IS NULL$q$,
  $$VALUES (false, 100.00::numeric, 5000.00::numeric, 2.00::numeric)$$,
  'the original ledger row is preserved untouched — reversal adds, never mutates'); -- 35

SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries t
    WHERE t.source_doc_type='PV' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='pv')),
  2, 'exactly one counter-row per original — the reversal is single and linked');  -- 36

-- Voiding an invoice reverses its VAT with the same provenance discipline, and
-- the reversal journal is equal and opposite on the tax account. A dedicated
-- invoice is used so the reconciliation proven in Section D stands undisturbed.
INSERT INTO t_ctx
SELECT 'si_void', fn_save_sales_invoice(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2','date','2026-06-15',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc','customer_tin_snapshot','395-000-001-00000',
    'customer_address_snapshot','Customer HQ'),
  jsonb_build_array(jsonb_build_object('description','Void probe','quantity',1,
    'unit_price',2000,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si_void'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si_void'));

CREATE TEMP TABLE t_void AS
SELECT journal_entry_id AS original_je FROM sales_invoices
WHERE id = (SELECT id FROM t_ctx WHERE key='si_void');

SELECT fn_void_sales_invoice((SELECT id FROM t_ctx WHERE key='si_void'), NULL, 'P4 void test');

SELECT results_eq(
  $q$SELECT t.is_reversal, t.tax_amount, t.tax_base,
            (t.vat_code_id = (SELECT id FROM vat_codes WHERE vat_code='VAT-12')),
            (o.tax_amount + t.tax_amount)
       FROM tax_detail_entries t
       JOIN tax_detail_entries o ON o.id = t.reverses_tax_detail_id
      WHERE t.source_doc_type='SI' AND t.source_doc_id=(SELECT id FROM t_ctx WHERE key='si_void')$q$,
  $$VALUES (true, -240.00::numeric, -2000.00::numeric, true, 0.00::numeric)$$,
  'voided Sales Invoice: the counter-row copies the VAT code and exactly negates the original'); -- 37

SELECT is(
  (SELECT jel.debit_amount FROM journal_entry_lines jel
    WHERE jel.je_id = (SELECT je.reversed_by_je_id FROM journal_entries je
                        WHERE je.id = (SELECT original_je FROM t_void))
      AND jel.account_id = '0f400000-0000-0000-0000-0000000000a6'),
  240.00::numeric, 'the reversal journal debits Output VAT exactly what the original credited'); -- 38

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — Rounding consistency across the reachable document calculators
--
-- Structural: rounding now has exactly ONE implementation, so consistency is
-- guaranteed by construction rather than by five copies happening to agree.
-- Behavioural: the same 100.05 base at 12% must still round to 12.01 in every
-- calculator that a document can reach. These figures are UNCHANGED from
-- before PAD-001, which is the point.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.prosrc ~ 'vat_codes' AND p.prosrc ~ 'rate\s*/\s*100'
      AND p.prosrc !~ 'ROUND\([^;]*rate\s*/\s*100,\s*2\)'),
  0, 'the one VAT calculator rounds to 2 decimals at the line');                  -- 39

-- Each calculator is invoked exactly once; the saved document id is captured
-- first, then the persisted VAT is read back from the document it wrote.
CREATE TEMP TABLE t_round_id AS
SELECT 'sales_invoice'::text AS calculator, fn_save_sales_invoice(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2','date','2026-04-01',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc','customer_tin_snapshot','395-000-001-00000',
    'customer_address_snapshot','Customer HQ'),
  jsonb_build_array(jsonb_build_object('description','Rounding probe','quantity',1,
    'unit_price',100.05,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8'))) AS id
UNION ALL
SELECT 'vendor_bill', fn_save_vendor_bill(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2',
    'supplier_id','0f400000-0000-0000-0000-0000000000d2',
    'supplier_name_snapshot','P4 Payment-Withholding Corp','supplier_tin_snapshot','393-000-001-00000',
    'supplier_invoice_number','SUP-P4-ROUND','bill_date','2026-04-01'),
  jsonb_build_array(jsonb_build_object('description','Rounding probe','quantity',1,
    'unit_price',100.05,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9')))
UNION ALL
SELECT 'cash_purchase', fn_save_cash_purchase(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2','transaction_date','2026-04-01',
    'supplier_id','0f400000-0000-0000-0000-0000000000d2',
    'supplier_name_snapshot','P4 Payment-Withholding Corp','supplier_tin_snapshot','393-000-001-00000'),
  jsonb_build_array(jsonb_build_object('description','Rounding probe','quantity',1,
    'unit_price',100.05,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9')))
UNION ALL
SELECT 'credit_memo', fn_save_credit_memo(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc','customer_tin_snapshot','395-000-001-00000',
    'cm_date','2026-04-01',
    'reason_code_id',(SELECT id FROM ref_reason_codes
                       WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1)),
  jsonb_build_array(jsonb_build_object('description','Rounding probe','quantity',1,
    'unit_price',100.05,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')),
  'draft')
UNION ALL
SELECT 'vendor_credit', fn_save_vendor_credit(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2',
    'supplier_id','0f400000-0000-0000-0000-0000000000d2',
    'supplier_name_snapshot','P4 Payment-Withholding Corp','supplier_tin_snapshot','393-000-001-00000',
    'credit_date','2026-04-01'),
  jsonb_build_array(jsonb_build_object('description','Rounding probe','quantity',1,
    'unit_price',100.05,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f400000-0000-0000-0000-0000000000a9')));

CREATE TEMP TABLE t_round AS
SELECT r.calculator,
       CASE r.calculator
         WHEN 'sales_invoice' THEN (SELECT si.total_vat_amount FROM sales_invoices si WHERE si.id = r.id)
         WHEN 'vendor_bill'   THEN (SELECT vb.total_input_vat_amount FROM vendor_bills vb WHERE vb.id = r.id)
         WHEN 'cash_purchase' THEN (SELECT cp.total_input_vat_amount FROM cash_purchases cp WHERE cp.id = r.id)
         WHEN 'credit_memo'   THEN (SELECT cm.total_vat_amount FROM credit_memos cm WHERE cm.id = r.id)
         WHEN 'vendor_credit' THEN (SELECT vc.total_input_vat_amount FROM vendor_credits vc WHERE vc.id = r.id)
       END AS vat
FROM t_round_id r;

SELECT results_eq(
  $q$SELECT calculator, vat FROM t_round ORDER BY calculator$q$,
  $$VALUES ('cash_purchase'::text, 12.01::numeric),
           ('credit_memo'::text,   12.01::numeric),
           ('sales_invoice'::text, 12.01::numeric),
           ('vendor_bill'::text,   12.01::numeric),
           ('vendor_credit'::text, 12.01::numeric)$$,
  'the same 100.05 base at 12% rounds to 12.01 in every reachable document calculator'); -- 40

SELECT is(
  (SELECT count(DISTINCT vat)::int FROM t_round),
  1, 'no calculator disagrees with any other on the rounded result');              -- 41

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — VAT-exclusive and VAT-inclusive behaviour is unchanged
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'si_inc', fn_save_sales_invoice(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2','date','2026-05-04',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc','customer_tin_snapshot','395-000-001-00000',
    'customer_address_snapshot','Customer HQ','vat_price_basis','inclusive'),
  jsonb_build_array(jsonb_build_object('description','VAT-inclusive services','quantity',1,
    'unit_price',11200,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si_inc'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si_inc'));

SELECT results_eq(
  $q$SELECT si.vat_price_basis, si.total_taxable_amount, si.total_vat_amount, si.total_amount,
            (SELECT jel.credit_amount FROM journal_entry_lines jel
              WHERE jel.je_id = si.journal_entry_id
                AND jel.account_id = '0f400000-0000-0000-0000-0000000000a6')
       FROM sales_invoices si WHERE si.id = (SELECT id FROM t_ctx WHERE key='si_inc')$q$,
  $$VALUES ('inclusive'::text, 10000.00::numeric, 1200.00::numeric, 11200.00::numeric, 1200.00::numeric)$$,
  'VAT-inclusive: 11,200 gross backs out to 10,000 net + 1,200 VAT, posted unchanged'); -- 42

SELECT results_eq(
  $q$SELECT si.vat_price_basis, si.total_taxable_amount, si.total_vat_amount, si.total_amount
       FROM sales_invoices si WHERE si.id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  $$VALUES ('exclusive'::text, 10000.00::numeric, 1200.00::numeric, 11200.00::numeric)$$,
  'VAT-exclusive: 10,000 net grosses up to 11,200, posted unchanged');             -- 43

-- The limitation this line used to record is closed. VAT-inclusive treatment
-- lived in ONE of seven calculators, so six document types could not price
-- tax-inclusively at all. It now lives in the engine, which every document
-- type calls, so the capability is available product-wide from one place.
-- The census no longer conjoins `vat_codes`: the engine reads the VAT master
-- through fn_resolve_vat_code, which test 118 pins as the single resolver.
SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.prokind='f'
       AND p.prosrc ~ 'rate\s*/\s*100'
       AND p.prosrc ~* 'inclusive'$$,
  $$VALUES ('fn_calculate_tax')$$,
  'VAT-inclusive treatment lives in the engine, so every document type reaches it'); -- 44

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION H — Missing or invalid stored tax data still fails closed
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'si_bad', fn_save_sales_invoice(NULL,
  jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
    'branch_id','0f400000-0000-0000-0000-0000000000b2','date','2026-06-01',
    'customer_id','0f400000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P4 Customer Inc','customer_tin_snapshot','395-000-001-00000',
    'customer_address_snapshot','Customer HQ'),
  jsonb_build_array(jsonb_build_object('description','Tamper probe','quantity',1,
    'unit_price',1000,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si_bad'));

UPDATE sales_invoices SET total_vat_amount = 999.99, updated_by = auth.uid(), updated_at = NOW()
WHERE id = (SELECT id FROM t_ctx WHERE key='si_bad');

SELECT throws_like(
  $$SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si_bad'))$$,
  '%header VAT%does not match line VAT%',
  'stored header VAT that disagrees with the stored line VAT is rejected — fail-closed'); -- 45

SELECT is(
  (SELECT count(*)::int FROM journal_entries
    WHERE reference_doc_type='SI' AND reference_doc_id=(SELECT id FROM t_ctx WHERE key='si_bad')),
  0, 'the rejected posting left no partial journal behind');                       -- 46

-- Dated inside the WC140@2.00 effective window (Section E capped it at
-- 2026-02-28). Before PAD-001 this probe was dated 2026-06-02 and still
-- resolved a rate, because fn_save_cash_sale read the ATC master with no
-- effective-date filter. It no longer does, so the probe now has to use a date
-- on which the rate it names is actually in force — which is the fix, not a
-- weakening: assertion 47a proves the out-of-window case is now refused.
SELECT throws_like(
  $$SELECT fn_save_cash_sale(
      jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
        'branch_id','0f400000-0000-0000-0000-0000000000b2','date','2026-02-02',
        'customer_id','0f400000-0000-0000-0000-0000000000c1',
        'customer_name_snapshot','P4 Customer Inc',
        'customer_tin_snapshot','395-000-001-00000',
        'bank_account_id','0f400000-0000-0000-0000-0000000000a1',
        'cwt_atc_id',(SELECT id FROM atc_codes WHERE code='WC140' AND rate=2.00)),
      jsonb_build_array(jsonb_build_object('description','Bad CWT','quantity',1,
        'unit_price',1000,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
        'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')),
      777)$$,
  '%does not match ATC rate%',
  'withholding that does not match the governed ATC rate is rejected — fail-closed'); -- 47

-- The deliberate behaviour change PAD-001 shipped. A cash sale dated after
-- WC140@2.00 was superseded may no longer withhold at that superseded version.
-- Every other withholding path in PXL already refused this; cash sale did not.
SELECT throws_like(
  $$SELECT fn_save_cash_sale(
      jsonb_build_object('company_id','0f400000-0000-0000-0000-0000000000b1',
        'branch_id','0f400000-0000-0000-0000-0000000000b2','date','2026-06-02',
        'customer_id','0f400000-0000-0000-0000-0000000000c1',
        'customer_name_snapshot','P4 Customer Inc',
        'customer_tin_snapshot','395-000-001-00000',
        'bank_account_id','0f400000-0000-0000-0000-0000000000a1',
        'cwt_atc_id',(SELECT id FROM atc_codes WHERE code='WC140' AND rate=2.00)),
      jsonb_build_array(jsonb_build_object('description','Superseded ATC','quantity',1,
        'unit_price',1000,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
        'revenue_account_id','0f400000-0000-0000-0000-0000000000a8')),
      20)$$,
  '%missing, inactive, or has no positive rate%',
  'a cash sale can no longer withhold at an ATC version superseded before its date'); -- 47a

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION I — The Tax Component contract exists, and the posting layer is
-- deliberately NOT one of its consumers
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='public' AND t.typname = 'tax_component' AND t.typtype = 'c'),
  1, 'the tax_component composite contract exists exactly once');                  -- 48

SELECT is(
  (SELECT count(*)::int FROM v_tax_writer
    WHERE prosrc ~* 'tax_component'),
  0, 'no posting writer consumes a tax component — posting still consumes stored facts only'); -- 49

SELECT * FROM finish();
ROLLBACK;
