-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P3C-001 — Manual Journal Control (frozen P3 spec §6, objective O-D)
--
-- Certifies that the COA Posting Control Contract (PXL_COA_ENGINE_SPEC.md §5) is now
-- enforced at manual-JE posting: `fn_assert_manual_postable`, delivered dormant by COA
-- Phase A with zero runtime callers, is wired into `fn_post_manual_je`.
--
-- NON-VACUOUS BY CONSTRUCTION. The canonical dataset contains zero control accounts, so
-- a canonical-only assertion would prove nothing. This file builds a dedicated fixture
-- that flags a genuine control account, proves the manual-JE post is REJECTED, then
-- clears the flag and proves the identical post SUCCEEDS — so the guard is shown to
-- protect something real, and the rejection is shown to be caused by the control flag
-- and nothing else.
--
-- Valid manual journals are proven byte-for-byte unchanged: every pre-P3C rejection
-- keeps its exact message, and a representative spread (regular / adjusting / opening /
-- auto-reverse / dimensioned / multi-line / null-branch) posts with identical numbering,
-- metadata, line order, amounts, and all six dimensions.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(30);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Wiring is real (structural)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc ~ 'fn_assert_manual_postable\s*\(' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'fn_post_manual_je calls fn_assert_manual_postable');                                -- 1

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  1, 'fn_post_manual_je still has exactly one signature (no overload introduced)');     -- 2

-- Validation order: the new call must sit AFTER the existing is_active check so every
-- pre-P3C rejection keeps its message.
SELECT ok(
  (SELECT strpos(p.prosrc, 'is inactive') < strpos(p.prosrc, 'fn_assert_manual_postable')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'the control assertion runs after the existing account checks (validation order preserved)'); -- 3

SELECT ok(
  (SELECT p.prosrc ~ 'fn_assert_manual_postable\s*\(\s*v_account_id\s*,\s*p_je_date\s*\)'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'effective dating is evaluated at the journal date, not wall-clock time');            -- 4

-- ══════════════════════════════════════════════════════════════════════════════
-- Fixture
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f3c0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p3c-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f3c0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f3c0000-0000-0000-0000-0000000000b1', 'corporation', 'P3C Manual Control Corp',
        'Services', '396-000-001-00000', 'vat', 'calendar',
        'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200',
        'p3c-owner@test.local', 'M Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f3c0000-0000-0000-0000-0000000000b2', '0f3c0000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO departments (id, company_id, department_code, department_name, created_by, updated_by)
VALUES ('0f3c0000-0000-0000-0000-0000000000d1', '0f3c0000-0000-0000-0000-0000000000b1', 'FIN', 'Finance', auth.uid(), auth.uid());
INSERT INTO cost_centers (id, company_id, cost_center_code, cost_center_name, created_by, updated_by)
VALUES ('0f3c0000-0000-0000-0000-0000000000d2', '0f3c0000-0000-0000-0000-0000000000b1', 'CC-1', 'Admin CC', auth.uid(), auth.uid());
INSERT INTO projects (id, company_id, branch_id, project_code, project_name)
VALUES ('0f3c0000-0000-0000-0000-0000000000d3', '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2', 'PRJ-1', 'Control Project');
INSERT INTO locations (id, company_id, location_code, location_name)
VALUES ('0f3c0000-0000-0000-0000-0000000000d4', '0f3c0000-0000-0000-0000-0000000000b1', 'LOC-1', 'Control Site');
INSERT INTO functional_entities (id, company_id, entity_code, entity_name)
VALUES ('0f3c0000-0000-0000-0000-0000000000d5', '0f3c0000-0000-0000-0000-0000000000b1', 'FE-1', 'Control Segment');

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f3c0000-0000-0000-0000-0000000000f1', '0f3c0000-0000-0000-0000-0000000000b1', 'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name, start_date, end_date, is_locked)
SELECT '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f3c0000-0000-0000-0000-0000000000a1', '0f3c0000-0000-0000-0000-0000000000b1', '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('0f3c0000-0000-0000-0000-0000000000a2', '0f3c0000-0000-0000-0000-0000000000b1', '5010', 'Supplies Expense', 'expense', 'debit', true, true, auth.uid(), auth.uid()),
  ('0f3c0000-0000-0000-0000-0000000000a3', '0f3c0000-0000-0000-0000-0000000000b1', '2010', 'Accrued Liabilities', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  -- Account inactive from creation, used to prove validation ORDER in Section E.
  ('0f3c0000-0000-0000-0000-0000000000a6', '0f3c0000-0000-0000-0000-0000000000b1', '1090', 'Dormant Cash', 'asset', 'debit', true, false, auth.uid(), auth.uid());

-- ── The attribution pair ───────────────────────────────────────────────────────
-- Two accounts identical in every posting-relevant attribute — type, normal balance,
-- postable, active, leaf, no effective dating — differing ONLY in is_control_account.
-- `fn_coa_change_policy_guard` makes is_control_account immutable once an account has
-- posted history, so the flag is set at creation rather than toggled; the pair is what
-- proves the rejection is caused by the flag and nothing else.
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               is_control_account, allow_subledger, subledger_type,
                               created_by, updated_by)
VALUES
  ('0f3c0000-0000-0000-0000-0000000000a4', '0f3c0000-0000-0000-0000-0000000000b1', '1200', 'Accounts Receivable (control)',
   'asset', 'debit', true, true, true,  true, 'receivable', auth.uid(), auth.uid()),
  ('0f3c0000-0000-0000-0000-0000000000a5', '0f3c0000-0000-0000-0000-0000000000b1', '1205', 'Receivable Shadow (not control)',
   'asset', 'debit', true, true, false, false, NULL, auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — NON-VACUITY: the guard rejects a real control account, and the flag
-- is the sole cause (same posting succeeds once the flag is cleared)
-- ══════════════════════════════════════════════════════════════════════════════

SELECT ok((SELECT is_control_account FROM chart_of_accounts WHERE id='0f3c0000-0000-0000-0000-0000000000a4'),
  'fixture created a genuine control account (guard has something to protect)');         -- 5

-- The pair differs ONLY in is_control_account; everything the validator inspects is equal.
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts a, chart_of_accounts b
    WHERE a.id='0f3c0000-0000-0000-0000-0000000000a4' AND b.id='0f3c0000-0000-0000-0000-0000000000a5'
      AND a.account_type = b.account_type AND a.normal_balance = b.normal_balance
      AND a.is_postable = b.is_postable AND a.is_active = b.is_active
      AND a.lifecycle_status = b.lifecycle_status
      AND a.effective_from IS NOT DISTINCT FROM b.effective_from
      AND a.effective_to   IS NOT DISTINCT FROM b.effective_to
      AND fn_account_is_leaf(a.id) AND fn_account_is_leaf(b.id)
      AND a.is_control_account <> b.is_control_account),
  1, 'the attribution pair is identical except for is_control_account');                 -- 6

