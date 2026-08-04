-- ══════════════════════════════════════════════════════════════════════════════
-- 125 — BIR filing artifacts on one governed path (Delivery Plan Phase 5.8)
--
-- WHAT THIS GUARDS
--   The path a filed return must travel, and the fact that there is only one of
--   it:
--
--       posted transactions → Tax Engine → tax ledger → working paper → artifact
--
--   Nothing has ever been filed from PXL, and what existed to file with was
--   three near-identical reconciliation functions in SQL plus three more
--   computations in JavaScript — the 2550Q, the SLSP and the SAWT were each
--   summed in a browser. This file proves that every registered artifact is
--   produced by the same three functions from the same posted ledger, on a
--   company it provisions itself through the current production RPCs.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   That anything has been filed with the Bureau. It also does not claim the
--   forms not registered in this increment (1601FQ, 2550M, QAP, 1604-E and the
--   Books of Accounts exports), which are seed rows plus a screen and are
--   recorded in the Product Backlog.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(42);

-- ── Fixture: a VAT-registered trading company that both withholds and is withheld from
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12500000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'filing-artifacts@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12500000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12500000-0000-0000-0000-0000000000c1', 'corporation', 'Filing Ready Trading Corp',
        'Wholesale and services', '355-125-001-00000', 'vat', 'calendar',
        '125 Filing St', '', 'Makati', 'Metro Manila', '1200',
        'filing-artifacts@test.local', 'Fiona Reyes', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12500000-0000-0000-0000-0000000000d1', '12500000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', '125 Filing St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12500000-0000-0000-0000-0000000000f1', '12500000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12500000-0000-0000-0000-0000000000c1', '12500000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12500000-0000-0000-0000-00000000a001', '12500000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a002', '12500000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a003', '12500000-0000-0000-0000-0000000000c1', '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a004', '12500000-0000-0000-0000-0000000000c1', '1400', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a005', '12500000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a006', '12500000-0000-0000-0000-0000000000c1', '2000', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a007', '12500000-0000-0000-0000-0000000000c1', '2210', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a008', '12500000-0000-0000-0000-0000000000c1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-00000000a009', '12500000-0000-0000-0000-0000000000c1', '6100', 'Rent Expense',        'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('12500000-0000-0000-0000-0000000000c1',
        '12500000-0000-0000-0000-00000000a002', '12500000-0000-0000-0000-00000000a006',
        '12500000-0000-0000-0000-00000000a005', '12500000-0000-0000-0000-00000000a004',
        '12500000-0000-0000-0000-00000000a003', '12500000-0000-0000-0000-00000000a007',
        '12500000-0000-0000-0000-00000000a001', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, vat_registered, vat_filing_frequency,
                                 percentage_tax_registered, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, files_0619e,
                                 created_by, updated_by)
VALUES ('12500000-0000-0000-0000-0000000000c1', true, 'quarterly', false, true, true,
        false, true, auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12500000-0000-0000-0000-0000000000c1', '12500000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-125-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS', 'SI', 'VB');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address,
                       is_subject_to_cwt, default_cwt_atc_code_id, created_by, updated_by)
