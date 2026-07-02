-- Add supplier AP withholding defaults that use the same ATC master as PV EWT.

ALTER TABLE suppliers
  ADD COLUMN IF NOT EXISTS is_subject_to_ewt BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS default_atc_code_id UUID REFERENCES atc_codes(id);

CREATE OR REPLACE FUNCTION fn_validate_supplier_atc_default()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
BEGIN
  IF NEW.default_atc_code_id IS NOT NULL THEN
    SELECT code INTO v_code
    FROM atc_codes
    WHERE id = NEW.default_atc_code_id
      AND tax_category = 'ewt'
      AND is_active = true;

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'Supplier default ATC must be an active EWT ATC code.';
    END IF;

    NEW.is_subject_to_ewt := true;
  END IF;

  IF NEW.is_subject_to_ewt = false THEN
    NEW.default_atc_code_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supplier_atc_default ON suppliers;
CREATE TRIGGER trg_supplier_atc_default
  BEFORE INSERT OR UPDATE OF is_subject_to_ewt, default_atc_code_id
  ON suppliers
  FOR EACH ROW EXECUTE FUNCTION fn_validate_supplier_atc_default();
