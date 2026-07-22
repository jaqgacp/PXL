-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-09 — Dimension Masters: Project, Location, Functional Entity
--          (gaps MD-14, MD-15, MD-16)
--
-- Adds the three governed analytical-dimension masters that PXL lacks, so future
-- transaction and reporting packages can tag and roll up by Project, Location, and
-- Functional Entity. Delivered as REUSABLE BACKEND masters + a reusable validation
-- helper + an admin-gated provisioning helper (for the future MDP-08 wizard). No
-- UI, no transaction-form/line changes, no posting-logic change, and no reports.
--
-- ── Inventory result (what already exists — NOT rebuilt) ──────────────────────
-- * departments (company_id, branch_id, parent_department_id hierarchy, is_active;
--   UNIQUE(company_id, department_code)) and cost_centers (…, department_id,
--   parent_cost_center_id, cost_center_type, valid_from/valid_to, is_active;
--   UNIQUE(company_id, cost_center_code)) exist, are member-gated, audit-covered
--   (20260701000005_audit_cas.sql), and are already referenced by journal_entry_lines
--   / sales_invoice_lines / purchase documents. warehouses and branches exist too.
--   None of these are touched here.
-- MISSING (this package): Project (MD-14), Location (MD-15), and Functional Entity
--   (MD-16) have NO master. They are added below.
--
-- ── What this migration adds (only the genuine gaps) ──────────────────────────
--   1. projects / locations / functional_entities — company-scoped, branch-aware,
--      self-referencing parent hierarchy, is_active lifecycle, valid_from/valid_to
--      effective dating, per-type vocabulary, UNIQUE(company_id, code). Modeled on
--      the existing cost_centers shape for consistency.
--   2. Member-gated RLS (read/insert/update/delete via is_company_member) — the same
--      posture as departments/cost_centers; tenant isolation preserved.
--   3. fn_dimension_hierarchy_guard — a shared BEFORE INSERT/UPDATE trigger enforcing
--      no self-parent, same-company parent, and no circular hierarchy.
--   4. Audit coverage via the existing fn_audit_trigger (MDP-02 mechanism).
--   5. fn_is_valid_dimension(...) — a reusable, side-effect-free checker future
--      transaction code can call (exists, same company, active, in-window, branch-
--      consistent). Nothing is wired into posting here.
--   6. fn_provision_company_dimension_defaults(company) — admin-gated, idempotent
--      default scaffold (a Head Office location + a General functional entity) for
--      the future MDP-08 wizard.
--
-- Additive, forward-only; idempotent (IF NOT EXISTS / DROP..IF EXISTS + CREATE);
-- no change to existing tables, RLS, posting, or tax logic. No engineering findings.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Master tables ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS projects (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  branch_id         UUID REFERENCES branches(id),
  project_code      TEXT NOT NULL,
  project_name      TEXT NOT NULL,
  parent_project_id UUID REFERENCES projects(id),
  project_status    TEXT NOT NULL DEFAULT 'active'
                       CHECK (project_status IN ('planned','active','on_hold','completed','cancelled')),
  manager_user_id   UUID,
  valid_from        DATE,
  valid_to          DATE,
  description       TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, project_code),
  CONSTRAINT projects_valid_window_check CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS locations (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID NOT NULL REFERENCES companies(id),
  branch_id          UUID REFERENCES branches(id),
  location_code      TEXT NOT NULL,
  location_name      TEXT NOT NULL,
  parent_location_id UUID REFERENCES locations(id),
  location_type      TEXT NOT NULL DEFAULT 'site'
                        CHECK (location_type IN ('site','office','warehouse','store','region','virtual')),
  valid_from         DATE,
  valid_to           DATE,
  description        TEXT,
  is_active          BOOLEAN NOT NULL DEFAULT true,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, location_code),
  CONSTRAINT locations_valid_window_check CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS functional_entities (
  id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                   UUID NOT NULL REFERENCES companies(id),
  branch_id                    UUID REFERENCES branches(id),
  entity_code                  TEXT NOT NULL,
  entity_name                  TEXT NOT NULL,
  parent_functional_entity_id  UUID REFERENCES functional_entities(id),
  functional_entity_type       TEXT NOT NULL DEFAULT 'segment'
                                  CHECK (functional_entity_type IN ('segment','division','business_unit','fund','program')),
  valid_from                   DATE,
  valid_to                     DATE,
  description                  TEXT,
  is_active                    BOOLEAN NOT NULL DEFAULT true,
  created_by                   UUID,
  updated_by                   UUID,
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, entity_code),
  CONSTRAINT functional_entities_valid_window_check CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX IF NOT EXISTS idx_projects_company            ON projects (company_id);