VALUES
  ('12500000-0000-0000-0000-0000000000e1', '12500000-0000-0000-0000-0000000000c1',
   'CUST-A', 'Ordinary Buyer Inc', '111-222-333-125', 'Pasig', 'Pasig',
   false, NULL, auth.uid(), auth.uid()),
  ('12500000-0000-0000-0000-0000000000e2', '12500000-0000-0000-0000-0000000000c1',
   'CUST-B', 'Top Withholding Agent Corp', '444-555-666-125', 'Taguig', 'Taguig',
   true, (SELECT id FROM atc_codes WHERE code = 'WC158' AND is_active), auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES ('12500000-0000-0000-0000-0000000000e3', '12500000-0000-0000-0000-0000000000c1',
        'SUPP-A', 'Landlord Services Inc', '777-888-999-125', 'Makati',
        true, (SELECT id FROM atc_codes WHERE code = 'WC160' AND is_active),
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Registering a form is configuration, not code
-- ══════════════════════════════════════════════════════════════════════════════
-- QAP was registered by Backlog 8e as a seed row, which is the claim this
-- registry makes about itself: a new form costs configuration, not code.
SELECT set_eq(
  $$SELECT form_code::text FROM ref_filing_artifact WHERE is_active$$,
  $$VALUES ('2550Q'),('2551Q'),('1601EQ'),('SLSP'),('SAWT'),('QAP')$$,
  'the filing registry names exactly the artifacts registered so far');           -- 1

SELECT results_eq(
  $$SELECT tax_kind::text, net_sign::int FROM ref_filing_artifact_kind
     WHERE form_code = '2550Q' ORDER BY tax_kind$$,
  $$VALUES ('input_vat'::text, -1), ('output_vat'::text, 1)$$,
  'a return states which way each tax kind moves its net; input VAT is a credit'); -- 2

SELECT is(
  (SELECT count(*)::integer FROM ref_tax_ledger_control
    WHERE tax_kind = 'ewt_payable'
      AND 'WHTREM' = ANY(excluded_reference_types)
      AND included_je_statuses = ARRAY['posted']),
  1,
  'the WHTREM exclusion and the journal statuses are configuration, not a second function'); -- 3

SELECT throws_like(
  $$SELECT * FROM fn_filing_working_paper('12500000-0000-0000-0000-0000000000c1',
      'NOT-A-FORM', 2026, 1)$$,
  '%Unknown or inactive filing artifact%',
  'an unregistered form is refused rather than guessed at');                      -- 4

SELECT results_eq(
  $$SELECT date_from, date_to FROM fn_filing_period_bounds('quarterly', 2026, 2)$$,
  $$VALUES ('2026-04-01'::date, '2026-06-30'::date)$$,
  'one function turns a filing period into dates');                               -- 5

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The documents. Everything below is read from these postings.
--   SI  : 100,000 net + 12,000 output VAT to an ordinary buyer
--   CS  :  50,000 net +  6,000 output VAT to a withholding agent, CWT 500 @1%
--   VB  :  25,000 net +  3,000 input VAT from a supplier, EWT 500 @2%
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '12500000-0000-0000-0000-0000000000c1',
    'branch_id',                 '12500000-0000-0000-0000-0000000000d1',
    'date',                      '2026-02-11',
    'customer_id',               '12500000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot',    'Ordinary Buyer Inc',
    'customer_tin_snapshot',     '111-222-333-125',
    'customer_address_snapshot', 'Pasig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Wholesale goods',
    'quantity',           1,
    'unit_price',         100000,
    'revenue_account_id', '12500000-0000-0000-0000-00000000a008',
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

INSERT INTO t_ctx
SELECT 'cs', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '12500000-0000-0000-0000-0000000000c1',
    'branch_id',              '12500000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-09',
    'customer_id',            '12500000-0000-0000-0000-0000000000e2',
    'customer_name_snapshot', 'Top Withholding Agent Corp',
    'customer_tin_snapshot',  '444-555-666-125'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',             'Counter sale',
    'quantity',                1,
    'unit_price',              50000,
    'revenue_account_id',      '12500000-0000-0000-0000-00000000a008',
    'vat_code_id',             (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code = 'WC158' AND is_active)
  )),
  0)->>'si_id')::uuid;

INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',             '12500000-0000-0000-0000-0000000000c1',
    'branch_id',              '12500000-0000-0000-0000-0000000000d1',
    'supplier_id',            '12500000-0000-0000-0000-0000000000e3',
    'supplier_name_snapshot', 'Landlord Services Inc',
    'supplier_tin_snapshot',  '777-888-999-125',
    'bill_date',              '2026-03-20',
    'supplier_invoice_number','LSI-125-001',
    'due_date',               '2026-04-20'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Quarterly office rent',
    'quantity',           1,
    'unit_price',         25000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', '12500000-0000-0000-0000-00000000a009',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC160' AND is_active)
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'));

