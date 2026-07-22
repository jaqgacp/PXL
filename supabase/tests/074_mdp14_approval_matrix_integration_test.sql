-- MDP-14-001 - Approval Matrix Integration
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(61);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       NOW(), NOW(), NOW(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111741'::UUID, 'mdp14-requester@test.local'),
  ('11111111-1111-1111-1111-111111111742'::UUID, 'mdp14-owner-approver@test.local'),
  ('11111111-1111-1111-1111-111111111743'::UUID, 'mdp14-reviewer-a@test.local'),
  ('11111111-1111-1111-1111-111111111744'::UUID, 'mdp14-reviewer-b@test.local'),
  ('11111111-1111-1111-1111-111111111745'::UUID, 'mdp14-viewer@test.local'),
  ('11111111-1111-1111-1111-111111111746'::UUID, 'mdp14-inactive@test.local'),
  ('11111111-1111-1111-1111-111111111747'::UUID, 'mdp14-outsider@test.local')
) u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user UUID)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::TEXT, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(UUID) TO authenticated;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
INSERT INTO companies (
  id, company_code, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, address_line_1, address_line_2,
  city, province, zip_code, email, signatory_name, signatory_position,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222741', 'M14A', 'corporation',
  'MDP14 Company A', 'Software', '741-111-222-000', 'vat', 'calendar',
  'One Street', 'One Building', 'Makati', 'Metro Manila', '1200',
  'mdp14-a@test.local', 'A Signatory', 'President', auth.uid(), auth.uid()
);

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111747');
INSERT INTO companies (
  id, company_code, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, address_line_1, address_line_2,
  city, province, zip_code, email, signatory_name, signatory_position,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222742', 'M14B', 'corporation',
  'MDP14 Company B', 'Software', '742-111-222-000', 'vat', 'calendar',
  'Two Street', 'Two Building', 'Makati', 'Metro Manila', '1200',
  'mdp14-b@test.local', 'B Signatory', 'President', auth.uid(), auth.uid()
);

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111742', '22222222-2222-2222-2222-222222222741', 'owner', '11111111-1111-1111-1111-111111111741'),
  ('11111111-1111-1111-1111-111111111743', '22222222-2222-2222-2222-222222222741', 'md_reviewer', '11111111-1111-1111-1111-111111111741'),
  ('11111111-1111-1111-1111-111111111744', '22222222-2222-2222-2222-222222222741', 'md_reviewer', '11111111-1111-1111-1111-111111111741'),
  ('11111111-1111-1111-1111-111111111745', '22222222-2222-2222-2222-222222222741', 'viewer', '11111111-1111-1111-1111-111111111741'),
  ('11111111-1111-1111-1111-111111111746', '22222222-2222-2222-2222-222222222741', 'md_reviewer', '11111111-1111-1111-1111-111111111741');

UPDATE auth.users SET deleted_at = NOW()
WHERE id = '11111111-1111-1111-1111-111111111746';

