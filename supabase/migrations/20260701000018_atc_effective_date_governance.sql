-- ══════════════════════════════════════════════════════════════════════════════
-- ATC GOVERNANCE: effective dates, deprecation, and historical immutability
-- Finding coverage: PXL-DA-010.
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE atc_codes
  ADD COLUMN IF NOT EXISTS effective_from DATE NOT NULL DEFAULT DATE '1900-01-01',
  ADD COLUMN IF NOT EXISTS effective_to DATE,
  ADD COLUMN IF NOT EXISTS deprecated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deprecated_reason TEXT,
  ADD COLUMN IF NOT EXISTS supersedes_atc_code_id UUID REFERENCES atc_codes(id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'atc_codes_effective_date_range_chk'
      AND conrelid = 'public.atc_codes'::regclass
  ) THEN
    ALTER TABLE atc_codes
      ADD CONSTRAINT atc_codes_effective_date_range_chk
      CHECK (effective_to IS NULL OR effective_to >= effective_from);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_atc_codes_effective_window
  ON atc_codes (tax_category, effective_from, effective_to)
  WHERE is_active = true AND deprecated_at IS NULL;

CREATE OR REPLACE FUNCTION fn_atc_code_used(p_atc_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM receipt_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM payment_voucher_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM tax_detail_entries WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM form_2307_issuance_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM customers WHERE default_cwt_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM suppliers WHERE default_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM ewt_codes WHERE atc_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM fwt_codes WHERE atc_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM percentage_tax_codes WHERE atc_id = p_atc_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_atc_code_is_current(
  p_atc_id UUID,
  p_tax_category TEXT,
  p_as_of_date DATE DEFAULT CURRENT_DATE
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM atc_codes
    WHERE id = p_atc_id
      AND is_active = true
      AND deprecated_at IS NULL
      AND tax_category = p_tax_category
      AND effective_from <= COALESCE(p_as_of_date, CURRENT_DATE)
      AND (effective_to IS NULL OR effective_to >= COALESCE(p_as_of_date, CURRENT_DATE))
  );
$$;

CREATE OR REPLACE FUNCTION fn_guard_atc_code_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF fn_atc_code_used(OLD.id) THEN
      RAISE EXCEPTION 'ATC code % is already used and cannot be deleted. Deprecate it and create a successor ATC instead.', OLD.code;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND fn_atc_code_used(OLD.id) THEN
    IF NEW.code IS DISTINCT FROM OLD.code
       OR NEW.tax_category IS DISTINCT FROM OLD.tax_category
       OR NEW.rate IS DISTINCT FROM OLD.rate THEN
      RAISE EXCEPTION 'ATC code %, tax category, and rate are immutable after use. Deprecate this ATC and create a successor version.', OLD.code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_atc_code_history_guard ON atc_codes;
CREATE TRIGGER trg_atc_code_history_guard
  BEFORE UPDATE OR DELETE ON atc_codes
  FOR EACH ROW EXECUTE FUNCTION fn_guard_atc_code_history();

CREATE OR REPLACE FUNCTION fn_validate_supplier_atc_default()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.default_atc_code_id IS NOT NULL THEN
    IF NOT fn_atc_code_is_current(NEW.default_atc_code_id, 'ewt', CURRENT_DATE) THEN
      RAISE EXCEPTION 'Default supplier EWT ATC must be an active, current EWT ATC code.';
    END IF;
    NEW.is_subject_to_ewt := true;
  END IF;

  IF COALESCE(NEW.is_subject_to_ewt, false) = false THEN
    NEW.default_atc_code_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_customer_cwt_default()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.default_cwt_atc_code_id IS NOT NULL THEN
    IF NOT fn_atc_code_is_current(NEW.default_cwt_atc_code_id, 'ewt', CURRENT_DATE) THEN
      RAISE EXCEPTION 'Default customer CWT ATC must be an active, current withholding ATC code.';
    END IF;
    NEW.is_subject_to_cwt := true;
  END IF;

  IF COALESCE(NEW.is_subject_to_cwt, false) = false THEN
    NEW.default_cwt_atc_code_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_line_ewt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_ewt_amount NUMERIC,
  p_atc_code_id UUID,
  p_ewt_tax_base NUMERIC DEFAULT NULL,
  p_ewt_variance_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate NUMERIC(8,4);
  v_code TEXT;
  v_expected NUMERIC(15,2);
  v_base NUMERIC(15,2);
  v_reason TEXT;
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_ewt_amount, 0) < 0 OR COALESCE(p_ewt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, EWT, and EWT taxable base cannot be negative.';
  END IF;

  IF COALESCE(p_ewt_amount, 0) = 0 AND COALESCE(p_ewt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when EWT amount or taxable base is specified.';
  END IF;

  SELECT code, rate INTO v_code, v_rate
  FROM atc_codes
  WHERE id = p_atc_code_id
    AND is_active = true
    AND deprecated_at IS NULL
    AND tax_category = 'ewt'
    AND effective_from <= CURRENT_DATE
    AND (effective_to IS NULL OR effective_to >= CURRENT_DATE);

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not valid for EWT.';
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive EWT rate.', v_code;
  END IF;

  v_base := ROUND(COALESCE(p_ewt_tax_base, p_payment_amount + p_ewt_amount, 0), 2);
  IF v_base <= 0 THEN
    RAISE EXCEPTION 'EWT taxable base is required when EWT is withheld.';
  END IF;

  v_expected := ROUND(v_base * v_rate / 100.0, 2);
  IF ABS(v_expected - COALESCE(p_ewt_amount, 0)) <= 0.02 THEN
    RETURN;
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_ewt_variance_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'EWT amount % does not match ATC % rate %%% on taxable base %. Expected EWT is %. Select a variance reason to proceed.',
      p_ewt_amount, v_code, v_rate, v_base, v_expected;
  END IF;

  IF v_reason NOT IN ('rounding', 'partial_non_taxable', 'bir_ruling', 'supplier_exempt', 'other_authorized') THEN
    RAISE EXCEPTION 'Invalid EWT variance reason: %', v_reason;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_receipt_line_cwt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_cwt_amount NUMERIC,
  p_atc_code_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate NUMERIC(8,4);
  v_code TEXT;
  v_base NUMERIC(15,2);
  v_expected NUMERIC(15,2);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_cwt_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Payment and CWT amounts cannot be negative.';
  END IF;

  IF COALESCE(p_cwt_amount, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when CWT amount is specified.';
  END IF;

  SELECT code, rate INTO v_code, v_rate
  FROM atc_codes
  WHERE id = p_atc_code_id
    AND is_active = true
    AND deprecated_at IS NULL
    AND tax_category = 'ewt'
    AND effective_from <= CURRENT_DATE
    AND (effective_to IS NULL OR effective_to >= CURRENT_DATE);

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not valid for withholding.';
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive withholding rate.', v_code;
  END IF;

  v_base := ROUND(COALESCE(p_payment_amount, 0) + COALESCE(p_cwt_amount, 0), 2);
  IF v_base <= 0 THEN
    RAISE EXCEPTION 'CWT taxable base is required when CWT is recorded.';
  END IF;

  v_expected := ROUND(v_base * v_rate / 100.0, 2);
  IF ABS(v_expected - COALESCE(p_cwt_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'CWT amount % does not match ATC % rate %%% on taxable base %. Expected CWT is %.',
      p_cwt_amount, v_code, v_rate, v_base, v_expected;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_atc_code_used(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_atc_code_is_current(UUID, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_line_ewt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_receipt_line_cwt(UUID, NUMERIC, NUMERIC, UUID) TO authenticated;
