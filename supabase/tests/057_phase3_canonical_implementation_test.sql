-- Phase 3 canonical-seeded deterministic lane.
-- Run after canonical_demo_seed.sql and canonical_phase3_enrichment.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT EXISTS (
  SELECT 1 FROM sales_invoices WHERE reference = 'P3-ABC-SI-LIFECYCLE'
) AS phase3_loaded \gset

SELECT plan(38);

\if :phase3_loaded

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

SELECT is(
  (SELECT count(*)::integer FROM companies WHERE trade_name LIKE 'DEMO-%'),
  5,
  'Phase 3 preserves exactly five canonical companies'
);

SELECT is(
  (SELECT count(*)::integer FROM companies WHERE trade_name LIKE 'DEMO-%'
    AND (rdo_id IS NULL OR registration_number IS NULL OR bir_reg_date IS NULL
      OR sec_dti_reg_date IS NULL OR lgu_reg_date IS NULL OR psic_code IS NULL)),
  0,
  'all canonical companies have complete legal registration profiles'
);

SELECT results_eq(
  $$SELECT c.trade_name, coa.account_name
    FROM companies c
    JOIN chart_of_accounts coa ON coa.company_id = c.id AND coa.account_code = '3000'
    WHERE c.trade_name LIKE 'DEMO-%'
    ORDER BY c.trade_name$$,
  $$VALUES
      ('DEMO-CORP-VAT'::text, 'Share Capital'::text),
      ('DEMO-OPC-NONVAT'::text, 'Single Stockholder''s Equity'::text),
      ('DEMO-PARTNERSHIP-VAT'::text, 'Partners'' Capital'::text),
      ('DEMO-SP-NONVAT'::text, 'Owner''s Capital'::text),
      ('DEMO-SVC-VAT'::text, 'Share Capital'::text)$$,
  'equity account labels match each legal form'
);

SELECT is(
  (SELECT count(*)::integer FROM atc_codes
    WHERE code = 'PT010' AND tax_category = 'pt' AND rate = 3
      AND is_active AND deprecated_at IS NULL),
  1,
  'global PT010 Section 116 reference is active at three percent'
);

SELECT is(
  (SELECT count(*)::integer
    FROM percentage_tax_codes pt
    JOIN companies c ON c.id = pt.company_id
    WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-OPC-NONVAT')
      AND pt.pt_code = 'PT-SEC116-3' AND pt.rate = 3 AND pt.is_active),
  2,
  'both non-VAT companies have company-specific percentage-tax setup'
);

SELECT is(
  (SELECT count(*)::integer FROM warehouses w JOIN companies c ON c.id = w.company_id
    WHERE c.trade_name = 'DEMO-PARTNERSHIP-VAT' AND w.warehouse_code = 'WH-BAYANI' AND w.is_active),
  1,
  'Bayani has its required mixed-business operating warehouse'
);

SELECT is(
  (SELECT count(*)::integer FROM companies c WHERE c.trade_name LIKE 'DEMO-%'
    AND (SELECT count(*) FROM customers x WHERE x.company_id = c.id) < 4),
  0,
  'every canonical company has at least four differentiated customers'
);

SELECT is(
  (SELECT count(*)::integer FROM companies c WHERE c.trade_name LIKE 'DEMO-%'
    AND (SELECT count(*) FROM suppliers x WHERE x.company_id = c.id) < 4),
  0,
  'every canonical company has at least four differentiated suppliers'
);

SELECT is(
  (SELECT count(*)::integer FROM companies c WHERE c.trade_name LIKE 'DEMO-%'
    AND NOT EXISTS (SELECT 1 FROM items i WHERE i.company_id = c.id AND i.is_active)
    OR c.trade_name LIKE 'DEMO-%'
    AND NOT EXISTS (SELECT 1 FROM items i WHERE i.company_id = c.id AND NOT i.is_active)),
  0,
  'every canonical company has active and inactive item/service fixtures'
);

SELECT is(
  (SELECT count(*)::integer FROM companies c WHERE c.trade_name LIKE 'DEMO-%'
    AND NOT EXISTS (SELECT 1 FROM employees e WHERE e.company_id = c.id AND e.is_active)),
  0,
  'every canonical company has active responsible employees'
);

SELECT is(
  (SELECT count(*)::integer
    FROM warehouses w
    JOIN companies c ON c.id = w.company_id
    JOIN items i ON i.company_id = w.company_id AND i.item_type = 'inventory_item' AND i.is_active
    LEFT JOIN warehouse_item_settings wis ON wis.warehouse_id = w.id AND wis.item_id = i.id
    WHERE c.trade_name IN ('DEMO-SP-NONVAT','DEMO-CORP-VAT','DEMO-PARTNERSHIP-VAT')
      AND wis.item_id IS NULL),
  0,
  'every active inventory item has warehouse replenishment controls'
);

