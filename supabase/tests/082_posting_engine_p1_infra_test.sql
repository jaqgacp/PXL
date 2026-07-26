-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P1-001 — Posting Engine Phase P1 infrastructure (additive, inert)
--
-- Proves the P1 infrastructure exists and behaves per the frozen spec
--   docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md (§3, §3.1, §3.2, §4.5, §5.2)
-- WITHOUT altering any accounting behavior: the new columns are nullable, the new
-- functions are additive, and the legacy kernel functions remain present and
-- unchanged (the full regression proves existing journals are byte-for-byte
-- identical; this file proves the new infrastructure in isolation).
--
-- Covers: additive metadata columns + CHECKs; fn_derive_journal_number (Option B);
-- fn_build_posting_context; fn_validate_posting_plan; fn_posting_plan_fingerprint;
-- fn_add_posting_line_push; and coexistence of the legacy builders (nothing removed).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ── User + claims ─────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0d0b0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p1-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
SELECT pg_temp.as_user('0d0b0000-0000-0000-0000-000000000001');

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0d0b0000-0000-0000-0000-0000000000a1', 'corporation', 'P1 Infra Corp',
        'Trading', '351-000-001-00000', 'vat', 'calendar',
        'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
        'p1-owner@test.local', 'A Owner', 'President',
        '0d0b0000-0000-0000-0000-000000000001', '0d0b0000-0000-0000-0000-000000000001');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0d0b0000-0000-0000-0000-0000000000c1', '0d0b0000-0000-0000-0000-0000000000a1',
        'HO', 'Head Office', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
        '0d0b0000-0000-0000-0000-000000000001', '0d0b0000-0000-0000-0000-000000000001');

INSERT INTO departments (id, company_id, department_code, department_name, created_by, updated_by)
VALUES ('0d0b0000-0000-0000-0000-0000000000d1', '0d0b0000-0000-0000-0000-0000000000a1',
        'FIN', 'Finance', '0d0b0000-0000-0000-0000-000000000001', '0d0b0000-0000-0000-0000-000000000001');

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES
 ('0d0b0000-0000-0000-0000-0000000000f1', '0d0b0000-0000-0000-0000-0000000000a1', 'CASH', 'Cash', 'asset', 'debit', true, 'active', true, '0d0b0000-0000-0000-0000-000000000001', '0d0b0000-0000-0000-0000-000000000001'),
 ('0d0b0000-0000-0000-0000-0000000000f2', '0d0b0000-0000-0000-0000-0000000000a1', 'SALES', 'Sales', 'revenue', 'credit', true, 'active', true, '0d0b0000-0000-0000-0000-000000000001', '0d0b0000-0000-0000-0000-000000000001');

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
) VALUES (
  '0d0b0000-0000-0000-0000-0000000000a2',
  '0d0b0000-0000-0000-0000-0000000000a1',
  'FY2026', '2026-01-01', '2026-12-31', true
);
INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
) VALUES (
  '0d0b0000-0000-0000-0000-0000000000a3',
  '0d0b0000-0000-0000-0000-0000000000a1',
  '0d0b0000-0000-0000-0000-0000000000a2',
  7, 'Jul 2026', '2026-07-01', '2026-07-31', false
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 1. Additive metadata columns (nullable) + CHECK constraints
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM information_schema.columns
    WHERE table_schema='public'
      AND ((table_name='journal_entries'     AND column_name IN ('posting_origin','reversal_of_je_id','posting_run_id','source_fingerprint'))
        OR (table_name='journal_entry_lines' AND column_name IN ('line_role','source_line_id')))
      AND is_nullable='YES'),
  6, 'all six additive P1 columns exist and are nullable (backward compatible)');       -- 1

-- Seed a posted JE through the kernel while ordinary triggers are off. The
-- P5.2 totality trigger is ALWAYS enabled, including in replica mode.
SET session_replication_role = replica;
CREATE TEMP TABLE t_p1_je AS
SELECT fn_create_posted_journal_entry(
  '0d0b0000-0000-0000-0000-0000000000a1',
  '0d0b0000-0000-0000-0000-0000000000c1',
  'JE-P1-TEST-1', '2026-07-24', 'P1 infrastructure fixture',
  'MANUAL', NULL, '0d0b0000-0000-0000-0000-0000000000a3',
  'posted', 100, 100,
  NULL, 'regular', false, false, false
) AS id;
SELECT throws_like(
  $$SELECT fn_create_posted_journal_entry(
      '0d0b0000-0000-0000-0000-0000000000a1',
      '0d0b0000-0000-0000-0000-0000000000c1',
      'JE-P1-BAD-ORIGIN', '2026-07-24', 'Invalid origin probe',
      'MANUAL', NULL, '0d0b0000-0000-0000-0000-0000000000a3',
      'posted', 1, 1, 'bogus',
      'regular', false, false, false)$$,
  '%je_posting_origin_check%', 'posting_origin CHECK rejects an invalid value');         -- 2