-- The unflagged twin accepts the posting, so the rejection below is attributable to the
-- control flag alone.
SELECT lives_ok(
  $$SELECT fn_post_manual_je(
      '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
      '2026-02-10', 'Same posting against the non-control twin', NULL, false,
      jsonb_build_array(
        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a5','debit_amount',300),
        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',300)))$$,
  'the identical posting succeeds against the non-control twin');                        -- 7

SELECT throws_like(
  $$SELECT fn_post_manual_je(
      '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
      '2026-02-11', 'Illegitimate manual touch of the AR control account', NULL, false,
      jsonb_build_array(
        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a4','debit_amount',300),
        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',300)))$$,
  '%control account % may not be posted by a manual journal%',
  'a manual JE debiting a control account is rejected');                                 -- 8

SELECT throws_like(
  $$SELECT fn_post_manual_je(
      '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
      '2026-02-11', 'Control account on the credit side', NULL, false,
      jsonb_build_array(
        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',300),
        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a4','credit_amount',300)))$$,
  '%must originate from the owning subledger%',
  'a manual JE crediting a control account is rejected, whichever line it sits on');     -- 9

-- Fail-closed: nothing is persisted by a rejected posting.
SELECT is(
  (SELECT count(*)::int FROM journal_entries
    WHERE company_id='0f3c0000-0000-0000-0000-0000000000b1' AND je_date='2026-02-11'),
  0, 'a rejected manual JE persists no journal header');                                 -- 10
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines jel
    WHERE jel.account_id='0f3c0000-0000-0000-0000-0000000000a4'),
  0, 'a rejected manual JE persists no journal line on the control account');            -- 11

-- Scope: the control is manual-JE-specific. No subledger/posting writer consults it, so
-- control-account movement originating from its owning subledger remains permitted.
SELECT is(
  (SELECT coalesce(string_agg(p.proname, ','), '(none)')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosrc ~ 'fn_assert_manual_postable\s*\('
      AND p.proname <> 'fn_assert_manual_postable'),
  'fn_post_manual_je',
  'only the manual-JE writer consults the control — subledger writers are unaffected');  -- 12

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — The other predicates of the validator are inert on certified data
-- (so the ONLY live behavior change is control-account rejection)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is((SELECT count(*)::int FROM chart_of_accounts c WHERE c.is_postable AND NOT fn_account_is_leaf(c.id)),
  0, 'no postable account has children — the leaf predicate adds no rejection');          -- 13
SELECT is((SELECT count(*)::int FROM chart_of_accounts WHERE effective_from IS NOT NULL OR effective_to IS NOT NULL),
  0, 'no account is effective-dated — the effective-window predicate adds no rejection'); -- 14
SELECT is((SELECT count(*)::int FROM chart_of_accounts WHERE lifecycle_status <> 'active' AND is_active),
  0, 'lifecycle_status and is_active never diverge — the lifecycle predicate adds no rejection'); -- 15

-- Replay: the wired validator rejects none of the journal lines already on this database.
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
    WHERE NOT fn_is_account_postable(jel.account_id, je.je_date)),
  0, 'replaying the validator over every existing journal line rejects nothing');         -- 16

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Valid manual journals are byte-for-byte unchanged
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx SELECT 'mje1', fn_post_manual_je(
  '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
  '2026-03-10', 'Supplies accrual', NULL, false,
  jsonb_build_array(
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',1500,'description','Supplies'),
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',1500,'description','Accrual')));

INSERT INTO t_ctx SELECT 'mje2', fn_post_manual_je(
  '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
  '2026-03-11', 'Dimensioned manual JE', NULL, false,
  jsonb_build_array(
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',900,
      'department_id','0f3c0000-0000-0000-0000-0000000000d1',
      'cost_center_id','0f3c0000-0000-0000-0000-0000000000d2',
      'project_id','0f3c0000-0000-0000-0000-0000000000d3',
      'location_id','0f3c0000-0000-0000-0000-0000000000d4',
      'functional_entity_id','0f3c0000-0000-0000-0000-0000000000d5'),
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a1','credit_amount',900)));

INSERT INTO t_ctx SELECT 'mje3', fn_post_manual_je(
  '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
  '2026-03-12', 'Adjusting entry', NULL, false,
  jsonb_build_array(
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',250),
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',250)),
  'adjusting');

INSERT INTO t_ctx SELECT 'mje4', fn_post_manual_je(
  '0f3c0000-0000-0000-0000-0000000000b1', '0f3c0000-0000-0000-0000-0000000000b2',
  '2026-03-13', 'Accrual to reverse', 'RECURRING', true,
  jsonb_build_array(
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',400),
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',100),
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',500)));

INSERT INTO t_ctx SELECT 'mje5', fn_post_manual_je(
  '0f3c0000-0000-0000-0000-0000000000b1', NULL,
  '2026-03-14', 'Second March entry, null branch', NULL, false,
  jsonb_build_array(
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',75),
    jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a1','credit_amount',75)));

-- Numbering, classification, and header metadata identical to the pre-P3C output.
SELECT results_eq(
  $q$SELECT je.je_number, je.je_date, je.reference_doc_type, je.entry_class, je.status,
            je.total_debit, je.total_credit, je.auto_reverse, je.is_auto_reversal
       FROM journal_entries je
      WHERE je.company_id='0f3c0000-0000-0000-0000-0000000000b1' AND je.je_date >= '2026-03-01'
      ORDER BY je.je_number$q$,
  $$VALUES ('MJE-202603-0001'::text, '2026-03-10'::date, 'MANUAL'::text, 'regular'::text, 'posted'::text, 1500.00::numeric(15,2), 1500.00::numeric(15,2), false, false),
           ('MJE-202603-0002'::text, '2026-03-11'::date, 'MANUAL'::text, 'regular'::text, 'posted'::text, 900.00::numeric(15,2), 900.00::numeric(15,2), false, false),
           ('MJE-202603-0003'::text, '2026-03-12'::date, 'MANUAL'::text, 'adjusting'::text, 'posted'::text, 250.00::numeric(15,2), 250.00::numeric(15,2), false, false),
           ('MJE-202603-0004'::text, '2026-03-13'::date, 'RECURRING'::text, 'regular'::text, 'posted'::text, 500.00::numeric(15,2), 500.00::numeric(15,2), true, false),
           ('MJE-202603-0005'::text, '2026-03-14'::date, 'MANUAL'::text, 'regular'::text, 'posted'::text, 75.00::numeric(15,2), 75.00::numeric(15,2), false, false)$$,
  'valid manual JE numbering, classification, and header metadata are unchanged');       -- 17

SELECT results_eq(
  $q$SELECT je.je_number, jel.line_number, coa.account_code, jel.description,
            jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel
       JOIN journal_entries je ON je.id = jel.je_id
       JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE je.company_id='0f3c0000-0000-0000-0000-0000000000b1' AND je.je_date >= '2026-03-01'
      ORDER BY je.je_number, jel.line_number$q$,
  $$VALUES ('MJE-202603-0001'::text, 1, '5010'::text, 'Supplies'::text, 1500.00::numeric(15,2), 0.00::numeric(15,2)),
           ('MJE-202603-0001'::text, 2, '2010'::text, 'Accrual'::text, 0.00::numeric(15,2), 1500.00::numeric(15,2)),
           ('MJE-202603-0002'::text, 1, '5010'::text, NULL::text, 900.00::numeric(15,2), 0.00::numeric(15,2)),
           ('MJE-202603-0002'::text, 2, '1010'::text, NULL::text, 0.00::numeric(15,2), 900.00::numeric(15,2)),
           ('MJE-202603-0003'::text, 1, '5010'::text, NULL::text, 250.00::numeric(15,2), 0.00::numeric(15,2)),
           ('MJE-202603-0003'::text, 2, '2010'::text, NULL::text, 0.00::numeric(15,2), 250.00::numeric(15,2)),
           ('MJE-202603-0004'::text, 1, '5010'::text, NULL::text, 400.00::numeric(15,2), 0.00::numeric(15,2)),
           ('MJE-202603-0004'::text, 2, '5010'::text, NULL::text, 100.00::numeric(15,2), 0.00::numeric(15,2)),
           ('MJE-202603-0004'::text, 3, '2010'::text, NULL::text, 0.00::numeric(15,2), 500.00::numeric(15,2)),
           ('MJE-202603-0005'::text, 1, '5010'::text, NULL::text, 75.00::numeric(15,2), 0.00::numeric(15,2)),
           ('MJE-202603-0005'::text, 2, '1010'::text, NULL::text, 0.00::numeric(15,2), 75.00::numeric(15,2))$$,
  'valid manual JE line order, accounts, descriptions, and amounts are unchanged');      -- 18

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje2') AND line_number=1
      AND branch_id            = '0f3c0000-0000-0000-0000-0000000000b2'
      AND department_id        = '0f3c0000-0000-0000-0000-0000000000d1'
      AND cost_center_id       = '0f3c0000-0000-0000-0000-0000000000d2'
      AND project_id           = '0f3c0000-0000-0000-0000-0000000000d3'
      AND location_id          = '0f3c0000-0000-0000-0000-0000000000d4'
      AND functional_entity_id = '0f3c0000-0000-0000-0000-0000000000d5'),
  1, 'all six dimensions still reach the manual JE line');                               -- 19

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje5') AND branch_id IS NULL),
  2, 'a null-branch manual JE still writes null-branch lines');                          -- 20

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — Every pre-P3C rejection keeps its exact message (validation order)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',10)))$$,
  'Journal entry must have at least 2 lines', 'too-few-lines message unchanged');        -- 21

SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',20)))$$,
  'Journal entry must balance: total debit 10.00 <> total credit 20.00',
  'unbalanced message unchanged');                                                       -- 22

SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','00000000-0000-0000-0000-0000000000ff','debit_amount',10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',10)))$$,
  '%does not belong to this company', 'foreign-account message unchanged');              -- 23

SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',-10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',10)))$$,
  'Line amounts cannot be negative', 'negative-amount message unchanged');               -- 24

SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',10,'credit_amount',10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',10)))$$,
  'A line cannot have both a debit and a credit amount', 'both-sides message unchanged'); -- 25

SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',10)), 'closing')$$,
  'Manual journal entries may only be classified regular, adjusting, or opening (got closing).%',
  'closing-class message unchanged');                                                    -- 26

SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2030-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a2','debit_amount',10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',10)))$$,
  'No open fiscal period covers 2030-03-15%', 'no-open-period message unchanged');       -- 27

-- An inactive account must still raise the ORIGINAL message, not the validator's —
-- the direct proof that validation order was preserved (account 1090 is inactive from
-- creation, so the COA change-policy guard is not involved).
SELECT throws_like(
  $$SELECT fn_post_manual_je('0f3c0000-0000-0000-0000-0000000000b1','0f3c0000-0000-0000-0000-0000000000b2','2026-03-15','x',NULL,false,
      jsonb_build_array(jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a6','debit_amount',10),
                        jsonb_build_object('account_id','0f3c0000-0000-0000-0000-0000000000a3','credit_amount',10)))$$,
  '%is inactive', 'an inactive account still raises the original message, not the validator''s'); -- 28

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — The validator itself still honors the frozen COA §5 contract
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT fn_assert_manual_postable('0f3c0000-0000-0000-0000-0000000000a4', '2026-03-15')$$,
  '%control account%', 'fn_assert_manual_postable rejects a control account directly');   -- 29
SELECT lives_ok(
  $$SELECT fn_assert_manual_postable('0f3c0000-0000-0000-0000-0000000000a2', '2026-03-15')$$,
  'fn_assert_manual_postable accepts an ordinary postable leaf account');                 -- 30

SELECT * FROM finish();
ROLLBACK;
