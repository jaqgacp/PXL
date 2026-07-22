-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-15 — Master-Data Import / Export Foundation
--
-- Backend-first tooling for completed master-data packages. This migration adds
-- reusable metadata, deterministic JSON export, import templates, validation,
-- preview, idempotent commit, row-level errors, rollback-safe execution, and
-- import/export audit trails.
--
-- Inventory result:
-- * Existing export helpers are report/CAS-specific (CSV/DAT snapshots + hashes).
--   They do not provide reusable master-data import/export.
-- * Existing master governance remains authoritative: company-scoped masters keep
--   their member/admin checks, FK/CHECK/guard triggers, and fn_audit_trigger; the
--   global statutory tax/BIR references remain MDP-01 maintainer-governed and are
--   not made tenant-importable here.
--
-- This package is additive and idempotent. No transaction import, posting logic,
-- UI wizard, or master redesign is introduced.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Registry and audit tables ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS master_data_import_registry (
  master_key          TEXT PRIMARY KEY,
  display_name        TEXT NOT NULL,
  table_schema        TEXT NOT NULL DEFAULT 'public',
  table_name          TEXT NOT NULL,
  scope               TEXT NOT NULL
                        CHECK (scope IN ('company','company_self','global_reference','global_statutory')),
  import_mode         TEXT NOT NULL DEFAULT 'upsert'
                        CHECK (import_mode IN ('upsert','export_only','governed_elsewhere')),
  business_key_columns TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  sort_columns        TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  export_sequence     INTEGER NOT NULL,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_master_data_import_registry_updated_at ON master_data_import_registry;
CREATE TRIGGER trg_master_data_import_registry_updated_at
  BEFORE UPDATE ON master_data_import_registry
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS master_data_import_batches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID REFERENCES companies(id),
  master_key      TEXT NOT NULL REFERENCES master_data_import_registry(master_key),
  mode            TEXT NOT NULL CHECK (mode IN ('preview','commit')),
  status          TEXT NOT NULL CHECK (status IN ('validated','failed','imported')),
  idempotency_key TEXT,
  input_hash      TEXT NOT NULL,
  row_count       INTEGER NOT NULL DEFAULT 0 CHECK (row_count >= 0),
  valid_row_count INTEGER NOT NULL DEFAULT 0 CHECK (valid_row_count >= 0),
  error_count     INTEGER NOT NULL DEFAULT 0 CHECK (error_count >= 0),
  inserted_count  INTEGER NOT NULL DEFAULT 0 CHECK (inserted_count >= 0),
  updated_count   INTEGER NOT NULL DEFAULT 0 CHECK (updated_count >= 0),
  skipped_count   INTEGER NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
  error_summary   JSONB NOT NULL DEFAULT '[]'::JSONB,
  options         JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_master_data_import_batches_idempotency
  ON master_data_import_batches (
    COALESCE(company_id, '00000000-0000-0000-0000-000000000000'::UUID),
    master_key,
    idempotency_key
  )
  WHERE idempotency_key IS NOT NULL AND mode = 'commit';

CREATE INDEX IF NOT EXISTS idx_master_data_import_batches_company
  ON master_data_import_batches (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_master_data_import_batches_master
  ON master_data_import_batches (master_key, created_at DESC);

CREATE TABLE IF NOT EXISTS master_data_import_rows (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id          UUID NOT NULL REFERENCES master_data_import_batches(id) ON DELETE CASCADE,
  row_number        INTEGER NOT NULL CHECK (row_number > 0),
  source_row        JSONB NOT NULL,
  action            TEXT NOT NULL CHECK (action IN ('insert','update','skip','error')),
  record_id         UUID,
  is_valid          BOOLEAN NOT NULL DEFAULT false,
  validation_errors JSONB NOT NULL DEFAULT '[]'::JSONB,
  imported_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (batch_id, row_number)
);

CREATE INDEX IF NOT EXISTS idx_master_data_import_rows_batch
  ON master_data_import_rows (batch_id, row_number);
CREATE INDEX IF NOT EXISTS idx_master_data_import_rows_record
  ON master_data_import_rows (record_id) WHERE record_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS master_data_export_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    UUID REFERENCES companies(id),
  master_key    TEXT NOT NULL REFERENCES master_data_import_registry(master_key),
  export_format TEXT NOT NULL DEFAULT 'json-v1',
  row_count     INTEGER NOT NULL DEFAULT 0 CHECK (row_count >= 0),
  content_hash  TEXT NOT NULL,
  exported_by   UUID,
  exported_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_master_data_export_logs_company
  ON master_data_export_logs (company_id, exported_at DESC);
CREATE INDEX IF NOT EXISTS idx_master_data_export_logs_master
  ON master_data_export_logs (master_key, exported_at DESC);

-- Audit the import/export operation metadata. Master row mutations still flow
-- through each master table's own audit trigger / governed RPC pattern.
DROP TRIGGER IF EXISTS trg_audit_master_data_import_batches ON master_data_import_batches;
CREATE TRIGGER trg_audit_master_data_import_batches
  AFTER INSERT OR UPDATE OR DELETE ON master_data_import_batches
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

DROP TRIGGER IF EXISTS trg_audit_master_data_export_logs ON master_data_export_logs;
CREATE TRIGGER trg_audit_master_data_export_logs
  AFTER INSERT OR UPDATE OR DELETE ON master_data_export_logs
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- ── 2. RLS / least privilege ─────────────────────────────────────────────────
ALTER TABLE master_data_import_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_data_import_batches  ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_data_import_rows     ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_data_export_logs     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS master_data_import_registry_read ON master_data_import_registry;
CREATE POLICY master_data_import_registry_read
  ON master_data_import_registry FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS master_data_import_batches_read ON master_data_import_batches;
CREATE POLICY master_data_import_batches_read
  ON master_data_import_batches FOR SELECT TO authenticated
  USING (
    (company_id IS NOT NULL AND is_company_member(company_id))
    OR (company_id IS NULL AND fn_is_bir_config_maintainer())
  );

DROP POLICY IF EXISTS master_data_import_rows_read ON master_data_import_rows;
CREATE POLICY master_data_import_rows_read
  ON master_data_import_rows FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM master_data_import_batches b
      WHERE b.id = batch_id
        AND (
          (b.company_id IS NOT NULL AND is_company_member(b.company_id))
          OR (b.company_id IS NULL AND fn_is_bir_config_maintainer())
        )
    )
  );

DROP POLICY IF EXISTS master_data_export_logs_read ON master_data_export_logs;
CREATE POLICY master_data_export_logs_read
  ON master_data_export_logs FOR SELECT TO authenticated
  USING (
    (company_id IS NOT NULL AND is_company_member(company_id))
    OR (company_id IS NULL AND fn_is_bir_config_maintainer())
  );

REVOKE ALL ON TABLE master_data_import_registry, master_data_import_batches,
  master_data_import_rows, master_data_export_logs FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE master_data_import_registry, master_data_import_batches,
  master_data_import_rows, master_data_export_logs TO authenticated;
GRANT ALL ON TABLE master_data_import_registry, master_data_import_batches,
  master_data_import_rows, master_data_export_logs TO service_role;

