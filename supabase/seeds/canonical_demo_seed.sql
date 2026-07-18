-- =============================================================================
-- PXL canonical demo and QA dataset
-- =============================================================================
--
-- Run after canonical_demo_reset.sql for a full replacement:
--
--   docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
--   SET pxl.allow_demo_reset = 'on';
--   \i supabase/seeds/canonical_demo_reset.sql
--   \i supabase/seeds/canonical_demo_seed.sql
--   SQL
--
-- This file is deterministic and uses stable business codes. It is safest to
-- rerun after the reset script; direct reruns are guarded by natural unique
-- keys and scenario reference checks where practical.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Demo users and seed execution identity.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'demo.admin@pxl.local', crypt('PxlDemo123!', gen_salt('bf')), now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'demo.accountant@pxl.local', crypt('PxlDemo123!', gen_salt('bf')), now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'demo.approver@pxl.local', crypt('PxlDemo123!', gen_salt('bf')), now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'demo.sales@pxl.local', crypt('PxlDemo123!', gen_salt('bf')), now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'demo.warehouse@pxl.local', crypt('PxlDemo123!', gen_salt('bf')), now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}')
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  encrypted_password = EXCLUDED.encrypted_password,
  updated_at = now();

-- GoTrue's local API expects auth token text fields to scan as non-null strings
-- for password login, even though the auth schema permits NULL.
UPDATE auth.users
SET
  confirmation_token = COALESCE(confirmation_token, ''),
  recovery_token = COALESCE(recovery_token, ''),
  email_change_token_new = COALESCE(email_change_token_new, ''),
  email_change = COALESCE(email_change, ''),
  phone_change = COALESCE(phone_change, ''),
  phone_change_token = COALESCE(phone_change_token, ''),
  email_change_token_current = COALESCE(email_change_token_current, ''),
  reauthentication_token = COALESCE(reauthentication_token, ''),
  email_change_confirm_status = COALESCE(email_change_confirm_status, 0),
  updated_at = now()
WHERE id IN (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000005'
);

INSERT INTO auth.identities (
  provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
SELECT
  u.id::text,
  u.id,
  jsonb_build_object(
    'sub', u.id::text,
    'email', u.email,
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  now(),
  now(),
  now()
FROM auth.users u
WHERE u.id IN (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000005'
)
ON CONFLICT (provider_id, provider) DO UPDATE SET
  identity_data = EXCLUDED.identity_data,
  updated_at = now();

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  false
);

-- ---------------------------------------------------------------------------
-- Legal entities, branches, roles, fiscal years, accounting setup.
-- ---------------------------------------------------------------------------
INSERT INTO companies (
  entity_type, registered_name, trade_name, line_of_business, tin,
  tax_registration, accounting_period, fiscal_start_month,
  address_line_1, address_line_2, city, province, zip_code,
  email, phone_number, signatory_name, signatory_position, signatory_tin,
  workspace_accent_color, ap_ewt_recognition_policy, is_active,
  created_by, updated_by
) VALUES
  ('sole_proprietor', 'Golden Retail Store', 'DEMO-SP-NONVAT', 'Neighborhood retail and trading', '900-100-001-00000', 'non_vat', 'calendar', NULL, '101 Mabini Street', 'Barangay Poblacion', 'Makati City', 'Metro Manila', '1210', 'golden.retail@pxl.local', '0280010001', 'Gloria Santos', 'Owner', '900-100-001-00000', '#A16207', 'payment', true, auth.uid(), auth.uid()),
  ('corporation', 'ABC Trading Corporation', 'DEMO-CORP-VAT', 'Wholesale and retail trading', '900-100-002-00000', 'vat', 'calendar', NULL, '12F Meridian Tower', 'Bonifacio Global City', 'Taguig City', 'Metro Manila', '1634', 'accounting@abctrading.pxl.local', '0280010002', 'Andrea Bautista', 'President', '900-100-002-00000', '#14532D', 'accrual_at_source', true, auth.uid(), auth.uid()),
  ('opc', 'Northstar Digital Solutions OPC', 'DEMO-OPC-NONVAT', 'Digital services and project consulting', '900-100-003-00000', 'non_vat', 'calendar', NULL, 'Unit 804 Northstar Hub', 'Ortigas Center', 'Pasig City', 'Metro Manila', '1605', 'finance@northstar.pxl.local', '0280010003', 'Noel Cruz', 'President', '900-100-003-00000', '#1D4ED8', 'payment', true, auth.uid(), auth.uid()),
  ('corporation', 'Prime Business Advisory Inc.', 'DEMO-SVC-VAT', 'Management and tax advisory services', '900-100-004-00000', 'vat', 'calendar', NULL, '25F Prime Center', 'Ayala Avenue', 'Makati City', 'Metro Manila', '1226', 'billing@primeadvisory.pxl.local', '0280010004', 'Patricia Lim', 'Managing Director', '900-100-004-00000', '#7C2D12', 'accrual_at_source', true, auth.uid(), auth.uid()),
  ('partnership', 'Bayani Partners and Company', 'DEMO-PARTNERSHIP-VAT', 'Professional partnership services', '900-100-005-00000', 'vat', 'calendar', NULL, '5F Bayani Building', 'Roxas Boulevard', 'Manila', 'Metro Manila', '1000', 'admin@bayanipartners.pxl.local', '0280010005', 'Benjamin Reyes', 'Managing Partner', '900-100-005-00000', '#6D28D9', 'accrual_at_source', true, auth.uid(), auth.uid())
ON CONFLICT (tin) DO UPDATE SET
  registered_name = EXCLUDED.registered_name,
  trade_name = EXCLUDED.trade_name,
  tax_registration = EXCLUDED.tax_registration,
  line_of_business = EXCLUDED.line_of_business,
  workspace_accent_color = EXCLUDED.workspace_accent_color,
  ap_ewt_recognition_policy = EXCLUDED.ap_ewt_recognition_policy,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
SELECT u.user_id, c.id, u.role, auth.uid()
FROM companies c
CROSS JOIN (VALUES
  ('10000000-0000-0000-0000-000000000001'::uuid, 'owner'),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'admin'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'admin'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'member'),
  ('10000000-0000-0000-0000-000000000005'::uuid, 'member')
) AS u(user_id, role)
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (user_id, company_id) DO UPDATE SET role = EXCLUDED.role, granted_by = auth.uid();

INSERT INTO branches (
  company_id, branch_code, branch_name, branch_type, tin_branch_code,
  address_line_1, address_line_2, city, province, zip_code,
  email, phone_number, branch_manager, is_active, created_by, updated_by
)
SELECT c.id, x.branch_code, x.branch_name, x.branch_type, x.tin_branch_code,
       x.address1, x.address2, x.city, x.province, x.zip_code,
       x.email, x.phone, x.manager, true, auth.uid(), auth.uid()
FROM (VALUES
  ('DEMO-SP-NONVAT','HO','Golden Retail Main','head_office','00000','101 Mabini Street','Barangay Poblacion','Makati City','Metro Manila','1210','golden.main@pxl.local','0281010001','Gloria Santos'),
  ('DEMO-SP-NONVAT','BR01','Golden Retail East Branch','branch','00001','88 JP Rizal Avenue','Barangay Olympia','Makati City','Metro Manila','1207','golden.east@pxl.local','0281010002','Mina Lopez'),
  ('DEMO-CORP-VAT','HO','ABC Head Office','head_office','00000','12F Meridian Tower','BGC','Taguig City','Metro Manila','1634','abc.ho@pxl.local','0281020001','Andrea Bautista'),
  ('DEMO-CORP-VAT','CEBU','ABC Cebu Branch','branch','00001','Cebu Business Park','Luz','Cebu City','Cebu','6000','abc.cebu@pxl.local','0328102001','Cesar Uy'),
  ('DEMO-CORP-VAT','DAVAO','ABC Davao Branch','branch','00002','JP Laurel Avenue','Bajada','Davao City','Davao del Sur','8000','abc.davao@pxl.local','0828102001','Diana Santos'),
  ('DEMO-OPC-NONVAT','HO','Northstar Head Office','head_office','00000','Unit 804 Northstar Hub','Ortigas Center','Pasig City','Metro Manila','1605','northstar.ho@pxl.local','0281030001','Noel Cruz'),
  ('DEMO-SVC-VAT','HO','Prime Head Office','head_office','00000','25F Prime Center','Ayala Avenue','Makati City','Metro Manila','1226','prime.ho@pxl.local','0281040001','Patricia Lim'),
  ('DEMO-PARTNERSHIP-VAT','HO','Bayani Main Office','head_office','00000','5F Bayani Building','Roxas Boulevard','Manila','Metro Manila','1000','bayani.ho@pxl.local','0281050001','Benjamin Reyes')
) AS x(company_code, branch_code, branch_name, branch_type, tin_branch_code, address1, address2, city, province, zip_code, email, phone, manager)
JOIN companies c ON c.trade_name = x.company_code
ON CONFLICT (company_id, branch_code) DO UPDATE SET
  branch_name = EXCLUDED.branch_name,
  branch_type = EXCLUDED.branch_type,
  tin_branch_code = EXCLUDED.tin_branch_code,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO departments (company_id, branch_id, department_code, department_name, department_head_name, description, is_active, created_by, updated_by)
