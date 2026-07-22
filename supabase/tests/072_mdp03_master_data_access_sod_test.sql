-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-03 - Master Data Access Control & Segregation-of-Duties Foundation
--
-- Verifies the additive permission catalog, role mapping compatibility,
-- optional branch scoping, direct RLS enforcement, export filtering, advisory
-- SoD inventory, and audit coverage for permission-sensitive metadata.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(35);

-- ── Users: owner/admin/member/viewer/custom-role users plus an outsider ──────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111721'::uuid, 'mdp03-owner@test.local'),
  ('11111111-1111-1111-1111-111111111722'::uuid, 'mdp03-admin@test.local'),
  ('11111111-1111-1111-1111-111111111723'::uuid, 'mdp03-member@test.local'),
  ('11111111-1111-1111-1111-111111111724'::uuid, 'mdp03-viewer@test.local'),
  ('11111111-1111-1111-1111-111111111725'::uuid, 'mdp03-custom@test.local'),
  ('11111111-1111-1111-1111-111111111726'::uuid, 'mdp03-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111721');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222721', 'corporation',
        'MDP03 Access Corp', 'Software Services', '901-222-333-721',
        'vat', 'calendar',
        'Unit 1', 'Access Bldg', 'Makati', 'Metro Manila', '1200',
        'mdp03-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111722', '22222222-2222-2222-2222-222222222721', 'admin', auth.uid()),
  ('11111111-1111-1111-1111-111111111723', '22222222-2222-2222-2222-222222222721', 'member', auth.uid()),
  ('11111111-1111-1111-1111-111111111724', '22222222-2222-2222-2222-222222222721', 'viewer', auth.uid()),
  ('11111111-1111-1111-1111-111111111725', '22222222-2222-2222-2222-222222222721', 'master_operator', auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name, branch_type,
                      tin_branch_code, address_line_1, address_line_2,
                      city, province, zip_code, created_by, updated_by)
VALUES
  ('33333333-3333-3333-3333-333333333721',
   '22222222-2222-2222-2222-222222222721', 'A', 'Branch A', 'branch',
   '00001', 'A1', 'A2', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid()),
  ('33333333-3333-3333-3333-333333333722',
   '22222222-2222-2222-2222-222222222721', 'B', 'Branch B', 'branch',
   '00002', 'B1', 'B2', 'Pasig', 'Metro Manila', '1600', auth.uid(), auth.uid());

INSERT INTO master_data_role_permissions (role_code, permission_code, is_allowed, granted_by)
SELECT 'master_operator', p.permission_code, true, auth.uid()
FROM master_data_permissions p
WHERE p.master_key = 'projects'
  AND p.action IN ('view','create','edit','export')
ON CONFLICT (role_code, permission_code) DO UPDATE
SET is_allowed = EXCLUDED.is_allowed,
    updated_at = NOW();

-- ══════════════════════════════════════════════════════════════════════════════
-- All assertions below run as the authenticated role so RLS applies.
-- ══════════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM master_data_permissions WHERE master_key = 'branches'),
  7,
  'permission catalog defines the seven standard actions for branches');

SELECT ok(
  EXISTS (
    SELECT 1 FROM master_data_permissions
    WHERE permission_code = 'branches.import'
      AND action = 'import'
      AND is_available
  ),
  'import permission is defined for importable company masters');

SELECT ok(
  EXISTS (
    SELECT 1 FROM master_data_permissions
    WHERE permission_code = 'branches.approve'
      AND action = 'approve'
      AND is_available
  ),
  'approve permission is present as future-ready master-data authority');

SELECT ok(
  EXISTS (
    SELECT 1
    FROM master_data_role_permissions rp
    JOIN master_data_permissions p ON p.permission_code = rp.permission_code
    WHERE rp.role_code = 'member'
      AND p.master_key = 'customers'
      AND p.action = 'edit'
      AND rp.is_allowed
  ),
  'member role maps to operational customer edit permission');

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM master_data_role_permissions rp
    JOIN master_data_permissions p ON p.permission_code = rp.permission_code
    WHERE rp.role_code = 'member'
      AND p.master_key = 'chart_of_accounts'
      AND p.action = 'create'
      AND rp.is_allowed
  ),
  'member role does not gain setup/control COA create permission');

