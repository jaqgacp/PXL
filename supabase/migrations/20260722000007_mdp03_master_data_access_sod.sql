-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-03 — Master Data Access Control & Segregation-of-Duties Foundation
--
-- Adds a reusable permission catalog for the completed master-data registry,
-- maps the existing membership roles onto that catalog, provides opt-in
-- branch-scoped access for branch-aware masters, and seeds advisory SoD
-- conflicts for future approval routing.
--
-- This migration deliberately keeps user_company_memberships as the source of
-- user/company identity. It broadens the role column so future custom role codes
-- can be mapped without introducing a parallel membership model.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Role compatibility: keep the same column, allow future custom role codes
ALTER TABLE user_company_memberships
  DROP CONSTRAINT IF EXISTS user_company_memberships_role_check;

ALTER TABLE user_company_memberships
  ADD CONSTRAINT user_company_memberships_role_check
  CHECK (role ~ '^[a-z][a-z0-9_]*$');

-- The original membership management policy queried user_company_memberships
-- from inside its own USING clause. Replace it with the existing SECURITY
-- DEFINER admin helper so authenticated membership reads/writes do not recurse.
DROP POLICY IF EXISTS "ucm_read_own" ON user_company_memberships;
DROP POLICY IF EXISTS "ucm_manage_own_companies" ON user_company_memberships;
DROP POLICY IF EXISTS "ucm_read_scoped" ON user_company_memberships;
DROP POLICY IF EXISTS "ucm_insert_admin" ON user_company_memberships;
DROP POLICY IF EXISTS "ucm_update_admin" ON user_company_memberships;
DROP POLICY IF EXISTS "ucm_delete_admin" ON user_company_memberships;

CREATE POLICY "ucm_read_scoped" ON user_company_memberships
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR can_admin_company(company_id));

CREATE POLICY "ucm_insert_admin" ON user_company_memberships
  FOR INSERT TO authenticated
  WITH CHECK (can_admin_company(company_id));

CREATE POLICY "ucm_update_admin" ON user_company_memberships
  FOR UPDATE TO authenticated
  USING (can_admin_company(company_id))
  WITH CHECK (can_admin_company(company_id));

CREATE POLICY "ucm_delete_admin" ON user_company_memberships
  FOR DELETE TO authenticated
  USING (can_admin_company(company_id));

-- ── 2. Permission catalog, role mappings, advisory SoD, branch scopes ─────────
CREATE TABLE IF NOT EXISTS master_data_permissions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_code TEXT NOT NULL UNIQUE,
  master_key      TEXT NOT NULL REFERENCES master_data_import_registry(master_key) ON DELETE CASCADE,
  action          TEXT NOT NULL
                    CHECK (action IN ('view','create','edit','delete','import','export','approve')),
  is_available    BOOLEAN NOT NULL DEFAULT true,
  is_sensitive    BOOLEAN NOT NULL DEFAULT false,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (master_key, action)
);

DROP TRIGGER IF EXISTS trg_master_data_permissions_updated_at ON master_data_permissions;
CREATE TRIGGER trg_master_data_permissions_updated_at
  BEFORE UPDATE ON master_data_permissions
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS master_data_role_permissions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_code       TEXT NOT NULL CHECK (role_code ~ '^[a-z][a-z0-9_]*$'),
  permission_code TEXT NOT NULL REFERENCES master_data_permissions(permission_code) ON DELETE CASCADE,
  is_allowed      BOOLEAN NOT NULL DEFAULT true,
  granted_by      UUID REFERENCES auth.users(id),
  granted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (role_code, permission_code)
);

