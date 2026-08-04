-- ══════════════════════════════════════════════════════════════════════════════
-- 127 — The 1601EQ and the QAP on the Filing Artifact layer (Backlog 8e i, iii)
--
-- WHAT THIS GUARDS
--   Two compliance surfaces that computed correctly and recorded nothing:
--
--     • The 1601EQ screen computed through the governed engine and then wrote
--       `ewt_returns` by typed INSERT from the browser, so a return could be
--       marked filed with **no filing artifact behind it** — no working paper,
--       nothing to export, nothing for the export layer to consume.
--     • The QAP was aggregated in JavaScript from `vw_ewt_summary_ap` and was
--       registered nowhere, so the alphalist attached to the 1601EQ could not be
--       shown to agree with it, or with the General Ledger.
--
--   The claim these assertions make is that both now travel one path:
--
--       posted transactions → Tax Engine → tax ledger → working paper
--                           → artifact → export
--
--   and that the alphalist adds up to the return it is attached to by
--   construction, because both read the same ledger through the same reader.
--
--   The company, its masters and its documents are provisioned here through the
--   current production RPCs. It never reads the canonical/demo seed
--   (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   That anything has been filed with the Bureau. It does not cover the SLSP
--   screen (Backlog 8e ii, blocked on the quarterly evidence model in 8c) or the
--   retirement of the legacy `compliance_*` working papers and
--   `fn_snapshot_wht_export` (Backlog 8f).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(34);

-- ── Fixture: a VAT-registered top withholding agent that withholds from two suppliers
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12700000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'ewt-qap@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12700000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12700000-0000-0000-0000-0000000000c1', 'corporation', 'Withholding Agent Corp',
        'Wholesale and services', '355-127-001-00000', 'vat', 'calendar',
        '127 Alphalist Ave', '', 'Makati', 'Metro Manila', '1200',
        'ewt-qap@test.local', 'Wilma Cruz', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12700000-0000-0000-0000-0000000000d1', '12700000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', '127 Alphalist Ave', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12700000-0000-0000-0000-0000000000f1', '12700000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12700000-0000-0000-0000-0000000000c1', '12700000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12700000-0000-0000-0000-00000000a001', '12700000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a002', '12700000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a003', '12700000-0000-0000-0000-0000000000c1', '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a004', '12700000-0000-0000-0000-0000000000c1', '1400', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a005', '12700000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a006', '12700000-0000-0000-0000-0000000000c1', '2000', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a007', '12700000-0000-0000-0000-0000000000c1', '2210', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a008', '12700000-0000-0000-0000-0000000000c1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a009', '12700000-0000-0000-0000-0000000000c1', '6100', 'Rent Expense',        'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-00000000a010', '12700000-0000-0000-0000-0000000000c1', '6200', 'Professional Fees',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('12700000-0000-0000-0000-0000000000c1',
        '12700000-0000-0000-0000-00000000a002', '12700000-0000-0000-0000-00000000a006',
        '12700000-0000-0000-0000-00000000a005', '12700000-0000-0000-0000-00000000a004',
        '12700000-0000-0000-0000-00000000a003', '12700000-0000-0000-0000-00000000a007',
        '12700000-0000-0000-0000-00000000a001', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, vat_registered, vat_filing_frequency,
                                 percentage_tax_registered, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, files_0619e,
                                 created_by, updated_by)
VALUES ('12700000-0000-0000-0000-0000000000c1', true, 'quarterly', false, true, true,
        false, true, auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12700000-0000-0000-0000-0000000000c1', '12700000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-127-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS', 'SI', 'VB');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, is_subject_to_ewt, default_atc_code_id,
                       created_by, updated_by)
