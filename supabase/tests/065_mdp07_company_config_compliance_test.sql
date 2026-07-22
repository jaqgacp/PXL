-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-07 — Company Accounting & Compliance Configuration Provisioning
--          (gaps MD-06, MD-07, MD-31)
--
-- Proves reusable backend provisioning: explicit functional/reporting currency
-- with a valid-currency guard; accounting-config creation with control-account
-- mapping from the company's own COA (fill-NULL-only, so manual mappings survive);
-- config validation (coherent vs. wrong-type/cross-company/missing); compliance
-- profile derivation from tax_registration; idempotency; company isolation;
-- rollback safety; admin-only authority; audit coverage of company_accounting_config
-- (the MDP-02 deferral); and regression that the sync + tax-calendar paths still run.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111771'::uuid, 'mdp07-admin@test.local'),
  ('11111111-1111-1111-1111-111111111772'::uuid, 'mdp07-member@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Company A (VAT) and Company B (non-VAT), both administered by the admin user;
-- the member user is a non-admin member of A.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222771', 'corporation',
   'MDP07 Alpha Corp', 'Wholesale', '311-222-771-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp07-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-111111111771', '11111111-1111-1111-1111-111111111771'),
  ('22222222-2222-2222-2222-222222222772', 'sole_proprietor',
   'MDP07 Beta Store', 'Retail', '311-222-772-00000',
   'non_vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp07-admin@test.local', 'B Owner', 'Proprietor',
   '11111111-1111-1111-1111-111111111771', '11111111-1111-1111-1111-111111111771');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-111111111771', '22222222-2222-2222-2222-222222222771', 'admin'),
  ('11111111-1111-1111-1111-111111111771', '22222222-2222-2222-2222-222222222772', 'admin'),
  ('11111111-1111-1111-1111-111111111772', '22222222-2222-2222-2222-222222222771', 'member');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111771');

-- Seed both companies' Chart of Accounts (MDP-05) so config mapping has real codes.
SELECT fn_seed_company_coa('22222222-2222-2222-2222-222222222771');
SELECT fn_seed_company_coa('22222222-2222-2222-2222-222222222772');

-- ── Functional / reporting currency (MD-31) ───────────────────────────────────
SELECT results_eq(
  $q$SELECT functional_currency_code, reporting_currency_code FROM companies
     WHERE id='22222222-2222-2222-2222-222222222771'$q$,
  $$VALUES ('PHP'::text, 'PHP'::text)$$,
  'a company defaults to PHP functional and reporting currency');
SELECT throws_ok(
  $q$UPDATE companies SET functional_currency_code='ZZZ'
     WHERE id='22222222-2222-2222-2222-222222222771'$q$,
  '23503', NULL, 'functional currency must reference a real currency (FK guard)');

-- ── Accounting config provisioning (MD-06) ────────────────────────────────────
SELECT ok(
  fn_provision_company_accounting_config('22222222-2222-2222-2222-222222222771') IS NOT NULL,
  'provisioning returns the accounting-config id');
SELECT results_eq(
  $q$SELECT c_ar.account_code, c_cash.account_code, c_vat.account_code, c_in.account_code,
            c_cwt.account_code, c_ewt.account_code, c_ap.account_code
     FROM company_accounting_config cfg
     LEFT JOIN chart_of_accounts c_ar   ON c_ar.id   = cfg.ar_account_id
     LEFT JOIN chart_of_accounts c_cash ON c_cash.id = cfg.default_cash_account_id
     LEFT JOIN chart_of_accounts c_vat  ON c_vat.id  = cfg.vat_payable_account_id
     LEFT JOIN chart_of_accounts c_in   ON c_in.id   = cfg.input_vat_account_id
     LEFT JOIN chart_of_accounts c_cwt  ON c_cwt.id  = cfg.ewt_withheld_account_id
     LEFT JOIN chart_of_accounts c_ewt  ON c_ewt.id  = cfg.ewt_payable_account_id
     LEFT JOIN chart_of_accounts c_ap   ON c_ap.id   = cfg.ap_account_id
     WHERE cfg.company_id='22222222-2222-2222-2222-222222222771'$q$,
  $$VALUES ('1200'::text,'1010'::text,'2100'::text,'1400'::text,'1410'::text,'2110'::text,'2010'::text)$$,
  'control accounts are mapped from the company COA by canonical code');
SELECT is(
  fn_provision_company_accounting_config('22222222-2222-2222-2222-222222222771'),
  (SELECT id FROM company_accounting_config WHERE company_id='22222222-2222-2222-2222-222222222771'),
  're-provisioning returns the same config id (idempotent)');
SELECT is(
  (SELECT count(*)::int FROM company_accounting_config WHERE company_id='22222222-2222-2222-2222-222222222771'),
  1, 'exactly one config row exists (no duplicate)');

-- Manual override survives a re-provision (fill-NULL-only semantics).
UPDATE company_accounting_config
   SET default_cash_account_id = (SELECT id FROM chart_of_accounts
       WHERE company_id='22222222-2222-2222-2222-222222222771' AND account_code='1020')
 WHERE company_id='22222222-2222-2222-2222-222222222771';
SELECT fn_provision_company_accounting_config('22222222-2222-2222-2222-222222222771');
SELECT results_eq(
  $q$SELECT c.account_code FROM company_accounting_config cfg
     JOIN chart_of_accounts c ON c.id=cfg.default_cash_account_id
     WHERE cfg.company_id='22222222-2222-2222-2222-222222222771'$q$,
  $$VALUES ('1020'::text)$$,
  're-provisioning preserves a manually mapped account (fills NULLs only)');

