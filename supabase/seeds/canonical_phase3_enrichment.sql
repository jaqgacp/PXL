-- =============================================================================
-- PXL Phase 3 canonical ERP enrichment
-- =============================================================================
-- Incremental and idempotent. This script preserves the existing canonical
-- companies and governed transaction history. Run only after the canonical
-- seed and migrations through 20260716000003.

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  false
);

DO $phase3_guard$
BEGIN
  IF (
    SELECT count(*)
    FROM companies
    WHERE trade_name IN (
      'DEMO-SP-NONVAT',
      'DEMO-CORP-VAT',
      'DEMO-OPC-NONVAT',
      'DEMO-SVC-VAT',
      'DEMO-PARTNERSHIP-VAT'
    )
  ) <> 5 THEN
    RAISE EXCEPTION 'Phase 3 enrichment requires all five canonical companies';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM atc_codes
    WHERE code = 'PT010'
      AND tax_category = 'pt'
      AND is_active
      AND deprecated_at IS NULL
  ) THEN
    RAISE EXCEPTION 'PT010 is missing; apply migration 20260716000003 first';
  END IF;
END
$phase3_guard$;

-- Complete the legal registration profile without changing company identity.
UPDATE companies AS company
SET rdo_id = rdo.id,
    registration_number = profile.registration_number,
    bir_reg_date = profile.bir_reg_date,
    sec_dti_reg_date = profile.sec_dti_reg_date,
    lgu_reg_date = profile.lgu_reg_date,
    psic_code = profile.psic_code,
    updated_by = auth.uid(),
    updated_at = now()
FROM (
  VALUES
    ('DEMO-SP-NONVAT', '049', 'DTI-2026-100001', DATE '2026-01-05', DATE '2025-12-15', DATE '2026-01-08', '47190'),
    ('DEMO-CORP-VAT', '044', 'CS2026-000102', DATE '2026-01-05', DATE '2025-11-20', DATE '2026-01-08', '46900'),
    ('DEMO-OPC-NONVAT', '043', 'OPC2026-000103', DATE '2026-01-05', DATE '2025-12-01', DATE '2026-01-08', '62020'),
    ('DEMO-SVC-VAT', '047', 'CS2026-000104', DATE '2026-01-05', DATE '2025-10-10', DATE '2026-01-08', '70209'),
    ('DEMO-PARTNERSHIP-VAT', '033', 'PG2026-000105', DATE '2026-01-05', DATE '2025-09-15', DATE '2026-01-08', '46900')
) AS profile(company_code, rdo_code, registration_number, bir_reg_date, sec_dti_reg_date, lgu_reg_date, psic_code)
JOIN ref_rdo_codes AS rdo ON rdo.rdo_code = profile.rdo_code
WHERE company.trade_name = profile.company_code;

-- Entity-specific equity labels retain the original account identifiers used by
-- opening journals while making reports understandable for each legal form.
UPDATE chart_of_accounts AS account
SET account_name = labels.account_name,
    updated_by = auth.uid(),
    updated_at = now()
FROM companies AS company
JOIN (
  VALUES
    ('DEMO-SP-NONVAT', '3000', 'Owner''s Capital'),
    ('DEMO-SP-NONVAT', '3300', 'Owner''s Drawings'),
    ('DEMO-CORP-VAT', '3000', 'Share Capital'),
    ('DEMO-CORP-VAT', '3300', 'Dividends Declared'),
    ('DEMO-OPC-NONVAT', '3000', 'Single Stockholder''s Equity'),
    ('DEMO-OPC-NONVAT', '3300', 'Dividends Declared'),
    ('DEMO-SVC-VAT', '3000', 'Share Capital'),
    ('DEMO-SVC-VAT', '3300', 'Dividends Declared'),
    ('DEMO-PARTNERSHIP-VAT', '3000', 'Partners'' Capital'),
    ('DEMO-PARTNERSHIP-VAT', '3100', 'Additional Partners'' Capital'),
    ('DEMO-PARTNERSHIP-VAT', '3300', 'Partners'' Drawings')
) AS labels(company_code, account_code, account_name)
  ON labels.company_code = company.trade_name
WHERE account.company_id = company.id
  AND account.account_code = labels.account_code;

INSERT INTO chart_of_accounts (
  company_id,
  account_code,
  account_name,
  account_type,
  normal_balance,
  is_postable,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  '2210',
  'Customer Advances',
  'liability',
  'credit',
  true,
  true,
  auth.uid(),
  auth.uid()
FROM companies AS company
WHERE company.trade_name LIKE 'DEMO-%'
ON CONFLICT (company_id, account_code) DO UPDATE
SET account_name = EXCLUDED.account_name,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now();

UPDATE company_accounting_config AS config
SET customer_advances_account_id = account.id,
    updated_by = auth.uid(),
    updated_at = now()
FROM chart_of_accounts AS account
WHERE account.company_id = config.company_id
  AND account.account_code = '2210'
  AND EXISTS (
    SELECT 1
    FROM companies
    WHERE id = config.company_id
      AND trade_name LIKE 'DEMO-%'
  );

-- Company-specific Section 116 setup. PT010 and PT3-OUT remain governed global
-- references; the rows below are company configuration recognized by the UI.
INSERT INTO percentage_tax_codes (
  company_id,
  tax_code_id,
  pt_code,
  description,
  atc_id,
  rate,
  form_type,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  tax_code.id,
  'PT-SEC116-3',
  'Section 116 percentage tax at 3%',
  atc.id,
  3.00,
  '2551Q',
  true,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN tax_codes AS tax_code ON tax_code.code = 'PT3-OUT'
JOIN atc_codes AS atc
  ON atc.code = 'PT010'
 AND atc.tax_category = 'pt'
 AND atc.is_active
 AND atc.deprecated_at IS NULL
WHERE company.trade_name IN ('DEMO-SP-NONVAT', 'DEMO-OPC-NONVAT')
ON CONFLICT (company_id, pt_code) DO UPDATE
SET tax_code_id = EXCLUDED.tax_code_id,
    description = EXCLUDED.description,
    atc_id = EXCLUDED.atc_id,
    rate = EXCLUDED.rate,
    form_type = EXCLUDED.form_type,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now();

-- Bayani is a mixed goods-and-services partnership and therefore needs one
-- operating warehouse. Service-only companies intentionally remain warehouse-free.
INSERT INTO warehouses (
  company_id,
  branch_id,
  warehouse_code,
  warehouse_name,
  warehouse_type,
  address,
  gl_inventory_account_id,
  gl_variance_account_id,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  branch.id,
  'WH-BAYANI',
  'Bayani Main Warehouse',
  'main',
  branch.address_line_1 || ', ' || branch.city,
  inventory_account.id,
  variance_account.id,
  true,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN branches AS branch
  ON branch.company_id = company.id
 AND branch.branch_code = 'HO'
JOIN chart_of_accounts AS inventory_account
  ON inventory_account.company_id = company.id
 AND inventory_account.account_code = '1200'
JOIN chart_of_accounts AS variance_account
  ON variance_account.company_id = company.id
 AND variance_account.account_code = '5020'
WHERE company.trade_name = 'DEMO-PARTNERSHIP-VAT'
ON CONFLICT (company_id, warehouse_code) DO UPDATE
SET warehouse_name = EXCLUDED.warehouse_name,
    branch_id = EXCLUDED.branch_id,
    gl_inventory_account_id = EXCLUDED.gl_inventory_account_id,
    gl_variance_account_id = EXCLUDED.gl_variance_account_id,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now();

-- Differentiated categories keep each company recognizable in lists and reports.
INSERT INTO item_categories (
  company_id,
  category_code,
  category_name,
  description,
  sales_account_id,
  cogs_account_id,
  inventory_account_id,
  adj_account_id,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  category.category_code,
  category.category_name,
  category.description,
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = category.sales_account_code),
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = category.cogs_account_code),
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = category.inventory_account_code),
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = '5020'),
  true,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN (
  VALUES
    ('DEMO-SP-NONVAT', 'GOLDEN-RETAIL', 'Golden Retail Goods', 'Everyday retail merchandise', '4000', '5000', '1200'),
    ('DEMO-CORP-VAT', 'ABC-WHOLESALE', 'ABC Wholesale Goods', 'Wholesale distribution inventory', '4000', '5000', '1200'),
    ('DEMO-OPC-NONVAT', 'NORTHSTAR-SVC', 'Northstar Digital Services', 'Retainer and milestone IT services', '4010', NULL, NULL),
    ('DEMO-SVC-VAT', 'PRIME-ADVISORY', 'Prime Advisory Services', 'Accounting, tax, and consulting engagements', '4010', NULL, NULL),
    ('DEMO-PARTNERSHIP-VAT', 'BAYANI-MIXED', 'Bayani Goods and Services', 'Mixed trading and professional services', '4000', '5000', '1200')
) AS category(company_code, category_code, category_name, description, sales_account_code, cogs_account_code, inventory_account_code)
  ON category.company_code = company.trade_name
ON CONFLICT (company_id, category_code) DO UPDATE
SET category_name = EXCLUDED.category_name,
    description = EXCLUDED.description,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now();

