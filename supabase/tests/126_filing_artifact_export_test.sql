-- ══════════════════════════════════════════════════════════════════════════════
-- 126 — Filing Artifact Export (Backlog 8d)
--
-- WHAT THIS GUARDS
--   The rule that closes the compliance architecture:
--
--     The Filing Artifact is the system of record for compliance outputs.
--     Every UI, export, snapshot, API and integration CONSUMES it, and none may
--     rebuild a compliance report from transactions, tax ledgers or a browser.
--
--   An accountant could previously generate a fully reconciled 2550Q, 2551Q,
--   1601EQ, SLSP or SAWT and had **no way to get it out of PXL**. This file
--   proves the export layer closes that gap as *another consumer of the
--   artifact* rather than as a second computation engine: it reads
--   `filing_artifacts` and `filing_artifact_lines` and nothing else, and a
--   form's export layout is a seed row rather than a function.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   That anything has been filed with the Bureau. It also does not touch the
--   three legacy snapshot functions, which still read source views and are
--   migrated under Backlog 8e/8f.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

-- ── Fixture: a VAT-registered company that sells to a withholding agent ─────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12600000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'filing-export@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12600000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12600000-0000-0000-0000-0000000000c1', 'corporation', 'Export Ready Trading Corp',
        'Wholesale', '355-126-001-00000', 'vat', 'calendar',
        '126 Export St', '', 'Makati', 'Metro Manila', '1200',
        'filing-export@test.local', 'Elena Cruz', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12600000-0000-0000-0000-0000000000d1', '12600000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', '126 Export St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12600000-0000-0000-0000-0000000000f1', '12600000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12600000-0000-0000-0000-0000000000c1', '12600000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12600000-0000-0000-0000-00000000a001', '12600000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a002', '12600000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a003', '12600000-0000-0000-0000-0000000000c1', '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a004', '12600000-0000-0000-0000-0000000000c1', '1400', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a005', '12600000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a006', '12600000-0000-0000-0000-0000000000c1', '2000', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a007', '12600000-0000-0000-0000-0000000000c1', '2210', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12600000-0000-0000-0000-00000000a008', '12600000-0000-0000-0000-0000000000c1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('12600000-0000-0000-0000-0000000000c1',
        '12600000-0000-0000-0000-00000000a002', '12600000-0000-0000-0000-00000000a006',
        '12600000-0000-0000-0000-00000000a005', '12600000-0000-0000-0000-00000000a004',
        '12600000-0000-0000-0000-00000000a003', '12600000-0000-0000-0000-00000000a007',
        '12600000-0000-0000-0000-00000000a001', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, vat_registered, vat_filing_frequency,
                                 percentage_tax_registered, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, files_0619e, created_by, updated_by)
VALUES ('12600000-0000-0000-0000-0000000000c1', true, 'quarterly', false, true, true,
        false, true, auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12600000-0000-0000-0000-0000000000c1', '12600000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-126-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS', 'SI', 'VB');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address,
                       is_subject_to_cwt, default_cwt_atc_code_id, created_by, updated_by)