SELECT c.id, b.id, x.department_code, x.department_name, x.head_name, 'Canonical demo department', true, auth.uid(), auth.uid()
FROM (VALUES
  ('DEMO-SP-NONVAT','HO','OPS','Retail Operations','Gloria Santos'),
  ('DEMO-SP-NONVAT','HO','FIN','Finance','Mina Lopez'),
  ('DEMO-CORP-VAT','HO','FIN','Finance','Alicia Gomez'),
  ('DEMO-CORP-VAT','HO','SALES','Sales','Sofia Reyes'),
  ('DEMO-CORP-VAT','HO','PROC','Procurement','Paolo Garcia'),
  ('DEMO-CORP-VAT','HO','WH','Warehouse','Ramil Torres'),
  ('DEMO-CORP-VAT','HO','ADMIN','Administration','Cora Mendoza'),
  ('DEMO-OPC-NONVAT','HO','DELIVERY','Project Delivery','Noel Cruz'),
  ('DEMO-OPC-NONVAT','HO','FIN','Finance','Nina Aquino'),
  ('DEMO-SVC-VAT','HO','ADVISORY','Advisory Services','Patricia Lim'),
  ('DEMO-SVC-VAT','HO','FIN','Finance','Paula Ramos'),
  ('DEMO-PARTNERSHIP-VAT','HO','PROF','Professional Services','Benjamin Reyes'),
  ('DEMO-PARTNERSHIP-VAT','HO','FIN','Finance','Bianca Cruz')
) AS x(company_code, branch_code, department_code, department_name, head_name)
JOIN companies c ON c.trade_name = x.company_code
JOIN branches b ON b.company_id = c.id AND b.branch_code = x.branch_code
ON CONFLICT (company_id, department_code) DO UPDATE SET
  department_name = EXCLUDED.department_name,
  department_head_name = EXCLUDED.department_head_name,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO cost_centers (company_id, branch_id, department_id, cost_center_code, cost_center_name, cost_center_type, valid_from, description, is_active, created_by, updated_by)
SELECT c.id, b.id, d.id, x.cost_center_code, x.cost_center_name, 'cost_center', DATE '2026-01-01', 'Canonical demo cost center', true, auth.uid(), auth.uid()
FROM (VALUES
  ('DEMO-SP-NONVAT','HO','OPS','CC-RETAIL','Retail Store Operations'),
  ('DEMO-SP-NONVAT','HO','FIN','CC-GA','General and Administrative'),
  ('DEMO-CORP-VAT','HO','FIN','CC-FIN','Finance Shared Services'),
  ('DEMO-CORP-VAT','HO','SALES','CC-SALES-MNL','Metro Manila Sales'),
  ('DEMO-CORP-VAT','CEBU','SALES','CC-SALES-VIS','Visayas Sales'),
  ('DEMO-CORP-VAT','DAVAO','SALES','CC-SALES-MIN','Mindanao Sales'),
  ('DEMO-CORP-VAT','HO','WH','CC-WH','Warehouse Operations'),
  ('DEMO-OPC-NONVAT','HO','DELIVERY','CC-PROJECTS','Client Projects'),
  ('DEMO-SVC-VAT','HO','ADVISORY','CC-ADVISORY','Advisory Engagements'),
  ('DEMO-PARTNERSHIP-VAT','HO','PROF','CC-PROF','Professional Services')
) AS x(company_code, branch_code, department_code, cost_center_code, cost_center_name)
JOIN companies c ON c.trade_name = x.company_code
JOIN branches b ON b.company_id = c.id AND b.branch_code = x.branch_code
JOIN departments d ON d.company_id = c.id AND d.department_code = x.department_code
ON CONFLICT (company_id, cost_center_code) DO UPDATE SET
  cost_center_name = EXCLUDED.cost_center_name,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO fiscal_years (company_id, year_name, start_date, end_date, is_calendar, status, retained_earnings_id, created_by, updated_by)
SELECT c.id, 'FY2026', DATE '2026-01-01', DATE '2026-12-31', true, 'open',
       NULL, auth.uid(), auth.uid()
FROM companies c
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, year_name) DO NOTHING;

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name, start_date, end_date, is_locked)
SELECT fy.company_id, fy.id, m,
       to_char(make_date(2026, m, 1), 'FMMonth YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM fiscal_years fy
CROSS JOIN generate_series(1, 12) AS m
JOIN companies c ON c.id = fy.company_id
WHERE fy.year_name = 'FY2026'
  AND c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (fiscal_year_id, period_number) DO UPDATE SET is_locked = false;

INSERT INTO chart_of_accounts (company_id, account_code, account_name, account_type, normal_balance, is_postable, is_active, created_by, updated_by)
SELECT c.id, x.account_code, x.account_name, x.account_type, x.normal_balance, x.is_postable, true, auth.uid(), auth.uid()
FROM companies c
CROSS JOIN (VALUES
  ('1000','Cash and Cash Equivalents','asset','debit',false),
  ('1010','Cash on Hand','asset','debit',true),
  ('1020','Petty Cash Fund','asset','debit',true),
  ('1030','Cash in Bank - Operating','asset','debit',true),
  ('1100','Accounts Receivable - Trade','asset','debit',true),
  ('1110','Allowance for Doubtful Accounts','asset','credit',true),
  ('1200','Inventory','asset','debit',true),
  ('1210','Inventory in Transit','asset','debit',true),
  ('1300','Input VAT','asset','debit',true),
  ('1310','Creditable Withholding Tax Receivable','asset','debit',true),
  ('1320','Prepaid Expenses','asset','debit',true),
  ('1330','Advances to Suppliers','asset','debit',true),
  ('1500','Property and Equipment','asset','debit',true),
  ('1590','Accumulated Depreciation','asset','credit',true),
  ('2000','Accounts Payable - Trade','liability','credit',true),
  ('2100','Output VAT Payable','liability','credit',true),
  ('2110','Expanded Withholding Tax Payable','liability','credit',true),
  ('2120','Percentage Tax Payable','liability','credit',true),
  ('2200','Accrued Expenses','liability','credit',true),
  ('2300','Loans Payable','liability','credit',true),
  ('3000','Owner Capital / Share Capital','equity','credit',true),
  ('3100','Additional Paid-in Capital','equity','credit',true),
  ('3200','Retained Earnings','equity','credit',true),
  ('3300','Owner Drawings / Dividends','equity','debit',true),
  ('4000','Sales Revenue - Goods','revenue','credit',true),
  ('4010','Sales Revenue - Services','revenue','credit',true),
  ('4020','Delivery Income','revenue','credit',true),
  ('4100','Sales Returns and Allowances','revenue','debit',true),
  ('4110','Sales Discounts','revenue','debit',true),
  ('4200','Other Income','revenue','credit',true),
  ('5000','Cost of Goods Sold','expense','debit',true),
  ('5010','Purchases / Inventory Clearing','expense','debit',true),
  ('5020','Inventory Variance','expense','debit',true),
  ('6000','Salaries and Wages','expense','debit',true),
  ('6010','Rent Expense','expense','debit',true),
  ('6020','Utilities Expense','expense','debit',true),
  ('6030','Professional Fees','expense','debit',true),
  ('6040','Transportation Expense','expense','debit',true),
  ('6050','Office Supplies Expense','expense','debit',true),
  ('6060','Depreciation Expense','expense','debit',true),
  ('6070','Bank Charges','expense','debit',true),
  ('6080','Miscellaneous Expense','expense','debit',true)
) AS x(account_code, account_name, account_type, normal_balance, is_postable)
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, account_code) DO UPDATE SET
  account_name = EXCLUDED.account_name,
  account_type = EXCLUDED.account_type,
  normal_balance = EXCLUDED.normal_balance,
  is_postable = EXCLUDED.is_postable,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

UPDATE chart_of_accounts child
SET parent_id = parent.id
FROM chart_of_accounts parent
JOIN companies c ON c.id = parent.company_id
WHERE child.company_id = parent.company_id
  AND parent.account_code = '1000'
  AND child.account_code IN ('1010','1020','1030')
  AND c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT');

UPDATE fiscal_years fy
SET retained_earnings_id = coa.id
FROM companies c
JOIN chart_of_accounts coa ON coa.company_id = c.id AND coa.account_code = '3200'
WHERE fy.company_id = c.id
  AND fy.year_name = 'FY2026'
  AND c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT');

INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id, default_cash_account_id,
  vat_payable_account_id, input_vat_account_id,
  ewt_withheld_account_id, ewt_payable_account_id,
  supplier_down_payments_account_id, created_by, updated_by
)
SELECT c.id,
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1100'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '2000'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1030'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '2100'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1300'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1310'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '2110'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1330'),
  auth.uid(), auth.uid()
FROM companies c
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id) DO UPDATE SET
  ar_account_id = EXCLUDED.ar_account_id,
  ap_account_id = EXCLUDED.ap_account_id,
  default_cash_account_id = EXCLUDED.default_cash_account_id,
  vat_payable_account_id = EXCLUDED.vat_payable_account_id,
  input_vat_account_id = EXCLUDED.input_vat_account_id,
  ewt_withheld_account_id = EXCLUDED.ewt_withheld_account_id,
  ewt_payable_account_id = EXCLUDED.ewt_payable_account_id,
  supplier_down_payments_account_id = EXCLUDED.supplier_down_payments_account_id,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO compliance_profiles (
  company_id, vat_registered, vat_effective_date, vat_filing_frequency,
  vat_threshold_monitoring, percentage_tax_registered, percentage_tax_rate,
  pt_effective_date, pt_filing_frequency,
  ewt_registered, is_twa, twa_effective_date, twa_auto_ewt_enabled,
  files_0619e, qap_required, requires_1604e,
  income_tax_regime, corporate_tax_rate, mcit_applicable, nolco_applicable,
  sawt_required, slsp_required, relief_required, dat_file_required,
  is_active, created_by, updated_by
)
SELECT c.id,
  c.tax_registration = 'vat',
  CASE WHEN c.tax_registration = 'vat' THEN DATE '2026-01-01' END,
  CASE WHEN c.tax_registration = 'vat' THEN 'quarterly' END,
  c.tax_registration = 'vat',
  c.tax_registration = 'non_vat',
  CASE WHEN c.tax_registration = 'non_vat' THEN 3.00 END,
  CASE WHEN c.tax_registration = 'non_vat' THEN DATE '2026-01-01' END,
  CASE WHEN c.tax_registration = 'non_vat' THEN 'quarterly' END,
  c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT'),
  c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT'),
  CASE WHEN c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT') THEN DATE '2026-01-01' END,
  c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT'),
  c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT'),
  c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT'),
  c.trade_name IN ('DEMO-CORP-VAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT'),
  'rcit', CASE WHEN c.entity_type = 'sole_proprietor' THEN 8.00 ELSE 25.00 END,
  c.entity_type <> 'sole_proprietor', true,
  c.tax_registration = 'vat',
  c.tax_registration = 'vat',
  c.tax_registration = 'vat',
  c.tax_registration = 'vat',
  true, auth.uid(), auth.uid()
FROM companies c
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id) DO UPDATE SET
  vat_registered = EXCLUDED.vat_registered,
  percentage_tax_registered = EXCLUDED.percentage_tax_registered,
  ewt_registered = EXCLUDED.ewt_registered,
  is_twa = EXCLUDED.is_twa,
  twa_auto_ewt_enabled = EXCLUDED.twa_auto_ewt_enabled,
  qap_required = EXCLUDED.qap_required,
  sawt_required = EXCLUDED.sawt_required,
  slsp_required = EXCLUDED.slsp_required,
  relief_required = EXCLUDED.relief_required,
  dat_file_required = EXCLUDED.dat_file_required,
  updated_by = auth.uid(),
  updated_at = now();

-- ---------------------------------------------------------------------------
-- Core masters: terms, users/employees, banks, UOMs, categories, items.
-- ---------------------------------------------------------------------------
INSERT INTO payment_terms (company_id, term_code, term_name, days_to_due, require_downpayment, is_active, created_by, updated_by)
SELECT c.id, x.term_code, x.term_name, x.days_to_due, false, true, auth.uid(), auth.uid()
FROM companies c
CROSS JOIN (VALUES
  ('COD','Cash on Delivery',0),
  ('NET7','Net 7 Days',7),
  ('NET15','Net 15 Days',15),
  ('NET30','Net 30 Days',30),
  ('NET45','Net 45 Days',45)
) AS x(term_code, term_name, days_to_due)
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, term_code) DO UPDATE SET term_name = EXCLUDED.term_name, days_to_due = EXCLUDED.days_to_due, is_active = true;

INSERT INTO units_of_measure (company_id, uom_code, description, is_base_unit, is_active, created_by, updated_by)
SELECT c.id, x.uom_code, x.description, true, true, auth.uid(), auth.uid()
FROM companies c
CROSS JOIN (VALUES
  ('PC','Piece'),
  ('REAM','Ream'),
  ('ROLL','Roll'),
  ('CASE','Case'),
  ('BOX','Box'),
  ('HR','Hour'),
  ('JOB','Job'),
  ('UNIT','Unit')
) AS x(uom_code, description)
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, uom_code) DO UPDATE SET description = EXCLUDED.description, is_active = true;

INSERT INTO item_categories (company_id, category_code, category_name, description, sales_account_id, cogs_account_id, inventory_account_id, adj_account_id, is_active, created_by, updated_by)
SELECT c.id, x.category_code, x.category_name, 'Canonical demo category',
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.sales_account),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.cogs_account),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.inventory_account),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '5020'),
  true, auth.uid(), auth.uid()
FROM companies c
CROSS JOIN (VALUES
  ('MERCH','Retail Merchandise','4000','5000','1200'),
  ('OFFICE','Office Supplies','4000','5000','1200'),
  ('FNB','Food and Beverage','4000','5000','1200'),
  ('SERVICE','Services','4010',NULL,NULL),
  ('NONSTOCK','Non-stock Supplies',NULL,NULL,NULL)
) AS x(category_code, category_name, sales_account, cogs_account, inventory_account)
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, category_code) DO UPDATE SET category_name = EXCLUDED.category_name, is_active = true;

INSERT INTO items (
  company_id, item_code, description, description_long, item_type,
  category_id, uom_id, standard_selling_price, standard_cost,
  price_is_vat_inclusive, default_sales_vat_id, default_purchase_vat_id,
  sales_account_id, cogs_account_id, inventory_account_id, purchase_expense_account_id,
  costing_method, min_stock_level, reorder_point, is_active, created_by, updated_by
)
SELECT c.id, x.item_code, x.description, x.description || ' - canonical demo', x.item_type,
  (SELECT id FROM item_categories WHERE company_id = c.id AND category_code = x.category_code),
  (SELECT id FROM units_of_measure WHERE company_id = c.id AND uom_code = x.uom_code),
  x.sell_price, x.cost,
  x.price_inclusive,
  (SELECT id FROM vat_codes WHERE vat_code = CASE WHEN c.tax_registration = 'vat' AND x.item_type <> 'non_inventory' THEN 'VAT-12' ELSE 'VAT-EXEMPT' END),
  (SELECT id FROM vat_codes WHERE vat_code = CASE WHEN c.tax_registration = 'vat' AND x.cost > 0 THEN 'IVAT-12' ELSE 'IVAT-EXEMPT' END),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.sales_account),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.cogs_account),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.inventory_account),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = COALESCE(x.expense_account, '6050')),
  CASE WHEN x.item_type = 'inventory_item' THEN 'weighted_average' END,
  x.min_stock, x.reorder_point, true, auth.uid(), auth.uid()
