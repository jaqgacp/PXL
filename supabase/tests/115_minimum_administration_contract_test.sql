-- Delivery Plan Phase 3 / PAD-003 administration contracts on fresh tenant data.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(14);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111176',
   'authenticated', 'authenticated', 'owner-admin@test.local', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111177',
   'authenticated', 'authenticated', 'member-admin@test.local', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111178',
   'authenticated', 'authenticated', 'second-owner@test.local', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111176","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-0000-0000-0000-000000000176', 'corporation',
        'Fresh Administration Inc', 'Business Services', '176-222-333-000',
        'vat', 'calendar', 'Unit 10', '', 'Makati', 'Metro Manila', '1200',
        'owner-admin@test.local', 'Mila Tan', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES
  ('33333333-0000-0000-0000-000000000176', '22222222-0000-0000-0000-000000000176',
   'HO', 'Head Office', 'Unit 10', '', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid()),
  ('33333333-0000-0000-0000-000000000177', '22222222-0000-0000-0000-000000000176',
   'CEB', 'Cebu Branch', 'Cebu IT Park', '', 'Cebu City', 'Cebu', '6000', auth.uid(), auth.uid());

SELECT is(
  (SELECT role FROM user_company_memberships
   WHERE company_id = '22222222-0000-0000-0000-000000000176'
     AND user_id = '11111111-1111-1111-1111-111111111176'),
  'owner', 'E1: company provisioning grants the creator the owner role');

SELECT is(
  (SELECT count(*)::int FROM fn_admin_list_company_users('22222222-0000-0000-0000-000000000176')),
  1, 'E2: the admin-only list begins with only the fresh company owner');

SELECT lives_ok(
  $$SELECT fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111177', 'member')$$,
  'E3: an owner can add an existing authenticated user as a company member');

SELECT is(
  (SELECT email FROM fn_admin_list_company_users('22222222-0000-0000-0000-000000000176')
   WHERE user_id = '11111111-1111-1111-1111-111111111177'),
  'member-admin@test.local', 'E4: the list exposes only the scoped member email through the RPC');

SELECT lives_ok(
  $$SELECT fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111177', 'admin')$$,
  'E5: role assignment uses the governed membership RPC');

SELECT is(
  fn_admin_set_branch_scopes(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111177',
    ARRAY['33333333-0000-0000-0000-000000000176'::uuid,
          '33333333-0000-0000-0000-000000000177'::uuid,
          '33333333-0000-0000-0000-000000000177'::uuid]
  ),
  2, 'E6: branch scope assigns both active fresh-company branches');

SELECT is(
  (SELECT count(*)::int FROM user_company_branch_scopes
   WHERE company_id = '22222222-0000-0000-0000-000000000176'
     AND user_id = '11111111-1111-1111-1111-111111111177'),
  2, 'E7: branch scope persists exactly the selected branches');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111177","role":"authenticated"}', true);

SELECT throws_ok(
  $$SELECT fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111177', 'owner')$$,
  'P0001', 'Only an owner can assign the owner role',
  'E8: an administrator cannot promote itself to owner');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111176","role":"authenticated"}', true);

SELECT lives_ok(
  $$SELECT fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111178', 'owner')$$,
  'E8b: an owner can appoint a second owner');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111177","role":"authenticated"}', true);

SELECT throws_ok(
  $$SELECT fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111178', 'viewer')$$,
  'P0001', 'Only an owner can change another owner''s role',
  'E8c: an administrator cannot demote an owner even when another owner remains');

SELECT throws_ok(
  $$SELECT fn_admin_remove_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111178')$$,
  'P0001', 'Only an owner can remove another owner',
  'E8d: an administrator cannot remove an owner');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111176","role":"authenticated"}', true);

DO $$
BEGIN
  PERFORM fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111178', 'viewer');
END;
$$;

SELECT throws_ok(
  $$SELECT fn_admin_upsert_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111176', 'admin')$$,
  'P0001', 'A company must retain at least one owner',
  'E9: the last owner cannot be demoted');

SELECT lives_ok(
  $$SELECT fn_admin_remove_membership(
    '22222222-0000-0000-0000-000000000176',
    '11111111-1111-1111-1111-111111111177')$$,
  'E10: an owner can remove a non-owner membership');

SELECT is(
  (SELECT count(*)::int FROM user_company_branch_scopes
   WHERE company_id = '22222222-0000-0000-0000-000000000176'
     AND user_id = '11111111-1111-1111-1111-111111111177'),
  0, 'E11: membership removal clears branch scope atomically');

SELECT * FROM finish();
ROLLBACK;
