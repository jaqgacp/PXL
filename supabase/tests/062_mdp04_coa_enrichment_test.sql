-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-04 — Chart of Accounts Enrichment (gaps MD-09..MD-13)
--
-- Proves the enriched COA master: generated FS-statement classification, FS
-- grouping, control-account reconciliation from company_accounting_config,
-- cash-flow / cost / tax classification, effective-date window and constraints,
-- preserved posting-vs-header and hierarchy behaviour, backward-compatible
-- inserts, and audit compatibility (fn_audit_trigger still fires on COA edits).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(23);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111621',
  'authenticated', 'authenticated', 'mdp04-admin@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222621', 'corporation',
   'MDP04 COA Corp', 'Wholesale', '311-222-621-00000',
   'vat', 'calendar', 'COA St', 'COA Bldg', 'Makati',
   'Metro Manila', '1200', 'mdp04-admin@test.local',
   'COA Owner', 'President',
   '11111111-1111-1111-1111-111111111621', '11111111-1111-1111-1111-111111111621');
INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES ('11111111-1111-1111-1111-111111111621', '22222222-2222-2222-2222-222222222621', 'admin');

-- Seed a small COA (as superuser): a header (non-postable) parent + postable
-- children, plus the control accounts config will reference.
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, created_by, updated_by)
VALUES
  ('c0a00000-0000-0000-0000-000000000601', '22222222-2222-2222-2222-222222222621',
   '1000', 'Assets', 'asset', 'debit', false, auth.uid(), auth.uid()),          -- header
  ('c0a00000-0000-0000-0000-000000000602', '22222222-2222-2222-2222-222222222621',
   '1010', 'Cash in Bank', 'asset', 'debit', true, auth.uid(), auth.uid()),      -- child, cash control
  ('c0a00000-0000-0000-0000-000000000603', '22222222-2222-2222-2222-222222222621',
   '1200', 'Accounts Receivable', 'asset', 'debit', true, auth.uid(), auth.uid()),
  ('c0a00000-0000-0000-0000-000000000604', '22222222-2222-2222-2222-222222222621',
   '2100', 'Output VAT Payable', 'liability', 'credit', true, auth.uid(), auth.uid()),
  ('c0a00000-0000-0000-0000-000000000605', '22222222-2222-2222-2222-222222222621',
   '4000', 'Service Revenue', 'revenue', 'credit', true, auth.uid(), auth.uid()),
  ('c0a00000-0000-0000-0000-000000000606', '22222222-2222-2222-2222-222222222621',
   '5000', 'Rent Expense', 'expense', 'debit', true, auth.uid(), auth.uid());
-- Parent the children to the header (hierarchy).
UPDATE chart_of_accounts SET parent_id = 'c0a00000-0000-0000-0000-000000000601'
 WHERE company_id = '22222222-2222-2222-2222-222222222621'
   AND account_code IN ('1010','1200');

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
                                       default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222621',
        'c0a00000-0000-0000-0000-000000000603',
        'c0a00000-0000-0000-0000-000000000604',
        'c0a00000-0000-0000-0000-000000000602',
        auth.uid(), auth.uid());

