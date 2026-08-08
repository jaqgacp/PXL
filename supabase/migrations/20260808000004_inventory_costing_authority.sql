-- ============================================================================
-- Inventory costing authority: exact FIFO allocations, Specific-ID identity,
-- reversible movements, and costing-method succession guards.
--
-- This is the production inventory authority.  The separate IA-5/ECC tables
-- remain dormant and untouched: their admission-order chronology is not safe to
-- activate.  Every active stock writer is migrated onto the helpers below in
-- this and the immediately following additive migration.
-- ============================================================================

-- ── 1. Identity and immutable costing evidence ──────────────────────────────
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS specific_id_tracking TEXT
    CHECK (specific_id_tracking IN ('serial', 'lot'));

COMMENT ON COLUMN public.items.specific_id_tracking IS
  'Required for Specific Identification items: serial means one unit per identity; lot means a selected traceable lot may carry quantity.';

ALTER TABLE public.receiving_report_lines
  ADD COLUMN IF NOT EXISTS lot_number TEXT,
  ADD COLUMN IF NOT EXISTS serial_number TEXT,
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

ALTER TABLE public.delivery_receipt_lines
  ADD COLUMN IF NOT EXISTS lot_number TEXT,
  ADD COLUMN IF NOT EXISTS serial_number TEXT,
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id);

ALTER TABLE public.sales_invoice_lines
  ADD COLUMN IF NOT EXISTS lot_number TEXT,
  ADD COLUMN IF NOT EXISTS serial_number TEXT,
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id);

ALTER TABLE public.cash_purchase_lines
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES public.warehouses(id),
  ADD COLUMN IF NOT EXISTS lot_number TEXT,
  ADD COLUMN IF NOT EXISTS serial_number TEXT,
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

ALTER TABLE public.goods_issue_lines
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

ALTER TABLE public.stock_adjustment_lines
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

ALTER TABLE public.stock_transfer_lines
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS source_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id),
  ADD COLUMN IF NOT EXISTS destination_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

ALTER TABLE public.physical_count_sheet_lines
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS source_line_id UUID,
  ADD COLUMN IF NOT EXISTS reverses_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id),
  ADD COLUMN IF NOT EXISTS reversed_by_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id),
  ADD COLUMN IF NOT EXISTS restores_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_transaction_one_reversal
  ON public.inventory_transactions(reverses_inventory_transaction_id)
  WHERE reverses_inventory_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_transaction_source_line
  ON public.inventory_transactions(reference_doc_type, reference_doc_id, source_line_id);

ALTER TABLE public.inventory_cost_layers
  ADD COLUMN IF NOT EXISTS source_line_id UUID,
  ADD COLUMN IF NOT EXISTS origin_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id),
  ADD COLUMN IF NOT EXISTS parent_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS original_value NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS remaining_value NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS voided_by_inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

UPDATE public.inventory_cost_layers
SET original_value = COALESCE(original_value, ROUND(original_qty * unit_cost, 2)),
    remaining_value = COALESCE(remaining_value, ROUND(qty_remaining * unit_cost, 2))
WHERE original_value IS NULL OR remaining_value IS NULL;

ALTER TABLE public.inventory_cost_layers
  ALTER COLUMN original_value SET NOT NULL,
  ALTER COLUMN remaining_value SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_specific_serial
  ON public.inventory_cost_layers(company_id, item_id, serial_number)
  WHERE serial_number IS NOT NULL AND qty_remaining > 0
    AND voided_by_inventory_transaction_id IS NULL;

CREATE TABLE IF NOT EXISTS public.inventory_layer_allocations (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               UUID NOT NULL REFERENCES public.companies(id),
  inventory_transaction_id UUID NOT NULL REFERENCES public.inventory_transactions(id),
  layer_id                 UUID NOT NULL REFERENCES public.inventory_cost_layers(id),
  allocation_kind          TEXT NOT NULL
    CHECK (allocation_kind IN ('consume', 'restore', 'receipt_cancel', 'return', 'transfer_in')),
  quantity                 NUMERIC(15,4) NOT NULL CHECK (quantity > 0),
  unit_cost                NUMERIC(18,6) NOT NULL,
  total_cost               NUMERIC(18,2) NOT NULL CHECK (total_cost >= 0),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (inventory_transaction_id, layer_id, allocation_kind)
);

CREATE INDEX IF NOT EXISTS idx_inventory_layer_allocations_layer
  ON public.inventory_layer_allocations(layer_id, created_at);

ALTER TABLE public.inventory_layer_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventory_layer_allocations_read ON public.inventory_layer_allocations;
CREATE POLICY inventory_layer_allocations_read
  ON public.inventory_layer_allocations FOR SELECT TO authenticated
  USING (is_company_member(company_id));

REVOKE ALL ON public.inventory_layer_allocations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.inventory_layer_allocations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.inventory_layer_allocations TO service_role;

-- Inventory projections and costing evidence are RPC-maintained.  The old RLS
-- write policies did not make direct REST mutation an accounting authority.
REVOKE INSERT, UPDATE, DELETE ON public.stock_balances FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.inventory_cost_layers FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.inventory_transactions FROM anon, authenticated;

