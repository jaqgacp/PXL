-- ── CWT / Form 2307 Compliance Tables ───────────────────────────────────────

-- ATC Codes: BIR Alphanumeric Tax Codes for withholding tax classification
CREATE TABLE IF NOT EXISTS ref_atc_codes (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  atc_code    TEXT        NOT NULL UNIQUE,
  description TEXT        NOT NULL,
  tax_rate    NUMERIC(5,2) NOT NULL DEFAULT 0,
  category    TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE
);

INSERT INTO ref_atc_codes (atc_code, description, tax_rate, category) VALUES
  ('WC010', 'Professional fees, talent fees, commissions — juridical persons',            15.00, 'professional'),
  ('WC158', 'Purchases of goods by Top Withholding Agents — juridical persons',            1.00, 'goods'),
  ('WC160', 'Purchases of services by Top Withholding Agents — juridical persons',         2.00, 'services'),
  ('WC220', 'Gross commissions of customs, insurance, stock, real estate brokers',        10.00, 'commission'),
  ('WC240', 'Income payments to partners of general professional partnerships',           15.00, 'professional'),
  ('WI010', 'Professional fees, talent fees, commissions — individuals',                   5.00, 'professional'),
  ('WI158', 'Purchases of goods by Top Withholding Agents — individual payees',            1.00, 'goods'),
  ('WI160', 'Purchases of services by Top Withholding Agents — individual payees',         2.00, 'services')
ON CONFLICT (atc_code) DO NOTHING;

-- Form 2307 Tracking: tracks receipt of BIR Form 2307 from withholding customers
CREATE TABLE IF NOT EXISTS form_2307_tracking (
  id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID         NOT NULL REFERENCES companies(id),
  receipt_line_id   UUID         NOT NULL UNIQUE REFERENCES receipt_lines(id),
  customer_id       UUID         REFERENCES customers(id),
  cwt_amount_booked NUMERIC(15,2) NOT NULL DEFAULT 0,
  status            TEXT         NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','received','claimed')),
  date_received     DATE,
  atc_code_id       UUID         REFERENCES ref_atc_codes(id),
  period_covered    TEXT,
  file_url          TEXT,
  remarks           TEXT,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_form_2307_tracking_updated_at
  BEFORE UPDATE ON form_2307_tracking
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Extend sales_invoices with informational CWT expected amount (display only, not deducted)
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS cwt_amount_expected NUMERIC(15,2);

-- Extend receipt_lines with ATC code classification per withheld line
ALTER TABLE receipt_lines ADD COLUMN IF NOT EXISTS atc_code_id UUID REFERENCES ref_atc_codes(id);

-- ── Row-Level Security ────────────────────────────────────────────────────────
ALTER TABLE ref_atc_codes         ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_2307_tracking    ENABLE ROW LEVEL SECURITY;

-- ATC codes: public read-only reference data
CREATE POLICY "read_ref_atc_codes" ON ref_atc_codes
  FOR SELECT TO authenticated USING (true);

-- 2307 tracking: full access for authenticated (company scoping enforced in app)
CREATE POLICY "read_form_2307_tracking" ON form_2307_tracking
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "insert_form_2307_tracking" ON form_2307_tracking
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "update_form_2307_tracking" ON form_2307_tracking
  FOR UPDATE TO authenticated USING (true);

CREATE POLICY "delete_form_2307_tracking" ON form_2307_tracking
  FOR DELETE TO authenticated USING (status = 'pending');
