-- =============================================================================
-- MDP-08 - Guided Company Provisioning
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(50);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '', now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111801'::UUID, 'mdp08-owner@test.local'),
  ('11111111-1111-1111-1111-111111111802'::UUID, 'mdp08-member@test.local'),
  ('11111111-1111-1111-1111-111111111803'::UUID, 'mdp08-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user UUID)
RETURNS VOID LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::TEXT, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(UUID) TO authenticated;

CREATE FUNCTION pg_temp.request(
  p_company_code TEXT,
  p_tin TEXT,
  p_template_code TEXT DEFAULT 'PH_STANDARD'
)
RETURNS JSONB LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'template_code', p_template_code,
    'company', jsonb_build_object(
      'company_code', p_company_code,
      'entity_type', 'corporation',
      'registered_name', p_company_code || ' Provisioned Corporation',
      'trade_name', p_company_code || ' Trading',
      'line_of_business', 'Software Services',
      'psic_code', '62010',
      'tin', p_tin,
      'tax_registration', 'vat',
      'accounting_period', 'calendar',
      'address_line_1', 'Unit 8',
      'address_line_2', 'Provisioning Building',
      'city', 'Makati',
      'province', 'Metro Manila',
      'zip_code', '1200',
      'email', lower(p_company_code) || '@test.local',
      'signatory_name', 'MDP08 Owner',
      'signatory_position', 'President',
      'workspace_accent_color', '#14532D',
      'functional_currency_code', 'PHP',
      'reporting_currency_code', 'PHP'
    ),
    'fiscal_year', jsonb_build_object(
      'start_date', '2026-01-01', 'year_name', 'FY2026'
    ),
    'default_branch', jsonb_build_object(
      'branch_code', 'HO', 'branch_name', 'Head Office',
      'branch_type', 'head_office', 'tin_branch_code', '00000'
    ),
    'default_warehouse', jsonb_build_object(
      'warehouse_code', 'MAIN', 'warehouse_name', 'Main Warehouse',
      'warehouse_type', 'main'
    )
  );
$$;
GRANT EXECUTE ON FUNCTION pg_temp.request(TEXT, TEXT, TEXT) TO authenticated;

-- A transaction-local extension module proves generic module dispatch and
-- rollback without adding a production test hook.
CREATE FUNCTION public.fn_mdp08_test_failure(p_context JSONB)
RETURNS JSONB LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'intentional extension-module failure';
END;
$$;

INSERT INTO company_provisioning_modules (
  module_code, module_name, handler_schema, handler_function,
  execution_order, is_active, notes
) VALUES (
  'test_failure', 'Rollback Test Module', 'public',
  'fn_mdp08_test_failure', 999, true, 'Transaction-local pgTAP extension module.'
);

INSERT INTO company_provisioning_templates (
  template_code, template_version, template_name, country_code,
  localization_code, coa_template_code,
  default_functional_currency_code, default_reporting_currency_code,
  template_config
)
SELECT 'PH_TEST_FAILURE', 1, 'Philippine Rollback Test', country_code,
       localization_code, coa_template_code,
       default_functional_currency_code, default_reporting_currency_code,
       template_config
FROM company_provisioning_templates
WHERE template_code = 'PH_STANDARD' AND is_current;

INSERT INTO company_provisioning_template_modules (
  template_id, module_code, execution_order, is_required, is_enabled, module_config
)
SELECT fail.id, tm.module_code, tm.execution_order, tm.is_required,
       tm.is_enabled, tm.module_config
FROM company_provisioning_templates fail
JOIN company_provisioning_templates standard
  ON standard.template_code = 'PH_STANDARD' AND standard.is_current
JOIN company_provisioning_template_modules tm ON tm.template_id = standard.id
WHERE fail.template_code = 'PH_TEST_FAILURE' AND fail.is_current;

INSERT INTO company_provisioning_template_modules (
  template_id, module_code, execution_order, is_required, is_enabled, module_config
)
SELECT id, 'test_failure', 999, true, true, '{}'::JSONB
FROM company_provisioning_templates
WHERE template_code = 'PH_TEST_FAILURE' AND is_current;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111801');

SELECT ok(
  EXISTS (
    SELECT 1 FROM company_provisioning_templates
    WHERE template_code = 'PH_STANDARD'
      AND template_name = 'Philippine Standard'
      AND country_code = 'PH' AND is_current AND is_active
  ),
  'authenticated users can discover the active Philippine Standard template');

