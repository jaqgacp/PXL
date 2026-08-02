-- ============================================================================
-- PXL-AUD-073 — Receiving Report inventory-to-GL posting
-- ============================================================================
-- DEFECT
--   fn_confirm_receiving_report increased stock (stock_balances, cost layers,
--   inventory_transactions) and never produced a journal entry. Measured on the
--   canonical dataset: 3 confirmed Receiving Reports, 3 stock movements, and
--   0 journal entries with reference_doc_type = 'RR'. Inventory therefore could
--   not reconcile to its control account, which is the stated blocker on
--   Posting Engine P6 and on Inventory module certification.
--
-- FIX (standard goods-received-not-invoiced accounting)
--   Receiving Report  : DR Inventory control      / CR Purchase Clearing
--   Vendor Bill       : DR Purchase Clearing      / CR AP        (already built)
--   Net effect        : Inventory is debited, AP credited, clearing nets to nil.
--
--   Account 5010 "Purchases / Inventory Clearing" already exists in every
--   company and vendor_bill_lines.expense_account_id already points at it for
--   inventory items. Only the receipt half was missing, so this migration
--   changes the receipt side and leaves the vendor-bill routine untouched.
--
-- SECONDARY DEFECT — cost-layer drift
--   fn_receive_inventory created a cost layer for every receipt including
--   weighted-average items, but every outflow path consumes layers only for
--   fifo/specific_identification. Layers therefore accumulated and never
--   depleted: 477 units created, 477 remaining, against 448 units on hand.
--   Layer creation is now gated on costing method, symmetric with consumption.
--
-- POSTING BOUNDARY
--   All ledger writes go through the sanctioned kernel functions
--   (fn_create_posted_journal_entry / fn_add_posting_line /
--   fn_finalize_journal_entry). No kernel, guard or totality change is made.
-- ============================================================================

-- ── 1. Governed account keys ────────────────────────────────────────────────
-- PURCHASE_CLEARING deliberately declares no expected account type. Goods
-- received not invoiced is conventionally a **liability** — the goods are held
-- and owed for but not yet billed — and that is what the standard template ships
-- as `2015`. Some existing charts instead settle the receipt against a
-- purchases/clearing account classified as an expense. Both net to zero once the
-- vendor bill posts, and the resolver must not reject a company for choosing the
-- more correct one. Constraining this key to `expense` (which an early draft did,
-- because it was inferred from a legacy demo chart) made a properly configured
-- company fail to receive stock at all.
INSERT INTO ref_mapping_key (key_code, description, expected_account_type, is_active)
VALUES
  ('INVENTORY_CONTROL', 'Inventory control / stock on hand', 'asset', true),
  ('PURCHASE_CLEARING', 'Goods received not invoiced / purchase clearing (liability by convention; an expense-classified clearing account is also accepted)', NULL, true)
ON CONFLICT (key_code) DO UPDATE
  SET description           = EXCLUDED.description,
      expected_account_type = EXCLUDED.expected_account_type,
      is_active             = true;

-- company_accounting_config is the single writable authority for account
-- determination; account_mapping is its projection. Both new keys therefore
-- get a config column rather than a hard-coded account code. Account codes are
-- NOT interchangeable across companies: the standard template uses 1200 for
-- Accounts Receivable and 1300 for Inventory, while the canonical demo COA uses
-- 1200 for Inventory and 5010 for purchase clearing. Anything that resolves an
-- inventory account by literal code is wrong for one of them.
ALTER TABLE company_accounting_config
  ADD COLUMN IF NOT EXISTS inventory_account_id        UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS purchase_clearing_account_id UUID REFERENCES chart_of_accounts(id);

-- A goods-received-not-invoiced account for newly provisioned companies. The
-- standard template had no clearing account at all, which is part of why the
-- receipt side was never posted.
INSERT INTO coa_template_lines (
  template_id, account_code, account_name, account_type, normal_balance,
  is_postable, parent_account_code, fs_group, fs_subgroup,
  is_control_account, allow_subledger, sort_order
)
SELECT t.template_id, '2015', 'Goods Received Not Invoiced', 'liability', 'credit',
       true, '2000', 'liabilities', 'Current Liabilities', false, false,
       COALESCE(MAX(t.sort_order), 0) + 1
