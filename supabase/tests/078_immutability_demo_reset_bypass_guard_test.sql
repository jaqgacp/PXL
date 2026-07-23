-- ══════════════════════════════════════════════════════════════════════════════
-- AUD070-001 — Posted-document immutability cannot be bypassed by a user GUC
--
-- PXL-AUD-070: the immutability guard family (fn_guard_doc_header,
-- fn_guard_doc_lines, fn_block_*_line_mutation_after_draft) previously
-- short-circuited whenever the session GUC `pxl.allow_demo_reset` was 'on'.
-- Because that placeholder GUC is USERSET, ANY authenticated user could set it
-- and then UPDATE/DELETE posted documents. The bypass is now gated on
-- `fn_demo_reset_bypass_authorized()` — the GUC AND a privileged `session_user`
-- (rolsuper OR rolbypassrls). PostgREST callers connect as `session_user =
-- authenticator` (unprivileged), so the GUC alone can never disable immutability.
--
-- Harness note: pgTAP connects as `postgres`, which is BYPASSRLS but NOT a
-- superuser, so this file cannot `SET SESSION AUTHORIZATION` to lower
-- `session_user`. The production-identical attack (real `authenticator`
-- connection → SET ROLE authenticated → GUC on → blocked) is executed and
-- recorded in the PXL-AUD-070 finding. This file proves the same guarantee
-- three deterministic ways: (a) direct-SQL immutability still blocks with the
-- GUC off; (b) the privileged-role classifier rejects every PostgREST role even
-- with the GUC on; (c) a permanent static guard fails if any function reads the
-- bypass GUC without routing through the privileged gate.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Fixtures (committed so tamper attempts run in a later transaction) ─────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '17777777-0000-0000-0000-000000000078', 'authenticated', 'authenticated',
        'aud070-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

-- Provision as the owner so the accounting-lifecycle admin guard admits a posted
-- document. Claims are session-level so they survive the COMMIT below.
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '17777777-0000-0000-0000-000000000078',
                    'role', 'authenticated')::text, false);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('27777777-0000-0000-0000-000000000078', 'corporation',
        'AUD070 Immutability Corp', 'Wholesale', '111-070-078-00000',
        'vat', 'calendar', 'Unit 78', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'aud070-owner@test.local', 'Juan Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES ('17777777-0000-0000-0000-000000000078',
        '27777777-0000-0000-0000-000000000078', 'owner')