FROM companies c
JOIN (VALUES
  ('ITEM-STOCK-001','Bond Paper A4','inventory_item','OFFICE','REAM',280.00,200.00,false,'4000','5000','1200',NULL,20,40),
  ('ITEM-STOCK-002','Printer Ink','inventory_item','OFFICE','PC',1250.00,850.00,false,'4000','5000','1200',NULL,10,20),
  ('ITEM-STOCK-003','Packaging Tape','inventory_item','OFFICE','ROLL',85.00,45.00,false,'4000','5000','1200',NULL,20,40),
  ('ITEM-STOCK-004','Instant Coffee','inventory_item','FNB','CASE',480.00,320.00,false,'4000','5000','1200',NULL,10,20),
  ('ITEM-STOCK-005','Office Chair','inventory_item','MERCH','PC',2800.00,1800.00,false,'4000','5000','1200',NULL,5,10),
  ('ITEM-STOCK-006','USB Drive','inventory_item','MERCH','PC',450.00,260.00,false,'4000','5000','1200',NULL,15,30),
  ('ITEM-STOCK-007','Cleaning Supplies','inventory_item','MERCH','BOX',650.00,390.00,false,'4000','5000','1200',NULL,10,20),
  ('ITEM-STOCK-008','Retail Merchandise A','inventory_item','MERCH','PC',350.00,210.00,false,'4000','5000','1200',NULL,20,50),
  ('ITEM-STOCK-009','Retail Merchandise B','inventory_item','MERCH','PC',520.00,310.00,false,'4000','5000','1200',NULL,20,50),
  ('ITEM-SERVICE-001','Consulting Service','service','SERVICE','HR',1500.00,0.00,false,'4010',NULL,NULL,'6030',NULL,NULL),
  ('ITEM-SERVICE-002','Bookkeeping Service','service','SERVICE','JOB',5000.00,0.00,false,'4010',NULL,NULL,'6030',NULL,NULL),
  ('ITEM-SERVICE-003','Registration Service','service','SERVICE','JOB',3500.00,0.00,false,'4010',NULL,NULL,'6030',NULL,NULL),
  ('ITEM-SERVICE-004','Delivery Fee','service','SERVICE','JOB',500.00,0.00,false,'4020',NULL,NULL,'6040',NULL,NULL),
  ('ITEM-SERVICE-005','Installation Service','service','SERVICE','JOB',1200.00,0.00,false,'4010',NULL,NULL,'6030',NULL,NULL),
  ('ITEM-SERVICE-006','Training Service','service','SERVICE','HR',1800.00,0.00,false,'4010',NULL,NULL,'6030',NULL,NULL),
  ('ITEM-NONSTOCK-001','Packaging Materials','non_inventory','NONSTOCK','PC',0.00,25.00,false,NULL,NULL,NULL,'6050',NULL,NULL)
) AS x(item_code, description, item_type, category_code, uom_code, sell_price, cost, price_inclusive, sales_account, cogs_account, inventory_account, expense_account, min_stock, reorder_point)
  ON (
    c.trade_name IN ('DEMO-CORP-VAT','DEMO-SP-NONVAT')
    OR (c.trade_name IN ('DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT') AND x.item_type <> 'inventory_item')
  )
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, item_code) DO UPDATE SET
  description = EXCLUDED.description,
  standard_selling_price = EXCLUDED.standard_selling_price,
  standard_cost = EXCLUDED.standard_cost,
  default_sales_vat_id = EXCLUDED.default_sales_vat_id,
  default_purchase_vat_id = EXCLUDED.default_purchase_vat_id,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO warehouses (company_id, branch_id, warehouse_code, warehouse_name, warehouse_type, address, gl_inventory_account_id, gl_variance_account_id, is_active, created_by, updated_by)
SELECT c.id, b.id, x.warehouse_code, x.warehouse_name, x.warehouse_type,
       b.address_line_1 || ', ' || b.city,
       (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1200'),
       (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '5020'),
       true, auth.uid(), auth.uid()
FROM (VALUES
  ('DEMO-SP-NONVAT','HO','WH-GOLDEN-HO','Golden Main Warehouse','main'),
  ('DEMO-SP-NONVAT','BR01','WH-GOLDEN-EAST','Golden East Warehouse','main'),
  ('DEMO-CORP-VAT','HO','WH-MAIN','ABC Main Warehouse','main'),
  ('DEMO-CORP-VAT','CEBU','WH-CEBU','ABC Cebu Warehouse','main'),
  ('DEMO-CORP-VAT','DAVAO','WH-DAVAO','ABC Davao Warehouse','main')
) AS x(company_code, branch_code, warehouse_code, warehouse_name, warehouse_type)
JOIN companies c ON c.trade_name = x.company_code
JOIN branches b ON b.company_id = c.id AND b.branch_code = x.branch_code
ON CONFLICT (company_id, warehouse_code) DO UPDATE SET
  warehouse_name = EXCLUDED.warehouse_name,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO bank_accounts (company_id, branch_id, bank_name, bank_branch, account_number, account_name, account_type, currency_id, gl_account_id, is_primary, is_active, opening_balance, notes, created_by, updated_by)
SELECT c.id, b.id, x.bank_name, x.bank_branch, x.account_number, c.registered_name, 'checking',
       (SELECT id FROM currencies WHERE currency_code = 'PHP'),
       (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1030'),
       x.is_primary, true, 0, 'Canonical demo bank account', auth.uid(), auth.uid()
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.branch_code = 'HO'
JOIN (VALUES
  ('PXL Demo Bank','Main', 'DEMO-OPERATING-001', true),
  ('PXL Demo Bank','Payroll', 'DEMO-PAYROLL-001', false)
) AS x(bank_name, bank_branch, account_number, is_primary) ON true
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, bank_name, account_number) DO UPDATE SET is_active = true, updated_by = auth.uid(), updated_at = now();

INSERT INTO employees (company_id, branch_id, employee_number, last_name, first_name, department_id, job_title, employment_type, hire_date, email, is_active, notes, created_by, updated_by)
SELECT c.id, b.id, x.employee_number, x.last_name, x.first_name,
       (SELECT id FROM departments WHERE company_id = c.id ORDER BY department_code LIMIT 1),
       x.job_title, 'regular', DATE '2026-01-02', x.email, true, 'Canonical demo responsible user', auth.uid(), auth.uid()
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.branch_code = 'HO'
CROSS JOIN (VALUES
  ('EMP-ADMIN','Admin','Demo','Administrator','demo.admin@pxl.local'),
  ('EMP-ACCT','Accountant','Demo','Accountant','demo.accountant@pxl.local'),
  ('EMP-APPROVER','Approver','Demo','Approver','demo.approver@pxl.local'),
  ('EMP-SALES','Sales','Demo','Salesperson','demo.sales@pxl.local'),
  ('EMP-WH','Warehouse','Demo','Warehouse Custodian','demo.warehouse@pxl.local')
) AS x(employee_number, last_name, first_name, job_title, email)
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, employee_number) DO UPDATE SET job_title = EXCLUDED.job_title, is_active = true, updated_by = auth.uid(), updated_at = now();

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix, number_length, starting_number, next_number, reset_frequency, allow_manual_override, is_active, created_by, updated_by)
SELECT c.id, b.id, rdt.id, c.trade_name || '-' || b.branch_code || '-' || rdt.document_code || '-', 6, 1, 1, 'never', false, true, auth.uid(), auth.uid()
FROM companies c
JOIN branches b ON b.company_id = c.id
JOIN ref_document_types rdt ON true
WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-OPC-NONVAT','DEMO-SVC-VAT','DEMO-PARTNERSHIP-VAT')
ON CONFLICT (company_id, branch_id, document_type_id) DO UPDATE SET
  prefix = EXCLUDED.prefix,
  number_length = EXCLUDED.number_length,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

