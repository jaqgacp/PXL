-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P52-001 — Kernel Totality Guard enforcement certification
--
-- The catalog census runs before the transaction-local attack helpers exist.
-- The negative matrix then attempts all six ledger mutations through eight
-- unauthorized paths. Every helper is rolled back with this test.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(78);

-- ──────────────────────────────────────────────────────────────────────────────
-- A. Armed configuration and complete permanent-catalog security census
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TEMP VIEW p52_app_functions AS
SELECT p.oid, p.proname, p.prosecdef, p.proacl, p.prosrc,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_depend d
    WHERE d.classid = 'pg_proc'::regclass
      AND d.objid = p.oid
      AND d.deptype = 'e'
  );

CREATE TEMP VIEW p52_direct_mutators AS
SELECT *
FROM p52_app_functions
WHERE prosrc ~*
  '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)';

CREATE TEMP VIEW p52_reachable_mutators AS
WITH RECURSIVE reachable AS (
  SELECT oid, proname, prosecdef, proacl, prosrc, identity_arguments
  FROM p52_direct_mutators
  UNION
  SELECT f.oid, f.proname, f.prosecdef, f.proacl, f.prosrc,
         f.identity_arguments
  FROM p52_app_functions f
  JOIN reachable r ON strpos(f.prosrc, r.proname || '(') > 0
)
SELECT * FROM reachable;

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM p52_app_functions p
    WHERE p.proname = 'fn_guard_journal_kernel_origin'),
  'the Kernel Totality Guard is armed with a compile-time true constant');             -- 1

SELECT ok(
  (SELECT p.prosrc !~ 'c_enforce\s+AND\s+NOT\s+v_maint'
     FROM p52_app_functions p
    WHERE p.proname = 'fn_guard_journal_kernel_origin'),
  'maintenance and replay classification is not an enforcement bypass');              -- 2

SELECT ok(
  (SELECT p.prosrc ~ 'PG_CONTEXT' AND p.prosrc !~ 'current_setting'
     FROM p52_app_functions p
    WHERE p.proname = 'fn_guard_journal_kernel_origin'),
  'kernel origin remains structural and cannot be forged with session state');         -- 3

SELECT ok(
  fn_posting_kernel_origin(
    'PL/pgSQL function fn_create_posted_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_reverse_posted_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_finalize_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_push(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_sales_invoice_posting_line(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_extra(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_finalize_journal_entry_bypass(uuid) line 1'),
  'the frozen exact-name classifier admits only sanctioned names, not lookalikes');    -- 4

SELECT set_eq(
  $$SELECT proname::text FROM p52_direct_mutators$$,
  $$VALUES ('fn_create_posted_journal_entry'),
           ('fn_reverse_posted_journal_entry'),
           ('fn_finalize_journal_entry'),
           ('fn_add_posting_line'),
           ('fn_add_posting_line_push'),
           ('fn_add_sales_invoice_posting_line')$$,
  'only the six sanctioned persistence functions contain permanent ledger DML');      -- 5

SELECT is((SELECT count(*)::int FROM p52_direct_mutators), 6,
  'the direct ledger-mutator census is exactly six');                                  -- 6

SELECT ok((SELECT bool_and(prosecdef) FROM p52_direct_mutators),
  'all six direct ledger mutators are SECURITY DEFINER');                              -- 7

SELECT is(
  (SELECT count(*)::int
     FROM p52_direct_mutators
    WHERE has_function_privilege('anon', oid, 'EXECUTE')
       OR has_function_privilege('authenticated', oid, 'EXECUTE')),
  0, 'no sanctioned persistence function is client executable');                      -- 8

SELECT set_eq(
  $$SELECT proname::text
      FROM p52_direct_mutators
     WHERE has_function_privilege('service_role', oid, 'EXECUTE')$$,
  $$VALUES ('fn_create_posted_journal_entry'),
           ('fn_add_posting_line'),
           ('fn_add_posting_line_push')$$,
  'service_role has only the three approved persistence entry points');                -- 9

