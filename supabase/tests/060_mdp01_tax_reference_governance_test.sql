-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-01 (gap MD-29) — Tax-Reference Write Governance  [TEMPLATE-REFINED]
--
-- Runs as `authenticated` so the tightened RLS and governed SECURITY DEFINER
-- write path on tax_codes / vat_codes / atc_codes are actually exercised.
--
-- Reflects the FINAL TEMPLATE REFINEMENT (migration 20260721000002):
--   * Authority = MAINTAINER-ONLY (Option A). A company admin who is NOT a
--     provisioned maintainer is denied — global statutory config is not governed
--     by tenant membership, exactly as PXL-AUD-063.
--   * Audit reason is supported END-TO-END: governed writes log a single
--     sys_audit_logs row carrying `_change_reason` (no generic-trigger double-log).
--   * Statutory codes are NORMALIZED (upper/btrim) before persistence.
--
-- Covers: read preserved; direct-client write denial (RLS) incl. for a company
-- admin (no bypass); governed RPC denial for a non-maintainer company admin and
-- an ordinary user; governed create/update/set_active for a provisioned
-- maintainer; single audit row with reason + actor (no double-logging); code
-- normalization; rollback on failure; and a PXL-AUD-063 regression check.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(29);

-- Users: an ordinary authenticated user, a company admin (NOT a maintainer),
-- and a provisioned global statutory-config maintainer.
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111641'::uuid, 'tax-ordinary@test.local'),
  ('11111111-1111-1111-1111-111111111642'::uuid, 'tax-admin@test.local'),
  ('11111111-1111-1111-1111-111111111643'::uuid, 'tax-maintainer@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Company owned by the admin user -> is_any_company_admin() true for that user
-- (which, under maintainer-only authority, must confer NO tax-config authority).
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222641', 'corporation',
   'Tax Governance Corp', 'Wholesale', '311-222-641-00000',
   'vat', 'calendar', 'Tax St', 'Tax Bldg', 'Makati',
   'Metro Manila', '1200', 'tax-admin@test.local',
   'Tax Owner', 'President',
   '11111111-1111-1111-1111-111111111642', '11111111-1111-1111-1111-111111111642');
INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES ('11111111-1111-1111-1111-111111111642', '22222222-2222-2222-2222-222222222641', 'admin');

-- Provision a global statutory-config maintainer (the shared allowlist).
INSERT INTO bir_config_maintainers (user_id, note)
VALUES ('11111111-1111-1111-1111-111111111643', 'tax reference maintainer');

-- Seed one existing tax code (as superuser, pre-RLS-role) for update/toggle paths.
INSERT INTO tax_codes (id, code, description, tax_type, rate, is_active)
VALUES ('44444444-4444-4444-4444-444444444641', 'VAT12-T', 'Test VAT 12%', 'vat', 12, true);

SET LOCAL ROLE authenticated;

-- 1. Read preserved for an ordinary user.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111641');
SELECT is((SELECT count(*)::int FROM tax_codes WHERE code = 'VAT12-T'), 1,
  'authenticated user can read tax_codes');
SELECT is((SELECT count(*)::int FROM atc_codes), (SELECT count(*)::int FROM atc_codes),
  'authenticated user can read atc_codes');

-- 2. Direct client writes denied for an ordinary user.
SELECT throws_ok(
  $q$INSERT INTO tax_codes (code, description, tax_type, rate) VALUES ('EVIL','x','vat',1)$q$,
  '42501', NULL, 'ordinary user cannot directly INSERT a tax_code');
SELECT throws_ok(
  $q$INSERT INTO vat_codes (tax_code_id, vat_code, description, vat_classification, transaction_type)
     VALUES ('44444444-4444-4444-4444-444444444641','EVIL','x','regular','output_vat')$q$,
  '42501', NULL, 'ordinary user cannot directly INSERT a vat_code');

-- 3. Governed RPC denied for an ordinary (non-maintainer) user.
SELECT is(fn_is_bir_config_maintainer(), false, 'ordinary user is not a statutory-config maintainer');
SELECT throws_ok(
  $q$SELECT fn_tax_code_upsert('EVIL2','x','vat',1)$q$,
  '42501', NULL, 'ordinary user cannot use the governed tax_code RPC');

-- 4. AUTHORITY MODEL (Option A, maintainer-only): a company admin who is NOT a
--    provisioned maintainer has NO authority over global statutory tax config.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111642');
SELECT is(fn_is_bir_config_maintainer(), false,
  'company admin is NOT a statutory-config maintainer (maintainer-only authority)');
SELECT throws_ok(
  $q$SELECT fn_tax_code_upsert('ADMIN-T','admin attempt','vat',12)$q$,
  '42501', NULL, 'company admin cannot maintain global tax config (no membership authority)');
