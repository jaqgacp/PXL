-- ══════════════════════════════════════════════════════════════════════════════
-- APPROVAL-SOD-001 - Approval Segregation of Duties (PXL-DA-012, DEC-010)
--
-- Exercises the DEC-010 gates as the `authenticated` role: workflow matching
-- (module, blank vs specific document type, amount threshold), self-approval
-- blocked when a workflow is configured, approval instance recorded with
-- actor/timestamp, posting requires a qualifying approval (instance or legacy
-- approved_by evidence), direct status-UPDATE shortcuts equally gated, and a
-- deactivated workflow restores plain DEC-009 role-gate behavior.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ── Users: owner, admin, member of company A ───────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111151'::uuid, 'sod-owner@test.local'),
  ('11111111-1111-1111-1111-111111111152'::uuid, 'sod-admin@test.local'),
  ('11111111-1111-1111-1111-111111111153'::uuid, 'sod-member@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- ── Company A with full SI posting setup (as in RLS-ROLES-001) ─────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111151');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222252', 'corporation',
        'SoD Test Corp', 'Software Services', '111-222-333-052',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'sod-owner@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
VALUES
  ('11111111-1111-1111-1111-111111111152', '22222222-2222-2222-2222-222222222252', 'admin',  auth.uid()),
  ('11111111-1111-1111-1111-111111111153', '22222222-2222-2222-2222-222222222252', 'member', auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333352',
        '22222222-2222-2222-2222-222222222252', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444472',
        '22222222-2222-2222-2222-222222222252',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222252',
       '44444444-4444-4444-4444-444444444472',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000101', '22222222-2222-2222-2222-222222222252',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000102', '22222222-2222-2222-2222-222222222252',
   '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000103', '22222222-2222-2222-2222-222222222252',
   '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222252',
        'aaaaaaaa-0000-0000-0000-000000000101',
        'aaaaaaaa-0000-0000-0000-000000000102',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222252',
       '33333333-3333-3333-3333-333333333352',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code = 'SI';

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555581',
        '22222222-2222-2222-2222-222222222252', 'CUST-001',
        'SoD Customer Inc', '444-555-666-052',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

-- ── Approval workflows: W1 all sales docs always; W2 VB above 10,000 ───────────
INSERT INTO approval_workflows (id, company_id, workflow_name, module_type,
                                document_type, trigger_condition_type, threshold_value,
                                is_active, created_by, updated_by)
VALUES
  ('66666666-6666-6666-6666-666666666601', '22222222-2222-2222-2222-222222222252',
   'Sales approval', 'sales', '', 'always', NULL, true, auth.uid(), auth.uid()),
  ('66666666-6666-6666-6666-666666666602', '22222222-2222-2222-2222-222222222252',
   'Large vendor bills', 'purchasing', 'Vendor Bill', 'amount_exceeds', 10000, true,
   auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON t_ctx TO authenticated;

CREATE FUNCTION pg_temp.save_si(p_date date, p_amount numeric)
RETURNS uuid LANGUAGE sql AS $$
  SELECT fn_save_sales_invoice(NULL,
    jsonb_build_object(
      'company_id',                '22222222-2222-2222-2222-222222222252',
      'branch_id',                 '33333333-3333-3333-3333-333333333352',
      'date',                      p_date,
      'customer_id',               '55555555-5555-5555-5555-555555555581',
      'customer_name_snapshot',    'SoD Customer Inc',
      'customer_tin_snapshot',     '444-555-666-052',
      'customer_address_snapshot', 'Customer HQ, Taguig'
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Consulting services',
      'quantity',           1,
      'unit_price',         p_amount,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000103'
    )));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.save_si(date, numeric) TO authenticated;

-- ══════════════════════════════════════════════════════════════════════════════
-- All assertions below run as the `authenticated` role.
-- ══════════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111151');

-- ── Workflow matching ──────────────────────────────────────────────────────────
SELECT is(
  fn_required_approval_workflow('22222222-2222-2222-2222-222222222252',
    'sales', 'Sales Invoice', 11200),
  '66666666-6666-6666-6666-666666666601'::uuid,
  'blank-document-type sales workflow governs sales invoices');

SELECT is(
  fn_required_approval_workflow('22222222-2222-2222-2222-222222222252',
    'sales', 'Official Receipt', 500),
  '66666666-6666-6666-6666-666666666601'::uuid,
  'blank-document-type sales workflow governs official receipts too');

SELECT ok(
  fn_required_approval_workflow('22222222-2222-2222-2222-222222222252',
    'purchasing', 'Vendor Bill', 5000) IS NULL,
  'vendor bill below the amount threshold needs no approval');

SELECT is(
  fn_required_approval_workflow('22222222-2222-2222-2222-222222222252',
    'purchasing', 'Vendor Bill', 15000),
  '66666666-6666-6666-6666-666666666602'::uuid,
  'vendor bill above the amount threshold needs approval');

-- ── Approval setup stays owner/admin ───────────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111153');
SELECT throws_ok(
  $q$INSERT INTO approval_workflows (company_id, workflow_name, module_type,
        document_type, trigger_condition_type, is_active, created_by, updated_by)
     VALUES ('22222222-2222-2222-2222-222222222252', 'Member workflow', 'sales',
        '', 'always', true, auth.uid(), auth.uid())$q$,
  '42501', NULL, 'member cannot configure approval workflows');

-- ── Self-approval blocked; admin approval recorded; creator may post ───────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111151');
INSERT INTO t_ctx SELECT 'si1', pg_temp.save_si('2026-05-10', 10000);

SELECT throws_like(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si1')),
  '%segregation of duties%',
  'creator cannot approve their own sales invoice when a workflow is configured');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111152');
SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si1')),
  'a different admin can approve the sales invoice');

