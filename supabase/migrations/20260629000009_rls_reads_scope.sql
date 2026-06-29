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

DROP POLICY "authenticated_all_companies" ON companies;

CREATE POLICY "companies_read_own"   ON companies FOR SELECT TO authenticated
  USING (is_company_member(id));

CREATE POLICY "companies_create"     ON companies FOR INSERT TO authenticated
  WITH CHECK (true); -- creator-owner trigger fires automatically

CREATE POLICY "companies_update"     ON companies FOR UPDATE TO authenticated
  USING (can_admin_company(id));

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
DROP POLICY "auth_read_branches"             ON branches;
DROP POLICY "auth_read_departments"          ON departments;
DROP POLICY "auth_read_cost_centers"         ON cost_centers;
DROP POLICY "auth_read_fiscal_years"         ON fiscal_years;
DROP POLICY "auth_read_fiscal_periods"       ON fiscal_periods;
DROP POLICY "auth_read_coa"                  ON chart_of_accounts;
DROP POLICY "auth_read_exchange_rates"       ON exchange_rates;
DROP POLICY "auth_read_feature_enablement"   ON sys_feature_enablement;
DROP POLICY "auth_read_number_series"        ON number_series;
DROP POLICY "auth_read_approval_workflows"   ON approval_workflows;
DROP POLICY "auth_read_workflow_steps"       ON approval_workflow_steps;
DROP POLICY "auth_read_approval_instances"   ON approval_instances;

CREATE POLICY "auth_read_branches"           ON branches             FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_departments"        ON departments          FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_cost_centers"       ON cost_centers         FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_fiscal_years"       ON fiscal_years         FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_fiscal_periods"     ON fiscal_periods       FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_coa"                ON chart_of_accounts    FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_exchange_rates"     ON exchange_rates       FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_feature_enablement" ON sys_feature_enablement FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_number_series"      ON number_series        FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_approval_workflows" ON approval_workflows   FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_workflow_steps"     ON approval_workflow_steps FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_approval_instances" ON approval_instances   FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 1: audit log (company_id nullable — system-level rows visible to all)
DROP POLICY "auth_read_audit_logs" ON sys_audit_logs;
CREATE POLICY "auth_read_audit_logs" ON sys_audit_logs FOR SELECT TO authenticated
  USING (company_id IS NULL OR is_company_member(company_id));

-- Sprint 2/3: master data (policies added in migration 008)
DROP POLICY "auth_read_ewt_codes"         ON ewt_codes;
DROP POLICY "auth_read_payment_terms"     ON payment_terms;
DROP POLICY "auth_read_item_categories"   ON item_categories;
DROP POLICY "auth_read_uom"               ON units_of_measure;
DROP POLICY "auth_read_customers"         ON customers;
DROP POLICY "auth_read_suppliers"         ON suppliers;
DROP POLICY "auth_read_items"             ON items;

CREATE POLICY "auth_read_ewt_codes"       ON ewt_codes         FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_payment_terms"   ON payment_terms     FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_item_categories" ON item_categories   FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_uom"             ON units_of_measure  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_customers"       ON customers         FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_suppliers"       ON suppliers         FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_items"           ON items             FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 2 tax: compliance setup (policies added in migration 008)
DROP POLICY "auth_read_fwt_codes"            ON fwt_codes;
DROP POLICY "auth_read_pt_codes"             ON percentage_tax_codes;
DROP POLICY "auth_read_compliance_profiles"  ON compliance_profiles;

CREATE POLICY "auth_read_fwt_codes"          ON fwt_codes            FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_pt_codes"           ON percentage_tax_codes FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_read_compliance_profiles" ON compliance_profiles FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 2 tax: calendar (original migration policy)
DROP POLICY "auth_read_tax_calendar" ON tax_calendar_events;
CREATE POLICY "auth_read_tax_calendar" ON tax_calendar_events FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 5: sales invoices and lines (original migration policies)
DROP POLICY "read_sales_invoices" ON sales_invoices;
DROP POLICY "read_si_lines"       ON sales_invoice_lines;
CREATE POLICY "read_sales_invoices" ON sales_invoices        FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_si_lines"       ON sales_invoice_lines  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 5 AR: receipts, CM, DM and their lines
DROP POLICY "read_receipts"        ON receipts;
DROP POLICY "read_receipt_lines"   ON receipt_lines;
DROP POLICY "read_credit_memos"    ON credit_memos;
DROP POLICY "read_cm_lines"        ON credit_memo_lines;
DROP POLICY "read_debit_memos"     ON debit_memos;
DROP POLICY "read_dm_lines"        ON debit_memo_lines;

CREATE POLICY "read_receipts"      ON receipts           FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_receipt_lines" ON receipt_lines      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_credit_memos"  ON credit_memos       FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_cm_lines"      ON credit_memo_lines  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_debit_memos"   ON debit_memos        FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_dm_lines"      ON debit_memo_lines   FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 5 SO/DR: quotations, orders, delivery receipts and their lines
DROP POLICY "read_sq"   ON sales_quotations;
DROP POLICY "read_sql"  ON sales_quotation_lines;
DROP POLICY "read_so"   ON sales_orders;
DROP POLICY "read_sol"  ON sales_order_lines;
DROP POLICY "read_dr"   ON delivery_receipts;
DROP POLICY "read_drl"  ON delivery_receipt_lines;

CREATE POLICY "read_sq"   ON sales_quotations        FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_sql"  ON sales_quotation_lines   FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_so"   ON sales_orders            FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_sol"  ON sales_order_lines       FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_dr"   ON delivery_receipts       FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "read_drl"  ON delivery_receipt_lines  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Sprint 6+: compliance docs
DROP POLICY "read_ewt_wp_headers" ON compliance_ewt_working_papers_headers;
CREATE POLICY "read_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- EWT WP lines have no company_id — scope via parent header
DROP POLICY "read_ewt_wp_lines" ON compliance_ewt_working_papers_lines;
CREATE POLICY "read_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR SELECT TO authenticated
  USING (
    header_id IN (
      SELECT id FROM compliance_ewt_working_papers_headers WHERE is_company_member(company_id)
    )
  );

DROP POLICY "read_form_2307_tracking" ON form_2307_tracking;
CREATE POLICY "read_form_2307_tracking" ON form_2307_tracking
  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- ── 6. Fix global reference tables: add missing write policies ────────────────
-- tax_codes, vat_codes, atc_codes are global BIR reference data (no company_id).
-- The UI has create/edit forms for them but no INSERT/UPDATE policy existed.

CREATE POLICY "auth_write_tax_codes"  ON tax_codes  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "auth_update_tax_codes" ON tax_codes  FOR UPDATE TO authenticated USING (true);

CREATE POLICY "auth_write_vat_codes"  ON vat_codes  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "auth_update_vat_codes" ON vat_codes  FOR UPDATE TO authenticated USING (true);

CREATE POLICY "auth_write_atc_codes"  ON atc_codes  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "auth_update_atc_codes" ON atc_codes  FOR UPDATE TO authenticated USING (true);