SELECT is((SELECT count(*)::int FROM p52_reachable_mutators), 80,
  'the complete static ledger-capable call graph contains 80 functions');              -- 10

SELECT ok((SELECT bool_and(prosecdef) FROM p52_reachable_mutators),
  'every function in the static ledger-capable call graph is SECURITY DEFINER');       -- 11

SELECT is((SELECT count(*)::int FROM p52_app_functions), 417,
  'the complete application-owned public function census contains 417 functions');    -- 12

SELECT is((SELECT count(*)::int FROM p52_app_functions WHERE prosecdef), 354,
  'the complete application-owned SECURITY DEFINER census contains 354 functions');   -- 13

SELECT is(
  (SELECT count(*)::int FROM p52_app_functions
    WHERE has_function_privilege('authenticated', oid, 'EXECUTE')),
  295, 'authenticated EXECUTE coverage is completely counted');                       -- 14

SELECT is(
  (SELECT count(*)::int FROM p52_app_functions
    WHERE has_function_privilege('anon', oid, 'EXECUTE')),
  199, 'anon EXECUTE coverage is completely counted');                                -- 15

SELECT is(
  (SELECT count(*)::int FROM p52_app_functions
    WHERE has_function_privilege('service_role', oid, 'EXECUTE')),
  293, 'service_role EXECUTE coverage is completely counted');                        -- 16

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgrelid IN (
        'public.journal_entries'::regclass,
        'public.journal_entry_lines'::regclass)),
  21, 'the complete ledger persistence trigger census contains 21 triggers');         -- 17

SELECT ok(
  (SELECT count(*) = 2 AND bool_and(t.tgenabled = 'A')
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid = 'public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgrelid IN (
        'public.journal_entries'::regclass,
        'public.journal_entry_lines'::regclass)),
  'the armed guard is ALWAYS-enabled on both ledger tables');                         -- 18

SELECT is(
  (SELECT count(*)::int
     FROM pg_class c
    WHERE c.oid IN (
      'public.journal_entries'::regclass,
      'public.journal_entry_lines'::regclass)
      AND c.relrowsecurity),
  2, 'RLS remains enabled on both ledger tables');                                     -- 19

SELECT set_eq(
  $$SELECT tablename || ':' || policyname || ':' || cmd
      FROM pg_policies
     WHERE schemaname='public'
       AND tablename IN ('journal_entries','journal_entry_lines')$$,
  $$VALUES ('journal_entries:je_read:SELECT'),
           ('journal_entry_lines:jel_read:SELECT')$$,
  'the complete ledger RLS census is the two membership-scoped read policies');        -- 20

SELECT is(
  (SELECT count(*)::int
     FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('journal_entries','journal_entry_lines')
      AND cmd <> 'SELECT'),
  0, 'there is no ledger write policy');                                               -- 21

SELECT is(
  (SELECT count(*)::int
     FROM (VALUES ('journal_entries'), ('journal_entry_lines')) AS t(name)
    WHERE has_table_privilege('authenticated', 'public.' || t.name,
                              'INSERT,UPDATE,DELETE')),
  0, 'authenticated has no direct ledger write privilege');                           -- 22

SELECT is(
  (SELECT count(*)::int
     FROM (VALUES ('journal_entries'), ('journal_entry_lines')) AS t(name)
    WHERE has_table_privilege('anon', 'public.' || t.name,
                              'INSERT,UPDATE,DELETE')),
  0, 'anon has no direct ledger write privilege');                                    -- 23

SELECT is((SELECT count(*)::int FROM sys_posting_guard_violations), 0,
  'the pre-attack violation census is zero');                                          -- 24