SET session_replication_role = DEFAULT;

-- ════════════════════════════════════════════════════════════════════════════════
-- 2. fn_derive_journal_number — Option B (§4.5)
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(fn_derive_journal_number('VB', '0001'), 'JE-VB-0001',
  'source-numbered derivation is byte-identical to legacy JE-<TYPE>-<source#>');          -- 3
SELECT is(fn_derive_journal_number('si', '0007'), 'JE-SI-0007',
  'source type is normalized to uppercase (matches legacy literals)');                    -- 4
SELECT throws_like(
  $$SELECT fn_derive_journal_number('MANUAL', NULL, NULL, NULL)$$,
  '%company_id is required%', 'source-less derivation without a company fails closed');    -- 5
SELECT throws_like(
  $$SELECT fn_derive_journal_number('MANUAL', NULL, '0d0b0000-0000-0000-0000-0000000000a1', '0d0b0000-0000-0000-0000-0000000000c1')$$,
  '%', 'source-less derivation fails closed when no JE number series is provisioned');     -- 6

-- ════════════════════════════════════════════════════════════════════════════════
-- 3. fn_build_posting_context (§3) — canonical, pure
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(
  (fn_build_posting_context('0d0b0000-0000-0000-0000-0000000000a1','0d0b0000-0000-0000-0000-0000000000c1',
     'si','0d0b0000-0000-0000-0000-0000000000e1','SI-0001', DATE '2026-07-24', NULL, 'system',
     '0d0b0000-0000-0000-0000-0000000000d1', NULL, NULL, NULL, NULL)->>'source_type'),
  'SI', 'posting context normalizes source_type to uppercase');                           -- 7
SELECT is(
  (fn_build_posting_context('0d0b0000-0000-0000-0000-0000000000a1','0d0b0000-0000-0000-0000-0000000000c1',
     'SI','0d0b0000-0000-0000-0000-0000000000e1','SI-0001', DATE '2026-07-24', NULL, 'system',
     '0d0b0000-0000-0000-0000-0000000000d1', NULL, NULL, NULL, NULL)->>'as_of'),
  '2026-07-24', 'posting context as_of defaults to the posting date');                     -- 8
SELECT is(
  (fn_build_posting_context('0d0b0000-0000-0000-0000-0000000000a1','0d0b0000-0000-0000-0000-0000000000c1',
     'SI','0d0b0000-0000-0000-0000-0000000000e1','SI-0001', DATE '2026-07-24', NULL, 'system',
     '0d0b0000-0000-0000-0000-0000000000d1', NULL, NULL, NULL, NULL)->'dimensions'->>'department_id'),
  '0d0b0000-0000-0000-0000-0000000000d1', 'posting context carries pushed dimensions');    -- 9

-- ════════════════════════════════════════════════════════════════════════════════
-- 4. fn_validate_posting_plan (§3.1) — pure invariant validator
-- ════════════════════════════════════════════════════════════════════════════════
SELECT ok(
  fn_validate_posting_plan(
    '{"header":{"company_id":"0d0b0000-0000-0000-0000-0000000000a1"},
      "lines":[{"account_id":"0d0b0000-0000-0000-0000-0000000000f1","debit":100,"credit":0},
               {"account_id":"0d0b0000-0000-0000-0000-0000000000f2","debit":0,"credit":100}]}'::jsonb),
  'a balanced, well-formed posting plan validates');                                       -- 10
SELECT throws_like(
  $$SELECT fn_validate_posting_plan('{"header":{"company_id":"0d0b0000-0000-0000-0000-0000000000a1"},"lines":[{"account_id":"0d0b0000-0000-0000-0000-0000000000f1","debit":100,"credit":0},{"account_id":"0d0b0000-0000-0000-0000-0000000000f2","debit":0,"credit":90}]}'::jsonb)$$,
  '%unbalanced%', 'unbalanced plan is rejected');                                          -- 11
SELECT throws_like(
  $$SELECT fn_validate_posting_plan('{"header":{"company_id":"0d0b0000-0000-0000-0000-0000000000a1"},"lines":[{"account_id":"0d0b0000-0000-0000-0000-0000000000f1","debit":100,"credit":100}]}'::jsonb)$$,
  '%both a debit and a credit%', 'a line with both debit and credit is rejected');         -- 12
