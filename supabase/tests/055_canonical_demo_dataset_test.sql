-- PXL canonical demo dataset regression coverage.
-- Verifies the canonical seed creates the expected non-production demo fixture
-- and that critical inventory/accounting/tax invariants hold.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT EXISTS (
  SELECT 1 FROM companies WHERE trade_name = 'DEMO-CORP-VAT'
) AS seed_loaded \gset

SELECT plan(34);

\if :seed_loaded

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

SELECT is(
  (SELECT COUNT(*)::integer FROM companies WHERE trade_name LIKE 'DEMO-%'),
  5,
  'canonical seed creates five demo companies'
);

SELECT results_eq(
  $$SELECT trade_name, entity_type, tax_registration
    FROM companies
    WHERE trade_name LIKE 'DEMO-%'
    ORDER BY trade_name$$,
  $$VALUES
      ('DEMO-CORP-VAT'::text, 'corporation'::text, 'vat'::text),
      ('DEMO-OPC-NONVAT'::text, 'opc'::text, 'non_vat'::text),
      ('DEMO-PARTNERSHIP-VAT'::text, 'partnership'::text, 'vat'::text),
      ('DEMO-SP-NONVAT'::text, 'sole_proprietor'::text, 'non_vat'::text),
      ('DEMO-SVC-VAT'::text, 'corporation'::text, 'vat'::text)$$,
  'demo companies cover the supported entity and taxpayer profiles'
);

SELECT results_eq(
  $$SELECT
      (SELECT COUNT(*)::integer FROM branches b JOIN companies c ON c.id = b.company_id WHERE c.trade_name = 'DEMO-CORP-VAT') AS branches,
      (SELECT COUNT(*)::integer FROM departments d JOIN companies c ON c.id = d.company_id WHERE c.trade_name = 'DEMO-CORP-VAT') AS departments,
      (SELECT COUNT(*)::integer FROM cost_centers cc JOIN companies c ON c.id = cc.company_id WHERE c.trade_name = 'DEMO-CORP-VAT') AS cost_centers,
      (SELECT COUNT(*)::integer FROM warehouses w JOIN companies c ON c.id = w.company_id WHERE c.trade_name = 'DEMO-CORP-VAT') AS warehouses$$,
  $$VALUES (3, 5, 5, 3)$$,
  'primary VAT trading company has branch, department, cost-center, and warehouse setup'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM customers cu JOIN companies c ON c.id = cu.company_id WHERE c.trade_name = 'DEMO-CORP-VAT'),
  10,
  'primary VAT trading company has ten customer fixtures'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM suppliers s JOIN companies c ON c.id = s.company_id WHERE c.trade_name = 'DEMO-CORP-VAT'),
  10,
  'primary VAT trading company has ten supplier fixtures'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM items i JOIN companies c ON c.id = i.company_id WHERE c.trade_name = 'DEMO-CORP-VAT' AND i.item_type = 'inventory_item'),
  9,
  'primary VAT trading company has nine inventory stock item fixtures'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM items i JOIN companies c ON c.id = i.company_id WHERE c.trade_name = 'DEMO-CORP-VAT' AND i.item_type = 'service'),
  6,
  'primary VAT trading company has six service item fixtures'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM approval_workflows aw JOIN companies c ON c.id = aw.company_id WHERE c.trade_name = 'DEMO-CORP-VAT' AND aw.is_active),
  2,
  'primary VAT trading company has supported sales and purchasing approval workflow fixtures'
);

SELECT is(
  (
    SELECT COUNT(DISTINCT rdt.document_code)::integer
    FROM number_series ns
    JOIN ref_document_types rdt ON rdt.id = ns.document_type_id
    JOIN branches b ON b.id = ns.branch_id
    JOIN companies c ON c.id = ns.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND b.branch_code = 'HO'
      AND rdt.document_code IN ('SI','OR','VB','PV','PO','RR','SO','DR','CM','VC','JE')
  ),
  11,
  'primary VAT trading company has number series for core document types'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM sales_invoices si JOIN companies c ON c.id = si.company_id WHERE c.trade_name LIKE 'DEMO-%' AND si.status = 'posted'),
  6,
  'canonical seed creates six posted sales invoices across demo companies'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM sales_invoices si JOIN companies c ON c.id = si.company_id WHERE c.trade_name = 'DEMO-CORP-VAT' AND si.status = 'posted'),
  3,
  'primary VAT trading company has three posted sales invoice scenarios'
);

SELECT results_eq(
  $$SELECT si.vat_price_basis, sil.net_amount, sil.vat_amount, sil.total_amount
    FROM sales_invoices si
    JOIN sales_invoice_lines sil ON sil.sales_invoice_id = si.id
    JOIN companies c ON c.id = si.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND si.reference = 'TEST-SI-VAT-INCLUSIVE'
      AND sil.line_number = 1$$,
  $$VALUES ('inclusive'::text, 1000.00::numeric, 120.00::numeric, 1120.00::numeric)$$,
  'VAT-inclusive commercial price is persisted and recomputed to net/VAT/gross'
);

