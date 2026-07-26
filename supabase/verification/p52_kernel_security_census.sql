-- Posting Engine P5.2 — complete, read-only kernel security census
--
-- Run:
--   docker exec -i supabase_db_PXL psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 < supabase/verification/p52_kernel_security_census.sql
--
-- Extension-owned functions are excluded from the application-function sections.
-- All other public functions are included; no name-prefix sampling is used.

\pset pager off
\echo '1. Every application function capable of ledger mutation (direct or static caller)'

WITH RECURSIVE app_functions AS (
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
    )
), direct_mutators AS (
  SELECT *
  FROM app_functions
  WHERE prosrc ~*
    '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)'
), reachable AS (
  SELECT oid, proname, prosecdef, proacl, prosrc, identity_arguments, true AS direct
  FROM direct_mutators
  UNION
  SELECT f.oid, f.proname, f.prosecdef, f.proacl, f.prosrc,
         f.identity_arguments, false
  FROM app_functions f
  JOIN reachable r ON strpos(f.prosrc, r.proname || '(') > 0
)
SELECT DISTINCT ON (proname, identity_arguments)
       proname, identity_arguments,
       bool_or(direct) OVER (
         PARTITION BY proname, identity_arguments
       ) AS contains_ledger_dml,
       prosecdef AS security_definer,
       has_function_privilege('anon', oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', oid, 'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role', oid, 'EXECUTE') AS service_role_execute
FROM reachable
ORDER BY proname, identity_arguments, direct DESC;

\echo '2. Every explicit/default EXECUTE grant on every application function'

WITH app_functions AS (
  SELECT p.oid, p.proowner, p.proname,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         COALESCE(p.proacl, acldefault('f', p.proowner)) AS effective_acl
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND NOT EXISTS (
      SELECT 1
      FROM pg_depend d
      WHERE d.classid = 'pg_proc'::regclass
        AND d.objid = p.oid
        AND d.deptype = 'e'
    )
)
SELECT f.proname, f.identity_arguments,
       CASE WHEN x.grantee = 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(x.grantee) END AS grantee,
       pg_get_userbyid(x.grantor) AS grantor,
       x.is_grantable
FROM app_functions f
CROSS JOIN LATERAL aclexplode(f.effective_acl) x
WHERE x.privilege_type = 'EXECUTE'
ORDER BY f.proname, f.identity_arguments, grantee;

\echo '3. Every application SECURITY DEFINER function'

SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_get_userbyid(p.proowner) AS owner,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND NOT EXISTS (
    SELECT 1
    FROM pg_depend d
    WHERE d.classid = 'pg_proc'::regclass
      AND d.objid = p.oid
      AND d.deptype = 'e'
  )
ORDER BY p.proname, identity_arguments;

\echo '4. Every trigger participating in ledger persistence'

SELECT t.tgrelid::regclass AS table_name,
       t.tgname AS trigger_name,
       CASE t.tgenabled
         WHEN 'O' THEN 'origin'
         WHEN 'R' THEN 'replica'
         WHEN 'A' THEN 'always'
         WHEN 'D' THEN 'disabled'
       END AS enabled_mode,
       t.tgfoid::regprocedure AS trigger_function,
       pg_get_triggerdef(t.oid, true) AS definition
FROM pg_trigger t
WHERE NOT t.tgisinternal
  AND t.tgrelid IN (
    'public.journal_entries'::regclass,
    'public.journal_entry_lines'::regclass
  )
ORDER BY table_name, trigger_name;

\echo '5. Every public-schema RLS policy'

SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

\echo '6. Every remaining accounting table with client-write reachability'

WITH accounting_tables(table_name) AS (VALUES
  ('journal_entries'),
  ('journal_entry_lines'),
  ('tax_detail_entries'),
  ('stock_balances'),
  ('inventory_cost_layers'),
  ('inventory_transactions'),
  ('asset_depreciation_entries'),
  ('amortization_entries'),
  ('revenue_recognition_entries'),
  ('bank_recon_items'),
  ('book_tax_reconciliation'),
  ('sys_posting_guard_violations')
)
SELECT a.table_name,
       c.relrowsecurity AS rls_enabled,
       has_table_privilege('anon', c.oid, 'INSERT') AS anon_insert,
       has_table_privilege('anon', c.oid, 'UPDATE') AS anon_update,
       has_table_privilege('anon', c.oid, 'DELETE') AS anon_delete,
       has_table_privilege('authenticated', c.oid, 'INSERT') AS authenticated_insert,
       has_table_privilege('authenticated', c.oid, 'UPDATE') AS authenticated_update,
       has_table_privilege('authenticated', c.oid, 'DELETE') AS authenticated_delete,
       COALESCE(
         string_agg(
           p.policyname || ':' || p.cmd,
           ', ' ORDER BY p.policyname
         ),
         '(none)'
       ) AS policies
FROM accounting_tables a
JOIN pg_class c ON c.oid = ('public.' || a.table_name)::regclass
LEFT JOIN pg_policies p
  ON p.schemaname = 'public'
 AND p.tablename = a.table_name
GROUP BY a.table_name, c.oid, c.relrowsecurity
ORDER BY a.table_name;

\echo '7. Enforcement invariants'

WITH app_functions AS (
  SELECT p.oid, p.proname, p.prosecdef, p.prosrc
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND NOT EXISTS (
      SELECT 1
      FROM pg_depend d
      WHERE d.classid = 'pg_proc'::regclass
        AND d.objid = p.oid
        AND d.deptype = 'e'
    )
), direct_mutators AS (
  SELECT *
  FROM app_functions
  WHERE prosrc ~*
    '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)'
)
SELECT
  (SELECT count(*) FROM app_functions) AS application_functions,
  (SELECT count(*) FROM app_functions WHERE prosecdef) AS security_definer_functions,
  (SELECT count(*) FROM direct_mutators) AS direct_ledger_mutators,
  (SELECT count(*) FROM sys_posting_guard_violations) AS violation_events,
  (SELECT count(*)
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid = 'public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgenabled = 'A') AS always_totality_triggers;
