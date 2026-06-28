-- ============================================================
-- Sprint 5: Sales Orders, Quotations, Delivery Receipts
-- S5.4 Quotations + Sales Orders | S5.5 Delivery Receipts
-- ============================================================

-- ── Sales Quotations (Header) ─────────────────────────────────
CREATE TABLE sales_quotations (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  branch_id          UUID          NOT NULL REFERENCES branches(id),
  customer_id        UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot TEXT      NOT NULL DEFAULT '',
  customer_tin_snapshot  TEXT      NOT NULL DEFAULT '',
  quotation_number   TEXT          NOT NULL,
  quotation_date     DATE          NOT NULL DEFAULT CURRENT_DATE,
  validity_date      DATE          NOT NULL,
  currency_code      TEXT          NOT NULL DEFAULT 'PHP',
  reference_number   TEXT,
  remarks            TEXT,
  total_amount       NUMERIC(15,2) NOT NULL DEFAULT 0,
  status             TEXT          NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft','pending','approved','rejected','expired')),
  approved_by        UUID,
  approved_at        TIMESTAMPTZ,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, quotation_number)
);

-- ── Sales Quotation Lines ─────────────────────────────────────
CREATE TABLE sales_quotation_lines (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  quotation_id       UUID          NOT NULL REFERENCES sales_quotations(id) ON DELETE CASCADE,
  company_id         UUID          NOT NULL REFERENCES companies(id),
  item_id            UUID          REFERENCES items(id),
  description        TEXT          NOT NULL,
  quantity           NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id             UUID          REFERENCES units_of_measure(id),
  unit_price         NUMERIC(15,4) NOT NULL DEFAULT 0,
  discount_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_amount         NUMERIC(15,2) NOT NULL DEFAULT 0,
  line_number        INTEGER       NOT NULL DEFAULT 1,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (quotation_id, line_number)
);

-- ── Sales Orders (Header) ─────────────────────────────────────
CREATE TABLE sales_orders (
  id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID          NOT NULL REFERENCES companies(id),
  branch_id              UUID          NOT NULL REFERENCES branches(id),
  quotation_id           UUID          REFERENCES sales_quotations(id),
  customer_id            UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot TEXT          NOT NULL DEFAULT '',
  customer_tin_snapshot  TEXT          NOT NULL DEFAULT '',
  so_number              TEXT          NOT NULL,
  so_date                DATE          NOT NULL DEFAULT CURRENT_DATE,
  expected_delivery_date DATE,
  currency_code          TEXT          NOT NULL DEFAULT 'PHP',
  reference_number       TEXT,
  remarks                TEXT,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  approval_status        TEXT          NOT NULL DEFAULT 'pending'
                                       CHECK (approval_status IN ('pending','approved','rejected')),
  fulfillment_status     TEXT          NOT NULL DEFAULT 'open'
                                       CHECK (fulfillment_status IN ('open','partial','fulfilled','cancelled')),
  approved_by            UUID,
  approved_at            TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, so_number)
);

-- ── Sales Order Lines ─────────────────────────────────────────
CREATE TABLE sales_order_lines (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_order_id     UUID          NOT NULL REFERENCES sales_orders(id) ON DELETE CASCADE,
  company_id         UUID          NOT NULL REFERENCES companies(id),
  quotation_line_id  UUID          REFERENCES sales_quotation_lines(id),
  item_id            UUID          REFERENCES items(id),
  description        TEXT          NOT NULL,
  quantity           NUMERIC(15,4) NOT NULL DEFAULT 0,
  fulfilled_quantity NUMERIC(15,4) NOT NULL DEFAULT 0,
  uom_id             UUID          REFERENCES units_of_measure(id),
  unit_price         NUMERIC(15,4) NOT NULL DEFAULT 0,
  discount_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_amount         NUMERIC(15,2) NOT NULL DEFAULT 0,
  line_number        INTEGER       NOT NULL DEFAULT 1,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (sales_order_id, line_number)
);

-- ── Delivery Receipts (Header) ────────────────────────────────
CREATE TABLE delivery_receipts (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  branch_id          UUID          NOT NULL REFERENCES branches(id),
  sales_order_id     UUID          REFERENCES sales_orders(id),
  customer_id        UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot TEXT      NOT NULL DEFAULT '',
  dr_number          TEXT          NOT NULL,
  dr_date            DATE          NOT NULL DEFAULT CURRENT_DATE,
  shipping_method    TEXT          NOT NULL DEFAULT 'in_house'
                                   CHECK (shipping_method IN ('courier','in_house','pickup')),
  tracking_number    TEXT,
  driver_name        TEXT,
  delivery_address   TEXT          NOT NULL DEFAULT '',
  status             TEXT          NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft','in_transit','delivered','cancelled')),
  delivered_at       TIMESTAMPTZ,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, dr_number)
);

