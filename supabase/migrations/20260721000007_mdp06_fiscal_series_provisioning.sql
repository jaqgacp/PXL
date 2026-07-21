-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-06 — Fiscal Calendar & Number Series Auto-Provisioning (gaps MD-02, MD-03)
--
-- Lets a company post and number documents immediately after setup, as REUSABLE
-- BACKEND capabilities (callable by the future MDP-08 wizard / operators). No UI,
-- no onboarding wizard, no posting-period validation, and no change to the
-- numbering-engine internals or posting logic.
--
-- ── Inventory result (what already exists — NOT rebuilt) ──────────────────────
-- * fiscal_years (company_id, year_name, start/end, is_calendar, status open/closed;
--   UNIQUE(company_id, year_name)) and fiscal_periods (fiscal_year_id, period_number
--   1..12, name, start/end, is_locked; UNIQUE(fiscal_year_id, period_number)) exist.
-- * number_series is a strong CAS-grade engine (branch_id, document_type_id,
--   document_code, prefix/padding/length, current_sequence, ATP fields, reset;
--   UNIQUE(company_id, branch_id, document_type_id)) with its own guard/shape
--   triggers and audit coverage — left untouched.
-- * fn_require_open_fiscal_period / fn_close_fiscal_year / the numbering guards
--   already exist and are OUT OF SCOPE (posting-period validation, year-end close,
--   numbering internals).
-- MISSING: (MD-02) automatic fiscal-year + 12-period generation, and (MD-03)
--   automatic default number-series provisioning per BIR-registered document type
--   and branch. Neither exists today. Also, MDP-02 deferred audit coverage of
--   fiscal_years/fiscal_periods to this (owning) package.
--
-- ── What this migration adds (only the genuine gaps) ──────────────────────────
--   1. Audit coverage for fiscal_years / fiscal_periods (reuses the MDP-02
--      fn_audit_trigger mechanism; number_series is already audited — not re-added,
--      so no double-logging).
--   2. fn_generate_fiscal_periods(fiscal_year) — idempotent 12 monthly periods.
--   3. fn_create_fiscal_year(company, start_date, year_name?) — creates the year
--      (configurable start) and generates its periods.
--   4. fn_provision_number_series(company, branch) — default series for every
--      BIR-registered document type, branch-aware and future-extensible.
--
-- Provisioning is done via EXPLICIT functions (NOT an INSERT trigger on
-- fiscal_years) so existing manual fiscal-year/period paths keep working. All
-- functions are SECURITY DEFINER, admin-gated (can_admin_company), and idempotent
-- (ON CONFLICT on the existing unique keys). Additive, forward-only, no RLS or
-- posting-logic change.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Complete MDP-02's deferred audit coverage for the fiscal tables ────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['fiscal_years','fiscal_periods'] LOOP
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