VALUES
  ('12700000-0000-0000-0000-0000000000e1', '12700000-0000-0000-0000-0000000000c1',
   'SUPP-A', 'Landlord Services Inc', '777-888-999-127', 'Makati',
   true, (SELECT id FROM atc_codes WHERE code = 'WC160' AND is_active),
   auth.uid(), auth.uid()),
  ('12700000-0000-0000-0000-0000000000e2', '12700000-0000-0000-0000-0000000000c1',
   'SUPP-B', 'Padilla Consulting Corp', '222-333-444-127', 'Pasig',
   true, (SELECT id FROM atc_codes WHERE code = 'WC010' AND is_active),
   auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Registering the QAP was a seed row, as the engine promised
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $$SELECT artifact_kind::text, period_basis::text, group_dimensions::text[]
      FROM ref_filing_artifact WHERE form_code = 'QAP' AND is_active$$,
  $$VALUES ('listing'::text, 'quarterly'::text, ARRAY['counterparty','atc']::text[])$$,
  'the QAP is registered as a quarterly listing grouped per payee and ATC');      -- 1

SELECT results_eq(
  $$SELECT tax_kind::text, net_sign::int FROM ref_filing_artifact_kind
     WHERE form_code = 'QAP'$$,
  $$VALUES ('ewt_payable'::text, 0)$$,
  'it reads the same tax kind as the 1601EQ and owes nothing itself');            -- 2

SELECT set_eq(
  $$SELECT DISTINCT export_format::text FROM ref_filing_export_column
     WHERE form_code = 'QAP'$$,
  $$VALUES ('csv'),('dat')$$,
  'and it was given both export layouts as configuration, not code');             -- 3

-- The constraint that keeps the export a consumer still admits nothing that
-- reaches a transaction or the tax ledger, with the ATC description added.
SELECT ok(
  (SELECT pg_get_constraintdef(oid) !~* 'tax_detail|journal|invoice|receipt|vw_'
     FROM pg_constraint
    WHERE conrelid = 'ref_filing_export_column'::regclass
      AND pg_get_constraintdef(oid) ~ 'source_field'),
  'no export column may name a transaction or tax-ledger source');                -- 4

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The documents. Everything below is read from these postings.
--   VB1 : 25,000 rent from Landlord Services, WC160 @2%  → EWT   500
--   VB2 : 15,000 rent from Landlord Services, WC160 @2%  → EWT   300
--   VB3 : 20,000 fees from Padilla Consulting, WC010 @10% → EWT 2,000
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'vb1', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',             '12700000-0000-0000-0000-0000000000c1',
    'branch_id',              '12700000-0000-0000-0000-0000000000d1',
    'supplier_id',            '12700000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot', 'Landlord Services Inc',
    'supplier_tin_snapshot',  '777-888-999-127',
    'bill_date',              '2026-02-10',
    'supplier_invoice_number','LSI-127-001',
    'due_date',               '2026-03-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'February office rent',
    'quantity',           1,
    'unit_price',         25000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', '12700000-0000-0000-0000-00000000a009',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC160' AND is_active)
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb1'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb1'));

INSERT INTO t_ctx
SELECT 'vb2', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',             '12700000-0000-0000-0000-0000000000c1',
    'branch_id',              '12700000-0000-0000-0000-0000000000d1',
    'supplier_id',            '12700000-0000-0000-0000-0000000000e1',
    'supplier_name_snapshot', 'Landlord Services Inc',
    'supplier_tin_snapshot',  '777-888-999-127',
    'bill_date',              '2026-03-05',
    'supplier_invoice_number','LSI-127-002',
    'due_date',               '2026-04-05'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'March office rent',
    'quantity',           1,
    'unit_price',         15000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', '12700000-0000-0000-0000-00000000a009',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC160' AND is_active)
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb2'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb2'));