SELECT ok(
  EXISTS (
    SELECT 1
    FROM master_data_role_permissions rp
    JOIN master_data_permissions p ON p.permission_code = rp.permission_code
    WHERE rp.role_code = 'viewer'
      AND p.master_key = 'branches'
      AND p.action = 'export'
      AND rp.is_allowed
  ),
  'viewer role keeps export permission for company master-data backup/template reads');

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM master_data_role_permissions rp
    JOIN master_data_permissions p ON p.permission_code = rp.permission_code
    WHERE rp.role_code = 'viewer'
      AND p.master_key = 'branches'
      AND p.action = 'import'
      AND rp.is_allowed
  ),
  'viewer role does not gain import permission');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111725');
SELECT is(
  (SELECT role FROM user_company_memberships
   WHERE user_id = auth.uid()
     AND company_id = '22222222-2222-2222-2222-222222222721'),
  'master_operator',
  'membership role column accepts future custom role codes without a second membership table');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111723');
SELECT ok(
  fn_can_perform('22222222-2222-2222-2222-222222222721', 'master_data', 'customers'),
  'legacy fn_can_perform master_data action still allows member customer maintenance');

SELECT ok(
  NOT fn_can_perform('22222222-2222-2222-2222-222222222721', 'master_data', 'chart_of_accounts'),
  'legacy fn_can_perform master_data action now denies member COA maintenance through the catalog');

SELECT lives_ok(
  $q$INSERT INTO customers (company_id, customer_code, registered_name, tin,
        registered_address, delivery_address, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721', 'CUST-M',
        'Member Maintained Customer', '901-222-333-001',
        'Member HQ', 'Member HQ', auth.uid(), auth.uid())$q$,
  'member can still create an operational customer master');

SELECT throws_ok(
  $q$INSERT INTO chart_of_accounts (company_id, account_code, account_name,
        account_type, normal_balance, is_postable, is_active, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721', '1999', 'Member COA',
        'asset', 'debit', true, true, auth.uid(), auth.uid())$q$,
  '42501', NULL,
  'member cannot create setup/control COA master data');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111722');
SELECT lives_ok(
  $q$INSERT INTO chart_of_accounts (company_id, account_code, account_name,
        account_type, normal_balance, is_postable, is_active, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721', '1000', 'Admin Cash',
        'asset', 'debit', true, true, auth.uid(), auth.uid())$q$,
  'admin can create setup/control COA master data');

SELECT ok(
  EXISTS (
    SELECT 1 FROM master_data_sod_conflicts
    WHERE conflict_code = 'branches.create_vs_approve'
      AND enforcement_mode = 'advisory'
  ),
  'advisory SoD conflict pairs are seeded for create versus approve');

SELECT ok(
  EXISTS (
    SELECT 1 FROM fn_master_data_sod_conflicts_for_current_user(
      '22222222-2222-2222-2222-222222222721'
    )
  ),
  'admin role exposes advisory SoD conflicts because it has maintain and approve permissions');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111723');
SELECT is(
  (SELECT count(*)::int
   FROM fn_master_data_sod_conflicts_for_current_user(
     '22222222-2222-2222-2222-222222222721'
   )),
  0,
  'member role has no advisory SoD conflict because approve is not assigned');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111722');
SELECT lives_ok(
  $q$INSERT INTO user_company_branch_scopes (user_id, company_id, branch_id, granted_by)
     VALUES ('11111111-1111-1111-1111-111111111724',
             '22222222-2222-2222-2222-222222222721',
             '33333333-3333-3333-3333-333333333721',
             auth.uid())$q$,
  'admin can grant an optional branch scope');

SELECT lives_ok(
  $q$INSERT INTO user_company_branch_scopes (user_id, company_id, branch_id, granted_by)
     VALUES ('11111111-1111-1111-1111-111111111723',
             '22222222-2222-2222-2222-222222222721',
             '33333333-3333-3333-3333-333333333721',
             auth.uid())$q$,
  'admin can grant a branch scope to a member');

SELECT ok(
  EXISTS (
    SELECT 1
    FROM sys_audit_logs
    WHERE table_name = 'user_company_branch_scopes'
      AND action = 'INSERT'
      AND company_id = '22222222-2222-2222-2222-222222222721'
  ),
  'branch-scope grant is captured by the existing audit log framework');

