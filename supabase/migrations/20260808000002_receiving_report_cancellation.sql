-- ══════════════════════════════════════════════════════════════════════════════
-- Receiving Report cancellation and reversal
--
-- The purchasing mirror of Backlog 18c. A confirmed Receiving Report increases
-- stock and posts DR Inventory Control / CR Goods Received Not Invoiced
-- (PXL-AUD-073), and until now **no function reversed any of it**. A `cancelled`
-- status existed on the table with nothing able to reach it, so a mis-received
-- delivery could be corrected only by a manual journal plus a stock adjustment —
-- which breaks the source-to-ledger trace the product otherwise maintains.
--
-- ── WHERE PURCHASING GENUINELY DIFFERS FROM SALES ─────────────────────────────
-- The Delivery Receipt cancellation is the model, but two rules are not
-- symmetric and must not be copied:
--
--   1. **The goods may already be gone.** A delivery cancellation always puts
--      stock back and can never fail on availability. A receipt cancellation
--      TAKES STOCK AWAY, and the received goods may already have been sold,
--      issued or transferred. Removing them anyway would drive on-hand negative
--      and silently corrupt valuation, so this refuses when the stock is no
--      longer there and says how much is missing.
--
--   2. **Cost layers.** `fn_receive_inventory` creates a cost layer for FIFO and
--      specific-identification items. Un-creating a layer that later outflows
--      may already have consumed is a costing-replay problem, not a reversal —
--      it is exactly what the frozen IA-5/ECC programme exists to solve. This
--      refuses for those costing methods rather than inventing partial-layer
--      semantics. Weighted average, the only method proven end to end, is fully
--      supported. Recorded as future work, not silently half-done.
--
-- ── ORDERING ──────────────────────────────────────────────────────────────────
-- A receipt may not be reversed while a live Vendor Bill consumes it. The bill
-- debits the same Goods Received Not Invoiced balance the receipt credited;
-- reversing underneath it would leave the bill clearing a balance that no longer
-- exists. A **draft** bill counts, because it already claims the receipt through
-- `vendor_bills.rr_id` and posting it later would find nothing. Void the bill
-- first, then the receipt — the same ordering rule the Delivery Receipt uses.
--
-- Additive only: two columns, a widened guard extras list, one new function.
-- `fn_confirm_receiving_report` and the posting path are untouched.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Void columns, named as every other document names them ─────────────────
ALTER TABLE receiving_reports
  ADD COLUMN IF NOT EXISTS void_reason_id UUID REFERENCES void_reason_codes(id),
  ADD COLUMN IF NOT EXISTS void_memo TEXT;

COMMENT ON COLUMN receiving_reports.void_reason_id IS
  'Why this goods receipt was cancelled. Required on cancellation.';

-- ── 2. The guard learns about the void columns ────────────────────────────────
-- Same guard, same editable statuses; only the columns a locked row may
-- legitimately change are widened. The posting stamps were already allowed by
-- PXL-AUD-073.
DROP TRIGGER IF EXISTS trg_guard_header_receiving_reports ON receiving_reports;
CREATE TRIGGER trg_guard_header_receiving_reports
  BEFORE UPDATE OR DELETE ON receiving_reports
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header(
    'status', 'draft',
    'confirmed_by,confirmed_at,journal_entry_id,fiscal_period_id,posted_at,posted_by,void_reason_id,void_memo',
    '', 'same_txn');