-- ──────────────────────────────────────────────────────────────────────────────
-- B. Positive kernel fixture
-- ──────────────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f520000-0000-0000-0000-000000000001',
        'authenticated', 'authenticated', 'p52-owner@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"0f520000-0000-0000-0000-000000000001","role":"authenticated"}',
  true);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, address_line_1, address_line_2,
  city, province, zip_code, email, signatory_name, signatory_position,
  created_by, updated_by
) VALUES (
  '0f520000-0000-0000-0000-0000000000b1', 'corporation',
  'P52 Enforcement Corp', 'Trading', '391-000-001-00000',
  'vat', 'calendar', 'Kernel St', 'Guard Bldg', 'Makati',
  'Metro Manila', '1200', 'p52-owner@test.local', 'Kernel Owner',
  'President', auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name, address_line_1, address_line_2,
  city, province, zip_code, created_by, updated_by
) VALUES (
  '0f520000-0000-0000-0000-0000000000b2',
  '0f520000-0000-0000-0000-0000000000b1',
  'HO', 'Head Office', 'Kernel St', 'Guard Bldg', 'Makati',
  'Metro Manila', '1200', auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
) VALUES (
  '0f520000-0000-0000-0000-0000000000f1',
  '0f520000-0000-0000-0000-0000000000b1',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
) VALUES (
  '0f520000-0000-0000-0000-0000000000f2',
  '0f520000-0000-0000-0000-0000000000b1',
  '0f520000-0000-0000-0000-0000000000f1',
  6, 'Jun 2026', '2026-06-01', '2026-06-30', false
);

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name, account_type,
  normal_balance, is_postable, is_active, created_by, updated_by
) VALUES (
  '0f520000-0000-0000-0000-0000000000a1',
  '0f520000-0000-0000-0000-0000000000b1',
  '1000', 'P52 Probe Account', 'asset', 'debit', true, true,
  auth.uid(), auth.uid()
);

CREATE TEMP TABLE p52_fixture AS
SELECT fn_create_posted_journal_entry(
  '0f520000-0000-0000-0000-0000000000b1',
  '0f520000-0000-0000-0000-0000000000b2',
  'P52-GUARD-DRAFT', '2026-06-15', 'P52 authorized kernel fixture',
  'MANUAL', NULL, '0f520000-0000-0000-0000-0000000000f2',
  'draft', 0, 0, 'manual', 'regular', false, false, false
) AS header_id;

ALTER TABLE p52_fixture ADD COLUMN line_id uuid;

UPDATE p52_fixture
SET line_id = fn_add_posting_line_push(
  header_id, 1,
  '0f520000-0000-0000-0000-0000000000a1',
  'P52 authorized kernel fixture line',
  1, 0, 'base', NULL,
  '0f520000-0000-0000-0000-0000000000b2'
);