-- Customers and suppliers. The primary VAT trading company carries the broad
-- set; service and non-VAT companies carry smaller operational sets.
INSERT INTO customers (
  company_id, customer_code, customer_group, registered_name, trade_name, business_style,
  tin, tin_branch_code, default_tax_type, registered_address, delivery_address,
  contact_person, email, phone_number, default_terms_id, default_currency_id,
  default_gl_account_id, credit_limit, is_subject_to_cwt, default_cwt_atc_code_id,
  is_active, created_by, updated_by
)
SELECT c.id, x.customer_code, x.customer_group, x.registered_name, x.trade_name, x.business_style,
       x.tin, x.branch_code, x.default_tax_type, x.address, x.address,
       x.contact_person, x.email, x.phone,
       (SELECT id FROM payment_terms WHERE company_id = c.id AND term_code = x.term_code),
       (SELECT id FROM currencies WHERE currency_code = 'PHP'),
       (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1100'),
       x.credit_limit, x.is_cwt,
       (SELECT id FROM atc_codes WHERE code = x.atc_code AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1),
       true, auth.uid(), auth.uid()
FROM companies c
JOIN (VALUES
  ('DEMO-CORP-VAT','CUST-VAT-CREDIT','corporate','Luzon Retail Group Inc.','Luzon Retail','VAT registered reseller','901-200-001-00000','00000','vat_registered','18 Commerce Avenue, Quezon City','Lara Reyes','ap@luzonretail.pxl.local','0282010001','NET30',250000,false,NULL),
  ('DEMO-CORP-VAT','CUST-NONVAT-CASH','retail','Mina sari-sari Store','Mina Store','Non-VAT sole proprietor','901-200-002-00000','00000','non_vat','41 Market Road, Pasig City','Mina Dela Cruz','mina.store@pxl.local','0282010002','COD',0,false,NULL),
  ('DEMO-CORP-VAT','CUST-CWT','corporate','Metro Development Corporation','MetroDev','Top withholding customer','901-200-003-00000','00000','vat_registered','7 Corporate Center, Makati City','Marco Tan','payables@metrodev.pxl.local','0282010003','NET30',500000,true,'WC159'),
  ('DEMO-CORP-VAT','CUST-NONCWT','corporate','Blue Ocean Retail Inc.','Blue Ocean','VAT customer','901-200-004-00000','00000','vat_registered','22 Bay Area, Pasay City','Bianca Lee','accounting@blueocean.pxl.local','0282010004','NET15',125000,false,NULL),
  ('DEMO-CORP-VAT','CUST-CASH','cash','Walk-in Cash Customer','Walk-in','Cash customer','901-200-005-00000','00000','non_vat','Store counter sale','Cashier','cash.customer@pxl.local','0282010005','COD',0,false,NULL),
  ('DEMO-CORP-VAT','CUST-OPEN-SO','distribution','VisMin Distribution Corp.','VisMin Distribution','Open SO customer','901-200-006-00000','00000','vat_registered','Cebu Business Park, Cebu City','Vince Ong','orders@vismin.pxl.local','0328201006','NET30',300000,false,NULL),
  ('DEMO-CORP-VAT','CUST-CREDIT-LIMIT','corporate','Credit Limit Test Customer Inc.','Credit Limit Test','Credit control scenario','901-200-007-00000','00000','vat_registered','Ortigas Center, Pasig City','Clara Yu','credit@testcustomer.pxl.local','0282010007','NET15',50000,false,NULL),
  ('DEMO-CORP-VAT','CUST-MULTI-ADDR','corporate','Multi Address Retail Corp.','Multi Address','Multiple delivery address scenario','901-200-008-00000','00000','vat_registered','Head Office, Makati City / Warehouse, Laguna','Marlon Cruz','ap@multiaddr.pxl.local','0282010008','NET30',180000,false,NULL),
  ('DEMO-CORP-VAT','CUST-SERVICE','services','Service Customer Corporation','Service Customer','Service invoice customer','901-200-009-00000','00000','vat_registered','BGC, Taguig City','Sarah Co','ap@servicecustomer.pxl.local','0282010009','NET30',200000,true,'WC159'),
  ('DEMO-CORP-VAT','CUST-INACTIVE','inactive','Inactive Customer Inc.','Inactive','Inactive negative-test customer','901-200-010-00000','00000','vat_registered','Old Address, Manila','Ivan Cruz','inactive@pxl.local','0282010010','NET30',10000,false,NULL),
  ('DEMO-SP-NONVAT','CUST-GOLDEN-CASH','retail','Golden Walk-in Customer','Golden Walk-in','Retail cash','901-201-001-00000','00000','non_vat','Makati City','Cashier','golden.cash@pxl.local','0282020001','COD',0,false,NULL),
  ('DEMO-OPC-NONVAT','CUST-NORTHSTAR-RET','services','Startup Client OPC','Startup Client','Retainer client','901-203-001-00000','00000','non_vat','Pasig City','Stella Lim','ap@startupclient.pxl.local','0282030001','NET30',100000,false,NULL),
  ('DEMO-SVC-VAT','CUST-PRIME-CWT','corporate','Enterprise Withholding Client Inc.','Enterprise Client','Top withholding customer','901-204-001-00000','00000','vat_registered','Makati City','Eddie Yap','ap@enterpriseclient.pxl.local','0282040001','NET30',250000,true,'WC159')
) AS x(company_code, customer_code, customer_group, registered_name, trade_name, business_style, tin, branch_code, default_tax_type, address, contact_person, email, phone, term_code, credit_limit, is_cwt, atc_code)
  ON c.trade_name = x.company_code
ON CONFLICT (company_id, customer_code) DO UPDATE SET
  registered_name = EXCLUDED.registered_name,
  tin = EXCLUDED.tin,
  default_tax_type = EXCLUDED.default_tax_type,
  credit_limit = EXCLUDED.credit_limit,
  is_subject_to_cwt = EXCLUDED.is_subject_to_cwt,
  default_cwt_atc_code_id = EXCLUDED.default_cwt_atc_code_id,
  is_active = CASE WHEN customers.customer_code = 'CUST-INACTIVE' THEN false ELSE true END,
  updated_by = auth.uid(),
  updated_at = now();

UPDATE customers
SET is_active = false, updated_at = now(), updated_by = auth.uid()
WHERE customer_code = 'CUST-INACTIVE'
  AND company_id = (SELECT id FROM companies WHERE trade_name = 'DEMO-CORP-VAT');

INSERT INTO suppliers (
  company_id, supplier_code, supplier_group, registered_name, trade_name, business_style,
  tin, default_tax_type, registered_address, contact_person, email, phone_number,
  default_terms_id, default_currency_id, default_gl_account_id,
  is_subject_to_ewt, default_atc_code_id, is_active, created_by, updated_by
)
SELECT c.id, x.supplier_code, x.supplier_group, x.registered_name, x.trade_name, x.business_style,
       x.tin, x.default_tax_type, x.address, x.contact_person, x.email, x.phone,
       (SELECT id FROM payment_terms WHERE company_id = c.id AND term_code = x.term_code),
       (SELECT id FROM currencies WHERE currency_code = 'PHP'),
       (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = x.default_account),
       x.is_ewt,
       (SELECT id FROM atc_codes WHERE code = x.atc_code AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1),
       true, auth.uid(), auth.uid()
FROM companies c
JOIN (VALUES
  ('DEMO-CORP-VAT','SUP-VAT-INVENTORY','goods','National Office Depot Inc.','National Office Depot','VAT inventory supplier','902-300-001-00000','vat_registered','Quezon City','Nestor Santos','sales@nationaldepot.pxl.local','0283010001','NET30','5010',true,'WC158'),
  ('DEMO-CORP-VAT','SUP-VAT-INCLUSIVE','goods','Inclusive Supply Corporation','Inclusive Supply','VAT-inclusive supplier','902-300-002-00000','vat_registered','Mandaluyong City','Irene Co','billing@inclusive.pxl.local','0283010002','NET15','5010',true,'WC158'),
  ('DEMO-CORP-VAT','SUP-NONVAT','goods','Prime Non-VAT Supply','Prime Non-VAT','Non-VAT supplier','902-300-003-00000','non_vat','Caloocan City','Paolo Reyes','prime.nonvat@pxl.local','0283010003','COD','5010',false,NULL),
  ('DEMO-CORP-VAT','SUP-EWT-SERVICE','services','Metro Computer Solutions Corp.','Metro Computer','Professional service supplier','902-300-004-00000','vat_registered','Eastwood City','Arlene Uy','billing@metrocomputer.pxl.local','0283010004','NET15','6030',true,'WC010'),
  ('DEMO-CORP-VAT','SUP-EWT-RENT','rent','Juan Rental Corporation','Juan Rentals','Office rental supplier','902-300-005-00000','vat_registered','Makati City','Juan Villanueva','leasing@juanrentals.pxl.local','0283010005','NET30','6010',true,'WC130'),
  ('DEMO-CORP-VAT','SUP-LOGISTICS','services','ABC Logistics Services Inc.','ABC Logistics','Freight supplier','902-300-006-00000','vat_registered','Manila Port Area','Dan Cruz','billing@abclogistics.pxl.local','0283010006','NET15','6040',true,'WC140'),
  ('DEMO-CORP-VAT','SUP-UTILITIES','utilities','Meralco Demo Utility','Meralco Demo','Utility supplier','902-300-007-00000','vat_registered','Pasig City','Utility Billing','billing@utility.pxl.local','0283010007','NET15','6020',false,NULL),
  ('DEMO-CORP-VAT','SUP-PROF-INDIV','professional','Ana Professional Services','Ana Professional','Individual professional','902-300-008-00000','non_vat','Makati City','Ana Lopez','ana.prof@pxl.local','0283010008','NET15','6030',true,'WI010'),
  ('DEMO-CORP-VAT','SUP-PACKAGING','goods','Packaging Plus Inc.','Packaging Plus','Packaging supplier','902-300-009-00000','vat_registered','Valenzuela City','Pam Cruz','orders@packagingplus.pxl.local','0283010009','NET30','6050',true,'WC158'),
  ('DEMO-CORP-VAT','SUP-INACTIVE','goods','Inactive Supplier Inc.','Inactive Supplier','Inactive negative-test supplier','902-300-010-00000','vat_registered','Old Manila','Inactive Contact','inactive.supplier@pxl.local','0283010010','NET30','5010',false,NULL),
  ('DEMO-SP-NONVAT','SUP-GOLDEN-GOODS','goods','Golden Goods Supplier','Golden Goods','Retail goods supplier','902-301-001-00000','non_vat','Pasay City','Gina Supplier','golden.supplier@pxl.local','0283020001','COD','5010',false,NULL),
  ('DEMO-OPC-NONVAT','SUP-NORTHSTAR-SVC','services','Northstar Contractor','Northstar Contractor','Contract services','902-303-001-00000','non_vat','Pasig City','Nico Contractor','contractor@northstar.pxl.local','0283030001','NET15','6030',true,'WI010'),
  ('DEMO-SVC-VAT','SUP-PRIME-RENT','rent','Prime Office Lessor Inc.','Prime Lessor','Office rent supplier','902-304-001-00000','vat_registered','Makati City','Liza Rental','billing@primelessor.pxl.local','0283040001','NET30','6010',true,'WC130')
) AS x(company_code, supplier_code, supplier_group, registered_name, trade_name, business_style, tin, default_tax_type, address, contact_person, email, phone, term_code, default_account, is_ewt, atc_code)
  ON c.trade_name = x.company_code
ON CONFLICT (company_id, supplier_code) DO UPDATE SET
  registered_name = EXCLUDED.registered_name,
  tin = EXCLUDED.tin,
  default_tax_type = EXCLUDED.default_tax_type,
  default_gl_account_id = EXCLUDED.default_gl_account_id,
  is_subject_to_ewt = EXCLUDED.is_subject_to_ewt,
  default_atc_code_id = EXCLUDED.default_atc_code_id,
  is_active = CASE WHEN suppliers.supplier_code = 'SUP-INACTIVE' THEN false ELSE true END,
  updated_by = auth.uid(),
  updated_at = now();

UPDATE suppliers
SET is_active = false, updated_at = now(), updated_by = auth.uid()
WHERE supplier_code = 'SUP-INACTIVE'
  AND company_id = (SELECT id FROM companies WHERE trade_name = 'DEMO-CORP-VAT');

-- Simple approval workflows for demo review/SoD exploration.
INSERT INTO approval_workflows (company_id, workflow_name, module_type, document_type, trigger_condition_type, threshold_value, is_active, created_by, updated_by)
SELECT c.id, 'Canonical ' || x.document_type || ' approval', x.module_type, x.document_type, 'amount_exceeds', x.threshold_value, true, auth.uid(), auth.uid()
FROM companies c
CROSS JOIN (VALUES
  ('sales','SI',50000::numeric),
  ('purchasing','VB',50000::numeric)
) AS x(module_type, document_type, threshold_value)
WHERE c.trade_name = 'DEMO-CORP-VAT'
ON CONFLICT (company_id, module_type, document_type, trigger_condition_type, threshold_value) DO UPDATE SET is_active = true, updated_by = auth.uid(), updated_at = now();

INSERT INTO approval_workflow_steps (company_id, workflow_id, step_sequence, approver_type, approver_user_id, action_required)
SELECT aw.company_id, aw.id, 1, 'user', '10000000-0000-0000-0000-000000000003'::uuid, 'approve'
FROM approval_workflows aw
WHERE aw.workflow_name LIKE 'Canonical % approval'
  AND NOT EXISTS (
    SELECT 1 FROM approval_workflow_steps s
    WHERE s.workflow_id = aw.id AND s.step_sequence = 1
  );

-- ---------------------------------------------------------------------------
-- Governed opening inventory, opening GL, and transaction scenarios.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_company UUID;
  v_company_a UUID;
  v_company_c UUID;
  v_company_d UUID;
  v_branch UUID;
  v_branch_a UUID;
  v_branch_c UUID;
  v_branch_d UUID;
  v_wh_main UUID;
  v_wh_cebu UUID;
  v_wh_golden UUID;
  v_item UUID;
  v_item_ink UUID;
  v_item_tape UUID;
  v_service UUID;
  v_vat UUID;
  v_vat_exempt UUID;
  v_ivat UUID;
  v_cwt_atc UUID;
  v_ewt_atc UUID;
  v_cash_mode UUID;
  v_bank_mode UUID;
  v_si UUID;
  v_vb UUID;
  v_or UUID;
  v_pv UUID;
  v_po UUID;
  v_po_line UUID;
  v_rr UUID;
  v_total_inventory NUMERIC := 0;
  v_stock_qty NUMERIC;
BEGIN
  SELECT id INTO v_company FROM companies WHERE trade_name = 'DEMO-CORP-VAT';
  SELECT id INTO v_company_a FROM companies WHERE trade_name = 'DEMO-SP-NONVAT';
  SELECT id INTO v_company_c FROM companies WHERE trade_name = 'DEMO-OPC-NONVAT';
  SELECT id INTO v_company_d FROM companies WHERE trade_name = 'DEMO-SVC-VAT';
  SELECT id INTO v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT id INTO v_branch_a FROM branches WHERE company_id = v_company_a AND branch_code = 'HO';
  SELECT id INTO v_branch_c FROM branches WHERE company_id = v_company_c AND branch_code = 'HO';
  SELECT id INTO v_branch_d FROM branches WHERE company_id = v_company_d AND branch_code = 'HO';
  SELECT id INTO v_wh_main FROM warehouses WHERE company_id = v_company AND warehouse_code = 'WH-MAIN';
  SELECT id INTO v_wh_cebu FROM warehouses WHERE company_id = v_company AND warehouse_code = 'WH-CEBU';
  SELECT id INTO v_wh_golden FROM warehouses WHERE company_id = v_company_a AND warehouse_code = 'WH-GOLDEN-HO';
  SELECT id INTO v_item FROM items WHERE company_id = v_company AND item_code = 'ITEM-STOCK-001';
  SELECT id INTO v_item_ink FROM items WHERE company_id = v_company AND item_code = 'ITEM-STOCK-002';
  SELECT id INTO v_item_tape FROM items WHERE company_id = v_company AND item_code = 'ITEM-STOCK-003';
  SELECT id INTO v_service FROM items WHERE company_id = v_company AND item_code = 'ITEM-SERVICE-001';
  SELECT id INTO v_vat FROM vat_codes WHERE vat_code = 'VAT-12';
  SELECT id INTO v_vat_exempt FROM vat_codes WHERE vat_code = 'VAT-EXEMPT';
  SELECT id INTO v_ivat FROM vat_codes WHERE vat_code = 'IVAT-12';
  SELECT id INTO v_cwt_atc FROM atc_codes WHERE code = 'WC159' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO v_ewt_atc FROM atc_codes WHERE code = 'WC158' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO v_cash_mode FROM ref_payment_modes WHERE code = 'CASH';
  SELECT id INTO v_bank_mode FROM ref_payment_modes WHERE code = 'BANK_XFER';

  -- Opening stock through governed inventory receipt RPCs.
  IF NOT EXISTS (
    SELECT 1 FROM inventory_transactions
    WHERE company_id = v_company AND reference_doc_type = 'DEMO_OPENING'
  ) THEN
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company, 'warehouse_id', v_wh_main, 'item_id', v_item, 'qty', 100, 'unit_cost', 200, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Opening stock: Bond Paper A4'));
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company, 'warehouse_id', v_wh_main, 'item_id', v_item_ink, 'qty', 40, 'unit_cost', 850, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Opening stock: Printer Ink'));
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company, 'warehouse_id', v_wh_main, 'item_id', v_item_tape, 'qty', 60, 'unit_cost', 45, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Opening stock: Packaging Tape'));
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company, 'warehouse_id', v_wh_cebu, 'item_id', v_item, 'qty', 30, 'unit_cost', 200, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Opening branch stock: Bond Paper A4'));
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company, 'warehouse_id', v_wh_cebu, 'item_id', v_item_ink, 'qty', 10, 'unit_cost', 850, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Opening branch stock: Printer Ink'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM inventory_transactions
    WHERE company_id = v_company_a AND reference_doc_type = 'DEMO_OPENING'
  ) THEN
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company_a, 'warehouse_id', v_wh_golden, 'item_id', (SELECT id FROM items WHERE company_id = v_company_a AND item_code = 'ITEM-STOCK-008'), 'qty', 80, 'unit_cost', 210, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Golden opening stock A'));
    PERFORM fn_receive_inventory(jsonb_build_object('company_id', v_company_a, 'warehouse_id', v_wh_golden, 'item_id', (SELECT id FROM items WHERE company_id = v_company_a AND item_code = 'ITEM-STOCK-009'), 'qty', 50, 'unit_cost', 310, 'receipt_date', '2026-01-02', 'reference_doc_type', 'DEMO_OPENING', 'notes', 'Golden opening stock B'));
  END IF;

  SELECT COALESCE(SUM(total_cost), 0) INTO v_total_inventory
  FROM stock_balances
  WHERE company_id = v_company;

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company
      AND reference_doc_type = 'MANUAL'
      AND entry_class = 'opening'
      AND description = 'DEMO-CORP-VAT opening balances'
  ) THEN
    PERFORM fn_post_manual_je(
      v_company, v_branch, DATE '2026-01-02',
      'DEMO-CORP-VAT opening balances',
      'MANUAL', false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1010'), 'description', 'Opening cash on hand', 'debit_amount', 50000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'), 'description', 'Opening bank balance', 'debit_amount', 500000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'), 'description', 'Opening inventory value', 'debit_amount', v_total_inventory, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '3000'), 'description', 'Opening equity', 'debit_amount', 0, 'credit_amount', 550000 + v_total_inventory, 'branch_id', v_branch)
      ),
      'opening'
    );
  END IF;

  -- Sales Invoice: standalone VAT-exclusive service with expected CWT and full OR.
  IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE company_id = v_company AND reference = 'TEST-SI-STANDALONE') THEN
    v_si := fn_save_sales_invoice(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch, 'date', '2026-01-10',
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company AND customer_code = 'CUST-CWT'),
        'customer_name_snapshot', 'Metro Development Corporation',
        'customer_tin_snapshot', '901-200-003-00000',
        'customer_address_snapshot', '7 Corporate Center, Makati City',
        'payment_terms_id', (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = 'NET30'),
        'reference', 'TEST-SI-STANDALONE',
        'memo', 'Standalone VAT-exclusive service invoice with expected CWT',
        'vat_price_basis', 'exclusive',
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'SALES'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-SALES-MNL'),
        'cwt_amount_expected', 40,
        'cwt_atc_code_id', v_cwt_atc,
        'cwt_tax_base', 2000
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service, 'description', 'Consulting Service',
          'quantity', 2, 'unit_price', 1000, 'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);

    v_or := fn_save_receipt(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch,
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company AND customer_code = 'CUST-CWT'),
        'customer_name_snapshot', 'Metro Development Corporation',
        'customer_tin_snapshot', '901-200-003-00000',
        'receipt_date', '2026-01-20',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'TEST-OR-SI-STANDALONE',
        'remarks', 'Full collection with CWT'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'invoice_id', v_si,
          'payment_amount', 2200,
          'cwt_amount', 40,
          'atc_code_id', v_cwt_atc,
          'cwt_tax_base', 2000
        )
      )
    );
    PERFORM fn_post_receipt(v_or);
  END IF;

  -- Sales Invoice: VAT-inclusive service price of 1,120 -> 1,000 net + 120 VAT.
  IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE company_id = v_company AND reference = 'TEST-SI-VAT-INCLUSIVE') THEN
    v_si := fn_save_sales_invoice(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch, 'date', '2026-01-11',
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company AND customer_code = 'CUST-SERVICE'),
        'customer_name_snapshot', 'Service Customer Corporation',
        'customer_tin_snapshot', '901-200-009-00000',
        'customer_address_snapshot', 'BGC, Taguig City',
        'payment_terms_id', (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = 'NET30'),
        'reference', 'TEST-SI-VAT-INCLUSIVE',
        'memo', 'VAT-inclusive price basis scenario',
        'vat_price_basis', 'inclusive'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service, 'description', 'Consulting Service - VAT inclusive',
          'quantity', 1, 'unit_price', 1120, 'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  -- Sales Invoice: inventory issue and COGS.
  IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE company_id = v_company AND reference = 'TEST-SI-INVENTORY') THEN
    v_si := fn_save_sales_invoice(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch, 'date', '2026-01-12',
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company AND customer_code = 'CUST-VAT-CREDIT'),
        'customer_name_snapshot', 'Luzon Retail Group Inc.',
        'customer_tin_snapshot', '901-200-001-00000',
        'customer_address_snapshot', '18 Commerce Avenue, Quezon City',
        'payment_terms_id', (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = 'NET30'),
        'reference', 'TEST-SI-INVENTORY',
        'memo', 'Inventory sale with COGS',
        'vat_price_basis', 'exclusive',
        'warehouse_id', v_wh_main
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item, 'description', 'Bond Paper A4',
          'quantity', 5, 'unit_price', 280, 'vat_code_id', v_vat,
          'warehouse_id', v_wh_main,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4000'),
          'inventory_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'),
          'cogs_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5000')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  -- Non-VAT standalone invoice.
  IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE company_id = v_company_a AND reference = 'TEST-SI-NONVAT') THEN
    v_si := fn_save_sales_invoice(NULL,
      jsonb_build_object(
        'company_id', v_company_a, 'branch_id', v_branch_a, 'date', '2026-01-13',
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company_a AND customer_code = 'CUST-GOLDEN-CASH'),
        'customer_name_snapshot', 'Golden Walk-in Customer',
        'customer_tin_snapshot', '901-201-001-00000',
        'customer_address_snapshot', 'Makati City',
        'reference', 'TEST-SI-NONVAT',
        'memo', 'Non-VAT retail invoice',
        'vat_price_basis', 'exclusive',
        'warehouse_id', v_wh_golden
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', (SELECT id FROM items WHERE company_id = v_company_a AND item_code = 'ITEM-STOCK-008'),
          'description', 'Retail Merchandise A',
          'quantity', 3, 'unit_price', 350, 'vat_code_id', v_vat_exempt,
          'warehouse_id', v_wh_golden,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company_a AND account_code = '4000'),
          'inventory_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company_a AND account_code = '1200'),
          'cogs_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company_a AND account_code = '5000')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  -- Service companies: non-VAT OPC and VAT service corporation.
  IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE company_id = v_company_c AND reference = 'TEST-SI-OPC-SERVICE') THEN
    v_si := fn_save_sales_invoice(NULL,
      jsonb_build_object(
        'company_id', v_company_c, 'branch_id', v_branch_c, 'date', '2026-01-14',
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company_c AND customer_code = 'CUST-NORTHSTAR-RET'),
        'customer_name_snapshot', 'Startup Client OPC',
        'customer_tin_snapshot', '901-203-001-00000',
        'customer_address_snapshot', 'Pasig City',
        'reference', 'TEST-SI-OPC-SERVICE',
        'memo', 'Non-VAT service retainer',
        'vat_price_basis', 'exclusive'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', (SELECT id FROM items WHERE company_id = v_company_c AND item_code = 'ITEM-SERVICE-002'),
          'description', 'Bookkeeping Service',
          'quantity', 1, 'unit_price', 5000, 'vat_code_id', v_vat_exempt,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company_c AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE company_id = v_company_d AND reference = 'TEST-SI-SVC-VAT') THEN
    v_si := fn_save_sales_invoice(NULL,
      jsonb_build_object(
        'company_id', v_company_d, 'branch_id', v_branch_d, 'date', '2026-01-15',
        'customer_id', (SELECT id FROM customers WHERE company_id = v_company_d AND customer_code = 'CUST-PRIME-CWT'),
        'customer_name_snapshot', 'Enterprise Withholding Client Inc.',
        'customer_tin_snapshot', '901-204-001-00000',
        'customer_address_snapshot', 'Makati City',
        'reference', 'TEST-SI-SVC-VAT',
        'memo', 'VAT service invoice',
        'vat_price_basis', 'exclusive',
        'cwt_amount_expected', 100,
        'cwt_atc_code_id', v_cwt_atc,
        'cwt_tax_base', 5000
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', (SELECT id FROM items WHERE company_id = v_company_d AND item_code = 'ITEM-SERVICE-001'),
          'description', 'Consulting Service',
          'quantity', 1, 'unit_price', 5000, 'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company_d AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  -- Purchase chain: PO -> partial RR -> governed inventory receipt.
  IF NOT EXISTS (SELECT 1 FROM purchase_orders WHERE company_id = v_company AND notes = 'TEST-PO-PARTIAL-RECEIPT') THEN
    v_po := fn_save_purchase_order(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch, 'po_date', '2026-01-16',
        'supplier_id', (SELECT id FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-VAT-INVENTORY'),
        'supplier_name_snapshot', 'National Office Depot Inc.',
        'supplier_tin_snapshot', '902-300-001-00000',
        'delivery_address', 'ABC Main Warehouse',
        'expected_date', '2026-01-20',
        'payment_terms_id', (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = 'NET30'),
        'notes', 'TEST-PO-PARTIAL-RECEIPT'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item, 'description', 'Bond Paper A4',
          'quantity', 20, 'uom_id', (SELECT uom_id FROM items WHERE id = v_item),
          'unit_price', 200
        )
      )
    );
    PERFORM fn_approve_purchase_order(v_po);
    SELECT id INTO v_po_line FROM purchase_order_lines WHERE po_id = v_po ORDER BY line_number LIMIT 1;
    v_rr := fn_save_receiving_report(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch, 'warehouse_id', v_wh_main,
        'po_id', v_po, 'rr_date', '2026-01-18',
        'supplier_dr_no', 'SUPDR-TEST-001',
        'remarks', 'TEST-RR-PARTIAL'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'po_line_id', v_po_line, 'item_id', v_item,
          'description', 'Bond Paper A4',
          'ordered_qty', 20, 'received_qty', 12, 'reject_qty', 0,
          'uom_id', (SELECT uom_id FROM items WHERE id = v_item),
          'unit_price', 200
        )
      )
    );
    PERFORM fn_confirm_receiving_report(v_rr);
  END IF;

  -- Vendor bill with source-basis EWT and partial payment.
  IF NOT EXISTS (SELECT 1 FROM vendor_bills WHERE company_id = v_company AND reference = 'TEST-VB-PARTIAL-PAYMENT') THEN
    v_vb := fn_save_vendor_bill(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch,
        'supplier_id', (SELECT id FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-VAT-INVENTORY'),
        'supplier_name_snapshot', 'National Office Depot Inc.',
        'supplier_tin_snapshot', '902-300-001-00000',
        'supplier_invoice_number', 'SUPINV-TEST-001',
        'bill_date', '2026-01-19',
        'due_date', '2026-02-18',
        'payment_terms_id', (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = 'NET30'),
        'reference', 'TEST-VB-PARTIAL-PAYMENT',
        'memo', 'Inventory supplier bill with source-basis EWT'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item, 'description', 'Bond Paper A4 supplier bill',
          'quantity', 12, 'unit_price', 200,
          'vat_code_id', v_ivat,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5010'),
          'ewt_atc_code_id', v_ewt_atc,
          'ewt_tax_base', 2400,
          'ewt_amount', 24,
          'ewt_income_nature', 'Goods purchase'
        )
      )
    );
    PERFORM fn_approve_vendor_bill(v_vb);
    PERFORM fn_post_vendor_bill(v_vb);

    v_pv := fn_save_payment_voucher(NULL,
      jsonb_build_object(
        'company_id', v_company, 'branch_id', v_branch,
        'supplier_id', (SELECT id FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-VAT-INVENTORY'),
        'supplier_name_snapshot', 'National Office Depot Inc.',
        'supplier_tin_snapshot', '902-300-001-00000',
        'voucher_date', '2026-01-25',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'TEST-PV-PARTIAL',
        'remarks', 'Partial payment against source-accrued EWT bill'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'vendor_bill_id', v_vb,
          'payment_amount', 1000,
          'ewt_amount', 0
        )
      )
    );
    PERFORM fn_post_payment_voucher(v_pv);
  END IF;

  -- Valid stock transfer within available quantity.
  IF NOT EXISTS (SELECT 1 FROM stock_transfers WHERE company_id = v_company AND transfer_number = 'TEST-INV-TRANSFER-OK') THEN
    INSERT INTO stock_transfers (company_id, transfer_number, transfer_date, from_warehouse_id, to_warehouse_id, notes, created_by, updated_by)
    VALUES (v_company, 'TEST-INV-TRANSFER-OK', DATE '2026-01-26', v_wh_main, v_wh_cebu, 'Valid transfer within source stock', auth.uid(), auth.uid());

    INSERT INTO stock_transfer_lines (transfer_id, company_id, item_id, qty_transferred)
    VALUES ((SELECT id FROM stock_transfers WHERE company_id = v_company AND transfer_number = 'TEST-INV-TRANSFER-OK'), v_company, v_item_tape, 10);

    PERFORM fn_post_stock_transfer((SELECT id FROM stock_transfers WHERE company_id = v_company AND transfer_number = 'TEST-INV-TRANSFER-OK'));
  END IF;

  -- Positive and negative stock adjustments that remain within stock.
  IF NOT EXISTS (SELECT 1 FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'TEST-INV-ADJ-POS') THEN
    INSERT INTO stock_adjustments (company_id, branch_id, warehouse_id, adjustment_number, adjustment_date, reason, notes, created_by, updated_by)
    VALUES (v_company, v_branch, v_wh_main, 'TEST-INV-ADJ-POS', DATE '2026-01-27', 'correction', 'Positive count correction', auth.uid(), auth.uid());
    INSERT INTO stock_adjustment_lines (adjustment_id, company_id, item_id, qty_before, qty_adjusted, qty_after, unit_cost, gl_offset_account_id)
    VALUES ((SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'TEST-INV-ADJ-POS'), v_company, v_item_tape, 50, 5, 55, 45, (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5020'));
    PERFORM fn_post_stock_adjustment((SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'TEST-INV-ADJ-POS'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'TEST-INV-ADJ-NEG') THEN
    SELECT qty_on_hand INTO v_stock_qty FROM stock_balances WHERE company_id = v_company AND warehouse_id = v_wh_main AND item_id = v_item_tape;
    INSERT INTO stock_adjustments (company_id, branch_id, warehouse_id, adjustment_number, adjustment_date, reason, notes, created_by, updated_by)
    VALUES (v_company, v_branch, v_wh_main, 'TEST-INV-ADJ-NEG', DATE '2026-01-28', 'damage', 'Negative adjustment within available stock', auth.uid(), auth.uid());
    INSERT INTO stock_adjustment_lines (adjustment_id, company_id, item_id, qty_before, qty_adjusted, qty_after, unit_cost, gl_offset_account_id)
    VALUES ((SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'TEST-INV-ADJ-NEG'), v_company, v_item_tape, v_stock_qty, -2, v_stock_qty - 2, 45, (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5020'));
    PERFORM fn_post_stock_adjustment((SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'TEST-INV-ADJ-NEG'));
  END IF;

  -- Open sales order assistance fixture: partial chain state for UI/report tests.
  IF NOT EXISTS (SELECT 1 FROM sales_orders WHERE company_id = v_company AND reference_number = 'TEST-SO-OPEN-PARTIAL') THEN
    INSERT INTO sales_orders (company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot, so_number, so_date, expected_delivery_date, reference_number, remarks, total_amount, approval_status, fulfillment_status, approved_by, approved_at, created_by, updated_by)
    VALUES (
      v_company, v_branch,
      (SELECT id FROM customers WHERE company_id = v_company AND customer_code = 'CUST-OPEN-SO'),
      'VisMin Distribution Corp.', '901-200-006-00000',
      fn_next_document_number(v_company, v_branch, 'SO'),
      DATE '2026-01-29', DATE '2026-02-05',
      'TEST-SO-OPEN-PARTIAL', 'Open SO fixture: ordered 10, delivered/invoiced 6, remaining 4',
      2800, 'approved', 'partial', auth.uid(), now(), auth.uid(), auth.uid()
    );
    INSERT INTO sales_order_lines (sales_order_id, company_id, item_id, description, quantity, fulfilled_quantity, uom_id, unit_price, net_amount, line_number, created_by, updated_by)
    VALUES (
      (SELECT id FROM sales_orders WHERE company_id = v_company AND reference_number = 'TEST-SO-OPEN-PARTIAL'),
      v_company, v_item, 'Bond Paper A4', 10, 6,
      (SELECT uom_id FROM items WHERE id = v_item), 280, 2800, 1, auth.uid(), auth.uid()
    );
  END IF;
END $$;

-- Optional seed summary for manual psql and CI logs.
DO $$
DECLARE
  v_summary RECORD;
BEGIN
  IF current_setting('pxl.seed_summary', true) IS DISTINCT FROM 'on' THEN
    RETURN;
  END IF;

  SELECT
    (SELECT count(*) FROM companies WHERE trade_name LIKE 'DEMO-%') AS companies,
    (SELECT count(*) FROM branches b JOIN companies c ON c.id = b.company_id WHERE c.trade_name LIKE 'DEMO-%') AS branches,
    (SELECT count(*) FROM customers cu JOIN companies c ON c.id = cu.company_id WHERE c.trade_name LIKE 'DEMO-%') AS customers,
    (SELECT count(*) FROM suppliers s JOIN companies c ON c.id = s.company_id WHERE c.trade_name LIKE 'DEMO-%') AS suppliers,
    (SELECT count(*) FROM items i JOIN companies c ON c.id = i.company_id WHERE c.trade_name LIKE 'DEMO-%') AS items,
    (SELECT count(*) FROM sales_invoices si JOIN companies c ON c.id = si.company_id WHERE c.trade_name LIKE 'DEMO-%' AND si.status = 'posted') AS posted_sales_invoices,
    (SELECT count(*) FROM vendor_bills vb JOIN companies c ON c.id = vb.company_id WHERE c.trade_name LIKE 'DEMO-%' AND vb.status = 'posted') AS posted_vendor_bills,
    (SELECT count(*) FROM inventory_transactions it JOIN companies c ON c.id = it.company_id WHERE c.trade_name LIKE 'DEMO-%') AS inventory_transactions
  INTO v_summary;

  RAISE NOTICE
    'Canonical demo seed summary: companies=%, branches=%, customers=%, suppliers=%, items=%, posted_sales_invoices=%, posted_vendor_bills=%, inventory_transactions=%',
    v_summary.companies,
    v_summary.branches,
    v_summary.customers,
    v_summary.suppliers,
    v_summary.items,
    v_summary.posted_sales_invoices,
    v_summary.posted_vendor_bills,
    v_summary.inventory_transactions;
END $$;
