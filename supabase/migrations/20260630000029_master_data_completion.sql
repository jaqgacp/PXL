-- ─────────────────────────────────────────────────────────────────────────────
-- Migration 029 — Master Data Completion
-- Adds:
--   1. warehouse_item_settings  — per-warehouse stock parameters per item
--   2. employees                — Personnel Lite (BIR-required fields)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Warehouse Item Settings ────────────────────────────────────────────────
-- Per-warehouse inventory control parameters. Separate from stock_balances
-- (which holds runtime quantities) so settings can exist before first receipt.

CREATE TABLE IF NOT EXISTS warehouse_item_settings (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID          NOT NULL REFERENCES companies(id),
  warehouse_id          UUID          NOT NULL REFERENCES warehouses(id),
  item_id               UUID          NOT NULL REFERENCES items(id),
  min_stock_level       NUMERIC(15,4) NOT NULL DEFAULT 0,
  max_stock_level       NUMERIC(15,4),
  reorder_point         NUMERIC(15,4),
  reorder_qty           NUMERIC(15,4),
  lead_time_days        SMALLINT,
  preferred_supplier_id UUID          REFERENCES suppliers(id),
  notes                 TEXT,
  created_by            UUID          REFERENCES auth.users(id),
  updated_by            UUID          REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (warehouse_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_wis_company   ON warehouse_item_settings (company_id);
CREATE INDEX IF NOT EXISTS idx_wis_warehouse ON warehouse_item_settings (warehouse_id);
CREATE INDEX IF NOT EXISTS idx_wis_item      ON warehouse_item_settings (item_id);

ALTER TABLE warehouse_item_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wis_read"   ON warehouse_item_settings FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "wis_insert" ON warehouse_item_settings FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "wis_update" ON warehouse_item_settings FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "wis_delete" ON warehouse_item_settings FOR DELETE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_wis_updated_at
  BEFORE UPDATE ON warehouse_item_settings
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 2. Employees ──────────────────────────────────────────────────────────────
-- "Lite" personnel master — holds BIR-required identifiers and payroll-relevant
-- fields without building a full HRIS. Linked to departments for GL cost
-- centre allocation and to goods issues / journal entries by employee_id.

CREATE TABLE IF NOT EXISTS employees (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID        NOT NULL REFERENCES companies(id),
  branch_id         UUID        REFERENCES branches(id),
  employee_number   TEXT        NOT NULL,           -- auto or manual
  last_name         TEXT        NOT NULL,
  first_name        TEXT        NOT NULL,
  middle_name       TEXT,
  suffix            TEXT,
  department_id     UUID        REFERENCES departments(id),
  job_title         TEXT,
  employment_type   TEXT        NOT NULL DEFAULT 'regular'
                    CHECK (employment_type IN ('regular','probationary','contractual','part_time','consultant')),
  hire_date         DATE        NOT NULL,
  regularization_date DATE,
  separation_date   DATE,
  separation_reason TEXT,
  birth_date        DATE,
  gender            TEXT        CHECK (gender IN ('male','female','other')),
  civil_status      TEXT        CHECK (civil_status IN ('single','married','widowed','separated','others')),
  -- BIR / government-mandated IDs
  tin               TEXT,
  sss_no            TEXT,
  philhealth_no     TEXT,
  pagibig_no        TEXT,
  -- Contact
  email             TEXT,
  mobile            TEXT,
  address_line      TEXT,
  city_municipality TEXT,
  province          TEXT,
  -- Status
  is_active         BOOLEAN     NOT NULL DEFAULT true,
  notes             TEXT,
  created_by        UUID        REFERENCES auth.users(id),
  updated_by        UUID        REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, employee_number)
);

CREATE INDEX IF NOT EXISTS idx_emp_company    ON employees (company_id, is_active);
CREATE INDEX IF NOT EXISTS idx_emp_department ON employees (department_id);
CREATE INDEX IF NOT EXISTS idx_emp_tin        ON employees (tin);

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "emp_read"   ON employees FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "emp_insert" ON employees FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "emp_update" ON employees FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "emp_delete" ON employees FOR DELETE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_emp_updated_at
  BEFORE UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
