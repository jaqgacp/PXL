-- ============================================================================
-- PXL-AUD-062 - Company selector and company-table RLS membership scope
--
-- Runs as `authenticated` with JWT claims so broad SELECT/UPDATE policies on
-- companies, branches, customers, and transactions are caught by pgTAP.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111621',
   'authenticated', 'authenticated', 'selector-owner@test.local', '',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111622',
   'authenticated', 'authenticated', 'selector-outsider@test.local', '',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111623',
   'authenticated', 'authenticated', 'selector-empty@test.local', '',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111621');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222621', 'corporation',
   'Selector Allowed Corporation', 'Wholesale', '311-222-621-00000',
   'vat', 'calendar', 'Allowed St', 'Allowed Bldg', 'Makati',
   'Metro Manila', '1200', 'selector-owner@test.local',
   'Allowed Owner', 'President', auth.uid(), auth.uid());

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111622');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222622', 'corporation',
   'Selector Hidden Corporation', 'Wholesale', '311-222-622-00000',
   'vat', 'calendar', 'Hidden St', 'Hidden Bldg', 'Pasig',
   'Metro Manila', '1600', 'selector-hidden@test.local',
   'Hidden Owner', 'President', auth.uid(), auth.uid());

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111621');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES
  ('33333333-3333-3333-3333-333333333621',
   '22222222-2222-2222-2222-222222222621', 'ALW', 'Allowed Branch',
   'Allowed St', 'Allowed Bldg', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-111111111621',
   '11111111-1111-1111-1111-111111111621'),
  ('33333333-3333-3333-3333-333333333622',
   '22222222-2222-2222-2222-222222222622', 'HID', 'Hidden Branch',
   'Hidden St', 'Hidden Bldg', 'Pasig', 'Metro Manila', '1600',
   '11111111-1111-1111-1111-111111111621',
   '11111111-1111-1111-1111-111111111621');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES
  ('55555555-5555-5555-5555-555555555621',
   '22222222-2222-2222-2222-222222222621', 'RLS-CUST-ALW',
   'Allowed Customer Inc', '411-222-621-00000',
   'Allowed Customer HQ', 'Allowed Customer HQ',
   '11111111-1111-1111-1111-111111111621',
   '11111111-1111-1111-1111-111111111621'),
  ('55555555-5555-5555-5555-555555555622',
   '22222222-2222-2222-2222-222222222622', 'RLS-CUST-HID',
   'Hidden Customer Inc', '411-222-622-00000',
   'Hidden Customer HQ', 'Hidden Customer HQ',
   '11111111-1111-1111-1111-111111111621',
   '11111111-1111-1111-1111-111111111621');

INSERT INTO sales_invoices (id, company_id, branch_id, si_number, date,
                            customer_id, customer_name_snapshot,
                            customer_tin_snapshot, customer_address_snapshot,
                            total_amount, status, created_by, updated_by)
VALUES
  ('66666666-6666-6666-6666-666666666621',
   '22222222-2222-2222-2222-222222222621',
   '33333333-3333-3333-3333-333333333621',
   'RLS-SI-ALW-001', '2026-07-16',
   '55555555-5555-5555-5555-555555555621',
   'Allowed Customer Inc', '411-222-621-00000', 'Allowed Customer HQ',
   100, 'draft',
   '11111111-1111-1111-1111-111111111621',
   '11111111-1111-1111-1111-111111111621');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111622');

INSERT INTO sales_invoices (id, company_id, branch_id, si_number, date,
                            customer_id, customer_name_snapshot,
                            customer_tin_snapshot, customer_address_snapshot,
                            total_amount, status, created_by, updated_by)
VALUES
  ('66666666-6666-6666-6666-666666666622',
   '22222222-2222-2222-2222-222222222622',
   '33333333-3333-3333-3333-333333333622',
   'RLS-SI-HID-001', '2026-07-16',
   '55555555-5555-5555-5555-555555555622',
   'Hidden Customer Inc', '411-222-622-00000', 'Hidden Customer HQ',
   100, 'draft',
   '11111111-1111-1111-1111-111111111622',
   '11111111-1111-1111-1111-111111111622');

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111621');

SELECT is(
  (SELECT count(*)::int FROM companies),
  1,
  'company selector query sees only member companies');

SELECT is(
  (SELECT registered_name FROM companies),
  'Selector Allowed Corporation',
  'company selector result excludes non-member companies');

SELECT is(
  (SELECT count(*)::int FROM companies WHERE id = '22222222-2222-2222-2222-222222222622'),
  0,
  'direct company table query cannot see non-member company');

UPDATE companies
SET registered_name = 'Selector Hidden Corporation Updated'
WHERE id = '22222222-2222-2222-2222-222222222622';
SELECT is(
  (SELECT registered_name FROM companies WHERE id = '22222222-2222-2222-2222-222222222622'),
  NULL,
  'unauthorized company update cannot target invisible company');

SELECT is(
  (SELECT count(*)::int FROM branches),
  1,
  'branch list is scoped to member company');

SELECT is(
  (SELECT branch_code FROM branches),
  'ALW',
  'branch access excludes non-member company branch');

SELECT is(
  (SELECT count(*)::int FROM customers),
  1,
  'cross-company master-data visibility is blocked');

SELECT is(
  (SELECT customer_code FROM customers),
  'RLS-CUST-ALW',
  'customer list returns only member-company customer');

SELECT is(
  (SELECT count(*)::int FROM sales_invoices),
  1,
  'cross-company transaction visibility is blocked');

SELECT is(
  (SELECT si_number FROM sales_invoices),
  'RLS-SI-ALW-001',
  'transaction list returns only member-company document');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111623');
SELECT is(
  (SELECT count(*)::int FROM companies),
  0,
  'user with no memberships sees no companies');

SELECT * FROM finish();
ROLLBACK;
