-- ══════════════════════════════════════════════════════════════════════════════
-- Backlog 10 — Governed tax-code maintenance: the succession link
--
-- The rule the product already states: a statutory rate change is a SUCCESSION,
-- never an in-place edit. Close the current version's window, then start a
-- successor that points back at the version it replaces.
--
-- The guards for that rule already exist and are tested:
--   * `trg_tax_code_version_rules` (20260713000012) and `trg_atc_version_rules`
--     (20260713000002) validate a successor: same official code, starts after
--     its predecessor, no overlapping live window.
--   * `fn_guard_tax_code_history` / `fn_guard_vat_code_history` /
--     `fn_guard_atc_code_history` freeze code, rate and effective start once a
--     version has been used, and refuse the delete.
--
-- WHAT WAS MISSING: the governed write path could not express the link those
-- guards validate. `fn_tax_code_upsert`, `fn_vat_code_upsert` and
-- `fn_atc_code_upsert` (20260721000002) took no `supersedes` argument, and RLS
-- denies every direct client INSERT (20260721000001 §1). So the only outcome an
-- application could produce was an ORPHAN successor: a new version with
-- `supersedes_*_id` NULL, indistinguishable from an unrelated code that happens
-- to share a name. The version chain existed in the schema and in the triggers,
-- and nowhere else.
--
-- ALSO MISSING: of the three families, `vat_codes` alone had no version-rules
-- trigger — only a history guard. Its successor identity, ordering and window
-- overlap were unenforced. That is closed here with the same trigger the other
-- two already carry, so the rule is stated once per family and in the same place
-- for all three, and holds for every writer rather than only the app path.
--
-- Authority, audit, normalization and the RLS read-only posture are UNCHANGED:
-- writes remain maintainer-only through `fn_is_bir_config_maintainer()` (the
-- Option A decision recorded in 20260721000002 §(1)), each logging a single
-- `fn_log_bir_config_change(...)` row carrying its reason.
--
-- The upsert signatures change, so the old ones are dropped and the grants
-- re-issued. Forward-only; idempotent (DROP ... IF EXISTS / CREATE OR REPLACE).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. vat_codes joins the other two: version rules, not just a history guard ───
CREATE OR REPLACE FUNCTION fn_enforce_vat_code_version_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_predecessor vat_codes%ROWTYPE;
BEGIN
  IF NEW.effective_to IS NOT NULL AND NEW.effective_to < NEW.effective_from THEN
    RAISE EXCEPTION 'VAT code effective end cannot be before its effective start.';
  END IF;

  IF NEW.supersedes_vat_code_id IS NOT NULL THEN
    IF NEW.supersedes_vat_code_id = NEW.id THEN
      RAISE EXCEPTION 'A VAT code version cannot supersede itself.';
    END IF;
    SELECT * INTO v_predecessor FROM vat_codes WHERE id = NEW.supersedes_vat_code_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Superseded VAT code version was not found.';
    END IF;
    IF v_predecessor.vat_code <> NEW.vat_code THEN
      RAISE EXCEPTION 'Successor VAT code must keep the same code as its predecessor.';
    END IF;
    IF v_predecessor.transaction_type <> NEW.transaction_type THEN
      RAISE EXCEPTION 'Successor VAT code must keep the same direction as its predecessor.';
    END IF;
    IF v_predecessor.effective_from >= NEW.effective_from THEN
      RAISE EXCEPTION 'Successor VAT code % must start after the version it supersedes.', NEW.vat_code;
    END IF;
  END IF;

  -- No two active, non-deprecated versions of one VAT code may cover an
  -- overlapping window. A row with the SAME start is not an overlap to report
  -- here: it is the same version, and `uq_vat_code_version` decides its fate.
  IF COALESCE(NEW.is_active, false) AND NEW.deprecated_at IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM vat_codes a
      WHERE a.id <> NEW.id
        AND a.vat_code = NEW.vat_code
        AND a.effective_from <> NEW.effective_from
        AND COALESCE(a.is_active, false)
        AND a.deprecated_at IS NULL
        AND a.effective_from <= COALESCE(NEW.effective_to, DATE 'infinity')
        AND NEW.effective_from <= COALESCE(a.effective_to, DATE 'infinity')
    ) THEN
      RAISE EXCEPTION 'VAT code % has an overlapping active effective window with an existing version. Close the previous version''s effective_to before starting a successor.',
        NEW.vat_code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vat_code_version_rules ON vat_codes;
