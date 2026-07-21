-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-01 — FINAL TEMPLATE REFINEMENT (canonical Master-Data governance pattern)
--
-- Purpose: freeze MDP-01 as the reusable governance template that every future
-- Master-Data governance package inherits. This migration resolves the four
-- template findings from the MDP-01 independent technical review and makes the
-- tax-reference governance STRUCTURALLY IDENTICAL to the PXL-AUD-063 BIR-config
-- governance so the pattern can be reused without interpretation.
--
-- ── CANONICAL GOVERNANCE PATTERN (the reusable template) ──────────────────────
-- Global statutory-configuration tables (no company_id, shared across all
-- tenants) are governed by exactly this surface, established by PXL-AUD-063 and
-- inherited here:
--   1. RLS: authenticated -> READ-ONLY (SELECT); no INSERT/UPDATE/DELETE policy,
--      so every direct client write is denied by default.
--   2. Authority: ONE shared helper `fn_is_bir_config_maintainer()` backed by the
--      ONE shared allowlist `bir_config_maintainers` (empty by default -> closed
--      by default). The `bir_config_*` names are historical (AUD-063 was the first
--      package); they are THE canonical "global statutory configuration
--      maintainer" surface, not a BIR-only surface. Generalizing the name is a
--      cosmetic follow-up that would re-touch the closed AUD-063 finding and its
--      test, and is intentionally out of MDP-01 scope.
--   3. Write path: SECURITY DEFINER RPCs that (a) check the authority helper,
--      (b) validate + NORMALIZE input, (c) capture old/new via %ROWTYPE, and
--      (d) PERFORM the shared audit helper `fn_log_bir_config_change(...)` with a
--      free-text change reason. Codes are soft-deactivated via set_active; DELETE
--      stays denied by RLS.
--   4. Least privilege: REVOKE ALL ... FROM PUBLIC; GRANT EXECUTE only on the
--      governed surface to authenticated; the audit helper is granted to nobody.
--
-- ── REVIEW FINDINGS RESOLVED ──────────────────────────────────────────────────
-- (1) Authority Model Decision (HIGH) — DECISION: Option A, MAINTAINER-ONLY.
--     Global statutory reference data is shared by every tenant; allowing any
--     tenant admin to mutate it is a cross-tenant integrity hole (the substance of
--     Critical gap MD-29). AUD-063 already ruled that "no tenant role may mutate
--     shared statutory config." Tax-reference data must follow the SAME rule to be
--     consistent and defensible. The admin-or-maintainer path from migration
--     20260721000001 is REMOVED; authority is now `fn_is_bir_config_maintainer()`
--     only. `fn_can_maintain_tax_reference()` (the divergent wrapper) is dropped.
--     Consequence: with an empty allowlist, tax-reference writes are closed until
--     a maintainer is provisioned by a platform operator — identical, deliberate,
--     closed-by-default posture to AUD-063.
-- (2) Canonical Governance Pattern — RPC structure, authority helper, audit flow,
--     and naming are now identical to AUD-063 (see above).
-- (3) Audit Reason — RESOLVED by FULLY SUPPORTING reasons end-to-end. The RPCs no
--     longer rely on the generic `fn_audit_trigger` (which cannot carry a reason);
--     they call `fn_log_bir_config_change(...)`, which records the reason in
--     `sys_audit_logs` as `_change_reason`. The generic audit trigger is removed
--     from the three tables to prevent double-logging (this is exactly the
--     tax-reference exclusion the MDP-02 audit-coverage plan anticipates). The
--     `p_reason` parameter is no longer dead — TaxSetupPage already passes it.
-- (4) Code Normalization — statutory codes are normalized to `upper(btrim(...))`
--     before persistence and before validation, so equivalent inputs (e.g.
--     ' vat12-t ' and 'VAT12-T') always produce the identical stored value.
--
-- Idempotent (DROP ... IF EXISTS / CREATE OR REPLACE), forward-only. Supersedes
-- the function bodies created in 20260721000001; RLS read-only posture and grants
-- from that migration are preserved.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Stop double-logging: remove the generic audit trigger from the three ────
--        governed tables. The governed RPCs now log explicitly (with reason).
DROP TRIGGER IF EXISTS trg_audit_tax_codes ON tax_codes;
DROP TRIGGER IF EXISTS trg_audit_vat_codes ON vat_codes;
DROP TRIGGER IF EXISTS trg_audit_atc_codes ON atc_codes;

