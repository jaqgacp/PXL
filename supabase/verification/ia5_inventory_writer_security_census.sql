-- Inventory Accounting IA-5 — complete read-only writer/security census
--
-- Run locally:
--   docker exec -i supabase_db_PXL psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 < supabase/verification/ia5_inventory_writer_security_census.sql
--
-- Function classification is body-based, not name-based. Extension-owned
-- functions are excluded. Dynamic SQL and trigger sections are listed
-- independently so they cannot be hidden by the direct-DML scan.

\pset pager off

\echo '1. Every direct writer of current Inventory derived state'

WITH app_functions AS (
  SELECT p.oid, p.proname, p.prosecdef, p.prosrc,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_proc'::regclass
        AND d.objid=p.oid
        AND d.deptype='e'
    )
)
SELECT proname, identity_arguments, prosecdef AS security_definer,
       has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',oid,'EXECUTE') AS service_role_execute
FROM app_functions
WHERE prosrc ~*
  '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?(inventory_transactions|inventory_cost_layers|stock_balances)'
ORDER BY proname, identity_arguments;

\echo '2. Every direct writer of IA-5 event, occurrence, policy, scope, and projection state'

WITH app_functions AS (
  SELECT p.oid, p.proname, p.prosecdef, p.prosrc,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_proc'::regclass
        AND d.objid=p.oid
        AND d.deptype='e'
    )
)
SELECT proname, identity_arguments, prosecdef AS security_definer,
       has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',oid,'EXECUTE') AS service_role_execute
FROM app_functions
WHERE prosrc ~*
  '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?'
  '(inventory_occurrences|inventory_events|inventory_event_source_links|inventory_event_values|inventory_event_allocations|inventory_precision_policies|inventory_accounting_profiles|inventory_cost_formula_policies|inventory_valuation_scopes|inventory_valuation_scope_sequences|inventory_projection_versions)'
ORDER BY proname, identity_arguments;

\echo '3. Static Inventory-capable call graph and Posting reachability'

WITH RECURSIVE app_functions AS (
  SELECT p.oid, p.proname, p.prosecdef, p.prosrc,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_proc'::regclass
        AND d.objid=p.oid
        AND d.deptype='e'
    )
), direct_inventory AS (
  SELECT * FROM app_functions
  WHERE prosrc ~*
    '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?'
    '(inventory_transactions|inventory_cost_layers|stock_balances|inventory_occurrences|inventory_events|inventory_event_source_links|inventory_event_values|inventory_event_allocations|inventory_precision_policies|inventory_accounting_profiles|inventory_cost_formula_policies|inventory_valuation_scopes|inventory_valuation_scope_sequences|inventory_projection_versions)'
), reachable AS (
  SELECT oid, proname, identity_arguments, prosecdef, prosrc, true AS direct
  FROM direct_inventory
  UNION
  SELECT f.oid, f.proname, f.identity_arguments, f.prosecdef, f.prosrc, false
  FROM app_functions f
  JOIN reachable r ON strpos(f.prosrc,r.proname || '(') > 0
)
SELECT DISTINCT ON (r.proname,r.identity_arguments)
       r.proname, r.identity_arguments,
       bool_or(r.direct) OVER (
         PARTITION BY r.proname,r.identity_arguments
       ) AS contains_inventory_dml,
       r.prosecdef AS security_definer,
       r.prosrc ~
         '(fn_create_posted_journal_entry|fn_add_posting_line_push|fn_add_sales_invoice_posting_line|fn_finalize_journal_entry|fn_reverse_posted_journal_entry)[[:space:]]*[(]'
         AS invokes_posting_kernel,
       has_function_privilege('authenticated',r.oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',r.oid,'EXECUTE') AS service_role_execute
FROM reachable r
ORDER BY r.proname,r.identity_arguments,r.direct DESC;

\echo '4. Exact callers of the legacy receipt helper and cost-consumption helper'

SELECT callee, p.proname AS caller,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       p.prosecdef AS security_definer,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') AS service_role_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
CROSS JOIN LATERAL (
  VALUES
    ('fn_receive_inventory',strpos(p.prosrc,'fn_receive_inventory(')),
    ('fn_consume_cost_layers',strpos(p.prosrc,'fn_consume_cost_layers('))
) c(callee,position)
WHERE n.nspname='public'
  AND c.position > 0
ORDER BY callee,caller,identity_arguments;

\echo '5. Every Inventory-related externally executable function'

WITH app_functions AS (
  SELECT p.oid,p.proname,p.prosrc,p.prosecdef,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_proc'::regclass
        AND d.objid=p.oid
        AND d.deptype='e'
    )
)
SELECT proname,identity_arguments,prosecdef AS security_definer,
       has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',oid,'EXECUTE') AS service_role_execute
