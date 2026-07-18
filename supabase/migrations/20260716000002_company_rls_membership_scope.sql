-- ============================================================================
-- Company RLS membership scope hardening
--
-- Finalizes PXL-AUD-062 by removing permissive authenticated company policies
-- that allowed broad company selector visibility and direct company updates.
-- ============================================================================

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

DROP POLICY IF EXISTS "authenticated_all_companies" ON companies;
DROP POLICY IF EXISTS "authenticated_select_companies" ON companies;
DROP POLICY IF EXISTS "authenticated_update_companies" ON companies;
DROP POLICY IF EXISTS "companies_read_own" ON companies;
DROP POLICY IF EXISTS "companies_create" ON companies;
DROP POLICY IF EXISTS "companies_update" ON companies;
DROP POLICY IF EXISTS "companies_delete" ON companies;

CREATE POLICY "companies_read_own" ON companies
  FOR SELECT TO authenticated
  USING (is_company_member(id));

CREATE POLICY "companies_create" ON companies
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "companies_update" ON companies
  FOR UPDATE TO authenticated
  USING (can_admin_company(id))
  WITH CHECK (can_admin_company(id));

CREATE POLICY "companies_delete" ON companies
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM user_company_memberships
      WHERE user_id = auth.uid()
        AND company_id = companies.id
        AND role = 'owner'
    )
  );
