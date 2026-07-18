-- =============================================================================
-- PXL canonical demo high-volume operational fixtures
-- =============================================================================
--
-- Run after canonical_demo_seed.sql and canonical_phase3_enrichment.sql.
-- Adds list-scale master data and editable draft transactions to the primary
-- VAT trading company without changing the governed posted regression cases.
-- The script is idempotent by stable business codes and references.
-- =============================================================================

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  false
);

-- Forty additional active customers for search, pagination, and transaction
-- entry. They deliberately do not default to CWT so draft invoices can be
-- continued without first entering withholding details.
INSERT INTO customers (
  company_id, customer_code, customer_group, registered_name, trade_name,
  business_style, tin, tin_branch_code, default_tax_type,
  registered_address, delivery_address, contact_person, email, phone_number,
  default_terms_id, default_currency_id, default_gl_account_id, credit_limit,
  is_subject_to_cwt, default_cwt_atc_code_id, is_active, created_by, updated_by
)
SELECT
  c.id,
  'CUST-BULK-' || lpad(g::text, 3, '0'),
  CASE g % 4
    WHEN 0 THEN 'distribution'
    WHEN 1 THEN 'corporate'
    WHEN 2 THEN 'retail'
    ELSE 'services'
  END,
  'Sample Customer ' || lpad(g::text, 3, '0') || ' Corporation',
  'Sample Customer ' || lpad(g::text, 3, '0'),
  'High-volume canonical sample customer',
  '910-' || lpad(g::text, 3, '0') || '-' || lpad((g + 100)::text, 3, '0') || '-00000',
  '00000',
  CASE WHEN g % 5 = 0 THEN 'non_vat' ELSE 'vat_registered' END,
  (100 + g)::text || ' Sample Commerce Street, Metro Manila',
  (200 + g)::text || ' Sample Delivery Avenue, Metro Manila',
  'Customer Contact ' || lpad(g::text, 3, '0'),
  'customer' || lpad(g::text, 3, '0') || '@sample.pxl.local',
  '0284' || lpad(g::text, 7, '0'),
  (SELECT id FROM payment_terms WHERE company_id = c.id AND term_code = CASE WHEN g % 4 = 0 THEN 'NET15' ELSE 'NET30' END),
  (SELECT id FROM currencies WHERE currency_code = 'PHP'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1100'),
  100000 + (g * 10000),
  false,
  NULL,
  true,
  auth.uid(),
  auth.uid()
FROM companies c
CROSS JOIN generate_series(1, 40) AS g
WHERE c.trade_name = 'DEMO-CORP-VAT'
ON CONFLICT (company_id, customer_code) DO UPDATE SET
  registered_name = EXCLUDED.registered_name,
  trade_name = EXCLUDED.trade_name,
  credit_limit = EXCLUDED.credit_limit,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

-- Thirty additional active suppliers without EWT defaults. Governed EWT
-- scenarios remain in the base canonical seed, while these records are simple
-- starting points for new purchase orders and vendor bills.
INSERT INTO suppliers (
  company_id, supplier_code, supplier_group, registered_name, trade_name,
  business_style, tin, default_tax_type, registered_address, contact_person,
  email, phone_number, default_terms_id, default_currency_id,
  default_gl_account_id, is_subject_to_ewt, default_atc_code_id,
  is_active, created_by, updated_by
)
SELECT
  c.id,
  'SUP-BULK-' || lpad(g::text, 3, '0'),
  CASE g % 4
    WHEN 0 THEN 'goods'
    WHEN 1 THEN 'services'
    WHEN 2 THEN 'logistics'
    ELSE 'office'
  END,
  'Sample Supplier ' || lpad(g::text, 3, '0') || ' Incorporated',
  'Sample Supplier ' || lpad(g::text, 3, '0'),
  'High-volume canonical sample supplier',
  '920-' || lpad(g::text, 3, '0') || '-' || lpad((g + 100)::text, 3, '0') || '-00000',
  CASE WHEN g % 6 = 0 THEN 'non_vat' ELSE 'vat_registered' END,
  (300 + g)::text || ' Sample Industrial Road, Metro Manila',
  'Supplier Contact ' || lpad(g::text, 3, '0'),
  'supplier' || lpad(g::text, 3, '0') || '@sample.pxl.local',
  '0285' || lpad(g::text, 7, '0'),
  (SELECT id FROM payment_terms WHERE company_id = c.id AND term_code = CASE WHEN g % 3 = 0 THEN 'NET15' ELSE 'NET30' END),
  (SELECT id FROM currencies WHERE currency_code = 'PHP'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = CASE WHEN g % 4 = 1 THEN '6030' ELSE '5010' END),
  false,
  NULL,
  true,
  auth.uid(),
  auth.uid()
FROM companies c
CROSS JOIN generate_series(1, 30) AS g
WHERE c.trade_name = 'DEMO-CORP-VAT'
ON CONFLICT (company_id, supplier_code) DO UPDATE SET
  registered_name = EXCLUDED.registered_name,
  trade_name = EXCLUDED.trade_name,
  default_gl_account_id = EXCLUDED.default_gl_account_id,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

-- Twelve inventory items ready for purchasing/receiving and twelve service
-- items ready for immediate invoicing.
INSERT INTO items (
  company_id, item_code, description, description_long, item_type,
  category_id, uom_id, standard_selling_price, standard_cost,
  price_is_vat_inclusive, default_sales_vat_id, default_purchase_vat_id,
  sales_account_id, cogs_account_id, inventory_account_id,
  purchase_expense_account_id, costing_method, min_stock_level,
  reorder_point, is_active, created_by, updated_by
)
SELECT
  c.id,
  'ITEM-BULK-STOCK-' || lpad(g::text, 3, '0'),
  'Sample Stock Item ' || lpad(g::text, 3, '0'),
  'High-volume inventory fixture ready for purchase and receipt',
  'inventory_item',
  (SELECT id FROM item_categories WHERE company_id = c.id AND category_code = 'MERCH'),
  (SELECT id FROM units_of_measure WHERE company_id = c.id AND uom_code = 'PC'),
  250 + (g * 35),
  150 + (g * 20),
  false,
  (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
  (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '4000'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '5000'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '1200'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '5010'),
  'weighted_average',
  10,
  20,
  true,
  auth.uid(),
  auth.uid()
FROM companies c
CROSS JOIN generate_series(1, 12) AS g
WHERE c.trade_name = 'DEMO-CORP-VAT'
ON CONFLICT (company_id, item_code) DO UPDATE SET
  description = EXCLUDED.description,
  standard_selling_price = EXCLUDED.standard_selling_price,
  standard_cost = EXCLUDED.standard_cost,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO warehouse_item_settings (
  company_id, warehouse_id, item_id, min_stock_level, max_stock_level,
  reorder_point, reorder_qty, lead_time_days, preferred_supplier_id,
  notes, created_by, updated_by
)
SELECT
  warehouse.company_id,
  warehouse.id,
  item.id,
  item.min_stock_level,
  item.reorder_point * 3,
  item.reorder_point,
  item.reorder_point * 2,
  7,
  (
    SELECT supplier.id
    FROM suppliers AS supplier
    WHERE supplier.company_id = warehouse.company_id
      AND supplier.supplier_code LIKE 'SUP-BULK-%'
      AND supplier.supplier_group = 'goods'
      AND supplier.is_active
    ORDER BY supplier.supplier_code
    LIMIT 1
  ),
  'High-volume canonical replenishment policy',
  auth.uid(),
  auth.uid()
FROM warehouses AS warehouse
JOIN companies AS company ON company.id = warehouse.company_id
JOIN items AS item
  ON item.company_id = warehouse.company_id
 AND item.item_code LIKE 'ITEM-BULK-STOCK-%'
 AND item.is_active
WHERE company.trade_name = 'DEMO-CORP-VAT'
ON CONFLICT (warehouse_id, item_id) DO UPDATE SET
  min_stock_level = EXCLUDED.min_stock_level,
  max_stock_level = EXCLUDED.max_stock_level,
  reorder_point = EXCLUDED.reorder_point,
  reorder_qty = EXCLUDED.reorder_qty,
  lead_time_days = EXCLUDED.lead_time_days,
  preferred_supplier_id = EXCLUDED.preferred_supplier_id,
  notes = EXCLUDED.notes,
  updated_by = auth.uid(),
  updated_at = now();

INSERT INTO items (
  company_id, item_code, description, description_long, item_type,
  category_id, uom_id, standard_selling_price, standard_cost,
  price_is_vat_inclusive, default_sales_vat_id, default_purchase_vat_id,
  sales_account_id, cogs_account_id, inventory_account_id,
  purchase_expense_account_id, costing_method, min_stock_level,
  reorder_point, is_active, created_by, updated_by
)
SELECT
  c.id,
  'ITEM-BULK-SVC-' || lpad(g::text, 3, '0'),
  'Sample Service Package ' || lpad(g::text, 3, '0'),
  'High-volume service fixture ready for invoicing',
  'service',
  (SELECT id FROM item_categories WHERE company_id = c.id AND category_code = 'SERVICE'),
  (SELECT id FROM units_of_measure WHERE company_id = c.id AND uom_code = 'JOB'),
  1000 + (g * 250),
  0,
  false,
  (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
  (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '4010'),
  NULL,
  NULL,
  (SELECT id FROM chart_of_accounts WHERE company_id = c.id AND account_code = '6030'),
  NULL,
  NULL,
  NULL,
  true,
  auth.uid(),
  auth.uid()
FROM companies c
CROSS JOIN generate_series(1, 12) AS g
WHERE c.trade_name = 'DEMO-CORP-VAT'
ON CONFLICT (company_id, item_code) DO UPDATE SET
  description = EXCLUDED.description,
  standard_selling_price = EXCLUDED.standard_selling_price,
  is_active = true,
  updated_by = auth.uid(),
  updated_at = now();

-- Sixty editable sales invoices, thirty purchase orders, and thirty vendor
-- bills. All remain draft by design so an operator can continue each workflow.
DO $volume_transactions$
DECLARE
  g INTEGER;
  v_company UUID;
  v_branch UUID;
  v_customer customers%ROWTYPE;
  v_supplier suppliers%ROWTYPE;
  v_item items%ROWTYPE;
  v_doc_date DATE;
BEGIN
  SELECT id INTO STRICT v_company
  FROM companies
  WHERE trade_name = 'DEMO-CORP-VAT';

  FOR g IN 1..60 LOOP
    IF NOT EXISTS (
      SELECT 1 FROM sales_invoices
      WHERE company_id = v_company
        AND reference = 'VOL-SI-' || lpad(g::text, 3, '0')
    ) THEN
      SELECT * INTO STRICT v_customer
      FROM customers
      WHERE company_id = v_company
        AND customer_code = 'CUST-BULK-' || lpad((((g - 1) % 40) + 1)::text, 3, '0');

      SELECT id INTO STRICT v_branch
      FROM branches
      WHERE company_id = v_company
      ORDER BY branch_code
      OFFSET ((g - 1) % 3)
      LIMIT 1;

      SELECT * INTO STRICT v_item
      FROM items
      WHERE company_id = v_company
        AND item_code = 'ITEM-BULK-SVC-' || lpad((((g - 1) % 12) + 1)::text, 3, '0');

      -- Keep editable drafts after the canonical 2026-07-16 accounting
      -- evidence cutoff so historical AR/GL reconciliation stays unchanged.
      v_doc_date := DATE '2026-07-17' + ((g * 3) % 160);

      PERFORM fn_save_sales_invoice(
        NULL,
        jsonb_build_object(
          'company_id', v_company,
          'branch_id', v_branch,
          'date', v_doc_date,
          'customer_id', v_customer.id,
          'customer_name_snapshot', v_customer.registered_name,
          'customer_tin_snapshot', v_customer.tin,
          'customer_address_snapshot', v_customer.registered_address,
          'payment_terms_id', v_customer.default_terms_id,
          'due_date', v_doc_date + 30,
          'reference', 'VOL-SI-' || lpad(g::text, 3, '0'),
          'memo', 'Editable high-volume sample sales invoice',
          'vat_price_basis', CASE WHEN g % 4 = 0 THEN 'inclusive' ELSE 'exclusive' END
        ),
        jsonb_build_array(
          jsonb_build_object(
            'item_id', v_item.id,
            'description', v_item.description,
            'quantity', 1 + (g % 4),
            'unit_price', v_item.standard_selling_price,
            'vat_code_id', v_item.default_sales_vat_id,
            'revenue_account_id', v_item.sales_account_id
          ),
          jsonb_build_object(
            'item_id', (SELECT id FROM items WHERE company_id = v_company AND item_code = 'ITEM-SERVICE-004'),
            'description', 'Delivery and handling service',
            'quantity', 1,
            'unit_price', 500,
            'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
            'revenue_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '4020')
          )
        )
      );
    END IF;
  END LOOP;

  FOR g IN 1..30 LOOP
    IF NOT EXISTS (
      SELECT 1 FROM purchase_orders
      WHERE company_id = v_company
        AND notes = 'VOL-PO-' || lpad(g::text, 3, '0')
    ) THEN
      SELECT * INTO STRICT v_supplier
      FROM suppliers
      WHERE company_id = v_company
        AND supplier_code = 'SUP-BULK-' || lpad(g::text, 3, '0');

      SELECT id INTO STRICT v_branch
      FROM branches
      WHERE company_id = v_company
      ORDER BY branch_code
      OFFSET ((g - 1) % 3)
      LIMIT 1;

      SELECT * INTO STRICT v_item
      FROM items
      WHERE company_id = v_company
        AND item_code = 'ITEM-BULK-STOCK-' || lpad((((g - 1) % 12) + 1)::text, 3, '0');

      v_doc_date := DATE '2026-01-08' + ((g * 5) % 165);

      PERFORM fn_save_purchase_order(
        NULL,
        jsonb_build_object(
          'company_id', v_company,
          'branch_id', v_branch,
          'po_date', v_doc_date,
          'supplier_id', v_supplier.id,
          'supplier_name_snapshot', v_supplier.registered_name,
          'supplier_tin_snapshot', v_supplier.tin,
          'delivery_address', 'Receiving warehouse for ' || v_supplier.trade_name,
          'expected_date', v_doc_date + 10,
          'payment_terms_id', v_supplier.default_terms_id,
          'currency_code', 'PHP',
          'notes', 'VOL-PO-' || lpad(g::text, 3, '0')
        ),
        jsonb_build_array(
          jsonb_build_object(
            'item_id', v_item.id,
            'description', v_item.description,
            'quantity', 10 + (g % 15),
            'uom_id', v_item.uom_id,
            'unit_price', v_item.standard_cost
          )
        )
      );
    END IF;
  END LOOP;

  FOR g IN 1..30 LOOP
    IF NOT EXISTS (
      SELECT 1 FROM vendor_bills
      WHERE company_id = v_company
        AND reference = 'VOL-VB-' || lpad(g::text, 3, '0')
    ) THEN
      SELECT * INTO STRICT v_supplier
      FROM suppliers
      WHERE company_id = v_company
        AND supplier_code = 'SUP-BULK-' || lpad(g::text, 3, '0');

      SELECT id INTO STRICT v_branch
      FROM branches
      WHERE company_id = v_company
      ORDER BY branch_code
      OFFSET ((g - 1) % 3)
      LIMIT 1;

      SELECT * INTO STRICT v_item
      FROM items
      WHERE company_id = v_company
        AND item_code = 'ITEM-NONSTOCK-001';

      v_doc_date := DATE '2026-01-10' + ((g * 5) % 165);

      PERFORM fn_save_vendor_bill(
        NULL,
        jsonb_build_object(
          'company_id', v_company,
          'branch_id', v_branch,
          'supplier_id', v_supplier.id,
          'supplier_name_snapshot', v_supplier.registered_name,
          'supplier_tin_snapshot', v_supplier.tin,
          'supplier_invoice_number', 'SUP-VOL-' || lpad(g::text, 3, '0'),
          'bill_date', v_doc_date,
          'due_date', v_doc_date + 30,
          'payment_terms_id', v_supplier.default_terms_id,
          'currency_code', 'PHP',
          'reference', 'VOL-VB-' || lpad(g::text, 3, '0'),
          'memo', 'Editable high-volume sample vendor bill'
        ),
        jsonb_build_array(
          jsonb_build_object(
            'item_id', v_item.id,
            'description', 'Operating supplies from ' || v_supplier.trade_name,
            'quantity', 2 + (g % 8),
            'uom_id', v_item.uom_id,
            'unit_price', 250 + (g * 10),
            'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
            'expense_account_id', (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '6050')
          )
        )
      );
    END IF;
  END LOOP;
END
$volume_transactions$;

DO $volume_assertions$
DECLARE
  v_company UUID;
BEGIN
  SELECT id INTO STRICT v_company FROM companies WHERE trade_name = 'DEMO-CORP-VAT';

  IF (SELECT count(*) FROM customers WHERE company_id = v_company AND customer_code LIKE 'CUST-BULK-%') <> 40 THEN
    RAISE EXCEPTION 'Expected 40 high-volume customers';
  END IF;
  IF (SELECT count(*) FROM suppliers WHERE company_id = v_company AND supplier_code LIKE 'SUP-BULK-%') <> 30 THEN
    RAISE EXCEPTION 'Expected 30 high-volume suppliers';
  END IF;
  IF (SELECT count(*) FROM items WHERE company_id = v_company AND item_code LIKE 'ITEM-BULK-%') <> 24 THEN
    RAISE EXCEPTION 'Expected 24 high-volume items';
  END IF;
  IF (SELECT count(*) FROM sales_invoices WHERE company_id = v_company AND reference LIKE 'VOL-SI-%' AND status = 'draft') <> 60 THEN
    RAISE EXCEPTION 'Expected 60 editable high-volume sales invoices';
  END IF;
  IF (SELECT count(*) FROM purchase_orders WHERE company_id = v_company AND notes LIKE 'VOL-PO-%' AND status = 'draft') <> 30 THEN
    RAISE EXCEPTION 'Expected 30 editable high-volume purchase orders';
  END IF;
  IF (SELECT count(*) FROM vendor_bills WHERE company_id = v_company AND reference LIKE 'VOL-VB-%' AND status = 'draft') <> 30 THEN
    RAISE EXCEPTION 'Expected 30 editable high-volume vendor bills';
  END IF;
END
$volume_assertions$;