FROM app_functions
WHERE (
    proname ~ '(inventory|stock|goods_issue|physical_count|receiving_report|cash_purchase)'
    OR prosrc ~
      '(inventory_transactions|inventory_cost_layers|stock_balances|inventory_events|inventory_occurrences)'
  )
  AND (
    has_function_privilege('anon',oid,'EXECUTE')
    OR has_function_privilege('authenticated',oid,'EXECUTE')
    OR has_function_privilege('service_role',oid,'EXECUTE')
  )
ORDER BY proname,identity_arguments;

\echo '6. Every trigger affecting current or IA-5 Inventory state'

SELECT t.tgrelid::regclass AS table_name,
       t.tgname AS trigger_name,
       CASE t.tgenabled
         WHEN 'O' THEN 'origin'
         WHEN 'R' THEN 'replica'
         WHEN 'A' THEN 'always'
         WHEN 'D' THEN 'disabled'
       END AS enabled_mode,
       t.tgfoid::regprocedure AS trigger_function,
       pg_get_triggerdef(t.oid,true) AS definition
FROM pg_trigger t
WHERE NOT t.tgisinternal
  AND t.tgrelid IN (
    'public.inventory_transactions'::regclass,
    'public.inventory_cost_layers'::regclass,
    'public.stock_balances'::regclass,
    'public.ref_inventory_event_source_types'::regclass,
    'public.inventory_precision_policies'::regclass,
    'public.inventory_accounting_profiles'::regclass,
    'public.inventory_cost_formula_policies'::regclass,
    'public.inventory_valuation_scopes'::regclass,
    'public.inventory_valuation_scope_sequences'::regclass,
    'public.inventory_occurrences'::regclass,
    'public.inventory_events'::regclass,
    'public.inventory_event_source_links'::regclass,
    'public.inventory_event_values'::regclass,
    'public.inventory_event_allocations'::regclass,
    'public.inventory_projection_versions'::regclass
  )
ORDER BY table_name,trigger_name;

\echo '7. RLS, policies, and table DML reachability for every governed Inventory table'

WITH governed(table_name) AS (VALUES
  ('inventory_transactions'),
  ('inventory_cost_layers'),
  ('stock_balances'),
  ('ref_inventory_event_source_types'),
  ('inventory_precision_policies'),
  ('inventory_accounting_profiles'),
  ('inventory_cost_formula_policies'),
  ('inventory_valuation_scopes'),
  ('inventory_valuation_scope_sequences'),
  ('inventory_occurrences'),
  ('inventory_events'),
  ('inventory_event_source_links'),
  ('inventory_event_values'),
  ('inventory_event_allocations'),
  ('inventory_projection_versions')
)
SELECT g.table_name,c.relrowsecurity AS rls_enabled,
       has_table_privilege('anon',c.oid,'INSERT,UPDATE,DELETE') AS anon_write,
       has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') AS authenticated_write,
       has_table_privilege('service_role',c.oid,'INSERT,UPDATE,DELETE') AS service_write,
       COALESCE(string_agg(p.policyname || ':' || p.cmd,', ' ORDER BY p.policyname),'(none)')
         AS policies
FROM governed g
JOIN pg_class c ON c.oid=('public.' || g.table_name)::regclass
LEFT JOIN pg_policies p
  ON p.schemaname='public' AND p.tablename=g.table_name
GROUP BY g.table_name,c.oid,c.relrowsecurity
ORDER BY g.table_name;

\echo '8. IA-5 and P5.2 enforcement invariants'

WITH app_functions AS (
  SELECT p.oid,p.proname,p.prosecdef,p.prosrc
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_proc'::regclass
        AND d.objid=p.oid
        AND d.deptype='e'
    )
)
SELECT
  (SELECT count(*) FROM app_functions) AS application_functions,
  (SELECT count(*) FROM app_functions WHERE prosecdef) AS security_definers,
  (SELECT count(*) FROM app_functions WHERE proname LIKE 'fn_ia5_%') AS ia5_functions,
  (SELECT count(*) FROM app_functions
    WHERE proname LIKE 'fn_ia5_%'
      AND (
        has_function_privilege('anon',oid,'EXECUTE')
        OR has_function_privilege('authenticated',oid,'EXECUTE')
        OR has_function_privilege('service_role',oid,'EXECUTE')
      )) AS ia5_externally_executable,
  has_function_privilege(
    'authenticated','public.fn_receive_inventory(jsonb)','EXECUTE'
  ) AS authenticated_legacy_receive_execute,
  (SELECT count(*) FROM app_functions
    WHERE prosrc ~*
      '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)')
    AS direct_ledger_mutators,
  (SELECT count(*) FROM public.sys_posting_guard_violations) AS violation_events,
  (SELECT count(*) FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid='public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgenabled='A') AS always_totality_triggers;