INSERT INTO t_ctx
SELECT 'vb3', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',             '12700000-0000-0000-0000-0000000000c1',
    'branch_id',              '12700000-0000-0000-0000-0000000000d1',
    'supplier_id',            '12700000-0000-0000-0000-0000000000e2',
    'supplier_name_snapshot', 'Padilla Consulting Corp',
    'supplier_tin_snapshot',  '222-333-444-127',
    'bill_date',              '2026-03-18',
    'supplier_invoice_number','PCC-127-001',
    'due_date',               '2026-04-18'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Quarterly advisory retainer',
    'quantity',           1,
    'unit_price',         20000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', '12700000-0000-0000-0000-00000000a010',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC010' AND is_active)
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb3'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb3'));

SELECT results_eq(
  $$SELECT SUM(tax_base)::numeric, SUM(tax_amount)::numeric
      FROM tax_detail_entries
     WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
       AND tax_kind = 'ewt_payable'$$,
  $$VALUES (60000.00::numeric, 2800.00::numeric)$$,
  'three bills leave 60,000 of income payments and 2,800 withheld in the ledger'); -- 5

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — The 1601EQ is projected from its artifact, never typed
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT '1601eq', (fn_generate_ewt_return(
  '12700000-0000-0000-0000-0000000000c1', 2026, 1)->>'artifact_id')::uuid;

SELECT results_eq(
  $$SELECT total_tax_base, total_tax_amount, net_tax_payable, status::text,
           period_from, period_to
      FROM filing_artifacts WHERE id = (SELECT id FROM t_ctx WHERE key = '1601eq')$$,
  $$VALUES (60000.00::numeric, 2800.00::numeric, 2800.00::numeric, 'draft'::text,
            '2026-01-01'::date, '2026-03-31'::date)$$,
  'generating the return generates the artifact the screen never used to leave'); -- 6

SELECT results_eq(
  $$SELECT total_tax_base, total_ewt_withheld, remitted_prior, still_due, status::text
      FROM ewt_returns
     WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_quarter = 1$$,
  $$VALUES (60000.00::numeric, 2800.00::numeric, 0.00::numeric, 2800.00::numeric,
            'draft'::text)$$,
  'and projects it into the ewt_returns row the screen reads');                   -- 7

SELECT is(
  (SELECT SUM(tax_amount) FROM filing_artifact_lines
    WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '1601eq')),
  (SELECT total_ewt_withheld FROM ewt_returns
    WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
      AND period_year = 2026 AND period_quarter = 1),
  'the working paper adds up to the return it stands behind');                    -- 8

SELECT results_eq(
  $$SELECT atc_code::text, tax_base, tax_amount, document_count
      FROM filing_artifact_lines
     WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '1601eq')
     ORDER BY atc_code$$,
  $$VALUES ('WC010'::text, 20000.00::numeric, 2000.00::numeric, 1),
           ('WC160'::text, 40000.00::numeric,  800.00::numeric, 2)$$,
  'grouped by ATC, which is how a 1601EQ is filed, and counting its documents');  -- 9

-- Derived, not stated: what was already remitted is a fact about posted 0619-E
-- remittances, and PXL-AUD-041 already made the gate say so. The projection
-- reads that governed source, so the 1601EQ carries no stated figure at all.
SELECT ok(
  (SELECT p.prosrc ~ '\mfn_compute_ewt_remitted_prior\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_ewt_return'),
  'what was already remitted is read from the posted 0619-E remittances');        -- 10

SELECT throws_like(
  $$UPDATE ewt_returns SET remitted_prior = 1000.00, still_due = 1800.00,
      status = 'final'
     WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_quarter = 1$$,
  '%does not match the controlled 0619-E remittances%',
  'and a remittance typed into the return instead is refused, not filed');        -- 11

SELECT results_eq(
  $$SELECT total_tax_base, total_ewt_withheld, remitted_prior, still_due
      FROM ewt_returns
     WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_quarter = 1$$,
  $$VALUES (60000.00::numeric, 2800.00::numeric, 0.00::numeric, 2800.00::numeric)$$,
  'regenerating a draft restates it from the same ledger and moves nothing')
FROM (SELECT fn_generate_ewt_return('12700000-0000-0000-0000-0000000000c1', 2026, 1)) g; -- 12