-- ── Audit coverage of company_accounting_config (MDP-02 deferral) ─────────────
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='company_accounting_config' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-222222222771') >= 1,
  'accounting-config creation is captured in the audit trail');

-- ── Regression: COA control flags reconciled by the MDP-04 sync (MD-10) ───────
SELECT ok(
  (SELECT is_control_account FROM chart_of_accounts
   WHERE company_id='22222222-2222-2222-2222-222222222771' AND account_code='1200'),
  'the mapped AR account is flagged as a control account (sync ran)');

-- ── Config validation (MD-06) ─────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM fn_validate_company_accounting_config('22222222-2222-2222-2222-222222222771')),
  0, 'a fully provisioned config validates clean (no problems)');

-- Wrong account type: point AR (expects asset) at a liability account.
UPDATE company_accounting_config
   SET ar_account_id = (SELECT id FROM chart_of_accounts
       WHERE company_id='22222222-2222-2222-2222-222222222771' AND account_code='2010')
 WHERE company_id='22222222-2222-2222-2222-222222222771';
SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_accounting_config('22222222-2222-2222-2222-222222222771')
          WHERE check_code='account_wrong_type'),
  'validation flags an account of the wrong type');

-- Cross-company account: point AP at a Company B account.
UPDATE company_accounting_config
   SET ar_account_id = (SELECT id FROM chart_of_accounts
       WHERE company_id='22222222-2222-2222-2222-222222222771' AND account_code='1200'),
       ap_account_id = (SELECT id FROM chart_of_accounts
       WHERE company_id='22222222-2222-2222-2222-222222222772' AND account_code='2010')
 WHERE company_id='22222222-2222-2222-2222-222222222771';
SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_accounting_config('22222222-2222-2222-2222-222222222771')
          WHERE check_code='account_not_in_company'),
  'validation flags an account belonging to another company');
-- restore a coherent AP mapping
UPDATE company_accounting_config
   SET ap_account_id = (SELECT id FROM chart_of_accounts
       WHERE company_id='22222222-2222-2222-2222-222222222771' AND account_code='2010')
 WHERE company_id='22222222-2222-2222-2222-222222222771';

-- Missing config: Company B has none yet.
SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_accounting_config('22222222-2222-2222-2222-222222222772')
          WHERE check_code='config_missing'),
  'validation reports a missing config row');

-- ── Company isolation: provisioning A left B without a config ─────────────────
SELECT is(
  (SELECT count(*)::int FROM company_accounting_config WHERE company_id='22222222-2222-2222-2222-222222222772'),
  0, 'provisioning company A did not create a config for company B (isolation)');

-- ── Compliance profile provisioning (MD-07) ───────────────────────────────────
SELECT ok(
  fn_provision_compliance_profile('22222222-2222-2222-2222-222222222771') IS NOT NULL,
  'provisioning returns the compliance-profile id');
SELECT results_eq(
  $q$SELECT vat_registered, vat_filing_frequency, percentage_tax_registered
     FROM compliance_profiles WHERE company_id='22222222-2222-2222-2222-222222222771'$q$,
  $$VALUES (true, 'quarterly'::text, false)$$,
  'a VAT company gets a VAT-registered profile filing quarterly');
-- Provision Company B's profile, then assert the non-VAT derivation.
SELECT fn_provision_compliance_profile('22222222-2222-2222-2222-222222222772');
SELECT results_eq(
  $q$SELECT percentage_tax_registered, percentage_tax_rate, vat_registered
     FROM compliance_profiles WHERE company_id='22222222-2222-2222-2222-222222222772'$q$,
  $$VALUES (true, 3.00, false)$$,
  'a non-VAT company gets a percentage-tax profile at 3%');
SELECT is(
  fn_provision_compliance_profile('22222222-2222-2222-2222-222222222771'),
  (SELECT id FROM compliance_profiles WHERE company_id='22222222-2222-2222-2222-222222222771'),
  're-provisioning returns the same compliance-profile id (idempotent)');
SELECT ok(
  (SELECT count(*)::int FROM tax_calendar_events
   WHERE company_id='22222222-2222-2222-2222-222222222771') > 0,
  'compliance provisioning regenerated the tax calendar (trigger intact)');

-- ── Rollback safety ───────────────────────────────────────────────────────────
SAVEPOINT sp_cfg;
SELECT fn_provision_company_accounting_config('22222222-2222-2222-2222-222222222772');
SELECT is(
  (SELECT count(*)::int FROM company_accounting_config WHERE company_id='22222222-2222-2222-2222-222222222772'),
  1, 'company B config present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_cfg;
SELECT is(
  (SELECT count(*)::int FROM company_accounting_config WHERE company_id='22222222-2222-2222-2222-222222222772'),
  0, 'rolling back removes the provisioned config (atomic)');

-- ── Authority: a non-admin member cannot provision or validate ────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111772');
SELECT throws_ok(
  $q$SELECT fn_provision_company_accounting_config('22222222-2222-2222-2222-222222222771')$q$,
  '42501', NULL, 'a non-admin member cannot provision accounting config');
SELECT throws_ok(
  $q$SELECT fn_provision_compliance_profile('22222222-2222-2222-2222-222222222771')$q$,
  '42501', NULL, 'a non-admin member cannot provision a compliance profile');
SELECT throws_ok(
  $q$SELECT * FROM fn_validate_company_accounting_config('22222222-2222-2222-2222-222222222771')$q$,
  '42501', NULL, 'a non-admin member cannot validate accounting config');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