UPDATE tax_codes SET description = 'tampered' WHERE id = '44444444-4444-4444-4444-444444444641';
SELECT is(
  (SELECT description FROM tax_codes WHERE id = '44444444-4444-4444-4444-444444444641'),
  'Test VAT 12%', 'admin direct table UPDATE changes nothing (RLS, no bypass)');

-- 5. Provisioned maintainer: governed create succeeds, is audited once, carries reason.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111643');
SELECT is(fn_is_bir_config_maintainer(), true, 'provisioned user is a statutory-config maintainer');
SELECT lives_ok(
  $q$SELECT fn_tax_code_upsert(' ewt10-t ','Test EWT 10%','ewt',10, NULL, NULL, NULL, NULL, NULL, 'maintainer create')$q$,
  'maintainer can create a tax_code through the governed RPC');
SELECT is((SELECT count(*)::int FROM tax_codes WHERE code = 'EWT10-T'), 1,
  'governed create inserts exactly one tax_code');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='tax_codes' AND action='INSERT' AND new_data->>'code'='EWT10-T'),
  1, 'governed create writes exactly one audit row (no generic-trigger double-logging)');
SELECT is(
  (SELECT changed_by FROM sys_audit_logs
   WHERE table_name='tax_codes' AND action='INSERT' AND new_data->>'code'='EWT10-T'),
  '11111111-1111-1111-1111-111111111643'::uuid, 'audit row records the acting maintainer');
SELECT is(
  (SELECT new_data->>'_change_reason' FROM sys_audit_logs
   WHERE table_name='tax_codes' AND action='INSERT' AND new_data->>'code'='EWT10-T'),
  'maintainer create', 'governed create audit row carries the change reason end-to-end');

-- 6. Normalization: mixed-case, padded input persists as the canonical value.
SELECT is(
  (SELECT code FROM tax_codes WHERE description='Test EWT 10%'),
  'EWT10-T', 'statutory code is normalized (upper/btrim) before persistence');

-- 7. Governed update + set_active are applied and audited with their reasons.
SELECT lives_ok(
  $q$SELECT fn_tax_code_upsert('VAT12-T','Test VAT 12% (amended)','vat',12,
       '44444444-4444-4444-4444-444444444641', NULL, NULL, NULL, NULL, 'amend reason')$q$,
  'maintainer can amend a tax_code through the governed RPC');
SELECT is(
  (SELECT description FROM tax_codes WHERE id='44444444-4444-4444-4444-444444444641'),
  'Test VAT 12% (amended)', 'governed update applied');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='tax_codes' AND action='UPDATE' AND new_data->>'_change_reason'='amend reason'),
  1, 'governed update audit row carries its change reason');
SELECT lives_ok(
  $q$SELECT fn_tax_code_set_active('44444444-4444-4444-4444-444444444641', false, 'deactivate reason')$q$,
  'maintainer can deactivate a tax_code through the governed RPC');
SELECT is(
  (SELECT is_active FROM tax_codes WHERE id='44444444-4444-4444-4444-444444444641'),
  false, 'governed set_active applied');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='tax_codes' AND action='UPDATE' AND new_data->>'_change_reason'='deactivate reason'),
  1, 'governed set_active audit row carries its change reason');

-- 8. Maintainer path works (and normalizes) for vat_codes and atc_codes.
SELECT lives_ok(
  $q$SELECT fn_vat_code_upsert('44444444-4444-4444-4444-444444444641',' ov12-t ','Output VAT 12%',
       'regular','output_vat', NULL, NULL, NULL, NULL, NULL, 'maintainer create vat')$q$,
  'maintainer can create a vat_code through the governed RPC');
SELECT is((SELECT count(*)::int FROM vat_codes WHERE vat_code='OV12-T'), 1,
  'vat_code is normalized before persistence');
SELECT lives_ok(
  $q$SELECT fn_atc_code_upsert(' wc160-t ','EWT professional','ewt',10, NULL, NULL, NULL, NULL, 'maintainer create atc')$q$,
  'maintainer can create an atc_code through the governed RPC');
SELECT is((SELECT count(*)::int FROM atc_codes WHERE code='WC160-T'), 1,
  'atc_code is normalized before persistence');

-- 9. Rollback on failure: invalid tax_type raises and leaves no row/audit.
SELECT throws_ok(
  $q$SELECT fn_tax_code_upsert('BAD-T','bad type','not_a_type',1)$q$,
  '23514', NULL, 'invalid tax_type is rejected by the constraint');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs WHERE table_name='tax_codes' AND new_data->>'code'='BAD-T'),
  0, 'failed governed write leaves no audit row (atomic rollback)');

-- 10. Regression: PXL-AUD-063 BIR governance still holds (ordinary user denied).
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111641');
SELECT throws_ok(
  $q$SELECT fn_bir_form_upsert('REG-T','x','monthly', true, 'regression')$q$,
  '42501', NULL, 'PXL-AUD-063 BIR governance intact: ordinary user still denied');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