SELECT results_eq(
  $$SELECT si.vat_price_basis, sil.net_amount, sil.vat_amount, sil.total_amount
    FROM sales_invoices si
    JOIN sales_invoice_lines sil ON sil.sales_invoice_id = si.id
    JOIN companies c ON c.id = si.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND si.reference = 'TEST-SI-STANDALONE'
      AND sil.line_number = 1$$,
  $$VALUES ('exclusive'::text, 2000.00::numeric, 240.00::numeric, 2240.00::numeric)$$,
  'VAT-exclusive commercial price is persisted and recomputed to net/VAT/gross'
);

SELECT results_eq(
  $$SELECT cwt_amount_expected, cwt_tax_base
    FROM sales_invoices si
    JOIN companies c ON c.id = si.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND si.reference = 'TEST-SI-STANDALONE'$$,
  $$VALUES (40.00::numeric, 2000.00::numeric)$$,
  'Sales Invoice stores expected CWT without recognizing actual CWT yet'
);

SELECT is(
  (
    SELECT COUNT(*)::integer
    FROM tax_detail_entries t
    JOIN sales_invoices si ON si.id = t.source_doc_id
    JOIN companies c ON c.id = t.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND si.reference = 'TEST-SI-STANDALONE'
      AND t.source_doc_type = 'SI'
      AND t.tax_kind = 'cwt_receivable'
  ),
  0,
  'Sales Invoice does not recognize actual CWT in the tax ledger'
);

SELECT results_eq(
  $$SELECT rl.payment_amount, rl.cwt_amount, rl.cwt_tax_base
    FROM receipts r
    JOIN receipt_lines rl ON rl.receipt_id = r.id
    JOIN companies c ON c.id = r.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND r.reference_number = 'TEST-OR-SI-STANDALONE'$$,
  $$VALUES (2200.00::numeric, 40.00::numeric, 2000.00::numeric)$$,
  'Official Receipt recognizes actual CWT separately from invoice expectation'
);

SELECT results_eq(
  $$SELECT tax_kind, tax_base, tax_amount
    FROM tax_detail_entries t
    JOIN receipts r ON r.id = t.source_doc_id
    JOIN companies c ON c.id = t.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND r.reference_number = 'TEST-OR-SI-STANDALONE'
      AND t.source_doc_type = 'OR'$$,
  $$VALUES ('cwt_receivable'::text, 2000.00::numeric, 40.00::numeric)$$,
  'receipt CWT creates tax-detail evidence at collection time'
);

SELECT is(
  (SELECT COUNT(*)::integer FROM vendor_bills vb JOIN companies c ON c.id = vb.company_id WHERE c.trade_name = 'DEMO-CORP-VAT' AND vb.status = 'posted'),
  1,
  'primary VAT trading company has one posted vendor bill scenario'
);

SELECT results_eq(
  $$SELECT tax_kind, tax_base, tax_amount
    FROM tax_detail_entries t
    JOIN vendor_bills vb ON vb.id = t.source_doc_id
    JOIN companies c ON c.id = t.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND vb.reference = 'TEST-VB-PARTIAL-PAYMENT'
      AND t.source_doc_type = 'VB'
    ORDER BY tax_kind$$,
  $$VALUES
      ('ewt_payable'::text, 2400.00::numeric, 24.00::numeric),
      ('input_vat'::text, 2400.00::numeric, 288.00::numeric)$$,
  'posted vendor bill creates input VAT and EWT tax-detail evidence'
);

SELECT results_eq(
  $$SELECT pv.status, pv.total_amount, pv.total_ewt
    FROM payment_vouchers pv
    JOIN companies c ON c.id = pv.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND pv.reference_number = 'TEST-PV-PARTIAL'$$,
  $$VALUES ('posted'::text, 1000.00::numeric, 0.00::numeric)$$,
  'partial supplier payment voucher posts with the expected payment amount'
);

SELECT results_eq(
  $$SELECT po.status, pol.quantity, rr.status, rrl.received_qty
    FROM purchase_orders po
    JOIN purchase_order_lines pol ON pol.po_id = po.id
    JOIN receiving_reports rr ON rr.po_id = po.id
    JOIN receiving_report_lines rrl ON rrl.rr_id = rr.id
    JOIN companies c ON c.id = po.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND po.notes = 'TEST-PO-PARTIAL-RECEIPT'$$,
  $$VALUES ('partially_received'::text, 20.0000::numeric, 'received'::text, 12.0000::numeric)$$,
  'purchase chain fixture keeps a partial receipt against the approved PO'
);

