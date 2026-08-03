-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P51-002 — Stage 2, Module 2 (memo posters: line persistence)
--
-- Stage 1 moved the CM / DM / VC header INSERTs into the sanctioned kernel. This
-- stage moves their nine direct `journal_entry_lines` INSERTs into the sanctioned
-- persistence helper, so the memo module now touches neither ledger table
-- directly. Certified here:
--   A. the module is fully migrated, structurally and behaviourally;
--   B. the guard classifies it as kernel-origin on BOTH tables (violation delta
--      to zero for all three writers);
--   C. accounting output — header, lines, ordering, line_role, tax detail,
--      dimensions, document status, audit — is unchanged;
--   D. the guard remains OBSERVE-ONLY and the phase boundary holds.
--
-- WHY THE PUSH HELPER: the memo lines carry `line_role`, which fn_add_posting_line
-- cannot express; and fn_add_posting_line would additionally impose
-- `fn_require_postable_account` plus a debit/credit-exclusivity check that the raw
-- INSERTs never performed — two new rejection paths, i.e. a validation change.
-- fn_add_posting_line_push performs the same single INSERT, so behaviour is
-- preserved exactly. Assertions 6-7 pin that reasoning.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(28);

CREATE TEMP VIEW v_memo_writer AS
SELECT unnest(ARRAY['fn_post_credit_memo_vat_lump_impl',
                    'fn_post_debit_memo_vat_lump_impl',
                    'fn_post_vendor_credit_vat_lump_impl']) AS proname;

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — The module is fully migrated (structural)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM v_memo_writer w
     JOIN pg_proc p ON p.proname = w.proname
     JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'INSERT INTO\s+journal_entr'),
  0, 'no memo writer touches journal_entries or journal_entry_lines directly');       -- 1

