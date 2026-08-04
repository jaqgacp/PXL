-- ══════════════════════════════════════════════════════════════════════════════
-- 128 — The governed Reconciling Item, and the artifact's role gate
--        (Backlog 8f, stage 1)
--
-- WHAT THIS GUARDS
--   8f eliminates the second compliance architecture. It does **not** delete
--   functionality to get there: the six legacy `compliance_*` working-paper
--   screens provide exactly one real capability — keying a line that no ledger
--   backs — and this file proves that capability now exists inside the governed
--   pipeline before any legacy screen or table is retired.
--
--   The owner's rule for it (2026-08-04): a reconciling item is manual and
--   typed; excluded from tax calculation, from working-paper totals, from
--   filing-artifact totals and from GL reconciliation; it never creates a
--   journal entry and never changes a computed amount; it is visible as a note;
--   it is frozen once the artifact is finalised; and it records reason,
--   reference, amount, remarks, user and timestamp, fully audited.
--
--   The exclusions are asserted **structurally**, not as filters. A reconciling
--   item's amount lives in `reconciling_amount`, which no computation reads, and
--   a CHECK forces its tax figures to zero — so assertion 7 sums *every* line in
--   the table, including the note, and still ties to the artifact total.
--
--   It also covers the control regression found while scoping 8f: every
--   projection of an artifact (`vat_returns`, `pt_returns`, `ewt_returns`) and
--   all twelve legacy working papers gate final/filed behind owner/admin, and
--   `filing_artifacts` gated nothing.
--
--   The company and its documents are provisioned here through the current
--   production RPCs; it never reads the canonical/demo seed.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(30);

-- ── Fixture: a VAT-registered company, its owner, and one ordinary member
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000',
   '12800000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'reconciling-owner@test.local', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000',
   '12800000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'reconciling-member@test.local', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12800000-0000-0000-0000-0000000000c1', 'corporation', 'Reconciling Notes Corp',
        'Wholesale', '355-128-001-00000', 'vat', 'calendar',
        '128 Note St', '', 'Makati', 'Metro Manila', '1200',
        'reconciling-owner@test.local', 'Rita Nunez', 'President', auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES ('12800000-0000-0000-0000-000000000002',
        '12800000-0000-0000-0000-0000000000c1', 'member', auth.uid())
ON CONFLICT (user_id, company_id) DO UPDATE SET role = 'member';

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12800000-0000-0000-0000-0000000000d1', '12800000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', '128 Note St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12800000-0000-0000-0000-0000000000f1', '12800000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12800000-0000-0000-0000-0000000000c1', '12800000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12800000-0000-0000-0000-00000000a001', '12800000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a002', '12800000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a003', '12800000-0000-0000-0000-0000000000c1', '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a004', '12800000-0000-0000-0000-0000000000c1', '1400', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a005', '12800000-0000-0000-0000-0000000000c1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a006', '12800000-0000-0000-0000-0000000000c1', '2000', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a007', '12800000-0000-0000-0000-0000000000c1', '2210', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12800000-0000-0000-0000-00000000a008', '12800000-0000-0000-0000-0000000000c1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('12800000-0000-0000-0000-0000000000c1',
        '12800000-0000-0000-0000-00000000a002', '12800000-0000-0000-0000-00000000a006',
        '12800000-0000-0000-0000-00000000a005', '12800000-0000-0000-0000-00000000a004',
        '12800000-0000-0000-0000-00000000a003', '12800000-0000-0000-0000-00000000a007',
        '12800000-0000-0000-0000-00000000a001', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, vat_registered, vat_filing_frequency,
                                 percentage_tax_registered, ewt_registered,
                                 created_by, updated_by)
