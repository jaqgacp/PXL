-- ══════════════════════════════════════════════════════════════════════════════
-- JE-DIMS-001 - Dimension propagation to JE lines (PXL-DA-017, DEC-011)
--
-- Exercises as the `authenticated` role: document branch propagates to the JE
-- header and every line inherits it; manual JE lines accept explicit
-- department/cost-center dimensions and fall back to the header branch;
-- reversal lines carry the original line dimensions; company-consistency is
-- enforced for header branch, line company, and line dimensions; and
-- vw_general_ledger branch/dimension columns reconcile a branch P&L to the
-- posted source document.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ── User and companies ─────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111191', 'authenticated', 'authenticated',
        'dims-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111191');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222291', 'corporation',
   'Dims Test Corp', 'Software Services', '111-222-333-091',
   'vat', 'calendar', 'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
   'dims-owner@test.local', 'Juan Dela Cruz', 'President', auth.uid(), auth.uid()),
  ('22222222-2222-2222-2222-222222222292', 'corporation',
   'Other Dims Corp', 'Trading', '111-222-333-092',
   'vat', 'calendar', 'Unit 2', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
   'dims-owner@test.local', 'Juan Dela Cruz', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES
  ('33333333-3333-3333-3333-333333333391', '22222222-2222-2222-2222-222222222291',
   'HO', 'Head Office', 'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
   auth.uid(), auth.uid()),
  ('33333333-3333-3333-3333-333333333392', '22222222-2222-2222-2222-222222222292',
   'XB', 'Foreign Branch', 'Unit 2', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
   auth.uid(), auth.uid());

INSERT INTO departments (id, company_id, department_code, department_name, created_by, updated_by)
VALUES
  ('77777777-7777-7777-7777-777777777791', '22222222-2222-2222-2222-222222222291',
   'FIN', 'Finance', auth.uid(), auth.uid()),
  ('77777777-7777-7777-7777-777777777792', '22222222-2222-2222-2222-222222222292',
   'OPS', 'Other Co Ops', auth.uid(), auth.uid());

INSERT INTO cost_centers (id, company_id, cost_center_code, cost_center_name, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-888888888891', '22222222-2222-2222-2222-222222222291',
        'CC-01', 'Head Office Admin', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444491',
        '22222222-2222-2222-2222-222222222291',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222291',
       '44444444-4444-4444-4444-444444444491',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000191', '22222222-2222-2222-2222-222222222291',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000192', '22222222-2222-2222-2222-222222222291',
   '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000193', '22222222-2222-2222-2222-222222222291',
   '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000194', '22222222-2222-2222-2222-222222222291',
   '6010', 'Office Supplies Expense', 'expense', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222291',
        'aaaaaaaa-0000-0000-0000-000000000191',
        'aaaaaaaa-0000-0000-0000-000000000192',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222291',
       '33333333-3333-3333-3333-333333333391',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code = 'SI';

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555591',
        '22222222-2222-2222-2222-222222222291', 'CUST-001',
        'Dims Customer Inc', '444-555-666-091',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON t_ctx TO authenticated;

-- ══════════════════════════════════════════════════════════════════════════════
-- All assertions below run as the `authenticated` role.
-- ══════════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111191');

-- ── 1-3. Document branch propagates: SI post → JE header + every line ─────────
INSERT INTO t_ctx SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222291',
    'branch_id',                 '33333333-3333-3333-3333-333333333391',
    'date',                      '2026-05-10',
    'customer_id',               '55555555-5555-5555-5555-555555555591',
    'customer_name_snapshot',    'Dims Customer Inc',
    'customer_tin_snapshot',     '444-555-666-091',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000193'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

INSERT INTO t_ctx SELECT 'si_je', je.id FROM journal_entries je
WHERE je.reference_doc_id = (SELECT id FROM t_ctx WHERE key='si')
  AND je.company_id = '22222222-2222-2222-2222-222222222291';

SELECT is(
  (SELECT branch_id FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')),
  '33333333-3333-3333-3333-333333333391'::uuid,
  'SI posting stamps the document branch on the JE header');

SELECT is(
  (SELECT count(*) FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je') AND branch_id IS NULL),
  0::bigint,
  'no SI JE line is missing a branch');

SELECT is(
  (SELECT count(DISTINCT branch_id) FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je')),
  1::bigint,
  'every SI JE line inherited the header branch');

-- ── 4-6. Manual JE: line dims accepted, branch falls back to header ────────────
INSERT INTO t_ctx SELECT 'mje', fn_post_manual_je(
  '22222222-2222-2222-2222-222222222291',
  '33333333-3333-3333-3333-333333333391',
  '2026-05-15', 'Supplies accrual', NULL, false,
  jsonb_build_array(
    jsonb_build_object(
      'account_id',    'aaaaaaaa-0000-0000-0000-000000000194',
      'debit_amount',  500,
      'department_id', '77777777-7777-7777-7777-777777777791',
      'cost_center_id','88888888-8888-8888-8888-888888888891'),
    jsonb_build_object(
      'account_id',    'aaaaaaaa-0000-0000-0000-000000000191',
      'credit_amount', 500)
  ));

SELECT is(
  (SELECT department_id FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='mje') AND line_number = 1),
  '77777777-7777-7777-7777-777777777791'::uuid,
  'manual JE line carries its explicit department');

SELECT is(
  (SELECT cost_center_id FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='mje') AND line_number = 1),
  '88888888-8888-8888-8888-888888888891'::uuid,
  'manual JE line carries its explicit cost center');

SELECT is(
  (SELECT count(*) FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='mje')
     AND branch_id = '33333333-3333-3333-3333-333333333391'),
  2::bigint,
  'manual JE lines without an explicit branch inherit the header branch');

-- ── 7-8. Reversal preserves line dimensions ────────────────────────────────────
INSERT INTO t_ctx SELECT 'rev', fn_reverse_je((SELECT id FROM t_ctx WHERE key='mje'), '2026-05-20');

SELECT is(
  (SELECT department_id FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='rev') AND line_number = 1),
  '77777777-7777-7777-7777-777777777791'::uuid,
  'reversal line preserves the original department');

SELECT is(
  (SELECT cost_center_id FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='rev') AND line_number = 1),
  '88888888-8888-8888-8888-888888888891'::uuid,
  'reversal line preserves the original cost center');