SELECT is(
  (SELECT count(DISTINCT company_id)::integer FROM journal_entries
    WHERE description IN (
      'DEMO-CORP-VAT opening balances','P3-GRS-OPENING-BALANCES',
      'P3-NS-OPENING-BALANCES','P3-PBA-OPENING-BALANCES','P3-BPC-OPENING-BALANCES'
    )),
  5,
  'all five companies have governed opening-balance journals'
);

SELECT is(
  (SELECT count(*)::integer FROM (
    SELECT 1 FROM sales_invoices WHERE reference = 'P3-GRS-SI-CREDIT'
    UNION ALL SELECT 1 FROM receipts WHERE reference_number = 'P3-GRS-OR-PARTIAL'
    UNION ALL SELECT 1 FROM vendor_bills WHERE reference = 'P3-GRS-VB-INVENTORY'
    UNION ALL SELECT 1 FROM payment_vouchers WHERE reference_number = 'P3-GRS-PV-PARTIAL'
  ) x),
  4,
  'Golden has governed sales, collection, bill, and payment scenarios'
);

SELECT is(
  (SELECT count(*)::integer FROM (
    SELECT 1 FROM sales_invoices WHERE reference = 'P3-NS-SI-RETAINER'
    UNION ALL SELECT 1 FROM sales_invoices WHERE reference = 'P3-NS-SI-MILESTONE'
    UNION ALL SELECT 1 FROM vendor_bills WHERE reference = 'P3-NS-VB-CLOUD'
  ) x),
  3,
  'Northstar has retainer, milestone, and operating-expense scenarios'
);

SELECT is(
  (SELECT count(*)::integer FROM (
    SELECT 1 FROM sales_invoices WHERE reference = 'P3-PBA-SI-VAT-EXCLUSIVE'
    UNION ALL SELECT 1 FROM sales_invoices WHERE reference = 'P3-PBA-SI-CWT-PARTIAL'
    UNION ALL SELECT 1 FROM receipts WHERE reference_number = 'P3-PBA-OR-CWT-PARTIAL'
    UNION ALL SELECT 1 FROM vendor_bills WHERE reference = 'P3-PBA-VB-PROF'
    UNION ALL SELECT 1 FROM vendor_bills WHERE reference = 'P3-PBA-VB-RENT'
  ) x),
  5,
  'Prime has differentiated VAT, CWT, professional-fee, and rent scenarios'
);

SELECT is(
  (SELECT count(*)::integer FROM (
    SELECT 1 FROM sales_orders WHERE reference_number = 'P3-BPC-SO-TRADE'
    UNION ALL SELECT 1 FROM sales_invoices WHERE reference = 'P3-BPC-SI-TRADE'
    UNION ALL SELECT 1 FROM sales_invoices WHERE reference = 'P3-BPC-SI-ADVISORY'
    UNION ALL SELECT 1 FROM vendor_bills WHERE reference = 'P3-BPC-VB-INVENTORY'
    UNION ALL SELECT 1 FROM payment_vouchers WHERE reference_number = 'P3-BPC-PV-PARTIAL'
  ) x),
  5,
  'Bayani has its first complete mixed goods-and-services operating history'
);

SELECT results_eq(
  $$SELECT sq.status, so.approval_status, so.fulfillment_status, dr.status
    FROM sales_quotations sq
    JOIN sales_orders so ON so.quotation_id = sq.id
    JOIN delivery_receipts dr ON dr.sales_order_id = so.id
    WHERE sq.reference_number = 'P3-ABC-QT-LIFECYCLE'$$,
  $$VALUES ('approved'::text, 'approved'::text, 'partial'::text, 'delivered'::text)$$,
  'ABC quotation converts through partial sales order fulfillment and delivery'
);

SELECT is(
  (SELECT count(*)::integer FROM sales_invoice_lines sil
    JOIN sales_invoices si ON si.id = sil.sales_invoice_id
    JOIN sales_order_lines sol ON sol.id = sil.source_line_id
    JOIN sales_orders so ON so.id = sol.sales_order_id
    WHERE si.reference = 'P3-ABC-SI-LIFECYCLE'
      AND sil.source_document_type = 'sales_order'
      AND so.reference_number = 'P3-ABC-SO-LIFECYCLE'),
  1,
  'ABC posted invoice retains its authoritative sales-order source line'
);

