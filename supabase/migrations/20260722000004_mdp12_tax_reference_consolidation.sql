-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-12 — Tax Reference Consolidation (gap MD-32)
--
-- ── Inventory finding (the plan is STALE; verified against the live schema) ────
-- MD-32 ("two parallel ATC representations: atc_codes vs ref_atc_codes") is ALREADY
-- RESOLVED by prior work and there is NO remaining consolidation gap to implement:
--   * ref_atc_codes was created (20260629000007) then DROPPED (20260629000014), with
--     its data + every FK (receipt_lines.atc_code_id, form_2307_tracking.atc_code_id)
--     migrated/repointed to atc_codes. atc_codes is the SINGLE authoritative ATC
--     source (verified: to_regclass('ref_atc_codes') IS NULL in the live DB).
--   * The company withholding tables ewt_codes / fwt_codes were also consolidated
--     away (20260714000003); EWT/FWT are represented by global atc_codes.
--   * tax_codes / vat_codes / atc_codes already share ONE governance + versioning
--     pattern: effective_from/effective_to, deprecated_at, supersedes_*_id, version-
--     aware uniqueness, overlap + successor guards, immutability-after-use, and
--     as-of resolvers (fn_tax_code_version_asof, fn_atc_version_asof) + is-current
--     predicates. Writes are MDP-01-governed (read-only RLS + SECURITY DEFINER RPCs,
--     RPC-audited); percentage_tax_codes stays company-scoped/member-gated/audited.
-- Every "expected scope" item (normalization, unified architecture, validation,
-- effective-date/company/reporting compatibility, audit) therefore already exists.
-- Building new reference tables/resolvers would DUPLICATE existing functionality,
-- which is out of bounds. No engineering finding is warranted (nothing is broken).
--
-- ── What this migration adds (the only genuine, non-duplicative value) ────────
-- A thin, additive, READ-ONLY consolidation SURFACE over the already-consolidated
-- masters — no new source of truth, no tax-engine/posting change:
--   1. vw_tax_reference_catalog — one canonical read interface unioning the rate-
--      bearing tax references (tax_codes ∪ atc_codes) into a common shape with a
--      computed is_current, for reporting/pickers/future transaction consumers.
--   2. fn_tax_reference_asof(reference_type, code, tax_category, as_of) — one
--      canonical as-of lookup entry point that DELEGATES to the existing
--      fn_tax_code_version_asof / fn_atc_version_asof resolvers (a facade, not a
--      reimplementation).
-- Additive, forward-only, idempotent; governance/audit/isolation unchanged.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Consolidated read-only tax-reference catalog ───────────────────────────
-- security_invoker so the underlying authenticated-read policies apply to the caller
-- (no privilege escalation); vat_codes are deliberately excluded — they are a
-- classification/mapping layer over tax_codes, not standalone rate-bearing references.
CREATE OR REPLACE VIEW vw_tax_reference_catalog
WITH (security_invoker = true) AS
SELECT 'tax_code'::text AS reference_type,
       t.id, t.code, t.description,
       t.tax_type AS tax_category, t.rate,
       t.is_active, t.effective_from, t.effective_to, t.deprecated_at,
       (t.is_active AND t.deprecated_at IS NULL
        AND t.effective_from <= CURRENT_DATE
        AND (t.effective_to IS NULL OR t.effective_to >= CURRENT_DATE)) AS is_current
FROM tax_codes t
UNION ALL
SELECT 'atc_code'::text,
       a.id, a.code, a.description,
       a.tax_category, a.rate,
       a.is_active, a.effective_from, a.effective_to, a.deprecated_at,
       (a.is_active AND a.deprecated_at IS NULL
        AND a.effective_from <= CURRENT_DATE
        AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)) AS is_current
FROM atc_codes a;

REVOKE ALL ON vw_tax_reference_catalog FROM PUBLIC, anon;
GRANT SELECT ON vw_tax_reference_catalog TO authenticated, service_role;

COMMENT ON VIEW vw_tax_reference_catalog IS
  'MDP-12 (MD-32): read-only consolidated catalog of rate-bearing tax references (tax_codes ∪ atc_codes) with a computed is_current. Single browse surface for reporting/pickers; no new source of truth.';

-- ── 2. Canonical as-of lookup facade ──────────────────────────────────────────
-- Delegates to the existing per-master resolvers so callers have ONE entry point.
CREATE OR REPLACE FUNCTION fn_tax_reference_asof(
  p_reference_type TEXT,
  p_code           TEXT,
  p_tax_category   TEXT DEFAULT NULL,
  p_as_of          DATE DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_reference_type = 'tax_code' THEN
    RETURN fn_tax_code_version_asof(p_code, p_as_of);
  ELSIF p_reference_type = 'atc_code' THEN
    IF p_tax_category IS NULL THEN
      RAISE EXCEPTION 'tax_category (ewt/fwt) is required to resolve an ATC code' USING ERRCODE = '22023';
    END IF;
    RETURN fn_atc_version_asof(p_code, p_tax_category, p_as_of);
  ELSE
    RAISE EXCEPTION 'unknown tax reference type %', p_reference_type USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_tax_reference_asof(TEXT, TEXT, TEXT, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_tax_reference_asof(TEXT, TEXT, TEXT, DATE) TO authenticated, service_role;

COMMENT ON FUNCTION fn_tax_reference_asof(TEXT, TEXT, TEXT, DATE) IS
  'MDP-12 (MD-32): canonical as-of lookup facade delegating to fn_tax_code_version_asof / fn_atc_version_asof. One entry point for resolving a tax reference by code on a document date; no resolution logic is reimplemented.';
