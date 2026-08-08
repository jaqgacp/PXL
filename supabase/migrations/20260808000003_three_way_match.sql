-- ══════════════════════════════════════════════════════════════════════════════
-- Three-way match: PO → Receiving Report → Vendor Bill
--
-- Nothing in PXL checked that a receipt agreed with its order, or that a bill
-- agreed with its receipt. A supplier could ship 500 against an order for 100,
-- and bill 500 against a receipt of 100, and every document would post.
--
-- ── THE GRAIN EACH RULE CAN HONESTLY BE STATED AT ─────────────────────────────
-- Two relationships exist in the schema, and they sit at different grains:
--
--   * `receiving_report_lines.po_line_id` — LINE to LINE. Receipt quantity can
--     therefore be controlled exactly, per ordered line.
--   * `vendor_bills.rr_id` — HEADER to HEADER. A bill claims a whole receipt;
--     its lines carry no receipt-line reference.
--
-- So billing is controlled at the grain the link supports: **per receipt, per
-- item**. Within one receipt, the quantity billed for an item across all live
-- bills may not exceed the quantity received for that item. This needs no new
-- column and invents no allocation the data cannot support.
--
-- A bill with NO `rr_id` is untouched. That is deliberate: expense and service
-- bills legitimately arrive without a goods receipt, and the product supports
-- them today.
--
-- ── TOLERANCE ────────────────────────────────────────────────────────────────
-- No governed over-receipt or price tolerance exists anywhere in the product,
-- and inventing one is a business decision, not an engineering one. Both rules
-- therefore **fail closed** at the exact ordered/received quantity. A governed
-- tolerance is recorded as future work rather than guessed at here.
--
-- ── PRICE VARIANCE IS DELIBERATELY NOT IN THIS MIGRATION ─────────────────────
-- Inspected before deciding: `purchase_order_lines.unit_price`,
-- `receiving_report_lines.unit_price` and `vendor_bill_lines.unit_price` all
-- exist, but there is **no price-variance concept anywhere** — no variance
-- account key, no tolerance, no variance reason on a bill line (the only
-- variance reason in the product is `ewt_variance_reason`, which is withholding,
-- not price). Building price matching would mean inventing a variance engine and
-- deciding who absorbs the difference, which is a Product Architecture question.
-- Quantity matching ships here; price variance is recorded as a separate item.
--
-- Additive only: two read-only views and two assertions, wired into validation
-- seams that approval and posting already both pass through.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Traceability, derived from posted data ────────────────────────────────
-- The authority for "how much of this order is still open". No screen recomputes
-- it; the guards below read the same expressions.
-- `security_invoker` is mandatory: without it a view runs as its owner and
-- bypasses RLS, which is exactly the cross-company leak PXL-AUD-069 closed.
-- Guard test `077` refuses any authenticated-granted view that omits it.
CREATE OR REPLACE VIEW public.vw_po_line_receipt_progress
WITH (security_invoker = true) AS
SELECT pol.id                AS po_line_id,
       pol.po_id,
       po.po_number,
       po.company_id,
       po.supplier_id,
       pol.line_number,
       pol.item_id,
       pol.description,
       pol.quantity          AS ordered_qty,
       COALESCE(rec.received_qty, 0)                       AS received_qty,
       pol.quantity - COALESCE(rec.received_qty, 0)        AS remaining_qty,
       (COALESCE(rec.received_qty, 0) > pol.quantity)      AS is_over_received
FROM purchase_order_lines pol
JOIN purchase_orders po ON po.id = pol.po_id
LEFT JOIN LATERAL (
  SELECT SUM(rrl.received_qty) AS received_qty
  FROM receiving_report_lines rrl
  JOIN receiving_reports rr ON rr.id = rrl.rr_id
  WHERE rrl.po_line_id = pol.id
    -- Only a CONFIRMED receipt has actually received anything. A draft is an
    -- intention, and a cancelled one released what it took.
    AND rr.status = 'received'
) rec ON TRUE;

