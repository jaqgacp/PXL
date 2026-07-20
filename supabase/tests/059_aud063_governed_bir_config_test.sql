-- ══════════════════════════════════════════════════════════════════════════════
-- PXL-AUD-063 — Governed BIR global configuration write policy
--
-- Runs as `authenticated` with JWT claims so the tightened RLS and the governed
-- SECURITY DEFINER write path are actually exercised (superuser would bypass RLS).
--
-- Covers: read preserved for authenticated; direct-client write denial (RLS)
-- for INSERT/UPDATE/DELETE; unauthorized-user RPC denial; no-authority company
-- owner RPC denial (global config is NOT governed by company membership);
-- governed create/update/mapping/delete for a provisioned maintainer; single
-- governed write path (direct table write still denied for a maintainer);
-- audit-row creation with reason and actor; replay/idempotency by form_number;
-- and rollback-on-failure (invalid form reference leaves no row and no audit).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ── Users: an ordinary authenticated user, a company owner (no BIR authority),
--    and a provisioned BIR-config maintainer ─────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111631'::uuid, 'bir-ordinary@test.local'),
  ('11111111-1111-1111-1111-111111111632'::uuid, 'bir-company-owner@test.local'),
  ('11111111-1111-1111-1111-111111111633'::uuid, 'bir-maintainer@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- A company owned by the "company owner" user — proves that owning/administering
-- a company confers NO authority over global BIR config.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222631', 'corporation',
   'BIR Governance Corp', 'Wholesale', '311-222-631-00000',
   'vat', 'calendar', 'Gov St', 'Gov Bldg', 'Makati',
   'Metro Manila', '1200', 'bir-company-owner@test.local',
   'Gov Owner', 'President',
   '11111111-1111-1111-1111-111111111632',
   '11111111-1111-1111-1111-111111111632');
INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES ('11111111-1111-1111-1111-111111111632',
        '22222222-2222-2222-2222-222222222631', 'owner');

-- Seed one existing global form and mapping (as superuser, pre-RLS-role) so the
-- update/delete paths have targets, and provision exactly one maintainer.
INSERT INTO bir_forms (id, form_number, description, frequency, is_active,
                       created_by, updated_by)
VALUES ('44444444-4444-4444-4444-444444444631', '2550M-T',
        'Monthly VAT Declaration (test)', 'monthly', true, NULL, NULL);
INSERT INTO bir_form_mappings (id, form_id, line_identifier, source_type,
                               created_by, updated_by)
VALUES ('45454545-4545-4545-4545-454545454631',
        '44444444-4444-4444-4444-444444444631', 'L19A', 'tax_code', NULL, NULL);

INSERT INTO bir_config_maintainers (user_id, note)
VALUES ('11111111-1111-1111-1111-111111111633', 'test maintainer');

-- ── Switch to the authenticated role so RLS is enforced ────────────────────────
SET LOCAL ROLE authenticated;

-- 1. Read is preserved for an ordinary authenticated user.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111631');
SELECT is(
  (SELECT count(*)::int FROM bir_forms WHERE form_number = '2550M-T'),
  1, 'authenticated user can read global BIR forms');
SELECT is(
  (SELECT count(*)::int FROM bir_form_mappings
   WHERE id = '45454545-4545-4545-4545-454545454631'),
  1, 'authenticated user can read global BIR form mappings');

-- 2. Direct client INSERT is denied by RLS (no write policy).
SELECT throws_ok(
  $q$INSERT INTO bir_forms (form_number, description, frequency)
     VALUES ('EVIL-1', 'unauthorized', 'monthly')$q$,
  '42501', NULL, 'ordinary user cannot directly INSERT a BIR form');
SELECT throws_ok(
  $q$INSERT INTO bir_form_mappings (form_id, line_identifier, source_type)
     VALUES ('44444444-4444-4444-4444-444444444631', 'EVIL', 'calc')$q$,
  '42501', NULL, 'ordinary user cannot directly INSERT a BIR form mapping');

-- 3. Direct client UPDATE/DELETE match zero rows (RLS filters them out).
UPDATE bir_forms SET description = 'tampered'
WHERE id = '44444444-4444-4444-4444-444444444631';
SELECT is(
  (SELECT description FROM bir_forms WHERE id = '44444444-4444-4444-4444-444444444631'),
  'Monthly VAT Declaration (test)',
  'direct UPDATE by ordinary user changes nothing (RLS)');

DELETE FROM bir_form_mappings WHERE id = '45454545-4545-4545-4545-454545454631';
SELECT is(
  (SELECT count(*)::int FROM bir_form_mappings
   WHERE id = '45454545-4545-4545-4545-454545454631'),
  1, 'direct DELETE by ordinary user removes nothing (RLS)');