-- ── 2. Costing-method succession fails closed while valuation is open ───────
CREATE OR REPLACE FUNCTION public.fn_guard_item_costing_method_succession()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.costing_method = 'specific_identification'
     AND NEW.specific_id_tracking IS NULL THEN
    RAISE EXCEPTION 'Specific Identification requires serial or lot tracking before the item can be saved'
      USING ERRCODE = '23514';
  END IF;

  IF (NEW.costing_method, NEW.specific_id_tracking)
       IS DISTINCT FROM (OLD.costing_method, OLD.specific_id_tracking)
     AND (
       EXISTS (
         SELECT 1 FROM stock_balances sb
         WHERE sb.item_id = OLD.id
           AND (ABS(sb.qty_on_hand) > 0.0001 OR ABS(sb.total_cost) > 0.01)
       )
       OR EXISTS (
         SELECT 1 FROM inventory_cost_layers l
         WHERE l.item_id = OLD.id AND l.qty_remaining > 0
           AND l.voided_by_inventory_transaction_id IS NULL
       )
     ) THEN
    RAISE EXCEPTION 'Costing method or Specific-ID tracking cannot change while item % has open inventory valuation. Clear or convert the inventory first.',
      OLD.item_code USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_item_costing_method_succession ON public.items;
CREATE TRIGGER trg_item_costing_method_succession
  BEFORE UPDATE OF costing_method, specific_id_tracking ON public.items
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_item_costing_method_succession();

CREATE OR REPLACE FUNCTION public.fn_guard_company_costing_method_succession()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.default_costing_method IS DISTINCT FROM OLD.default_costing_method
     AND (
       EXISTS (
         SELECT 1 FROM items i JOIN stock_balances sb ON sb.item_id = i.id
         WHERE i.company_id = OLD.company_id AND i.costing_method IS NULL
           AND (ABS(sb.qty_on_hand) > 0.0001 OR ABS(sb.total_cost) > 0.01)
       )
       OR EXISTS (
         SELECT 1 FROM items i JOIN inventory_cost_layers l ON l.item_id = i.id
         WHERE i.company_id = OLD.company_id AND i.costing_method IS NULL
           AND l.qty_remaining > 0 AND l.voided_by_inventory_transaction_id IS NULL
       )
     ) THEN
    RAISE EXCEPTION 'Default costing method cannot change while inheriting items have open inventory valuation. Clear or convert the inventory first.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_company_costing_method_succession
  ON public.company_inventory_config;
CREATE TRIGGER trg_company_costing_method_succession
  BEFORE UPDATE OF default_costing_method ON public.company_inventory_config
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_company_costing_method_succession();