INSERT INTO items (
  company_id,
  item_code,
  description,
  description_long,
  item_type,
  category_id,
  uom_id,
  standard_selling_price,
  standard_cost,
  price_is_vat_inclusive,
  default_sales_vat_id,
  default_purchase_vat_id,
  sales_account_id,
  cogs_account_id,
  inventory_account_id,
  purchase_expense_account_id,
  costing_method,
  min_stock_level,
  reorder_point,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  item.item_code,
  item.description,
  item.description_long,
  item.item_type,
  category.id,
  uom.id,
  item.sell_price,
  item.standard_cost,
  item.price_inclusive,
  CASE
    WHEN company.tax_registration = 'vat' AND item.item_type <> 'non_inventory'
      THEN (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12')
    ELSE (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT')
  END,
  CASE
    WHEN company.tax_registration = 'vat' AND item.standard_cost > 0
      THEN (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12')
    ELSE (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT')
  END,
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = item.sales_account_code),
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = item.cogs_account_code),
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = item.inventory_account_code),
  (SELECT id FROM chart_of_accounts WHERE company_id = company.id AND account_code = item.expense_account_code),
  CASE WHEN item.item_type = 'inventory_item' THEN 'weighted_average' END,
  item.min_stock,
  item.reorder_point,
  item.is_active,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN (
  VALUES
    ('DEMO-SP-NONVAT', 'GRS-RICE-5KG', 'Premium Rice 5kg', 'Golden Retail fast-moving household staple', 'inventory_item', 'GOLDEN-RETAIL', 'PC', 360.00, 300.00, false, '4000', '5000', '1200', '5010', 15::numeric, 30::numeric, true),
    ('DEMO-SP-NONVAT', 'GRS-DELIVERY', 'Neighborhood Delivery Fee', 'Golden Retail local delivery service', 'service', 'GOLDEN-RETAIL', 'JOB', 150.00, 0.00, false, '4020', NULL, NULL, '6040', NULL, NULL, true),
    ('DEMO-SP-NONVAT', 'GRS-INACTIVE', 'Discontinued Retail Bundle', 'Inactive negative-test retail item', 'non_inventory', 'GOLDEN-RETAIL', 'PC', 0.00, 0.00, false, NULL, NULL, NULL, '6050', NULL, NULL, false),
    ('DEMO-CORP-VAT', 'ABC-BULK-PAPER', 'Wholesale Bond Paper Case', 'ABC wholesale case pack for branch distribution', 'inventory_item', 'ABC-WHOLESALE', 'CASE', 2750.00, 2100.00, false, '4000', '5000', '1200', '5010', 8, 16, true),
    ('DEMO-CORP-VAT', 'ABC-INACTIVE', 'Legacy Printer Bundle', 'Inactive negative-test wholesale item', 'non_inventory', 'ABC-WHOLESALE', 'UNIT', 0.00, 0.00, false, NULL, NULL, NULL, '6050', NULL, NULL, false),
    ('DEMO-OPC-NONVAT', 'NS-RETAINER', 'Managed IT Retainer', 'Northstar monthly managed service retainer', 'service', 'NORTHSTAR-SVC', 'JOB', 18000.00, 0.00, false, '4010', NULL, NULL, '6030', NULL, NULL, true),
    ('DEMO-OPC-NONVAT', 'NS-MILESTONE', 'Application Delivery Milestone', 'Northstar project milestone billing unit', 'service', 'NORTHSTAR-SVC', 'JOB', 45000.00, 0.00, false, '4010', NULL, NULL, '6030', NULL, NULL, true),
    ('DEMO-OPC-NONVAT', 'NS-INACTIVE', 'Legacy Hosting Plan', 'Inactive negative-test service plan', 'service', 'NORTHSTAR-SVC', 'JOB', 0.00, 0.00, false, '4010', NULL, NULL, '6030', NULL, NULL, false),
    ('DEMO-SVC-VAT', 'PBA-TAX-ADVISORY', 'Quarterly Tax Advisory', 'Prime quarterly tax compliance engagement', 'service', 'PRIME-ADVISORY', 'JOB', 28000.00, 0.00, false, '4010', NULL, NULL, '6030', NULL, NULL, true),
    ('DEMO-SVC-VAT', 'PBA-RETAINER', 'Monthly Advisory Retainer', 'Prime recurring advisory retainer', 'service', 'PRIME-ADVISORY', 'JOB', 22400.00, 0.00, true, '4010', NULL, NULL, '6030', NULL, NULL, true),
    ('DEMO-SVC-VAT', 'PBA-INACTIVE', 'Legacy Compliance Package', 'Inactive negative-test advisory service', 'service', 'PRIME-ADVISORY', 'JOB', 0.00, 0.00, false, '4010', NULL, NULL, '6030', NULL, NULL, false),
    ('DEMO-PARTNERSHIP-VAT', 'BPC-PAPER-CASE', 'Bayani Bond Paper Case', 'Bayani trading inventory case', 'inventory_item', 'BAYANI-MIXED', 'CASE', 2800.00, 2100.00, false, '4000', '5000', '1200', '5010', 5, 10, true),
    ('DEMO-PARTNERSHIP-VAT', 'BPC-ADVISORY', 'Business Advisory Engagement', 'Bayani professional advisory engagement', 'service', 'BAYANI-MIXED', 'JOB', 15000.00, 0.00, false, '4010', NULL, NULL, '6030', NULL, NULL, true),
    ('DEMO-PARTNERSHIP-VAT', 'BPC-INACTIVE', 'Discontinued Partner Package', 'Inactive negative-test mixed-business item', 'non_inventory', 'BAYANI-MIXED', 'UNIT', 0.00, 0.00, false, NULL, NULL, NULL, '6050', NULL, NULL, false)
) AS item(
  company_code, item_code, description, description_long, item_type,
  category_code, uom_code, sell_price, standard_cost, price_inclusive,
  sales_account_code, cogs_account_code, inventory_account_code,
  expense_account_code, min_stock, reorder_point, is_active
)
  ON item.company_code = company.trade_name
JOIN item_categories AS category
  ON category.company_id = company.id
 AND category.category_code = item.category_code
JOIN units_of_measure AS uom
  ON uom.company_id = company.id
 AND uom.uom_code = item.uom_code
ON CONFLICT (company_id, item_code) DO UPDATE
SET description = EXCLUDED.description,
    description_long = EXCLUDED.description_long,
    standard_selling_price = EXCLUDED.standard_selling_price,
    standard_cost = EXCLUDED.standard_cost,
    price_is_vat_inclusive = EXCLUDED.price_is_vat_inclusive,
    default_sales_vat_id = EXCLUDED.default_sales_vat_id,
    default_purchase_vat_id = EXCLUDED.default_purchase_vat_id,
    sales_account_id = EXCLUDED.sales_account_id,
    cogs_account_id = EXCLUDED.cogs_account_id,
    inventory_account_id = EXCLUDED.inventory_account_id,
    purchase_expense_account_id = EXCLUDED.purchase_expense_account_id,
    min_stock_level = EXCLUDED.min_stock_level,
    reorder_point = EXCLUDED.reorder_point,
    is_active = EXCLUDED.is_active,
    updated_by = auth.uid(),
    updated_at = now();

INSERT INTO customers (
  company_id,
  customer_code,
  customer_group,
  registered_name,
  trade_name,
  business_style,
  tin,
  tin_branch_code,
  default_tax_type,
  registered_address,
  delivery_address,
  contact_person,
  email,
  phone_number,
  default_terms_id,
  default_currency_id,
  default_gl_account_id,
  credit_limit,
  is_subject_to_cwt,
  default_cwt_atc_code_id,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  customer.customer_code,
  customer.customer_group,
  customer.registered_name,
  customer.trade_name,
  customer.business_style,
  customer.tin,
  '00000',
  customer.default_tax_type,
  customer.address,
  customer.address,
  customer.contact_person,
  customer.email,
  customer.phone,
  terms.id,
  currency.id,
  ar_account.id,
  customer.credit_limit,
  customer.is_cwt,
  CASE WHEN customer.atc_code IS NULL THEN NULL ELSE (
    SELECT id FROM atc_codes
    WHERE code = customer.atc_code
      AND tax_category = 'ewt'
      AND is_active
      AND deprecated_at IS NULL
    ORDER BY effective_from DESC
    LIMIT 1
  ) END,
  customer.is_active,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN (
  VALUES
    ('DEMO-SP-NONVAT', 'CUST-GOLDEN-CREDIT', 'retail', 'Poblacion Mini Mart', 'Poblacion Mart', 'Short-term credit retailer', '901-201-002-00000', 'non_vat', 'Makati City', 'Paula Mendoza', 'ap@poblacionmart.pxl.local', '0282020002', 'NET15', 25000::numeric, false, NULL, true),
    ('DEMO-SP-NONVAT', 'CUST-GOLDEN-DELIVERY', 'household', 'Golden Neighborhood Account', 'Neighborhood Account', 'Local delivery customer', '901-201-003-00000', 'non_vat', 'Makati City', 'Nina Flores', 'nina.flores@pxl.local', '0282020003', 'NET7', 10000, false, NULL, true),
    ('DEMO-SP-NONVAT', 'CUST-GOLDEN-INACTIVE', 'inactive', 'Closed Corner Store', 'Closed Corner', 'Inactive negative-test customer', '901-201-004-00000', 'non_vat', 'Makati City', 'Inactive Contact', 'inactive.golden@pxl.local', '0282020004', 'COD', 0, false, NULL, false),
    ('DEMO-OPC-NONVAT', 'CUST-NORTHSTAR-MILESTONE', 'project', 'Harborline Logistics OPC', 'Harborline', 'Application project client', '901-203-002-00000', 'vat_registered', 'Paranaque City', 'Henry Chua', 'ap@harborline.pxl.local', '0282030002', 'NET30', 250000, false, NULL, true),
    ('DEMO-OPC-NONVAT', 'CUST-NORTHSTAR-SUPPORT', 'services', 'Cedar Health Services Inc.', 'Cedar Health', 'Managed support client', '901-203-003-00000', 'vat_registered', 'Quezon City', 'Celine Ramos', 'finance@cedarhealth.pxl.local', '0282030003', 'NET15', 120000, false, NULL, true),
    ('DEMO-OPC-NONVAT', 'CUST-NORTHSTAR-INACTIVE', 'inactive', 'Dormant Startup Labs OPC', 'Dormant Labs', 'Inactive negative-test client', '901-203-004-00000', 'non_vat', 'Pasig City', 'Inactive Contact', 'inactive.northstar@pxl.local', '0282030004', 'NET30', 0, false, NULL, false),
    ('DEMO-SVC-VAT', 'CUST-PRIME-SME', 'corporate', 'Sunrise Foods Manufacturing Inc.', 'Sunrise Foods', 'VAT advisory client', '901-204-002-00000', 'vat_registered', 'Laguna', 'Sofia Tan', 'finance@sunrisefoods.pxl.local', '0282040002', 'NET30', 300000, false, NULL, true),
    ('DEMO-SVC-VAT', 'CUST-PRIME-RETAINER', 'retainer', 'Apex Property Holdings Inc.', 'Apex Property', 'Monthly withholding retainer client', '901-204-003-00000', 'vat_registered', 'Makati City', 'Alvin Go', 'ap@apexproperty.pxl.local', '0282040003', 'NET30', 400000, true, 'WC159', true),
    ('DEMO-SVC-VAT', 'CUST-PRIME-INACTIVE', 'inactive', 'Former Advisory Client Inc.', 'Former Client', 'Inactive negative-test client', '901-204-004-00000', 'vat_registered', 'Makati City', 'Inactive Contact', 'inactive.prime@pxl.local', '0282040004', 'NET30', 0, false, NULL, false),
    ('DEMO-PARTNERSHIP-VAT', 'CUST-BAYANI-TRADE', 'trading', 'Lakbay Office Network Inc.', 'Lakbay Office', 'VAT trading customer', '901-205-001-00000', 'vat_registered', 'Manila', 'Lara Gomez', 'ap@lakbayoffice.pxl.local', '0282050001', 'NET30', 150000, false, NULL, true),
    ('DEMO-PARTNERSHIP-VAT', 'CUST-BAYANI-SERVICE', 'services', 'Makabayan Development Foundation', 'Makabayan Foundation', 'Withholding advisory client', '901-205-002-00000', 'vat_registered', 'Manila', 'Mario Reyes', 'finance@makabayan.pxl.local', '0282050002', 'NET30', 200000, true, 'WC159', true),
    ('DEMO-PARTNERSHIP-VAT', 'CUST-BAYANI-CASH', 'cash', 'Bayani Walk-in Customer', 'Bayani Walk-in', 'Cash customer', '901-205-003-00000', 'non_vat', 'Manila', 'Cashier', 'cash.bayani@pxl.local', '0282050003', 'COD', 0, false, NULL, true),
    ('DEMO-PARTNERSHIP-VAT', 'CUST-BAYANI-INACTIVE', 'inactive', 'Old Port Retailer Inc.', 'Old Port Retailer', 'Inactive negative-test customer', '901-205-004-00000', 'vat_registered', 'Manila', 'Inactive Contact', 'inactive.bayani@pxl.local', '0282050004', 'NET30', 0, false, NULL, false)
) AS customer(
  company_code, customer_code, customer_group, registered_name, trade_name,
  business_style, tin, default_tax_type, address, contact_person, email, phone,
  term_code, credit_limit, is_cwt, atc_code, is_active
)
  ON customer.company_code = company.trade_name
JOIN payment_terms AS terms
  ON terms.company_id = company.id
 AND terms.term_code = customer.term_code
JOIN currencies AS currency ON currency.currency_code = 'PHP'
JOIN chart_of_accounts AS ar_account
  ON ar_account.company_id = company.id
 AND ar_account.account_code = '1100'
ON CONFLICT (company_id, customer_code) DO UPDATE
SET registered_name = EXCLUDED.registered_name,
    trade_name = EXCLUDED.trade_name,
    business_style = EXCLUDED.business_style,
    tin = EXCLUDED.tin,
    default_tax_type = EXCLUDED.default_tax_type,
    default_terms_id = EXCLUDED.default_terms_id,
    credit_limit = EXCLUDED.credit_limit,
    is_subject_to_cwt = EXCLUDED.is_subject_to_cwt,
    default_cwt_atc_code_id = EXCLUDED.default_cwt_atc_code_id,
    is_active = EXCLUDED.is_active,
    updated_by = auth.uid(),
    updated_at = now();

INSERT INTO suppliers (
  company_id,
  supplier_code,
  supplier_group,
  registered_name,
  trade_name,
  business_style,
  tin,
  default_tax_type,
  registered_address,
  contact_person,
  email,
  phone_number,
  default_terms_id,
  default_currency_id,
  default_gl_account_id,
  is_subject_to_ewt,
  default_atc_code_id,
  is_active,
  created_by,
  updated_by
)
SELECT
  company.id,
  supplier.supplier_code,
  supplier.supplier_group,
  supplier.registered_name,
  supplier.trade_name,
  supplier.business_style,
  supplier.tin,
  supplier.default_tax_type,
  supplier.address,
  supplier.contact_person,
  supplier.email,
  supplier.phone,
  terms.id,
  currency.id,
  expense_account.id,
  supplier.is_ewt,
  CASE WHEN supplier.atc_code IS NULL THEN NULL ELSE (
    SELECT id FROM atc_codes
    WHERE code = supplier.atc_code
      AND tax_category = 'ewt'
      AND is_active
      AND deprecated_at IS NULL
    ORDER BY effective_from DESC
    LIMIT 1
  ) END,
  supplier.is_active,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN (
  VALUES
    ('DEMO-SP-NONVAT', 'SUP-GOLDEN-UTILITY', 'utilities', 'Golden Electric Cooperative', 'Golden Electric', 'Utility supplier', '902-301-002-00000', 'non_vat', 'Makati City', 'Utility Billing', 'billing@goldenelectric.pxl.local', '0283020002', 'NET15', '6020', false, NULL, true),
    ('DEMO-SP-NONVAT', 'SUP-GOLDEN-PACK', 'goods', 'Makati Packaging House', 'Makati Packaging', 'Packaging supplier', '902-301-003-00000', 'non_vat', 'Makati City', 'Paolo Garcia', 'orders@makatipack.pxl.local', '0283020003', 'NET15', '5010', false, NULL, true),
    ('DEMO-SP-NONVAT', 'SUP-GOLDEN-INACTIVE', 'inactive', 'Closed Wholesale Depot', 'Closed Depot', 'Inactive negative-test supplier', '902-301-004-00000', 'non_vat', 'Pasay City', 'Inactive Contact', 'inactive.golden.supplier@pxl.local', '0283020004', 'COD', '5010', false, NULL, false),
    ('DEMO-OPC-NONVAT', 'SUP-NORTHSTAR-CLOUD', 'services', 'Cloud Platform Philippines Inc.', 'Cloud Platform PH', 'Cloud infrastructure supplier', '902-303-002-00000', 'vat_registered', 'Taguig City', 'Carlo Lim', 'billing@cloudplatform.pxl.local', '0283030002', 'NET30', '6030', true, 'WC159', true),
    ('DEMO-OPC-NONVAT', 'SUP-NORTHSTAR-OFFICE', 'services', 'Ortigas Shared Offices Inc.', 'Ortigas Shared Offices', 'Office service supplier', '902-303-003-00000', 'vat_registered', 'Pasig City', 'Olivia Tan', 'billing@ortigasshared.pxl.local', '0283030003', 'NET30', '6010', true, 'WC130', true),
    ('DEMO-OPC-NONVAT', 'SUP-NORTHSTAR-INACTIVE', 'inactive', 'Legacy Hosting Vendor', 'Legacy Hosting', 'Inactive negative-test supplier', '902-303-004-00000', 'non_vat', 'Pasig City', 'Inactive Contact', 'inactive.northstar.supplier@pxl.local', '0283030004', 'NET15', '6030', false, NULL, false),
    ('DEMO-SVC-VAT', 'SUP-PRIME-PROF', 'professional', 'Cruz Legal and Professional Services', 'Cruz Professional', 'Professional fee supplier', '902-304-002-00000', 'vat_registered', 'Makati City', 'Carmen Cruz', 'billing@cruzprofessional.pxl.local', '0283040002', 'NET15', '6030', true, 'WC010', true),
    ('DEMO-SVC-VAT', 'SUP-PRIME-IT', 'services', 'Prime Systems Support Inc.', 'Prime Systems', 'IT support supplier', '902-304-003-00000', 'vat_registered', 'Taguig City', 'Ian Sy', 'billing@primesystems.pxl.local', '0283040003', 'NET15', '6030', true, 'WC159', true),
    ('DEMO-SVC-VAT', 'SUP-PRIME-INACTIVE', 'inactive', 'Former Office Vendor Inc.', 'Former Vendor', 'Inactive negative-test supplier', '902-304-004-00000', 'vat_registered', 'Makati City', 'Inactive Contact', 'inactive.prime.supplier@pxl.local', '0283040004', 'NET30', '6010', false, NULL, false),
    ('DEMO-PARTNERSHIP-VAT', 'SUP-BAYANI-GOODS', 'goods', 'Manila Paper and Office Supply Inc.', 'Manila Paper Supply', 'VAT inventory supplier', '902-305-001-00000', 'vat_registered', 'Manila', 'Miguel Santos', 'sales@manilapaper.pxl.local', '0283050001', 'NET30', '5010', true, 'WC158', true),
    ('DEMO-PARTNERSHIP-VAT', 'SUP-BAYANI-PROF', 'professional', 'Reyes Independent Consultant', 'Reyes Consultant', 'Professional service supplier', '902-305-002-00000', 'non_vat', 'Manila', 'Ramon Reyes', 'ramon@reyesconsultant.pxl.local', '0283050002', 'NET15', '6030', true, 'WI010', true),
    ('DEMO-PARTNERSHIP-VAT', 'SUP-BAYANI-UTILITY', 'utilities', 'Manila Demo Utility', 'Manila Utility', 'Utility supplier', '902-305-003-00000', 'vat_registered', 'Manila', 'Utility Billing', 'billing@manilautility.pxl.local', '0283050003', 'NET15', '6020', false, NULL, true),
    ('DEMO-PARTNERSHIP-VAT', 'SUP-BAYANI-INACTIVE', 'inactive', 'Old Harbor Supplier Inc.', 'Old Harbor', 'Inactive negative-test supplier', '902-305-004-00000', 'vat_registered', 'Manila', 'Inactive Contact', 'inactive.bayani.supplier@pxl.local', '0283050004', 'NET30', '5010', false, NULL, false)
) AS supplier(
  company_code, supplier_code, supplier_group, registered_name, trade_name,
  business_style, tin, default_tax_type, address, contact_person, email, phone,
  term_code, default_account_code, is_ewt, atc_code, is_active
)
  ON supplier.company_code = company.trade_name
JOIN payment_terms AS terms
  ON terms.company_id = company.id
 AND terms.term_code = supplier.term_code
JOIN currencies AS currency ON currency.currency_code = 'PHP'
JOIN chart_of_accounts AS expense_account
  ON expense_account.company_id = company.id
 AND expense_account.account_code = supplier.default_account_code
ON CONFLICT (company_id, supplier_code) DO UPDATE
SET registered_name = EXCLUDED.registered_name,
    trade_name = EXCLUDED.trade_name,
    business_style = EXCLUDED.business_style,
    tin = EXCLUDED.tin,
    default_tax_type = EXCLUDED.default_tax_type,
    default_terms_id = EXCLUDED.default_terms_id,
    default_gl_account_id = EXCLUDED.default_gl_account_id,
    is_subject_to_ewt = EXCLUDED.is_subject_to_ewt,
    default_atc_code_id = EXCLUDED.default_atc_code_id,
    is_active = EXCLUDED.is_active,
    updated_by = auth.uid(),
    updated_at = now();

INSERT INTO employees (
  company_id,
  branch_id,
  employee_number,
  last_name,
  first_name,
  department_id,
  job_title,
  employment_type,
  hire_date,
  email,
  is_active,
  notes,
  created_by,
  updated_by
)
SELECT
  company.id,
  branch.id,
  employee.employee_number,
  employee.last_name,
  employee.first_name,
  department.id,
  employee.job_title,
  employee.employment_type,
  employee.hire_date,
  employee.email,
  employee.is_active,
  employee.notes,
  auth.uid(),
  auth.uid()
FROM companies AS company
JOIN branches AS branch
  ON branch.company_id = company.id
 AND branch.branch_code = 'HO'
JOIN (
  VALUES
    ('DEMO-SP-NONVAT', 'GRS-MGR', 'Santos', 'Gloria', 'OPERATIONS', 'Owner and Store Manager', 'regular', DATE '2025-09-01', 'gloria.santos@golden.pxl.local', true, 'Owner and retail account owner'),
    ('DEMO-SP-NONVAT', 'GRS-CASHIER', 'Lopez', 'Mina', 'SALES', 'Cashier and Collections Clerk', 'regular', DATE '2026-01-02', 'mina.lopez@golden.pxl.local', true, 'Cash sales and collections'),
    ('DEMO-CORP-VAT', 'ABC-SALES-MGR', 'Reyes', 'Lara', 'SALES', 'Sales Manager', 'regular', DATE '2025-08-01', 'lara.reyes@abc.pxl.local', true, 'Wholesale sales account owner'),
    ('DEMO-CORP-VAT', 'ABC-BUYER', 'Uy', 'Cesar', 'PURCH', 'Purchasing Officer', 'regular', DATE '2025-08-15', 'cesar.uy@abc.pxl.local', true, 'Purchasing owner'),
    ('DEMO-OPC-NONVAT', 'NS-OWNER', 'Cruz', 'Noel', 'OPERATIONS', 'President and Engagement Owner', 'regular', DATE '2025-10-01', 'noel.cruz@northstar.pxl.local', true, 'OPC engagement owner'),
    ('DEMO-OPC-NONVAT', 'NS-PM', 'Lim', 'Stella', 'SALES', 'Project Manager', 'regular', DATE '2026-01-02', 'stella.lim@northstar.pxl.local', true, 'Milestone billing owner'),
    ('DEMO-SVC-VAT', 'PBA-DIRECTOR', 'Lim', 'Patricia', 'OPERATIONS', 'Managing Director', 'regular', DATE '2025-07-01', 'patricia.lim@prime.pxl.local', true, 'Engagement owner'),
    ('DEMO-SVC-VAT', 'PBA-MANAGER', 'Yap', 'Eddie', 'SALES', 'Accounting Manager', 'regular', DATE '2025-09-01', 'eddie.yap@prime.pxl.local', true, 'Billing and collection owner'),
    ('DEMO-PARTNERSHIP-VAT', 'BPC-PARTNER', 'Reyes', 'Benjamin', 'OPERATIONS', 'Managing Partner', 'regular', DATE '2025-06-01', 'benjamin.reyes@bayani.pxl.local', true, 'Partner and engagement owner'),
    ('DEMO-PARTNERSHIP-VAT', 'BPC-WH', 'Gomez', 'Lara', 'SALES', 'Warehouse and Sales Coordinator', 'regular', DATE '2026-01-02', 'lara.gomez@bayani.pxl.local', true, 'Mixed trading coordinator')
) AS employee(
  company_code, employee_number, last_name, first_name, department_code,
  job_title, employment_type, hire_date, email, is_active, notes
)
  ON employee.company_code = company.trade_name
JOIN departments AS department
  ON department.company_id = company.id
 AND department.department_code = employee.department_code
ON CONFLICT (company_id, employee_number) DO UPDATE
SET last_name = EXCLUDED.last_name,
    first_name = EXCLUDED.first_name,
    department_id = EXCLUDED.department_id,
    job_title = EXCLUDED.job_title,
    email = EXCLUDED.email,
    is_active = EXCLUDED.is_active,
    notes = EXCLUDED.notes,
    updated_by = auth.uid(),
    updated_at = now();

-- Warehouse replenishment controls are setup data, not generated balances.
INSERT INTO warehouse_item_settings (
  company_id,
  warehouse_id,
  item_id,
  min_stock_level,
  max_stock_level,
  reorder_point,
  reorder_qty,
  lead_time_days,
  preferred_supplier_id,
  notes,
  created_by,
  updated_by
)
SELECT
  warehouse.company_id,
  warehouse.id,
  item.id,
  COALESCE(item.min_stock_level, 5),
  GREATEST(COALESCE(item.reorder_point, 10) * 3, COALESCE(item.min_stock_level, 5) + 10),
  COALESCE(item.reorder_point, 10),
  GREATEST(COALESCE(item.reorder_point, 10) * 2, 10),
  7,
  (
    SELECT supplier.id
    FROM suppliers AS supplier
    WHERE supplier.company_id = warehouse.company_id
      AND supplier.is_active
      AND supplier.supplier_group = 'goods'
    ORDER BY supplier.supplier_code
    LIMIT 1
  ),
  'Phase 3 canonical replenishment policy',
  auth.uid(),
  auth.uid()
FROM warehouses AS warehouse
JOIN companies AS company ON company.id = warehouse.company_id
JOIN items AS item
  ON item.company_id = warehouse.company_id
 AND item.item_type = 'inventory_item'
 AND item.is_active
WHERE company.trade_name IN ('DEMO-SP-NONVAT', 'DEMO-CORP-VAT', 'DEMO-PARTNERSHIP-VAT')
ON CONFLICT (warehouse_id, item_id) DO UPDATE
SET min_stock_level = EXCLUDED.min_stock_level,
    max_stock_level = EXCLUDED.max_stock_level,
    reorder_point = EXCLUDED.reorder_point,
    reorder_qty = EXCLUDED.reorder_qty,
    lead_time_days = EXCLUDED.lead_time_days,
    preferred_supplier_id = EXCLUDED.preferred_supplier_id,
    notes = EXCLUDED.notes,
    updated_by = auth.uid(),
    updated_at = now();

-- Golden Retail Store: establish several months of non-VAT retail activity.
DO $golden_phase3$
DECLARE
  v_company UUID;
  v_branch UUID;
  v_branch_east UUID;
  v_wh_main UUID;
  v_wh_east UUID;
  v_item UUID;
  v_customer UUID;
  v_supplier UUID;
  v_vat_exempt UUID;
  v_ivat_exempt UUID;
  v_bank_mode UUID;
  v_inventory_value NUMERIC;
  v_si UUID;
  v_or UUID;
  v_po UUID;
  v_po_line UUID;
  v_rr UUID;
  v_vb UUID;
  v_pv UUID;
  v_stock NUMERIC;
BEGIN
  SELECT id INTO STRICT v_company FROM companies WHERE trade_name = 'DEMO-SP-NONVAT';
  SELECT id INTO STRICT v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT id INTO STRICT v_branch_east FROM branches WHERE company_id = v_company AND branch_code = 'BR01';
  SELECT id INTO STRICT v_wh_main FROM warehouses WHERE company_id = v_company AND warehouse_code = 'WH-GOLDEN-HO';
  SELECT id INTO STRICT v_wh_east FROM warehouses WHERE company_id = v_company AND warehouse_code = 'WH-GOLDEN-EAST';
  SELECT id INTO STRICT v_item FROM items WHERE company_id = v_company AND item_code = 'GRS-RICE-5KG';
  SELECT id INTO STRICT v_customer FROM customers WHERE company_id = v_company AND customer_code = 'CUST-GOLDEN-CREDIT';
  SELECT id INTO STRICT v_supplier FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-GOLDEN-GOODS';
  SELECT id INTO STRICT v_vat_exempt FROM vat_codes WHERE vat_code = 'VAT-EXEMPT';
  SELECT id INTO STRICT v_ivat_exempt FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT';
  SELECT id INTO STRICT v_bank_mode FROM ref_payment_modes WHERE code = 'BANK_XFER';

  IF NOT EXISTS (
    SELECT 1 FROM inventory_transactions
    WHERE company_id = v_company
      AND reference_doc_type = 'P3_OPENING'
      AND item_id = v_item
  ) THEN
    PERFORM fn_receive_inventory(jsonb_build_object(
      'company_id', v_company,
      'warehouse_id', v_wh_main,
      'item_id', v_item,
      'qty', 40,
      'unit_cost', 300,
      'receipt_date', '2026-01-02',
      'reference_doc_type', 'P3_OPENING',
      'notes', 'P3-GRS-OPENING-RICE'
    ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company
      AND description = 'P3-GRS-OPENING-BALANCES'
  ) THEN
    SELECT COALESCE(SUM(total_cost), 0)
    INTO v_inventory_value
    FROM stock_balances
    WHERE company_id = v_company;

    PERFORM fn_post_manual_je(
      v_company,
      v_branch,
      DATE '2026-01-02',
      'P3-GRS-OPENING-BALANCES',
      'MANUAL',
      false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1010'), 'description', 'Opening cash', 'debit_amount', 25000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'), 'description', 'Opening bank', 'debit_amount', 100000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'), 'description', 'Opening retail inventory', 'debit_amount', v_inventory_value, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '3000'), 'description', 'Owner capital', 'debit_amount', 0, 'credit_amount', 125000 + v_inventory_value, 'branch_id', v_branch)
      ),
      'opening'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-GRS-SI-CREDIT'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'warehouse_id', v_wh_main,
        'date', '2026-02-10',
        'customer_id', v_customer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer),
        'reference', 'P3-GRS-SI-CREDIT',
        'memo', 'Short-term credit sale with partial collection',
        'vat_price_basis', 'exclusive',
        'warehouse_id', v_wh_main,
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'OPERATIONS'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-RETAIL')
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item,
          'description', 'Premium Rice 5kg',
          'quantity', 10,
          'unit_price', 360,
          'vat_code_id', v_vat_exempt,
          'warehouse_id', v_wh_main,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4000'),
          'inventory_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'),
          'cogs_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5000')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);

    v_or := fn_save_receipt(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'customer_id', v_customer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer),
        'receipt_date', '2026-03-05',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-GRS-OR-PARTIAL',
        'remarks', 'Partial collection on February credit sale'
      ),
      jsonb_build_array(
        jsonb_build_object('invoice_id', v_si, 'payment_amount', 2000, 'cwt_amount', 0)
      )
    );
    PERFORM fn_post_receipt(v_or);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM purchase_orders
    WHERE company_id = v_company AND notes = 'P3-GRS-PO-INVENTORY'
  ) THEN
    v_po := fn_save_purchase_order(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'po_date', '2026-04-02',
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'delivery_address', 'Golden Retail Main Warehouse',
        'expected_date', '2026-04-05',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier),
        'notes', 'P3-GRS-PO-INVENTORY'
      ),
      jsonb_build_array(
        jsonb_build_object('item_id', v_item, 'description', 'Premium Rice 5kg', 'quantity', 20, 'uom_id', (SELECT uom_id FROM items WHERE id = v_item), 'unit_price', 300)
      )
    );
    PERFORM fn_approve_purchase_order(v_po);
    SELECT id INTO STRICT v_po_line FROM purchase_order_lines WHERE po_id = v_po ORDER BY line_number LIMIT 1;

    v_rr := fn_save_receiving_report(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'warehouse_id', v_wh_main,
        'po_id', v_po,
        'rr_date', '2026-04-05',
        'supplier_dr_no', 'P3-GRS-SUPDR-001',
        'remarks', 'P3-GRS-RR-INVENTORY'
      ),
      jsonb_build_array(
        jsonb_build_object('po_line_id', v_po_line, 'item_id', v_item, 'description', 'Premium Rice 5kg', 'ordered_qty', 20, 'received_qty', 20, 'reject_qty', 0, 'uom_id', (SELECT uom_id FROM items WHERE id = v_item), 'unit_price', 300)
      )
    );
    PERFORM fn_confirm_receiving_report(v_rr);

    v_vb := fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'warehouse_id', v_wh_main,
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'supplier_invoice_number', 'P3-GRS-SUPINV-001',
        'bill_date', '2026-04-06',
        'due_date', '2026-04-21',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier),
        'reference', 'P3-GRS-VB-INVENTORY',
        'memo', 'Non-VAT retail inventory purchase'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item,
          'description', 'Premium Rice 5kg inventory purchase',
          'quantity', 20,
          'unit_price', 300,
          'vat_code_id', v_ivat_exempt,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5010')
        )
      )
    );
    PERFORM fn_approve_vendor_bill(v_vb);
    PERFORM fn_post_vendor_bill(v_vb);

    v_pv := fn_save_payment_voucher(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'voucher_date', '2026-04-15',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-GRS-PV-PARTIAL',
        'remarks', 'Partial payment for retail inventory purchase'
      ),
      jsonb_build_array(
        jsonb_build_object('vendor_bill_id', v_vb, 'payment_amount', 3000, 'ewt_amount', 0)
      )
    );
    PERFORM fn_post_payment_voucher(v_pv);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM stock_transfers
    WHERE company_id = v_company AND transfer_number = 'P3-GRS-TRANSFER-EAST'
  ) THEN
    INSERT INTO stock_transfers (
      company_id, transfer_number, transfer_date, from_warehouse_id,
      to_warehouse_id, notes, created_by, updated_by
    ) VALUES (
      v_company, 'P3-GRS-TRANSFER-EAST', DATE '2026-05-03', v_wh_main,
      v_wh_east, 'Branch replenishment', auth.uid(), auth.uid()
    );
    INSERT INTO stock_transfer_lines (transfer_id, company_id, item_id, qty_transferred)
    VALUES (
      (SELECT id FROM stock_transfers WHERE company_id = v_company AND transfer_number = 'P3-GRS-TRANSFER-EAST'),
      v_company, v_item, 8
    );
    PERFORM fn_post_stock_transfer(
      (SELECT id FROM stock_transfers WHERE company_id = v_company AND transfer_number = 'P3-GRS-TRANSFER-EAST')
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM stock_adjustments
    WHERE company_id = v_company AND adjustment_number = 'P3-GRS-ADJ-SHRINKAGE'
  ) THEN
    SELECT qty_on_hand INTO STRICT v_stock
    FROM stock_balances
    WHERE company_id = v_company AND warehouse_id = v_wh_main AND item_id = v_item;

    INSERT INTO stock_adjustments (
      company_id, branch_id, warehouse_id, adjustment_number,
      adjustment_date, reason, notes, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_wh_main, 'P3-GRS-ADJ-SHRINKAGE',
      DATE '2026-06-01', 'damage', 'Counted retail shrinkage within available stock', auth.uid(), auth.uid()
    );
    INSERT INTO stock_adjustment_lines (
      adjustment_id, company_id, item_id, qty_before, qty_adjusted, qty_after,
      unit_cost, gl_offset_account_id
    ) VALUES (
      (SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'P3-GRS-ADJ-SHRINKAGE'),
      v_company, v_item, v_stock, -1, v_stock - 1, 300,
      (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5020')
    );
    PERFORM fn_post_stock_adjustment(
      (SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'P3-GRS-ADJ-SHRINKAGE')
    );
  END IF;
END
$golden_phase3$;

-- Northstar Digital Solutions OPC: non-VAT retainer and milestone billing.
DO $northstar_phase3$
DECLARE
  v_company UUID;
  v_branch UUID;
  v_customer_retainer UUID;
  v_customer_milestone UUID;
  v_supplier UUID;
  v_service_retainer UUID;
  v_service_milestone UUID;
  v_vat_exempt UUID;
  v_ivat_exempt UUID;
  v_bank_mode UUID;
  v_si UUID;
  v_or UUID;
  v_vb UUID;
  v_pv UUID;
BEGIN
  SELECT id INTO STRICT v_company FROM companies WHERE trade_name = 'DEMO-OPC-NONVAT';
  SELECT id INTO STRICT v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT id INTO STRICT v_customer_retainer FROM customers WHERE company_id = v_company AND customer_code = 'CUST-NORTHSTAR-RET';
  SELECT id INTO STRICT v_customer_milestone FROM customers WHERE company_id = v_company AND customer_code = 'CUST-NORTHSTAR-MILESTONE';
  SELECT id INTO STRICT v_supplier FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-NORTHSTAR-CLOUD';
  SELECT id INTO STRICT v_service_retainer FROM items WHERE company_id = v_company AND item_code = 'NS-RETAINER';
  SELECT id INTO STRICT v_service_milestone FROM items WHERE company_id = v_company AND item_code = 'NS-MILESTONE';
  SELECT id INTO STRICT v_vat_exempt FROM vat_codes WHERE vat_code = 'VAT-EXEMPT';
  SELECT id INTO STRICT v_ivat_exempt FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT';
  SELECT id INTO STRICT v_bank_mode FROM ref_payment_modes WHERE code = 'BANK_XFER';

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company AND description = 'P3-NS-OPENING-BALANCES'
  ) THEN
    PERFORM fn_post_manual_je(
      v_company,
      v_branch,
      DATE '2026-01-02',
      'P3-NS-OPENING-BALANCES',
      'MANUAL',
      false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1010'), 'description', 'Opening petty cash', 'debit_amount', 20000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'), 'description', 'Opening operating bank', 'debit_amount', 200000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '3000'), 'description', 'Single stockholder equity', 'debit_amount', 0, 'credit_amount', 220000, 'branch_id', v_branch)
      ),
      'opening'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-NS-SI-RETAINER'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-02-28',
        'customer_id', v_customer_retainer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_retainer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_retainer),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer_retainer),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer_retainer),
        'reference', 'P3-NS-SI-RETAINER',
        'memo', 'February managed IT retainer',
        'vat_price_basis', 'exclusive',
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'OPERATIONS'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-PROJECTS')
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service_retainer,
          'description', 'Managed IT Retainer - February 2026',
          'quantity', 1,
          'unit_price', 18000,
          'vat_code_id', v_vat_exempt,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);

    v_or := fn_save_receipt(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'customer_id', v_customer_retainer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_retainer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_retainer),
        'receipt_date', '2026-03-15',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-NS-OR-RETAINER',
        'remarks', 'Full retainer collection'
      ),
      jsonb_build_array(
        jsonb_build_object('invoice_id', v_si, 'payment_amount', 18000, 'cwt_amount', 0)
      )
    );
    PERFORM fn_post_receipt(v_or);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-NS-SI-MILESTONE'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-04-15',
        'customer_id', v_customer_milestone,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_milestone),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_milestone),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer_milestone),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer_milestone),
        'reference', 'P3-NS-SI-MILESTONE',
        'memo', 'Application delivery milestone remains open',
        'vat_price_basis', 'exclusive',
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'SALES'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-PROJECTS')
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service_milestone,
          'description', 'Application Delivery Milestone 1',
          'quantity', 1,
          'unit_price', 45000,
          'vat_code_id', v_vat_exempt,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vendor_bills
    WHERE company_id = v_company AND reference = 'P3-NS-VB-CLOUD'
  ) THEN
    v_vb := fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'supplier_invoice_number', 'P3-NS-CLOUD-APR',
        'bill_date', '2026-04-30',
        'due_date', '2026-05-30',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier),
        'reference', 'P3-NS-VB-CLOUD',
        'memo', 'Cloud platform operating expense'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'description', 'April cloud infrastructure service',
          'quantity', 1,
          'unit_price', 12000,
          'vat_code_id', v_ivat_exempt,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6030')
        )
      )
    );
    PERFORM fn_approve_vendor_bill(v_vb);
    PERFORM fn_post_vendor_bill(v_vb);

    v_pv := fn_save_payment_voucher(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'voucher_date', '2026-05-20',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-NS-PV-CLOUD',
        'remarks', 'Cloud service payment'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'vendor_bill_id', v_vb,
          'payment_amount', 12000,
          'ewt_amount', 0
        )
      )
    );
    PERFORM fn_post_payment_voucher(v_pv);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company AND description = 'P3-NS-MONTH-END-ACCRUAL'
  ) THEN
    PERFORM fn_post_manual_je(
      v_company,
      v_branch,
      DATE '2026-06-30',
      'P3-NS-MONTH-END-ACCRUAL',
      'MANUAL',
      false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6030'), 'description', 'Accrued contractor services', 'debit_amount', 5000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '2300'), 'description', 'Accrued contractor liability', 'debit_amount', 0, 'credit_amount', 5000, 'branch_id', v_branch)
      ),
      'adjusting'
    );
  END IF;
