-- ══════════════════════════════════════════════════════════════════════════════
-- PXL-AUD-063 — Governed BIR global configuration write policy
--
-- Problem: bir_forms and bir_form_mappings are GLOBAL statutory-configuration
-- tables (no company_id, no lifecycle) that carried broad
--   FOR ALL TO authenticated USING (true)
-- policies (auth_all_bir_forms / auth_all_bir_form_mappings, from
-- 20260628000005_sprint2_tax.sql). Any authenticated tenant user could
-- insert/update/delete shared BIR form definitions and line mappings.
--
-- No live UI reads or writes these tables (BIRFormConfigPage reads
-- ref_compliance_forms), so tightening them has no legitimate-workflow impact.
--
-- Governed model:
--   * authenticated  → READ-ONLY (SELECT) on both tables; no direct writes.
--   * All writes flow through ONE server-side path: SECURITY DEFINER RPCs that
--     require an explicit global BIR-config maintainer authority
--     (bir_config_maintainers allowlist, EMPTY by default → closed by default),
--     validate input, and write a sys_audit_logs row carrying old/new/user/
--     action/reason.
--   * Global statutory config is deliberately NOT governed by company
--     owner/admin membership — no tenant role may mutate shared BIR config.
--   * bir_forms are soft-deactivated, never hard-deleted through the app path.
--
-- These tables have no draft/finalized/filed/posted lifecycle; the applicable
-- immutability control is "no direct mutation; every change audited via the
-- governed RPC path." A statutory-config lifecycle remains a deferred product
-- decision and is intentionally out of scope here.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Replace broad policies with read-only authenticated SELECT ──────────────
DROP POLICY IF EXISTS "auth_all_bir_forms"         ON bir_forms;
DROP POLICY IF EXISTS "auth_all_bir_form_mappings" ON bir_form_mappings;

DROP POLICY IF EXISTS "bir_forms_read_authenticated"         ON bir_forms;
DROP POLICY IF EXISTS "bir_form_mappings_read_authenticated" ON bir_form_mappings;

CREATE POLICY "bir_forms_read_authenticated"
  ON bir_forms FOR SELECT TO authenticated USING (true);

CREATE POLICY "bir_form_mappings_read_authenticated"
  ON bir_form_mappings FOR SELECT TO authenticated USING (true);
-- No INSERT/UPDATE/DELETE policies → all direct client writes denied by RLS.

