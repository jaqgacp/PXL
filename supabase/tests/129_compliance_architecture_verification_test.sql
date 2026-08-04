-- ══════════════════════════════════════════════════════════════════════════════
-- 129 — Compliance architecture verification (Backlog 8f, stage 2)
--
-- THIS FILE IS THE VERIFICATION REPORT.
--
--   The owner asked, on completion of 8f, for a report showing that only one
--   compliance architecture remains and that no routed screen, RPC or export
--   bypasses the governed pipeline. Prose goes stale the moment someone adds a
--   function; this asserts it instead, on every run of the suite.
--
--   The claim, stated exactly as it must be stated:
--
--     **The governed compliance architecture is complete for every implemented
--     compliance family. FWT remains the single documented exception because no
--     governed FWT pipeline exists yet.**
--
--   Assertions 1–8 verify the first sentence. Assertions 9–11 verify the second
--   — the exception is asserted, not merely written down, so it cannot be
--   quietly forgotten or quietly widened.
--
--   The database half is here. The screen half is `tests/compliance_architecture
--   .test.ts`, which reads `src/` and asserts no page reaches a retired table or
--   the retired export.
--
-- IT ALSO CARRIES WHAT RETIREMENT WOULD OTHERWISE HAVE LOST
--   Test `016` covered the legacy SAWT/QAP export snapshots. Its subject was
--   retired by migration `20260804000006`, so the file was deleted — but two of
--   its claims were not about that subject: report snapshots are append-only to
--   an ordinary user, and an export is blocked while the control account does
--   not reconcile. Both are re-asserted here against the governed export
--   (Section C), which is what "migrate the capability, then retire" means for a
--   test.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — The second architecture is gone
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
        'compliance_vat_working_papers_headers', 'compliance_vat_working_papers_lines',
        'compliance_ewt_working_papers_headers', 'compliance_ewt_working_papers_lines',
        'compliance_1601eq_working_papers_headers', 'compliance_1601eq_working_papers_lines',
        'compliance_pt_working_papers_headers', 'compliance_pt_working_papers_lines')),
  0, 'the eight VAT, EWT, 1601EQ and PT legacy working-paper tables are gone');    -- 1

SELECT is(
  (SELECT count(*)::integer FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wht_export_periods'),
  0, 'and so is the synthesised key the legacy withholding export needed');        -- 2

SELECT is(
  (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_snapshot_wht_export'),
  0, 'the legacy withholding export function is retired, not merely unused');      -- 3

SELECT is(
  (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc ~ 'compliance_(vat|ewt|1601eq|pt)_working_papers'),
  0, 'no function anywhere in PXL still reads or writes a retired working paper'); -- 4

-- The governed working paper is a filing artifact's own lines. Nothing else in
-- the schema is a working-paper store.
SELECT set_eq(
  $$SELECT table_name::text FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name LIKE '%working_papers%'$$,
  $$VALUES ('compliance_fwt_working_papers_headers'),
           ('compliance_fwt_working_papers_lines'),
           ('compliance_1601fq_working_papers_headers'),
           ('compliance_1601fq_working_papers_lines')$$,
  'the only working-paper tables left are the four FWT ones');                     -- 5

-- Every compliance output that has left the system did so as a filing artifact.
SELECT is(
  (SELECT count(*)::integer FROM report_snapshots s
    WHERE s.report_type IN (SELECT form_code FROM ref_filing_artifact)
      AND s.source_table <> 'filing_artifacts'),
  0, 'no export snapshot of a registered form is keyed to anything else');         -- 6

-- No filing, export or artifact function reaches a review view or a transaction:
-- the whole point of the artifact layer is that they read the artifact instead.
SELECT is(
  (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname ~ '^fn_(filing|generate_filing|snapshot_filing)'
      AND p.prosrc ~* 'vw_[a-z_]*(review|summary|export)'),
  0, 'no filing or export function reads a review view');                          -- 7

SELECT is(
  (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc ~ 'INSERT INTO filing_artifacts'),
  1, 'exactly one function writes a filing artifact');                             -- 8

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The single documented exception, asserted rather than promised
--
--   FWT remains hand-keyed because there is nothing governed to move it to. The
--   two assertions below are the *reason*, so this exception cannot be widened
--   without failing, and cannot be forgotten once Backlog 22 lands: giving FWT a
--   tax kind will fail assertion 9 and force this file to be revisited.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM ref_tax_ledger_control WHERE tax_kind ~* 'fwt'),
  0, 'FWT is not a governed tax kind — Backlog 22');                               -- 9

