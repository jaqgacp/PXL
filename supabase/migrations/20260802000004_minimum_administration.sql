-- =============================================================================
-- Delivery Plan Phase 3 / PAD-003 — minimum company administration contracts
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_admin_list_company_users(p_company_id UUID)
RETURNS TABLE (
  membership_id UUID,
  user_id UUID,
  email TEXT,
  role TEXT,
  granted_at TIMESTAMPTZ,
  last_sign_in_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can list company users';
  END IF;

  RETURN QUERY
  SELECT m.id, m.user_id, u.email::TEXT, m.role, m.granted_at, u.last_sign_in_at
  FROM public.user_company_memberships m
  JOIN auth.users u ON u.id = m.user_id
  WHERE m.company_id = p_company_id
  ORDER BY lower(u.email), m.user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_admin_upsert_membership(
  p_company_id UUID,
  p_user_id UUID,
  p_role TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id UUID;
  v_caller_role TEXT;
  v_old_role TEXT;
BEGIN
  IF p_role NOT IN ('owner', 'admin', 'member', 'viewer') THEN
    RAISE EXCEPTION 'Role must be owner, admin, member, or viewer';
  END IF;
  IF NOT public.can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can manage memberships';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_company_id::TEXT || ':membership-admin', 0));
  SELECT role INTO v_caller_role
  FROM public.user_company_memberships
  WHERE company_id = p_company_id AND user_id = auth.uid();
  IF p_role = 'owner' AND v_caller_role <> 'owner' THEN
    RAISE EXCEPTION 'Only an owner can assign the owner role';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;

  SELECT role INTO v_old_role
  FROM public.user_company_memberships
  WHERE company_id = p_company_id AND user_id = p_user_id
  FOR UPDATE;
  IF v_old_role = 'owner' AND v_caller_role <> 'owner' THEN
    RAISE EXCEPTION 'Only an owner can change another owner''s role';
  END IF;
  IF v_old_role = 'owner' AND p_role <> 'owner'
     AND (SELECT count(*) FROM public.user_company_memberships
          WHERE company_id = p_company_id AND role = 'owner') <= 1 THEN
    RAISE EXCEPTION 'A company must retain at least one owner';
  END IF;

  INSERT INTO public.user_company_memberships (
    user_id, company_id, role, granted_by
  ) VALUES (
    p_user_id, p_company_id, p_role, auth.uid()
  )
  ON CONFLICT (user_id, company_id) DO UPDATE SET
    role = EXCLUDED.role,
    granted_by = auth.uid(),
    granted_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_admin_remove_membership(
  p_company_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_caller_role TEXT;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can manage memberships';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_company_id::TEXT || ':membership-admin', 0));
  SELECT role INTO v_caller_role
  FROM user_company_memberships
  WHERE company_id = p_company_id AND user_id = auth.uid();
  SELECT role INTO v_role FROM user_company_memberships
  WHERE company_id = p_company_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_role = 'owner' AND v_caller_role <> 'owner' THEN
    RAISE EXCEPTION 'Only an owner can remove another owner';
  END IF;
  IF v_role = 'owner'
     AND (SELECT count(*) FROM user_company_memberships
          WHERE company_id = p_company_id AND role = 'owner') <= 1 THEN
    RAISE EXCEPTION 'A company must retain at least one owner';
  END IF;

  DELETE FROM user_company_branch_scopes
  WHERE company_id = p_company_id AND user_id = p_user_id;
  DELETE FROM user_company_memberships
  WHERE company_id = p_company_id AND user_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_admin_set_branch_scopes(
  p_company_id UUID,
  p_user_id UUID,
  p_branch_ids UUID[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can manage branch scope';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM user_company_memberships
    WHERE company_id = p_company_id AND user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'User must be a company member before branch scope is assigned';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_branch_ids, ARRAY[]::UUID[])) branch_id
    WHERE NOT EXISTS (
      SELECT 1 FROM branches b
      WHERE b.id = branch_id AND b.company_id = p_company_id AND b.is_active
    )
  ) THEN
    RAISE EXCEPTION 'Every branch scope must be an active branch of the company';
  END IF;

  DELETE FROM user_company_branch_scopes
  WHERE company_id = p_company_id AND user_id = p_user_id;

  INSERT INTO user_company_branch_scopes (
    user_id, company_id, branch_id, is_active, granted_by
  )
  SELECT DISTINCT p_user_id, p_company_id, branch_id, true, auth.uid()
  FROM unnest(COALESCE(p_branch_ids, ARRAY[]::UUID[])) branch_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_list_company_users(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_upsert_membership(UUID, UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_remove_membership(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_set_branch_scopes(UUID, UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_list_company_users(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_upsert_membership(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_remove_membership(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_set_branch_scopes(UUID, UUID, UUID[]) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_list_company_users(UUID) IS
  'PAD-003 admin-only company user list; auth.users is not directly exposed.';
COMMENT ON FUNCTION public.fn_admin_upsert_membership(UUID, UUID, TEXT) IS
  'PAD-003 governed membership and role assignment with last-owner protection.';
