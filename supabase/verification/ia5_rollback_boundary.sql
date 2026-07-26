-- IA5-ROLLBACK-001
-- Transactional proof of the dormant pre-activation rollback boundary.
-- Every DDL statement is rolled back. Do not convert this into a production
-- down migration after authoritative IA-5 events exist.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(6);

CREATE TEMP TABLE ia5_rollback_counts AS
SELECT
  (SELECT count(*) FROM public.stock_balances) AS stock_rows,
  (SELECT count(*) FROM public.inventory_cost_layers) AS layer_rows,
  (SELECT count(*) FROM public.inventory_transactions) AS movement_rows,
  (SELECT count(*) FROM public.journal_entries) AS journal_rows;

DROP FUNCTION public.fn_ia5_record_dormant_inventory_occurrence(
  UUID, TEXT, UUID, UUID, TEXT, BIGINT, TEXT, TEXT,
  TIMESTAMPTZ, UUID, JSONB
);
DROP FUNCTION public.fn_ia5_create_dormant_policy_bundle(
  UUID, UUID, TEXT, UUID, UUID, TEXT, SMALLINT,
  TEXT, SMALLINT, DATE, DATE, UUID
);

DROP TABLE public.inventory_event_allocations;
DROP TABLE public.inventory_event_values;
DROP TABLE public.inventory_event_source_links;
DROP TABLE public.inventory_events;
DROP TABLE public.inventory_occurrences;
ALTER TABLE public.stock_balances
  DROP CONSTRAINT stock_balances_projection_version_id_fkey;
DROP TABLE public.inventory_projection_versions;
DROP TABLE public.inventory_valuation_scope_sequences;
DROP TABLE public.inventory_valuation_scopes;
DROP TABLE public.inventory_cost_formula_policies;
DROP TABLE public.inventory_accounting_profiles;
DROP TABLE public.inventory_precision_policies;
DROP TABLE public.ref_inventory_event_source_types;

DROP FUNCTION public.fn_ia5_guard_inventory_event_fact();
DROP FUNCTION public.fn_ia5_guard_inventory_policy_foundation();
DROP FUNCTION public.fn_ia5_reject_immutable_inventory_fact();
DROP FUNCTION public.fn_ia5_derive_unit_rate(NUMERIC, NUMERIC);
DROP FUNCTION public.fn_ia5_quantize_exact(NUMERIC, INTEGER, TEXT);
DROP FUNCTION public.fn_ia5_quantize_exact(NUMERIC, SMALLINT, TEXT);

ALTER TABLE public.stock_balances
  DROP CONSTRAINT stock_balances_ia5_legacy_projection_ck,
  DROP COLUMN projection_fingerprint,
  DROP COLUMN projection_watermark_sequence,
  DROP COLUMN projection_version_id,
  DROP COLUMN projection_authority;

SELECT is(
  (SELECT count(*)::int
     FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name LIKE 'inventory_event%'),
  0,
  'dormant event tables can be removed without CASCADE'
);

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname LIKE 'fn_ia5_%'),
  0,
  'IA-5 functions can be removed without a production dependency'
);

SELECT is(
  (SELECT count(*)::int
     FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name IN (
        'stock_balances','inventory_cost_layers','inventory_transactions'
      )),
  3,
  'all current Inventory authorities remain present'
);

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosrc ~*
        '(insert[[:space:]]+into|update|delete[[:space:]]+from)'
        '[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)'),
  6,
  'Posting Kernel remains exactly six after the transactional rollback'
);

SELECT is(
  (SELECT count(*)::int FROM public.stock_balances)
  + (SELECT count(*)::int FROM public.inventory_cost_layers)
  + (SELECT count(*)::int FROM public.inventory_transactions),
  (SELECT (stock_rows + layer_rows + movement_rows)::int
     FROM ia5_rollback_counts),
  'rollback boundary changes no current Inventory history'
);

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows::int FROM ia5_rollback_counts),
  'rollback boundary changes no journal history'
);

SELECT * FROM finish();
ROLLBACK;
