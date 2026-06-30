-- ══════════════════════════════════════════════════════════════════════════════
-- S12: INVENTORY MODULE
-- Costing methods: Weighted Average Cost (WAC), FIFO, Specific Identification
-- Immutable transaction log + cost layers for FIFO/Specific ID
-- All financial movements post atomic journal entries
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Warehouses ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS warehouses (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  branch_id               UUID        REFERENCES branches(id),
  warehouse_code          TEXT        NOT NULL,
  warehouse_name          TEXT        NOT NULL,
  warehouse_type          TEXT        NOT NULL DEFAULT 'main'
                            CHECK (warehouse_type IN ('main','transit','consignment','damaged')),
  address                 TEXT,
  gl_inventory_account_id UUID        REFERENCES chart_of_accounts(id),
  gl_variance_account_id  UUID        REFERENCES chart_of_accounts(id),
  is_active               BOOLEAN     NOT NULL DEFAULT true,
  created_by              UUID        REFERENCES auth.users(id),
  updated_by              UUID        REFERENCES auth.users(id),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, warehouse_code)
);

CREATE INDEX IF NOT EXISTS idx_wh_company ON warehouses (company_id, is_active);

ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wh_read"   ON warehouses FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "wh_insert" ON warehouses FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "wh_update" ON warehouses FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_wh_updated_at BEFORE UPDATE ON warehouses FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 2. Warehouse Zones ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS warehouse_zones (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id UUID        NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  zone_code    TEXT        NOT NULL,
  zone_name    TEXT        NOT NULL,
  is_active    BOOLEAN     NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(warehouse_id, zone_code)
);

ALTER TABLE warehouse_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "whz_read" ON warehouse_zones FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM warehouses w WHERE w.id = warehouse_id AND is_company_member(w.company_id)));
CREATE POLICY "whz_write" ON warehouse_zones FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM warehouses w WHERE w.id = warehouse_id AND is_company_member(w.company_id)));

-- ── 3. Stock Balances ─────────────────────────────────────────────────────────
-- One row per item/warehouse. Maintained by RPCs — never updated directly.

