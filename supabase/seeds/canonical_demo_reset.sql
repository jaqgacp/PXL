-- =============================================================================
-- PXL canonical demo dataset reset
-- =============================================================================
--
-- Purpose:
--   Remove only the canonical PXL demo/QA tenant data so the complete demo seed
--   can be rerun without duplicate companies, masters, documents, stock, or
--   journal activity.
--
-- Safety:
--   This script is destructive and refuses to run unless the caller explicitly
--   sets:
--
--     SET pxl.allow_demo_reset = 'on';
--
--   Intended targets are local, preview, test, and isolated demo databases.
--   Do not run against production.
--
-- Preserved:
--   Migrations, schema, functions, triggers, RLS policies, roles, BIR/RDO
--   references, VAT/EWT/ATC references, document-type references, currencies,
--   payment modes, and other governed global masters.
-- =============================================================================

DO $$
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION
      'Refusing canonical demo reset. Set pxl.allow_demo_reset = on only after confirming a non-production target.';
  END IF;
END $$;

CREATE TEMP TABLE IF NOT EXISTS pxl_demo_reset_company_ids (
  id UUID PRIMARY KEY
);

TRUNCATE pxl_demo_reset_company_ids;

INSERT INTO pxl_demo_reset_company_ids (id)
SELECT id
FROM public.companies
WHERE registered_name IN (
    'Golden Retail Store',
    'ABC Trading Corporation',
    'Northstar Digital Solutions OPC',
    'Prime Business Advisory Inc.',
    'Bayani Partners and Company'
  )
   OR trade_name IN (
    'DEMO-SP-NONVAT',
    'DEMO-CORP-VAT',
    'DEMO-OPC-NONVAT',
    'DEMO-SVC-VAT',
    'DEMO-PARTNERSHIP-VAT'
  )
   OR tin IN (
    '900-100-001-00000',
    '900-100-002-00000',
    '900-100-003-00000',
    '900-100-004-00000',
    '900-100-005-00000'
  );

DO $$
DECLARE
  v_company_count INTEGER;
  v_remaining TEXT[];
  v_table TEXT;
  v_progress BOOLEAN;
  v_round INTEGER := 0;
BEGIN
  SELECT count(*) INTO v_company_count FROM pxl_demo_reset_company_ids;

  IF v_company_count = 0 THEN
    RAISE NOTICE 'No canonical demo companies found. Nothing to reset.';
    RETURN;
  END IF;

  RAISE NOTICE 'Resetting % canonical demo companies and dependent tenant rows.', v_company_count;

  -- Indirect child tables without company_id that reference company-owned
  -- headers. Delete these before the generic company_id dependency pass.
  DELETE FROM public.compliance_vat_working_papers_lines l
  USING public.compliance_vat_working_papers_headers h
  WHERE l.header_id = h.id AND h.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.compliance_pt_working_papers_lines l
  USING public.compliance_pt_working_papers_headers h
  WHERE l.header_id = h.id AND h.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.compliance_ewt_working_papers_lines l
  USING public.compliance_ewt_working_papers_headers h
  WHERE l.header_id = h.id AND h.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.compliance_fwt_working_papers_lines l
  USING public.compliance_fwt_working_papers_headers h
  WHERE l.header_id = h.id AND h.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.compliance_1601eq_working_papers_lines l
  USING public.compliance_1601eq_working_papers_headers h
  WHERE l.header_id = h.id AND h.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.compliance_1601fq_working_papers_lines l
  USING public.compliance_1601fq_working_papers_headers h
  WHERE l.header_id = h.id AND h.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.warehouse_zones z
  USING public.warehouses w
  WHERE z.warehouse_id = w.id AND w.company_id IN (SELECT id FROM pxl_demo_reset_company_ids);

  DELETE FROM public.tax_codes tc
  USING public.chart_of_accounts coa
  WHERE tc.gl_account_id = coa.id
    AND coa.company_id IN (SELECT id FROM pxl_demo_reset_company_ids)
    AND NOT EXISTS (SELECT 1 FROM public.vat_codes vc WHERE vc.tax_code_id = tc.id);

  SELECT array_agg(c.table_name ORDER BY c.table_name)
  INTO v_remaining
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_schema = c.table_schema
   AND t.table_name = c.table_name
   AND t.table_type = 'BASE TABLE'
  WHERE c.table_schema = 'public'
    AND c.column_name = 'company_id'
    AND c.table_name <> 'companies';

  WHILE COALESCE(array_length(v_remaining, 1), 0) > 0 LOOP
    v_round := v_round + 1;
    v_progress := false;

    FOREACH v_table IN ARRAY v_remaining LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_schema = tc.constraint_schema
         AND ccu.constraint_name = tc.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_name = ANY(v_remaining)
          AND ccu.table_schema = 'public'
          AND ccu.table_name = v_table
          AND tc.table_name <> v_table
      ) THEN
        EXECUTE format(
          'DELETE FROM public.%I WHERE company_id IN (SELECT id FROM pxl_demo_reset_company_ids)',
          v_table
        );
        v_remaining := array_remove(v_remaining, v_table);
        v_progress := true;
      END IF;
    END LOOP;

    IF NOT v_progress THEN
      RAISE EXCEPTION 'Could not derive a safe delete order for remaining company tables: %', v_remaining;
    END IF;

    IF v_round > 250 THEN
      RAISE EXCEPTION 'Aborting canonical demo reset after too many dependency-order passes.';
    END IF;
  END LOOP;

  DELETE FROM public.companies
  WHERE id IN (SELECT id FROM pxl_demo_reset_company_ids);

  RAISE NOTICE 'Canonical demo reset complete.';
END $$;

DROP TABLE IF EXISTS pxl_demo_reset_company_ids;