INSERT INTO branches (
  id, company_id, branch_code, branch_name, address_line_1, address_line_2,
  city, province, zip_code, created_by, updated_by
) VALUES
  ('33333333-3333-3333-3333-333333333741', '22222222-2222-2222-2222-222222222741',
   'B1', 'Branch One', 'One Street', 'One Building', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-111111111741', '11111111-1111-1111-1111-111111111741'),
  ('33333333-3333-3333-3333-333333333742', '22222222-2222-2222-2222-222222222741',
   'B2', 'Branch Two', 'Two Street', 'Two Building', 'Taguig', 'Metro Manila', '1630',
   '11111111-1111-1111-1111-111111111741', '11111111-1111-1111-1111-111111111741');

INSERT INTO user_company_branch_scopes (user_id, company_id, branch_id, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111743', '22222222-2222-2222-2222-222222222741',
   '33333333-3333-3333-3333-333333333741', '11111111-1111-1111-1111-111111111741'),
  ('11111111-1111-1111-1111-111111111744', '22222222-2222-2222-2222-222222222741',
   '33333333-3333-3333-3333-333333333742', '11111111-1111-1111-1111-111111111741');

INSERT INTO master_data_role_permissions (role_code, permission_code, is_allowed)
SELECT 'md_reviewer', p.permission_code, true
FROM master_data_permissions p
WHERE p.action = 'approve'
ON CONFLICT (role_code, permission_code) DO UPDATE SET is_allowed = true;

CREATE TEMP TABLE mdp14_ctx (
  key TEXT PRIMARY KEY,
  id UUID,
  payload JSONB,
  version TEXT
);
GRANT SELECT, INSERT, UPDATE, DELETE ON mdp14_ctx TO authenticated;

-- Schema, compatibility, and safe defaults.
SELECT has_table('approval_requests', 'MDP-14 adds the approval request header');
SELECT has_column('approval_workflows', 'branch_id', 'approval rules support branch criteria');
SELECT has_column('approval_workflows', 'action_type', 'approval rules support action criteria');
SELECT has_column('approval_workflow_steps', 'approver_role_code', 'steps map existing role codes');
SELECT is(
  (SELECT count(*)::INTEGER FROM pg_proc WHERE proname IN ('fn_import_master_data','fn_import_master_data_mdp15_core')),
  2, 'MDP-15 public wrapper and internal core both exist');
SELECT ok(
  to_regprocedure('fn_provision_company(jsonb,text)') IS NOT NULL,
  'MDP-08 provisioning RPC remains available');
SELECT is(
  (SELECT count(*)::INTEGER FROM approval_workflows
   WHERE company_id = '22222222-2222-2222-2222-222222222741'),
  0, 'MDP-14 seeds no unsafe company approval rules');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
SET LOCAL ROLE authenticated;

SELECT lives_ok($q$
  INSERT INTO approval_workflows (
    id, company_id, workflow_name, module_type, document_type, action_type,
    trigger_condition_type, branch_id, effective_from,
    is_active, created_by, updated_by
  ) VALUES
    ('66666666-6666-6666-6666-666666666741', '22222222-2222-2222-2222-222222222741',
     'Department import', 'master_data', 'departments', 'import', 'always', NULL, NULL, true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666742', '22222222-2222-2222-2222-222222222741',
     'Warehouse edit fallback', 'master_data', 'warehouses', 'edit', 'always', NULL, NULL, true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666743', '22222222-2222-2222-2222-222222222741',
     'Warehouse branch-one edit', 'master_data', 'warehouses', 'edit', 'always',
     '33333333-3333-3333-3333-333333333741', NULL, true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666744', '22222222-2222-2222-2222-222222222741',
     'Future project edit', 'master_data', 'projects', 'edit', 'always', NULL,
     '2027-01-01 00:00:00+00', true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666745', '22222222-2222-2222-2222-222222222741',
     'Customer group edit', 'master_data', 'customer_groups', 'edit', 'always', NULL, NULL, true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666746', '22222222-2222-2222-2222-222222222741',
     'Supplier group edit', 'master_data', 'supplier_groups', 'edit', 'always', NULL, NULL, true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666747', '22222222-2222-2222-2222-222222222741',
     'Location edit', 'master_data', 'locations', 'edit', 'always', NULL, NULL, true, auth.uid(), auth.uid()),
    ('66666666-6666-6666-6666-666666666748', '22222222-2222-2222-2222-222222222741',
     'Inactive-user item edit', 'master_data', 'items', 'edit', 'always', NULL, NULL, true, auth.uid(), auth.uid())
$q$, 'authorized owner can create approval matrix rules');

INSERT INTO approval_workflow_steps (
  id, company_id, workflow_id, step_sequence, approver_type,
  approver_role_code, approver_user_id, action_required
) VALUES
  ('77777777-7777-7777-7777-777777777741', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666741', 1, 'role', 'owner', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777742', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666741', 2, 'role', 'md_reviewer', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777743', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666742', 1, 'role', 'owner', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777744', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666743', 1, 'role', 'md_reviewer', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777745', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666744', 1, 'role', 'owner', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777746', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666745', 1, 'role', 'owner', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777747', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666746', 1, 'role', 'owner', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777748', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666747', 1, 'role', 'owner', NULL, 'approve'),
  ('77777777-7777-7777-7777-777777777749', '22222222-2222-2222-2222-222222222741', '66666666-6666-6666-6666-666666666748', 1, 'user', NULL, '11111111-1111-1111-1111-111111111746', 'approve');

SELECT is(
  (SELECT count(*)::INTEGER FROM approval_workflow_steps WHERE approver_role_code IS NOT NULL),
  8, 'role-based approver assignments are stored on existing workflow steps');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111745');
SELECT throws_ok($q$
  INSERT INTO approval_workflows (
    company_id, workflow_name, module_type, document_type, action_type,
    trigger_condition_type, created_by, updated_by
  ) VALUES (
    '22222222-2222-2222-2222-222222222741', 'Viewer rule', 'master_data',
    'departments', 'edit', 'always', auth.uid(), auth.uid()
  )
$q$, '42501', NULL, 'non-admin cannot maintain approval rules');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111747');
SELECT is(
  (SELECT count(*)::INTEGER FROM approval_workflows
   WHERE company_id = '22222222-2222-2222-2222-222222222741'),
  0, 'approval rules are tenant-isolated by RLS');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');

-- Decision behavior: no rule, specificity, fallback, effective dates, and route health.
SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'bank_accounts', 'edit', NULL, NULL, NOW()
  ) ->> 'approval_required',
  'false', 'unconfigured master-data actions remain approval-not-required');

SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741',
    '33333333-3333-3333-3333-333333333741', 'master_data',
    'warehouses', 'edit', NULL, NULL, NOW()
  ) ->> 'workflow_id',
  '66666666-6666-6666-6666-666666666743',
  'more-specific branch rule wins deterministic precedence');

SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741',
    '33333333-3333-3333-3333-333333333742', 'master_data',
    'warehouses', 'edit', NULL, NULL, NOW()
  ) ->> 'workflow_id',
  '66666666-6666-6666-6666-666666666742',
  'broader company rule is the deterministic branch fallback');

SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'projects', 'edit', NULL, NULL, '2026-12-31 23:59:59+00'
  ) ->> 'approval_required',
  'false', 'future approval rule is not effective early');

SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'projects', 'edit', NULL, NULL, '2027-01-01 00:00:00+00'
  ) ->> 'approval_required',
  'true', 'approval rule becomes effective at its exact start');

SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'departments', 'import', NULL, NULL, NOW()
  ) ->> 'approval_required',
  'true', 'configured department import requires approval');
SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'departments', 'import', NULL, NULL, NOW()
  ) ->> 'valid_approver_available',
  'true', 'multi-level department route has valid active approvers');
SELECT ok(
  fn_can_master_data_permission(
    '22222222-2222-2222-2222-222222222741', 'departments', 'import'
  ), 'MDP-03 owner import permission is reused');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111745');
SELECT ok(
  NOT fn_can_master_data_permission(
    '22222222-2222-2222-2222-222222222741', 'departments', 'import'
  ), 'MDP-03 viewer import denial remains authoritative');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
SELECT is(
  fn_get_approval_decision(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'items', 'edit', NULL, NULL, NOW()
  ) ->> 'valid_approver_available',
  'false', 'deleted users are not valid approval-route candidates');
SELECT throws_like($q$
  SELECT fn_submit_approval_request(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data', 'items', 'edit',
    '88888888-8888-8888-8888-888888888741', 'ITEM-STALE', 'v1', NULL, NULL, '{}', NULL
  )
$q$, '%without a valid approver%', 'submission fails closed when a route has no valid approver');

-- Unconfigured MDP-15 commit remains backward compatible.
INSERT INTO mdp14_ctx (key, payload)
SELECT 'unconfigured-branch', fn_import_master_data(
  '22222222-2222-2222-2222-222222222741', 'branches',
  jsonb_build_array(jsonb_build_object(
    'branch_code','B3', 'branch_name','Branch Three',
    'address_line_1','Three Street', 'address_line_2','Three Building',
    'city','Pasig', 'province','Metro Manila', 'zip_code','1600'
  )), false, 'mdp14-unconfigured-branch', '{}'
);
SELECT is(
  (SELECT payload ->> 'status' FROM mdp14_ctx WHERE key = 'unconfigured-branch'),
  'imported', 'unconfigured master-data import commit remains compatible');
SELECT is(
  (SELECT branch_name FROM branches
   WHERE company_id = '22222222-2222-2222-2222-222222222741' AND branch_code = 'B3'),
  'Branch Three', 'unconfigured import still writes its governed master row');