-- ──────────────────────────────────────────────────────────────────────────────
-- C. Transaction-local unauthorized helpers and six-operation matrix
-- ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.p52_probe_mutate(p_operation text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  CASE p_operation
    WHEN 'INSERT journal_entries' THEN
      INSERT INTO journal_entries (
        company_id, branch_id, je_number, je_date, fiscal_period_id,
        description, reference_doc_type, status, total_debit, total_credit,
        created_by, updated_by
      ) VALUES (
        '0f520000-0000-0000-0000-0000000000b1',
        '0f520000-0000-0000-0000-0000000000b2',
        'P52-UNAUTHORIZED', '2026-06-15',
        '0f520000-0000-0000-0000-0000000000f2',
        'unauthorized probe', 'MANUAL', 'draft', 0, 0,
        '0f520000-0000-0000-0000-000000000001',
        '0f520000-0000-0000-0000-000000000001'
      );
    WHEN 'UPDATE journal_entries' THEN
      UPDATE journal_entries
      SET description = 'unauthorized header update'
      WHERE je_number = 'P52-GUARD-DRAFT';
    WHEN 'DELETE journal_entries' THEN
      DELETE FROM journal_entries
      WHERE je_number = 'P52-GUARD-DRAFT';
    WHEN 'INSERT journal_entry_lines' THEN
      INSERT INTO journal_entry_lines (
        je_id, company_id, line_number, account_id, description,
        debit_amount, credit_amount, branch_id, created_by, updated_by
      ) VALUES (
        (SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'),
        '0f520000-0000-0000-0000-0000000000b1', 99,
        '0f520000-0000-0000-0000-0000000000a1',
        'unauthorized probe line', 1, 0,
        '0f520000-0000-0000-0000-0000000000b2',
        '0f520000-0000-0000-0000-000000000001',
        '0f520000-0000-0000-0000-000000000001'
      );
    WHEN 'UPDATE journal_entry_lines' THEN
      UPDATE journal_entry_lines
      SET description = 'unauthorized line update'
      WHERE je_id = (
        SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
      ) AND line_number = 1;
    WHEN 'DELETE journal_entry_lines' THEN
      DELETE FROM journal_entry_lines
      WHERE je_id = (
        SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
      ) AND line_number = 1;
    ELSE
      RAISE EXCEPTION 'Unknown P5.2 probe operation: %', p_operation;
  END CASE;
END;
$$;

CREATE FUNCTION public.p52_security_definer_probe(p_operation text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.p52_probe_mutate(p_operation) $$;

CREATE FUNCTION public.p52_sql_script_probe(p_operation text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.p52_probe_mutate(p_operation) $$;

CREATE FUNCTION public.p52_rpc_probe(p_operation text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.p52_probe_mutate(p_operation) $$;

CREATE FUNCTION public.p52_migration_helper_probe(p_operation text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('pxl.allow_demo_reset', 'on', true);
  PERFORM public.p52_probe_mutate(p_operation);
END;
$$;

CREATE FUNCTION public.p52_replay_helper_probe(p_operation text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('pxl.allow_demo_reset', 'on', true);
  PERFORM public.p52_probe_mutate(p_operation);
END;
$$;

REVOKE ALL ON FUNCTION public.p52_probe_mutate(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_security_definer_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_sql_script_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_rpc_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_migration_helper_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_replay_helper_probe(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.p52_rpc_probe(text) TO authenticated;

CREATE TEMP TABLE p52_operations (
  ordinal integer PRIMARY KEY,
  operation text NOT NULL,
  direct_statement text NOT NULL
);

INSERT INTO p52_operations VALUES
  (1, 'INSERT journal_entries', $sql$
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status, total_debit, total_credit,
      created_by, updated_by
    ) VALUES (
      '0f520000-0000-0000-0000-0000000000b1',
      '0f520000-0000-0000-0000-0000000000b2',
      'P52-UNAUTHORIZED', '2026-06-15',
      '0f520000-0000-0000-0000-0000000000f2',
      'unauthorized probe', 'MANUAL', 'draft', 0, 0,
      '0f520000-0000-0000-0000-000000000001',
      '0f520000-0000-0000-0000-000000000001'
    )
  $sql$),
  (2, 'UPDATE journal_entries', $sql$
    UPDATE journal_entries
    SET description = 'unauthorized header update'
    WHERE je_number = 'P52-GUARD-DRAFT'
  $sql$),
  (3, 'DELETE journal_entries', $sql$
    DELETE FROM journal_entries
    WHERE je_number = 'P52-GUARD-DRAFT'
  $sql$),
  (4, 'INSERT journal_entry_lines', $sql$
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, branch_id, created_by, updated_by
    ) VALUES (
      (SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'),
      '0f520000-0000-0000-0000-0000000000b1', 99,
      '0f520000-0000-0000-0000-0000000000a1',
      'unauthorized probe line', 1, 0,
      '0f520000-0000-0000-0000-0000000000b2',
      '0f520000-0000-0000-0000-000000000001',
      '0f520000-0000-0000-0000-000000000001'
    )
  $sql$),
  (5, 'UPDATE journal_entry_lines', $sql$
    UPDATE journal_entry_lines
    SET description = 'unauthorized line update'
    WHERE je_id = (
      SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
    ) AND line_number = 1
  $sql$),
  (6, 'DELETE journal_entry_lines', $sql$
    DELETE FROM journal_entry_lines
    WHERE je_id = (
      SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
    ) AND line_number = 1
  $sql$);

GRANT SELECT ON p52_operations TO authenticated, anon;

-- Authenticated and anon are rejected by table privileges/RLS before a trigger
-- can run. The other six paths reach the armed trigger and must receive 23514.
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  direct_statement, '42501', NULL,
  'authenticated rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 25-30
RESET ROLE;

SET LOCAL ROLE anon;
SELECT throws_ok(
  direct_statement, '42501', NULL,
  'anon rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 31-36
RESET ROLE;

SELECT throws_ok(
  format('SELECT public.p52_security_definer_probe(%L)', operation),
  '23514', NULL,
  'non-kernel SECURITY DEFINER helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 37-42

SELECT throws_ok(
  format('SELECT public.p52_sql_script_probe(%L)', operation),
  '23514', NULL,
  'SQL script helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 43-48

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  format('SELECT public.p52_rpc_probe(%L)', operation),
  '23514', NULL,
  'authenticated RPC rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 49-54
RESET ROLE;

SELECT throws_ok(
  format('SELECT public.p52_migration_helper_probe(%L)', operation),
  '23514', NULL,
  'migration helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 55-60

SET LOCAL session_replication_role = replica;
SELECT throws_ok(
  format('SELECT public.p52_replay_helper_probe(%L)', operation),
  '23514', NULL,
  'replay helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 61-66
SET LOCAL session_replication_role = origin;

SELECT throws_ok(
  direct_statement, '23514', NULL,
  'direct owner SQL rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 67-72

-- ──────────────────────────────────────────────────────────────────────────────
-- D. Positive result and rollback proof
-- ──────────────────────────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int
     FROM journal_entries
    WHERE id = (SELECT header_id FROM p52_fixture)),
  1, 'the sanctioned header kernel succeeds under enforcement');                      -- 73

SELECT is(
  (SELECT count(*)::int
     FROM journal_entry_lines
    WHERE id = (SELECT line_id FROM p52_fixture)),
  1, 'the sanctioned line kernel succeeds under enforcement');                        -- 74

SELECT results_eq(
  $q$SELECT status, posting_origin, entry_class, total_debit, total_credit
       FROM journal_entries
      WHERE id = (SELECT header_id FROM p52_fixture)$q$,
  $$VALUES ('draft'::text, 'manual'::text, 'regular'::text,
            0::numeric, 0::numeric)$$,
  'authorized header metadata is unchanged');                                         -- 75

SELECT results_eq(
  $q$SELECT line_number, line_role, debit_amount, credit_amount, branch_id
       FROM journal_entry_lines
      WHERE id = (SELECT line_id FROM p52_fixture)$q$,
  $$VALUES (1, 'base'::text, 1::numeric, 0::numeric,
            '0f520000-0000-0000-0000-0000000000b2'::uuid)$$,
  'authorized line content and ordering are unchanged');                              -- 76

SELECT is((SELECT count(*)::int FROM sys_posting_guard_violations), 0,
  'all rejected violation evidence rolls back and the census remains zero');           -- 77

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM journal_entries WHERE je_number='P52-UNAUTHORIZED'
  )
  AND (SELECT description='P52 authorized kernel fixture'
         FROM journal_entries
        WHERE id=(SELECT header_id FROM p52_fixture))
  AND (SELECT description='P52 authorized kernel fixture line'
         FROM journal_entry_lines
        WHERE id=(SELECT line_id FROM p52_fixture)),
  'no unauthorized insert, update, or delete has persisted');                         -- 78

SELECT * FROM finish();
ROLLBACK;
