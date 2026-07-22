-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-11 — Attribution & Reference Masters (gaps MD-20, MD-25, MD-26)
--
-- Proves: governed salesperson/buyer designation on employees + fn_is_valid_attribution
-- (lifecycle, company isolation, unknown-kind guard); the ref_banks read-only reference
-- master + bank_accounts.bank_id link with legacy bank_name preserved; and company-scoped
-- payment modes with GL-mapping integrity (same-company + postable), uniqueness, company
-- isolation, lifecycle, audit, rollback, and member/non-member write authority.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(28);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-1111111110b1'::uuid, 'mdp11-admin@test.local'),
  ('11111111-1111-1111-1111-1111111110b2'::uuid, 'mdp11-member@test.local'),
  ('11111111-1111-1111-1111-1111111110b3'::uuid, 'mdp11-outsider@test.local')
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
  ('22222222-2222-2222-2222-2222222211b1', 'corporation',
   'MDP11 Alpha Corp', 'Wholesale', '311-222-811-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp11-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-1111111110b1', '11111111-1111-1111-1111-1111111110b1'),
  ('22222222-2222-2222-2222-2222222211b2', 'corporation',
   'MDP11 Beta Corp', 'Services', '311-222-812-00000',
   'vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp11-admin@test.local', 'B Owner', 'President',
   '11111111-1111-1111-1111-1111111110b1', '11111111-1111-1111-1111-1111111110b1');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-1111111110b1', '22222222-2222-2222-2222-2222222211b1', 'admin'),
  ('11111111-1111-1111-1111-1111111110b1', '22222222-2222-2222-2222-2222222211b2', 'admin'),
  ('11111111-1111-1111-1111-1111111110b2', '22222222-2222-2222-2222-2222222211b1', 'member');