SELECT ok(
  (SELECT p.prosrc ~ '\mfn_generate_filing_artifact\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_ewt_return'),
  'the 1601EQ is generated through the one generator');                           -- 13

SELECT ok(
  (SELECT p.prosrc !~* 'tax_detail_entries|journal_entr|vw_ewt_summary'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_ewt_return'),
  'and reads no ledger, journal or review source of its own');                    -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — The QAP is the alphalist behind that return
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'qap', (fn_generate_filing_artifact(
  '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1)->>'artifact_id')::uuid;

SELECT results_eq(
  $$SELECT counterparty_name::text, counterparty_tin::text, atc_code::text,
           tax_rate, tax_base, tax_amount
      FROM filing_artifact_lines
     WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = 'qap')
     ORDER BY counterparty_name$$,
  $$VALUES ('Landlord Services Inc'::text,   '777-888-999-00127'::text, 'WC160'::text,
            2.0000::numeric, 40000.00::numeric,  800.00::numeric),
           ('Padilla Consulting Corp'::text, '222-333-444-00127'::text, 'WC010'::text,
            10.0000::numeric, 20000.00::numeric, 2000.00::numeric)$$,
  'the alphalist is one row per payee and ATC, from the one working paper');       -- 15

SELECT is(
  (SELECT SUM(l.tax_amount) FROM filing_artifact_lines l
    WHERE l.artifact_id = (SELECT id FROM t_ctx WHERE key = 'qap')),
  (SELECT a.total_tax_amount FROM filing_artifacts a
    WHERE a.id = (SELECT id FROM t_ctx WHERE key = '1601eq')),
  'and it adds up to the 1601EQ it is attached to, by construction');              -- 16

SELECT is(
  (SELECT net_tax_payable FROM filing_artifacts
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'qap')),
  NULL, 'a listing owes nothing, so it reports no payable');                       -- 17

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_reconciliation(
     '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1)
    WHERE NOT is_reconciled),
  0, 'the alphalist ties to the EWT Payable control account at zero variance');    -- 18

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — Getting it out of PXL, through the one export
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT * FROM fn_filing_artifact_export(
      '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1, 'csv')$$,
  '%still a draft and cannot be exported%',
  'a draft alphalist does not leave the system');                                  -- 19

SELECT lives_ok(
  $$UPDATE filing_artifacts SET status = 'final'
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'qap')$$,
  'an alphalist that agrees with the ledger may be marked final');                 -- 20

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1, 'csv')
    WHERE line_number = 0),
  '"TIN","Registered Name","ATC","Nature of Payment","Rate","Income Payments","Tax Withheld"',
  'row 0 is the header the registry declares, in its declared order');             -- 21

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1, 'csv')
    WHERE line_number = 1),
  '"222-333-444-00127","Padilla Consulting Corp","WC010","Professional Fees — Corporation","10.00","20000.00","2000.00"',
  'and a payee row names the nature of payment from the governed ATC, not a guess'); -- 22

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1, 'dat')
    WHERE line_number = 1),
  '22233344400127,Padilla Consulting Corp,WC010,20000.00,2000.00',
  'the same artifact line renders as a DAT alphalist from the same layout table'); -- 23

