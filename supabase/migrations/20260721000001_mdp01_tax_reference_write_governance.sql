-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-01 (gap MD-29) — Tax-Reference Write Governance
--
-- Extends the governance pattern proven in PXL-AUD-063 (BIR config) to the global
-- tax-reference tables `tax_codes`, `vat_codes`, `atc_codes`.
--
-- WORKING-TREE REALITY (differs from the gap register's base-schema assumption):
--   * These tables no longer carry `USING(true)` writes — `20260630000021_gap_fill`
--     already replaced them with `is_any_company_admin()`-gated INSERT/UPDATE
--     (policies admin_write_* / admin_update_*). The raw "any authenticated user
--     can write" hole is thus already closed; what remains is that writes are
--     direct (not routed through a governed path) and reachable by any tenant
--     admin of ANY company.
--   * Audit ALREADY EXISTS: `20260701000005_audit_cas` attaches `fn_audit_trigger`
--     to all three tables, so every successful write is logged to sys_audit_logs.
--     This migration therefore does NOT add a second audit write (that would
--     double-log); it relies on the existing trigger. Trade-off: the generic
--     trigger does not capture a free-text change reason.
--   * `atc_codes` was renamed: atc_code -> code, tax_type -> tax_category.
--   * There IS a live client writer: src/pages/TaxSetupPage.tsx writes tax_codes
--     and vat_codes (atc_codes is read-only in the UI; percentage_tax_codes is
--     company-scoped and OUT of MDP-01 scope). That page is rewired to the RPCs
--     below in the same change so the workflow is preserved.
--
-- GOVERNED MODEL (reuses the AUD-063 governance surface — no duplication):
--   * authenticated -> READ-ONLY on all three tables; direct writes denied by RLS.
--   * All mutations flow through SECURITY DEFINER RPCs; the existing audit trigger
--     records each successful mutation (actor/action/old/new).
--   * Authority = is_any_company_admin() OR fn_is_bir_config_maintainer(). This
--     PRESERVES exactly who may maintain these codes today (any company admin),
--     while adding a single governed path + deny-by-default direct writes, and
--     allowing designated global maintainers. Restricting to maintainer-only
--     (removing the tenant-admin path) is a follow-up product decision, recorded
--     as an MDP-01 residual — intentionally NOT made here to avoid locking out
--     current admin users.
--   * The maintainer allowlist `bir_config_maintainers` and helper
--     `fn_is_bir_config_maintainer` are REUSED as the shared "global statutory
--     configuration" governance surface.
--   * Codes are deactivated via set_active, never hard-deleted through the app
--     path (DELETE remains denied by RLS), preserving referential history.
--
-- Idempotent (DROP POLICY IF EXISTS / CREATE OR REPLACE), forward-only.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Remove all direct write policies; assert authenticated read-only ────────
DROP POLICY IF EXISTS "admin_write_tax_codes"  ON tax_codes;
DROP POLICY IF EXISTS "admin_update_tax_codes" ON tax_codes;
DROP POLICY IF EXISTS "auth_write_tax_codes"   ON tax_codes;
DROP POLICY IF EXISTS "auth_update_tax_codes"  ON tax_codes;
DROP POLICY IF EXISTS "auth_all_tax_codes"     ON tax_codes;

DROP POLICY IF EXISTS "admin_write_vat_codes"  ON vat_codes;
DROP POLICY IF EXISTS "admin_update_vat_codes" ON vat_codes;
DROP POLICY IF EXISTS "auth_write_vat_codes"   ON vat_codes;
DROP POLICY IF EXISTS "auth_update_vat_codes"  ON vat_codes;
DROP POLICY IF EXISTS "auth_all_vat_codes"     ON vat_codes;

DROP POLICY IF EXISTS "admin_write_atc_codes"  ON atc_codes;
DROP POLICY IF EXISTS "admin_update_atc_codes" ON atc_codes;
DROP POLICY IF EXISTS "auth_write_atc_codes"   ON atc_codes;
DROP POLICY IF EXISTS "auth_update_atc_codes"  ON atc_codes;
DROP POLICY IF EXISTS "auth_all_atc_codes"     ON atc_codes;

-- Re-assert read-only SELECT for authenticated (idempotent).
DROP POLICY IF EXISTS "auth_read_tax_codes" ON tax_codes;
DROP POLICY IF EXISTS "auth_read_vat_codes" ON vat_codes;
DROP POLICY IF EXISTS "auth_read_atc_codes" ON atc_codes;
CREATE POLICY "auth_read_tax_codes" ON tax_codes FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read_vat_codes" ON vat_codes FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read_atc_codes" ON atc_codes FOR SELECT TO authenticated USING (true);
-- No INSERT/UPDATE/DELETE policies remain -> all direct client writes denied.

-- ── 2. Shared authority gate for tax-reference maintenance ─────────────────────
CREATE OR REPLACE FUNCTION fn_can_maintain_tax_reference()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT is_any_company_admin() OR fn_is_bir_config_maintainer();
$$;

-- ── 3. Governed write path: tax_codes ──────────────────────────────────────────
-- (Audit is provided by the pre-existing fn_audit_trigger on tax_codes.)
CREATE OR REPLACE FUNCTION fn_tax_code_upsert(
  p_code           TEXT,
  p_description    TEXT,
  p_tax_type       TEXT,
  p_rate           NUMERIC,
  p_id             UUID DEFAULT NULL,
  p_gl_account_id  UUID DEFAULT NULL,
  p_is_active      BOOLEAN DEFAULT NULL,
  p_effective_from DATE DEFAULT NULL,
  p_effective_to   DATE DEFAULT NULL,
  p_reason         TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_can_maintain_tax_reference() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_code IS NULL OR btrim(p_code) = '' OR p_description IS NULL OR btrim(p_description) = ''
     OR p_tax_type IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION 'code, description, tax_type, and rate are required' USING ERRCODE = '23514';
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE tax_codes
       SET code = p_code, description = p_description, tax_type = p_tax_type, rate = p_rate,
           gl_account_id  = COALESCE(p_gl_account_id, gl_account_id),
           is_active      = COALESCE(p_is_active, is_active),
           effective_from = COALESCE(p_effective_from, effective_from),
           effective_to   = COALESCE(p_effective_to, effective_to),
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'tax_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
  ELSE
    INSERT INTO tax_codes (code, description, tax_type, rate, gl_account_id, is_active,
                           effective_from, effective_to, created_by, updated_by)
    VALUES (p_code, p_description, p_tax_type, p_rate, p_gl_account_id,
            COALESCE(p_is_active, true), COALESCE(p_effective_from, DATE '1900-01-01'),
            p_effective_to, auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_tax_code_set_active(
  p_id UUID, p_is_active BOOLEAN, p_reason TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_can_maintain_tax_reference() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514'; END IF;
  UPDATE tax_codes SET is_active = p_is_active, updated_by = auth.uid(), updated_at = NOW()
   WHERE id = p_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'tax_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
END;
$$;

-- ── 4. Governed write path: vat_codes (no updated_by/updated_at columns) ────────
CREATE OR REPLACE FUNCTION fn_vat_code_upsert(
  p_tax_code_id        UUID,
  p_vat_code           TEXT,
  p_description        TEXT,
  p_vat_classification TEXT,
  p_transaction_type   TEXT,
  p_id                 UUID DEFAULT NULL,
  p_relief_category    TEXT DEFAULT NULL,
  p_is_active          BOOLEAN DEFAULT NULL,
  p_effective_from     DATE DEFAULT NULL,
  p_effective_to       DATE DEFAULT NULL,
  p_reason             TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_can_maintain_tax_reference() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_tax_code_id IS NULL OR p_vat_code IS NULL OR btrim(p_vat_code) = ''
     OR p_description IS NULL OR btrim(p_description) = ''
     OR p_vat_classification IS NULL OR p_transaction_type IS NULL THEN
    RAISE EXCEPTION 'tax_code_id, vat_code, description, vat_classification, and transaction_type are required'
      USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM tax_codes WHERE id = p_tax_code_id) THEN
    RAISE EXCEPTION 'parent tax_code % does not exist', p_tax_code_id USING ERRCODE = '23503';
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE vat_codes
       SET tax_code_id = p_tax_code_id, vat_code = p_vat_code, description = p_description,
           vat_classification = p_vat_classification, transaction_type = p_transaction_type,
           relief_category = p_relief_category,
           is_active      = COALESCE(p_is_active, is_active),
           effective_from = COALESCE(p_effective_from, effective_from),
           effective_to   = COALESCE(p_effective_to, effective_to)
     WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'vat_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
  ELSE
    INSERT INTO vat_codes (tax_code_id, vat_code, description, vat_classification, transaction_type,
                           relief_category, is_active, effective_from, effective_to)
    VALUES (p_tax_code_id, p_vat_code, p_description, p_vat_classification, p_transaction_type,
            p_relief_category, COALESCE(p_is_active, true),
            COALESCE(p_effective_from, DATE '1900-01-01'), p_effective_to)
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_vat_code_set_active(
  p_id UUID, p_is_active BOOLEAN, p_reason TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_can_maintain_tax_reference() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514'; END IF;
  UPDATE vat_codes SET is_active = p_is_active WHERE id = p_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'vat_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
END;
$$;

-- ── 5. Governed write path: atc_codes (columns: code, tax_category) ─────────────
CREATE OR REPLACE FUNCTION fn_atc_code_upsert(
  p_code           TEXT,
  p_description    TEXT,
  p_tax_category   TEXT,
  p_rate           NUMERIC,
  p_id             UUID DEFAULT NULL,
  p_is_active      BOOLEAN DEFAULT NULL,
  p_effective_from DATE DEFAULT NULL,
  p_effective_to   DATE DEFAULT NULL,
  p_reason         TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_can_maintain_tax_reference() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_code IS NULL OR btrim(p_code) = '' OR p_description IS NULL OR btrim(p_description) = ''
     OR p_tax_category IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION 'code, description, tax_category, and rate are required' USING ERRCODE = '23514';
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE atc_codes
       SET code = p_code, description = p_description, tax_category = p_tax_category, rate = p_rate,
           is_active      = COALESCE(p_is_active, is_active),
           effective_from = COALESCE(p_effective_from, effective_from),
           effective_to   = COALESCE(p_effective_to, effective_to),
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'atc_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
  ELSE
    INSERT INTO atc_codes (code, description, tax_category, rate, is_active,
                           effective_from, effective_to, created_by, updated_by)
    VALUES (p_code, p_description, p_tax_category, p_rate, COALESCE(p_is_active, true),
            COALESCE(p_effective_from, DATE '1900-01-01'), p_effective_to, auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_atc_code_set_active(
  p_id UUID, p_is_active BOOLEAN, p_reason TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT fn_can_maintain_tax_reference() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514'; END IF;
  UPDATE atc_codes SET is_active = p_is_active, updated_by = auth.uid(), updated_at = NOW()
   WHERE id = p_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'atc_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
END;
$$;

-- ── 6. Least privilege: revoke PUBLIC, grant authenticated (self-checked) ───────
REVOKE ALL ON FUNCTION fn_can_maintain_tax_reference() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_tax_code_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_vat_code_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atc_code_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_can_maintain_tax_reference() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_code_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