SELECT ok(
  (SELECT pg_get_constraintdef(oid) !~* 'fwt'
     FROM pg_constraint
    WHERE conrelid = 'tax_detail_entries'::regclass
      AND conname = 'tax_detail_entries_tax_kind_check'),
  'and the tax ledger will not accept an FWT row, so no FWT artifact can exist');  -- 10

SELECT is(
  (SELECT count(*)::integer FROM ref_filing_artifact
    WHERE form_code IN ('1601FQ', '2306')),
  0, 'so no FWT form is registered: the exception is a gap, not a second engine'); -- 11

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Fixture, and the claims inherited from retired test 016
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12900000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'architecture@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12900000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12900000-0000-0000-0000-0000000000c1', 'corporation', 'One Architecture Corp',
        'Wholesale', '355-129-001-00000', 'vat', 'calendar',
        '129 Governed Ave', '', 'Makati', 'Metro Manila', '1200',
        'architecture@test.local', 'Alma Cruz', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12900000-0000-0000-0000-0000000000d1', '12900000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', '129 Governed Ave', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12900000-0000-0000-0000-0000000000f1', '12900000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12900000-0000-0000-0000-0000000000c1', '12900000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12900000-0000-0000-0000-00000000a001', '12900000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a002', '12900000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a003', '12900000-0000-0000-0000-0000000000c1', '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a004', '12900000-0000-0000-0000-0000000000c1', '1400', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a005', '12900000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a006', '12900000-0000-0000-0000-0000000000c1', '2000', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a007', '12900000-0000-0000-0000-0000000000c1', '2210', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a008', '12900000-0000-0000-0000-0000000000c1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('12900000-0000-0000-0000-00000000a009', '12900000-0000-0000-0000-0000000000c1', '2190', 'Suspense',            'liability', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('12900000-0000-0000-0000-0000000000c1',
        '12900000-0000-0000-0000-00000000a002', '12900000-0000-0000-0000-00000000a006',
        '12900000-0000-0000-0000-00000000a005', '12900000-0000-0000-0000-00000000a004',
        '12900000-0000-0000-0000-00000000a003', '12900000-0000-0000-0000-00000000a007',
        '12900000-0000-0000-0000-00000000a001', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, vat_registered, vat_filing_frequency,
                                 percentage_tax_registered, ewt_registered,
                                 created_by, updated_by)
VALUES ('12900000-0000-0000-0000-0000000000c1', true, 'quarterly', false, true,
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12900000-0000-0000-0000-0000000000c1', '12900000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-129-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS', 'SI', 'VB');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('12900000-0000-0000-0000-0000000000e1', '12900000-0000-0000-0000-0000000000c1',
        'CUST-A', 'Ordinary Buyer Inc', '111-222-333-129', 'Pasig', 'Pasig',
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '12900000-0000-0000-0000-0000000000c1',
    'branch_id',                 '12900000-0000-0000-0000-0000000000d1',
    'date',                      '2026-02-11',
    'customer_id',               '12900000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot',    'Ordinary Buyer Inc',
    'customer_tin_snapshot',     '111-222-333-129',
    'customer_address_snapshot', 'Pasig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Wholesale goods',
    'quantity',           1,
    'unit_price',         100000,
    'revenue_account_id', '12900000-0000-0000-0000-00000000a008',
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

SELECT fn_generate_filing_artifact('12900000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1);
SELECT fn_generate_vat_return('12900000-0000-0000-0000-0000000000c1', 2026, 1);
UPDATE filing_artifacts SET status = 'final'
 WHERE company_id = '12900000-0000-0000-0000-0000000000c1' AND form_code = '2550Q';

SELECT lives_ok(
  $$SELECT fn_snapshot_filing_artifact_export(
      '12900000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1, 'csv')$$,
  'a reconciled, final artifact exports and is evidenced');                        -- 12

-- Inherited from retired test 016: snapshots are append-only to an ordinary user.
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$INSERT INTO report_snapshots (company_id, report_type, source_table, source_id,
       snapshot_status, snapshot_version, period_start, period_end,
       report_payload, source_payload, source_hash)
     VALUES ('12900000-0000-0000-0000-0000000000c1', '2550Q', 'filing_artifacts',
       gen_random_uuid(), 'exported', 99, '2026-01-01', '2026-03-31',
       '{}'::jsonb, '{}'::jsonb, repeat('0', 64))$$,
  '42501', NULL,
  'authenticated users cannot insert a report snapshot directly');                 -- 13
RESET ROLE;

-- Inherited from retired test 016: an export is blocked while the control
-- account does not reconcile. Here the books move underneath a *final* artifact
-- — the mapping is re-pointed at another account, which is exactly the
-- misconfiguration the guarantee exists for.
UPDATE account_mapping SET account_id = '12900000-0000-0000-0000-00000000a009'
 WHERE company_id = '12900000-0000-0000-0000-0000000000c1' AND key_code = 'VAT_OUTPUT';

SELECT throws_like(
  $$SELECT fn_snapshot_filing_artifact_export(
      '12900000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1, 'csv')$$,
  '%no longer ties to the General Ledger%',
  'and refuses once the books no longer tie to it, even though it was final');     -- 14

UPDATE account_mapping SET account_id = '12900000-0000-0000-0000-00000000a005'
 WHERE company_id = '12900000-0000-0000-0000-0000000000c1' AND key_code = 'VAT_OUTPUT';

SELECT throws_like(
  $$SELECT * FROM fn_filing_period_bounds('quarterly', 2026, 7)$$,
  '%Invalid quarterly filing period%',
  'an impossible filing period is refused rather than guessed at');                -- 15

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — One pipeline, end to end, on one company
--
--   The same posted sale reaches the working paper, the artifact, the return
--   projection and the export, and every one of them states the same figure.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT SUM(w.tax_amount) FROM fn_filing_working_paper(
     '12900000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1) w),
  12000.00::numeric, 'the working paper reads 12,000 of output VAT from the ledger'); -- 16

SELECT is(
  (SELECT a.total_tax_amount FROM filing_artifacts a
    WHERE a.company_id = '12900000-0000-0000-0000-0000000000c1' AND a.form_code = '2550Q'),
  12000.00::numeric, 'the artifact states the same 12,000');                       -- 17

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_reconciliation(
     '12900000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1) WHERE NOT is_reconciled),
  0, 'and it ties to the General Ledger at zero variance');                        -- 18

SELECT is(
  (SELECT r.output_vat FROM vat_returns r
    WHERE r.company_id = '12900000-0000-0000-0000-0000000000c1' AND r.return_type = '2550Q'),
  12000.00::numeric, 'the return projection carries it without recomputing it');    -- 19

SELECT ok(
  (SELECT s.source_payload->>'content' LIKE '%12000.00%'
     FROM report_snapshots s
    WHERE s.company_id = '12900000-0000-0000-0000-0000000000c1'
      AND s.source_table = 'filing_artifacts'
    ORDER BY s.snapshot_version DESC LIMIT 1),
  'and the exported bytes carry the same figure the ledger posted');               -- 20

-- The reconciling item is the only manual entry anywhere in the chain, and it
-- moves none of the four figures above.
SELECT is(
  (SELECT count(*)::integer FROM filing_artifact_lines l
    WHERE l.line_kind = 'reconciling_item'),
  0, 'no reconciling item was needed to make any of that tie');                    -- 21

-- The claim the file exists for, in one assertion.
SELECT ok(
  (SELECT NOT EXISTS (
     SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND (p.prosrc ~ 'compliance_(vat|ewt|1601eq|pt)_working_papers'
             OR p.proname = 'fn_snapshot_wht_export'))
   AND NOT EXISTS (
     SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name LIKE '%working_papers%'
        AND table_name NOT LIKE '%fwt%'
        AND table_name NOT LIKE '%1601fq%')),
  'one compliance architecture remains, with FWT the single documented exception'); -- 22

SELECT * FROM finish();
ROLLBACK;