SELECT is(
  (SELECT count(*)::INTEGER
   FROM company_provisioning_template_modules tm
   JOIN company_provisioning_templates t ON t.id = tm.template_id
   WHERE t.template_code = 'PH_STANDARD' AND t.is_current
     AND tm.is_required AND tm.is_enabled),
  10,
  'Philippine Standard composes ten required reusable provisioning modules');

SELECT ok(fn_can_provision_company(),
  'the first authenticated user can use the explicit zero-company bootstrap');

INSERT INTO companies (
  company_code, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, address_line_1, address_line_2,
  city, province, zip_code, email, signatory_name, signatory_position,
  created_by, updated_by
) VALUES (
  'ANCHOR', 'corporation', 'MDP08 Anchor Corporation', 'Software Services',
  '908-000-001-00000', 'vat', 'calendar', 'Unit 1', 'Anchor Building',
  'Makati', 'Metro Manila', '1200', 'anchor@test.local',
  'Anchor Owner', 'President', auth.uid(), auth.uid()
);

SELECT is(
  (SELECT role FROM user_company_memberships
   WHERE user_id = auth.uid()
     AND company_id = (SELECT id FROM companies WHERE company_code = 'ANCHOR')),
  'owner',
  'the existing creator trigger makes the bootstrap company creator its owner');

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
SELECT '11111111-1111-1111-1111-111111111802', id, 'member', auth.uid()
FROM companies WHERE company_code = 'ANCHOR';

SELECT ok(fn_can_provision_company(),
  'an owner remains authorized through the MDP-03 companies.create role mapping');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111802');
SELECT ok(NOT fn_can_provision_company(),
  'a member without companies.create is not authorized to provision companies');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111803');
SELECT ok(NOT fn_can_provision_company(),
  'a user with no membership is not authorized to provision companies');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111801');

SELECT is(
  (SELECT count(*)::INTEGER FROM fn_validate_company_provisioning(
    pg_temp.request('GUIDED01', '908-000-002-00000'))),
  0,
  'a complete Philippine Standard request passes server validation');

SELECT is(
  fn_provision_company(
    pg_temp.request('GUIDED01', '908-000-002-00000'),
    'mdp08-success-001')->>'status',
  'succeeded',
  'one RPC provisions the complete company successfully');

SELECT is(
  (SELECT count(*)::INTEGER FROM companies WHERE company_code = 'GUIDED01'),
  1,
  'successful provisioning creates exactly one company');