-- ── 3. Shared inbound authority ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_receive_inventory(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id    UUID    := NULLIF(p_data->>'company_id', '')::UUID;
  v_warehouse_id  UUID    := NULLIF(p_data->>'warehouse_id', '')::UUID;
  v_item_id       UUID    := NULLIF(p_data->>'item_id', '')::UUID;
  v_qty           NUMERIC := NULLIF(p_data->>'qty', '')::NUMERIC;
  v_unit_cost     NUMERIC := NULLIF(p_data->>'unit_cost', '')::NUMERIC;
  v_date          DATE    := COALESCE(NULLIF(p_data->>'receipt_date', '')::DATE, CURRENT_DATE);
  v_lot           TEXT    := NULLIF(BTRIM(COALESCE(p_data->>'lot_number', '')), '');
  v_serial        TEXT    := NULLIF(BTRIM(COALESCE(p_data->>'serial_number', '')), '');
  v_ref_type      TEXT    := NULLIF(p_data->>'reference_doc_type', '');
  v_ref_id        UUID    := NULLIF(p_data->>'reference_doc_id', '')::UUID;
  v_source_line   UUID    := NULLIF(p_data->>'source_line_id', '')::UUID;
  v_journal_id    UUID    := NULLIF(p_data->>'journal_entry_id', '')::UUID;
  v_parent_layer  UUID    := NULLIF(p_data->>'parent_layer_id', '')::UUID;
  v_item          items%ROWTYPE;
  v_method        TEXT;
  v_tx_id         UUID;
  v_layer_id      UUID;
  v_sb            stock_balances%ROWTYPE;
  v_total         NUMERIC(18,2);
BEGIN
  IF v_company_id IS NULL OR NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Receipt qty must be positive'; END IF;
  IF v_unit_cost IS NULL OR v_unit_cost < 0 THEN RAISE EXCEPTION 'Receipt unit cost cannot be negative'; END IF;

  SELECT * INTO v_item FROM items WHERE id = v_item_id AND company_id = v_company_id;
  IF NOT FOUND OR v_item.item_type <> 'inventory_item' THEN
    RAISE EXCEPTION 'Inventory item not found in company';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM warehouses w
    WHERE w.id = v_warehouse_id AND w.company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Warehouse does not belong to the company';
  END IF;

  v_method := fn_item_costing_method(v_item_id);
  IF v_method = 'specific_identification' THEN
    IF v_item.specific_id_tracking = 'serial' THEN
      IF v_serial IS NULL OR v_qty <> 1 THEN
        RAISE EXCEPTION 'Serial-tracked item % requires one serial number per receipt line and quantity exactly 1', v_item.item_code
          USING ERRCODE = '23514';
      END IF;
    ELSIF v_item.specific_id_tracking = 'lot' THEN
      IF v_lot IS NULL THEN
        RAISE EXCEPTION 'Lot-tracked item % requires a lot number', v_item.item_code
          USING ERRCODE = '23514';
      END IF;
    ELSE
      RAISE EXCEPTION 'Specific Identification item % has no governed tracking basis', v_item.item_code
        USING ERRCODE = '23514';
    END IF;
  END IF;

  v_total := ROUND(v_qty * v_unit_cost, 2);
  v_sb := fn_ensure_stock_balance(v_company_id, v_warehouse_id, v_item_id);
  PERFORM 1 FROM stock_balances
  WHERE company_id = v_company_id AND warehouse_id = v_warehouse_id AND item_id = v_item_id
  FOR UPDATE;

  UPDATE stock_balances
  SET qty_on_hand       = qty_on_hand + v_qty,
      total_cost        = total_cost + v_total,
      last_receipt_date = v_date,
      updated_at        = now()
  WHERE company_id = v_company_id AND warehouse_id = v_warehouse_id AND item_id = v_item_id;

  IF v_method = 'weighted_average' THEN
    UPDATE stock_balances
    SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
    WHERE company_id = v_company_id AND warehouse_id = v_warehouse_id AND item_id = v_item_id;
  END IF;

  INSERT INTO inventory_transactions (
    company_id, warehouse_id, item_id, transaction_type, transaction_date,
    qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
    reference_doc_type, reference_doc_id, source_line_id, journal_entry_id,
    lot_number, serial_number, notes, created_by,
    project_id, location_id, functional_entity_id, restores_inventory_transaction_id
  )
  SELECT v_company_id, v_warehouse_id, v_item_id, 'receipt', v_date,
    v_qty, v_unit_cost, v_total, sb.qty_on_hand, v_method,
    v_ref_type, v_ref_id, v_source_line, v_journal_id,
    v_lot, v_serial, p_data->>'notes', auth.uid(),
    NULLIF(p_data->>'project_id', '')::UUID,
    NULLIF(p_data->>'location_id', '')::UUID,
    NULLIF(p_data->>'functional_entity_id', '')::UUID,
    NULLIF(p_data->>'restores_inventory_transaction_id', '')::UUID
  FROM stock_balances sb
  WHERE sb.company_id = v_company_id AND sb.warehouse_id = v_warehouse_id AND sb.item_id = v_item_id
  RETURNING id INTO v_tx_id;

  IF v_method IN ('fifo', 'specific_identification') THEN
    INSERT INTO inventory_cost_layers (
      company_id, warehouse_id, item_id, layer_date,
      reference_doc_type, reference_doc_id, source_line_id,
      lot_number, serial_number, original_qty, qty_remaining,
      unit_cost, original_value, remaining_value, is_exhausted,
      origin_inventory_transaction_id, parent_layer_id
    ) VALUES (
      v_company_id, v_warehouse_id, v_item_id, v_date,
      v_ref_type, v_ref_id, v_source_line,
      v_lot, v_serial, v_qty, v_qty,
      v_unit_cost, v_total, v_total, false,
      v_tx_id, v_parent_layer
    ) RETURNING id INTO v_layer_id;
  END IF;

  RETURN v_tx_id;
END;
$$;

-- ── 4. Shared outbound authority ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_issue_inventory(p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id     UUID    := NULLIF(p_data->>'company_id', '')::UUID;
  v_warehouse_id   UUID    := NULLIF(p_data->>'warehouse_id', '')::UUID;
  v_item_id        UUID    := NULLIF(p_data->>'item_id', '')::UUID;
  v_qty            NUMERIC := NULLIF(p_data->>'qty', '')::NUMERIC;
  v_date           DATE    := COALESCE(NULLIF(p_data->>'transaction_date', '')::DATE, CURRENT_DATE);
  v_ref_type       TEXT    := NULLIF(p_data->>'reference_doc_type', '');
  v_ref_id         UUID    := NULLIF(p_data->>'reference_doc_id', '')::UUID;
  v_source_line    UUID    := NULLIF(p_data->>'source_line_id', '')::UUID;
  v_journal_id     UUID    := NULLIF(p_data->>'journal_entry_id', '')::UUID;
  v_selected_layer UUID    := NULLIF(p_data->>'inventory_cost_layer_id', '')::UUID;
  v_lot            TEXT    := NULLIF(BTRIM(COALESCE(p_data->>'lot_number', '')), '');
  v_serial         TEXT    := NULLIF(BTRIM(COALESCE(p_data->>'serial_number', '')), '');
  v_tx_type        TEXT    := COALESCE(NULLIF(p_data->>'transaction_type', ''), 'issue');
  v_item           items%ROWTYPE;
  v_method         TEXT;
  v_sb             stock_balances%ROWTYPE;
  v_layer          inventory_cost_layers%ROWTYPE;
  v_remaining      NUMERIC;
  v_take           NUMERIC;
  v_take_value     NUMERIC(18,2);
  v_total          NUMERIC(18,2) := 0;
  v_tx_id          UUID;
  v_allocs         JSONB := '[]'::JSONB;
  v_matches        INTEGER;
BEGIN
  IF v_company_id IS NULL OR NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Issue qty must be positive'; END IF;
  IF v_tx_type NOT IN ('issue', 'adjustment_out', 'transfer_out', 'count_variance_out') THEN
    RAISE EXCEPTION 'Unsupported outbound inventory transaction type %', v_tx_type;
  END IF;

  SELECT * INTO v_item FROM items WHERE id = v_item_id AND company_id = v_company_id;
  IF NOT FOUND OR v_item.item_type <> 'inventory_item' THEN RAISE EXCEPTION 'Inventory item not found in company'; END IF;
  IF NOT EXISTS (SELECT 1 FROM warehouses WHERE id = v_warehouse_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Warehouse does not belong to the company';
  END IF;
  v_method := fn_item_costing_method(v_item_id);

  PERFORM fn_ensure_stock_balance(v_company_id, v_warehouse_id, v_item_id);
  SELECT * INTO v_sb FROM stock_balances
  WHERE company_id = v_company_id AND warehouse_id = v_warehouse_id AND item_id = v_item_id
  FOR UPDATE;
  IF COALESCE(v_sb.qty_on_hand, 0) < v_qty THEN
    RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
      v_item.item_code, COALESCE(v_sb.qty_on_hand, 0), v_qty USING ERRCODE = '23514';
  END IF;

  IF v_method = 'weighted_average' THEN
    v_total := CASE WHEN v_qty = v_sb.qty_on_hand THEN v_sb.total_cost
                    ELSE ROUND(v_qty * v_sb.total_cost / NULLIF(v_sb.qty_on_hand, 0), 2) END;
  ELSIF v_method = 'specific_identification' THEN
    IF v_item.specific_id_tracking IS NULL THEN
      RAISE EXCEPTION 'Specific Identification item % has no governed tracking basis', v_item.item_code USING ERRCODE = '23514';
    END IF;
    IF v_selected_layer IS NULL AND v_lot IS NULL AND v_serial IS NULL THEN
      RAISE EXCEPTION 'Specific Identification item % requires an available serial/lot selection', v_item.item_code USING ERRCODE = '23514';
    END IF;

    IF v_selected_layer IS NULL THEN
      SELECT COUNT(*) INTO v_matches
      FROM inventory_cost_layers l
      WHERE l.company_id = v_company_id AND l.warehouse_id = v_warehouse_id
        AND l.item_id = v_item_id AND l.qty_remaining > 0
        AND l.voided_by_inventory_transaction_id IS NULL
        AND (v_lot IS NULL OR l.lot_number = v_lot)
        AND (v_serial IS NULL OR l.serial_number = v_serial);
      IF v_matches <> 1 THEN
        RAISE EXCEPTION 'Specific Identification selection must resolve exactly one available layer; found %', v_matches USING ERRCODE = '23514';
      END IF;
    END IF;

    SELECT * INTO v_layer
    FROM inventory_cost_layers l
    WHERE l.company_id = v_company_id AND l.warehouse_id = v_warehouse_id
      AND l.item_id = v_item_id AND l.qty_remaining > 0
      AND l.voided_by_inventory_transaction_id IS NULL
      AND (v_selected_layer IS NULL OR l.id = v_selected_layer)
      AND (v_lot IS NULL OR l.lot_number = v_lot)
      AND (v_serial IS NULL OR l.serial_number = v_serial)
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Selected inventory identity is unavailable or belongs to another item, warehouse, or company' USING ERRCODE = '23514'; END IF;
    IF v_item.specific_id_tracking = 'serial' AND (v_layer.serial_number IS NULL OR v_qty <> 1) THEN
      RAISE EXCEPTION 'Serial-tracked issues require the exact serial and quantity 1' USING ERRCODE = '23514';
    END IF;
    IF v_layer.qty_remaining < v_qty THEN
      RAISE EXCEPTION 'Selected identity has % available but % was requested', v_layer.qty_remaining, v_qty USING ERRCODE = '23514';
    END IF;
    v_take_value := CASE WHEN v_qty = v_layer.qty_remaining THEN v_layer.remaining_value
                         ELSE ROUND(v_qty * v_layer.remaining_value / v_layer.qty_remaining, 2) END;
    v_total := v_take_value;
    v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
      'layer_id', v_layer.id, 'quantity', v_qty,
      'unit_cost', CASE WHEN v_qty > 0 THEN ROUND(v_take_value / v_qty, 6) ELSE 0 END,
      'total_cost', v_take_value));
    UPDATE inventory_cost_layers
    SET qty_remaining = qty_remaining - v_qty,
        remaining_value = remaining_value - v_take_value,
        is_exhausted = (qty_remaining - v_qty = 0)
    WHERE id = v_layer.id;
    v_lot := v_layer.lot_number;
    v_serial := v_layer.serial_number;
  ELSE
    v_remaining := v_qty;
    FOR v_layer IN
      SELECT l.* FROM inventory_cost_layers l
      WHERE l.company_id = v_company_id AND l.warehouse_id = v_warehouse_id
        AND l.item_id = v_item_id AND l.qty_remaining > 0
        AND l.voided_by_inventory_transaction_id IS NULL
      ORDER BY l.layer_date, l.created_at, l.id
      FOR UPDATE
    LOOP
      EXIT WHEN v_remaining = 0;
      v_take := LEAST(v_layer.qty_remaining, v_remaining);
      v_take_value := CASE WHEN v_take = v_layer.qty_remaining THEN v_layer.remaining_value
                           ELSE ROUND(v_take * v_layer.remaining_value / v_layer.qty_remaining, 2) END;
      v_total := v_total + v_take_value;
      v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
        'layer_id', v_layer.id, 'quantity', v_take,
        'unit_cost', CASE WHEN v_take > 0 THEN ROUND(v_take_value / v_take, 6) ELSE 0 END,
        'total_cost', v_take_value));
      UPDATE inventory_cost_layers
      SET qty_remaining = qty_remaining - v_take,
          remaining_value = remaining_value - v_take_value,
          is_exhausted = (qty_remaining - v_take = 0)
      WHERE id = v_layer.id;
      v_remaining := v_remaining - v_take;
    END LOOP;
    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'Insufficient FIFO layers for item %. Short by %', v_item.item_code, v_remaining USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_total > v_sb.total_cost + 0.01 THEN
    RAISE EXCEPTION 'Inventory layer value % exceeds stock projection value % for item %', v_total, v_sb.total_cost, v_item.item_code USING ERRCODE = '23514';
  END IF;

  UPDATE stock_balances
  SET qty_on_hand = qty_on_hand - v_qty,
      total_cost = total_cost - v_total,
      wac_unit_cost = CASE
        WHEN v_method = 'weighted_average' AND qty_on_hand - v_qty > 0
          THEN ROUND((total_cost - v_total) / (qty_on_hand - v_qty), 6)
        WHEN v_method = 'weighted_average' THEN 0 ELSE wac_unit_cost END,
      last_issue_date = v_date,
      updated_at = now()
  WHERE company_id = v_company_id AND warehouse_id = v_warehouse_id AND item_id = v_item_id;

  INSERT INTO inventory_transactions (
    company_id, warehouse_id, item_id, transaction_type, transaction_date,
    qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
    reference_doc_type, reference_doc_id, source_line_id, journal_entry_id,
    lot_number, serial_number, notes, created_by,
    project_id, location_id, functional_entity_id
  )
  SELECT v_company_id, v_warehouse_id, v_item_id, v_tx_type, v_date,
    -v_qty, CASE WHEN v_qty > 0 THEN ROUND(v_total / v_qty, 6) ELSE 0 END, -v_total,
    sb.qty_on_hand, v_method, v_ref_type, v_ref_id, v_source_line, v_journal_id,
    v_lot, v_serial, p_data->>'notes', auth.uid(),
    NULLIF(p_data->>'project_id', '')::UUID,
    NULLIF(p_data->>'location_id', '')::UUID,
    NULLIF(p_data->>'functional_entity_id', '')::UUID
  FROM stock_balances sb
  WHERE sb.company_id = v_company_id AND sb.warehouse_id = v_warehouse_id AND sb.item_id = v_item_id
  RETURNING id INTO v_tx_id;

  IF v_method IN ('fifo', 'specific_identification') THEN
    INSERT INTO inventory_layer_allocations (
      company_id, inventory_transaction_id, layer_id, allocation_kind,
      quantity, unit_cost, total_cost
    )
    SELECT v_company_id, v_tx_id, (a->>'layer_id')::UUID, 'consume',
      (a->>'quantity')::NUMERIC, (a->>'unit_cost')::NUMERIC, (a->>'total_cost')::NUMERIC
    FROM jsonb_array_elements(v_allocs) AS a;
  END IF;

  RETURN jsonb_build_object(
    'inventory_transaction_id', v_tx_id,
    'costing_method', v_method,
    'unit_cost', CASE WHEN v_qty > 0 THEN ROUND(v_total / v_qty, 6) ELSE 0 END,
    'total_cost', v_total,
    'lot_number', v_lot,
    'serial_number', v_serial
  );
