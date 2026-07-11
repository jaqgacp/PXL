-- =============================================================================
-- PXL DEMO/TEST operational master data seed — items, warehouses, banks,
-- petty cash, fixed-asset categories, employees
-- =============================================================================
-- Runs AFTER demo_company_setup_seed.sql (needs the demo company + COA).
-- Master data only: NO transactions, NO stock balances (stock must come from
-- posting receiving/adjustment documents so inventory integrity holds).
--
-- Properties: idempotent (stable codes + ON CONFLICT/NOT EXISTS), never
-- deletes or overwrites existing data, reuses existing reference records.
--
-- Run (local):  docker exec -i supabase_db_PXL psql -U postgres -d postgres \
--                 < supabase/seeds/demo_items_inventory_seed.sql
-- Run (hosted): execute contents via the Supabase management API SQL endpoint.
-- =============================================================================

DO $$
DECLARE
  v_company uuid;
  v_branch  uuid;
  v_user    uuid;
  v_php     uuid;
  v_fin     uuid;
BEGIN
  SELECT id INTO v_company FROM companies
  WHERE registered_name = 'PXL Demo Trading Corporation';
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Demo company not found - run demo_company_setup_seed.sql first';
  END IF;

  SELECT id INTO v_branch FROM branches WHERE company_id = v_company AND branch_code = 'HO';
  SELECT user_id INTO v_user FROM user_company_memberships WHERE company_id = v_company LIMIT 1;
  SELECT id INTO v_php FROM currencies WHERE currency_code = 'PHP';
  SELECT id INTO v_fin FROM departments WHERE company_id = v_company AND department_code = 'FIN';

  -- ---------------------------------------------------------------------------
  -- COA additions for fixed-asset lifecycle (gain/loss/impairment were missing)
  -- ---------------------------------------------------------------------------
  INSERT INTO chart_of_accounts (company_id, account_code, account_name,
    account_type, normal_balance, is_postable, is_active, created_by)
  SELECT v_company, x.code, x.name, x.typ, x.nb, true, true, v_user
  FROM (VALUES
    ('4220-00', 'Gain on Disposal of Assets', 'revenue', 'credit'),
    ('6170-00', 'Loss on Disposal of Assets', 'expense', 'debit'),
    ('6180-00', 'Impairment Loss',            'expense', 'debit')
  ) AS x(code, name, typ, nb)
  ON CONFLICT (company_id, account_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Units of measure
  -- ---------------------------------------------------------------------------
  INSERT INTO units_of_measure (company_id, uom_code, description, is_base_unit,
    is_active, created_by)
  SELECT v_company, x.code, x.descr, true, true, v_user
  FROM (VALUES
    ('PC',   'Piece'),
    ('REAM', 'Ream (500 sheets)'),
    ('HR',   'Hour'),
    ('UNIT', 'Unit')
  ) AS x(code, descr)
  ON CONFLICT (company_id, uom_code) DO NOTHING;

  INSERT INTO units_of_measure (company_id, uom_code, description, is_base_unit,
    base_uom_id, conversion_factor, is_active, created_by)
  SELECT v_company, 'BOX', 'Box of 12 pieces', false,
    (SELECT id FROM units_of_measure WHERE company_id = v_company AND uom_code = 'PC'),
    12, true, v_user
  ON CONFLICT (company_id, uom_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Item categories with GL defaults
  -- ---------------------------------------------------------------------------
  INSERT INTO item_categories (company_id, category_code, category_name,
    description, sales_account_id, cogs_account_id, inventory_account_id,
    adj_account_id, is_active, created_by)
  SELECT v_company, x.code, x.name, x.descr || ' (TEST seed)',
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.sales),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.cogs),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.inv),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.adj),
    true, v_user
  FROM (VALUES
    ('MERCH-OFF', 'Office Supplies Merchandise', 'Office supplies for resale',
     '4000-00', '5000-00', '1200-00', '9020-00'),
    ('MERCH-FNB', 'Food and Beverage Merchandise', 'Food and beverage for resale',
     '4000-00', '5000-00', '1200-00', '9020-00'),
    ('MERCH-HW',  'Hardware Merchandise', 'Hardware and tools for resale',
     '4000-00', '5000-00', '1200-00', '9020-00'),
    ('SVC',       'Services', 'Service offerings',
     '4010-00', NULL, NULL, NULL)
  ) AS x(code, name, descr, sales, cogs, inv, adj)
  ON CONFLICT (company_id, category_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Items: 7 inventory + 2 services + 1 non-inventory
  -- ---------------------------------------------------------------------------
  INSERT INTO items (company_id, item_code, description, description_long,
    item_type, category_id, uom_id, standard_selling_price, standard_cost,
    price_is_vat_inclusive, default_sales_vat_id, default_purchase_vat_id,
    sales_account_id, cogs_account_id, inventory_account_id,
    purchase_expense_account_id, costing_method, min_stock_level,
    reorder_point, is_active, created_by)
  SELECT v_company, x.code, x.descr, x.descr || ' (TEST seed)',
    x.typ,
    (SELECT id FROM item_categories WHERE company_id = v_company AND category_code = x.cat),
    (SELECT id FROM units_of_measure WHERE company_id = v_company AND uom_code = x.uom),
    x.sell, x.cost, false,
    CASE WHEN x.sell > 0 THEN (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12') END,
    CASE WHEN x.cost > 0 THEN (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12') END,
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.sales_acct),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.cogs_acct),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.inv_acct),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.exp_acct),
    x.costing, x.min_lvl, x.reorder, true, v_user
  FROM (VALUES
    ('ITEM-0001', 'Bond Paper A4 80gsm',          'inventory_item', 'MERCH-OFF', 'REAM', 285.00,  210.00, '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 20::numeric,  40::numeric),
    ('ITEM-0002', 'Ballpen Black 0.5mm',          'inventory_item', 'MERCH-OFF', 'PC',   15.00,   8.00,   '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 100, 200),
    ('ITEM-0003', 'Ink Cartridge 682 Black',      'inventory_item', 'MERCH-OFF', 'PC',   1250.00, 900.00, '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 10,  20),
    ('ITEM-0004', 'Instant Coffee 3-in-1 (48s)',  'inventory_item', 'MERCH-FNB', 'BOX',  480.00,  360.00, '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 15,  30),
    ('ITEM-0005', 'Purified Water 500ml (24s)',   'inventory_item', 'MERCH-FNB', 'BOX',  350.00,  240.00, '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 20,  50),
    ('ITEM-0006', 'Claw Hammer 16oz',             'inventory_item', 'MERCH-HW',  'PC',   420.00,  300.00, '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 5,   10),
    ('ITEM-0007', 'Electrical Tape 19mm',         'inventory_item', 'MERCH-HW',  'PC',   65.00,   40.00,  '4000-00', '5000-00', '1200-00', NULL,      'weighted_average', 30,  60),
    ('SVC-0001',  'Delivery Service',             'service',        'SVC',       'HR',   500.00,  0.00,   '4020-00', NULL,      NULL,      NULL,      NULL,               NULL, NULL),
    ('SVC-0002',  'Installation Service',         'service',        'SVC',       'HR',   800.00,  0.00,   '4010-00', NULL,      NULL,      NULL,      NULL,               NULL, NULL),
    ('NON-0001',  'Packaging Materials',          'non_inventory',  'MERCH-OFF', 'PC',   0.00,    25.00,  NULL,      NULL,      NULL,      '6050-00', NULL,               NULL, NULL)
  ) AS x(code, descr, typ, cat, uom, sell, cost, sales_acct, cogs_acct,
         inv_acct, exp_acct, costing, min_lvl, reorder)
  ON CONFLICT (company_id, item_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Warehouses
  -- ---------------------------------------------------------------------------
  INSERT INTO warehouses (company_id, branch_id, warehouse_code, warehouse_name,
    warehouse_type, address, gl_inventory_account_id, gl_variance_account_id,
    is_active, created_by)
  SELECT v_company, v_branch, x.code, x.name, x.typ,
    'Unit 1201, One Ayala Tower, Ayala Avenue, Makati City (TEST seed)',
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.inv),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '5020-00'),
    true, v_user
  FROM (VALUES
    ('WH-MAIN',    'Main Warehouse',    'main',    '1200-00'),
    ('WH-TRANSIT', 'Transit Warehouse', 'transit', '1210-00')
  ) AS x(code, name, typ, inv)
  ON CONFLICT (company_id, warehouse_code) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Bank accounts (opening_balance 0 so GL stays consistent; balances must
  -- come from posted documents)
  -- ---------------------------------------------------------------------------
  INSERT INTO bank_accounts (company_id, branch_id, bank_name, bank_branch,
    account_number, account_name, account_type, currency_id, gl_account_id,
    is_primary, is_active, opening_balance, notes, created_by)
  SELECT v_company, v_branch, x.bank, x.bbranch, x.acct_no,
    'PXL Demo Trading Corporation', x.acct_type, v_php,
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.gl),
    x.is_primary, true, 0, 'TEST seed - sample bank account', v_user
  FROM (VALUES
    ('BPI', 'Makati Main',   '1234-5678-90',  'checking', '1030-00', true),
    ('BDO', 'Ayala Triangle','0045-6789-012', 'savings',  '1040-00', false)
  ) AS x(bank, bbranch, acct_no, acct_type, gl, is_primary)
  ON CONFLICT (company_id, bank_name, account_number) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Employees (custodian/payee realism; no payroll data)
  -- ---------------------------------------------------------------------------
  INSERT INTO employees (company_id, branch_id, employee_number, last_name,
    first_name, department_id, job_title, employment_type, hire_date,
    email, is_active, notes, created_by)
  SELECT v_company, v_branch, x.no, x.lname, x.fname, v_fin, x.title,
    'regular', DATE '2026-01-05', x.email, true, 'TEST seed employee', v_user
  FROM (VALUES
    ('EMP-0001', 'Lim',       'Grace', 'Accounting Supervisor', 'grace.lim@pxldemo.ph'),
    ('EMP-0002', 'Torres',    'Ramil', 'Warehouse Officer',     'ramil.torres@pxldemo.ph'),
    ('EMP-0003', 'Dela Cruz', 'Ana',   'Admin Assistant',       'ana.delacruz@pxldemo.ph')
  ) AS x(no, lname, fname, title, email)
  ON CONFLICT (company_id, employee_number) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Petty cash fund
  -- ---------------------------------------------------------------------------
  INSERT INTO petty_cash_funds (company_id, branch_id, fund_name, custodian_name,
    authorized_amount, replenishment_threshold, gl_account_id, is_active, created_by)
  SELECT v_company, v_branch, 'Head Office Petty Cash', 'Grace Lim',
    10000.00, 3000.00,
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1020-00'),
    true, v_user
  ON CONFLICT (company_id, fund_name) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Fixed asset categories
  -- ---------------------------------------------------------------------------
  INSERT INTO fixed_asset_categories (company_id, category_code, category_name,
    depreciation_method, useful_life_months, salvage_rate,
    gl_asset_account_id, gl_accum_depr_account_id, gl_depr_expense_account_id,
    gl_gain_on_disposal_account_id, gl_loss_on_disposal_account_id,
    gl_impairment_loss_account_id, is_active, created_by)
  SELECT v_company, x.code, x.name, 'straight_line', x.life, 0.05,
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = x.asset),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1590-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6120-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4220-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6170-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6180-00'),
    true, v_user
  FROM (VALUES
    ('OFFEQ', 'Office Equipment',       60, '1500-00'),
    ('FURN',  'Furniture and Fixtures', 84, '1510-00')
  ) AS x(code, name, life, asset)
  ON CONFLICT (company_id, category_code) DO NOTHING;

  RAISE NOTICE 'Demo items/inventory master data seed complete for company %', v_company;
END $$;

-- Post-seed summary (safe to run standalone)
WITH co AS (SELECT id FROM companies WHERE registered_name = 'PXL Demo Trading Corporation')
SELECT
  (SELECT count(*) FROM units_of_measure u, co WHERE u.company_id = co.id AND u.is_active) AS uoms,
  (SELECT count(*) FROM item_categories i, co WHERE i.company_id = co.id AND i.is_active) AS item_categories,
  (SELECT count(*) FROM items i, co WHERE i.company_id = co.id AND i.is_active) AS items,
  (SELECT count(*) FROM warehouses w, co WHERE w.company_id = co.id AND w.is_active) AS warehouses,
  (SELECT count(*) FROM bank_accounts b, co WHERE b.company_id = co.id AND b.is_active) AS bank_accounts,
  (SELECT count(*) FROM employees e, co WHERE e.company_id = co.id AND e.is_active) AS employees,
  (SELECT count(*) FROM petty_cash_funds p, co WHERE p.company_id = co.id AND p.is_active) AS petty_cash_funds,
  (SELECT count(*) FROM fixed_asset_categories f, co WHERE f.company_id = co.id AND f.is_active) AS fa_categories;