DROP TRIGGER IF EXISTS trg_master_data_role_permissions_updated_at ON master_data_role_permissions;
CREATE TRIGGER trg_master_data_role_permissions_updated_at
  BEFORE UPDATE ON master_data_role_permissions
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS master_data_sod_conflicts (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conflict_code         TEXT NOT NULL UNIQUE,
  left_permission_code  TEXT NOT NULL REFERENCES master_data_permissions(permission_code) ON DELETE CASCADE,
  right_permission_code TEXT NOT NULL REFERENCES master_data_permissions(permission_code) ON DELETE CASCADE,
  severity              TEXT NOT NULL DEFAULT 'medium'
                          CHECK (severity IN ('low','medium','high','critical')),
  enforcement_mode      TEXT NOT NULL DEFAULT 'advisory'
                          CHECK (enforcement_mode IN ('advisory','enforced')),
  is_active             BOOLEAN NOT NULL DEFAULT true,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (left_permission_code <> right_permission_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_master_data_sod_conflicts_pair
  ON master_data_sod_conflicts (
    LEAST(left_permission_code, right_permission_code),
    GREATEST(left_permission_code, right_permission_code)
  );

DROP TRIGGER IF EXISTS trg_master_data_sod_conflicts_updated_at ON master_data_sod_conflicts;
CREATE TRIGGER trg_master_data_sod_conflicts_updated_at
  BEFORE UPDATE ON master_data_sod_conflicts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS user_company_branch_scopes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  branch_id  UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  granted_by UUID REFERENCES auth.users(id),
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, company_id, branch_id)
);

CREATE INDEX IF NOT EXISTS idx_user_company_branch_scopes_user
  ON user_company_branch_scopes (user_id, company_id)
  WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_user_company_branch_scopes_branch
  ON user_company_branch_scopes (company_id, branch_id)
  WHERE is_active;

DROP TRIGGER IF EXISTS trg_user_company_branch_scopes_updated_at ON user_company_branch_scopes;
CREATE TRIGGER trg_user_company_branch_scopes_updated_at
  BEFORE UPDATE ON user_company_branch_scopes
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE OR REPLACE FUNCTION fn_user_company_branch_scope_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch_company UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM user_company_memberships m
    WHERE m.user_id = NEW.user_id
      AND m.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'branch scope user must already be a member of the company'
      USING ERRCODE = '23503';
  END IF;

  SELECT b.company_id INTO v_branch_company
  FROM branches b
  WHERE b.id = NEW.branch_id;

  IF v_branch_company IS NULL THEN
    RAISE EXCEPTION 'branch scope branch does not exist' USING ERRCODE = '23503';
  END IF;
  IF v_branch_company <> NEW.company_id THEN
    RAISE EXCEPTION 'branch scope branch must belong to the scoped company'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_company_branch_scope_guard ON user_company_branch_scopes;
CREATE TRIGGER trg_user_company_branch_scope_guard
  BEFORE INSERT OR UPDATE ON user_company_branch_scopes
  FOR EACH ROW EXECUTE FUNCTION fn_user_company_branch_scope_guard();

-- ── 3. RLS / grants for the new metadata tables ──────────────────────────────
ALTER TABLE master_data_permissions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_data_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_data_sod_conflicts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_company_branch_scopes   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS master_data_permissions_read ON master_data_permissions;
CREATE POLICY master_data_permissions_read
  ON master_data_permissions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS master_data_role_permissions_read ON master_data_role_permissions;
CREATE POLICY master_data_role_permissions_read
  ON master_data_role_permissions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS master_data_sod_conflicts_read ON master_data_sod_conflicts;
CREATE POLICY master_data_sod_conflicts_read
  ON master_data_sod_conflicts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS user_company_branch_scopes_read ON user_company_branch_scopes;
CREATE POLICY user_company_branch_scopes_read
  ON user_company_branch_scopes FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR can_admin_company(company_id));

DROP POLICY IF EXISTS user_company_branch_scopes_insert ON user_company_branch_scopes;
CREATE POLICY user_company_branch_scopes_insert
  ON user_company_branch_scopes FOR INSERT TO authenticated
  WITH CHECK (can_admin_company(company_id));

DROP POLICY IF EXISTS user_company_branch_scopes_update ON user_company_branch_scopes;
CREATE POLICY user_company_branch_scopes_update
  ON user_company_branch_scopes FOR UPDATE TO authenticated
  USING (can_admin_company(company_id))
  WITH CHECK (can_admin_company(company_id));

DROP POLICY IF EXISTS user_company_branch_scopes_delete ON user_company_branch_scopes;
CREATE POLICY user_company_branch_scopes_delete
  ON user_company_branch_scopes FOR DELETE TO authenticated
  USING (can_admin_company(company_id));