END
$northstar_phase3$;

-- Prime Business Advisory Inc.: VAT-inclusive/exclusive fees, CWT collection,
-- and source-accrued EWT on professional and rental expenses.
DO $prime_phase3$
DECLARE
  v_company UUID;
  v_branch UUID;
  v_customer_sme UUID;
  v_customer_retainer UUID;
  v_supplier_prof UUID;
  v_supplier_rent UUID;
  v_service_advisory UUID;
  v_service_retainer UUID;
  v_vat UUID;
  v_ivat UUID;
  v_cwt_atc UUID;
  v_ewt_prof UUID;
  v_ewt_rent UUID;
  v_bank_mode UUID;
  v_si UUID;
  v_or UUID;
  v_vb UUID;
  v_pv UUID;
BEGIN
  SELECT id INTO STRICT v_company FROM companies WHERE trade_name = 'DEMO-SVC-VAT';
  SELECT id INTO STRICT v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT id INTO STRICT v_customer_sme FROM customers WHERE company_id = v_company AND customer_code = 'CUST-PRIME-SME';
  SELECT id INTO STRICT v_customer_retainer FROM customers WHERE company_id = v_company AND customer_code = 'CUST-PRIME-RETAINER';
  SELECT id INTO STRICT v_supplier_prof FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-PRIME-PROF';
  SELECT id INTO STRICT v_supplier_rent FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-PRIME-RENT';
  SELECT id INTO STRICT v_service_advisory FROM items WHERE company_id = v_company AND item_code = 'PBA-TAX-ADVISORY';
  SELECT id INTO STRICT v_service_retainer FROM items WHERE company_id = v_company AND item_code = 'PBA-RETAINER';
  SELECT id INTO STRICT v_vat FROM vat_codes WHERE vat_code = 'VAT-12';
  SELECT id INTO STRICT v_ivat FROM vat_codes WHERE vat_code = 'IVAT-12';
  SELECT id INTO STRICT v_cwt_atc FROM atc_codes WHERE code = 'WC159' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO STRICT v_ewt_prof FROM atc_codes WHERE code = 'WC010' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO STRICT v_ewt_rent FROM atc_codes WHERE code = 'WC130' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO STRICT v_bank_mode FROM ref_payment_modes WHERE code = 'BANK_XFER';

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company AND description = 'P3-PBA-OPENING-BALANCES'
  ) THEN
    PERFORM fn_post_manual_je(
      v_company,
      v_branch,
      DATE '2026-01-02',
      'P3-PBA-OPENING-BALANCES',
      'MANUAL',
      false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1010'), 'description', 'Opening petty cash', 'debit_amount', 50000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'), 'description', 'Opening operating bank', 'debit_amount', 500000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '3000'), 'description', 'Share capital', 'debit_amount', 0, 'credit_amount', 550000, 'branch_id', v_branch)
      ),
      'opening'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-PBA-SI-VAT-EXCLUSIVE'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-02-12',
        'customer_id', v_customer_sme,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_sme),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_sme),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer_sme),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer_sme),
        'reference', 'P3-PBA-SI-VAT-EXCLUSIVE',
        'memo', 'VAT-exclusive quarterly tax advisory',
        'vat_price_basis', 'exclusive',
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'OPERATIONS'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-ENGAGEMENTS')
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service_advisory,
          'description', 'Quarterly Tax Advisory',
          'quantity', 1,
          'unit_price', 28000,
          'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-PBA-SI-CWT-PARTIAL'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-03-01',
        'customer_id', v_customer_retainer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_retainer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_retainer),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer_retainer),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer_retainer),
        'reference', 'P3-PBA-SI-CWT-PARTIAL',
        'memo', 'VAT-inclusive retainer with expected and actual CWT',
        'vat_price_basis', 'inclusive',
        'cwt_amount_expected', 400,
        'cwt_atc_code_id', v_cwt_atc,
        'cwt_tax_base', 20000,
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'SALES'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-ENGAGEMENTS')
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service_retainer,
          'description', 'Monthly Advisory Retainer - March 2026',
          'quantity', 1,
          'unit_price', 22400,
          'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);

    v_or := fn_save_receipt(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'customer_id', v_customer_retainer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_retainer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_retainer),
        'receipt_date', '2026-03-20',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-PBA-OR-CWT-PARTIAL',
        'remarks', 'Partial retainer collection with actual CWT'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'invoice_id', v_si,
          'payment_amount', 16500,
          'cwt_amount', 300,
          'atc_code_id', v_cwt_atc,
          'cwt_tax_base', 15000
        )
      )
    );
    PERFORM fn_post_receipt(v_or);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vendor_bills
    WHERE company_id = v_company AND reference = 'P3-PBA-VB-PROF'
  ) THEN
    v_vb := fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier_prof,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier_prof),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier_prof),
        'supplier_invoice_number', 'P3-PBA-PROF-001',
        'bill_date', '2026-04-05',
        'due_date', '2026-04-20',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier_prof),
        'reference', 'P3-PBA-VB-PROF',
        'memo', 'Professional fee with 10% EWT at source'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'description', 'Legal and professional advisory',
          'quantity', 1,
          'unit_price', 20000,
          'vat_code_id', v_ivat,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6030'),
          'ewt_atc_code_id', v_ewt_prof,
          'ewt_tax_base', 20000,
          'ewt_amount', 2000,
          'ewt_income_nature', 'Professional fees'
        )
      )
    );
    PERFORM fn_approve_vendor_bill(v_vb);
    PERFORM fn_post_vendor_bill(v_vb);

    v_pv := fn_save_payment_voucher(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier_prof,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier_prof),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier_prof),
        'voucher_date', '2026-04-18',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-PBA-PV-PROF-PARTIAL',
        'remarks', 'Partial professional-fee payment; EWT accrued at bill posting'
      ),
      jsonb_build_array(
        jsonb_build_object('vendor_bill_id', v_vb, 'payment_amount', 10000, 'ewt_amount', 0)
      )
    );
    PERFORM fn_post_payment_voucher(v_pv);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vendor_bills
    WHERE company_id = v_company AND reference = 'P3-PBA-VB-RENT'
  ) THEN
    v_vb := fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier_rent,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier_rent),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier_rent),
        'supplier_invoice_number', 'P3-PBA-RENT-MAY',
        'bill_date', '2026-05-01',
        'due_date', '2026-05-15',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier_rent),
        'reference', 'P3-PBA-VB-RENT',
        'memo', 'May office rent with 2% EWT at source'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'description', 'May office rent',
          'quantity', 1,
          'unit_price', 30000,
          'vat_code_id', v_ivat,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6010'),
          'ewt_atc_code_id', v_ewt_rent,
          'ewt_tax_base', 30000,
          'ewt_amount', 600,
          'ewt_income_nature', 'Rental of real property'
        )
      )
    );
    PERFORM fn_approve_vendor_bill(v_vb);
    PERFORM fn_post_vendor_bill(v_vb);
  END IF;
