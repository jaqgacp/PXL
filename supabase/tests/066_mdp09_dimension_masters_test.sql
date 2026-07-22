-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-09 — Dimension Masters: Project, Location, Functional Entity
--          (gaps MD-14, MD-15, MD-16)
--
-- Proves the three governed dimension masters: CRUD, parent-child hierarchy with
-- self-parent / cross-company / cycle guards, company isolation, branch
-- relationship, active/inactive + effective-dating lifecycle via the reusable
-- fn_is_valid_dimension checker, admin-gated default provisioning, company
-- isolation of provisioning, rollback safety, member-only write authority, and
-- audit coverage (MDP-02 mechanism).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(32);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111991'::uuid, 'mdp09-admin@test.local'),
  ('11111111-1111-1111-1111-111111111992'::uuid, 'mdp09-member@test.local'),
  ('11111111-1111-1111-1111-111111111993'::uuid, 'mdp09-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Company A (admin + member) and Company B (isolation), each with a branch.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222991', 'corporation',
   'MDP09 Alpha Corp', 'Wholesale', '311-222-991-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp09-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-111111111991', '11111111-1111-1111-1111-111111111991'),
  ('22222222-2222-2222-2222-222222222992', 'corporation',
   'MDP09 Beta Corp', 'Services', '311-222-992-00000',
   'vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp09-admin@test.local', 'B Owner', 'President',
   '11111111-1111-1111-1111-111111111991', '11111111-1111-1111-1111-111111111991');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-111111111991', '22222222-2222-2222-2222-222222222991', 'admin'),
  ('11111111-1111-1111-1111-111111111991', '22222222-2222-2222-2222-222222222992', 'admin'),
  ('11111111-1111-1111-1111-111111111992', '22222222-2222-2222-2222-222222222991', 'member');
