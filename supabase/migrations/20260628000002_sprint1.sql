-- ============================================================
-- Sprint 1: Setup Module Tables (S1.2 – S1.10)
-- ============================================================

-- ── S1.2: Branches ──────────────────────────────────────────
CREATE TABLE branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  branch_code TEXT NOT NULL,
  branch_name TEXT NOT NULL,
  branch_type TEXT NOT NULL DEFAULT 'branch'
    CHECK (branch_type IN ('head_office','branch','satellite_office','warehouse','project_site')),
  tin_branch_code TEXT NOT NULL DEFAULT '00000',
  rdo_id UUID REFERENCES ref_rdo_codes(id),
  tax_registration_override TEXT NOT NULL DEFAULT 'inherit'
    CHECK (tax_registration_override IN ('inherit','peza','boi','bmbe')),
  bir_reg_date DATE,
  lgu_permit_number TEXT,
  lgu_reg_date DATE,
  cas_permit_no TEXT,
  cas_date_issued DATE,
  address_line_1 TEXT NOT NULL,
  address_line_2 TEXT NOT NULL,
  city TEXT NOT NULL,
  province TEXT NOT NULL,
  zip_code TEXT NOT NULL,
  email TEXT,
  phone_number TEXT,
  mobile_number TEXT,
  branch_manager TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, branch_code)
);

-- ── S1.3: Departments ────────────────────────────────────────
CREATE TABLE departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  branch_id UUID REFERENCES branches(id),
  department_code TEXT NOT NULL,
  department_name TEXT NOT NULL,
  parent_department_id UUID REFERENCES departments(id),
  department_head_name TEXT,
  department_head_user_id UUID,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, department_code)
);

-- ── S1.3: Cost Centers ───────────────────────────────────────
CREATE TABLE cost_centers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  branch_id UUID REFERENCES branches(id),
  department_id UUID REFERENCES departments(id),
  cost_center_code TEXT NOT NULL,
  cost_center_name TEXT NOT NULL,
  cost_center_type TEXT NOT NULL DEFAULT 'cost_center'
    CHECK (cost_center_type IN ('revenue_center','cost_center','profit_center','investment_center')),
  parent_cost_center_id UUID REFERENCES cost_centers(id),
  manager_user_id UUID,
  valid_from DATE,
  valid_to DATE,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, cost_center_code)
);

-- ── S1.4: Fiscal Years ───────────────────────────────────────
CREATE TABLE fiscal_years (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  year_name TEXT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  is_calendar BOOLEAN DEFAULT false,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  retained_earnings_id UUID,  -- FK to chart_of_accounts added later
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, year_name)
);

-- ── S1.4: Fiscal Periods (auto-generated 12 per year) ────────
CREATE TABLE fiscal_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  fiscal_year_id UUID NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  period_number INTEGER NOT NULL CHECK (period_number BETWEEN 1 AND 12),
  period_name TEXT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  is_locked BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(fiscal_year_id, period_number)
);

-- ── S1.5: Chart of Accounts ──────────────────────────────────
CREATE TABLE chart_of_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  account_code TEXT NOT NULL,
  account_name TEXT NOT NULL,
  parent_id UUID REFERENCES chart_of_accounts(id),
  account_type TEXT NOT NULL
    CHECK (account_type IN ('asset','liability','equity','revenue','expense')),
  normal_balance TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
  is_postable BOOLEAN DEFAULT false,
  currency_code TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, account_code)
);

-- Add retained earnings FK now that COA exists
ALTER TABLE fiscal_years
  ADD CONSTRAINT fiscal_years_retained_earnings_fk
  FOREIGN KEY (retained_earnings_id) REFERENCES chart_of_accounts(id);

-- ── S1.6: Currencies (pre-seeded) ────────────────────────────
CREATE TABLE currencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  currency_code TEXT NOT NULL UNIQUE,
  currency_name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  is_base BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO currencies (currency_code, currency_name, symbol, is_base, is_active) VALUES
  ('PHP','Philippine Peso','₱',true,true),
  ('USD','US Dollar','$',false,true),
  ('EUR','Euro','€',false,true),
  ('JPY','Japanese Yen','¥',false,true),
  ('SGD','Singapore Dollar','S$',false,true),
  ('CNY','Chinese Yuan Renminbi','CN¥',false,true),
  ('HKD','Hong Kong Dollar','HK$',false,true),
  ('GBP','British Pound','£',false,true),
  ('AUD','Australian Dollar','A$',false,true);

-- ── S1.6: Exchange Rates ─────────────────────────────────────
CREATE TABLE exchange_rates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  currency_id UUID NOT NULL REFERENCES currencies(id),
  rate_date DATE NOT NULL,
  rate NUMERIC(18,6) NOT NULL CHECK (rate > 0),
  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, currency_id, rate_date)
);

-- ── S1.7: Feature Definitions (pre-seeded) ───────────────────
CREATE TABLE ref_feature_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_key TEXT NOT NULL UNIQUE,
  feature_name TEXT NOT NULL,
  module_category TEXT NOT NULL,
  description TEXT NOT NULL,
  always_enabled BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO ref_feature_definitions
  (feature_key, feature_name, module_category, description, always_enabled, sort_order)
