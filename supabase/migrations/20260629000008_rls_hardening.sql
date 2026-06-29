-- ══════════════════════════════════════════════════════════════════════════════
-- RLS HARDENING: User-company membership model
-- Replaces blanket USING (true) write policies with company-scoped enforcement.
-- READ policies remain open for authenticated users (single-org trusted context).
-- WRITE policies (INSERT/UPDATE/DELETE) require is_company_member(company_id).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. User-company membership table ──────────────────────────────────────────

CREATE TABLE user_company_memberships (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID        NOT NULL REFERENCES companies(id)  ON DELETE CASCADE,
  role       TEXT        NOT NULL DEFAULT 'member'
               CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  granted_by UUID        REFERENCES auth.users(id),
  UNIQUE (user_id, company_id)
);

CREATE INDEX idx_ucm_user    ON user_company_memberships (user_id);
CREATE INDEX idx_ucm_company ON user_company_memberships (company_id);

ALTER TABLE user_company_memberships ENABLE ROW LEVEL SECURITY;

-- Users can see their own memberships
CREATE POLICY "ucm_read_own" ON user_company_memberships
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Owners and admins can manage memberships for their companies
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

CREATE TRIGGER trg_new_user_grant_companies
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION fn_grant_new_user_all_companies();

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. RE-SCOPE EXISTING POLICIES
-- Pattern: drop old FOR ALL USING (true); replace with separate SELECT/INSERT/
--          UPDATE/DELETE where SELECT stays open and writes check membership.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Sprint 1: Organization & setup tables ─────────────────────────────────────

DROP POLICY "auth_all_branches" ON branches;
CREATE POLICY "auth_read_branches"   ON branches FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_branches" ON branches FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_branches" ON branches FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_branches" ON branches FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_departments" ON departments;
CREATE POLICY "auth_read_departments"   ON departments FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_departments" ON departments FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_departments" ON departments FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_departments" ON departments FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_cost_centers" ON cost_centers;
CREATE POLICY "auth_read_cost_centers"   ON cost_centers FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_cost_centers" ON cost_centers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_cost_centers" ON cost_centers FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_cost_centers" ON cost_centers FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_read_fiscal_years"   ON fiscal_years FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_fiscal_years" ON fiscal_years FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_fiscal_years" ON fiscal_years FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_fiscal_years" ON fiscal_years FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_read_fiscal_periods"   ON fiscal_periods FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_fiscal_periods" ON fiscal_periods FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_fiscal_periods" ON fiscal_periods FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_fiscal_periods" ON fiscal_periods FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_coa" ON chart_of_accounts;
CREATE POLICY "auth_read_coa"   ON chart_of_accounts FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_coa" ON chart_of_accounts FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_coa" ON chart_of_accounts FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_coa" ON chart_of_accounts FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_exchange_rates" ON exchange_rates;
CREATE POLICY "auth_read_exchange_rates"   ON exchange_rates FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_exchange_rates" ON exchange_rates FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_exchange_rates" ON exchange_rates FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_exchange_rates" ON exchange_rates FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_feature_enablement" ON sys_feature_enablement;
CREATE POLICY "auth_read_feature_enablement"   ON sys_feature_enablement FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_feature_enablement" ON sys_feature_enablement FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_feature_enablement" ON sys_feature_enablement FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_feature_enablement" ON sys_feature_enablement FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_number_series" ON number_series;
CREATE POLICY "auth_read_number_series"   ON number_series FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_number_series" ON number_series FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_number_series" ON number_series FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_number_series" ON number_series FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_approval_workflows" ON approval_workflows;
CREATE POLICY "auth_read_approval_workflows"   ON approval_workflows FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_approval_workflows" ON approval_workflows FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_approval_workflows" ON approval_workflows FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_approval_workflows" ON approval_workflows FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_workflow_steps" ON approval_workflow_steps;
CREATE POLICY "auth_read_workflow_steps"   ON approval_workflow_steps FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_workflow_steps" ON approval_workflow_steps FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_workflow_steps" ON approval_workflow_steps FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_workflow_steps" ON approval_workflow_steps FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_approval_instances" ON approval_instances;
CREATE POLICY "auth_read_approval_instances"   ON approval_instances FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_approval_instances" ON approval_instances FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_approval_instances" ON approval_instances FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_approval_instances" ON approval_instances FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Sprint 2/3: Master data ────────────────────────────────────────────────────

