-- ══════════════════════════════════════════════════════════════════════════════
-- Backlog 18b (minimal cut) — a hand-typed invoice may not relieve delivered
-- stock a second time
--
-- THE HOLE. `fn_post_sales_invoice` decides how to treat a stockable line by
-- asking one question: does this line carry `source_document_type = 'DR'` and a
-- `source_line_id` whose delivery line was already costed?
--
--   * If YES, the cost already left inventory at delivery. The invoice moves it
--     from Goods Delivered Not Invoiced to COGS and touches no stock.
--   * If NO, the invoice relieves the stock itself.
--
-- Nothing checks whether the goods on an unlinked line were, in fact, already
-- delivered. "Bill This Delivery" on the Delivery Receipt is the only path that
-- creates the link. An invoice typed on the Sales Invoice screen for goods that
-- a delivery already shipped therefore takes the second branch and relieves the
-- stock AGAIN.
--
-- WHY IT IS SILENT. Both the stock and the ledger move together on that second
-- relief, so the inventory-to-control reconciliation still ties at ₱0.00 — the
-- one guard that would normally catch an inventory error cannot see this. What
-- is left behind is a Goods Delivered Not Invoiced balance that never clears,
-- because the delivery that created it was never billed against.
--
-- THE GUARD. Before an invoice may be approved or posted, every stockable line
-- that does NOT carry a delivery link is checked against the deliveries this
-- customer already has open. If the same item is sitting on a delivered,
-- unbilled, un-cancelled delivery line, the invoice is refused and told which
-- delivery to bill instead.
--
-- WHERE IT LIVES, AND WHY THERE. `fn_validate_sales_invoice_accounting_ready` is
-- already called by BOTH `fn_approve_sales_invoice` and `fn_post_sales_invoice`.
-- Extending it puts the refusal at approval — early, where the user can still
-- fix the document — and again at posting, which is the authoritative gate. The
-- posting function itself is not touched, so the relief logic it owns is
-- unchanged and there is no second inventory path.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   * It does not implement the Document Conversion Engine (Delivery Plan
--     Phase 5 item 5). It refuses the unsafe act; it does not build the link.
--   * It does not match on quantity or price. A delivered-but-unbilled line for
--     the same item is enough to make a hand-typed invoice unsafe, and quantity
--     matching belongs with three-way match, not here.
--   * It says nothing about service or non-stockable lines, which move no stock
--     and are never affected.
--
-- Additive only: one new function plus one CREATE OR REPLACE of the validator,
-- rebuilt from its LIVE definition.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── The rule, stated once ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_no_unlinked_delivered_stock(
  p_invoice_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv     sales_invoices%ROWTYPE;
  v_offence RECORD;
BEGIN
  SELECT * INTO v_inv FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RETURN;   -- the caller's own not-found handling owns this case
  END IF;

  -- One offending line is enough to refuse, and naming it is what makes the
  -- refusal actionable.
  SELECT sil.line_number,
         i.item_code,
         dr.dr_number,
         dr.dr_date
    INTO v_offence
  FROM sales_invoice_lines sil
  JOIN items i ON i.id = sil.item_id
  JOIN delivery_receipt_lines drl
    ON drl.item_id = sil.item_id
  JOIN delivery_receipts dr
    ON dr.id = drl.dr_id
  WHERE sil.sales_invoice_id = p_invoice_id
    -- Only stockable lines can be relieved twice.
    AND i.item_type = 'inventory_item'
    -- Only lines that do NOT already carry the governed delivery relationship.
    AND (sil.source_document_type IS DISTINCT FROM 'DR' OR sil.source_line_id IS NULL)
    -- The delivery must be this company's, this customer's, and still live.
    AND dr.company_id = v_inv.company_id
    AND dr.customer_id = v_inv.customer_id
    AND dr.status = 'delivered'
    -- The delivery must actually have relieved stock: an uncosted line moved
    -- nothing, so billing around it costs the books nothing either.
    AND drl.inventory_cost IS NOT NULL
    -- ...and must still be unbilled. A delivery already billed cannot be double
    -- relieved by this invoice, and a cancelled invoice releases its claim.
    AND NOT EXISTS (
      SELECT 1
      FROM sales_invoice_lines bill
      JOIN sales_invoices bsi ON bsi.id = bill.sales_invoice_id
      WHERE bill.source_document_type = 'DR'
        AND bill.source_line_id = drl.id
        AND bsi.status <> 'cancelled'
    )
  ORDER BY sil.line_number, dr.dr_date
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Line %: % was already delivered on % (%) and that delivery has not been billed. '
      'Bill the delivery from the Delivery Receipt so the invoice carries it, or cancel the delivery. '
      'Invoicing it directly here would relieve the stock a second time.',
      v_offence.line_number,
      COALESCE(v_offence.item_code, 'this item'),
      v_offence.dr_number,
      v_offence.dr_date
      USING ERRCODE = '23514';
  END IF;
END;
$$;

-- Internal assertion only. The authenticated API calls the validator; exposing
-- this SECURITY DEFINER helper directly would let a caller probe another
-- tenant's invoice/delivery relationship by UUID and read its document number
-- back from the refusal message.
REVOKE ALL ON FUNCTION public.fn_assert_no_unlinked_delivered_stock(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_assert_no_unlinked_delivered_stock(UUID) IS
  'Backlog 18b: refuses a Sales Invoice whose stockable line would relieve stock a delivery already relieved. Called from fn_validate_sales_invoice_accounting_ready, so it gates both approval and posting.';

-- ── Wire it into the validator both approval and posting already call ────────
-- Rebuilt from the LIVE definition, with exactly one line added at the end.
CREATE OR REPLACE FUNCTION public.fn_validate_sales_invoice_accounting_ready(
  p_invoice_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice sales_invoices%ROWTYPE;
  v_line RECORD;
BEGIN
  SELECT * INTO v_invoice
  FROM sales_invoices
  WHERE id = p_invoice_id;
  IF NOT FOUND OR NOT is_company_member(v_invoice.company_id) THEN
    RAISE EXCEPTION 'Sales invoice not found or access denied';
  END IF;

  PERFORM fn_validate_sales_invoice_accounting_ready_aud053_core(p_invoice_id);

  IF UPPER(COALESCE(v_invoice.currency_code, 'PHP')) <> 'PHP' THEN
    RAISE EXCEPTION
      'Foreign-currency Sales Invoices are not supported; currency_code must be PHP';
  END IF;

  PERFORM fn_assert_sales_invoice_dimension(
    'project', v_invoice.project_id, v_invoice.company_id,
    v_invoice.branch_id, v_invoice.date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'location', v_invoice.location_id, v_invoice.company_id,
    v_invoice.branch_id, v_invoice.date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'functional_entity', v_invoice.functional_entity_id, v_invoice.company_id,
    v_invoice.branch_id, v_invoice.date, 'header'
  );

  FOR v_line IN
    SELECT line_number, project_id, location_id, functional_entity_id
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
    ORDER BY line_number
  LOOP
    PERFORM fn_assert_sales_invoice_dimension(
      'project', v_line.project_id, v_invoice.company_id,
      v_invoice.branch_id, v_invoice.date, 'line ' || v_line.line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'location', v_line.location_id, v_invoice.company_id,
      v_invoice.branch_id, v_invoice.date, 'line ' || v_line.line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'functional_entity', v_line.functional_entity_id, v_invoice.company_id,
      v_invoice.branch_id, v_invoice.date, 'line ' || v_line.line_number
    );
  END LOOP;

  -- Backlog 18b: a stockable line with no delivery relationship may not bill
  -- goods a delivery already shipped, because posting would relieve them twice.
  PERFORM fn_assert_no_unlinked_delivered_stock(p_invoice_id);
END;
$$;

COMMENT ON FUNCTION public.fn_validate_sales_invoice_accounting_ready(UUID) IS
  'Sales Invoice accounting readiness: AUD-053 core, PHP-only, governed dimensions, and the Backlog 18b delivered-stock guard. Called by both fn_approve_sales_invoice and fn_post_sales_invoice.';

-- CREATE OR REPLACE preserves the historical PUBLIC grant. Re-state the API
-- boundary explicitly after replacing this SECURITY DEFINER function.
REVOKE ALL ON FUNCTION public.fn_validate_sales_invoice_accounting_ready(UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_validate_sales_invoice_accounting_ready(UUID)
  TO authenticated, service_role;