-- ── 2. Generate the 12 monthly periods for a fiscal year (idempotent) ─────────
CREATE OR REPLACE FUNCTION fn_generate_fiscal_periods(p_fiscal_year_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_start      DATE;
BEGIN
  SELECT company_id, start_date INTO v_company_id, v_start
  FROM fiscal_years WHERE id = p_fiscal_year_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fiscal year % not found', p_fiscal_year_id USING ERRCODE = 'P0002';
  END IF;
  IF NOT can_admin_company(v_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision fiscal periods for company %', v_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                             start_date, end_date, is_locked)
  SELECT v_company_id, p_fiscal_year_id, gs.m,
         to_char((v_start + ((gs.m - 1) || ' months')::interval), 'Mon YYYY'),
         (v_start + ((gs.m - 1) || ' months')::interval)::date,
         (v_start + (gs.m || ' months')::interval - interval '1 day')::date,
         false
  FROM generate_series(1, 12) AS gs(m)
  ON CONFLICT (fiscal_year_id, period_number) DO NOTHING;

  RETURN (SELECT count(*)::INTEGER FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id);
END;
$$;

-- ── 3. Create a fiscal year (configurable start) + its periods (idempotent) ───
CREATE OR REPLACE FUNCTION fn_create_fiscal_year(
  p_company_id UUID,
  p_start_date DATE,
  p_year_name  TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year_name   TEXT := COALESCE(NULLIF(btrim(p_year_name), ''), 'FY' || to_char(p_start_date, 'YYYY'));
  v_is_calendar BOOLEAN := (EXTRACT(MONTH FROM p_start_date) = 1 AND EXTRACT(DAY FROM p_start_date) = 1);
  v_fy_id       UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision a fiscal year for company %', p_company_id USING ERRCODE = '42501';
  END IF;
  IF p_start_date IS NULL THEN
    RAISE EXCEPTION 'fiscal year start date is required' USING ERRCODE = '23514';
  END IF;

  INSERT INTO fiscal_years (company_id, year_name, start_date, end_date, is_calendar, status,
                            created_by, updated_by)
  VALUES (p_company_id, v_year_name, p_start_date,
          (p_start_date + interval '1 year' - interval '1 day')::date,
          v_is_calendar, 'open', auth.uid(), auth.uid())
  ON CONFLICT (company_id, year_name) DO NOTHING;

  SELECT id INTO v_fy_id FROM fiscal_years
  WHERE company_id = p_company_id AND year_name = v_year_name;

  PERFORM fn_generate_fiscal_periods(v_fy_id);
  RETURN v_fy_id;
END;
$$;

-- ── 4. Provision default number series per BIR-registered document type ───────
-- Branch-aware and future-extensible: every BIR-registered ref_document_types row
-- gets a series for the branch; new BIR document types are picked up on the next
-- call. Idempotent on UNIQUE(company_id, branch_id, document_type_id).
CREATE OR REPLACE FUNCTION fn_provision_number_series(
  p_company_id UUID,
  p_branch_id  UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision number series for company %', p_company_id USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'branch % does not belong to company %', p_branch_id, p_company_id USING ERRCODE = '23503';
  END IF;

  INSERT INTO number_series (company_id, branch_id, document_type_id, document_code,
                             prefix, suffix, number_length, padding, starting_number,
                             next_number, current_sequence, reset_frequency, is_active,
                             created_by, updated_by)
  SELECT p_company_id, p_branch_id, dt.id, dt.document_code,
         dt.document_code || '-', NULL, 6, 6, 1, 1, 0, 'never', true,
         auth.uid(), auth.uid()
  FROM ref_document_types dt
  WHERE dt.is_bir_registered = true
  ON CONFLICT (company_id, branch_id, document_type_id) DO NOTHING;

  RETURN (SELECT count(*)::INTEGER
          FROM number_series ns
          JOIN ref_document_types dt ON dt.id = ns.document_type_id
          WHERE ns.company_id = p_company_id AND ns.branch_id = p_branch_id
            AND dt.is_bir_registered = true);
END;
$$;

-- ── 5. Least privilege: functions self-check authority; grant execute ─────────
REVOKE ALL ON FUNCTION fn_generate_fiscal_periods(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_create_fiscal_year(UUID, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_provision_number_series(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_generate_fiscal_periods(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_create_fiscal_year(UUID, DATE, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_provision_number_series(UUID, UUID) TO authenticated, service_role;

COMMENT ON FUNCTION fn_generate_fiscal_periods(UUID) IS
  'MDP-06: generates the 12 monthly periods for a fiscal year. Idempotent; admin-gated.';
COMMENT ON FUNCTION fn_create_fiscal_year(UUID, DATE, TEXT) IS
  'MDP-06: creates a fiscal year (configurable start) and its 12 periods. Idempotent; admin-gated.';
COMMENT ON FUNCTION fn_provision_number_series(UUID, UUID) IS
  'MDP-06: provisions default number series per BIR-registered document type for a branch. Idempotent; admin-gated.';