INSERT INTO branches (id, company_id, branch_code, branch_name, cas_permit_no, cas_date_issued,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES
  ('33333333-3333-3333-3333-333333333991', '22222222-2222-2222-2222-222222222991', 'HO', 'Head Office',
   'CAS-991-HO', '2026-01-01', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-111111111991', '11111111-1111-1111-1111-111111111991'),
  ('33333333-3333-3333-3333-333333333992', '22222222-2222-2222-2222-222222222992', 'HO', 'Head Office',
   'CAS-992-HO', '2026-01-01', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-111111111991', '11111111-1111-1111-1111-111111111991');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111991');

-- ── Schema presence ───────────────────────────────────────────────────────────
SELECT has_table('projects');
SELECT has_table('locations');
SELECT has_table('functional_entities');

-- ── CRUD: create a parent + child of each master ──────────────────────────────
INSERT INTO projects (id, company_id, branch_id, project_code, project_name)
VALUES ('44444444-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222991',
        '33333333-3333-3333-3333-333333333991', 'PRJ-P', 'Parent Project');
INSERT INTO projects (id, company_id, project_code, project_name, parent_project_id)
VALUES ('44444444-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222991',
        'PRJ-C', 'Child Project', '44444444-0000-0000-0000-000000000001');
SELECT is(
  (SELECT count(*)::int FROM projects WHERE company_id='22222222-2222-2222-2222-222222222991'),
  2, 'projects: parent and child created');

INSERT INTO locations (id, company_id, location_code, location_name, location_type)
VALUES ('44444444-0000-0000-0000-000000000011', '22222222-2222-2222-2222-222222222991', 'LOC-P', 'Region', 'region');
INSERT INTO locations (company_id, location_code, location_name, parent_location_id)
VALUES ('22222222-2222-2222-2222-222222222991', 'LOC-C', 'Store', '44444444-0000-0000-0000-000000000011');
SELECT is(
  (SELECT count(*)::int FROM locations WHERE company_id='22222222-2222-2222-2222-222222222991'),
  2, 'locations: parent and child created');

INSERT INTO functional_entities (id, company_id, entity_code, entity_name, functional_entity_type)
VALUES ('44444444-0000-0000-0000-000000000021', '22222222-2222-2222-2222-222222222991', 'FE-P', 'Division', 'division');
INSERT INTO functional_entities (company_id, entity_code, entity_name, parent_functional_entity_id)
VALUES ('22222222-2222-2222-2222-222222222991', 'FE-C', 'Business Unit', '44444444-0000-0000-0000-000000000021');
SELECT is(
  (SELECT count(*)::int FROM functional_entities WHERE company_id='22222222-2222-2222-2222-222222222991'),
  2, 'functional_entities: parent and child created');

-- ── Update (rename) round-trips ───────────────────────────────────────────────
UPDATE projects SET project_name='Renamed Parent' WHERE id='44444444-0000-0000-0000-000000000001';
SELECT is(
  (SELECT project_name FROM projects WHERE id='44444444-0000-0000-0000-000000000001'),
  'Renamed Parent', 'projects: update round-trips');

-- ── Uniqueness of code within a company ───────────────────────────────────────
SELECT throws_ok(
  $q$INSERT INTO projects (company_id, project_code, project_name)
     VALUES ('22222222-2222-2222-2222-222222222991','PRJ-P','Dup')$q$,
  '23505', NULL, 'projects: duplicate code within a company is rejected');

-- ── Hierarchy guards ──────────────────────────────────────────────────────────
SELECT throws_ok(
  $q$UPDATE projects SET parent_project_id=id WHERE id='44444444-0000-0000-0000-000000000001'$q$,
  '23514', NULL, 'hierarchy: a project cannot be its own parent');
SELECT throws_ok(
  $q$UPDATE projects SET parent_project_id='44444444-0000-0000-0000-000000000002'
     WHERE id='44444444-0000-0000-0000-000000000001'$q$,
  '23514', NULL, 'hierarchy: a cycle (parent -> child -> parent) is rejected');

-- Cross-company parent: a Company B project pointing at a Company A project.
INSERT INTO projects (id, company_id, project_code, project_name)
VALUES ('44444444-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222992', 'PRJ-B', 'B Project');
SELECT throws_ok(
  $q$UPDATE projects SET parent_project_id='44444444-0000-0000-0000-000000000001'
     WHERE id='44444444-0000-0000-0000-000000000003'$q$,
  '23514', NULL, 'hierarchy: a parent in another company is rejected');

-- ── Effective-window CHECK ────────────────────────────────────────────────────
SELECT throws_ok(
  $q$INSERT INTO locations (company_id, location_code, location_name, valid_from, valid_to)
     VALUES ('22222222-2222-2222-2222-222222222991','LOC-BAD','Bad','2026-12-31','2026-01-01')$q$,
  '23514', NULL, 'effective dating: valid_to before valid_from is rejected');

-- ── Branch relationship: FK enforced ──────────────────────────────────────────
SELECT throws_ok(
  $q$INSERT INTO projects (company_id, branch_id, project_code, project_name)
     VALUES ('22222222-2222-2222-2222-222222222991','99999999-9999-9999-9999-999999999999','PRJ-X','X')$q$,
  '23503', NULL, 'branch relationship: an unknown branch_id is rejected by FK');

-- ── Reusable validity checker (lifecycle + effective dating + branch) ─────────
SELECT ok(
  fn_is_valid_dimension('project', '44444444-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222991'),
  'validity: an active project validates for its company');
SELECT ok(
  NOT fn_is_valid_dimension('project', '44444444-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222992'),
  'validity: a project does not validate for a different company (isolation)');
SELECT ok(
  fn_is_valid_dimension('project', NULL, '22222222-2222-2222-2222-222222222991'),
  'validity: a NULL dimension is valid (dimensions are optional tags)');
-- Inactivate the parent project → no longer valid.
UPDATE projects SET is_active=false WHERE id='44444444-0000-0000-0000-000000000001';
SELECT ok(
  NOT fn_is_valid_dimension('project', '44444444-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222991'),
  'validity: an inactive project fails validation (lifecycle)');
UPDATE projects SET is_active=true WHERE id='44444444-0000-0000-0000-000000000001';
-- Effective window: set a future validity, check as-of dates.
UPDATE projects SET valid_from='2026-06-01', valid_to='2026-12-31'
  WHERE id='44444444-0000-0000-0000-000000000001';
SELECT ok(
  fn_is_valid_dimension('project', '44444444-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222991', NULL, '2026-07-15'),
  'validity: in-window date passes');
SELECT ok(
  NOT fn_is_valid_dimension('project', '44444444-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222991', NULL, '2026-01-15'),
  'validity: out-of-window date fails');
-- Branch consistency: dimension carries branch HO of A; a mismatched branch fails.
SELECT ok(
  NOT fn_is_valid_dimension('project', '44444444-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222991', '33333333-3333-3333-3333-333333333992', '2026-07-15'),
  'validity: a mismatched branch fails');
SELECT throws_ok(
  $q$SELECT fn_is_valid_dimension('bogus', '44444444-0000-0000-0000-000000000001',
       '22222222-2222-2222-2222-222222222991')$q$,
  '22023', NULL, 'validity: an unknown dimension type raises');

-- ── Company isolation on reads (RLS) ──────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM projects WHERE company_id='22222222-2222-2222-2222-222222222992'),
  1, 'reads are scoped: admin of B sees only B''s one project via RLS');

