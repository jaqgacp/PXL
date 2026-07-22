-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-10 — Party Masters Enrichment (gaps MD-17, MD-18, MD-19)
--
-- Proves governed customer/supplier group masters (with legacy free-text preserved),
-- a multi-contact master with one-primary-per-party + XOR + company-isolation guards,
-- and side-effect-free duplicate-TIN detection (per party type, per company, with
-- exclusion + input normalization). Also: canonical TIN regression, active/inactive
-- lifecycle, audit coverage, rollback safety, company isolation, and member/non-member
-- write authority.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(30);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-1111111110a1'::uuid, 'mdp10-admin@test.local'),
  ('11111111-1111-1111-1111-1111111110a2'::uuid, 'mdp10-member@test.local'),
  ('11111111-1111-1111-1111-1111111110a3'::uuid, 'mdp10-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-2222222210a1', 'corporation',
   'MDP10 Alpha Corp', 'Wholesale', '311-222-810-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp10-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-1111111110a1', '11111111-1111-1111-1111-1111111110a1'),
  ('22222222-2222-2222-2222-2222222210a2', 'corporation',
   'MDP10 Beta Corp', 'Services', '311-222-820-00000',
   'vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp10-admin@test.local', 'B Owner', 'President',
   '11111111-1111-1111-1111-1111111110a1', '11111111-1111-1111-1111-1111111110a1');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-1111111110a1', '22222222-2222-2222-2222-2222222210a1', 'admin'),
  ('11111111-1111-1111-1111-1111111110a1', '22222222-2222-2222-2222-2222222210a2', 'admin'),
  ('11111111-1111-1111-1111-1111111110a2', '22222222-2222-2222-2222-2222222210a1', 'member');

-- Parties: two A-customers sharing a TIN (duplicate), one B-customer with the same
-- TIN (isolation), and A-suppliers (one sharing the TIN for type separation).
INSERT INTO customers (id, company_id, customer_code, customer_group, registered_name, trade_name, tin,
                       registered_address, delivery_address, contact_person, email, phone_number, created_by, updated_by)
VALUES
  ('44444444-0000-0000-0000-0000000000c1','22222222-2222-2222-2222-2222222210a1','CU1','VIP',
   'Alpha Customer One Inc','Alpha One','444-555-666-000','Addr','Addr','Juan Dela Cruz','j@a.local','0900',
   '11111111-1111-1111-1111-1111111110a1','11111111-1111-1111-1111-1111111110a1'),
  ('44444444-0000-0000-0000-0000000000c2','22222222-2222-2222-2222-2222222210a1','CU2',NULL,
   'Alpha Customer Two Inc',NULL,'444-555-666-000','Addr','Addr',NULL,NULL,NULL,
   '11111111-1111-1111-1111-1111111110a1','11111111-1111-1111-1111-1111111110a1'),
  ('44444444-0000-0000-0000-0000000000cb','22222222-2222-2222-2222-2222222210a2','CUB',NULL,
   'Beta Customer Inc',NULL,'444-555-666-000','Addr','Addr',NULL,NULL,NULL,
   '11111111-1111-1111-1111-1111111110a1','11111111-1111-1111-1111-1111111110a1');
INSERT INTO suppliers (id, company_id, supplier_code, supplier_group, registered_name, tin,
                       registered_address, contact_person, created_by, updated_by)
VALUES
  ('44444444-0000-0000-0000-0000000000d1','22222222-2222-2222-2222-2222222210a1','SUP1','TRADE',
   'Alpha Supplier One Corp','444-555-666-000','Addr','Pedro Santos',
   '11111111-1111-1111-1111-1111111110a1','11111111-1111-1111-1111-1111111110a1'),
  ('44444444-0000-0000-0000-0000000000d2','22222222-2222-2222-2222-2222222210a1','SUP2',NULL,
   'Alpha Supplier Two Corp','777-888-999-000','Addr',NULL,
   '11111111-1111-1111-1111-1111111110a1','11111111-1111-1111-1111-1111111110a1');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110a1');

-- ── Schema presence ───────────────────────────────────────────────────────────
SELECT has_table('customer_groups');
SELECT has_table('supplier_groups');
SELECT has_table('party_contacts');
SELECT has_column('customers', 'customer_group_id');
SELECT has_column('suppliers', 'supplier_group_id');

