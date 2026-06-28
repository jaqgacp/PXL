-- ============================================================
-- Sprint 2: Master Data Tables (S2.1 – S2.5)
-- ============================================================

-- ── Tax Codes: Global master registry ────────────────────────
CREATE TABLE tax_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  tax_type TEXT NOT NULL CHECK (tax_type IN ('vat', 'ewt', 'fwt', 'pt')),
  rate NUMERIC(6,2) NOT NULL,
  gl_account_id UUID REFERENCES chart_of_accounts(id),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-seed standard Philippine VAT codes
INSERT INTO tax_codes (code, description, tax_type, rate) VALUES
  ('VAT12-OUT',  'Output VAT 12%',              'vat', 12.00),
  ('VAT12-IN',   'Input VAT 12%',               'vat', 12.00),
  ('VAT0-OUT',   'Zero-Rated Output VAT 0%',    'vat',  0.00),
  ('VAT0-IN',    'Zero-Rated Input VAT 0%',     'vat',  0.00),
  ('VATEX-OUT',  'VAT-Exempt Sales',            'vat',  0.00),
  ('VATEX-IN',   'VAT-Exempt Purchases',        'vat',  0.00),
  ('PT3-OUT',    'Percentage Tax 3% (Sales)',   'pt',   3.00),
  ('PT12-OUT',   'Percentage Tax 12% (Non-VAT Telecom)', 'pt', 12.00);

-- ── VAT Codes: PH-specific extension of tax_codes ────────────
CREATE TABLE vat_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tax_code_id UUID NOT NULL REFERENCES tax_codes(id),
  vat_code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  vat_classification TEXT NOT NULL CHECK (vat_classification IN ('regular','zero_rated','exempt')),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('input_vat','output_vat')),
  relief_category TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tax_code_id, transaction_type)
);

-- Pre-seed standard Philippine VAT codes
INSERT INTO vat_codes (tax_code_id, vat_code, description, vat_classification, transaction_type, relief_category)
SELECT id, 'VAT-12', 'Standard 12% Output VAT', 'regular', 'output_vat', 'G' FROM tax_codes WHERE code = 'VAT12-OUT'
UNION ALL
SELECT id, 'IVAT-12', 'Standard 12% Input VAT', 'regular', 'input_vat', 'G' FROM tax_codes WHERE code = 'VAT12-IN'
UNION ALL
SELECT id, 'VAT-0-EXPORT', 'Zero-Rated — Export Sales', 'zero_rated', 'output_vat', 'Z' FROM tax_codes WHERE code = 'VAT0-OUT'
UNION ALL
SELECT id, 'IVAT-0', 'Zero-Rated — Purchases', 'zero_rated', 'input_vat', 'Z' FROM tax_codes WHERE code = 'VAT0-IN'
UNION ALL
SELECT id, 'VAT-EXEMPT', 'VAT-Exempt Sales', 'exempt', 'output_vat', 'E' FROM tax_codes WHERE code = 'VATEX-OUT'
UNION ALL
SELECT id, 'IVAT-EXEMPT', 'VAT-Exempt Purchases', 'exempt', 'input_vat', 'E' FROM tax_codes WHERE code = 'VATEX-IN';