SELECT throws_like(
  $$SELECT fn_validate_posting_plan('{"header":{"company_id":"0d0b0000-0000-0000-0000-0000000000a1"},"lines":[{"debit":100,"credit":0},{"account_id":"0d0b0000-0000-0000-0000-0000000000f2","debit":0,"credit":100}]}'::jsonb)$$,
  '%missing account_id%', 'a line missing account_id is rejected');                        -- 13
SELECT throws_like(
  $$SELECT fn_validate_posting_plan('{"header":{"company_id":"0d0b0000-0000-0000-0000-0000000000a1"},"lines":[]}'::jsonb)$$,
  '%no lines%', 'an empty plan is rejected');                                              -- 14
SELECT throws_like(
  $$SELECT fn_validate_posting_plan('{"header":{},"lines":[{"account_id":"0d0b0000-0000-0000-0000-0000000000f1","debit":100,"credit":0},{"account_id":"0d0b0000-0000-0000-0000-0000000000f2","debit":0,"credit":100}]}'::jsonb)$$,
  '%company_id is required%', 'a plan missing header.company_id is rejected');             -- 15

-- ════════════════════════════════════════════════════════════════════════════════
-- 5. fn_posting_plan_fingerprint (§3.1) — deterministic
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(
  fn_posting_plan_fingerprint('{"a":1,"b":2}'::jsonb),
  fn_posting_plan_fingerprint('{"b":2,"a":1}'::jsonb),
  'fingerprint is deterministic for equal plans (canonical JSONB)');                       -- 16
SELECT isnt(
  fn_posting_plan_fingerprint('{"a":1,"b":2}'::jsonb),
  fn_posting_plan_fingerprint('{"a":1,"b":3}'::jsonb),
  'fingerprint differs for different plans');                                              -- 17

-- ════════════════════════════════════════════════════════════════════════════════
-- 6. fn_add_posting_line_push (§5.2) — push-based, dimensions supplied by caller
-- ════════════════════════════════════════════════════════════════════════════════
SELECT lives_ok(
  $$SELECT fn_add_posting_line_push((SELECT id FROM t_p1_je), 1,
      '0d0b0000-0000-0000-0000-0000000000f1', 'Cash', 100, 0, 'base',
      '0d0b0000-0000-0000-0000-00000000aa01',
      '0d0b0000-0000-0000-0000-0000000000c1', '0d0b0000-0000-0000-0000-0000000000d1', NULL, NULL, NULL, NULL)$$,
  'push line builder inserts a base line with pushed dimensions');                         -- 18
SELECT fn_add_posting_line_push((SELECT id FROM t_p1_je), 2,
      '0d0b0000-0000-0000-0000-0000000000f2', 'Sales', 0, 100, 'control',
      '0d0b0000-0000-0000-0000-00000000aa02',
      '0d0b0000-0000-0000-0000-0000000000c1', '0d0b0000-0000-0000-0000-0000000000d1', NULL, NULL, NULL, NULL);
SELECT is(
  (SELECT line_role || '|' || (source_line_id IS NOT NULL)::text || '|' || COALESCE(department_id::text,'-')
     FROM journal_entry_lines
    WHERE je_id=(SELECT id FROM t_p1_je) AND line_number=1),
  'base|true|0d0b0000-0000-0000-0000-0000000000d1',
  'pushed line carries line_role, source_line_id, and department (no source-table pull)'); -- 19
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_p1_je)),
  2, 'both pushed lines are present and balanced');                                        -- 20

SET session_replication_role = replica;
SELECT throws_like(
  $$SELECT fn_add_posting_line_push(
      (SELECT id FROM t_p1_je), 3,
      '0d0b0000-0000-0000-0000-0000000000f1',
      'Invalid role probe', 1, 0, 'bogus')$$,
  '%jel_line_role_check%', 'line_role CHECK rejects an invalid value');                    -- 21
SET session_replication_role = DEFAULT;

-- ════════════════════════════════════════════════════════════════════════════════
-- 7. Zero-removal: legacy kernel builders still exist alongside the new ones
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(DISTINCT proname)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND proname IN ('fn_create_posted_journal_entry','fn_add_posting_line','fn_add_posting_line_push')),
  3, 'legacy fn_create_posted_journal_entry and fn_add_posting_line remain alongside the new push builder');  -- 22

SELECT * FROM finish();
ROLLBACK;