SELECT is(
  (SELECT count(*)::int FROM v_memo_writer w
     JOIN pg_proc p ON p.proname = w.proname
     JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'),
  3, 'all three memo writers use the kernel for the header and the helper for lines'); -- 2

SELECT is(
  (SELECT (SELECT count(*)::int FROM regexp_matches(p.prosrc, 'fn_add_posting_line_push', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_credit_memo_vat_lump_impl'),
  5, 'the Credit Memo poster persists its five lines through the helper');            -- 3

-- The helper is now sanctioned, and remains unreachable by any client role.
SELECT ok(
  (SELECT p.prosrc ~ 'fn_add_posting_line_push'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'the push helper is part of the sanctioned kernel set');                            -- 4

SELECT ok(
  NOT has_function_privilege('authenticated',
    'public.fn_add_posting_line_push(uuid,integer,uuid,text,numeric,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon',
    'public.fn_add_posting_line_push(uuid,integer,uuid,text,numeric,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'the push helper is callable by no client role (P5.0 posture preserved)');           -- 5

-- Validation parity: the chosen helper adds no rejection path the raw INSERT lacked.
SELECT ok(
  (SELECT p.prosrc !~ 'fn_require_postable_account'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line_push'),
  'the push helper imposes no account validation the replaced INSERT did not');        -- 6

SELECT ok(
  (SELECT p.prosrc ~ 'fn_require_postable_account'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  'and the alternative helper does — which is why it was NOT used (non-vacuous choice)'); -- 7

-- ══════════════════════════════════════════════════════════════════════════════
-- Fixture
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f520000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p52-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f520000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f520000-0000-0000-0000-0000000000b1', 'corporation', 'P52 Memo Corp',
        'Trading', '387-000-001-00000', 'vat', 'calendar',
        'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200',
        'p52-owner@test.local', 'M Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f520000-0000-0000-0000-0000000000b2', '0f520000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f520000-0000-0000-0000-0000000000f1', '0f520000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '0f520000-0000-0000-0000-0000000000b1', '0f520000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f520000-0000-0000-0000-0000000000a1', '0f520000-0000-0000-0000-0000000000b1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f520000-0000-0000-0000-0000000000a2', '0f520000-0000-0000-0000-0000000000b1', '2010', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f520000-0000-0000-0000-0000000000a3', '0f520000-0000-0000-0000-0000000000b1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f520000-0000-0000-0000-0000000000a4', '0f520000-0000-0000-0000-0000000000b1', '1300', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f520000-0000-0000-0000-0000000000a5', '0f520000-0000-0000-0000-0000000000b1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('0f520000-0000-0000-0000-0000000000a6', '0f520000-0000-0000-0000-0000000000b1', '5010', 'Operating Expense',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, created_by, updated_by)
VALUES ('0f520000-0000-0000-0000-0000000000b1',
        '0f520000-0000-0000-0000-0000000000a1', '0f520000-0000-0000-0000-0000000000a2',
        '0f520000-0000-0000-0000-0000000000a3', '0f520000-0000-0000-0000-0000000000a4',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f520000-0000-0000-0000-0000000000b1', '0f520000-0000-0000-0000-0000000000b2',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('CM','DM-S','VC');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('0f520000-0000-0000-0000-0000000000c1', '0f520000-0000-0000-0000-0000000000b1', 'CUST-P52',
        'P52 Customer Inc', '386-000-001-00000', 'Customer HQ', 'Customer HQ', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('0f520000-0000-0000-0000-0000000000d1', '0f520000-0000-0000-0000-0000000000b1', 'SUPP-P52',
        'P52 Supplier Corp', '385-000-001-00000', 'Supplier HQ', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
CREATE TEMP TABLE t_pre AS
SELECT (SELECT count(*) FROM sys_posting_guard_violations) AS viol,
       (SELECT coalesce(sum(next_number),0) FROM number_series
         WHERE company_id='0f520000-0000-0000-0000-0000000000b1') AS series;

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — Accounting output unchanged (behavioural)
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object('company_id','0f520000-0000-0000-0000-0000000000b1',
    'branch_id','0f520000-0000-0000-0000-0000000000b2',
    'customer_id','0f520000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P52 Customer Inc','customer_tin_snapshot','386-000-001-00000',
    'cm_date','2026-04-12',
    'reason_code_id',(SELECT id FROM ref_reason_codes
                       WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1)),
  jsonb_build_array(jsonb_build_object('description','Returned goods','quantity',2,'unit_price',1500,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f520000-0000-0000-0000-0000000000a5')),
  'draft');
SELECT lives_ok($$SELECT fn_post_credit_memo((SELECT id FROM t_ctx WHERE key='cm'))$$,
  'the fully migrated Credit Memo poster posts');                                      -- 8

SELECT results_eq(
  $q$SELECT je.status, je.total_debit, je.total_credit, je.posting_origin, je.entry_class,
            je.auto_reverse, je.reference_doc_type, je.je_number
       FROM journal_entries je
      WHERE je.id=(SELECT journal_entry_id FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm'))$q$,
  $$VALUES ('posted'::text, 3360.00::numeric, 3360.00::numeric, 'system'::text,
            'regular'::text, false, 'CM'::text, 'JE-CM-CM-000001'::text)$$,
  'CM header unchanged, including source-derived numbering');                          -- 9

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount,
            jel.line_role, jel.description
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id=jel.account_id
      WHERE jel.je_id=(SELECT journal_entry_id FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '4010'::text, 3000.00::numeric, 0.00::numeric, 'base'::text,    'Sales return — Returned goods'::text),
           (2, '2100'::text,  360.00::numeric, 0.00::numeric, 'tax'::text,     'Output VAT reversal — CM-000001'::text),
           (3, '1200'::text,    0.00::numeric, 3360.00::numeric, 'control'::text, 'AR — P52 Customer Inc'::text)$$,
  'CM lines unchanged: order, accounts, amounts, line_role, descriptions');            -- 10

-- Dimensions are unchanged: the certified Dimension Engine guard
-- (fn_je_line_dimensions_guard) defaults a NULL line branch from the journal header
-- on INSERT, and it fires identically for the helper and for the raw INSERT it
-- replaced. The memo writers supply no analytical dimensions, before or after.
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id=(SELECT journal_entry_id FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm'))
      AND branch_id = '0f520000-0000-0000-0000-0000000000b2'
      AND department_id IS NULL AND cost_center_id IS NULL AND project_id IS NULL
      AND location_id IS NULL AND functional_entity_id IS NULL),
  3, 'CM lines inherit the header branch and carry no analytical dimensions — unchanged'); -- 11

SELECT results_eq(
  $q$SELECT tax_kind, tax_base, tax_amount, is_reversal FROM tax_detail_entries
      WHERE source_doc_type='CM' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='cm')$q$,
  $$VALUES ('output_vat'::text, -3000.00::numeric, -360.00::numeric, true)$$,
  'CM tax detail unchanged');                                                          -- 12

SELECT is((SELECT status FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm')),
  'applied', 'CM document lifecycle unchanged');                                       -- 13

INSERT INTO t_ctx
SELECT 'dm', fn_save_debit_memo(NULL,
  jsonb_build_object('company_id','0f520000-0000-0000-0000-0000000000b1',
    'branch_id','0f520000-0000-0000-0000-0000000000b2',
    'customer_id','0f520000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P52 Customer Inc','customer_tin_snapshot','386-000-001-00000',
    'dm_date','2026-04-13',
    'reason_code_id',(SELECT id FROM ref_reason_codes
                       WHERE applies_to IN ('debit_memo','both') ORDER BY id LIMIT 1)),
  jsonb_build_array(jsonb_build_object('description','Freight','amount',800,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'account_id','0f520000-0000-0000-0000-0000000000a5')),
  'draft');
SELECT lives_ok($$SELECT fn_post_debit_memo((SELECT id FROM t_ctx WHERE key='dm'))$$,
  'the fully migrated Debit Memo poster posts');                                       -- 14

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount,
            jel.line_role, jel.description
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id=jel.account_id
      WHERE jel.je_id=(SELECT journal_entry_id FROM debit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='dm'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '1200'::text, 896.00::numeric, 0.00::numeric, 'control'::text, 'AR — P52 Customer Inc'::text),
           (2, '4010'::text,   0.00::numeric, 800.00::numeric, 'base'::text,  'DM charge — Freight'::text),
           (3, '2100'::text,   0.00::numeric,  96.00::numeric, 'tax'::text,   'Output VAT — DM-S-000001'::text)$$,
  'DM lines unchanged: control line first, then base, then tax');                      -- 15

SELECT results_eq(
  $q$SELECT je.status, je.total_debit, je.total_credit, je.posting_origin
       FROM journal_entries je
      WHERE je.id=(SELECT journal_entry_id FROM debit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='dm'))$q$,
  $$VALUES ('posted'::text, 896.00::numeric, 896.00::numeric, 'system'::text)$$,
  'DM header unchanged');                                                              -- 16

SELECT results_eq(
  $q$SELECT tax_kind, tax_amount, is_reversal FROM tax_detail_entries
      WHERE source_doc_type='DM' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='dm')$q$,
  $$VALUES ('output_vat'::text, 96.00::numeric, false)$$,
  'DM tax detail unchanged');                                                          -- 17

INSERT INTO t_ctx
SELECT 'vc', fn_save_vendor_credit(NULL,
  jsonb_build_object('company_id','0f520000-0000-0000-0000-0000000000b1',
    'branch_id','0f520000-0000-0000-0000-0000000000b2',
    'supplier_id','0f520000-0000-0000-0000-0000000000d1',
    'supplier_name_snapshot','P52 Supplier Corp','supplier_tin_snapshot','385-000-001-00000',
    'credit_date','2026-04-14'),
  jsonb_build_array(jsonb_build_object('description','Returned supplies','quantity',1,'unit_price',1200,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f520000-0000-0000-0000-0000000000a6')));
SELECT lives_ok($$SELECT fn_post_vendor_credit((SELECT id FROM t_ctx WHERE key='vc'))$$,
  'the fully migrated Vendor Credit poster posts');                                    -- 18

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount,
            jel.line_role, jel.description
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id=jel.account_id
      WHERE jel.je_id=(SELECT journal_entry_id FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '2010'::text, 1344.00::numeric,    0.00::numeric, 'control'::text, 'AP — P52 Supplier Corp'::text),
           (2, '5010'::text,    0.00::numeric, 1200.00::numeric, 'base'::text,    'Credit reversal — Returned supplies'::text),
           (3, '1300'::text,    0.00::numeric,  144.00::numeric, 'tax'::text,     'Input VAT reversal — VC-000001'::text)$$,
  'VC lines unchanged: order, accounts, amounts, line_role, descriptions');            -- 19

SELECT results_eq(
  $q$SELECT je.status, je.total_debit, je.total_credit, je.posting_origin
       FROM journal_entries je
      WHERE je.id=(SELECT journal_entry_id FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc'))$q$,
  $$VALUES ('posted'::text, 1344.00::numeric, 1344.00::numeric, 'system'::text)$$,
  'VC header unchanged');                                                              -- 20

SELECT is((SELECT status FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc')),
  'open', 'VC document lifecycle unchanged');                                          -- 21

-- Numbering: three documents consumed exactly three series numbers.
SELECT is(
  (SELECT coalesce(sum(next_number),0) FROM number_series
    WHERE company_id='0f520000-0000-0000-0000-0000000000b1'),
  (SELECT series + 3 FROM t_pre), 'numbering is unchanged — three documents, three numbers'); -- 22

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Audit equality
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs a
    WHERE a.table_name='journal_entries' AND a.action='INSERT'
      AND a.record_id IN (
        (SELECT journal_entry_id FROM credit_memos   WHERE id=(SELECT id FROM t_ctx WHERE key='cm')),
        (SELECT journal_entry_id FROM debit_memos    WHERE id=(SELECT id FROM t_ctx WHERE key='dm')),
        (SELECT journal_entry_id FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc')))),
  3, 'each migrated journal header is audited exactly once');                          -- 23

-- Line-level audit: `journal_entry_lines` carries NO fn_audit_trigger. That is the
-- pre-existing certified state (the Audit Engine covers 79 tables; journal lines are
-- covered by the posted-document immutability guards instead), so moving the nine
-- line INSERTs into the helper could not change line audit coverage either way.
-- Pinned here so the absence reads as a known fact rather than a regression.
SELECT is(
  (SELECT count(*)::int FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE NOT t.tgisinternal AND t.tgrelid='journal_entry_lines'::regclass
      AND p.proname='fn_audit_trigger'),
  0, 'journal lines carry no audit trigger — line audit coverage is unchanged by construction'); -- 24

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Violation delta and phase boundary
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN ('fn_post_credit_memo_vat_lump_impl',
                              'fn_post_debit_memo_vat_lump_impl',
                              'fn_post_vendor_credit_vat_lump_impl')),
  0, 'the memo module produces ZERO violations on either ledger table');               -- 25

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations),
  (SELECT viol FROM t_pre)::int,
  'posting three memo documents added no violation at all — the module is drained');   -- 26

-- P5.2 subsequently arms the same guard without changing this stage's writers.
SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the unchanged Kernel Totality Guard');                -- 27

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosrc ~ 'INSERT INTO\s+journal_entries'
      AND p.proname <> 'fn_create_posted_journal_entry'),
  0, 'later approved P5.1 stages drain every remaining forward header insert');        -- 28

SELECT * FROM finish();
ROLLBACK;