-- ── ATC Codes: Global BIR Alphanumeric Tax Codes ─────────────
CREATE TABLE atc_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  atc_code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  tax_type TEXT NOT NULL CHECK (tax_type IN ('ewt', 'fwt')),
  rate NUMERIC(5,2) NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO atc_codes (atc_code, description, tax_type, rate) VALUES
  ('WC158', 'Goods — Top Withholding Agent',                'ewt', 1.00),
  ('WC159', 'Services — Top Withholding Agent',             'ewt', 2.00),
  ('WI010', 'Professional Fees — Individual',               'ewt', 10.00),
  ('WC010', 'Professional Fees — Corporation',              'ewt', 10.00),
  ('WI011', 'Professional Fees — Individual (>₱720K)',      'ewt', 15.00),
  ('WC120', 'Rental — Personal Property',                   'ewt', 5.00),
  ('WC130', 'Rental — Real Property',                       'ewt', 2.00),
  ('WC140', 'Contractor & Sub-contractor Payments',         'ewt', 2.00),
  ('WC150', 'Income Payments to Healthcare',                'ewt', 1.00),
  ('WC160', 'Income Payments to Real Estate',               'ewt', 6.00),
  ('WC001', 'Dividends to Domestic Corp',                   'fwt', 15.00),
  ('WC002', 'Interest on Bank Deposits (FCDS)',             'fwt', 7.50),
  ('WC003', 'Interest on Bonds (Long-term)',                'fwt', 20.00);

-- ── EWT Codes: Per-company EWT configuration ─────────────────
CREATE TABLE ewt_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  tax_code_id UUID NOT NULL REFERENCES tax_codes(id),
  ewt_code TEXT NOT NULL,
  description TEXT NOT NULL,
  atc_id UUID NOT NULL REFERENCES atc_codes(id),
  rate NUMERIC(5,2) NOT NULL,
  form_type TEXT NOT NULL CHECK (form_type IN ('1601EQ','1601FQ','2550M')),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, ewt_code),
  UNIQUE(company_id, atc_id, rate)
);

-- ── S2.3: Payment Terms ───────────────────────────────────────
CREATE TABLE payment_terms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  term_code TEXT NOT NULL,
  term_name TEXT NOT NULL,
  days_to_due INTEGER NOT NULL DEFAULT 0,
  require_downpayment BOOLEAN NOT NULL DEFAULT false,
  dp_percentage NUMERIC(5,2),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, term_code)
);

-- ── S2.4: Item Categories ─────────────────────────────────────
CREATE TABLE item_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  category_code TEXT NOT NULL,
  category_name TEXT NOT NULL,
  parent_category_id UUID REFERENCES item_categories(id),
  description TEXT,
  sales_account_id UUID REFERENCES chart_of_accounts(id),
  cogs_account_id UUID REFERENCES chart_of_accounts(id),
  inventory_account_id UUID REFERENCES chart_of_accounts(id),
  adj_account_id UUID REFERENCES chart_of_accounts(id),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, category_code)
);

-- ── S2.4: Units of Measure ────────────────────────────────────
CREATE TABLE units_of_measure (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  uom_code TEXT NOT NULL,
  description TEXT NOT NULL,
  is_base_unit BOOLEAN NOT NULL DEFAULT false,
  base_uom_id UUID REFERENCES units_of_measure(id),
  conversion_factor NUMERIC(15,6),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, uom_code)
);

-- ── S2.1: Customers ───────────────────────────────────────────
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  customer_code TEXT NOT NULL,
  customer_group TEXT,
  registered_name TEXT NOT NULL,
  trade_name TEXT,
  business_style TEXT,
  tin TEXT NOT NULL,
  default_tax_type TEXT NOT NULL DEFAULT 'vat_registered'
    CHECK (default_tax_type IN ('vat_registered','non_vat','vat_exempt','zero_rated')),
  default_ewt_code_id UUID REFERENCES ewt_codes(id),
  registered_address TEXT NOT NULL,
  delivery_address TEXT NOT NULL,
  contact_person TEXT,
  email TEXT,
  phone_number TEXT,
  default_terms_id UUID REFERENCES payment_terms(id),
  default_currency_id UUID REFERENCES currencies(id),
  default_gl_account_id UUID REFERENCES chart_of_accounts(id),
  credit_limit NUMERIC(15,2) DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, customer_code)
);