VALUES ('12800000-0000-0000-0000-0000000000c1', true, 'quarterly', false, true,
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12800000-0000-0000-0000-0000000000c1', '12800000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-128-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS', 'SI', 'VB');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('12800000-0000-0000-0000-0000000000e1', '12800000-0000-0000-0000-0000000000c1',
        'CUST-A', 'Ordinary Buyer Inc', '111-222-333-128', 'Pasig', 'Pasig',
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- One posted sale: 100,000 net + 12,000 output VAT.
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '12800000-0000-0000-0000-0000000000c1',
    'branch_id',                 '12800000-0000-0000-0000-0000000000d1',
    'date',                      '2026-02-11',
    'customer_id',               '12800000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot',    'Ordinary Buyer Inc',
    'customer_tin_snapshot',     '111-222-333-128',
    'customer_address_snapshot', 'Pasig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Wholesale goods',
    'quantity',           1,
    'unit_price',         100000,
    'revenue_account_id', '12800000-0000-0000-0000-00000000a008',
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

INSERT INTO t_ctx
SELECT '2550q', (fn_generate_filing_artifact(
  '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)->>'artifact_id')::uuid;

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — The capability exists, and only through the governed path
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM pg_policy
    WHERE polrelid = 'filing_artifact_lines'::regclass AND polcmd IN ('a','w','d')),
  0,
  'a working-paper line cannot be written from a browser: the table has read policies only'); -- 1

SELECT throws_like(
  $$SELECT fn_add_filing_reconciling_item('12800000-0000-0000-0000-0000000000c1',
      '2550Q', 2026, 1, 'Timing difference', '', 1500.00, 'Per BIR ruling')$$,
  '%must record a reason, a reference, an amount and remarks%',
  'an item without its full record is refused: evidence without provenance is not evidence'); -- 2

SELECT throws_like(
  $$SELECT fn_add_filing_reconciling_item('12800000-0000-0000-0000-0000000000c1',
      '2550Q', 2026, 4, 'Timing difference', 'MEMO-1', 1500.00, 'Per BIR ruling')$$,
  '%No 2550Q artifact exists%',
  'and one cannot be recorded against a working paper that does not exist');        -- 3

INSERT INTO t_ctx
SELECT 'item', fn_add_filing_reconciling_item(
  '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1,
  'Timing difference on export documentation',
  'MEMO-2026-001', 1500.00,
  'Zero-rating support received after the quarter closed; declared next quarter.');

SELECT results_eq(
  $$SELECT line_number, reason::text, reference::text, amount, remarks::text
      FROM fn_filing_reconciling_items('12800000-0000-0000-0000-0000000000c1',
             '2550Q', 2026, 1)$$,
  $$VALUES (1, 'Timing difference on export documentation'::text,
            'MEMO-2026-001'::text, 1500.00::numeric,
            'Zero-rating support received after the quarter closed; declared next quarter.'::text)$$,
  'a recorded item carries its reason, reference, amount and remarks');             -- 4

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_reconciling_items(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)
    WHERE created_by = '12800000-0000-0000-0000-000000000001' AND created_at IS NOT NULL),
  1, 'and the user and timestamp that recorded it');                                -- 5

SELECT is(
  (SELECT count(*)::integer FROM sys_audit_logs
    WHERE table_name = 'filing_artifact_lines'
      AND record_id = (SELECT id FROM t_ctx WHERE key = 'item')
      AND action = 'INSERT'),
  1, 'fully audited, through the same audit trigger every governed table uses');    -- 6

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — It explains a difference. It never becomes one.
--
--   These assertions deliberately do NOT filter by line_kind: the exclusion is
--   structural, so a total that knows nothing about reconciling items is still
--   correct in their presence.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT total_tax_amount FROM filing_artifacts
    WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  12000.00::numeric,
  'the artifact total is what the ledger said before the note, and after it');      -- 7

SELECT is(
  (SELECT SUM(tax_amount) FROM filing_artifact_lines
    WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  (SELECT total_tax_amount FROM filing_artifacts
    WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  'every line in the working paper still sums to the artifact total');              -- 8

SELECT is(
  (SELECT SUM(tax_base) FROM filing_artifact_lines
    WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')),
  100000.00::numeric,
  'and so does its base: a reconciling item carries neither');                      -- 9

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_reconciliation(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)
    WHERE NOT is_reconciled),
  0, 'the ledger still ties to the General Ledger at zero variance');               -- 10

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_working_paper(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)),
  1, 'the working-paper reader returns the ledger only; a note is not a source');   -- 11

SELECT is(
  (SELECT count(*)::integer FROM journal_entries
    WHERE company_id = '12800000-0000-0000-0000-0000000000c1'),
  1, 'and no journal entry was created: the sale posted one, the note posted none'); -- 12

SELECT throws_like(
  $$UPDATE filing_artifact_lines SET tax_amount = 1500.00
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'item')$$,
  '%filing_artifact_lines_kind_shape_chk%',
  'a reconciling item may not acquire a tax figure — the schema forbids it');       -- 13

SELECT throws_like(
  $$UPDATE filing_artifact_lines SET line_kind = 'generated'
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'item')$$,
  '%cannot change kind%',
  'and it may not become a generated figure by changing its own kind');             -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Regeneration restates the figures and keeps the explanation
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM fn_filing_reconciling_items(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)),
  1, 'regenerating the artifact leaves the accountant''s note in place')
FROM (SELECT fn_generate_filing_artifact(
        '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)) g;               -- 15

SELECT is(
  (SELECT count(*)::integer FROM filing_artifact_lines
    WHERE artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')
      AND line_kind = 'generated'),
  1, 'and restates the ledger side exactly once, not twice');                       -- 16

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — The role gate the artifact never had
--
--   pt_returns, vat_returns, ewt_returns and all twelve legacy working papers
--   restrict final/filed to owner/admin. filing_artifacts restricted nothing.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT set_config('request.jwt.claims',
  '{"sub":"12800000-0000-0000-0000-000000000002","role":"authenticated"}', true);

SELECT throws_like(
  $$UPDATE filing_artifacts SET status = 'final'
     WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  '%owner/admin role required%',
  'an ordinary member cannot declare a return final');                              -- 17

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_reconciling_items(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1)),
  1, 'though a member may still read the working paper they work on');              -- 18

