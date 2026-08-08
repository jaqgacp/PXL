-- ============================================================================
-- Route the existing committed posting surfaces through the production costing
-- evidence authority without cloning their accounting or tax logic.
--
-- The legacy posting bodies remain the one Posting Engine implementation. Thin
-- wrappers stage source-line identity; the shared layer helper persists the
-- exact allocation; an inventory-transaction trigger binds the two atomically.
-- ============================================================================

-- ── 1. Transaction-local bridge used only inside SECURITY DEFINER writers ───
CREATE TABLE public.inventory_costing_runtime_queue (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backend_pid              INTEGER NOT NULL,
  local_txid               BIGINT NOT NULL,
  sequence_no              INTEGER NOT NULL,
  operation                TEXT NOT NULL CHECK (operation IN ('issue', 'reverse')),
  company_id               UUID NOT NULL REFERENCES public.companies(id),
  warehouse_id             UUID NOT NULL REFERENCES public.warehouses(id),
  item_id                  UUID NOT NULL REFERENCES public.items(id),
  source_line_id           UUID,
  inventory_cost_layer_id  UUID REFERENCES public.inventory_cost_layers(id),
  lot_number               TEXT,
  serial_number            TEXT,
  original_transaction_id  UUID REFERENCES public.inventory_transactions(id),
  selection_consumed       BOOLEAN NOT NULL DEFAULT false,
  layers_restored          BOOLEAN NOT NULL DEFAULT false,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (backend_pid, local_txid, operation, sequence_no)
);

CREATE TABLE public.inventory_costing_pending_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backend_pid       INTEGER NOT NULL,
  local_txid        BIGINT NOT NULL,
  company_id        UUID NOT NULL REFERENCES public.companies(id),
  warehouse_id      UUID NOT NULL REFERENCES public.warehouses(id),
  item_id           UUID NOT NULL REFERENCES public.items(id),
  source_line_id    UUID,
  quantity          NUMERIC(15,4) NOT NULL CHECK (quantity > 0),
  total_cost        NUMERIC(18,2) NOT NULL CHECK (total_cost >= 0),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.inventory_costing_pending_allocations (
  batch_id    UUID NOT NULL REFERENCES public.inventory_costing_pending_batches(id) ON DELETE CASCADE,
  layer_id    UUID NOT NULL REFERENCES public.inventory_cost_layers(id),
  quantity    NUMERIC(15,4) NOT NULL CHECK (quantity > 0),
  unit_cost   NUMERIC(18,6) NOT NULL,
  total_cost  NUMERIC(18,2) NOT NULL CHECK (total_cost >= 0),
  PRIMARY KEY (batch_id, layer_id)
);

ALTER TABLE public.inventory_costing_runtime_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_costing_pending_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_costing_pending_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.inventory_costing_runtime_queue FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.inventory_costing_pending_batches FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.inventory_costing_pending_allocations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_costing_runtime_queue TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_costing_pending_batches TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_costing_pending_allocations TO service_role;