-- ── 3. Supported-master registry ─────────────────────────────────────────────
WITH registry(master_key, display_name, table_name, scope, import_mode,
              business_key_columns, sort_columns, export_sequence, notes) AS (
  VALUES
  ('currencies', 'Currencies', 'currencies', 'global_reference', 'export_only',
    ARRAY['currency_code'], ARRAY['currency_code'], 10, 'Global read-only reference master.'),
  ('ref_rdo_codes', 'RDO Codes', 'ref_rdo_codes', 'global_reference', 'export_only',
    ARRAY['rdo_code'], ARRAY['rdo_code'], 11, 'Global read-only BIR RDO reference master.'),
  ('ref_document_types', 'Document Types', 'ref_document_types', 'global_reference', 'export_only',
    ARRAY['document_code'], ARRAY['sort_order','document_code'], 12, 'Global read-only document type reference master.'),
  ('ref_payment_modes', 'Payment Mode References', 'ref_payment_modes', 'global_reference', 'export_only',
    ARRAY['mode_code'], ARRAY['mode_code'], 13, 'Global read-only payment mode reference master.'),
  ('ref_reason_codes', 'Reason Codes', 'ref_reason_codes', 'global_reference', 'export_only',
    ARRAY['reason_code'], ARRAY['reason_code'], 14, 'Global read-only reason code reference master.'),
  ('ref_compliance_forms', 'Compliance Form References', 'ref_compliance_forms', 'global_reference', 'export_only',
    ARRAY['form_code'], ARRAY['form_code'], 15, 'Global read-only compliance form reference master.'),
  ('ref_banks', 'Bank References', 'ref_banks', 'global_reference', 'export_only',
    ARRAY['bank_code'], ARRAY['sort_order','bank_code'], 16, 'MDP-11 global read-only bank reference master.'),

  ('tax_codes', 'Tax Codes', 'tax_codes', 'global_statutory', 'governed_elsewhere',
    ARRAY['code','tax_type','effective_from'], ARRAY['code','effective_from'], 20, 'MDP-01 maintainer-governed statutory reference; use tax-code RPCs for writes.'),
  ('vat_codes', 'VAT Codes', 'vat_codes', 'global_statutory', 'governed_elsewhere',
    ARRAY['vat_code','transaction_type','effective_from'], ARRAY['vat_code','transaction_type','effective_from'], 21, 'MDP-01 maintainer-governed statutory reference; use VAT-code RPCs for writes.'),
  ('atc_codes', 'ATC Codes', 'atc_codes', 'global_statutory', 'governed_elsewhere',
    ARRAY['code','tax_category','effective_from'], ARRAY['code','tax_category','effective_from'], 22, 'MDP-01 maintainer-governed statutory reference; use ATC-code RPCs for writes.'),
  ('bir_forms', 'BIR Forms', 'bir_forms', 'global_statutory', 'governed_elsewhere',
    ARRAY['form_number'], ARRAY['form_number'], 23, 'PXL-AUD-063 maintainer-governed statutory config; use BIR-config RPCs for writes.'),
  ('bir_form_mappings', 'BIR Form Mappings', 'bir_form_mappings', 'global_statutory', 'governed_elsewhere',
    ARRAY['form_id','line_identifier'], ARRAY['form_id','line_identifier'], 24, 'PXL-AUD-063 maintainer-governed statutory config; use BIR-config RPCs for writes.'),
  ('tax_reference_catalog', 'Tax Reference Catalog', 'vw_tax_reference_catalog', 'global_statutory', 'export_only',
    ARRAY['reference_type','code','tax_category','effective_from'], ARRAY['reference_type','code','tax_category','effective_from'], 25, 'MDP-12 read-only consolidated tax-reference catalog view.'),

  ('companies', 'Companies', 'companies', 'company_self', 'upsert',
    ARRAY['id'], ARRAY['registered_name'], 100, 'The company row itself. Imports update the selected company only.'),
  ('branches', 'Branches', 'branches', 'company', 'upsert',
    ARRAY['branch_code'], ARRAY['branch_code'], 110, 'Company-scoped branch master.'),
  ('chart_of_accounts', 'Chart of Accounts', 'chart_of_accounts', 'company', 'upsert',
    ARRAY['account_code'], ARRAY['account_code'], 120, 'Company-scoped COA master with hierarchy and MDP-04 enrichment fields.'),
  ('departments', 'Departments', 'departments', 'company', 'upsert',
    ARRAY['department_code'], ARRAY['department_code'], 130, 'Company-scoped department master.'),
  ('cost_centers', 'Cost Centers', 'cost_centers', 'company', 'upsert',
    ARRAY['cost_center_code'], ARRAY['cost_center_code'], 140, 'Company-scoped cost-center master.'),
  ('warehouses', 'Warehouses', 'warehouses', 'company', 'upsert',
    ARRAY['warehouse_code'], ARRAY['warehouse_code'], 150, 'Company-scoped warehouse master.'),
  ('projects', 'Projects', 'projects', 'company', 'upsert',
    ARRAY['project_code'], ARRAY['project_code'], 160, 'MDP-09 project dimension master.'),
  ('locations', 'Locations', 'locations', 'company', 'upsert',
    ARRAY['location_code'], ARRAY['location_code'], 170, 'MDP-09 location dimension master.'),
  ('functional_entities', 'Functional Entities', 'functional_entities', 'company', 'upsert',
    ARRAY['entity_code'], ARRAY['entity_code'], 180, 'MDP-09 functional entity dimension master.'),

  ('fiscal_years', 'Fiscal Years', 'fiscal_years', 'company', 'upsert',
    ARRAY['year_name'], ARRAY['start_date','year_name'], 200, 'Company-scoped fiscal year master.'),
  ('fiscal_periods', 'Fiscal Periods', 'fiscal_periods', 'company', 'upsert',
    ARRAY['fiscal_year_id','period_number'], ARRAY['fiscal_year_id','period_number'], 210, 'Company-scoped fiscal period master.'),
  ('number_series', 'Number Series', 'number_series', 'company', 'upsert',
    ARRAY['branch_id','document_type_id'], ARRAY['branch_id','document_code','document_type_id'], 220, 'Company/branch document numbering master.'),
  ('company_accounting_config', 'Company Accounting Configuration', 'company_accounting_config', 'company', 'upsert',
    ARRAY[]::TEXT[], ARRAY['company_id'], 230, 'Singleton company accounting configuration.'),
  ('company_inventory_config', 'Company Inventory Configuration', 'company_inventory_config', 'company', 'upsert',
    ARRAY[]::TEXT[], ARRAY['company_id'], 240, 'MDP-13 singleton company inventory configuration.'),
  ('compliance_profiles', 'Compliance Profiles', 'compliance_profiles', 'company', 'upsert',
    ARRAY[]::TEXT[], ARRAY['company_id'], 250, 'Singleton company compliance profile.'),

  ('customer_groups', 'Customer Groups', 'customer_groups', 'company', 'upsert',
    ARRAY['group_code'], ARRAY['group_code'], 300, 'MDP-10 customer group master.'),
  ('supplier_groups', 'Supplier Groups', 'supplier_groups', 'company', 'upsert',
    ARRAY['group_code'], ARRAY['group_code'], 310, 'MDP-10 supplier group master.'),
  ('customers', 'Customers', 'customers', 'company', 'upsert',
    ARRAY['customer_code'], ARRAY['customer_code'], 320, 'Company-scoped customer master.'),
  ('suppliers', 'Suppliers', 'suppliers', 'company', 'upsert',
    ARRAY['supplier_code'], ARRAY['supplier_code'], 330, 'Company-scoped supplier master.'),
  ('party_contacts', 'Contacts', 'party_contacts', 'company', 'upsert',
    ARRAY['customer_id','supplier_id','contact_name'], ARRAY['customer_id','supplier_id','contact_name'], 340, 'MDP-10 customer/supplier contact master.'),
  ('employees', 'Employees', 'employees', 'company', 'upsert',
    ARRAY['employee_number'], ARRAY['employee_number'], 350, 'Personnel-lite master; includes MDP-11 salesperson/buyer designations when present.'),

  ('units_of_measure', 'Units of Measure', 'units_of_measure', 'company', 'upsert',
    ARRAY['uom_code'], ARRAY['uom_code'], 400, 'Company-scoped UOM master.'),
  ('item_categories', 'Item Categories', 'item_categories', 'company', 'upsert',
    ARRAY['category_code'], ARRAY['category_code'], 410, 'Company-scoped item category master.'),
  ('items', 'Items', 'items', 'company', 'upsert',
    ARRAY['item_code'], ARRAY['item_code'], 420, 'Company-scoped item/service master.'),
  ('item_uom_conversions', 'Item UOM Conversions', 'item_uom_conversions', 'company', 'upsert',
    ARRAY['item_id','uom_id'], ARRAY['item_id','uom_id'], 430, 'MDP-13 per-item alternate UOM conversion master.'),
  ('item_barcodes', 'Item Barcodes', 'item_barcodes', 'company', 'upsert',
    ARRAY['barcode'], ARRAY['barcode'], 440, 'MDP-13 item barcode master.'),
  ('item_media', 'Item Media', 'item_media', 'company', 'upsert',
    ARRAY['item_id','url'], ARRAY['item_id','sort_order','url'], 450, 'MDP-13 item media metadata master.'),

  ('bank_accounts', 'Company Bank Accounts', 'bank_accounts', 'company', 'upsert',
    ARRAY['bank_name','account_number'], ARRAY['bank_name','account_number'], 500, 'Company-scoped bank account master; bank_id may point to ref_banks.'),
  ('company_payment_modes', 'Company Payment Modes', 'company_payment_modes', 'company', 'upsert',
    ARRAY['payment_mode_id'], ARRAY['payment_mode_id'], 510, 'MDP-11 company-scoped payment mode GL mapping.'),
  ('percentage_tax_codes', 'Percentage Tax Codes', 'percentage_tax_codes', 'company', 'upsert',
    ARRAY['pt_code'], ARRAY['pt_code'], 520, 'Company-scoped percentage-tax code master.')
)
INSERT INTO master_data_import_registry (
  master_key, display_name, table_schema, table_name, scope, import_mode,
  business_key_columns, sort_columns, export_sequence, notes
)
SELECT master_key, display_name, 'public', table_name, scope, import_mode,
       business_key_columns, sort_columns, export_sequence, notes