INSERT INTO branches (id, company_id, branch_code, branch_name, cas_permit_no, cas_date_issued,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES
  ('33333333-3333-3333-3333-3333333311b1', '22222222-2222-2222-2222-2222222211b1', 'HO', 'Head Office',
   'CAS-811-HO', '2026-01-01', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-1111111110b1', '11111111-1111-1111-1111-1111111110b1');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110b1');

-- Seed both companies' COA so payment-mode GL mapping has real postable accounts.
SELECT fn_seed_company_coa('22222222-2222-2222-2222-2222222211b1');
SELECT fn_seed_company_coa('22222222-2222-2222-2222-2222222211b2');

-- Employees: one salesperson, one buyer.
INSERT INTO employees (id, company_id, employee_number, last_name, first_name, hire_date, is_salesperson)
VALUES ('44444444-0000-0000-0000-0000000000e1','22222222-2222-2222-2222-2222222211b1','EMP-1','Reyes','Ana','2026-01-01', true);
INSERT INTO employees (id, company_id, employee_number, last_name, first_name, hire_date, is_buyer)
VALUES ('44444444-0000-0000-0000-0000000000e2','22222222-2222-2222-2222-2222222211b1','EMP-2','Cruz','Ben','2026-01-01', true);
INSERT INTO employees (id, company_id, employee_number, last_name, first_name, hire_date)
VALUES ('44444444-0000-0000-0000-0000000000e3','22222222-2222-2222-2222-2222222211b1','EMP-3','Lim','Cara','2026-01-01');

-- ── Schema presence ───────────────────────────────────────────────────────────
SELECT has_table('ref_banks');
SELECT has_table('company_payment_modes');
SELECT has_column('employees', 'is_salesperson');
SELECT has_column('employees', 'is_buyer');
SELECT has_column('bank_accounts', 'bank_id');

-- ── Salesperson / buyer designation (MD-20) ───────────────────────────────────
SELECT ok(
  fn_is_valid_attribution('salesperson','44444444-0000-0000-0000-0000000000e1','22222222-2222-2222-2222-2222222211b1'),
  'a designated active salesperson validates for the company');
SELECT ok(
  NOT fn_is_valid_attribution('salesperson','44444444-0000-0000-0000-0000000000e1','22222222-2222-2222-2222-2222222211b2'),
  'the salesperson does not validate for a different company (isolation)');
SELECT ok(
  NOT fn_is_valid_attribution('salesperson','44444444-0000-0000-0000-0000000000e3','22222222-2222-2222-2222-2222222211b1'),
  'an undesignated employee is not a valid salesperson');
SELECT ok(
  fn_is_valid_attribution('buyer','44444444-0000-0000-0000-0000000000e2','22222222-2222-2222-2222-2222222211b1'),
  'a designated buyer validates');
SELECT ok(
  fn_is_valid_attribution('salesperson', NULL, '22222222-2222-2222-2222-2222222211b1'),
  'a NULL employee is valid (attribution is optional)');
UPDATE employees SET is_active=false WHERE id='44444444-0000-0000-0000-0000000000e1';
SELECT ok(
  NOT fn_is_valid_attribution('salesperson','44444444-0000-0000-0000-0000000000e1','22222222-2222-2222-2222-2222222211b1'),
  'an inactive salesperson fails validation (lifecycle)');
UPDATE employees SET is_active=true WHERE id='44444444-0000-0000-0000-0000000000e1';
SELECT throws_ok(
  $q$SELECT fn_is_valid_attribution('manager','44444444-0000-0000-0000-0000000000e1','22222222-2222-2222-2222-2222222211b1')$q$,
  '22023', NULL, 'an unknown attribution kind raises');

-- ── Bank reference master (MD-25) ─────────────────────────────────────────────
SELECT cmp_ok((SELECT count(*)::int FROM ref_banks), '>=', 13,
  'ref_banks is seeded with Philippine banks');
INSERT INTO bank_accounts (id, company_id, branch_id, bank_name, account_number, account_name,
                           gl_account_id, bank_id, created_by, updated_by)
VALUES ('55555555-0000-0000-0000-0000000000a1','22222222-2222-2222-2222-2222222211b1',
        '33333333-3333-3333-3333-3333333311b1','My BDO Payroll Account','000-123','Alpha Payroll',
        (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1020'),
        (SELECT id FROM ref_banks WHERE bank_code='BDO'),
        '11111111-1111-1111-1111-1111111110b1','11111111-1111-1111-1111-1111111110b1');
SELECT is(
  (SELECT rb.bank_name FROM bank_accounts ba JOIN ref_banks rb ON rb.id=ba.bank_id
   WHERE ba.id='55555555-0000-0000-0000-0000000000a1'),
  'BDO Unibank, Inc.', 'a bank account links to the ref_banks master');
SELECT is(
  (SELECT bank_name FROM bank_accounts WHERE id='55555555-0000-0000-0000-0000000000a1'),
  'My BDO Payroll Account', 'the legacy free-text bank_name is preserved (non-destructive)');
SELECT throws_ok(
  $q$INSERT INTO ref_banks (bank_code, bank_name) VALUES ('X','Rogue Bank')$q$,
  '42501', NULL, 'ref_banks is read-only to authenticated users (deny-by-default writes)');
SELECT throws_ok(
  $q$INSERT INTO bank_accounts (company_id, bank_name, account_number, account_name, gl_account_id, bank_id, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-2222222211b1','Ghost','1','G',
       (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1020'),
       '99999999-9999-9999-9999-999999999999',
       '11111111-1111-1111-1111-1111111110b1','11111111-1111-1111-1111-1111111110b1')$q$,
  '23503', NULL, 'an unknown bank_id is rejected by the FK');

-- ── Company payment modes with GL mapping (MD-26) ─────────────────────────────
INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
VALUES ('22222222-2222-2222-2222-2222222211b1',
        (SELECT id FROM ref_payment_modes WHERE code='CASH'),
        (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1010'));
SELECT is(
  (SELECT count(*)::int FROM company_payment_modes WHERE company_id='22222222-2222-2222-2222-2222222211b1'),
  1, 'a company payment mode with a GL mapping is created');
SELECT throws_ok(
  $q$INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
     VALUES ('22222222-2222-2222-2222-2222222211b1',
       (SELECT id FROM ref_payment_modes WHERE code='CHECK'),
       (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b2' AND account_code='1010'))$q$,
  '23514', NULL, 'GL mapping integrity: a cross-company GL account is rejected');
SELECT throws_ok(
  $q$INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
     VALUES ('22222222-2222-2222-2222-2222222211b1',
       (SELECT id FROM ref_payment_modes WHERE code='BANK_XFER'),
       (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1000'))$q$,
  '23514', NULL, 'GL mapping integrity: a non-postable GL account is rejected');
SELECT throws_ok(
  $q$INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
     VALUES ('22222222-2222-2222-2222-2222222211b1',
       (SELECT id FROM ref_payment_modes WHERE code='CASH'),
       (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1020'))$q$,
  '23505', NULL, 'a payment mode is unique per company');

-- Isolation setup: a payment mode for Company B.
INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
VALUES ('22222222-2222-2222-2222-2222222211b2',
        (SELECT id FROM ref_payment_modes WHERE code='CASH'),
        (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b2' AND account_code='1010'));

-- Lifecycle.
UPDATE company_payment_modes SET is_active=false
  WHERE company_id='22222222-2222-2222-2222-2222222211b1'
    AND payment_mode_id=(SELECT id FROM ref_payment_modes WHERE code='CASH');
SELECT is(
  (SELECT is_active FROM company_payment_modes
   WHERE company_id='22222222-2222-2222-2222-2222222211b1'
     AND payment_mode_id=(SELECT id FROM ref_payment_modes WHERE code='CASH')),
  false, 'a company payment mode can be deactivated (lifecycle)');

-- Audit.
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='company_payment_modes' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-2222222211b1') >= 1,
  'company-payment-mode creation is captured in the audit trail');

-- Rollback.
SAVEPOINT sp_cpm;
INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
VALUES ('22222222-2222-2222-2222-2222222211b1',
        (SELECT id FROM ref_payment_modes WHERE code='EWALLET'),
        (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1010'));
SELECT is(
  (SELECT count(*)::int FROM company_payment_modes WHERE company_id='22222222-2222-2222-2222-2222222211b1'),
  2, 'payment mode present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_cpm;
SELECT is(
  (SELECT count(*)::int FROM company_payment_modes WHERE company_id='22222222-2222-2222-2222-2222222211b1'),
  1, 'rolling back removes the row (atomic)');

-- ── Company isolation + write authority ───────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110b2');  -- member of A only
SELECT is(
  (SELECT count(*)::int FROM company_payment_modes WHERE company_id='22222222-2222-2222-2222-2222222211b2'),
  0, 'a member of A cannot see Company B''s payment modes (RLS isolation)');
SELECT lives_ok(
  $q$INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
     VALUES ('22222222-2222-2222-2222-2222222211b1',
       (SELECT id FROM ref_payment_modes WHERE code='PDC'),
       (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1010'))$q$,
  'a company member can create a payment mode');

SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110b3');  -- outsider
-- A non-member's write is rejected (RLS WITH CHECK, or the GL guard which cannot even
-- see the company's accounts under RLS — either way the write cannot succeed).
SELECT throws_ok(
  $q$INSERT INTO company_payment_modes (company_id, payment_mode_id, gl_account_id)
     VALUES ('22222222-2222-2222-2222-2222222211b1',
       (SELECT id FROM ref_payment_modes WHERE code='CHECK'),
       (SELECT id FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-2222222211b1' AND account_code='1010'))$q$,
  NULL, NULL, 'a non-member cannot create a payment mode');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
