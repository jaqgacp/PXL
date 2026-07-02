-- ══════════════════════════════════════════════════════════════════════════════
-- RLS-ROLES-001 - Role-Based Access Controls (PXL-AUD-004, PXL-DA-003)
--
-- First seeded execution of the RLS/role model as the `authenticated` role
-- (earlier tests ran as superuser, so RLS policies were never exercised).
-- Covers: cross-company read isolation, member/viewer reads, admin-only setup
-- writes (branches, fiscal periods, number series), member draft entry through
-- RPCs, and the owner/admin lifecycle trigger for restricted statuses.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Users: owner, admin, member, viewer of company A; outsider owns company B ──
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111131'::uuid, 'rls-owner@test.local'),
  ('11111111-1111-1111-1111-111111111132'::uuid, 'rls-admin@test.local'),
  ('11111111-1111-1111-1111-111111111133'::uuid, 'rls-member@test.local'),
  ('11111111-1111-1111-1111-111111111134'::uuid, 'rls-viewer@test.local'),
  ('11111111-1111-1111-1111-111111111135'::uuid, 'rls-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- ── Company A (owner-created) with full posting setup ──────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111131');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222232', 'corporation',
        'RLS Test Corp A', 'Software Services', '111-222-333-012',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'rls-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111132', '22222222-2222-2222-2222-222222222232', 'admin',  auth.uid()),
  ('11111111-1111-1111-1111-111111111133', '22222222-2222-2222-2222-222222222232', 'member', auth.uid()),
  ('11111111-1111-1111-1111-111111111134', '22222222-2222-2222-2222-222222222232', 'viewer', auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333342',
        '22222222-2222-2222-2222-222222222232', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444462',
        '22222222-2222-2222-2222-222222222232',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222232',
       '44444444-4444-4444-4444-444444444462',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000091', '22222222-2222-2222-2222-222222222232',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000092', '22222222-2222-2222-2222-222222222232',
   '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000093', '22222222-2222-2222-2222-222222222232',
   '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222232',
        'aaaaaaaa-0000-0000-0000-000000000091',
        'aaaaaaaa-0000-0000-0000-000000000092',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222232',
       '33333333-3333-3333-3333-333333333342',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code = 'SI';

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555561',
        '22222222-2222-2222-2222-222222222232', 'CUST-001',
        'RLS Customer Inc', '444-555-666-012',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

-- ── Company B (outsider-created) ───────────────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111135');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222233', 'corporation',
        'RLS Test Corp B', 'Trading', '111-222-333-013',
        'vat', 'calendar',
        'Unit 2', 'Other Bldg', 'Pasig', 'Metro Manila', '1600',
        'rls-outsider@test.local', 'Maria Santos', 'President',
        auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON t_ctx TO authenticated;

-- ══════════════════════════════════════════════════════════════════════════════
-- All assertions below run as the `authenticated` role so RLS applies.
-- ══════════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;

-- ── Cross-company read isolation ───────────────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111131');
SELECT is(
  (SELECT count(*)::int FROM companies WHERE id = '22222222-2222-2222-2222-222222222232'),
  1, 'owner can read their company');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111135');
SELECT is(
  (SELECT count(*)::int FROM companies WHERE id = '22222222-2222-2222-2222-222222222232'),
  0, 'a non-member cannot see another company through RLS');
SELECT is(
  (SELECT count(*)::int FROM customers WHERE company_id = '22222222-2222-2222-2222-222222222232'),
  0, 'a non-member cannot see another company''s customers');

-- ── Member/viewer reads inside the company ─────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111133');
SELECT is(
  (SELECT count(*)::int FROM branches WHERE company_id = '22222222-2222-2222-2222-222222222232'),
  1, 'member can read company branches');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111134');
SELECT is(
  (SELECT count(*)::int FROM branches WHERE company_id = '22222222-2222-2222-2222-222222222232'),
  1, 'viewer can read company branches');

-- ── Setup/control writes require owner/admin ───────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111133');
SELECT throws_ok(
  $q$INSERT INTO branches (company_id, branch_code, branch_name,
        address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222232', 'BR2', 'Member Branch',
        'X', 'Y', 'Makati', 'MM', '1200', auth.uid(), auth.uid())$q$,
  '42501', NULL, 'member cannot create a branch');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111134');
SELECT throws_ok(
  $q$INSERT INTO branches (company_id, branch_code, branch_name,
        address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222232', 'BR3', 'Viewer Branch',
        'X', 'Y', 'Makati', 'MM', '1200', auth.uid(), auth.uid())$q$,
  '42501', NULL, 'viewer cannot create a branch');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111132');
SELECT lives_ok(
  $q$INSERT INTO branches (company_id, branch_code, branch_name,
        address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222232', 'BR4', 'Admin Branch',
        'X', 'Y', 'Makati', 'MM', '1200', auth.uid(), auth.uid())$q$,
  'admin can create a branch');

-- Member's period-lock attempt silently matches no rows under RLS
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111133');
UPDATE fiscal_periods SET is_locked = true
WHERE company_id = '22222222-2222-2222-2222-222222222232';
SELECT is(
  (SELECT bool_or(is_locked) FROM fiscal_periods
   WHERE company_id = '22222222-2222-2222-2222-222222222232'),
  false, 'member cannot lock fiscal periods (RLS filters the update)');

SELECT throws_ok(
  $q$INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
        number_length, starting_number, next_number, is_active, created_by, updated_by)
     SELECT '22222222-2222-2222-2222-222222222232',
            '33333333-3333-3333-3333-333333333342',
            rdt.id, 'XX-', 6, 1, 1, true, auth.uid(), auth.uid()
     FROM ref_document_types rdt WHERE rdt.document_code = 'OR'$q$,
  '42501', NULL, 'member cannot create a number series');

-- ── Transaction lifecycle: member drafts, owner/admin posts ────────────────────
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222232',
    'branch_id',                 '33333333-3333-3333-3333-333333333342',
    'date',                      '2026-05-10',
    'customer_id',               '55555555-5555-5555-5555-555555555561',
    'customer_name_snapshot',    'RLS Customer Inc',
    'customer_tin_snapshot',     '444-555-666-012',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000093'
  )));

SELECT ok(
  (SELECT id FROM t_ctx WHERE key='si') IS NOT NULL,
  'member can save a draft sales invoice through the RPC');

-- Documents current design: approval is not yet role-restricted (PXL-DA-012).
SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  'member can approve an accounting-ready SI (approval SoD remains open under PXL-DA-012)');

SELECT throws_like(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  '%owner/admin role required%',
  'member cannot post: restricted status transition requires owner/admin');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111132');
SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si')),
  'admin can post the approved SI');
SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  'posted', 'SI posted by admin');

-- ── Outsider cannot enter transactions in company A ────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111135');
SELECT throws_like(
  $q$SELECT fn_save_sales_invoice(NULL,
    jsonb_build_object(
      'company_id',                '22222222-2222-2222-2222-222222222232',
      'branch_id',                 '33333333-3333-3333-3333-333333333342',
      'date',                      '2026-05-11',
      'customer_id',               '55555555-5555-5555-5555-555555555561',
      'customer_name_snapshot',    'RLS Customer Inc',
      'customer_tin_snapshot',     '444-555-666-012',
      'customer_address_snapshot', 'Customer HQ, Taguig'
    ),
    jsonb_build_array(jsonb_build_object(
      'description', 'Intrusion', 'quantity', 1, 'unit_price', 1,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000093'
    )))$q$,
  '%Access denied%',
  'a non-member cannot create documents in another company through the RPC');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