SELECT results_eq(
  $$SELECT status, total_amount FROM credit_memos WHERE remarks = 'P3-ABC-CM-ALLOWANCE'$$,
  $$VALUES ('applied'::text, 112.00::numeric)$$,
  'ABC customer allowance posts as an applied credit memo'
);

SELECT results_eq(
  $$SELECT vc.status, vc.total_amount, vc.remaining_balance, SUM(vca.applied_amount)
    FROM vendor_credits vc
    JOIN vendor_credit_applications vca ON vca.vendor_credit_id = vc.id
    WHERE vc.supplier_cm_no = 'P3-ABC-SUPCM-001'
    GROUP BY vc.id$$,
  $$VALUES ('applied'::text, 224.00::numeric, 0.00::numeric, 224.00::numeric)$$,
  'ABC vendor credit posts and is fully applied to its source bill'
);

SELECT is(
  (SELECT status FROM cash_purchases WHERE reference_number = 'P3-ABC-CP-UTILITY'),
  'posted',
  'ABC immediate utility cash purchase is posted'
);

SELECT results_eq(
  $$SELECT status, journal_entry_id IS NOT NULL FROM physical_count_sheets WHERE count_number = 'P3-ABC-COUNT-JUNE'$$,
  $$VALUES ('posted'::text, true)$$,
  'ABC physical count posts its variance through the inventory engine'
);

SELECT is(
  (SELECT status FROM sales_invoices WHERE reference = 'P3-ABC-SI-VOIDED'),
  'cancelled',
  'ABC governed void fixture is cancelled after posting'
);

SELECT results_eq(
  $$SELECT original.status, original.reversed_by_je_id IS NOT NULL,
           reversal.status, reversal.reference_doc_type
    FROM sales_invoices si
    JOIN journal_entries original ON original.id = si.journal_entry_id
    JOIN journal_entries reversal ON reversal.id = original.reversed_by_je_id
    WHERE si.reference = 'P3-ABC-SI-VOIDED'$$,
  $$VALUES ('reversed'::text, true, 'posted'::text, 'REV'::text)$$,
  'voided invoice retains reversed original and posted counter-journal evidence'
);

SELECT is(
  (SELECT count(*)::integer FROM (
    SELECT je.id
    FROM journal_entries je
    JOIN journal_entry_lines jel ON jel.je_id = je.id
    JOIN companies c ON c.id = je.company_id
    WHERE c.trade_name LIKE 'DEMO-%'
      AND je.status IN ('posted','reversed')
    GROUP BY je.id
    HAVING ROUND(SUM(jel.debit_amount - jel.credit_amount), 2) <> 0
  ) unbalanced),
  0,
  'all canonical posted and reversed journals balance at line level'
);

SELECT is(
  (SELECT count(*)::integer FROM stock_balances sb JOIN companies c ON c.id = sb.company_id
    WHERE c.trade_name LIKE 'DEMO-%' AND sb.qty_on_hand < 0),
  0,
  'no canonical warehouse stock balance is negative'
);

SELECT is(
  (WITH movement AS (
    SELECT company_id, warehouse_id, item_id, SUM(qty) AS qty, SUM(total_cost) AS cost
    FROM inventory_transactions GROUP BY company_id, warehouse_id, item_id
  )
  SELECT count(*)::integer
  FROM stock_balances sb
  JOIN companies c ON c.id = sb.company_id
  LEFT JOIN movement m USING (company_id, warehouse_id, item_id)
  WHERE c.trade_name LIKE 'DEMO-%'
    AND (ROUND(sb.qty_on_hand - COALESCE(m.qty, 0), 4) <> 0
      OR ROUND(sb.total_cost - COALESCE(m.cost, 0), 2) <> 0)),
  0,
  'all canonical stock balances reconcile to inventory movements by warehouse and item'
);

SELECT is(
  (SELECT count(*)::integer
   FROM companies c
   CROSS JOIN LATERAL fn_ar_subledger_gl_reconciliation_asof(c.id, CURRENT_DATE) r
   WHERE c.trade_name LIKE 'DEMO-%' AND NOT r.is_reconciled),
  0,
  'AR subledgers reconcile to reversal-aware GL balances for all companies'
);

SELECT is(
  (SELECT count(*)::integer
   FROM companies c
   CROSS JOIN LATERAL fn_ap_subledger_gl_reconciliation_asof(c.id, CURRENT_DATE) r
   WHERE c.trade_name LIKE 'DEMO-%' AND NOT r.is_reconciled),
  0,
  'AP subledgers reconcile to reversal-aware GL balances for all companies'
);

