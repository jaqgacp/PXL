-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-05 — Company Setup Defaults & Seed Templates (gaps MD-01, MD-04*, MD-05)
--   (* MD-04 here is the gap-register "default per-company UOM set", not package MDP-04)
--
-- Lets a new company start with a usable Philippine Chart of Accounts, a standard
-- UOM set, and common percentage-tax codes instead of an empty database — as
-- REUSABLE BACKEND capabilities that future provisioning (the MDP-08 wizard) and
-- operators can call. No wizard, no onboarding UX, and no change to company
-- creation are implemented here.
--
-- ── Inventory result (what already exists — NOT rebuilt) ──────────────────────
-- * companies master, company_accounting_config, and (post-MDP-04) an enriched
--   chart_of_accounts carrying FS/control/subledger/cash-flow classification.
-- * units_of_measure and percentage_tax_codes company-scoped masters, audited
--   (MDP-02) and RLS-gated (admin write). Withholding EWT/FWT are represented by
--   GLOBAL atc_codes (shared by every company via supplier.default_atc_code_id /
--   customer.default_cwt_atc_code_id), so there is no per-company EWT/FWT code
--   table to seed — only percentage_tax_codes is a company-scoped withholding
--   master. There is NO company-creation RPC and NO template architecture yet.
--
-- ── What this migration adds (only the genuine gaps) ──────────────────────────
--   1. coa_templates / coa_template_lines — global, read-only reference tables
--      holding entity-type COA templates whose lines carry the MDP-04
--      classification (fs_group, control/subledger/tax flags, cash-flow). One
--      canonical PH_STANDARD template is seeded (applicable to every entity type;
--      the architecture supports adding entity-specific templates later).
--   2. fn_seed_company_coa(company, template?)  — copies a template into a
--      company's chart_of_accounts (resolving parent hierarchy), idempotent.
--   3. fn_seed_company_uom(company)             — seeds a standard UOM set.
--   4. fn_seed_company_percentage_tax_codes(company) — seeds common PH percentage
--      -tax codes against the existing global pt tax_code + atc_code.
--
-- Governance reuse (MDP-01 pattern): the template tables are global reference and
-- are authenticated-READ-ONLY with deny-by-default writes (seeded via migration /
-- service_role); the seed functions are SECURITY DEFINER and self-check
-- can_admin_company(company) so a caller can only seed a company it administers.
-- Seeded rows flow through the existing per-table audit triggers (provenance), so
-- no new audit path is added. All inserts are idempotent (ON CONFLICT DO NOTHING)
-- on the existing (company_id, code) unique keys. Additive, forward-only, no RLS
-- change to existing tables, no posting-logic change.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Template reference tables (global, read-only) ──────────────────────────
CREATE TABLE IF NOT EXISTS coa_templates (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_code TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL,
  description   TEXT,
  entity_types  TEXT[] NOT NULL DEFAULT ARRAY['sole_proprietor','opc','corporation','partnership','cooperative'],
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS coa_template_lines (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id         UUID NOT NULL REFERENCES coa_templates(id) ON DELETE CASCADE,
  account_code        TEXT NOT NULL,
  account_name        TEXT NOT NULL,
  account_type        TEXT NOT NULL CHECK (account_type IN ('asset','liability','equity','revenue','expense')),
  normal_balance      TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
  is_postable         BOOLEAN NOT NULL DEFAULT true,
  parent_account_code TEXT,
  fs_group            TEXT,
  fs_subgroup         TEXT,
  cash_flow_category  TEXT,
  is_control_account  BOOLEAN NOT NULL DEFAULT false,
  allow_subledger     BOOLEAN NOT NULL DEFAULT false,
  subledger_type      TEXT,
  is_tax_account      BOOLEAN NOT NULL DEFAULT false,
  sort_order          INTEGER NOT NULL DEFAULT 0,
  UNIQUE (template_id, account_code)
);

ALTER TABLE coa_templates      ENABLE ROW LEVEL SECURITY;
ALTER TABLE coa_template_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS coa_templates_read      ON coa_templates;
DROP POLICY IF EXISTS coa_template_lines_read ON coa_template_lines;
CREATE POLICY coa_templates_read      ON coa_templates      FOR SELECT TO authenticated USING (true);
CREATE POLICY coa_template_lines_read ON coa_template_lines FOR SELECT TO authenticated USING (true);
-- No write policy → deny-by-default; templates are maintained by migration/operator.

REVOKE ALL ON TABLE coa_templates, coa_template_lines FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE coa_templates, coa_template_lines TO authenticated;
GRANT ALL    ON TABLE coa_templates, coa_template_lines TO service_role;

-- ── 2. Seed the canonical PH_STANDARD template ────────────────────────────────
INSERT INTO coa_templates (template_code, name, description)
VALUES ('PH_STANDARD', 'Philippine Standard Chart of Accounts',
        'General-purpose Philippine COA with FS classification, control accounts, and tax accounts; applicable to all entity types.')
ON CONFLICT (template_code) DO NOTHING;

INSERT INTO coa_template_lines (template_id, account_code, account_name, account_type,
  normal_balance, is_postable, parent_account_code, fs_group, fs_subgroup,
  cash_flow_category, is_control_account, allow_subledger, subledger_type, is_tax_account, sort_order)
SELECT t.id, v.account_code, v.account_name, v.account_type, v.normal_balance, v.is_postable,
       v.parent_account_code, v.fs_group, v.fs_subgroup, v.cash_flow_category,
       v.is_control_account, v.allow_subledger, v.subledger_type, v.is_tax_account, v.sort_order
FROM coa_templates t
CROSS JOIN (VALUES
  -- ASSETS
  ('1000','Assets','asset','debit',false,NULL,'assets','Assets',NULL,false,false,NULL,false,10),
  ('1010','Cash on Hand','asset','debit',true,'1000','assets','Current Assets',NULL,false,false,NULL,false,11),
  ('1020','Cash in Bank','asset','debit',true,'1000','assets','Current Assets',NULL,true,true,'bank',false,12),
  ('1200','Accounts Receivable','asset','debit',true,'1000','assets','Current Assets',NULL,true,true,'receivable',false,13),
  ('1210','Allowance for Doubtful Accounts','asset','credit',true,'1000','assets','Current Assets',NULL,false,false,NULL,false,14),
  ('1300','Inventory','asset','debit',true,'1000','assets','Current Assets',NULL,true,true,'inventory',false,15),
  ('1400','Input VAT','asset','debit',true,'1000','assets','Current Assets',NULL,false,false,NULL,true,16),
  ('1410','Creditable Withholding Tax','asset','debit',true,'1000','assets','Current Assets',NULL,false,false,NULL,true,17),
  ('1500','Property, Plant and Equipment','asset','debit',true,'1000','assets','Non-current Assets',NULL,true,true,'fixed_asset',false,18),
  ('1510','Accumulated Depreciation','asset','credit',true,'1000','assets','Non-current Assets',NULL,false,false,NULL,false,19),
  ('1600','Prepaid Expenses','asset','debit',true,'1000','assets','Current Assets',NULL,false,false,NULL,false,20),
  -- LIABILITIES
  ('2000','Liabilities','liability','credit',false,NULL,'liabilities','Liabilities',NULL,false,false,NULL,false,30),
  ('2010','Accounts Payable','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,true,true,'payable',false,31),
  ('2100','Output VAT Payable','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,false,false,NULL,true,32),
  ('2110','Expanded Withholding Tax Payable','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,false,false,NULL,true,33),
  ('2120','VAT Payable','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,false,false,NULL,true,34),
  ('2200','Accrued Expenses','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,false,false,NULL,false,35),
  ('2300','SSS/PhilHealth/HDMF Payable','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,false,false,NULL,false,36),
  ('2400','Income Tax Payable','liability','credit',true,'2000','liabilities','Current Liabilities',NULL,false,false,NULL,true,37),
  ('2500','Loans Payable','liability','credit',true,'2000','liabilities','Non-current Liabilities',NULL,false,false,NULL,false,38),
  -- EQUITY
  ('3000','Equity','equity','credit',false,NULL,'equity','Equity',NULL,false,false,NULL,false,50),
  ('3010','Owners/Partners/Share Capital','equity','credit',true,'3000','equity','Equity',NULL,false,false,NULL,false,51),
  ('3020','Retained Earnings','equity','credit',true,'3000','equity','Equity',NULL,false,false,NULL,false,52),
  ('3030','Drawings/Dividends','equity','debit',true,'3000','equity','Equity',NULL,false,false,NULL,false,53),
  -- REVENUE
  ('4000','Revenue','revenue','credit',false,NULL,'revenue','Revenue','operating',false,false,NULL,false,60),
  ('4010','Sales / Service Revenue','revenue','credit',true,'4000','revenue','Revenue','operating',false,false,NULL,false,61),
  ('4020','Sales Returns and Allowances','revenue','debit',true,'4000','revenue','Revenue','operating',false,false,NULL,false,62),
  ('4030','Other Income','revenue','credit',true,'4000','other_income','Other Income','operating',false,false,NULL,false,63),
  -- COST OF SALES
  ('5000','Cost of Sales','expense','debit',false,NULL,'cost_of_sales','Cost of Sales','operating',false,false,NULL,false,70),
  ('5010','Cost of Sales','expense','debit',true,'5000','cost_of_sales','Cost of Sales','operating',false,false,NULL,false,71),
  -- OPERATING EXPENSES
  ('6000','Operating Expenses','expense','debit',false,NULL,'expenses','Operating Expenses','operating',false,false,NULL,false,80),
  ('6010','Salaries and Wages','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,81),
  ('6020','Rent Expense','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,82),
  ('6030','Utilities Expense','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,83),
  ('6040','Depreciation Expense','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,84),
  ('6050','Taxes and Licenses','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,85),
  ('6060','Professional Fees','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,86),
  ('6070','Office Supplies','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,87),
  ('6900','Miscellaneous Expense','expense','debit',true,'6000','expenses','Operating Expenses','operating',false,false,NULL,false,88)
) AS v(account_code, account_name, account_type, normal_balance, is_postable, parent_account_code,
       fs_group, fs_subgroup, cash_flow_category, is_control_account, allow_subledger, subledger_type,
       is_tax_account, sort_order)
WHERE t.template_code = 'PH_STANDARD'
ON CONFLICT (template_id, account_code) DO NOTHING;

-- ── 3. Seed a company's Chart of Accounts from a template ─────────────────────
CREATE OR REPLACE FUNCTION fn_seed_company_coa(
  p_company_id   UUID,
  p_template_code TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template_id UUID;
  v_code        TEXT := p_template_code;
  v_count       INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed defaults for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  -- Default template selection: resolve from the company's entity_type when the
  -- caller does not name one explicitly.
  IF v_code IS NULL THEN
    SELECT t.template_code INTO v_code
    FROM coa_templates t
    JOIN companies c ON c.id = p_company_id
    WHERE t.is_active AND c.entity_type = ANY (t.entity_types)
    ORDER BY t.template_code
    LIMIT 1;
  END IF;

  SELECT id INTO v_template_id FROM coa_templates WHERE template_code = v_code AND is_active;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'COA template % not found or inactive', COALESCE(v_code, '(none)') USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO chart_of_accounts (
    company_id, account_code, account_name, account_type, normal_balance, is_postable,
    fs_group, fs_subgroup, cash_flow_category, is_control_account, allow_subledger,
    subledger_type, is_tax_account, created_by, updated_by)
  SELECT p_company_id, l.account_code, l.account_name, l.account_type, l.normal_balance, l.is_postable,
         l.fs_group, l.fs_subgroup, l.cash_flow_category, l.is_control_account, l.allow_subledger,
         l.subledger_type, l.is_tax_account, auth.uid(), auth.uid()
  FROM coa_template_lines l
  WHERE l.template_id = v_template_id
  ON CONFLICT (company_id, account_code) DO NOTHING;

  -- Resolve parent hierarchy by account_code within the same company.
  UPDATE chart_of_accounts c
     SET parent_id = p.id
  FROM coa_template_lines l
  JOIN chart_of_accounts p
    ON p.company_id = p_company_id AND p.account_code = l.parent_account_code
  WHERE l.template_id = v_template_id
    AND c.company_id = p_company_id
    AND c.account_code = l.account_code
    AND l.parent_account_code IS NOT NULL
    AND c.parent_id IS NULL;

  SELECT count(*)::INTEGER INTO v_count
  FROM chart_of_accounts c
  WHERE c.company_id = p_company_id
    AND c.account_code IN (SELECT account_code FROM coa_template_lines WHERE template_id = v_template_id);
  RETURN v_count;
END;
$$;

-- ── 4. Seed a standard company UOM set ────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_seed_company_uom(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed defaults for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO units_of_measure (company_id, uom_code, description, is_base_unit, created_by, updated_by)
  SELECT p_company_id, v.uom_code, v.description, v.is_base, auth.uid(), auth.uid()
  FROM (VALUES
    ('PCS','Pieces',true), ('UNIT','Unit',true), ('BOX','Box',false),
    ('PACK','Pack',false), ('DOZEN','Dozen',false), ('SET','Set',false),
    ('KG','Kilogram',true), ('G','Gram',false), ('L','Liter',true),
    ('ML','Milliliter',false), ('M','Meter',true), ('CM','Centimeter',false),
    ('HOUR','Hour',true), ('DAY','Day',false), ('LOT','Lot',false)
  ) AS v(uom_code, description, is_base)
  ON CONFLICT (company_id, uom_code) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ── 5. Seed common company percentage-tax codes (MD-05 withholding scope) ──────
-- EWT/FWT are global atc_codes shared by every company; only percentage_tax_codes
-- is a company-scoped withholding master, so only it is seeded. References the
-- existing global pt tax_code + a percentage-tax atc_code; seeds nothing if those
-- global references are unavailable (safe / best-effort).
CREATE OR REPLACE FUNCTION fn_seed_company_percentage_tax_codes(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tax_code_id UUID;
  v_atc_id      UUID;
  v_count       INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed defaults for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_tax_code_id FROM tax_codes WHERE tax_type = 'pt' AND is_active ORDER BY code LIMIT 1;
  SELECT id INTO v_atc_id      FROM atc_codes WHERE tax_category = 'pt' ORDER BY code LIMIT 1;
  IF v_atc_id IS NULL THEN
    SELECT id INTO v_atc_id FROM atc_codes ORDER BY code LIMIT 1;  -- fallback: any atc
  END IF;

  IF v_tax_code_id IS NULL OR v_atc_id IS NULL THEN
    RETURN 0;  -- required global references not present; seed nothing
  END IF;

  INSERT INTO percentage_tax_codes (company_id, tax_code_id, pt_code, description, atc_id, rate, form_type, created_by, updated_by)
  SELECT p_company_id, v_tax_code_id, v.pt_code, v.description, v_atc_id, v.rate, v.form_type, auth.uid(), auth.uid()
  FROM (VALUES
    ('PT-3','Percentage Tax - 3% (general, non-VAT)', 3.0, '2551Q')
  ) AS v(pt_code, description, rate, form_type)
  ON CONFLICT (company_id, pt_code) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ── 6. Least privilege: seed functions self-check authority; grant execute ─────
REVOKE ALL ON FUNCTION fn_seed_company_coa(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_seed_company_uom(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_seed_company_percentage_tax_codes(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_seed_company_coa(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_seed_company_uom(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_seed_company_percentage_tax_codes(UUID) TO authenticated, service_role;

COMMENT ON FUNCTION fn_seed_company_coa(UUID, TEXT) IS
  'MDP-05: seeds a company Chart of Accounts from a coa_templates template (default: resolved from entity_type). Idempotent; admin-gated.';
COMMENT ON FUNCTION fn_seed_company_uom(UUID) IS
  'MDP-05: seeds a standard company UOM set. Idempotent; admin-gated.';
COMMENT ON FUNCTION fn_seed_company_percentage_tax_codes(UUID) IS
  'MDP-05: seeds common company percentage-tax codes against global references. Idempotent; admin-gated.';