SELECT is(
  (SELECT role FROM user_company_memberships
   WHERE user_id = auth.uid()
     AND company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  'owner',
  'the provisioner owns the new company before setup modules execute');

SELECT results_eq(
  $$SELECT functional_currency_code, reporting_currency_code
    FROM companies WHERE company_code = 'GUIDED01'$$,
  $$VALUES ('PHP'::TEXT, 'PHP'::TEXT)$$,
  'functional and reporting currency selections are persisted');

SELECT results_eq(
  $$SELECT branch_code, branch_name, branch_type, address_line_1
    FROM branches
    WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')$$,
  $$VALUES ('HO'::TEXT, 'Head Office'::TEXT, 'head_office'::TEXT, 'Unit 8'::TEXT)$$,
  'default branch is created and explicitly inherits the company address');

SELECT results_eq(
  $$SELECT w.warehouse_code, w.warehouse_name, w.warehouse_type, b.branch_code
    FROM warehouses w JOIN branches b ON b.id = w.branch_id
    WHERE w.company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')$$,
  $$VALUES ('MAIN'::TEXT, 'Main Warehouse'::TEXT, 'main'::TEXT, 'HO'::TEXT)$$,
  'default warehouse belongs to the provisioned default branch');

SELECT is(
  (SELECT count(*)::INTEGER FROM chart_of_accounts
   WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  41,
  'the complete Philippine Standard COA is provisioned');

SELECT is(
  (SELECT parent.account_code
   FROM chart_of_accounts child
   JOIN chart_of_accounts parent ON parent.id = child.parent_id
   WHERE child.company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')
     AND child.account_code = '2050'),
  '2000',
  'COA hierarchy is preserved for the customer-advances liability');

SELECT is(
  (SELECT count(*)::INTEGER FROM units_of_measure
   WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  15,
  'standard units of measure are initialized');

SELECT results_eq(
  $$SELECT year_name, start_date, end_date, is_calendar, status
    FROM fiscal_years
    WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')$$,
  $$VALUES ('FY2026'::TEXT, '2026-01-01'::DATE, '2026-12-31'::DATE, true, 'open'::TEXT)$$,
  'the selected fiscal year is created exactly');

SELECT is(
  (SELECT count(*)::INTEGER FROM fiscal_periods
   WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  12,
  'the fiscal calendar contains exactly twelve monthly periods');

SELECT is(
  (SELECT count(*)::INTEGER FROM number_series
   WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  (SELECT count(*)::INTEGER FROM ref_document_types WHERE is_bir_registered),
  'number series are initialized for every governed BIR document type');

SELECT ok(
  (SELECT ar_account_id IS NOT NULL AND ap_account_id IS NOT NULL
      AND default_cash_account_id IS NOT NULL
      AND vat_payable_account_id IS NOT NULL
      AND input_vat_account_id IS NOT NULL
      AND ewt_withheld_account_id IS NOT NULL
      AND ewt_payable_account_id IS NOT NULL
      AND customer_advances_account_id IS NOT NULL
      AND supplier_down_payments_account_id IS NOT NULL
   FROM company_accounting_config
   WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  'all current automated-posting accounts are configured');

SELECT results_eq(
  $$SELECT customer.account_type, supplier.account_type
    FROM company_accounting_config cfg
    JOIN chart_of_accounts customer ON customer.id = cfg.customer_advances_account_id
    JOIN chart_of_accounts supplier ON supplier.id = cfg.supplier_down_payments_account_id
    WHERE cfg.company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')$$,
  $$VALUES ('liability'::TEXT, 'asset'::TEXT)$$,
  'advance settlement mappings use the correct liability and asset account types');

SELECT is(
  (SELECT count(*)::INTEGER FROM fn_validate_company_accounting_config(
    (SELECT id FROM companies WHERE company_code = 'GUIDED01'))),
  0,
  'the completed accounting configuration validates cleanly');

SELECT results_eq(
  $$SELECT vat_registered, percentage_tax_registered, is_active
    FROM compliance_profiles
    WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')$$,
  $$VALUES (true, false, true)$$,
  'compliance defaults match the selected VAT taxpayer classification');

SELECT ok(
  (SELECT count(*) FROM tax_calendar_events
   WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')) > 0,
  'compliance provisioning creates the existing tax-calendar defaults');

SELECT is(
  (SELECT count(*)::INTEGER FROM (
     SELECT id FROM locations
     WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')
     UNION ALL
     SELECT id FROM functional_entities
     WHERE company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')
   ) dimensions),
  2,
  'standard location and functional-entity defaults are initialized');

SELECT is(
  (SELECT w.warehouse_code
   FROM company_inventory_config cfg
   JOIN warehouses w ON w.id = cfg.default_warehouse_id
   WHERE cfg.company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  'MAIN',
  'inventory configuration points to the selected default warehouse');

SELECT is(
  (SELECT pm.code
   FROM company_payment_modes cpm
   JOIN ref_payment_modes pm ON pm.id = cpm.payment_mode_id
   WHERE cpm.company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  'CASH',
  'template-selected standard payment mode is initialized');

SELECT is(
  (SELECT status FROM company_provisioning_runs
   WHERE idempotency_key = 'mdp08-success-001'),
  'succeeded',
  'the audited provisioning run records completion');

SELECT ok(
  EXISTS (SELECT 1 FROM sys_audit_logs
    WHERE table_name = 'companies' AND action = 'INSERT'
      AND company_id = (SELECT id FROM companies WHERE company_code = 'GUIDED01')),
  'company creation flows through the existing audit trigger');

SELECT ok(
  (SELECT count(*) FROM sys_audit_logs
   WHERE table_name = 'company_provisioning_runs'
     AND record_id = (SELECT id FROM company_provisioning_runs
       WHERE idempotency_key = 'mdp08-success-001')) >= 2,
  'run insert and completion are captured by the existing audit framework');

SELECT ok(
  (fn_provision_company(
    pg_temp.request('GUIDED01', '908-000-002-00000'),
    'mdp08-success-001')->>'idempotent_replay')::BOOLEAN,
  'replaying the same key and request returns the prior result');

SELECT is(
  (SELECT count(*)::INTEGER FROM companies WHERE company_code = 'GUIDED01'),
  1,
  'idempotent replay creates no duplicate company');

SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_provisioning(
    pg_temp.request('GUIDED01', '908-000-003-00000'))
    WHERE check_code = 'company_code_duplicate'),
  'server validation detects a duplicate company code');

SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_provisioning(
    pg_temp.request('GUIDED02', '908-000-002-00000'))
    WHERE check_code = 'tin_duplicate'),
  'server validation detects a duplicate TIN');

SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_provisioning(
    jsonb_set(pg_temp.request('GUIDED03', '908-000-003-00000'),
      '{fiscal_year,start_date}', '"2026-02-01"'::JSONB))
    WHERE check_code = 'calendar_year_start_invalid'),
  'server validation rejects an invalid calendar fiscal configuration');

SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_provisioning(
    pg_temp.request('GUIDED04', '908-000-004-00000', 'DOES_NOT_EXIST'))
    WHERE check_code = 'template_invalid'),
  'server validation rejects an invalid template reference');

SELECT results_eq(
  $$SELECT check_code FROM fn_validate_company_provisioning(
      pg_temp.request('GUIDED01', '908-000-002-00000'))
    ORDER BY error_order, check_code$$,
  $$VALUES ('company_code_duplicate'::TEXT), ('tin_duplicate'::TEXT)$$,
  'multiple validation errors are returned in deterministic order');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111802');
SELECT throws_ok(
  $$SELECT fn_provision_company(
      pg_temp.request('DENIED01', '908-000-010-00000'), 'mdp08-denied-member')$$,
  '42501', NULL,
  'a member cannot call the provisioning RPC');

SELECT throws_ok(
  $$INSERT INTO companies (
      company_code, entity_type, registered_name, line_of_business, tin,
      tax_registration, accounting_period, address_line_1, address_line_2,
      city, province, zip_code, email, signatory_name, signatory_position
    ) VALUES (
      'DIRECT01', 'corporation', 'Denied Direct Company', 'Services',
      '908-000-011-00000', 'vat', 'calendar', 'A', 'B', 'Makati',
      'Metro Manila', '1200', 'direct@test.local', 'Owner', 'President')$$,
  '42501', NULL,
  'direct company insertion reuses the same MDP-03 permission decision');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111803');
SELECT throws_ok(
  $$SELECT fn_validate_company_provisioning(
      pg_temp.request('DENIED02', '908-000-012-00000'))$$,
  '42501', NULL,
  'a non-member cannot use validation as an authorization bypass');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111801');
SELECT is(
  fn_provision_company(
    pg_temp.request('ROLLBACK01', '908-000-020-00000', 'PH_TEST_FAILURE'),
    'mdp08-rollback-001')->>'status',
  'failed',
  'a failing registered extension module returns a deterministic failed result');

SELECT is(
  (SELECT count(*)::INTEGER FROM companies WHERE company_code = 'ROLLBACK01'),
  0,
  'a runtime failure rolls back the company row');

SELECT is(
  (SELECT count(*)::INTEGER FROM branches
   WHERE company_id IN (SELECT id FROM companies WHERE company_code = 'ROLLBACK01')),
  0,
  'a runtime failure leaves no partial branch or downstream company setup');

SELECT results_eq(
  $$SELECT status, company_id IS NULL, error_code
    FROM company_provisioning_runs
    WHERE idempotency_key = 'mdp08-rollback-001'$$,
  $$VALUES ('failed'::TEXT, true, 'P0001'::TEXT)$$,
  'failure metadata remains auditable without retaining business rows');

SELECT ok(
  EXISTS (SELECT 1 FROM sys_audit_logs
    WHERE table_name = 'company_provisioning_runs'
      AND record_id = (SELECT id FROM company_provisioning_runs
        WHERE idempotency_key = 'mdp08-rollback-001')
      AND action = 'UPDATE' AND new_data->>'status' = 'failed'),
  'the existing audit log captures provisioning failure completion');

SELECT ok(
  NOT has_function_privilege('authenticated', 'fn_mdp08_module_coa(jsonb)', 'EXECUTE'),
  'internal module adapters are not directly executable by authenticated users');

SELECT ok(
  has_function_privilege('authenticated', 'fn_provision_company(jsonb,text)', 'EXECUTE'),
  'authenticated callers receive only the governed orchestration RPC');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111803');
SELECT is((SELECT count(*)::INTEGER FROM companies), 0,
  'company RLS keeps provisioned companies isolated from an outsider');

SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111801');
SELECT is(
  (SELECT count(*)::INTEGER FROM companies
   WHERE company_code IN ('ANCHOR','GUIDED01')),
  2,
  'the owner sees only the bootstrap and successfully provisioned companies');

SELECT * FROM finish();
ROLLBACK;
