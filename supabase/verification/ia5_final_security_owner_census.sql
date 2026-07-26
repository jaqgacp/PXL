-- IA5-IA6-GATE-SECURITY-001
-- Read-only catalog census plus a rolled-back owner TRUNCATE probe.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(15);

CREATE TEMP TABLE gate_security_classification(
  subject TEXT PRIMARY KEY,
  observed_fact TEXT NOT NULL,
  classification TEXT NOT NULL,
  ia6_requirement TEXT NOT NULL
);

SELECT is(
  (SELECT count(DISTINCT r.rolname)::int
   FROM pg_class c
   JOIN pg_namespace n ON n.oid=c.relnamespace
   JOIN pg_roles r ON r.oid=c.relowner
   WHERE n.nspname='public'
     AND c.relname IN(
       'ref_inventory_event_source_types',
       'inventory_precision_policies','inventory_accounting_profiles',
       'inventory_cost_formula_policies','inventory_valuation_scopes',
       'inventory_valuation_scope_sequences','inventory_occurrences',
       'inventory_events','inventory_event_source_links',
       'inventory_event_values','inventory_event_allocations',
       'inventory_projection_versions'
     )),
  1,
  'all IA-5 tables share one owner role'
);
SELECT is(
  (SELECT min(r.rolname)
   FROM pg_class c
   JOIN pg_namespace n ON n.oid=c.relnamespace
   JOIN pg_roles r ON r.oid=c.relowner
   WHERE n.nspname='public' AND c.relname='inventory_events'),
  'postgres',
  'inventory event owner is postgres'
);
SELECT ok(
  (SELECT relrowsecurity AND NOT relforcerowsecurity
   FROM pg_class
   WHERE oid='public.inventory_events'::regclass),
  'event RLS is enabled but not forced on the table owner'
);
SELECT ok(
  (SELECT rolbypassrls FROM pg_roles WHERE rolname='postgres'),
  'postgres owner role also has BYPASSRLS'
);

SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   JOIN pg_roles r ON r.oid=p.proowner
   WHERE n.nspname='public'
     AND p.proname LIKE 'fn_ia5%'
     AND p.prosecdef
     AND r.rolname='postgres'),
  5,
  'five IA-5 SECURITY DEFINER functions are postgres-owned'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.prosecdef
     AND (
       p.prosrc ~* '\\minsert\\s+into\\s+(public\\.)?inventory_events\\M'
       OR p.prosrc ~* '\\minsert\\s+into\\s+(public\\.)?inventory_occurrences\\M'
       OR p.prosrc ~* '\\minsert\\s+into\\s+(public\\.)?inventory_event_values\\M'
       OR p.prosrc ~* '\\minsert\\s+into\\s+(public\\.)?inventory_event_allocations\\M'
     )),
  1,
  'one current SECURITY DEFINER directly writes IA-5 event authority'
);
SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.fn_ia5_record_dormant_inventory_occurrence(
      uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb
    )',
    'EXECUTE'
  ),
  'authenticated cannot execute the IA-5 writer'
);
SELECT ok(
  NOT has_table_privilege(
    'authenticated','public.inventory_events','INSERT,UPDATE,DELETE,TRUNCATE'
  ),
  'authenticated has no event mutation or TRUNCATE privilege'
);