COMMENT ON VIEW public.vw_po_line_receipt_progress IS
  'Per ordered line: ordered, received and remaining. Cancelled receipts release their quantity. The authority for open-order quantity.';

-- Billing progress at the grain `vendor_bills.rr_id` supports: per receipt, per item.
CREATE OR REPLACE VIEW public.vw_rr_item_billing_progress
WITH (security_invoker = true) AS
SELECT rr.id                 AS rr_id,
       rr.rr_number,
       rr.company_id,
       rrl.item_id,
       SUM(rrl.received_qty) AS received_qty,
       COALESCE(bill.billed_qty, 0)                             AS billed_qty,
       SUM(rrl.received_qty) - COALESCE(bill.billed_qty, 0)     AS remaining_billable_qty
FROM receiving_reports rr
JOIN receiving_report_lines rrl ON rrl.rr_id = rr.id
LEFT JOIN LATERAL (
  SELECT SUM(vbl.quantity) AS billed_qty
  FROM vendor_bill_lines vbl
  JOIN vendor_bills vb ON vb.id = vbl.vendor_bill_id
  WHERE vb.rr_id = rr.id
    AND vb.status <> 'cancelled'
    AND vbl.item_id = rrl.item_id
) bill ON TRUE
-- A draft is entered quantity, not received quantity. Only a confirmed receipt
-- can support a Vendor Bill match.
WHERE rr.status = 'received'
  AND rrl.received_qty > 0
GROUP BY rr.id, rr.rr_number, rr.company_id, rrl.item_id, bill.billed_qty;

COMMENT ON VIEW public.vw_rr_item_billing_progress IS
  'Per receipt per item: received, billed and remaining billable. Cancelled bills release their quantity.';

REVOKE ALL ON public.vw_po_line_receipt_progress FROM PUBLIC, anon;
REVOKE ALL ON public.vw_rr_item_billing_progress FROM PUBLIC, anon;
GRANT SELECT ON public.vw_po_line_receipt_progress TO authenticated;
GRANT SELECT ON public.vw_rr_item_billing_progress TO authenticated;