CREATE INDEX IF NOT EXISTS idx_projects_branch             ON projects (branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_projects_parent             ON projects (parent_project_id) WHERE parent_project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_locations_company           ON locations (company_id);
CREATE INDEX IF NOT EXISTS idx_locations_branch            ON locations (branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_locations_parent            ON locations (parent_location_id) WHERE parent_location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_functional_entities_company ON functional_entities (company_id);
CREATE INDEX IF NOT EXISTS idx_functional_entities_branch  ON functional_entities (branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_functional_entities_parent  ON functional_entities (parent_functional_entity_id) WHERE parent_functional_entity_id IS NOT NULL;

-- ── 2. updated_at triggers ────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_projects_updated_at ON projects;
CREATE TRIGGER trg_projects_updated_at BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_locations_updated_at ON locations;
CREATE TRIGGER trg_locations_updated_at BEFORE UPDATE ON locations
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_functional_entities_updated_at ON functional_entities;
CREATE TRIGGER trg_functional_entities_updated_at BEFORE UPDATE ON functional_entities
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 3. RLS — company-member gated (mirrors departments / cost_centers) ────────
ALTER TABLE projects            ENABLE ROW LEVEL SECURITY;
ALTER TABLE locations           ENABLE ROW LEVEL SECURITY;
ALTER TABLE functional_entities ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['projects','locations','functional_entities'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "auth_read_%1$s"   ON %1$s;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_insert_%1$s" ON %1$s;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_update_%1$s" ON %1$s;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_delete_%1$s" ON %1$s;', t);
    EXECUTE format('CREATE POLICY "auth_read_%1$s"   ON %1$s FOR SELECT TO authenticated USING (is_company_member(company_id));', t);
    EXECUTE format('CREATE POLICY "auth_insert_%1$s" ON %1$s FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));', t);
    EXECUTE format('CREATE POLICY "auth_update_%1$s" ON %1$s FOR UPDATE TO authenticated USING (is_company_member(company_id));', t);
    EXECUTE format('CREATE POLICY "auth_delete_%1$s" ON %1$s FOR DELETE TO authenticated USING (is_company_member(company_id));', t);
  END LOOP;
END;
$$;

-- ── 4. Shared hierarchy guard: no self-parent, same-company, no cycles ────────
CREATE OR REPLACE FUNCTION fn_dimension_hierarchy_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_parent_col     TEXT := TG_ARGV[0];
  v_parent         UUID;
  v_parent_company UUID;
  v_cursor         UUID;
  v_depth          INT := 0;
BEGIN
  v_parent := (to_jsonb(NEW) ->> v_parent_col)::UUID;
  IF v_parent IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_parent = NEW.id THEN
    RAISE EXCEPTION '% cannot be its own parent', TG_TABLE_NAME USING ERRCODE = '23514';
  END IF;

  EXECUTE format('SELECT company_id FROM %I WHERE id = $1', TG_TABLE_NAME)
    INTO v_parent_company USING v_parent;
  IF v_parent_company IS NULL THEN
    RAISE EXCEPTION 'parent % does not exist in %', v_parent, TG_TABLE_NAME USING ERRCODE = '23503';
  END IF;
  IF v_parent_company <> NEW.company_id THEN
    RAISE EXCEPTION 'parent must belong to the same company' USING ERRCODE = '23514';
  END IF;

  -- Walk ancestors; if we reach NEW.id the edge would close a cycle.
  v_cursor := v_parent;
  WHILE v_cursor IS NOT NULL LOOP
    IF v_cursor = NEW.id THEN
      RAISE EXCEPTION 'circular hierarchy detected in %', TG_TABLE_NAME USING ERRCODE = '23514';
    END IF;
    v_depth := v_depth + 1;
    IF v_depth > 100 THEN
      RAISE EXCEPTION 'hierarchy in % exceeds maximum depth', TG_TABLE_NAME USING ERRCODE = '54001';
    END IF;
    EXECUTE format('SELECT %I FROM %I WHERE id = $1', v_parent_col, TG_TABLE_NAME)
      INTO v_cursor USING v_cursor;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_projects_hierarchy_guard ON projects;
CREATE TRIGGER trg_projects_hierarchy_guard
  BEFORE INSERT OR UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION fn_dimension_hierarchy_guard('parent_project_id');
DROP TRIGGER IF EXISTS trg_locations_hierarchy_guard ON locations;
CREATE TRIGGER trg_locations_hierarchy_guard
  BEFORE INSERT OR UPDATE ON locations
  FOR EACH ROW EXECUTE FUNCTION fn_dimension_hierarchy_guard('parent_location_id');
DROP TRIGGER IF EXISTS trg_functional_entities_hierarchy_guard ON functional_entities;
CREATE TRIGGER trg_functional_entities_hierarchy_guard
  BEFORE INSERT OR UPDATE ON functional_entities
  FOR EACH ROW EXECUTE FUNCTION fn_dimension_hierarchy_guard('parent_functional_entity_id');

-- ── 5. Audit coverage (reuse the MDP-02 fn_audit_trigger mechanism) ───────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['projects','locations','functional_entities'] LOOP
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

-- ── 6. Reusable dimension validation (for future transaction packages) ────────
-- Side-effect-free: returns true only when the dimension exists for the company,
-- is active, is within its effective window as of the given date, and — when both
-- the dimension and the caller carry a branch — the branches agree. Nothing is
-- wired into posting here; this is the contract future transaction code can call.
CREATE OR REPLACE FUNCTION fn_is_valid_dimension(
  p_dimension_type TEXT,
  p_dimension_id   UUID,
  p_company_id     UUID,
  p_branch_id      UUID DEFAULT NULL,
  p_as_of          DATE DEFAULT CURRENT_DATE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_table TEXT;
  v_ok    BOOLEAN;
BEGIN
  IF p_dimension_id IS NULL THEN
    RETURN true;  -- an unset (NULL) dimension is valid: dimensions are optional tags
  END IF;

  v_table := CASE p_dimension_type
    WHEN 'project'           THEN 'projects'
    WHEN 'location'          THEN 'locations'
    WHEN 'functional_entity' THEN 'functional_entities'
    ELSE NULL
  END;
  IF v_table IS NULL THEN
    RAISE EXCEPTION 'unknown dimension type %', p_dimension_type USING ERRCODE = '22023';
  END IF;

  EXECUTE format(
    'SELECT EXISTS (
       SELECT 1 FROM %I d
       WHERE d.id = $1
         AND d.company_id = $2
         AND d.is_active
         AND (d.valid_from IS NULL OR $3 >= d.valid_from)
         AND (d.valid_to   IS NULL OR $3 <= d.valid_to)
         AND ($4 IS NULL OR d.branch_id IS NULL OR d.branch_id = $4)
     )', v_table)
  INTO v_ok
  USING p_dimension_id, p_company_id, p_as_of, p_branch_id;

  RETURN v_ok;
END;
$$;

-- ── 7. Admin-gated default provisioning (support for the future MDP-08 wizard) ─
-- Idempotently scaffolds a minimal default dimension set: a Head Office location
-- and a General functional entity. Projects are transaction-specific, so none is
-- seeded. Company-isolated and admin-gated; returns the number of default rows now
-- present (created or pre-existing).
CREATE OR REPLACE FUNCTION fn_provision_company_dimension_defaults(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision dimensions for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO locations (company_id, location_code, location_name, location_type, created_by, updated_by)
  VALUES (p_company_id, 'HO', 'Head Office', 'office', auth.uid(), auth.uid())
  ON CONFLICT (company_id, location_code) DO NOTHING;

  INSERT INTO functional_entities (company_id, entity_code, entity_name, functional_entity_type, created_by, updated_by)
  VALUES (p_company_id, 'GEN', 'General Operations', 'segment', auth.uid(), auth.uid())
  ON CONFLICT (company_id, entity_code) DO NOTHING;

  SELECT (SELECT count(*) FROM locations           WHERE company_id = p_company_id AND location_code = 'HO')
       + (SELECT count(*) FROM functional_entities WHERE company_id = p_company_id AND entity_code = 'GEN')
    INTO v_count;
  RETURN v_count;
END;
$$;

-- ── 8. Least privilege ─────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION fn_is_valid_dimension(TEXT, UUID, UUID, UUID, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_provision_company_dimension_defaults(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_is_valid_dimension(TEXT, UUID, UUID, UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_provision_company_dimension_defaults(UUID) TO authenticated, service_role;
-- The hierarchy guard runs only as a trigger; it is not part of the callable surface.
REVOKE ALL ON FUNCTION fn_dimension_hierarchy_guard() FROM PUBLIC;

COMMENT ON TABLE projects            IS 'MDP-09 (MD-14): governed Project analytical dimension. Company-scoped, branch-aware, hierarchical, effective-dated.';
COMMENT ON TABLE locations           IS 'MDP-09 (MD-15): governed Location analytical dimension. Company-scoped, branch-aware, hierarchical, effective-dated.';
COMMENT ON TABLE functional_entities IS 'MDP-09 (MD-16): governed Functional Entity analytical dimension. Company-scoped, branch-aware, hierarchical, effective-dated.';
COMMENT ON FUNCTION fn_is_valid_dimension(TEXT, UUID, UUID, UUID, DATE) IS
  'MDP-09: reusable side-effect-free validity check (exists, same company, active, in effective window, branch-consistent) for future transaction packages. NULL dimension = valid (optional tag).';
COMMENT ON FUNCTION fn_provision_company_dimension_defaults(UUID) IS
  'MDP-09: idempotently scaffolds default dimensions (Head Office location, General functional entity) for a company. Admin-gated; supports the future MDP-08 wizard.';
COMMENT ON FUNCTION fn_dimension_hierarchy_guard() IS
  'MDP-09: shared BEFORE INSERT/UPDATE trigger enforcing no self-parent, same-company parent, and acyclic hierarchy for dimension masters. Parent column passed as TG_ARGV[0].';