REVOKE ALL ON TABLE master_data_permissions, master_data_role_permissions,
  master_data_sod_conflicts, user_company_branch_scopes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE master_data_permissions, master_data_role_permissions,
  master_data_sod_conflicts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE user_company_branch_scopes TO authenticated;
GRANT ALL ON TABLE master_data_permissions, master_data_role_permissions,
  master_data_sod_conflicts, user_company_branch_scopes TO service_role;

-- ── 4. Seed permissions and role mappings from the MDP-15 registry ───────────
CREATE TEMP TABLE mdp03_delete_policy_snapshot ON COMMIT DROP AS
SELECT r.master_key,
       EXISTS (
         SELECT 1
         FROM pg_policies p
         WHERE p.schemaname = r.table_schema
           AND p.tablename = r.table_name
           AND p.cmd IN ('DELETE','ALL')
       ) AS delete_was_permitted
FROM master_data_import_registry r;

WITH actions(action, action_order) AS (
  VALUES
    ('view', 1),
    ('create', 2),
    ('edit', 3),
    ('delete', 4),
    ('import', 5),
    ('export', 6),
    ('approve', 7)
),
source_permissions AS (
  SELECT
    r.master_key || '.' || a.action AS permission_code,
    r.master_key,
    a.action,
    CASE
      WHEN a.action IN ('view','export') THEN true
      WHEN r.scope NOT IN ('company','company_self') THEN false
      WHEN r.import_mode <> 'upsert' THEN false
      WHEN a.action = 'delete' THEN COALESCE(d.delete_was_permitted, false)
      WHEN a.action = 'approve' THEN true
      ELSE true
    END AS is_available,
    a.action IN ('create','edit','delete','import','approve') AS is_sensitive,
    CASE
      WHEN a.action = 'approve' THEN 'Future-ready MDP-14 approval permission; MDP-03 records advisory SoD only.'
      WHEN a.action = 'delete' THEN 'Delete permission is available only where a delete policy existed before MDP-03.'
      WHEN r.scope LIKE 'global%' AND a.action NOT IN ('view','export') THEN 'Global statutory/reference writes remain governed by their existing dedicated paths.'
      ELSE 'Seeded from the MDP-15 master-data import/export registry.'
    END AS notes
  FROM master_data_import_registry r
  CROSS JOIN actions a
  LEFT JOIN mdp03_delete_policy_snapshot d ON d.master_key = r.master_key
)
INSERT INTO master_data_permissions (
  permission_code, master_key, action, is_available, is_sensitive, notes
)
SELECT permission_code, master_key, action, is_available, is_sensitive, notes
FROM source_permissions
ON CONFLICT (permission_code) DO UPDATE
SET master_key = EXCLUDED.master_key,
    action = EXCLUDED.action,
    is_available = EXCLUDED.is_available,
    is_sensitive = EXCLUDED.is_sensitive,
    notes = EXCLUDED.notes,
    updated_at = NOW();

WITH operational_member_masters(master_key) AS (
  VALUES
    ('warehouses'),
    ('projects'),
    ('locations'),
    ('functional_entities'),
    ('customer_groups'),
    ('supplier_groups'),
    ('customers'),
    ('suppliers'),
    ('party_contacts'),
    ('employees'),
    ('items'),
    ('item_uom_conversions'),
    ('item_barcodes'),
    ('item_media'),
    ('bank_accounts'),
    ('company_payment_modes')
),
role_grants(role_code, permission_code, is_allowed) AS (
  SELECT r.role_code, p.permission_code, true
  FROM (VALUES ('owner'), ('admin')) AS r(role_code)
  JOIN master_data_permissions p ON p.is_available

  UNION ALL
  SELECT 'viewer', p.permission_code, true
  FROM master_data_permissions p
  JOIN master_data_import_registry r ON r.master_key = p.master_key
  WHERE p.is_available
    AND p.action IN ('view','export')
    AND r.scope IN ('company','company_self')

  UNION ALL
  SELECT 'member', p.permission_code, true
  FROM master_data_permissions p
  JOIN master_data_import_registry r ON r.master_key = p.master_key
  WHERE p.is_available
    AND p.action IN ('view','export')
    AND r.scope IN ('company','company_self')

  UNION ALL
  SELECT 'member', p.permission_code, true
  FROM master_data_permissions p
  JOIN operational_member_masters om ON om.master_key = p.master_key
  WHERE p.is_available
    AND p.action IN ('create','edit')
)
INSERT INTO master_data_role_permissions (role_code, permission_code, is_allowed)
SELECT role_code, permission_code, is_allowed
FROM role_grants
ON CONFLICT (role_code, permission_code) DO UPDATE
SET is_allowed = EXCLUDED.is_allowed,
    updated_at = NOW();