VALUES
  ('core_accounting','Core Accounting','Accounting','Journal Entries, Chart of Accounts, Fiscal Periods. Always enabled.',true,1),
  ('accounts_receivable','Accounts Receivable','Sales','Sales Invoices, Customer Payments, AR Aging.',false,2),
  ('accounts_payable','Accounts Payable','Purchasing','Purchase Invoices, Supplier Payments, AP Aging.',false,3),
  ('inventory_management','Inventory Management','Inventory','Item Master, Stock Movements, Warehouse Management.',false,4),
  ('fixed_assets','Fixed Assets','Fixed Assets','Asset Register, Depreciation, Disposals, Impairment.',false,5),
  ('petty_cash','Petty Cash','Banking & Treasury','Petty Cash Funds, Vouchers, Replenishments.',false,6),
  ('banking_module','Banking Module','Banking & Treasury','Bank Accounts, Reconciliation, Fund Transfers.',false,7),
  ('check_vouchers','Check Vouchers','Banking & Treasury','AP Check Voucher module and EWT 2307 deduction.',false,8),
  ('vat_compliance','VAT Compliance','Compliance','VAT Returns (2550M/2550Q), SLSP, RELIEF, Input VAT tracking.',false,9),
  ('ewt_compliance','EWT Compliance','Compliance','EWT Returns (0619-E/1601EQ), 2307 Certificates, QAP.',false,10),
  ('fwt_compliance','FWT Compliance','Compliance','FWT Returns (0619-F/1601FQ), 2306 Certificates.',false,11),
  ('budget_module','Budget Module','Accounting','Budget vs Actual reporting and Budget creation.',false,12),
  ('multi_branch','Multi-Branch','Setup','Multi-branch operations and inter-branch transfers.',false,13),
  ('multi_currency','Multi-Currency','Accounting','Foreign currency transactions and Forex revaluation.',false,14),
  ('approval_workflows','Approval Workflows','Setup','Approval routing for sales, purchasing, payment, journal entries.',false,15),
  ('tax_calendar','Tax Calendar','Compliance','Automated BIR deadline calendar and alerts.',false,16);

-- ── S1.7: Feature Enablement Per Company ─────────────────────
CREATE TABLE sys_feature_enablement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  feature_definition_id UUID NOT NULL REFERENCES ref_feature_definitions(id),
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  enabled_by UUID,
  enabled_at TIMESTAMPTZ,
  disabled_by UUID,
  disabled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, feature_definition_id)
);

CREATE INDEX idx_feature_enablement_company
  ON sys_feature_enablement (company_id, is_enabled);

-- ── S1.8: Document Types (pre-seeded) ────────────────────────
CREATE TABLE ref_document_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL CHECK (category IN ('sales','purchasing','accounting','compliance')),
  document_code TEXT NOT NULL UNIQUE,
  document_name TEXT NOT NULL,
  is_bir_registered BOOLEAN DEFAULT false,
  sort_order INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO ref_document_types (category, document_code, document_name, is_bir_registered, sort_order) VALUES
  -- Sales
  ('sales','QT','Quotation',false,1),
  ('sales','SO','Sales Order',false,2),
  ('sales','DR','Delivery Receipt',false,3),
  ('sales','SI','Sales Invoice',true,4),
  ('sales','CS','Cash Sales',true,5),
  ('sales','OR','Official Receipt',true,6),
  ('sales','CM','Credit Memo',false,7),
  ('sales','DM-S','Debit Memo to Customer',false,8),
  ('sales','CR','Customer Return',false,9),
  -- Purchasing
  ('purchasing','PO','Purchase Order',false,10),
  ('purchasing','RR','Receiving Report',false,11),
  ('purchasing','VB','Vendor Bill',false,12),
  ('purchasing','CP','Cash Purchase',false,13),
  ('purchasing','PV','Payment Voucher',false,14),
  ('purchasing','VC','Vendor Credit',false,15),
  ('purchasing','DM-P','Debit Memo to Supplier',false,16),
  ('purchasing','PR','Purchase Return',false,17),
  -- Accounting
  ('accounting','JV','Journal Voucher',false,18),
  ('accounting','RJV','Recurring Journal Voucher',false,19),
  ('accounting','CV','Check Voucher',false,20),
  ('accounting','PCF','Petty Cash Fund',false,21),
  ('accounting','PCV','Petty Cash Voucher',false,22),
  -- Compliance
  ('compliance','2307','BIR Form 2307',false,23),
  ('compliance','2306','BIR Form 2306',false,24);