-- ── 3. Cancellation and reversal ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_void_receiving_report(
  p_rr_id          UUID,
  p_void_reason_id UUID,
  p_memo           TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rr          receiving_reports%ROWTYPE;
  v_reversal_id UUID;
  v_reason      TEXT;
  v_billed      TEXT;
  v_layered     TEXT;
  v_moved       RECORD;
  v_short       RECORD;
  v_line        RECORD;
BEGIN
  SELECT * INTO v_rr FROM receiving_reports WHERE id = p_rr_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN
    RAISE EXCEPTION 'Receiving report not found or access denied';
  END IF;
  IF v_rr.status = 'cancelled' THEN
    RAISE EXCEPTION 'Receiving report is already cancelled';
  END IF;

  IF p_void_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason
    FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid or inactive void reason';
    END IF;
  END IF;
  v_reason := COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), v_reason);
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A void reason is required';
  END IF;
  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  -- ── Ordering: a live bill claims this receipt ───────────────────────────────
  SELECT vb.bill_number INTO v_billed
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rr.id
    AND vb.company_id = v_rr.company_id
    AND vb.status <> 'cancelled'
  LIMIT 1;
  IF v_billed IS NOT NULL THEN
    RAISE EXCEPTION 'Receiving Report % is billed by Vendor Bill %. Void that bill first, then cancel this receipt.',
      v_rr.rr_number, v_billed
      USING ERRCODE = '23514';
  END IF;

  IF v_rr.journal_entry_id IS NOT NULL THEN
    -- ── Costing methods this reversal cannot honestly support ────────────────
    SELECT string_agg(DISTINCT i.item_code, ', ') INTO v_layered
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
      AND COALESCE(i.costing_method, 'weighted_average') IN ('fifo', 'specific_identification');
    IF v_layered IS NOT NULL THEN
      RAISE EXCEPTION 'Receiving Report % holds cost-layered items (%). Reversing a receipt whose layers a later issue may already have consumed needs governed costing replay, which is not built. Correct this receipt with a Purchase Return instead.',
        v_rr.rr_number, v_layered
        USING ERRCODE = '0A000';   -- feature_not_supported
    END IF;

    -- Lock every affected stock pool before checking availability. All governed
    -- outbound paths take the same row lock, so a sale/issue cannot pass the
    -- check concurrently and make the subtraction below negative.
    FOR v_line IN
      SELECT DISTINCT rrl.item_id
      FROM receiving_report_lines rrl
      JOIN items i ON i.id = rrl.item_id
      WHERE rrl.rr_id = v_rr.id
        AND rrl.received_qty > 0
        AND i.item_type = 'inventory_item'
      ORDER BY rrl.item_id
    LOOP
      PERFORM fn_ensure_stock_balance(
        v_rr.company_id, v_rr.warehouse_id, v_line.item_id
      );
      PERFORM 1
      FROM stock_balances sb
      WHERE sb.company_id = v_rr.company_id
        AND sb.warehouse_id = v_rr.warehouse_id
        AND sb.item_id = v_line.item_id
      FOR UPDATE;
    END LOOP;

    -- Weighted-average stock is a pooled value. Once any quantity has left the
    -- pool after this receipt, subtracting the receipt's original cost is no
    -- longer a faithful reversal even if later receipts replenished the units.
    -- Fail closed rather than shifting that cost into the remaining stock.
    WITH receipt_tx AS (
      SELECT it.item_id, MIN(it.created_at) AS received_at
      FROM inventory_transactions it
      WHERE it.company_id = v_rr.company_id
        AND it.warehouse_id = v_rr.warehouse_id
        AND it.reference_doc_type = 'RR'
        AND it.reference_doc_id = v_rr.id
        AND it.qty > 0
      GROUP BY it.item_id
    )
    SELECT i.item_code, SUM(ABS(it.qty)) AS moved_qty
      INTO v_moved
    FROM receipt_tx rt
    JOIN inventory_transactions it
      ON it.company_id = v_rr.company_id
     AND it.warehouse_id = v_rr.warehouse_id
     AND it.item_id = rt.item_id
     AND it.created_at > rt.received_at
     AND it.qty < 0
     -- Another RR cancellation removes its own original receipt cost exactly;
     -- it does not make the remaining receipt unreplayable.
     AND it.reference_doc_type IS DISTINCT FROM 'RR_VOID'
    JOIN items i ON i.id = rt.item_id
    GROUP BY i.item_code
    ORDER BY i.item_code
    LIMIT 1;
    IF v_moved.item_code IS NOT NULL THEN
      RAISE EXCEPTION 'Cannot cancel Receiving Report %: % has % units of outbound movement after this receipt. The weighted-average pool has changed; correct it with a Purchase Return.',
        v_rr.rr_number, v_moved.item_code, v_moved.moved_qty
        USING ERRCODE = '23514';
    END IF;

    -- ── The goods must still be here to take back ────────────────────────────
    SELECT i.item_code,
           SUM(rrl.received_qty) AS needed,
           COALESCE(sb.qty_on_hand, 0) AS on_hand
      INTO v_short
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    LEFT JOIN stock_balances sb
      ON sb.warehouse_id = v_rr.warehouse_id AND sb.item_id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
    GROUP BY i.item_code, sb.qty_on_hand
    HAVING SUM(rrl.received_qty) > COALESCE(sb.qty_on_hand, 0)
    LIMIT 1;
    IF v_short.item_code IS NOT NULL THEN
      RAISE EXCEPTION 'Cannot cancel Receiving Report %: % has only % on hand but the receipt brought in %. Those goods have already moved; use a Purchase Return.',
        v_rr.rr_number, v_short.item_code, v_short.on_hand, v_short.needed
        USING ERRCODE = '23514';
    END IF;

    PERFORM fn_assert_source_journal_link(
      'RR', v_rr.id, v_rr.journal_entry_id, v_rr.company_id
    );
    v_reversal_id := fn_reverse_posted_journal_entry(
      v_rr.journal_entry_id, CURRENT_DATE,
      'REV', v_rr.id,
      'JE-REV-' || v_rr.rr_number,
      'Reversal of RR ' || v_rr.rr_number || ' (' || COALESCE(v_rr.supplier_name_snapshot, 'Supplier') || ') - ' || v_reason
    );

    -- ── Take the stock back out, through the same shared path ────────────────
    FOR v_line IN
      SELECT rrl.item_id,
             SUM(rrl.received_qty) AS qty,
             ROUND(SUM(rrl.received_qty * rrl.unit_price), 2) AS cost,
             COALESCE(i.costing_method, 'weighted_average') AS costing_method
      FROM receiving_report_lines rrl
      JOIN items i ON i.id = rrl.item_id
      WHERE rrl.rr_id = v_rr.id
        AND rrl.received_qty > 0
        AND i.item_type = 'inventory_item'
      GROUP BY rrl.item_id, i.costing_method
    LOOP
      PERFORM fn_ensure_stock_balance(v_rr.company_id, v_rr.warehouse_id, v_line.item_id);

      UPDATE stock_balances
      SET qty_on_hand   = qty_on_hand - v_line.qty,
          total_cost    = total_cost - v_line.cost,
          last_issue_date = CURRENT_DATE,
          updated_at    = NOW()
      WHERE company_id = v_rr.company_id
        AND warehouse_id = v_rr.warehouse_id
        AND item_id = v_line.item_id
        AND qty_on_hand >= v_line.qty
        AND total_cost >= v_line.cost;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot cancel Receiving Report %: locked stock quantity or value is no longer sufficient for item %',
          v_rr.rr_number, v_line.item_id
          USING ERRCODE = '23514';
      END IF;

      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0
                               THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE company_id = v_rr.company_id
        AND warehouse_id = v_rr.warehouse_id
        AND item_id = v_line.item_id;

      INSERT INTO inventory_transactions (
        company_id, warehouse_id, item_id, transaction_type, transaction_date,
        qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
        reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by
      )
      SELECT v_rr.company_id, v_rr.warehouse_id, v_line.item_id,
        'adjustment_out', CURRENT_DATE,
        -v_line.qty,
        CASE WHEN v_line.qty > 0 THEN ROUND(v_line.cost / v_line.qty, 6) ELSE 0 END,
        -v_line.cost,
        sb.qty_on_hand, v_line.costing_method,
        'RR_VOID', v_rr.id, v_reversal_id,
        'Cancellation of Goods Receipt ' || v_rr.rr_number,
        auth.uid()
      FROM stock_balances sb
      WHERE sb.company_id = v_rr.company_id
        AND sb.warehouse_id = v_rr.warehouse_id
        AND sb.item_id = v_line.item_id;
    END LOOP;
  END IF;

  UPDATE receiving_reports
  SET status = 'cancelled',
      void_reason_id = p_void_reason_id,
      void_memo = COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), void_memo),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rr.id;

  -- Reopen the source order to the quantity the still-live receipts actually
  -- support. Without this, cancelling a fully received RR left the header at
  -- `fully_received`, so the UI could not create the replacement receipt even
  -- though the governed progress view showed open quantity.
  UPDATE purchase_orders po
  SET status = CASE
        WHEN progress.received_qty >= progress.ordered_qty THEN 'fully_received'
        WHEN progress.received_qty > 0 THEN 'partially_received'
        ELSE 'approved'
      END,
      updated_by = auth.uid(),
      updated_at = NOW()
  FROM (
    SELECT COALESCE(SUM(pol.quantity), 0) AS ordered_qty,
           COALESCE(SUM(rec.received_qty), 0) AS received_qty
    FROM purchase_order_lines pol
    LEFT JOIN LATERAL (
      SELECT SUM(rrl.received_qty) AS received_qty
      FROM receiving_report_lines rrl
      JOIN receiving_reports rr ON rr.id = rrl.rr_id
      WHERE rrl.po_line_id = pol.id
        AND rr.status = 'received'
    ) rec ON TRUE
    WHERE pol.po_id = v_rr.po_id
  ) progress
  WHERE po.id = v_rr.po_id
    AND po.company_id = v_rr.company_id
    AND po.status <> 'cancelled';

  PERFORM fn_record_posting_event(
    v_rr.company_id, 'RR', v_rr.id, 'VOIDED', v_reversal_id,
    jsonb_build_object('void_reason_id', p_void_reason_id, 'reason', v_reason)
  );
END;
$$;

COMMENT ON FUNCTION public.fn_void_receiving_report(UUID, UUID, TEXT) IS
  'Cancels a goods receipt: reverses its journal, removes the stock through the shared path, and refuses while a live Vendor Bill claims it. Refuses cost-layered items, whose reversal needs governed costing replay.';

REVOKE ALL ON FUNCTION public.fn_void_receiving_report(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_void_receiving_report(UUID, UUID, TEXT) TO authenticated, service_role;