SELECT results_eq(
  $$SELECT tax_kind::text, SUM(tax_base)::numeric, SUM(tax_amount)::numeric
      FROM tax_detail_entries
     WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
     GROUP BY tax_kind ORDER BY tax_kind$$,
  $$VALUES ('cwt_receivable'::text, 50000.00::numeric, 500.00::numeric),
           ('ewt_payable'::text,    25000.00::numeric, 500.00::numeric),
           ('input_vat'::text,      25000.00::numeric, 3000.00::numeric),
           ('output_vat'::text,    150000.00::numeric, 18000.00::numeric)$$,
  'the three documents leave exactly four kinds of tax in the ledger');           -- 6

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — One reconciliation, three faces
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $$SELECT tax_kind::text, ledger_tax_amount, gl_amount, variance, is_reconciled
      FROM fn_tax_ledger_gl_reconciliation('12500000-0000-0000-0000-0000000000c1',
             ARRAY['input_vat','output_vat'], DATE '2026-01-01', DATE '2026-03-31')$$,
  $$SELECT tax_kind::text, ledger_tax_amount, gl_amount, variance, is_reconciled
      FROM fn_vat_gl_reconciliation('12500000-0000-0000-0000-0000000000c1',
             DATE '2026-01-01', DATE '2026-03-31')$$,
  'the VAT face returns exactly what the one reconciliation returns');            -- 7

SELECT results_eq(
  $$SELECT tax_kind::text, ledger_tax_amount, gl_amount, variance, is_reconciled
      FROM fn_tax_ledger_gl_reconciliation('12500000-0000-0000-0000-0000000000c1',
             ARRAY['cwt_receivable','ewt_payable'], DATE '2026-01-01', DATE '2026-03-31')$$,
  $$SELECT tax_kind::text, ledger_tax_amount, gl_amount, variance, is_reconciled
      FROM fn_wht_gl_reconciliation('12500000-0000-0000-0000-0000000000c1',
             DATE '2026-01-01', DATE '2026-03-31')$$,
  'and so does the withholding face');                                            -- 8

SELECT is(
  (SELECT count(*)::integer FROM fn_tax_ledger_gl_reconciliation(
     '12500000-0000-0000-0000-0000000000c1',
     ARRAY['input_vat','output_vat','ewt_payable','cwt_receivable'],
     DATE '2026-01-01', DATE '2026-03-31')
   WHERE NOT is_reconciled),
  0, 'every tax kind ties to its control account at zero variance');              -- 9