-- 4. Governed RPC denies an ordinary authenticated user.
SELECT throws_ok(
  $q$SELECT fn_bir_form_upsert('EVIL-2', 'x', 'monthly', true, 'attempt')$q$,
  '42501', NULL, 'ordinary user cannot use the governed BIR upsert RPC');

-- 4b. The internal audit helper is not directly callable (no audit spoofing).
SELECT throws_ok(
  $q$SELECT fn_log_bir_config_change('bir_forms', gen_random_uuid(), 'INSERT',
       NULL, '{"form_number":"SPOOF"}'::jsonb, 'spoof')$q$,
  '42501', NULL, 'ordinary user cannot call the audit helper directly');

-- 5. Governed RPC denies a company owner: global config is not membership-governed.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111632');
SELECT is(fn_is_bir_config_maintainer(), false,
  'company owner is not a BIR-config maintainer');
SELECT throws_ok(
  $q$SELECT fn_bir_form_mapping_upsert(
       '44444444-4444-4444-4444-444444444631', 'L20', 'tax_code',
       NULL, NULL, 'company owner attempt')$q$,
  '42501', NULL, 'company owner cannot maintain global BIR config');

-- 6. Provisioned maintainer: governed create succeeds and is audited.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111633');
SELECT is(fn_is_bir_config_maintainer(), true, 'provisioned user is a maintainer');

SELECT lives_ok(
  $q$SELECT fn_bir_form_upsert('1601EQ-T', 'Quarterly EWT (test)', 'quarterly',
       true, 'initial governed creation')$q$,
  'maintainer can create a BIR form through the governed RPC');
SELECT is(
  (SELECT count(*)::int FROM bir_forms WHERE form_number = '1601EQ-T'),
  1, 'governed create inserts exactly one BIR form');
SELECT is(
  (SELECT (new_data->>'_change_reason') FROM sys_audit_logs
   WHERE table_name = 'bir_forms' AND action = 'INSERT'
     AND new_data->>'form_number' = '1601EQ-T'),
  'initial governed creation',
  'governed create writes an audit row with the change reason');
SELECT is(
  (SELECT changed_by FROM sys_audit_logs
   WHERE table_name = 'bir_forms' AND action = 'INSERT'
     AND new_data->>'form_number' = '1601EQ-T'),
  '11111111-1111-1111-1111-111111111633'::uuid,
  'audit row records the acting maintainer');

-- 7. Replay/idempotency: re-upserting the same form_number updates, not duplicates.
SELECT lives_ok(
  $q$SELECT fn_bir_form_upsert('1601EQ-T', 'Quarterly EWT (amended)', 'quarterly',
       true, 'amendment')$q$,
  'maintainer can amend an existing form through the governed RPC');
SELECT is(
  (SELECT count(*)::int FROM bir_forms WHERE form_number = '1601EQ-T'),
  1, 'governed re-upsert by form_number does not create a duplicate');

-- 8. Single write path: even a maintainer cannot bypass via a direct table write.
UPDATE bir_forms SET description = 'direct bypass'
WHERE form_number = '1601EQ-T';
SELECT is(
  (SELECT description FROM bir_forms WHERE form_number = '1601EQ-T'),
  'Quarterly EWT (amended)',
  'maintainer direct table UPDATE is still blocked by RLS (RPC is the only path)');

-- 9. Governed mapping delete succeeds and is audited.
SELECT lives_ok(
  $q$SELECT fn_bir_form_mapping_delete(
       '45454545-4545-4545-4545-454545454631', 'obsolete line')$q$,
  'maintainer can delete a mapping through the governed RPC');
SELECT is(
  (SELECT (old_data->>'_change_reason') FROM sys_audit_logs
   WHERE table_name = 'bir_form_mappings' AND action = 'DELETE'
     AND record_id = '45454545-4545-4545-4545-454545454631'),
  'obsolete line',
  'governed delete writes an audit row with the change reason');

-- 10. Rollback on failure: an invalid form reference raises and leaves no trace.
SELECT throws_ok(
  $q$SELECT fn_bir_form_mapping_upsert(
       '00000000-0000-0000-0000-0000000000ff', 'L99', 'calc',
       NULL, NULL, 'bad ref')$q$,
  '23503', NULL, 'governed mapping upsert rejects a non-existent form');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name = 'bir_form_mappings'
     AND new_data->>'line_identifier' = 'L99'),
  0, 'failed governed write leaves no audit row (atomic rollback)');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
