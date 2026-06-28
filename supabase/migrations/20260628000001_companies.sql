-- Reference table: BIR RDO Codes
CREATE TABLE ref_rdo_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rdo_code TEXT NOT NULL UNIQUE,
  rdo_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed RDO codes
INSERT INTO ref_rdo_codes (rdo_code, rdo_name) VALUES
('001','Laoag City'),('002','Vigan City'),('003','San Fernando, La Union'),
('004','Dagupan City'),('005','San Fernando, Pampanga'),('006','Cabanatuan City'),
('007','Palayan City'),('008','Baler, Aurora'),('009','Olongapo City'),
('010','Malolos, Bulacan'),('011','Caloocan City North'),('012','Caloocan City South'),
('013','Lipa City'),('014','Nasugbu, Batangas'),('015','Naga City'),
('016','Legazpi City'),('017','Puerto Princesa, Palawan'),('018','Romblon'),
('019','Boac, Marinduque'),('020','Calapan, Oriental Mindoro'),
('021','San Jose, Occidental Mindoro'),('022','Iloilo City'),('023','Kalibo, Aklan'),
('024','Roxas City'),('025','San Jose, Antique'),('026','Bacolod City'),
('027','Dumaguete City'),('028','Cebu City North'),('029','Cebu City South'),
('030','Mandaue City'),('031','Tagbilaran City'),('032','Tacloban City'),
('033','Catbalogan, Samar'),('034','Borongan, Eastern Samar'),
('035','Calbayog City'),('036','Zamboanga City'),('037','Pagadian City'),
('038','Dipolog City'),('039','Ozamiz City'),('040','Iligan City'),
('041','Cagayan de Oro City'),('042','Malaybalay, Bukidnon'),
('043','Butuan City'),('044','Surigao City'),('045','Tandag, Surigao del Sur'),
('046','Davao City'),('047','Digos City'),('048','Mati City'),
('049','Kidapawan City'),('050','General Santos City'),('051','Cotabato City'),
('052','Marawi City'),('053','Tacurong City'),
('054','Tuguegarao City'),('055','Bayombong, Nueva Vizcaya'),
('056','Ilagan, Isabela'),('057','Santiago City'),('058','Cauayan City'),
('059','Quezon City North'),('060','Quezon City South'),
('061','Pasay City'),('062','Makati City RDO 47'),('063','Makati City RDO 48'),
('064','Mandaluyong City'),('065','Marikina City'),('066','Pasig City'),
('067','Pateros/Taguig City'),('068','Parañaque City'),('069','Las Piñas City'),
('070','Muntinlupa City'),('071','Valenzuela City'),('072','Malabon/Navotas'),
('073','Manila I - Intramuros'),('074','Manila II - Sta. Cruz'),
('075','Manila III - Quiapo'),('076','Manila IV - Sampaloc'),
('077','Manila V - Paco'),('078','Manila VI - Tondo'),
('079','San Juan City'),('080','Mandaluyong City RDO 43'),
('081','Antipolo City'),('082','Biñan City'),('083','San Pedro, Laguna'),
('084','Sta. Rosa, Laguna'),('085','Calamba City'),('086','San Pablo City'),
('087','Lucena City'),('088','Gumaca, Quezon'),('089','Batangas City'),
('090','Trece Martires City'),('091','Bacoor City'),('092','Dasmariñas City'),
('093','Imus City'),('094','Tagaytay City'),('095','Tanauan City'),
('096','Balanga City, Bataan'),('097','Guagua, Pampanga'),
('098','Angeles City'),('099','Tarlac City'),('100','San Jose, Nueva Ecija');

-- Main companies table
CREATE TABLE companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_company_id UUID REFERENCES companies(id),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('sole_proprietor','opc','corporation','partnership','cooperative')),
  registered_name TEXT NOT NULL,
  trade_name TEXT,
  line_of_business TEXT NOT NULL,
  psic_code TEXT,
  tin TEXT NOT NULL UNIQUE,
  tax_registration TEXT NOT NULL CHECK (tax_registration IN ('vat','non_vat','exempt')),
  rdo_id UUID REFERENCES ref_rdo_codes(id),
  registration_number TEXT,
  bir_reg_date DATE,
  sec_dti_reg_date DATE,
  lgu_reg_date DATE,
  accounting_period TEXT NOT NULL CHECK (accounting_period IN ('calendar','fiscal')),
  fiscal_start_month INTEGER CHECK (fiscal_start_month BETWEEN 1 AND 12),
  cas_permit_no TEXT,
  cas_date_issued DATE,
  address_line_1 TEXT NOT NULL,
  address_line_2 TEXT NOT NULL,
  city TEXT NOT NULL,
  province TEXT NOT NULL,
  zip_code TEXT NOT NULL,
  email TEXT NOT NULL,
  phone_number TEXT,
  mobile_number TEXT,
  signatory_name TEXT NOT NULL,
  signatory_position TEXT NOT NULL,
  signatory_tin TEXT,
  logo_url TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_rdo_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_read_rdo" ON ref_rdo_codes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated_all_companies" ON companies
  FOR ALL TO authenticated USING (true);

-- Updated at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER companies_updated_at
  BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();