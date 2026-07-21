-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-02 (gap MD-30) — Master-Data Audit Coverage
--
-- Runs as a company admin (authenticated) so RLS-gated master writes are exercised
-- and fn_audit_trigger records the acting user. Proves that the three newly
-- covered company-scoped masters (units_of_measure, item_categories,
-- percentage_tax_codes) write exactly one sys_audit_logs row per mutation with
-- correct action, before/after images, actor, company context, and timestamp;
-- that failed/rolled-back mutations leave no audit row; that no free-text reason
-- is fabricated (trigger audit, not RPC audit); and — as an MDP-01/PXL-AUD-063
-- regression guard — that the RPC-audited global statutory tables carry NO audit
-- trigger, so this package introduces no double-logging.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(26);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111661',
  'authenticated', 'authenticated', 'mdp02-admin@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Company owned by the admin user (can_admin_company() true for the three masters).
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222661', 'corporation',
   'MDP02 Audit Corp', 'Wholesale', '311-222-661-00000',
   'vat', 'calendar', 'MDP St', 'MDP Bldg', 'Makati',
   'Metro Manila', '1200', 'mdp02-admin@test.local',
   'MDP Owner', 'President',
   '11111111-1111-1111-1111-111111111661', '11111111-1111-1111-1111-111111111661');
INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES ('11111111-1111-1111-1111-111111111661', '22222222-2222-2222-2222-222222222661', 'admin');

-- FK targets for percentage_tax_codes (global tables; seeded as superuser).
INSERT INTO tax_codes (id, code, description, tax_type, rate, is_active)
VALUES ('44444444-4444-4444-4444-444444444661', 'PT3-661', 'Percentage Tax 3%', 'pt', 3, true);
INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active)
VALUES ('44444444-4444-4444-4444-444444444662', 'PT010-661', 'Percentage tax', 'pt', 3, true);

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111661');

-- ── units_of_measure: INSERT / UPDATE / DELETE ────────────────────────────────
INSERT INTO units_of_measure (id, company_id, uom_code, description, is_base_unit)
VALUES ('55555555-5555-5555-5555-555555555661',
        '22222222-2222-2222-2222-222222222661', 'BOX', 'Box', true);

SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  1, 'UOM insert writes exactly one audit row (single record per mutation)');
SELECT is(
  (SELECT action FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  'INSERT', 'UOM insert audit row records action INSERT');
SELECT is(
  (SELECT new_data->>'uom_code' FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  'BOX', 'UOM insert captures after-values');
SELECT ok(
  (SELECT old_data IS NULL FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  'UOM insert has no before-image');
SELECT is(
  (SELECT changed_by FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  '11111111-1111-1111-1111-111111111661'::uuid, 'UOM insert captures the acting user');
SELECT is(
  (SELECT company_id FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  '22222222-2222-2222-2222-222222222661'::uuid, 'UOM insert captures company context');
SELECT ok(
  (SELECT changed_at IS NOT NULL FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  'UOM insert captures a timestamp');
SELECT ok(
  (SELECT NOT (new_data ? '_change_reason') FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  'trigger-audited master carries no fabricated change reason');

UPDATE units_of_measure SET description='Carton'
WHERE id='55555555-5555-5555-5555-555555555661';
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'),
  2, 'UOM update adds exactly one more audit row');
SELECT results_eq(
  $q$SELECT action, old_data->>'description', new_data->>'description'
     FROM sys_audit_logs
     WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'
       AND action='UPDATE'$q$,
  $$VALUES ('UPDATE'::text, 'Box'::text, 'Carton'::text)$$,
  'UOM update captures both before and after values');

DELETE FROM units_of_measure WHERE id='55555555-5555-5555-5555-555555555661';
SELECT results_eq(
  $q$SELECT action, old_data->>'uom_code', (new_data IS NULL)
     FROM sys_audit_logs
     WHERE table_name='units_of_measure' AND record_id='55555555-5555-5555-5555-555555555661'
       AND action='DELETE'$q$,
  $$VALUES ('DELETE'::text, 'BOX'::text, true)$$,
  'UOM delete captures the before-image and null after-image');

-- ── item_categories: INSERT / UPDATE / DELETE ─────────────────────────────────
INSERT INTO item_categories (id, company_id, category_code, category_name)
VALUES ('55555555-5555-5555-5555-555555555662',
        '22222222-2222-2222-2222-222222222661', 'RAW', 'Raw Materials');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='item_categories' AND record_id='55555555-5555-5555-5555-555555555662'),
  1, 'item_categories insert writes exactly one audit row');
SELECT is(
  (SELECT action FROM sys_audit_logs
   WHERE table_name='item_categories' AND record_id='55555555-5555-5555-5555-555555555662'),
  'INSERT', 'item_categories insert records action INSERT');
SELECT is(
  (SELECT company_id FROM sys_audit_logs
   WHERE table_name='item_categories' AND record_id='55555555-5555-5555-5555-555555555662'),
  '22222222-2222-2222-2222-222222222661'::uuid, 'item_categories insert captures company context');

UPDATE item_categories SET category_name='Raw Mats'
WHERE id='55555555-5555-5555-5555-555555555662';
SELECT results_eq(
  $q$SELECT action, old_data->>'category_name', new_data->>'category_name'
     FROM sys_audit_logs
     WHERE table_name='item_categories' AND record_id='55555555-5555-5555-5555-555555555662'
       AND action='UPDATE'$q$,
  $$VALUES ('UPDATE'::text, 'Raw Materials'::text, 'Raw Mats'::text)$$,
  'item_categories update captures before and after values');

DELETE FROM item_categories WHERE id='55555555-5555-5555-5555-555555555662';
SELECT ok(
  (SELECT new_data IS NULL FROM sys_audit_logs
   WHERE table_name='item_categories' AND record_id='55555555-5555-5555-5555-555555555662'
     AND action='DELETE'),
  'item_categories delete records a DELETE audit row with null after-image');

-- ── percentage_tax_codes: INSERT / UPDATE / DELETE ────────────────────────────
INSERT INTO percentage_tax_codes (id, company_id, tax_code_id, pt_code, description,
                                  atc_id, rate, form_type)
VALUES ('55555555-5555-5555-5555-555555555663',
        '22222222-2222-2222-2222-222222222661',
        '44444444-4444-4444-4444-444444444661', 'PT-3', '3% Percentage Tax',
        '44444444-4444-4444-4444-444444444662', 3, '2551Q');
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='percentage_tax_codes' AND record_id='55555555-5555-5555-5555-555555555663'),
  1, 'percentage_tax_codes insert writes exactly one audit row');
SELECT is(
  (SELECT company_id FROM sys_audit_logs
   WHERE table_name='percentage_tax_codes' AND record_id='55555555-5555-5555-5555-555555555663'),
  '22222222-2222-2222-2222-222222222661'::uuid, 'percentage_tax_codes insert captures company context');
SELECT is(
  (SELECT changed_by FROM sys_audit_logs
   WHERE table_name='percentage_tax_codes' AND record_id='55555555-5555-5555-5555-555555555663'),
  '11111111-1111-1111-1111-111111111661'::uuid, 'percentage_tax_codes insert captures the acting user');

UPDATE percentage_tax_codes SET rate=5
WHERE id='55555555-5555-5555-5555-555555555663';
SELECT results_eq(
  $q$SELECT action, old_data->>'rate', new_data->>'rate'
     FROM sys_audit_logs
     WHERE table_name='percentage_tax_codes' AND record_id='55555555-5555-5555-5555-555555555663'
       AND action='UPDATE'$q$,
  $$VALUES ('UPDATE'::text, '3.00'::text, '5.00'::text)$$,
  'percentage_tax_codes update captures before and after values');

DELETE FROM percentage_tax_codes WHERE id='55555555-5555-5555-5555-555555555663';
SELECT ok(
  (SELECT new_data IS NULL FROM sys_audit_logs
   WHERE table_name='percentage_tax_codes' AND record_id='55555555-5555-5555-5555-555555555663'
     AND action='DELETE'),
  'percentage_tax_codes delete records a DELETE audit row with null after-image');

-- ── Rollback safety: a rolled-back mutation leaves no audit row (atomic) ───────
SAVEPOINT before_uom;
INSERT INTO units_of_measure (id, company_id, uom_code, description, is_base_unit)
VALUES ('55555555-5555-5555-5555-555555555664',
        '22222222-2222-2222-2222-222222222661', 'PCS', 'Pieces', true);
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE record_id='55555555-5555-5555-5555-555555555664'),
  1, 'audit row is present inside the transaction before rollback');
ROLLBACK TO SAVEPOINT before_uom;
SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE record_id='55555555-5555-5555-5555-555555555664'),
  0, 'rolling back the mutation also rolls back its audit row (atomic, no orphan)');

-- ── Coverage + regression guards ──────────────────────────────────────────────
RESET ROLE;
SELECT is(
  (SELECT count(*)::int FROM pg_trigger tg
   JOIN pg_class c ON c.oid=tg.tgrelid JOIN pg_proc p ON p.oid=tg.tgfoid
   WHERE p.proname='fn_audit_trigger' AND NOT tg.tgisinternal
     AND c.relname IN ('units_of_measure','item_categories','percentage_tax_codes')),
  3, 'MDP-02 attaches exactly one audit trigger to each of the three masters');
SELECT is(
  (SELECT count(*)::int FROM pg_trigger tg
   JOIN pg_class c ON c.oid=tg.tgrelid JOIN pg_proc p ON p.oid=tg.tgfoid
   WHERE p.proname='fn_audit_trigger' AND NOT tg.tgisinternal
     AND c.relname IN ('tax_codes','vat_codes','atc_codes','bir_forms','bir_form_mappings')),
  0, 'MDP-01/PXL-AUD-063 RPC-audited global tables carry no audit trigger (no double-logging)');
SELECT is(
  (SELECT count(*)::int FROM pg_trigger tg
   JOIN pg_class c ON c.oid=tg.tgrelid JOIN pg_proc p ON p.oid=tg.tgfoid
   WHERE p.proname='fn_audit_trigger' AND NOT tg.tgisinternal
     AND c.relname='units_of_measure'),
  1, 'exactly one audit trigger on units_of_measure (no duplicate mechanism)');

SELECT * FROM finish();
ROLLBACK;
