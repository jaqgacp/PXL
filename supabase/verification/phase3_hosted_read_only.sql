-- Phase 3 hosted-safe canonical dataset verification.
-- Pure read path: psql generates one count SELECT per public base table.

\set ON_ERROR_STOP on
BEGIN TRANSACTION READ ONLY;

SELECT CASE
  WHEN EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = tables.table_schema
      AND table_name = tables.table_name
      AND column_name = 'company_id'
  ) THEN format(
    'SELECT %L::text AS table_name, true AS has_company_id, count(*)::bigint AS hosted_rows, count(*) FILTER (WHERE company.trade_name LIKE ''DEMO-%%'')::bigint AS canonical_rows FROM %I.%I AS source LEFT JOIN public.companies AS company ON company.id = source.company_id',
    tables.table_name,
    tables.table_schema,
    tables.table_name
  )
  ELSE format(
    'SELECT %L::text AS table_name, false AS has_company_id, count(*)::bigint AS hosted_rows, NULL::bigint AS canonical_rows FROM %I.%I',
    tables.table_name,
    tables.table_schema,
    tables.table_name
  )
END
FROM information_schema.tables AS tables
WHERE tables.table_schema = 'public'
  AND tables.table_type = 'BASE TABLE'
ORDER BY tables.table_name
\gexec

COMMIT;