END;
$$;

-- ── 5. Exact inverse events ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_reverse_inventory_issue(
  p_inventory_transaction_id UUID,
  p_reversal_date             DATE,
  p_reference_doc_type        TEXT,
  p_reference_doc_id          UUID,
  p_source_line_id            UUID,
  p_journal_entry_id          UUID,
  p_notes                     TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original inventory_transactions%ROWTYPE;
  v_reverse  UUID;
  v_alloc    RECORD;
BEGIN
  SELECT * INTO v_original FROM inventory_transactions
  WHERE id = p_inventory_transaction_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_original.company_id) THEN
    RAISE EXCEPTION 'Inventory issue not found or access denied';
  END IF;
  IF v_original.qty >= 0 THEN RAISE EXCEPTION 'Only an outbound inventory transaction can be restored'; END IF;
  IF v_original.reversed_by_inventory_transaction_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM inventory_transactions WHERE reverses_inventory_transaction_id = v_original.id) THEN
    RAISE EXCEPTION 'Inventory transaction is already reversed' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM inventory_transactions WHERE restores_inventory_transaction_id = v_original.id) THEN
    RAISE EXCEPTION 'Inventory issue already has a live return; correct the return before voiding the source' USING ERRCODE = '23514';
  END IF;

  PERFORM fn_ensure_stock_balance(v_original.company_id, v_original.warehouse_id, v_original.item_id);
  PERFORM 1 FROM stock_balances
  WHERE company_id = v_original.company_id AND warehouse_id = v_original.warehouse_id AND item_id = v_original.item_id
  FOR UPDATE;

  IF v_original.costing_method IN ('fifo', 'specific_identification') THEN
    IF NOT EXISTS (SELECT 1 FROM inventory_layer_allocations WHERE inventory_transaction_id = v_original.id AND allocation_kind = 'consume') THEN
      RAISE EXCEPTION 'Layered issue has no persisted allocation evidence and cannot be reversed safely' USING ERRCODE = '23514';
    END IF;
    FOR v_alloc IN
      SELECT a.*, l.qty_remaining, l.remaining_value
      FROM inventory_layer_allocations a
      JOIN inventory_cost_layers l ON l.id = a.layer_id
      WHERE a.inventory_transaction_id = v_original.id AND a.allocation_kind = 'consume'
      ORDER BY a.id
      FOR UPDATE OF l
    LOOP
      UPDATE inventory_cost_layers
      SET qty_remaining = qty_remaining + v_alloc.quantity,
          remaining_value = remaining_value + v_alloc.total_cost,
          is_exhausted = false
      WHERE id = v_alloc.layer_id;
    END LOOP;
  END IF;

  UPDATE stock_balances
  SET qty_on_hand = qty_on_hand + ABS(v_original.qty),
      total_cost = total_cost + ABS(v_original.total_cost),
      wac_unit_cost = CASE
        WHEN v_original.costing_method = 'weighted_average' AND qty_on_hand + ABS(v_original.qty) > 0
          THEN ROUND((total_cost + ABS(v_original.total_cost)) / (qty_on_hand + ABS(v_original.qty)), 6)
        ELSE wac_unit_cost END,
      last_receipt_date = COALESCE(p_reversal_date, CURRENT_DATE), updated_at = now()
  WHERE company_id = v_original.company_id AND warehouse_id = v_original.warehouse_id AND item_id = v_original.item_id;

  INSERT INTO inventory_transactions (
    company_id, warehouse_id, item_id, transaction_type, transaction_date,
    qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
    reference_doc_type, reference_doc_id, source_line_id, journal_entry_id,
    lot_number, serial_number, notes, created_by,
    project_id, location_id, functional_entity_id,
    reverses_inventory_transaction_id
  )
  SELECT v_original.company_id, v_original.warehouse_id, v_original.item_id,
    'adjustment_in', COALESCE(p_reversal_date, CURRENT_DATE),
    ABS(v_original.qty), v_original.unit_cost, ABS(v_original.total_cost), sb.qty_on_hand,
    v_original.costing_method, p_reference_doc_type, p_reference_doc_id,
    p_source_line_id, p_journal_entry_id, v_original.lot_number, v_original.serial_number,
    p_notes, auth.uid(), v_original.project_id, v_original.location_id,
    v_original.functional_entity_id, v_original.id
  FROM stock_balances sb
  WHERE sb.company_id = v_original.company_id AND sb.warehouse_id = v_original.warehouse_id AND sb.item_id = v_original.item_id
  RETURNING id INTO v_reverse;

  UPDATE inventory_transactions SET reversed_by_inventory_transaction_id = v_reverse
  WHERE id = v_original.id;

  INSERT INTO inventory_layer_allocations (
    company_id, inventory_transaction_id, layer_id, allocation_kind,
    quantity, unit_cost, total_cost
  )
  SELECT company_id, v_reverse, layer_id, 'restore', quantity, unit_cost, total_cost
  FROM inventory_layer_allocations
  WHERE inventory_transaction_id = v_original.id AND allocation_kind = 'consume';

  RETURN v_reverse;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_reverse_inventory_receipt(
  p_inventory_transaction_id UUID,
  p_reversal_date             DATE,
  p_reference_doc_type        TEXT,
  p_reference_doc_id          UUID,
  p_source_line_id            UUID,
  p_journal_entry_id          UUID,
  p_notes                     TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original inventory_transactions%ROWTYPE;
  v_reverse  UUID;
  v_layer    RECORD;
BEGIN
  SELECT * INTO v_original FROM inventory_transactions
  WHERE id = p_inventory_transaction_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_original.company_id) THEN
    RAISE EXCEPTION 'Inventory receipt not found or access denied';
  END IF;
  IF v_original.qty <= 0 THEN RAISE EXCEPTION 'Only an inbound inventory transaction can be cancelled'; END IF;
  IF v_original.reversed_by_inventory_transaction_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM inventory_transactions WHERE reverses_inventory_transaction_id = v_original.id) THEN
    RAISE EXCEPTION 'Inventory transaction is already reversed' USING ERRCODE = '23514';
  END IF;

  PERFORM fn_ensure_stock_balance(v_original.company_id, v_original.warehouse_id, v_original.item_id);
  PERFORM 1 FROM stock_balances
  WHERE company_id = v_original.company_id AND warehouse_id = v_original.warehouse_id AND item_id = v_original.item_id
  FOR UPDATE;

  IF v_original.costing_method = 'weighted_average' AND EXISTS (
    SELECT 1 FROM inventory_transactions later
    WHERE later.company_id = v_original.company_id
      AND later.warehouse_id = v_original.warehouse_id
      AND later.item_id = v_original.item_id
      AND later.created_at > v_original.created_at
      AND later.qty < 0
      AND later.reversed_by_inventory_transaction_id IS NULL
      AND later.reverses_inventory_transaction_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot cancel receipt: the weighted-average pool has a live downstream outbound movement. Reverse downstream inventory first.'
      USING ERRCODE = '23514';
  END IF;

  IF v_original.costing_method IN ('fifo', 'specific_identification') THEN
    FOR v_layer IN
      SELECT * FROM inventory_cost_layers
      WHERE origin_inventory_transaction_id = v_original.id
      ORDER BY id FOR UPDATE
    LOOP
      IF v_layer.qty_remaining <> v_layer.original_qty
         OR v_layer.remaining_value <> v_layer.original_value THEN
        RAISE EXCEPTION 'Cannot cancel receipt: cost layer % has downstream consumption. Reverse the dependent issue or transfer first.', v_layer.id
          USING ERRCODE = '23514';
      END IF;
    END LOOP;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Layered receipt has no origin layer evidence and cannot be cancelled safely' USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE stock_balances
  SET qty_on_hand = qty_on_hand - v_original.qty,
      total_cost = total_cost - v_original.total_cost,
      wac_unit_cost = CASE
        WHEN v_original.costing_method = 'weighted_average' AND qty_on_hand - v_original.qty > 0
          THEN ROUND((total_cost - v_original.total_cost) / (qty_on_hand - v_original.qty), 6)
        WHEN v_original.costing_method = 'weighted_average' THEN 0 ELSE wac_unit_cost END,
      last_issue_date = COALESCE(p_reversal_date, CURRENT_DATE), updated_at = now()
  WHERE company_id = v_original.company_id AND warehouse_id = v_original.warehouse_id
    AND item_id = v_original.item_id
    AND qty_on_hand >= v_original.qty AND total_cost >= v_original.total_cost;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cannot cancel receipt: locked stock quantity or value is insufficient for the original receipt'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO inventory_transactions (
    company_id, warehouse_id, item_id, transaction_type, transaction_date,
    qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
    reference_doc_type, reference_doc_id, source_line_id, journal_entry_id,
    lot_number, serial_number, notes, created_by,
    reverses_inventory_transaction_id
  )
  SELECT v_original.company_id, v_original.warehouse_id, v_original.item_id,
    'adjustment_out', COALESCE(p_reversal_date, CURRENT_DATE),
    -v_original.qty, v_original.unit_cost, -v_original.total_cost, sb.qty_on_hand,
    v_original.costing_method, p_reference_doc_type, p_reference_doc_id,
    p_source_line_id, p_journal_entry_id, v_original.lot_number, v_original.serial_number,
    p_notes, auth.uid(), v_original.id
  FROM stock_balances sb
  WHERE sb.company_id = v_original.company_id AND sb.warehouse_id = v_original.warehouse_id AND sb.item_id = v_original.item_id
  RETURNING id INTO v_reverse;

  UPDATE inventory_transactions SET reversed_by_inventory_transaction_id = v_reverse
  WHERE id = v_original.id;

  UPDATE inventory_cost_layers
  SET qty_remaining = 0, remaining_value = 0, is_exhausted = true,
      voided_by_inventory_transaction_id = v_reverse
  WHERE origin_inventory_transaction_id = v_original.id;

  INSERT INTO inventory_layer_allocations (
    company_id, inventory_transaction_id, layer_id, allocation_kind,
    quantity, unit_cost, total_cost
  )
  SELECT v_original.company_id, v_reverse, l.id, 'receipt_cancel',
    l.original_qty, l.unit_cost, l.original_value
  FROM inventory_cost_layers l WHERE l.origin_inventory_transaction_id = v_original.id;

  RETURN v_reverse;