-- ── MD-09: generated FS-statement classification ──────────────────────────────
SELECT is((SELECT fs_statement FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000603'),
  'balance_sheet', 'asset account is classified to the balance sheet (generated)');
SELECT is((SELECT fs_statement FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000605'),
  'income_statement', 'revenue account is classified to the income statement (generated)');
SELECT is((SELECT fs_statement FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000604'),
  'balance_sheet', 'liability account is classified to the balance sheet (generated)');

-- ── MD-09: fs_group is backfilled to a correct coarse bucket per type ──────────
SELECT is((SELECT fs_group FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000603'),
  'assets', 'fs_group backfilled for asset accounts');
SELECT is((SELECT fs_group FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000606'),
  'expenses', 'fs_group backfilled for expense accounts');

-- ── MD-11: cash-flow classification backfill (P&L -> operating) ───────────────
SELECT is((SELECT cash_flow_category FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000605'),
  'operating', 'revenue account backfilled to operating cash-flow section');
SELECT ok((SELECT cash_flow_category IS NULL FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000603'),
  'balance-sheet account cash-flow category left for explicit classification');

-- ── MD-10: control-account reconciliation from company_accounting_config ──────
SELECT is(fn_sync_coa_control_accounts('22222222-2222-2222-2222-222222222621'), 3,
  'control-account sync updates exactly the three configured accounts');
SELECT results_eq(
  $q$SELECT is_control_account, allow_subledger, subledger_type
     FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000603'$q$,
  $$VALUES (true, true, 'receivable'::text)$$,
  'AR account is reconciled as a receivable control account');
SELECT results_eq(
  $q$SELECT is_control_account, subledger_type, is_tax_account
     FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000604'$q$,
  $$VALUES (true, 'tax'::text, true)$$,
  'VAT payable is reconciled as a tax control account and flagged tax-relevant');
SELECT is((SELECT subledger_type FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000602'),
  'bank', 'default cash account is reconciled as a bank control account');
SELECT ok((SELECT NOT is_control_account FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000605'),
  'a non-configured account is not made a control account (no over-reach)');

-- ── MD-09/MD-12: FS grouping reporting fixture ────────────────────────────────
SELECT results_eq(
  $q$SELECT fs_statement, count(*)::int
     FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-222222222621'
     GROUP BY fs_statement ORDER BY fs_statement$q$,
  $$VALUES ('balance_sheet'::text, 4), ('income_statement'::text, 2)$$,
  'accounts roll up into balance-sheet and income-statement groups for reporting');

-- ── Hierarchy: parent-child relationships resolve ─────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts
   WHERE parent_id='c0a00000-0000-0000-0000-000000000601'), 2,
  'the header account reports its two child accounts (hierarchy preserved)');

-- ── Posting restriction: header is non-postable, children postable (preserved) ─
SELECT ok((SELECT NOT is_postable FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000601'),
  'header/summary account remains non-postable (posting restriction preserved)');
SELECT ok((SELECT is_postable FROM chart_of_accounts WHERE id='c0a00000-0000-0000-0000-000000000602'),
  'detail account remains postable');

-- ── Constraints reject invalid classification values ──────────────────────────
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111621');
SELECT throws_ok(
  $q$UPDATE chart_of_accounts SET fs_group='nonsense' WHERE id='c0a00000-0000-0000-0000-000000000602'$q$,
  '23514', NULL, 'invalid fs_group is rejected by CHECK constraint');
SELECT throws_ok(
  $q$UPDATE chart_of_accounts SET subledger_type='wallet' WHERE id='c0a00000-0000-0000-0000-000000000602'$q$,
  '23514', NULL, 'invalid subledger_type is rejected by CHECK constraint');
SELECT throws_ok(
  $q$UPDATE chart_of_accounts SET cash_flow_category='misc' WHERE id='c0a00000-0000-0000-0000-000000000606'$q$,
  '23514', NULL, 'invalid cash_flow_category is rejected by CHECK constraint');
SELECT throws_ok(
  $q$UPDATE chart_of_accounts SET effective_from='2026-12-31', effective_to='2026-01-01'
     WHERE id='c0a00000-0000-0000-0000-000000000602'$q$,
  '23514', NULL, 'an effective_to before effective_from is rejected');

-- ── MD-13: a valid effective window is accepted ───────────────────────────────
SELECT lives_ok(
  $q$UPDATE chart_of_accounts SET effective_from='2026-01-01', effective_to='2026-12-31'
     WHERE id='c0a00000-0000-0000-0000-000000000606'$q$,
  'a valid effective-date window is accepted');

-- ── Backward compatibility: a legacy-shaped insert (no new columns) still works ─
SELECT lives_ok(
  $q$INSERT INTO chart_of_accounts (company_id, account_code, account_name,
       account_type, normal_balance, is_postable)
     VALUES ('22222222-2222-2222-2222-222222222621','1020','Petty Cash','asset','debit',true)$q$,
  'a COA insert that omits every new column still succeeds (backward compatible)');

-- ── Audit compatibility: COA edits still write a sys_audit_logs row ────────────
UPDATE chart_of_accounts SET fs_subgroup='Trade Receivables'
 WHERE id='c0a00000-0000-0000-0000-000000000603';
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='chart_of_accounts' AND action='UPDATE'
     AND record_id='c0a00000-0000-0000-0000-000000000603'
     AND new_data->>'fs_subgroup'='Trade Receivables') >= 1,
  'COA classification edits are captured in the audit trail (MDP-02 coverage intact)');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