DROP POLICY "auth_all_ewt_codes" ON ewt_codes;
CREATE POLICY "auth_read_ewt_codes"   ON ewt_codes FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_ewt_codes" ON ewt_codes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_ewt_codes" ON ewt_codes FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_ewt_codes" ON ewt_codes FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_payment_terms" ON payment_terms;
CREATE POLICY "auth_read_payment_terms"   ON payment_terms FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_payment_terms" ON payment_terms FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_payment_terms" ON payment_terms FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_payment_terms" ON payment_terms FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_item_categories" ON item_categories;
CREATE POLICY "auth_read_item_categories"   ON item_categories FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_item_categories" ON item_categories FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_item_categories" ON item_categories FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_item_categories" ON item_categories FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_uom" ON units_of_measure;
CREATE POLICY "auth_read_uom"   ON units_of_measure FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_uom" ON units_of_measure FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_uom" ON units_of_measure FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_uom" ON units_of_measure FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_customers" ON customers;
CREATE POLICY "auth_read_customers"   ON customers FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_customers" ON customers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_customers" ON customers FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_customers" ON customers FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_suppliers" ON suppliers;
CREATE POLICY "auth_read_suppliers"   ON suppliers FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_suppliers" ON suppliers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_suppliers" ON suppliers FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_suppliers" ON suppliers FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_items" ON items;
CREATE POLICY "auth_read_items"   ON items FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_items" ON items FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_items" ON items FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_items" ON items FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Sprint 2 Tax: Compliance setup ────────────────────────────────────────────

DROP POLICY "auth_all_fwt_codes" ON fwt_codes;
CREATE POLICY "auth_read_fwt_codes"   ON fwt_codes FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_fwt_codes" ON fwt_codes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_fwt_codes" ON fwt_codes FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_fwt_codes" ON fwt_codes FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_pt_codes" ON percentage_tax_codes;
CREATE POLICY "auth_read_pt_codes"   ON percentage_tax_codes FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_pt_codes" ON percentage_tax_codes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_pt_codes" ON percentage_tax_codes FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_pt_codes" ON percentage_tax_codes FOR DELETE TO authenticated USING (is_company_member(company_id));

DROP POLICY "auth_all_compliance_profiles" ON compliance_profiles;
CREATE POLICY "auth_read_compliance_profiles"   ON compliance_profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_insert_compliance_profiles" ON compliance_profiles FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_compliance_profiles" ON compliance_profiles FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_compliance_profiles" ON compliance_profiles FOR DELETE TO authenticated USING (is_company_member(company_id));

-- tax_calendar_events: keep SELECT open; upgrade INSERT/UPDATE to require membership
DROP POLICY "auth_insert_tax_calendar" ON tax_calendar_events;
DROP POLICY "auth_update_pending_calendar" ON tax_calendar_events;
CREATE POLICY "auth_insert_tax_calendar" ON tax_calendar_events
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_tax_calendar" ON tax_calendar_events
  FOR UPDATE TO authenticated USING (status = 'pending' AND is_company_member(company_id));
CREATE POLICY "auth_delete_tax_calendar" ON tax_calendar_events
  FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Sprint 5: Sales transactions ──────────────────────────────────────────────

-- sales_invoices: add company member check to insert/update
DROP POLICY "insert_sales_invoices"    ON sales_invoices;
DROP POLICY "update_draft_approved_si" ON sales_invoices;
CREATE POLICY "insert_sales_invoices" ON sales_invoices
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_draft_approved_si" ON sales_invoices
  FOR UPDATE TO authenticated
  USING (status IN ('draft', 'approved') AND is_company_member(company_id));

-- sales_invoice_lines: scope via parent SI company
DROP POLICY "insert_si_lines" ON sales_invoice_lines;
DROP POLICY "update_si_lines" ON sales_invoice_lines;
DROP POLICY "delete_si_lines" ON sales_invoice_lines;
CREATE POLICY "insert_si_lines" ON sales_invoice_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM sales_invoices WHERE id = sales_invoice_id AND is_company_member(company_id))
  );
CREATE POLICY "update_si_lines" ON sales_invoice_lines
  FOR UPDATE TO authenticated
  USING (
    sales_invoice_id IN (
      SELECT id FROM sales_invoices WHERE status IN ('draft','approved') AND is_company_member(company_id)
    )
  );
CREATE POLICY "delete_si_lines" ON sales_invoice_lines
  FOR DELETE TO authenticated
  USING (
    sales_invoice_id IN (
      SELECT id FROM sales_invoices WHERE status = 'draft' AND is_company_member(company_id)
    )
  );