SELECT is(
  (SELECT count(*)::int FROM approval_instances
   WHERE source_document_id = (SELECT id FROM t_ctx WHERE key='si1')
     AND workflow_id = '66666666-6666-6666-6666-666666666601'
     AND status = 'approved'
     AND actual_approver_id = '11111111-1111-1111-1111-111111111152'
     AND acted_at IS NOT NULL),
  1, 'the approval is recorded as an instance with actor and timestamp');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111151');
SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si1')),
  'the creator may post once someone else approved');

-- ── Direct status-UPDATE shortcut is equally gated ─────────────────────────────
INSERT INTO t_ctx SELECT 'si2', pg_temp.save_si('2026-05-11', 20000);

SELECT throws_like(
  format($q$UPDATE sales_invoices SET status = 'approved', updated_by = auth.uid()
         WHERE id = %L$q$, (SELECT id FROM t_ctx WHERE key='si2')),
  '%segregation of duties%',
  'creator cannot self-approve through a direct status update either');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111152');
SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si2')),
  'admin approves the second invoice');

-- ── Posting requires a qualifying approval ─────────────────────────────────────
-- Simulate a pre-migration/legacy state: no instance, approved_by = creator.
RESET ROLE;
DELETE FROM approval_instances
WHERE source_document_id = (SELECT id FROM t_ctx WHERE key='si2');
UPDATE sales_invoices
SET approved_by = '11111111-1111-1111-1111-111111111151'
WHERE id = (SELECT id FROM t_ctx WHERE key='si2');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111151');

SELECT throws_like(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si2')),
  '%approval by someone other than the creator%',
  'posting is blocked without a qualifying approval (self-approved legacy evidence rejected)');

RESET ROLE;
UPDATE sales_invoices
SET approved_by = '11111111-1111-1111-1111-111111111152'
WHERE id = (SELECT id FROM t_ctx WHERE key='si2');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111151');

SELECT lives_ok(
  format('SELECT fn_post_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si2')),
  'legacy approved_by evidence from a different approver satisfies the post gate');

-- ── Deactivated workflow restores plain role-gate behavior ─────────────────────
UPDATE approval_workflows SET is_active = false
WHERE id = '66666666-6666-6666-6666-666666666601';

INSERT INTO t_ctx SELECT 'si3', pg_temp.save_si('2026-05-12', 3000);
SELECT lives_ok(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT id FROM t_ctx WHERE key='si3')),
  'with no active workflow the owner may approve their own document (DEC-009 role gate only)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
