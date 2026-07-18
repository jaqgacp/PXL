-- Phase 3 hosted-safe canonical dataset verification.
-- This file creates temporary session tables only and does not mutate hosted data.

CREATE TEMPORARY TABLE phase3_table_counts (
  table_name text,
  has_company_id boolean,
  hosted_rows bigint,
  canonical_rows bigint
);

DO $phase3$
DECLARE
  table_record record;
  hosted_count bigint;
  canonical_count bigint;
BEGIN
  FOR table_record IN
    SELECT
      tables.table_name,
      EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = tables.table_name
          AND column_name = 'company_id'
      ) AS has_company_id
    FROM information_schema.tables AS tables
    WHERE tables.table_schema = 'public'
      AND tables.table_type = 'BASE TABLE'
    ORDER BY tables.table_name
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', table_record.table_name)
      INTO hosted_count;

    IF table_record.has_company_id THEN
      EXECUTE format(
        'SELECT count(*) FROM public.%I AS source JOIN public.companies AS company ON company.id = source.company_id WHERE company.trade_name LIKE %L',
        table_record.table_name,
        'DEMO-%'
      ) INTO canonical_count;
    ELSE
      canonical_count := NULL;
    END IF;

    INSERT INTO phase3_table_counts
    VALUES (
      table_record.table_name,
      table_record.has_company_id,
      hosted_count,
      canonical_count
    );
  END LOOP;
END
$phase3$;

SELECT *
FROM phase3_table_counts
ORDER BY table_name;