SELECT ok(
  (SELECT p.prosrc !~* 'tax_detail_entries|journal_entry_lines|journal_entries|vw_[a-z_]*review|vw_slp_export|vw_cwt_summary|vw_ewt_summary|sales_invoice|receipts'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_filing_artifact_export'),
  'the exporter still reads no transaction, tax-ledger or review source');         -- 24

SELECT ok(
  (SELECT p.prosrc !~* 'SUM\s*\(|AVG\s*\(|MAX\s*\(|COUNT\s*\(\s*[a-z]'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_filing_artifact_export'),
  'and still aggregates no figure: the artifact already stated every number');     -- 25

INSERT INTO t_ctx
SELECT 'snap', fn_snapshot_filing_artifact_export(
  '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1, 'csv');

SELECT results_eq(
  $$SELECT source_table::text, report_type::text, snapshot_status::text, source_row_count
      FROM report_snapshots WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')$$,
  $$VALUES ('filing_artifacts'::text, 'QAP'::text, 'exported'::text, 3)$$,
  'the QAP export is evidenced against the artifact, header row and two payees'); -- 26

SELECT is(
  (SELECT source_id FROM report_snapshots
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')),
  (SELECT id FROM t_ctx WHERE key = 'qap'),
  'keyed to the artifact by its own id, not a synthesised one');                  -- 27

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — The withholding-agent gate reaches the new path
--
--   A company that is not EWT-registered may not produce a QAP. That gate keyed
--   on the legacy snapshot's source table; migrating the screen would have
--   walked around it.
-- ══════════════════════════════════════════════════════════════════════════════
UPDATE compliance_profiles SET ewt_registered = false
 WHERE company_id = '12700000-0000-0000-0000-0000000000c1';

SELECT throws_like(
  $$SELECT fn_snapshot_filing_artifact_export(
      '12700000-0000-0000-0000-0000000000c1', 'QAP', 2026, 1, 'csv')$$,
  '%not EWT-registered%',
  'a company that is not a withholding agent cannot export a QAP');               -- 28

UPDATE compliance_profiles SET ewt_registered = true
 WHERE company_id = '12700000-0000-0000-0000-0000000000c1';

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — The QAP-to-2307 comparison is no longer an orphan reading a view
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc ~ '\mfn_filing_working_paper\M' AND p.prosrc !~ 'vw_ewt_summary_ap'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_qap_2307_reconciliation'),
  'the comparison reads the artifact working paper, not the source view');        -- 29

SELECT results_eq(
  $$SELECT supplier_name::text, atc_code::text, nature_of_payment::text,
           qap_tax_withheld, form2307_tax_withheld, is_reconciled
      FROM fn_qap_2307_reconciliation('12700000-0000-0000-0000-0000000000c1', 2026, 1)$$,
  $$VALUES ('Landlord Services Inc'::text,   'WC160'::text,
            'Purchases of services by Top Withholding Agents - juridical persons'::text,
            800.00::numeric, 0.00::numeric, false),
           ('Padilla Consulting Corp'::text, 'WC010'::text,
            'Professional Fees — Corporation'::text,
            2000.00::numeric, 0.00::numeric, false)$$,
  'with no certificate issued, every alphalist row is unsupported and says so');  -- 30

-- Issued in its own statement: the comparison is STABLE, so within one statement
-- it would read the snapshot taken before these certificates existed.
SELECT fn_generate_form_2307_issued('12700000-0000-0000-0000-0000000000c1', 2026, 1);

SELECT is(
  (SELECT count(*)::integer FROM fn_qap_2307_reconciliation(
     '12700000-0000-0000-0000-0000000000c1', 2026, 1) WHERE NOT is_reconciled),
  0, 'and once the 2307 certificates are issued, every row agrees with them');    -- 31

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION H — A return that has left draft is evidence
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok(
  $$UPDATE ewt_returns SET status = 'final'
     WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_quarter = 1$$,
  'a projected 1601EQ satisfies the gate that ties it to the tax ledger');        -- 32

SELECT throws_like(
  $$SELECT fn_generate_ewt_return('12700000-0000-0000-0000-0000000000c1', 2026, 1)$$,
  '%cannot be regenerated%',
  'and once final it is never regenerated underneath the accountant');            -- 33

-- The claim the whole file exists for.
SELECT set_eq(
  $$SELECT form_code::text FROM filing_artifacts
     WHERE company_id = '12700000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_number = 1$$,
  $$VALUES ('1601EQ'),('QAP')$$,
  'the return and the alphalist attached to it are both artifacts of one ledger'); -- 34

SELECT * FROM finish();
ROLLBACK;