-- ── Delivery Receipt Lines ────────────────────────────────────
CREATE TABLE delivery_receipt_lines (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  dr_id              UUID          NOT NULL REFERENCES delivery_receipts(id) ON DELETE CASCADE,
  company_id         UUID          NOT NULL REFERENCES companies(id),
  so_line_id         UUID          REFERENCES sales_order_lines(id),
  item_id            UUID          REFERENCES items(id),
  description        TEXT          NOT NULL,
  quantity           NUMERIC(15,4) NOT NULL DEFAULT 0,
  uom_id             UUID          REFERENCES units_of_measure(id),
  lot_serial_no      TEXT,
  line_number        INTEGER       NOT NULL DEFAULT 1,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_sq_company        ON sales_quotations (company_id);
CREATE INDEX idx_sq_customer       ON sales_quotations (customer_id);
CREATE INDEX idx_sq_date           ON sales_quotations (quotation_date DESC);
CREATE INDEX idx_sql_quotation     ON sales_quotation_lines (quotation_id);

CREATE INDEX idx_so_company        ON sales_orders (company_id);
CREATE INDEX idx_so_customer       ON sales_orders (customer_id);
CREATE INDEX idx_so_quotation      ON sales_orders (quotation_id);
CREATE INDEX idx_so_date           ON sales_orders (so_date DESC);
CREATE INDEX idx_sol_order         ON sales_order_lines (sales_order_id);

CREATE INDEX idx_dr_company        ON delivery_receipts (company_id);
CREATE INDEX idx_dr_customer       ON delivery_receipts (customer_id);
CREATE INDEX idx_dr_so             ON delivery_receipts (sales_order_id);
CREATE INDEX idx_dr_date           ON delivery_receipts (dr_date DESC);
CREATE INDEX idx_drl_dr            ON delivery_receipt_lines (dr_id);
CREATE INDEX idx_drl_so_line       ON delivery_receipt_lines (so_line_id);

-- ── updated_at triggers ───────────────────────────────────────
CREATE TRIGGER trg_sq_updated_at
  BEFORE UPDATE ON sales_quotations
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_sql_updated_at
  BEFORE UPDATE ON sales_quotation_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_so_updated_at
  BEFORE UPDATE ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_sol_updated_at
  BEFORE UPDATE ON sales_order_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_dr_updated_at
  BEFORE UPDATE ON delivery_receipts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_drl_updated_at
  BEFORE UPDATE ON delivery_receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Row-Level Security ────────────────────────────────────────
ALTER TABLE sales_quotations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_quotation_lines  ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_order_lines      ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_receipts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_receipt_lines ENABLE ROW LEVEL SECURITY;

-- Sales Quotations
CREATE POLICY "read_sq"   ON sales_quotations FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_sq" ON sales_quotations FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_sq" ON sales_quotations FOR UPDATE TO authenticated
  USING (status IN ('draft','pending'));
CREATE POLICY "block_delete_sq" ON sales_quotations FOR DELETE TO authenticated USING (false);

CREATE POLICY "read_sql"   ON sales_quotation_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_sql" ON sales_quotation_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_sql" ON sales_quotation_lines FOR UPDATE TO authenticated
  USING (quotation_id IN (SELECT id FROM sales_quotations WHERE status IN ('draft','pending')));
CREATE POLICY "delete_sql" ON sales_quotation_lines FOR DELETE TO authenticated
  USING (quotation_id IN (SELECT id FROM sales_quotations WHERE status = 'draft'));

-- Sales Orders
CREATE POLICY "read_so"   ON sales_orders FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_so" ON sales_orders FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_so" ON sales_orders FOR UPDATE TO authenticated
  USING (approval_status IN ('pending'));
CREATE POLICY "block_delete_so" ON sales_orders FOR DELETE TO authenticated USING (false);

CREATE POLICY "read_sol"   ON sales_order_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_sol" ON sales_order_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_sol" ON sales_order_lines FOR UPDATE TO authenticated
  USING (sales_order_id IN (SELECT id FROM sales_orders WHERE approval_status = 'pending'));
CREATE POLICY "delete_sol" ON sales_order_lines FOR DELETE TO authenticated
  USING (sales_order_id IN (SELECT id FROM sales_orders WHERE approval_status = 'pending'));

-- Delivery Receipts
CREATE POLICY "read_dr"   ON delivery_receipts FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_dr" ON delivery_receipts FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_dr" ON delivery_receipts FOR UPDATE TO authenticated
  USING (status IN ('draft','in_transit'));
CREATE POLICY "block_delete_dr" ON delivery_receipts FOR DELETE TO authenticated USING (false);

CREATE POLICY "read_drl"   ON delivery_receipt_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_drl" ON delivery_receipt_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_drl" ON delivery_receipt_lines FOR UPDATE TO authenticated
  USING (dr_id IN (SELECT id FROM delivery_receipts WHERE status IN ('draft','in_transit')));
CREATE POLICY "delete_drl" ON delivery_receipt_lines FOR DELETE TO authenticated
  USING (dr_id IN (SELECT id FROM delivery_receipts WHERE status = 'draft'));