-- ── 9-12. Company-consistency enforcement ──────────────────────────────────────
SELECT throws_like(
  $q$SELECT fn_post_manual_je(
      '22222222-2222-2222-2222-222222222291',
      '33333333-3333-3333-3333-333333333392',
      '2026-05-15', 'Cross-company branch', NULL, false,
      jsonb_build_array(
        jsonb_build_object('account_id','aaaaaaaa-0000-0000-0000-000000000194','debit_amount',100),
        jsonb_build_object('account_id','aaaaaaaa-0000-0000-0000-000000000191','credit_amount',100)
      ))$q$,
  '%does not belong to company%',
  'JE header branch from another company is rejected');

SELECT throws_like(
  $q$SELECT fn_post_manual_je(
      '22222222-2222-2222-2222-222222222291',
      '33333333-3333-3333-3333-333333333391',
      '2026-05-15', 'Cross-company department', NULL, false,
      jsonb_build_array(
        jsonb_build_object('account_id','aaaaaaaa-0000-0000-0000-000000000194','debit_amount',100,
                           'department_id','77777777-7777-7777-7777-777777777792'),
        jsonb_build_object('account_id','aaaaaaaa-0000-0000-0000-000000000191','credit_amount',100)
      ))$q$,
  '%does not belong to company%',
  'JE line department from another company is rejected');

SELECT throws_like(
  $q$SELECT fn_post_manual_je(
      '22222222-2222-2222-2222-222222222291',
      '33333333-3333-3333-3333-333333333391',
      '2026-05-15', 'Cross-company line branch', NULL, false,
      jsonb_build_array(
        jsonb_build_object('account_id','aaaaaaaa-0000-0000-0000-000000000194','debit_amount',100,
                           'branch_id','33333333-3333-3333-3333-333333333392'),
        jsonb_build_object('account_id','aaaaaaaa-0000-0000-0000-000000000191','credit_amount',100)
      ))$q$,
  '%does not belong to company%',
  'JE line branch from another company is rejected');

-- Direct UPDATE is filtered by RLS (0 rows) before the guard can raise; either
-- layer blocking it keeps line company welded to the JE company. Prove the
-- post-state: the attempted divergence changes nothing.
UPDATE journal_entry_lines
SET company_id = '22222222-2222-2222-2222-222222222292'
WHERE je_id = (SELECT id FROM t_ctx WHERE key='mje') AND line_number = 1;

SELECT is(
  (SELECT company_id FROM journal_entry_lines
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='mje') AND line_number = 1),
  '22222222-2222-2222-2222-222222222291'::uuid,
  'JE line company cannot diverge from the journal entry company');

-- ── 13-14. vw_general_ledger: line-accurate dimensions and branch P&L ──────────
SELECT is(
  (SELECT department_id FROM vw_general_ledger
   WHERE je_id = (SELECT id FROM t_ctx WHERE key='mje') AND line_number = 1),
  '77777777-7777-7777-7777-777777777791'::uuid,
  'vw_general_ledger exposes the line department');

-- Branch P&L for HO = SI revenue (net of VAT): 10,000.00. The reversed manual
-- JE nets to zero and touched no revenue accounts anyway.
SELECT is(
  (SELECT SUM(credit_amount - debit_amount) FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222291'
     AND branch_id = '33333333-3333-3333-3333-333333333391'
     AND account_type = 'revenue'),
  10000.00::numeric,
  'branch P&L revenue from vw_general_ledger reconciles to the posted SI');

SELECT * FROM finish();
ROLLBACK;
