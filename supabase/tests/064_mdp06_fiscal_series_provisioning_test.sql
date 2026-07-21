-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-06 — Fiscal Calendar & Number Series Auto-Provisioning (gaps MD-02, MD-03)
--
-- Proves reusable backend provisioning: automatic fiscal-year + 12-period
-- generation (calendar and non-calendar starts), default BIR-document-type number
-- series per branch, idempotency/duplicate-prevention, company isolation, rollback
-- safety, admin-only authority, and audit coverage of the fiscal tables (the
-- MDP-02 mechanism, deferred here).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111661'::uuid, 'mdp06-admin@test.local'),
  ('11111111-1111-1111-1111-111111111662'::uuid, 'mdp06-member@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Company A (with two branches) administered by admin; Company B for isolation.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222661', 'corporation',
   'MDP06 Alpha Corp', 'Wholesale', '311-222-661-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp06-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-111111111661', '11111111-1111-1111-1111-111111111661'),
  ('22222222-2222-2222-2222-222222222662', 'corporation',
   'MDP06 Beta Corp', 'Services', '311-222-662-00000',
   'vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp06-admin@test.local', 'B Owner', 'President',
   '11111111-1111-1111-1111-111111111661', '11111111-1111-1111-1111-111111111661');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-111111111661', '22222222-2222-2222-2222-222222222661', 'admin'),
  ('11111111-1111-1111-1111-111111111661', '22222222-2222-2222-2222-222222222662', 'admin'),
  ('11111111-1111-1111-1111-111111111662', '22222222-2222-2222-2222-222222222661', 'member');