SELECT results_eq(
  $$SELECT w.warehouse_code, i.item_code, sb.qty_on_hand, sb.total_cost, sb.wac_unit_cost
    FROM stock_balances sb
    JOIN warehouses w ON w.id = sb.warehouse_id
    JOIN items i ON i.id = sb.item_id
    JOIN companies c ON c.id = sb.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND w.warehouse_code IN ('WH-MAIN','WH-CEBU')
      AND i.item_code IN ('ITEM-STOCK-001','ITEM-STOCK-003')
    ORDER BY w.warehouse_code, i.item_code$$,
  $$VALUES
      ('WH-CEBU'::text, 'ITEM-STOCK-001'::text, 30.0000::numeric, 6000.00::numeric, 200.000000::numeric),
      ('WH-CEBU'::text, 'ITEM-STOCK-003'::text, 10.0000::numeric, 450.00::numeric, 45.000000::numeric),
      ('WH-MAIN'::text, 'ITEM-STOCK-001'::text, 107.0000::numeric, 21400.00::numeric, 200.000000::numeric),
      ('WH-MAIN'::text, 'ITEM-STOCK-003'::text, 53.0000::numeric, 2385.00::numeric, 45.000000::numeric)$$,
  'warehouse-level stock balances reconcile after opening stock, sale, receipt, transfer, and adjustments'
);

SELECT is(
  (
    SELECT COUNT(*)::integer
    FROM stock_balances sb
    JOIN companies c ON c.id = sb.company_id
    WHERE c.trade_name LIKE 'DEMO-%'
      AND sb.qty_on_hand < 0
  ),
  0,
  'canonical seed leaves no negative warehouse stock balances'
);

SELECT results_eq(
  $$SELECT it.transaction_type, it.qty, it.unit_cost, it.total_cost
    FROM inventory_transactions it
    JOIN stock_transfers st ON st.id = it.reference_doc_id
    JOIN companies c ON c.id = it.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND st.transfer_number = 'TEST-INV-TRANSFER-OK'
    ORDER BY it.transaction_type$$,
  $$VALUES
      ('transfer_in'::text, 10.0000::numeric, 45.000000::numeric, 450.00::numeric),
      ('transfer_out'::text, -10.0000::numeric, 45.000000::numeric, -450.00::numeric)$$,
  'valid warehouse transfer creates balanced transfer-in and transfer-out inventory movements'
);

SELECT is(
  (
    SELECT COUNT(*)::integer
    FROM journal_entries je
    JOIN companies c ON c.id = je.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND je.status = 'posted'
      AND ROUND(je.total_debit - je.total_credit, 2) <> 0
  ),
  0,
  'all posted journals in the primary VAT trading company are balanced at header level'
);

SELECT is(
  (
    SELECT COUNT(*)::integer
    FROM (
      SELECT je.id, ROUND(SUM(jel.debit_amount - jel.credit_amount), 2) AS balance
      FROM journal_entries je
      JOIN journal_entry_lines jel ON jel.je_id = je.id
      JOIN companies c ON c.id = je.company_id
      WHERE c.trade_name = 'DEMO-CORP-VAT'
      GROUP BY je.id
    ) x
    WHERE x.balance <> 0
  ),
  0,
  'all posted journals in the primary VAT trading company are balanced at line level'
);

SELECT results_eq(
  $$SELECT reference_doc_type, COUNT(*)::integer, ROUND(SUM(total_debit - total_credit), 2)
    FROM journal_entries je
    JOIN companies c ON c.id = je.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
    GROUP BY reference_doc_type
    ORDER BY reference_doc_type$$,
  $$VALUES
      ('INV_ADJ'::text, 2, 0.00::numeric),
      ('MANUAL'::text, 1, 0.00::numeric),
      ('OR'::text, 1, 0.00::numeric),
      ('PV'::text, 1, 0.00::numeric),
      ('SI'::text, 3, 0.00::numeric),
      ('VB'::text, 1, 0.00::numeric)$$,
  'journal source counts match the posted canonical transaction set'
);

SELECT is(
  (
    SELECT ROUND(SUM(jel.debit_amount - jel.credit_amount), 2)
    FROM journal_entries je
    JOIN journal_entry_lines jel ON jel.je_id = je.id
    JOIN companies c ON c.id = je.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
  ),
  0.00::numeric,
  'primary VAT trading company trial-balance delta is zero'
);

SELECT results_eq(
  $$SELECT approval_status, fulfillment_status
    FROM sales_orders so
    JOIN companies c ON c.id = so.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND so.reference_number = 'TEST-SO-OPEN-PARTIAL'$$,
  $$VALUES ('approved'::text, 'partial'::text)$$,
  'open sales order assistance fixture retains partially fulfilled status'
);