SELECT is(
  (SELECT count(*)::int
   FROM pg_trigger
   WHERE tgrelid IN(
     'public.inventory_events'::regclass,
     'public.inventory_event_source_links'::regclass,
     'public.inventory_event_values'::regclass,
     'public.inventory_event_allocations'::regclass
   )
     AND NOT tgisinternal
     AND tgname LIKE 'aa_%_guard'
     AND tgenabled='O'),
  4,
  'four insert consistency guards are origin-only triggers'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_trigger
   WHERE tgrelid IN(
     'public.inventory_occurrences'::regclass,
     'public.inventory_events'::regclass,
     'public.inventory_event_source_links'::regclass,
     'public.inventory_event_values'::regclass,
     'public.inventory_event_allocations'::regclass
   )
     AND NOT tgisinternal
     AND tgname LIKE 'trg_%_audit'
     AND tgenabled='O'),
  5,
  'IA-5 insert audit triggers are origin-only'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_trigger
   WHERE tgrelid='public.inventory_events'::regclass
     AND NOT tgisinternal
     AND tgname LIKE 'zz_%_immutable'
     AND tgenabled='A'),
  1,
  'event update/delete immutability trigger is ALWAYS enabled'
);
SELECT ok(
  (SELECT (tgtype & 32)=0
   FROM pg_trigger
   WHERE tgrelid='public.inventory_events'::regclass
     AND NOT tgisinternal
     AND tgname LIKE 'zz_%_immutable'),
  'immutability trigger is not a TRUNCATE trigger'
);

SELECT lives_ok(
  $$TRUNCATE TABLE public.inventory_events CASCADE$$,
  'table owner can TRUNCATE IA-5 events without invoking row immutability'
);

SELECT is(
  (SELECT count(*)::int
   FROM pg_constraint
   WHERE conrelid='public.inventory_occurrences'::regclass
     AND contype='f'
     AND pg_get_constraintdef(oid) ILIKE '%audit_identity%'),
  0,
  'occurrence audit_identity is not a foreign key to sys_audit_logs'
);
SELECT ok(
  (SELECT p.prosrc ILIKE '%auth.uid()%'
   FROM pg_proc p
   WHERE p.oid='public.fn_audit_trigger()'::regprocedure)
  AND
  (SELECT p.prosrc NOT ILIKE '%p_actor_id%auth.uid%'
   FROM pg_proc p
   WHERE p.oid='public.fn_ia5_record_dormant_inventory_occurrence(
     uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb
   )'::regprocedure),
  'audit changed_by uses auth.uid while IA-5 created_by accepts a member actor parameter'
);

INSERT INTO gate_security_classification VALUES
  ('postgres ownership and RLS bypass',
   'postgres owns all IA-5 tables/functions and bypasses RLS',
   'accepted superuser/DDL trust boundary',
   'do not expose postgres-owned writers; retain migration review and runtime revokes'),
  ('origin-only insert guards',
   'consistency and insert audit triggers are disabled in replica session role',
   'migration-governance weakness',
   'IA-6 migrations must prohibit replica-role data admission and census trigger modes'),
  ('TRUNCATE',
   'runtime roles lack privilege; owner TRUNCATE succeeds and row triggers do not run',
   'accepted DDL trust plus migration-governance weakness',
   'future writer-totality check must census TRUNCATE grants and destructive migration DDL'),
  ('created_by versus audit changed_by',
   'created_by is p_actor_id; audit changed_by is auth.uid()',
   'audit-evidence weakness',
   'trusted orchestration must bind actor/session identity or store both explicitly'),
  ('audit_identity',
   'audit_identity equals occurrence id but has no audit-row FK',
   'audit-evidence weakness',
   'define it as correlation identity or add explicit relational audit evidence before activation'),
  ('writer totality',
   'revokes and current writer census are enforced; future definer creation is migration-controlled',
   'migration-governance weakness',
   'IA-6 requires an executable writer/body/grant/trigger census gate');

TABLE gate_security_classification;

SELECT
  c.relname AS table_name,
  r.rolname AS owner,
  c.relrowsecurity,
  c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_roles r ON r.oid=c.relowner
WHERE n.nspname='public' AND c.relname LIKE 'inventory_%'
ORDER BY c.relname;

SELECT
  p.oid::regprocedure AS function_signature,
  r.rolname AS owner,
  p.prosecdef,
  p.proconfig,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
  has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_roles r ON r.oid=p.proowner
WHERE n.nspname='public' AND p.proname LIKE 'fn_ia5%'
ORDER BY p.oid::regprocedure::text;

SELECT * FROM finish();
ROLLBACK;