CREATE TABLE IF NOT EXISTS stock_balances (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID        NOT NULL REFERENCES companies(id),
  warehouse_id      UUID        NOT NULL REFERENCES warehouses(id),
  item_id           UUID        NOT NULL REFERENCES items(id),
  qty_on_hand       NUMERIC(15,4) NOT NULL DEFAULT 0,
  qty_reserved      NUMERIC(15,4) NOT NULL DEFAULT 0,
  total_cost        NUMERIC(18,2) NOT NULL DEFAULT 0,
  wac_unit_cost     NUMERIC(18,6) NOT NULL DEFAULT 0,
  last_receipt_date DATE,
  last_issue_date   DATE,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(warehouse_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_sb_company   ON stock_balances (company_id);
CREATE INDEX IF NOT EXISTS idx_sb_warehouse ON stock_balances (warehouse_id, item_id);
CREATE INDEX IF NOT EXISTS idx_sb_item      ON stock_balances (item_id);

ALTER TABLE stock_balances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sb_read"   ON stock_balances FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "sb_insert" ON stock_balances FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "sb_update" ON stock_balances FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- ── 4. Inventory Cost Layers ──────────────────────────────────────────────────
-- One row per receipt batch. Used for FIFO (consumed oldest-first) and
-- Specific Identification (consumed by lot/serial).
-- WAC items also get layers for full audit trail but the unit_cost stored is the WAC at time of receipt.

CREATE TABLE IF NOT EXISTS inventory_cost_layers (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID        NOT NULL REFERENCES companies(id),
  warehouse_id      UUID        NOT NULL REFERENCES warehouses(id),
  item_id           UUID        NOT NULL REFERENCES items(id),
  layer_date        DATE        NOT NULL,
  reference_doc_type TEXT,
  reference_doc_id  UUID,
  lot_number        TEXT,
  serial_number     TEXT,
  original_qty      NUMERIC(15,4) NOT NULL CHECK (original_qty > 0),
  qty_remaining     NUMERIC(15,4) NOT NULL,
  unit_cost         NUMERIC(18,6) NOT NULL DEFAULT 0,
  is_exhausted      BOOLEAN     NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cl_item_wh  ON inventory_cost_layers (item_id, warehouse_id, is_exhausted, layer_date, id);
CREATE INDEX IF NOT EXISTS idx_cl_lot      ON inventory_cost_layers (item_id, warehouse_id, lot_number, serial_number) WHERE NOT is_exhausted;

ALTER TABLE inventory_cost_layers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cl_read"   ON inventory_cost_layers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cl_insert" ON inventory_cost_layers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "cl_update" ON inventory_cost_layers FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- ── 5. Inventory Transactions ─────────────────────────────────────────────────
-- Immutable audit log. Never updated after creation.

CREATE TABLE IF NOT EXISTS inventory_transactions (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID        NOT NULL REFERENCES companies(id),
  warehouse_id        UUID        NOT NULL REFERENCES warehouses(id),
  item_id             UUID        NOT NULL REFERENCES items(id),
  transaction_type    TEXT        NOT NULL
                        CHECK (transaction_type IN (
                          'receipt','adjustment_in','adjustment_out',
                          'transfer_out','transfer_in',
                          'issue','count_variance_in','count_variance_out'
                        )),
  transaction_date    DATE        NOT NULL,
  qty                 NUMERIC(15,4) NOT NULL,
  unit_cost           NUMERIC(18,6) NOT NULL DEFAULT 0,
  total_cost          NUMERIC(18,2) NOT NULL DEFAULT 0,
  qty_on_hand_after   NUMERIC(15,4) NOT NULL,
  costing_method      TEXT,
  reference_doc_type  TEXT,
  reference_doc_id    UUID,
  journal_entry_id    UUID        REFERENCES journal_entries(id),
  lot_number          TEXT,
  serial_number       TEXT,
  notes               TEXT,
  created_by          UUID        REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invtx_company   ON inventory_transactions (company_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_invtx_item      ON inventory_transactions (item_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_invtx_warehouse ON inventory_transactions (warehouse_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_invtx_ref       ON inventory_transactions (reference_doc_type, reference_doc_id);

ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invtx_read"   ON inventory_transactions FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "invtx_insert" ON inventory_transactions FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

-- ── 6. Stock Adjustments ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS stock_adjustments (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID        NOT NULL REFERENCES companies(id),
  branch_id         UUID        REFERENCES branches(id),
  warehouse_id      UUID        NOT NULL REFERENCES warehouses(id),
  adjustment_number TEXT        NOT NULL,
  adjustment_date   DATE        NOT NULL,
  reason            TEXT        NOT NULL
                      CHECK (reason IN ('shrinkage','damage','expired','correction','initial_load','donation','write_off','other')),
  status            TEXT        NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft','posted')),
  fiscal_period_id  UUID        REFERENCES fiscal_periods(id),
  notes             TEXT,
  journal_entry_id  UUID        REFERENCES journal_entries(id),
  posted_at         TIMESTAMPTZ,
  posted_by         UUID        REFERENCES auth.users(id),
  created_by        UUID        REFERENCES auth.users(id),
  updated_by        UUID        REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, adjustment_number)
);

CREATE TABLE IF NOT EXISTS stock_adjustment_lines (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  adjustment_id            UUID        NOT NULL REFERENCES stock_adjustments(id) ON DELETE CASCADE,
  company_id               UUID        NOT NULL REFERENCES companies(id),
  item_id                  UUID        NOT NULL REFERENCES items(id),
  lot_number               TEXT,
  serial_number            TEXT,
  qty_before               NUMERIC(15,4) NOT NULL DEFAULT 0,
  qty_adjusted             NUMERIC(15,4) NOT NULL,
  qty_after                NUMERIC(15,4) NOT NULL,
  unit_cost                NUMERIC(18,6) NOT NULL DEFAULT 0,
  total_cost_impact        NUMERIC(18,2) NOT NULL DEFAULT 0,
  gl_offset_account_id     UUID        REFERENCES chart_of_accounts(id)
);

CREATE INDEX IF NOT EXISTS idx_sadj_company ON stock_adjustments (company_id, adjustment_date DESC);
CREATE INDEX IF NOT EXISTS idx_sadjl_adj    ON stock_adjustment_lines (adjustment_id);

ALTER TABLE stock_adjustments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_adjustment_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sadj_read"   ON stock_adjustments FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "sadj_insert" ON stock_adjustments FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "sadj_update" ON stock_adjustments FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "sadjl_read"  ON stock_adjustment_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "sadjl_write" ON stock_adjustment_lines FOR ALL TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_sadj_updated_at BEFORE UPDATE ON stock_adjustments FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 7. Stock Transfers ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS stock_transfers (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID        NOT NULL REFERENCES companies(id),
  transfer_number     TEXT        NOT NULL,
  transfer_date       DATE        NOT NULL,
  from_warehouse_id   UUID        NOT NULL REFERENCES warehouses(id),
  to_warehouse_id     UUID        NOT NULL REFERENCES warehouses(id),
  status              TEXT        NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','posted','cancelled')),
  fiscal_period_id    UUID        REFERENCES fiscal_periods(id),
  notes               TEXT,
  journal_entry_id    UUID        REFERENCES journal_entries(id),
  posted_at           TIMESTAMPTZ,
  posted_by           UUID        REFERENCES auth.users(id),
  created_by          UUID        REFERENCES auth.users(id),
  updated_by          UUID        REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (from_warehouse_id <> to_warehouse_id),
  UNIQUE(company_id, transfer_number)
);

CREATE TABLE IF NOT EXISTS stock_transfer_lines (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id       UUID        NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  company_id        UUID        NOT NULL REFERENCES companies(id),
  item_id           UUID        NOT NULL REFERENCES items(id),
  lot_number        TEXT,
  serial_number     TEXT,
  qty_transferred   NUMERIC(15,4) NOT NULL CHECK (qty_transferred > 0),
  unit_cost         NUMERIC(18,6) NOT NULL DEFAULT 0,
  total_cost        NUMERIC(18,2) NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_stx_company ON stock_transfers (company_id, transfer_date DESC);
CREATE INDEX IF NOT EXISTS idx_stxl_tx     ON stock_transfer_lines (transfer_id);

ALTER TABLE stock_transfers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfer_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stx_read"   ON stock_transfers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "stx_insert" ON stock_transfers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "stx_update" ON stock_transfers FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "stxl_read"  ON stock_transfer_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "stxl_write" ON stock_transfer_lines FOR ALL TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_stx_updated_at BEFORE UPDATE ON stock_transfers FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 8. Goods Issues ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS goods_issues (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID        NOT NULL REFERENCES companies(id),
  branch_id         UUID        REFERENCES branches(id),
  warehouse_id      UUID        NOT NULL REFERENCES warehouses(id),
  issue_number      TEXT        NOT NULL,
  issue_date        DATE        NOT NULL,
  department_id     UUID        REFERENCES departments(id),
  purpose           TEXT,
  status            TEXT        NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft','posted')),
  fiscal_period_id  UUID        REFERENCES fiscal_periods(id),
  notes             TEXT,
  journal_entry_id  UUID        REFERENCES journal_entries(id),
  posted_at         TIMESTAMPTZ,
  posted_by         UUID        REFERENCES auth.users(id),
  created_by        UUID        REFERENCES auth.users(id),
  updated_by        UUID        REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, issue_number)
);

CREATE TABLE IF NOT EXISTS goods_issue_lines (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id              UUID        NOT NULL REFERENCES goods_issues(id) ON DELETE CASCADE,
  company_id            UUID        NOT NULL REFERENCES companies(id),
  item_id               UUID        NOT NULL REFERENCES items(id),
  lot_number            TEXT,
  serial_number         TEXT,
  qty_issued            NUMERIC(15,4) NOT NULL CHECK (qty_issued > 0),
  unit_cost             NUMERIC(18,6) NOT NULL DEFAULT 0,
  total_cost            NUMERIC(18,2) NOT NULL DEFAULT 0,
  gl_expense_account_id UUID        REFERENCES chart_of_accounts(id)
);

CREATE INDEX IF NOT EXISTS idx_gi_company ON goods_issues (company_id, issue_date DESC);
CREATE INDEX IF NOT EXISTS idx_gil_gi     ON goods_issue_lines (issue_id);

ALTER TABLE goods_issues      ENABLE ROW LEVEL SECURITY;
ALTER TABLE goods_issue_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gi_read"   ON goods_issues FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "gi_insert" ON goods_issues FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "gi_update" ON goods_issues FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "gil_read"  ON goods_issue_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "gil_write" ON goods_issue_lines FOR ALL TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_gi_updated_at BEFORE UPDATE ON goods_issues FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 9. Physical Count Sheets ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS physical_count_sheets (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID        NOT NULL REFERENCES companies(id),
  branch_id         UUID        REFERENCES branches(id),
  warehouse_id      UUID        NOT NULL REFERENCES warehouses(id),
  count_number      TEXT        NOT NULL,
  count_date        DATE        NOT NULL,
  status            TEXT        NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft','counting','variance_review','posted','cancelled')),
  fiscal_period_id  UUID        REFERENCES fiscal_periods(id),
  notes             TEXT,
  journal_entry_id  UUID        REFERENCES journal_entries(id),
  posted_at         TIMESTAMPTZ,
  posted_by         UUID        REFERENCES auth.users(id),
  created_by        UUID        REFERENCES auth.users(id),
  updated_by        UUID        REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, count_number)
);

CREATE TABLE IF NOT EXISTS physical_count_sheet_lines (
  id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  count_sheet_id           UUID          NOT NULL REFERENCES physical_count_sheets(id) ON DELETE CASCADE,
  company_id               UUID          NOT NULL REFERENCES companies(id),
  item_id                  UUID          NOT NULL REFERENCES items(id),
  lot_number               TEXT,
  serial_number            TEXT,
  system_qty               NUMERIC(15,4) NOT NULL DEFAULT 0,
  counted_qty              NUMERIC(15,4),
  unit_cost                NUMERIC(18,6) NOT NULL DEFAULT 0,
  gl_variance_account_id   UUID          REFERENCES chart_of_accounts(id)
);

CREATE INDEX IF NOT EXISTS idx_pcs_company ON physical_count_sheets (company_id, count_date DESC);
CREATE INDEX IF NOT EXISTS idx_pcsl_cs     ON physical_count_sheet_lines (count_sheet_id);

ALTER TABLE physical_count_sheets      ENABLE ROW LEVEL SECURITY;
ALTER TABLE physical_count_sheet_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pcs_read"   ON physical_count_sheets FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pcs_insert" ON physical_count_sheets FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pcs_update" ON physical_count_sheets FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pcsl_read"  ON physical_count_sheet_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pcsl_write" ON physical_count_sheet_lines FOR ALL TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_pcs_updated_at BEFORE UPDATE ON physical_count_sheets FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ══════════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════

-- ── fn_ensure_stock_balance ───────────────────────────────────────────────────
-- Upserts a stock_balances row for item/warehouse, returns the row.

CREATE OR REPLACE FUNCTION fn_ensure_stock_balance(
  p_company_id   UUID,
  p_warehouse_id UUID,
  p_item_id      UUID
)
RETURNS stock_balances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_row stock_balances;
BEGIN
  INSERT INTO stock_balances (company_id, warehouse_id, item_id)
  VALUES (p_company_id, p_warehouse_id, p_item_id)
  ON CONFLICT (warehouse_id, item_id) DO NOTHING;

  SELECT * INTO v_row FROM stock_balances
  WHERE warehouse_id = p_warehouse_id AND item_id = p_item_id;
  RETURN v_row;
END;
$$;

-- ── fn_consume_cost_layers ────────────────────────────────────────────────────
-- Core cost-allocation logic for all three methods.
-- Returns TABLE of (layer_id, qty_consumed, unit_cost).
-- For WAC: single row with wac_unit_cost; no layers consumed.
-- For FIFO: oldest-first layers.
-- For Specific ID: layer matching lot/serial.
-- Raises if insufficient qty.

CREATE OR REPLACE FUNCTION fn_consume_cost_layers(
  p_company_id     UUID,
  p_warehouse_id   UUID,
  p_item_id        UUID,
  p_qty            NUMERIC,
  p_lot_number     TEXT     DEFAULT NULL,
  p_serial_number  TEXT     DEFAULT NULL
)
RETURNS TABLE (
  layer_id     UUID,
  qty_consumed NUMERIC,
  unit_cost    NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_method       TEXT;
  v_sb           stock_balances%ROWTYPE;
  v_remaining    NUMERIC := p_qty;
  v_layer        inventory_cost_layers%ROWTYPE;
  v_take         NUMERIC;
BEGIN
  SELECT costing_method INTO v_method FROM items WHERE id = p_item_id;

  -- WAC: return single row with WAC unit cost; caller does not touch layers
  IF v_method = 'weighted_average' OR v_method IS NULL THEN
    SELECT * INTO v_sb FROM stock_balances
    WHERE warehouse_id = p_warehouse_id AND item_id = p_item_id;

    IF v_sb.qty_on_hand < p_qty THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        p_item_id, COALESCE(v_sb.qty_on_hand, 0), p_qty;
    END IF;

    layer_id     := NULL;
    qty_consumed := p_qty;
    unit_cost    := COALESCE(v_sb.wac_unit_cost, 0);
    RETURN NEXT;
    RETURN;
  END IF;

  -- FIFO or Specific Identification
  IF v_method = 'specific_identification' THEN
    -- Must have lot or serial to identify
    IF p_lot_number IS NULL AND p_serial_number IS NULL THEN
      RAISE EXCEPTION 'Specific Identification requires lot_number or serial_number';
    END IF;

    SELECT * INTO v_layer FROM inventory_cost_layers
    WHERE item_id = p_item_id AND warehouse_id = p_warehouse_id
      AND NOT is_exhausted
      AND (p_lot_number IS NULL OR lot_number = p_lot_number)
      AND (p_serial_number IS NULL OR serial_number = p_serial_number)
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No cost layer found for lot % / serial %', p_lot_number, p_serial_number;
    END IF;
    IF v_layer.qty_remaining < p_qty THEN
      RAISE EXCEPTION 'Layer qty (%) insufficient for requested qty (%)',
        v_layer.qty_remaining, p_qty;
    END IF;

    layer_id     := v_layer.id;
    qty_consumed := p_qty;
    unit_cost    := v_layer.unit_cost;
    RETURN NEXT;

    -- Update layer
    UPDATE inventory_cost_layers
    SET qty_remaining = qty_remaining - p_qty,
        is_exhausted  = (qty_remaining - p_qty <= 0)
    WHERE id = v_layer.id;
    RETURN;
  END IF;

  -- FIFO: consume oldest layers
  FOR v_layer IN
    SELECT * FROM inventory_cost_layers
    WHERE item_id = p_item_id AND warehouse_id = p_warehouse_id
      AND NOT is_exhausted
    ORDER BY layer_date ASC, id ASC
    FOR UPDATE SKIP LOCKED
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_take := LEAST(v_layer.qty_remaining, v_remaining);

    layer_id     := v_layer.id;
    qty_consumed := v_take;
    unit_cost    := v_layer.unit_cost;
    RETURN NEXT;

    UPDATE inventory_cost_layers
    SET qty_remaining = qty_remaining - v_take,
        is_exhausted  = (qty_remaining - v_take <= 0)
    WHERE id = v_layer.id;

    v_remaining := v_remaining - v_take;
  END LOOP;

  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'Insufficient FIFO layers. Short by %', v_remaining;
  END IF;
END;
$$;

-- ── fn_add_cost_layer ─────────────────────────────────────────────────────────
-- Creates a receipt cost layer (used by all methods for audit trail).

CREATE OR REPLACE FUNCTION fn_add_cost_layer(
  p_company_id       UUID,
  p_warehouse_id     UUID,
  p_item_id          UUID,
  p_layer_date       DATE,
  p_qty              NUMERIC,
  p_unit_cost        NUMERIC,
  p_ref_doc_type     TEXT    DEFAULT NULL,
  p_ref_doc_id       UUID    DEFAULT NULL,
  p_lot_number       TEXT    DEFAULT NULL,
  p_serial_number    TEXT    DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO inventory_cost_layers (
    company_id, warehouse_id, item_id, layer_date,
    reference_doc_type, reference_doc_id,
    lot_number, serial_number,
    original_qty, qty_remaining, unit_cost
  ) VALUES (
    p_company_id, p_warehouse_id, p_item_id, p_layer_date,
    p_ref_doc_type, p_ref_doc_id,
    p_lot_number, p_serial_number,
    p_qty, p_qty, p_unit_cost
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── fn_update_wac ─────────────────────────────────────────────────────────────
-- Recalculates WAC after a receipt and updates stock_balances.

CREATE OR REPLACE FUNCTION fn_update_wac(
  p_warehouse_id UUID,
  p_item_id      UUID,
  p_qty_in       NUMERIC,
  p_unit_cost_in NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_sb stock_balances%ROWTYPE;
BEGIN
  SELECT * INTO v_sb FROM stock_balances
  WHERE warehouse_id = p_warehouse_id AND item_id = p_item_id;

  IF FOUND AND v_sb.qty_on_hand + p_qty_in > 0 THEN
    UPDATE stock_balances
    SET wac_unit_cost = ROUND(
          (v_sb.total_cost + p_qty_in * p_unit_cost_in) /
          (v_sb.qty_on_hand + p_qty_in), 6)
    WHERE warehouse_id = p_warehouse_id AND item_id = p_item_id;
  END IF;
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════

-- ── fn_receive_inventory ──────────────────────────────────────────────────────
-- Adds stock to a warehouse. Called by purchasing receiving or manual entry.
-- Creates cost layer, updates WAC if applicable, posts optional GL entry.

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
  v_wh            warehouses%ROWTYPE;
  v_tx_id         UUID;
  v_sb            stock_balances%ROWTYPE;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_qty <= 0 THEN RAISE EXCEPTION 'Receipt qty must be positive'; END IF;

  SELECT * INTO v_item FROM items WHERE id = v_item_id;
  SELECT * INTO v_wh   FROM warehouses WHERE id = v_warehouse_id;

  -- Update WAC before upsert (needs existing balance)
  IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
    PERFORM fn_update_wac(v_warehouse_id, v_item_id, v_qty, v_unit_cost);
  END IF;

  -- Upsert stock balance
  v_sb := fn_ensure_stock_balance(v_company_id, v_warehouse_id, v_item_id);

  UPDATE stock_balances
  SET qty_on_hand       = qty_on_hand + v_qty,
      total_cost        = total_cost + (v_qty * v_unit_cost),
      last_receipt_date = v_date,
      updated_at        = NOW()
  WHERE warehouse_id = v_warehouse_id AND item_id = v_item_id;

  -- After balance update, refresh wac_unit_cost field
  IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
    UPDATE stock_balances
    SET wac_unit_cost = CASE WHEN (qty_on_hand) > 0
        THEN ROUND(total_cost / qty_on_hand, 6)
        ELSE 0 END
    WHERE warehouse_id = v_warehouse_id AND item_id = v_item_id;
  END IF;

  -- Add cost layer for FIFO / Specific ID (and audit trail for WAC)
  PERFORM fn_add_cost_layer(
    v_company_id, v_warehouse_id, v_item_id, v_date,
    v_qty, v_unit_cost, v_ref_type, v_ref_id, v_lot, v_serial
  );

  -- Immutable transaction log
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

-- ── fn_post_stock_adjustment ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_post_stock_adjustment(p_adjustment_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adj      stock_adjustments%ROWTYPE;
  v_line     stock_adjustment_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_wh       warehouses%ROWTYPE;
  v_sb       stock_balances%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line_no  INT := 1;
  v_total_impact NUMERIC := 0;
BEGIN
  SELECT * INTO v_adj FROM stock_adjustments WHERE id = p_adjustment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Adjustment not found'; END IF;
  IF NOT is_company_member(v_adj.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_adj.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT * INTO v_wh FROM warehouses WHERE id = v_adj.warehouse_id;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_adj.company_id
    AND start_date <= v_adj.adjustment_date AND end_date >= v_adj.adjustment_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_adj.adjustment_date; END IF;

  -- Process each line
  FOR v_line IN SELECT * FROM stock_adjustment_lines WHERE adjustment_id = p_adjustment_id LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    v_sb := fn_ensure_stock_balance(v_adj.company_id, v_adj.warehouse_id, v_line.item_id);

    IF v_line.qty_adjusted < 0 AND v_sb.qty_on_hand < ABS(v_line.qty_adjusted) THEN
      RAISE EXCEPTION 'Item % has insufficient stock. On hand: %, trying to reduce by: %',
        v_item.description, v_sb.qty_on_hand, ABS(v_line.qty_adjusted);
    END IF;

    -- Determine unit cost for adjustment
    DECLARE v_uc NUMERIC;
    BEGIN
      v_uc := CASE
        WHEN v_line.unit_cost > 0 THEN v_line.unit_cost
        WHEN v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL
          THEN COALESCE(v_sb.wac_unit_cost, v_item.standard_cost, 0)
        ELSE v_item.standard_cost
      END;

      -- Update stock balance
      UPDATE stock_balances
      SET qty_on_hand   = qty_on_hand + v_line.qty_adjusted,
          total_cost    = GREATEST(total_cost + (v_line.qty_adjusted * v_uc), 0),
          updated_at    = NOW()
      WHERE warehouse_id = v_adj.warehouse_id AND item_id = v_line.item_id;

      -- Refresh WAC
      IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
        UPDATE stock_balances
        SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
        WHERE warehouse_id = v_adj.warehouse_id AND item_id = v_line.item_id;
      END IF;

      -- For FIFO positive adjustments: add layer; negative: consume via FIFO
      IF v_item.costing_method IN ('fifo','specific_identification') THEN
        IF v_line.qty_adjusted > 0 THEN
          PERFORM fn_add_cost_layer(v_adj.company_id, v_adj.warehouse_id, v_line.item_id,
            v_adj.adjustment_date, v_line.qty_adjusted, v_uc, 'ADJ', p_adjustment_id,
            v_line.lot_number, v_line.serial_number);
        ELSIF v_line.qty_adjusted < 0 THEN
          PERFORM fn_consume_cost_layers(v_adj.company_id, v_adj.warehouse_id, v_line.item_id,
            ABS(v_line.qty_adjusted), v_line.lot_number, v_line.serial_number);
        END IF;
      END IF;

      -- Accumulate GL impact
      v_total_impact := v_total_impact + (v_line.qty_adjusted * v_uc);

      -- Update line with resolved cost
      UPDATE stock_adjustment_lines
      SET unit_cost         = v_uc,
          total_cost_impact = ROUND(v_line.qty_adjusted * v_uc, 2)
      WHERE id = v_line.id;

      -- Transaction log
      INSERT INTO inventory_transactions (
        company_id, warehouse_id, item_id,
        transaction_type, transaction_date,
        qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
        reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
      )
      SELECT v_adj.company_id, v_adj.warehouse_id, v_line.item_id,
        CASE WHEN v_line.qty_adjusted >= 0 THEN 'adjustment_in' ELSE 'adjustment_out' END,
        v_adj.adjustment_date,
        v_line.qty_adjusted, v_uc, ROUND(v_line.qty_adjusted * v_uc, 2),
        qty_on_hand, v_item.costing_method,
        'ADJ', p_adjustment_id, v_line.lot_number, v_line.serial_number, auth.uid()
      FROM stock_balances WHERE warehouse_id = v_adj.warehouse_id AND item_id = v_line.item_id;
    END;
  END LOOP;

  -- Post GL entry if there is a non-zero impact
  IF ABS(v_total_impact) > 0 THEN
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_adj.company_id, v_adj.branch_id,
      fn_next_document_number(v_adj.company_id, 'JE'),
      v_adj.adjustment_date, v_fp_id,
      'Stock Adjustment: ' || v_adj.adjustment_number || ' (' || v_adj.reason || ')',
      'INV_ADJ', p_adjustment_id, 'posted',
      GREATEST(v_total_impact, 0), GREATEST(-v_total_impact, 0),
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    -- Build JE lines per line (using item's inventory and offset accounts)
    FOR v_line IN SELECT sal.*, i.inventory_account_id
      FROM stock_adjustment_lines sal
      JOIN items i ON i.id = sal.item_id
      WHERE sal.adjustment_id = p_adjustment_id
    LOOP
      DECLARE v_inv_acct UUID; v_off_acct UUID; v_impact NUMERIC;
      BEGIN
        v_inv_acct := v_line.gl_offset_account_id; -- reuse field for simplicity
        SELECT inventory_account_id INTO v_inv_acct FROM items WHERE id = v_line.item_id;
        v_off_acct := v_line.gl_offset_account_id;
        v_impact   := ROUND(v_line.qty_adjusted * v_line.unit_cost, 2);

        IF v_inv_acct IS NOT NULL AND v_off_acct IS NOT NULL AND v_impact <> 0 THEN
          -- Positive: DR Inventory / CR Offset. Negative: DR Offset / CR Inventory
          INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
          VALUES
            (v_je_id, v_adj.company_id, v_line_no,     v_inv_acct, 'Inventory adj', GREATEST(v_impact,0), GREATEST(-v_impact,0), auth.uid(), auth.uid()),
            (v_je_id, v_adj.company_id, v_line_no + 1, v_off_acct, 'Adj offset',    GREATEST(-v_impact,0), GREATEST(v_impact,0), auth.uid(), auth.uid());
          v_line_no := v_line_no + 2;
        END IF;
      END;
    END LOOP;
  END IF;

  UPDATE stock_adjustments
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_adjustment_id;

  RETURN v_je_id;
END;
$$;

-- ── fn_post_stock_transfer ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_post_stock_transfer(p_transfer_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx       stock_transfers%ROWTYPE;
  v_line     stock_transfer_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_from_wh  warehouses%ROWTYPE;
  v_to_wh    warehouses%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line_no  INT := 1;
  v_layer    RECORD;
  v_uc       NUMERIC;
  v_total    NUMERIC := 0;
BEGIN
  SELECT * INTO v_tx FROM stock_transfers WHERE id = p_transfer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found'; END IF;
  IF NOT is_company_member(v_tx.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_tx.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT * INTO v_from_wh FROM warehouses WHERE id = v_tx.from_warehouse_id;
  SELECT * INTO v_to_wh   FROM warehouses WHERE id = v_tx.to_warehouse_id;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_tx.company_id
    AND start_date <= v_tx.transfer_date AND end_date >= v_tx.transfer_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_tx.transfer_date; END IF;

  FOR v_line IN SELECT * FROM stock_transfer_lines WHERE transfer_id = p_transfer_id LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    PERFORM fn_ensure_stock_balance(v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id);
    PERFORM fn_ensure_stock_balance(v_tx.company_id, v_tx.to_warehouse_id,   v_line.item_id);

    v_uc := 0;
    v_total := 0;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      -- WAC: use source WAC cost
      SELECT wac_unit_cost INTO v_uc FROM stock_balances
      WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;
      v_uc    := COALESCE(v_uc, 0);
      v_total := ROUND(v_line.qty_transferred * v_uc, 2);

      -- Deduct from source
      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand - v_line.qty_transferred,
          total_cost  = GREATEST(total_cost - v_total, 0),
          last_issue_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;

      -- Add to destination (re-computes WAC at destination)
      PERFORM fn_update_wac(v_tx.to_warehouse_id, v_line.item_id, v_line.qty_transferred, v_uc);
      UPDATE stock_balances
      SET qty_on_hand      = qty_on_hand + v_line.qty_transferred,
          total_cost       = total_cost + v_total,
          last_receipt_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;

    ELSE
      -- FIFO / Specific ID: consume layers at source, recreate at destination
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id,
          v_line.qty_transferred, v_line.lot_number, v_line.serial_number
        )
      LOOP
        v_total := v_total + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        -- Create layer at destination preserving cost and date
        PERFORM fn_add_cost_layer(
          v_tx.company_id, v_tx.to_warehouse_id, v_line.item_id,
          v_tx.transfer_date, v_layer.qty_consumed, v_layer.unit_cost,
          'STX', p_transfer_id, v_line.lot_number, v_line.serial_number
        );
        v_uc := v_layer.unit_cost; -- last unit cost for logging
      END LOOP;

      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand - v_line.qty_transferred,
          total_cost  = GREATEST(total_cost - v_total, 0),
          last_issue_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;

      UPDATE stock_balances
      SET qty_on_hand       = qty_on_hand + v_line.qty_transferred,
          total_cost        = total_cost + v_total,
          last_receipt_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;
    END IF;

    -- Update line totals
    UPDATE stock_transfer_lines
    SET unit_cost = ROUND(v_total / v_line.qty_transferred, 6), total_cost = v_total
    WHERE id = v_line.id;

    -- Transaction log
    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id,
      'transfer_out', v_tx.transfer_date,
      -v_line.qty_transferred, ROUND(v_total / v_line.qty_transferred, 6), -v_total,
      qty_on_hand, v_item.costing_method,
      'STX', p_transfer_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_tx.company_id, v_tx.to_warehouse_id, v_line.item_id,
      'transfer_in', v_tx.transfer_date,
      v_line.qty_transferred, ROUND(v_total / v_line.qty_transferred, 6), v_total,
      qty_on_hand, v_item.costing_method,
      'STX', p_transfer_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;
  END LOOP;

  -- GL entry only if warehouses have different inventory GL accounts
  IF v_from_wh.gl_inventory_account_id IS NOT NULL
     AND v_to_wh.gl_inventory_account_id IS NOT NULL
     AND v_from_wh.gl_inventory_account_id <> v_to_wh.gl_inventory_account_id THEN

    SELECT SUM(total_cost) INTO v_total FROM stock_transfer_lines WHERE transfer_id = p_transfer_id;

    INSERT INTO journal_entries (
      company_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_tx.company_id, fn_next_document_number(v_tx.company_id, 'JE'),
      v_tx.transfer_date, v_fp_id,
      'Stock Transfer: ' || v_tx.transfer_number,
      'INV_STX', p_transfer_id, 'posted', v_total, v_total,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES
      (v_je_id, v_tx.company_id, 1, v_to_wh.gl_inventory_account_id,   'Transfer in',  v_total, 0,       auth.uid(), auth.uid()),
      (v_je_id, v_tx.company_id, 2, v_from_wh.gl_inventory_account_id, 'Transfer out', 0,       v_total, auth.uid(), auth.uid());
  END IF;

  UPDATE stock_transfers
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_transfer_id;

  RETURN v_je_id;
END;
$$;

-- ── fn_post_goods_issue ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_post_goods_issue(p_issue_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gi      goods_issues%ROWTYPE;
  v_line    goods_issue_lines%ROWTYPE;
  v_item    items%ROWTYPE;
  v_sb      stock_balances%ROWTYPE;
  v_fp_id   UUID;
  v_je_id   UUID;
  v_line_no INT := 1;
  v_layer   RECORD;
  v_uc      NUMERIC;
  v_total   NUMERIC;
  v_je_total NUMERIC := 0;
BEGIN
  SELECT * INTO v_gi FROM goods_issues WHERE id = p_issue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Goods issue not found'; END IF;
  IF NOT is_company_member(v_gi.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_gi.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_gi.company_id
    AND start_date <= v_gi.issue_date AND end_date >= v_gi.issue_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_gi.issue_date; END IF;

  -- Create JE header
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_gi.company_id, v_gi.branch_id,
    fn_next_document_number(v_gi.company_id, 'JE'),
    v_gi.issue_date, v_fp_id,
    'Goods Issue: ' || v_gi.issue_number || COALESCE(' — ' || v_gi.purpose, ''),
    'INV_GI', p_issue_id, 'posted', 0, 0,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN SELECT * FROM goods_issue_lines WHERE issue_id = p_issue_id LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    v_sb := fn_ensure_stock_balance(v_gi.company_id, v_gi.warehouse_id, v_line.item_id);

    v_total := 0;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      SELECT wac_unit_cost INTO v_uc FROM stock_balances
      WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;
      v_uc    := COALESCE(v_uc, 0);
      v_total := ROUND(v_line.qty_issued * v_uc, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_gi.company_id, v_gi.warehouse_id, v_line.item_id,
          v_line.qty_issued, v_line.lot_number, v_line.serial_number
        )
      LOOP
        v_total := v_total + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        v_uc    := v_layer.unit_cost;
      END LOOP;
    END IF;

    -- Deduct stock
    UPDATE stock_balances
    SET qty_on_hand     = qty_on_hand - v_line.qty_issued,
        total_cost      = GREATEST(total_cost - v_total, 0),
        last_issue_date = v_gi.issue_date,
        updated_at      = NOW()
    WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;
    END IF;

    -- Update line cost
    UPDATE goods_issue_lines SET unit_cost = ROUND(v_total / v_line.qty_issued, 6), total_cost = v_total WHERE id = v_line.id;

    -- JE lines: DR Expense / CR Inventory
    DECLARE v_inv_acct UUID; v_exp_acct UUID;
    BEGIN
      SELECT inventory_account_id, cogs_account_id INTO v_inv_acct, v_exp_acct FROM items WHERE id = v_line.item_id;
      v_exp_acct := COALESCE(v_line.gl_expense_account_id, v_exp_acct);
      IF v_inv_acct IS NOT NULL AND v_exp_acct IS NOT NULL AND v_total > 0 THEN
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
        VALUES
          (v_je_id, v_gi.company_id, v_line_no,     v_exp_acct, 'Goods issue — ' || v_item.description, v_total, 0,       auth.uid(), auth.uid()),
          (v_je_id, v_gi.company_id, v_line_no + 1, v_inv_acct, 'Goods issue — ' || v_item.description, 0,       v_total, auth.uid(), auth.uid());
        v_line_no  := v_line_no + 2;
        v_je_total := v_je_total + v_total;
      END IF;
    END;

    -- Transaction log
    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_gi.company_id, v_gi.warehouse_id, v_line.item_id,
      'issue', v_gi.issue_date,
      -v_line.qty_issued, ROUND(v_total / v_line.qty_issued, 6), -v_total,
      qty_on_hand, v_item.costing_method,
      'INV_GI', p_issue_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;
  END LOOP;

  -- Update JE totals
  UPDATE journal_entries SET total_debit = v_je_total, total_credit = v_je_total WHERE id = v_je_id;

  UPDATE goods_issues
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_issue_id;

  RETURN v_je_id;
END;
$$;

-- ── fn_post_physical_count ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_post_physical_count(p_sheet_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs       physical_count_sheets%ROWTYPE;
  v_line     physical_count_sheet_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line_no  INT := 1;
  v_variance NUMERIC;
  v_uc       NUMERIC;
  v_je_total NUMERIC := 0;
BEGIN
  SELECT * INTO v_cs FROM physical_count_sheets WHERE id = p_sheet_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Count sheet not found'; END IF;
  IF NOT is_company_member(v_cs.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_cs.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_cs.company_id
    AND start_date <= v_cs.count_date AND end_date >= v_cs.count_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_cs.count_date; END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_cs.company_id, v_cs.branch_id,
    fn_next_document_number(v_cs.company_id, 'JE'),
    v_cs.count_date, v_fp_id,
    'Physical Count Variance: ' || v_cs.count_number,
    'INV_COUNT', p_sheet_id, 'posted', 0, 0,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN SELECT * FROM physical_count_sheet_lines WHERE count_sheet_id = p_sheet_id LOOP
    v_variance := COALESCE(v_line.counted_qty, v_line.system_qty) - v_line.system_qty;
    CONTINUE WHEN v_variance = 0;

    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    PERFORM fn_ensure_stock_balance(v_cs.company_id, v_cs.warehouse_id, v_line.item_id);

    -- Determine unit cost for variance
    SELECT wac_unit_cost INTO v_uc FROM stock_balances
    WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;
    v_uc := COALESCE(
      CASE WHEN v_line.unit_cost > 0 THEN v_line.unit_cost ELSE NULL END,
      v_uc, v_item.standard_cost, 0
    );

    -- Apply variance to stock balance
    UPDATE stock_balances
    SET qty_on_hand = qty_on_hand + v_variance,
        total_cost  = GREATEST(total_cost + (v_variance * v_uc), 0),
        updated_at  = NOW()
    WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;
    END IF;

    -- For FIFO: add/consume layer for variance
    IF v_item.costing_method IN ('fifo','specific_identification') THEN
      IF v_variance > 0 THEN
        PERFORM fn_add_cost_layer(v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
          v_cs.count_date, v_variance, v_uc, 'COUNT', p_sheet_id, v_line.lot_number, v_line.serial_number);
      ELSE
        PERFORM fn_consume_cost_layers(v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
          ABS(v_variance), v_line.lot_number, v_line.serial_number);
      END IF;
    END IF;

    -- Update line variance cost
    UPDATE physical_count_sheet_lines
    SET unit_cost      = v_uc,
        variance_cost  = ROUND(v_variance * v_uc, 2)
    WHERE id = v_line.id;

    -- GL: DR/CR Inventory / CR/DR Variance Account
    DECLARE v_inv_acct UUID; v_var_acct UUID; v_impact NUMERIC;
    BEGIN
      SELECT inventory_account_id INTO v_inv_acct FROM items WHERE id = v_line.item_id;
      v_var_acct := COALESCE(
        v_line.gl_variance_account_id,
        (SELECT gl_variance_account_id FROM warehouses WHERE id = v_cs.warehouse_id)
      );
      v_impact := ROUND(v_variance * v_uc, 2);
      v_je_total := v_je_total + ABS(v_impact);

      IF v_inv_acct IS NOT NULL AND v_var_acct IS NOT NULL THEN
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
        VALUES
          (v_je_id, v_cs.company_id, v_line_no,     v_inv_acct, 'Count variance — ' || v_item.description,
            GREATEST(v_impact,0), GREATEST(-v_impact,0), auth.uid(), auth.uid()),
          (v_je_id, v_cs.company_id, v_line_no + 1, v_var_acct, 'Count variance — ' || v_item.description,
            GREATEST(-v_impact,0), GREATEST(v_impact,0), auth.uid(), auth.uid());
        v_line_no := v_line_no + 2;
      END IF;
    END;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id,
      transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
      CASE WHEN v_variance >= 0 THEN 'count_variance_in' ELSE 'count_variance_out' END,
      v_cs.count_date,
      v_variance, v_uc, ROUND(v_variance * v_uc, 2),
      qty_on_hand, v_item.costing_method,
      'INV_COUNT', p_sheet_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;
  END LOOP;

  UPDATE journal_entries SET total_debit = v_je_total, total_credit = v_je_total WHERE id = v_je_id;

  UPDATE physical_count_sheets
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_sheet_id;

  RETURN v_je_id;
END;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION fn_ensure_stock_balance(UUID, UUID, UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_consume_cost_layers(UUID, UUID, UUID, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_add_cost_layer(UUID, UUID, UUID, DATE, NUMERIC, NUMERIC, TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_update_wac(UUID, UUID, NUMERIC, NUMERIC)         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_receive_inventory(JSONB)                          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_stock_adjustment(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_stock_transfer(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_goods_issue(UUID)                            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_physical_count(UUID)                         TO authenticated;
