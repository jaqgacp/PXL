-- ══════════════════════════════════════════════════════════════════════════════
-- RBAC-CANPERFORM-001 - fn_can_perform Role/Action Matrix (PXL-DA-003, PXL-AUD-004)
--
-- Executes the DEC-009 matrix as the `authenticated` role: unit checks of
-- fn_can_perform per role/action, then the operational master-data policy on
-- customers/suppliers (members create/edit, viewers read-only, delete is
-- owner/admin). Items share the identical policy shape (verified by policy
-- definition; seeding an item would only re-test the same expression through
-- admin-only category/UoM prerequisites).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- ── Users: owner, admin, member, viewer of company A; outsider ─────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111141'::uuid, 'cp-owner@test.local'),
  ('11111111-1111-1111-1111-111111111142'::uuid, 'cp-admin@test.local'),
  ('11111111-1111-1111-1111-111111111143'::uuid, 'cp-member@test.local'),
  ('11111111-1111-1111-1111-111111111144'::uuid, 'cp-viewer@test.local'),
  ('11111111-1111-1111-1111-111111111145'::uuid, 'cp-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- ── Company A with an owner-created customer ───────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111141');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222242', 'corporation',
        'CanPerform Test Corp', 'Software Services', '111-222-333-042',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'cp-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111142', '22222222-2222-2222-2222-222222222242', 'admin',  auth.uid()),
  ('11111111-1111-1111-1111-111111111143', '22222222-2222-2222-2222-222222222242', 'member', auth.uid()),
  ('11111111-1111-1111-1111-111111111144', '22222222-2222-2222-2222-222222222242', 'viewer', auth.uid());

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555571',
        '22222222-2222-2222-2222-222222222242', 'CUST-A',
        'Matrix Customer Inc', '444-555-666-042',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

-- ══════════════════════════════════════════════════════════════════════════════
-- All assertions below run as the `authenticated` role.
-- ══════════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;

-- ── fn_can_perform unit checks per DEC-009 ─────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111141');
SELECT ok(
  fn_can_perform('22222222-2222-2222-2222-222222222242', 'post', 'sales_invoices'),
  'owner can post');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111143');
SELECT ok(
  NOT fn_can_perform('22222222-2222-2222-2222-222222222242', 'post', 'sales_invoices'),
  'member cannot post');
SELECT ok(
  NOT fn_can_perform('22222222-2222-2222-2222-222222222242', 'approve', 'vendor_bills'),
  'member cannot approve');
SELECT ok(
  fn_can_perform('22222222-2222-2222-2222-222222222242', 'master_data', 'customers'),
  'member can maintain master data');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111144');
SELECT ok(
  NOT fn_can_perform('22222222-2222-2222-2222-222222222242', 'master_data', 'customers'),
  'viewer cannot maintain master data');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111145');
SELECT ok(
  NOT fn_can_perform('22222222-2222-2222-2222-222222222242', 'create', 'sales_invoices'),
  'a non-member can perform nothing');

-- ── Master data: member creates and edits ──────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111143');
SELECT lives_ok(
  $q$INSERT INTO customers (company_id, customer_code, registered_name, tin,
        registered_address, delivery_address, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222242', 'CUST-M',
        'Member Customer Inc', '444-555-666-043',
        'Member HQ, Pasig', 'Member HQ, Pasig', auth.uid(), auth.uid())$q$,
  'member can create a customer');

UPDATE customers SET registered_name = 'Matrix Customer Renamed'
WHERE id = '55555555-5555-5555-5555-555555555571';
SELECT is(
  (SELECT registered_name FROM customers
   WHERE id = '55555555-5555-5555-5555-555555555571'),
  'Matrix Customer Renamed', 'member can edit a customer');

SELECT lives_ok(
  $q$INSERT INTO suppliers (company_id, supplier_code, registered_name, tin,
        registered_address, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222242', 'SUPP-M',
        'Member Supplier Corp', '777-888-999-043',
        'Supplier HQ, Pasig', auth.uid(), auth.uid())$q$,
  'member can create a supplier');

-- ── Master data: viewer is read-only ───────────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111144');
SELECT throws_ok(
  $q$INSERT INTO customers (company_id, customer_code, registered_name, tin,
        registered_address, delivery_address, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222242', 'CUST-V',
        'Viewer Customer Inc', '444-555-666-044',
        'Viewer HQ, QC', 'Viewer HQ, QC', auth.uid(), auth.uid())$q$,
  '42501', NULL, 'viewer cannot create a customer');

-- Viewer's update silently matches no rows under RLS
UPDATE customers SET registered_name = 'Viewer Was Here'
WHERE id = '55555555-5555-5555-5555-555555555571';
SELECT is(
  (SELECT registered_name FROM customers
   WHERE id = '55555555-5555-5555-5555-555555555571'),
  'Matrix Customer Renamed', 'viewer cannot edit a customer (RLS filters the update)');

-- ── Master data delete is owner/admin ──────────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111143');
DELETE FROM customers WHERE id = '55555555-5555-5555-5555-555555555571';
SELECT is(
  (SELECT count(*)::int FROM customers
   WHERE id = '55555555-5555-5555-5555-555555555571'),
  1, 'member cannot delete a customer (RLS filters the delete)');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111142');
DELETE FROM customers WHERE id = '55555555-5555-5555-5555-555555555571';
SELECT is(
  (SELECT count(*)::int FROM customers
   WHERE id = '55555555-5555-5555-5555-555555555571'),
  0, 'admin can delete a customer');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
