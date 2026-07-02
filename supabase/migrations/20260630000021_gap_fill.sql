-- ══════════════════════════════════════════════════════════════════════════════
-- GAP-FILL: Idempotent catch-up for migrations 008-021
-- Covers all DDL from 008 through 021 safely for a partially-applied database.
-- Each CREATE POLICY is preceded by DROP POLICY IF EXISTS.
-- Each CREATE TABLE uses IF NOT EXISTS. Functions use CREATE OR REPLACE.
-- ══════════════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000008_rls_hardening.sql                                        │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- RLS HARDENING: User-company membership model
-- Replaces blanket USING (true) write policies with company-scoped enforcement.
-- READ policies remain open for authenticated users (single-org trusted context).
-- WRITE policies (INSERT/UPDATE/DELETE) require is_company_member(company_id).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. User-company membership table ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS user_company_memberships (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID        NOT NULL REFERENCES companies(id)  ON DELETE CASCADE,
  role       TEXT        NOT NULL DEFAULT 'member'
               CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  granted_by UUID        REFERENCES auth.users(id),
  UNIQUE (user_id, company_id)
);

CREATE INDEX IF NOT EXISTS idx_ucm_user    ON user_company_memberships (user_id);
CREATE INDEX IF NOT EXISTS idx_ucm_company ON user_company_memberships (company_id);

ALTER TABLE user_company_memberships ENABLE ROW LEVEL SECURITY;

-- Users can see their own memberships
DROP POLICY IF EXISTS "ucm_read_own" ON user_company_memberships;
CREATE POLICY "ucm_read_own" ON user_company_memberships
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Owners and admins can manage memberships for their companies
DROP POLICY IF EXISTS "ucm_manage_own_companies" ON user_company_memberships;
CREATE POLICY "ucm_manage_own_companies" ON user_company_memberships
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_company_memberships m
      WHERE m.user_id    = auth.uid()
        AND m.company_id = user_company_memberships.company_id
        AND m.role       IN ('owner', 'admin')
    )
  );

-- ── 2. Helper: check if current user is a member of the given company ──────────

CREATE OR REPLACE FUNCTION is_company_member(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_company_memberships
    WHERE user_id = auth.uid() AND company_id = p_company_id
  );
$$;

-- ── 3. Bootstrap: seed all existing users × all existing companies ─────────────
-- Grants every current auth user access to every current company as 'admin'.
-- Replace with explicit grants when a user-management UI is built.

INSERT INTO user_company_memberships (user_id, company_id, role)
SELECT u.id, c.id, 'admin'
FROM   auth.users u
CROSS  JOIN companies c
ON CONFLICT (user_id, company_id) DO NOTHING;

-- ── 4. Triggers: keep memberships current going forward ───────────────────────

