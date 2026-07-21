-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-05 — Company Setup Defaults & Seed Templates (gaps MD-01, MD-04*, MD-05)
--
-- Proves the reusable backend seed capabilities: entity-type COA template
-- selection and seeding (balanced, classified, hierarchical), default UOM set,
-- default percentage-tax codes, company isolation, idempotency, rollback safety,
-- admin-only authority, and regressions against MDP-04 (COA classification) and
-- MDP-02 (audit provenance).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111651'::uuid, 'mdp05-admin@test.local'),
  ('11111111-1111-1111-1111-111111111652'::uuid, 'mdp05-member@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Company A (corporation) and Company B (partnership), both administered by admin.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222651', 'corporation',
   'MDP05 Alpha Corp', 'Wholesale', '311-222-651-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp05-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-111111111651', '11111111-1111-1111-1111-111111111651'),
  ('22222222-2222-2222-2222-222222222652', 'partnership',
   'MDP05 Beta Partners', 'Services', '311-222-652-00000',
   'vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp05-admin@test.local', 'B Owner', 'Partner',
   '11111111-1111-1111-1111-111111111651', '11111111-1111-1111-1111-111111111651');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-111111111651', '22222222-2222-2222-2222-222222222651', 'admin'),
  ('11111111-1111-1111-1111-111111111651', '22222222-2222-2222-2222-222222222652', 'admin'),
  ('11111111-1111-1111-1111-111111111652', '22222222-2222-2222-2222-222222222651', 'member');

-- Guarantee global references for the percentage-tax seed (as superuser).
INSERT INTO tax_codes (id, code, description, tax_type, rate, is_active)
VALUES ('44444444-4444-4444-4444-444444444651', 'PT-GLOBAL-651', 'PT global', 'pt', 3, true)
ON CONFLICT DO NOTHING;
INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active)
VALUES ('44444444-4444-4444-4444-444444444652', 'PTATC-651', 'PT ATC', 'pt', 3, true)
ON CONFLICT DO NOTHING;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111651');

-- ── COA seeding via default template selection (entity_type -> PH_STANDARD) ────
SELECT is(fn_seed_company_coa('22222222-2222-2222-2222-222222222651'), 39,
  'default template selection seeds the full PH_STANDARD chart of accounts');
SELECT is(
  (SELECT count(DISTINCT account_type)::int FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651'), 5,
  'seeded COA is balanced across all five account types');
SELECT is(
  (SELECT fs_statement FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1000'),
  'balance_sheet', 'asset header classifies to the balance sheet (generated)');
SELECT is(
  (SELECT fs_statement FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='4010'),
  'income_statement', 'revenue account classifies to the income statement (generated)');
SELECT ok(
  (SELECT NOT is_postable FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1000'),
  'header account is non-postable');
SELECT ok(
  (SELECT is_postable FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1010'),
  'detail account is postable');
SELECT is(
  (SELECT parent_id FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1010'),
  (SELECT id FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1000'),
  'template inheritance resolves the parent-child hierarchy');
SELECT results_eq(
  $q$SELECT is_control_account, subledger_type FROM chart_of_accounts
     WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1200'$q$,
  $$VALUES (true, 'receivable'::text)$$,
  'seeded AR account inherits control-account classification');
SELECT ok(
  (SELECT is_tax_account FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1400'),
  'seeded Input VAT account inherits the tax-account flag');

-- ── Idempotency: re-seeding does not duplicate ────────────────────────────────
SELECT is(fn_seed_company_coa('22222222-2222-2222-2222-222222222651'), 39,
  're-seeding returns the same account count (idempotent)');
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-222222222651'), 39,
  're-seeding creates no duplicate accounts');

-- ── Company isolation ─────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-222222222652'), 0,
  'seeding company A does not touch company B (isolation)');

-- ── Default UOM set ───────────────────────────────────────────────────────────
SELECT is(fn_seed_company_uom('22222222-2222-2222-2222-222222222651'), 15,
  'default UOM set seeds fifteen units');
SELECT ok(
  EXISTS (SELECT 1 FROM units_of_measure
          WHERE company_id='22222222-2222-2222-2222-222222222651' AND uom_code='PCS'),
  'standard UOM (PCS) is present after seeding');
SELECT is(fn_seed_company_uom('22222222-2222-2222-2222-222222222651'), 0,
  're-seeding the UOM set inserts nothing (idempotent)');

-- ── Default percentage-tax codes ──────────────────────────────────────────────
SELECT is(fn_seed_company_percentage_tax_codes('22222222-2222-2222-2222-222222222651'), 1,
  'default percentage-tax code is seeded');
SELECT ok(
  EXISTS (SELECT 1 FROM percentage_tax_codes
          WHERE company_id='22222222-2222-2222-2222-222222222651' AND pt_code='PT-3'),
  'the seeded PT-3 percentage-tax code is present');
SELECT is(fn_seed_company_percentage_tax_codes('22222222-2222-2222-2222-222222222651'), 0,
  're-seeding percentage-tax codes inserts nothing (idempotent)');

-- ── Regression: MDP-04 classification and MDP-02 audit provenance ─────────────
SELECT is(
  (SELECT fs_group FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222651' AND account_code='1200'),
  'assets', 'seeded accounts carry MDP-04 FS classification');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='chart_of_accounts' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-222222222651') >= 30,
  'seeded COA inserts are captured in the audit trail (MDP-02 provenance)');

-- ── Rollback safety ───────────────────────────────────────────────────────────
SAVEPOINT sp_seed_b;
SELECT fn_seed_company_coa('22222222-2222-2222-2222-222222222652');
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-222222222652'), 39,
  'company B COA is present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_seed_b;
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-222222222652'), 0,
  'rolling back removes the seeded COA (atomic)');

-- ── Default template selection for a different entity type ────────────────────
SELECT is(fn_seed_company_coa('22222222-2222-2222-2222-222222222652'), 39,
  'a partnership also resolves and seeds the PH_STANDARD template by default');

-- ── Authority: a non-admin member cannot seed ────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111652');
SELECT throws_ok(
  $q$SELECT fn_seed_company_coa('22222222-2222-2222-2222-222222222651')$q$,
  '42501', NULL, 'a non-admin member cannot seed company defaults');

-- ── Templates are readable reference data ─────────────────────────────────────
SELECT ok(
  (SELECT count(*)::int FROM coa_templates WHERE template_code='PH_STANDARD') = 1,
  'the PH_STANDARD template is readable reference data');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