FROM registry
WHERE to_regclass('public.' || quote_ident(table_name)) IS NOT NULL
ON CONFLICT (master_key) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  table_schema = EXCLUDED.table_schema,
  table_name = EXCLUDED.table_name,
  scope = EXCLUDED.scope,
  import_mode = EXCLUDED.import_mode,
  business_key_columns = EXCLUDED.business_key_columns,
  sort_columns = EXCLUDED.sort_columns,
  export_sequence = EXCLUDED.export_sequence,
  notes = EXCLUDED.notes;

-- ── 4. Metadata helpers ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_mdp15_import_columns(
  p_table_schema TEXT,
  p_table_name   TEXT
)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(c.column_name::TEXT ORDER BY c.ordinal_position), ARRAY[]::TEXT[])
  FROM information_schema.columns c
  WHERE c.table_schema = p_table_schema
    AND c.table_name = p_table_name
    AND COALESCE(c.is_generated, 'NEVER') = 'NEVER';
$$;

CREATE OR REPLACE FUNCTION fn_mdp15_find_record_id(
  p_company_id UUID,
  p_master_key TEXT,
  p_row        JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta        master_data_import_registry%ROWTYPE;
  v_filter      TEXT;
  v_sql         TEXT;
  v_col         TEXT;
  v_existing_id UUID;
BEGIN
  SELECT * INTO v_meta
  FROM master_data_import_registry
  WHERE master_key = p_master_key;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF p_row ? 'id' AND NULLIF(p_row ->> 'id', '') IS NOT NULL THEN
    v_filter := 'id::TEXT = $2';
    IF v_meta.scope = 'company' THEN
      v_filter := v_filter || ' AND company_id = $1';
    ELSIF v_meta.scope = 'company_self' THEN
      v_filter := v_filter || ' AND id = $1';
    END IF;

    v_sql := format('SELECT id FROM %I.%I WHERE %s LIMIT 1',
                    v_meta.table_schema, v_meta.table_name, v_filter);
    EXECUTE v_sql INTO v_existing_id USING p_company_id, p_row ->> 'id';
    RETURN v_existing_id;
  END IF;

  IF v_meta.scope = 'company_self' THEN
    v_sql := format('SELECT id FROM %I.%I WHERE id = $1 LIMIT 1',
                    v_meta.table_schema, v_meta.table_name);
    EXECUTE v_sql INTO v_existing_id USING p_company_id;
    RETURN v_existing_id;
  END IF;

  v_filter := CASE
    WHEN v_meta.scope = 'company' THEN 'company_id = $1'
    ELSE 'true'
  END;

  FOREACH v_col IN ARRAY v_meta.business_key_columns LOOP
    v_filter := v_filter || format(' AND to_jsonb(%1$I) = ($2 -> %2$L)', v_col, v_col);
  END LOOP;

  v_sql := format('SELECT id FROM %I.%I WHERE %s LIMIT 1',
                  v_meta.table_schema, v_meta.table_name, v_filter);
  EXECUTE v_sql INTO v_existing_id USING p_company_id, p_row;
  RETURN v_existing_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_mdp15_import_columns(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_mdp15_find_record_id(UUID, TEXT, JSONB) FROM PUBLIC;

-- ── 5. Template / manifest RPC ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_master_data_import_template(p_master_key TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta    master_data_import_registry%ROWTYPE;
  v_columns JSONB;
  v_fks     JSONB;
BEGIN
  SELECT * INTO v_meta
  FROM master_data_import_registry
  WHERE master_key = p_master_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown master data key %', p_master_key USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'column_name', c.column_name,
      'data_type', c.data_type,
      'udt_name', c.udt_name,
      'required_for_insert',
        (c.is_nullable = 'NO' AND c.column_default IS NULL
         AND c.column_name NOT IN ('id','company_id','created_at','updated_at')),
      'business_key', c.column_name = ANY(v_meta.business_key_columns),
      'scope_column', v_meta.scope = 'company' AND c.column_name = 'company_id',
      'default_expression', c.column_default
    )
    ORDER BY c.ordinal_position
  ), '[]'::JSONB)
  INTO v_columns
  FROM information_schema.columns c
  WHERE c.table_schema = v_meta.table_schema
    AND c.table_name = v_meta.table_name
    AND COALESCE(c.is_generated, 'NEVER') = 'NEVER';

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'source_column', src_att.attname,
      'target_table', tgt_ns.nspname || '.' || tgt_cls.relname,
      'target_column', tgt_att.attname
    )
    ORDER BY src_att.attname
  ), '[]'::JSONB)
  INTO v_fks
  FROM pg_constraint con
  JOIN pg_class src_cls ON src_cls.oid = con.conrelid
  JOIN pg_namespace src_ns ON src_ns.oid = src_cls.relnamespace
  JOIN pg_class tgt_cls ON tgt_cls.oid = con.confrelid
  JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt_cls.relnamespace
  JOIN unnest(con.conkey) WITH ORDINALITY src_key(attnum, ord) ON true
  JOIN unnest(con.confkey) WITH ORDINALITY tgt_key(attnum, ord) ON tgt_key.ord = src_key.ord
  JOIN pg_attribute src_att ON src_att.attrelid = con.conrelid AND src_att.attnum = src_key.attnum
  JOIN pg_attribute tgt_att ON tgt_att.attrelid = con.confrelid AND tgt_att.attnum = tgt_key.attnum
  WHERE con.contype = 'f'
    AND array_length(con.conkey, 1) = 1
    AND src_ns.nspname = v_meta.table_schema
    AND src_cls.relname = v_meta.table_name;

  RETURN jsonb_build_object(
    'format_version', 1,
    'master_key', v_meta.master_key,
    'display_name', v_meta.display_name,
    'table', v_meta.table_schema || '.' || v_meta.table_name,
    'scope', v_meta.scope,
    'import_mode', v_meta.import_mode,
    'business_key_columns', to_jsonb(v_meta.business_key_columns),
    'sort_columns', to_jsonb(v_meta.sort_columns),
    'columns', v_columns,
    'foreign_keys', v_fks,
    'template_rows', '[]'::JSONB,
    'notes', v_meta.notes
  );
