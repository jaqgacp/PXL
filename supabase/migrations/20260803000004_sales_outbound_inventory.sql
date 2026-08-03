-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery Plan Phase 5 item 3 — the last two outbound inventory entry points.
--
-- THE GAP
--   Two of the three ways stock leaves or returns to a Philippine trading
--   company were still not accounted for.
--
--   **Delivery Receipt did not relieve inventory.** Relief happened only at
--   invoice, so goods physically shipped and not yet billed sat in stock at
--   full cost. A month-end count found them gone and the ledger said they were
--   there, with no unbilled-delivery account to explain the difference.
--
--   **Customer Return returned no stock.** The credit memo reversed revenue and
--   output VAT against AR and stopped there, so a returned item credited the
--   customer without ever coming back on hand and without reversing its COGS.
--   Gross margin stayed overstated by the cost of every return ever processed.
--
-- WHAT THIS CHANGES
--   1. `fn_post_delivery_receipt` relieves stock when goods are delivered and
--      parks the cost in **Goods Delivered Not Invoiced** — a governed account
--      key, the mirror of the PURCHASE_CLEARING key receiving already uses.
--   2. `fn_post_sales_invoice` consumes that clearing instead of relieving
--      stock a second time, whenever its line traces to an already-relieved
--      delivery line. **This is not optional**: without it, enabling delivery
--      relief would double-relieve every invoiced delivery. A partial unique
--      index makes billing one delivery line twice impossible.
--   3. Credit Memo returns stock through `fn_receive_inventory` — the same
--      inbound path receiving uses — at the cost the goods were originally
--      issued at, and posts DR inventory / CR COGS.
--
--   The economics now close: cost leaves inventory once, at delivery or at
--   invoice, never both; it reaches COGS exactly when the revenue does; and a
--   return puts both the stock and the cost back.
--
-- WHAT THIS DOES NOT CHANGE
--   No costing logic is duplicated. Outbound uses the existing
--   `fn_ensure_stock_balance` / `fn_consume_cost_layers` pair; inbound uses
--   `fn_receive_inventory`, which already owns weighted-average roll-forward,
--   FIFO layer creation and the `inventory_transactions` row. No tax
--   arithmetic moves — `fn_calculate_tax` remains the only calculator. No
--   Posting Engine kernel, guard or totality change.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. The governed clearing account ───────────────────────────────────────
-- The mirror of PURCHASE_CLEARING, and permissive for the same reason: goods
-- delivered not invoiced is conventionally an **asset** (the cost is still the
-- company's until the sale is recognised), but a chart that models it as a
-- contra-inventory or a clearing expense nets to the same zero once the invoice
-- posts. Constraining the type here would make a correctly configured company
-- unable to deliver.
INSERT INTO ref_mapping_key (key_code, description, expected_account_type, is_active)
VALUES
  ('SALES_DELIVERY_CLEARING',
   'Goods delivered not invoiced / sales delivery clearing (asset by convention; a contra-inventory or clearing account is also accepted)',
   NULL, true)
ON CONFLICT (key_code) DO UPDATE
  SET description           = EXCLUDED.description,
      expected_account_type = EXCLUDED.expected_account_type,
      is_active             = true;

ALTER TABLE company_accounting_config
  ADD COLUMN IF NOT EXISTS sales_delivery_clearing_account_id UUID REFERENCES chart_of_accounts(id);

INSERT INTO coa_template_lines (
  template_id, account_code, account_name, account_type, normal_balance,
  is_postable, parent_account_code, fs_group, fs_subgroup,
  is_control_account, allow_subledger, sort_order
)
SELECT t.template_id, '1310', 'Goods Delivered Not Invoiced', 'asset', 'debit',
       true, '1000', 'assets', 'Current Assets', false, false,
       COALESCE(MAX(t.sort_order), 0) + 1
FROM coa_template_lines t
WHERE NOT EXISTS (
  SELECT 1 FROM coa_template_lines x
  WHERE x.template_id = t.template_id AND x.account_code = '1310'
)
GROUP BY t.template_id;

-- Existing companies: adopt an explicitly named clearing account if the chart
-- already has one. Nothing is invented — a company with no such account simply
-- cannot post a delivery until an administrator configures the key, which is
-- the correct fail-closed behaviour and the message says so.
UPDATE company_accounting_config cfg
SET sales_delivery_clearing_account_id = COALESCE(cfg.sales_delivery_clearing_account_id, src.account_id)
FROM (
  SELECT DISTINCT ON (a.company_id) a.company_id, a.id AS account_id
  FROM chart_of_accounts a
  WHERE a.is_postable
    AND (a.account_code = '1310' OR a.account_name ILIKE '%delivered not invoiced%')
  ORDER BY a.company_id, a.account_code
) src
WHERE src.company_id = cfg.company_id
  AND cfg.sales_delivery_clearing_account_id IS NULL;

CREATE OR REPLACE FUNCTION fn_sync_account_mapping_from_config(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg   company_accounting_config%ROWTYPE;
  r       RECORD;
  v_count INTEGER := 0;
BEGIN
  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = p_company_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('AR_TRADE',                v_cfg.ar_account_id),
      ('AP_TRADE',                v_cfg.ap_account_id),
      ('VAT_OUTPUT',              v_cfg.vat_payable_account_id),
      ('VAT_INPUT',               v_cfg.input_vat_account_id),
      ('EWT_WITHHELD',            v_cfg.ewt_withheld_account_id),
      ('EWT_PAYABLE',             v_cfg.ewt_payable_account_id),
      ('CASH_DEFAULT',            v_cfg.default_cash_account_id),
      ('CUSTOMER_ADVANCES',       v_cfg.customer_advances_account_id),
      ('SUPPLIER_DOWNPAYMENTS',   v_cfg.supplier_down_payments_account_id),
      ('INVENTORY_CONTROL',       v_cfg.inventory_account_id),
      ('PURCHASE_CLEARING',       v_cfg.purchase_clearing_account_id),
      ('SALES_DELIVERY_CLEARING', v_cfg.sales_delivery_clearing_account_id)
    ) AS t(key_code, account_id)
    WHERE t.account_id IS NOT NULL
  LOOP
    UPDATE account_mapping m
       SET account_id = r.account_id, source = 'config_sync', updated_at = now()
     WHERE m.company_id = p_company_id
       AND m.key_code = r.key_code
       AND m.branch_id IS NULL AND m.document_type IS NULL AND m.party_id IS NULL
       AND m.item_id IS NULL AND m.item_group_id IS NULL AND m.tax_profile_id IS NULL
       AND m.effective_to IS NULL;
    IF NOT FOUND THEN
      INSERT INTO account_mapping (company_id, key_code, account_id, source)
      VALUES (p_company_id, r.key_code, r.account_id, 'config_sync');
    END IF;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ── 2. Documents learn where the goods are and what they cost ──────────────
ALTER TABLE delivery_receipts
  ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id),
  ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS posted_by UUID;