END
$prime_phase3$;

-- Bayani Partners and Company: mixed trading and advisory operations.
DO $bayani_phase3$
DECLARE
  v_company UUID;
  v_branch UUID;
  v_warehouse UUID;
  v_item UUID;
  v_service UUID;
  v_customer_trade UUID;
  v_customer_service UUID;
  v_supplier UUID;
  v_vat UUID;
  v_ivat UUID;
  v_cwt_atc UUID;
  v_ewt_atc UUID;
  v_bank_mode UUID;
  v_inventory_value NUMERIC;
  v_po UUID;
  v_po_line UUID;
  v_rr UUID;
  v_vb UUID;
  v_pv UUID;
  v_so UUID;
  v_so_line UUID;
  v_dr UUID;
  v_si UUID;
  v_or UUID;
  v_stock NUMERIC;
BEGIN
  SELECT id INTO STRICT v_company FROM companies WHERE trade_name = 'DEMO-PARTNERSHIP-VAT';
  SELECT id INTO STRICT v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT id INTO STRICT v_warehouse FROM warehouses WHERE company_id = v_company AND warehouse_code = 'WH-BAYANI';
  SELECT id INTO STRICT v_item FROM items WHERE company_id = v_company AND item_code = 'BPC-PAPER-CASE';
  SELECT id INTO STRICT v_service FROM items WHERE company_id = v_company AND item_code = 'BPC-ADVISORY';
  SELECT id INTO STRICT v_customer_trade FROM customers WHERE company_id = v_company AND customer_code = 'CUST-BAYANI-TRADE';
  SELECT id INTO STRICT v_customer_service FROM customers WHERE company_id = v_company AND customer_code = 'CUST-BAYANI-SERVICE';
  SELECT id INTO STRICT v_supplier FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-BAYANI-GOODS';
  SELECT id INTO STRICT v_vat FROM vat_codes WHERE vat_code = 'VAT-12';
  SELECT id INTO STRICT v_ivat FROM vat_codes WHERE vat_code = 'IVAT-12';
  SELECT id INTO STRICT v_cwt_atc FROM atc_codes WHERE code = 'WC159' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO STRICT v_ewt_atc FROM atc_codes WHERE code = 'WC158' AND tax_category = 'ewt' AND is_active AND deprecated_at IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT id INTO STRICT v_bank_mode FROM ref_payment_modes WHERE code = 'BANK_XFER';

  IF NOT EXISTS (
    SELECT 1 FROM inventory_transactions
    WHERE company_id = v_company
      AND reference_doc_type = 'P3_OPENING'
      AND item_id = v_item
  ) THEN
    PERFORM fn_receive_inventory(jsonb_build_object(
      'company_id', v_company,
      'warehouse_id', v_warehouse,
      'item_id', v_item,
      'qty', 25,
      'unit_cost', 2100,
      'receipt_date', '2026-01-02',
      'reference_doc_type', 'P3_OPENING',
      'notes', 'P3-BPC-OPENING-PAPER'
    ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company AND description = 'P3-BPC-OPENING-BALANCES'
  ) THEN
    SELECT COALESCE(SUM(total_cost), 0)
    INTO v_inventory_value
    FROM stock_balances
    WHERE company_id = v_company;

    PERFORM fn_post_manual_je(
      v_company,
      v_branch,
      DATE '2026-01-02',
      'P3-BPC-OPENING-BALANCES',
      'MANUAL',
      false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1010'), 'description', 'Opening cash', 'debit_amount', 75000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'), 'description', 'Opening bank', 'debit_amount', 300000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'), 'description', 'Opening trading inventory', 'debit_amount', v_inventory_value, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '3000'), 'description', 'Partners capital', 'debit_amount', 0, 'credit_amount', 375000 + v_inventory_value, 'branch_id', v_branch)
      ),
      'opening'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM purchase_orders
    WHERE company_id = v_company AND notes = 'P3-BPC-PO-PARTIAL'
  ) THEN
    v_po := fn_save_purchase_order(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'po_date', '2026-02-03',
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'delivery_address', 'Bayani Main Warehouse',
        'expected_date', '2026-02-08',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier),
        'notes', 'P3-BPC-PO-PARTIAL'
      ),
      jsonb_build_array(
        jsonb_build_object('item_id', v_item, 'description', 'Bayani Bond Paper Case', 'quantity', 15, 'uom_id', (SELECT uom_id FROM items WHERE id = v_item), 'unit_price', 2100)
      )
    );
    PERFORM fn_approve_purchase_order(v_po);
    SELECT id INTO STRICT v_po_line FROM purchase_order_lines WHERE po_id = v_po ORDER BY line_number LIMIT 1;

    v_rr := fn_save_receiving_report(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'warehouse_id', v_warehouse,
        'po_id', v_po,
        'rr_date', '2026-02-08',
        'supplier_dr_no', 'P3-BPC-SUPDR-001',
        'remarks', 'P3-BPC-RR-PARTIAL'
      ),
      jsonb_build_array(
        jsonb_build_object('po_line_id', v_po_line, 'item_id', v_item, 'description', 'Bayani Bond Paper Case', 'ordered_qty', 15, 'received_qty', 10, 'reject_qty', 0, 'uom_id', (SELECT uom_id FROM items WHERE id = v_item), 'unit_price', 2100)
      )
    );
    PERFORM fn_confirm_receiving_report(v_rr);

    v_vb := fn_save_vendor_bill(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'supplier_invoice_number', 'P3-BPC-SUPINV-001',
        'bill_date', '2026-02-09',
        'due_date', '2026-03-11',
        'payment_terms_id', (SELECT default_terms_id FROM suppliers WHERE id = v_supplier),
        'reference', 'P3-BPC-VB-INVENTORY',
        'memo', 'Inventory bill for partial receipt with EWT at source'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item,
          'description', 'Ten cases received and billed',
          'quantity', 10,
          'unit_price', 2100,
          'vat_code_id', v_ivat,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5010'),
          'ewt_atc_code_id', v_ewt_atc,
          'ewt_tax_base', 21000,
          'ewt_amount', 210,
          'ewt_income_nature', 'Goods purchase'
        )
      )
    );
    PERFORM fn_approve_vendor_bill(v_vb);
    PERFORM fn_post_vendor_bill(v_vb);

    v_pv := fn_save_payment_voucher(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'supplier_id', v_supplier,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier),
        'voucher_date', '2026-03-01',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-BPC-PV-PARTIAL',
        'remarks', 'Partial inventory supplier payment'
      ),
      jsonb_build_array(
        jsonb_build_object('vendor_bill_id', v_vb, 'payment_amount', 10000, 'ewt_amount', 0)
      )
    );
    PERFORM fn_post_payment_voucher(v_pv);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_orders
    WHERE company_id = v_company AND reference_number = 'P3-BPC-SO-TRADE'
  ) THEN
    INSERT INTO sales_orders (
      company_id, branch_id, customer_id, customer_name_snapshot,
      customer_tin_snapshot, so_number, so_date, expected_delivery_date,
      reference_number, remarks, total_amount, approval_status,
      fulfillment_status, approved_by, approved_at, created_by, updated_by
    ) VALUES (
      v_company,
      v_branch,
      v_customer_trade,
      (SELECT registered_name FROM customers WHERE id = v_customer_trade),
      (SELECT tin FROM customers WHERE id = v_customer_trade),
      fn_next_document_number(v_company, v_branch, 'SO'),
      DATE '2026-03-10',
      DATE '2026-03-15',
      'P3-BPC-SO-TRADE',
      'Twelve cases ordered; seven delivered and invoiced',
      33600,
      'approved',
      'partial',
      auth.uid(),
      now(),
      auth.uid(),
      auth.uid()
    ) RETURNING id INTO v_so;

    INSERT INTO sales_order_lines (
      sales_order_id, company_id, item_id, description, quantity,
      fulfilled_quantity, uom_id, unit_price, net_amount, line_number,
      created_by, updated_by
    ) VALUES (
      v_so, v_company, v_item, 'Bayani Bond Paper Case', 12, 7,
      (SELECT uom_id FROM items WHERE id = v_item), 2800, 33600, 1,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_so_line;

    INSERT INTO delivery_receipts (
      company_id, branch_id, sales_order_id, customer_id,
      customer_name_snapshot, dr_number, dr_date, shipping_method,
      delivery_address, status, delivered_at, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_so, v_customer_trade,
      (SELECT registered_name FROM customers WHERE id = v_customer_trade),
      fn_next_document_number(v_company, v_branch, 'DR'),
      DATE '2026-03-15', 'in_house',
      (SELECT delivery_address FROM customers WHERE id = v_customer_trade),
      'delivered', TIMESTAMPTZ '2026-03-15 10:00:00+08', auth.uid(), auth.uid()
    ) RETURNING id INTO v_dr;

    INSERT INTO delivery_receipt_lines (
      dr_id, company_id, so_line_id, item_id, description, quantity,
      uom_id, line_number, created_by, updated_by
    ) VALUES (
      v_dr, v_company, v_so_line, v_item, 'Bayani Bond Paper Case', 7,
      (SELECT uom_id FROM items WHERE id = v_item), 1, auth.uid(), auth.uid()
    );
  ELSE
    SELECT id INTO STRICT v_so FROM sales_orders WHERE company_id = v_company AND reference_number = 'P3-BPC-SO-TRADE';
    SELECT id INTO STRICT v_so_line FROM sales_order_lines WHERE sales_order_id = v_so ORDER BY line_number LIMIT 1;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-BPC-SI-TRADE'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-03-16',
        'customer_id', v_customer_trade,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_trade),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_trade),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer_trade),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer_trade),
        'reference', 'P3-BPC-SI-TRADE',
        'memo', 'Partial fulfillment invoice sourced from sales order',
        'vat_price_basis', 'exclusive',
        'warehouse_id', v_warehouse
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item,
          'description', 'Bayani Bond Paper Case',
          'quantity', 7,
          'unit_price', 2800,
          'vat_code_id', v_vat,
          'warehouse_id', v_warehouse,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4000'),
          'inventory_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'),
          'cogs_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5000'),
          'source_document_type', 'sales_order',
          'source_line_id', v_so_line
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);

    v_or := fn_save_receipt(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'customer_id', v_customer_trade,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_trade),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_trade),
        'receipt_date', '2026-04-10',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-BPC-OR-TRADE',
        'remarks', 'Full collection for delivered trading invoice'
      ),
      jsonb_build_array(
        jsonb_build_object('invoice_id', v_si, 'payment_amount', 21952, 'cwt_amount', 0)
      )
    );
    PERFORM fn_post_receipt(v_or);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-BPC-SI-ADVISORY'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-05-15',
        'customer_id', v_customer_service,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer_service),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer_service),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer_service),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer_service),
        'reference', 'P3-BPC-SI-ADVISORY',
        'memo', 'Open advisory invoice with expected CWT',
        'vat_price_basis', 'exclusive',
        'cwt_amount_expected', 300,
        'cwt_atc_code_id', v_cwt_atc,
        'cwt_tax_base', 15000
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service,
          'description', 'Business Advisory Engagement',
          'quantity', 1,
          'unit_price', 15000,
          'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM stock_adjustments
    WHERE company_id = v_company AND adjustment_number = 'P3-BPC-ADJ-COUNT-GAIN'
  ) THEN
    SELECT qty_on_hand INTO STRICT v_stock
    FROM stock_balances
    WHERE company_id = v_company AND warehouse_id = v_warehouse AND item_id = v_item;

    INSERT INTO stock_adjustments (
      company_id, branch_id, warehouse_id, adjustment_number,
      adjustment_date, reason, notes, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_warehouse, 'P3-BPC-ADJ-COUNT-GAIN',
      DATE '2026-06-01', 'correction', 'Counted one additional sealed case', auth.uid(), auth.uid()
    );
    INSERT INTO stock_adjustment_lines (
      adjustment_id, company_id, item_id, qty_before, qty_adjusted, qty_after,
      unit_cost, gl_offset_account_id
    ) VALUES (
      (SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'P3-BPC-ADJ-COUNT-GAIN'),
      v_company, v_item, v_stock, 1, v_stock + 1, 2100,
      (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5020')
    );
    PERFORM fn_post_stock_adjustment(
      (SELECT id FROM stock_adjustments WHERE company_id = v_company AND adjustment_number = 'P3-BPC-ADJ-COUNT-GAIN')
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_company AND description = 'P3-BPC-PARTNER-DRAWING'
  ) THEN
    PERFORM fn_post_manual_je(
      v_company,
      v_branch,
      DATE '2026-06-15',
      'P3-BPC-PARTNER-DRAWING',
      'MANUAL',
      false,
      jsonb_build_array(
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '3300'), 'description', 'Partner drawing', 'debit_amount', 10000, 'credit_amount', 0, 'branch_id', v_branch),
        jsonb_build_object('account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'), 'description', 'Bank disbursement', 'debit_amount', 0, 'credit_amount', 10000, 'branch_id', v_branch)
      ),
      'regular'
    );
  END IF;