WITH pairs AS (
  SELECT p_create.master_key,
         p_create.permission_code AS left_permission_code,
         p_approve.permission_code AS right_permission_code,
         p_create.action AS left_action,
         p_approve.action AS right_action
  FROM master_data_permissions p_create
  JOIN master_data_permissions p_approve
    ON p_approve.master_key = p_create.master_key
   AND p_approve.action = 'approve'
   AND p_approve.is_available
  WHERE p_create.action IN ('create','edit','delete','import')
    AND p_create.is_available
),
source_conflicts AS (
  SELECT master_key || '.' || left_action || '_vs_' || right_action AS conflict_code,
         left_permission_code,
         right_permission_code,
         CASE WHEN left_action IN ('delete','import') THEN 'high' ELSE 'medium' END AS severity,
         'advisory' AS enforcement_mode,
         format(
           'MDP-03 advisory SoD preparation: %s and approve on %s should be assigned cautiously. MDP-14 owns approval-route enforcement.',
           left_action, master_key
         ) AS notes
  FROM pairs
)
INSERT INTO master_data_sod_conflicts (
  conflict_code, left_permission_code, right_permission_code,
  severity, enforcement_mode, notes
)
SELECT conflict_code, left_permission_code, right_permission_code,
       severity, enforcement_mode, notes
FROM source_conflicts
ON CONFLICT (conflict_code) DO UPDATE
SET left_permission_code = EXCLUDED.left_permission_code,
    right_permission_code = EXCLUDED.right_permission_code,
    severity = EXCLUDED.severity,
    enforcement_mode = EXCLUDED.enforcement_mode,
    notes = EXCLUDED.notes,
    is_active = true,
    updated_at = NOW();

