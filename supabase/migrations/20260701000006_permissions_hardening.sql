-- ══════════════════════════════════════════════════════════════════════════════
-- PERMISSIONS HARDENING: core setup and posting lifecycle controls
-- Finding coverage: PXL-AUD-004 / PXL-DA-003, scoped to the critical SI/OR/VB/PV
-- flow and its setup prerequisites.
-- ══════════════════════════════════════════════════════════════════════════════

-- Keep the role helper current even on databases that skipped the earlier read
-- scope migration. Setup and lifecycle controls use owner/admin only.
CREATE OR REPLACE FUNCTION can_admin_company(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM user_company_memberships
    WHERE user_id = auth.uid()
      AND company_id = p_company_id
      AND role IN ('owner', 'admin')
  );
$$;

-- ── Core setup tables: reads stay member-scoped; writes require owner/admin. ──

DROP POLICY IF EXISTS "auth_insert_branches" ON branches;
DROP POLICY IF EXISTS "auth_update_branches" ON branches;
DROP POLICY IF EXISTS "auth_delete_branches" ON branches;
CREATE POLICY "auth_insert_branches" ON branches FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_update_branches" ON branches FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_delete_branches" ON branches FOR DELETE TO authenticated USING (can_admin_company(company_id));

DROP POLICY IF EXISTS "auth_insert_fiscal_years" ON fiscal_years;
DROP POLICY IF EXISTS "auth_update_fiscal_years" ON fiscal_years;
DROP POLICY IF EXISTS "auth_delete_fiscal_years" ON fiscal_years;
CREATE POLICY "auth_insert_fiscal_years" ON fiscal_years FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_update_fiscal_years" ON fiscal_years FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_delete_fiscal_years" ON fiscal_years FOR DELETE TO authenticated USING (can_admin_company(company_id));

DROP POLICY IF EXISTS "auth_insert_fiscal_periods" ON fiscal_periods;
DROP POLICY IF EXISTS "auth_update_fiscal_periods" ON fiscal_periods;
DROP POLICY IF EXISTS "auth_delete_fiscal_periods" ON fiscal_periods;
CREATE POLICY "auth_insert_fiscal_periods" ON fiscal_periods FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_update_fiscal_periods" ON fiscal_periods FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_delete_fiscal_periods" ON fiscal_periods FOR DELETE TO authenticated USING (can_admin_company(company_id));

DROP POLICY IF EXISTS "auth_insert_coa" ON chart_of_accounts;
DROP POLICY IF EXISTS "auth_update_coa" ON chart_of_accounts;
DROP POLICY IF EXISTS "auth_delete_coa" ON chart_of_accounts;
CREATE POLICY "auth_insert_coa" ON chart_of_accounts FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_update_coa" ON chart_of_accounts FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_delete_coa" ON chart_of_accounts FOR DELETE TO authenticated USING (can_admin_company(company_id));

DROP POLICY IF EXISTS "auth_insert_number_series" ON number_series;
DROP POLICY IF EXISTS "auth_update_number_series" ON number_series;
DROP POLICY IF EXISTS "auth_delete_number_series" ON number_series;
CREATE POLICY "auth_insert_number_series" ON number_series FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_update_number_series" ON number_series FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
CREATE POLICY "auth_delete_number_series" ON number_series FOR DELETE TO authenticated USING (can_admin_company(company_id));

DROP POLICY IF EXISTS "cac_insert" ON company_accounting_config;
DROP POLICY IF EXISTS "cac_update" ON company_accounting_config;
CREATE POLICY "cac_insert" ON company_accounting_config FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "cac_update" ON company_accounting_config FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));

-- ── Posting lifecycle gate ───────────────────────────────────────────────────
-- Existing SECURITY DEFINER posting RPCs still perform the accounting work. This
-- trigger blocks the restricted status transitions unless the caller is an
-- owner/admin for the source company. It also protects direct PostgREST updates.

CREATE OR REPLACE FUNCTION fn_require_admin_for_accounting_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  IF TG_OP = 'INSERT'
     AND NEW.status IN ('posted', 'cancelled', 'bounced', 'reversed') THEN
    v_company_id := NEW.company_id;
    IF NOT can_admin_company(v_company_id) THEN
      RAISE EXCEPTION 'Access denied: owner/admin role required to create % with status %',
        TG_TABLE_NAME, NEW.status;
    END IF;
  ELSIF TG_OP = 'UPDATE'
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('posted', 'cancelled', 'bounced', 'reversed') THEN
    v_company_id := COALESCE(NEW.company_id, OLD.company_id);
    IF NOT can_admin_company(v_company_id) THEN
      RAISE EXCEPTION 'Access denied: owner/admin role required to change % status to %',
        TG_TABLE_NAME, NEW.status;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admin_lifecycle_sales_invoices_insert ON sales_invoices;
CREATE TRIGGER trg_admin_lifecycle_sales_invoices_insert
  BEFORE INSERT ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_sales_invoices ON sales_invoices;
CREATE TRIGGER trg_admin_lifecycle_sales_invoices
  BEFORE UPDATE OF status ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_receipts_insert ON receipts;
CREATE TRIGGER trg_admin_lifecycle_receipts_insert
  BEFORE INSERT ON receipts
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_receipts ON receipts;
CREATE TRIGGER trg_admin_lifecycle_receipts
  BEFORE UPDATE OF status ON receipts
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_vendor_bills_insert ON vendor_bills;
CREATE TRIGGER trg_admin_lifecycle_vendor_bills_insert
  BEFORE INSERT ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_vendor_bills ON vendor_bills;
CREATE TRIGGER trg_admin_lifecycle_vendor_bills
  BEFORE UPDATE OF status ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_payment_vouchers_insert ON payment_vouchers;
CREATE TRIGGER trg_admin_lifecycle_payment_vouchers_insert
  BEFORE INSERT ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();

DROP TRIGGER IF EXISTS trg_admin_lifecycle_payment_vouchers ON payment_vouchers;
CREATE TRIGGER trg_admin_lifecycle_payment_vouchers
  BEFORE UPDATE OF status ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle();
