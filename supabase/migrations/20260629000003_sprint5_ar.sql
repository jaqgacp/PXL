-- ============================================================
-- Sprint 5: Sales AR — Receipts, Credit Memos, Debit Memos
-- S5.2 Receipts | S5.3 Credit Memos | S5.3 Debit Memos
-- ============================================================

-- ── Reference: Payment Modes ──────────────────────────────────
CREATE TABLE ref_payment_modes (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT        NOT NULL UNIQUE,
  name        TEXT        NOT NULL,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  is_active   BOOLEAN     NOT NULL DEFAULT true
);

INSERT INTO ref_payment_modes (code, name, sort_order) VALUES
  ('CASH',      'Cash',              1),
  ('CHECK',     'Check',             2),
  ('BANK_XFER', 'Bank Transfer',     3),
  ('EWALLET',   'E-Wallet',          4),
  ('PDC',       'Post-Dated Check',  5);

-- ── Reference: Reason Codes (CM and DM) ─────────────────────
CREATE TABLE ref_reason_codes (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT        NOT NULL UNIQUE,
  description TEXT        NOT NULL,
  applies_to  TEXT        NOT NULL CHECK (applies_to IN ('credit_memo','debit_memo','both')),
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  is_active   BOOLEAN     NOT NULL DEFAULT true
);

INSERT INTO ref_reason_codes (code, description, applies_to, sort_order) VALUES
  -- Credit Memo reasons
  ('CM_OVERBILLING',    'Overbilling / Pricing Error',          'credit_memo', 1),
  ('CM_DISCOUNT',       'Sales Discount',                       'credit_memo', 2),
  ('CM_ALLOWANCE',      'Sales Allowance',                      'credit_memo', 3),
  ('CM_RETURN',         'Customer Return Credit',               'credit_memo', 4),
  ('CM_OTHER',          'Other — Credit Memo',                  'credit_memo', 9),
  -- Debit Memo reasons
  ('DM_BOUNCED_CHECK',  'Bounced Check Reversal',               'debit_memo',  1),
  ('DM_LATE_PENALTY',   'Late Payment Penalty',                 'debit_memo',  2),
  ('DM_UNDERBILLING',   'Underbilling Correction',              'debit_memo',  3),
  ('DM_BANK_CHARGES',   'Bank Charges Passed On',               'debit_memo',  4),
  ('DM_OTHER',          'Other — Debit Memo',                   'debit_memo',  9);

-- ── Receipts (Header) ─────────────────────────────────────────
CREATE TABLE receipts (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  branch_id          UUID          NOT NULL REFERENCES branches(id),
  customer_id        UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot TEXT      NOT NULL DEFAULT '',
  customer_tin_snapshot  TEXT      NOT NULL DEFAULT '',
  receipt_number     TEXT          NOT NULL,
  receipt_date       DATE          NOT NULL DEFAULT CURRENT_DATE,
  payment_mode_id    UUID          NOT NULL REFERENCES ref_payment_modes(id),
  reference_number   TEXT,
  bank_account_id    UUID          REFERENCES chart_of_accounts(id),
  total_amount       NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_cwt          NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks            TEXT,
  status             TEXT          NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft','posted','bounced','cancelled')),
  journal_entry_id   UUID,
  posted_at          TIMESTAMPTZ,
  posted_by          UUID,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, receipt_number)
);

-- ── Receipt Lines (Invoice Application) ──────────────────────
CREATE TABLE receipt_lines (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id        UUID          NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
  company_id        UUID          NOT NULL REFERENCES companies(id),
  invoice_id        UUID          NOT NULL REFERENCES sales_invoices(id),
  payment_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  cwt_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  forex_adjustment  NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (receipt_id, invoice_id)
);

-- ── Credit Memos (Header) ─────────────────────────────────────
CREATE TABLE credit_memos (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID          NOT NULL REFERENCES companies(id),
  branch_id           UUID          NOT NULL REFERENCES branches(id),
  customer_id         UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot TEXT       NOT NULL DEFAULT '',
  customer_tin_snapshot  TEXT       NOT NULL DEFAULT '',
  invoice_id          UUID          REFERENCES sales_invoices(id),
  cm_number           TEXT          NOT NULL,
  cm_date             DATE          NOT NULL DEFAULT CURRENT_DATE,
  reason_code_id      UUID          NOT NULL REFERENCES ref_reason_codes(id),
  remarks             TEXT,
  total_net_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_vat_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  status              TEXT          NOT NULL DEFAULT 'draft'
                                    CHECK (status IN ('draft','approved','applied','cancelled')),
  journal_entry_id    UUID,
  posted_at           TIMESTAMPTZ,
  posted_by           UUID,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, cm_number)
);

-- ── Credit Memo Lines ─────────────────────────────────────────
CREATE TABLE credit_memo_lines (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_memo_id      UUID          NOT NULL REFERENCES credit_memos(id) ON DELETE CASCADE,
  company_id          UUID          NOT NULL REFERENCES companies(id),
  invoice_line_id     UUID          REFERENCES sales_invoice_lines(id),
  item_id             UUID          REFERENCES items(id),
  description         TEXT          NOT NULL,
  quantity            NUMERIC(15,4) NOT NULL DEFAULT 1,
  unit_price          NUMERIC(15,4) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID          REFERENCES vat_codes(id),
  vat_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  revenue_account_id  UUID          REFERENCES chart_of_accounts(id),
  line_number         INTEGER       NOT NULL DEFAULT 1,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── Debit Memos (Header) ──────────────────────────────────────
CREATE TABLE debit_memos (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID          NOT NULL REFERENCES companies(id),
  branch_id           UUID          NOT NULL REFERENCES branches(id),
  customer_id         UUID          NOT NULL REFERENCES customers(id),
  customer_name_snapshot TEXT       NOT NULL DEFAULT '',
  customer_tin_snapshot  TEXT       NOT NULL DEFAULT '',
  source_doc_type     TEXT          CHECK (source_doc_type IN ('invoice','receipt')),
  source_doc_id       UUID,
  dm_number           TEXT          NOT NULL,
  dm_date             DATE          NOT NULL DEFAULT CURRENT_DATE,
  reason_code_id      UUID          NOT NULL REFERENCES ref_reason_codes(id),
  remarks             TEXT,
  total_net_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_vat_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  status              TEXT          NOT NULL DEFAULT 'draft'
                                    CHECK (status IN ('draft','approved','paid','cancelled')),
  journal_entry_id    UUID,
  posted_at           TIMESTAMPTZ,
  posted_by           UUID,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, dm_number)
);