VALUES ('12600000-0000-0000-0000-0000000000e2', '12600000-0000-0000-0000-0000000000c1',
        'CUST-B', 'Top Withholding Agent Corp', '444-555-666-00126', 'Taguig', 'Taguig',
        true, (SELECT id FROM atc_codes WHERE code = 'WC158' AND is_active),
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — A form's export layout is configuration, not code
-- ══════════════════════════════════════════════════════════════════════════════
SELECT set_eq(
  $$SELECT DISTINCT form_code::text FROM ref_filing_export_column$$,
  $$SELECT form_code::text FROM ref_filing_artifact WHERE is_active$$,
  'every registered artifact has a registered export layout');                   -- 1

SELECT results_eq(
  $$SELECT column_order, column_header::text, source_field::text, value_kind::text
      FROM ref_filing_export_column
     WHERE form_code = 'SAWT' AND export_format = 'dat' ORDER BY column_order$$,
  $$VALUES (1, 'Payor TIN'::text,      'counterparty_tin'::text,  'tin'::text),
           (2, 'Payor Name'::text,     'counterparty_name'::text, 'text'::text),
           (3, 'ATC'::text,            'atc_code'::text,          'text'::text),
           (4, 'Income Payment'::text, 'tax_base'::text,          'decimal'::text),
           (5, 'Tax Withheld'::text,   'tax_amount'::text,        'decimal'::text)$$,
  'a layout is an ordered list of artifact fields and how to render them');      -- 2

-- The claim that keeps the export a consumer: there is no source field that can
-- reach a transaction or the tax ledger, so no layout can be written that does.
SELECT ok(
  (SELECT pg_get_constraintdef(oid) !~* 'tax_detail|journal|invoice|receipt|vw_'
     FROM pg_constraint
    WHERE conrelid = 'ref_filing_export_column'::regclass
      AND pg_get_constraintdef(oid) ~ 'source_field'),
  'no export column may name a transaction or tax-ledger source');              -- 3

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The documents, and the artifacts read from them
--   SI : 100,000 net + 12,000 output VAT to an ordinary buyer
--   CS :  50,000 net +  6,000 output VAT to a withholding agent, CWT 500 @1%
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'cs', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '12600000-0000-0000-0000-0000000000c1',
    'branch_id',              '12600000-0000-0000-0000-0000000000d1',
    'date',                   '2026-03-09',
    'customer_id',            '12600000-0000-0000-0000-0000000000e2',
    'customer_name_snapshot', 'Top Withholding Agent Corp',
    'customer_tin_snapshot',  '444-555-666-00126'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',             'Counter sale',
    'quantity',                1,
    'unit_price',              50000,
    'revenue_account_id',      '12600000-0000-0000-0000-00000000a008',
    'vat_code_id',             (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code = 'WC158' AND is_active)
  )),
  0)->>'si_id')::uuid;

SELECT lives_ok(
  $$SELECT fn_generate_filing_artifact('12600000-0000-0000-0000-0000000000c1','2550Q',2026,1),
           fn_generate_filing_artifact('12600000-0000-0000-0000-0000000000c1','SAWT',2026,1)$$,
  'the quarter generates its VAT return and its alphalist');                     -- 4

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — An export is evidence, so a draft does not leave the system
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT * FROM fn_filing_artifact_export(
      '12600000-0000-0000-0000-0000000000c1','2550Q',2026,1,'csv')$$,
  '%still a draft and cannot be exported%',
  'a draft return is refused: an export is evidence of a settled figure');       -- 5

UPDATE filing_artifacts SET status = 'final'
 WHERE company_id = '12600000-0000-0000-0000-0000000000c1'
   AND period_year = 2026 AND period_number = 1;

SELECT throws_like(
  $$SELECT * FROM fn_filing_artifact_export(
      '12600000-0000-0000-0000-0000000000c1','2550Q',2026,1,'pdf')$$,
  '%Unsupported filing export format%',
  'an unsupported format is refused rather than guessed at');                    -- 6

SELECT throws_like(
  $$SELECT * FROM fn_filing_artifact_export(
      '12600000-0000-0000-0000-0000000000c1','2550Q',2026,1,'dat')$$,
  '%No dat export layout is registered%',
  'and a format the form has no layout for is refused, not silently empty');     -- 7