-- ── S2.2: Suppliers ───────────────────────────────────────────
CREATE TABLE suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  supplier_code TEXT NOT NULL,
  supplier_group TEXT,
  registered_name TEXT NOT NULL,
  trade_name TEXT,
  business_style TEXT,
  tin TEXT NOT NULL,
  default_tax_type TEXT NOT NULL DEFAULT 'vat_registered'
    CHECK (default_tax_type IN ('vat_registered','non_vat','vat_exempt','zero_rated')),
  default_ewt_code_id UUID REFERENCES ewt_codes(id),
  registered_address TEXT NOT NULL,
  contact_person TEXT,
  email TEXT,
  phone_number TEXT,
  default_terms_id UUID REFERENCES payment_terms(id),
  default_currency_id UUID REFERENCES currencies(id),
  default_gl_account_id UUID REFERENCES chart_of_accounts(id),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, supplier_code)
);

-- ── S2.5: Items ───────────────────────────────────────────────
CREATE TABLE items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  item_code TEXT NOT NULL,
  description TEXT NOT NULL,
  description_long TEXT,
  item_type TEXT NOT NULL CHECK (item_type IN ('inventory_item','service','non_inventory')),
  category_id UUID NOT NULL REFERENCES item_categories(id),
  uom_id UUID NOT NULL REFERENCES units_of_measure(id),
  barcode TEXT,
  standard_selling_price NUMERIC(15,2) NOT NULL DEFAULT 0,
  standard_cost NUMERIC(15,2) NOT NULL DEFAULT 0,
  price_is_vat_inclusive BOOLEAN NOT NULL DEFAULT false,
  default_sales_vat_id UUID REFERENCES vat_codes(id),
  default_purchase_vat_id UUID REFERENCES vat_codes(id),
  default_ewt_code_id UUID REFERENCES ewt_codes(id),
  sales_account_id UUID REFERENCES chart_of_accounts(id),
  cogs_account_id UUID REFERENCES chart_of_accounts(id),
  inventory_account_id UUID REFERENCES chart_of_accounts(id),
  purchase_expense_account_id UUID REFERENCES chart_of_accounts(id),
  costing_method TEXT CHECK (costing_method IN ('fifo','weighted_average','specific_identification')),
  min_stock_level NUMERIC(15,4),
  reorder_point NUMERIC(15,4),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, item_code)
);

-- ── Indexes ───────────────────────────────────────────────────
CREATE INDEX idx_customers_company   ON customers (company_id, is_active);
CREATE INDEX idx_customers_tin       ON customers (tin);
CREATE INDEX idx_suppliers_company   ON suppliers (company_id, is_active);
CREATE INDEX idx_suppliers_tin       ON suppliers (tin);
CREATE INDEX idx_items_company       ON items (company_id, is_active);
CREATE INDEX idx_items_category      ON items (category_id);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE tax_codes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE vat_codes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE atc_codes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ewt_codes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_terms   ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE units_of_measure ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE items           ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_read_tax_codes"      ON tax_codes       FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read_vat_codes"      ON vat_codes       FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read_atc_codes"      ON atc_codes       FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_all_ewt_codes"       ON ewt_codes       FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_payment_terms"   ON payment_terms   FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_item_categories" ON item_categories FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_uom"             ON units_of_measure FOR ALL   TO authenticated USING (true);
CREATE POLICY "auth_all_customers"       ON customers       FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_suppliers"       ON suppliers       FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_items"           ON items           FOR ALL    TO authenticated USING (true);

-- ── updated_at triggers ───────────────────────────────────────
CREATE TRIGGER ewt_codes_updated_at       BEFORE UPDATE ON ewt_codes       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER payment_terms_updated_at   BEFORE UPDATE ON payment_terms   FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER item_categories_updated_at BEFORE UPDATE ON item_categories FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER uom_updated_at             BEFORE UPDATE ON units_of_measure FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER customers_updated_at       BEFORE UPDATE ON customers       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER suppliers_updated_at       BEFORE UPDATE ON suppliers       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER items_updated_at           BEFORE UPDATE ON items           FOR EACH ROW EXECUTE FUNCTION update_updated_at();