ON CONFLICT (user_id, company_id) DO UPDATE SET role = 'owner';

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('37777777-0000-0000-0000-000000000078', '27777777-0000-0000-0000-000000000078',
        'HO', 'Head Office', 'Unit 78', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES ('a7000000-0000-0000-0000-000000000078', '27777777-0000-0000-0000-000000000078',
        '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           account_type, gl_account_id, created_at, updated_at)
VALUES ('b7000000-0000-0000-0000-000000000078', '27777777-0000-0000-0000-000000000078',
        'BDO', '00780078', 'AUD070 Operating', 'checking',
        'a7000000-0000-0000-0000-000000000078', now(), now());

INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
                            bank_account_id, check_number, check_date, payee,
                            total_gross_amount, particulars, status,
                            posted_at, posted_by, created_by, updated_by)
VALUES ('c7000000-0000-0000-0000-000000000078', '27777777-0000-0000-0000-000000000078',
        '37777777-0000-0000-0000-000000000078', 'CV-AUD070-078', '2026-05-10',
        'b7000000-0000-0000-0000-000000000078', 'CHK-078', '2026-05-10', 'Original Payee Inc',
        1000, 'Office supplies', 'posted',
        now(), auth.uid(), auth.uid(), auth.uid());

INSERT INTO check_voucher_lines (id, cv_id, company_id, line_number,
                                 expense_account_id, description, amount,
                                 created_by, updated_by)
VALUES ('c7100000-0000-0000-0000-000000000078', 'c7000000-0000-0000-0000-000000000078',
        '27777777-0000-0000-0000-000000000078', 1,
        'a7000000-0000-0000-0000-000000000078', 'Supplies', 1000, auth.uid(), auth.uid());

COMMIT;

-- ══════════════════════════════════════════════════════════════════════════════
-- Each statement below runs in its own transaction, like a PostgREST call.
-- `pxl.allow_demo_reset` is OFF here (default), so the guards enforce normally.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1-3. Direct-SQL immutability still blocks (GUC off) ────────────────────────
SELECT throws_like(
  $q$UPDATE check_vouchers SET payee = 'tampered'
     WHERE id = 'c7000000-0000-0000-0000-000000000078'$q$,
  '%immutable%',
  'posted check voucher header cannot be updated by direct SQL');

SELECT throws_like(
  $q$DELETE FROM check_voucher_lines
     WHERE cv_id = 'c7000000-0000-0000-0000-000000000078'$q$,
  '%cannot be changed%',
  'posted check voucher line cannot be deleted by direct SQL');

SELECT throws_like(
  $q$UPDATE check_voucher_lines SET amount = amount + 999
     WHERE cv_id = 'c7000000-0000-0000-0000-000000000078'$q$,
  '%cannot be changed%',
  'posted check voucher line amount cannot be updated by direct SQL');

-- ── 4-8. The privileged-role classifier rejects every PostgREST role ──────────
SELECT ok(NOT fn_role_is_privileged_maintenance('authenticated'),
  'authenticated is not a privileged maintenance role');
SELECT ok(NOT fn_role_is_privileged_maintenance('authenticator'),
  'authenticator (the PostgREST login role) is not a privileged maintenance role');
SELECT ok(NOT fn_role_is_privileged_maintenance('anon'),
  'anon is not a privileged maintenance role');
SELECT ok(fn_role_is_privileged_maintenance('postgres'),
  'postgres (maintenance connection) is a privileged maintenance role');
SELECT ok(fn_role_is_privileged_maintenance('service_role'),
  'service_role (trusted server context) is a privileged maintenance role');

-- ── 9. With the GUC OFF, the bypass gate denies (baseline) ─────────────────────
SELECT ok(NOT fn_demo_reset_bypass_authorized(),
  'the demo-reset bypass is not authorized when the GUC is off');

-- ── 10-11. Turn the GUC ON; only a privileged session_user is authorized ──────
SET pxl.allow_demo_reset = 'on';

SELECT ok(fn_demo_reset_bypass_authorized(),
  'the bypass is authorized for a privileged session (postgres) with the GUC on');

SELECT ok(
  bool_and(NOT (current_setting('pxl.allow_demo_reset', true) = 'on'
                AND fn_role_is_privileged_maintenance(r))),
  'the GUC alone never authorizes a bypass for authenticator/authenticated/anon')
FROM unnest(ARRAY['authenticator','authenticated','anon']) AS r;

-- ── 12. The authorized maintenance path still works (privileged + GUC on) ──────
SELECT lives_ok(
  $q$UPDATE check_vouchers SET payee = 'MAINTENANCE-RESET-OK'
     WHERE id = 'c7000000-0000-0000-0000-000000000078'$q$,
  'a privileged maintenance context can still rewrite a posted document with the GUC on');

RESET pxl.allow_demo_reset;

-- ── 13-16. Permanent static guard against reintroducing a naked GUC bypass ─────
SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.prosrc LIKE '%allow_demo_reset%'
     AND p.proname <> 'fn_demo_reset_bypass_authorized'
     AND p.prosrc NOT LIKE '%fn_demo_reset_bypass_authorized%'),
  0,
  'no function reads pxl.allow_demo_reset for a bypass without routing through the privileged gate');

SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('fn_guard_doc_header','fn_guard_doc_lines',
                       'fn_block_si_line_mutation_after_draft',
                       'fn_block_receipt_line_mutation_after_draft',
                       'fn_block_vb_line_mutation_after_draft',
                       'fn_block_pv_line_mutation_after_draft')
     AND p.prosrc LIKE '%fn_demo_reset_bypass_authorized%'),
  6,
  'all six immutability guard functions route their demo-reset bypass through the privileged gate');

SELECT ok(
  (SELECT bool_and(p.prosrc LIKE '%session_user%'
               AND p.prosrc LIKE '%fn_role_is_privileged_maintenance%')
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_demo_reset_bypass_authorized'),
  'the bypass gate is defined in terms of session_user and the privileged-role classifier');

SELECT ok(
  (SELECT bool_and(p.prosrc LIKE '%rolsuper%' AND p.prosrc LIKE '%rolbypassrls%')
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_role_is_privileged_maintenance'),
  'the privileged-role classifier keys off rolsuper/rolbypassrls, not a user-settable value');

SELECT * FROM finish();

-- ── Company-scoped teardown (triggers disabled for the cleanup only) ───────────
-- Delete every company_id-scoped row so no numbering/CAS/audit side-table leaks
-- between repeated suite runs, then the company and its owner.
SET session_replication_role = replica;
DO $$
DECLARE
  v_table RECORD;
BEGIN
  FOR v_table IN
    SELECT DISTINCT c.table_schema, c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public'
      AND c.column_name = 'company_id'
      AND c.table_name <> 'companies'
    ORDER BY c.table_name
  LOOP
    EXECUTE format(
      'DELETE FROM %I.%I WHERE company_id = %L',
      v_table.table_schema, v_table.table_name,
      '27777777-0000-0000-0000-000000000078');
  END LOOP;
END;
$$;
DELETE FROM companies  WHERE id = '27777777-0000-0000-0000-000000000078';
DELETE FROM auth.users WHERE id = '17777777-0000-0000-0000-000000000078';
SET session_replication_role = origin;
