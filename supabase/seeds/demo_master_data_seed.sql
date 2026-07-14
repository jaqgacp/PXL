-- =============================================================================
-- PXL DEMO/TEST master data seed — payment terms, customers, suppliers
-- =============================================================================
-- Runs AFTER demo_company_setup_seed.sql (needs the demo company, COA, and
-- withholding ATCs). Master data only: NO transactions are created.
--
-- Properties: idempotent (stable codes + ON CONFLICT/NOT EXISTS), never
-- deletes or overwrites existing data, reuses existing reference records
-- (currencies, ATC masters, COA accounts).
--
-- Run (local):  docker exec -i supabase_db_PXL psql -U postgres -d postgres \
--                 < supabase/seeds/demo_master_data_seed.sql
-- Run (hosted): execute contents via the Supabase management API SQL endpoint.
-- =============================================================================

DO $$
DECLARE
  v_company uuid;
  v_user    uuid;
  v_php     uuid;
  v_ar      uuid;
BEGIN
  SELECT id INTO v_company FROM companies
  WHERE registered_name = 'PXL Demo Trading Corporation';
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Demo company not found - run demo_company_setup_seed.sql first';
  END IF;

  SELECT user_id INTO v_user FROM user_company_memberships
  WHERE company_id = v_company LIMIT 1;

  SELECT id INTO v_php FROM currencies WHERE currency_code = 'PHP';

  SELECT id INTO v_ar FROM chart_of_accounts
  WHERE company_id = v_company AND account_code = '1100-00';

  -- ---------------------------------------------------------------------------
  -- Payment terms (company-scoped; table was empty)
  -- ---------------------------------------------------------------------------
  INSERT INTO payment_terms (company_id, term_code, term_name, days_to_due,
    require_downpayment, is_active, created_by)
  SELECT v_company, x.code, x.name, x.days, false, true, v_user
  FROM (VALUES
    ('COD',   'Cash on Delivery', 0),
    ('NET7',  'Net 7 Days',       7),
    ('NET15', 'Net 15 Days',      15),
    ('NET30', 'Net 30 Days',      30),
    ('NET45', 'Net 45 Days',      45)
  ) AS x(code, name, days)
  ON CONFLICT (company_id, term_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Customers (5): VAT/non-VAT, large/SME, cash/credit mix.
  -- CWT defaults only where the customer is a plausible withholding agent.
  -- default_gl_account_id = AR - Trade for all (subledger control default).
  -- ---------------------------------------------------------------------------
  INSERT INTO customers (company_id, customer_code, customer_group,
    registered_name, trade_name, business_style, tin, tin_branch_code,
    default_tax_type, registered_address, delivery_address, contact_person,
    email, phone_number, default_terms_id, default_currency_id,
    default_gl_account_id, credit_limit,
    is_subject_to_cwt, default_cwt_atc_code_id, is_active, created_by)
  SELECT v_company, x.code, x.grp, x.name, x.trade, x.style, x.tin, '000',
    x.tax_type, x.addr, x.addr, x.contact, x.email, x.phone,
    (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = x.terms),
    v_php, v_ar, x.limit_amt, x.cwt,
    (SELECT id FROM atc_codes a WHERE a.code = x.atc AND a.is_active AND a.deprecated_at IS NULL),
    true, v_user
  FROM (VALUES
    ('CUST-0001', 'trading', 'ABC Trading Corporation', 'ABC Trading',
     'Wholesale Trading', '203-455-789-000', 'vat_registered',
     '123 Rizal Avenue, Barangay 1, Quezon City, Metro Manila 1100',
     'Carlos Mendoza', 'ap@abctrading.ph', '(02) 8123-4567',
     'NET30', 250000.00, true,  'WC158'),
    ('CUST-0002', 'trading', 'Metro Office Supplies Inc.', 'Metro Office Supplies',
     'Office Supplies Trading', '204-566-890-000', 'vat_registered',
     '456 Shaw Boulevard, Barangay Wack-Wack, Mandaluyong City, Metro Manila 1550',
     'Liza Fernandez', 'purchasing@metrooffice.ph', '(02) 8234-5678',
     'NET15', 100000.00, false, NULL),
    ('CUST-0003', 'services', 'Prime Construction Services Corp.', 'Prime Construction',
     'General Construction', '205-677-901-000', 'vat_registered',
     '789 EDSA, Barangay Highway Hills, Mandaluyong City, Metro Manila 1554',
     'Ramon Bautista', 'finance@primeconstruction.ph', '(02) 8345-6789',
     'NET45', 500000.00, true,  'WC159'),
    ('CUST-0004', 'retail', 'Golden Retail Store', 'Golden Retail',
     'Retail Store', '206-788-012-000', 'non_vat',
     '25 P. Burgos Street, Barangay Poblacion, Makati City, Metro Manila 1210',
     'Grace Tan', 'goldenretail@gmail.com', '0917-123-4567',
     'COD', 0.00, false, NULL),
    ('CUST-0005', 'distribution', 'Sunrise Food Distribution Inc.', 'Sunrise Foods',
     'Food Distribution', '207-899-123-000', 'vat_registered',
     '88 MacArthur Highway, Barangay Karuhatan, Valenzuela City, Metro Manila 1441',
     'Nena Reyes', 'orders@sunrisefoods.ph', '(02) 8456-7890',
     'NET7', 50000.00, false, NULL)
  ) AS x(code, grp, name, trade, style, tin, tax_type, addr, contact, email,
         phone, terms, limit_amt, cwt, atc)
  ON CONFLICT (company_id, customer_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Suppliers (5): goods / professional services / transport / rental mix,
  -- with and without EWT. default_gl_account_id = natural expense account.
  -- ---------------------------------------------------------------------------
  INSERT INTO suppliers (company_id, supplier_code, supplier_group,
    registered_name, trade_name, business_style, tin, default_tax_type,
    registered_address, contact_person, email, phone_number,
    default_terms_id, default_currency_id, default_gl_account_id,
    is_subject_to_ewt, default_atc_code_id,
    is_active, created_by)
  SELECT v_company, x.code, x.grp, x.name, x.trade, x.style, x.tin, x.tax_type,
    x.addr, x.contact, x.email, x.phone,
    (SELECT id FROM payment_terms WHERE company_id = v_company AND term_code = x.terms),
    v_php,
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.gl),
    x.ewt,
    (SELECT id FROM atc_codes a WHERE a.code = x.atc AND a.is_active AND a.deprecated_at IS NULL),
    true, v_user
  FROM (VALUES
    ('SUP-0001', 'goods', 'National Office Depot Inc.', 'National Office Depot',
     'Office Supplies Trading', '301-234-567-000', 'vat_registered',
     '10 Quezon Avenue, Barangay Paligsahan, Quezon City, Metro Manila 1103',
     'Edgar Santos', 'sales@nationaldepot.ph', '(02) 8567-8901',
     'NET30', '6050-00', true,  'WC158'),
    ('SUP-0002', 'professional_services', 'Metro Computer Solutions Corp.', 'Metro Computer Solutions',
     'IT Consulting Services', '302-345-678-000', 'vat_registered',
     'Unit 8B, Cyber One Tower, Eastwood City, Quezon City, Metro Manila 1110',
     'Arlene Uy', 'billing@metrocomputer.ph', '(02) 8678-9012',
     'NET15', '6060-00', true,  'WC010'),
    ('SUP-0003', 'transportation', 'ABC Logistics Services Inc.', 'ABC Logistics',
     'Freight and Logistics', '303-456-789-000', 'vat_registered',
     '900 Port Area, Barangay 650, Manila, Metro Manila 1018',
     'Danilo Cruz', 'accounts@abclogistics.ph', '(02) 8789-0123',
     'NET15', '5010-00', true,  'WC140'),
    ('SUP-0004', 'goods', 'Prime Industrial Supply', 'Prime Industrial',
     'Industrial Hardware Trading', '304-567-890-000', 'non_vat',
     '45 A. Bonifacio Street, Barangay Balingasa, Quezon City, Metro Manila 1115',
     'Marites Lopez', 'primeindustrial@gmail.com', '0918-234-5678',
     'COD', '6070-00', false, NULL),
    ('SUP-0005', 'rental', 'Juan Rental Corporation', 'Juan Rentals',
     'Real Property Leasing', '305-678-901-000', 'vat_registered',
     '12F Ayala Tower One, Ayala Avenue, Makati City, Metro Manila 1226',
     'Juan Villanueva', 'leasing@juanrentals.ph', '(02) 8890-1234',
     'NET30', '6020-00', true,  'WC130')
  ) AS x(code, grp, name, trade, style, tin, tax_type, addr, contact, email,
         phone, terms, gl, ewt, atc)
  ON CONFLICT (company_id, supplier_code) DO NOTHING;

  RAISE NOTICE 'Demo master data seed complete for company %', v_company;
END $$;

-- Post-seed summary (safe to run standalone)
SELECT
  (SELECT count(*) FROM payment_terms t JOIN companies co ON co.id = t.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation' AND t.is_active) AS payment_terms,
  (SELECT count(*) FROM customers c JOIN companies co ON co.id = c.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation' AND c.is_active) AS customers,
  (SELECT count(*) FROM suppliers s JOIN companies co ON co.id = s.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation' AND s.is_active) AS suppliers;