END
$bayani_phase3$;

-- ABC Trading Corporation: advanced sales conversion, corrective documents,
-- cash purchasing, physical count, and governed void/reversal coverage.
DO $abc_phase3$
DECLARE
  v_company UUID;
  v_branch UUID;
  v_warehouse UUID;
  v_item UUID;
  v_item_tape UUID;
  v_service UUID;
  v_customer UUID;
  v_supplier_utility UUID;
  v_vat UUID;
  v_ivat UUID;
  v_bank_mode UUID;
  v_quote UUID;
  v_quote_line UUID;
  v_so UUID;
  v_so_line UUID;
  v_dr UUID;
  v_si UUID;
  v_or UUID;
  v_cm UUID;
  v_vc UUID;
  v_cp UUID;
  v_original_si UUID;
  v_original_si_line UUID;
  v_original_vb UUID;
  v_sheet UUID;
  v_stock NUMERIC;
  v_cost NUMERIC;
BEGIN
  SELECT id INTO STRICT v_company FROM companies WHERE trade_name = 'DEMO-CORP-VAT';
  SELECT id INTO STRICT v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT id INTO STRICT v_warehouse FROM warehouses WHERE company_id = v_company AND warehouse_code = 'WH-MAIN';
  SELECT id INTO STRICT v_item FROM items WHERE company_id = v_company AND item_code = 'ITEM-STOCK-001';
  SELECT id INTO STRICT v_item_tape FROM items WHERE company_id = v_company AND item_code = 'ITEM-STOCK-003';
  SELECT id INTO STRICT v_service FROM items WHERE company_id = v_company AND item_code = 'ITEM-SERVICE-001';
  SELECT id INTO STRICT v_customer FROM customers WHERE company_id = v_company AND customer_code = 'CUST-VAT-CREDIT';
  SELECT id INTO STRICT v_supplier_utility FROM suppliers WHERE company_id = v_company AND supplier_code = 'SUP-UTILITIES';
  SELECT id INTO STRICT v_vat FROM vat_codes WHERE vat_code = 'VAT-12';
  SELECT id INTO STRICT v_ivat FROM vat_codes WHERE vat_code = 'IVAT-12';
  SELECT id INTO STRICT v_bank_mode FROM ref_payment_modes WHERE code = 'BANK_XFER';

  IF NOT EXISTS (
    SELECT 1 FROM sales_quotations
    WHERE company_id = v_company AND reference_number = 'P3-ABC-QT-LIFECYCLE'
  ) THEN
    INSERT INTO sales_quotations (
      company_id, branch_id, customer_id, customer_name_snapshot,
      customer_tin_snapshot, quotation_number, quotation_date, validity_date,
      currency_code, reference_number, remarks, total_amount, status,
      approved_by, approved_at, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_customer,
      (SELECT registered_name FROM customers WHERE id = v_customer),
      (SELECT tin FROM customers WHERE id = v_customer),
      fn_next_document_number(v_company, v_branch, 'QT'),
      DATE '2026-02-01', DATE '2026-02-15', 'PHP',
      'P3-ABC-QT-LIFECYCLE', 'Wholesale quotation converted to a partially fulfilled order',
      5600, 'approved', auth.uid(), now(), auth.uid(), auth.uid()
    ) RETURNING id INTO v_quote;

    INSERT INTO sales_quotation_lines (
      quotation_id, company_id, item_id, description, quantity, uom_id,
      unit_price, discount_amount, net_amount, line_number, created_by, updated_by
    ) VALUES (
      v_quote, v_company, v_item, 'Bond Paper A4', 20,
      (SELECT uom_id FROM items WHERE id = v_item), 280, 0, 5600, 1,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_quote_line;

    INSERT INTO sales_orders (
      company_id, branch_id, quotation_id, customer_id,
      customer_name_snapshot, customer_tin_snapshot, so_number, so_date,
      expected_delivery_date, currency_code, reference_number, remarks,
      total_amount, approval_status, fulfillment_status, approved_by,
      approved_at, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_quote, v_customer,
      (SELECT registered_name FROM customers WHERE id = v_customer),
      (SELECT tin FROM customers WHERE id = v_customer),
      fn_next_document_number(v_company, v_branch, 'SO'),
      DATE '2026-02-03', DATE '2026-02-10', 'PHP',
      'P3-ABC-SO-LIFECYCLE', 'Twenty ordered; eight delivered and invoiced',
      5600, 'approved', 'partial', auth.uid(), now(), auth.uid(), auth.uid()
    ) RETURNING id INTO v_so;

    INSERT INTO sales_order_lines (
      sales_order_id, company_id, quotation_line_id, item_id, description,
      quantity, fulfilled_quantity, uom_id, unit_price, discount_amount,
      net_amount, line_number, created_by, updated_by
    ) VALUES (
      v_so, v_company, v_quote_line, v_item, 'Bond Paper A4', 20, 8,
      (SELECT uom_id FROM items WHERE id = v_item), 280, 0, 5600, 1,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_so_line;

    INSERT INTO delivery_receipts (
      company_id, branch_id, sales_order_id, customer_id,
      customer_name_snapshot, dr_number, dr_date, shipping_method,
      delivery_address, status, delivered_at, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_so, v_customer,
      (SELECT registered_name FROM customers WHERE id = v_customer),
      fn_next_document_number(v_company, v_branch, 'DR'),
      DATE '2026-02-10', 'in_house',
      (SELECT delivery_address FROM customers WHERE id = v_customer),
      'delivered', TIMESTAMPTZ '2026-02-10 11:00:00+08', auth.uid(), auth.uid()
    ) RETURNING id INTO v_dr;

    INSERT INTO delivery_receipt_lines (
      dr_id, company_id, so_line_id, item_id, description, quantity,
      uom_id, line_number, created_by, updated_by
    ) VALUES (
      v_dr, v_company, v_so_line, v_item, 'Bond Paper A4', 8,
      (SELECT uom_id FROM items WHERE id = v_item), 1, auth.uid(), auth.uid()
    );
  ELSE
    SELECT id INTO STRICT v_so FROM sales_orders WHERE company_id = v_company AND reference_number = 'P3-ABC-SO-LIFECYCLE';
    SELECT id INTO STRICT v_so_line FROM sales_order_lines WHERE sales_order_id = v_so ORDER BY line_number LIMIT 1;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-ABC-SI-LIFECYCLE'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-02-11',
        'customer_id', v_customer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer),
        'reference', 'P3-ABC-SI-LIFECYCLE',
        'memo', 'Partial invoice from quotation and sales order lifecycle',
        'vat_price_basis', 'exclusive',
        'warehouse_id', v_warehouse,
        'department_id', (SELECT id FROM departments WHERE company_id = v_company AND department_code = 'SALES'),
        'cost_center_id', (SELECT id FROM cost_centers WHERE company_id = v_company AND cost_center_code = 'CC-SALES-MNL')
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item,
          'description', 'Bond Paper A4',
          'quantity', 8,
          'unit_price', 280,
          'vat_code_id', v_vat,
          'warehouse_id', v_warehouse,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4000'),
          'inventory_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1200'),
          'cogs_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5000'),
          'source_document_type', 'sales_order',
          'source_line_id', v_so_line
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);

    v_or := fn_save_receipt(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'customer_id', v_customer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer),
        'receipt_date', '2026-03-01',
        'payment_mode_id', v_bank_mode,
        'reference_number', 'P3-ABC-OR-LIFECYCLE-PARTIAL',
        'remarks', 'Partial collection against converted sales order invoice'
      ),
      jsonb_build_array(
        jsonb_build_object('invoice_id', v_si, 'payment_amount', 1500, 'cwt_amount', 0)
      )
    );
    PERFORM fn_post_receipt(v_or);
  END IF;

  SELECT id INTO STRICT v_original_si
  FROM sales_invoices
  WHERE company_id = v_company AND reference = 'TEST-SI-VAT-INCLUSIVE';
  SELECT id INTO STRICT v_original_si_line
  FROM sales_invoice_lines
  WHERE sales_invoice_id = v_original_si
  ORDER BY line_number
  LIMIT 1;

  IF NOT EXISTS (
    SELECT 1 FROM credit_memos
    WHERE company_id = v_company AND remarks = 'P3-ABC-CM-ALLOWANCE'
  ) THEN
    v_cm := fn_save_credit_memo(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'customer_id', (SELECT customer_id FROM sales_invoices WHERE id = v_original_si),
        'customer_name_snapshot', (SELECT customer_name_snapshot FROM sales_invoices WHERE id = v_original_si),
        'customer_tin_snapshot', (SELECT customer_tin_snapshot FROM sales_invoices WHERE id = v_original_si),
        'invoice_id', v_original_si,
        'cm_date', '2026-03-05',
        'reason_code_id', (SELECT id FROM ref_reason_codes WHERE code = 'CM_ALLOWANCE'),
        'remarks', 'P3-ABC-CM-ALLOWANCE'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'invoice_line_id', v_original_si_line,
          'item_id', v_service,
          'description', 'Service quality allowance',
          'quantity', 1,
          'unit_price', 100,
          'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      ),
      'applied'
    );
  END IF;

  SELECT id INTO STRICT v_original_vb
  FROM vendor_bills
  WHERE company_id = v_company AND reference = 'TEST-VB-PARTIAL-PAYMENT';

  IF NOT EXISTS (
    SELECT 1 FROM vendor_credits
    WHERE company_id = v_company AND supplier_cm_no = 'P3-ABC-SUPCM-001'
  ) THEN
    v_vc := fn_save_vendor_credit(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'credit_date', '2026-03-10',
        'supplier_id', (SELECT supplier_id FROM vendor_bills WHERE id = v_original_vb),
        'supplier_name_snapshot', (SELECT supplier_name_snapshot FROM vendor_bills WHERE id = v_original_vb),
        'supplier_tin_snapshot', (SELECT supplier_tin_snapshot FROM vendor_bills WHERE id = v_original_vb),
        'supplier_cm_no', 'P3-ABC-SUPCM-001',
        'reference_bill_id', v_original_vb,
        'remarks', 'Supplier credit for one damaged unit'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_item,
          'description', 'Supplier allowance for damaged paper',
          'quantity', 1,
          'uom_id', (SELECT uom_id FROM items WHERE id = v_item),
          'unit_price', 200,
          'vat_code_id', v_ivat,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5010')
        )
      )
    );
    PERFORM fn_post_vendor_credit(v_vc);
    PERFORM fn_apply_vendor_credit(v_vc, v_original_vb, 224, DATE '2026-03-10', 'P3 supplier credit application');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM cash_purchases
    WHERE company_id = v_company AND reference_number = 'P3-ABC-CP-UTILITY'
  ) THEN
    v_cp := fn_save_cash_purchase(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'transaction_date', '2026-04-12',
        'supplier_id', v_supplier_utility,
        'supplier_name_snapshot', (SELECT registered_name FROM suppliers WHERE id = v_supplier_utility),
        'supplier_tin_snapshot', (SELECT tin FROM suppliers WHERE id = v_supplier_utility),
        'payment_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1030'),
        'payment_method', 'transfer',
        'reference_number', 'P3-ABC-CP-UTILITY',
        'remarks', 'April utility paid immediately'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'description', 'April electricity expense',
          'quantity', 1,
          'unit_price', 5000,
          'vat_code_id', v_ivat,
          'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6020')
        )
      )
    );
    PERFORM fn_post_cash_purchase(v_cp);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM physical_count_sheets
    WHERE company_id = v_company AND count_number = 'P3-ABC-COUNT-JUNE'
  ) THEN
    SELECT qty_on_hand, wac_unit_cost INTO STRICT v_stock, v_cost
    FROM stock_balances
    WHERE company_id = v_company AND warehouse_id = v_warehouse AND item_id = v_item_tape;

    INSERT INTO physical_count_sheets (
      company_id, branch_id, warehouse_id, count_number, count_date,
      status, fiscal_period_id, notes, created_by, updated_by
    ) VALUES (
      v_company, v_branch, v_warehouse, 'P3-ABC-COUNT-JUNE', DATE '2026-06-01',
      'variance_review',
      (SELECT id FROM fiscal_periods WHERE company_id = v_company AND start_date <= DATE '2026-06-01' AND end_date >= DATE '2026-06-01' LIMIT 1),
      'Cycle count found one additional tape roll', auth.uid(), auth.uid()
    ) RETURNING id INTO v_sheet;

    INSERT INTO physical_count_sheet_lines (
      count_sheet_id, company_id, item_id, system_qty, counted_qty,
      unit_cost, gl_variance_account_id
    ) VALUES (
      v_sheet, v_company, v_item_tape, v_stock, v_stock + 1, v_cost,
      (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5020')
    );
    PERFORM fn_post_physical_count(v_sheet);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM sales_invoices
    WHERE company_id = v_company AND reference = 'P3-ABC-SI-VOIDED'
  ) THEN
    v_si := fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', v_company,
        'branch_id', v_branch,
        'date', '2026-06-10',
        'customer_id', v_customer,
        'customer_name_snapshot', (SELECT registered_name FROM customers WHERE id = v_customer),
        'customer_tin_snapshot', (SELECT tin FROM customers WHERE id = v_customer),
        'customer_address_snapshot', (SELECT registered_address FROM customers WHERE id = v_customer),
        'payment_terms_id', (SELECT default_terms_id FROM customers WHERE id = v_customer),
        'reference', 'P3-ABC-SI-VOIDED',
        'memo', 'Posted then voided regression scenario',
        'vat_price_basis', 'exclusive'
      ),
      jsonb_build_array(
        jsonb_build_object(
          'item_id', v_service,
          'description', 'Voided consulting charge',
          'quantity', 1,
          'unit_price', 1000,
          'vat_code_id', v_vat,
          'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4010')
        )
      )
    );
    PERFORM fn_approve_sales_invoice(v_si);
    PERFORM fn_post_sales_invoice(v_si);
    PERFORM fn_void_sales_invoice(
      v_si,
      (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR'),
      'P3 governed void and reversal fixture'
    );
  END IF;
END
$abc_phase3$;
