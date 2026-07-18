-- High-volume canonical demo fixture validation.
-- Run after canonical_demo_volume.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT EXISTS (
  SELECT 1 FROM sales_invoices WHERE reference = 'VOL-SI-001'
) AS volume_loaded \gset

SELECT plan(16);

\if :volume_loaded

SELECT is(
  (SELECT count(*)::integer FROM customers cu JOIN companies c ON c.id = cu.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND cu.customer_code LIKE 'CUST-BULK-%'),
  40,
  'volume seed creates forty additional customers'
);

SELECT is(
  (SELECT count(*)::integer FROM suppliers s JOIN companies c ON c.id = s.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND s.supplier_code LIKE 'SUP-BULK-%'),
  30,
  'volume seed creates thirty additional suppliers'
);

SELECT is(
  (SELECT count(*)::integer FROM items i JOIN companies c ON c.id = i.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND i.item_code LIKE 'ITEM-BULK-STOCK-%'),
  12,
  'volume seed creates twelve purchase-ready inventory items'
);

SELECT is(
  (SELECT count(*)::integer FROM items i JOIN companies c ON c.id = i.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND i.item_code LIKE 'ITEM-BULK-SVC-%'),
  12,
  'volume seed creates twelve invoice-ready service items'
);

SELECT is(
  (SELECT count(*)::integer FROM sales_invoices si JOIN companies c ON c.id = si.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND si.reference LIKE 'VOL-SI-%'),
  60,
  'volume seed creates sixty sales invoices'
);

SELECT is(
  (SELECT count(*)::integer FROM sales_invoices si JOIN companies c ON c.id = si.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND si.reference LIKE 'VOL-SI-%' AND si.status = 'draft'),
  60,
  'all volume sales invoices remain editable drafts'
);

SELECT is(
  (SELECT count(*)::integer FROM sales_invoice_lines sil
   JOIN sales_invoices si ON si.id = sil.sales_invoice_id
   JOIN companies c ON c.id = si.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND si.reference LIKE 'VOL-SI-%'),
  120,
  'each volume sales invoice has two computed lines'
);

SELECT is(
  (SELECT count(*)::integer FROM sales_invoices si JOIN companies c ON c.id = si.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND si.reference LIKE 'VOL-SI-%'
     AND (si.fiscal_period_id IS NULL OR si.total_amount <= 0)),
  0,
  'volume sales invoices have valid periods and positive totals'
);

SELECT is(
  (SELECT count(DISTINCT b.branch_code)::integer
   FROM sales_invoices si JOIN branches b ON b.id = si.branch_id
   JOIN companies c ON c.id = si.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND si.reference LIKE 'VOL-SI-%'),
  3,
  'volume sales invoices exercise all three ABC branches'
);

SELECT is(
  (SELECT count(*)::integer FROM purchase_orders po JOIN companies c ON c.id = po.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND po.notes LIKE 'VOL-PO-%' AND po.status = 'draft'),
  30,
  'volume seed creates thirty editable purchase orders'
);

SELECT is(
  (SELECT count(*)::integer FROM purchase_order_lines pol
   JOIN purchase_orders po ON po.id = pol.po_id
   JOIN companies c ON c.id = po.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND po.notes LIKE 'VOL-PO-%'),
  30,
  'each volume purchase order has a purchase-ready line'
);

SELECT is(
  (SELECT count(*)::integer FROM vendor_bills vb JOIN companies c ON c.id = vb.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND vb.reference LIKE 'VOL-VB-%' AND vb.status = 'draft'),
  30,
  'volume seed creates thirty editable vendor bills'
);

SELECT is(
  (SELECT count(*)::integer FROM vendor_bill_lines vbl
   JOIN vendor_bills vb ON vb.id = vbl.vendor_bill_id
   JOIN companies c ON c.id = vb.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND vb.reference LIKE 'VOL-VB-%'),
  30,
  'each volume vendor bill has a computed expense line'
);

SELECT is(
  (SELECT count(*)::integer FROM vendor_bills vb JOIN companies c ON c.id = vb.company_id
   WHERE c.trade_name = 'DEMO-CORP-VAT' AND vb.reference LIKE 'VOL-VB-%'
     AND (vb.fiscal_period_id IS NULL OR vb.total_amount <= 0)),
  0,
  'volume vendor bills have valid periods and positive totals'
);

SELECT is(
  (SELECT count(*)::integer
   FROM (SELECT reference FROM sales_invoices si JOIN companies c ON c.id = si.company_id
         WHERE c.trade_name = 'DEMO-CORP-VAT' AND reference LIKE 'VOL-SI-%'
         GROUP BY reference HAVING count(*) > 1) duplicates),
  0,
  'volume sales invoice references are idempotent'
);

SELECT is(
  (SELECT count(*)::integer FROM companies c
   WHERE c.trade_name = 'DEMO-CORP-VAT'
     AND EXISTS (SELECT 1 FROM company_accounting_config cfg WHERE cfg.company_id = c.id)
     AND EXISTS (SELECT 1 FROM compliance_profiles cp WHERE cp.company_id = c.id)
     AND (SELECT count(*) FROM branches b WHERE b.company_id = c.id) = 3),
  1,
  'the high-volume company remains accounting, compliance, and branch ready'
);

\else

SELECT skip(16, 'high-volume seed not loaded; run canonical_demo_volume.sql first');

\endif

SELECT * FROM finish();
ROLLBACK;