-- ── 5. Authorization helpers ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_master_data_key_for_table(p_table_name TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.master_key
  FROM master_data_import_registry r
  WHERE r.table_schema = 'public'
    AND r.table_name = p_table_name
  ORDER BY r.export_sequence, r.master_key
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_can_master_data_permission(
  p_company_id UUID,
  p_master_key TEXT,
  p_action     TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role       TEXT;
  v_scope      TEXT;
  v_available BOOLEAN;
  v_allowed    BOOLEAN;
BEGIN
  IF p_master_key IS NULL OR p_action IS NULL THEN
    RETURN false;
  END IF;

  SELECT r.scope, p.is_available
    INTO v_scope, v_available
  FROM master_data_import_registry r
  JOIN master_data_permissions p
    ON p.master_key = r.master_key
   AND p.action = p_action
  WHERE r.master_key = p_master_key;

  IF NOT FOUND OR NOT v_available THEN
    RETURN false;
  END IF;

  IF v_scope LIKE 'global%' THEN
    IF p_action IN ('view','export') THEN
      RETURN auth.uid() IS NOT NULL;
    END IF;

    -- Global statutory writes remain governed by the MDP-01/PXL-AUD-063
    -- maintainer path. This helper exposes the decision point without replacing
    -- those RPCs or RLS policies.
    RETURN fn_is_bir_config_maintainer();
  END IF;

  IF p_company_id IS NULL OR NOT is_company_member(p_company_id) THEN
    RETURN false;
  END IF;

  SELECT m.role INTO v_role
  FROM user_company_memberships m
  WHERE m.user_id = auth.uid()
    AND m.company_id = p_company_id;

  IF v_role IS NULL THEN
    RETURN false;
  END IF;

  SELECT COALESCE(rp.is_allowed, false)
    INTO v_allowed
  FROM master_data_role_permissions rp
  JOIN master_data_permissions p
    ON p.permission_code = rp.permission_code
  WHERE rp.role_code = v_role
    AND p.master_key = p_master_key
    AND p.action = p_action
    AND p.is_available;

  RETURN COALESCE(v_allowed, false);
END;
$$;

CREATE OR REPLACE FUNCTION fn_can_access_company_branch(
  p_company_id UUID,
  p_branch_id  UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF p_company_id IS NULL OR NOT is_company_member(p_company_id) THEN
    RETURN false;
  END IF;

  IF p_branch_id IS NULL THEN
    RETURN true;
  END IF;

  SELECT m.role INTO v_role
  FROM user_company_memberships m
  WHERE m.user_id = auth.uid()
    AND m.company_id = p_company_id;

  IF v_role IN ('owner','admin') THEN
    RETURN true;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM user_company_branch_scopes s
    WHERE s.user_id = auth.uid()
      AND s.company_id = p_company_id
      AND s.is_active
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM user_company_branch_scopes s
    WHERE s.user_id = auth.uid()
      AND s.company_id = p_company_id
      AND s.branch_id = p_branch_id
      AND s.is_active
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_master_data_sod_conflicts_for_current_user(
  p_company_id UUID
)
RETURNS TABLE (
  conflict_code TEXT,
  left_permission_code TEXT,
  right_permission_code TEXT,
  severity TEXT,
  enforcement_mode TEXT,
  notes TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF p_company_id IS NULL OR NOT is_company_member(p_company_id) THEN
    RETURN;
  END IF;

  SELECT m.role INTO v_role
  FROM user_company_memberships m
  WHERE m.user_id = auth.uid()
    AND m.company_id = p_company_id;

  RETURN QUERY
  SELECT c.conflict_code,
         c.left_permission_code,
         c.right_permission_code,
         c.severity,
         c.enforcement_mode,
         c.notes
  FROM master_data_sod_conflicts c
  JOIN master_data_role_permissions lrp
    ON lrp.permission_code = c.left_permission_code
   AND lrp.role_code = v_role
   AND lrp.is_allowed
  JOIN master_data_role_permissions rrp
    ON rrp.permission_code = c.right_permission_code
   AND rrp.role_code = v_role
   AND rrp.is_allowed
  WHERE c.is_active
  ORDER BY c.severity DESC, c.conflict_code;
END;
$$;

-- Preserve the existing DEC-009 lifecycle contract while routing the legacy
-- master_data action through the new permission catalog.
CREATE OR REPLACE FUNCTION fn_can_perform(
  p_company_id UUID,
  p_action TEXT,
  p_document_type TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role       TEXT;
  v_master_key TEXT;
  v_action     TEXT;
BEGIN
  IF p_company_id IS NULL THEN
    RETURN false;
  END IF;

  IF p_action IN (
    'master_data',
    'view_master_data',
    'create_master_data',
    'edit_master_data',
    'delete_master_data',
    'import_master_data',
    'export_master_data',
    'approve_master_data'
  ) THEN
    v_master_key := COALESCE(fn_master_data_key_for_table(p_document_type), p_document_type);
    v_action := CASE p_action
      WHEN 'master_data' THEN 'edit'
      WHEN 'view_master_data' THEN 'view'
      WHEN 'create_master_data' THEN 'create'
      WHEN 'edit_master_data' THEN 'edit'
      WHEN 'delete_master_data' THEN 'delete'
      WHEN 'import_master_data' THEN 'import'
      WHEN 'export_master_data' THEN 'export'
      WHEN 'approve_master_data' THEN 'approve'
      ELSE p_action
    END;

    RETURN fn_can_master_data_permission(p_company_id, v_master_key, v_action);
  END IF;

  SELECT role INTO v_role
  FROM user_company_memberships
  WHERE user_id = auth.uid()
    AND company_id = p_company_id;

  IF v_role IN ('owner', 'admin') THEN
    RETURN true;
  ELSIF v_role = 'member' THEN
    -- Preserve DEC-009 transaction capture authority. Fine-grained master data
    -- is evaluated through the branch above.
    RETURN p_action IN ('create', 'edit');
  END IF;

  RETURN false;
END;
$$;

-- ── 6. Rewire company-scoped master RLS policies to the permission helper ────
DO $$
DECLARE
  spec RECORD;
  pol RECORD;
  v_has_company_col BOOLEAN;
  v_has_branch_col  BOOLEAN;
  v_branch_expr     TEXT;
  v_read_expr       TEXT;
  v_create_expr     TEXT;
  v_edit_expr       TEXT;
  v_delete_expr     TEXT;
  v_delete_allowed  BOOLEAN;
BEGIN
  FOR spec IN
    SELECT r.master_key, r.table_schema, r.table_name
    FROM master_data_import_registry r
    WHERE r.scope = 'company'
      AND r.import_mode = 'upsert'
      AND to_regclass(format('%I.%I', r.table_schema, r.table_name)) IS NOT NULL
    ORDER BY r.export_sequence, r.master_key
  LOOP
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns c
      WHERE c.table_schema = spec.table_schema
        AND c.table_name = spec.table_name
        AND c.column_name = 'company_id'
    ) INTO v_has_company_col;

    IF NOT v_has_company_col THEN
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns c
      WHERE c.table_schema = spec.table_schema
        AND c.table_name = spec.table_name
        AND c.column_name = 'branch_id'
    ) INTO v_has_branch_col;

    v_branch_expr := CASE
      WHEN spec.table_name = 'branches' THEN 'id'
      WHEN v_has_branch_col THEN 'branch_id'
      ELSE NULL
    END;

    SELECT delete_was_permitted
      INTO v_delete_allowed
    FROM mdp03_delete_policy_snapshot
    WHERE master_key = spec.master_key;

    FOR pol IN
      SELECT p.policyname
      FROM pg_policies p
      WHERE p.schemaname = spec.table_schema
        AND p.tablename = spec.table_name
        AND p.cmd IN ('SELECT','INSERT','UPDATE','DELETE','ALL')
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                     pol.policyname, spec.table_schema, spec.table_name);
    END LOOP;

    v_read_expr := format(
      'fn_can_master_data_permission(company_id, %L, ''view'')',
      spec.master_key
    );
    v_create_expr := format(
      'fn_can_master_data_permission(company_id, %L, ''create'')',
      spec.master_key
    );
    v_edit_expr := format(
      'fn_can_master_data_permission(company_id, %L, ''edit'')',
      spec.master_key
    );
    v_delete_expr := format(
      'fn_can_master_data_permission(company_id, %L, ''delete'')',
      spec.master_key
    );

    IF v_branch_expr IS NOT NULL THEN
      v_read_expr := v_read_expr || format(
        ' AND fn_can_access_company_branch(company_id, %I)',
        v_branch_expr
      );
      v_create_expr := v_create_expr || format(
        ' AND fn_can_access_company_branch(company_id, %I)',
        v_branch_expr
      );
      v_edit_expr := v_edit_expr || format(
        ' AND fn_can_access_company_branch(company_id, %I)',
        v_branch_expr
      );
      v_delete_expr := v_delete_expr || format(
        ' AND fn_can_access_company_branch(company_id, %I)',
        v_branch_expr
      );
    END IF;

    EXECUTE format(
      'CREATE POLICY %I ON %I.%I FOR SELECT TO authenticated USING (%s)',
      'mdp03_master_data_' || spec.table_name || '_select',
      spec.table_schema,
      spec.table_name,
      v_read_expr
    );
    EXECUTE format(
      'CREATE POLICY %I ON %I.%I FOR INSERT TO authenticated WITH CHECK (%s)',
      'mdp03_master_data_' || spec.table_name || '_insert',
      spec.table_schema,
      spec.table_name,
      v_create_expr
    );
    EXECUTE format(
      'CREATE POLICY %I ON %I.%I FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)',
      'mdp03_master_data_' || spec.table_name || '_update',
      spec.table_schema,
      spec.table_name,
      v_edit_expr,
      v_edit_expr
    );

    IF COALESCE(v_delete_allowed, false) THEN
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR DELETE TO authenticated USING (%s)',
        'mdp03_master_data_' || spec.table_name || '_delete',
        spec.table_schema,
        spec.table_name,
        v_delete_expr
      );
    END IF;
  END LOOP;
END;
$$;

-- Company self remains governed by the existing companies policies; tighten the
-- action helper and exports without replacing company creation/update semantics.

-- ── 7. Branch-aware export wrapper around the MDP-15 implementation ──────────
DO $$
BEGIN
  IF to_regprocedure('fn_mdp15_export_master_data_impl(uuid,text,boolean)') IS NULL THEN
    ALTER FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN)
      RENAME TO fn_mdp15_export_master_data_impl;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_export_master_data(
  p_company_id       UUID,
  p_master_key       TEXT,
  p_include_inactive BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meta          master_data_import_registry%ROWTYPE;
  v_columns       TEXT[];
  v_sort_cols     TEXT[];
  v_branch_col    TEXT;
  v_has_branch    BOOLEAN;
  v_select_sql    TEXT;
  v_where_sql     TEXT := 'true';
  v_order_sql     TEXT;
  v_rows          JSONB;
  v_content       JSONB;
  v_hash          TEXT;
  v_log_id        UUID;
  v_row_count     INTEGER;
  v_scope_company UUID;
BEGIN
  SELECT * INTO v_meta
  FROM master_data_import_registry
  WHERE master_key = p_master_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown master data key %', p_master_key USING ERRCODE = '22023';
  END IF;

  IF v_meta.scope IN ('company','company_self') THEN
    IF p_company_id IS NULL THEN
      RAISE EXCEPTION 'company_id is required for % export', p_master_key USING ERRCODE = '23514';
    END IF;
    IF NOT fn_can_master_data_permission(p_company_id, p_master_key, 'export') THEN
      RAISE EXCEPTION 'not authorized to export % master data for company %',
        p_master_key, p_company_id USING ERRCODE = '42501';
    END IF;
  ELSIF NOT fn_can_master_data_permission(NULL, p_master_key, 'export') THEN
    RAISE EXCEPTION 'not authorized to export % master data', p_master_key
      USING ERRCODE = '42501';
  END IF;

  v_columns := fn_mdp15_import_columns(v_meta.table_schema, v_meta.table_name);
  IF cardinality(v_columns) = 0 THEN
    RAISE EXCEPTION 'registered master % has no visible columns', p_master_key USING ERRCODE = '42703';
  END IF;

  IF v_meta.scope IN ('company','company_self') THEN
    v_scope_company := p_company_id;
    v_where_sql := CASE
      WHEN v_meta.scope = 'company' THEN 't.company_id = $1'
      ELSE 't.id = $1'
    END;
  END IF;

  IF NOT p_include_inactive AND 'is_active' = ANY(v_columns) THEN
    v_where_sql := v_where_sql || ' AND t.is_active IS TRUE';
  END IF;

  v_has_branch := 'branch_id' = ANY(v_columns);
  v_branch_col := CASE
    WHEN v_meta.table_name = 'branches' THEN 'id'
    WHEN v_has_branch THEN 'branch_id'
    ELSE NULL
  END;

  IF v_meta.scope = 'company' AND v_branch_col IS NOT NULL THEN
    v_where_sql := v_where_sql || format(
      ' AND fn_can_access_company_branch(t.company_id, t.%I)',
      v_branch_col
    );
  END IF;

  SELECT COALESCE(array_agg(c ORDER BY array_position(v_meta.sort_columns, c)), ARRAY[]::TEXT[])
  INTO v_sort_cols
  FROM unnest(v_meta.sort_columns) AS c
  WHERE c = ANY(v_columns);

  IF cardinality(v_sort_cols) = 0 THEN
    v_sort_cols := CASE WHEN 'id' = ANY(v_columns) THEN ARRAY['id'] ELSE ARRAY[v_columns[1]] END;
  END IF;

  SELECT string_agg(format('t.%I', c), ', ')
  INTO v_order_sql
  FROM unnest(v_sort_cols) AS c;

  v_select_sql := format(
    'SELECT COALESCE(jsonb_agg(to_jsonb(q)), ''[]''::jsonb)
       FROM (
         SELECT %s
         FROM %I.%I t
         WHERE %s
         ORDER BY %s
       ) q',
    (SELECT string_agg(format('t.%I', c), ', ') FROM unnest(v_columns) AS c),
    v_meta.table_schema,
    v_meta.table_name,
    v_where_sql,
    v_order_sql
  );

  EXECUTE v_select_sql INTO v_rows USING p_company_id;
  v_row_count := jsonb_array_length(v_rows);

  v_content := jsonb_build_object(
    'format_version', 1,
    'master_key', v_meta.master_key,
    'display_name', v_meta.display_name,
    'table', v_meta.table_schema || '.' || v_meta.table_name,
    'scope', v_meta.scope,
    'company_id', v_scope_company,
    'columns', to_jsonb(v_columns),
    'row_count', v_row_count,
    'rows', v_rows
  );
  v_hash := encode(extensions.digest(convert_to(v_content::TEXT, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO master_data_export_logs (
    company_id, master_key, export_format, row_count, content_hash, exported_by
  )
  VALUES (v_scope_company, v_meta.master_key, 'json-v1', v_row_count, v_hash, auth.uid())
  RETURNING id INTO v_log_id;

  RETURN v_content || jsonb_build_object(
    'content_sha256', v_hash,
    'export_log_id', v_log_id,
    'exported_at', NOW()
  );
END;
$$;

-- ── 8. Audit coverage for permission-sensitive metadata ─────────────────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_company_memberships',
    'master_data_permissions',
    'master_data_role_permissions',
    'master_data_sod_conflicts',
    'user_company_branch_scopes'
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

-- ── 9. Least privilege for helpers and comments ─────────────────────────────
REVOKE ALL ON FUNCTION fn_user_company_branch_scope_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_master_data_key_for_table(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_master_data_permission(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_access_company_branch(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_master_data_sod_conflicts_for_current_user(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_perform(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_mdp15_export_master_data_impl(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_master_data_key_for_table(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_can_master_data_permission(UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_can_access_company_branch(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_master_data_sod_conflicts_for_current_user(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_can_perform(UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_mdp15_export_master_data_impl(UUID, TEXT, BOOLEAN) TO service_role;
GRANT EXECUTE ON FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN) TO authenticated, service_role;

COMMENT ON TABLE master_data_permissions IS
  'MDP-03: reusable action-level permission catalog for registered master-data surfaces.';
COMMENT ON TABLE master_data_role_permissions IS
  'MDP-03: maps existing user_company_memberships.role codes, and future custom role codes, to master-data permissions.';
COMMENT ON TABLE master_data_sod_conflicts IS
  'MDP-03: advisory master-data segregation-of-duties conflict pairs; MDP-14 owns approval-route enforcement.';
COMMENT ON TABLE user_company_branch_scopes IS
  'MDP-03: optional branch access scope per user/company. No active rows means company-wide access; owner/admin bypass branch narrowing.';
COMMENT ON FUNCTION fn_can_master_data_permission(UUID, TEXT, TEXT) IS
  'MDP-03: central master-data permission helper backed by user_company_memberships role mappings and the MDP-15 registry.';
COMMENT ON FUNCTION fn_can_access_company_branch(UUID, UUID) IS
  'MDP-03: branch-scope helper for branch-aware master-data RLS and export filtering. Scopes are opt-in for backward compatibility.';
COMMENT ON FUNCTION fn_master_data_sod_conflicts_for_current_user(UUID) IS
  'MDP-03: returns active advisory SoD conflicts currently assigned through the caller''s company role.';
COMMENT ON FUNCTION fn_can_perform(UUID, TEXT, TEXT) IS
  'DEC-009 plus MDP-03: existing lifecycle actions are preserved; master_data actions route through the granular master-data permission catalog.';
COMMENT ON FUNCTION fn_export_master_data(UUID, TEXT, BOOLEAN) IS
  'MDP-15 export RPC hardened by MDP-03: deterministic export remains API-compatible, now consulting granular export permission and optional branch scopes.';