CREATE TRIGGER trg_vat_code_version_rules
  BEFORE INSERT OR UPDATE OF vat_code, tax_code_id, transaction_type, effective_from,
    effective_to, is_active, deprecated_at, supersedes_vat_code_id
  ON vat_codes
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_vat_code_version_rules();

-- ── 2. Retire the superseded upsert signatures ─────────────────────────────────
DROP FUNCTION IF EXISTS fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT);
DROP FUNCTION IF EXISTS fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT);
DROP FUNCTION IF EXISTS fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT);

-- ── 3. The governed writes, now able to state the link ─────────────────────────
-- Each is unchanged but for `p_supersedes_id`; the version-rules trigger on each
-- table remains the one implementation of what a valid successor is.

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
  p_reason         TEXT DEFAULT NULL,
  p_supersedes_id  UUID DEFAULT NULL
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
           -- A succession link may be recorded on an existing version, never cleared.
           supersedes_tax_code_id = COALESCE(p_supersedes_id, supersedes_tax_code_id),
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO tax_codes (code, description, tax_type, rate, gl_account_id, is_active,
                           effective_from, effective_to, supersedes_tax_code_id,
                           created_by, updated_by)
    VALUES (v_code, p_description, p_tax_type, p_rate, p_gl_account_id,
            COALESCE(p_is_active, true), COALESCE(p_effective_from, DATE '1900-01-01'),
            p_effective_to, p_supersedes_id, auth.uid(), auth.uid())
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
  p_reason             TEXT DEFAULT NULL,
  p_supersedes_id      UUID DEFAULT NULL
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
           effective_to   = COALESCE(p_effective_to, effective_to),
           supersedes_vat_code_id = COALESCE(p_supersedes_id, supersedes_vat_code_id)
     WHERE id = p_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO vat_codes (tax_code_id, vat_code, description, vat_classification, transaction_type,
                           relief_category, is_active, effective_from, effective_to,
                           supersedes_vat_code_id)
    VALUES (p_tax_code_id, v_vat_code, p_description, p_vat_classification, p_transaction_type,
            p_relief_category, COALESCE(p_is_active, true),
            COALESCE(p_effective_from, DATE '1900-01-01'), p_effective_to, p_supersedes_id)
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