FROM coa_template_lines t
WHERE NOT EXISTS (
  SELECT 1 FROM coa_template_lines x
  WHERE x.template_id = t.template_id AND x.account_code = '2015'
)
GROUP BY t.template_id;

-- Backfill the config for existing companies from what is demonstrably already
-- in use, rather than from an assumed code:
--   inventory        <- the account the item master already posts stock to
--   purchase clearing <- the account vendor bills already debit for inventory
--                        lines, else an explicitly clearing-named account
UPDATE company_accounting_config cfg
SET inventory_account_id = COALESCE(cfg.inventory_account_id, src.account_id)
FROM (
  SELECT DISTINCT ON (i.company_id) i.company_id, i.inventory_account_id AS account_id
  FROM items i
  WHERE i.item_type = 'inventory_item' AND i.inventory_account_id IS NOT NULL
) src
WHERE src.company_id = cfg.company_id
  AND cfg.inventory_account_id IS NULL;

UPDATE company_accounting_config cfg
SET purchase_clearing_account_id = COALESCE(cfg.purchase_clearing_account_id, src.account_id)
FROM (
  SELECT DISTINCT ON (a.company_id) a.company_id, a.id AS account_id
  FROM chart_of_accounts a
  WHERE a.is_postable
    AND (
      EXISTS (
        SELECT 1 FROM vendor_bill_lines vbl
        JOIN items i ON i.id = vbl.item_id
        WHERE vbl.expense_account_id = a.id AND i.item_type = 'inventory_item'
      )
      OR a.account_name ILIKE '%clearing%'
      OR a.account_code = '2015'
    )
  ORDER BY a.company_id,
           (EXISTS (
              SELECT 1 FROM vendor_bill_lines vbl
              JOIN items i ON i.id = vbl.item_id
              WHERE vbl.expense_account_id = a.id AND i.item_type = 'inventory_item'
           )) DESC,
           a.account_code
) src
WHERE src.company_id = cfg.company_id
  AND cfg.purchase_clearing_account_id IS NULL;

-- Project the two new config columns into account_mapping. Body is unchanged
-- apart from the two added rows.
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
      ('AR_TRADE',              v_cfg.ar_account_id),
      ('AP_TRADE',              v_cfg.ap_account_id),
      ('VAT_OUTPUT',            v_cfg.vat_payable_account_id),
      ('VAT_INPUT',             v_cfg.input_vat_account_id),
      ('EWT_WITHHELD',          v_cfg.ewt_withheld_account_id),
      ('EWT_PAYABLE',           v_cfg.ewt_payable_account_id),
      ('CASH_DEFAULT',          v_cfg.default_cash_account_id),
      ('CUSTOMER_ADVANCES',     v_cfg.customer_advances_account_id),
      ('SUPPLIER_DOWNPAYMENTS', v_cfg.supplier_down_payments_account_id),
      ('INVENTORY_CONTROL',     v_cfg.inventory_account_id),
      ('PURCHASE_CLEARING',     v_cfg.purchase_clearing_account_id)
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