SELECT throws_like(
  $$SELECT * FROM fn_tax_ledger_gl_reconciliation(
      '12500000-0000-0000-0000-0000000000c1', ARRAY[]::text[],
      DATE '2026-01-01', DATE '2026-03-31')$$,
  '%at least one tax kind%',
  'a reconciliation over no tax kind is refused rather than silently empty');     -- 10

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — 2550Q, generated from the books rather than the browser
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT '2550q', (fn_generate_filing_artifact(
  '12500000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)->>'artifact_id')::uuid;

SELECT results_eq(
  $$SELECT total_tax_base, total_tax_amount, net_tax_payable, status::text,
           period_from, period_to
      FROM filing_artifacts WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  $$VALUES (175000.00::numeric, 21000.00::numeric, 15000.00::numeric, 'draft'::text,
            '2026-01-01'::date, '2026-03-31'::date)$$,
  'the 2550Q nets 18,000 output VAT against 3,000 input VAT to 15,000 payable');  -- 11

SELECT results_eq(
  $$SELECT tax_kind::text, classification::text, tax_base, tax_amount
      FROM filing_artifact_lines
     WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')
     ORDER BY tax_kind, tax_base$$,
  $$VALUES ('input_vat'::text,  'regular'::text,  25000.00::numeric,  3000.00::numeric),
           ('output_vat'::text, 'regular'::text, 150000.00::numeric, 18000.00::numeric)$$,
  'and its working paper carries the VAT-code split behind each figure');         -- 12

SELECT is(
  (SELECT (summary->'output_vat'->>'tax_amount')::numeric
     FROM filing_artifacts WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  18000.00::numeric,
  'the per-kind summary is stored on the artifact, not as per-form columns');     -- 13

SELECT is(
  (SELECT SUM(tax_amount) FROM filing_artifact_lines
    WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  (SELECT total_tax_amount FROM filing_artifacts
    WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  'the working paper adds up to the return it stands behind');                    -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — The same engine, four more artifacts
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (fn_generate_filing_artifact('12500000-0000-0000-0000-0000000000c1',
     '1601EQ', 2026, 1)->>'total_tax_amount')::numeric,
  500.00::numeric, 'the 1601EQ reports the 500.00 withheld from the supplier');   -- 15

SELECT results_eq(
  $$SELECT atc_code::text, tax_base, tax_amount FROM filing_artifact_lines l
      JOIN filing_artifacts a ON a.id = l.artifact_id
     WHERE a.company_id = '12500000-0000-0000-0000-0000000000c1'
       AND a.form_code = '1601EQ'$$,
  $$VALUES ('WC160'::text, 25000.00::numeric, 500.00::numeric)$$,
  'grouped by ATC, which is how a 1601EQ alphalist is filed');                    -- 16

SELECT is(
  (SELECT (fn_generate_filing_artifact('12500000-0000-0000-0000-0000000000c1',
     'SLSP', 2026, 1)->>'line_count')::integer),
  3, 'the SLSP lists three counterparties: two customers and one supplier');      -- 17

SELECT results_eq(
  $$SELECT tax_kind::text, counterparty_name::text, tax_base, tax_amount
      FROM filing_artifact_lines l JOIN filing_artifacts a ON a.id = l.artifact_id
     WHERE a.company_id = '12500000-0000-0000-0000-0000000000c1'
       AND a.form_code = 'SLSP'
     ORDER BY tax_kind, counterparty_name$$,
  $$VALUES ('input_vat'::text,  'Landlord Services Inc'::text,       25000.00::numeric,  3000.00::numeric),
           ('output_vat'::text, 'Ordinary Buyer Inc'::text,         100000.00::numeric, 12000.00::numeric),
           ('output_vat'::text, 'Top Withholding Agent Corp'::text,  50000.00::numeric,  6000.00::numeric)$$,
  'the same reader groups by counterparty when the artifact says to');            -- 18

SELECT is(
  (SELECT net_tax_payable FROM filing_artifacts
    WHERE company_id = '12500000-0000-0000-0000-0000000000c1' AND form_code = 'SLSP'),
  NULL, 'a listing owes nothing, so it reports no payable');                      -- 19

SELECT results_eq(
  $$SELECT counterparty_name::text, atc_code::text, tax_base, tax_amount
      FROM filing_artifact_lines l JOIN filing_artifacts a ON a.id = l.artifact_id
     WHERE a.company_id = '12500000-0000-0000-0000-0000000000c1'
       AND a.form_code = 'SAWT'$$,
  $$VALUES ('Top Withholding Agent Corp'::text, 'WC158'::text, 50000.00::numeric, 500.00::numeric)$$,
  'the SAWT lists the tax withheld FROM this company, per payor and ATC')
FROM (SELECT fn_generate_filing_artifact('12500000-0000-0000-0000-0000000000c1',
        'SAWT', 2026, 1)) g;                                                      -- 20

SELECT is(
  (fn_generate_filing_artifact('12500000-0000-0000-0000-0000000000c1',
     '2551Q', 2026, 1)->>'line_count')::integer,
  0, 'a VAT company files an empty 2551Q rather than an error: it owes none');    -- 21

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — Percentage tax uses this engine, not the one it shipped with
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc ~ '\mfn_generate_filing_artifact\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_pt_return'),
  'fn_generate_pt_return generates its return through the one generator');        -- 22

SELECT ok(
  (SELECT p.prosrc ~ '\mfn_filing_working_paper\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_compute_percentage_tax_return'),
  'and the 2551Q computation reads the one working paper');                       -- 23

SELECT ok(
  (SELECT bool_and(p.prosrc !~ 'FROM\s+tax_detail_entries')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('fn_vat_gl_reconciliation', 'fn_wht_gl_reconciliation',
                        'fn_percentage_tax_gl_reconciliation', 'fn_compute_ewt_return',
                        'fn_compute_percentage_tax_return')),
  'no per-form function reads the tax ledger itself any more');                   -- 24

SELECT results_eq(
  $$SELECT total_tax_base, total_ewt_withheld
      FROM fn_compute_ewt_return('12500000-0000-0000-0000-0000000000c1', 2026, 1)$$,
  $$VALUES (25000.00::numeric(15,2), 500.00::numeric(15,2))$$,
  'the 1601EQ face still answers exactly as its screen expects');                 -- 25

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F2 — The 2550Q stops being computed in a browser
--
--   The quarterly VAT return screen summed two review views with JavaScript
--   `reduce` and typed the result into `vat_returns`. These assertions prove the
--   same row is now a projection of the artifact, that the VAT classification
--   split the form needs survives the trip, and that the two figures which are
--   NOT this quarter's ledger are preserved rather than invented.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $$SELECT output_taxable_sales, output_vat, input_taxable_purchases, input_vat,
           total_available_input_vat, net_vat_payable, status::text
      FROM vat_returns
     WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
       AND return_type = '2550Q' AND period_year = 2026 AND period_quarter = 1$$,
  $$VALUES (150000.00::numeric, 18000.00::numeric, 25000.00::numeric, 3000.00::numeric,
            3000.00::numeric, 15000.00::numeric, 'draft'::text)$$,
  'the 2550Q projects into vat_returns straight from the artifact')
FROM (SELECT fn_generate_vat_return('12500000-0000-0000-0000-0000000000c1', 2026, 1)) g; -- 26

SELECT ok(
  (SELECT p.prosrc ~ '\mfn_generate_filing_artifact\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_vat_return'),
  'and it generates that return through the one generator');                      -- 27

SELECT ok(
  (SELECT p.prosrc !~ 'vw_output_vat_review|vw_input_vat_review'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_vat_return'),
  'reading neither of the review views the browser used to sum');                 -- 28

-- Input VAT carried over is the prior quarter's fact, not this quarter's
-- ledger. The accountant states it to the engine; the engine nets it.
SELECT results_eq(
  $$SELECT input_vat, input_vat_carried_over, total_available_input_vat,
           net_vat_payable, vat_paid_prior_months, vat_still_due
      FROM vat_returns
     WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
       AND return_type = '2550Q' AND period_year = 2026 AND period_quarter = 1$$,
  $$VALUES (3000.00::numeric, 1000.00::numeric, 4000.00::numeric,
            14000.00::numeric, 2000.00::numeric, 12000.00::numeric)$$,
  'a stated carry-over and prior payment are netted in the database, not the browser')
FROM (SELECT fn_generate_vat_return('12500000-0000-0000-0000-0000000000c1',
        2026, 1, 1000.00, 2000.00)) g;                                          -- 29

SELECT results_eq(
  $$SELECT input_vat_carried_over, vat_paid_prior_months FROM vat_returns
     WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
       AND return_type = '2550Q' AND period_year = 2026 AND period_quarter = 1$$,
  $$VALUES (1000.00::numeric, 2000.00::numeric)$$,
  'and regenerating without restating them leaves them where they were')
FROM (SELECT fn_generate_vat_return('12500000-0000-0000-0000-0000000000c1', 2026, 1)) g; -- 30

SELECT throws_like(
  $$SELECT fn_generate_vat_return('12500000-0000-0000-0000-0000000000c1',
      2026, 1, -5.00, NULL)$$,
  '%cannot be negative%',
  'a negative carry-over is refused rather than quietly netted');                -- 31

-- ── A quarter with all three VAT treatments on one invoice ──────────────────
INSERT INTO t_ctx
SELECT 'si2', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '12500000-0000-0000-0000-0000000000c1',
    'branch_id',                 '12500000-0000-0000-0000-0000000000d1',
    'date',                      '2026-05-12',
    'customer_id',               '12500000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot',    'Ordinary Buyer Inc',
    'customer_tin_snapshot',     '111-222-333-125',
    'customer_address_snapshot', 'Pasig'
  ),
  jsonb_build_array(
    jsonb_build_object('description','Taxable goods','quantity',1,'unit_price',10000,
      'revenue_account_id','12500000-0000-0000-0000-00000000a008',
      'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12')),
    jsonb_build_object('description','Export sale','quantity',1,'unit_price',40000,
      'revenue_account_id','12500000-0000-0000-0000-00000000a008',
      'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-0-EXPORT')),
    jsonb_build_object('description','Exempt goods','quantity',1,'unit_price',30000,
      'revenue_account_id','12500000-0000-0000-0000-00000000a008',
      'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'))
  ));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si2'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si2'));

