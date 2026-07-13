-- ══════════════════════════════════════════════════════════════════════════════
-- TAX / VAT CODE EFFECTIVE-DATE + VERSION GOVERNANCE (PXL-DA-010 residue)
--
-- ATC governance (20260701000018 + 20260713000002) already effective-dates and
-- version-locks withholding codes. VAT and percentage-tax rates live on
-- tax_codes.rate, which the VAT/PT computation RPCs resolve at posting/recompute
-- time through vat_codes -> tax_codes. That rate carried NO effective-date or
-- version governance: an in-place edit of tax_codes.rate (e.g. VAT 12% -> 14%)
-- silently changed BOTH future postings AND the recomputed VAT of every already
-- posted document that references the code, breaking historical report stability.
--
-- This migration extends the exact ATC release pattern to tax_codes (the rate
-- holder) and vat_codes (the classification/mapping holder):
--
--   * effective_from / effective_to / deprecation / supersession columns;
--   * version-aware uniqueness (code, effective_from) replacing the global code
--     key, so one official code may carry successive effective-dated versions;
--   * an overlap + successor-integrity guard;
--   * immutability-after-use: once a tax_code has driven a posted computation its
--     code, tax_type, rate, and effective_from are frozen (deprecate + successor
--     is the only path), which is what makes historical VAT/PT recomputation
--     stable under a statutory rate change; vat_codes freeze their tax_code_id,
--     classification, and direction once transactionally used;
--   * delete protection for used codes;
--   * an as-of version resolver + is-current predicate for pickers/reconciliation.
--
-- No heavy VAT/PT posting RPC is modified: because a used version's rate is now
-- immutable and rate changes create a NEW successor version (a new vat_code the
-- item/document then selects), every already posted line keeps resolving the
-- frozen rate on the version it referenced. This mirrors the ATC approach:
-- versioning + immutability, not per-caller rewrites.
-- ══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Governance columns
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE tax_codes
  ADD COLUMN IF NOT EXISTS effective_from DATE NOT NULL DEFAULT DATE '1900-01-01',
  ADD COLUMN IF NOT EXISTS effective_to DATE,
  ADD COLUMN IF NOT EXISTS deprecated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deprecated_reason TEXT,
  ADD COLUMN IF NOT EXISTS supersedes_tax_code_id UUID REFERENCES tax_codes(id);

ALTER TABLE vat_codes
  ADD COLUMN IF NOT EXISTS effective_from DATE NOT NULL DEFAULT DATE '1900-01-01',
  ADD COLUMN IF NOT EXISTS effective_to DATE,
  ADD COLUMN IF NOT EXISTS deprecated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deprecated_reason TEXT,
  ADD COLUMN IF NOT EXISTS supersedes_vat_code_id UUID REFERENCES vat_codes(id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tax_codes_effective_date_range_chk'
      AND conrelid = 'public.tax_codes'::regclass
  ) THEN
    ALTER TABLE tax_codes ADD CONSTRAINT tax_codes_effective_date_range_chk
      CHECK (effective_to IS NULL OR effective_to >= effective_from);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'vat_codes_effective_date_range_chk'
      AND conrelid = 'public.vat_codes'::regclass
  ) THEN
    ALTER TABLE vat_codes ADD CONSTRAINT vat_codes_effective_date_range_chk
      CHECK (effective_to IS NULL OR effective_to >= effective_from);
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Version-aware uniqueness (one official code, successive versions)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE tax_codes DROP CONSTRAINT IF EXISTS tax_codes_code_key;
DROP INDEX IF EXISTS tax_codes_code_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_tax_code_version
  ON tax_codes (code, effective_from);
CREATE UNIQUE INDEX IF NOT EXISTS uq_tax_code_direct_successor
  ON tax_codes (supersedes_tax_code_id)
  WHERE supersedes_tax_code_id IS NOT NULL;

ALTER TABLE vat_codes DROP CONSTRAINT IF EXISTS vat_codes_vat_code_key;
DROP INDEX IF EXISTS vat_codes_vat_code_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_vat_code_version
  ON vat_codes (vat_code, effective_from);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vat_code_direct_successor
  ON vat_codes (supersedes_vat_code_id)
  WHERE supersedes_vat_code_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tax_codes_effective_window
  ON tax_codes (code, effective_from, effective_to)
  WHERE is_active = true AND deprecated_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Usage predicates
-- ─────────────────────────────────────────────────────────────────────────────
-- A vat_code is "used" once any transaction line or the posted tax ledger
-- references it. Item master defaults are intentionally excluded (the FK already
-- blocks orphaning them, and a master default is not a posted computation).
CREATE OR REPLACE FUNCTION fn_vat_code_used(p_vat_code_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM sales_invoice_lines WHERE vat_code_id = p_vat_code_id)
      OR EXISTS (SELECT 1 FROM credit_memo_lines   WHERE vat_code_id = p_vat_code_id)
      OR EXISTS (SELECT 1 FROM debit_memo_lines    WHERE vat_code_id = p_vat_code_id)
      OR EXISTS (SELECT 1 FROM vendor_bill_lines   WHERE vat_code_id = p_vat_code_id)
      OR EXISTS (SELECT 1 FROM cash_purchase_lines WHERE vat_code_id = p_vat_code_id)
      OR EXISTS (SELECT 1 FROM vendor_credit_lines WHERE vat_code_id = p_vat_code_id)
      OR EXISTS (SELECT 1 FROM tax_detail_entries  WHERE vat_code_id = p_vat_code_id);
END;
$$;