-- Real MDP-15 preview -> two-level approval -> commit.
INSERT INTO mdp14_ctx (key, payload)
SELECT 'department-preview', fn_import_master_data(
  '22222222-2222-2222-2222-222222222741', 'departments',
  jsonb_build_array(jsonb_build_object(
    'branch_id','33333333-3333-3333-3333-333333333741',
    'department_code','OPS', 'department_name','Operations'
  )), true, NULL, '{}'
);
UPDATE mdp14_ctx
SET id = (payload ->> 'batch_id')::UUID, version = payload ->> 'input_hash'
WHERE key = 'department-preview';
SELECT is(
  (SELECT payload ->> 'status' FROM mdp14_ctx WHERE key = 'department-preview'),
  'validated', 'MDP-15 preview remains available before approval');

SELECT throws_like($q$
  SELECT fn_import_master_data(
    '22222222-2222-2222-2222-222222222741', 'departments',
    jsonb_build_array(jsonb_build_object(
      'branch_id','33333333-3333-3333-3333-333333333741',
      'department_code','OPS', 'department_name','Operations'
    )), false, 'mdp14-department-import', '{}'
  )
$q$, '%approval request%required%', 'configured import cannot commit without approval');

INSERT INTO mdp14_ctx (key, payload)
SELECT 'department-request', fn_submit_approval_request(
  '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
  'departments', 'import', id, 'DEPT-IMPORT-OPS', version,
  NULL, NULL, jsonb_build_object('row_count', 1), 'Onboarding departments'
)
FROM mdp14_ctx WHERE key = 'department-preview';
UPDATE mdp14_ctx SET id = (payload ->> 'request_id')::UUID
WHERE key = 'department-request';
SELECT is(
  (SELECT payload ->> 'status' FROM mdp14_ctx WHERE key = 'department-request'),
  'pending', 'authorized requester submits a pending approval request');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111745');
SELECT throws_like(
  format($q$SELECT fn_submit_approval_request(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'departments', 'import', %L, 'DEPT-IMPORT-OPS', %L,
    NULL, NULL, '{}', NULL)$q$,
    (SELECT id FROM mdp14_ctx WHERE key='department-preview'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview')),
  '%not authorized to submit%', 'unauthorized viewer cannot submit an import approval');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
SELECT is(
  (fn_submit_approval_request(
    '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
    'departments', 'import',
    (SELECT id FROM mdp14_ctx WHERE key='department-preview'), 'DEPT-IMPORT-OPS',
    (SELECT version FROM mdp14_ctx WHERE key='department-preview'),
    NULL, NULL, '{}', NULL
  ) ->> 'idempotent_replay'),
  'true', 'same-version duplicate submission is idempotent');
SELECT is(
  (SELECT count(*)::INTEGER FROM approval_requests
   WHERE source_document_id = (SELECT id FROM mdp14_ctx WHERE key='department-preview')
     AND status IN ('pending','partially_approved')),
  1, 'duplicate pending approval requests are prevented');

SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, %L, NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview')),
  '%self-approval%', 'requester self-approval is prevented');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111745');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, %L, NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview')),
  '%not authorized%', 'user without approve permission cannot approve');

RESET ROLE;
UPDATE master_data_sod_conflicts SET enforcement_mode = 'enforced'
WHERE conflict_code = 'departments.import_vs_approve';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111742');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, %L, NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview')),
  '%SOD conflict%', 'MDP-03 conflict blocks approval when explicitly enforced');

RESET ROLE;
UPDATE master_data_sod_conflicts SET enforcement_mode = 'advisory'
WHERE conflict_code = 'departments.import_vs_approve';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111742');
SELECT is(
  (fn_approve_approval_request(
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview'), 'Level one approved'
  ) ->> 'status'),
  'partially_approved', 'first approval advances a multi-level request');
SELECT is(
  (SELECT current_step_sequence FROM approval_requests
   WHERE id = (SELECT id FROM mdp14_ctx WHERE key='department-request')),
  2, 'multi-level routing advances deterministically to step two');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, %L, NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview')),
  '%not the configured approver%', 'wrong role cannot act on the next approval level');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111743');
SELECT is(
  (fn_approve_approval_request(
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview'), 'Level two approved'
  ) ->> 'status'),
  'approved', 'second configured role completes the approval route');