SELECT results_eq(
  $$SELECT output_taxable_sales, zero_rated_sales, exempt_sales, output_vat, net_vat_payable
      FROM vat_returns
     WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
       AND return_type = '2550Q' AND period_year = 2026 AND period_quarter = 2$$,
  $$VALUES (10000.00::numeric, 40000.00::numeric, 30000.00::numeric,
            1200.00::numeric, 1200.00::numeric)$$,
  'zero-rated and exempt sales reach the return in their own columns, taxed at nil')
FROM (SELECT fn_generate_vat_return('12500000-0000-0000-0000-0000000000c1', 2026, 2)) g; -- 32

SELECT results_eq(
  $$SELECT classification::text, tax_base, tax_amount
      FROM filing_artifact_lines l JOIN filing_artifacts a ON a.id = l.artifact_id
     WHERE a.company_id = '12500000-0000-0000-0000-0000000000c1'
       AND a.form_code = '2550Q' AND a.period_number = 2
     ORDER BY classification$$,
  $$VALUES ('exempt'::text,     30000.00::numeric,    0.00::numeric),
           ('regular'::text,    10000.00::numeric, 1200.00::numeric),
           ('zero_rated'::text, 40000.00::numeric,    0.00::numeric)$$,
  'because the working paper carries the classification behind every figure');    -- 33