END;
$$;

-- ── 6. Receiving Report identity reachability and exact cancellation ────────
CREATE OR REPLACE FUNCTION public.fn_save_receiving_report(
  p_rr_id UUID, p_header JSONB, p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_warehouse_id UUID;
  v_department_id UUID;
  v_cost_center_id UUID;
BEGIN
  SELECT
    COALESCE(NULLIF(p_header->>'warehouse_id', '')::UUID, po.warehouse_id),
    COALESCE(NULLIF(p_header->>'department_id', '')::UUID, po.department_id),
    COALESCE(NULLIF(p_header->>'cost_center_id', '')::UUID, po.cost_center_id)
  INTO v_warehouse_id, v_department_id, v_cost_center_id
  FROM purchase_orders po
  WHERE po.id = (p_header->>'po_id')::UUID AND po.company_id = v_company_id;

  PERFORM fn_validate_purchase_dimensions(
    v_company_id, v_branch_id, v_warehouse_id, v_department_id, v_cost_center_id
  );
  v_id := fn_save_receiving_report_core_20260718(p_rr_id, p_header, p_lines);
  UPDATE receiving_reports
  SET warehouse_id = v_warehouse_id, department_id = v_department_id,
      cost_center_id = v_cost_center_id, updated_at = now(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;

  WITH payload AS (
    SELECT ordinality::INTEGER AS line_number,
      NULLIF(BTRIM(COALESCE(value->>'lot_number', '')), '') AS lot_number,
      NULLIF(BTRIM(COALESCE(value->>'serial_number', '')), '') AS serial_number
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) WITH ORDINALITY
  )
  UPDATE receiving_report_lines rrl
  SET lot_number = payload.lot_number, serial_number = payload.serial_number,
      updated_at = now()
  FROM payload WHERE rrl.rr_id = v_id AND rrl.line_number = payload.line_number;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_confirm_receiving_report(p_rr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rr receiving_reports%ROWTYPE;
  v_receipt RECORD;
  v_tx_id UUID;
  v_je_id UUID;
BEGIN
  SELECT * INTO v_rr FROM receiving_reports WHERE id = p_rr_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN RAISE EXCEPTION 'Receiving report not found or access denied'; END IF;
  IF v_rr.status <> 'draft' THEN RAISE EXCEPTION 'Only draft RRs can be confirmed (current: %)', v_rr.status; END IF;

  PERFORM fn_validate_purchase_dimensions(v_rr.company_id, v_rr.branch_id, v_rr.warehouse_id, v_rr.department_id, v_rr.cost_center_id);
  PERFORM fn_assert_receipt_within_po(p_rr_id);
  IF EXISTS (
    SELECT 1 FROM receiving_report_lines rrl JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id AND rrl.received_qty > 0 AND i.company_id <> v_rr.company_id
  ) THEN RAISE EXCEPTION 'A receiving-report item does not belong to this company'; END IF;
  IF v_rr.warehouse_id IS NULL AND EXISTS (
    SELECT 1 FROM receiving_report_lines rrl JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id AND rrl.received_qty > 0 AND i.item_type = 'inventory_item'
  ) THEN RAISE EXCEPTION 'Warehouse is required to confirm inventory-item receipts'; END IF;
  IF EXISTS (
    SELECT 1 FROM receiving_report_lines rrl JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item' AND i.inventory_account_id IS NULL
  ) THEN RAISE EXCEPTION 'An inventory item on this receipt has no inventory account configured'; END IF;

  PERFORM fn_post_receiving_report(p_rr_id);
  SELECT journal_entry_id INTO v_je_id FROM receiving_reports WHERE id = p_rr_id;

  FOR v_receipt IN
    SELECT rrl.id, rrl.line_number, rrl.item_id, rrl.received_qty AS qty,
      rrl.unit_price AS unit_cost, rrl.lot_number, rrl.serial_number
    FROM receiving_report_lines rrl JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id AND rrl.received_qty > 0 AND i.item_type = 'inventory_item'
    ORDER BY rrl.line_number
  LOOP
    v_tx_id := fn_receive_inventory(jsonb_build_object(
      'company_id', v_rr.company_id, 'warehouse_id', v_rr.warehouse_id,
      'item_id', v_receipt.item_id, 'qty', v_receipt.qty,
      'unit_cost', v_receipt.unit_cost, 'receipt_date', v_rr.rr_date,
      'reference_doc_type', 'RR', 'reference_doc_id', v_rr.id,
      'source_line_id', v_receipt.id, 'journal_entry_id', v_je_id,
      'lot_number', v_receipt.lot_number, 'serial_number', v_receipt.serial_number,
      'notes', COALESCE(v_rr.remarks, 'Goods Receipt ' || v_rr.rr_number) || ' line ' || v_receipt.line_number
    ));
    UPDATE receiving_report_lines SET inventory_transaction_id = v_tx_id,
      updated_at = now() WHERE id = v_receipt.id;
  END LOOP;
  PERFORM fn_confirm_receiving_report_status_core_20260718(p_rr_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_void_receiving_report(
  p_rr_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rr receiving_reports%ROWTYPE;
  v_reversal_id UUID;
  v_reason TEXT;
  v_billed TEXT;
  v_line RECORD;
  v_tx_id UUID;
BEGIN
  SELECT * INTO v_rr FROM receiving_reports WHERE id = p_rr_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN RAISE EXCEPTION 'Receiving report not found or access denied'; END IF;
  IF v_rr.status = 'cancelled' THEN RAISE EXCEPTION 'Receiving report is already cancelled'; END IF;
  IF p_void_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive void reason'; END IF;
  END IF;
  v_reason := COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), v_reason);
  IF v_reason IS NULL THEN RAISE EXCEPTION 'A void reason is required'; END IF;
  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  SELECT vb.bill_number INTO v_billed FROM vendor_bills vb
  WHERE vb.rr_id = v_rr.id AND vb.company_id = v_rr.company_id AND vb.status <> 'cancelled' LIMIT 1;
  IF v_billed IS NOT NULL THEN
    RAISE EXCEPTION 'Receiving Report % is billed by Vendor Bill %. Void that bill first, then cancel this receipt.', v_rr.rr_number, v_billed USING ERRCODE = '23514';
  END IF;

  IF v_rr.journal_entry_id IS NOT NULL THEN
    PERFORM fn_assert_source_journal_link('RR', v_rr.id, v_rr.journal_entry_id, v_rr.company_id);
    v_reversal_id := fn_reverse_posted_journal_entry(
      v_rr.journal_entry_id, CURRENT_DATE, 'REV', v_rr.id,
      'JE-REV-' || v_rr.rr_number,
      'Reversal of RR ' || v_rr.rr_number || ' (' || COALESCE(v_rr.supplier_name_snapshot, 'Supplier') || ') - ' || v_reason
    );

    FOR v_line IN
      SELECT rrl.* FROM receiving_report_lines rrl JOIN items i ON i.id = rrl.item_id
      WHERE rrl.rr_id = v_rr.id AND rrl.received_qty > 0 AND i.item_type = 'inventory_item'
      ORDER BY rrl.line_number
    LOOP
      v_tx_id := v_line.inventory_transaction_id;
      IF v_tx_id IS NULL THEN
        SELECT it.id INTO v_tx_id FROM inventory_transactions it
        WHERE it.company_id = v_rr.company_id AND it.warehouse_id = v_rr.warehouse_id
          AND it.item_id = v_line.item_id AND it.reference_doc_type = 'RR'
          AND it.reference_doc_id = v_rr.id AND it.qty > 0
        ORDER BY it.created_at LIMIT 1;
      END IF;
      IF v_tx_id IS NULL THEN RAISE EXCEPTION 'Receipt line % has no inventory transaction evidence', v_line.line_number USING ERRCODE = '23514'; END IF;
      PERFORM fn_reverse_inventory_receipt(
        v_tx_id, CURRENT_DATE, 'RR_VOID', v_rr.id, v_line.id, v_reversal_id,
        'Cancellation of Goods Receipt ' || v_rr.rr_number || ' line ' || v_line.line_number
      );
    END LOOP;
  END IF;

  UPDATE receiving_reports SET status = 'cancelled', void_reason_id = p_void_reason_id,
    void_memo = COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), void_memo),
    updated_by = auth.uid(), updated_at = now() WHERE id = v_rr.id;

  UPDATE purchase_orders po
  SET status = CASE WHEN progress.received_qty >= progress.ordered_qty THEN 'fully_received'
                    WHEN progress.received_qty > 0 THEN 'partially_received' ELSE 'approved' END,
      updated_by = auth.uid(), updated_at = now()
  FROM (
    SELECT COALESCE(SUM(pol.quantity), 0) AS ordered_qty,
           COALESCE(SUM(rec.received_qty), 0) AS received_qty
    FROM purchase_order_lines pol
    LEFT JOIN LATERAL (
      SELECT SUM(rrl.received_qty) AS received_qty
      FROM receiving_report_lines rrl JOIN receiving_reports rr ON rr.id = rrl.rr_id
      WHERE rrl.po_line_id = pol.id AND rr.status = 'received'
    ) rec ON TRUE WHERE pol.po_id = v_rr.po_id
  ) progress
  WHERE po.id = v_rr.po_id AND po.company_id = v_rr.company_id AND po.status <> 'cancelled';

  PERFORM fn_record_posting_event(v_rr.company_id, 'RR', v_rr.id, 'VOIDED', v_reversal_id,
    jsonb_build_object('void_reason_id', p_void_reason_id, 'reason', v_reason));
END;
$$;

COMMENT ON FUNCTION public.fn_issue_inventory(JSONB) IS
  'One outbound costing authority for WAC, FIFO, and Specific Identification. Locks stock/layers, persists exact allocations, and returns the authoritative cost stamp.';
COMMENT ON FUNCTION public.fn_reverse_inventory_issue(UUID,DATE,TEXT,UUID,UUID,UUID,TEXT) IS
  'Restores an outbound movement from its historical transaction and exact layer allocations; never recomputes current FIFO or identity.';
COMMENT ON FUNCTION public.fn_reverse_inventory_receipt(UUID,DATE,TEXT,UUID,UUID,UUID,TEXT) IS
  'Cancels a receipt only when downstream costing state is safe, retaining the original layer and immutable inverse transaction evidence.';

REVOKE ALL ON FUNCTION public.fn_issue_inventory(JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_reverse_inventory_issue(UUID,DATE,TEXT,UUID,UUID,UUID,TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_reverse_inventory_receipt(UUID,DATE,TEXT,UUID,UUID,UUID,TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_guard_item_costing_method_succession() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_guard_company_costing_method_succession() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.fn_void_receiving_report(UUID,UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_void_receiving_report(UUID,UUID,TEXT) TO authenticated, service_role;