SELECT results_eq(
  $$SELECT si.vat_price_basis, sil.net_amount, sil.vat_amount, sil.total_amount
    FROM sales_invoices si JOIN sales_invoice_lines sil ON sil.sales_invoice_id = si.id
    WHERE si.reference = 'P3-PBA-SI-CWT-PARTIAL' AND sil.line_number = 1$$,
  $$VALUES ('inclusive'::text, 20000.00::numeric, 2400.00::numeric, 22400.00::numeric)$$,
  'Prime VAT-inclusive retainer extracts the correct net and VAT amounts'
);

SELECT results_eq(
  $$SELECT si.cwt_amount_expected, si.cwt_tax_base, rl.cwt_amount, rl.cwt_tax_base
    FROM sales_invoices si
    JOIN receipt_lines rl ON rl.invoice_id = si.id
    JOIN receipts r ON r.id = rl.receipt_id
    WHERE si.reference = 'P3-PBA-SI-CWT-PARTIAL'
      AND r.reference_number = 'P3-PBA-OR-CWT-PARTIAL'$$,
  $$VALUES (400.00::numeric, 20000.00::numeric, 300.00::numeric, 15000.00::numeric)$$,
  'Prime separates expected invoice CWT from actual partial-collection CWT'
);

SELECT results_eq(
  $$SELECT vb.reference, t.tax_base, t.tax_amount
    FROM tax_detail_entries t
    JOIN vendor_bills vb ON vb.id = t.source_doc_id
    WHERE t.source_doc_type = 'VB' AND t.tax_kind = 'ewt_payable'
      AND vb.reference IN ('P3-PBA-VB-PROF','P3-PBA-VB-RENT')
    ORDER BY vb.reference$$,
  $$VALUES
      ('P3-PBA-VB-PROF'::text, 20000.00::numeric, 2000.00::numeric),
      ('P3-PBA-VB-RENT'::text, 30000.00::numeric, 600.00::numeric)$$,
  'Prime professional and rent bills create correct source-accrued EWT rows'
);

SELECT is(
  (SELECT count(*)::integer
   FROM companies c
   WHERE c.trade_name LIKE 'DEMO-%'
     AND NOT EXISTS (
       SELECT 1 FROM fn_trial_balance_report(c.id, DATE '2026-01-01', DATE '2026-07-16', NULL, false, NULL)
     )),
  0,
  'trial-balance report returns meaningful rows for every canonical company'
);

SELECT is(
  (SELECT count(*)::integer FROM warehouses w JOIN companies c ON c.id = w.company_id
    WHERE c.trade_name IN ('DEMO-OPC-NONVAT','DEMO-SVC-VAT')),
  0,
  'service-only companies remain legitimately warehouse-free'
);

SELECT results_eq(
  $$SELECT po.status, pol.quantity, rr.status, rrl.received_qty
    FROM purchase_orders po
    JOIN purchase_order_lines pol ON pol.po_id = po.id
    JOIN receiving_reports rr ON rr.po_id = po.id
    JOIN receiving_report_lines rrl ON rrl.rr_id = rr.id
    WHERE po.notes = 'P3-BPC-PO-PARTIAL'$$,
  $$VALUES ('partially_received'::text, 15.0000::numeric, 'received'::text, 10.0000::numeric)$$,
  'Bayani purchase chain preserves the intended partial-receipt state'
);

SELECT throws_like(
  format(
    'UPDATE sales_invoices SET total_amount = total_amount + 1 WHERE id = %L',
    (SELECT id FROM sales_invoices WHERE reference = 'P3-PBA-SI-VAT-EXCLUSIVE')
  ),
  '%immutable%',
  'posted sales invoice commercial values are immutable'
);

SELECT is(
  (SELECT count(*)::integer FROM (
    SELECT company_id, reference, count(*)
    FROM sales_invoices
    WHERE reference LIKE 'P3-%'
    GROUP BY company_id, reference
    HAVING count(*) > 1
  ) duplicates),
  0,
  'Phase 3 invoice references are idempotent and unique per company'
);

SELECT is(
  (SELECT count(*)::integer FROM companies c
   WHERE c.trade_name LIKE 'DEMO-%'
     AND NOT EXISTS (
       SELECT 1 FROM journal_entries je
       WHERE je.company_id = c.id AND je.status IN ('posted','reversed')
     )),
  0,
  'every canonical company has reportable accounting activity'
);

\else

SELECT skip(38, 'Phase 3 enrichment not loaded; run canonical_phase3_enrichment.sql before this regression file');

\endif

SELECT * FROM finish();
ROLLBACK;