REVOKE ALL ON FUNCTION fn_sync_account_mapping_from_config(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_sync_account_mapping_from_config(UUID) TO service_role;

-- Default the two new accounts when a company is provisioned. 1300 Inventory
-- and 2015 Goods Received Not Invoiced are the standard template codes; a
-- company whose chart differs keeps whatever the config already holds.
CREATE OR REPLACE FUNCTION fn_provision_company_accounting_config(p_company_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config_id UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision accounting config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO company_accounting_config (company_id, created_by, updated_by)
  VALUES (p_company_id, auth.uid(), auth.uid())
  ON CONFLICT (company_id) DO NOTHING;

  UPDATE company_accounting_config cfg
     SET ar_account_id           = COALESCE(cfg.ar_account_id,           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1200' AND is_postable)),
         default_cash_account_id = COALESCE(cfg.default_cash_account_id, (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1010' AND is_postable)),
         vat_payable_account_id  = COALESCE(cfg.vat_payable_account_id,  (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2100' AND is_postable)),
         ewt_withheld_account_id = COALESCE(cfg.ewt_withheld_account_id, (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1410' AND is_postable)),
         ap_account_id           = COALESCE(cfg.ap_account_id,           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2010' AND is_postable)),
         input_vat_account_id    = COALESCE(cfg.input_vat_account_id,    (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1400' AND is_postable)),
         ewt_payable_account_id  = COALESCE(cfg.ewt_payable_account_id,  (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2110' AND is_postable)),
         customer_advances_account_id = COALESCE(cfg.customer_advances_account_id,
           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2050' AND is_postable)),
         supplier_down_payments_account_id = COALESCE(cfg.supplier_down_payments_account_id,
           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1350' AND is_postable)),
         inventory_account_id    = COALESCE(cfg.inventory_account_id,
           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1300' AND is_postable)),
         purchase_clearing_account_id = COALESCE(cfg.purchase_clearing_account_id,
           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2015' AND is_postable)),
         updated_by = auth.uid()
   WHERE cfg.company_id = p_company_id;

  PERFORM fn_sync_coa_control_accounts(p_company_id);
  SELECT id INTO v_config_id
  FROM company_accounting_config
  WHERE company_id = p_company_id;
  RETURN v_config_id;
END;
$$;

-- Project the backfilled config for every existing company.
DO $sync$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT company_id FROM company_accounting_config LOOP
    PERFORM fn_sync_account_mapping_from_config(r.company_id);
  END LOOP;
END;
$sync$;

-- ── 2. Register RR as a governed posting source ─────────────────────────────
INSERT INTO ref_posting_source_types (
  document_type, source_table, document_number_column, document_date_column,
  status_column, route_path, display_name,
  allows_multiple_journal_entries, is_active
) VALUES (
  'RR', 'receiving_reports', 'rr_number', 'rr_date',
  'status', '/receiving-reports', 'Receiving Report', false, true
)
ON CONFLICT (document_type) DO UPDATE
  SET source_table                    = EXCLUDED.source_table,
      document_number_column          = EXCLUDED.document_number_column,
      document_date_column            = EXCLUDED.document_date_column,
      status_column                   = EXCLUDED.status_column,
      route_path                      = EXCLUDED.route_path,
      display_name                    = EXCLUDED.display_name,
      allows_multiple_journal_entries = EXCLUDED.allows_multiple_journal_entries,
      is_active                       = true;

-- ── 3. Journal linkage on the source document ───────────────────────────────
ALTER TABLE receiving_reports
  ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id),
  ADD COLUMN IF NOT EXISTS fiscal_period_id UUID REFERENCES fiscal_periods(id),
  ADD COLUMN IF NOT EXISTS posted_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS posted_by        UUID;

-- The status-immutability guard must permit the posting-linkage columns on a
-- confirmed receipt, exactly as it already does for every other posting
-- document (sales invoices, vendor bills, payment vouchers). Business fields
-- stay immutable; only journal linkage and posting stamps become writable.
DROP TRIGGER IF EXISTS trg_guard_header_receiving_reports ON receiving_reports;
CREATE TRIGGER trg_guard_header_receiving_reports
  BEFORE DELETE OR UPDATE ON receiving_reports
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header(
    'status', 'draft',
    'confirmed_by,confirmed_at,journal_entry_id,fiscal_period_id,posted_at,posted_by',
    '', 'same_txn');

-- ── 4. Stop creating cost layers for weighted-average items ─────────────────
CREATE OR REPLACE FUNCTION fn_receive_inventory(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id    UUID    := (p_data->>'company_id')::UUID;
  v_warehouse_id  UUID    := (p_data->>'warehouse_id')::UUID;
  v_item_id       UUID    := (p_data->>'item_id')::UUID;
  v_qty           NUMERIC := (p_data->>'qty')::NUMERIC;
  v_unit_cost     NUMERIC := (p_data->>'unit_cost')::NUMERIC;
  v_date          DATE    := (p_data->>'receipt_date')::DATE;
  v_lot           TEXT    := p_data->>'lot_number';
  v_serial        TEXT    := p_data->>'serial_number';
  v_ref_type      TEXT    := p_data->>'reference_doc_type';
  v_ref_id        UUID    := (p_data->>'reference_doc_id')::UUID;
  v_item          items%ROWTYPE;
  v_tx_id         UUID;
  v_sb            stock_balances%ROWTYPE;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_qty <= 0 THEN RAISE EXCEPTION 'Receipt qty must be positive'; END IF;

  SELECT * INTO v_item FROM items WHERE id = v_item_id;

  IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
    PERFORM fn_update_wac(v_warehouse_id, v_item_id, v_qty, v_unit_cost);
  END IF;

  v_sb := fn_ensure_stock_balance(v_company_id, v_warehouse_id, v_item_id);

  UPDATE stock_balances
  SET qty_on_hand       = qty_on_hand + v_qty,
      total_cost        = total_cost + (v_qty * v_unit_cost),
      last_receipt_date = v_date,
      updated_at        = NOW()
  WHERE warehouse_id = v_warehouse_id AND item_id = v_item_id;

  IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
    UPDATE stock_balances
    SET wac_unit_cost = CASE WHEN (qty_on_hand) > 0
        THEN ROUND(total_cost / qty_on_hand, 6)
        ELSE 0 END
    WHERE warehouse_id = v_warehouse_id AND item_id = v_item_id;
  END IF;

  -- PXL-AUD-073: cost layers exist to support fifo / specific identification.
  -- Every outflow path consumes layers only for those methods, so creating a
  -- layer for a weighted-average item produced a layer that could never be
  -- depleted. Creation is now symmetric with consumption. Weighted-average
  -- quantity and value remain authoritative in stock_balances.
  IF v_item.costing_method IN ('fifo', 'specific_identification') THEN
    PERFORM fn_add_cost_layer(
      v_company_id, v_warehouse_id, v_item_id, v_date,
      v_qty, v_unit_cost, v_ref_type, v_ref_id, v_lot, v_serial
    );
  END IF;

  SELECT qty_on_hand INTO v_sb.qty_on_hand FROM stock_balances
  WHERE warehouse_id = v_warehouse_id AND item_id = v_item_id;

  INSERT INTO inventory_transactions (
    company_id, warehouse_id, item_id, transaction_type, transaction_date,
    qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
    reference_doc_type, reference_doc_id, lot_number, serial_number,
    notes, created_by
  ) VALUES (
    v_company_id, v_warehouse_id, v_item_id, 'receipt', v_date,
    v_qty, v_unit_cost, ROUND(v_qty * v_unit_cost, 2), v_sb.qty_on_hand,
    v_item.costing_method,
    v_ref_type, v_ref_id, v_lot, v_serial,
    p_data->>'notes', auth.uid()
  ) RETURNING id INTO v_tx_id;

  RETURN v_tx_id;
END;
$$;

-- ── 5. Receiving Report journal ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_receiving_report_source_locked_impl(p_rr_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rr        receiving_reports%ROWTYPE;
  v_clearing  UUID;
  v_je_id     UUID;
  v_fp_id     UUID;
  v_line      RECORD;
  v_line_no   INTEGER := 1;
  v_total     NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO STRICT v_rr FROM receiving_reports WHERE id = p_rr_id;

  SELECT COALESCE(SUM(ROUND(rrl.received_qty * rrl.unit_price, 2)), 0)
  INTO v_total
  FROM receiving_report_lines rrl
  JOIN items i ON i.id = rrl.item_id
  WHERE rrl.rr_id = v_rr.id
    AND rrl.received_qty > 0
    AND i.item_type = 'inventory_item';

  -- A receipt with no inventory value has no accounting effect.
  IF v_total <= 0 THEN
    RETURN NULL;
  END IF;

  v_clearing := fn_resolve_posting_account(
    v_rr.company_id, 'PURCHASE_CLEARING', v_rr.rr_date,
    'Purchase clearing account not configured. Set it up in GL Posting Configuration.'
  );

  v_je_id := fn_create_posted_journal_entry(
    v_rr.company_id, v_rr.branch_id,
    'JE-RR-' || v_rr.rr_number, v_rr.rr_date,
    'Goods Receipt ' || v_rr.rr_number || ' - ' || COALESCE(v_rr.supplier_name_snapshot, 'Supplier'),
    'RR', v_rr.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  -- DR inventory control, grouped by the account the item master resolves to.
  FOR v_line IN
    SELECT i.inventory_account_id AS account_id,
           SUM(ROUND(rrl.received_qty * rrl.unit_price, 2)) AS amount
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
      AND i.inventory_account_id IS NOT NULL
    GROUP BY i.inventory_account_id
    HAVING SUM(ROUND(rrl.received_qty * rrl.unit_price, 2)) <> 0
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.account_id,
      'Inventory received - ' || v_rr.rr_number,
      v_line.amount, 0,
      v_rr.branch_id, v_rr.department_id, v_rr.cost_center_id,
      NULL, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  -- CR purchase clearing; the vendor bill debits this same account.
  PERFORM fn_add_posting_line(
    v_je_id, v_line_no, v_clearing,
    'Goods received not invoiced - ' || v_rr.rr_number,
    0, v_total,
    v_rr.branch_id, v_rr.department_id, v_rr.cost_center_id,
    NULL, NULL, NULL
  );

  PERFORM fn_finalize_journal_entry(
    v_je_id, v_total, v_total, true, NULL, NULL, false, NULL, false, false
  );

  UPDATE receiving_reports
  SET journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id,
      posted_at        = NOW(),
      posted_by        = auth.uid(),
      updated_by       = auth.uid(),
      updated_at       = NOW()
  WHERE id = p_rr_id;

  PERFORM fn_record_posting_event(
    v_rr.company_id, 'RR', v_rr.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rr.rr_date, 'basis', 'goods_received_not_invoiced')
  );

  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_receiving_report(p_rr_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting('RR', p_rr_id, ARRAY['draft'], ARRAY['received']);
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;

  v_je_id := fn_post_receiving_report_source_locked_impl(p_rr_id);

  IF v_je_id IS NOT NULL THEN
    PERFORM fn_complete_secondary_posting('RR', p_rr_id, v_je_id);
  END IF;

  RETURN v_je_id;
END;
$$;

-- ── 6. Confirm now posts before the status transition ───────────────────────
CREATE OR REPLACE FUNCTION fn_confirm_receiving_report(p_rr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

-- Match the tight grant convention used by fn_post_vendor_bill. PostgreSQL
-- grants EXECUTE to PUBLIC by default, which would have handed the posting
-- entry point to anon; revoke first, then grant explicitly. The source-locked
-- implementation stays owner-only and is reachable only through its guard.
REVOKE ALL ON FUNCTION fn_post_receiving_report(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_post_receiving_report_source_locked_impl(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_post_receiving_report(UUID) TO authenticated, service_role;

-- ── 7. Backfill already-confirmed receipts ──────────────────────────────────
-- These receipts moved stock before the defect was fixed, so their inventory
-- value has no ledger counterpart. None of them is linked to a posted vendor
-- bill (vendor_bills.rr_id is null for every bill in the dataset), so posting
-- them now cannot double-count. Journals are dated at the original rr_date.
DO $backfill$
DECLARE
  v_rr        RECORD;
  v_clearing  UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INTEGER;
  v_total     NUMERIC(15,2);
  v_actor     UUID;
  v_prior     TEXT := current_setting('request.jwt.claims', true);
BEGIN
  FOR v_rr IN
    SELECT r.*
    FROM receiving_reports r
    WHERE r.status = 'received'
      AND r.journal_entry_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM journal_entries je
        WHERE je.reference_doc_type = 'RR' AND je.reference_doc_id = r.id
      )
    ORDER BY r.rr_date, r.rr_number
  LOOP
    SELECT COALESCE(SUM(ROUND(rrl.received_qty * rrl.unit_price, 2)), 0)
    INTO v_total
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item';

    CONTINUE WHEN v_total <= 0;

    SELECT account_id INTO v_clearing
    FROM account_mapping
    WHERE company_id = v_rr.company_id AND key_code = 'PURCHASE_CLEARING'
    LIMIT 1;
    CONTINUE WHEN v_clearing IS NULL;

    -- The sanctioned posting functions authorise against auth.uid(). A
    -- migration has no request identity, so adopt an existing member of the
    -- owning company for the duration of this backfill. A company with no
    -- membership is skipped rather than posted without an accountable actor.
    SELECT user_id INTO v_actor
    FROM user_company_memberships
    WHERE company_id = v_rr.company_id
    ORDER BY granted_at
    LIMIT 1;
    CONTINUE WHEN v_actor IS NULL;

    PERFORM set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', v_actor::text, 'role', 'authenticated')::text,
      true
    );

    v_je_id := fn_create_posted_journal_entry(
      v_rr.company_id, v_rr.branch_id,
      'JE-RR-' || v_rr.rr_number, v_rr.rr_date,
      'Goods Receipt ' || v_rr.rr_number || ' - ' || COALESCE(v_rr.supplier_name_snapshot, 'Supplier'),
      'RR', v_rr.id,
      NULL, 'posted', 0, 0, 'system', 'regular', false, true
    );

    v_line_no := 1;
    FOR v_line IN
      SELECT i.inventory_account_id AS account_id,
             SUM(ROUND(rrl.received_qty * rrl.unit_price, 2)) AS amount
      FROM receiving_report_lines rrl
      JOIN items i ON i.id = rrl.item_id
      WHERE rrl.rr_id = v_rr.id
        AND rrl.received_qty > 0
        AND i.item_type = 'inventory_item'
        AND i.inventory_account_id IS NOT NULL
      GROUP BY i.inventory_account_id
      HAVING SUM(ROUND(rrl.received_qty * rrl.unit_price, 2)) <> 0
    LOOP
      PERFORM fn_add_posting_line(
        v_je_id, v_line_no, v_line.account_id,
        'Inventory received - ' || v_rr.rr_number,
        v_line.amount, 0,
        v_rr.branch_id, v_rr.department_id, v_rr.cost_center_id,
        NULL, NULL, NULL
      );
      v_line_no := v_line_no + 1;
    END LOOP;

    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_clearing,
      'Goods received not invoiced - ' || v_rr.rr_number,
      0, v_total,
      v_rr.branch_id, v_rr.department_id, v_rr.cost_center_id,
      NULL, NULL, NULL
    );

    PERFORM fn_finalize_journal_entry(
      v_je_id, v_total, v_total, true, NULL, NULL, false, NULL, false, false
    );

    UPDATE receiving_reports
    SET journal_entry_id = v_je_id,
        fiscal_period_id = (SELECT fiscal_period_id FROM journal_entries WHERE id = v_je_id),
        posted_at        = NOW(),
        updated_at       = NOW()
    WHERE id = v_rr.id;
  END LOOP;

  PERFORM set_config('request.jwt.claims', COALESCE(v_prior, ''), true);
END;
$backfill$;

-- ── 8. Retire undepletable weighted-average cost layers ─────────────────────
-- These layers were created by the pre-fix receipt path for weighted-average
-- items and no outflow path could ever consume them. The rows are retained as
-- history; their remaining quantity is zeroed so that layer quantity can no
-- longer disagree with stock on hand. Weighted-average value remains
-- authoritative in stock_balances.
UPDATE inventory_cost_layers l
SET qty_remaining = 0,
    is_exhausted  = true
FROM items i
WHERE i.id = l.item_id
  AND (i.costing_method = 'weighted_average' OR i.costing_method IS NULL)
  AND l.qty_remaining > 0;