END;
$$;

-- ── 6. Deterministic export RPCs ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_export_master_data(
  p_company_id       UUID,
  p_master_key       TEXT,
  p_include_inactive BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta        master_data_import_registry%ROWTYPE;
  v_columns     TEXT[];
  v_sort_cols   TEXT[];
  v_select_sql  TEXT;
  v_where_sql   TEXT := 'true';
  v_order_sql   TEXT;
  v_rows        JSONB;
  v_content     JSONB;
  v_hash        TEXT;
  v_log_id      UUID;
  v_row_count   INTEGER;
  v_scope_company UUID;
BEGIN
  SELECT * INTO v_meta
  FROM master_data_import_registry
  WHERE master_key = p_master_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown master data key %', p_master_key USING ERRCODE = '22023';
  END IF;

  v_columns := fn_mdp15_import_columns(v_meta.table_schema, v_meta.table_name);
  IF cardinality(v_columns) = 0 THEN
    RAISE EXCEPTION 'registered master % has no visible columns', p_master_key USING ERRCODE = '42703';
  END IF;

  IF v_meta.scope IN ('company','company_self') THEN
    IF p_company_id IS NULL THEN
      RAISE EXCEPTION 'company_id is required for % export', p_master_key USING ERRCODE = '23514';
    END IF;
    IF NOT is_company_member(p_company_id) THEN
      RAISE EXCEPTION 'not authorized to export master data for company %', p_company_id USING ERRCODE = '42501';
    END IF;
    v_scope_company := p_company_id;
    v_where_sql := CASE
      WHEN v_meta.scope = 'company' THEN 't.company_id = $1'
      ELSE 't.id = $1'
    END;
  END IF;

  IF NOT p_include_inactive AND 'is_active' = ANY(v_columns) THEN
    v_where_sql := v_where_sql || ' AND t.is_active IS TRUE';
  END IF;

  SELECT COALESCE(array_agg(c ORDER BY array_position(v_meta.sort_columns, c)), ARRAY[]::TEXT[])
  INTO v_sort_cols
  FROM unnest(v_meta.sort_columns) AS c
  WHERE c = ANY(v_columns);

  IF cardinality(v_sort_cols) = 0 THEN
    v_sort_cols := CASE WHEN 'id' = ANY(v_columns) THEN ARRAY['id'] ELSE ARRAY[v_columns[1]] END;
  END IF;

  SELECT string_agg(format('t.%I', c), ', ')
  INTO v_order_sql
  FROM unnest(v_sort_cols) AS c;

  v_select_sql := format(
    'SELECT COALESCE(jsonb_agg(to_jsonb(q)), ''[]''::jsonb)
       FROM (
         SELECT %s
         FROM %I.%I t
         WHERE %s
         ORDER BY %s
       ) q',
    (SELECT string_agg(format('t.%I', c), ', ') FROM unnest(v_columns) AS c),
    v_meta.table_schema,
    v_meta.table_name,
    v_where_sql,
    v_order_sql
  );

  EXECUTE v_select_sql INTO v_rows USING p_company_id;
  v_row_count := jsonb_array_length(v_rows);

  v_content := jsonb_build_object(
    'format_version', 1,
    'master_key', v_meta.master_key,
    'display_name', v_meta.display_name,
    'table', v_meta.table_schema || '.' || v_meta.table_name,
    'scope', v_meta.scope,
    'company_id', v_scope_company,
    'columns', to_jsonb(v_columns),
    'row_count', v_row_count,
    'rows', v_rows
  );
  v_hash := encode(extensions.digest(convert_to(v_content::TEXT, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO master_data_export_logs (
    company_id, master_key, export_format, row_count, content_hash, exported_by
  )
  VALUES (v_scope_company, v_meta.master_key, 'json-v1', v_row_count, v_hash, auth.uid())
  RETURNING id INTO v_log_id;

  RETURN v_content || jsonb_build_object(
    'content_sha256', v_hash,
    'export_log_id', v_log_id,
    'exported_at', NOW()
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_export_master_data_package(
  p_company_id       UUID,
  p_include_global   BOOLEAN DEFAULT true,
  p_include_inactive BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta    master_data_import_registry%ROWTYPE;
  v_export  JSONB;
  v_exports JSONB := '[]'::JSONB;
  v_content JSONB;
  v_hash    TEXT;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id is required for package export' USING ERRCODE = '23514';
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to export master data for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  FOR v_meta IN
    SELECT *
    FROM master_data_import_registry
    WHERE (p_include_global OR scope IN ('company','company_self'))
    ORDER BY export_sequence, master_key
  LOOP
    v_export := fn_export_master_data(
      CASE WHEN v_meta.scope IN ('company','company_self') THEN p_company_id ELSE NULL END,
      v_meta.master_key,
      p_include_inactive
    );
    v_exports := v_exports || jsonb_build_array(v_export - 'exported_at' - 'export_log_id');
  END LOOP;

  v_content := jsonb_build_object(
    'format_version', 1,
    'company_id', p_company_id,
    'export_count', jsonb_array_length(v_exports),
    'exports', v_exports
  );
  v_hash := encode(extensions.digest(convert_to(v_content::TEXT, 'UTF8'), 'sha256'), 'hex');

  RETURN v_content || jsonb_build_object('content_sha256', v_hash, 'exported_at', NOW());
END;
$$;

-- ── 7. Import validation and commit RPCs ─────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_validate_master_data_import(
  p_company_id UUID,
  p_master_key TEXT,
  p_rows       JSONB,
  p_options    JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta          master_data_import_registry%ROWTYPE;
  v_allowed_cols  TEXT[];
  v_required_cols TEXT[];
  v_rows          JSONB := COALESCE(p_rows, '[]'::JSONB);
  v_row           JSONB;
  v_effective_row JSONB;
  v_row_number    INTEGER := 0;
  v_errors        JSONB;
  v_result_rows   JSONB := '[]'::JSONB;
  v_unknown_cols  JSONB;
  v_seen_keys     JSONB := '{}'::JSONB;
  v_key           TEXT;
  v_key_col       TEXT;
  v_missing_key   BOOLEAN;
  v_existing_id   UUID;
  v_error_count   INTEGER := 0;
  v_insert_count  INTEGER := 0;
  v_update_count  INTEGER := 0;
  v_action        TEXT;
  v_id_exists_any BOOLEAN;
  v_fk            RECORD;
  v_fk_value      TEXT;
  v_ref_ok        BOOLEAN;
  v_ref_in_payload BOOLEAN;
  v_sql           TEXT;
  v_required_col  TEXT;
BEGIN
  SELECT * INTO v_meta
  FROM master_data_import_registry
  WHERE master_key = p_master_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown master data key %', p_master_key USING ERRCODE = '22023';
  END IF;

  IF v_meta.import_mode <> 'upsert' THEN
    RETURN jsonb_build_object(
      'master_key', p_master_key,
      'valid', false,
      'row_count', CASE WHEN jsonb_typeof(v_rows) = 'array' THEN jsonb_array_length(v_rows) ELSE 0 END,
      'valid_row_count', 0,
      'error_count', 1,
      'insert_count', 0,
      'update_count', 0,
      'rows', '[]'::JSONB,
      'errors', jsonb_build_array(jsonb_build_object(
        'code', 'master_not_importable',
        'detail', COALESCE(v_meta.notes, 'registered master is export-only or governed elsewhere')
      ))
    );
  END IF;

  IF v_meta.scope IN ('company','company_self') THEN
    IF p_company_id IS NULL THEN
      RAISE EXCEPTION 'company_id is required for % import validation', p_master_key USING ERRCODE = '23514';
    END IF;
    IF NOT is_company_member(p_company_id) THEN
      RAISE EXCEPTION 'not authorized to validate master data for company %', p_company_id USING ERRCODE = '42501';
    END IF;
  END IF;

  IF jsonb_typeof(v_rows) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object(
      'master_key', p_master_key,
      'valid', false,
      'row_count', 0,
      'valid_row_count', 0,
      'error_count', 1,
      'insert_count', 0,
      'update_count', 0,
      'rows', '[]'::JSONB,
      'errors', jsonb_build_array(jsonb_build_object('code','rows_not_array','detail','rows must be a JSON array'))
    );
  END IF;

  v_allowed_cols := fn_mdp15_import_columns(v_meta.table_schema, v_meta.table_name);

  FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows) LOOP
    v_row_number := v_row_number + 1;
    v_errors := '[]'::JSONB;
    v_action := 'error';
    v_existing_id := NULL;
    v_effective_row := v_row;

    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code','row_not_object',
        'detail','each import row must be a JSON object'
      ));
    ELSE
      SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::JSONB)
      INTO v_unknown_cols
      FROM jsonb_object_keys(v_row) AS keys(k)
      WHERE NOT (k = ANY(v_allowed_cols));
      IF jsonb_array_length(v_unknown_cols) > 0 THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code','unknown_columns',
          'columns', v_unknown_cols,
          'detail','row contains columns that are not part of the registered master table'
        ));
      END IF;

      IF v_meta.scope = 'company' THEN
        IF v_row ? 'company_id' AND v_row ->> 'company_id' IS NOT NULL
           AND v_row ->> 'company_id' <> p_company_id::TEXT THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code','company_scope_mismatch',
            'column','company_id',
            'detail','row company_id does not match the import company_id'
          ));
        END IF;
        v_effective_row := v_row || jsonb_build_object('company_id', p_company_id);
      ELSIF v_meta.scope = 'company_self' THEN
        IF NOT (v_row ? 'id') OR v_row ->> 'id' IS NULL OR v_row ->> 'id' <> p_company_id::TEXT THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code','company_self_id_required',
            'column','id',
            'detail','company imports must carry id equal to the selected company_id'
          ));
        END IF;
      END IF;

      BEGIN
        EXECUTE format('SELECT jsonb_populate_record(NULL::%I.%I, $1)',
                       v_meta.table_schema, v_meta.table_name)
        USING v_effective_row;
      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code','invalid_column_value',
          'detail', SQLERRM
        ));
      END;

      IF v_row ? 'id' AND NULLIF(v_row ->> 'id', '') IS NOT NULL THEN
        v_sql := format('SELECT EXISTS (SELECT 1 FROM %I.%I WHERE id::TEXT = $1)',
                        v_meta.table_schema, v_meta.table_name);
        EXECUTE v_sql INTO v_id_exists_any USING v_row ->> 'id';
      ELSE
        v_id_exists_any := false;
      END IF;

      v_existing_id := fn_mdp15_find_record_id(p_company_id, p_master_key, v_effective_row);
      IF v_id_exists_any AND v_existing_id IS NULL THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code','record_scope_mismatch',
          'column','id',
          'detail','the supplied id exists outside this import scope'
        ));
      END IF;

      v_missing_key := false;
      IF NOT (v_effective_row ? 'id' AND NULLIF(v_effective_row ->> 'id', '') IS NOT NULL) THEN
        FOREACH v_key_col IN ARRAY v_meta.business_key_columns LOOP
          IF NOT (v_effective_row ? v_key_col)
             OR v_effective_row ->> v_key_col IS NULL
             OR btrim(v_effective_row ->> v_key_col) = '' THEN
            v_missing_key := true;
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code','business_key_missing',
              'column', v_key_col,
              'detail','business key column is required when id is not supplied'
            ));
          END IF;
        END LOOP;
      END IF;

      IF v_effective_row ? 'id' AND NULLIF(v_effective_row ->> 'id', '') IS NOT NULL THEN
        v_key := 'id:' || (v_effective_row ->> 'id');
      ELSIF cardinality(v_meta.business_key_columns) = 0 THEN
        v_key := 'singleton:' || COALESCE(p_company_id::TEXT, v_meta.master_key);
      ELSIF NOT v_missing_key THEN
        v_key := 'key';
        FOREACH v_key_col IN ARRAY v_meta.business_key_columns LOOP
          v_key := v_key || '|' || v_key_col || '=' || COALESCE(v_effective_row ->> v_key_col, '<null>');
        END LOOP;
      ELSE
        v_key := NULL;
      END IF;

      IF v_key IS NOT NULL THEN
        IF v_seen_keys ? v_key THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code','duplicate_source_key',
            'detail', format('duplicate source business key; first seen at row %s', v_seen_keys ->> v_key)
          ));
        ELSE
          v_seen_keys := v_seen_keys || jsonb_build_object(v_key, v_row_number);
        END IF;
      END IF;

      IF v_existing_id IS NULL THEN
        SELECT COALESCE(array_agg(c.column_name::TEXT ORDER BY c.ordinal_position), ARRAY[]::TEXT[])
        INTO v_required_cols
        FROM information_schema.columns c
        WHERE c.table_schema = v_meta.table_schema
          AND c.table_name = v_meta.table_name
          AND COALESCE(c.is_generated, 'NEVER') = 'NEVER'
          AND c.is_nullable = 'NO'
          AND c.column_default IS NULL
          AND c.column_name NOT IN ('id','company_id','created_at','updated_at');

        FOREACH v_required_col IN ARRAY v_required_cols LOOP
          IF NOT (v_effective_row ? v_required_col)
             OR v_effective_row ->> v_required_col IS NULL
             OR (jsonb_typeof(v_effective_row -> v_required_col) = 'string'
                 AND btrim(v_effective_row ->> v_required_col) = '') THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code','required_column_missing',
              'column', v_required_col,
              'detail','required insert column is missing or blank'
            ));
          END IF;
        END LOOP;
      END IF;

      FOR v_fk IN
        SELECT src_att.attname::TEXT AS source_column,
               tgt_ns.nspname::TEXT AS target_schema,
               tgt_cls.relname::TEXT AS target_table,
               tgt_att.attname::TEXT AS target_column,
               EXISTS (
                 SELECT 1
                 FROM pg_attribute company_att
                 WHERE company_att.attrelid = tgt_cls.oid
                   AND company_att.attname = 'company_id'
                   AND NOT company_att.attisdropped
               ) AS target_company_scoped
        FROM pg_constraint con
        JOIN pg_class src_cls ON src_cls.oid = con.conrelid
        JOIN pg_namespace src_ns ON src_ns.oid = src_cls.relnamespace
        JOIN pg_class tgt_cls ON tgt_cls.oid = con.confrelid
        JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt_cls.relnamespace
        JOIN unnest(con.conkey) WITH ORDINALITY src_key(attnum, ord) ON true
        JOIN unnest(con.confkey) WITH ORDINALITY tgt_key(attnum, ord) ON tgt_key.ord = src_key.ord
        JOIN pg_attribute src_att ON src_att.attrelid = con.conrelid AND src_att.attnum = src_key.attnum
        JOIN pg_attribute tgt_att ON tgt_att.attrelid = con.confrelid AND tgt_att.attnum = tgt_key.attnum
        WHERE con.contype = 'f'
          AND array_length(con.conkey, 1) = 1
          AND src_ns.nspname = v_meta.table_schema
          AND src_cls.relname = v_meta.table_name
      LOOP
        IF v_effective_row ? v_fk.source_column
           AND v_effective_row ->> v_fk.source_column IS NOT NULL THEN
          v_fk_value := v_effective_row ->> v_fk.source_column;
          v_ref_in_payload := false;

          IF v_fk.target_schema = v_meta.table_schema
             AND v_fk.target_table = v_meta.table_name
             AND v_fk.target_column = 'id' THEN
            IF v_effective_row ? 'id' AND v_effective_row ->> 'id' = v_fk_value THEN
              v_errors := v_errors || jsonb_build_array(jsonb_build_object(
                'code','self_reference',
                'column', v_fk.source_column,
                'detail','a row cannot reference itself as parent'
              ));
            END IF;

            SELECT EXISTS (
              SELECT 1
              FROM jsonb_array_elements(v_rows) AS payload_rows(source_row)
              WHERE source_row ? 'id'
                AND source_row ->> 'id' = v_fk_value
            )
            INTO v_ref_in_payload;
          END IF;

          IF v_ref_in_payload THEN
            v_ref_ok := true;
          ELSE
            v_sql := format(
              'SELECT EXISTS (SELECT 1 FROM %I.%I t WHERE t.%I::TEXT = $1%s)',
              v_fk.target_schema,
              v_fk.target_table,
              v_fk.target_column,
              CASE
                WHEN v_fk.target_company_scoped AND p_company_id IS NOT NULL THEN ' AND t.company_id = $2'
                ELSE ''
              END
            );
            IF v_fk.target_company_scoped AND p_company_id IS NOT NULL THEN
              EXECUTE v_sql INTO v_ref_ok USING v_fk_value, p_company_id;
            ELSE
              EXECUTE v_sql INTO v_ref_ok USING v_fk_value;
            END IF;
          END IF;

          IF NOT v_ref_ok THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code','missing_reference',
              'column', v_fk.source_column,
              'target_table', v_fk.target_schema || '.' || v_fk.target_table,
              'detail','referenced row does not exist in the allowed scope'
            ));
          END IF;
        END IF;
      END LOOP;
    END IF;

    IF jsonb_array_length(v_errors) = 0 THEN
      IF v_existing_id IS NULL THEN
        v_action := 'insert';
        v_insert_count := v_insert_count + 1;
      ELSE
        v_action := 'update';
        v_update_count := v_update_count + 1;
      END IF;
    ELSE
      v_error_count := v_error_count + 1;
      v_action := 'error';
    END IF;

    v_result_rows := v_result_rows || jsonb_build_array(jsonb_build_object(
      'row_number', v_row_number,
      'source_row', v_row,
      'is_valid', jsonb_array_length(v_errors) = 0,
      'action', v_action,
      'record_id', v_existing_id,
      'errors', v_errors
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'master_key', p_master_key,
    'valid', v_error_count = 0,
    'row_count', v_row_number,
    'valid_row_count', v_row_number - v_error_count,
    'error_count', v_error_count,
    'insert_count', v_insert_count,
    'update_count', v_update_count,
    'rows', v_result_rows,
    'errors', '[]'::JSONB
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_import_master_data(
  p_company_id       UUID,
  p_master_key       TEXT,
  p_rows             JSONB,
  p_preview          BOOLEAN DEFAULT true,
  p_idempotency_key  TEXT DEFAULT NULL,
  p_options          JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta          master_data_import_registry%ROWTYPE;
  v_validation    JSONB;
  v_hash          TEXT;
  v_existing_batch master_data_import_batches%ROWTYPE;
  v_batch_id      UUID;
  v_status        TEXT;
  v_result_row    JSONB;
  v_row_count     INTEGER;
  v_valid_count   INTEGER;
  v_error_count   INTEGER;
  v_inserted      INTEGER := 0;
  v_updated       INTEGER := 0;
  v_skipped       INTEGER := 0;
  v_pending       RECORD;
  v_progress      BOOLEAN;
  v_payload       JSONB;
  v_existing_id   UUID;
  v_record_id     UUID;
  v_allowed_cols  TEXT[];
  v_insert_cols   TEXT[];
  v_update_cols   TEXT[];
  v_cols_sql      TEXT;
  v_set_sql       TEXT;
  v_sql           TEXT;
  v_fk            RECORD;
  v_fk_value      TEXT;
  v_ref_exists    BOOLEAN;
  v_pass          INTEGER := 0;
BEGIN
  SELECT * INTO v_meta
  FROM master_data_import_registry
  WHERE master_key = p_master_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown master data key %', p_master_key USING ERRCODE = '22023';
  END IF;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'company_id', p_company_id,
    'master_key', p_master_key,
    'rows', COALESCE(p_rows, 'null'::JSONB)
  )::TEXT, 'UTF8'), 'sha256'), 'hex');

  IF NOT p_preview AND p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing_batch
    FROM master_data_import_batches b
    WHERE b.company_id IS NOT DISTINCT FROM p_company_id
      AND b.master_key = p_master_key
      AND b.idempotency_key = p_idempotency_key
      AND b.mode = 'commit'
    LIMIT 1;

    IF FOUND THEN
      IF v_existing_batch.input_hash <> v_hash THEN
        RAISE EXCEPTION 'idempotency key % was already used with a different payload', p_idempotency_key
          USING ERRCODE = '23505';
      END IF;

      RETURN jsonb_build_object(
        'batch_id', v_existing_batch.id,
        'master_key', p_master_key,
        'status', v_existing_batch.status,
        'idempotent_replay', true,
        'row_count', v_existing_batch.row_count,
        'valid_row_count', v_existing_batch.valid_row_count,
        'error_count', v_existing_batch.error_count,
        'inserted_count', v_existing_batch.inserted_count,
        'updated_count', v_existing_batch.updated_count,
        'skipped_count', v_existing_batch.skipped_count,
        'input_hash', v_existing_batch.input_hash
      );
    END IF;
  END IF;

  v_validation := fn_validate_master_data_import(p_company_id, p_master_key, p_rows, p_options);
  v_row_count := (v_validation ->> 'row_count')::INTEGER;
  v_valid_count := (v_validation ->> 'valid_row_count')::INTEGER;
  v_error_count := (v_validation ->> 'error_count')::INTEGER;
  v_status := CASE WHEN (v_validation ->> 'valid')::BOOLEAN THEN 'validated' ELSE 'failed' END;

  INSERT INTO master_data_import_batches (
    company_id, master_key, mode, status, idempotency_key, input_hash,
    row_count, valid_row_count, error_count, error_summary, options,
    created_by, completed_at
  )
  VALUES (
    CASE WHEN v_meta.scope IN ('company','company_self') THEN p_company_id ELSE NULL END,
    p_master_key,
    CASE WHEN p_preview THEN 'preview' ELSE 'commit' END,
    v_status,
    CASE WHEN p_preview THEN NULL ELSE p_idempotency_key END,
    v_hash,
    v_row_count,
    v_valid_count,
    v_error_count,
    COALESCE(v_validation -> 'errors', '[]'::JSONB),
    COALESCE(p_options, '{}'::JSONB),
    auth.uid(),
    CASE WHEN p_preview OR v_status = 'failed' THEN NOW() ELSE NULL END
  )
  RETURNING id INTO v_batch_id;

  FOR v_result_row IN SELECT value FROM jsonb_array_elements(v_validation -> 'rows') LOOP
    INSERT INTO master_data_import_rows (
      batch_id, row_number, source_row, action, record_id, is_valid, validation_errors
    )
    VALUES (
      v_batch_id,
      (v_result_row ->> 'row_number')::INTEGER,
      v_result_row -> 'source_row',
      v_result_row ->> 'action',
      NULLIF(v_result_row ->> 'record_id', '')::UUID,
      (v_result_row ->> 'is_valid')::BOOLEAN,
      v_result_row -> 'errors'
    );
  END LOOP;

  IF p_preview OR v_status = 'failed' THEN
    RETURN v_validation || jsonb_build_object(
      'batch_id', v_batch_id,
      'status', v_status,
      'mode', CASE WHEN p_preview THEN 'preview' ELSE 'commit' END,
      'input_hash', v_hash
    );
  END IF;

  IF v_meta.scope IN ('company','company_self') AND NOT can_admin_company(p_company_id) THEN
    UPDATE master_data_import_batches
       SET status = 'failed',
           error_count = GREATEST(error_count, 1),
           error_summary = jsonb_build_array(jsonb_build_object(
             'code','not_authorized',
             'detail','committing master-data imports requires company admin authority'
           )),
           completed_at = NOW()
     WHERE id = v_batch_id;

    RETURN v_validation || jsonb_build_object(
      'batch_id', v_batch_id,
      'status', 'failed',
      'mode', 'commit',
      'input_hash', v_hash,
      'errors', jsonb_build_array(jsonb_build_object(
        'code','not_authorized',
        'detail','committing master-data imports requires company admin authority'
      ))
    );
  END IF;

  v_allowed_cols := fn_mdp15_import_columns(v_meta.table_schema, v_meta.table_name);

  DROP TABLE IF EXISTS pg_temp.mdp15_pending_import;
  CREATE TEMP TABLE mdp15_pending_import (
    row_number INTEGER PRIMARY KEY,
    row_data   JSONB NOT NULL,
    processed  BOOLEAN NOT NULL DEFAULT false
  ) ON COMMIT DROP;

  INSERT INTO mdp15_pending_import (row_number, row_data)
  SELECT (r.value ->> 'row_number')::INTEGER, r.value -> 'source_row'
  FROM jsonb_array_elements(v_validation -> 'rows') AS r(value)
  WHERE (r.value ->> 'is_valid')::BOOLEAN
  ORDER BY (r.value ->> 'row_number')::INTEGER;

  BEGIN
    LOOP
      v_pass := v_pass + 1;
      v_progress := false;

      FOR v_pending IN
        SELECT row_number, row_data
        FROM mdp15_pending_import
        WHERE processed = false
        ORDER BY row_number
      LOOP
        v_payload := v_pending.row_data;
        IF v_meta.scope = 'company' THEN
          v_payload := v_payload || jsonb_build_object('company_id', p_company_id);
        END IF;

        -- Defer self-referencing rows until their parent has been inserted.
        v_ref_exists := true;
        FOR v_fk IN
          SELECT src_att.attname::TEXT AS source_column,
                 tgt_ns.nspname::TEXT AS target_schema,
                 tgt_cls.relname::TEXT AS target_table,
                 tgt_att.attname::TEXT AS target_column
          FROM pg_constraint con
          JOIN pg_class src_cls ON src_cls.oid = con.conrelid
          JOIN pg_namespace src_ns ON src_ns.oid = src_cls.relnamespace
          JOIN pg_class tgt_cls ON tgt_cls.oid = con.confrelid
          JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt_cls.relnamespace
          JOIN unnest(con.conkey) WITH ORDINALITY src_key(attnum, ord) ON true
          JOIN unnest(con.confkey) WITH ORDINALITY tgt_key(attnum, ord) ON tgt_key.ord = src_key.ord
          JOIN pg_attribute src_att ON src_att.attrelid = con.conrelid AND src_att.attnum = src_key.attnum
          JOIN pg_attribute tgt_att ON tgt_att.attrelid = con.confrelid AND tgt_att.attnum = tgt_key.attnum
          WHERE con.contype = 'f'
            AND array_length(con.conkey, 1) = 1
            AND src_ns.nspname = v_meta.table_schema
            AND src_cls.relname = v_meta.table_name
            AND tgt_ns.nspname = v_meta.table_schema
            AND tgt_cls.relname = v_meta.table_name
            AND tgt_att.attname = 'id'
        LOOP
          IF v_payload ? v_fk.source_column AND v_payload ->> v_fk.source_column IS NOT NULL THEN
            v_fk_value := v_payload ->> v_fk.source_column;
            v_sql := format('SELECT EXISTS (SELECT 1 FROM %I.%I WHERE id::TEXT = $1)',
                            v_meta.table_schema, v_meta.table_name);
            EXECUTE v_sql INTO v_ref_exists USING v_fk_value;
            IF NOT v_ref_exists THEN
              EXIT;
            END IF;
          END IF;
        END LOOP;

        IF NOT v_ref_exists THEN
          CONTINUE;
        END IF;

        v_existing_id := fn_mdp15_find_record_id(p_company_id, p_master_key, v_payload);

        IF v_existing_id IS NULL THEN
          SELECT COALESCE(array_agg(k ORDER BY array_position(v_allowed_cols, k)), ARRAY[]::TEXT[])
          INTO v_insert_cols
          FROM jsonb_object_keys(v_payload) AS keys(k)
          WHERE k = ANY(v_allowed_cols)
            AND jsonb_typeof(v_payload -> k) <> 'null';

          SELECT string_agg(format('%I', c), ', ')
          INTO v_cols_sql
          FROM unnest(v_insert_cols) AS c;

          v_sql := format(
            'INSERT INTO %I.%I (%s)
             SELECT %s
             FROM jsonb_populate_record(NULL::%I.%I, $1) AS r
             RETURNING id',
            v_meta.table_schema, v_meta.table_name, v_cols_sql, v_cols_sql,
            v_meta.table_schema, v_meta.table_name
          );
          EXECUTE v_sql INTO v_record_id USING v_payload;
          v_inserted := v_inserted + 1;

          UPDATE master_data_import_rows
             SET action = 'insert', record_id = v_record_id, imported_at = NOW()
           WHERE batch_id = v_batch_id AND row_number = v_pending.row_number;
        ELSE
          SELECT COALESCE(array_agg(k ORDER BY array_position(v_allowed_cols, k)), ARRAY[]::TEXT[])
          INTO v_update_cols
          FROM jsonb_object_keys(v_payload) AS keys(k)
          WHERE k = ANY(v_allowed_cols)
            AND k NOT IN ('id','company_id','created_at','created_by');

          IF cardinality(v_update_cols) = 0 THEN
            v_skipped := v_skipped + 1;
            UPDATE master_data_import_rows
               SET action = 'skip', record_id = v_existing_id, imported_at = NOW()
             WHERE batch_id = v_batch_id AND row_number = v_pending.row_number;
          ELSE
            SELECT string_agg(format('%1$I = r.%1$I', c), ', ')
            INTO v_set_sql
            FROM unnest(v_update_cols) AS c;

            v_sql := format(
              'UPDATE %I.%I AS t
                  SET %s
                 FROM jsonb_populate_record(NULL::%I.%I, $2) AS r
                WHERE t.id = $1
                RETURNING t.id',
              v_meta.table_schema, v_meta.table_name, v_set_sql,
              v_meta.table_schema, v_meta.table_name
            );
            EXECUTE v_sql INTO v_record_id USING v_existing_id, v_payload;
            v_updated := v_updated + 1;

            UPDATE master_data_import_rows
               SET action = 'update', record_id = v_record_id, imported_at = NOW()
             WHERE batch_id = v_batch_id AND row_number = v_pending.row_number;
          END IF;
        END IF;

        UPDATE mdp15_pending_import
           SET processed = true
         WHERE row_number = v_pending.row_number;
        v_progress := true;
      END LOOP;

      EXIT WHEN NOT EXISTS (SELECT 1 FROM mdp15_pending_import WHERE processed = false);

      IF NOT v_progress OR v_pass > GREATEST(v_row_count, 1) THEN
        RAISE EXCEPTION 'could not resolve hierarchical/self references for % import', p_master_key
          USING ERRCODE = '23503';
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    UPDATE master_data_import_batches
       SET status = 'failed',
           error_count = GREATEST(error_count, 1),
           error_summary = jsonb_build_array(jsonb_build_object(
             'code','commit_failed',
             'detail', SQLERRM
           )),
           completed_at = NOW()
     WHERE id = v_batch_id;

    RETURN v_validation || jsonb_build_object(
      'batch_id', v_batch_id,
      'status', 'failed',
      'mode', 'commit',
      'input_hash', v_hash,
      'inserted_count', 0,
      'updated_count', 0,
      'skipped_count', 0,
      'errors', jsonb_build_array(jsonb_build_object(
        'code','commit_failed',
        'detail', SQLERRM
      ))
    );
  END;

  UPDATE master_data_import_batches
     SET status = 'imported',
         inserted_count = v_inserted,
         updated_count = v_updated,
         skipped_count = v_skipped,
         completed_at = NOW()
   WHERE id = v_batch_id;

  RETURN v_validation || jsonb_build_object(
    'batch_id', v_batch_id,
    'status', 'imported',
    'mode', 'commit',
    'input_hash', v_hash,
    'inserted_count', v_inserted,
    'updated_count', v_updated,
    'skipped_count', v_skipped,
    'idempotent_replay', false
  );
