-- PXL-AUD-044: consolidate withholding masters.
--
-- The operative withholding defaults are customers.default_cwt_atc_code_id and
-- suppliers.default_atc_code_id, both pointing directly to atc_codes. Retire the
-- older company-specific ewt_codes/fwt_codes wrappers and the unused
-- default_ewt_code_id columns after migrating any surviving defaults.

UPDATE customers c
SET default_cwt_atc_code_id = COALESCE(c.default_cwt_atc_code_id, e.atc_id),
    is_subject_to_cwt = true
FROM ewt_codes e
WHERE c.default_ewt_code_id = e.id;

UPDATE customers
SET is_subject_to_cwt = true
WHERE COALESCE(is_withholding_agent, false) = true;

UPDATE suppliers s
SET default_atc_code_id = COALESCE(s.default_atc_code_id, e.atc_id),
    is_subject_to_ewt = true
FROM ewt_codes e
WHERE s.default_ewt_code_id = e.id;

CREATE OR REPLACE FUNCTION fn_atc_code_used(p_atc_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM receipt_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM payment_voucher_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM vendor_bill_lines WHERE ewt_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM tax_detail_entries WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM form_2307_issuance_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM customers WHERE default_cwt_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM suppliers WHERE default_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM percentage_tax_codes WHERE atc_id = p_atc_id);
END;
$$;

ALTER TABLE customers
  DROP COLUMN IF EXISTS is_withholding_agent,
  DROP COLUMN IF EXISTS default_ewt_code_id;

ALTER TABLE suppliers
  DROP COLUMN IF EXISTS default_ewt_code_id;

ALTER TABLE items
  DROP COLUMN IF EXISTS default_ewt_code_id;

DROP TABLE IF EXISTS fwt_codes;
DROP TABLE IF EXISTS ewt_codes;

GRANT EXECUTE ON FUNCTION fn_atc_code_used(UUID) TO authenticated, service_role;