SELECT results_eq(
  $$SELECT quantity, fulfilled_quantity, quantity - fulfilled_quantity AS remaining_quantity
    FROM sales_order_lines sol
    JOIN sales_orders so ON so.id = sol.sales_order_id
    JOIN companies c ON c.id = sol.company_id
    WHERE c.trade_name = 'DEMO-CORP-VAT'
      AND so.reference_number = 'TEST-SO-OPEN-PARTIAL'$$,
  $$VALUES (10.0000::numeric, 6.0000::numeric, 4.0000::numeric)$$,
  'partial sales order line exposes four remaining units'
);

CREATE TEMP TABLE t_transfer_block AS
WITH ctx AS (
  SELECT c.id AS company_id, wh_from.id AS from_warehouse_id,
         wh_to.id AS to_warehouse_id, i.id AS item_id
  FROM companies c
  JOIN warehouses wh_from ON wh_from.company_id = c.id AND wh_from.warehouse_code = 'WH-CEBU'
  JOIN warehouses wh_to ON wh_to.company_id = c.id AND wh_to.warehouse_code = 'WH-MAIN'
  JOIN items i ON i.company_id = c.id AND i.item_code = 'ITEM-STOCK-003'
  WHERE c.trade_name = 'DEMO-CORP-VAT'
),
ins AS (
  INSERT INTO stock_transfers (
    company_id, transfer_number, transfer_date,
    from_warehouse_id, to_warehouse_id, notes, created_by, updated_by
  )
  SELECT
    company_id, 'TEST-INV-TRANSFER-BLOCK', DATE '2026-01-30',
    from_warehouse_id, to_warehouse_id, 'Invalid transfer exceeds source warehouse stock',
    auth.uid(), auth.uid()
  FROM ctx
  RETURNING id AS transfer_id, company_id, from_warehouse_id, to_warehouse_id
)
SELECT ins.transfer_id, ins.company_id, ins.from_warehouse_id, ins.to_warehouse_id, ctx.item_id
FROM ins
JOIN ctx ON ctx.company_id = ins.company_id;

INSERT INTO stock_transfer_lines (transfer_id, company_id, item_id, qty_transferred)
SELECT transfer_id, company_id, item_id, 11
FROM t_transfer_block;

SELECT throws_like(
  format('SELECT fn_post_stock_transfer(%L)', (SELECT transfer_id FROM t_transfer_block)),
  '%Insufficient stock for transfer item%',
  'stock transfer exceeding source warehouse stock is blocked server-side'
);

SELECT results_eq(
  $$SELECT sb.qty_on_hand, sb.total_cost
    FROM stock_balances sb
    JOIN t_transfer_block b
      ON b.from_warehouse_id = sb.warehouse_id
     AND b.item_id = sb.item_id$$,
  $$VALUES (10.0000::numeric, 450.00::numeric)$$,
  'blocked transfer leaves source warehouse quantity and value unchanged'
);

CREATE TEMP TABLE t_si_oversell AS
SELECT fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', c.id,
    'branch_id', b.id,
    'customer_id', cu.id,
    'customer_name_snapshot', cu.registered_name,
    'customer_tin_snapshot', cu.tin,
    'customer_address_snapshot', cu.registered_address,
    'payment_terms_id', cu.default_terms_id,
    'date', '2026-01-31',
    'due_date', '2026-02-15',
    'reference', 'TEST-INV-OVERSELL-BLOCK',
    'memo', 'Invalid SI exceeds warehouse stock',
    'vat_price_basis', 'exclusive',
    'warehouse_id', wh.id
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id', i.id,
    'description', 'Oversell Bond Paper A4',
    'quantity', 999,
    'uom_id', i.uom_id,
    'unit_price', 280,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', i.sales_account_id,
    'warehouse_id', wh.id,
    'inventory_account_id', i.inventory_account_id,
    'cogs_account_id', i.cogs_account_id
  ))
) AS invoice_id
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.branch_code = 'HO'
JOIN customers cu ON cu.company_id = c.id AND cu.customer_code = 'CUST-VAT-CREDIT'
JOIN warehouses wh ON wh.company_id = c.id AND wh.warehouse_code = 'WH-CEBU'
JOIN items i ON i.company_id = c.id AND i.item_code = 'ITEM-STOCK-001'
WHERE c.trade_name = 'DEMO-CORP-VAT';

SELECT throws_like(
  format('SELECT fn_approve_sales_invoice(%L)', (SELECT invoice_id FROM t_si_oversell)),
  '%Insufficient stock%',
  'sales invoice approval blocks inventory oversell at warehouse level'
);

SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT invoice_id FROM t_si_oversell)),
  'draft',
  'blocked oversell invoice remains draft and unposted after failed approval readiness check'
);

\else

SELECT skip(34, 'canonical demo seed not loaded; run canonical_demo_reset.sql and canonical_demo_seed.sql before this regression file');

\endif

SELECT * FROM finish();
ROLLBACK;