-- receipts
DROP POLICY "insert_receipts"       ON receipts;
DROP POLICY "update_draft_receipts" ON receipts;
CREATE POLICY "insert_receipts" ON receipts
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_draft_receipts" ON receipts
  FOR UPDATE TO authenticated USING (status IN ('draft') AND is_company_member(company_id));

-- receipt_lines
DROP POLICY "insert_receipt_lines" ON receipt_lines;
DROP POLICY "update_receipt_lines" ON receipt_lines;
DROP POLICY "delete_receipt_lines" ON receipt_lines;
CREATE POLICY "insert_receipt_lines" ON receipt_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM receipts WHERE id = receipt_id AND is_company_member(company_id))
  );
CREATE POLICY "update_receipt_lines" ON receipt_lines
  FOR UPDATE TO authenticated
  USING (
    receipt_id IN (SELECT id FROM receipts WHERE status = 'draft' AND is_company_member(company_id))
  );
CREATE POLICY "delete_receipt_lines" ON receipt_lines
  FOR DELETE TO authenticated
  USING (
    receipt_id IN (SELECT id FROM receipts WHERE status = 'draft' AND is_company_member(company_id))
  );

-- credit_memos
DROP POLICY "insert_credit_memos" ON credit_memos;
DROP POLICY "update_draft_cm"     ON credit_memos;
CREATE POLICY "insert_credit_memos" ON credit_memos
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_draft_cm" ON credit_memos
  FOR UPDATE TO authenticated USING (status IN ('draft','approved') AND is_company_member(company_id));

-- credit_memo_lines
DROP POLICY "insert_cm_lines" ON credit_memo_lines;
DROP POLICY "update_cm_lines" ON credit_memo_lines;
DROP POLICY "delete_cm_lines" ON credit_memo_lines;
CREATE POLICY "insert_cm_lines" ON credit_memo_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM credit_memos WHERE id = credit_memo_id AND is_company_member(company_id))
  );
CREATE POLICY "update_cm_lines" ON credit_memo_lines
  FOR UPDATE TO authenticated
  USING (
    credit_memo_id IN (
      SELECT id FROM credit_memos WHERE status IN ('draft','approved') AND is_company_member(company_id)
    )
  );
CREATE POLICY "delete_cm_lines" ON credit_memo_lines
  FOR DELETE TO authenticated
  USING (
    credit_memo_id IN (SELECT id FROM credit_memos WHERE status = 'draft' AND is_company_member(company_id))
  );

-- debit_memos
DROP POLICY "insert_debit_memos" ON debit_memos;
DROP POLICY "update_draft_dm"    ON debit_memos;
CREATE POLICY "insert_debit_memos" ON debit_memos
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_draft_dm" ON debit_memos
  FOR UPDATE TO authenticated USING (status IN ('draft','approved') AND is_company_member(company_id));

-- debit_memo_lines
DROP POLICY "insert_dm_lines" ON debit_memo_lines;
DROP POLICY "update_dm_lines" ON debit_memo_lines;
DROP POLICY "delete_dm_lines" ON debit_memo_lines;
CREATE POLICY "insert_dm_lines" ON debit_memo_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM debit_memos WHERE id = debit_memo_id AND is_company_member(company_id))
  );
CREATE POLICY "update_dm_lines" ON debit_memo_lines
  FOR UPDATE TO authenticated
  USING (
    debit_memo_id IN (
      SELECT id FROM debit_memos WHERE status IN ('draft','approved') AND is_company_member(company_id)
    )
  );
CREATE POLICY "delete_dm_lines" ON debit_memo_lines
  FOR DELETE TO authenticated
  USING (
    debit_memo_id IN (SELECT id FROM debit_memos WHERE status = 'draft' AND is_company_member(company_id))
  );

-- sales_quotations
DROP POLICY "insert_sq" ON sales_quotations;
DROP POLICY "update_sq" ON sales_quotations;
CREATE POLICY "insert_sq" ON sales_quotations
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_sq" ON sales_quotations
  FOR UPDATE TO authenticated USING (status IN ('draft','pending') AND is_company_member(company_id));

-- sales_quotation_lines
DROP POLICY "insert_sql" ON sales_quotation_lines;
DROP POLICY "update_sql" ON sales_quotation_lines;
DROP POLICY "delete_sql" ON sales_quotation_lines;
CREATE POLICY "insert_sql" ON sales_quotation_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM sales_quotations WHERE id = quotation_id AND is_company_member(company_id))
  );