SELECT is(
  jsonb_array_length(fn_get_approval_request_status(
    (SELECT id FROM mdp14_ctx WHERE key='department-request')
  ) -> 'history'),
  2, 'approval history preserves both ordered approval levels');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, %L, NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='department-request'),
    (SELECT version FROM mdp14_ctx WHERE key='department-preview')),
  '%not actionable%', 'repeated approval is rejected after final approval');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
INSERT INTO mdp14_ctx (key, payload)
SELECT 'department-commit', fn_import_master_data(
  '22222222-2222-2222-2222-222222222741', 'departments',
  jsonb_build_array(jsonb_build_object(
    'branch_id','33333333-3333-3333-3333-333333333741',
    'department_code','OPS', 'department_name','Operations'
  )), false, 'mdp14-department-import',
  jsonb_build_object('approval_request_id', (SELECT id FROM mdp14_ctx WHERE key='department-request'))
);
SELECT is(
  (SELECT payload ->> 'status' FROM mdp14_ctx WHERE key='department-commit'),
  'imported', 'approved MDP-15 import commits through the compatibility wrapper');
SELECT is(
  (SELECT department_name FROM departments
   WHERE company_id='22222222-2222-2222-2222-222222222741' AND department_code='OPS'),
  'Operations', 'approved import writes the master-data row');
SELECT ok(
  (SELECT consumed_at IS NOT NULL FROM approval_requests
   WHERE id=(SELECT id FROM mdp14_ctx WHERE key='department-request')),
  'successful import consumption is audited on the approval request');
SELECT is(
  (fn_import_master_data(
    '22222222-2222-2222-2222-222222222741', 'departments',
    jsonb_build_array(jsonb_build_object(
      'branch_id','33333333-3333-3333-3333-333333333741',
      'department_code','OPS', 'department_name','Operations'
    )), false, 'mdp14-department-import',
    jsonb_build_object('approval_request_id', (SELECT id FROM mdp14_ctx WHERE key='department-request'))
  ) ->> 'idempotent_replay'),
  'true', 'approved import preserves MDP-15 idempotent replay');

-- Branch-scope enforcement on a specific route.
INSERT INTO mdp14_ctx (key, payload)
SELECT 'branch-request', fn_submit_approval_request(
  '22222222-2222-2222-2222-222222222741',
  '33333333-3333-3333-3333-333333333741', 'master_data',
  'warehouses', 'edit', '88888888-8888-8888-8888-888888888742',
  'WH-B1', 'wh-v1', NULL, NULL, '{}', NULL
);
UPDATE mdp14_ctx SET id=(payload ->> 'request_id')::UUID WHERE key='branch-request';
SELECT is(
  (SELECT payload ->> 'status' FROM mdp14_ctx WHERE key='branch-request'),
  'pending', 'branch-specific request routes successfully when a scoped approver exists');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111744');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, ''wh-v1'', NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='branch-request')),
  '%outside branch scope%', 'same-role user outside the branch scope cannot approve');
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111743');
SELECT is(
  (fn_approve_approval_request(
    (SELECT id FROM mdp14_ctx WHERE key='branch-request'), 'wh-v1', NULL
  ) ->> 'status'),
  'approved', 'same-role user inside the branch scope can approve');

-- Rejection, withdrawal, stale version, and resubmission lifecycle.
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
INSERT INTO mdp14_ctx (key, payload)
SELECT 'reject-request', fn_submit_approval_request(
  '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
  'customer_groups', 'edit', '88888888-8888-8888-8888-888888888743',
  'CG-01', 'cg-v1', NULL, NULL, '{}', NULL
);
UPDATE mdp14_ctx SET id=(payload ->> 'request_id')::UUID WHERE key='reject-request';
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111742');
SELECT is(
  (fn_reject_approval_request(
    (SELECT id FROM mdp14_ctx WHERE key='reject-request'), 'cg-v1', 'Incorrect classification'
  ) ->> 'status'),
  'rejected', 'configured approver can reject with a reason');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, ''cg-v1'', NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='reject-request')),
  '%not actionable%', 'rejected request cannot transition to approved');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