SELECT lives_ok(
  $$SELECT fn_add_filing_reconciling_item('12800000-0000-0000-0000-0000000000c1',
      '2550Q', 2026, 1, 'Second look', 'MEMO-2026-002', 250.00,
      'Recorded by a preparer, not an approver.')$$,
  'and may record a reconciling item: preparing evidence is not approving it');     -- 19

SELECT set_config('request.jwt.claims',
  '{"sub":"12800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

SELECT lives_ok(
  $$SELECT fn_delete_filing_reconciling_item(
      (SELECT l.id FROM filing_artifact_lines l
        WHERE l.artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')
          AND l.reference = 'MEMO-2026-002'))$$,
  'a draft note can be withdrawn');                                                 -- 20

SELECT throws_like(
  $$SELECT fn_delete_filing_reconciling_item(
      (SELECT l.id FROM filing_artifact_lines l
        WHERE l.artifact_id = (SELECT id FROM t_ctx WHERE key = '2550q')
          AND l.line_kind = 'generated' LIMIT 1))$$,
  '%generated working-paper line is not deletable%',
  'a generated figure cannot be deleted through the note path');                    -- 21

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — Frozen when the artifact settles
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok(
  $$UPDATE filing_artifacts SET status = 'final'
     WHERE id = (SELECT id FROM t_ctx WHERE key = '2550q')$$,
  'an owner may declare the same return final');                                    -- 22

SELECT throws_like(
  $$SELECT fn_add_filing_reconciling_item('12800000-0000-0000-0000-0000000000c1',
      '2550Q', 2026, 1, 'Late thought', 'MEMO-2026-003', 10.00, 'Too late')$$,
  '%reconciling items are frozen%',
  'after which no note may be added');                                              -- 23

SELECT throws_like(
  $$SELECT fn_delete_filing_reconciling_item((SELECT id FROM t_ctx WHERE key = 'item'))$$,
  '%frozen%',
  'and none may be withdrawn: the working paper settles with the return');          -- 24

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — Visible as a note, and only as a note
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM fn_filing_artifact_export(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1, 'csv')),
  3, 'the CSV export is one header, one generated row and one note');               -- 25

SELECT is(
  (SELECT content FROM fn_filing_artifact_export(
     '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1, 'csv')
    WHERE line_number > 1000),
  '"RECONCILING ITEM","Timing difference on export documentation","MEMO-2026-001","1500.00","Zero-rating support received after the quarter closed; declared next quarter."',
  'the note travels with the figures it explains, marked as what it is');           -- 26

-- The SLSP is the alphalist the Bureau ingests as a DAT file, so it is the
-- honest place to prove a note never reaches one.
SELECT fn_generate_filing_artifact('12800000-0000-0000-0000-0000000000c1', 'SLSP', 2026, 1);
SELECT fn_add_filing_reconciling_item(
  '12800000-0000-0000-0000-0000000000c1', 'SLSP', 2026, 1,
  'Counterparty TIN pending', 'MEMO-2026-004', 0.00,
  'Buyer has not supplied its TIN; listed as recorded.');
UPDATE filing_artifacts SET status = 'final'
 WHERE company_id = '12800000-0000-0000-0000-0000000000c1'
   AND form_code = 'SLSP' AND period_year = 2026 AND period_number = 1;

SELECT is(
  (SELECT count(*)::integer FROM fn_filing_artifact_export(
     '12800000-0000-0000-0000-0000000000c1', 'SLSP', 2026, 1, 'dat')
    WHERE line_number > 1000),
  0, 'a DAT alphalist carries no note: the Bureau ingests it and a note corrupts it'); -- 27

INSERT INTO t_ctx
SELECT 'snap', fn_snapshot_filing_artifact_export(
  '12800000-0000-0000-0000-0000000000c1', '2550Q', 2026, 1, 'csv');

SELECT is(
  (SELECT source_payload->>'content' FROM report_snapshots
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'snap')),
  (SELECT string_agg(e.content, E'\n' ORDER BY e.line_number)
     FROM fn_filing_artifact_export('12800000-0000-0000-0000-0000000000c1',
            '2550Q', 2026, 1, 'csv') e),
  'and the evidence row holds exactly the bytes that were exported, note included'); -- 28

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — The claim the file exists for
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc !~ 'reconciling_amount'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_tax_ledger_gl_reconciliation'),
  'the one reconciliation cannot see a reconciling item at all');                   -- 29

SELECT is(
  (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc ~ 'reconciling_amount'
      AND p.proname NOT IN ('fn_add_filing_reconciling_item',
                            'fn_delete_filing_reconciling_item',
                            'fn_filing_reconciling_items',
                            'fn_filing_artifact_export')),
  0,
  'and no other function in PXL reads the column a reconciling item states its amount in'); -- 30

SELECT * FROM finish();
ROLLBACK;