SELECT throws_like(
  $$SELECT * FROM fn_filing_artifact_export(
      '12600000-0000-0000-0000-0000000000c1','2550Q',2026,4,'csv')$$,
  '%Generate it first%',
  'a period with no artifact says so rather than exporting nothing');            -- 8

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — CSV, rendered through the shared export primitives
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12600000-0000-0000-0000-0000000000c1','2550Q',2026,1,'csv') WHERE line_number = 0),
  '"Tax Kind","VAT Code","Classification","Taxable Base","VAT Amount","Documents"',
  'row 0 is the header the registry declares, in its declared order');           -- 9

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12600000-0000-0000-0000-0000000000c1','2550Q',2026,1,'csv') WHERE line_number = 1),
  '"output_vat","VAT-12","regular","50000.00","6000.00","1"',
  'and the detail row carries the artifact line, decimals through fn_export_decimal'); -- 10

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_artifact_export(
     '12600000-0000-0000-0000-0000000000c1','2550Q',2026,1,'csv')),
  2, 'a CSV export is one header row plus one row per artifact line');           -- 11

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — DAT, the alphalist shape
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM fn_filing_artifact_export(
     '12600000-0000-0000-0000-0000000000c1','SAWT',2026,1,'dat')
    WHERE line_number = 0),
  0, 'a DAT file carries no header row');                                        -- 12

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12600000-0000-0000-0000-0000000000c1','SAWT',2026,1,'dat') WHERE line_number = 1),
  '44455566600126,Top Withholding Agent Corp,WC158,50000.00,500.00',
  'and its TIN is normalised through fn_export_dat_tin, not re-punctuated here'); -- 13

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12600000-0000-0000-0000-0000000000c1','SAWT',2026,1,'csv') WHERE line_number = 1),
  '"444-555-666-00126","Top Withholding Agent Corp","WC158","50000.00","500.00"',
  'the same artifact line renders differently per format, from one layout table'); -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — The claim this file exists for: the export is a consumer
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc !~* 'tax_detail_entries|journal_entry_lines|journal_entries|vw_[a-z_]*review|vw_slp_export|vw_cwt_summary|vw_ewt_summary|sales_invoice|receipts'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_filing_artifact_export'),
  'the exporter reads no transaction, tax-ledger or review source');             -- 15

SELECT ok(
  (SELECT p.prosrc ~ '\mfiling_artifact_lines\M' AND p.prosrc ~ '\mfiling_artifacts\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_filing_artifact_export'),
  'it reads the filing artifact and its lines, and that is its only source');    -- 16

SELECT ok(
  (SELECT bool_and(p.prosrc !~* 'SUM\s*\(|AVG\s*\(')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_filing_artifact_export'),
  'and it aggregates no figure: the artifact already stated every number');      -- 17

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — The governed evidence record points at the artifact itself
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'snap', fn_snapshot_filing_artifact_export(
  '12600000-0000-0000-0000-0000000000c1','SAWT',2026,1,'dat');

SELECT results_eq(
  $$SELECT source_table::text, snapshot_status::text, snapshot_version,
           report_type::text, source_row_count
      FROM report_snapshots WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')$$,
  $$VALUES ('filing_artifacts'::text, 'exported'::text, 1, 'SAWT'::text, 1)$$,
  'the snapshot records what was exported and from which table');                -- 18

SELECT is(
  (SELECT s.source_id FROM report_snapshots s WHERE s.id = (SELECT id FROM t_ctx WHERE key = 'snap')),
  (SELECT a.id FROM filing_artifacts a
    WHERE a.company_id = '12600000-0000-0000-0000-0000000000c1'
      AND a.form_code = 'SAWT' AND a.period_year = 2026 AND a.period_number = 1),
  'and it points at the artifact by its own id, not a synthesised key');         -- 19

SELECT is(
  (SELECT source_payload->>'content' FROM report_snapshots
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')),
  '44455566600126,Top Withholding Agent Corp,WC158,50000.00,500.00',
  'the evidence holds exactly the bytes that were exported');                    -- 20

SELECT is(
  (SELECT length(source_hash) FROM report_snapshots
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')),
  64, 'hashed for tamper evidence');                                             -- 21

SELECT is(
  (SELECT (report_payload->>'total_tax_amount')::numeric FROM report_snapshots
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')),
  500.00::numeric,
  'and it carries the artifact totals it was taken from');                       -- 22

-- Captured first: the generator is volatile, so calling it inside a WHERE over
-- the table it writes would scan a snapshot taken before its own insert.
INSERT INTO t_ctx
SELECT 'snap2', fn_snapshot_filing_artifact_export(
  '12600000-0000-0000-0000-0000000000c1','SAWT',2026,1,'dat');

SELECT is(
  (SELECT snapshot_version FROM report_snapshots
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap2')),
  2, 'exporting the same artifact again supersedes nothing and versions up');    -- 23

-- The claim the whole file exists for.
SELECT ok(
  (SELECT bool_and(s.source_table = 'filing_artifacts')
     FROM report_snapshots s
    WHERE s.company_id = '12600000-0000-0000-0000-0000000000c1'),
  'every compliance export this company produced came from a filing artifact');  -- 24

SELECT * FROM finish();
ROLLBACK;