-- ── Group masters + linkage (MD-17) ───────────────────────────────────────────
INSERT INTO customer_groups (id, company_id, group_code, group_name)
VALUES ('55555555-0000-0000-0000-0000000000e1','22222222-2222-2222-2222-2222222210a1','KEY-ACCTS','Key Accounts');
UPDATE customers SET customer_group_id='55555555-0000-0000-0000-0000000000e1'
  WHERE id='44444444-0000-0000-0000-0000000000c1';
SELECT is(
  (SELECT g.group_name FROM customers c JOIN customer_groups g ON g.id=c.customer_group_id
   WHERE c.id='44444444-0000-0000-0000-0000000000c1'),
  'Key Accounts', 'a customer links to a governed group master');
SELECT is(
  (SELECT customer_group FROM customers WHERE id='44444444-0000-0000-0000-0000000000c1'),
  'VIP', 'the legacy free-text group is preserved (non-destructive)');
SELECT throws_ok(
  $q$INSERT INTO customer_groups (company_id, group_code, group_name)
     VALUES ('22222222-2222-2222-2222-2222222210a1','KEY-ACCTS','Dup')$q$,
  '23505', NULL, 'duplicate group_code within a company is rejected');
-- Supplier group in company B (for the isolation check later).
INSERT INTO customer_groups (company_id, group_code, group_name)
VALUES ('22222222-2222-2222-2222-2222222210a2','B-GRP','Beta Group');

-- ── Contacts master (MD-18) ───────────────────────────────────────────────────
INSERT INTO party_contacts (company_id, customer_id, contact_name, is_primary)
VALUES ('22222222-2222-2222-2222-2222222210a1','44444444-0000-0000-0000-0000000000c1','Primary Contact', true);
INSERT INTO party_contacts (company_id, customer_id, contact_name, is_primary)
VALUES ('22222222-2222-2222-2222-2222222210a1','44444444-0000-0000-0000-0000000000c1','Second Contact', false);
SELECT is(
  (SELECT count(*)::int FROM party_contacts WHERE customer_id='44444444-0000-0000-0000-0000000000c1'),
  2, 'a customer can have multiple contacts');
SELECT throws_ok(
  $q$INSERT INTO party_contacts (company_id, customer_id, contact_name, is_primary)
     VALUES ('22222222-2222-2222-2222-2222222210a1','44444444-0000-0000-0000-0000000000c1','Another Primary', true)$q$,
  '23505', NULL, 'at most one primary contact per party');
SELECT throws_ok(
  $q$INSERT INTO party_contacts (company_id, customer_id, supplier_id, contact_name)
     VALUES ('22222222-2222-2222-2222-2222222210a1','44444444-0000-0000-0000-0000000000c1','44444444-0000-0000-0000-0000000000d1','Both')$q$,
  '23514', NULL, 'a contact cannot belong to both a customer and a supplier');
SELECT throws_ok(
  $q$INSERT INTO party_contacts (company_id, contact_name) VALUES ('22222222-2222-2222-2222-2222222210a1','Neither')$q$,
  '23514', NULL, 'a contact must belong to exactly one party');
SELECT throws_ok(
  $q$INSERT INTO party_contacts (company_id, customer_id, contact_name)
     VALUES ('22222222-2222-2222-2222-2222222210a2','44444444-0000-0000-0000-0000000000c1','Wrong Co')$q$,
  '23514', NULL, 'a contact company must match its party company (isolation guard)');
INSERT INTO party_contacts (company_id, supplier_id, contact_name, is_primary)
VALUES ('22222222-2222-2222-2222-2222222210a1','44444444-0000-0000-0000-0000000000d1','Supplier Contact', true);
SELECT is(
  (SELECT count(*)::int FROM party_contacts WHERE supplier_id='44444444-0000-0000-0000-0000000000d1'),
  1, 'a supplier contact is stored');

-- ── Duplicate-TIN detection (MD-19) ───────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM fn_party_tin_duplicates(
     '22222222-2222-2222-2222-2222222210a1','customer','444-555-666-000',
     '44444444-0000-0000-0000-0000000000c1')),
  1, 'duplicate-TIN detection finds the other customer, excluding self');