SELECT lives_ok(
  $$UPDATE vat_returns SET status = 'final'
     WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
       AND return_type = '2550Q' AND period_year = 2026 AND period_quarter = 2$$,
  'a projected return satisfies the guard that ties it to the tax ledger');       -- 34

SELECT throws_like(
  $$SELECT fn_generate_vat_return('12500000-0000-0000-0000-0000000000c1', 2026, 2)$$,
  '%cannot be regenerated%',
  'and once final it is never regenerated underneath the accountant');            -- 35

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — A return is evidence: it cannot outrun the ledger, and once filed
--   it cannot move.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$UPDATE filing_artifacts SET total_tax_amount = 999, status = 'final'
     WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  '%does not reconcile to the posted ledger%',
  'a return may not be filed on a figure the ledger does not support');           -- 36

SELECT lives_ok(
  $$UPDATE filing_artifacts SET status = 'final'
     WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  'a return that agrees with the ledger may be marked final');                    -- 37

SELECT throws_like(
  $$SELECT fn_generate_filing_artifact('12500000-0000-0000-0000-0000000000c1',
      '2550Q', 2026, 1)$$,
  '%cannot be regenerated%',
  'and is never silently regenerated underneath the accountant');                 -- 38

SELECT lives_ok(
  $$UPDATE filing_artifacts SET status = 'filed', filed_date = DATE '2026-04-24',
      reference_no = 'EFPS-125-0001'
     WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  'filing it records the reference and the date');                                -- 39

SELECT throws_like(
  $$UPDATE filing_artifacts SET total_tax_amount = 21000.01
     WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  '%filed 2550Q return is immutable%',
  'a filed return is immutable: a correction is an amended return');              -- 40

SELECT throws_like(
  $$DELETE FROM filing_artifacts WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  '%cannot be deleted%',
  'and a filed return cannot be deleted');                                        -- 41

-- The claim the whole file exists for.
SELECT is(
  (SELECT count(*)::integer FROM filing_artifacts
    WHERE company_id = '12500000-0000-0000-0000-0000000000c1'
      AND period_year = 2026 AND period_number = 1),
  5,
  'five artifacts for one quarter, all from one ledger through one engine');      -- 42

SELECT * FROM finish();
ROLLBACK;