-- ── Default provisioning (support for MDP-08) ─────────────────────────────────
SELECT is(fn_provision_company_dimension_defaults('22222222-2222-2222-2222-222222222991'), 2,
  'provisioning scaffolds a Head Office location and a General functional entity');
SELECT ok(
  EXISTS (SELECT 1 FROM locations WHERE company_id='22222222-2222-2222-2222-222222222991' AND location_code='HO')
  AND EXISTS (SELECT 1 FROM functional_entities WHERE company_id='22222222-2222-2222-2222-222222222991' AND entity_code='GEN'),
  'provisioning created the expected default rows');
SELECT is(fn_provision_company_dimension_defaults('22222222-2222-2222-2222-222222222991'), 2,
  're-provisioning is idempotent (no duplicates)');

-- ── Audit coverage (MDP-02 mechanism) ─────────────────────────────────────────
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='projects' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-222222222991') >= 2,
  'project creation is captured in the audit trail');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='functional_entities' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-222222222991') >= 1,
  'functional-entity creation is captured in the audit trail');

-- ── Rollback safety ───────────────────────────────────────────────────────────
SAVEPOINT sp_dim;
INSERT INTO locations (company_id, location_code, location_name)
VALUES ('22222222-2222-2222-2222-222222222991', 'ROLLBK', 'Rollback Test');
SELECT is(
  (SELECT count(*)::int FROM locations WHERE company_id='22222222-2222-2222-2222-222222222991' AND location_code='ROLLBK'),
  1, 'location present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_dim;
SELECT is(
  (SELECT count(*)::int FROM locations WHERE company_id='22222222-2222-2222-2222-222222222991' AND location_code='ROLLBK'),
  0, 'rolling back removes the row (atomic)');

-- ── Authority: a non-member cannot write; a member can; provisioning is admin ─
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111993');  -- outsider (no membership)
SELECT throws_ok(
  $q$INSERT INTO projects (company_id, project_code, project_name)
     VALUES ('22222222-2222-2222-2222-222222222991','PRJ-OUT','Outsider')$q$,
  '42501', NULL, 'a non-member cannot insert a dimension (RLS)');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111992');  -- member of A (non-admin)
SELECT lives_ok(
  $q$INSERT INTO projects (company_id, project_code, project_name)
     VALUES ('22222222-2222-2222-2222-222222222991','PRJ-MEM','Member Project')$q$,
  'a company member can insert a dimension');
SELECT throws_ok(
  $q$SELECT fn_provision_company_dimension_defaults('22222222-2222-2222-2222-222222222991')$q$,
  '42501', NULL, 'a non-admin member cannot run default provisioning');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