-- New company created → grant access to all existing users
CREATE OR REPLACE FUNCTION fn_grant_all_users_on_new_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO user_company_memberships (user_id, company_id, role)
  SELECT id, NEW.id, 'member' FROM auth.users
  ON CONFLICT (user_id, company_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_new_company_grant_access ON companies;
CREATE TRIGGER trg_new_company_grant_access
  AFTER INSERT ON companies
  FOR EACH ROW EXECUTE FUNCTION fn_grant_all_users_on_new_company();

-- New user signs up → grant access to all existing companies
CREATE OR REPLACE FUNCTION fn_grant_new_user_all_companies()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO user_company_memberships (user_id, company_id, role)
  SELECT NEW.id, id, 'member' FROM public.companies
  ON CONFLICT (user_id, company_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_new_user_grant_companies ON auth.users;
CREATE TRIGGER trg_new_user_grant_companies
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION fn_grant_new_user_all_companies();

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. RE-SCOPE EXISTING POLICIES
-- Pattern: drop old FOR ALL USING (true); replace with separate SELECT/INSERT/
--          UPDATE/DELETE where SELECT stays open and writes check membership.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Sprint 1: Organization & setup tables ─────────────────────────────────────

DROP POLICY IF EXISTS "auth_all_branches" ON branches;
DROP POLICY IF EXISTS "auth_read_branches" ON branches;
CREATE POLICY "auth_read_branches"   ON branches FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_branches" ON branches;
CREATE POLICY "auth_insert_branches" ON branches FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_branches" ON branches;
CREATE POLICY "auth_update_branches" ON branches FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_branches" ON branches;
CREATE POLICY "auth_delete_branches" ON branches FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_departments" ON departments;
DROP POLICY IF EXISTS "auth_read_departments" ON departments;
CREATE POLICY "auth_read_departments"   ON departments FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_departments" ON departments;
CREATE POLICY "auth_insert_departments" ON departments FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_departments" ON departments;
CREATE POLICY "auth_update_departments" ON departments FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_departments" ON departments;
CREATE POLICY "auth_delete_departments" ON departments FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_cost_centers" ON cost_centers;
DROP POLICY IF EXISTS "auth_read_cost_centers" ON cost_centers;
CREATE POLICY "auth_read_cost_centers"   ON cost_centers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_cost_centers" ON cost_centers;
CREATE POLICY "auth_insert_cost_centers" ON cost_centers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_cost_centers" ON cost_centers;
CREATE POLICY "auth_update_cost_centers" ON cost_centers FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_cost_centers" ON cost_centers;
CREATE POLICY "auth_delete_cost_centers" ON cost_centers FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_fiscal_years" ON fiscal_years;
DROP POLICY IF EXISTS "auth_read_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_read_fiscal_years"   ON fiscal_years FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_insert_fiscal_years" ON fiscal_years FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_update_fiscal_years" ON fiscal_years FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_delete_fiscal_years" ON fiscal_years FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_fiscal_periods" ON fiscal_periods;
DROP POLICY IF EXISTS "auth_read_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_read_fiscal_periods"   ON fiscal_periods FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_insert_fiscal_periods" ON fiscal_periods FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_update_fiscal_periods" ON fiscal_periods FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_delete_fiscal_periods" ON fiscal_periods FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_coa" ON chart_of_accounts;
DROP POLICY IF EXISTS "auth_read_coa" ON chart_of_accounts;
CREATE POLICY "auth_read_coa"   ON chart_of_accounts FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_coa" ON chart_of_accounts;
CREATE POLICY "auth_insert_coa" ON chart_of_accounts FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_coa" ON chart_of_accounts;
CREATE POLICY "auth_update_coa" ON chart_of_accounts FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_coa" ON chart_of_accounts;
CREATE POLICY "auth_delete_coa" ON chart_of_accounts FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_exchange_rates" ON exchange_rates;
DROP POLICY IF EXISTS "auth_read_exchange_rates" ON exchange_rates;
CREATE POLICY "auth_read_exchange_rates"   ON exchange_rates FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_exchange_rates" ON exchange_rates;
CREATE POLICY "auth_insert_exchange_rates" ON exchange_rates FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_exchange_rates" ON exchange_rates;
CREATE POLICY "auth_update_exchange_rates" ON exchange_rates FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_exchange_rates" ON exchange_rates;
CREATE POLICY "auth_delete_exchange_rates" ON exchange_rates FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_feature_enablement" ON sys_feature_enablement;
DROP POLICY IF EXISTS "auth_read_feature_enablement" ON sys_feature_enablement;
CREATE POLICY "auth_read_feature_enablement"   ON sys_feature_enablement FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_feature_enablement" ON sys_feature_enablement;
CREATE POLICY "auth_insert_feature_enablement" ON sys_feature_enablement FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_feature_enablement" ON sys_feature_enablement;
CREATE POLICY "auth_update_feature_enablement" ON sys_feature_enablement FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_feature_enablement" ON sys_feature_enablement;
CREATE POLICY "auth_delete_feature_enablement" ON sys_feature_enablement FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_number_series" ON number_series;
DROP POLICY IF EXISTS "auth_read_number_series" ON number_series;
CREATE POLICY "auth_read_number_series"   ON number_series FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_number_series" ON number_series;
CREATE POLICY "auth_insert_number_series" ON number_series FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_number_series" ON number_series;
CREATE POLICY "auth_update_number_series" ON number_series FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_number_series" ON number_series;
CREATE POLICY "auth_delete_number_series" ON number_series FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_approval_workflows" ON approval_workflows;
DROP POLICY IF EXISTS "auth_read_approval_workflows" ON approval_workflows;
CREATE POLICY "auth_read_approval_workflows"   ON approval_workflows FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_approval_workflows" ON approval_workflows;
CREATE POLICY "auth_insert_approval_workflows" ON approval_workflows FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_approval_workflows" ON approval_workflows;
CREATE POLICY "auth_update_approval_workflows" ON approval_workflows FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_approval_workflows" ON approval_workflows;
CREATE POLICY "auth_delete_approval_workflows" ON approval_workflows FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_workflow_steps" ON approval_workflow_steps;
DROP POLICY IF EXISTS "auth_read_workflow_steps" ON approval_workflow_steps;
CREATE POLICY "auth_read_workflow_steps"   ON approval_workflow_steps FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_workflow_steps" ON approval_workflow_steps;
CREATE POLICY "auth_insert_workflow_steps" ON approval_workflow_steps FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_workflow_steps" ON approval_workflow_steps;
CREATE POLICY "auth_update_workflow_steps" ON approval_workflow_steps FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_workflow_steps" ON approval_workflow_steps;
CREATE POLICY "auth_delete_workflow_steps" ON approval_workflow_steps FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_approval_instances" ON approval_instances;
DROP POLICY IF EXISTS "auth_read_approval_instances" ON approval_instances;
CREATE POLICY "auth_read_approval_instances"   ON approval_instances FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_approval_instances" ON approval_instances;
CREATE POLICY "auth_insert_approval_instances" ON approval_instances FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_approval_instances" ON approval_instances;
CREATE POLICY "auth_update_approval_instances" ON approval_instances FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_approval_instances" ON approval_instances;
CREATE POLICY "auth_delete_approval_instances" ON approval_instances FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Sprint 2/3: Master data ────────────────────────────────────────────────────

DROP POLICY IF EXISTS "auth_all_ewt_codes" ON ewt_codes;
DROP POLICY IF EXISTS "auth_read_ewt_codes" ON ewt_codes;
CREATE POLICY "auth_read_ewt_codes"   ON ewt_codes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_ewt_codes" ON ewt_codes;
CREATE POLICY "auth_insert_ewt_codes" ON ewt_codes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_ewt_codes" ON ewt_codes;
CREATE POLICY "auth_update_ewt_codes" ON ewt_codes FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_ewt_codes" ON ewt_codes;
CREATE POLICY "auth_delete_ewt_codes" ON ewt_codes FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_payment_terms" ON payment_terms;
DROP POLICY IF EXISTS "auth_read_payment_terms" ON payment_terms;
CREATE POLICY "auth_read_payment_terms"   ON payment_terms FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_payment_terms" ON payment_terms;
CREATE POLICY "auth_insert_payment_terms" ON payment_terms FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_payment_terms" ON payment_terms;
CREATE POLICY "auth_update_payment_terms" ON payment_terms FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_payment_terms" ON payment_terms;
CREATE POLICY "auth_delete_payment_terms" ON payment_terms FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_item_categories" ON item_categories;
DROP POLICY IF EXISTS "auth_read_item_categories" ON item_categories;
CREATE POLICY "auth_read_item_categories"   ON item_categories FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_item_categories" ON item_categories;
CREATE POLICY "auth_insert_item_categories" ON item_categories FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_item_categories" ON item_categories;
CREATE POLICY "auth_update_item_categories" ON item_categories FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_item_categories" ON item_categories;
CREATE POLICY "auth_delete_item_categories" ON item_categories FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_uom" ON units_of_measure;
DROP POLICY IF EXISTS "auth_read_uom" ON units_of_measure;
CREATE POLICY "auth_read_uom"   ON units_of_measure FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_uom" ON units_of_measure;
CREATE POLICY "auth_insert_uom" ON units_of_measure FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_uom" ON units_of_measure;
CREATE POLICY "auth_update_uom" ON units_of_measure FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_uom" ON units_of_measure;
CREATE POLICY "auth_delete_uom" ON units_of_measure FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_customers" ON customers;
DROP POLICY IF EXISTS "auth_read_customers" ON customers;
CREATE POLICY "auth_read_customers"   ON customers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_customers" ON customers;
CREATE POLICY "auth_insert_customers" ON customers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_customers" ON customers;
CREATE POLICY "auth_update_customers" ON customers FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_customers" ON customers;
CREATE POLICY "auth_delete_customers" ON customers FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_suppliers" ON suppliers;
DROP POLICY IF EXISTS "auth_read_suppliers" ON suppliers;
CREATE POLICY "auth_read_suppliers"   ON suppliers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_suppliers" ON suppliers;
CREATE POLICY "auth_insert_suppliers" ON suppliers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_suppliers" ON suppliers;
CREATE POLICY "auth_update_suppliers" ON suppliers FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_suppliers" ON suppliers;
CREATE POLICY "auth_delete_suppliers" ON suppliers FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_items" ON items;
DROP POLICY IF EXISTS "auth_read_items" ON items;
CREATE POLICY "auth_read_items"   ON items FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_items" ON items;
CREATE POLICY "auth_insert_items" ON items FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_items" ON items;
CREATE POLICY "auth_update_items" ON items FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_items" ON items;
CREATE POLICY "auth_delete_items" ON items FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Sprint 2 Tax: Compliance setup ────────────────────────────────────────────

DROP POLICY IF EXISTS "auth_all_fwt_codes" ON fwt_codes;
DROP POLICY IF EXISTS "auth_read_fwt_codes" ON fwt_codes;
CREATE POLICY "auth_read_fwt_codes"   ON fwt_codes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_fwt_codes" ON fwt_codes;
CREATE POLICY "auth_insert_fwt_codes" ON fwt_codes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_fwt_codes" ON fwt_codes;
CREATE POLICY "auth_update_fwt_codes" ON fwt_codes FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_fwt_codes" ON fwt_codes;
CREATE POLICY "auth_delete_fwt_codes" ON fwt_codes FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_pt_codes" ON percentage_tax_codes;
DROP POLICY IF EXISTS "auth_read_pt_codes" ON percentage_tax_codes;
CREATE POLICY "auth_read_pt_codes"   ON percentage_tax_codes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_pt_codes" ON percentage_tax_codes;
CREATE POLICY "auth_insert_pt_codes" ON percentage_tax_codes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_pt_codes" ON percentage_tax_codes;
CREATE POLICY "auth_update_pt_codes" ON percentage_tax_codes FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_pt_codes" ON percentage_tax_codes;
CREATE POLICY "auth_delete_pt_codes" ON percentage_tax_codes FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "auth_all_compliance_profiles" ON compliance_profiles;
DROP POLICY IF EXISTS "auth_read_compliance_profiles" ON compliance_profiles;
CREATE POLICY "auth_read_compliance_profiles"   ON compliance_profiles FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_compliance_profiles" ON compliance_profiles;
CREATE POLICY "auth_insert_compliance_profiles" ON compliance_profiles FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_compliance_profiles" ON compliance_profiles;
CREATE POLICY "auth_update_compliance_profiles" ON compliance_profiles FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_compliance_profiles" ON compliance_profiles;
CREATE POLICY "auth_delete_compliance_profiles" ON compliance_profiles FOR DELETE TO authenticated USING (is_company_member(company_id));

-- tax_calendar_events: keep SELECT open; upgrade INSERT/UPDATE to require membership
DROP POLICY IF EXISTS "auth_insert_tax_calendar" ON tax_calendar_events;
DROP POLICY IF EXISTS "auth_update_pending_calendar" ON tax_calendar_events;
DROP POLICY IF EXISTS "auth_insert_tax_calendar" ON tax_calendar_events;
CREATE POLICY "auth_insert_tax_calendar" ON tax_calendar_events
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_update_tax_calendar" ON tax_calendar_events;
CREATE POLICY "auth_update_tax_calendar" ON tax_calendar_events
  FOR UPDATE TO authenticated USING (status = 'pending' AND is_company_member(company_id));
DROP POLICY IF EXISTS "auth_delete_tax_calendar" ON tax_calendar_events;
CREATE POLICY "auth_delete_tax_calendar" ON tax_calendar_events
  FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Sprint 5: Sales transactions ──────────────────────────────────────────────

-- sales_invoices: add company member check to insert/update
DROP POLICY IF EXISTS "insert_sales_invoices"    ON sales_invoices;
DROP POLICY IF EXISTS "update_draft_approved_si" ON sales_invoices;
DROP POLICY IF EXISTS "insert_sales_invoices" ON sales_invoices;
CREATE POLICY "insert_sales_invoices" ON sales_invoices
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_draft_approved_si" ON sales_invoices;
CREATE POLICY "update_draft_approved_si" ON sales_invoices
  FOR UPDATE TO authenticated
  USING (status IN ('draft', 'approved') AND is_company_member(company_id));

-- sales_invoice_lines: scope via parent SI company
DROP POLICY IF EXISTS "insert_si_lines" ON sales_invoice_lines;
DROP POLICY IF EXISTS "update_si_lines" ON sales_invoice_lines;
DROP POLICY IF EXISTS "delete_si_lines" ON sales_invoice_lines;
DROP POLICY IF EXISTS "insert_si_lines" ON sales_invoice_lines;
CREATE POLICY "insert_si_lines" ON sales_invoice_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM sales_invoices WHERE id = sales_invoice_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_si_lines" ON sales_invoice_lines;
CREATE POLICY "update_si_lines" ON sales_invoice_lines
  FOR UPDATE TO authenticated
  USING (
    sales_invoice_id IN (
      SELECT id FROM sales_invoices WHERE status IN ('draft','approved') AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_si_lines" ON sales_invoice_lines;
CREATE POLICY "delete_si_lines" ON sales_invoice_lines
  FOR DELETE TO authenticated
  USING (
    sales_invoice_id IN (
      SELECT id FROM sales_invoices WHERE status = 'draft' AND is_company_member(company_id)
    )
  );

-- receipts
DROP POLICY IF EXISTS "insert_receipts"       ON receipts;
DROP POLICY IF EXISTS "update_draft_receipts" ON receipts;
DROP POLICY IF EXISTS "insert_receipts" ON receipts;
CREATE POLICY "insert_receipts" ON receipts
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_draft_receipts" ON receipts;
CREATE POLICY "update_draft_receipts" ON receipts
  FOR UPDATE TO authenticated USING (status IN ('draft') AND is_company_member(company_id));

-- receipt_lines
DROP POLICY IF EXISTS "insert_receipt_lines" ON receipt_lines;
DROP POLICY IF EXISTS "update_receipt_lines" ON receipt_lines;
DROP POLICY IF EXISTS "delete_receipt_lines" ON receipt_lines;
DROP POLICY IF EXISTS "insert_receipt_lines" ON receipt_lines;
CREATE POLICY "insert_receipt_lines" ON receipt_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM receipts WHERE id = receipt_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_receipt_lines" ON receipt_lines;
CREATE POLICY "update_receipt_lines" ON receipt_lines
  FOR UPDATE TO authenticated
  USING (
    receipt_id IN (SELECT id FROM receipts WHERE status = 'draft' AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "delete_receipt_lines" ON receipt_lines;
CREATE POLICY "delete_receipt_lines" ON receipt_lines
  FOR DELETE TO authenticated
  USING (
    receipt_id IN (SELECT id FROM receipts WHERE status = 'draft' AND is_company_member(company_id))
  );

-- credit_memos
DROP POLICY IF EXISTS "insert_credit_memos" ON credit_memos;
DROP POLICY IF EXISTS "update_draft_cm"     ON credit_memos;
DROP POLICY IF EXISTS "insert_credit_memos" ON credit_memos;
CREATE POLICY "insert_credit_memos" ON credit_memos
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_draft_cm" ON credit_memos;
CREATE POLICY "update_draft_cm" ON credit_memos
  FOR UPDATE TO authenticated USING (status IN ('draft','approved') AND is_company_member(company_id));

-- credit_memo_lines
DROP POLICY IF EXISTS "insert_cm_lines" ON credit_memo_lines;
DROP POLICY IF EXISTS "update_cm_lines" ON credit_memo_lines;
DROP POLICY IF EXISTS "delete_cm_lines" ON credit_memo_lines;
DROP POLICY IF EXISTS "insert_cm_lines" ON credit_memo_lines;
CREATE POLICY "insert_cm_lines" ON credit_memo_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM credit_memos WHERE id = credit_memo_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_cm_lines" ON credit_memo_lines;
CREATE POLICY "update_cm_lines" ON credit_memo_lines
  FOR UPDATE TO authenticated
  USING (
    credit_memo_id IN (
      SELECT id FROM credit_memos WHERE status IN ('draft','approved') AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_cm_lines" ON credit_memo_lines;
CREATE POLICY "delete_cm_lines" ON credit_memo_lines
  FOR DELETE TO authenticated
  USING (
    credit_memo_id IN (SELECT id FROM credit_memos WHERE status = 'draft' AND is_company_member(company_id))
  );

-- debit_memos
DROP POLICY IF EXISTS "insert_debit_memos" ON debit_memos;
DROP POLICY IF EXISTS "update_draft_dm"    ON debit_memos;
DROP POLICY IF EXISTS "insert_debit_memos" ON debit_memos;
CREATE POLICY "insert_debit_memos" ON debit_memos
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_draft_dm" ON debit_memos;
CREATE POLICY "update_draft_dm" ON debit_memos
  FOR UPDATE TO authenticated USING (status IN ('draft','approved') AND is_company_member(company_id));

-- debit_memo_lines
DROP POLICY IF EXISTS "insert_dm_lines" ON debit_memo_lines;
DROP POLICY IF EXISTS "update_dm_lines" ON debit_memo_lines;
DROP POLICY IF EXISTS "delete_dm_lines" ON debit_memo_lines;
DROP POLICY IF EXISTS "insert_dm_lines" ON debit_memo_lines;
CREATE POLICY "insert_dm_lines" ON debit_memo_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM debit_memos WHERE id = debit_memo_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_dm_lines" ON debit_memo_lines;
CREATE POLICY "update_dm_lines" ON debit_memo_lines
  FOR UPDATE TO authenticated
  USING (
    debit_memo_id IN (
      SELECT id FROM debit_memos WHERE status IN ('draft','approved') AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_dm_lines" ON debit_memo_lines;
CREATE POLICY "delete_dm_lines" ON debit_memo_lines
  FOR DELETE TO authenticated
  USING (
    debit_memo_id IN (SELECT id FROM debit_memos WHERE status = 'draft' AND is_company_member(company_id))
  );

-- sales_quotations
DROP POLICY IF EXISTS "insert_sq" ON sales_quotations;
DROP POLICY IF EXISTS "update_sq" ON sales_quotations;
DROP POLICY IF EXISTS "insert_sq" ON sales_quotations;
CREATE POLICY "insert_sq" ON sales_quotations
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_sq" ON sales_quotations;
CREATE POLICY "update_sq" ON sales_quotations
  FOR UPDATE TO authenticated USING (status IN ('draft','pending') AND is_company_member(company_id));

-- sales_quotation_lines
DROP POLICY IF EXISTS "insert_sql" ON sales_quotation_lines;
DROP POLICY IF EXISTS "update_sql" ON sales_quotation_lines;
DROP POLICY IF EXISTS "delete_sql" ON sales_quotation_lines;
DROP POLICY IF EXISTS "insert_sql" ON sales_quotation_lines;
CREATE POLICY "insert_sql" ON sales_quotation_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM sales_quotations WHERE id = quotation_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_sql" ON sales_quotation_lines;
CREATE POLICY "update_sql" ON sales_quotation_lines
  FOR UPDATE TO authenticated
  USING (
    quotation_id IN (
      SELECT id FROM sales_quotations WHERE status IN ('draft','pending') AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_sql" ON sales_quotation_lines;
CREATE POLICY "delete_sql" ON sales_quotation_lines
  FOR DELETE TO authenticated
  USING (
    quotation_id IN (
      SELECT id FROM sales_quotations WHERE status = 'draft' AND is_company_member(company_id)
    )
  );

-- sales_orders
DROP POLICY IF EXISTS "insert_so" ON sales_orders;
DROP POLICY IF EXISTS "update_so" ON sales_orders;
DROP POLICY IF EXISTS "insert_so" ON sales_orders;
CREATE POLICY "insert_so" ON sales_orders
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_so" ON sales_orders;
CREATE POLICY "update_so" ON sales_orders
  FOR UPDATE TO authenticated USING (approval_status IN ('pending') AND is_company_member(company_id));

-- sales_order_lines
DROP POLICY IF EXISTS "insert_sol" ON sales_order_lines;
DROP POLICY IF EXISTS "update_sol" ON sales_order_lines;
DROP POLICY IF EXISTS "delete_sol" ON sales_order_lines;
DROP POLICY IF EXISTS "insert_sol" ON sales_order_lines;
CREATE POLICY "insert_sol" ON sales_order_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM sales_orders WHERE id = sales_order_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_sol" ON sales_order_lines;
CREATE POLICY "update_sol" ON sales_order_lines
  FOR UPDATE TO authenticated
  USING (
    sales_order_id IN (
      SELECT id FROM sales_orders WHERE approval_status = 'pending' AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_sol" ON sales_order_lines;
CREATE POLICY "delete_sol" ON sales_order_lines
  FOR DELETE TO authenticated
  USING (
    sales_order_id IN (
      SELECT id FROM sales_orders WHERE approval_status = 'pending' AND is_company_member(company_id)
    )
  );

-- delivery_receipts
DROP POLICY IF EXISTS "insert_dr" ON delivery_receipts;
DROP POLICY IF EXISTS "update_dr" ON delivery_receipts;
DROP POLICY IF EXISTS "insert_dr" ON delivery_receipts;
CREATE POLICY "insert_dr" ON delivery_receipts
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_dr" ON delivery_receipts;
CREATE POLICY "update_dr" ON delivery_receipts
  FOR UPDATE TO authenticated USING (status IN ('draft','in_transit') AND is_company_member(company_id));

-- delivery_receipt_lines (FK column is dr_id)
DROP POLICY IF EXISTS "insert_drl" ON delivery_receipt_lines;
DROP POLICY IF EXISTS "update_drl" ON delivery_receipt_lines;
DROP POLICY IF EXISTS "delete_drl" ON delivery_receipt_lines;
DROP POLICY IF EXISTS "insert_drl" ON delivery_receipt_lines;
CREATE POLICY "insert_drl" ON delivery_receipt_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM delivery_receipts WHERE id = dr_id AND is_company_member(company_id))
  );
DROP POLICY IF EXISTS "update_drl" ON delivery_receipt_lines;
CREATE POLICY "update_drl" ON delivery_receipt_lines
  FOR UPDATE TO authenticated
  USING (
    dr_id IN (
      SELECT id FROM delivery_receipts WHERE status IN ('draft','in_transit') AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_drl" ON delivery_receipt_lines;
CREATE POLICY "delete_drl" ON delivery_receipt_lines
  FOR DELETE TO authenticated
  USING (
    dr_id IN (SELECT id FROM delivery_receipts WHERE status = 'draft' AND is_company_member(company_id))
  );

-- ── Sprint 6+: Compliance documents ───────────────────────────────────────────

-- compliance_ewt_working_papers_headers
DROP POLICY IF EXISTS "insert_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
DROP POLICY IF EXISTS "update_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
DROP POLICY IF EXISTS "delete_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
DROP POLICY IF EXISTS "insert_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
CREATE POLICY "insert_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
CREATE POLICY "update_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "delete_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
CREATE POLICY "delete_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR DELETE TO authenticated USING (status = 'draft' AND is_company_member(company_id));

-- compliance_ewt_working_papers_lines (scope via parent header)
DROP POLICY IF EXISTS "insert_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
DROP POLICY IF EXISTS "update_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
DROP POLICY IF EXISTS "delete_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
DROP POLICY IF EXISTS "insert_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
CREATE POLICY "insert_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM compliance_ewt_working_papers_headers
      WHERE id = header_id AND is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "update_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
CREATE POLICY "update_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR UPDATE TO authenticated
  USING (
    header_id IN (
      SELECT id FROM compliance_ewt_working_papers_headers WHERE is_company_member(company_id)
    )
  );
DROP POLICY IF EXISTS "delete_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
CREATE POLICY "delete_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR DELETE TO authenticated
  USING (
    header_id IN (
      SELECT id FROM compliance_ewt_working_papers_headers WHERE is_company_member(company_id)
    )
  );

-- form_2307_tracking
DROP POLICY IF EXISTS "insert_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "update_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "delete_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "insert_form_2307_tracking" ON form_2307_tracking;
CREATE POLICY "insert_form_2307_tracking" ON form_2307_tracking
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "update_form_2307_tracking" ON form_2307_tracking;
CREATE POLICY "update_form_2307_tracking" ON form_2307_tracking
  FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "delete_form_2307_tracking" ON form_2307_tracking;
CREATE POLICY "delete_form_2307_tracking" ON form_2307_tracking
  FOR DELETE TO authenticated USING (status = 'pending' AND is_company_member(company_id));



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000009_rls_reads_scope.sql                                      │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- RLS READS SCOPE + COMPANIES POLICY + REFERENCE TABLE WRITES
-- Addresses: auto-grant removal, company read scoping, open SELECT policies,
-- broken global reference table writes (tax_codes, vat_codes, atc_codes).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Remove auto-grant-all triggers (from migration 008) ────────────────────
-- These gave every user access to every company, which was the problem we were
-- trying to fix. Replace with a creator-gets-owner trigger on company INSERT.

DROP TRIGGER IF EXISTS trg_new_company_grant_access ON companies;
DROP TRIGGER IF EXISTS trg_new_user_grant_companies ON auth.users;
DROP FUNCTION IF EXISTS fn_grant_all_users_on_new_company();
DROP FUNCTION IF EXISTS fn_grant_new_user_all_companies();

-- ── 2. Creator-becomes-owner trigger ─────────────────────────────────────────
-- When a user creates a company, they are automatically the owner.

CREATE OR REPLACE FUNCTION fn_grant_creator_company_ownership()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
    VALUES (auth.uid(), NEW.id, 'owner', auth.uid())
    ON CONFLICT (user_id, company_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_company_creator_owner ON companies;
CREATE TRIGGER trg_company_creator_owner
  AFTER INSERT ON companies
  FOR EACH ROW EXECUTE FUNCTION fn_grant_creator_company_ownership();

-- ── 3. Helper: admin-level check on a company ────────────────────────────────

CREATE OR REPLACE FUNCTION can_admin_company(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_company_memberships
    WHERE user_id = auth.uid()
      AND company_id = p_company_id
      AND role IN ('owner', 'admin')
  );
$$;

-- ── 4. Fix companies policy ───────────────────────────────────────────────────
-- Was: FOR ALL TO authenticated USING (true)  ← any user could touch any company

DROP POLICY IF EXISTS "authenticated_all_companies" ON companies;

DROP POLICY IF EXISTS "companies_read_own" ON companies;
CREATE POLICY "companies_read_own"   ON companies FOR SELECT TO authenticated
  USING (is_company_member(id));

DROP POLICY IF EXISTS "companies_create" ON companies;
CREATE POLICY "companies_create"     ON companies FOR INSERT TO authenticated
  WITH CHECK (true); -- creator-owner trigger fires automatically

DROP POLICY IF EXISTS "companies_update" ON companies;
CREATE POLICY "companies_update"     ON companies FOR UPDATE TO authenticated
  USING (can_admin_company(id));

DROP POLICY IF EXISTS "companies_delete" ON companies;
CREATE POLICY "companies_delete"     ON companies FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_company_memberships
      WHERE user_id = auth.uid() AND company_id = id AND role = 'owner'
    )
  );

-- ── 5. Scope all company-scoped SELECT policies ───────────────────────────────
-- Replace USING (true) with USING (is_company_member(company_id)) for every
-- company-scoped table. Global reference tables (no company_id) stay open.

-- Sprint 1: org/setup tables (policies added in migration 008)
DROP POLICY IF EXISTS "auth_read_branches"             ON branches;
DROP POLICY IF EXISTS "auth_read_departments"          ON departments;
DROP POLICY IF EXISTS "auth_read_cost_centers"         ON cost_centers;
DROP POLICY IF EXISTS "auth_read_fiscal_years"         ON fiscal_years;
DROP POLICY IF EXISTS "auth_read_fiscal_periods"       ON fiscal_periods;
DROP POLICY IF EXISTS "auth_read_coa"                  ON chart_of_accounts;
DROP POLICY IF EXISTS "auth_read_exchange_rates"       ON exchange_rates;
DROP POLICY IF EXISTS "auth_read_feature_enablement"   ON sys_feature_enablement;
DROP POLICY IF EXISTS "auth_read_number_series"        ON number_series;
DROP POLICY IF EXISTS "auth_read_approval_workflows"   ON approval_workflows;
DROP POLICY IF EXISTS "auth_read_workflow_steps"       ON approval_workflow_steps;
DROP POLICY IF EXISTS "auth_read_approval_instances"   ON approval_instances;

DROP POLICY IF EXISTS "auth_read_branches" ON branches;
CREATE POLICY "auth_read_branches"           ON branches             FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_departments" ON departments;
CREATE POLICY "auth_read_departments"        ON departments          FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_cost_centers" ON cost_centers;
CREATE POLICY "auth_read_cost_centers"       ON cost_centers         FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_read_fiscal_years"       ON fiscal_years         FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_read_fiscal_periods"     ON fiscal_periods       FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_coa" ON chart_of_accounts;
CREATE POLICY "auth_read_coa"                ON chart_of_accounts    FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_exchange_rates" ON exchange_rates;
CREATE POLICY "auth_read_exchange_rates"     ON exchange_rates       FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_feature_enablement" ON sys_feature_enablement;
CREATE POLICY "auth_read_feature_enablement" ON sys_feature_enablement FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_number_series" ON number_series;
CREATE POLICY "auth_read_number_series"      ON number_series        FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_approval_workflows" ON approval_workflows;
CREATE POLICY "auth_read_approval_workflows" ON approval_workflows   FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_workflow_steps" ON approval_workflow_steps;
CREATE POLICY "auth_read_workflow_steps"     ON approval_workflow_steps FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_approval_instances" ON approval_instances;
CREATE POLICY "auth_read_approval_instances" ON approval_instances   FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 1: audit log (company_id nullable — system-level rows visible to all)
DROP POLICY IF EXISTS "auth_read_audit_logs" ON sys_audit_logs;
DROP POLICY IF EXISTS "auth_read_audit_logs" ON sys_audit_logs;
CREATE POLICY "auth_read_audit_logs" ON sys_audit_logs FOR SELECT TO authenticated
  USING (company_id IS NULL OR is_company_member(company_id));

-- Sprint 2/3: master data (policies added in migration 008)
DROP POLICY IF EXISTS "auth_read_ewt_codes"         ON ewt_codes;
DROP POLICY IF EXISTS "auth_read_payment_terms"     ON payment_terms;
DROP POLICY IF EXISTS "auth_read_item_categories"   ON item_categories;
DROP POLICY IF EXISTS "auth_read_uom"               ON units_of_measure;
DROP POLICY IF EXISTS "auth_read_customers"         ON customers;
DROP POLICY IF EXISTS "auth_read_suppliers"         ON suppliers;
DROP POLICY IF EXISTS "auth_read_items"             ON items;

DROP POLICY IF EXISTS "auth_read_ewt_codes" ON ewt_codes;
CREATE POLICY "auth_read_ewt_codes"       ON ewt_codes         FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_payment_terms" ON payment_terms;
CREATE POLICY "auth_read_payment_terms"   ON payment_terms     FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_item_categories" ON item_categories;
CREATE POLICY "auth_read_item_categories" ON item_categories   FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_uom" ON units_of_measure;
CREATE POLICY "auth_read_uom"             ON units_of_measure  FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_customers" ON customers;
CREATE POLICY "auth_read_customers"       ON customers         FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_suppliers" ON suppliers;
CREATE POLICY "auth_read_suppliers"       ON suppliers         FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_items" ON items;
CREATE POLICY "auth_read_items"           ON items             FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 2 tax: compliance setup (policies added in migration 008)
DROP POLICY IF EXISTS "auth_read_fwt_codes"            ON fwt_codes;
DROP POLICY IF EXISTS "auth_read_pt_codes"             ON percentage_tax_codes;
DROP POLICY IF EXISTS "auth_read_compliance_profiles"  ON compliance_profiles;

DROP POLICY IF EXISTS "auth_read_fwt_codes" ON fwt_codes;
CREATE POLICY "auth_read_fwt_codes"          ON fwt_codes            FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_pt_codes" ON percentage_tax_codes;
CREATE POLICY "auth_read_pt_codes"           ON percentage_tax_codes FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "auth_read_compliance_profiles" ON compliance_profiles;
CREATE POLICY "auth_read_compliance_profiles" ON compliance_profiles FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 2 tax: calendar (original migration policy)
DROP POLICY IF EXISTS "auth_read_tax_calendar" ON tax_calendar_events;
DROP POLICY IF EXISTS "auth_read_tax_calendar" ON tax_calendar_events;
CREATE POLICY "auth_read_tax_calendar" ON tax_calendar_events FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 5: sales invoices and lines (original migration policies)
DROP POLICY IF EXISTS "read_sales_invoices" ON sales_invoices;
DROP POLICY IF EXISTS "read_si_lines"       ON sales_invoice_lines;
DROP POLICY IF EXISTS "read_sales_invoices" ON sales_invoices;
CREATE POLICY "read_sales_invoices" ON sales_invoices        FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_si_lines" ON sales_invoice_lines;
CREATE POLICY "read_si_lines"       ON sales_invoice_lines  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 5 AR: receipts, CM, DM and their lines
DROP POLICY IF EXISTS "read_receipts"        ON receipts;
DROP POLICY IF EXISTS "read_receipt_lines"   ON receipt_lines;
DROP POLICY IF EXISTS "read_credit_memos"    ON credit_memos;
DROP POLICY IF EXISTS "read_cm_lines"        ON credit_memo_lines;
DROP POLICY IF EXISTS "read_debit_memos"     ON debit_memos;
DROP POLICY IF EXISTS "read_dm_lines"        ON debit_memo_lines;

DROP POLICY IF EXISTS "read_receipts" ON receipts;
CREATE POLICY "read_receipts"      ON receipts           FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_receipt_lines" ON receipt_lines;
CREATE POLICY "read_receipt_lines" ON receipt_lines      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_credit_memos" ON credit_memos;
CREATE POLICY "read_credit_memos"  ON credit_memos       FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_cm_lines" ON credit_memo_lines;
CREATE POLICY "read_cm_lines"      ON credit_memo_lines  FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_debit_memos" ON debit_memos;
CREATE POLICY "read_debit_memos"   ON debit_memos        FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_dm_lines" ON debit_memo_lines;
CREATE POLICY "read_dm_lines"      ON debit_memo_lines   FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 5 SO/DR: quotations, orders, delivery receipts and their lines
DROP POLICY IF EXISTS "read_sq"   ON sales_quotations;
DROP POLICY IF EXISTS "read_sql"  ON sales_quotation_lines;
DROP POLICY IF EXISTS "read_so"   ON sales_orders;
DROP POLICY IF EXISTS "read_sol"  ON sales_order_lines;
DROP POLICY IF EXISTS "read_dr"   ON delivery_receipts;
DROP POLICY IF EXISTS "read_drl"  ON delivery_receipt_lines;

DROP POLICY IF EXISTS "read_sq" ON sales_quotations;
CREATE POLICY "read_sq"   ON sales_quotations        FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_sql" ON sales_quotation_lines;
CREATE POLICY "read_sql"  ON sales_quotation_lines   FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_so" ON sales_orders;
CREATE POLICY "read_so"   ON sales_orders            FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_sol" ON sales_order_lines;
CREATE POLICY "read_sol"  ON sales_order_lines       FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_dr" ON delivery_receipts;
CREATE POLICY "read_dr"   ON delivery_receipts       FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "read_drl" ON delivery_receipt_lines;
CREATE POLICY "read_drl"  ON delivery_receipt_lines  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 6+: compliance docs
DROP POLICY IF EXISTS "read_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
DROP POLICY IF EXISTS "read_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
CREATE POLICY "read_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- EWT WP lines have no company_id — scope via parent header
DROP POLICY IF EXISTS "read_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
DROP POLICY IF EXISTS "read_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
CREATE POLICY "read_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR SELECT TO authenticated
  USING (
    header_id IN (
      SELECT id FROM compliance_ewt_working_papers_headers WHERE is_company_member(company_id)
    )
  );

DROP POLICY IF EXISTS "read_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "read_form_2307_tracking" ON form_2307_tracking;
CREATE POLICY "read_form_2307_tracking" ON form_2307_tracking
  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- ── 6. Fix global reference tables: add missing write policies ────────────────
-- tax_codes, vat_codes, atc_codes are global BIR reference data (no company_id).
-- The UI has create/edit forms for them but no INSERT/UPDATE policy existed.

DROP POLICY IF EXISTS "auth_write_tax_codes" ON tax_codes;
CREATE POLICY "auth_write_tax_codes"  ON tax_codes  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_tax_codes" ON tax_codes;
CREATE POLICY "auth_update_tax_codes" ON tax_codes  FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_write_vat_codes" ON vat_codes;
CREATE POLICY "auth_write_vat_codes"  ON vat_codes  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_vat_codes" ON vat_codes;
CREATE POLICY "auth_update_vat_codes" ON vat_codes  FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_write_atc_codes" ON atc_codes;
CREATE POLICY "auth_write_atc_codes"  ON atc_codes  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_atc_codes" ON atc_codes;
CREATE POLICY "auth_update_atc_codes" ON atc_codes  FOR UPDATE TO authenticated USING (true);



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000010_posting_rpcs.sql                                         │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- ATOMIC SAVE + STATUS TRANSITION RPCs
-- Replaces multi-round-trip direct table writes with single SECURITY DEFINER
-- transactions. Each RPC validates membership and business rules internally.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Schema additions ──────────────────────────────────────────────────────────

ALTER TABLE sales_invoices
  ADD COLUMN IF NOT EXISTS approved_by  UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at  TIMESTAMPTZ;

-- ── Sales Invoice RPCs ────────────────────────────────────────────────────────

-- fn_save_sales_invoice
-- Atomically saves header + lines in a single transaction.
-- Creates a new SI (status='draft') or updates an existing draft/approved SI.
-- Number generation and fiscal period resolution happen here, not in the UI.
-- Returns the SI UUID.

CREATE OR REPLACE FUNCTION fn_save_sales_invoice(
  p_invoice_id  UUID,     -- null for new, existing id for edit
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_si_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_si_number      TEXT;
  v_fiscal_period  UUID;
  v_current_status TEXT;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- Cross-company integrity: validate branch and customer belong to this company
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  -- Resolve open fiscal period for the document date
  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    -- New document: generate number and insert as draft
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_amount, cwt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id,
      v_branch_id,
      v_si_number,
      (p_header->>'date')::DATE,
      v_fiscal_period,
      (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''),
      NULLIF(p_header->>'memo', ''),
      COALESCE((p_header->>'total_taxable_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_zero_rated_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_exempt_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_vat_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      'draft',
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_si_id;

  ELSE
    -- Existing document: validate it can still be edited
    SELECT id, status INTO v_si_id, v_current_status
    FROM sales_invoices
    WHERE id = p_invoice_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sales invoice not found or access denied';
    END IF;
    IF v_current_status NOT IN ('draft', 'approved') THEN
      RAISE EXCEPTION 'Cannot edit a % sales invoice', v_current_status;
    END IF;

    UPDATE sales_invoices SET
      branch_id                 = v_branch_id,
      date                      = (p_header->>'date')::DATE,
      fiscal_period_id          = v_fiscal_period,
      customer_id               = (p_header->>'customer_id')::UUID,
      customer_name_snapshot    = p_header->>'customer_name_snapshot',
      customer_tin_snapshot     = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id          = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date                  = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code             = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference                 = NULLIF(p_header->>'reference', ''),
      memo                      = NULLIF(p_header->>'memo', ''),
      total_taxable_amount      = COALESCE((p_header->>'total_taxable_amount')::NUMERIC, 0),
      total_zero_rated_amount   = COALESCE((p_header->>'total_zero_rated_amount')::NUMERIC, 0),
      total_exempt_amount       = COALESCE((p_header->>'total_exempt_amount')::NUMERIC, 0),
      total_vat_amount          = COALESCE((p_header->>'total_vat_amount')::NUMERIC, 0),
      total_amount              = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      cwt_amount_expected       = NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      updated_at                = NOW(),
      updated_by                = auth.uid()
    WHERE id = v_si_id;
  END IF;

  -- Replace lines atomically
  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  INSERT INTO sales_invoice_lines (
    sales_invoice_id, company_id, line_number, item_id, description,
    quantity, uom_id, unit_price, discount_percent, discount_amount,
    net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
    created_by, updated_by
  )
  SELECT
    v_si_id,
    v_company_id,
    (l->>'line_number')::INT,
    NULLIF(l->>'item_id', '')::UUID,
    l->>'description',
    COALESCE((l->>'quantity')::NUMERIC, 1),
    NULLIF(l->>'uom_id', '')::UUID,
    COALESCE((l->>'unit_price')::NUMERIC, 0),
    COALESCE((l->>'discount_percent')::NUMERIC, 0),
    COALESCE((l->>'discount_amount')::NUMERIC, 0),
    COALESCE((l->>'net_amount')::NUMERIC, 0),
    NULLIF(l->>'vat_code_id', '')::UUID,
    COALESCE((l->>'vat_amount')::NUMERIC, 0),
    COALESCE((l->>'total_amount')::NUMERIC, 0),
    NULLIF(l->>'revenue_account_id', '')::UUID,
    auth.uid(),
    auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE NULLIF(TRIM(l->>'description'), '') IS NOT NULL;

  RETURN v_si_id;
END;
$$;

-- fn_approve_sales_invoice
-- Transitions a draft SI to approved.
-- Future: if an approval_workflow is configured, route to the approver instead.

CREATE OR REPLACE FUNCTION fn_approve_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft invoices can be approved (current status: %)', v_rec.status;
  END IF;

  UPDATE sales_invoices
  SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- fn_post_sales_invoice
-- Transitions an approved SI to posted. Records who posted and when.
-- GL journal entry creation is stubbed here — implement in Sprint 9 GL module.

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved invoices can be posted (current status: %)', v_rec.status;
  END IF;

  -- Sprint 9 GL stub: when the GL module is built, create journal entries here:
  --   DR  Accounts Receivable (customer control account)  = total_amount
  --   CR  Revenue accounts (by line, from revenue_account_id)
  --   CR  VAT Payable (output VAT)                        = total_vat_amount
  --   Then: UPDATE sales_invoices SET journal_entry_id = <new_je_id>

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- fn_void_sales_invoice
-- Cancels a sales invoice regardless of current status (draft/approved/posted).
-- SECURITY DEFINER bypasses the UPDATE policy which only allows draft/approved edits.
-- BIR rule: voided SI numbers are never reused (enforced at number-series level).

CREATE OR REPLACE FUNCTION fn_void_sales_invoice(
  p_invoice_id    UUID,
  p_void_reason_id UUID,
  p_memo          TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Invoice is already voided';
  END IF;

  IF p_void_reason_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid or inactive void reason';
  END IF;

  UPDATE sales_invoices
  SET
    status          = 'cancelled',
    void_reason_id  = p_void_reason_id,
    memo            = COALESCE(NULLIF(p_memo, ''), v_rec.memo),
    updated_by      = auth.uid(),
    updated_at      = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- ── Receipt RPCs ──────────────────────────────────────────────────────────────

-- fn_save_receipt
-- Atomically saves receipt header + lines. Returns receipt UUID.

CREATE OR REPLACE FUNCTION fn_save_receipt(
  p_receipt_id  UUID,
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_receipt_number TEXT;
  v_current_status TEXT;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  IF p_receipt_id IS NULL THEN
    v_receipt_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

    INSERT INTO receipts (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      receipt_number, receipt_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_cwt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id,
      v_branch_id,
      (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number,
      (p_header->>'receipt_date')::DATE,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''),
      'draft',
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_receipt_id;

  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts WHERE id = p_receipt_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Receipt not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id              = v_branch_id,
      customer_id            = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot  = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date           = (p_header->>'receipt_date')::DATE,
      payment_mode_id        = (p_header->>'payment_mode_id')::UUID,
      reference_number       = NULLIF(p_header->>'reference_number', ''),
      bank_account_id        = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount           = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt              = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks                = NULLIF(p_header->>'remarks', ''),
      updated_at             = NOW(),
      updated_by             = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  -- Replace lines atomically
  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount, forex_adjustment, atc_code_id,
    created_by, updated_by
  )
  SELECT
    v_receipt_id,
    v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(),
    auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0;

  RETURN v_receipt_id;
END;
$$;

-- fn_post_receipt
-- Transitions a draft receipt to posted.
-- Sprint 9 GL stub: when GL is built, create journal entries here.

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec receipts%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  -- Sprint 9 GL stub: when GL is built, create journal entries here:
  --   DR  Cash/Bank (from payment_mode/bank_account)  = total_amount
  --   DR  EWT Withheld (if total_cwt > 0)             = total_cwt
  --   CR  Accounts Receivable (customer)              = total_amount + total_cwt

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- fn_bounce_receipt
-- Marks a posted receipt as bounced (dishonored cheque etc.).
-- SECURITY DEFINER bypasses the UPDATE policy (posted rows cannot be updated directly).

CREATE OR REPLACE FUNCTION fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec receipts%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted receipts can be marked as bounced (current status: %)', v_rec.status;
  END IF;

  UPDATE receipts
  SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- ── Grant execute to authenticated users ──────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_save_sales_invoice(UUID, JSONB, JSONB)    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_sales_invoice(UUID)               TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_sales_invoice(UUID, UUID, TEXT)      TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bounce_receipt(UUID)                      TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000011_audit_triggers.sql                                       │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- REAL AUDIT LOG TRIGGERS
-- Replaces manual log calls with automatic DB-level triggers on key tables.
-- Uses sys_audit_logs (id, company_id, table_name, record_id, action,
-- old_data, new_data, changed_by, changed_at).
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_record     JSONB;
  v_company_id UUID;
BEGIN
  -- Works for INSERT, UPDATE, DELETE
  v_record := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;

  -- companies table uses its own 'id' as the tenant identifier
  v_company_id := CASE
    WHEN TG_TABLE_NAME = 'companies' THEN (v_record->>'id')::UUID
    ELSE (v_record->>'company_id')::UUID
  END;

  INSERT INTO sys_audit_logs (
    company_id,
    table_name,
    record_id,
    action,
    old_data,
    new_data,
    changed_by
  ) VALUES (
    v_company_id,
    TG_TABLE_NAME,
    (v_record->>'id')::UUID,
    TG_OP,
    CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
    auth.uid()
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ── Apply to key tables ───────────────────────────────────────────────────────
-- Limit to high-value tables: master data, transactional headers.
-- Line-level changes are captured implicitly via parent document headers.

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'companies',
    'branches',
    'customers',
    'suppliers',
    'items',
    'sales_invoices',
    'receipts',
    'credit_memos',
    'debit_memos',
    'sales_orders',
    'delivery_receipts'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
       CREATE TRIGGER trg_audit_%1$s
         AFTER INSERT OR UPDATE OR DELETE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();',
      t
    );
  END LOOP;
END;
$$;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000012_fn_numbering_hardening.sql                               │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- NUMBER SERIES FUNCTION HARDENING
-- Adds: SET search_path = public (prevents search_path injection),
--       membership check (prevents cross-company sequence exhaustion),
--       restricted execute grant (revoke from PUBLIC, grant to authenticated).
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_next_document_number(
  p_company_id    UUID,
  p_branch_id     UUID,
  p_document_code TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_series    number_series%ROWTYPE;
  v_seq       BIGINT;
  v_padded    TEXT;
  v_number    TEXT;
BEGIN
  -- Membership check: callers can only generate numbers for their own company
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_series
  FROM number_series
  WHERE company_id    = p_company_id
    AND branch_id     = p_branch_id
    AND document_code = p_document_code
    AND is_active     = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active number series for document code "%" in this branch. Set one up under Number Series Setup.', p_document_code;
  END IF;

  v_seq := v_series.current_sequence + 1;

  UPDATE number_series
  SET current_sequence = v_seq, updated_at = NOW()
  WHERE id = v_series.id;

  v_padded := LPAD(v_seq::TEXT, v_series.padding, '0');
  v_number := CONCAT(
    COALESCE(v_series.prefix, ''),
    v_padded,
    COALESCE(v_series.suffix, '')
  );

  RETURN v_number;
END;
$$;

-- Restrict execution: revoke from PUBLIC (default implicit grant),
-- then grant only to authenticated users.
REVOKE EXECUTE ON FUNCTION fn_next_document_number(UUID, UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_next_document_number(UUID, UUID, TEXT) TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000013_gl_core.sql                                              │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- GL CORE: Journal Entries + Company Accounting Config
-- "Posted" now means posted to the books with a balanced journal entry.
-- Posting RPCs require company_accounting_config to be set up before any
-- document can move to posted status.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── company_accounting_config ─────────────────────────────────────────────────
-- Stores the canonical GL account IDs needed for automated journal entry creation.
-- Each company must configure this before posting is allowed.

CREATE TABLE IF NOT EXISTS company_accounting_config (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL UNIQUE REFERENCES companies(id),
  ar_account_id          UUID        REFERENCES chart_of_accounts(id),
  vat_payable_account_id UUID        REFERENCES chart_of_accounts(id),
  ewt_withheld_account_id UUID       REFERENCES chart_of_accounts(id),
  default_cash_account_id UUID       REFERENCES chart_of_accounts(id),
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_company_accounting_config_updated_at ON company_accounting_config;
CREATE TRIGGER trg_company_accounting_config_updated_at
  BEFORE UPDATE ON company_accounting_config
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE company_accounting_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cac_read" ON company_accounting_config;
CREATE POLICY "cac_read"   ON company_accounting_config FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "cac_insert" ON company_accounting_config;
CREATE POLICY "cac_insert" ON company_accounting_config FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
DROP POLICY IF EXISTS "cac_update" ON company_accounting_config;
CREATE POLICY "cac_update" ON company_accounting_config FOR UPDATE TO authenticated USING (can_admin_company(company_id));

-- ── journal_entries ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS journal_entries (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID        NOT NULL REFERENCES companies(id),
  branch_id               UUID        REFERENCES branches(id),
  je_number               TEXT        NOT NULL,
  je_date                 DATE        NOT NULL,
  fiscal_period_id        UUID        REFERENCES fiscal_periods(id),
  description             TEXT,
  reference_doc_type      TEXT        CHECK (reference_doc_type IN ('SI','OR','CM','DM','MANUAL')),
  reference_doc_id        UUID,
  status                  TEXT        NOT NULL DEFAULT 'posted'
                                      CHECK (status IN ('draft','posted','reversed')),
  total_debit             NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_credit            NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, je_number)
);

CREATE TABLE IF NOT EXISTS journal_entry_lines (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  je_id         UUID          NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  company_id    UUID          NOT NULL REFERENCES companies(id),
  line_number   INT           NOT NULL,
  account_id    UUID          NOT NULL REFERENCES chart_of_accounts(id),
  description   TEXT,
  debit_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  credit_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  updated_by    UUID,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (debit_amount >= 0 AND credit_amount >= 0),
  CHECK (debit_amount = 0 OR credit_amount = 0)
);

CREATE INDEX IF NOT EXISTS idx_je_company_date ON journal_entries (company_id, je_date DESC);
CREATE INDEX IF NOT EXISTS idx_jel_je_id       ON journal_entry_lines (je_id);
CREATE INDEX IF NOT EXISTS idx_jel_account_id  ON journal_entry_lines (account_id);

DROP TRIGGER IF EXISTS trg_journal_entries_updated_at ON journal_entries;
CREATE TRIGGER trg_journal_entries_updated_at
  BEFORE UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_journal_entry_lines_updated_at ON journal_entry_lines;
CREATE TRIGGER trg_journal_entry_lines_updated_at
  BEFORE UPDATE ON journal_entry_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE journal_entries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry_lines  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "je_read" ON journal_entries;
CREATE POLICY "je_read"   ON journal_entries     FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "jel_read" ON journal_entry_lines;
CREATE POLICY "jel_read"  ON journal_entry_lines FOR SELECT TO authenticated
  USING (je_id IN (SELECT id FROM journal_entries WHERE is_company_member(company_id)));

-- ── Update fn_post_sales_invoice: create real journal entry ───────────────────

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec      sales_invoices%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_line_no  INT := 1;
  v_total_dr NUMERIC(15,2) := 0;
  v_total_cr NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved invoices can be posted (current status: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.date AND end_date >= v_rec.date AND is_locked = false LIMIT 1;

  -- Create journal entry header
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date, v_fp_id,
    'Sales Invoice ' || v_rec.si_number || ' — ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Receivable for total invoice amount
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id, 'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());
  v_line_no := 2;

  -- CR: Revenue per line (net_amount per revenue account)
  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum, sil.description AS ln_desc
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id, 'Revenue — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_line_no := v_line_no + 1;
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  -- CR: VAT Payable if any
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_rec.si_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  -- Verify the entry is balanced (debit = credit); if not, surface the issue
  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check that all lines have revenue accounts assigned.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── Update fn_post_receipt: create real journal entry ─────────────────────────

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       receipts%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ar_cr     NUMERIC(15,2);
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_cwt > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in GL Posting Configuration.';
  END IF;

  -- Determine cash/bank account: prefer bank_account_id (already a COA id), else default_cash_account_id
  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.receipt_date AND end_date >= v_rec.receipt_date AND is_locked = false LIMIT 1;

  v_ar_cr := v_rec.total_amount + v_rec.total_cwt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date, v_fp_id,
    'Official Receipt ' || v_rec.receipt_number || ' — ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id, 'posted',
    v_ar_cr, v_ar_cr,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Cash / Bank
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cash_acct, 'Cash received — ' || v_rec.receipt_number, v_rec.total_amount, 0, auth.uid(), auth.uid());

  -- DR: EWT Withheld (if applicable)
  IF v_rec.total_cwt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 2, v_cfg.ewt_withheld_account_id, 'EWT withheld — ' || v_rec.receipt_number, v_rec.total_cwt, 0, auth.uid(), auth.uid());
  END IF;

  -- CR: Accounts Receivable (total cash + CWT clears the full invoice)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
          v_cfg.ar_account_id, 'AR cleared — ' || v_rec.receipt_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- Grant execute
GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID)        TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000014_hardening.sql                                            │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- HARDENING: ATC consolidation, AR view CWT fix, server-side computation,
-- approved-edit lock, over-application guard, tax calendar RPC,
-- audit line triggers, global tax write restriction, membership cleanup note.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Broaden atc_codes tax_category check to include 'pt' ──────────────────
ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_tax_type_check;
ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_tax_category_check;
ALTER TABLE atc_codes ADD CONSTRAINT atc_codes_tax_category_check
  CHECK (tax_category IN ('ewt', 'fwt', 'pt'));

-- ── 2. Consolidate ref_atc_codes into atc_codes ───────────────────────────────
-- Insert ref_atc_codes rows that don't already exist in atc_codes by code.
-- Uses the ref_atc_codes UUID so FK references stay valid after FK migration.

-- Fresh-database replay guard: 20260629000014_hardening.sql already consolidated
-- and dropped ref_atc_codes, so this block only runs when the table still exists.
DO $$
BEGIN
  IF to_regclass('public.ref_atc_codes') IS NOT NULL THEN
    INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active)
    SELECT r.id, r.atc_code, r.description, 'ewt', r.tax_rate, r.is_active
    FROM ref_atc_codes r
    WHERE NOT EXISTS (SELECT 1 FROM atc_codes a WHERE a.code = r.atc_code);

    -- For codes that exist in both (same code, different UUIDs):
    -- remap receipt_lines.atc_code_id from ref_atc_codes UUID → atc_codes UUID
    UPDATE receipt_lines rl
    SET atc_code_id = (
      SELECT a.id FROM atc_codes a
      INNER JOIN ref_atc_codes r ON r.atc_code = a.code
      WHERE r.id = rl.atc_code_id
    )
    WHERE rl.atc_code_id IN (SELECT id FROM ref_atc_codes);

    -- Same for form_2307_tracking
    UPDATE form_2307_tracking ft
    SET atc_code_id = (
      SELECT a.id FROM atc_codes a
      INNER JOIN ref_atc_codes r ON r.atc_code = a.code
      WHERE r.id = ft.atc_code_id
    )
    WHERE ft.atc_code_id IN (SELECT id FROM ref_atc_codes);
  END IF;
END;
$$;

-- Migrate receipt_lines FK from ref_atc_codes → atc_codes
ALTER TABLE receipt_lines
  DROP CONSTRAINT IF EXISTS receipt_lines_atc_code_id_fkey,
  ADD CONSTRAINT receipt_lines_atc_code_id_fkey FOREIGN KEY (atc_code_id) REFERENCES atc_codes(id);

-- Migrate form_2307_tracking FK
ALTER TABLE form_2307_tracking
  DROP CONSTRAINT IF EXISTS form_2307_tracking_atc_code_id_fkey,
  ADD CONSTRAINT form_2307_tracking_atc_code_id_fkey FOREIGN KEY (atc_code_id) REFERENCES atc_codes(id);

-- Drop ref_atc_codes (policies must be dropped first).
-- Fresh-database replay guard: DROP POLICY errors when the table is already gone.
DO $$
BEGIN
  IF to_regclass('public.ref_atc_codes') IS NOT NULL THEN
    DROP POLICY IF EXISTS "read_ref_atc_codes" ON ref_atc_codes;
    DROP TABLE ref_atc_codes;
  END IF;
END;
$$;

-- ── 3. Fix vw_customer_ledger: receipt credit should clear total_amount + total_cwt ─
-- AR is debited at total_amount + total_cwt when posting (CWT clears AR too).
-- The ledger must credit the same amount so AR aging and ledger agree.

CREATE OR REPLACE VIEW vw_customer_ledger AS
SELECT
  si.company_id, si.customer_id, si.date AS transaction_date,
  'SI'::TEXT AS doc_type, si.si_number AS doc_number,
  COALESCE(si.memo, 'Sales Invoice') AS description,
  si.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  si.created_at
FROM sales_invoices si
WHERE si.status = 'posted'

UNION ALL

SELECT
  r.company_id, r.customer_id, r.receipt_date AS transaction_date,
  'OR'::TEXT AS doc_type, r.receipt_number AS doc_number,
  COALESCE(r.remarks, 'Official Receipt') AS description,
  0::NUMERIC AS debit_amount, (r.total_amount + r.total_cwt) AS credit_amount,
  r.created_at
FROM receipts r
WHERE r.status = 'posted'

UNION ALL

SELECT
  cm.company_id, cm.customer_id, cm.cm_date AS transaction_date,
  'CM'::TEXT AS doc_type, cm.cm_number AS doc_number,
  COALESCE(cm.remarks, 'Credit Memo') AS description,
  0::NUMERIC AS debit_amount, cm.total_amount AS credit_amount,
  cm.created_at
FROM credit_memos cm
WHERE cm.status IN ('approved', 'applied')

UNION ALL

SELECT
  dm.company_id, dm.customer_id, dm.dm_date AS transaction_date,
  'DM'::TEXT AS doc_type, dm.dm_number AS doc_number,
  COALESCE(dm.remarks, 'Debit Memo') AS description,
  dm.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  dm.created_at
FROM debit_memos dm
WHERE dm.status IN ('approved', 'paid');

-- ── 4. Restrict global tax table writes to company admins ─────────────────────
-- Any authenticated user could previously modify BIR reference data.
-- Restrict INSERT/UPDATE to users who admin at least one company.
-- This is a pragmatic check until a system-admin role is added.

CREATE OR REPLACE FUNCTION is_any_company_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_company_memberships
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  );
$$;

DROP POLICY IF EXISTS "auth_write_tax_codes"  ON tax_codes;
DROP POLICY IF EXISTS "auth_update_tax_codes" ON tax_codes;
DROP POLICY IF EXISTS "auth_write_vat_codes"  ON vat_codes;
DROP POLICY IF EXISTS "auth_update_vat_codes" ON vat_codes;
DROP POLICY IF EXISTS "auth_write_atc_codes"  ON atc_codes;
DROP POLICY IF EXISTS "auth_update_atc_codes" ON atc_codes;

DROP POLICY IF EXISTS "admin_write_tax_codes" ON tax_codes;
CREATE POLICY "admin_write_tax_codes"  ON tax_codes  FOR INSERT TO authenticated WITH CHECK (is_any_company_admin());
DROP POLICY IF EXISTS "admin_update_tax_codes" ON tax_codes;
CREATE POLICY "admin_update_tax_codes" ON tax_codes  FOR UPDATE TO authenticated USING (is_any_company_admin());
DROP POLICY IF EXISTS "admin_write_vat_codes" ON vat_codes;
CREATE POLICY "admin_write_vat_codes"  ON vat_codes  FOR INSERT TO authenticated WITH CHECK (is_any_company_admin());
DROP POLICY IF EXISTS "admin_update_vat_codes" ON vat_codes;
CREATE POLICY "admin_update_vat_codes" ON vat_codes  FOR UPDATE TO authenticated USING (is_any_company_admin());
DROP POLICY IF EXISTS "admin_write_atc_codes" ON atc_codes;
CREATE POLICY "admin_write_atc_codes"  ON atc_codes  FOR INSERT TO authenticated WITH CHECK (is_any_company_admin());
DROP POLICY IF EXISTS "admin_update_atc_codes" ON atc_codes;
CREATE POLICY "admin_update_atc_codes" ON atc_codes  FOR UPDATE TO authenticated USING (is_any_company_admin());

-- ── 5. fn_mark_tax_event_filed ────────────────────────────────────────────────
-- Direct update of tax_calendar_events was blocked by status update policies.
-- This SECURITY DEFINER RPC validates membership and handles the transition.

CREATE OR REPLACE FUNCTION fn_mark_tax_event_filed(
  p_event_id      UUID,
  p_date_filed    DATE,
  p_efps_ref      TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev tax_calendar_events%ROWTYPE;
BEGIN
  SELECT * INTO v_ev FROM tax_calendar_events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tax calendar event not found'; END IF;
  IF NOT is_company_member(v_ev.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_ev.status = 'filed' THEN RAISE EXCEPTION 'Event is already filed'; END IF;

  UPDATE tax_calendar_events
  SET status = 'filed',
      date_filed = COALESCE(p_date_filed, CURRENT_DATE),
      efps_reference_no = p_efps_ref,
      updated_at = NOW()
  WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_mark_tax_event_filed(UUID, DATE, TEXT) TO authenticated;

-- ── 6. Extend audit triggers to transactional line tables ─────────────────────

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'sales_invoice_lines',
    'receipt_lines',
    'credit_memo_lines',
    'debit_memo_lines',
    'sales_order_lines',
    'delivery_receipt_lines'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
       CREATE TRIGGER trg_audit_%1$s
         AFTER INSERT OR UPDATE OR DELETE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();',
      t
    );
  END LOOP;
END;
$$;

-- ── 7. fn_save_sales_invoice: reject approved, server-side VAT computation ────
-- Approved SIs cannot be edited. Revert to draft first via fn_revert_si_to_draft.
-- Server now recomputes all line amounts from source data; UI preview values
-- are accepted only for display purposes, never trusted for the ledger.

CREATE OR REPLACE FUNCTION fn_save_sales_invoice(
  p_invoice_id  UUID,
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_si_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_si_number      TEXT;
  v_fiscal_period  UUID;
  v_current_status TEXT;
  -- Line computation
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  -- Totals
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_amount, cwt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_si_number, (p_header->>'date')::DATE, v_fiscal_period,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0, -- totals computed below
      NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_si_id;

  ELSE
    SELECT id, status INTO v_si_id, v_current_status
    FROM sales_invoices WHERE id = p_invoice_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sales invoice not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % sales invoice. Revert to draft first.', v_current_status;
    END IF;

    UPDATE sales_invoices SET
      branch_id = v_branch_id, date = (p_header->>'date')::DATE, fiscal_period_id = v_fiscal_period,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_vat_amount = 0, total_amount = 0, -- recomputed below
      cwt_amount_expected = NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_si_id;
  END IF;

  -- Replace lines and compute server-side totals
  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    -- Look up VAT classification and rate for this line
    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);

    -- Recompute amounts from source — UI preview values not trusted
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    -- Accumulate header totals
    CASE v_vat_class
      WHEN 'regular'   THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number,
      item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, vat_amount, total_amount,
      revenue_account_id, created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID,
      v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0),
      v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line item is required';
  END IF;

  -- Write server-computed totals back to header
  UPDATE sales_invoices SET
    total_taxable_amount    = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount     = v_exempt,
    total_vat_amount        = v_total_vat,
    total_amount            = v_grand_total,
    updated_at              = NOW()
  WHERE id = v_si_id;

  RETURN v_si_id;
END;
$$;

-- ── 8. fn_revert_si_to_draft ──────────────────────────────────────────────────
-- Allows an approved (not yet posted/cancelled) SI to return to draft so
-- it can be edited. Clears the approval record.

CREATE OR REPLACE FUNCTION fn_revert_si_to_draft(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved invoices can be reverted to draft (current status: %)', v_rec.status;
  END IF;

  UPDATE sales_invoices
  SET status = 'draft', approved_by = NULL, approved_at = NULL,
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_sales_invoice(UUID, JSONB, JSONB)  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_revert_si_to_draft(UUID)                TO authenticated;

-- ── 9. fn_save_receipt: add over-application check ────────────────────────────

CREATE OR REPLACE FUNCTION fn_save_receipt(
  p_receipt_id  UUID,
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_receipt_number TEXT;
  v_current_status TEXT;
  -- Line validation
  v_line           JSONB;
  v_inv_id         UUID;
  v_pay_amt        NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN RAISE EXCEPTION 'Branch does not belong to this company'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id
  ) THEN RAISE EXCEPTION 'Customer does not belong to this company'; END IF;

  -- Validate each line: no over-application, no cross-company invoices
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_inv_id := NULLIF(v_line->>'invoice_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    CONTINUE WHEN v_inv_id IS NULL OR v_pay_amt <= 0;

    -- Verify invoice belongs to this company
    IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE id = v_inv_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
    END IF;

    -- Compute outstanding balance (total - already applied payments, excluding current receipt)
    SELECT si.total_amount - COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
    INTO v_outstanding
    FROM sales_invoices si
    LEFT JOIN receipt_lines rl
      ON rl.invoice_id = si.id
      AND rl.receipt_id != COALESCE(p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND rl.receipt_id IN (SELECT id FROM receipts WHERE status != 'bounced')
    WHERE si.id = v_inv_id
    GROUP BY si.total_amount;

    IF v_pay_amt + COALESCE((v_line->>'cwt_amount')::NUMERIC, 0) > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % exceeds outstanding balance of % for invoice', v_pay_amt, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_receipt_id IS NULL THEN
    v_receipt_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

    INSERT INTO receipts (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      receipt_number, receipt_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_cwt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number, (p_header->>'receipt_date')::DATE,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''), NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''), 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_receipt_id;

  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts WHERE id = p_receipt_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id = v_branch_id, customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date = (p_header->>'receipt_date')::DATE,
      payment_mode_id = (p_header->>'payment_mode_id')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, forex_adjustment, atc_code_id, created_by, updated_by)
  SELECT v_receipt_id, v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0;

  RETURN v_receipt_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB) TO authenticated;

-- ── 10. Membership cleanup documentation ──────────────────────────────────────
-- Migration 008 bootstrapped all users × companies as 'admin'.
-- Migration 009 removed the auto-grant triggers, but existing memberships remain.
-- To remediate in a production environment, identify and remove excess memberships:
--
-- MANUAL REVIEW (do not run blindly — may lock legitimate users out):
-- DELETE FROM user_company_memberships ucm
-- WHERE role = 'admin'
--   AND NOT EXISTS (
--     SELECT 1 FROM companies c WHERE c.id = ucm.company_id AND c.created_by = ucm.user_id
--   )
--   AND granted_by = ucm.user_id; -- bootstrap pattern: user granted themselves
--
-- After cleanup, each user should only have memberships for companies they own or
-- were explicitly invited to. The creator-owner trigger (migration 009) handles
-- new companies going forward.



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000015_cm_dm_rpcs.sql                                           │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- CREDIT MEMO AND DEBIT MEMO RPCS
-- fn_save_credit_memo, fn_save_debit_memo and their status transition RPCs.
-- Replaces multi-round-trip direct writes in CreditMemosPage/DebitMemosPage.
-- Server recomputes totals from line data; browser values not trusted.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── fn_save_credit_memo ───────────────────────────────────────────────────────
-- Atomically saves CM header + lines and transitions to p_next_status.
-- Status rules: draft → approved → applied; approved → draft (Return to Draft)
-- Returns CM UUID.

CREATE OR REPLACE FUNCTION fn_save_credit_memo(
  p_cm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_cm_number      TEXT;
  v_current_status TEXT;
  -- Line computation
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  -- Totals
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- Validate status transition
  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  IF p_cm_id IS NULL THEN
    v_cm_number := fn_next_document_number(v_company_id, v_branch_id, 'CM');

    INSERT INTO credit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      invoice_id, cm_number, cm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'invoice_id', '')::UUID,
      v_cm_number, (p_header->>'cm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0,
      p_next_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_cm_id;

  ELSE
    SELECT id, status INTO v_cm_id, v_current_status
    FROM credit_memos WHERE id = p_cm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found or access denied'; END IF;

    -- Validate allowed transitions
    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','applied','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','applied','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition credit memo from % to %', v_current_status, p_next_status;
    END IF;

    UPDATE credit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      invoice_id = NULLIF(p_header->>'invoice_id', '')::UUID,
      cm_date = (p_header->>'cm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0, -- recomputed below
      status = p_next_status,
      posted_at = CASE WHEN p_next_status = 'applied' AND v_current_status != 'applied' THEN NOW() ELSE posted_at END,
      posted_by = CASE WHEN p_next_status = 'applied' AND v_current_status != 'applied' THEN auth.uid() ELSE posted_by END,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  -- Replace lines with server-computed amounts
  DELETE FROM credit_memo_lines WHERE credit_memo_id = v_cm_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    v_total_net := v_total_net + v_net;
    v_total_vat := v_total_vat + v_vat_amt;
    v_total_amt := v_total_amt + v_total_line;

    INSERT INTO credit_memo_lines (
      credit_memo_id, company_id, line_number,
      invoice_line_id, item_id, description, quantity, unit_price,
      net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_cm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'invoice_line_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_qty, v_price,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE credit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    updated_at = NOW()
  WHERE id = v_cm_id;

  RETURN v_cm_id;
END;
$$;

-- ── fn_save_debit_memo ────────────────────────────────────────────────────────
-- Atomically saves DM header + lines and transitions to p_next_status.
-- Status: draft → approved → paid; approved → draft (Return to Draft)

CREATE OR REPLACE FUNCTION fn_save_debit_memo(
  p_dm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_dm_number      TEXT;
  v_current_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_amount         NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF p_next_status NOT IN ('draft','approved','paid','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  IF p_dm_id IS NULL THEN
    v_dm_number := fn_next_document_number(v_company_id, v_branch_id, 'DM-S');

    INSERT INTO debit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      source_doc_type, source_doc_id, dm_number, dm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'source_doc_type', ''),
      NULLIF(p_header->>'source_doc_id', '')::UUID,
      v_dm_number, (p_header->>'dm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0,
      p_next_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_dm_id;

  ELSE
    SELECT id, status INTO v_dm_id, v_current_status
    FROM debit_memos WHERE id = p_dm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found or access denied'; END IF;

    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','paid','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','paid','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition debit memo from % to %', v_current_status, p_next_status;
    END IF;

    UPDATE debit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      source_doc_type = NULLIF(p_header->>'source_doc_type', ''),
      source_doc_id = NULLIF(p_header->>'source_doc_id', '')::UUID,
      dm_date = (p_header->>'dm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      status = p_next_status,
      posted_at = CASE WHEN p_next_status = 'paid' AND v_current_status != 'paid' THEN NOW() ELSE posted_at END,
      posted_by = CASE WHEN p_next_status = 'paid' AND v_current_status != 'paid' THEN auth.uid() ELSE posted_by END,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_dm_id;
  END IF;

  DELETE FROM debit_memo_lines WHERE debit_memo_id = v_dm_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_amount    := GREATEST(COALESCE((v_line->>'amount')::NUMERIC, 0), 0);
    v_vat_amt   := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_amount * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_amount + v_vat_amt;

    v_total_net := v_total_net + v_amount;
    v_total_vat := v_total_vat + v_vat_amt;
    v_total_amt := v_total_amt + v_total_line;

    INSERT INTO debit_memo_lines (
      debit_memo_id, company_id, line_number,
      account_id, item_id, description, amount,
      vat_code_id, vat_amount, total_amount,
      created_by, updated_by
    ) VALUES (
      v_dm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'account_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_amount,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE debit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    updated_at = NOW()
  WHERE id = v_dm_id;

  RETURN v_dm_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_credit_memo(UUID, JSONB, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_debit_memo(UUID, JSONB, JSONB, TEXT)  TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000016_cash_sales.sql                                           │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- CASH SALES: is_cash_sale flag + atomic fn_save_cash_sale RPC
-- Cash Sale = SI posted immediately with a matching OR, both in one transaction.
-- Requires company_accounting_config (same as fn_post_sales_invoice).
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS is_cash_sale BOOLEAN NOT NULL DEFAULT false;

-- Document series for Cash Sales uses separate prefix 'CS' so BIR cash sales
-- journal is distinct from credit sales journal.
-- (Add 'CS' to document_series via existing number series setup.)

CREATE OR REPLACE FUNCTION fn_save_cash_sale(
  p_header       JSONB,  -- SI header fields + bank_account_id + payment_mode_id
  p_lines        JSONB,  -- SI line items
  p_cwt_amount   NUMERIC DEFAULT 0
)
RETURNS JSONB            -- { si_id, receipt_id, si_number, receipt_number }
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id    UUID;
  v_branch_id     UUID;
  v_si_id         UUID;
  v_receipt_id    UUID;
  v_si_number     TEXT;
  v_or_number     TEXT;
  v_cfg           company_accounting_config%ROWTYPE;
  v_cash_acct     UUID;
  v_fp_id         UUID;
  v_je_si_id      UUID;
  v_je_or_id      UUID;
  v_line          JSONB;
  v_vat_class     TEXT;
  v_vat_rate      NUMERIC(5,2);
  v_qty           NUMERIC(15,4);
  v_price         NUMERIC(15,4);
  v_disc          NUMERIC(15,2);
  v_net           NUMERIC(15,2);
  v_vat_amt       NUMERIC(15,2);
  v_total_line    NUMERIC(15,2);
  v_line_no       INT;
  v_taxable       NUMERIC(15,2) := 0;
  v_zero_rated    NUMERIC(15,2) := 0;
  v_exempt        NUMERIC(15,2) := 0;
  v_total_vat     NUMERIC(15,2) := 0;
  v_grand_total   NUMERIC(15,2) := 0;
  v_has_lines     BOOLEAN := false;
  v_total_cr      NUMERIC(15,2) := 0;
  v_rev_line      RECORD;
  v_rev_line_no   INT;
  v_ar_cr         NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- GL config is mandatory for cash sales (must post immediately)
  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in Setup → GL Posting Configuration.';
  END IF;
  IF p_cwt_amount > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in Setup → GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(
    NULLIF(p_header->>'bank_account_id', '')::UUID,
    v_cfg.default_cash_account_id
  );
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No cash/bank account specified and no default cash account configured.';
  END IF;

  -- Resolve fiscal period
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= (p_header->>'date')::DATE
    AND end_date >= (p_header->>'date')::DATE AND is_locked = false LIMIT 1;

  -- Generate numbers
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Create SI header
  INSERT INTO sales_invoices (
    company_id, branch_id, si_number, date, fiscal_period_id,
    customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
    payment_terms_id, due_date, currency_code, reference, memo,
    total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
    total_vat_amount, total_amount, cwt_amount_expected,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, v_si_number, (p_header->>'date')::DATE, v_fp_id,
    (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot', ''),
    NULLIF(p_header->>'customer_address_snapshot', ''),
    NULLIF(p_header->>'payment_terms_id', '')::UUID,
    (p_header->>'date')::DATE, -- due immediately for cash sale
    COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
    NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
    0, 0, 0, 0, 0, p_cwt_amount,
    true, 'approved', auth.uid(), auth.uid() -- skip draft, go straight to approved
  ) RETURNING id INTO v_si_id;

  -- Insert lines with server-side VAT computation
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount, net_amount, vat_code_id, vat_amount, total_amount,
      revenue_account_id, created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID, auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one non-empty line is required'; END IF;

  -- Update SI totals
  UPDATE sales_invoices SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_vat_amount = v_total_vat, total_amount = v_grand_total
  WHERE id = v_si_id;

  IF v_grand_total <= 0 THEN RAISE EXCEPTION 'Cash sale total must be greater than zero'; END IF;

  -- ── Post SI: create JE ──────────────────────────────────────

  IF v_cfg.vat_payable_account_id IS NULL AND v_total_vat > 0 THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-SI-' || v_si_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id, 'posted', v_grand_total, v_grand_total, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_si_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_si_id, v_company_id, 1, v_cfg.ar_account_id, 'AR — ' || (p_header->>'customer_name_snapshot'), v_grand_total, 0, auth.uid(), auth.uid());

  v_rev_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_rev_line.revenue_account_id, 'Revenue — ' || v_rev_line.ln_desc, 0, v_rev_line.net_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rev_line.net_sum;
    v_rev_line_no := v_rev_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_si_number, 0, v_total_vat, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_total_vat;
  END IF;

  UPDATE sales_invoices SET
    status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_si_id, approved_by = auth.uid(), approved_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- ── Create and Post Receipt ──────────────────────────────────

  v_ar_cr := v_grand_total + p_cwt_amount;

  INSERT INTO receipts (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    receipt_number, receipt_date, payment_mode_id, bank_account_id,
    total_amount, total_cwt, remarks, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
    v_or_number, (p_header->>'date')::DATE,
    NULLIF(p_header->>'payment_mode_id', '')::UUID, v_cash_acct,
    v_grand_total, p_cwt_amount, 'Cash Sale — ' || v_si_number,
    'posted', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total, p_cwt_amount, auth.uid(), auth.uid());

  -- Post receipt JE
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-OR-' || v_or_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id, 'posted', v_ar_cr, v_ar_cr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_or_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, 1, v_cash_acct, 'Cash received — ' || v_or_number, v_grand_total, 0, auth.uid(), auth.uid());

  IF p_cwt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_or_id, v_company_id, 2, v_cfg.ewt_withheld_account_id, 'EWT withheld — ' || v_or_number, p_cwt_amount, 0, auth.uid(), auth.uid());
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_cfg.ar_account_id, 'AR cleared — ' || v_or_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts SET journal_entry_id = v_je_or_id, posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_cash_sale(JSONB, JSONB, NUMERIC) TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000017_purchasing.sql                                           │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- PURCHASING MODULE: Vendor Bills + Payment Vouchers
-- AP mirror of the SI/Receipt cycle. GL entries are balanced double-entry.
-- Posting requires company_accounting_config (ap_account_id at minimum).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Extend company_accounting_config for AP ───────────────────────────────────
ALTER TABLE company_accounting_config
  ADD COLUMN IF NOT EXISTS ap_account_id        UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS input_vat_account_id UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS ewt_payable_account_id UUID REFERENCES chart_of_accounts(id);

-- ── vendor_bills ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vendor_bills (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               UUID        NOT NULL REFERENCES companies(id),
  branch_id                UUID        REFERENCES branches(id),
  supplier_id              UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot   TEXT        NOT NULL,
  supplier_tin_snapshot    TEXT,
  bill_number              TEXT        NOT NULL,          -- internal VB number
  supplier_invoice_number  TEXT,                          -- supplier's own ref
  bill_date                DATE        NOT NULL,
  due_date                 DATE,
  fiscal_period_id         UUID        REFERENCES fiscal_periods(id),
  payment_terms_id         UUID        REFERENCES payment_terms(id),
  currency_code            TEXT        NOT NULL DEFAULT 'PHP',
  reference                TEXT,
  memo                     TEXT,
  total_taxable_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_zero_rated_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_exempt_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_input_vat_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount             NUMERIC(15,2) NOT NULL DEFAULT 0,
  ewt_amount_expected      NUMERIC(15,2),
  status                   TEXT        NOT NULL DEFAULT 'draft'
                                       CHECK (status IN ('draft','approved','posted','cancelled')),
  void_reason_id           UUID        REFERENCES void_reason_codes(id),
  journal_entry_id         UUID        REFERENCES journal_entries(id),
  posted_by                UUID,
  posted_at                TIMESTAMPTZ,
  approved_by              UUID,
  approved_at              TIMESTAMPTZ,
  created_by               UUID,
  updated_by               UUID,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, bill_number)
);

CREATE TABLE IF NOT EXISTS vendor_bill_lines (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_bill_id    UUID        NOT NULL REFERENCES vendor_bills(id) ON DELETE CASCADE,
  company_id        UUID        NOT NULL REFERENCES companies(id),
  line_number       INT         NOT NULL,
  item_id           UUID        REFERENCES items(id),
  description       TEXT        NOT NULL,
  quantity          NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id            UUID        REFERENCES units_of_measure(id),
  unit_price        NUMERIC(15,4) NOT NULL DEFAULT 0,
  discount_percent  NUMERIC(5,2) NOT NULL DEFAULT 0,
  discount_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id       UUID        REFERENCES vat_codes(id),
  input_vat_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  expense_account_id UUID       REFERENCES chart_of_accounts(id),
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vendor_bills_company   ON vendor_bills (company_id, bill_date DESC);
CREATE INDEX IF NOT EXISTS idx_vendor_bills_supplier  ON vendor_bills (supplier_id);
CREATE INDEX IF NOT EXISTS idx_vbl_bill_id            ON vendor_bill_lines (vendor_bill_id);

DROP TRIGGER IF EXISTS trg_vendor_bills_updated_at ON vendor_bills;
CREATE TRIGGER trg_vendor_bills_updated_at
  BEFORE UPDATE ON vendor_bills FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_vendor_bill_lines_updated_at ON vendor_bill_lines;
CREATE TRIGGER trg_vendor_bill_lines_updated_at
  BEFORE UPDATE ON vendor_bill_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE vendor_bills      ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_bill_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vb_read" ON vendor_bills;
CREATE POLICY "vb_read"   ON vendor_bills      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "vb_insert" ON vendor_bills;
CREATE POLICY "vb_insert" ON vendor_bills      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "vb_update" ON vendor_bills;
CREATE POLICY "vb_update" ON vendor_bills      FOR UPDATE TO authenticated
  USING (status IN ('draft','approved') AND is_company_member(company_id));
DROP POLICY IF EXISTS "vbl_read" ON vendor_bill_lines;
CREATE POLICY "vbl_read"  ON vendor_bill_lines FOR SELECT TO authenticated
  USING (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "vbl_write" ON vendor_bill_lines;
CREATE POLICY "vbl_write" ON vendor_bill_lines FOR INSERT TO authenticated
  WITH CHECK (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "vbl_update" ON vendor_bill_lines;
CREATE POLICY "vbl_update" ON vendor_bill_lines FOR UPDATE TO authenticated
  USING (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "vbl_delete" ON vendor_bill_lines;
CREATE POLICY "vbl_delete" ON vendor_bill_lines FOR DELETE TO authenticated
  USING (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));

-- ── payment_vouchers ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_vouchers (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  voucher_number         TEXT        NOT NULL,
  voucher_date           DATE        NOT NULL,
  payment_mode_id        UUID        REFERENCES ref_payment_modes(id),
  reference_number       TEXT,
  bank_account_id        UUID        REFERENCES chart_of_accounts(id),
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_ewt              NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks                TEXT,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','posted','cancelled')),
  journal_entry_id       UUID        REFERENCES journal_entries(id),
  posted_by              UUID,
  posted_at              TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, voucher_number)
);

CREATE TABLE IF NOT EXISTS payment_voucher_lines (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_voucher_id  UUID        NOT NULL REFERENCES payment_vouchers(id) ON DELETE CASCADE,
  company_id          UUID        NOT NULL REFERENCES companies(id),
  vendor_bill_id      UUID        REFERENCES vendor_bills(id),
  payment_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  ewt_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  atc_code_id         UUID        REFERENCES atc_codes(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_vouchers_company  ON payment_vouchers (company_id, voucher_date DESC);
CREATE INDEX IF NOT EXISTS idx_pvl_voucher_id            ON payment_voucher_lines (payment_voucher_id);
CREATE INDEX IF NOT EXISTS idx_pvl_bill_id               ON payment_voucher_lines (vendor_bill_id);

DROP TRIGGER IF EXISTS trg_payment_vouchers_updated_at ON payment_vouchers;
CREATE TRIGGER trg_payment_vouchers_updated_at
  BEFORE UPDATE ON payment_vouchers FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_payment_voucher_lines_updated_at ON payment_voucher_lines;
CREATE TRIGGER trg_payment_voucher_lines_updated_at
  BEFORE UPDATE ON payment_voucher_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE payment_vouchers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_voucher_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pv_read" ON payment_vouchers;
CREATE POLICY "pv_read"   ON payment_vouchers      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "pv_insert" ON payment_vouchers;
CREATE POLICY "pv_insert" ON payment_vouchers      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "pv_update" ON payment_vouchers;
CREATE POLICY "pv_update" ON payment_vouchers      FOR UPDATE TO authenticated
  USING (status = 'draft' AND is_company_member(company_id));
DROP POLICY IF EXISTS "pvl_read" ON payment_voucher_lines;
CREATE POLICY "pvl_read"  ON payment_voucher_lines FOR SELECT TO authenticated
  USING (payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "pvl_write" ON payment_voucher_lines;
CREATE POLICY "pvl_write" ON payment_voucher_lines FOR INSERT TO authenticated
  WITH CHECK (payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "pvl_delete" ON payment_voucher_lines;
CREATE POLICY "pvl_delete" ON payment_voucher_lines FOR DELETE TO authenticated
  USING (payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE is_company_member(company_id)));

-- ── Audit triggers ────────────────────────────────────────────────────────────
DO $$
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_vendor_bills ON vendor_bills;
    DROP TRIGGER IF EXISTS trg_audit_vendor_bills ON vendor_bills;
    CREATE TRIGGER trg_audit_vendor_bills AFTER INSERT OR UPDATE OR DELETE ON vendor_bills
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_payment_vouchers ON payment_vouchers;
    DROP TRIGGER IF EXISTS trg_audit_payment_vouchers ON payment_vouchers;
    CREATE TRIGGER trg_audit_payment_vouchers AFTER INSERT OR UPDATE OR DELETE ON payment_vouchers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END;
$$;

-- ── fn_save_vendor_bill ───────────────────────────────────────────────────────
-- Atomic save of header + lines. Recomputes input VAT server-side.
-- Rejects edits on non-draft bills (must revert first).

CREATE OR REPLACE FUNCTION fn_save_vendor_bill(
  p_bill_id UUID,
  p_header  JSONB,
  p_lines   JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bill_id        UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_bill_number    TEXT;
  v_current_status TEXT;
  v_fiscal_period  UUID;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= (p_header->>'bill_date')::DATE
    AND end_date >= (p_header->>'bill_date')::DATE AND is_locked = false LIMIT 1;

  IF p_bill_id IS NULL THEN
    v_bill_number := fn_next_document_number(v_company_id, v_branch_id, 'VB');
    INSERT INTO vendor_bills (
      company_id, branch_id, supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      bill_number, supplier_invoice_number, bill_date, due_date, fiscal_period_id,
      payment_terms_id, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_input_vat_amount, total_amount, ewt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'supplier_id')::UUID, p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_bill_number, NULLIF(p_header->>'supplier_invoice_number', ''),
      (p_header->>'bill_date')::DATE, NULLIF(p_header->>'due_date', '')::DATE,
      v_fiscal_period, NULLIF(p_header->>'payment_terms_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0,
      NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_bill_id;
  ELSE
    SELECT id, status INTO v_bill_id, v_current_status
    FROM vendor_bills WHERE id = p_bill_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % vendor bill. Revert to draft first.', v_current_status;
    END IF;
    UPDATE vendor_bills SET
      branch_id = v_branch_id, supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_invoice_number = NULLIF(p_header->>'supplier_invoice_number', ''),
      bill_date = (p_header->>'bill_date')::DATE,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      fiscal_period_id = v_fiscal_period,
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      ewt_amount_expected = NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_input_vat_amount = 0, total_amount = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_bill_id;
  END IF;

  DELETE FROM vendor_bill_lines WHERE vendor_bill_id = v_bill_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO vendor_bill_lines (
      vendor_bill_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_bill_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one non-empty line is required'; END IF;

  UPDATE vendor_bills SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, updated_at = NOW()
  WHERE id = v_bill_id;

  RETURN v_bill_id;
END;
$$;

-- ── fn_approve_vendor_bill ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_approve_vendor_bill(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft bills can be approved (current: %)', v_rec.status; END IF;
  UPDATE vendor_bills SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(),
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_bill_id;
END;
$$;

-- ── fn_revert_vendor_bill_to_draft ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_revert_vendor_bill_to_draft(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN RAISE EXCEPTION 'Only approved bills can be reverted (current: %)', v_rec.status; END IF;
  UPDATE vendor_bills SET status = 'draft', approved_by = NULL, approved_at = NULL,
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_bill_id;
END;
$$;

-- ── fn_post_vendor_bill ───────────────────────────────────────────────────────
-- DR Expense accounts (per line) + DR Input VAT = CR Accounts Payable
CREATE OR REPLACE FUNCTION fn_post_vendor_bill(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec      vendor_bills%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_line_no  INT;
  v_total_dr NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved bills can be posted (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.bill_date
    AND end_date >= v_rec.bill_date AND is_locked = false LIMIT 1;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date, v_fp_id,
    'Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
    'MANUAL', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Expense accounts per line (grouped by expense_account_id)
  v_line_no := 1;
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_bill_lines
    WHERE vendor_bill_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- DR: Input VAT (if any)
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.bill_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  -- CR: Accounts Payable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE vendor_bills SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_void_vendor_bill ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_void_vendor_bill(
  p_bill_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN RAISE EXCEPTION 'Bill is already cancelled'; END IF;
  UPDATE vendor_bills SET status = 'cancelled', void_reason_id = p_void_reason_id,
    memo = COALESCE(p_memo, memo), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_bill_id;
END;
$$;

-- ── fn_save_payment_voucher ───────────────────────────────────────────────────
-- Saves PV header + lines. Validates that payment doesn't exceed outstanding AP balance.
CREATE OR REPLACE FUNCTION fn_save_payment_voucher(
  p_voucher_id UUID,
  p_header     JSONB,
  p_lines      JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_voucher_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_voucher_number TEXT;
  v_current_status TEXT;
  v_line           JSONB;
  v_bill_id        UUID;
  v_pay_amt        NUMERIC(15,2);
  v_ewt_amt        NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  -- Validate each line: no over-payment
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_bill_id := NULLIF(v_line->>'vendor_bill_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_ewt_amt := COALESCE((v_line->>'ewt_amount')::NUMERIC, 0);
    CONTINUE WHEN v_bill_id IS NULL OR (v_pay_amt + v_ewt_amt) <= 0;

    IF NOT EXISTS (SELECT 1 FROM vendor_bills WHERE id = v_bill_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Vendor bill % does not belong to this company', v_bill_id;
    END IF;

    SELECT vb.total_amount - COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
    INTO v_outstanding
    FROM vendor_bills vb
    LEFT JOIN payment_voucher_lines pvl ON pvl.vendor_bill_id = vb.id
      AND pvl.payment_voucher_id != COALESCE(p_voucher_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND pvl.payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE status != 'cancelled')
    WHERE vb.id = v_bill_id GROUP BY vb.total_amount;

    IF (v_pay_amt + v_ewt_amt) > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % + EWT % exceeds outstanding AP balance of % for this bill',
        v_pay_amt, v_ewt_amt, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_voucher_id IS NULL THEN
    v_voucher_number := fn_next_document_number(v_company_id, v_branch_id, 'PV');
    INSERT INTO payment_vouchers (
      company_id, branch_id, supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      voucher_number, voucher_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_ewt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'supplier_id')::UUID, p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_voucher_number, (p_header->>'voucher_date')::DATE,
      NULLIF(p_header->>'payment_mode_id', '')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_voucher_id;
  ELSE
    SELECT id, status INTO v_voucher_id, v_current_status
    FROM payment_vouchers WHERE id = p_voucher_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % payment voucher', v_current_status; END IF;
    UPDATE payment_vouchers SET
      branch_id = v_branch_id, supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      voucher_date = (p_header->>'voucher_date')::DATE,
      payment_mode_id = NULLIF(p_header->>'payment_mode_id', '')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_ewt = COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_voucher_id;
  END IF;

  DELETE FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id;

  INSERT INTO payment_voucher_lines (payment_voucher_id, company_id, vendor_bill_id, payment_amount, ewt_amount, atc_code_id, created_by, updated_by)
  SELECT v_voucher_id, v_company_id,
    NULLIF(l->>'vendor_bill_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'ewt_amount')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) > 0;

  RETURN v_voucher_id;
END;
$$;

-- ── fn_post_payment_voucher ───────────────────────────────────────────────────
-- DR Accounts Payable = CR Cash/Bank + CR EWT Payable
CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ap_dr     NUMERIC(15,2);
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft vouchers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_ewt > 0 AND v_cfg.ewt_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on voucher and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;

  v_ap_dr := v_rec.total_amount + v_rec.total_ewt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date, v_fp_id,
    'Payment Voucher ' || v_rec.voucher_number || ' — ' || v_rec.supplier_name_snapshot,
    'MANUAL', v_rec.id, 'posted',
    v_ap_dr, v_ap_dr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Payable (total cash + EWT clears the full AP balance)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP cleared — ' || v_rec.voucher_number, v_ap_dr, 0, auth.uid(), auth.uid());

  -- CR: Cash / Bank
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 2, v_cash_acct,
          'Cash paid — ' || v_rec.voucher_number, 0, v_rec.total_amount, auth.uid(), auth.uid());
  v_line_no := 3;

  -- CR: EWT Payable (amount withheld from supplier, to be remitted to BIR)
  IF v_rec.total_ewt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ewt_payable_account_id,
            'EWT withheld — ' || v_rec.voucher_number, 0, v_rec.total_ewt, auth.uid(), auth.uid());
  END IF;

  UPDATE payment_vouchers SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_save_vendor_bill(UUID, JSONB, JSONB)              TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_vendor_bill(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_revert_vendor_bill_to_draft(UUID)                 TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_bill(UUID)                            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_vendor_bill(UUID, UUID, TEXT)                TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_payment_voucher(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID)                        TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000018_purchasing_full.sql                                      │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- PURCHASING MODULE — Full Build
-- Purchase Orders → Receiving Reports → Vendor Bills → Payment Vouchers
-- Plus: Cash Purchases, Vendor Credits, Supplier Debit Memos, Purchase Returns
-- Plus: AP Aging, Supplier Ledger, Input VAT Review, EWT Summary, Registers
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Extend payment_vouchers for check/payment tracking ────────────────────────
ALTER TABLE payment_vouchers
  ADD COLUMN IF NOT EXISTS check_number   TEXT,
  ADD COLUMN IF NOT EXISTS check_date     DATE,
  ADD COLUMN IF NOT EXISTS date_released  DATE,
  ADD COLUMN IF NOT EXISTS released_by    UUID,
  ADD COLUMN IF NOT EXISTS date_cleared   DATE,
  ADD COLUMN IF NOT EXISTS cleared_by     UUID;

-- ── purchase_orders ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS purchase_orders (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  po_number              TEXT        NOT NULL,
  po_date                DATE        NOT NULL,
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  delivery_address       TEXT,
  expected_date          DATE,
  payment_terms_id       UUID        REFERENCES payment_terms(id),
  currency_code          TEXT        NOT NULL DEFAULT 'PHP',
  notes                  TEXT,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','approved','partially_received','fully_received','cancelled')),
  approved_by            UUID,
  approved_at            TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, po_number)
);

CREATE TABLE IF NOT EXISTS purchase_order_lines (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id         UUID        NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  company_id    UUID        NOT NULL REFERENCES companies(id),
  line_number   INT         NOT NULL,
  item_id       UUID        REFERENCES items(id),
  description   TEXT        NOT NULL,
  quantity      NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id        UUID        REFERENCES units_of_measure(id),
  unit_price    NUMERIC(15,4) NOT NULL DEFAULT 0,
  total_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_company  ON purchase_orders (company_id, po_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders (supplier_id);
CREATE INDEX IF NOT EXISTS idx_pol_po_id               ON purchase_order_lines (po_id);

DROP TRIGGER IF EXISTS trg_po_updated_at ON purchase_orders;
CREATE TRIGGER trg_po_updated_at   BEFORE UPDATE ON purchase_orders      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_pol_updated_at ON purchase_order_lines;
CREATE TRIGGER trg_pol_updated_at  BEFORE UPDATE ON purchase_order_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE purchase_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "po_read" ON purchase_orders;
CREATE POLICY "po_read"    ON purchase_orders      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "po_insert" ON purchase_orders;
CREATE POLICY "po_insert"  ON purchase_orders      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "po_update" ON purchase_orders;
CREATE POLICY "po_update"  ON purchase_orders      FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "pol_read" ON purchase_order_lines;
CREATE POLICY "pol_read"   ON purchase_order_lines FOR SELECT TO authenticated USING (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "pol_write" ON purchase_order_lines;
CREATE POLICY "pol_write"  ON purchase_order_lines FOR INSERT TO authenticated WITH CHECK (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "pol_update" ON purchase_order_lines;
CREATE POLICY "pol_update" ON purchase_order_lines FOR UPDATE TO authenticated USING (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "pol_delete" ON purchase_order_lines;
CREATE POLICY "pol_delete" ON purchase_order_lines FOR DELETE TO authenticated USING (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));

DO $$ BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_purchase_orders ON purchase_orders;
    DROP TRIGGER IF EXISTS trg_audit_purchase_orders ON purchase_orders;
    CREATE TRIGGER trg_audit_purchase_orders AFTER INSERT OR UPDATE OR DELETE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END; $$;

-- ── receiving_reports ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS receiving_reports (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  rr_number              TEXT        NOT NULL,
  rr_date                DATE        NOT NULL,
  po_id                  UUID        NOT NULL REFERENCES purchase_orders(id),
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_dr_no         TEXT,
  remarks                TEXT,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','received','cancelled')),
  confirmed_by           UUID,
  confirmed_at           TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, rr_number)
);

CREATE TABLE IF NOT EXISTS receiving_report_lines (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  rr_id         UUID        NOT NULL REFERENCES receiving_reports(id) ON DELETE CASCADE,
  company_id    UUID        NOT NULL REFERENCES companies(id),
  po_line_id    UUID        REFERENCES purchase_order_lines(id),
  line_number   INT         NOT NULL,
  item_id       UUID        REFERENCES items(id),
  description   TEXT        NOT NULL,
  ordered_qty   NUMERIC(15,4) NOT NULL DEFAULT 0,
  received_qty  NUMERIC(15,4) NOT NULL DEFAULT 0,
  reject_qty    NUMERIC(15,4) NOT NULL DEFAULT 0,
  uom_id        UUID        REFERENCES units_of_measure(id),
  unit_price    NUMERIC(15,4) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rr_company ON receiving_reports (company_id, rr_date DESC);
CREATE INDEX IF NOT EXISTS idx_rr_po_id   ON receiving_reports (po_id);
CREATE INDEX IF NOT EXISTS idx_rrl_rr_id  ON receiving_report_lines (rr_id);

DROP TRIGGER IF EXISTS trg_rr_updated_at ON receiving_reports;
CREATE TRIGGER trg_rr_updated_at  BEFORE UPDATE ON receiving_reports      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_rrl_updated_at ON receiving_report_lines;
CREATE TRIGGER trg_rrl_updated_at BEFORE UPDATE ON receiving_report_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE receiving_reports      ENABLE ROW LEVEL SECURITY;
ALTER TABLE receiving_report_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rr_read" ON receiving_reports;
CREATE POLICY "rr_read"    ON receiving_reports      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "rr_insert" ON receiving_reports;
CREATE POLICY "rr_insert"  ON receiving_reports      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "rr_update" ON receiving_reports;
CREATE POLICY "rr_update"  ON receiving_reports      FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "rrl_read" ON receiving_report_lines;
CREATE POLICY "rrl_read"   ON receiving_report_lines FOR SELECT TO authenticated USING (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "rrl_write" ON receiving_report_lines;
CREATE POLICY "rrl_write"  ON receiving_report_lines FOR INSERT TO authenticated WITH CHECK (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "rrl_update" ON receiving_report_lines;
CREATE POLICY "rrl_update" ON receiving_report_lines FOR UPDATE TO authenticated USING (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "rrl_delete" ON receiving_report_lines;
CREATE POLICY "rrl_delete" ON receiving_report_lines FOR DELETE TO authenticated USING (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));

-- ── cash_purchases ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cash_purchases (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  cp_number              TEXT        NOT NULL,
  transaction_date       DATE        NOT NULL,
  supplier_id            UUID        REFERENCES suppliers(id),
  supplier_name_snapshot TEXT,
  supplier_tin_snapshot  TEXT,
  payment_account_id     UUID        REFERENCES chart_of_accounts(id),
  payment_method         TEXT        NOT NULL DEFAULT 'cash'
                                     CHECK (payment_method IN ('cash','check','transfer')),
  reference_number       TEXT,
  fiscal_period_id       UUID        REFERENCES fiscal_periods(id),
  remarks                TEXT,
  total_taxable_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_zero_rated_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_exempt_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_input_vat_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','posted','cancelled')),
  journal_entry_id       UUID        REFERENCES journal_entries(id),
  posted_by              UUID,
  posted_at              TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, cp_number)
);

CREATE TABLE IF NOT EXISTS cash_purchase_lines (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cp_id               UUID        NOT NULL REFERENCES cash_purchases(id) ON DELETE CASCADE,
  company_id          UUID        NOT NULL REFERENCES companies(id),
  line_number         INT         NOT NULL,
  item_id             UUID        REFERENCES items(id),
  description         TEXT        NOT NULL,
  quantity            NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id              UUID        REFERENCES units_of_measure(id),
  unit_price          NUMERIC(15,4) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID        REFERENCES vat_codes(id),
  input_vat_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  expense_account_id  UUID        REFERENCES chart_of_accounts(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cp_company ON cash_purchases (company_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_cpl_cp_id  ON cash_purchase_lines (cp_id);

DROP TRIGGER IF EXISTS trg_cp_updated_at ON cash_purchases;
CREATE TRIGGER trg_cp_updated_at  BEFORE UPDATE ON cash_purchases      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_cpl_updated_at ON cash_purchase_lines;
CREATE TRIGGER trg_cpl_updated_at BEFORE UPDATE ON cash_purchase_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE cash_purchases      ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_purchase_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cp_read" ON cash_purchases;
CREATE POLICY "cp_read"    ON cash_purchases      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "cp_insert" ON cash_purchases;
CREATE POLICY "cp_insert"  ON cash_purchases      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "cp_update" ON cash_purchases;
CREATE POLICY "cp_update"  ON cash_purchases      FOR UPDATE TO authenticated USING (status IN ('draft') AND is_company_member(company_id));
DROP POLICY IF EXISTS "cpl_read" ON cash_purchase_lines;
CREATE POLICY "cpl_read"   ON cash_purchase_lines FOR SELECT TO authenticated USING (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "cpl_write" ON cash_purchase_lines;
CREATE POLICY "cpl_write"  ON cash_purchase_lines FOR INSERT TO authenticated WITH CHECK (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "cpl_update" ON cash_purchase_lines;
CREATE POLICY "cpl_update" ON cash_purchase_lines FOR UPDATE TO authenticated USING (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "cpl_delete" ON cash_purchase_lines;
CREATE POLICY "cpl_delete" ON cash_purchase_lines FOR DELETE TO authenticated USING (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));

DO $$ BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_cash_purchases ON cash_purchases;
    DROP TRIGGER IF EXISTS trg_audit_cash_purchases ON cash_purchases;
    CREATE TRIGGER trg_audit_cash_purchases AFTER INSERT OR UPDATE OR DELETE ON cash_purchases
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END; $$;

-- ── vendor_credits ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vendor_credits (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  vc_number              TEXT        NOT NULL,
  credit_date            DATE        NOT NULL,
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  supplier_cm_no         TEXT,
  reference_bill_id      UUID        REFERENCES vendor_bills(id),
  fiscal_period_id       UUID        REFERENCES fiscal_periods(id),
  remarks                TEXT,
  total_taxable_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_input_vat_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  remaining_balance      NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','open','applied','cancelled')),
  journal_entry_id       UUID        REFERENCES journal_entries(id),
  posted_by              UUID,
  posted_at              TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, vc_number)
);

CREATE TABLE IF NOT EXISTS vendor_credit_lines (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  vc_id               UUID        NOT NULL REFERENCES vendor_credits(id) ON DELETE CASCADE,
  company_id          UUID        NOT NULL REFERENCES companies(id),
  line_number         INT         NOT NULL,
  item_id             UUID        REFERENCES items(id),
  description         TEXT        NOT NULL,
  quantity            NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id              UUID        REFERENCES units_of_measure(id),
  unit_price          NUMERIC(15,4) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID        REFERENCES vat_codes(id),
  input_vat_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  expense_account_id  UUID        REFERENCES chart_of_accounts(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vc_company ON vendor_credits (company_id, credit_date DESC);
CREATE INDEX IF NOT EXISTS idx_vcl_vc_id  ON vendor_credit_lines (vc_id);

DROP TRIGGER IF EXISTS trg_vc_updated_at ON vendor_credits;
CREATE TRIGGER trg_vc_updated_at  BEFORE UPDATE ON vendor_credits      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_vcl_updated_at ON vendor_credit_lines;
CREATE TRIGGER trg_vcl_updated_at BEFORE UPDATE ON vendor_credit_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE vendor_credits      ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_credit_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vc_read" ON vendor_credits;
CREATE POLICY "vc_read"    ON vendor_credits      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "vc_insert" ON vendor_credits;
CREATE POLICY "vc_insert"  ON vendor_credits      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "vc_update" ON vendor_credits;
CREATE POLICY "vc_update"  ON vendor_credits      FOR UPDATE TO authenticated USING (status IN ('draft') AND is_company_member(company_id));
DROP POLICY IF EXISTS "vcl_read" ON vendor_credit_lines;
CREATE POLICY "vcl_read"   ON vendor_credit_lines FOR SELECT TO authenticated USING (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "vcl_write" ON vendor_credit_lines;
CREATE POLICY "vcl_write"  ON vendor_credit_lines FOR INSERT TO authenticated WITH CHECK (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "vcl_update" ON vendor_credit_lines;
CREATE POLICY "vcl_update" ON vendor_credit_lines FOR UPDATE TO authenticated USING (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "vcl_delete" ON vendor_credit_lines;
CREATE POLICY "vcl_delete" ON vendor_credit_lines FOR DELETE TO authenticated USING (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));

DO $$ BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_vendor_credits ON vendor_credits;
    DROP TRIGGER IF EXISTS trg_audit_vendor_credits ON vendor_credits;
    CREATE TRIGGER trg_audit_vendor_credits AFTER INSERT OR UPDATE OR DELETE ON vendor_credits
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END; $$;

-- ── supplier_debit_memos ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS supplier_debit_memos (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  sdm_number             TEXT        NOT NULL,
  dm_date                DATE        NOT NULL,
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  reference_doc_id       UUID,
  reference_doc_type     TEXT        CHECK (reference_doc_type IN ('receiving_report','vendor_bill')),
  reason                 TEXT,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','sent','acknowledged','cancelled')),
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, sdm_number)
);

CREATE TABLE IF NOT EXISTS supplier_debit_memo_lines (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sdm_id        UUID        NOT NULL REFERENCES supplier_debit_memos(id) ON DELETE CASCADE,
  company_id    UUID        NOT NULL REFERENCES companies(id),
  line_number   INT         NOT NULL,
  item_id       UUID        REFERENCES items(id),
  description   TEXT        NOT NULL,
  quantity      NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id        UUID        REFERENCES units_of_measure(id),
  unit_price    NUMERIC(15,4) NOT NULL DEFAULT 0,
  total_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sdm_company ON supplier_debit_memos (company_id, dm_date DESC);
CREATE INDEX IF NOT EXISTS idx_sdml_sdm_id ON supplier_debit_memo_lines (sdm_id);

DROP TRIGGER IF EXISTS trg_sdm_updated_at ON supplier_debit_memos;
CREATE TRIGGER trg_sdm_updated_at  BEFORE UPDATE ON supplier_debit_memos      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_sdml_updated_at ON supplier_debit_memo_lines;
CREATE TRIGGER trg_sdml_updated_at BEFORE UPDATE ON supplier_debit_memo_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE supplier_debit_memos      ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_debit_memo_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sdm_read" ON supplier_debit_memos;
CREATE POLICY "sdm_read"    ON supplier_debit_memos      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "sdm_insert" ON supplier_debit_memos;
CREATE POLICY "sdm_insert"  ON supplier_debit_memos      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "sdm_update" ON supplier_debit_memos;
CREATE POLICY "sdm_update"  ON supplier_debit_memos      FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "sdml_read" ON supplier_debit_memo_lines;
CREATE POLICY "sdml_read"   ON supplier_debit_memo_lines FOR SELECT TO authenticated USING (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "sdml_write" ON supplier_debit_memo_lines;
CREATE POLICY "sdml_write"  ON supplier_debit_memo_lines FOR INSERT TO authenticated WITH CHECK (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "sdml_update" ON supplier_debit_memo_lines;
CREATE POLICY "sdml_update" ON supplier_debit_memo_lines FOR UPDATE TO authenticated USING (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "sdml_delete" ON supplier_debit_memo_lines;
CREATE POLICY "sdml_delete" ON supplier_debit_memo_lines FOR DELETE TO authenticated USING (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));

-- ── purchase_returns ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS purchase_returns (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  return_number          TEXT        NOT NULL,
  return_date            DATE        NOT NULL,
  rr_id                  UUID        NOT NULL REFERENCES receiving_reports(id),
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  remarks                TEXT,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','shipped','completed','cancelled')),
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, return_number)
);

CREATE TABLE IF NOT EXISTS purchase_return_lines (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id    UUID        NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
  company_id   UUID        NOT NULL REFERENCES companies(id),
  rr_line_id   UUID        REFERENCES receiving_report_lines(id),
  line_number  INT         NOT NULL,
  item_id      UUID        REFERENCES items(id),
  description  TEXT        NOT NULL,
  max_qty      NUMERIC(15,4) NOT NULL DEFAULT 0,
  return_qty   NUMERIC(15,4) NOT NULL DEFAULT 0,
  uom_id       UUID        REFERENCES units_of_measure(id),
  unit_price   NUMERIC(15,4) NOT NULL DEFAULT 0,
  reason       TEXT,
  created_by   UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pr_company ON purchase_returns (company_id, return_date DESC);
CREATE INDEX IF NOT EXISTS idx_prl_pr_id  ON purchase_return_lines (return_id);

DROP TRIGGER IF EXISTS trg_pr_updated_at ON purchase_returns;
CREATE TRIGGER trg_pr_updated_at  BEFORE UPDATE ON purchase_returns      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_prl_updated_at ON purchase_return_lines;
CREATE TRIGGER trg_prl_updated_at BEFORE UPDATE ON purchase_return_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE purchase_returns      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_return_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pr_read" ON purchase_returns;
CREATE POLICY "pr_read"    ON purchase_returns      FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "pr_insert" ON purchase_returns;
CREATE POLICY "pr_insert"  ON purchase_returns      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "pr_update" ON purchase_returns;
CREATE POLICY "pr_update"  ON purchase_returns      FOR UPDATE TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "prl_read" ON purchase_return_lines;
CREATE POLICY "prl_read"   ON purchase_return_lines FOR SELECT TO authenticated USING (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "prl_write" ON purchase_return_lines;
CREATE POLICY "prl_write"  ON purchase_return_lines FOR INSERT TO authenticated WITH CHECK (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "prl_update" ON purchase_return_lines;
CREATE POLICY "prl_update" ON purchase_return_lines FOR UPDATE TO authenticated USING (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));
DROP POLICY IF EXISTS "prl_delete" ON purchase_return_lines;
CREATE POLICY "prl_delete" ON purchase_return_lines FOR DELETE TO authenticated USING (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));

-- ── form_2307_issuances ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS form_2307_issuances (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID        NOT NULL REFERENCES companies(id),
  supplier_id     UUID        NOT NULL REFERENCES suppliers(id),
  tax_year        INT         NOT NULL,
  tax_quarter     INT         NOT NULL CHECK (tax_quarter BETWEEN 1 AND 4),
  total_tax_base  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_ewt       NUMERIC(15,2) NOT NULL DEFAULT 0,
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','generated','sent','acknowledged')),
  date_generated  TIMESTAMPTZ,
  date_sent       TIMESTAMPTZ,
  date_acknowledged TIMESTAMPTZ,
  remarks         TEXT,
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, supplier_id, tax_year, tax_quarter)
);

CREATE INDEX IF NOT EXISTS idx_f2307_company ON form_2307_issuances (company_id, tax_year DESC, tax_quarter DESC);

DROP TRIGGER IF EXISTS trg_f2307_updated_at ON form_2307_issuances;
CREATE TRIGGER trg_f2307_updated_at BEFORE UPDATE ON form_2307_issuances FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE form_2307_issuances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "f2307_read" ON form_2307_issuances;
CREATE POLICY "f2307_read"   ON form_2307_issuances FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "f2307_insert" ON form_2307_issuances;
CREATE POLICY "f2307_insert" ON form_2307_issuances FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "f2307_update" ON form_2307_issuances;
CREATE POLICY "f2307_update" ON form_2307_issuances FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- ══════════════════════════════════════════════════════════════════════════════
-- VIEWS
-- ══════════════════════════════════════════════════════════════════════════════

-- ── vw_ap_aging ───────────────────────────────────────────────────────────────
-- Active payables (posted VBs) with balance_due computed from posted PVs
CREATE OR REPLACE VIEW vw_ap_aging AS
SELECT
  vb.id,
  vb.company_id,
  vb.supplier_id,
  s.registered_name  AS supplier_name,
  s.tin              AS supplier_tin,
  vb.bill_number,
  vb.bill_date,
  vb.due_date,
  vb.total_amount,
  vb.total_amount - COALESCE((
    SELECT SUM(pvl.payment_amount + pvl.ewt_amount)
    FROM payment_voucher_lines pvl
    JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.vendor_bill_id = vb.id AND pv.status = 'posted' AND pv.company_id = vb.company_id
  ), 0) AS balance_due
FROM vendor_bills vb
JOIN suppliers s ON s.id = vb.supplier_id
WHERE vb.status = 'posted';

-- ── vw_supplier_ledger ────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_supplier_ledger AS
SELECT
  vb.company_id,
  vb.supplier_id,
  vb.bill_date        AS transaction_date,
  'vendor_bill'       AS document_type,
  vb.id               AS document_id,
  vb.bill_number      AS document_number,
  vb.supplier_invoice_number AS external_ref,
  vb.memo             AS description,
  0                   AS debit_amount,
  vb.total_amount     AS credit_amount,
  vb.created_at
FROM vendor_bills vb
WHERE vb.status = 'posted'
UNION ALL
SELECT
  pv.company_id,
  pv.supplier_id,
  pv.voucher_date     AS transaction_date,
  'payment_voucher'   AS document_type,
  pv.id               AS document_id,
  pv.voucher_number   AS document_number,
  pv.reference_number AS external_ref,
  pv.remarks          AS description,
  pv.total_amount + pv.total_ewt AS debit_amount,
  0                   AS credit_amount,
  pv.created_at
FROM payment_vouchers pv
WHERE pv.status = 'posted'
UNION ALL
SELECT
  vc.company_id,
  vc.supplier_id,
  vc.credit_date      AS transaction_date,
  'vendor_credit'     AS document_type,
  vc.id               AS document_id,
  vc.vc_number        AS document_number,
  vc.supplier_cm_no   AS external_ref,
  vc.remarks          AS description,
  vc.total_amount     AS debit_amount,
  0                   AS credit_amount,
  vc.created_at
FROM vendor_credits vc
WHERE vc.status IN ('open','applied');

-- ── vw_input_vat_review ───────────────────────────────────────────────────────
-- Aggregates per bill from vendor_bill_lines classified by VAT type
DROP VIEW IF EXISTS vw_input_vat_review;
CREATE OR REPLACE VIEW vw_input_vat_review AS
SELECT
  vb.id                 AS transaction_id,
  'vendor_bill'         AS source_module,
  vb.company_id,
  vb.bill_date          AS invoice_date,
  vb.supplier_tin_snapshot AS supplier_tin,
  vb.supplier_name_snapshot AS supplier_name,
  COALESCE((SELECT s.registered_address FROM suppliers s WHERE s.id = vb.supplier_id), '') AS supplier_address,
  vb.supplier_invoice_number AS invoice_no,
  vb.bill_number        AS system_no,
  COALESCE(SUM(vbl.net_amount + vbl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc2.vat_classification = 'exempt'    THEN vbl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc2.vat_classification = 'zero_rated' THEN vbl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc2.vat_classification = 'regular'   THEN vbl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(vbl.input_vat_amount), 0) AS input_vat
FROM vendor_bills vb
JOIN vendor_bill_lines vbl ON vbl.vendor_bill_id = vb.id
LEFT JOIN vat_codes vc2 ON vc2.id = vbl.vat_code_id
WHERE vb.status = 'posted'
GROUP BY vb.id, vb.company_id, vb.bill_date, vb.supplier_tin_snapshot, vb.supplier_name_snapshot,
         vb.supplier_id, vb.supplier_invoice_number, vb.bill_number
UNION ALL
SELECT
  cp.id                 AS transaction_id,
  'cash_purchase'       AS source_module,
  cp.company_id,
  cp.transaction_date   AS invoice_date,
  cp.supplier_tin_snapshot AS supplier_tin,
  COALESCE(cp.supplier_name_snapshot, 'Cash Purchase') AS supplier_name,
  ''                    AS supplier_address,
  cp.reference_number   AS invoice_no,
  cp.cp_number          AS system_no,
  COALESCE(SUM(cpl.net_amount + cpl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'exempt'    THEN cpl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'zero_rated' THEN cpl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'regular'   THEN cpl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(cpl.input_vat_amount), 0) AS input_vat
FROM cash_purchases cp
JOIN cash_purchase_lines cpl ON cpl.cp_id = cp.id
LEFT JOIN vat_codes vc3 ON vc3.id = cpl.vat_code_id
WHERE cp.status = 'posted'
GROUP BY cp.id, cp.company_id, cp.transaction_date, cp.supplier_tin_snapshot,
         cp.supplier_name_snapshot, cp.reference_number, cp.cp_number;

-- ── vw_ewt_summary_ap ─────────────────────────────────────────────────────────
-- EWT withheld per PV line grouped by ATC code
CREATE OR REPLACE VIEW vw_ewt_summary_ap AS
SELECT
  pv.id               AS transaction_id,
  pv.company_id,
  pv.voucher_date     AS invoice_date,
  pv.supplier_id,
  pv.supplier_tin_snapshot AS supplier_tin,
  pv.supplier_name_snapshot AS supplier_name,
  ac.code AS atc_code,
  ac.description      AS nature_of_payment,
  ac.rate             AS tax_rate,
  pvl.ewt_amount / NULLIF(ac.rate / 100.0, 0) AS tax_base,
  pvl.ewt_amount      AS tax_withheld
FROM payment_vouchers pv
JOIN payment_voucher_lines pvl ON pvl.payment_voucher_id = pv.id
JOIN atc_codes ac ON ac.id = pvl.atc_code_id
WHERE pv.status = 'posted' AND pvl.ewt_amount > 0;

-- ── vw_vendor_bill_register ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_vendor_bill_register AS
SELECT
  vb.id,
  vb.company_id,
  vb.bill_date,
  vb.bill_number,
  vb.supplier_name_snapshot AS supplier_name,
  vb.supplier_tin_snapshot  AS supplier_tin,
  vb.supplier_invoice_number,
  vb.due_date,
  vb.total_taxable_amount,
  vb.total_zero_rated_amount,
  vb.total_exempt_amount,
  vb.total_input_vat_amount AS input_vat,
  COALESCE(vb.ewt_amount_expected, 0) AS ewt_deducted,
  vb.total_amount,
  vb.status,
  vb.created_at
FROM vendor_bills vb;

-- ── vw_payment_register ───────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_payment_register AS
SELECT
  pv.id,
  pv.company_id,
  pv.voucher_date,
  pv.voucher_number,
  pv.supplier_name_snapshot AS supplier_name,
  pv.supplier_tin_snapshot  AS supplier_tin,
  pv.reference_number,
  pv.check_number,
  pv.check_date,
  pv.total_amount,
  pv.total_ewt,
  pv.total_amount + pv.total_ewt AS total_cleared,
  pv.status,
  pv.date_released,
  pv.date_cleared,
  pv.created_at
FROM payment_vouchers pv;

-- ── vw_sdm_register ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_sdm_register AS
SELECT
  sdm.id,
  sdm.company_id,
  sdm.dm_date,
  sdm.sdm_number,
  sdm.supplier_name_snapshot AS supplier_name,
  sdm.supplier_tin_snapshot  AS supplier_tin,
  sdm.reason,
  sdm.total_amount,
  sdm.status,
  sdm.created_at
FROM supplier_debit_memos sdm;

-- ── vw_slp_export ─────────────────────────────────────────────────────────────
-- Summary List of Purchases grouped by supplier per month (from posted VBs)
CREATE OR REPLACE VIEW vw_slp_export AS
SELECT
  vb.company_id,
  TO_CHAR(DATE_TRUNC('month', vb.bill_date), 'MM/YYYY') AS taxable_month,
  vb.bill_date,
  vb.supplier_tin_snapshot  AS supplier_tin,
  vb.supplier_name_snapshot AS registered_name,
  COALESCE((SELECT s.registered_address FROM suppliers s WHERE s.id = vb.supplier_id), '') AS address,
  COALESCE(SUM(vbl.net_amount + vbl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc4.vat_classification = 'exempt'    THEN vbl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc4.vat_classification = 'zero_rated' THEN vbl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc4.vat_classification = 'regular'   THEN vbl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(vbl.input_vat_amount), 0) AS input_vat
FROM vendor_bills vb
JOIN vendor_bill_lines vbl ON vbl.vendor_bill_id = vb.id
LEFT JOIN vat_codes vc4 ON vc4.id = vbl.vat_code_id
WHERE vb.status = 'posted'
GROUP BY vb.company_id, DATE_TRUNC('month', vb.bill_date), vb.bill_date,
         vb.supplier_tin_snapshot, vb.supplier_name_snapshot, vb.supplier_id;

-- ══════════════════════════════════════════════════════════════════════════════
-- RPCs
-- ══════════════════════════════════════════════════════════════════════════════

-- ── fn_save_purchase_order ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_purchase_order(
  p_po_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_po_number    TEXT;
  v_cur_status   TEXT;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF p_po_id IS NULL THEN
    v_po_number := fn_next_document_number(v_company_id, v_branch_id, 'PO');
    INSERT INTO purchase_orders (
      company_id, branch_id, po_number, po_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot,
      delivery_address, expected_date, payment_terms_id,
      currency_code, notes, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_po_number,
      (p_header->>'po_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'delivery_address', ''),
      NULLIF(p_header->>'expected_date', '')::DATE,
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'notes', ''),
      0, 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_po_id;
  ELSE
    SELECT id, status INTO v_po_id, v_cur_status
    FROM purchase_orders WHERE id = p_po_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order not found'; END IF;
    IF v_cur_status NOT IN ('draft') THEN
      RAISE EXCEPTION 'Cannot edit a % purchase order', v_cur_status;
    END IF;
    UPDATE purchase_orders SET
      branch_id = v_branch_id,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      po_date = (p_header->>'po_date')::DATE,
      delivery_address = NULLIF(p_header->>'delivery_address', ''),
      expected_date = NULLIF(p_header->>'expected_date', '')::DATE,
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      notes = NULLIF(p_header->>'notes', ''),
      total_amount = 0, updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_po_id;
  END IF;

  DELETE FROM purchase_order_lines WHERE po_id = v_po_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    INSERT INTO purchase_order_lines (
      po_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, total_amount, created_by
    ) VALUES (
      v_po_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      ROUND(v_qty * v_price, 2), auth.uid()
    );
    v_grand_total := v_grand_total + ROUND(v_qty * v_price, 2);
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE purchase_orders SET total_amount = v_grand_total, updated_at = NOW() WHERE id = v_po_id;
  RETURN v_po_id;
END;
$$;

-- ── fn_approve_purchase_order ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_approve_purchase_order(p_po_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_orders WHERE id = p_po_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft POs can be approved (current: %)', v_rec.status; END IF;
  UPDATE purchase_orders SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(),
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_po_id;
END;
$$;

-- ── fn_cancel_purchase_order ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_purchase_order(p_po_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_orders WHERE id = p_po_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status IN ('fully_received','cancelled') THEN RAISE EXCEPTION 'Cannot cancel a % purchase order', v_rec.status; END IF;
  UPDATE purchase_orders SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_po_id;
END;
$$;

-- ── fn_save_receiving_report ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_receiving_report(
  p_rr_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rr_id      UUID;
  v_company_id UUID;
  v_branch_id  UUID;
  v_rr_number  TEXT;
  v_cur_status TEXT;
  v_po_rec     purchase_orders%ROWTYPE;
  v_line       JSONB;
  v_line_no    INT := 1;
  v_has_lines  BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_po_rec FROM purchase_orders
  WHERE id = (p_header->>'po_id')::UUID AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order not found'; END IF;
  IF v_po_rec.status NOT IN ('approved','partially_received') THEN
    RAISE EXCEPTION 'PO must be approved to create RR (current: %)', v_po_rec.status;
  END IF;

  IF p_rr_id IS NULL THEN
    v_rr_number := fn_next_document_number(v_company_id, v_branch_id, 'RR');
    INSERT INTO receiving_reports (
      company_id, branch_id, rr_number, rr_date, po_id, supplier_id,
      supplier_name_snapshot, supplier_dr_no, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_rr_number,
      (p_header->>'rr_date')::DATE,
      v_po_rec.id, v_po_rec.supplier_id,
      v_po_rec.supplier_name_snapshot,
      NULLIF(p_header->>'supplier_dr_no', ''),
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_rr_id;
  ELSE
    SELECT id, status INTO v_rr_id, v_cur_status
    FROM receiving_reports WHERE id = p_rr_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Receiving report not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % RR', v_cur_status; END IF;
    UPDATE receiving_reports SET
      rr_date = (p_header->>'rr_date')::DATE,
      supplier_dr_no = NULLIF(p_header->>'supplier_dr_no', ''),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_rr_id;
  END IF;

  DELETE FROM receiving_report_lines WHERE rr_id = v_rr_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    INSERT INTO receiving_report_lines (
      rr_id, company_id, po_line_id, line_number,
      item_id, description, ordered_qty, received_qty, reject_qty,
      uom_id, unit_price, created_by
    ) VALUES (
      v_rr_id, v_company_id,
      NULLIF(v_line->>'po_line_id', '')::UUID,
      v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description',
      COALESCE((v_line->>'ordered_qty')::NUMERIC, 0),
      GREATEST(COALESCE((v_line->>'received_qty')::NUMERIC, 0), 0),
      GREATEST(COALESCE((v_line->>'reject_qty')::NUMERIC, 0), 0),
      NULLIF(v_line->>'uom_id', '')::UUID,
      COALESCE((v_line->>'unit_price')::NUMERIC, 0),
      auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  RETURN v_rr_id;
END;
$$;

-- ── fn_confirm_receiving_report ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_confirm_receiving_report(p_rr_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rr    receiving_reports%ROWTYPE;
  v_total_ordered  NUMERIC(15,4);
  v_total_received NUMERIC(15,4);
BEGIN
  SELECT * INTO v_rr FROM receiving_reports WHERE id = p_rr_id;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rr.status != 'draft' THEN RAISE EXCEPTION 'Only draft RRs can be confirmed (current: %)', v_rr.status; END IF;

  UPDATE receiving_reports SET status = 'received', confirmed_by = auth.uid(), confirmed_at = NOW(),
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_rr_id;

  -- Update PO receiving status
  SELECT SUM(pol.quantity), SUM(rrl.received_qty)
  INTO v_total_ordered, v_total_received
  FROM purchase_order_lines pol
  LEFT JOIN receiving_report_lines rrl ON rrl.po_line_id = pol.id
    AND rrl.rr_id IN (SELECT id FROM receiving_reports WHERE po_id = v_rr.po_id AND status = 'received')
  WHERE pol.po_id = v_rr.po_id;

  UPDATE purchase_orders SET
    status = CASE
      WHEN v_total_received >= v_total_ordered THEN 'fully_received'
      ELSE 'partially_received'
    END,
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_rr.po_id;
END;
$$;

-- ── fn_save_cash_purchase ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_cash_purchase(
  p_cp_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cp_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_cp_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_vat_rate     NUMERIC(5,2);
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_taxable      NUMERIC(15,2) := 0;
  v_zero_rated   NUMERIC(15,2) := 0;
  v_exempt       NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'transaction_date')::DATE
    AND end_date   >= (p_header->>'transaction_date')::DATE
    AND is_locked = false LIMIT 1;

  IF p_cp_id IS NULL THEN
    v_cp_number := fn_next_document_number(v_company_id, v_branch_id, 'CP');
    INSERT INTO cash_purchases (
      company_id, branch_id, cp_number, transaction_date,
      supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      payment_account_id, payment_method, reference_number,
      fiscal_period_id, remarks, total_taxable_amount, total_zero_rated_amount,
      total_exempt_amount, total_input_vat_amount, total_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_cp_number,
      (p_header->>'transaction_date')::DATE,
      NULLIF(p_header->>'supplier_id', '')::UUID,
      NULLIF(p_header->>'supplier_name_snapshot', ''),
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'payment_account_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      NULLIF(p_header->>'reference_number', ''),
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_cp_id;
  ELSE
    SELECT id, status INTO v_cp_id, v_cur_status
    FROM cash_purchases WHERE id = p_cp_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash purchase not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % cash purchase', v_cur_status; END IF;
    UPDATE cash_purchases SET
      transaction_date = (p_header->>'transaction_date')::DATE,
      supplier_id = NULLIF(p_header->>'supplier_id', '')::UUID,
      supplier_name_snapshot = NULLIF(p_header->>'supplier_name_snapshot', ''),
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      payment_account_id = NULLIF(p_header->>'payment_account_id', '')::UUID,
      payment_method = COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      reference_number = NULLIF(p_header->>'reference_number', ''),
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0,
      total_exempt_amount = 0, total_input_vat_amount = 0, total_amount = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cp_id;
  END IF;

  DELETE FROM cash_purchase_lines WHERE cp_id = v_cp_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_net + v_vat_amt;
    INSERT INTO cash_purchase_lines (
      cp_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_cp_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_net + v_vat_amt,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE cash_purchases SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, updated_at = NOW()
  WHERE id = v_cp_id;
  RETURN v_cp_id;
END;
$$;

-- ── fn_post_cash_purchase ─────────────────────────────────────────────────────
-- DR Expense accounts + DR Input VAT = CR Cash/Bank account
CREATE OR REPLACE FUNCTION fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM cash_purchases WHERE id = p_cp_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft cash purchases can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  v_cash_acct := COALESCE(v_rec.payment_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'Payment account not set. Add it on the form or configure a default cash account.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND (NOT FOUND OR v_cfg.input_vat_account_id IS NULL) THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.transaction_date
    AND end_date >= v_rec.transaction_date AND is_locked = false LIMIT 1;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CP-' || v_rec.cp_number, v_rec.transaction_date, v_fp_id,
    'Cash Purchase ' || v_rec.cp_number || COALESCE(' — ' || v_rec.supplier_name_snapshot, ''),
    'MANUAL', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Expense accounts per line
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM cash_purchase_lines
    WHERE cp_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- DR: Input VAT
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.cp_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  -- CR: Cash / Bank
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cash_acct,
          'Cash paid — ' || v_rec.cp_number, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE cash_purchases SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_save_vendor_credit ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_vendor_credit(
  p_vc_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_vc_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_vc_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_vat_rate     NUMERIC(5,2);
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_taxable      NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'credit_date')::DATE
    AND end_date   >= (p_header->>'credit_date')::DATE
    AND is_locked = false LIMIT 1;

  IF p_vc_id IS NULL THEN
    v_vc_number := fn_next_document_number(v_company_id, v_branch_id, 'VC');
    INSERT INTO vendor_credits (
      company_id, branch_id, vc_number, credit_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot, supplier_cm_no,
      reference_bill_id, fiscal_period_id, remarks,
      total_taxable_amount, total_input_vat_amount, total_amount, remaining_balance,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_vc_number,
      (p_header->>'credit_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'supplier_cm_no', ''),
      NULLIF(p_header->>'reference_bill_id', '')::UUID,
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_vc_id;
  ELSE
    SELECT id, status INTO v_vc_id, v_cur_status
    FROM vendor_credits WHERE id = p_vc_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vendor credit not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % vendor credit', v_cur_status; END IF;
    UPDATE vendor_credits SET
      credit_date = (p_header->>'credit_date')::DATE,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_cm_no = NULLIF(p_header->>'supplier_cm_no', ''),
      reference_bill_id = NULLIF(p_header->>'reference_bill_id', '')::UUID,
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_input_vat_amount = 0,
      total_amount = 0, remaining_balance = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_vc_id;
  END IF;

  DELETE FROM vendor_credit_lines WHERE vc_id = v_vc_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc2.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc2 JOIN tax_codes tc ON tc.id = vc2.tax_code_id
    WHERE vc2.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    IF v_vat_class = 'regular' THEN v_taxable := v_taxable + v_net; END IF;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_net + v_vat_amt;
    INSERT INTO vendor_credit_lines (
      vc_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_vc_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_net + v_vat_amt,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE vendor_credits SET
    total_taxable_amount = v_taxable, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, remaining_balance = v_grand_total,
    updated_at = NOW()
  WHERE id = v_vc_id;
  RETURN v_vc_id;
END;
$$;

-- ── fn_post_vendor_credit ─────────────────────────────────────────────────────
-- DR Accounts Payable = CR Expense accounts + CR Input VAT
CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.credit_date
    AND end_date >= v_rec.credit_date AND is_locked = false LIMIT 1;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date, v_fp_id,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'MANUAL', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Payable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  -- CR: Expense accounts per line
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  -- CR: Input VAT reversal
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_save_supplier_debit_memo ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_supplier_debit_memo(
  p_sdm_id UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sdm_id     UUID;
  v_company_id UUID;
  v_branch_id  UUID;
  v_sdm_number TEXT;
  v_cur_status TEXT;
  v_line       JSONB;
  v_line_no    INT := 1;
  v_qty        NUMERIC(15,4);
  v_price      NUMERIC(15,4);
  v_grand_total NUMERIC(15,2) := 0;
  v_has_lines  BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF p_sdm_id IS NULL THEN
    v_sdm_number := fn_next_document_number(v_company_id, v_branch_id, 'SDM');
    INSERT INTO supplier_debit_memos (
      company_id, branch_id, sdm_number, dm_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot,
      reference_doc_id, reference_doc_type, reason, total_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_sdm_number,
      (p_header->>'dm_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'reference_doc_id', '')::UUID,
      NULLIF(p_header->>'reference_doc_type', ''),
      NULLIF(p_header->>'reason', ''),
      0, 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_sdm_id;
  ELSE
    SELECT id, status INTO v_sdm_id, v_cur_status
    FROM supplier_debit_memos WHERE id = p_sdm_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
    IF v_cur_status NOT IN ('draft') THEN RAISE EXCEPTION 'Cannot edit a % debit memo', v_cur_status; END IF;
    UPDATE supplier_debit_memos SET
      dm_date = (p_header->>'dm_date')::DATE,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      reason = NULLIF(p_header->>'reason', ''),
      total_amount = 0, updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_sdm_id;
  END IF;

  DELETE FROM supplier_debit_memo_lines WHERE sdm_id = v_sdm_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    INSERT INTO supplier_debit_memo_lines (
      sdm_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, total_amount, created_by
    ) VALUES (
      v_sdm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      ROUND(v_qty * v_price, 2), auth.uid()
    );
    v_grand_total := v_grand_total + ROUND(v_qty * v_price, 2);
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE supplier_debit_memos SET total_amount = v_grand_total, updated_at = NOW() WHERE id = v_sdm_id;
  RETURN v_sdm_id;
END;
$$;

-- ── fn_send_supplier_debit_memo ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_send_supplier_debit_memo(p_sdm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec supplier_debit_memos%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM supplier_debit_memos WHERE id = p_sdm_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft memos can be sent (current: %)', v_rec.status; END IF;
  UPDATE supplier_debit_memos SET status = 'sent', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_sdm_id;
END;
$$;

-- ── fn_acknowledge_supplier_debit_memo ───────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_acknowledge_supplier_debit_memo(p_sdm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec supplier_debit_memos%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM supplier_debit_memos WHERE id = p_sdm_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'sent' THEN RAISE EXCEPTION 'Only sent memos can be acknowledged (current: %)', v_rec.status; END IF;
  UPDATE supplier_debit_memos SET status = 'acknowledged', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_sdm_id;
END;
$$;

-- ── fn_save_purchase_return ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_purchase_return(
  p_return_id UUID,
  p_header    JSONB,
  p_lines     JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ret_id     UUID;
  v_company_id UUID;
  v_branch_id  UUID;
  v_ret_number TEXT;
  v_cur_status TEXT;
  v_rr_rec     receiving_reports%ROWTYPE;
  v_line       JSONB;
  v_line_no    INT := 1;
  v_has_lines  BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_rr_rec FROM receiving_reports
  WHERE id = (p_header->>'rr_id')::UUID AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receiving report not found'; END IF;
  IF v_rr_rec.status != 'received' THEN
    RAISE EXCEPTION 'RR must be confirmed to create a return (current: %)', v_rr_rec.status;
  END IF;

  IF p_return_id IS NULL THEN
    v_ret_number := fn_next_document_number(v_company_id, v_branch_id, 'PRT');
    INSERT INTO purchase_returns (
      company_id, branch_id, return_number, return_date,
      rr_id, supplier_id, supplier_name_snapshot, remarks,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_ret_number,
      (p_header->>'return_date')::DATE,
      v_rr_rec.id, v_rr_rec.supplier_id, v_rr_rec.supplier_name_snapshot,
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_ret_id;
  ELSE
    SELECT id, status INTO v_ret_id, v_cur_status
    FROM purchase_returns WHERE id = p_return_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase return not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % return', v_cur_status; END IF;
    UPDATE purchase_returns SET
      return_date = (p_header->>'return_date')::DATE,
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_ret_id;
  END IF;

  DELETE FROM purchase_return_lines WHERE return_id = v_ret_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    INSERT INTO purchase_return_lines (
      return_id, company_id, rr_line_id, line_number,
      item_id, description, max_qty, return_qty, uom_id, unit_price, reason, created_by
    ) VALUES (
      v_ret_id, v_company_id,
      NULLIF(v_line->>'rr_line_id', '')::UUID,
      v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description',
      GREATEST(COALESCE((v_line->>'max_qty')::NUMERIC, 0), 0),
      GREATEST(LEAST(
        COALESCE((v_line->>'return_qty')::NUMERIC, 0),
        COALESCE((v_line->>'max_qty')::NUMERIC, 0)
      ), 0),
      NULLIF(v_line->>'uom_id', '')::UUID,
      COALESCE((v_line->>'unit_price')::NUMERIC, 0),
      NULLIF(v_line->>'reason', ''),
      auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  RETURN v_ret_id;
END;
$$;

-- ── fn_ship_purchase_return ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_ship_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_returns%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_returns WHERE id = p_return_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft returns can be shipped (current: %)', v_rec.status; END IF;
  UPDATE purchase_returns SET status = 'shipped', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_return_id;
END;
$$;

-- ── fn_complete_purchase_return ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_complete_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_returns%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_returns WHERE id = p_return_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'shipped' THEN RAISE EXCEPTION 'Only shipped returns can be completed (current: %)', v_rec.status; END IF;
  UPDATE purchase_returns SET status = 'completed', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_return_id;
END;
$$;

-- ── fn_update_payment_tracking ────────────────────────────────────────────────
-- p_action: 'released' | 'cleared' | 'stale'
CREATE OR REPLACE FUNCTION fn_update_payment_tracking(
  p_voucher_id UUID,
  p_action     TEXT,
  p_date       DATE DEFAULT NULL,
  p_remarks    TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec payment_vouchers%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status NOT IN ('posted','released','cleared','stale') THEN
    RAISE EXCEPTION 'Cannot update tracking on a % voucher', v_rec.status;
  END IF;
  IF p_action = 'released' THEN
    UPDATE payment_vouchers SET status = 'released', date_released = COALESCE(p_date, CURRENT_DATE),
      released_by = auth.uid(), remarks = COALESCE(p_remarks, remarks), updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_voucher_id;
  ELSIF p_action = 'cleared' THEN
    UPDATE payment_vouchers SET status = 'cleared', date_cleared = COALESCE(p_date, CURRENT_DATE),
      cleared_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_voucher_id;
  ELSIF p_action = 'stale' THEN
    UPDATE payment_vouchers SET status = 'stale', updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_voucher_id;
  ELSE
    RAISE EXCEPTION 'Unknown action: %', p_action;
  END IF;
END;
$$;

-- Also update the status check on payment_vouchers to allow new tracking states
ALTER TABLE payment_vouchers DROP CONSTRAINT IF EXISTS payment_vouchers_status_check;
ALTER TABLE payment_vouchers ADD CONSTRAINT payment_vouchers_status_check
  CHECK (status IN ('draft','posted','released','cleared','stale','cancelled'));

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_save_purchase_order(UUID, JSONB, JSONB)         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_purchase_order(UUID)                    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_purchase_order(UUID)                     TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_receiving_report(UUID, JSONB, JSONB)       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_confirm_receiving_report(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_cash_purchase(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_cash_purchase(UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_vendor_credit(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_supplier_debit_memo(UUID, JSONB, JSONB)    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_send_supplier_debit_memo(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_acknowledge_supplier_debit_memo(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_purchase_return(UUID, JSONB, JSONB)        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ship_purchase_return(UUID)                      TO authenticated;
GRANT EXECUTE ON FUNCTION fn_complete_purchase_return(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_update_payment_tracking(UUID, TEXT, DATE, TEXT) TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000019_hardening_v2.sql                                         │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- HARDENING V2: Accounting Integrity Fixes
-- Covers: C0 FK patches for existing installs, reference_doc_type extension,
-- period enforcement, EWT/ATC validation, CWT bug fix, reversal JEs,
-- CM/DM GL posting, tax ledger, vendor credit applications, purchase return GL
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. FK patches for existing installs (017 migration had wrong table refs) ─

-- Drop the wrong constraint on vendor_bills.void_reason_id → void_reasons
-- and recreate pointing to void_reason_codes (global reference table)
ALTER TABLE vendor_bills
  DROP CONSTRAINT IF EXISTS vendor_bills_void_reason_id_fkey;
ALTER TABLE vendor_bills
  ADD CONSTRAINT vendor_bills_void_reason_id_fkey
    FOREIGN KEY (void_reason_id) REFERENCES void_reason_codes(id);

-- Drop the wrong constraint on payment_vouchers.payment_mode_id → payment_modes
-- and recreate pointing to ref_payment_modes (canonical global reference table)
ALTER TABLE payment_vouchers
  DROP CONSTRAINT IF EXISTS payment_vouchers_payment_mode_id_fkey;
ALTER TABLE payment_vouchers
  ADD CONSTRAINT payment_vouchers_payment_mode_id_fkey
    FOREIGN KEY (payment_mode_id) REFERENCES ref_payment_modes(id);

-- ── 2. Extend reference_doc_type to include AP document types ─────────────────

ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_reference_doc_type_check;
ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_reference_doc_type_check
    CHECK (reference_doc_type IN ('SI','OR','CM','DM','MANUAL','VB','PV','CP','VC','REV'));

-- ── 3. New tables ─────────────────────────────────────────────────────────────

-- tax_detail_entries: immutable tax ledger populated at posting time
CREATE TABLE IF NOT EXISTS tax_detail_entries (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID          NOT NULL REFERENCES companies(id),
  branch_id             UUID          REFERENCES branches(id),
  source_doc_type       TEXT          NOT NULL,
  source_doc_id         UUID          NOT NULL,
  tax_kind              TEXT          NOT NULL
                                      CHECK (tax_kind IN ('output_vat','input_vat','ewt_payable','cwt_receivable','percentage_tax')),
  tax_code_id           UUID          REFERENCES tax_codes(id),
  vat_code_id           UUID          REFERENCES vat_codes(id),
  atc_code_id           UUID          REFERENCES atc_codes(id),
  tax_base              NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_rate              NUMERIC(5,2),
  tax_amount            NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_period_id         UUID          REFERENCES fiscal_periods(id),
  posting_date          DATE          NOT NULL,
  document_date         DATE          NOT NULL,
  counterparty_id       UUID,
  counterparty_tin      TEXT,
  counterparty_name     TEXT,
  is_reversal           BOOLEAN       NOT NULL DEFAULT false,
  reverses_tax_detail_id UUID         REFERENCES tax_detail_entries(id),
  filing_status         TEXT          NOT NULL DEFAULT 'draft'
                                      CHECK (filing_status IN ('draft','final','filed','amended')),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tde_company_period ON tax_detail_entries (company_id, tax_period_id, tax_kind);
CREATE INDEX IF NOT EXISTS idx_tde_source         ON tax_detail_entries (source_doc_type, source_doc_id);

ALTER TABLE tax_detail_entries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tde_read" ON tax_detail_entries;
CREATE POLICY "tde_read"   ON tax_detail_entries FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "tde_insert" ON tax_detail_entries;
CREATE POLICY "tde_insert" ON tax_detail_entries FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

-- vendor_credit_applications: track how vendor credits are applied to vendor bills
CREATE TABLE IF NOT EXISTS vendor_credit_applications (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID          NOT NULL REFERENCES companies(id),
  vendor_credit_id UUID          NOT NULL REFERENCES vendor_credits(id),
  vendor_bill_id   UUID          NOT NULL REFERENCES vendor_bills(id),
  applied_amount   NUMERIC(15,2) NOT NULL CHECK (applied_amount > 0),
  applied_date     DATE          NOT NULL,
  applied_by       UUID,
  remarks          TEXT,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (vendor_credit_id, vendor_bill_id)
);

CREATE INDEX IF NOT EXISTS idx_vca_credit ON vendor_credit_applications (vendor_credit_id);
CREATE INDEX IF NOT EXISTS idx_vca_bill   ON vendor_credit_applications (vendor_bill_id);

ALTER TABLE vendor_credit_applications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "vca_read" ON vendor_credit_applications;
CREATE POLICY "vca_read"   ON vendor_credit_applications FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS "vca_insert" ON vendor_credit_applications;
CREATE POLICY "vca_insert" ON vendor_credit_applications FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
DROP POLICY IF EXISTS "vca_delete" ON vendor_credit_applications;
CREATE POLICY "vca_delete" ON vendor_credit_applications FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── 4. Column additions ───────────────────────────────────────────────────────

ALTER TABLE purchase_returns ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id);
ALTER TABLE credit_memos     ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id);
ALTER TABLE credit_memos     ADD COLUMN IF NOT EXISTS posted_at        TIMESTAMPTZ;
ALTER TABLE credit_memos     ADD COLUMN IF NOT EXISTS posted_by        UUID;
ALTER TABLE debit_memos      ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id);
ALTER TABLE debit_memos      ADD COLUMN IF NOT EXISTS posted_at        TIMESTAMPTZ;
ALTER TABLE debit_memos      ADD COLUMN IF NOT EXISTS posted_by        UUID;

-- ── 5. Fix fn_save_cash_sale: CWT accounting bug ──────────────────────────────
-- Bug: receipt JE debited Cash at gross + CWT and credited AR at gross + CWT.
-- Fix: DR Cash = gross − CWT (net received), DR CWT Receivable = CWT, CR AR = gross.

CREATE OR REPLACE FUNCTION fn_save_cash_sale(
  p_header       JSONB,
  p_lines        JSONB,
  p_cwt_amount   NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id    UUID;
  v_branch_id     UUID;
  v_si_id         UUID;
  v_receipt_id    UUID;
  v_si_number     TEXT;
  v_or_number     TEXT;
  v_cfg           company_accounting_config%ROWTYPE;
  v_cash_acct     UUID;
  v_fp_id         UUID;
  v_je_si_id      UUID;
  v_je_or_id      UUID;
  v_grand_total   NUMERIC(15,2) := 0;
  v_total_vat     NUMERIC(15,2) := 0;
  v_total_cr      NUMERIC(15,2) := 0;
  v_rev_line      RECORD;
  v_rev_line_no   INT;
  v_line          JSONB;
  v_net           NUMERIC(15,2);
  v_vat           NUMERIC(15,2);
  v_line_no_si    INT := 1;
  v_cash_received NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id','')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := NULLIF(p_header->>'bank_account_id','')::UUID;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := v_cfg.default_cash_account_id;
  END IF;
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No cash/bank account specified and no default cash account configured.';
  END IF;
  IF p_cwt_amount > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld (CWT Receivable) account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for date %. Create or unlock a fiscal period.', (p_header->>'date')::DATE;
  END IF;

  -- Number series
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'CS');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Compute totals from lines
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_net         := COALESCE((v_line->>'net_amount')::NUMERIC, 0);
    v_vat         := COALESCE((v_line->>'vat_amount')::NUMERIC, 0);
    v_grand_total := v_grand_total + v_net + v_vat;
    v_total_vat   := v_total_vat + v_vat;
  END LOOP;

  -- Insert SI
  INSERT INTO sales_invoices (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    si_number, date, due_date, currency_code, remarks,
    total_amount, total_vat_amount, total_net_amount, total_taxable_amount,
    total_zero_rated_amount, total_exempt_amount,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot',''),
    v_si_number,
    (p_header->>'date')::DATE,
    (p_header->>'date')::DATE,
    COALESCE(NULLIF(p_header->>'currency_code',''),'PHP'),
    NULLIF(p_header->>'memo',''),
    v_grand_total, v_total_vat, v_grand_total - v_total_vat, v_grand_total - v_total_vat,
    0, 0,
    true, 'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_si_id;

  -- Insert SI lines
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description,
      quantity, unit_price, discount_amount, net_amount,
      vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no_si,
      NULLIF(v_line->>'item_id','')::UUID,
      v_line->>'description',
      COALESCE((v_line->>'quantity')::NUMERIC,1),
      COALESCE((v_line->>'unit_price')::NUMERIC,0),
      COALESCE((v_line->>'discount_amount')::NUMERIC,0),
      COALESCE((v_line->>'net_amount')::NUMERIC,0),
      NULLIF(v_line->>'vat_code_id','')::UUID,
      COALESCE((v_line->>'vat_amount')::NUMERIC,0),
      COALESCE((v_line->>'total_amount')::NUMERIC,0),
      NULLIF(v_line->>'revenue_account_id','')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no_si := v_line_no_si + 1;
  END LOOP;

  -- Post SI JE: DR AR, CR Revenue lines, CR VAT Payable
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id, 'posted', v_grand_total, v_grand_total, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_si_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_si_id, v_company_id, 1, v_cfg.ar_account_id, 'AR — ' || (p_header->>'customer_name_snapshot'), v_grand_total, 0, auth.uid(), auth.uid());

  v_rev_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_rev_line.revenue_account_id, 'Revenue — ' || v_rev_line.ln_desc, 0, v_rev_line.net_sum, auth.uid(), auth.uid());
    v_total_cr    := v_total_cr + v_rev_line.net_sum;
    v_rev_line_no := v_rev_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_si_number, 0, v_total_vat, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_total_vat;
  END IF;

  UPDATE sales_invoices SET
    status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_si_id, approved_by = auth.uid(), approved_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- ── Receipt JE (CWT fix) ─────────────────────────────────────────────────
  -- v_grand_total = full invoice amount (what AR carries)
  -- p_cwt_amount  = portion withheld by customer as EWT/CWT
  -- v_cash_received = actual cash deposited = grand_total − cwt
  v_cash_received := v_grand_total - p_cwt_amount;

  INSERT INTO receipts (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    receipt_number, receipt_date, payment_mode_id, bank_account_id,
    total_amount, total_cwt, remarks, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot',''),
    v_or_number, (p_header->>'date')::DATE,
    NULLIF(p_header->>'payment_mode_id','')::UUID, v_cash_acct,
    v_grand_total, p_cwt_amount, 'Cash Sale — ' || v_si_number,
    'posted', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total, p_cwt_amount, auth.uid(), auth.uid());

  -- Post receipt JE: DR Cash (net) + DR CWT Receivable = CR AR (gross)
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-OR-' || v_or_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id, 'posted', v_grand_total, v_grand_total, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_or_id;

  -- DR: Cash / Bank (net of CWT)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, 1, v_cash_acct, 'Cash received — ' || v_or_number, v_cash_received, 0, auth.uid(), auth.uid());

  -- DR: CWT Receivable (tax withheld by customer, to be reclaimed)
  IF p_cwt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_or_id, v_company_id, 2, v_cfg.ewt_withheld_account_id, 'CWT receivable — ' || v_or_number, p_cwt_amount, 0, auth.uid(), auth.uid());
  END IF;

  -- CR: Accounts Receivable (full invoice amount)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_cfg.ar_account_id, 'AR cleared — ' || v_or_number, 0, v_grand_total, auth.uid(), auth.uid());

  UPDATE receipts SET journal_entry_id = v_je_or_id, posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number
  );
END;
$$;

-- ── 6. Fix fn_post_vendor_bill: period enforcement + correct doc type ─────────

CREATE OR REPLACE FUNCTION fn_post_vendor_bill(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec      vendor_bills%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_line_no  INT;
  v_total_dr NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved bills can be posted (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.bill_date
    AND end_date >= v_rec.bill_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for bill date %. Create or unlock a fiscal period first.', v_rec.bill_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date, v_fp_id,
    'Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
    'VB', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  v_line_no := 1;
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_bill_lines
    WHERE vendor_bill_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.bill_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE vendor_bills SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Populate tax ledger for input VAT
  IF v_rec.total_input_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id,
      'input_vat', v_rec.total_taxable_amount, v_rec.total_input_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END IF;
END;
$$;

-- ── 7. Fix fn_post_payment_voucher: period enforcement, EWT/ATC, doc type ─────

CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ap_dr     NUMERIC(15,2);
  v_line_no   INT := 1;
  v_pvl       RECORD;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft vouchers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_ewt > 0 AND v_cfg.ewt_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on voucher and no default cash account configured.';
  END IF;

  -- Validate: EWT amount > 0 requires ATC code per line
  FOR v_pvl IN
    SELECT id, ewt_amount, atc_code_id FROM payment_voucher_lines
    WHERE payment_voucher_id = p_voucher_id AND ewt_amount > 0
  LOOP
    IF v_pvl.atc_code_id IS NULL THEN
      RAISE EXCEPTION 'ATC code is required on payment voucher line when EWT amount is specified. Set the ATC code before posting.';
    END IF;
  END LOOP;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for voucher date %. Create or unlock a fiscal period first.', v_rec.voucher_date;
  END IF;

  v_ap_dr := v_rec.total_amount + v_rec.total_ewt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date, v_fp_id,
    'Payment Voucher ' || v_rec.voucher_number || ' — ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id, 'posted',
    v_ap_dr, v_ap_dr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP cleared — ' || v_rec.voucher_number, v_ap_dr, 0, auth.uid(), auth.uid());

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 2, v_cash_acct,
          'Cash paid — ' || v_rec.voucher_number, 0, v_rec.total_amount, auth.uid(), auth.uid());
  v_line_no := 3;

  IF v_rec.total_ewt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ewt_payable_account_id,
            'EWT withheld — ' || v_rec.voucher_number, 0, v_rec.total_ewt, auth.uid(), auth.uid());
    v_line_no := v_line_no + 1;
  END IF;

  UPDATE payment_vouchers SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Populate EWT tax ledger
  IF v_rec.total_ewt > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id,
      'ewt_payable', v_rec.total_amount, v_rec.total_ewt, v_fp_id,
      NOW()::DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END IF;
END;
$$;

-- ── 8. Fix fn_post_cash_purchase: period enforcement + doc type ───────────────

CREATE OR REPLACE FUNCTION fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM cash_purchases WHERE id = p_cp_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft cash purchases can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  v_cash_acct := COALESCE(v_rec.payment_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'Payment account not set. Add it on the form or configure a default cash account.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND (NOT FOUND OR v_cfg.input_vat_account_id IS NULL) THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.transaction_date
    AND end_date >= v_rec.transaction_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for transaction date %. Create or unlock a fiscal period first.', v_rec.transaction_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CP-' || v_rec.cp_number, v_rec.transaction_date, v_fp_id,
    'Cash Purchase ' || v_rec.cp_number || COALESCE(' — ' || v_rec.supplier_name_snapshot, ''),
    'CP', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM cash_purchase_lines
    WHERE cp_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.cp_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cash_acct,
          'Cash paid — ' || v_rec.cp_number, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE cash_purchases SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 9. Fix fn_post_vendor_credit: period enforcement + doc type ───────────────

CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.credit_date
    AND end_date >= v_rec.credit_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for credit date %. Create or unlock a fiscal period first.', v_rec.credit_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date, v_fp_id,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'VC', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 10. fn_void_sales_invoice: add reversing JE ───────────────────────────────

CREATE OR REPLACE FUNCTION fn_void_sales_invoice(
  p_invoice_id     UUID,
  p_void_reason_id UUID,
  p_memo           TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       sales_invoices%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_orig_line RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN RAISE EXCEPTION 'Invoice is already voided'; END IF;

  IF p_void_reason_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid or inactive void reason';
  END IF;

  -- Create reversing JE only if the SI was posted
  IF v_rec.status = 'posted' AND v_rec.journal_entry_id IS NOT NULL THEN
    SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;

    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for today. Cannot post reversal. Unlock a period first.';
    END IF;

    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_rec.company_id, v_rec.branch_id,
      'JE-REV-' || v_rec.si_number, CURRENT_DATE, v_fp_id,
      'Reversal of SI ' || v_rec.si_number || ' — ' || v_rec.customer_name_snapshot,
      'REV', v_rec.id, 'posted',
      v_rec.total_amount, v_rec.total_amount,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_rev_je_id;

    FOR v_orig_line IN
      SELECT * FROM journal_entry_lines WHERE je_id = v_rec.journal_entry_id ORDER BY line_number
    LOOP
      INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
      VALUES (v_rev_je_id, v_rec.company_id, v_line_no, v_orig_line.account_id,
              'Reversal: ' || COALESCE(v_orig_line.description,''),
              v_orig_line.credit_amount, v_orig_line.debit_amount,
              auth.uid(), auth.uid());
      v_line_no := v_line_no + 1;
    END LOOP;

    -- Mark original JE as reversed
    UPDATE journal_entries SET status = 'reversed', updated_at = NOW() WHERE id = v_rec.journal_entry_id;
  END IF;

  UPDATE sales_invoices SET
    status         = 'cancelled',
    void_reason_id = p_void_reason_id,
    memo           = COALESCE(NULLIF(p_memo,''), v_rec.memo),
    updated_by     = auth.uid(),
    updated_at     = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- ── 11. fn_bounce_receipt: add reversing JE ───────────────────────────────────

CREATE OR REPLACE FUNCTION fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       receipts%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_orig_line RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted receipts can be marked as bounced (current status: %)', v_rec.status;
  END IF;

  IF v_rec.journal_entry_id IS NOT NULL THEN
    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for today. Cannot post bounce reversal. Unlock a period first.';
    END IF;

    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_rec.company_id, v_rec.branch_id,
      'JE-REV-' || v_rec.receipt_number, CURRENT_DATE, v_fp_id,
      'Bounced Receipt ' || v_rec.receipt_number,
      'REV', v_rec.id, 'posted',
      v_rec.total_amount + v_rec.total_cwt,
      v_rec.total_amount + v_rec.total_cwt,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_rev_je_id;

    FOR v_orig_line IN
      SELECT * FROM journal_entry_lines WHERE je_id = v_rec.journal_entry_id ORDER BY line_number
    LOOP
      INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
      VALUES (v_rev_je_id, v_rec.company_id, v_line_no, v_orig_line.account_id,
              'Bounce reversal: ' || COALESCE(v_orig_line.description,''),
              v_orig_line.credit_amount, v_orig_line.debit_amount,
              auth.uid(), auth.uid());
      v_line_no := v_line_no + 1;
    END LOOP;

    UPDATE journal_entries SET status = 'reversed', updated_at = NOW() WHERE id = v_rec.journal_entry_id;
  END IF;

  UPDATE receipts SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- ── 12. fn_void_vendor_bill: add reversing JE ────────────────────────────────

CREATE OR REPLACE FUNCTION fn_void_vendor_bill(
  p_bill_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_bills%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_orig_line RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN RAISE EXCEPTION 'Bill is already cancelled'; END IF;

  IF v_rec.status = 'posted' AND v_rec.journal_entry_id IS NOT NULL THEN
    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for today. Cannot post void reversal. Unlock a period first.';
    END IF;

    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_rec.company_id, v_rec.branch_id,
      'JE-REV-' || v_rec.bill_number, CURRENT_DATE, v_fp_id,
      'Void of Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
      'REV', v_rec.id, 'posted',
      v_rec.total_amount, v_rec.total_amount,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_rev_je_id;

    FOR v_orig_line IN
      SELECT * FROM journal_entry_lines WHERE je_id = v_rec.journal_entry_id ORDER BY line_number
    LOOP
      INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
      VALUES (v_rev_je_id, v_rec.company_id, v_line_no, v_orig_line.account_id,
              'Void reversal: ' || COALESCE(v_orig_line.description,''),
              v_orig_line.credit_amount, v_orig_line.debit_amount,
              auth.uid(), auth.uid());
      v_line_no := v_line_no + 1;
    END LOOP;

    UPDATE journal_entries SET status = 'reversed', updated_at = NOW() WHERE id = v_rec.journal_entry_id;

    -- Mark tax detail entries as reversed
    UPDATE tax_detail_entries SET
      filing_status = 'amended',
      is_reversal   = true
    WHERE source_doc_type = 'VB' AND source_doc_id = p_bill_id AND is_reversal = false;
  END IF;

  UPDATE vendor_bills SET status = 'cancelled', void_reason_id = p_void_reason_id,
    memo = COALESCE(p_memo, memo), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_bill_id;
END;
$$;

-- ── 13. fn_post_credit_memo: GL posting ──────────────────────────────────────
-- DR: Sales Returns (per revenue_account_id) + DR: Output VAT reversal
-- CR: Accounts Receivable

CREATE OR REPLACE FUNCTION fn_post_credit_memo(p_cm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       credit_memos%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM credit_memos WHERE id = p_cm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Credit memo cannot be posted in status: %', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date, v_fp_id,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Sales Returns per revenue account (reversal of original revenue)
  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id,
            'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- DR: Output VAT reversal
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id,
            'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  -- CR: Accounts Receivable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ar_account_id,
          'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;
END;
$$;

-- ── 14. fn_post_debit_memo: GL posting ───────────────────────────────────────
-- DR: Accounts Receivable = CR: Revenue/Charge accounts + CR: Output VAT

CREATE OR REPLACE FUNCTION fn_post_debit_memo(p_dm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       debit_memos%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 2;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM debit_memos WHERE id = p_dm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Debit memo cannot be posted in status: %', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.dm_date
    AND end_date >= v_rec.dm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for DM date %. Create or unlock a fiscal period first.', v_rec.dm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-DM-' || v_rec.dm_number, v_rec.dm_date, v_fp_id,
    'Debit Memo ' || v_rec.dm_number || ' — ' || v_rec.customer_name_snapshot,
    'DM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Receivable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id,
          'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  -- CR: Revenue/Charge accounts per line
  FOR v_line IN
    SELECT account_id, SUM(amount) AS amt_sum, description AS ln_desc
    FROM debit_memo_lines
    WHERE debit_memo_id = v_rec.id AND account_id IS NOT NULL
    GROUP BY account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.account_id,
            'DM charge — ' || v_line.ln_desc, 0, v_line.amt_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.amt_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- CR: Output VAT
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id,
            'Output VAT — ' || v_rec.dm_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'DM journal entry unbalanced: DR=% CR=%. Ensure all DM lines have GL accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE debit_memos SET
    status = 'paid', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_dm_id;
END;
$$;

-- ── 15. fn_complete_purchase_return: add GL effect ────────────────────────────
-- On completion, post a reversing GL entry:
-- DR: AP (if a vendor bill exists for the linked RR), otherwise expense accounts
-- CR: Expense accounts per line (reversal of original purchase)
-- CR: Input VAT reversal

CREATE OR REPLACE FUNCTION fn_complete_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec        purchase_returns%ROWTYPE;
  v_cfg        company_accounting_config%ROWTYPE;
  v_fp_id      UUID;
  v_je_id      UUID;
  v_vb_id      UUID;
  v_vb_posted  BOOLEAN := false;
  v_line       RECORD;
  v_line_no    INT := 1;
  v_total_cr   NUMERIC(15,2) := 0;
  v_total_vat  NUMERIC(15,2) := 0;
  v_ret_total  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM purchase_returns WHERE id = p_return_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Not found or access denied';
  END IF;
  IF v_rec.status != 'shipped' THEN
    RAISE EXCEPTION 'Only shipped returns can be completed (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;

  -- Find the linked vendor bill (if any, posted)
  SELECT vb.id, (vb.status = 'posted') INTO v_vb_id, v_vb_posted
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rec.rr_id AND vb.company_id = v_rec.company_id
  ORDER BY vb.created_at DESC LIMIT 1;

  -- Only post GL if we have an AP account and a posted vendor bill
  IF v_cfg.ap_account_id IS NOT NULL AND v_vb_posted THEN
    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;

    IF v_fp_id IS NOT NULL THEN
      -- Compute return amounts from lines
      SELECT SUM(prl.return_qty * prl.unit_price) INTO v_ret_total
      FROM purchase_return_lines prl WHERE prl.return_id = p_return_id;

      IF v_ret_total > 0 THEN
        INSERT INTO journal_entries (
          company_id, branch_id, je_number, je_date, fiscal_period_id,
          description, reference_doc_type, reference_doc_id, status,
          total_debit, total_credit, created_by, updated_by
        ) VALUES (
          v_rec.company_id, v_rec.branch_id,
          'JE-PR-' || v_rec.return_number, CURRENT_DATE, v_fp_id,
          'Purchase Return ' || v_rec.return_number || ' — ' || v_rec.supplier_name_snapshot,
          'MANUAL', v_rec.id, 'posted',
          v_ret_total, v_ret_total,
          auth.uid(), auth.uid()
        ) RETURNING id INTO v_je_id;

        -- DR: AP (reduce liability for returned goods)
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
        VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
                'AP reversal — ' || v_rec.return_number, v_ret_total, 0, auth.uid(), auth.uid());

        -- CR: Expense accounts from original vendor bill lines (matched by item)
        FOR v_line IN
          SELECT vbl.expense_account_id,
                 SUM(LEAST(prl.return_qty, rrl.received_qty) * prl.unit_price) AS rev_amount,
                 vbl.description AS ln_desc
          FROM purchase_return_lines prl
          JOIN receiving_report_lines rrl ON rrl.id = prl.rr_line_id
          JOIN vendor_bill_lines vbl
            ON vbl.vendor_bill_id = v_vb_id AND vbl.item_id = prl.item_id
          WHERE prl.return_id = p_return_id AND vbl.expense_account_id IS NOT NULL
          GROUP BY vbl.expense_account_id, vbl.description
        LOOP
          v_line_no := v_line_no + 1;
          INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
          VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
                  'Return of: ' || v_line.ln_desc, 0, v_line.rev_amount, auth.uid(), auth.uid());
          v_total_cr := v_total_cr + v_line.rev_amount;
        END LOOP;

        -- Fallback: if no matched lines, credit AP directly (manual reconciliation needed)
        IF v_total_cr = 0 THEN
          UPDATE journal_entries SET total_debit = 0, total_credit = 0 WHERE id = v_je_id;
          DELETE FROM journal_entry_lines WHERE je_id = v_je_id;
          DELETE FROM journal_entries WHERE id = v_je_id;
          v_je_id := NULL;
        END IF;
      END IF;
    END IF;
  END IF;

  UPDATE purchase_returns SET
    status = 'completed',
    journal_entry_id = v_je_id,
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_return_id;
END;
$$;

-- ── 16. Grants ────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION fn_save_cash_sale(JSONB, JSONB, NUMERIC)         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_bill(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID)                     TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_cash_purchase(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_sales_invoice(UUID, UUID, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bounce_receipt(UUID)                           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_vendor_bill(UUID, UUID, TEXT)             TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_credit_memo(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_debit_memo(UUID)                          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_complete_purchase_return(UUID)                 TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000020_period_enforcement_ar.sql                                │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- Period enforcement for AR posting functions (migration 013 gap)
-- fn_post_sales_invoice and fn_post_receipt previously allowed null fiscal_period_id,
-- meaning transactions could post outside any accounting period.
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec      sales_invoices%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_line_no  INT := 1;
  v_total_cr NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved invoices can be posted (current status: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.date AND end_date >= v_rec.date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for invoice date %. Create or unlock a fiscal period first.', v_rec.date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date, v_fp_id,
    'Sales Invoice ' || v_rec.si_number || ' — ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id, 'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());
  v_line_no := 2;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum, sil.description AS ln_desc
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id, 'Revenue — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_line_no  := v_line_no + 1;
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_rec.si_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check that all lines have revenue accounts assigned.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Populate output VAT tax ledger
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id,
      'output_vat', v_rec.total_net_amount, v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       receipts%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ar_cr     NUMERIC(15,2);
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_cwt > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.receipt_date AND end_date >= v_rec.receipt_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for receipt date %. Create or unlock a fiscal period first.', v_rec.receipt_date;
  END IF;

  -- AR is cleared at cash collected + CWT withheld (equals the original invoice balance applied)
  v_ar_cr := v_rec.total_amount + v_rec.total_cwt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date, v_fp_id,
    'Official Receipt ' || v_rec.receipt_number || ' — ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id, 'posted',
    v_ar_cr, v_ar_cr,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cash_acct, 'Cash received — ' || v_rec.receipt_number, v_rec.total_amount, 0, auth.uid(), auth.uid());

  IF v_rec.total_cwt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 2, v_cfg.ewt_withheld_account_id, 'CWT receivable — ' || v_rec.receipt_number, v_rec.total_cwt, 0, auth.uid(), auth.uid());
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
          v_cfg.ar_account_id, 'AR cleared — ' || v_rec.receipt_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID)        TO authenticated;



-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ 20260629000021_cm_dm_gl_pv_void_vc_apply.sql                            │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 021: Wire CM/DM GL posting, PV void reversal, vendor credit apply
-- Fixes identified in Transaction Flow Audit
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. fn_save_credit_memo: wire GL posting when transitioning to 'applied' ───
-- When p_next_status = 'applied', save lines as 'approved' then call
-- fn_post_credit_memo which creates the journal entry and sets to 'applied'.

CREATE OR REPLACE FUNCTION fn_save_credit_memo(
  p_cm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_cm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  -- When applying, save data as 'approved' first, then let fn_post_credit_memo
  -- create the GL entry and set the final 'applied' status.
  v_effective_status := CASE WHEN p_next_status = 'applied' THEN 'approved' ELSE p_next_status END;

  IF p_cm_id IS NULL THEN
    v_cm_number := fn_next_document_number(v_company_id, v_branch_id, 'CM');

    INSERT INTO credit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      invoice_id, cm_number, cm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'invoice_id', '')::UUID,
      v_cm_number, (p_header->>'cm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0,
      v_effective_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_cm_id;

  ELSE
    SELECT id, status INTO v_cm_id, v_current_status
    FROM credit_memos WHERE id = p_cm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found or access denied'; END IF;

    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','applied','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','applied','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition credit memo from % to %', v_current_status, p_next_status;
    END IF;

    UPDATE credit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      invoice_id = NULLIF(p_header->>'invoice_id', '')::UUID,
      cm_date = (p_header->>'cm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  DELETE FROM credit_memo_lines WHERE credit_memo_id = v_cm_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    v_total_net := v_total_net + v_net;
    v_total_vat := v_total_vat + v_vat_amt;
    v_total_amt := v_total_amt + v_total_line;

    INSERT INTO credit_memo_lines (
      credit_memo_id, company_id, line_number,
      invoice_line_id, item_id, description, quantity, unit_price,
      net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_cm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'invoice_line_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_qty, v_price,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE credit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    updated_at = NOW()
  WHERE id = v_cm_id;

  -- If the intent was 'applied', delegate to fn_post_credit_memo for GL + final status
  IF p_next_status = 'applied' THEN
    PERFORM fn_post_credit_memo(v_cm_id);
  END IF;

  RETURN v_cm_id;
END;
$$;

-- ── 2. fn_save_debit_memo: wire GL posting when transitioning to 'paid' ───────
-- When p_next_status = 'paid', save lines as 'approved' then call
-- fn_post_debit_memo which creates the journal entry and sets to 'paid'.

CREATE OR REPLACE FUNCTION fn_save_debit_memo(
  p_dm_id       UUID,
  p_header      JSONB,
  p_lines       JSONB,
  p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_dm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_amount         NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF p_next_status NOT IN ('draft','approved','paid','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  -- When posting, save data as 'approved' first, then let fn_post_debit_memo
  -- create the GL entry and set the final 'paid' status.
  v_effective_status := CASE WHEN p_next_status = 'paid' THEN 'approved' ELSE p_next_status END;

  IF p_dm_id IS NULL THEN
    v_dm_number := fn_next_document_number(v_company_id, v_branch_id, 'DM-S');

    INSERT INTO debit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      source_doc_type, source_doc_id, dm_number, dm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'source_doc_type', ''),
      NULLIF(p_header->>'source_doc_id', '')::UUID,
      v_dm_number, (p_header->>'dm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0,
      v_effective_status,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_dm_id;

  ELSE
    SELECT id, status INTO v_dm_id, v_current_status
    FROM debit_memos WHERE id = p_dm_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found or access denied'; END IF;

    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','paid','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','paid','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition debit memo from % to %', v_current_status, p_next_status;
    END IF;

    UPDATE debit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      source_doc_type = NULLIF(p_header->>'source_doc_type', ''),
      source_doc_id = NULLIF(p_header->>'source_doc_id', '')::UUID,
      dm_date = (p_header->>'dm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_dm_id;
  END IF;

  DELETE FROM debit_memo_lines WHERE debit_memo_id = v_dm_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_amount    := GREATEST(COALESCE((v_line->>'amount')::NUMERIC, 0), 0);
    v_vat_amt   := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_amount * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_amount + v_vat_amt;

    v_total_net := v_total_net + v_amount;
    v_total_vat := v_total_vat + v_vat_amt;
    v_total_amt := v_total_amt + v_total_line;

    INSERT INTO debit_memo_lines (
      debit_memo_id, company_id, line_number,
      account_id, item_id, description, amount,
      vat_code_id, vat_amount, total_amount,
      created_by, updated_by
    ) VALUES (
      v_dm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'account_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_amount,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE debit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    updated_at = NOW()
  WHERE id = v_dm_id;

  -- If the intent was 'paid', delegate to fn_post_debit_memo for GL + final status
  IF p_next_status = 'paid' THEN
    PERFORM fn_post_debit_memo(v_dm_id);
  END IF;

  RETURN v_dm_id;
END;
$$;

-- ── 3. fn_cancel_payment_voucher: void a posted PV with reversing JE ──────────

CREATE OR REPLACE FUNCTION fn_cancel_payment_voucher(
  p_voucher_id UUID,
  p_memo       TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_orig_je   journal_entries%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted payment vouchers can be voided (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_orig_je FROM journal_entries WHERE id = v_rec.journal_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original journal entry not found for this payment voucher'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for today. Create or unlock a fiscal period to process this void.';
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VOID-' || v_rec.voucher_number, CURRENT_DATE, v_fp_id,
    'VOID: ' || v_orig_je.description || COALESCE(' — ' || p_memo, ''),
    'PV', v_rec.id, 'posted',
    v_orig_je.total_debit, v_orig_je.total_credit,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_rev_je_id;

  FOR v_line IN
    SELECT * FROM journal_entry_lines WHERE je_id = v_orig_je.id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_rev_je_id, v_rec.company_id, v_line_no, v_line.account_id,
      'VOID — ' || v_line.description,
      v_line.credit_amount, v_line.debit_amount,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE journal_entries SET status = 'reversed', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_orig_je.id;

  UPDATE payment_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 4. fn_apply_vendor_credit: record credit application against a vendor bill ─
-- No new GL entry needed — the GL was already captured when the vendor credit was
-- posted (DR AP, CR Expense + Input VAT). This RPC tracks the allocation and
-- reduces the credit's remaining balance.

CREATE OR REPLACE FUNCTION fn_apply_vendor_credit(
  p_credit_id UUID,
  p_bill_id   UUID,
  p_amount    NUMERIC,
  p_date      DATE    DEFAULT CURRENT_DATE,
  p_remarks   TEXT    DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vc              vendor_credits%ROWTYPE;
  v_bill            vendor_bills%ROWTYPE;
  v_bill_paid       NUMERIC(15,2);
  v_bill_applied    NUMERIC(15,2);
  v_bill_outstanding NUMERIC(15,2);
  v_new_balance     NUMERIC(15,2);
  v_app_id          UUID;
BEGIN
  SELECT * INTO v_vc FROM vendor_credits WHERE id = p_credit_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor credit not found'; END IF;
  IF NOT is_company_member(v_vc.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_vc.status != 'open' THEN
    RAISE EXCEPTION 'Vendor credit must be in open status to apply (current: %)', v_vc.status;
  END IF;

  SELECT * INTO v_bill FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF v_bill.company_id != v_vc.company_id THEN
    RAISE EXCEPTION 'Credit and bill must belong to the same company';
  END IF;
  IF v_bill.supplier_id != v_vc.supplier_id THEN
    RAISE EXCEPTION 'Credit and bill must be for the same supplier';
  END IF;
  IF v_bill.status != 'posted' THEN
    RAISE EXCEPTION 'Vendor bill must be posted to apply credits (current: %)', v_bill.status;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Application amount must be greater than zero';
  END IF;
  IF p_amount > v_vc.remaining_balance THEN
    RAISE EXCEPTION 'Amount (%) exceeds vendor credit remaining balance (%)', p_amount, v_vc.remaining_balance;
  END IF;

  SELECT COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
  INTO v_bill_paid
  FROM payment_voucher_lines pvl
  JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
  WHERE pvl.vendor_bill_id = p_bill_id AND pv.status = 'posted';

  SELECT COALESCE(SUM(applied_amount), 0)
  INTO v_bill_applied
  FROM vendor_credit_applications
  WHERE vendor_bill_id = p_bill_id;

  v_bill_outstanding := v_bill.total_amount - v_bill_paid - v_bill_applied;

  IF v_bill_outstanding <= 0 THEN
    RAISE EXCEPTION 'Vendor bill has no outstanding balance';
  END IF;
  IF p_amount > v_bill_outstanding THEN
    RAISE EXCEPTION 'Amount (%) exceeds bill outstanding balance (%)', p_amount, v_bill_outstanding;
  END IF;

  INSERT INTO vendor_credit_applications (
    company_id, vendor_credit_id, vendor_bill_id, applied_amount, applied_date, applied_by, remarks
  ) VALUES (
    v_vc.company_id, p_credit_id, p_bill_id, p_amount, p_date, auth.uid(), p_remarks
  ) RETURNING id INTO v_app_id;

  v_new_balance := v_vc.remaining_balance - p_amount;
  UPDATE vendor_credits SET
    remaining_balance = v_new_balance,
    status = CASE WHEN v_new_balance = 0 THEN 'applied' ELSE status END,
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_credit_id;

  RETURN v_app_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_credit_memo(UUID, JSONB, JSONB, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_debit_memo(UUID, JSONB, JSONB, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_payment_voucher(UUID, TEXT)                   TO authenticated;
GRANT EXECUTE ON FUNCTION fn_apply_vendor_credit(UUID, UUID, NUMERIC, DATE, TEXT) TO authenticated;