-- ── 2. Over-receipt control ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_receipt_within_po(p_rr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rr receiving_reports%ROWTYPE;
  v_bad RECORD;
  v_over RECORD;
BEGIN
  SELECT * INTO v_rr
  FROM receiving_reports
  WHERE id = p_rr_id;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN
    RAISE EXCEPTION 'Receiving report not found or access denied';
  END IF;

  -- The header already names one Purchase Order. Every governed line must point
  -- at a line on that same order, in that same tenant, for that same item. The
  -- legacy save RPC checked only the header; without this assertion a crafted
  -- po_line_id could cross an order or company boundary inside a SECURITY
  -- DEFINER call.
  SELECT rrl.line_number, rrl.description
    INTO v_bad
  FROM receiving_report_lines rrl
  LEFT JOIN purchase_order_lines pol ON pol.id = rrl.po_line_id
  LEFT JOIN purchase_orders po ON po.id = pol.po_id
  WHERE rrl.rr_id = v_rr.id
    AND (
      rrl.company_id IS DISTINCT FROM v_rr.company_id
      OR rrl.po_line_id IS NULL
      OR po.id IS NULL
      OR po.id IS DISTINCT FROM v_rr.po_id
      OR po.company_id IS DISTINCT FROM v_rr.company_id
      OR pol.item_id IS DISTINCT FROM rrl.item_id
    )
  ORDER BY rrl.line_number
  LIMIT 1;
  IF v_bad.line_number IS NOT NULL THEN
    RAISE EXCEPTION 'Receiving Report line % (%) must reference the matching item line on its own Purchase Order.',
      v_bad.line_number, v_bad.description
      USING ERRCODE = '23514';
  END IF;

  -- Concurrent receipts for the same ordered line serialize here. Without the
  -- shared PO-line lock, two confirmations could both read the same remaining
  -- quantity and both pass.
  PERFORM 1
  FROM purchase_order_lines pol
  JOIN receiving_report_lines rrl ON rrl.po_line_id = pol.id
  WHERE rrl.rr_id = v_rr.id
  ORDER BY pol.id
  FOR UPDATE OF pol;

  -- The view reports what has already been CONFIRMED. This receipt is still
  -- draft while it is being confirmed, so its own quantity is added here — that
  -- sum is what may not exceed the order.
  SELECT pol.line_number,
         COALESCE(i.item_code, rrl.description) AS item_code,
         pol.quantity                              AS ordered,
         prog.received_qty + SUM(rrl.received_qty) AS attempted,
         po.po_number
    INTO v_over
  FROM receiving_report_lines rrl
  JOIN purchase_order_lines pol ON pol.id = rrl.po_line_id
  JOIN purchase_orders po ON po.id = pol.po_id
  JOIN vw_po_line_receipt_progress prog ON prog.po_line_id = pol.id
  LEFT JOIN items i ON i.id = rrl.item_id
  WHERE rrl.rr_id = p_rr_id
    AND rrl.received_qty > 0
  GROUP BY pol.line_number, i.item_code, rrl.description, pol.quantity,
           prog.received_qty, po.po_number
  HAVING prog.received_qty + SUM(rrl.received_qty) > pol.quantity
  LIMIT 1;

  IF v_over.line_number IS NOT NULL THEN
    RAISE EXCEPTION 'Over-receipt on %: line % (%) ordered % but receiving % in total. No over-receipt tolerance is configured, so the receipt is refused. Amend the purchase order first if the extra quantity is genuinely ordered.',
      v_over.po_number, v_over.line_number, v_over.item_code,
      v_over.ordered, v_over.attempted
      USING ERRCODE = '23514';
  END IF;
END;
$$;

-- Internal assertion only; fn_confirm_receiving_report is the authenticated API.
REVOKE ALL ON FUNCTION public.fn_assert_receipt_within_po(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_assert_receipt_within_po(UUID) IS
  'Three-way match: cumulative received quantity may not exceed the ordered quantity. Fails closed — no governed tolerance exists.';

-- ── 3. Over-billing control ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_bill_within_receipt(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bill vendor_bills%ROWTYPE;
  v_rr receiving_reports%ROWTYPE;
  v_over RECORD;
BEGIN
  SELECT * INTO v_bill FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND OR NOT is_company_member(v_bill.company_id) THEN
    RAISE EXCEPTION 'Vendor bill not found or access denied';
  END IF;
  IF v_bill.rr_id IS NULL THEN
    -- A bill that claims no receipt is an expense or service bill. The product
    -- supports those and this rule does not apply to them.
    RETURN;
  END IF;

  -- The receipt row is both the relationship authority and the concurrency
  -- lock shared by every bill that claims it.
  SELECT * INTO v_rr
  FROM receiving_reports
  WHERE id = v_bill.rr_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_rr.company_id IS DISTINCT FROM v_bill.company_id
     OR v_rr.supplier_id IS DISTINCT FROM v_bill.supplier_id THEN
    RAISE EXCEPTION 'Vendor bill must reference a Receiving Report for the same company and supplier.'
      USING ERRCODE = '23514';
  END IF;
  IF v_rr.status <> 'received' THEN
    RAISE EXCEPTION 'Receiving Report % is %, not received. Confirm the receipt before billing it.',
      v_rr.rr_number, v_rr.status
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(i.item_code, vbl.description) AS item_code,
         prog.received_qty,
         prog.billed_qty,
         rr.rr_number
    INTO v_over
  FROM vendor_bill_lines vbl
  JOIN vw_rr_item_billing_progress prog
    ON prog.rr_id = v_bill.rr_id AND prog.item_id = vbl.item_id
  JOIN receiving_reports rr ON rr.id = v_bill.rr_id
  LEFT JOIN items i ON i.id = vbl.item_id
  WHERE vbl.vendor_bill_id = p_bill_id
    AND vbl.item_id IS NOT NULL
    AND prog.billed_qty > prog.received_qty
  LIMIT 1;

  IF v_over.item_code IS NOT NULL THEN
    RAISE EXCEPTION 'Over-billing against %: % was received % but bills claim % in total. Reduce the bill, or receive the extra quantity first.',
      v_over.rr_number, v_over.item_code, v_over.received_qty, v_over.billed_qty
      USING ERRCODE = '23514';
  END IF;

  -- An item billed against this receipt that the receipt never contained is the
  -- same error wearing different clothes.
  SELECT COALESCE(i.item_code, vbl.description) AS item_code, rr.rr_number
    INTO v_over
  FROM vendor_bill_lines vbl
  JOIN receiving_reports rr ON rr.id = v_bill.rr_id
  LEFT JOIN items i ON i.id = vbl.item_id
  WHERE vbl.vendor_bill_id = p_bill_id
    AND vbl.item_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM vw_rr_item_billing_progress prog
      WHERE prog.rr_id = v_bill.rr_id AND prog.item_id = vbl.item_id
    )
  LIMIT 1;

  IF v_over.item_code IS NOT NULL THEN
    RAISE EXCEPTION 'Vendor bill claims Receiving Report % but bills %, which that receipt does not contain.',
      v_over.rr_number, v_over.item_code
      USING ERRCODE = '23514';
  END IF;
END;
$$;

-- Internal assertion only; bill approval/posting are the authenticated APIs.
REVOKE ALL ON FUNCTION public.fn_assert_bill_within_receipt(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_assert_bill_within_receipt(UUID) IS
  'Three-way match: for a bill linked to a receipt, billed quantity per item may not exceed received quantity. Bills with no receipt link are untouched.';

-- ── 4. Wire the bill rule into the seam approval and posting already share ────
-- Rebuilt from the LIVE definition with exactly one line added at the end.
CREATE OR REPLACE FUNCTION public.fn_validate_vendor_bill_accounting_ready(
  p_bill_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_supplier_tin TEXT;
BEGIN
  SELECT company_id, supplier_tin_snapshot
  INTO v_company_id, v_supplier_tin
  FROM vendor_bills
  WHERE id = p_bill_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found';
  END IF;
  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Vendor bill not found or access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Vendor bill must have at least one line before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND expense_account_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill line must have an expense account before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines vbl
    LEFT JOIN chart_of_accounts coa
      ON coa.id = vbl.expense_account_id
     AND coa.company_id = v_company_id
     AND coa.is_active = true
     AND coa.is_postable = true
    WHERE vbl.vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(vbl.description), '') IS NOT NULL
      AND coa.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill expense account must be active, postable, and belong to the bill company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND vat_code_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill line must have a VAT code before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines vbl
    LEFT JOIN vat_codes vc
      ON vc.id = vbl.vat_code_id
     AND vc.is_active = true
     AND vc.transaction_type = 'input_vat'
    WHERE vbl.vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(vbl.description), '') IS NOT NULL
      AND vc.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill VAT code must be active and valid for input VAT.';
  END IF;

  IF NULLIF(BTRIM(COALESCE(v_supplier_tin, '')), '') IS NULL
     AND EXISTS (
       SELECT 1
       FROM vendor_bill_lines vbl
       WHERE vbl.vendor_bill_id = p_bill_id
         AND (
           COALESCE(vbl.ewt_amount, 0) > 0
           OR vbl.ewt_atc_code_id IS NOT NULL
           OR vbl.ewt_tax_base IS NOT NULL
         )
     ) THEN
    RAISE EXCEPTION 'Supplier TIN is required when vendor bill has EWT withholding.';
  END IF;

  -- Three-way match: a bill claiming a receipt may not bill more than it received.
  PERFORM fn_assert_bill_within_receipt(p_bill_id);
END;
$$;

COMMENT ON FUNCTION public.fn_validate_vendor_bill_accounting_ready(UUID) IS
  'Vendor bill accounting readiness, plus the three-way-match over-billing rule. Called by both fn_approve_vendor_bill and fn_post_vendor_bill.';

-- CREATE OR REPLACE preserves the historical PUBLIC grant. Keep the validation
-- endpoint authenticated and prevent anonymous relationship probes.
REVOKE ALL ON FUNCTION public.fn_validate_vendor_bill_accounting_ready(UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_validate_vendor_bill_accounting_ready(UUID)
  TO authenticated, service_role;

-- ── 5. Wire the receipt rule into confirmation, before anything posts ────────
-- Rebuilt from the LIVE definition with exactly one call added after the
-- existing validations and before `fn_post_receiving_report`.
CREATE OR REPLACE FUNCTION public.fn_confirm_receiving_report(p_rr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rr receiving_reports%ROWTYPE;
  v_receipt RECORD;
BEGIN
  SELECT * INTO v_rr
  FROM receiving_reports
  WHERE id = p_rr_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN
    RAISE EXCEPTION 'Receiving report not found or access denied';
  END IF;
  IF v_rr.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft RRs can be confirmed (current: %)', v_rr.status;
  END IF;

  PERFORM fn_validate_purchase_dimensions(
    v_rr.company_id, v_rr.branch_id, v_rr.warehouse_id,
    v_rr.department_id, v_rr.cost_center_id
  );

  -- Three-way match: the cumulative received quantity may not exceed what the
  -- purchase order asked for. Checked before anything posts or moves.
  PERFORM fn_assert_receipt_within_po(p_rr_id);

  IF EXISTS (
    SELECT 1
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.company_id <> v_rr.company_id
  ) THEN
    RAISE EXCEPTION 'A receiving-report item does not belong to this company';
  END IF;

  IF v_rr.warehouse_id IS NULL AND EXISTS (
    SELECT 1
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
  ) THEN
    RAISE EXCEPTION 'Warehouse is required to confirm inventory-item receipts';
  END IF;

  -- PXL-AUD-073: an inventory item without an inventory control account would
  -- silently move stock with no ledger effect. Fail closed instead.
  IF EXISTS (
    SELECT 1
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
      AND i.inventory_account_id IS NULL
  ) THEN
    RAISE EXCEPTION 'An inventory item on this receipt has no inventory account configured';
  END IF;

  -- PXL-AUD-073: the journal is written while the source is still 'draft', so
  -- fn_begin_source_posting sees a postable status and takes the source lock.
  PERFORM fn_post_receiving_report(p_rr_id);

  FOR v_receipt IN
    SELECT rrl.item_id,
           SUM(rrl.received_qty) AS qty,
           ROUND(SUM(rrl.received_qty * rrl.unit_price)
                 / NULLIF(SUM(rrl.received_qty), 0), 6) AS unit_cost
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
    GROUP BY rrl.item_id
  LOOP
    PERFORM fn_receive_inventory(jsonb_build_object(
      'company_id', v_rr.company_id,
      'warehouse_id', v_rr.warehouse_id,
      'item_id', v_receipt.item_id,
      'qty', v_receipt.qty,
      'unit_cost', v_receipt.unit_cost,
      'receipt_date', v_rr.rr_date,
      'reference_doc_type', 'RR',
      'reference_doc_id', v_rr.id,
      'notes', COALESCE(v_rr.remarks, 'Goods Receipt ' || v_rr.rr_number)
    ));
  END LOOP;

  PERFORM fn_confirm_receiving_report_status_core_20260718(p_rr_id);
END;

$fn$;

COMMENT ON FUNCTION public.fn_confirm_receiving_report(UUID) IS
  'Confirms a goods receipt: validates, enforces the three-way-match over-receipt rule, posts DR inventory / CR purchase clearing, then receives the stock.';