-- ── 2. Authority: collapse to the ONE shared maintainer-only helper ────────────
--        Drop the divergent admin-or-maintainer wrapper; the RPCs below now check
--        fn_is_bir_config_maintainer() directly, exactly like the AUD-063 RPCs.
DROP FUNCTION IF EXISTS fn_can_maintain_tax_reference();

-- ── 3. Governed write path: tax_codes (structurally identical to AUD-063) ───────
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
DECLARE
  v_old    tax_codes%ROWTYPE;
  v_new    tax_codes%ROWTYPE;
  v_action TEXT;
  v_code   TEXT := upper(btrim(p_code));   -- normalization
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF v_code IS NULL OR v_code = '' OR p_description IS NULL OR btrim(p_description) = ''
     OR p_tax_type IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION 'code, description, tax_type, and rate are required' USING ERRCODE = '23514';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_old FROM tax_codes WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'tax_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
    UPDATE tax_codes
       SET code = v_code, description = p_description, tax_type = p_tax_type, rate = p_rate,
           gl_account_id  = COALESCE(p_gl_account_id, gl_account_id),
           is_active      = COALESCE(p_is_active, is_active),
           effective_from = COALESCE(p_effective_from, effective_from),
           effective_to   = COALESCE(p_effective_to, effective_to),
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO tax_codes (code, description, tax_type, rate, gl_account_id, is_active,
                           effective_from, effective_to, created_by, updated_by)
    VALUES (v_code, p_description, p_tax_type, p_rate, p_gl_account_id,
            COALESCE(p_is_active, true), COALESCE(p_effective_from, DATE '1900-01-01'),
            p_effective_to, auth.uid(), auth.uid())
    RETURNING * INTO v_new;
    v_action := 'INSERT';
  END IF;

  PERFORM fn_log_bir_config_change(
    'tax_codes', v_new.id, v_action,
    CASE WHEN v_action = 'UPDATE' THEN to_jsonb(v_old) ELSE NULL END,
    to_jsonb(v_new), p_reason);
  RETURN v_new.id;
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
DECLARE
  v_old tax_codes%ROWTYPE;
  v_new tax_codes%ROWTYPE;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514'; END IF;

  SELECT * INTO v_old FROM tax_codes WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'tax_code % not found', p_id USING ERRCODE = 'P0002'; END IF;

  UPDATE tax_codes SET is_active = p_is_active, updated_by = auth.uid(), updated_at = NOW()
   WHERE id = p_id RETURNING * INTO v_new;

  PERFORM fn_log_bir_config_change(
    'tax_codes', p_id, 'UPDATE', to_jsonb(v_old), to_jsonb(v_new), p_reason);
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
DECLARE
  v_old      vat_codes%ROWTYPE;
  v_new      vat_codes%ROWTYPE;
  v_action   TEXT;
  v_vat_code TEXT := upper(btrim(p_vat_code));   -- normalization
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_tax_code_id IS NULL OR v_vat_code IS NULL OR v_vat_code = ''
     OR p_description IS NULL OR btrim(p_description) = ''
     OR p_vat_classification IS NULL OR p_transaction_type IS NULL THEN
    RAISE EXCEPTION 'tax_code_id, vat_code, description, vat_classification, and transaction_type are required'
      USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM tax_codes WHERE id = p_tax_code_id) THEN
    RAISE EXCEPTION 'parent tax_code % does not exist', p_tax_code_id USING ERRCODE = '23503';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_old FROM vat_codes WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'vat_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
    UPDATE vat_codes
       SET tax_code_id = p_tax_code_id, vat_code = v_vat_code, description = p_description,
           vat_classification = p_vat_classification, transaction_type = p_transaction_type,
           relief_category = p_relief_category,
           is_active      = COALESCE(p_is_active, is_active),
           effective_from = COALESCE(p_effective_from, effective_from),
           effective_to   = COALESCE(p_effective_to, effective_to)
     WHERE id = p_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO vat_codes (tax_code_id, vat_code, description, vat_classification, transaction_type,
                           relief_category, is_active, effective_from, effective_to)
    VALUES (p_tax_code_id, v_vat_code, p_description, p_vat_classification, p_transaction_type,
            p_relief_category, COALESCE(p_is_active, true),
            COALESCE(p_effective_from, DATE '1900-01-01'), p_effective_to)
    RETURNING * INTO v_new;
    v_action := 'INSERT';
  END IF;

  PERFORM fn_log_bir_config_change(
    'vat_codes', v_new.id, v_action,
    CASE WHEN v_action = 'UPDATE' THEN to_jsonb(v_old) ELSE NULL END,
    to_jsonb(v_new), p_reason);
  RETURN v_new.id;
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
DECLARE
  v_old vat_codes%ROWTYPE;
  v_new vat_codes%ROWTYPE;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514'; END IF;

  SELECT * INTO v_old FROM vat_codes WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vat_code % not found', p_id USING ERRCODE = 'P0002'; END IF;

  UPDATE vat_codes SET is_active = p_is_active WHERE id = p_id RETURNING * INTO v_new;

  PERFORM fn_log_bir_config_change(
    'vat_codes', p_id, 'UPDATE', to_jsonb(v_old), to_jsonb(v_new), p_reason);
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
DECLARE
  v_old    atc_codes%ROWTYPE;
  v_new    atc_codes%ROWTYPE;
  v_action TEXT;
  v_code   TEXT := upper(btrim(p_code));   -- normalization
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF v_code IS NULL OR v_code = '' OR p_description IS NULL OR btrim(p_description) = ''
     OR p_tax_category IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION 'code, description, tax_category, and rate are required' USING ERRCODE = '23514';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_old FROM atc_codes WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'atc_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
    UPDATE atc_codes
       SET code = v_code, description = p_description, tax_category = p_tax_category, rate = p_rate,
           is_active      = COALESCE(p_is_active, is_active),
           effective_from = COALESCE(p_effective_from, effective_from),
           effective_to   = COALESCE(p_effective_to, effective_to),
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO atc_codes (code, description, tax_category, rate, is_active,
                           effective_from, effective_to, created_by, updated_by)
    VALUES (v_code, p_description, p_tax_category, p_rate, COALESCE(p_is_active, true),
            COALESCE(p_effective_from, DATE '1900-01-01'), p_effective_to, auth.uid(), auth.uid())
    RETURNING * INTO v_new;
    v_action := 'INSERT';
  END IF;

  PERFORM fn_log_bir_config_change(
    'atc_codes', v_new.id, v_action,
    CASE WHEN v_action = 'UPDATE' THEN to_jsonb(v_old) ELSE NULL END,
    to_jsonb(v_new), p_reason);
  RETURN v_new.id;
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
DECLARE
  v_old atc_codes%ROWTYPE;
  v_new atc_codes%ROWTYPE;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514'; END IF;

  SELECT * INTO v_old FROM atc_codes WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'atc_code % not found', p_id USING ERRCODE = 'P0002'; END IF;

  UPDATE atc_codes SET is_active = p_is_active, updated_by = auth.uid(), updated_at = NOW()
   WHERE id = p_id RETURNING * INTO v_new;

  PERFORM fn_log_bir_config_change(
    'atc_codes', p_id, 'UPDATE', to_jsonb(v_old), to_jsonb(v_new), p_reason);
END;
$$;

-- ── 6. Least privilege (signatures unchanged; re-assert explicitly) ─────────────
REVOKE ALL ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_tax_code_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_vat_code_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atc_code_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_code_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