SELECT ok(
  EXISTS (
    SELECT 1
    FROM sys_audit_logs
    WHERE table_name = 'user_company_memberships'
      AND action = 'INSERT'
      AND company_id = '22222222-2222-2222-2222-222222222721'
  ),
  'membership grants are now captured by the existing audit log framework');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111724');
SELECT is(
  (SELECT count(*)::int FROM branches
   WHERE company_id = '22222222-2222-2222-2222-222222222721'),
  1,
  'scoped viewer reads only the explicitly allowed branch');

SELECT is(
  (fn_export_master_data('22222222-2222-2222-2222-222222222721', 'branches', true) ->> 'row_count')::int,
  1,
  'master-data export respects optional branch scope for branch masters');

SELECT throws_ok(
  $q$SELECT fn_mdp15_export_master_data_impl(
        '22222222-2222-2222-2222-222222222721',
        'branches',
        true
      )$q$,
  '42501', NULL,
  'authenticated callers cannot bypass the MDP-03 export wrapper');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111723');
SELECT is(
  (SELECT count(*)::int FROM branches
   WHERE company_id = '22222222-2222-2222-2222-222222222721'),
  1,
  'scoped member also reads only the explicitly allowed branch');

SELECT lives_ok(
  $q$INSERT INTO projects (company_id, branch_id, project_code, project_name,
        project_status, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721',
             '33333333-3333-3333-3333-333333333721',
             'PRJ-A-M', 'Member Branch A Project', 'active', auth.uid(), auth.uid())$q$,
  'scoped member can create an operational project in an allowed branch');

SELECT throws_ok(
  $q$INSERT INTO projects (company_id, branch_id, project_code, project_name,
        project_status, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721',
             '33333333-3333-3333-3333-333333333722',
             'PRJ-B-M', 'Member Branch B Project', 'active', auth.uid(), auth.uid())$q$,
  '42501', NULL,
  'scoped member cannot create an operational project in an unscoped branch');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111721');
INSERT INTO projects (company_id, branch_id, project_code, project_name,
                      project_status, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222721',
        '33333333-3333-3333-3333-333333333722',
        'PRJ-B-O', 'Owner Branch B Project', 'active', auth.uid(), auth.uid());

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111723');
SELECT is(
  (fn_export_master_data('22222222-2222-2222-2222-222222222721', 'projects', true) ->> 'row_count')::int,
  1,
  'branch-aware export filters operational masters by branch scope');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111725');
SELECT ok(
  fn_can_master_data_permission(
    '22222222-2222-2222-2222-222222222721',
    'projects',
    'create'
  ),
  'custom role mappings are honored by the master-data permission helper');

SELECT lives_ok(
  $q$INSERT INTO projects (company_id, branch_id, project_code, project_name,
        project_status, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721',
             '33333333-3333-3333-3333-333333333722',
             'PRJ-CUSTOM', 'Custom Role Project', 'active', auth.uid(), auth.uid())$q$,
  'custom role can maintain a mapped operational master without a new membership model');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111724');
SELECT throws_ok(
  $q$INSERT INTO customers (company_id, customer_code, registered_name, tin,
        registered_address, delivery_address, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222721', 'CUST-V',
        'Viewer Customer', '901-222-333-002', 'Viewer HQ', 'Viewer HQ',
        auth.uid(), auth.uid())$q$,
  '42501', NULL,
  'viewer remains read/export-only for operational master data');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111723');
DELETE FROM customers WHERE customer_code = 'CUST-M';
SELECT is(
  (SELECT count(*)::int FROM customers WHERE customer_code = 'CUST-M'),
  1,
  'member cannot delete customer master data');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111722');
DELETE FROM customers WHERE customer_code = 'CUST-M';
SELECT is(
  (SELECT count(*)::int FROM customers WHERE customer_code = 'CUST-M'),
  0,
  'admin can delete customer master data where delete is permitted');

SELECT lives_ok(
  $q$SELECT fn_export_master_data(NULL, 'ref_banks', true)$q$,
  'authenticated users can still export global read-only reference masters');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111726');
SELECT throws_ok(
  $q$SELECT fn_export_master_data('22222222-2222-2222-2222-222222222721', 'branches', true)$q$,
  '42501', NULL,
  'non-member cannot export company master data');

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM master_data_permissions
    WHERE permission_code = 'warehouses.delete'
      AND is_available
  ),
  'delete permission is not made available when the pre-MDP-03 master had no delete policy');

SELECT * FROM finish();
ROLLBACK;