-- ── 2. Governed maintainer allowlist (global statutory-config authority) ───────
CREATE TABLE IF NOT EXISTS bir_config_maintainers (
  user_id    UUID PRIMARY KEY,
  note       TEXT,
  granted_by UUID,
  granted_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE bir_config_maintainers ENABLE ROW LEVEL SECURITY;

-- Authenticated users may READ the allowlist (so the RPCs / a maintainer can
-- confirm authority); there is NO client write policy — grants happen only via
-- the service-role / migration path by a platform operator. An empty allowlist
-- closes the finding by denying every authenticated write until a governed
-- maintainer is explicitly provisioned.
DROP POLICY IF EXISTS "bir_config_maintainers_read" ON bir_config_maintainers;
CREATE POLICY "bir_config_maintainers_read"
  ON bir_config_maintainers FOR SELECT TO authenticated USING (true);

-- ── 3. Authority helper ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_is_bir_config_maintainer(p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM bir_config_maintainers WHERE user_id = p_user);
$$;

-- ── 4. Governed audit helper (single row per change, carries reason) ───────────
-- Internal helper: NOT granted to authenticated. Invoked only from the
-- SECURITY DEFINER RPCs below, which run as the definer.
CREATE OR REPLACE FUNCTION fn_log_bir_config_change(
  p_table  TEXT,
  p_record UUID,
  p_action TEXT,
  p_old    JSONB,
  p_new    JSONB,
  p_reason TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO sys_audit_logs (company_id, table_name, record_id, action,
                              old_data, new_data, changed_by)
  VALUES (
    NULL, p_table, p_record, p_action,
    CASE WHEN p_old IS NULL THEN NULL
         ELSE p_old || jsonb_build_object('_change_reason', p_reason) END,
    CASE WHEN p_new IS NULL THEN NULL
         ELSE p_new || jsonb_build_object('_change_reason', p_reason) END,
    auth.uid()
  );
END;
$$;

-- ── 5. Governed write path: bir_forms ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_bir_form_upsert(
  p_form_number TEXT,
  p_description TEXT,
  p_frequency   TEXT,
  p_is_active   BOOLEAN DEFAULT true,
  p_reason      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old    bir_forms%ROWTYPE;
  v_new    bir_forms%ROWTYPE;
  v_action TEXT;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain BIR form configuration'
      USING ERRCODE = '42501';
  END IF;
  IF p_form_number IS NULL OR btrim(p_form_number) = ''
     OR p_description IS NULL OR btrim(p_description) = ''
     OR p_frequency IS NULL THEN
    RAISE EXCEPTION 'form_number, description, and frequency are required'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_old FROM bir_forms WHERE form_number = p_form_number;

  IF FOUND THEN
    UPDATE bir_forms
       SET description = p_description,
           frequency   = p_frequency,
           is_active   = COALESCE(p_is_active, is_active),
           updated_by  = auth.uid(),
           updated_at  = NOW()
     WHERE id = v_old.id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO bir_forms (form_number, description, frequency, is_active,
                           created_by, updated_by)
    VALUES (p_form_number, p_description, p_frequency, COALESCE(p_is_active, true),
            auth.uid(), auth.uid())
    RETURNING * INTO v_new;
    v_action := 'INSERT';
  END IF;

  PERFORM fn_log_bir_config_change(
    'bir_forms', v_new.id, v_action,
    CASE WHEN v_action = 'UPDATE' THEN to_jsonb(v_old) ELSE NULL END,
    to_jsonb(v_new), p_reason);
  RETURN v_new.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bir_form_set_active(
  p_form_id   UUID,
  p_is_active BOOLEAN,
  p_reason    TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old bir_forms%ROWTYPE;
  v_new bir_forms%ROWTYPE;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain BIR form configuration'
      USING ERRCODE = '42501';
  END IF;
  IF p_is_active IS NULL THEN
    RAISE EXCEPTION 'is_active is required' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_old FROM bir_forms WHERE id = p_form_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BIR form % not found', p_form_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE bir_forms
     SET is_active = p_is_active, updated_by = auth.uid(), updated_at = NOW()
   WHERE id = p_form_id
  RETURNING * INTO v_new;

  PERFORM fn_log_bir_config_change(
    'bir_forms', p_form_id, 'UPDATE', to_jsonb(v_old), to_jsonb(v_new), p_reason);
END;
$$;

-- ── 6. Governed write path: bir_form_mappings ──────────────────────────────────
CREATE OR REPLACE FUNCTION fn_bir_form_mapping_upsert(
  p_form_id         UUID,
  p_line_identifier TEXT,
  p_source_type     TEXT,
  p_source_id       UUID DEFAULT NULL,
  p_mapping_id      UUID DEFAULT NULL,
  p_reason          TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old    bir_form_mappings%ROWTYPE;
  v_new    bir_form_mappings%ROWTYPE;
  v_action TEXT;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain BIR form configuration'
      USING ERRCODE = '42501';
  END IF;
  IF p_form_id IS NULL OR p_line_identifier IS NULL OR btrim(p_line_identifier) = ''
     OR p_source_type IS NULL THEN
    RAISE EXCEPTION 'form_id, line_identifier, and source_type are required'
      USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bir_forms WHERE id = p_form_id) THEN
    RAISE EXCEPTION 'BIR form % does not exist', p_form_id USING ERRCODE = '23503';
  END IF;

  IF p_mapping_id IS NOT NULL THEN
    SELECT * INTO v_old FROM bir_form_mappings WHERE id = p_mapping_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'BIR form mapping % not found', p_mapping_id
        USING ERRCODE = 'P0002';
    END IF;
    UPDATE bir_form_mappings
       SET form_id = p_form_id, line_identifier = p_line_identifier,
           source_type = p_source_type, source_id = p_source_id,
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_mapping_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO bir_form_mappings (form_id, line_identifier, source_type,
                                   source_id, created_by, updated_by)
    VALUES (p_form_id, p_line_identifier, p_source_type, p_source_id,
            auth.uid(), auth.uid())
    RETURNING * INTO v_new;
    v_action := 'INSERT';
  END IF;

  PERFORM fn_log_bir_config_change(
    'bir_form_mappings', v_new.id, v_action,
    CASE WHEN v_action = 'UPDATE' THEN to_jsonb(v_old) ELSE NULL END,
    to_jsonb(v_new), p_reason);
  RETURN v_new.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bir_form_mapping_delete(
  p_mapping_id UUID,
  p_reason     TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old bir_form_mappings%ROWTYPE;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain BIR form configuration'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old FROM bir_form_mappings WHERE id = p_mapping_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BIR form mapping % not found', p_mapping_id
      USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM bir_form_mappings WHERE id = p_mapping_id;

  PERFORM fn_log_bir_config_change(
    'bir_form_mappings', p_mapping_id, 'DELETE', to_jsonb(v_old), NULL, p_reason);
END;
$$;

-- ── 7. Grants: least privilege for the governed write path ─────────────────────
-- Postgres grants EXECUTE to PUBLIC by default. Revoke that and grant only the
-- governed surface to authenticated. The internal audit helper is granted to
-- NOBODY: it is invoked only from the SECURITY DEFINER RPCs, which run as the
-- definer, so revoking PUBLIC prevents audit-row spoofing without breaking them.
-- The maintainer check inside each RPC governs actual authority; EXECUTE grants
-- only permit calling the governed path, not bypassing it.
REVOKE ALL ON FUNCTION fn_log_bir_config_change(TEXT, UUID, TEXT, JSONB, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_bir_config_maintainer(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bir_form_upsert(TEXT, TEXT, TEXT, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bir_form_set_active(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bir_form_mapping_upsert(UUID, TEXT, TEXT, UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bir_form_mapping_delete(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_is_bir_config_maintainer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bir_form_upsert(TEXT, TEXT, TEXT, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bir_form_set_active(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bir_form_mapping_upsert(UUID, TEXT, TEXT, UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bir_form_mapping_delete(UUID, TEXT) TO authenticated;
