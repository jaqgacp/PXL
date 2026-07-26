-- IA5-IA6-GATE-PARTITION-001
-- Read-only physical-key and future-partition impact census.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(8);

CREATE TEMP TABLE gate_partition_options(
  option_name TEXT PRIMARY KEY,
  partition_key TEXT NOT NULL,
  current_pk_unique_compatible BOOLEAN NOT NULL,
  current_fk_compatible BOOLEAN NOT NULL,
  conversion_cost TEXT NOT NULL,
  recommendation TEXT NOT NULL
);

INSERT INTO gate_partition_options VALUES
  ('hash by immutable event id','id',true,true,
   'moderate physical rewrite; permanent ID/FKs remain stable',
   'viable if horizontal distribution matters more than tenant/date pruning'),
  ('hash/list by company','company_id',false,false,
   'high: PK/unique keys and all event FKs need tenant-composite candidates',
   'add and use (company_id,id) candidate identity before high-volume IA-6 data'),
  ('range by effective date','effective_at',false,false,
   'high: PK/unique keys and FKs need date-inclusive identity or registry',
   'do not bind permanent FKs to a date that may change by correction semantics'),
  ('company then effective-date subpartition','company_id,effective_at',false,false,
   'high: composite uniqueness/FKs or unpartitioned identity registry required',
   'viable only with explicit tenant identity plus stable registry/lookup boundary'),
  ('unpartitioned event identity registry','registry id; facts separately partitioned',
   true,true,
   'medium: additive registry and fact routing; event identity can remain stable',
   'viable future bridge when tenant/date partition pruning is required'),
  ('keep events unpartitioned; partition method state/projections',
   'method-specific company/scope/date keys',true,true,
   'low for IA-5; IA-6 physical design carries partition burden',
   'viable while event indexes/replay benchmarks remain within limits');

SELECT is(
  (SELECT pg_get_constraintdef(oid)
   FROM pg_constraint
   WHERE conrelid='public.inventory_events'::regclass
     AND contype='p'),
  'PRIMARY KEY (id)',
  'inventory event permanent primary key is UUID id only'
);
SELECT is(
  (SELECT pg_get_constraintdef(oid)
   FROM pg_constraint
   WHERE conrelid='public.inventory_occurrences'::regclass
     AND contype='p'),
  'PRIMARY KEY (id)',
  'occurrence permanent primary key is UUID id only'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_constraint
   WHERE conrelid='public.inventory_events'::regclass
     AND contype IN('p','u')
     AND pg_get_constraintdef(oid) ~
       '\\(company_id, id\\)|\\(id, company_id\\)'),
  0,
  'events have no tenant-composite candidate key'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_constraint
   WHERE conrelid='public.inventory_occurrences'::regclass
     AND contype IN('p','u')
     AND pg_get_constraintdef(oid) ~
       '\\(company_id, id\\)|\\(id, company_id\\)'),
  0,
  'occurrences have no tenant-composite candidate key'
);
SELECT ok(
  (SELECT bool_and(pg_get_constraintdef(oid) NOT ILIKE '%company_id%')
   FROM pg_constraint
   WHERE contype='f'
     AND confrelid='public.inventory_events'::regclass),
  'all current foreign keys to inventory_events reference ID without tenant key'
);
SELECT ok(
  (SELECT bool_and(pg_get_constraintdef(oid) NOT ILIKE '%company_id%')
   FROM pg_constraint
   WHERE contype='f'
     AND confrelid='public.inventory_occurrences'::regclass),
  'all current foreign keys to occurrences reference ID without tenant key'
);
SELECT is(
  (SELECT count(*)::int FROM gate_partition_options
   WHERE current_pk_unique_compatible),
  3,
  'three modeled physical strategies preserve current permanent ID directly'
);
SELECT is(
  (SELECT count(*)::int FROM gate_partition_options
   WHERE NOT current_pk_unique_compatible),
  3,
  'three realistic tenant/date strategies require composite identity or registry'
);

CREATE TEMP TABLE gate_current_keys AS
SELECT
  c.relname AS table_name,
  con.conname AS constraint_name,
  CASE con.contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE'
    WHEN 'f' THEN 'FOREIGN KEY' ELSE con.contype::text END AS constraint_type,
  pg_get_constraintdef(con.oid) AS definition,
  conf.relname AS referenced_table
FROM pg_constraint con
JOIN pg_class c ON c.oid=con.conrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_class conf ON conf.oid=con.confrelid
WHERE n.nspname='public'
  AND c.relname IN(
    'inventory_occurrences','inventory_events',
    'inventory_event_source_links','inventory_event_values',
    'inventory_event_allocations','inventory_projection_versions'
  )
  AND con.contype IN('p','u','f')
ORDER BY c.relname,constraint_type,con.conname;

TABLE gate_current_keys;
TABLE gate_partition_options;

CREATE TEMP TABLE gate_partition_decision(
  decision_area TEXT,
  evidence TEXT,
  gate TEXT
);
INSERT INTO gate_partition_decision VALUES
  ('IA-6 event foreign keys',
   'ID-only FK is valid now but expensive to tenant-partition later',
   'IA-6 design must choose ID-hash/registry or tenant-composite FK before durable data'),
  ('IA-6 method-state partitioning',
   'method state naturally keys by company, scope and ordered event',
   'include company_id and immutable event/scope identity in every permanent method-state key'),
  ('reconsideration benchmark',
   'partition benefit is workload and memory dependent',
   'benchmark at 1M and 10M representative events; mandatory design review before 100M or when event indexes exceed available memory'),
  ('hot scope sequence',
   'one sequence row serializes each valuation scope independent of total table size',
   'benchmark commands/second per hot scope in IA-6 concurrency lane');

TABLE gate_partition_decision;

SELECT * FROM finish();
ROLLBACK;
