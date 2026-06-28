-- ============================================================
-- Fix Migration: Schema alignment with blueprint documentation
-- ============================================================

-- ── Fix 1: atc_codes ─────────────────────────────────────────
-- Doc uses `code` (not `atc_code`) and `tax_category` (not `tax_type`)
-- Also adds 'it' and 'pt' values to match BIR ATC taxonomy

ALTER TABLE atc_codes RENAME COLUMN atc_code TO code;
ALTER TABLE atc_codes RENAME COLUMN tax_type TO tax_category;

-- Drop the old check constraint (name retained from original column name after rename)
ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_tax_type_check;
ALTER TABLE atc_codes ADD CONSTRAINT atc_codes_tax_category_check
  CHECK (tax_category IN ('ewt', 'fwt', 'it', 'pt'));

-- Rename the unique key for clarity
ALTER INDEX IF EXISTS atc_codes_atc_code_key RENAME TO atc_codes_code_key;

-- Add missing audit columns
ALTER TABLE atc_codes ADD COLUMN IF NOT EXISTS created_by UUID;
ALTER TABLE atc_codes ADD COLUMN IF NOT EXISTS updated_by UUID;
ALTER TABLE atc_codes ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE TRIGGER atc_codes_updated_at
  BEFORE UPDATE ON atc_codes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── Fix 2: currencies ─────────────────────────────────────────
-- Doc uses `name` (not `currency_name`) and adds `decimal_places`

ALTER TABLE currencies RENAME COLUMN currency_name TO name;

ALTER TABLE currencies ADD COLUMN IF NOT EXISTS decimal_places INTEGER NOT NULL DEFAULT 2;

-- Set JPY to 0 decimal places (standard ISO 4217)
UPDATE currencies SET decimal_places = 0 WHERE currency_code = 'JPY';

-- ── Fix 3: exchange_rates ─────────────────────────────────────
-- Doc requires rate_type (bsp_reference/buy/sell) and source (manual/bsp_import/api_feed)
-- Unique constraint must include rate_type

ALTER TABLE exchange_rates
  ADD COLUMN IF NOT EXISTS rate_type TEXT NOT NULL DEFAULT 'bsp_reference'
    CHECK (rate_type IN ('bsp_reference', 'buy', 'sell'));

ALTER TABLE exchange_rates
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual', 'bsp_import', 'api_feed'));

-- Update unique constraint to include rate_type
ALTER TABLE exchange_rates
  DROP CONSTRAINT IF EXISTS exchange_rates_company_id_currency_id_rate_date_key;

ALTER TABLE exchange_rates
  ADD CONSTRAINT exchange_rates_company_currency_date_type_key
  UNIQUE(company_id, currency_id, rate_date, rate_type);

-- Add index for rate lookup (used in multi-currency transaction lookup)
CREATE INDEX IF NOT EXISTS idx_exchange_rates_lookup
  ON exchange_rates (company_id, currency_id, rate_date DESC, rate_type);

-- ── Fix 4: tax_codes ─────────────────────────────────────────
-- Doc requires audit columns

ALTER TABLE tax_codes ADD COLUMN IF NOT EXISTS created_by UUID;
ALTER TABLE tax_codes ADD COLUMN IF NOT EXISTS updated_by UUID;
ALTER TABLE tax_codes ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE TRIGGER tax_codes_updated_at
  BEFORE UPDATE ON tax_codes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