CREATE OR REPLACE FUNCTION fn_atc_code_upsert(
  p_code           TEXT,
  p_description    TEXT,
  p_tax_category   TEXT,
  p_rate           NUMERIC,
  p_id             UUID DEFAULT NULL,
  p_is_active      BOOLEAN DEFAULT NULL,
  p_effective_from DATE DEFAULT NULL,
  p_effective_to   DATE DEFAULT NULL,
  p_reason         TEXT DEFAULT NULL,
  p_supersedes_id  UUID DEFAULT NULL
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
           supersedes_atc_code_id = COALESCE(p_supersedes_id, supersedes_atc_code_id),
           updated_by = auth.uid(), updated_at = NOW()
     WHERE id = p_id
    RETURNING * INTO v_new;
    v_action := 'UPDATE';
  ELSE
    INSERT INTO atc_codes (code, description, tax_category, rate, is_active,
                           effective_from, effective_to, supersedes_atc_code_id,
                           created_by, updated_by)
    VALUES (v_code, p_description, p_tax_category, p_rate, COALESCE(p_is_active, true),
            COALESCE(p_effective_from, DATE '1900-01-01'), p_effective_to, p_supersedes_id,
            auth.uid(), auth.uid())
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

-- ── 4. Succession as ONE operation ─────────────────────────────────────────────
-- "Close the current window and start a successor" is a single governed act, so
-- it is a single transaction. Done as two client calls it can half-succeed: the
-- predecessor's window closes, the successor insert fails, and the code resolves
-- to nothing from that date on. The order cannot be reversed either — an open
-- predecessor makes the successor overlap.
--
-- These are DELEGATIONS, not a second write path: each PERFORMs the governed
-- upsert above, so authority, normalization, validation and audit are stated
-- once and inherited here.

CREATE OR REPLACE FUNCTION fn_tax_code_succeed(
  p_id             UUID,
  p_effective_from DATE,
  p_rate           NUMERIC,
  p_description    TEXT DEFAULT NULL,
  p_gl_account_id  UUID DEFAULT NULL,
  p_reason         TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pred tax_codes%ROWTYPE;
  v_new  UUID;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_effective_from IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION 'the successor needs an effective start and a rate' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_pred FROM tax_codes WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'tax_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
  IF p_effective_from <= v_pred.effective_from THEN
    RAISE EXCEPTION 'Successor tax code % must start after the version it supersedes (% starts %).',
      v_pred.code, v_pred.code, v_pred.effective_from USING ERRCODE = '23514';
  END IF;

  -- Close the predecessor's window the day before the successor starts, unless
  -- it already ends earlier. Rate and identity are passed back unchanged, so the
  -- history guard on a used version is satisfied.
  IF v_pred.effective_to IS NULL OR v_pred.effective_to >= p_effective_from THEN
    PERFORM fn_tax_code_upsert(
      v_pred.code, v_pred.description, v_pred.tax_type, v_pred.rate, v_pred.id,
      v_pred.gl_account_id, NULL, NULL, p_effective_from - 1,
      COALESCE(p_reason, 'succession') || ' — closing the superseded version');
  END IF;

  v_new := fn_tax_code_upsert(
    v_pred.code, COALESCE(p_description, v_pred.description), v_pred.tax_type, p_rate, NULL,
    COALESCE(p_gl_account_id, v_pred.gl_account_id), true, p_effective_from, NULL,
    COALESCE(p_reason, 'succession'), v_pred.id);
  RETURN v_new;
END;
$$;

-- A VAT rate change is a change of the governed HOLDER of the rate: `vat_codes`
-- states no rate of its own, and `vat_codes_tax_code_id_transaction_type_key`
-- allows one VAT code per tax-code version per direction. So the successor must
-- point at the tax-code version carrying the new rate, and that argument is
-- required rather than optional.
CREATE OR REPLACE FUNCTION fn_vat_code_succeed(
  p_id              UUID,
  p_effective_from  DATE,
  p_tax_code_id     UUID,
  p_description     TEXT DEFAULT NULL,
  p_relief_category TEXT DEFAULT NULL,
  p_reason          TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pred vat_codes%ROWTYPE;
  v_new  UUID;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION 'the successor needs an effective start' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_pred FROM vat_codes WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vat_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
  IF p_effective_from <= v_pred.effective_from THEN
    RAISE EXCEPTION 'Successor VAT code % must start after the version it supersedes (% starts %).',
      v_pred.vat_code, v_pred.vat_code, v_pred.effective_from USING ERRCODE = '23514';
  END IF;
  IF p_tax_code_id IS NULL OR p_tax_code_id = v_pred.tax_code_id THEN
    RAISE EXCEPTION 'A VAT code successor must point at the tax-code version carrying the new rate; % still points at the old one.',
      v_pred.vat_code USING ERRCODE = '23514';
  END IF;

  IF v_pred.effective_to IS NULL OR v_pred.effective_to >= p_effective_from THEN
    PERFORM fn_vat_code_upsert(
      v_pred.tax_code_id, v_pred.vat_code, v_pred.description, v_pred.vat_classification,
      v_pred.transaction_type, v_pred.id, v_pred.relief_category, NULL, NULL,
      p_effective_from - 1,
      COALESCE(p_reason, 'succession') || ' — closing the superseded version');
  END IF;

  v_new := fn_vat_code_upsert(
    p_tax_code_id, v_pred.vat_code, COALESCE(p_description, v_pred.description),
    v_pred.vat_classification, v_pred.transaction_type, NULL,
    COALESCE(p_relief_category, v_pred.relief_category),
    true, p_effective_from, NULL, COALESCE(p_reason, 'succession'), v_pred.id);
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION fn_atc_code_succeed(
  p_id             UUID,
  p_effective_from DATE,
  p_rate           NUMERIC,
  p_description    TEXT DEFAULT NULL,
  p_reason         TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pred atc_codes%ROWTYPE;
  v_new  UUID;
BEGIN
  IF NOT fn_is_bir_config_maintainer() THEN
    RAISE EXCEPTION 'not authorized to maintain tax reference codes' USING ERRCODE = '42501';
  END IF;
  IF p_effective_from IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION 'the successor needs an effective start and a rate' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_pred FROM atc_codes WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'atc_code % not found', p_id USING ERRCODE = 'P0002'; END IF;
  IF p_effective_from <= v_pred.effective_from THEN
    RAISE EXCEPTION 'Successor ATC % must start after the version it supersedes (% starts %).',
      v_pred.code, v_pred.code, v_pred.effective_from USING ERRCODE = '23514';
  END IF;

  IF v_pred.effective_to IS NULL OR v_pred.effective_to >= p_effective_from THEN
    PERFORM fn_atc_code_upsert(
      v_pred.code, v_pred.description, v_pred.tax_category, v_pred.rate, v_pred.id,
      NULL, NULL, p_effective_from - 1,
      COALESCE(p_reason, 'succession') || ' — closing the superseded version');
  END IF;

  v_new := fn_atc_code_upsert(
    v_pred.code, COALESCE(p_description, v_pred.description), v_pred.tax_category, p_rate,
    NULL, true, p_effective_from, NULL, COALESCE(p_reason, 'succession'), v_pred.id);
  RETURN v_new;
END;
$$;

-- ── 5. Least privilege on the new signatures ───────────────────────────────────
-- A trigger function is invoked by the trigger, never by a caller. The two older
-- version-rule functions were left PUBLIC-executable; the newest one
-- (fn_enforce_percentage_tax_code_version_rules, 20260804000001) was not, and
-- that tighter posture is the one followed here.
REVOKE ALL ON FUNCTION fn_enforce_vat_code_version_rules() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_tax_code_succeed(UUID, DATE, NUMERIC, TEXT, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_vat_code_succeed(UUID, DATE, UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atc_code_succeed(UUID, DATE, NUMERIC, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_succeed(UUID, DATE, NUMERIC, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_code_succeed(UUID, DATE, UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_succeed(UUID, DATE, NUMERIC, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_enforce_vat_code_version_rules() IS
  'Backlog 10: the version-rules guard vat_codes lacked, matching trg_tax_code_version_rules and trg_atc_version_rules.';
COMMENT ON FUNCTION fn_tax_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, UUID, BOOLEAN, DATE, DATE, TEXT, UUID) IS
  'Governed tax-code write (Backlog 10). Maintainer-only. p_supersedes_id records the version this one replaces; trg_tax_code_version_rules validates the chain.';
COMMENT ON FUNCTION fn_vat_code_upsert(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, DATE, DATE, TEXT, UUID) IS
  'Governed VAT-code write (Backlog 10). Maintainer-only. trg_vat_code_version_rules validates the chain.';
COMMENT ON FUNCTION fn_atc_code_upsert(TEXT, TEXT, TEXT, NUMERIC, UUID, BOOLEAN, DATE, DATE, TEXT, UUID) IS
  'Governed ATC write (Backlog 10). Maintainer-only. trg_atc_version_rules validates the chain.';
COMMENT ON FUNCTION fn_tax_code_succeed(UUID, DATE, NUMERIC, TEXT, UUID, TEXT) IS
  'Backlog 10: close a tax-code version and start its successor in one transaction. Delegates both writes to fn_tax_code_upsert.';
COMMENT ON FUNCTION fn_vat_code_succeed(UUID, DATE, UUID, TEXT, TEXT, TEXT) IS
  'Backlog 10: close a VAT-code version and start its successor in one transaction. The successor must point at the tax-code version holding the new rate.';
COMMENT ON FUNCTION fn_atc_code_succeed(UUID, DATE, NUMERIC, TEXT, TEXT) IS
  'Backlog 10: close an ATC version and start its successor in one transaction. Delegates both writes to fn_atc_code_upsert.';