END;
$$;

-- ── 8. Grants and comments ───────────────────────────────────────────────────
REVOKE ALL ON FUNCTION fn_master_data_import_template(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_export_master_data_package(UUID, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_validate_master_data_import(UUID, TEXT, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_master_data_import_template(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_export_master_data_package(UUID, BOOLEAN, BOOLEAN) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_master_data_import(UUID, TEXT, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB) TO authenticated, service_role;

COMMENT ON TABLE master_data_import_registry IS
  'MDP-15: registry of current supported master-data import/export surfaces, their scope, governance mode, business key, and deterministic export order.';
COMMENT ON TABLE master_data_import_batches IS
  'MDP-15: audited batch header for master-data import preview/commit, including input hash, idempotency key, validation counts, and commit counts.';
COMMENT ON TABLE master_data_import_rows IS
  'MDP-15: row-level validation/action record for each master-data import batch.';
COMMENT ON TABLE master_data_export_logs IS
  'MDP-15: audited export provenance for deterministic master-data JSON exports, storing row count and content SHA-256.';
COMMENT ON FUNCTION fn_master_data_import_template(TEXT) IS
  'MDP-15: returns the backend JSON import/export template for a registered master, including columns, keys, FK metadata, and governance mode.';
COMMENT ON FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN) IS
  'MDP-15: exports one registered master as deterministic JSON rows and logs row count plus SHA-256 content hash. Company-scoped exports require membership.';
COMMENT ON FUNCTION fn_export_master_data_package(UUID, BOOLEAN, BOOLEAN) IS
  'MDP-15: exports all registered master-data surfaces in dependency order for backup/migration/onboarding. Logs each component export.';
COMMENT ON FUNCTION fn_validate_master_data_import(UUID, TEXT, JSONB, JSONB) IS
  'MDP-15: validates a master-data JSON row array without mutation. Reports row-level unknown-column, required-column, duplicate-key, scope, type, and FK errors.';
COMMENT ON FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB) IS
  'MDP-15: preview-or-commit master-data import. Commit is admin-gated, idempotency-key aware, prevalidated, audited, and rollback-safe.';