ALTER TABLE delivery_receipt_lines
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(18,6),
  ADD COLUMN IF NOT EXISTS inventory_cost NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID REFERENCES inventory_transactions(id);

ALTER TABLE credit_memo_lines
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(18,6),
  ADD COLUMN IF NOT EXISTS inventory_cost NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID REFERENCES inventory_transactions(id);

COMMENT ON COLUMN delivery_receipt_lines.warehouse_id IS
  'Where the goods physically left from. Required before a delivery of an inventory item can post.';
COMMENT ON COLUMN delivery_receipt_lines.inventory_cost IS
  'System-derived at delivery posting. Its presence is what tells the Sales Invoice the cost has already left inventory and must be taken from the clearing account instead.';
COMMENT ON COLUMN credit_memo_lines.warehouse_id IS
  'Where returned goods come back to. A credit memo line with no warehouse is a price adjustment, not a physical return, and moves no stock.';

-- One delivered line may be billed once. Without this, two invoices could each
-- claim the same clearing balance and inventory would reconcile to nothing.
CREATE UNIQUE INDEX IF NOT EXISTS uq_sil_delivery_source
  ON sales_invoice_lines (source_line_id)
  WHERE source_document_type = 'DR' AND source_line_id IS NOT NULL;

-- ── 3. Delivery Receipt posting ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_post_delivery_receipt(p_dr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_rec        delivery_receipts%ROWTYPE;
  v_clearing   UUID;
  v_fp_id      UUID;
  v_je_id      UUID;
  v_line       RECORD;
  v_stock      stock_balances%ROWTYPE;
  v_layer      RECORD;
  v_line_no    INT := 1;
  v_total_cost NUMERIC(18,2);
  v_unit_cost  NUMERIC(18,6);
  v_grand_cost NUMERIC(18,2) := 0;
  v_tx_id      UUID;
BEGIN
  SELECT * INTO v_rec FROM delivery_receipts WHERE id = p_dr_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF v_rec.status <> 'delivered' THEN
    RAISE EXCEPTION 'Only a delivered delivery receipt relieves inventory. Current status: %.', v_rec.status;
  END IF;
  IF v_rec.journal_entry_id IS NOT NULL THEN
    RETURN;  -- already posted; idempotent, like every other posting entry point
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.dr_date AND end_date >= v_rec.dr_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for delivery date %. Create or unlock a fiscal period.', v_rec.dr_date;
  END IF;

  -- A delivery of nothing stockable is a shipping record, not an accounting
  -- event. It stays unposted rather than producing an empty journal.
  IF NOT EXISTS (
    SELECT 1 FROM delivery_receipt_lines drl
    JOIN items i ON i.id = drl.item_id
    WHERE drl.dr_id = p_dr_id AND i.item_type = 'inventory_item' AND drl.quantity > 0
  ) THEN
    RETURN;
  END IF;

  v_clearing := fn_resolve_posting_account(
    v_rec.company_id, 'SALES_DELIVERY_CLEARING', v_rec.dr_date,
    'Goods Delivered Not Invoiced account not configured. Set it up in GL Posting Configuration before delivering stock.');

  -- Cost the whole delivery first: the journal header carries its totals.
  FOR v_line IN
    SELECT drl.id, drl.line_number, drl.item_id, drl.quantity, drl.warehouse_id,
           drl.description, i.item_code,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           COALESCE(i.inventory_account_id, NULL) AS inv_acct
    FROM delivery_receipt_lines drl
    JOIN items i ON i.id = drl.item_id
    WHERE drl.dr_id = p_dr_id AND i.item_type = 'inventory_item' AND drl.quantity > 0
    ORDER BY drl.line_number
  LOOP
    IF v_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Warehouse is required for inventory item line % before the delivery can relieve stock', v_line.line_number;
    END IF;
    IF v_line.inv_acct IS NULL THEN
      RAISE EXCEPTION 'Inventory account is required for inventory item line %', v_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(v_rec.company_id, v_line.warehouse_id, v_line.item_id);
    SELECT * INTO v_stock FROM stock_balances
    WHERE warehouse_id = v_line.warehouse_id AND item_id = v_line.item_id
    FOR UPDATE;

    IF COALESCE(v_stock.qty_on_hand, 0) < v_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        v_line.item_code, COALESCE(v_stock.qty_on_hand, 0), v_line.quantity;
    END IF;

    v_total_cost := 0;
    v_unit_cost  := 0;
    IF v_line.costing_method = 'weighted_average' THEN
      v_unit_cost  := COALESCE(v_stock.wac_unit_cost, 0);
      v_total_cost := ROUND(v_line.quantity * v_unit_cost, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_rec.company_id, v_line.warehouse_id, v_line.item_id, v_line.quantity, NULL, NULL)
      LOOP
        v_total_cost := v_total_cost + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
      END LOOP;
      IF v_line.quantity > 0 THEN
        v_unit_cost := ROUND(v_total_cost / v_line.quantity, 6);
      END IF;
    END IF;

    UPDATE stock_balances
    SET qty_on_hand     = qty_on_hand - v_line.quantity,
        total_cost      = GREATEST(total_cost - v_total_cost, 0),
        last_issue_date = v_rec.dr_date,
        updated_at      = NOW()
    WHERE warehouse_id = v_line.warehouse_id AND item_id = v_line.item_id;

    IF v_line.costing_method = 'weighted_average' THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_line.warehouse_id AND item_id = v_line.item_id;
    END IF;

    UPDATE delivery_receipt_lines
    SET unit_cost = v_unit_cost, inventory_cost = v_total_cost, updated_at = NOW()
    WHERE id = v_line.id;

    v_grand_cost := v_grand_cost + v_total_cost;
  END LOOP;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-DR-' || v_rec.dr_number, v_rec.dr_date,
    'Delivery Receipt ' || v_rec.dr_number || ' — ' || v_rec.customer_name_snapshot,
    'DR', v_rec.id,
    v_fp_id, 'posted', v_grand_cost, v_grand_cost,
    'system', 'regular', false, false, false
  );

  FOR v_line IN
    SELECT drl.id, drl.line_number, drl.item_id, drl.quantity, drl.warehouse_id,
           drl.description, drl.unit_cost, drl.inventory_cost, i.item_code,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           i.inventory_account_id AS inv_acct
    FROM delivery_receipt_lines drl
    JOIN items i ON i.id = drl.item_id
    WHERE drl.dr_id = p_dr_id AND i.item_type = 'inventory_item' AND drl.quantity > 0
    ORDER BY drl.line_number
  LOOP
    IF COALESCE(v_line.inventory_cost, 0) > 0 THEN
      PERFORM fn_add_posting_line_push(
        v_je_id, v_line_no, v_clearing,
        'Goods delivered not invoiced — ' || COALESCE(v_line.item_code, v_line.description),
        v_line.inventory_cost, 0, 'base', NULL, v_rec.branch_id);
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_je_id, v_line_no, v_line.inv_acct,
        'Inventory — ' || COALESCE(v_line.item_code, v_line.description),
        0, v_line.inventory_cost, 'base', NULL, v_rec.branch_id);
      v_line_no := v_line_no + 1;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by
    )
    SELECT v_rec.company_id, v_line.warehouse_id, v_line.item_id,
      'issue', v_rec.dr_date,
      -v_line.quantity, COALESCE(v_line.unit_cost, 0), -COALESCE(v_line.inventory_cost, 0),
      sb.qty_on_hand, v_line.costing_method,
      'DR', v_rec.id, v_je_id,
      'Delivery Receipt ' || v_rec.dr_number || ' line ' || v_line.line_number,
      auth.uid()
    FROM stock_balances sb
    WHERE sb.warehouse_id = v_line.warehouse_id AND sb.item_id = v_line.item_id
    RETURNING id INTO v_tx_id;

    UPDATE delivery_receipt_lines
    SET inventory_transaction_id = v_tx_id, updated_at = NOW()
    WHERE id = v_line.id;
  END LOOP;

  UPDATE delivery_receipts
  SET journal_entry_id = v_je_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = p_dr_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_post_delivery_receipt(UUID) IS
  'Relieves stock when goods are delivered and parks the cost in Goods Delivered Not Invoiced until the Sales Invoice recognises it as COGS. Uses the shared costing path; idempotent once posted.';