-- A tax_code is "used" once the posted tax ledger references it directly (VAT/PT),
-- or once any of its vat_code children has itself been used.
CREATE OR REPLACE FUNCTION fn_tax_code_used(p_tax_code_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM tax_detail_entries WHERE tax_code_id = p_tax_code_id)
      OR EXISTS (
        SELECT 1 FROM vat_codes vc
        WHERE vc.tax_code_id = p_tax_code_id AND fn_vat_code_used(vc.id)
      );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. As-of resolvers / is-current predicates
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_tax_code_version_asof(
  p_code TEXT,
  p_as_of DATE DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id
  FROM tax_codes
  WHERE code = UPPER(BTRIM(p_code))
    AND is_active = true
    AND deprecated_at IS NULL
    AND effective_from <= COALESCE(p_as_of, CURRENT_DATE)
    AND (effective_to IS NULL OR effective_to >= COALESCE(p_as_of, CURRENT_DATE))
  ORDER BY effective_from DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_tax_code_is_current(
  p_tax_code_id UUID,
  p_as_of DATE DEFAULT CURRENT_DATE
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tax_codes
    WHERE id = p_tax_code_id
      AND is_active = true
      AND deprecated_at IS NULL
      AND effective_from <= COALESCE(p_as_of, CURRENT_DATE)
      AND (effective_to IS NULL OR effective_to >= COALESCE(p_as_of, CURRENT_DATE))
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Version integrity guard: no overlapping active windows; valid successor
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enforce_tax_code_version_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_predecessor tax_codes%ROWTYPE;
BEGIN
  IF NEW.effective_to IS NOT NULL AND NEW.effective_to < NEW.effective_from THEN
    RAISE EXCEPTION 'Tax code effective end cannot be before its effective start.';
  END IF;

  IF NEW.supersedes_tax_code_id IS NOT NULL THEN
    IF NEW.supersedes_tax_code_id = NEW.id THEN
      RAISE EXCEPTION 'A tax code version cannot supersede itself.';
    END IF;
    SELECT * INTO v_predecessor FROM tax_codes WHERE id = NEW.supersedes_tax_code_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Superseded tax code version was not found.';
    END IF;
    IF v_predecessor.code <> NEW.code THEN
      RAISE EXCEPTION 'Successor tax code must keep the same official code as its predecessor.';
    END IF;
    IF v_predecessor.effective_from >= NEW.effective_from THEN
      RAISE EXCEPTION 'Successor tax code % must start after the version it supersedes.', NEW.code;
    END IF;
  END IF;

  -- No two active, non-deprecated versions of the same code may cover an
  -- overlapping window. The admin closes the prior version's effective_to before
  -- starting a successor (the documented deprecate-and-succeed workflow).
  IF COALESCE(NEW.is_active, false) AND NEW.deprecated_at IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM tax_codes a
      WHERE a.id <> NEW.id
        AND a.code = NEW.code
        AND COALESCE(a.is_active, false)
        AND a.deprecated_at IS NULL
        AND a.effective_from <= COALESCE(NEW.effective_to, DATE 'infinity')
        AND NEW.effective_from <= COALESCE(a.effective_to, DATE 'infinity')
    ) THEN
      RAISE EXCEPTION 'Tax code % has an overlapping active effective window with an existing version. Close the previous version''s effective_to before starting a successor.',
        NEW.code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_code_version_rules ON tax_codes;
CREATE TRIGGER trg_tax_code_version_rules
  BEFORE INSERT OR UPDATE OF code, effective_from, effective_to,
    is_active, deprecated_at, supersedes_tax_code_id
  ON tax_codes
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_tax_code_version_rules();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. History guards: freeze rate/identity once used, block delete once used
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_guard_tax_code_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF fn_tax_code_used(OLD.id) THEN
      RAISE EXCEPTION 'Tax code % is already used and cannot be deleted. Deprecate it and create a successor version instead.', OLD.code;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND fn_tax_code_used(OLD.id) THEN
    IF NEW.code IS DISTINCT FROM OLD.code
       OR NEW.tax_type IS DISTINCT FROM OLD.tax_type
       OR NEW.rate IS DISTINCT FROM OLD.rate
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from THEN
      RAISE EXCEPTION 'Tax code, type, rate, and effective start are immutable after use. Deprecate this tax code and create a successor version.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_code_history_guard ON tax_codes;
CREATE TRIGGER trg_tax_code_history_guard
  BEFORE UPDATE OR DELETE ON tax_codes
  FOR EACH ROW EXECUTE FUNCTION fn_guard_tax_code_history();

CREATE OR REPLACE FUNCTION fn_guard_vat_code_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF fn_vat_code_used(OLD.id) THEN
      RAISE EXCEPTION 'VAT code % is already used and cannot be deleted. Deprecate it and create a successor version instead.', OLD.vat_code;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND fn_vat_code_used(OLD.id) THEN
    IF NEW.vat_code IS DISTINCT FROM OLD.vat_code
       OR NEW.tax_code_id IS DISTINCT FROM OLD.tax_code_id
       OR NEW.vat_classification IS DISTINCT FROM OLD.vat_classification
       OR NEW.transaction_type IS DISTINCT FROM OLD.transaction_type
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from THEN
      RAISE EXCEPTION 'VAT code, its tax code, classification, direction, and effective start are immutable after use. Deprecate this VAT code and create a successor version.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vat_code_history_guard ON vat_codes;
CREATE TRIGGER trg_vat_code_history_guard
  BEFORE UPDATE OR DELETE ON vat_codes
  FOR EACH ROW EXECUTE FUNCTION fn_guard_vat_code_history();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Grants
-- ─────────────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_vat_code_used(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_used(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_version_asof(TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_tax_code_is_current(UUID, DATE) TO authenticated;
