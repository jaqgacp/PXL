-- Add the standard Section 116 percentage-tax ATC required by non-VAT
-- canonical companies. The BIR 2551Q reference identifies PT010 at 3%.

INSERT INTO atc_codes (
  code,
  description,
  tax_category,
  rate,
  is_active,
  effective_from
)
VALUES (
  'PT010',
  'Persons exempt from VAT under Section 109 (Section 116)',
  'pt',
  3.00,
  true,
  DATE '1900-01-01'
)
ON CONFLICT (code, tax_category, effective_from) DO UPDATE
SET description = EXCLUDED.description,
    rate = EXCLUDED.rate,
    is_active = true,
    effective_to = NULL,
    deprecated_at = NULL,
    deprecated_reason = NULL,
    updated_at = now();