INSERT INTO branches (id, company_id, branch_code, branch_name, cas_permit_no, cas_date_issued,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES
  ('33333333-3333-3333-3333-333333333661', '22222222-2222-2222-2222-222222222661', 'HO', 'Head Office',
   'CAS-661-HO', '2026-01-01', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-111111111661', '11111111-1111-1111-1111-111111111661'),
  ('33333333-3333-3333-3333-333333333662', '22222222-2222-2222-2222-222222222661', 'BR2', 'Branch 2',
   'CAS-661-BR2', '2026-01-01', 'A St 2', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   '11111111-1111-1111-1111-111111111661', '11111111-1111-1111-1111-111111111661');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111661');

-- ── Fiscal year + period generation (calendar start) ──────────────────────────
SELECT fn_create_fiscal_year('22222222-2222-2222-2222-222222222661', '2026-01-01', 'FY2026');

SELECT ok(
  EXISTS (SELECT 1 FROM fiscal_years WHERE company_id='22222222-2222-2222-2222-222222222661' AND year_name='FY2026'),
  'fiscal year is created');
SELECT results_eq(
  $q$SELECT is_calendar, end_date FROM fiscal_years
     WHERE company_id='22222222-2222-2222-2222-222222222661' AND year_name='FY2026'$q$,
  $$VALUES (true, '2026-12-31'::date)$$,
  'a January-1 start yields a calendar fiscal year ending Dec 31');
SELECT is(
  (SELECT count(*)::int FROM fiscal_periods fp JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
   WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026'), 12,
  'twelve monthly periods are generated');
SELECT results_eq(
  $q$SELECT fp.period_name, fp.start_date, fp.end_date FROM fiscal_periods fp
     JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
     WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026' AND fp.period_number=1$q$,
  $$VALUES ('Jan 2026'::text, '2026-01-01'::date, '2026-01-31'::date)$$,
  'period 1 spans the first month');
SELECT results_eq(
  $q$SELECT fp.period_name, fp.start_date, fp.end_date FROM fiscal_periods fp
     JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
     WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026' AND fp.period_number=12$q$,
  $$VALUES ('Dec 2026'::text, '2026-12-01'::date, '2026-12-31'::date)$$,
  'period 12 spans the last month');
SELECT ok(
  (SELECT bool_and(NOT fp.is_locked) FROM fiscal_periods fp JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
   WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026'),
  'newly generated periods are open (unlocked)');

-- ── Idempotency / duplicate prevention ────────────────────────────────────────
SELECT is(
  fn_create_fiscal_year('22222222-2222-2222-2222-222222222661', '2026-01-01', 'FY2026'),
  (SELECT id FROM fiscal_years WHERE company_id='22222222-2222-2222-2222-222222222661' AND year_name='FY2026'),
  're-creating the same fiscal year returns the same id (idempotent)');
SELECT is(
  (SELECT count(*)::int FROM fiscal_periods fp JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
   WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026'), 12,
  're-provisioning does not duplicate periods');

-- ── Configurable (non-calendar) fiscal year start ─────────────────────────────
SELECT fn_create_fiscal_year('22222222-2222-2222-2222-222222222661', '2026-07-01', 'FY2026-JUL');
SELECT results_eq(
  $q$SELECT is_calendar, end_date FROM fiscal_years
     WHERE company_id='22222222-2222-2222-2222-222222222661' AND year_name='FY2026-JUL'$q$,
  $$VALUES (false, '2027-06-30'::date)$$,
  'a July-1 start yields a non-calendar fiscal year ending Jun 30');
SELECT results_eq(
  $q$SELECT fp.start_date, fp.end_date FROM fiscal_periods fp JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
     WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026-JUL' AND fp.period_number=1$q$,
  $$VALUES ('2026-07-01'::date, '2026-07-31'::date)$$,
  'non-calendar period 1 starts on the configured start date');
SELECT results_eq(
  $q$SELECT fp.end_date FROM fiscal_periods fp JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
     WHERE fy.company_id='22222222-2222-2222-2222-222222222661' AND fy.year_name='FY2026-JUL' AND fp.period_number=12$q$,
  $$VALUES ('2027-06-30'::date)$$,
  'non-calendar period 12 ends at fiscal year end');

-- ── Number-series provisioning (BIR document types, branch-aware) ─────────────
SELECT is(fn_provision_number_series('22222222-2222-2222-2222-222222222661',
          '33333333-3333-3333-3333-333333333661'), 3,
  'default series provisioned for the three BIR-registered document types');
SELECT results_eq(
  $q$SELECT ns.prefix, ns.number_length, ns.next_number, ns.is_active
     FROM number_series ns JOIN ref_document_types dt ON dt.id=ns.document_type_id
     WHERE ns.company_id='22222222-2222-2222-2222-222222222661'
       AND ns.branch_id='33333333-3333-3333-3333-333333333661' AND dt.document_code='SI'$q$,
  $$VALUES ('SI-'::text, 6, 1, true)$$,
  'the Sales Invoice series is provisioned with a sane default shape');
SELECT is(fn_provision_number_series('22222222-2222-2222-2222-222222222661',
          '33333333-3333-3333-3333-333333333661'), 3,
  're-provisioning the same branch does not duplicate series (idempotent)');
SELECT is(
  (SELECT count(*)::int FROM number_series
   WHERE company_id='22222222-2222-2222-2222-222222222661'
     AND branch_id='33333333-3333-3333-3333-333333333661'), 3,
  'exactly three series exist for the branch (duplicate prevention)');
SELECT is(fn_provision_number_series('22222222-2222-2222-2222-222222222661',
          '33333333-3333-3333-3333-333333333662'), 3,
  'a second branch is provisioned its own series (branch-aware numbering)');

-- ── Company isolation ─────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM fiscal_years WHERE company_id='22222222-2222-2222-2222-222222222662'), 0,
  'provisioning company A does not create fiscal years for company B (isolation)');

-- ── Audit coverage of the fiscal tables (MDP-02 mechanism, deferred to MDP-06) ─
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs sl
   JOIN fiscal_years fy ON fy.id=sl.record_id
   WHERE sl.table_name='fiscal_years' AND sl.action='INSERT'
     AND fy.company_id='22222222-2222-2222-2222-222222222661') >= 2,
  'fiscal year creation is captured in the audit trail');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='fiscal_periods' AND action='INSERT' AND company_id='22222222-2222-2222-2222-222222222661') >= 12,
  'generated fiscal periods are captured in the audit trail');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name='number_series' AND action='INSERT' AND company_id='22222222-2222-2222-2222-222222222661') >= 3,
  'provisioned number series are captured in the audit trail (existing coverage intact)');

-- ── Rollback safety ───────────────────────────────────────────────────────────
SAVEPOINT sp_fy;
SELECT fn_create_fiscal_year('22222222-2222-2222-2222-222222222662', '2026-01-01', 'FY2026-B');
SELECT is((SELECT count(*)::int FROM fiscal_periods fp JOIN fiscal_years fy ON fy.id=fp.fiscal_year_id
           WHERE fy.company_id='22222222-2222-2222-2222-222222222662'), 12,
  'company B fiscal periods present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_fy;
SELECT is((SELECT count(*)::int FROM fiscal_years WHERE company_id='22222222-2222-2222-2222-222222222662'), 0,
  'rolling back removes the provisioned fiscal year and periods (atomic)');

-- ── Authority: a non-admin member cannot provision ───────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111662');
SELECT throws_ok(
  $q$SELECT fn_create_fiscal_year('22222222-2222-2222-2222-222222222661', '2027-01-01', 'FY2027')$q$,
  '42501', NULL, 'a non-admin member cannot create a fiscal year');
SELECT throws_ok(
  $q$SELECT fn_provision_number_series('22222222-2222-2222-2222-222222222661', '33333333-3333-3333-3333-333333333661')$q$,
  '42501', NULL, 'a non-admin member cannot provision number series');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