-- ── S1.8: Number Series ──────────────────────────────────────
CREATE TABLE number_series (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  branch_id UUID NOT NULL REFERENCES branches(id),
  document_type_id UUID NOT NULL REFERENCES ref_document_types(id),
  prefix TEXT,
  has_dynamic_year BOOLEAN DEFAULT false,
  number_length INTEGER NOT NULL DEFAULT 6,
  starting_number INTEGER NOT NULL DEFAULT 1,
  next_number INTEGER NOT NULL DEFAULT 1,
  reset_frequency TEXT NOT NULL DEFAULT 'never'
    CHECK (reset_frequency IN ('never','yearly','monthly')),
  last_reset_date DATE,
  atp_series_start INTEGER,
  atp_series_end INTEGER,
  atp_alert_threshold INTEGER,
  allow_manual_override BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, branch_id, document_type_id)
);

-- ── S1.9: Approval Workflows ─────────────────────────────────
CREATE TABLE approval_workflows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  workflow_name TEXT NOT NULL,
  module_type TEXT NOT NULL
    CHECK (module_type IN ('sales','purchasing','payment','journal','master_data','asset','credit_memo')),
  document_type TEXT NOT NULL,
  trigger_condition_type TEXT NOT NULL
    CHECK (trigger_condition_type IN ('always','amount_exceeds','discount_pct_exceeds','credit_limit_exceeded')),
  threshold_value NUMERIC(15,2),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, module_type, document_type, trigger_condition_type, threshold_value)
);

CREATE TABLE approval_workflow_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  workflow_id UUID NOT NULL REFERENCES approval_workflows(id) ON DELETE CASCADE,
  step_sequence INTEGER NOT NULL,
  approver_type TEXT NOT NULL CHECK (approver_type IN ('user','role','dept_head')),
  approver_user_id UUID,
  approver_role_id UUID,
  action_required TEXT NOT NULL DEFAULT 'approve' CHECK (action_required IN ('approve','review')),
  escalation_hours INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(workflow_id, step_sequence)
);

CREATE TABLE approval_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  workflow_id UUID NOT NULL REFERENCES approval_workflows(id),
  workflow_step_id UUID NOT NULL REFERENCES approval_workflow_steps(id),
  source_document_type TEXT NOT NULL,
  source_document_id UUID NOT NULL,
  source_document_no TEXT NOT NULL,
  source_document_amount NUMERIC(15,2),
  step_sequence INTEGER NOT NULL,
  required_approver_type TEXT NOT NULL,
  required_approver_id UUID,
  actual_approver_id UUID,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','escalated','bypassed')),
  remarks TEXT,
  acted_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  escalated_at TIMESTAMPTZ,
  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_approval_instances_approver
  ON approval_instances (company_id, required_approver_id, status)
  WHERE status = 'pending';
CREATE INDEX idx_approval_instances_document
  ON approval_instances (source_document_type, source_document_id);

-- ── S1.10: System Audit Log ──────────────────────────────────
CREATE TABLE sys_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID,
  table_name TEXT NOT NULL,
  record_id UUID,
  action TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  old_data JSONB,
  new_data JSONB,
  changed_by UUID,
  changed_at TIMESTAMPTZ DEFAULT NOW(),
  ip_address TEXT,
  user_agent TEXT
);

CREATE INDEX idx_audit_logs_table ON sys_audit_logs (table_name, changed_at DESC);
CREATE INDEX idx_audit_logs_company ON sys_audit_logs (company_id, changed_at DESC);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_of_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_feature_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sys_feature_enablement ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE number_series ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_workflow_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE sys_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_all_branches"             ON branches             FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_departments"          ON departments          FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_cost_centers"         ON cost_centers         FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_fiscal_years"         ON fiscal_years         FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_fiscal_periods"       ON fiscal_periods       FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_coa"                  ON chart_of_accounts    FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_read_currencies"          ON currencies           FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_all_exchange_rates"       ON exchange_rates       FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_read_feature_defs"        ON ref_feature_definitions FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_all_feature_enablement"   ON sys_feature_enablement FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_read_document_types"      ON ref_document_types   FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_all_number_series"        ON number_series        FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_approval_workflows"   ON approval_workflows   FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_workflow_steps"       ON approval_workflow_steps FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_all_approval_instances"   ON approval_instances   FOR ALL TO authenticated USING (true);
CREATE POLICY "auth_read_audit_logs"          ON sys_audit_logs       FOR SELECT TO authenticated USING (true);

-- ── Updated_at triggers ───────────────────────────────────────
CREATE TRIGGER branches_updated_at         BEFORE UPDATE ON branches         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER departments_updated_at      BEFORE UPDATE ON departments      FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER cost_centers_updated_at     BEFORE UPDATE ON cost_centers     FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER fiscal_years_updated_at     BEFORE UPDATE ON fiscal_years     FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER fiscal_periods_updated_at   BEFORE UPDATE ON fiscal_periods   FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER coa_updated_at             BEFORE UPDATE ON chart_of_accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER feature_enablement_updated_at BEFORE UPDATE ON sys_feature_enablement FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER number_series_updated_at    BEFORE UPDATE ON number_series    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER approval_workflows_updated_at BEFORE UPDATE ON approval_workflows FOR EACH ROW EXECUTE FUNCTION update_updated_at();