-- ── 2. Current six-argument layer allocator, now concurrency-safe and evidenced
CREATE OR REPLACE FUNCTION public.fn_consume_cost_layers(
  p_company_id UUID,
  p_warehouse_id UUID,
  p_item_id UUID,
  p_qty NUMERIC,
  p_lot_number TEXT DEFAULT NULL,
  p_serial_number TEXT DEFAULT NULL
)
RETURNS TABLE(layer_id UUID, qty_consumed NUMERIC, unit_cost NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_method       TEXT;
  v_remaining    NUMERIC := p_qty;
  v_layer        inventory_cost_layers%ROWTYPE;
  v_take         NUMERIC;
  v_take_value   NUMERIC(18,2);
  v_total        NUMERIC(18,2) := 0;
  v_batch_id     UUID := gen_random_uuid();
  v_runtime      inventory_costing_runtime_queue%ROWTYPE;
  v_selected     UUID;
  v_lot          TEXT := NULLIF(BTRIM(COALESCE(p_lot_number, '')), '');
  v_serial       TEXT := NULLIF(BTRIM(COALESCE(p_serial_number, '')), '');
  v_matches      INTEGER;
BEGIN
  IF p_qty IS NULL OR p_qty <= 0 THEN RAISE EXCEPTION 'Issue qty must be positive'; END IF;
  IF NOT is_company_member(p_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  v_method := fn_item_costing_method(p_item_id);

  -- A posting wrapper stages the exact source line and browser selection.  The
  -- queue is private and transaction-local; a caller cannot forge it over REST.
  SELECT * INTO v_runtime
  FROM inventory_costing_runtime_queue q
  WHERE q.backend_pid = pg_backend_pid() AND q.local_txid = txid_current()
    AND q.operation = 'issue' AND q.company_id = p_company_id
    AND q.warehouse_id = p_warehouse_id AND q.item_id = p_item_id
    AND q.selection_consumed = false
  ORDER BY q.sequence_no
  LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    v_selected := v_runtime.inventory_cost_layer_id;
    v_lot := COALESCE(v_lot, v_runtime.lot_number);
    v_serial := COALESCE(v_serial, v_runtime.serial_number);
    UPDATE inventory_costing_runtime_queue SET selection_consumed = true WHERE id = v_runtime.id;
  END IF;

  -- Allocation rows reference this batch, so create the transaction-local
  -- header before consuming any layer and fill in the exact total afterward.
  INSERT INTO inventory_costing_pending_batches(
    id, backend_pid, local_txid, company_id, warehouse_id, item_id,
    source_line_id, quantity, total_cost
  ) VALUES (
    v_batch_id, pg_backend_pid(), txid_current(), p_company_id, p_warehouse_id,
    p_item_id, v_runtime.source_line_id, p_qty, 0
  );

  IF v_method = 'weighted_average' THEN
    RAISE EXCEPTION 'Weighted-average callers must use the stock pool, not cost layers';
  ELSIF v_method = 'specific_identification' THEN
    IF v_selected IS NULL AND v_lot IS NULL AND v_serial IS NULL THEN
      RAISE EXCEPTION 'Specific Identification requires an available serial/lot selection' USING ERRCODE = '23514';
    END IF;
    IF v_selected IS NULL THEN
      SELECT COUNT(*) INTO v_matches FROM inventory_cost_layers l
      WHERE l.company_id = p_company_id AND l.warehouse_id = p_warehouse_id
        AND l.item_id = p_item_id AND l.qty_remaining > 0
        AND l.voided_by_inventory_transaction_id IS NULL
        AND (v_lot IS NULL OR l.lot_number = v_lot)
        AND (v_serial IS NULL OR l.serial_number = v_serial);
      IF v_matches <> 1 THEN
        RAISE EXCEPTION 'Specific Identification selection must resolve exactly one available layer; found %', v_matches USING ERRCODE = '23514';
      END IF;
    END IF;
    SELECT * INTO v_layer FROM inventory_cost_layers l
    WHERE l.company_id = p_company_id AND l.warehouse_id = p_warehouse_id
      AND l.item_id = p_item_id AND l.qty_remaining > 0
      AND l.voided_by_inventory_transaction_id IS NULL
      AND (v_selected IS NULL OR l.id = v_selected)
      AND (v_lot IS NULL OR l.lot_number = v_lot)
      AND (v_serial IS NULL OR l.serial_number = v_serial)
    FOR UPDATE;
    IF NOT FOUND OR v_layer.qty_remaining < p_qty THEN
      RAISE EXCEPTION 'Selected inventory identity is unavailable or has insufficient quantity' USING ERRCODE = '23514';
    END IF;
    IF (SELECT specific_id_tracking FROM items WHERE id = p_item_id) = 'serial'
       AND (v_layer.serial_number IS NULL OR p_qty <> 1) THEN
      RAISE EXCEPTION 'Serial-tracked issues require the exact serial and quantity 1' USING ERRCODE = '23514';
    END IF;
    v_take_value := CASE WHEN p_qty = v_layer.qty_remaining THEN v_layer.remaining_value
                         ELSE ROUND(p_qty * v_layer.remaining_value / v_layer.qty_remaining, 2) END;
    UPDATE inventory_cost_layers
    SET qty_remaining = qty_remaining - p_qty,
        remaining_value = remaining_value - v_take_value,
        is_exhausted = (qty_remaining - p_qty = 0)
    WHERE id = v_layer.id;
    INSERT INTO inventory_costing_pending_allocations(batch_id, layer_id, quantity, unit_cost, total_cost)
    VALUES (v_batch_id, v_layer.id, p_qty, ROUND(v_take_value / p_qty, 6), v_take_value);
    layer_id := v_layer.id; qty_consumed := p_qty; unit_cost := ROUND(v_take_value / p_qty, 6);
    v_total := v_take_value;
    RETURN NEXT;
  ELSE
    FOR v_layer IN
      SELECT l.* FROM inventory_cost_layers l
      WHERE l.company_id = p_company_id AND l.warehouse_id = p_warehouse_id
        AND l.item_id = p_item_id AND l.qty_remaining > 0
        AND l.voided_by_inventory_transaction_id IS NULL
      ORDER BY l.layer_date, l.created_at, l.id
      FOR UPDATE
    LOOP
      EXIT WHEN v_remaining = 0;
      v_take := LEAST(v_layer.qty_remaining, v_remaining);
      v_take_value := CASE WHEN v_take = v_layer.qty_remaining THEN v_layer.remaining_value
                           ELSE ROUND(v_take * v_layer.remaining_value / v_layer.qty_remaining, 2) END;
      UPDATE inventory_cost_layers
      SET qty_remaining = qty_remaining - v_take,
          remaining_value = remaining_value - v_take_value,
          is_exhausted = (qty_remaining - v_take = 0)
      WHERE id = v_layer.id;
      INSERT INTO inventory_costing_pending_allocations(batch_id, layer_id, quantity, unit_cost, total_cost)
      VALUES (v_batch_id, v_layer.id, v_take, ROUND(v_take_value / v_take, 6), v_take_value);
      layer_id := v_layer.id; qty_consumed := v_take; unit_cost := ROUND(v_take_value / v_take, 6);
      v_total := v_total + v_take_value;
      v_remaining := v_remaining - v_take;
      RETURN NEXT;
    END LOOP;
    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'Insufficient FIFO layers. Short by %', v_remaining USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE inventory_costing_pending_batches
  SET total_cost = v_total
  WHERE id = v_batch_id;
END;
$$;

-- ── 3. Existing positive-layer helper gains exact value and void interception
CREATE OR REPLACE FUNCTION public.fn_add_cost_layer(
  p_company_id UUID, p_warehouse_id UUID, p_item_id UUID, p_layer_date DATE,
  p_qty NUMERIC, p_unit_cost NUMERIC, p_ref_doc_type TEXT DEFAULT NULL,
  p_ref_doc_id UUID DEFAULT NULL, p_lot_number TEXT DEFAULT NULL,
  p_serial_number TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_runtime inventory_costing_runtime_queue%ROWTYPE;
  v_alloc RECORD;
  v_total NUMERIC(18,2) := ROUND(p_qty * p_unit_cost, 2);
  v_method TEXT;
  v_tracking TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF p_qty <= 0 OR p_unit_cost < 0 THEN RAISE EXCEPTION 'Cost layer quantity/cost is invalid'; END IF;

  -- Legacy SI/DR void bodies already restore stock balance, then call this
  -- helper.  Intercept that call and restore the ORIGINAL allocations instead
  -- of manufacturing an anonymous replacement layer.
  IF p_ref_doc_type IN ('SI_VOID', 'DR_VOID') THEN
    SELECT * INTO v_runtime FROM inventory_costing_runtime_queue q
    WHERE q.backend_pid = pg_backend_pid() AND q.local_txid = txid_current()
      AND q.operation = 'reverse' AND q.company_id = p_company_id
      AND q.warehouse_id = p_warehouse_id AND q.item_id = p_item_id
      AND q.layers_restored = false
    ORDER BY q.sequence_no LIMIT 1 FOR UPDATE;
    IF NOT FOUND OR v_runtime.original_transaction_id IS NULL THEN
      RAISE EXCEPTION 'Void has no original inventory-allocation context' USING ERRCODE = '23514';
    END IF;
    FOR v_alloc IN
      SELECT a.* FROM inventory_layer_allocations a
      JOIN inventory_cost_layers l ON l.id = a.layer_id
      WHERE a.inventory_transaction_id = v_runtime.original_transaction_id
        AND a.allocation_kind = 'consume'
      ORDER BY a.id FOR UPDATE OF l
    LOOP
      UPDATE inventory_cost_layers
      SET qty_remaining = qty_remaining + v_alloc.quantity,
          remaining_value = remaining_value + v_alloc.total_cost,
          is_exhausted = false
      WHERE id = v_alloc.layer_id;
      v_id := COALESCE(v_id, v_alloc.layer_id);
    END LOOP;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Layered issue has no persisted allocation evidence' USING ERRCODE = '23514';
    END IF;
    UPDATE inventory_costing_runtime_queue SET layers_restored = true WHERE id = v_runtime.id;
    RETURN v_id;
  END IF;

  v_method := fn_item_costing_method(p_item_id);
  SELECT specific_id_tracking INTO v_tracking FROM items WHERE id = p_item_id;
  IF v_method = 'specific_identification' THEN
    IF v_tracking = 'serial' AND (NULLIF(BTRIM(COALESCE(p_serial_number, '')), '') IS NULL OR p_qty <> 1) THEN
      RAISE EXCEPTION 'Serial-tracked receipt requires one serial and quantity 1' USING ERRCODE = '23514';
    ELSIF v_tracking = 'lot' AND NULLIF(BTRIM(COALESCE(p_lot_number, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Lot-tracked receipt requires a lot number' USING ERRCODE = '23514';
    END IF;
  END IF;

  INSERT INTO inventory_cost_layers(
    company_id, warehouse_id, item_id, layer_date,
    reference_doc_type, reference_doc_id, lot_number, serial_number,
    original_qty, qty_remaining, unit_cost, original_value, remaining_value,
    is_exhausted
  ) VALUES (
    p_company_id, p_warehouse_id, p_item_id, p_layer_date,
    p_ref_doc_type, p_ref_doc_id,
    NULLIF(BTRIM(COALESCE(p_lot_number, '')), ''),
    NULLIF(BTRIM(COALESCE(p_serial_number, '')), ''),
    p_qty, p_qty, p_unit_cost, v_total, v_total, false
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── 4. Bind a legacy movement row to its source selection and allocations ───
CREATE OR REPLACE FUNCTION public.fn_bind_inventory_costing_evidence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch inventory_costing_pending_batches%ROWTYPE;
  v_runtime inventory_costing_runtime_queue%ROWTYPE;
  v_source_line_id UUID;
  v_layer_count INTEGER;
BEGIN
  IF NEW.qty < 0 THEN
    SELECT * INTO v_batch FROM inventory_costing_pending_batches b
    WHERE b.backend_pid = pg_backend_pid() AND b.local_txid = txid_current()
      AND b.company_id = NEW.company_id AND b.warehouse_id = NEW.warehouse_id
      AND b.item_id = NEW.item_id AND b.quantity = ABS(NEW.qty)
    ORDER BY b.created_at, b.id LIMIT 1 FOR UPDATE;
    IF FOUND THEN
      IF ABS(v_batch.total_cost - ABS(NEW.total_cost)) > 0.01 THEN
        RAISE EXCEPTION 'Posted movement cost % disagrees with layer allocation cost %', ABS(NEW.total_cost), v_batch.total_cost USING ERRCODE = '23514';
      END IF;
      INSERT INTO inventory_layer_allocations(
        company_id, inventory_transaction_id, layer_id, allocation_kind,
        quantity, unit_cost, total_cost
      ) SELECT NEW.company_id, NEW.id, a.layer_id, 'consume',
          a.quantity, a.unit_cost, a.total_cost
        FROM inventory_costing_pending_allocations a WHERE a.batch_id = v_batch.id;
      UPDATE inventory_transactions
      SET source_line_id = COALESCE(source_line_id, v_batch.source_line_id)
      WHERE id = NEW.id;
      DELETE FROM inventory_costing_pending_batches WHERE id = v_batch.id;
    END IF;

    SELECT * INTO v_runtime FROM inventory_costing_runtime_queue q
    WHERE q.backend_pid = pg_backend_pid() AND q.local_txid = txid_current()
      AND q.operation = 'issue' AND q.company_id = NEW.company_id
      AND q.warehouse_id = NEW.warehouse_id AND q.item_id = NEW.item_id
      AND (q.selection_consumed OR NEW.costing_method = 'weighted_average')
    ORDER BY q.sequence_no LIMIT 1 FOR UPDATE;
    IF FOUND THEN
      v_source_line_id := v_runtime.source_line_id;
      IF v_source_line_id IS NULL AND NEW.reference_doc_type = 'SI' THEN
        SELECT sil.id INTO v_source_line_id
        FROM sales_invoice_lines sil
        WHERE sil.sales_invoice_id = NEW.reference_doc_id
          AND sil.line_number = v_runtime.sequence_no;
      END IF;
      UPDATE inventory_transactions SET
        source_line_id = COALESCE(source_line_id, v_source_line_id),
        lot_number = COALESCE(lot_number, v_runtime.lot_number),
        serial_number = COALESCE(serial_number, v_runtime.serial_number)
      WHERE id = NEW.id;
      IF NEW.reference_doc_type = 'DR' AND v_source_line_id IS NOT NULL THEN
        UPDATE delivery_receipt_lines SET inventory_transaction_id = NEW.id,
          inventory_cost_layer_id = COALESCE(inventory_cost_layer_id, v_runtime.inventory_cost_layer_id),
          lot_number = COALESCE(lot_number, v_runtime.lot_number),
          serial_number = COALESCE(serial_number, v_runtime.serial_number), updated_at = now()
        WHERE id = v_source_line_id;
      ELSIF NEW.reference_doc_type = 'SI' AND v_source_line_id IS NOT NULL THEN
        PERFORM set_config('pxl.sales_invoice_posting_internal', 'on', true);
        UPDATE sales_invoice_lines SET inventory_transaction_id = NEW.id,
          inventory_cost_layer_id = COALESCE(inventory_cost_layer_id, v_runtime.inventory_cost_layer_id),
          lot_number = COALESCE(lot_number, v_runtime.lot_number),
          serial_number = COALESCE(serial_number, v_runtime.serial_number), updated_at = now()
        WHERE id = v_source_line_id;
        PERFORM set_config('pxl.sales_invoice_posting_internal', '', true);
      END IF;
      DELETE FROM inventory_costing_runtime_queue WHERE id = v_runtime.id;
    END IF;
  END IF;

  -- Positive legacy writers add their layer just before the transaction row.
  IF NEW.qty > 0 AND NEW.costing_method IN ('fifo', 'specific_identification') THEN
    UPDATE inventory_cost_layers l SET origin_inventory_transaction_id = NEW.id
    WHERE l.company_id = NEW.company_id AND l.warehouse_id = NEW.warehouse_id
      AND l.item_id = NEW.item_id AND l.reference_doc_type = NEW.reference_doc_type
      AND l.reference_doc_id = NEW.reference_doc_id
      AND l.origin_inventory_transaction_id IS NULL
      AND l.voided_by_inventory_transaction_id IS NULL;
  END IF;

  -- Legacy SI/DR void rows are inverse events. The wrapper supplies the exact
  -- original transaction and fn_add_cost_layer has already restored its layers.
  IF NEW.reference_doc_type IN ('SI_VOID', 'DR_VOID') THEN
    SELECT * INTO v_runtime FROM inventory_costing_runtime_queue q
    WHERE q.backend_pid = pg_backend_pid() AND q.local_txid = txid_current()
      AND q.operation = 'reverse' AND q.company_id = NEW.company_id
      AND q.warehouse_id = NEW.warehouse_id AND q.item_id = NEW.item_id
    ORDER BY q.sequence_no LIMIT 1 FOR UPDATE;
    IF FOUND THEN
      IF v_runtime.original_transaction_id IS NULL THEN
        RAISE EXCEPTION 'Void inventory row has no original transaction';
      END IF;
      UPDATE inventory_transactions
      SET reverses_inventory_transaction_id = v_runtime.original_transaction_id,
          source_line_id = COALESCE(source_line_id, v_runtime.source_line_id),
          lot_number = COALESCE(lot_number, v_runtime.lot_number),
          serial_number = COALESCE(serial_number, v_runtime.serial_number)
      WHERE id = NEW.id;
      UPDATE inventory_transactions SET reversed_by_inventory_transaction_id = NEW.id
      WHERE id = v_runtime.original_transaction_id;
      INSERT INTO inventory_layer_allocations(
        company_id, inventory_transaction_id, layer_id, allocation_kind,
        quantity, unit_cost, total_cost
      )
      SELECT NEW.company_id, NEW.id, a.layer_id, 'restore', a.quantity, a.unit_cost, a.total_cost
      FROM inventory_layer_allocations a
      WHERE a.inventory_transaction_id = v_runtime.original_transaction_id
        AND a.allocation_kind = 'consume';
      DELETE FROM inventory_costing_runtime_queue WHERE id = v_runtime.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bind_inventory_costing_evidence ON public.inventory_transactions;
CREATE TRIGGER trg_bind_inventory_costing_evidence
  AFTER INSERT ON public.inventory_transactions
  FOR EACH ROW EXECUTE FUNCTION public.fn_bind_inventory_costing_evidence();

-- ── 5. Thin wrappers around the current Posting/Correction implementations ──
ALTER FUNCTION public.fn_post_sales_invoice(UUID)
  RENAME TO fn_post_sales_invoice_costing_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_post_sales_invoice_costing_legacy_20260808(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_validate_sales_invoice_accounting_ready(p_invoice_id);
  INSERT INTO inventory_costing_runtime_queue(
    backend_pid, local_txid, sequence_no, operation, company_id, warehouse_id,
    item_id, source_line_id, inventory_cost_layer_id, lot_number, serial_number
  )
  SELECT pg_backend_pid(), txid_current(), row_number() OVER (ORDER BY sil.line_number),
    'issue', si.company_id, sil.warehouse_id, sil.item_id, sil.id,
    sil.inventory_cost_layer_id, sil.lot_number, sil.serial_number
  FROM sales_invoice_lines sil
  JOIN sales_invoices si ON si.id = sil.sales_invoice_id
  JOIN items i ON i.id = sil.item_id
  WHERE sil.sales_invoice_id = p_invoice_id AND i.item_type = 'inventory_item'
    AND sil.warehouse_id IS NOT NULL AND sil.quantity > 0
    AND NOT (sil.source_document_type = 'DR' AND sil.source_line_id IS NOT NULL)
    AND sil.inventory_transaction_id IS NULL;

  PERFORM fn_post_sales_invoice_costing_legacy_20260808(p_invoice_id);
  IF EXISTS (SELECT 1 FROM inventory_costing_runtime_queue
             WHERE backend_pid=pg_backend_pid() AND local_txid=txid_current() AND operation='issue') THEN
    RAISE EXCEPTION 'Sales Invoice left an unconsumed inventory identity selection' USING ERRCODE = '23514';
  END IF;
END;
$$;

ALTER FUNCTION public.fn_post_delivery_receipt(UUID)
  RENAME TO fn_post_delivery_receipt_costing_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_post_delivery_receipt_costing_legacy_20260808(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_post_delivery_receipt(p_dr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO inventory_costing_runtime_queue(
    backend_pid, local_txid, sequence_no, operation, company_id, warehouse_id,
    item_id, source_line_id, inventory_cost_layer_id, lot_number, serial_number
  )
  SELECT pg_backend_pid(), txid_current(), row_number() OVER (ORDER BY drl.line_number),
    'issue', dr.company_id, drl.warehouse_id, drl.item_id, drl.id,
    drl.inventory_cost_layer_id, drl.lot_number,
    COALESCE(drl.serial_number, CASE WHEN i.specific_id_tracking='serial' THEN NULLIF(drl.lot_serial_no,'') END)
  FROM delivery_receipt_lines drl
  JOIN delivery_receipts dr ON dr.id = drl.dr_id
  JOIN items i ON i.id = drl.item_id
  WHERE drl.dr_id = p_dr_id AND i.item_type = 'inventory_item'
    AND drl.warehouse_id IS NOT NULL AND drl.quantity > 0
    AND drl.inventory_transaction_id IS NULL;
  PERFORM fn_post_delivery_receipt_costing_legacy_20260808(p_dr_id);
  IF EXISTS (SELECT 1 FROM inventory_costing_runtime_queue
             WHERE backend_pid=pg_backend_pid() AND local_txid=txid_current() AND operation='issue') THEN
    RAISE EXCEPTION 'Delivery Receipt left an unconsumed inventory identity selection' USING ERRCODE = '23514';
  END IF;
END;
$$;

ALTER FUNCTION public.fn_save_cash_sale(JSONB,JSONB,NUMERIC)
  RENAME TO fn_save_cash_sale_costing_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_save_cash_sale_costing_legacy_20260808(JSONB,JSONB,NUMERIC)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_save_cash_sale(
  p_header JSONB, p_lines JSONB, p_cwt_amount NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_id UUID;
BEGIN
  INSERT INTO inventory_costing_runtime_queue(
    backend_pid, local_txid, sequence_no, operation, company_id, warehouse_id,
    item_id, inventory_cost_layer_id, lot_number, serial_number
  )
  SELECT pg_backend_pid(), txid_current(), payload.line_number, 'issue',
    (p_header->>'company_id')::UUID, NULLIF(payload.value->>'warehouse_id','')::UUID,
    NULLIF(payload.value->>'item_id','')::UUID,
    NULLIF(payload.value->>'inventory_cost_layer_id','')::UUID,
    NULLIF(BTRIM(COALESCE(payload.value->>'lot_number','')), ''),
    NULLIF(BTRIM(COALESCE(payload.value->>'serial_number','')), '')
  FROM (
    SELECT value, row_number() OVER (ORDER BY ordinality)::INTEGER AS line_number
    FROM jsonb_array_elements(COALESCE(p_lines,'[]'::JSONB)) WITH ORDINALITY
    WHERE NULLIF(BTRIM(COALESCE(value->>'description','')), '') IS NOT NULL
  ) payload
  JOIN items i ON i.id = NULLIF(payload.value->>'item_id','')::UUID
  WHERE i.item_type='inventory_item' AND NULLIF(payload.value->>'warehouse_id','') IS NOT NULL
    AND COALESCE((payload.value->>'quantity')::NUMERIC,0) > 0;
  v_result := fn_save_cash_sale_costing_legacy_20260808(p_header, p_lines, p_cwt_amount);
  v_id := (v_result->>'si_id')::UUID;
  IF EXISTS (SELECT 1 FROM inventory_costing_runtime_queue
             WHERE backend_pid=pg_backend_pid() AND local_txid=txid_current() AND operation='issue') THEN
    RAISE EXCEPTION 'Cash Sale left an unconsumed inventory identity selection' USING ERRCODE = '23514';
  END IF;
  RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_void_sales_invoice_aud053_core(UUID,UUID,TEXT)
  RENAME TO fn_void_sales_invoice_costing_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_void_sales_invoice_costing_legacy_20260808(UUID,UUID,TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_void_sales_invoice_aud053_core(
  p_invoice_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO inventory_costing_runtime_queue(
    backend_pid, local_txid, sequence_no, operation, company_id, warehouse_id,
    item_id, source_line_id, lot_number, serial_number, original_transaction_id
  )
  SELECT pg_backend_pid(), txid_current(), row_number() OVER (ORDER BY sil.line_number),
    'reverse', si.company_id, sil.warehouse_id, sil.item_id, sil.id,
    it.lot_number, it.serial_number, sil.inventory_transaction_id
  FROM sales_invoice_lines sil JOIN sales_invoices si ON si.id=sil.sales_invoice_id
  JOIN inventory_transactions it ON it.id=sil.inventory_transaction_id
  WHERE sil.sales_invoice_id=p_invoice_id AND sil.inventory_transaction_id IS NOT NULL;
  PERFORM fn_void_sales_invoice_costing_legacy_20260808(p_invoice_id,p_void_reason_id,p_memo);
  IF EXISTS (SELECT 1 FROM inventory_costing_runtime_queue
             WHERE backend_pid=pg_backend_pid() AND local_txid=txid_current() AND operation='reverse') THEN
    RAISE EXCEPTION 'Sales Invoice void left inventory restoration unbound' USING ERRCODE='23514';
  END IF;
END;
$$;

ALTER FUNCTION public.fn_void_delivery_receipt(UUID,UUID,TEXT)
  RENAME TO fn_void_delivery_receipt_costing_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_void_delivery_receipt_costing_legacy_20260808(UUID,UUID,TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_void_delivery_receipt(
  p_dr_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO inventory_costing_runtime_queue(
    backend_pid, local_txid, sequence_no, operation, company_id, warehouse_id,
    item_id, source_line_id, lot_number, serial_number, original_transaction_id
  )
  SELECT pg_backend_pid(), txid_current(), row_number() OVER (ORDER BY drl.line_number),
    'reverse', dr.company_id, drl.warehouse_id, drl.item_id, drl.id,
    it.lot_number, it.serial_number, drl.inventory_transaction_id
  FROM delivery_receipt_lines drl JOIN delivery_receipts dr ON dr.id=drl.dr_id
  JOIN inventory_transactions it ON it.id=drl.inventory_transaction_id
  WHERE drl.dr_id=p_dr_id AND drl.inventory_transaction_id IS NOT NULL;
  PERFORM fn_void_delivery_receipt_costing_legacy_20260808(p_dr_id,p_void_reason_id,p_memo);
  IF EXISTS (SELECT 1 FROM inventory_costing_runtime_queue
             WHERE backend_pid=pg_backend_pid() AND local_txid=txid_current() AND operation='reverse') THEN
    RAISE EXCEPTION 'Delivery Receipt void left inventory restoration unbound' USING ERRCODE='23514';
  END IF;
END;
$$;

-- Preserve the exact public/private surface. The renamed bodies are private.
REVOKE ALL ON FUNCTION public.fn_post_sales_invoice(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_post_sales_invoice(UUID) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_post_delivery_receipt(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_post_delivery_receipt(UUID) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_save_cash_sale(JSONB,JSONB,NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_save_cash_sale(JSONB,JSONB,NUMERIC) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_void_sales_invoice_aud053_core(UUID,UUID,TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_void_delivery_receipt(UUID,UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_void_delivery_receipt(UUID,UUID,TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_consume_cost_layers(UUID,UUID,UUID,NUMERIC,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_add_cost_layer(UUID,UUID,UUID,DATE,NUMERIC,NUMERIC,TEXT,UUID,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_bind_inventory_costing_evidence()
  FROM PUBLIC, anon, authenticated;