REVOKE ALL ON FUNCTION public.fn_post_delivery_receipt(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_post_delivery_receipt(UUID) TO authenticated, service_role;

-- ── 4. Sales Invoice consumes the clearing instead of relieving twice ──────
CREATE OR REPLACE FUNCTION public.fn_post_sales_invoice(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec sales_invoices%ROWTYPE;
  v_ar UUID;
  v_vat UUID;
  v_clearing UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_inv_line RECORD;
  v_tax RECORD;
  v_stock stock_balances%ROWTYPE;
  v_layer RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
  v_total_cost NUMERIC(18,2);
  v_unit_cost NUMERIC(18,6);
  v_inventory_tx_id UUID;
  v_delivered_cost NUMERIC(18,2);
BEGIN
  v_begin := fn_begin_source_posting(
    'SI', p_invoice_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM sales_invoices WHERE id = p_invoice_id;
  PERFORM fn_validate_sales_invoice_accounting_ready(p_invoice_id);
  PERFORM fn_validate_sales_invoice_vat_registration(p_invoice_id);
  PERFORM fn_validate_invoice_posting_totals('SI', p_invoice_id);

  -- COA resolver adoption (P2A): AR control + Output VAT via fn_resolve_account.
  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date,
    'Sales Invoice ' || v_rec.si_number || ' - ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  PERFORM fn_add_sales_invoice_posting_line(
    v_je_id, 1, v_ar,
    'AR - ' || v_rec.customer_name_snapshot,
    v_rec.total_amount, 0,
    v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
    v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
  );
  v_line_no := 2;
  v_total_debit := v_rec.total_amount;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum,
           sil.description AS line_description,
           COALESCE(sil.department_id, v_rec.department_id) AS department_id,
           COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id,
           COALESCE(sil.project_id, v_rec.project_id) AS project_id,
           COALESCE(sil.location_id, v_rec.location_id) AS location_id,
           COALESCE(
             sil.functional_entity_id, v_rec.functional_entity_id
           ) AS functional_entity_id
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description,
             COALESCE(sil.department_id, v_rec.department_id),
             COALESCE(sil.cost_center_id, v_rec.cost_center_id),
             COALESCE(sil.project_id, v_rec.project_id),
             COALESCE(sil.location_id, v_rec.location_id),
             COALESCE(sil.functional_entity_id, v_rec.functional_entity_id)
  LOOP
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_line.revenue_account_id,
      'Revenue - ' || v_line.line_description,
      0, v_line.net_sum,
      v_rec.branch_id, v_line.department_id, v_line.cost_center_id,
      v_line.project_id, v_line.location_id, v_line.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_vat,
      'Output VAT - ' || v_rec.si_number,
      0, v_rec.total_vat_amount,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_rec.total_vat_amount;
  END IF;

  FOR v_inv_line IN
    SELECT sil.*,
           i.item_code,
           i.description AS item_description,
           i.item_type,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           COALESCE(sil.inventory_account_id, i.inventory_account_id) AS resolved_inventory_account_id,
           COALESCE(sil.cogs_account_id, i.cogs_account_id) AS resolved_cogs_account_id,
           -- The cost already relieved by a delivery, if this line bills one.
           (SELECT drl.inventory_cost
              FROM delivery_receipt_lines drl
             WHERE drl.id = sil.source_line_id
               AND sil.source_document_type = 'DR') AS delivered_cost
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_rec.id
      AND i.item_type = 'inventory_item'
  LOOP
    IF v_inv_line.resolved_inventory_account_id IS NULL
       OR v_inv_line.resolved_cogs_account_id IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required for inventory item line %', v_inv_line.line_number;
    END IF;

    v_delivered_cost := v_inv_line.delivered_cost;

    -- ── The line bills a delivery that already relieved the stock ──────────
    -- The cost is sitting in Goods Delivered Not Invoiced. Recognise it as COGS
    -- and clear it; do NOT touch stock, which left at delivery.
    IF v_delivered_cost IS NOT NULL THEN
      IF v_delivered_cost > 0 THEN
        v_clearing := fn_resolve_posting_account(
          v_rec.company_id, 'SALES_DELIVERY_CLEARING', v_rec.date,
          'Goods Delivered Not Invoiced account not configured. Set it up in GL Posting Configuration.');

        PERFORM fn_add_sales_invoice_posting_line(
          v_je_id, v_line_no, v_inv_line.resolved_cogs_account_id,
          'COGS - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
          v_delivered_cost, 0,
          v_rec.branch_id,
          COALESCE(v_inv_line.department_id, v_rec.department_id),
          COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
          COALESCE(v_inv_line.project_id, v_rec.project_id),
          COALESCE(v_inv_line.location_id, v_rec.location_id),
          COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
        );
        v_line_no := v_line_no + 1;
        PERFORM fn_add_sales_invoice_posting_line(
          v_je_id, v_line_no, v_clearing,
          'Goods delivered not invoiced cleared - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
          0, v_delivered_cost,
          v_rec.branch_id,
          COALESCE(v_inv_line.department_id, v_rec.department_id),
          COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
          COALESCE(v_inv_line.project_id, v_rec.project_id),
          COALESCE(v_inv_line.location_id, v_rec.location_id),
          COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
        );
        v_line_no := v_line_no + 1;
        v_total_debit := v_total_debit + v_delivered_cost;
        v_total_credit := v_total_credit + v_delivered_cost;
      END IF;

      PERFORM set_config('pxl.sales_invoice_posting_internal', 'on', true);
      UPDATE sales_invoice_lines
      SET inventory_account_id = v_inv_line.resolved_inventory_account_id,
          cogs_account_id = v_inv_line.resolved_cogs_account_id,
          unit_cost = (SELECT drl.unit_cost FROM delivery_receipt_lines drl
                        WHERE drl.id = v_inv_line.source_line_id),
          inventory_cost = v_delivered_cost,
          updated_by = auth.uid(),
          updated_at = NOW()
      WHERE id = v_inv_line.id;
      PERFORM set_config('pxl.sales_invoice_posting_internal', '', true);

      CONTINUE;
    END IF;

    IF v_inv_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Warehouse is required for inventory item line %', v_inv_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(
      v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id
    );
    SELECT * INTO v_stock
    FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id
    FOR UPDATE;

    IF COALESCE(v_stock.qty_on_hand, 0) < v_inv_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        v_inv_line.item_code, COALESCE(v_stock.qty_on_hand, 0), v_inv_line.quantity;
    END IF;

    v_total_cost := 0;
    v_unit_cost := 0;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      v_unit_cost := COALESCE(v_stock.wac_unit_cost, 0);
      v_total_cost := ROUND(v_inv_line.quantity * v_unit_cost, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
          v_inv_line.quantity, NULL, NULL
        )
      LOOP
        v_total_cost := v_total_cost + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        v_unit_cost := v_layer.unit_cost;
      END LOOP;
      IF v_inv_line.quantity > 0 THEN
        v_unit_cost := ROUND(v_total_cost / v_inv_line.quantity, 6);
      END IF;
    END IF;

    UPDATE stock_balances
    SET qty_on_hand = qty_on_hand - v_inv_line.quantity,
        total_cost = GREATEST(total_cost - v_total_cost, 0),
        last_issue_date = v_rec.date,
        updated_at = NOW()
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE
        WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_inv_line.warehouse_id
        AND item_id = v_inv_line.item_id;
    END IF;

    IF v_total_cost > 0 THEN
      PERFORM fn_add_sales_invoice_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_cogs_account_id,
        'COGS - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        v_total_cost, 0,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
        COALESCE(v_inv_line.project_id, v_rec.project_id),
        COALESCE(v_inv_line.location_id, v_rec.location_id),
        COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
      );
      v_line_no := v_line_no + 1;
      PERFORM fn_add_sales_invoice_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_inventory_account_id,
        'Inventory - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        0, v_total_cost,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
        COALESCE(v_inv_line.project_id, v_rec.project_id),
        COALESCE(v_inv_line.location_id, v_rec.location_id),
        COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
      );
      v_line_no := v_line_no + 1;
      v_total_debit := v_total_debit + v_total_cost;
      v_total_credit := v_total_credit + v_total_cost;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by,
      project_id, location_id, functional_entity_id
    )
    SELECT v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
      'issue', v_rec.date,
      -v_inv_line.quantity, v_unit_cost, -v_total_cost,
      qty_on_hand, v_inv_line.costing_method,
      'SI', v_rec.id, v_je_id,
      'Sales Invoice ' || v_rec.si_number || ' line ' || v_inv_line.line_number,
      auth.uid(),
      COALESCE(v_inv_line.project_id, v_rec.project_id),
      COALESCE(v_inv_line.location_id, v_rec.location_id),
      COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
    FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id
    RETURNING id INTO v_inventory_tx_id;

    PERFORM set_config('pxl.sales_invoice_posting_internal', 'on', true);
    UPDATE sales_invoice_lines
    SET inventory_account_id = v_inv_line.resolved_inventory_account_id,
        cogs_account_id = v_inv_line.resolved_cogs_account_id,
        unit_cost = v_unit_cost,
        inventory_cost = v_total_cost,
        inventory_transaction_id = v_inventory_tx_id,
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = v_inv_line.id;
    PERFORM set_config('pxl.sales_invoice_posting_internal', '', true);
  END LOOP;

  IF ABS(v_total_debit - v_total_credit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check line revenue, VAT, inventory, and COGS configuration.',
      v_total_debit, v_total_credit;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT sil.vat_code_id,
           SUM(sil.net_amount) AS tax_base,
           COALESCE(SUM(sil.vat_amount), 0) AS tax_amount
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY sil.vat_code_id
    HAVING SUM(sil.net_amount) <> 0
       OR COALESCE(SUM(sil.vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id, NULL,
      'output_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.date)
  );
END;
$function$;

-- ── 5. Credit Memo returns stock ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_post_credit_memo_vat_lump_impl(p_cm_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rec         credit_memos%ROWTYPE;
  v_ar          UUID;
  v_vat         UUID;
  v_fp_id       UUID;
  v_je_id       UUID;
  v_line        RECORD;
  v_ret         RECORD;
  v_line_no     INT := 1;
  v_total_dr    NUMERIC(15,2) := 0;
  v_return_cost NUMERIC(18,2);
  v_unit_cost   NUMERIC(18,6);
  v_total_return NUMERIC(18,2) := 0;
  v_tx_id       UUID;
BEGIN
  SELECT * INTO v_rec FROM credit_memos WHERE id = p_cm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Credit memo cannot be posted in status: %', v_rec.status;
  END IF;

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.cm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.cm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  -- ── Physical returns are costed before the journal is opened ─────────────
  -- A line returns stock only when it names an inventory item AND a warehouse:
  -- a price adjustment or a discount credit moves no goods and must not.
  -- The cost is the cost the goods LEFT at, taken from the invoice line they
  -- came back from, so the COGS reversal exactly undoes the original charge.
  FOR v_ret IN
    SELECT cml.id, cml.line_number, cml.item_id, cml.quantity, cml.warehouse_id,
           cml.description, cml.invoice_line_id, i.item_code,
           COALESCE(sil.unit_cost, sb.wac_unit_cost, i.standard_cost, 0) AS cost_basis
    FROM credit_memo_lines cml
    JOIN items i ON i.id = cml.item_id
    LEFT JOIN sales_invoice_lines sil ON sil.id = cml.invoice_line_id
    LEFT JOIN stock_balances sb
           ON sb.warehouse_id = cml.warehouse_id AND sb.item_id = cml.item_id
    WHERE cml.credit_memo_id = p_cm_id
      AND i.item_type = 'inventory_item'
      AND cml.warehouse_id IS NOT NULL
      AND cml.quantity > 0
    ORDER BY cml.line_number
  LOOP
    v_unit_cost   := ROUND(v_ret.cost_basis, 6);
    v_return_cost := ROUND(v_ret.quantity * v_unit_cost, 2);
    UPDATE credit_memo_lines
    SET unit_cost = v_unit_cost, inventory_cost = v_return_cost, updated_at = NOW()
    WHERE id = v_ret.id;
    v_total_return := v_total_return + v_return_cost;
  END LOOP;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount + v_total_return,
    v_rec.total_amount + v_total_return, 'system'
  );

  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_line.revenue_account_id, 'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, 'base');
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_vat, 'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, 'tax');
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  PERFORM fn_add_posting_line_push(
    v_je_id, v_line_no, v_ar, 'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, 'control');
  v_line_no := v_line_no + 1;

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  -- ── The goods come back ─────────────────────────────────────────────────
  -- fn_receive_inventory is the shared inbound path: weighted-average
  -- roll-forward, FIFO layer creation, stock balance and the transaction row.
  -- Nothing about costing is reimplemented here.
  FOR v_ret IN
    SELECT cml.id, cml.line_number, cml.item_id, cml.quantity, cml.warehouse_id,
           cml.description, cml.unit_cost, cml.inventory_cost, i.item_code,
           COALESCE(i.inventory_account_id, NULL) AS inv_acct,
           COALESCE(i.cogs_account_id, NULL) AS cogs_acct
    FROM credit_memo_lines cml
    JOIN items i ON i.id = cml.item_id
    WHERE cml.credit_memo_id = p_cm_id
      AND i.item_type = 'inventory_item'
      AND cml.warehouse_id IS NOT NULL
      AND cml.quantity > 0
    ORDER BY cml.line_number
  LOOP
    IF v_ret.inv_acct IS NULL OR v_ret.cogs_acct IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required to return item % to stock', v_ret.item_code;
    END IF;

    v_tx_id := fn_receive_inventory(jsonb_build_object(
      'company_id',         v_rec.company_id,
      'warehouse_id',       v_ret.warehouse_id,
      'item_id',            v_ret.item_id,
      'qty',                v_ret.quantity,
      'unit_cost',          v_ret.unit_cost,
      'receipt_date',       v_rec.cm_date,
      'reference_doc_type', 'CM',
      'reference_doc_id',   v_rec.id,
      'notes',              'Customer return ' || v_rec.cm_number || ' line ' || v_ret.line_number
    ));

    UPDATE inventory_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
    UPDATE credit_memo_lines SET inventory_transaction_id = v_tx_id, updated_at = NOW()
    WHERE id = v_ret.id;

    IF COALESCE(v_ret.inventory_cost, 0) > 0 THEN
      PERFORM fn_add_posting_line_push(
        v_je_id, v_line_no, v_ret.inv_acct,
        'Inventory returned — ' || COALESCE(v_ret.item_code, v_ret.description),
        v_ret.inventory_cost, 0, 'base', NULL, v_rec.branch_id);
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_je_id, v_line_no, v_ret.cogs_acct,
        'COGS reversal — ' || COALESCE(v_ret.item_code, v_ret.description),
        0, v_ret.inventory_cost, 'base', NULL, v_rec.branch_id);
      v_line_no := v_line_no + 1;
    END IF;
  END LOOP;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;

  -- Negative output VAT in tax ledger (reversal of original SI output VAT)
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CM', v_rec.id,
      'output_vat', -v_rec.total_taxable_amount, -v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.cm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      true
    );
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.fn_post_credit_memo_vat_lump_impl(uuid) IS
  'Credit memo journal: reverses revenue and output VAT against AR, and — for lines that name an inventory item and a warehouse — returns the goods to stock through fn_receive_inventory at the cost they were issued at, reversing COGS. A line with no warehouse is a price adjustment and moves no stock.';

-- ── 6. Credit Memo save accepts the return warehouse ───────────────────────
-- Only the line INSERT changes: a credit memo line that names a warehouse is a
-- physical return, and the posting routine above is what acts on it.
CREATE OR REPLACE FUNCTION public.fn_save_credit_memo(p_cm_id uuid, p_header jsonb, p_lines jsonb, p_next_status text DEFAULT 'draft'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_cm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
  v_total_taxable  NUMERIC(15,2) := 0;
  v_total_zero     NUMERIC(15,2) := 0;
  v_total_exempt   NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  v_effective_status := CASE WHEN p_next_status = 'applied' THEN 'approved' ELSE p_next_status END;

  IF p_cm_id IS NULL THEN
    v_cm_number := fn_next_document_number(v_company_id, v_branch_id, 'CM');
    INSERT INTO credit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      invoice_id, cm_number, cm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'invoice_id', '')::UUID,
      v_cm_number, (p_header->>'cm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      v_effective_status, auth.uid(), auth.uid()
    ) RETURNING id INTO v_cm_id;
  ELSE
    SELECT id, status INTO v_cm_id, v_current_status
    FROM credit_memos WHERE id = p_cm_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found or access denied'; END IF;
    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','applied','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','applied','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition credit memo from % to %', v_current_status, p_next_status;
    END IF;
    UPDATE credit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      invoice_id = NULLIF(p_header->>'invoice_id', '')::UUID,
      cm_date = (p_header->>'cm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  DELETE FROM credit_memo_lines WHERE credit_memo_id = v_cm_id;
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    SELECT c.classification, c.net_amount, c.tax_amount
      INTO v_vat_class, v_net, v_vat_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', (p_header->>'cm_date')::DATE,
           'direction',     'sale',
           'amount',        GREATEST(ROUND(v_qty * v_price, 2), 0),
           'vat_code_id',   NULLIF(v_line->>'vat_code_id', '')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');
    v_total_line := v_net + v_vat_amt;
    v_total_net  := v_total_net + v_net;
    v_total_vat  := v_total_vat + v_vat_amt;
    v_total_amt  := v_total_amt + v_total_line;
    IF    v_vat_class = 'regular'   THEN v_total_taxable := v_total_taxable + v_net;
    ELSIF v_vat_class = 'zero_rated' THEN v_total_zero   := v_total_zero    + v_net;
    ELSE                                  v_total_exempt  := v_total_exempt  + v_net;
    END IF;
    INSERT INTO credit_memo_lines (
      credit_memo_id, company_id, line_number,
      invoice_line_id, item_id, description, quantity, unit_price,
      net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
      warehouse_id,
      created_by, updated_by
    ) VALUES (
      v_cm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'invoice_line_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_qty, v_price,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      -- A warehouse on the line is what turns a credit into a physical return.
      COALESCE(NULLIF(v_line->>'warehouse_id', '')::UUID,
               NULLIF(p_header->>'warehouse_id', '')::UUID),
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE credit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    total_taxable_amount = v_total_taxable, total_zero_rated_amount = v_total_zero,
    total_exempt_amount = v_total_exempt,
    updated_at = NOW()
  WHERE id = v_cm_id;

  IF p_next_status = 'applied' THEN
    PERFORM fn_post_credit_memo(v_cm_id);
  END IF;
  RETURN v_cm_id;
END;
$function$

;

-- ── 7. The delivery becomes a posting source and an invoiceable source ─────
-- `journal_entries.reference_doc_type` is a foreign key into the posting-source
-- registry: a delivery journal is impossible until DR is registered there.
INSERT INTO ref_posting_source_types (
  document_type, source_table, document_number_column, document_date_column,
  status_column, route_path, display_name, allows_multiple_journal_entries, is_active
) VALUES (
  'DR', 'delivery_receipts', 'dr_number', 'dr_date', 'status',
  '/delivery-receipts', 'Delivery Receipt', false, true
)
ON CONFLICT (document_type) DO UPDATE
  SET source_table                    = EXCLUDED.source_table,
      document_number_column          = EXCLUDED.document_number_column,
      document_date_column            = EXCLUDED.document_date_column,
      status_column                   = EXCLUDED.status_column,
      route_path                      = EXCLUDED.route_path,
      display_name                    = EXCLUDED.display_name,
      is_active                       = true;

-- The Sales Invoice save accepts a delivery as a line source. Only the source
-- validation block changes; the sales-order path is untouched.
CREATE OR REPLACE FUNCTION public.fn_save_sales_invoice(p_invoice_id uuid, p_header jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_invoice_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := (p_header->>'branch_id')::UUID;
  v_date DATE := COALESCE((p_header->>'date')::DATE, CURRENT_DATE);
  v_project_id UUID := NULLIF(p_header->>'project_id', '')::UUID;
  v_location_id UUID := NULLIF(p_header->>'location_id', '')::UUID;
  v_functional_entity_id UUID := NULLIF(p_header->>'functional_entity_id', '')::UUID;
  v_line JSONB;
  v_line_number INTEGER := 0;
BEGIN
  IF UPPER(COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP')) <> 'PHP' THEN
    RAISE EXCEPTION
      'Foreign-currency Sales Invoices are not supported; currency_code must be PHP';
  END IF;

  PERFORM fn_assert_sales_invoice_dimension(
    'project', v_project_id, v_company_id, v_branch_id, v_date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'location', v_location_id, v_company_id, v_branch_id, v_date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'functional_entity', v_functional_entity_id,
    v_company_id, v_branch_id, v_date, 'header'
  );

  FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
  LOOP
    v_line_number := v_line_number + 1;
    IF NULLIF(v_line->>'source_document_type', '') IS NOT NULL THEN
      IF v_line->>'source_document_type' NOT IN ('sales_order', 'DR') THEN
        RAISE EXCEPTION 'Unsupported Sales Invoice source document type % on line %',
          v_line->>'source_document_type', v_line_number;
      END IF;
      IF v_line->>'source_document_type' = 'sales_order' AND NOT EXISTS (
        SELECT 1
        FROM sales_order_lines sol
        JOIN sales_orders so ON so.id = sol.sales_order_id
        WHERE sol.id = NULLIF(v_line->>'source_line_id', '')::UUID
          AND sol.company_id = v_company_id
          AND so.company_id = v_company_id
          AND so.customer_id = (p_header->>'customer_id')::UUID
      ) THEN
        RAISE EXCEPTION 'Invalid Sales Order source line for Sales Invoice line %',
          v_line_number;
      END IF;
      -- Billing a delivery: the line must trace to a DELIVERED delivery line of
      -- this company and this customer. Anything else would let an invoice claim
      -- a clearing balance that was never created.
      IF v_line->>'source_document_type' = 'DR' AND NOT EXISTS (
        SELECT 1
        FROM delivery_receipt_lines drl
        JOIN delivery_receipts dr ON dr.id = drl.dr_id
        WHERE drl.id = NULLIF(v_line->>'source_line_id', '')::UUID
          AND drl.company_id = v_company_id
          AND dr.company_id = v_company_id
          AND dr.customer_id = (p_header->>'customer_id')::UUID
          AND dr.status = 'delivered'
      ) THEN
        RAISE EXCEPTION 'Invalid or undelivered Delivery Receipt source line for Sales Invoice line %',
          v_line_number;
      END IF;
    END IF;
    PERFORM fn_assert_sales_invoice_dimension(
      'project', COALESCE(NULLIF(v_line->>'project_id', '')::UUID, v_project_id),
      v_company_id, v_branch_id, v_date, 'line ' || v_line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'location', COALESCE(NULLIF(v_line->>'location_id', '')::UUID, v_location_id),
      v_company_id, v_branch_id, v_date, 'line ' || v_line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'functional_entity',
      COALESCE(NULLIF(v_line->>'functional_entity_id', '')::UUID, v_functional_entity_id),
      v_company_id, v_branch_id, v_date, 'line ' || v_line_number
    );
  END LOOP;

  v_invoice_id := fn_save_sales_invoice_aud053_core(p_invoice_id, p_header, p_lines);

  UPDATE sales_invoices
  SET project_id = v_project_id,
      location_id = v_location_id,
      functional_entity_id = v_functional_entity_id,
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = v_invoice_id;

  WITH payload AS (
    SELECT
      ordinality::INTEGER AS line_number,
      NULLIF(value->>'project_id', '')::UUID AS project_id,
      NULLIF(value->>'location_id', '')::UUID AS location_id,
      NULLIF(value->>'functional_entity_id', '')::UUID AS functional_entity_id
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) WITH ORDINALITY
  )
  UPDATE sales_invoice_lines sil
  SET project_id = COALESCE(payload.project_id, v_project_id),
      location_id = COALESCE(payload.location_id, v_location_id),
      functional_entity_id = COALESCE(
        payload.functional_entity_id, v_functional_entity_id
      ),
      updated_by = auth.uid(),
      updated_at = NOW()
  FROM payload
  WHERE sil.sales_invoice_id = v_invoice_id
    AND sil.line_number = payload.line_number;

  RETURN v_invoice_id;
END;
$function$

;
