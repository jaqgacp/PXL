-- =============================================================================
-- MDP-08 - Guided Company Provisioning
--
-- Adds an extensible, template-driven orchestration layer over the provisioning
-- primitives delivered by MDP-05/06/07/09/11/13. New-company provisioning is a
-- single atomic RPC: legal identity, owner membership, branch, warehouse, COA,
-- standard masters, fiscal calendar, number series, accounting/compliance and
-- inventory defaults either all succeed or all roll back.
-- =============================================================================

-- -- 1. Stable company identifier ------------------------------------------------
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS company_code TEXT;

ALTER TABLE companies
  DROP CONSTRAINT IF EXISTS companies_company_code_format_check;
ALTER TABLE companies
  ADD CONSTRAINT companies_company_code_format_check
  CHECK (
    company_code IS NULL
    OR company_code ~ '^[A-Z][A-Z0-9_-]{1,19}$'
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_company_code
  ON companies (upper(company_code))
  WHERE company_code IS NOT NULL;

COMMENT ON COLUMN companies.company_code IS
  'MDP-08: stable 2-20 character company identifier used by guided provisioning. Nullable for backward compatibility with companies created before MDP-08.';

-- MDP-15 keeps company-self imports update-only by id, but deterministic company
-- exports should now sort by the stable code when one exists.
UPDATE master_data_import_registry
SET sort_columns = ARRAY['company_code','registered_name'],
    notes = 'The company row itself. MDP-08 adds company_code; imports remain update-only for the selected company id.',
    updated_at = NOW()
WHERE master_key = 'companies';

-- -- 2. Extensible provisioning template and module registries -------------------
CREATE TABLE IF NOT EXISTS company_provisioning_templates (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_code             TEXT NOT NULL,
  template_version          INTEGER NOT NULL DEFAULT 1 CHECK (template_version > 0),
  template_name             TEXT NOT NULL,
  country_code              TEXT NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  localization_code         TEXT NOT NULL,
  coa_template_code         TEXT NOT NULL REFERENCES coa_templates(template_code),
  default_functional_currency_code TEXT NOT NULL REFERENCES currencies(currency_code),
  default_reporting_currency_code  TEXT NOT NULL REFERENCES currencies(currency_code),
  applicable_entity_types   TEXT[] NOT NULL DEFAULT ARRAY[
    'sole_proprietor','opc','corporation','partnership','cooperative'
  ]::TEXT[],
  template_config           JSONB NOT NULL DEFAULT '{}'::JSONB,
  is_current                BOOLEAN NOT NULL DEFAULT true,
  is_active                 BOOLEAN NOT NULL DEFAULT true,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (template_code, template_version),
  CHECK (template_code ~ '^[A-Z][A-Z0-9_-]{1,39}$'),
  CHECK (jsonb_typeof(template_config) = 'object')
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_company_provisioning_templates_current
  ON company_provisioning_templates (template_code)
  WHERE is_current;

DROP TRIGGER IF EXISTS trg_company_provisioning_templates_updated_at
  ON company_provisioning_templates;
CREATE TRIGGER trg_company_provisioning_templates_updated_at
  BEFORE UPDATE ON company_provisioning_templates
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS company_provisioning_modules (
  module_code      TEXT PRIMARY KEY,
  module_name      TEXT NOT NULL,
  handler_schema   TEXT NOT NULL DEFAULT 'public',
  handler_function TEXT NOT NULL,
  execution_order  INTEGER NOT NULL,
  is_active        BOOLEAN NOT NULL DEFAULT true,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (module_code ~ '^[a-z][a-z0-9_]*$'),
  CHECK (handler_schema ~ '^[a-z_][a-z0-9_]*$'),
  CHECK (handler_function ~ '^[a-z_][a-z0-9_]*$')
);

DROP TRIGGER IF EXISTS trg_company_provisioning_modules_updated_at
  ON company_provisioning_modules;
CREATE TRIGGER trg_company_provisioning_modules_updated_at
  BEFORE UPDATE ON company_provisioning_modules
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS company_provisioning_template_modules (
  template_id     UUID NOT NULL REFERENCES company_provisioning_templates(id) ON DELETE CASCADE,
  module_code     TEXT NOT NULL REFERENCES company_provisioning_modules(module_code),
  execution_order INTEGER,
  is_required     BOOLEAN NOT NULL DEFAULT true,
  is_enabled      BOOLEAN NOT NULL DEFAULT true,
  module_config   JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (template_id, module_code),
  CHECK (jsonb_typeof(module_config) = 'object')
);

DROP TRIGGER IF EXISTS trg_company_provisioning_template_modules_updated_at
  ON company_provisioning_template_modules;
CREATE TRIGGER trg_company_provisioning_template_modules_updated_at
  BEFORE UPDATE ON company_provisioning_template_modules
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS company_provisioning_runs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID REFERENCES companies(id) ON DELETE SET NULL,
  template_id       UUID REFERENCES company_provisioning_templates(id),
  template_code     TEXT NOT NULL,
  template_version  INTEGER,
  request_actor     TEXT NOT NULL,
  requested_by      UUID REFERENCES auth.users(id),
  idempotency_key   TEXT NOT NULL,
  request_hash      TEXT NOT NULL,
  requested_company_code TEXT,
  status            TEXT NOT NULL CHECK (status IN ('running','succeeded','failed')),
  validation_errors JSONB NOT NULL DEFAULT '[]'::JSONB,
  module_results    JSONB NOT NULL DEFAULT '{}'::JSONB,
  result            JSONB,
  error_code        TEXT,
  error_detail      TEXT,
  started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (request_actor, idempotency_key),
  CHECK (jsonb_typeof(validation_errors) = 'array'),
  CHECK (jsonb_typeof(module_results) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_company_provisioning_runs_company
  ON company_provisioning_runs (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_company_provisioning_runs_requester
  ON company_provisioning_runs (requested_by, created_at DESC);

DROP TRIGGER IF EXISTS trg_company_provisioning_runs_updated_at
  ON company_provisioning_runs;
CREATE TRIGGER trg_company_provisioning_runs_updated_at
  BEFORE UPDATE ON company_provisioning_runs
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_audit_company_provisioning_runs
  ON company_provisioning_runs;
CREATE TRIGGER trg_audit_company_provisioning_runs
  AFTER INSERT OR UPDATE OR DELETE ON company_provisioning_runs
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

ALTER TABLE company_provisioning_templates        ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_provisioning_modules          ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_provisioning_template_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_provisioning_runs             ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_provisioning_templates_read
  ON company_provisioning_templates;
CREATE POLICY company_provisioning_templates_read
  ON company_provisioning_templates FOR SELECT TO authenticated
  USING (is_active);

DROP POLICY IF EXISTS company_provisioning_modules_read
  ON company_provisioning_modules;
CREATE POLICY company_provisioning_modules_read
  ON company_provisioning_modules FOR SELECT TO authenticated
  USING (is_active);

DROP POLICY IF EXISTS company_provisioning_template_modules_read
  ON company_provisioning_template_modules;
CREATE POLICY company_provisioning_template_modules_read
  ON company_provisioning_template_modules FOR SELECT TO authenticated
  USING (
    is_enabled
    AND EXISTS (
      SELECT 1
      FROM company_provisioning_templates t
      WHERE t.id = template_id AND t.is_active
    )
  );

DROP POLICY IF EXISTS company_provisioning_runs_read
  ON company_provisioning_runs;
CREATE POLICY company_provisioning_runs_read
  ON company_provisioning_runs FOR SELECT TO authenticated
  USING (
    requested_by = auth.uid()
    OR (company_id IS NOT NULL AND can_admin_company(company_id))
  );

REVOKE ALL ON TABLE company_provisioning_templates,
  company_provisioning_modules, company_provisioning_template_modules,
  company_provisioning_runs FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE company_provisioning_templates,
  company_provisioning_modules, company_provisioning_template_modules,
  company_provisioning_runs TO authenticated;
GRANT ALL ON TABLE company_provisioning_templates,
  company_provisioning_modules, company_provisioning_template_modules,
  company_provisioning_runs TO service_role;

-- -- 3. Permission decision for creating a company -------------------------------
-- Company creation has no target company yet. Reuse MDP-03's companies.create
-- role mapping from any current membership. The zero-company case is the explicit
-- bootstrap path for the first authenticated owner.
CREATE OR REPLACE FUNCTION fn_can_provision_company()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() = 'service_role' THEN
    RETURN true;
  END IF;
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM companies) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM user_company_memberships m
    JOIN master_data_role_permissions rp
      ON rp.role_code = m.role AND rp.is_allowed
    JOIN master_data_permissions p
      ON p.permission_code = rp.permission_code
     AND p.master_key = 'companies'
     AND p.action = 'create'
     AND p.is_available
    WHERE m.user_id = auth.uid()
  );
END;
$$;

DROP POLICY IF EXISTS "companies_create" ON companies;
CREATE POLICY "companies_create" ON companies
  FOR INSERT TO authenticated
  WITH CHECK (fn_can_provision_company());

-- -- 4. Complete the standard COA/config needed by advance settlement paths -------
INSERT INTO coa_template_lines (
  template_id, account_code, account_name, account_type, normal_balance,
  is_postable, parent_account_code, fs_group, fs_subgroup,
  cash_flow_category, is_control_account, allow_subledger, subledger_type,
  is_tax_account, sort_order
)
SELECT t.id, v.account_code, v.account_name, v.account_type, v.normal_balance,
       true, v.parent_account_code, v.fs_group, v.fs_subgroup,
       NULL, true, true, v.subledger_type, false, v.sort_order
FROM coa_templates t
CROSS JOIN (VALUES
  ('1350','Supplier Down Payments','asset','debit','1000','assets','Current Assets','payable',14),
  ('2050','Customer Advances','liability','credit','2000','liabilities','Current Liabilities','receivable',32)
) AS v(account_code, account_name, account_type, normal_balance,
       parent_account_code, fs_group, fs_subgroup, subledger_type, sort_order)
WHERE t.template_code = 'PH_STANDARD'
ON CONFLICT (template_id, account_code) DO NOTHING;

CREATE OR REPLACE FUNCTION fn_provision_company_accounting_config(p_company_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config_id UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision accounting config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO company_accounting_config (company_id, created_by, updated_by)
  VALUES (p_company_id, auth.uid(), auth.uid())
  ON CONFLICT (company_id) DO NOTHING;

  UPDATE company_accounting_config cfg
     SET ar_account_id           = COALESCE(cfg.ar_account_id,           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1200' AND is_postable)),
         default_cash_account_id = COALESCE(cfg.default_cash_account_id, (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1010' AND is_postable)),
         vat_payable_account_id  = COALESCE(cfg.vat_payable_account_id,  (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2100' AND is_postable)),
         ewt_withheld_account_id = COALESCE(cfg.ewt_withheld_account_id, (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1410' AND is_postable)),
         ap_account_id           = COALESCE(cfg.ap_account_id,           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2010' AND is_postable)),
         input_vat_account_id    = COALESCE(cfg.input_vat_account_id,    (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1400' AND is_postable)),
         ewt_payable_account_id  = COALESCE(cfg.ewt_payable_account_id,  (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2110' AND is_postable)),
         customer_advances_account_id = COALESCE(cfg.customer_advances_account_id,
           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2050' AND is_postable)),
         supplier_down_payments_account_id = COALESCE(cfg.supplier_down_payments_account_id,
           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1350' AND is_postable)),
         updated_by = auth.uid()
   WHERE cfg.company_id = p_company_id;

  PERFORM fn_sync_coa_control_accounts(p_company_id);
  SELECT id INTO v_config_id
  FROM company_accounting_config
  WHERE company_id = p_company_id;
  RETURN v_config_id;
END;
$$;

-- Correct a pre-existing MDP-07 validation inversion. Posting and UI already use
-- customer advances as a liability and supplier down payments as an asset.
CREATE OR REPLACE FUNCTION fn_validate_company_accounting_config(p_company_id UUID)
RETURNS TABLE (check_code TEXT, detail TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to validate accounting config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM company_accounting_config WHERE company_id = p_company_id) THEN
    RETURN QUERY SELECT 'config_missing'::TEXT,
      format('no company_accounting_config row for company %s', p_company_id);
    RETURN;
  END IF;

  RETURN QUERY
  WITH cfg AS (
    SELECT * FROM company_accounting_config WHERE company_id = p_company_id
  ),
  mapped(label, account_id, expected_type) AS (
    SELECT 'ar_account_id', ar_account_id, 'asset' FROM cfg WHERE ar_account_id IS NOT NULL
    UNION ALL SELECT 'default_cash_account_id', default_cash_account_id, 'asset' FROM cfg WHERE default_cash_account_id IS NOT NULL
    UNION ALL SELECT 'vat_payable_account_id', vat_payable_account_id, 'liability' FROM cfg WHERE vat_payable_account_id IS NOT NULL
    UNION ALL SELECT 'input_vat_account_id', input_vat_account_id, 'asset' FROM cfg WHERE input_vat_account_id IS NOT NULL
    UNION ALL SELECT 'ewt_withheld_account_id', ewt_withheld_account_id, 'asset' FROM cfg WHERE ewt_withheld_account_id IS NOT NULL
    UNION ALL SELECT 'ewt_payable_account_id', ewt_payable_account_id, 'liability' FROM cfg WHERE ewt_payable_account_id IS NOT NULL
    UNION ALL SELECT 'ap_account_id', ap_account_id, 'liability' FROM cfg WHERE ap_account_id IS NOT NULL
    UNION ALL SELECT 'customer_advances_account_id', customer_advances_account_id, 'liability' FROM cfg WHERE customer_advances_account_id IS NOT NULL
    UNION ALL SELECT 'supplier_down_payments_account_id', supplier_down_payments_account_id, 'asset' FROM cfg WHERE supplier_down_payments_account_id IS NOT NULL
  )
  SELECT 'account_not_in_company', format('%s -> account %s is not a chart_of_accounts row of this company', m.label, m.account_id)
  FROM mapped m
  WHERE NOT EXISTS (
    SELECT 1 FROM chart_of_accounts c
    WHERE c.id = m.account_id AND c.company_id = p_company_id
  )
  UNION ALL
  SELECT 'account_not_postable', format('%s -> account %s is not postable', m.label, c.account_code)
  FROM mapped m
  JOIN chart_of_accounts c ON c.id = m.account_id AND c.company_id = p_company_id
  WHERE c.is_postable = false
  UNION ALL
  SELECT 'account_wrong_type', format('%s -> account %s is %s, expected %s', m.label, c.account_code, c.account_type, m.expected_type)
  FROM mapped m
  JOIN chart_of_accounts c ON c.id = m.account_id AND c.company_id = p_company_id
  WHERE c.account_type <> m.expected_type
  UNION ALL
  SELECT 'currency_inactive', format('%s currency %s is not an active currency', lbl, code)
  FROM (
    SELECT 'functional' AS lbl, functional_currency_code AS code FROM companies WHERE id = p_company_id
    UNION ALL
    SELECT 'reporting', reporting_currency_code FROM companies WHERE id = p_company_id
  ) cc
  WHERE NOT EXISTS (
    SELECT 1 FROM currencies cu
    WHERE cu.currency_code = cc.code AND cu.is_active
  );
END;
$$;

-- -- 5. Uniform module adapters over existing provisioning primitives -------------
CREATE OR REPLACE FUNCTION fn_mdp08_module_coa(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count INTEGER;
BEGIN
  v_count := fn_seed_company_coa(
    (p_context->>'company_id')::UUID,
    p_context->>'coa_template_code'
  );
  RETURN jsonb_build_object('account_count', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_uom(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_inserted INTEGER;
BEGIN
  v_inserted := fn_seed_company_uom((p_context->>'company_id')::UUID);
  RETURN jsonb_build_object(
    'inserted_count', v_inserted,
    'row_count', (SELECT count(*) FROM units_of_measure WHERE company_id = (p_context->>'company_id')::UUID)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_percentage_tax(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_inserted INTEGER;
BEGIN
  v_inserted := fn_seed_company_percentage_tax_codes((p_context->>'company_id')::UUID);
  RETURN jsonb_build_object('inserted_count', v_inserted);
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_fiscal_calendar(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_fiscal_year_id UUID;
BEGIN
  v_fiscal_year_id := fn_create_fiscal_year(
    (p_context->>'company_id')::UUID,
    (p_context->'request'->'fiscal_year'->>'start_date')::DATE,
    NULLIF(p_context->'request'->'fiscal_year'->>'year_name', '')
  );
  RETURN jsonb_build_object(
    'fiscal_year_id', v_fiscal_year_id,
    'period_count', (SELECT count(*) FROM fiscal_periods WHERE fiscal_year_id = v_fiscal_year_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_number_series(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count INTEGER;
BEGIN
  v_count := fn_provision_number_series(
    (p_context->>'company_id')::UUID,
    (p_context->>'branch_id')::UUID
  );
  RETURN jsonb_build_object('series_count', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_accounting_config(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID; v_errors INTEGER;
BEGIN
  v_id := fn_provision_company_accounting_config((p_context->>'company_id')::UUID);
  SELECT count(*) INTO v_errors
  FROM fn_validate_company_accounting_config((p_context->>'company_id')::UUID);
  IF v_errors > 0 THEN
    RAISE EXCEPTION 'provisioned accounting configuration failed % validation check(s)', v_errors
      USING ERRCODE = '23514';
  END IF;
  RETURN jsonb_build_object('config_id', v_id, 'validation_error_count', 0);
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_compliance(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  v_id := fn_provision_compliance_profile((p_context->>'company_id')::UUID);
  RETURN jsonb_build_object(
    'profile_id', v_id,
    'calendar_event_count', (SELECT count(*) FROM tax_calendar_events WHERE company_id = (p_context->>'company_id')::UUID)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_dimensions(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count INTEGER;
BEGIN
  v_count := fn_provision_company_dimension_defaults((p_context->>'company_id')::UUID);
  RETURN jsonb_build_object('default_dimension_count', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_inventory_config(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID; v_company_id UUID := (p_context->>'company_id')::UUID;
BEGIN
  v_id := fn_provision_company_inventory_config(v_company_id);
  UPDATE company_inventory_config
  SET default_warehouse_id = (p_context->>'warehouse_id')::UUID,
      updated_by = auth.uid()
  WHERE company_id = v_company_id
    AND default_warehouse_id IS DISTINCT FROM (p_context->>'warehouse_id')::UUID;
  RETURN jsonb_build_object('config_id', v_id, 'default_warehouse_id', p_context->>'warehouse_id');
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_module_payment_modes(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id UUID := (p_context->>'company_id')::UUID;
  v_cash_id UUID;
  v_count INTEGER;
BEGIN
  SELECT default_cash_account_id INTO v_cash_id
  FROM company_accounting_config
  WHERE company_id = v_company_id;
  IF v_cash_id IS NULL THEN
    RAISE EXCEPTION 'default cash account is required before payment-mode provisioning'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO company_payment_modes (
    company_id, payment_mode_id, gl_account_id, description,
    created_by, updated_by
  )
  SELECT v_company_id, pm.id, v_cash_id,
         'Provisioned by ' || (p_context->>'template_code'),
         auth.uid(), auth.uid()
  FROM ref_payment_modes pm
  WHERE pm.is_active
    AND pm.code IN (
      SELECT jsonb_array_elements_text(
        COALESCE(p_context->'module_config'->'payment_mode_codes', '["CASH"]'::JSONB)
      )
    )
  ON CONFLICT (company_id, payment_mode_id) DO NOTHING;

  SELECT count(*) INTO v_count
  FROM company_payment_modes
  WHERE company_id = v_company_id;
  RETURN jsonb_build_object('payment_mode_count', v_count);
END;
$$;

-- -- 6. Philippine Standard provisioning template -------------------------------
INSERT INTO company_provisioning_modules (
  module_code, module_name, handler_schema, handler_function,
  execution_order, notes
) VALUES
  ('chart_of_accounts', 'Chart of Accounts', 'public', 'fn_mdp08_module_coa', 100, 'Adapter over MDP-05 fn_seed_company_coa.'),
  ('units_of_measure', 'Units of Measure', 'public', 'fn_mdp08_module_uom', 200, 'Adapter over MDP-05 fn_seed_company_uom.'),
  ('percentage_tax', 'Percentage Tax Defaults', 'public', 'fn_mdp08_module_percentage_tax', 210, 'Adapter over MDP-05 percentage-tax defaults.'),
  ('fiscal_calendar', 'Fiscal Calendar', 'public', 'fn_mdp08_module_fiscal_calendar', 300, 'Adapter over MDP-06 fiscal calendar generation.'),
  ('number_series', 'Number Series', 'public', 'fn_mdp08_module_number_series', 310, 'Adapter over MDP-06 BIR document number-series provisioning.'),
  ('accounting_configuration', 'Accounting Configuration', 'public', 'fn_mdp08_module_accounting_config', 400, 'Adapter over MDP-07 accounting config plus validation.'),
  ('compliance_profile', 'Compliance Profile', 'public', 'fn_mdp08_module_compliance', 410, 'Adapter over MDP-07 compliance provisioning.'),
  ('dimension_defaults', 'Dimension Defaults', 'public', 'fn_mdp08_module_dimensions', 500, 'Adapter over MDP-09 dimension defaults.'),
  ('inventory_configuration', 'Inventory Configuration', 'public', 'fn_mdp08_module_inventory_config', 510, 'Adapter over MDP-13 inventory defaults.'),
  ('payment_modes', 'Payment Modes', 'public', 'fn_mdp08_module_payment_modes', 520, 'Initializes template-selected MDP-11 company payment modes.')
ON CONFLICT (module_code) DO UPDATE
SET module_name = EXCLUDED.module_name,
    handler_schema = EXCLUDED.handler_schema,
    handler_function = EXCLUDED.handler_function,
    execution_order = EXCLUDED.execution_order,
    notes = EXCLUDED.notes,
    is_active = true,
    updated_at = NOW();

INSERT INTO company_provisioning_templates (
  template_code, template_version, template_name, country_code,
  localization_code, coa_template_code,
  default_functional_currency_code, default_reporting_currency_code,
  template_config
) VALUES (
  'PH_STANDARD', 1, 'Philippine Standard', 'PH', 'en-PH',
  'PH_STANDARD', 'PHP', 'PHP',
  jsonb_build_object(
    'default_branch', jsonb_build_object(
      'branch_code', 'HO', 'branch_name', 'Head Office',
      'branch_type', 'head_office', 'tin_branch_code', '00000'
    ),
    'default_warehouse', jsonb_build_object(
      'warehouse_code', 'MAIN', 'warehouse_name', 'Main Warehouse',
      'warehouse_type', 'main'
    )
  )
)
ON CONFLICT (template_code, template_version) DO UPDATE
SET template_name = EXCLUDED.template_name,
    country_code = EXCLUDED.country_code,
    localization_code = EXCLUDED.localization_code,
    coa_template_code = EXCLUDED.coa_template_code,
    default_functional_currency_code = EXCLUDED.default_functional_currency_code,
    default_reporting_currency_code = EXCLUDED.default_reporting_currency_code,
    template_config = EXCLUDED.template_config,
    is_current = true,
    is_active = true,
    updated_at = NOW();

INSERT INTO company_provisioning_template_modules (
  template_id, module_code, is_required, is_enabled, module_config
)
SELECT t.id, m.module_code, true, true,
       CASE WHEN m.module_code = 'payment_modes'
            THEN '{"payment_mode_codes":["CASH"]}'::JSONB
            ELSE '{}'::JSONB END
FROM company_provisioning_templates t
JOIN company_provisioning_modules m ON m.is_active
WHERE t.template_code = 'PH_STANDARD'
  AND t.template_version = 1
ON CONFLICT (template_id, module_code) DO UPDATE
SET is_required = EXCLUDED.is_required,
    is_enabled = EXCLUDED.is_enabled,
    module_config = EXCLUDED.module_config,
    updated_at = NOW();

-- -- 7. Side-effect-free server validation ---------------------------------------
CREATE OR REPLACE FUNCTION fn_mdp08_try_uuid(p_value TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  RETURN p_value::UUID;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION fn_mdp08_try_date(p_value TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  RETURN p_value::DATE;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_company_provisioning(p_request JSONB)
RETURNS TABLE (
  error_order INTEGER,
  check_code  TEXT,
  field_name  TEXT,
  detail      TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company        JSONB;
  v_branch         JSONB;
  v_warehouse      JSONB;
  v_fiscal         JSONB;
  v_template       company_provisioning_templates%ROWTYPE;
  v_template_code  TEXT;
  v_template_ver   INTEGER;
  v_tin             TEXT;
  v_signatory_tin   TEXT;
  v_fiscal_start    DATE;
  v_fiscal_month    INTEGER;
  v_parent_id       UUID;
  v_rdo_id          UUID;
  v_branch_rdo_id   UUID;
  v_functional      TEXT;
  v_reporting       TEXT;
  v_required        TEXT;
BEGIN
  IF NOT fn_can_provision_company() THEN
    RAISE EXCEPTION 'not authorized to provision companies' USING ERRCODE = '42501';
  END IF;

  IF p_request IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' THEN
    RETURN QUERY SELECT 10, 'request_not_object', 'request', 'provisioning request must be a JSON object';
    RETURN;
  END IF;

  v_company := p_request->'company';
  v_branch := p_request->'default_branch';
  v_warehouse := p_request->'default_warehouse';
  v_fiscal := p_request->'fiscal_year';
  v_template_code := NULLIF(btrim(p_request->>'template_code'), '');
  v_template_ver := CASE
    WHEN COALESCE(p_request->>'template_version', '') ~ '^[0-9]+$'
    THEN (p_request->>'template_version')::INTEGER
    ELSE NULL
  END;

  IF v_template_code IS NULL THEN
    RETURN QUERY SELECT 20, 'template_required', 'template_code', 'template_code is required';
  ELSE
    SELECT * INTO v_template
    FROM company_provisioning_templates t
    WHERE t.template_code = v_template_code
      AND t.is_active
      AND (
        (v_template_ver IS NULL AND t.is_current)
        OR t.template_version = v_template_ver
      )
    ORDER BY t.is_current DESC, t.template_version DESC
    LIMIT 1;

    IF NOT FOUND THEN
      RETURN QUERY SELECT 21, 'template_invalid', 'template_code',
        format('template %s version %s does not exist or is inactive',
          v_template_code, COALESCE(v_template_ver::TEXT, 'current'));
    END IF;
  END IF;

  IF jsonb_typeof(v_company) IS DISTINCT FROM 'object' THEN
    RETURN QUERY SELECT 30, 'company_required', 'company', 'company must be a JSON object';
    RETURN;
  END IF;

  FOREACH v_required IN ARRAY ARRAY[
    'company_code','entity_type','registered_name','line_of_business','tin',
    'tax_registration','accounting_period','address_line_1','address_line_2',
    'city','province','zip_code','email','signatory_name','signatory_position'
  ] LOOP
    IF NULLIF(btrim(v_company->>v_required), '') IS NULL THEN
      RETURN QUERY SELECT 100, 'required_field_missing', 'company.' || v_required,
        format('%s is required', v_required);
    END IF;
  END LOOP;

  IF NULLIF(v_company->>'company_code', '') IS NOT NULL
     AND (v_company->>'company_code') !~ '^[A-Z][A-Z0-9_-]{1,19}$' THEN
    RETURN QUERY SELECT 110, 'company_code_invalid', 'company.company_code',
      'company_code must be 2-20 uppercase letters, digits, underscores, or hyphens and start with a letter';
  END IF;
  IF EXISTS (
    SELECT 1 FROM companies c
    WHERE c.company_code IS NOT NULL
      AND upper(c.company_code) = upper(v_company->>'company_code')
  ) THEN
    RETURN QUERY SELECT 111, 'company_code_duplicate', 'company.company_code',
      format('company code %s already exists', v_company->>'company_code');
  END IF;

  IF COALESCE(v_company->>'entity_type', '') NOT IN (
    'sole_proprietor','opc','corporation','partnership','cooperative'
  ) THEN
    RETURN QUERY SELECT 120, 'entity_type_invalid', 'company.entity_type', 'entity_type is invalid';
  ELSIF v_template.id IS NOT NULL
        AND NOT ((v_company->>'entity_type') = ANY(v_template.applicable_entity_types)) THEN
    RETURN QUERY SELECT 121, 'template_entity_type_invalid', 'company.entity_type',
      format('template %s does not support entity type %s', v_template.template_code, v_company->>'entity_type');
  END IF;

  IF COALESCE(v_company->>'tax_registration', '') NOT IN ('vat','non_vat','exempt') THEN
    RETURN QUERY SELECT 130, 'taxpayer_classification_invalid', 'company.tax_registration',
      'tax_registration must be vat, non_vat, or exempt';
  END IF;

  BEGIN
    v_tin := fn_format_ph_tin(v_company->>'tin');
  EXCEPTION WHEN OTHERS THEN
    v_tin := NULL;
  END;
  IF v_tin IS NULL OR v_company->>'tin' IS DISTINCT FROM v_tin THEN
    RETURN QUERY SELECT 140, 'tin_invalid', 'company.tin', 'TIN must use XXX-XXX-XXX-XXXXX';
  ELSIF EXISTS (SELECT 1 FROM companies c WHERE c.tin = v_tin) THEN
    RETURN QUERY SELECT 141, 'tin_duplicate', 'company.tin', format('TIN %s already exists', v_tin);
  END IF;

  IF NULLIF(btrim(v_company->>'signatory_tin'), '') IS NOT NULL THEN
    BEGIN
      v_signatory_tin := fn_format_ph_tin(v_company->>'signatory_tin');
    EXCEPTION WHEN OTHERS THEN
      v_signatory_tin := NULL;
    END;
    IF v_signatory_tin IS NULL OR v_company->>'signatory_tin' IS DISTINCT FROM v_signatory_tin THEN
      RETURN QUERY SELECT 142, 'signatory_tin_invalid', 'company.signatory_tin',
        'signatory_tin must use XXX-XXX-XXX-XXXXX';
    END IF;
  END IF;

  IF NULLIF(btrim(v_company->>'email'), '') IS NOT NULL
     AND (v_company->>'email') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RETURN QUERY SELECT 150, 'email_invalid', 'company.email', 'email is not valid';
  END IF;

  IF NULLIF(btrim(v_company->>'workspace_accent_color'), '') IS NOT NULL
     AND (v_company->>'workspace_accent_color') !~ '^#[0-9A-Fa-f]{6}$' THEN
    RETURN QUERY SELECT 151, 'workspace_accent_invalid', 'company.workspace_accent_color',
      'workspace_accent_color must be a six-digit hexadecimal color';
  END IF;

  IF NULLIF(v_company->>'parent_company_id', '') IS NOT NULL THEN
    v_parent_id := fn_mdp08_try_uuid(v_company->>'parent_company_id');
    IF v_parent_id IS NULL OR NOT EXISTS (SELECT 1 FROM companies WHERE id = v_parent_id) THEN
      RETURN QUERY SELECT 160, 'parent_company_invalid', 'company.parent_company_id',
        'parent_company_id does not reference an existing company';
    ELSIF NOT can_admin_company(v_parent_id) THEN
      RETURN QUERY SELECT 161, 'parent_company_not_authorized', 'company.parent_company_id',
        'caller must administer the selected parent company';
    END IF;
  END IF;

  IF NULLIF(v_company->>'rdo_id', '') IS NOT NULL THEN
    v_rdo_id := fn_mdp08_try_uuid(v_company->>'rdo_id');
    IF v_rdo_id IS NULL OR NOT EXISTS (SELECT 1 FROM ref_rdo_codes WHERE id = v_rdo_id) THEN
      RETURN QUERY SELECT 170, 'rdo_invalid', 'company.rdo_id', 'rdo_id does not reference an RDO';
    END IF;
  END IF;

  IF COALESCE(v_company->>'accounting_period', '') NOT IN ('calendar','fiscal') THEN
    RETURN QUERY SELECT 180, 'accounting_period_invalid', 'company.accounting_period',
      'accounting_period must be calendar or fiscal';
  END IF;
  v_fiscal_month := CASE
    WHEN COALESCE(v_company->>'fiscal_start_month', '') ~ '^[0-9]+$'
    THEN (v_company->>'fiscal_start_month')::INTEGER
    WHEN v_company->>'accounting_period' = 'calendar' THEN 1
    ELSE NULL
  END;
  IF v_company->>'accounting_period' = 'fiscal'
     AND (v_fiscal_month IS NULL OR v_fiscal_month NOT BETWEEN 1 AND 12) THEN
    RETURN QUERY SELECT 181, 'fiscal_start_month_invalid', 'company.fiscal_start_month',
      'fiscal_start_month from 1 through 12 is required for a fiscal company';
  END IF;

  IF jsonb_typeof(v_fiscal) IS DISTINCT FROM 'object' THEN
    RETURN QUERY SELECT 190, 'fiscal_year_required', 'fiscal_year', 'fiscal_year must be a JSON object';
  ELSE
    v_fiscal_start := fn_mdp08_try_date(v_fiscal->>'start_date');
    IF v_fiscal_start IS NULL THEN
      RETURN QUERY SELECT 191, 'fiscal_start_date_invalid', 'fiscal_year.start_date',
        'fiscal_year.start_date must be a valid date';
    ELSE
      IF extract(day FROM v_fiscal_start) <> 1 THEN
        RETURN QUERY SELECT 192, 'fiscal_start_day_invalid', 'fiscal_year.start_date',
          'fiscal year must begin on the first day of a month';
      END IF;
      IF v_company->>'accounting_period' = 'calendar'
         AND extract(month FROM v_fiscal_start) <> 1 THEN
        RETURN QUERY SELECT 193, 'calendar_year_start_invalid', 'fiscal_year.start_date',
          'a calendar accounting period must begin on January 1';
      ELSIF v_company->>'accounting_period' = 'fiscal'
            AND v_fiscal_month IS NOT NULL
            AND extract(month FROM v_fiscal_start) <> v_fiscal_month THEN
        RETURN QUERY SELECT 194, 'fiscal_month_mismatch', 'fiscal_year.start_date',
          'fiscal year start date must match company.fiscal_start_month';
      END IF;
    END IF;
  END IF;

  v_functional := COALESCE(NULLIF(v_company->>'functional_currency_code', ''), v_template.default_functional_currency_code);
  v_reporting := COALESCE(NULLIF(v_company->>'reporting_currency_code', ''), v_template.default_reporting_currency_code);
  IF v_functional IS NULL OR NOT EXISTS (
    SELECT 1 FROM currencies WHERE currency_code = v_functional AND is_active
  ) THEN
    RETURN QUERY SELECT 200, 'functional_currency_invalid', 'company.functional_currency_code',
      format('functional currency %s does not exist or is inactive', COALESCE(v_functional, '(none)'));
  END IF;
  IF v_reporting IS NULL OR NOT EXISTS (
    SELECT 1 FROM currencies WHERE currency_code = v_reporting AND is_active
  ) THEN
    RETURN QUERY SELECT 201, 'reporting_currency_invalid', 'company.reporting_currency_code',
      format('reporting currency %s does not exist or is inactive', COALESCE(v_reporting, '(none)'));
  END IF;

  IF jsonb_typeof(v_branch) IS DISTINCT FROM 'object' THEN
    RETURN QUERY SELECT 210, 'default_branch_required', 'default_branch', 'default_branch must be a JSON object';
  ELSE
    IF COALESCE(v_branch->>'branch_code', '') !~ '^[A-Z][A-Z0-9_-]{0,19}$' THEN
      RETURN QUERY SELECT 211, 'branch_code_invalid', 'default_branch.branch_code',
        'default branch code must be 1-20 uppercase letters, digits, underscores, or hyphens';
    END IF;
    IF NULLIF(btrim(v_branch->>'branch_name'), '') IS NULL THEN
      RETURN QUERY SELECT 212, 'branch_name_required', 'default_branch.branch_name', 'default branch name is required';
    END IF;
    IF COALESCE(v_branch->>'branch_type', '') NOT IN (
      'head_office','branch','satellite_office','warehouse','project_site'
    ) THEN
      RETURN QUERY SELECT 213, 'branch_type_invalid', 'default_branch.branch_type', 'default branch type is invalid';
    END IF;
    IF COALESCE(v_branch->>'tin_branch_code', '') !~ '^[0-9]{5}$' THEN
      RETURN QUERY SELECT 214, 'branch_tin_code_invalid', 'default_branch.tin_branch_code',
        'default branch TIN code must be exactly five digits';
    END IF;
    IF NULLIF(v_branch->>'rdo_id', '') IS NOT NULL THEN
      v_branch_rdo_id := fn_mdp08_try_uuid(v_branch->>'rdo_id');
      IF v_branch_rdo_id IS NULL OR NOT EXISTS (SELECT 1 FROM ref_rdo_codes WHERE id = v_branch_rdo_id) THEN
        RETURN QUERY SELECT 215, 'branch_rdo_invalid', 'default_branch.rdo_id',
          'default branch rdo_id does not reference an RDO';
      END IF;
    END IF;
  END IF;

  IF jsonb_typeof(v_warehouse) IS DISTINCT FROM 'object' THEN
    RETURN QUERY SELECT 220, 'default_warehouse_required', 'default_warehouse',
      'default_warehouse must be a JSON object';
  ELSE
    IF COALESCE(v_warehouse->>'warehouse_code', '') !~ '^[A-Z][A-Z0-9_-]{0,19}$' THEN
      RETURN QUERY SELECT 221, 'warehouse_code_invalid', 'default_warehouse.warehouse_code',
        'default warehouse code must be 1-20 uppercase letters, digits, underscores, or hyphens';
    END IF;
    IF NULLIF(btrim(v_warehouse->>'warehouse_name'), '') IS NULL THEN
      RETURN QUERY SELECT 222, 'warehouse_name_required', 'default_warehouse.warehouse_name',
        'default warehouse name is required';
    END IF;
    IF COALESCE(v_warehouse->>'warehouse_type', '') NOT IN ('main','transit','consignment','damaged') THEN
      RETURN QUERY SELECT 223, 'warehouse_type_invalid', 'default_warehouse.warehouse_type',
        'default warehouse type is invalid';
    END IF;
  END IF;

  IF v_template.id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM coa_templates c
      WHERE c.template_code = v_template.coa_template_code AND c.is_active
    ) THEN
      RETURN QUERY SELECT 230, 'coa_template_invalid', 'template_code',
        format('COA template %s is missing or inactive', v_template.coa_template_code);
    END IF;
    IF EXISTS (
      SELECT 1
      FROM company_provisioning_template_modules tm
      LEFT JOIN company_provisioning_modules m
        ON m.module_code = tm.module_code AND m.is_active
      WHERE tm.template_id = v_template.id
        AND tm.is_required
        AND tm.is_enabled
        AND (
          m.module_code IS NULL
          OR to_regprocedure(format('%I.%I(jsonb)', m.handler_schema, m.handler_function)) IS NULL
        )
    ) THEN
      RETURN QUERY SELECT 231, 'template_module_invalid', 'template_code',
        'one or more required template modules has no active JSON handler';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM company_provisioning_template_modules tm
      WHERE tm.template_id = v_template.id AND tm.is_required AND tm.is_enabled
    ) THEN
      RETURN QUERY SELECT 232, 'template_modules_missing', 'template_code',
        'template has no required provisioning modules';
    END IF;
  END IF;
END;
$$;

-- -- 8. Atomic, idempotent orchestration RPC -------------------------------------
CREATE OR REPLACE FUNCTION fn_provision_company(
  p_request JSONB,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor             TEXT;
  v_key               TEXT;
  v_hash              TEXT;
  v_run               company_provisioning_runs%ROWTYPE;
  v_run_id            UUID;
  v_template          company_provisioning_templates%ROWTYPE;
  v_company           JSONB;
  v_branch            JSONB;
  v_warehouse         JSONB;
  v_errors            JSONB;
  v_company_id        UUID;
  v_branch_id         UUID;
  v_warehouse_id      UUID;
  v_context           JSONB;
  v_module_result     JSONB;
  v_module_results    JSONB := '{}'::JSONB;
  v_result            JSONB;
  v_module            RECORD;
  v_error_code        TEXT;
  v_error_detail      TEXT;
  v_error_constraint  TEXT;
  v_template_version  INTEGER;
BEGIN
  IF NOT fn_can_provision_company() THEN
    RAISE EXCEPTION 'not authorized to provision companies' USING ERRCODE = '42501';
  END IF;

  v_actor := COALESCE(auth.uid()::TEXT, auth.role(), 'database_owner');
  v_hash := encode(extensions.digest(convert_to(COALESCE(p_request, 'null'::JSONB)::TEXT, 'UTF8'), 'sha256'), 'hex');
  v_key := COALESCE(NULLIF(btrim(p_idempotency_key), ''), v_hash);
  IF length(v_key) > 200 THEN
    RAISE EXCEPTION 'idempotency key exceeds 200 characters' USING ERRCODE = '22023';
  END IF;

  -- Serialize concurrent retries before inspecting or creating the run record.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_actor || ':' || v_key, 0));

  SELECT * INTO v_run
  FROM company_provisioning_runs
  WHERE request_actor = v_actor AND idempotency_key = v_key
  FOR UPDATE;

  IF FOUND THEN
    IF v_run.request_hash <> v_hash THEN
      RAISE EXCEPTION 'idempotency key was already used for a different provisioning request'
        USING ERRCODE = '22023';
    END IF;
    IF v_run.status = 'succeeded' THEN
      RETURN COALESCE(v_run.result, '{}'::JSONB) || jsonb_build_object(
        'idempotent_replay', true,
        'provisioning_run_id', v_run.id
      );
    END IF;

    v_run_id := v_run.id;
    UPDATE company_provisioning_runs
    SET status = 'running', validation_errors = '[]'::JSONB,
        module_results = '{}'::JSONB, result = NULL,
        error_code = NULL, error_detail = NULL,
        started_at = NOW(), completed_at = NULL
    WHERE id = v_run_id;
  ELSE
    INSERT INTO company_provisioning_runs (
      template_code, request_actor, requested_by, idempotency_key,
      request_hash, requested_company_code, status
    ) VALUES (
      COALESCE(NULLIF(btrim(p_request->>'template_code'), ''), '(missing)'),
      v_actor, auth.uid(), v_key, v_hash,
      p_request->'company'->>'company_code', 'running'
    )
    RETURNING id INTO v_run_id;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'order', e.error_order,
        'code', e.check_code,
        'field', e.field_name,
        'detail', e.detail
      ) ORDER BY e.error_order, e.check_code, e.field_name, e.detail
    ),
    '[]'::JSONB
  ) INTO v_errors
  FROM fn_validate_company_provisioning(p_request) e;

  IF jsonb_array_length(v_errors) > 0 THEN
    v_result := jsonb_build_object(
      'status', 'failed',
      'provisioning_run_id', v_run_id,
      'errors', v_errors
    );
    UPDATE company_provisioning_runs
    SET status = 'failed', validation_errors = v_errors,
        result = v_result, error_code = 'validation_failed',
        error_detail = format('%s validation error(s)', jsonb_array_length(v_errors)),
        completed_at = NOW()
    WHERE id = v_run_id;
    RETURN v_result;
  END IF;

  v_company := p_request->'company';
  v_branch := p_request->'default_branch';
  v_warehouse := p_request->'default_warehouse';
  v_template_version := CASE
    WHEN COALESCE(p_request->>'template_version', '') ~ '^[0-9]+$'
    THEN (p_request->>'template_version')::INTEGER
    ELSE NULL
  END;

  SELECT * INTO STRICT v_template
  FROM company_provisioning_templates t
  WHERE t.template_code = p_request->>'template_code'
    AND t.is_active
    AND (
      (v_template_version IS NULL AND t.is_current)
      OR t.template_version = v_template_version
    )
  ORDER BY t.is_current DESC, t.template_version DESC
  LIMIT 1;

  UPDATE company_provisioning_runs
  SET template_id = v_template.id,
      template_version = v_template.template_version
  WHERE id = v_run_id;

  BEGIN
    INSERT INTO companies (
      company_code, parent_company_id, entity_type, registered_name, trade_name,
      line_of_business, psic_code, tin, tax_registration, rdo_id,
      registration_number, bir_reg_date, sec_dti_reg_date, lgu_reg_date,
      accounting_period, fiscal_start_month, cas_permit_no, cas_date_issued,
      address_line_1, address_line_2, city, province, zip_code, email,
      phone_number, mobile_number, signatory_name, signatory_position,
      signatory_tin, workspace_accent_color,
      functional_currency_code, reporting_currency_code,
      created_by, updated_by
    ) VALUES (
      v_company->>'company_code', fn_mdp08_try_uuid(v_company->>'parent_company_id'),
      v_company->>'entity_type', v_company->>'registered_name', NULLIF(v_company->>'trade_name', ''),
      v_company->>'line_of_business', NULLIF(v_company->>'psic_code', ''),
      v_company->>'tin', v_company->>'tax_registration', fn_mdp08_try_uuid(v_company->>'rdo_id'),
      NULLIF(v_company->>'registration_number', ''), fn_mdp08_try_date(v_company->>'bir_reg_date'),
      fn_mdp08_try_date(v_company->>'sec_dti_reg_date'), fn_mdp08_try_date(v_company->>'lgu_reg_date'),
      v_company->>'accounting_period',
      CASE WHEN v_company->>'accounting_period' = 'fiscal' THEN (v_company->>'fiscal_start_month')::INTEGER ELSE NULL END,
      NULLIF(v_company->>'cas_permit_no', ''), fn_mdp08_try_date(v_company->>'cas_date_issued'),
      v_company->>'address_line_1', v_company->>'address_line_2', v_company->>'city',
      v_company->>'province', v_company->>'zip_code', v_company->>'email',
      NULLIF(v_company->>'phone_number', ''), NULLIF(v_company->>'mobile_number', ''),
      v_company->>'signatory_name', v_company->>'signatory_position',
      NULLIF(v_company->>'signatory_tin', ''),
      COALESCE(NULLIF(v_company->>'workspace_accent_color', ''), '#14532D'),
      COALESCE(NULLIF(v_company->>'functional_currency_code', ''), v_template.default_functional_currency_code),
      COALESCE(NULLIF(v_company->>'reporting_currency_code', ''), v_template.default_reporting_currency_code),
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_company_id;

    -- The existing creator-owner trigger establishes authority before any reused
    -- admin-gated provisioning primitive is called.
    IF auth.uid() IS NOT NULL AND NOT can_admin_company(v_company_id) THEN
      RAISE EXCEPTION 'company creator ownership was not established' USING ERRCODE = '42501';
    END IF;

    INSERT INTO branches (
      company_id, branch_code, branch_name, branch_type, tin_branch_code,
      rdo_id, tax_registration_override, bir_reg_date,
      address_line_1, address_line_2, city, province, zip_code,
      email, phone_number, mobile_number, branch_manager,
      created_by, updated_by
    ) VALUES (
      v_company_id, v_branch->>'branch_code', v_branch->>'branch_name',
      v_branch->>'branch_type', v_branch->>'tin_branch_code',
      COALESCE(fn_mdp08_try_uuid(v_branch->>'rdo_id'), fn_mdp08_try_uuid(v_company->>'rdo_id')),
      COALESCE(NULLIF(v_branch->>'tax_registration_override', ''), 'inherit'),
      COALESCE(fn_mdp08_try_date(v_branch->>'bir_reg_date'), fn_mdp08_try_date(v_company->>'bir_reg_date')),
      COALESCE(NULLIF(v_branch->>'address_line_1', ''), v_company->>'address_line_1'),
      COALESCE(NULLIF(v_branch->>'address_line_2', ''), v_company->>'address_line_2'),
      COALESCE(NULLIF(v_branch->>'city', ''), v_company->>'city'),
      COALESCE(NULLIF(v_branch->>'province', ''), v_company->>'province'),
      COALESCE(NULLIF(v_branch->>'zip_code', ''), v_company->>'zip_code'),
      COALESCE(NULLIF(v_branch->>'email', ''), v_company->>'email'),
      COALESCE(NULLIF(v_branch->>'phone_number', ''), NULLIF(v_company->>'phone_number', '')),
      COALESCE(NULLIF(v_branch->>'mobile_number', ''), NULLIF(v_company->>'mobile_number', '')),
      NULLIF(v_branch->>'branch_manager', ''), auth.uid(), auth.uid()
    ) RETURNING id INTO v_branch_id;

    INSERT INTO warehouses (
      company_id, branch_id, warehouse_code, warehouse_name,
      warehouse_type, address, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_warehouse->>'warehouse_code',
      v_warehouse->>'warehouse_name', v_warehouse->>'warehouse_type',
      COALESCE(NULLIF(v_warehouse->>'address', ''),
        concat_ws(', ', v_company->>'address_line_1', v_company->>'address_line_2',
          v_company->>'city', v_company->>'province', v_company->>'zip_code')),
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_warehouse_id;

    FOR v_module IN
      SELECT m.module_code, m.handler_schema, m.handler_function,
             tm.module_config, tm.is_required
      FROM company_provisioning_template_modules tm
      JOIN company_provisioning_modules m ON m.module_code = tm.module_code
      WHERE tm.template_id = v_template.id
        AND tm.is_enabled
        AND m.is_active
      ORDER BY COALESCE(tm.execution_order, m.execution_order), m.module_code
    LOOP
      v_context := jsonb_build_object(
        'company_id', v_company_id,
        'branch_id', v_branch_id,
        'warehouse_id', v_warehouse_id,
        'template_code', v_template.template_code,
        'template_version', v_template.template_version,
        'coa_template_code', v_template.coa_template_code,
        'module_code', v_module.module_code,
        'module_config', v_module.module_config,
        'request', p_request
      );

      EXECUTE format('SELECT %I.%I($1)', v_module.handler_schema, v_module.handler_function)
      INTO v_module_result
      USING v_context;

      IF v_module.is_required AND v_module_result IS NULL THEN
        RAISE EXCEPTION 'required provisioning module % returned no result', v_module.module_code
          USING ERRCODE = '23514';
      END IF;
      v_module_results := v_module_results || jsonb_build_object(v_module.module_code, COALESCE(v_module_result, 'null'::JSONB));
    END LOOP;

    IF (SELECT count(*) FROM fiscal_periods WHERE company_id = v_company_id) <> 12 THEN
      RAISE EXCEPTION 'provisioning did not create exactly 12 fiscal periods' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM number_series WHERE company_id = v_company_id AND branch_id = v_branch_id) THEN
      RAISE EXCEPTION 'provisioning did not create a default number series' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM fn_validate_company_accounting_config(v_company_id)) THEN
      RAISE EXCEPTION 'provisioned accounting configuration is not valid' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM fn_validate_company_inventory_config(v_company_id)) THEN
      RAISE EXCEPTION 'provisioned inventory configuration is not valid' USING ERRCODE = '23514';
    END IF;

    v_result := jsonb_build_object(
      'status', 'succeeded',
      'provisioning_run_id', v_run_id,
      'company_id', v_company_id,
      'company_code', v_company->>'company_code',
      'branch_id', v_branch_id,
      'warehouse_id', v_warehouse_id,
      'template_code', v_template.template_code,
      'template_version', v_template.template_version,
      'module_results', v_module_results,
      'idempotent_replay', false
    );

    UPDATE company_provisioning_runs
    SET company_id = v_company_id, status = 'succeeded',
        module_results = v_module_results, result = v_result,
        completed_at = NOW()
    WHERE id = v_run_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_error_code = RETURNED_SQLSTATE,
      v_error_detail = MESSAGE_TEXT,
      v_error_constraint = CONSTRAINT_NAME;
    v_company_id := NULL;
  END;

  IF v_company_id IS NULL THEN
    v_result := jsonb_build_object(
      'status', 'failed',
      'provisioning_run_id', v_run_id,
      'errors', jsonb_build_array(jsonb_build_object(
        'order', 900,
        'code', COALESCE(v_error_code, 'provisioning_failed'),
        'field', 'provisioning',
        'detail', COALESCE(v_error_detail, 'company provisioning failed'),
        'constraint', NULLIF(v_error_constraint, '')
      ))
    );
    UPDATE company_provisioning_runs
    SET company_id = NULL, status = 'failed',
        module_results = '{}'::JSONB, result = v_result,
        error_code = COALESCE(v_error_code, 'provisioning_failed'),
        error_detail = COALESCE(v_error_detail, 'company provisioning failed'),
        completed_at = NOW()
    WHERE id = v_run_id;
  END IF;

  RETURN v_result;
END;
$$;

-- -- 9. Least privilege ----------------------------------------------------------
REVOKE ALL ON FUNCTION fn_can_provision_company() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_validate_company_provisioning(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_provision_company(JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_mdp08_try_uuid(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_mdp08_try_date(TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_can_provision_company() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_company_provisioning(JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_provision_company(JSONB, TEXT) TO authenticated, service_role;

DO $$
DECLARE v_function TEXT;
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    'fn_mdp08_module_coa',
    'fn_mdp08_module_uom',
    'fn_mdp08_module_percentage_tax',
    'fn_mdp08_module_fiscal_calendar',
    'fn_mdp08_module_number_series',
    'fn_mdp08_module_accounting_config',
    'fn_mdp08_module_compliance',
    'fn_mdp08_module_dimensions',
    'fn_mdp08_module_inventory_config',
    'fn_mdp08_module_payment_modes'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %I(JSONB) FROM PUBLIC, anon, authenticated', v_function);
  END LOOP;
END;
$$;

COMMENT ON TABLE company_provisioning_templates IS
  'MDP-08: versioned, country/localization-aware company templates. Read-only to authenticated users; future editions add rows and module mappings.';
COMMENT ON TABLE company_provisioning_modules IS
  'MDP-08: registry of uniform JSON provisioning handlers. The orchestrator is generic; new optional modules register a handler instead of changing its control flow.';
COMMENT ON TABLE company_provisioning_runs IS
  'MDP-08: audited provisioning execution metadata, deterministic validation/runtime failures, module results, and idempotency state.';
COMMENT ON FUNCTION fn_can_provision_company() IS
  'MDP-08/MDP-03: authorizes new-company creation from the existing companies.create role mapping; permits only the explicit zero-company bootstrap and service role outside mapped roles.';
COMMENT ON FUNCTION fn_validate_company_provisioning(JSONB) IS
  'MDP-08: side-effect-free, server-side validation for template, identity, TIN/code duplicates, fiscal setup, currencies, branch, warehouse, and required module handlers. Errors have deterministic ordering.';
COMMENT ON FUNCTION fn_provision_company(JSONB, TEXT) IS
  'MDP-08: atomic, idempotent company provisioning from a versioned template. Reuses MDP-05/06/07/09/11/13 services and retains only failure execution metadata when business provisioning rolls back.';