-- ── Debit Memo Lines ──────────────────────────────────────────
CREATE TABLE debit_memo_lines (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  debit_memo_id       UUID          NOT NULL REFERENCES debit_memos(id) ON DELETE CASCADE,
  company_id          UUID          NOT NULL REFERENCES companies(id),
  account_id          UUID          REFERENCES chart_of_accounts(id),
  item_id             UUID          REFERENCES items(id),
  description         TEXT          NOT NULL,
  amount              NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID          REFERENCES vat_codes(id),
  vat_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  line_number         INTEGER       NOT NULL DEFAULT 1,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_receipts_company_id    ON receipts (company_id);
CREATE INDEX idx_receipts_customer_id   ON receipts (customer_id);
CREATE INDEX idx_receipts_date          ON receipts (receipt_date DESC);
CREATE INDEX idx_receipt_lines_si       ON receipt_lines (invoice_id);
CREATE INDEX idx_cm_company_id          ON credit_memos (company_id);
CREATE INDEX idx_cm_customer_id         ON credit_memos (customer_id);
CREATE INDEX idx_cm_invoice_id          ON credit_memos (invoice_id);
CREATE INDEX idx_dm_company_id          ON debit_memos (company_id);
CREATE INDEX idx_dm_customer_id         ON debit_memos (customer_id);

-- ── updated_at triggers ───────────────────────────────────────
CREATE TRIGGER trg_receipts_updated_at
  BEFORE UPDATE ON receipts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_receipt_lines_updated_at
  BEFORE UPDATE ON receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_credit_memos_updated_at
  BEFORE UPDATE ON credit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_credit_memo_lines_updated_at
  BEFORE UPDATE ON credit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_debit_memos_updated_at
  BEFORE UPDATE ON debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_debit_memo_lines_updated_at
  BEFORE UPDATE ON debit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Row-Level Security ────────────────────────────────────────
ALTER TABLE ref_payment_modes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_reason_codes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE receipts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE receipt_lines      ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_memos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_memo_lines  ENABLE ROW LEVEL SECURITY;
ALTER TABLE debit_memos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE debit_memo_lines   ENABLE ROW LEVEL SECURITY;

-- Reference tables: read by all
CREATE POLICY "read_payment_modes"  ON ref_payment_modes FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_reason_codes"   ON ref_reason_codes  FOR SELECT TO authenticated USING (true);

-- Receipts
CREATE POLICY "read_receipts"       ON receipts FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_receipts"     ON receipts FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_draft_receipts" ON receipts FOR UPDATE TO authenticated
  USING (status IN ('draft'));
CREATE POLICY "block_delete_receipts" ON receipts FOR DELETE TO authenticated USING (false);

CREATE POLICY "read_receipt_lines"  ON receipt_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_receipt_lines" ON receipt_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_receipt_lines" ON receipt_lines FOR UPDATE TO authenticated
  USING (receipt_id IN (SELECT id FROM receipts WHERE status = 'draft'));
CREATE POLICY "delete_receipt_lines" ON receipt_lines FOR DELETE TO authenticated
  USING (receipt_id IN (SELECT id FROM receipts WHERE status = 'draft'));

-- Credit Memos
CREATE POLICY "read_credit_memos"   ON credit_memos FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_credit_memos" ON credit_memos FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_draft_cm"     ON credit_memos FOR UPDATE TO authenticated
  USING (status IN ('draft','approved'));
CREATE POLICY "block_delete_cm"     ON credit_memos FOR DELETE TO authenticated USING (false);

CREATE POLICY "read_cm_lines"       ON credit_memo_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_cm_lines"     ON credit_memo_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_cm_lines"     ON credit_memo_lines FOR UPDATE TO authenticated
  USING (credit_memo_id IN (SELECT id FROM credit_memos WHERE status IN ('draft','approved')));
CREATE POLICY "delete_cm_lines"     ON credit_memo_lines FOR DELETE TO authenticated
  USING (credit_memo_id IN (SELECT id FROM credit_memos WHERE status = 'draft'));

-- Debit Memos
CREATE POLICY "read_debit_memos"    ON debit_memos FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_debit_memos"  ON debit_memos FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_draft_dm"     ON debit_memos FOR UPDATE TO authenticated
  USING (status IN ('draft','approved'));
CREATE POLICY "block_delete_dm"     ON debit_memos FOR DELETE TO authenticated USING (false);

CREATE POLICY "read_dm_lines"       ON debit_memo_lines FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_dm_lines"     ON debit_memo_lines FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "update_dm_lines"     ON debit_memo_lines FOR UPDATE TO authenticated
  USING (debit_memo_id IN (SELECT id FROM debit_memos WHERE status IN ('draft','approved')));
CREATE POLICY "delete_dm_lines"     ON debit_memo_lines FOR DELETE TO authenticated
  USING (debit_memo_id IN (SELECT id FROM debit_memos WHERE status = 'draft'));