INSERT INTO mdp14_ctx (key, payload)
SELECT 'withdraw-request', fn_submit_approval_request(
  '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
  'supplier_groups', 'edit', '88888888-8888-8888-8888-888888888744',
  'SG-01', 'sg-v1', NULL, NULL, '{}', NULL
);
UPDATE mdp14_ctx SET id=(payload ->> 'request_id')::UUID WHERE key='withdraw-request';
SELECT is(
  (fn_withdraw_approval_request(
    (SELECT id FROM mdp14_ctx WHERE key='withdraw-request'), 'Requester correction'
  ) ->> 'status'),
  'withdrawn', 'requester can withdraw an actionable request');
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111742');
SELECT throws_like(
  format('SELECT fn_approve_approval_request(%L, ''sg-v1'', NULL)',
    (SELECT id FROM mdp14_ctx WHERE key='withdraw-request')),
  '%not actionable%', 'withdrawn request cannot be approved');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
INSERT INTO mdp14_ctx (key, payload)
SELECT 'stale-request', fn_submit_approval_request(
  '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
  'locations', 'edit', '88888888-8888-8888-8888-888888888745',
  'LOC-01', 'loc-v1', NULL, NULL, '{}', NULL
);
UPDATE mdp14_ctx SET id=(payload ->> 'request_id')::UUID WHERE key='stale-request';
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111742');
SELECT is(
  (fn_approve_approval_request(
    (SELECT id FROM mdp14_ctx WHERE key='stale-request'), 'loc-v2', NULL
  ) ->> 'status'),
  'superseded', 'changed source version prevents stale approval');
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111741');
INSERT INTO mdp14_ctx (key, payload)
SELECT 'stale-resubmit', fn_submit_approval_request(
  '22222222-2222-2222-2222-222222222741', NULL, 'master_data',
  'locations', 'edit', '88888888-8888-8888-8888-888888888745',
  'LOC-01', 'loc-v2', NULL, NULL, '{}', NULL
);
SELECT isnt(
  (SELECT payload ->> 'request_id' FROM mdp14_ctx WHERE key='stale-resubmit'),
  (SELECT id::TEXT FROM mdp14_ctx WHERE key='stale-request'),
  'changed record can be resubmitted as a distinct current request');

-- Audit, RPC-only integrity, and existing architecture compatibility.
SELECT ok(
  EXISTS (SELECT 1 FROM sys_audit_logs WHERE table_name='approval_workflows'),
  'rule creation and modification have audit evidence');
SELECT ok(
  EXISTS (SELECT 1 FROM sys_audit_logs WHERE table_name='approval_requests'),
  'submission and request lifecycle have audit evidence');
SELECT ok(
  EXISTS (SELECT 1 FROM sys_audit_logs WHERE table_name='approval_instances'),
  'approver resolution and decisions have per-step audit evidence');

SELECT throws_like($q$
  INSERT INTO approval_instances (
    company_id, workflow_id, source_document_type, source_document_id,
    source_document_no, step_sequence, required_approver_type, status
  ) VALUES (
    '22222222-2222-2222-2222-222222222741',
    '66666666-6666-6666-6666-666666666741', 'departments',
    '88888888-8888-8888-8888-888888888746', 'DIRECT', 1, 'role', 'approved'
  )
$q$, '%permission denied for table approval_instances%',
  'direct approval instance writes cannot bypass server lifecycle RPCs');
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes
          WHERE tablename='approval_requests'
            AND indexname='uq_approval_requests_actionable_source'),
  'actionable-request uniqueness protects concurrent duplicate submission');
SELECT ok(
  to_regprocedure('fn_required_approval_workflow(uuid,text,text,numeric)') IS NOT NULL,
  'existing DEC-010 approval helper signature remains compatible');
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111742');
SELECT ok(
  fn_can_perform('22222222-2222-2222-2222-222222222741', 'approve', 'sales_invoices'),
  'existing role-based transaction approval authorization remains available');
SELECT ok(
  EXISTS (SELECT 1 FROM master_data_sod_conflicts
          WHERE conflict_code='departments.import_vs_approve' AND is_active),
  'MDP-14 reuses the MDP-03 SOD conflict catalog');
SELECT is(
  fn_get_approval_request_status(
    (SELECT id FROM mdp14_ctx WHERE key='department-request')
  ) ->> 'final_actionable',
  'false', 'consumed approval is no longer reported as finally actionable');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