SELECT is(
  (SELECT count(*)::int FROM fn_party_tin_duplicates(
     '22222222-2222-2222-2222-2222222210a1','customer','444-555-666-000', NULL)),
  2, 'without exclusion both same-TIN customers are returned');
SELECT is(
  (SELECT count(*)::int FROM fn_party_tin_duplicates(
     '22222222-2222-2222-2222-2222222210a2','customer','444-555-666-000', NULL)),
  1, 'detection is company-scoped (Company B sees only its own)');
SELECT is(
  (SELECT count(*)::int FROM fn_party_tin_duplicates(
     '22222222-2222-2222-2222-2222222210a1','supplier','444-555-666-000', NULL)),
  1, 'detection is party-type-scoped (customers and suppliers do not collide)');
SELECT throws_ok(
  $q$SELECT * FROM fn_party_tin_duplicates('22222222-2222-2222-2222-2222222210a1','vendor','444-555-666-000',NULL)$q$,
  '22023', NULL, 'an unknown party type raises');
SELECT is(
  (SELECT count(*)::int FROM fn_party_tin_duplicates(
     '22222222-2222-2222-2222-2222222210a1','customer','4445556660000', NULL)),
  2, 'detection normalizes the input TIN before matching');

-- ── Canonical TIN regression + name persistence ───────────────────────────────
SELECT ok(
  (SELECT tin FROM customers WHERE id='44444444-0000-0000-0000-0000000000c1') ~ '^[0-9]{3}-[0-9]{3}-[0-9]{3}-[0-9]{5}$',
  'party TIN is stored in canonical XXX-XXX-XXX-XXXXX format (regression)');
SELECT is(
  (SELECT trade_name FROM customers WHERE id='44444444-0000-0000-0000-0000000000c1'),
  'Alpha One', 'registered/trade name persists unchanged');

-- ── Lifecycle ─────────────────────────────────────────────────────────────────
UPDATE customer_groups SET is_active=false WHERE id='55555555-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT is_active FROM customer_groups WHERE id='55555555-0000-0000-0000-0000000000e1'),
  false, 'a group can be deactivated (lifecycle)');

-- ── Audit coverage (MDP-02 mechanism) ─────────────────────────────────────────
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='customer_groups' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-2222222210a1') >= 1,
  'customer-group creation is captured in the audit trail');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='party_contacts' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-2222222210a1') >= 1,
  'party-contact creation is captured in the audit trail');

-- ── Rollback safety ───────────────────────────────────────────────────────────
SAVEPOINT sp_grp;
INSERT INTO customer_groups (company_id, group_code, group_name)
VALUES ('22222222-2222-2222-2222-2222222210a1','ROLLBK','Rollback Test');
SELECT is(
  (SELECT count(*)::int FROM customer_groups WHERE company_id='22222222-2222-2222-2222-2222222210a1' AND group_code='ROLLBK'),
  1, 'group present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_grp;
SELECT is(
  (SELECT count(*)::int FROM customer_groups WHERE company_id='22222222-2222-2222-2222-2222222210a1' AND group_code='ROLLBK'),
  0, 'rolling back removes the row (atomic)');

-- ── Company isolation + write authority (member vs non-member) ────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110a2');  -- member of A only
SELECT is(
  (SELECT count(*)::int FROM customer_groups WHERE company_id='22222222-2222-2222-2222-2222222210a2'),
  0, 'a member of A cannot see Company B''s groups (RLS isolation)');
SELECT lives_ok(
  $q$INSERT INTO customer_groups (company_id, group_code, group_name)
     VALUES ('22222222-2222-2222-2222-2222222210a1','MEM-GRP','Member Group')$q$,
  'a company member can create a group');

SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110a3');  -- outsider (no membership)
SELECT throws_ok(
  $q$INSERT INTO customer_groups (company_id, group_code, group_name)
     VALUES ('22222222-2222-2222-2222-2222222210a1','OUT-GRP','Outsider Group')$q$,
  '42501', NULL, 'a non-member cannot create a group (RLS)');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
