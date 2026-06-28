-- ============================================================
-- Sprint 5: Sales Module — S5.1 Sales Invoices
-- ============================================================

-- ── Augment customers with missing SI fields ──────────────────
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS tin_branch_code TEXT NOT NULL DEFAULT '000',
  ADD COLUMN IF NOT EXISTS is_withholding_agent BOOLEAN NOT NULL DEFAULT false;

-- ── Void Reason Codes (global reference) ─────────────────────
CREATE TABLE void_reason_codes (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT        NOT NULL UNIQUE,
  description TEXT        NOT NULL,
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO void_reason_codes (code, description) VALUES
  ('WRONG_CUSTOMER',   'Wrong Customer'),
  ('WRONG_AMOUNT',     'Wrong Amount or Price'),
  ('WRONG_ITEM',       'Wrong Item or Description'),
  ('DUPLICATE',        'Duplicate Document'),
  ('CANCELLED_ORDER',  'Order Cancelled by Customer'),
  ('DATA_ENTRY_ERROR', 'Data Entry Error'),
  ('OTHER',            'Other — Specify in Memo');

-- ── Sales Invoices (Header) ────────────────────────────────────
CREATE TABLE sales_invoices (
  id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               UUID          NOT NULL REFERENCES companies(id),
  branch_id                UUID          NOT NULL REFERENCES branches(id),
  si_number                TEXT          NOT NULL,
  date                     DATE          NOT NULL DEFAULT CURRENT_DATE,
  fiscal_period_id         UUID          REFERENCES fiscal_periods(id),
  customer_id              UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot   TEXT          NOT NULL DEFAULT '',
  customer_tin_snapshot    TEXT          NOT NULL DEFAULT '',
  customer_address_snapshot TEXT         NOT NULL DEFAULT '',
  payment_terms_id         UUID          REFERENCES payment_terms(id),
  due_date                 DATE,
  currency_code            TEXT          NOT NULL DEFAULT 'PHP',
  reference                TEXT,
  memo                     TEXT,
  total_taxable_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_zero_rated_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_exempt_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_vat_amount         NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount             NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                   TEXT          NOT NULL DEFAULT 'draft'
                                         CHECK (status IN ('draft','approved','posted','cancelled')),
  void_reason_id           UUID          REFERENCES void_reason_codes(id),
  journal_entry_id         UUID,         -- FK to journal_entries added in S9
  posted_at                TIMESTAMPTZ,
  posted_by                UUID,
  created_by               UUID,
  updated_by               UUID,
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, si_number)
);

-- ── Sales Invoice Lines ────────────────────────────────────────
CREATE TABLE sales_invoice_lines (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_invoice_id    UUID          NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
  company_id          UUID          NOT NULL REFERENCES companies(id),
  line_number         INTEGER       NOT NULL,
  item_id             UUID          REFERENCES items(id),
  description         TEXT          NOT NULL,
  quantity            NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id              UUID          REFERENCES units_of_measure(id),
  unit_price          NUMERIC(15,4) NOT NULL DEFAULT 0,
  discount_percent    NUMERIC(5,2)  NOT NULL DEFAULT 0,
  discount_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID          REFERENCES vat_codes(id),
  vat_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  revenue_account_id  UUID          REFERENCES chart_of_accounts(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (sales_invoice_id, line_number)
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_si_company_id   ON sales_invoices (company_id);
CREATE INDEX idx_si_customer_id  ON sales_invoices (customer_id);
CREATE INDEX idx_si_date         ON sales_invoices (date DESC);
CREATE INDEX idx_si_status       ON sales_invoices (status);
CREATE INDEX idx_sil_si_id       ON sales_invoice_lines (sales_invoice_id);

-- ── updated_at triggers ───────────────────────────────────────
CREATE TRIGGER trg_si_updated_at
  BEFORE UPDATE ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_sil_updated_at
  BEFORE UPDATE ON sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Document Number Generator ─────────────────────────────────
-- Returns the next formatted document number and increments the series counter.
-- SECURITY DEFINER so the series counter increment bypasses RLS.
CREATE OR REPLACE FUNCTION fn_next_document_number(
  p_company_id    UUID,
  p_branch_id     UUID,
  p_document_code TEXT
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_series  number_series%ROWTYPE;
  v_result  TEXT;
BEGIN
  SELECT ns.* INTO v_series
  FROM number_series ns
  JOIN ref_document_types rdt ON ns.document_type_id = rdt.id
  WHERE ns.company_id       = p_company_id
    AND ns.branch_id        = p_branch_id
    AND rdt.document_code   = p_document_code
    AND ns.is_active        = true
  ORDER BY ns.created_at
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active number series for document type % in this branch. Configure one in Number Series Setup.', p_document_code;
  END IF;

  -- Build formatted number: prefix + [year-] + zero-padded sequence
  v_result := COALESCE(v_series.prefix, '');
  IF v_series.has_dynamic_year THEN
    v_result := v_result || TO_CHAR(NOW(), 'YYYY') || '-';
  END IF;
  v_result := v_result || LPAD(v_series.next_number::TEXT, v_series.number_length, '0');

  -- Increment
  UPDATE number_series
  SET next_number = next_number + 1,
      updated_at  = NOW()
  WHERE id = v_series.id;

  RETURN v_result;
END;
$$;

-- ── Row-Level Security ────────────────────────────────────────
ALTER TABLE sales_invoices     ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE void_reason_codes  ENABLE ROW LEVEL SECURITY;

-- Void reason codes: readable by all authenticated users
CREATE POLICY "read_void_reason_codes" ON void_reason_codes
  FOR SELECT TO authenticated USING (true);

-- Sales Invoices: readable by authenticated users (company scoping enforced in app)
CREATE POLICY "read_sales_invoices" ON sales_invoices
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "insert_sales_invoices" ON sales_invoices
  FOR INSERT TO authenticated WITH CHECK (true);

-- Only draft and approved can be updated
CREATE POLICY "update_draft_approved_si" ON sales_invoices
  FOR UPDATE TO authenticated
  USING (status IN ('draft', 'approved'));

-- Voiding = UPDATE to cancelled. Prevent physical DELETE.
CREATE POLICY "block_delete_si" ON sales_invoices
  FOR DELETE TO authenticated USING (false);

-- Lines: accessible while parent SI is editable
CREATE POLICY "read_si_lines" ON sales_invoice_lines
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "insert_si_lines" ON sales_invoice_lines
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "update_si_lines" ON sales_invoice_lines
  FOR UPDATE TO authenticated
  USING (
    sales_invoice_id IN (
      SELECT id FROM sales_invoices WHERE status IN ('draft', 'approved')
    )
  );

CREATE POLICY "delete_si_lines" ON sales_invoice_lines
  FOR DELETE TO authenticated
  USING (
    sales_invoice_id IN (
      SELECT id FROM sales_invoices WHERE status = 'draft'
    )
  );