CREATE POLICY "update_sql" ON sales_quotation_lines
  FOR UPDATE TO authenticated
  USING (
    quotation_id IN (
      SELECT id FROM sales_quotations WHERE status IN ('draft','pending') AND is_company_member(company_id)
    )
  );
CREATE POLICY "delete_sql" ON sales_quotation_lines
  FOR DELETE TO authenticated
  USING (
    quotation_id IN (
      SELECT id FROM sales_quotations WHERE status = 'draft' AND is_company_member(company_id)
    )
  );

-- sales_orders
DROP POLICY "insert_so" ON sales_orders;
DROP POLICY "update_so" ON sales_orders;
CREATE POLICY "insert_so" ON sales_orders
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_so" ON sales_orders
  FOR UPDATE TO authenticated USING (approval_status IN ('pending') AND is_company_member(company_id));

-- sales_order_lines
DROP POLICY "insert_sol" ON sales_order_lines;
DROP POLICY "update_sol" ON sales_order_lines;
DROP POLICY "delete_sol" ON sales_order_lines;
CREATE POLICY "insert_sol" ON sales_order_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM sales_orders WHERE id = sales_order_id AND is_company_member(company_id))
  );
CREATE POLICY "update_sol" ON sales_order_lines
  FOR UPDATE TO authenticated
  USING (
    sales_order_id IN (
      SELECT id FROM sales_orders WHERE approval_status = 'pending' AND is_company_member(company_id)
    )
  );
CREATE POLICY "delete_sol" ON sales_order_lines
  FOR DELETE TO authenticated
  USING (
    sales_order_id IN (
      SELECT id FROM sales_orders WHERE approval_status = 'pending' AND is_company_member(company_id)
    )
  );

-- delivery_receipts
DROP POLICY "insert_dr" ON delivery_receipts;
DROP POLICY "update_dr" ON delivery_receipts;
CREATE POLICY "insert_dr" ON delivery_receipts
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_dr" ON delivery_receipts
  FOR UPDATE TO authenticated USING (status IN ('draft','in_transit') AND is_company_member(company_id));

-- delivery_receipt_lines (FK column is dr_id)
DROP POLICY "insert_drl" ON delivery_receipt_lines;
DROP POLICY "update_drl" ON delivery_receipt_lines;
DROP POLICY "delete_drl" ON delivery_receipt_lines;
CREATE POLICY "insert_drl" ON delivery_receipt_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM delivery_receipts WHERE id = dr_id AND is_company_member(company_id))
  );
CREATE POLICY "update_drl" ON delivery_receipt_lines
  FOR UPDATE TO authenticated
  USING (
    dr_id IN (
      SELECT id FROM delivery_receipts WHERE status IN ('draft','in_transit') AND is_company_member(company_id)
    )
  );
CREATE POLICY "delete_drl" ON delivery_receipt_lines
  FOR DELETE TO authenticated
  USING (
    dr_id IN (SELECT id FROM delivery_receipts WHERE status = 'draft' AND is_company_member(company_id))
  );

-- ── Sprint 6+: Compliance documents ───────────────────────────────────────────

-- compliance_ewt_working_papers_headers
DROP POLICY "insert_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
DROP POLICY "update_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
DROP POLICY "delete_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
CREATE POLICY "insert_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "delete_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR DELETE TO authenticated USING (status = 'draft' AND is_company_member(company_id));

-- compliance_ewt_working_papers_lines (scope via parent header)
DROP POLICY "insert_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
DROP POLICY "update_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
DROP POLICY "delete_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
CREATE POLICY "insert_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM compliance_ewt_working_papers_headers
      WHERE id = header_id AND is_company_member(company_id)
    )
  );
CREATE POLICY "update_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR UPDATE TO authenticated
  USING (
    header_id IN (
      SELECT id FROM compliance_ewt_working_papers_headers WHERE is_company_member(company_id)
    )
  );
CREATE POLICY "delete_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR DELETE TO authenticated
  USING (
    header_id IN (
      SELECT id FROM compliance_ewt_working_papers_headers WHERE is_company_member(company_id)
    )
  );

-- form_2307_tracking
DROP POLICY "insert_form_2307_tracking" ON form_2307_tracking;
DROP POLICY "update_form_2307_tracking" ON form_2307_tracking;
DROP POLICY "delete_form_2307_tracking" ON form_2307_tracking;
CREATE POLICY "insert_form_2307_tracking" ON form_2307_tracking
  FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "update_form_2307_tracking" ON form_2307_tracking
  FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "delete_form_2307_tracking" ON form_2307_tracking
  FOR DELETE TO authenticated USING (status = 'pending' AND is_company_member(company_id));
