-- ══════════════════════════════════════════════════════════════════════════════
-- PURCHASING MODULE — Full Build
-- Purchase Orders → Receiving Reports → Vendor Bills → Payment Vouchers
-- Plus: Cash Purchases, Vendor Credits, Supplier Debit Memos, Purchase Returns
-- Plus: AP Aging, Supplier Ledger, Input VAT Review, EWT Summary, Registers
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Extend payment_vouchers for check/payment tracking ────────────────────────
ALTER TABLE payment_vouchers
  ADD COLUMN IF NOT EXISTS check_number   TEXT,
  ADD COLUMN IF NOT EXISTS check_date     DATE,
  ADD COLUMN IF NOT EXISTS date_released  DATE,
  ADD COLUMN IF NOT EXISTS released_by    UUID,
  ADD COLUMN IF NOT EXISTS date_cleared   DATE,
  ADD COLUMN IF NOT EXISTS cleared_by     UUID;

-- ── purchase_orders ───────────────────────────────────────────────────────────
CREATE TABLE purchase_orders (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  po_number              TEXT        NOT NULL,
  po_date                DATE        NOT NULL,
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  delivery_address       TEXT,
  expected_date          DATE,
  payment_terms_id       UUID        REFERENCES payment_terms(id),
  currency_code          TEXT        NOT NULL DEFAULT 'PHP',
  notes                  TEXT,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','approved','partially_received','fully_received','cancelled')),
  approved_by            UUID,
  approved_at            TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, po_number)
);

CREATE TABLE purchase_order_lines (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id         UUID        NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  company_id    UUID        NOT NULL REFERENCES companies(id),
  line_number   INT         NOT NULL,
  item_id       UUID        REFERENCES items(id),
  description   TEXT        NOT NULL,
  quantity      NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id        UUID        REFERENCES units_of_measure(id),
  unit_price    NUMERIC(15,4) NOT NULL DEFAULT 0,
  total_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_purchase_orders_company  ON purchase_orders (company_id, po_date DESC);
CREATE INDEX idx_purchase_orders_supplier ON purchase_orders (supplier_id);
CREATE INDEX idx_pol_po_id               ON purchase_order_lines (po_id);

CREATE TRIGGER trg_po_updated_at   BEFORE UPDATE ON purchase_orders      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_pol_updated_at  BEFORE UPDATE ON purchase_order_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE purchase_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "po_read"    ON purchase_orders      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "po_insert"  ON purchase_orders      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "po_update"  ON purchase_orders      FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pol_read"   ON purchase_order_lines FOR SELECT TO authenticated USING (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));
CREATE POLICY "pol_write"  ON purchase_order_lines FOR INSERT TO authenticated WITH CHECK (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));
CREATE POLICY "pol_update" ON purchase_order_lines FOR UPDATE TO authenticated USING (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));
CREATE POLICY "pol_delete" ON purchase_order_lines FOR DELETE TO authenticated USING (po_id IN (SELECT id FROM purchase_orders WHERE is_company_member(company_id)));

DO $$ BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_purchase_orders ON purchase_orders;
    CREATE TRIGGER trg_audit_purchase_orders AFTER INSERT OR UPDATE OR DELETE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END; $$;

-- ── receiving_reports ─────────────────────────────────────────────────────────
CREATE TABLE receiving_reports (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  rr_number              TEXT        NOT NULL,
  rr_date                DATE        NOT NULL,
  po_id                  UUID        NOT NULL REFERENCES purchase_orders(id),
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_dr_no         TEXT,
  remarks                TEXT,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','received','cancelled')),
  confirmed_by           UUID,
  confirmed_at           TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, rr_number)
);

CREATE TABLE receiving_report_lines (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  rr_id         UUID        NOT NULL REFERENCES receiving_reports(id) ON DELETE CASCADE,
  company_id    UUID        NOT NULL REFERENCES companies(id),
  po_line_id    UUID        REFERENCES purchase_order_lines(id),
  line_number   INT         NOT NULL,
  item_id       UUID        REFERENCES items(id),
  description   TEXT        NOT NULL,
  ordered_qty   NUMERIC(15,4) NOT NULL DEFAULT 0,
  received_qty  NUMERIC(15,4) NOT NULL DEFAULT 0,
  reject_qty    NUMERIC(15,4) NOT NULL DEFAULT 0,
  uom_id        UUID        REFERENCES units_of_measure(id),
  unit_price    NUMERIC(15,4) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rr_company ON receiving_reports (company_id, rr_date DESC);
CREATE INDEX idx_rr_po_id   ON receiving_reports (po_id);
CREATE INDEX idx_rrl_rr_id  ON receiving_report_lines (rr_id);

CREATE TRIGGER trg_rr_updated_at  BEFORE UPDATE ON receiving_reports      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_rrl_updated_at BEFORE UPDATE ON receiving_report_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE receiving_reports      ENABLE ROW LEVEL SECURITY;
ALTER TABLE receiving_report_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rr_read"    ON receiving_reports      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "rr_insert"  ON receiving_reports      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "rr_update"  ON receiving_reports      FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "rrl_read"   ON receiving_report_lines FOR SELECT TO authenticated USING (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));
CREATE POLICY "rrl_write"  ON receiving_report_lines FOR INSERT TO authenticated WITH CHECK (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));
CREATE POLICY "rrl_update" ON receiving_report_lines FOR UPDATE TO authenticated USING (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));
CREATE POLICY "rrl_delete" ON receiving_report_lines FOR DELETE TO authenticated USING (rr_id IN (SELECT id FROM receiving_reports WHERE is_company_member(company_id)));

-- ── cash_purchases ────────────────────────────────────────────────────────────
CREATE TABLE cash_purchases (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  cp_number              TEXT        NOT NULL,
  transaction_date       DATE        NOT NULL,
  supplier_id            UUID        REFERENCES suppliers(id),
  supplier_name_snapshot TEXT,
  supplier_tin_snapshot  TEXT,
  payment_account_id     UUID        REFERENCES chart_of_accounts(id),
  payment_method         TEXT        NOT NULL DEFAULT 'cash'
                                     CHECK (payment_method IN ('cash','check','transfer')),
  reference_number       TEXT,
  fiscal_period_id       UUID        REFERENCES fiscal_periods(id),
  remarks                TEXT,
  total_taxable_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_zero_rated_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_exempt_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_input_vat_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','posted','cancelled')),
  journal_entry_id       UUID        REFERENCES journal_entries(id),
  posted_by              UUID,
  posted_at              TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, cp_number)
);

CREATE TABLE cash_purchase_lines (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cp_id               UUID        NOT NULL REFERENCES cash_purchases(id) ON DELETE CASCADE,
  company_id          UUID        NOT NULL REFERENCES companies(id),
  line_number         INT         NOT NULL,
  item_id             UUID        REFERENCES items(id),
  description         TEXT        NOT NULL,
  quantity            NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id              UUID        REFERENCES units_of_measure(id),
  unit_price          NUMERIC(15,4) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID        REFERENCES vat_codes(id),
  input_vat_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  expense_account_id  UUID        REFERENCES chart_of_accounts(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_cp_company ON cash_purchases (company_id, transaction_date DESC);
CREATE INDEX idx_cpl_cp_id  ON cash_purchase_lines (cp_id);

CREATE TRIGGER trg_cp_updated_at  BEFORE UPDATE ON cash_purchases      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_cpl_updated_at BEFORE UPDATE ON cash_purchase_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE cash_purchases      ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_purchase_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cp_read"    ON cash_purchases      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cp_insert"  ON cash_purchases      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "cp_update"  ON cash_purchases      FOR UPDATE TO authenticated USING (status IN ('draft') AND is_company_member(company_id));
CREATE POLICY "cpl_read"   ON cash_purchase_lines FOR SELECT TO authenticated USING (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));
CREATE POLICY "cpl_write"  ON cash_purchase_lines FOR INSERT TO authenticated WITH CHECK (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));
CREATE POLICY "cpl_update" ON cash_purchase_lines FOR UPDATE TO authenticated USING (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));
CREATE POLICY "cpl_delete" ON cash_purchase_lines FOR DELETE TO authenticated USING (cp_id IN (SELECT id FROM cash_purchases WHERE is_company_member(company_id)));

DO $$ BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_cash_purchases ON cash_purchases;
    CREATE TRIGGER trg_audit_cash_purchases AFTER INSERT OR UPDATE OR DELETE ON cash_purchases
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END; $$;

-- ── vendor_credits ────────────────────────────────────────────────────────────
CREATE TABLE vendor_credits (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  vc_number              TEXT        NOT NULL,
  credit_date            DATE        NOT NULL,
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  supplier_cm_no         TEXT,
  reference_bill_id      UUID        REFERENCES vendor_bills(id),
  fiscal_period_id       UUID        REFERENCES fiscal_periods(id),
  remarks                TEXT,
  total_taxable_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_input_vat_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  remaining_balance      NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','open','applied','cancelled')),
  journal_entry_id       UUID        REFERENCES journal_entries(id),
  posted_by              UUID,
  posted_at              TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, vc_number)
);

CREATE TABLE vendor_credit_lines (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  vc_id               UUID        NOT NULL REFERENCES vendor_credits(id) ON DELETE CASCADE,
  company_id          UUID        NOT NULL REFERENCES companies(id),
  line_number         INT         NOT NULL,
  item_id             UUID        REFERENCES items(id),
  description         TEXT        NOT NULL,
  quantity            NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id              UUID        REFERENCES units_of_measure(id),
  unit_price          NUMERIC(15,4) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id         UUID        REFERENCES vat_codes(id),
  input_vat_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  expense_account_id  UUID        REFERENCES chart_of_accounts(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_vc_company ON vendor_credits (company_id, credit_date DESC);
CREATE INDEX idx_vcl_vc_id  ON vendor_credit_lines (vc_id);

CREATE TRIGGER trg_vc_updated_at  BEFORE UPDATE ON vendor_credits      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_vcl_updated_at BEFORE UPDATE ON vendor_credit_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE vendor_credits      ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_credit_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vc_read"    ON vendor_credits      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "vc_insert"  ON vendor_credits      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "vc_update"  ON vendor_credits      FOR UPDATE TO authenticated USING (status IN ('draft') AND is_company_member(company_id));
CREATE POLICY "vcl_read"   ON vendor_credit_lines FOR SELECT TO authenticated USING (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));
CREATE POLICY "vcl_write"  ON vendor_credit_lines FOR INSERT TO authenticated WITH CHECK (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));
CREATE POLICY "vcl_update" ON vendor_credit_lines FOR UPDATE TO authenticated USING (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));
CREATE POLICY "vcl_delete" ON vendor_credit_lines FOR DELETE TO authenticated USING (vc_id IN (SELECT id FROM vendor_credits WHERE is_company_member(company_id)));

DO $$ BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_vendor_credits ON vendor_credits;
    CREATE TRIGGER trg_audit_vendor_credits AFTER INSERT OR UPDATE OR DELETE ON vendor_credits
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END; $$;

-- ── supplier_debit_memos ──────────────────────────────────────────────────────
CREATE TABLE supplier_debit_memos (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  sdm_number             TEXT        NOT NULL,
  dm_date                DATE        NOT NULL,
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  reference_doc_id       UUID,
  reference_doc_type     TEXT        CHECK (reference_doc_type IN ('receiving_report','vendor_bill')),
  reason                 TEXT,
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','sent','acknowledged','cancelled')),
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, sdm_number)
);

CREATE TABLE supplier_debit_memo_lines (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sdm_id        UUID        NOT NULL REFERENCES supplier_debit_memos(id) ON DELETE CASCADE,
  company_id    UUID        NOT NULL REFERENCES companies(id),
  line_number   INT         NOT NULL,
  item_id       UUID        REFERENCES items(id),
  description   TEXT        NOT NULL,
  quantity      NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id        UUID        REFERENCES units_of_measure(id),
  unit_price    NUMERIC(15,4) NOT NULL DEFAULT 0,
  total_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sdm_company ON supplier_debit_memos (company_id, dm_date DESC);
CREATE INDEX idx_sdml_sdm_id ON supplier_debit_memo_lines (sdm_id);

CREATE TRIGGER trg_sdm_updated_at  BEFORE UPDATE ON supplier_debit_memos      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_sdml_updated_at BEFORE UPDATE ON supplier_debit_memo_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE supplier_debit_memos      ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_debit_memo_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sdm_read"    ON supplier_debit_memos      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "sdm_insert"  ON supplier_debit_memos      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "sdm_update"  ON supplier_debit_memos      FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "sdml_read"   ON supplier_debit_memo_lines FOR SELECT TO authenticated USING (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));
CREATE POLICY "sdml_write"  ON supplier_debit_memo_lines FOR INSERT TO authenticated WITH CHECK (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));
CREATE POLICY "sdml_update" ON supplier_debit_memo_lines FOR UPDATE TO authenticated USING (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));
CREATE POLICY "sdml_delete" ON supplier_debit_memo_lines FOR DELETE TO authenticated USING (sdm_id IN (SELECT id FROM supplier_debit_memos WHERE is_company_member(company_id)));

-- ── purchase_returns ──────────────────────────────────────────────────────────
CREATE TABLE purchase_returns (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  return_number          TEXT        NOT NULL,
  return_date            DATE        NOT NULL,
  rr_id                  UUID        NOT NULL REFERENCES receiving_reports(id),
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  remarks                TEXT,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','shipped','completed','cancelled')),
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, return_number)
);

CREATE TABLE purchase_return_lines (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id    UUID        NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
  company_id   UUID        NOT NULL REFERENCES companies(id),
  rr_line_id   UUID        REFERENCES receiving_report_lines(id),
  line_number  INT         NOT NULL,
  item_id      UUID        REFERENCES items(id),
  description  TEXT        NOT NULL,
  max_qty      NUMERIC(15,4) NOT NULL DEFAULT 0,
  return_qty   NUMERIC(15,4) NOT NULL DEFAULT 0,
  uom_id       UUID        REFERENCES units_of_measure(id),
  unit_price   NUMERIC(15,4) NOT NULL DEFAULT 0,
  reason       TEXT,
  created_by   UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pr_company ON purchase_returns (company_id, return_date DESC);
CREATE INDEX idx_prl_pr_id  ON purchase_return_lines (return_id);

CREATE TRIGGER trg_pr_updated_at  BEFORE UPDATE ON purchase_returns      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_prl_updated_at BEFORE UPDATE ON purchase_return_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE purchase_returns      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_return_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pr_read"    ON purchase_returns      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pr_insert"  ON purchase_returns      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pr_update"  ON purchase_returns      FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "prl_read"   ON purchase_return_lines FOR SELECT TO authenticated USING (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));
CREATE POLICY "prl_write"  ON purchase_return_lines FOR INSERT TO authenticated WITH CHECK (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));
CREATE POLICY "prl_update" ON purchase_return_lines FOR UPDATE TO authenticated USING (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));
CREATE POLICY "prl_delete" ON purchase_return_lines FOR DELETE TO authenticated USING (return_id IN (SELECT id FROM purchase_returns WHERE is_company_member(company_id)));

-- ── form_2307_issuances ───────────────────────────────────────────────────────
CREATE TABLE form_2307_issuances (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID        NOT NULL REFERENCES companies(id),
  supplier_id     UUID        NOT NULL REFERENCES suppliers(id),
  tax_year        INT         NOT NULL,
  tax_quarter     INT         NOT NULL CHECK (tax_quarter BETWEEN 1 AND 4),
  total_tax_base  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_ewt       NUMERIC(15,2) NOT NULL DEFAULT 0,
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','generated','sent','acknowledged')),
  date_generated  TIMESTAMPTZ,
  date_sent       TIMESTAMPTZ,
  date_acknowledged TIMESTAMPTZ,
  remarks         TEXT,
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, supplier_id, tax_year, tax_quarter)
);

CREATE INDEX idx_f2307_company ON form_2307_issuances (company_id, tax_year DESC, tax_quarter DESC);

CREATE TRIGGER trg_f2307_updated_at BEFORE UPDATE ON form_2307_issuances FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE form_2307_issuances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "f2307_read"   ON form_2307_issuances FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "f2307_insert" ON form_2307_issuances FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "f2307_update" ON form_2307_issuances FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- ══════════════════════════════════════════════════════════════════════════════
-- VIEWS
-- ══════════════════════════════════════════════════════════════════════════════

-- ── vw_ap_aging ───────────────────────────────────────────────────────────────
-- Active payables (posted VBs) with balance_due computed from posted PVs
CREATE OR REPLACE VIEW vw_ap_aging AS
SELECT
  vb.id,
  vb.company_id,
  vb.supplier_id,
  s.registered_name  AS supplier_name,
  s.tin              AS supplier_tin,
  vb.bill_number,
  vb.bill_date,
  vb.due_date,
  vb.total_amount,
  vb.total_amount - COALESCE((
    SELECT SUM(pvl.payment_amount + pvl.ewt_amount)
    FROM payment_voucher_lines pvl
    JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.vendor_bill_id = vb.id AND pv.status = 'posted' AND pv.company_id = vb.company_id
  ), 0) AS balance_due
FROM vendor_bills vb
JOIN suppliers s ON s.id = vb.supplier_id
WHERE vb.status = 'posted';

-- ── vw_supplier_ledger ────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_supplier_ledger AS
SELECT
  vb.company_id,
  vb.supplier_id,
  vb.bill_date        AS transaction_date,
  'vendor_bill'       AS document_type,
  vb.id               AS document_id,
  vb.bill_number      AS document_number,
  vb.supplier_invoice_number AS external_ref,
  vb.memo             AS description,
  0                   AS debit_amount,
  vb.total_amount     AS credit_amount,
  vb.created_at
FROM vendor_bills vb
WHERE vb.status = 'posted'
UNION ALL
SELECT
  pv.company_id,
  pv.supplier_id,
  pv.voucher_date     AS transaction_date,
  'payment_voucher'   AS document_type,
  pv.id               AS document_id,
  pv.voucher_number   AS document_number,
  pv.reference_number AS external_ref,
  pv.remarks          AS description,
  pv.total_amount + pv.total_ewt AS debit_amount,
  0                   AS credit_amount,
  pv.created_at
FROM payment_vouchers pv
WHERE pv.status = 'posted'
UNION ALL
SELECT
  vc.company_id,
  vc.supplier_id,
  vc.credit_date      AS transaction_date,
  'vendor_credit'     AS document_type,
  vc.id               AS document_id,
  vc.vc_number        AS document_number,
  vc.supplier_cm_no   AS external_ref,
  vc.remarks          AS description,
  vc.total_amount     AS debit_amount,
  0                   AS credit_amount,
  vc.created_at
FROM vendor_credits vc
WHERE vc.status IN ('open','applied');

-- ── vw_input_vat_review ───────────────────────────────────────────────────────
-- Aggregates per bill from vendor_bill_lines classified by VAT type
DROP VIEW IF EXISTS vw_input_vat_review;
CREATE OR REPLACE VIEW vw_input_vat_review AS
SELECT
  vb.id                 AS transaction_id,
  'vendor_bill'         AS source_module,
  vb.company_id,
  vb.bill_date          AS invoice_date,
  vb.supplier_tin_snapshot AS supplier_tin,
  vb.supplier_name_snapshot AS supplier_name,
  COALESCE((SELECT s.registered_address FROM suppliers s WHERE s.id = vb.supplier_id), '') AS supplier_address,
  vb.supplier_invoice_number AS invoice_no,
  vb.bill_number        AS system_no,
  COALESCE(SUM(vbl.net_amount + vbl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc2.vat_classification = 'exempt'    THEN vbl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc2.vat_classification = 'zero_rated' THEN vbl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc2.vat_classification = 'regular'   THEN vbl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(vbl.input_vat_amount), 0) AS input_vat
FROM vendor_bills vb
JOIN vendor_bill_lines vbl ON vbl.vendor_bill_id = vb.id
LEFT JOIN vat_codes vc2 ON vc2.id = vbl.vat_code_id
WHERE vb.status = 'posted'
GROUP BY vb.id, vb.company_id, vb.bill_date, vb.supplier_tin_snapshot, vb.supplier_name_snapshot,
         vb.supplier_id, vb.supplier_invoice_number, vb.bill_number
UNION ALL
SELECT
  cp.id                 AS transaction_id,
  'cash_purchase'       AS source_module,
  cp.company_id,
  cp.transaction_date   AS invoice_date,
  cp.supplier_tin_snapshot AS supplier_tin,
  COALESCE(cp.supplier_name_snapshot, 'Cash Purchase') AS supplier_name,
  ''                    AS supplier_address,
  cp.reference_number   AS invoice_no,
  cp.cp_number          AS system_no,
  COALESCE(SUM(cpl.net_amount + cpl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'exempt'    THEN cpl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'zero_rated' THEN cpl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'regular'   THEN cpl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(cpl.input_vat_amount), 0) AS input_vat
FROM cash_purchases cp
JOIN cash_purchase_lines cpl ON cpl.cp_id = cp.id
LEFT JOIN vat_codes vc3 ON vc3.id = cpl.vat_code_id
WHERE cp.status = 'posted'
GROUP BY cp.id, cp.company_id, cp.transaction_date, cp.supplier_tin_snapshot,
         cp.supplier_name_snapshot, cp.reference_number, cp.cp_number;

-- ── vw_ewt_summary_ap ─────────────────────────────────────────────────────────
-- EWT withheld per PV line grouped by ATC code
CREATE OR REPLACE VIEW vw_ewt_summary_ap AS
SELECT
  pv.id               AS transaction_id,
  pv.company_id,
  pv.voucher_date     AS invoice_date,
  pv.supplier_id,
  pv.supplier_tin_snapshot AS supplier_tin,
  pv.supplier_name_snapshot AS supplier_name,
  ac.code AS atc_code,
  ac.description      AS nature_of_payment,
  ac.rate             AS tax_rate,
  pvl.ewt_amount / NULLIF(ac.rate / 100.0, 0) AS tax_base,
  pvl.ewt_amount      AS tax_withheld
FROM payment_vouchers pv
JOIN payment_voucher_lines pvl ON pvl.payment_voucher_id = pv.id
JOIN atc_codes ac ON ac.id = pvl.atc_code_id
WHERE pv.status = 'posted' AND pvl.ewt_amount > 0;

-- ── vw_vendor_bill_register ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_vendor_bill_register AS
SELECT
  vb.id,
  vb.company_id,
  vb.bill_date,
  vb.bill_number,
  vb.supplier_name_snapshot AS supplier_name,
  vb.supplier_tin_snapshot  AS supplier_tin,
  vb.supplier_invoice_number,
  vb.due_date,
  vb.total_taxable_amount,
  vb.total_zero_rated_amount,
  vb.total_exempt_amount,
  vb.total_input_vat_amount AS input_vat,
  COALESCE(vb.ewt_amount_expected, 0) AS ewt_deducted,
  vb.total_amount,
  vb.status,
  vb.created_at
FROM vendor_bills vb;

-- ── vw_payment_register ───────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_payment_register AS
SELECT
  pv.id,
  pv.company_id,
  pv.voucher_date,
  pv.voucher_number,
  pv.supplier_name_snapshot AS supplier_name,
  pv.supplier_tin_snapshot  AS supplier_tin,
  pv.reference_number,
  pv.check_number,
  pv.check_date,
  pv.total_amount,
  pv.total_ewt,
  pv.total_amount + pv.total_ewt AS total_cleared,
  pv.status,
  pv.date_released,
  pv.date_cleared,
  pv.created_at
FROM payment_vouchers pv;

-- ── vw_sdm_register ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_sdm_register AS
SELECT
  sdm.id,
  sdm.company_id,
  sdm.dm_date,
  sdm.sdm_number,
  sdm.supplier_name_snapshot AS supplier_name,
  sdm.supplier_tin_snapshot  AS supplier_tin,
  sdm.reason,
  sdm.total_amount,
  sdm.status,
  sdm.created_at
FROM supplier_debit_memos sdm;

-- ── vw_slp_export ─────────────────────────────────────────────────────────────
-- Summary List of Purchases grouped by supplier per month (from posted VBs)
CREATE OR REPLACE VIEW vw_slp_export AS
SELECT
  vb.company_id,
  TO_CHAR(DATE_TRUNC('month', vb.bill_date), 'MM/YYYY') AS taxable_month,
  vb.bill_date,
  vb.supplier_tin_snapshot  AS supplier_tin,
  vb.supplier_name_snapshot AS registered_name,
  COALESCE((SELECT s.registered_address FROM suppliers s WHERE s.id = vb.supplier_id), '') AS address,
  COALESCE(SUM(vbl.net_amount + vbl.input_vat_amount), 0) AS gross_purchases,
  COALESCE(SUM(CASE WHEN vc4.vat_classification = 'exempt'    THEN vbl.net_amount ELSE 0 END), 0) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN vc4.vat_classification = 'zero_rated' THEN vbl.net_amount ELSE 0 END), 0) AS zero_rated,
  COALESCE(SUM(CASE WHEN vc4.vat_classification = 'regular'   THEN vbl.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(vbl.input_vat_amount), 0) AS input_vat
FROM vendor_bills vb
JOIN vendor_bill_lines vbl ON vbl.vendor_bill_id = vb.id
LEFT JOIN vat_codes vc4 ON vc4.id = vbl.vat_code_id
WHERE vb.status = 'posted'
GROUP BY vb.company_id, DATE_TRUNC('month', vb.bill_date), vb.bill_date,
         vb.supplier_tin_snapshot, vb.supplier_name_snapshot, vb.supplier_id;

-- ══════════════════════════════════════════════════════════════════════════════
-- RPCs
-- ══════════════════════════════════════════════════════════════════════════════

-- ── fn_save_purchase_order ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_purchase_order(
  p_po_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_po_number    TEXT;
  v_cur_status   TEXT;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF p_po_id IS NULL THEN
    v_po_number := fn_next_document_number(v_company_id, v_branch_id, 'PO');
    INSERT INTO purchase_orders (
      company_id, branch_id, po_number, po_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot,
      delivery_address, expected_date, payment_terms_id,
      currency_code, notes, total_amount, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_po_number,
      (p_header->>'po_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'delivery_address', ''),
      NULLIF(p_header->>'expected_date', '')::DATE,
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'notes', ''),
      0, 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_po_id;
  ELSE
    SELECT id, status INTO v_po_id, v_cur_status
    FROM purchase_orders WHERE id = p_po_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order not found'; END IF;
    IF v_cur_status NOT IN ('draft') THEN
      RAISE EXCEPTION 'Cannot edit a % purchase order', v_cur_status;
    END IF;
    UPDATE purchase_orders SET
      branch_id = v_branch_id,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      po_date = (p_header->>'po_date')::DATE,
      delivery_address = NULLIF(p_header->>'delivery_address', ''),
      expected_date = NULLIF(p_header->>'expected_date', '')::DATE,
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      notes = NULLIF(p_header->>'notes', ''),
      total_amount = 0, updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_po_id;
  END IF;

  DELETE FROM purchase_order_lines WHERE po_id = v_po_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    INSERT INTO purchase_order_lines (
      po_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, total_amount, created_by
    ) VALUES (
      v_po_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      ROUND(v_qty * v_price, 2), auth.uid()
    );
    v_grand_total := v_grand_total + ROUND(v_qty * v_price, 2);
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE purchase_orders SET total_amount = v_grand_total, updated_at = NOW() WHERE id = v_po_id;
  RETURN v_po_id;
END;
$$;

-- ── fn_approve_purchase_order ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_approve_purchase_order(p_po_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_orders WHERE id = p_po_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft POs can be approved (current: %)', v_rec.status; END IF;
  UPDATE purchase_orders SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(),
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_po_id;
END;
$$;

-- ── fn_cancel_purchase_order ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_purchase_order(p_po_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_orders WHERE id = p_po_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status IN ('fully_received','cancelled') THEN RAISE EXCEPTION 'Cannot cancel a % purchase order', v_rec.status; END IF;
  UPDATE purchase_orders SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_po_id;
END;
$$;

-- ── fn_save_receiving_report ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_receiving_report(
  p_rr_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rr_id      UUID;
  v_company_id UUID;
  v_branch_id  UUID;
  v_rr_number  TEXT;
  v_cur_status TEXT;
  v_po_rec     purchase_orders%ROWTYPE;
  v_line       JSONB;
  v_line_no    INT := 1;
  v_has_lines  BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_po_rec FROM purchase_orders
  WHERE id = (p_header->>'po_id')::UUID AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order not found'; END IF;
  IF v_po_rec.status NOT IN ('approved','partially_received') THEN
    RAISE EXCEPTION 'PO must be approved to create RR (current: %)', v_po_rec.status;
  END IF;

  IF p_rr_id IS NULL THEN
    v_rr_number := fn_next_document_number(v_company_id, v_branch_id, 'RR');
    INSERT INTO receiving_reports (
      company_id, branch_id, rr_number, rr_date, po_id, supplier_id,
      supplier_name_snapshot, supplier_dr_no, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_rr_number,
      (p_header->>'rr_date')::DATE,
      v_po_rec.id, v_po_rec.supplier_id,
      v_po_rec.supplier_name_snapshot,
      NULLIF(p_header->>'supplier_dr_no', ''),
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_rr_id;
  ELSE
    SELECT id, status INTO v_rr_id, v_cur_status
    FROM receiving_reports WHERE id = p_rr_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Receiving report not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % RR', v_cur_status; END IF;
    UPDATE receiving_reports SET
      rr_date = (p_header->>'rr_date')::DATE,
      supplier_dr_no = NULLIF(p_header->>'supplier_dr_no', ''),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_rr_id;
  END IF;

  DELETE FROM receiving_report_lines WHERE rr_id = v_rr_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    INSERT INTO receiving_report_lines (
      rr_id, company_id, po_line_id, line_number,
      item_id, description, ordered_qty, received_qty, reject_qty,
      uom_id, unit_price, created_by
    ) VALUES (
      v_rr_id, v_company_id,
      NULLIF(v_line->>'po_line_id', '')::UUID,
      v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description',
      COALESCE((v_line->>'ordered_qty')::NUMERIC, 0),
      GREATEST(COALESCE((v_line->>'received_qty')::NUMERIC, 0), 0),
      GREATEST(COALESCE((v_line->>'reject_qty')::NUMERIC, 0), 0),
      NULLIF(v_line->>'uom_id', '')::UUID,
      COALESCE((v_line->>'unit_price')::NUMERIC, 0),
      auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  RETURN v_rr_id;
END;
$$;

-- ── fn_confirm_receiving_report ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_confirm_receiving_report(p_rr_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rr    receiving_reports%ROWTYPE;
  v_total_ordered  NUMERIC(15,4);
  v_total_received NUMERIC(15,4);
BEGIN
  SELECT * INTO v_rr FROM receiving_reports WHERE id = p_rr_id;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rr.status != 'draft' THEN RAISE EXCEPTION 'Only draft RRs can be confirmed (current: %)', v_rr.status; END IF;

  UPDATE receiving_reports SET status = 'received', confirmed_by = auth.uid(), confirmed_at = NOW(),
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_rr_id;

  -- Update PO receiving status
  SELECT SUM(pol.quantity), SUM(rrl.received_qty)
  INTO v_total_ordered, v_total_received
  FROM purchase_order_lines pol
  LEFT JOIN receiving_report_lines rrl ON rrl.po_line_id = pol.id
    AND rrl.rr_id IN (SELECT id FROM receiving_reports WHERE po_id = v_rr.po_id AND status = 'received')
  WHERE pol.po_id = v_rr.po_id;

  UPDATE purchase_orders SET
    status = CASE
      WHEN v_total_received >= v_total_ordered THEN 'fully_received'
      ELSE 'partially_received'
    END,
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_rr.po_id;
END;
$$;

-- ── fn_save_cash_purchase ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_cash_purchase(
  p_cp_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cp_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_cp_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_vat_rate     NUMERIC(5,2);
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_taxable      NUMERIC(15,2) := 0;
  v_zero_rated   NUMERIC(15,2) := 0;
  v_exempt       NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'transaction_date')::DATE
    AND end_date   >= (p_header->>'transaction_date')::DATE
    AND is_locked = false LIMIT 1;

  IF p_cp_id IS NULL THEN
    v_cp_number := fn_next_document_number(v_company_id, v_branch_id, 'CP');
    INSERT INTO cash_purchases (
      company_id, branch_id, cp_number, transaction_date,
      supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      payment_account_id, payment_method, reference_number,
      fiscal_period_id, remarks, total_taxable_amount, total_zero_rated_amount,
      total_exempt_amount, total_input_vat_amount, total_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_cp_number,
      (p_header->>'transaction_date')::DATE,
      NULLIF(p_header->>'supplier_id', '')::UUID,
      NULLIF(p_header->>'supplier_name_snapshot', ''),
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'payment_account_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      NULLIF(p_header->>'reference_number', ''),
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_cp_id;
  ELSE
    SELECT id, status INTO v_cp_id, v_cur_status
    FROM cash_purchases WHERE id = p_cp_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash purchase not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % cash purchase', v_cur_status; END IF;
    UPDATE cash_purchases SET
      transaction_date = (p_header->>'transaction_date')::DATE,
      supplier_id = NULLIF(p_header->>'supplier_id', '')::UUID,
      supplier_name_snapshot = NULLIF(p_header->>'supplier_name_snapshot', ''),
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      payment_account_id = NULLIF(p_header->>'payment_account_id', '')::UUID,
      payment_method = COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      reference_number = NULLIF(p_header->>'reference_number', ''),
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0,
      total_exempt_amount = 0, total_input_vat_amount = 0, total_amount = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cp_id;
  END IF;

  DELETE FROM cash_purchase_lines WHERE cp_id = v_cp_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_net + v_vat_amt;
    INSERT INTO cash_purchase_lines (
      cp_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_cp_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_net + v_vat_amt,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE cash_purchases SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, updated_at = NOW()
  WHERE id = v_cp_id;
  RETURN v_cp_id;
END;
$$;

-- ── fn_post_cash_purchase ─────────────────────────────────────────────────────
-- DR Expense accounts + DR Input VAT = CR Cash/Bank account
CREATE OR REPLACE FUNCTION fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM cash_purchases WHERE id = p_cp_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft cash purchases can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  v_cash_acct := COALESCE(v_rec.payment_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'Payment account not set. Add it on the form or configure a default cash account.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND (NOT FOUND OR v_cfg.input_vat_account_id IS NULL) THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.transaction_date
    AND end_date >= v_rec.transaction_date AND is_locked = false LIMIT 1;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CP-' || v_rec.cp_number, v_rec.transaction_date, v_fp_id,
    'Cash Purchase ' || v_rec.cp_number || COALESCE(' — ' || v_rec.supplier_name_snapshot, ''),
    'MANUAL', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Expense accounts per line
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM cash_purchase_lines
    WHERE cp_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- DR: Input VAT
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.cp_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  -- CR: Cash / Bank
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cash_acct,
          'Cash paid — ' || v_rec.cp_number, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE cash_purchases SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_save_vendor_credit ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_vendor_credit(
  p_vc_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_vc_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_vc_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_vat_rate     NUMERIC(5,2);
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_taxable      NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'credit_date')::DATE
    AND end_date   >= (p_header->>'credit_date')::DATE
    AND is_locked = false LIMIT 1;

  IF p_vc_id IS NULL THEN
    v_vc_number := fn_next_document_number(v_company_id, v_branch_id, 'VC');
    INSERT INTO vendor_credits (
      company_id, branch_id, vc_number, credit_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot, supplier_cm_no,
      reference_bill_id, fiscal_period_id, remarks,
      total_taxable_amount, total_input_vat_amount, total_amount, remaining_balance,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_vc_number,
      (p_header->>'credit_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'supplier_cm_no', ''),
      NULLIF(p_header->>'reference_bill_id', '')::UUID,
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_vc_id;
  ELSE
    SELECT id, status INTO v_vc_id, v_cur_status
    FROM vendor_credits WHERE id = p_vc_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vendor credit not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % vendor credit', v_cur_status; END IF;
    UPDATE vendor_credits SET
      credit_date = (p_header->>'credit_date')::DATE,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_cm_no = NULLIF(p_header->>'supplier_cm_no', ''),
      reference_bill_id = NULLIF(p_header->>'reference_bill_id', '')::UUID,
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_input_vat_amount = 0,
      total_amount = 0, remaining_balance = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_vc_id;
  END IF;

  DELETE FROM vendor_credit_lines WHERE vc_id = v_vc_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc2.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc2 JOIN tax_codes tc ON tc.id = vc2.tax_code_id
    WHERE vc2.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    IF v_vat_class = 'regular' THEN v_taxable := v_taxable + v_net; END IF;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_net + v_vat_amt;
    INSERT INTO vendor_credit_lines (
      vc_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_vc_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_net + v_vat_amt,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE vendor_credits SET
    total_taxable_amount = v_taxable, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, remaining_balance = v_grand_total,
    updated_at = NOW()
  WHERE id = v_vc_id;
  RETURN v_vc_id;
END;
$$;

-- ── fn_post_vendor_credit ─────────────────────────────────────────────────────
-- DR Accounts Payable = CR Expense accounts + CR Input VAT
CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.credit_date
    AND end_date >= v_rec.credit_date AND is_locked = false LIMIT 1;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date, v_fp_id,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'MANUAL', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Payable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  -- CR: Expense accounts per line
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  -- CR: Input VAT reversal
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_save_supplier_debit_memo ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_supplier_debit_memo(
  p_sdm_id UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sdm_id     UUID;
  v_company_id UUID;
  v_branch_id  UUID;
  v_sdm_number TEXT;
  v_cur_status TEXT;
  v_line       JSONB;
  v_line_no    INT := 1;
  v_qty        NUMERIC(15,4);
  v_price      NUMERIC(15,4);
  v_grand_total NUMERIC(15,2) := 0;
  v_has_lines  BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF p_sdm_id IS NULL THEN
    v_sdm_number := fn_next_document_number(v_company_id, v_branch_id, 'SDM');
    INSERT INTO supplier_debit_memos (
      company_id, branch_id, sdm_number, dm_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot,
      reference_doc_id, reference_doc_type, reason, total_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_sdm_number,
      (p_header->>'dm_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'reference_doc_id', '')::UUID,
      NULLIF(p_header->>'reference_doc_type', ''),
      NULLIF(p_header->>'reason', ''),
      0, 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_sdm_id;
  ELSE
    SELECT id, status INTO v_sdm_id, v_cur_status
    FROM supplier_debit_memos WHERE id = p_sdm_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
    IF v_cur_status NOT IN ('draft') THEN RAISE EXCEPTION 'Cannot edit a % debit memo', v_cur_status; END IF;
    UPDATE supplier_debit_memos SET
      dm_date = (p_header->>'dm_date')::DATE,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      reason = NULLIF(p_header->>'reason', ''),
      total_amount = 0, updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_sdm_id;
  END IF;

  DELETE FROM supplier_debit_memo_lines WHERE sdm_id = v_sdm_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    INSERT INTO supplier_debit_memo_lines (
      sdm_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, total_amount, created_by
    ) VALUES (
      v_sdm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      ROUND(v_qty * v_price, 2), auth.uid()
    );
    v_grand_total := v_grand_total + ROUND(v_qty * v_price, 2);
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE supplier_debit_memos SET total_amount = v_grand_total, updated_at = NOW() WHERE id = v_sdm_id;
  RETURN v_sdm_id;
END;
$$;

-- ── fn_send_supplier_debit_memo ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_send_supplier_debit_memo(p_sdm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec supplier_debit_memos%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM supplier_debit_memos WHERE id = p_sdm_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft memos can be sent (current: %)', v_rec.status; END IF;
  UPDATE supplier_debit_memos SET status = 'sent', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_sdm_id;
END;
$$;

-- ── fn_acknowledge_supplier_debit_memo ───────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_acknowledge_supplier_debit_memo(p_sdm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec supplier_debit_memos%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM supplier_debit_memos WHERE id = p_sdm_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'sent' THEN RAISE EXCEPTION 'Only sent memos can be acknowledged (current: %)', v_rec.status; END IF;
  UPDATE supplier_debit_memos SET status = 'acknowledged', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_sdm_id;
END;
$$;

-- ── fn_save_purchase_return ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_save_purchase_return(
  p_return_id UUID,
  p_header    JSONB,
  p_lines     JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ret_id     UUID;
  v_company_id UUID;
  v_branch_id  UUID;
  v_ret_number TEXT;
  v_cur_status TEXT;
  v_rr_rec     receiving_reports%ROWTYPE;
  v_line       JSONB;
  v_line_no    INT := 1;
  v_has_lines  BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_rr_rec FROM receiving_reports
  WHERE id = (p_header->>'rr_id')::UUID AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receiving report not found'; END IF;
  IF v_rr_rec.status != 'received' THEN
    RAISE EXCEPTION 'RR must be confirmed to create a return (current: %)', v_rr_rec.status;
  END IF;

  IF p_return_id IS NULL THEN
    v_ret_number := fn_next_document_number(v_company_id, v_branch_id, 'PRT');
    INSERT INTO purchase_returns (
      company_id, branch_id, return_number, return_date,
      rr_id, supplier_id, supplier_name_snapshot, remarks,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_ret_number,
      (p_header->>'return_date')::DATE,
      v_rr_rec.id, v_rr_rec.supplier_id, v_rr_rec.supplier_name_snapshot,
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_ret_id;
  ELSE
    SELECT id, status INTO v_ret_id, v_cur_status
    FROM purchase_returns WHERE id = p_return_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase return not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % return', v_cur_status; END IF;
    UPDATE purchase_returns SET
      return_date = (p_header->>'return_date')::DATE,
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_ret_id;
  END IF;

  DELETE FROM purchase_return_lines WHERE return_id = v_ret_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    INSERT INTO purchase_return_lines (
      return_id, company_id, rr_line_id, line_number,
      item_id, description, max_qty, return_qty, uom_id, unit_price, reason, created_by
    ) VALUES (
      v_ret_id, v_company_id,
      NULLIF(v_line->>'rr_line_id', '')::UUID,
      v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description',
      GREATEST(COALESCE((v_line->>'max_qty')::NUMERIC, 0), 0),
      GREATEST(LEAST(
        COALESCE((v_line->>'return_qty')::NUMERIC, 0),
        COALESCE((v_line->>'max_qty')::NUMERIC, 0)
      ), 0),
      NULLIF(v_line->>'uom_id', '')::UUID,
      COALESCE((v_line->>'unit_price')::NUMERIC, 0),
      NULLIF(v_line->>'reason', ''),
      auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  RETURN v_ret_id;
END;
$$;

-- ── fn_ship_purchase_return ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_ship_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_returns%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_returns WHERE id = p_return_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft returns can be shipped (current: %)', v_rec.status; END IF;
  UPDATE purchase_returns SET status = 'shipped', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_return_id;
END;
$$;

-- ── fn_complete_purchase_return ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_complete_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec purchase_returns%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM purchase_returns WHERE id = p_return_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'shipped' THEN RAISE EXCEPTION 'Only shipped returns can be completed (current: %)', v_rec.status; END IF;
  UPDATE purchase_returns SET status = 'completed', updated_by = auth.uid(), updated_at = NOW() WHERE id = p_return_id;
END;
$$;

-- ── fn_update_payment_tracking ────────────────────────────────────────────────
-- p_action: 'released' | 'cleared' | 'stale'
CREATE OR REPLACE FUNCTION fn_update_payment_tracking(
  p_voucher_id UUID,
  p_action     TEXT,
  p_date       DATE DEFAULT NULL,
  p_remarks    TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec payment_vouchers%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status NOT IN ('posted','released','cleared','stale') THEN
    RAISE EXCEPTION 'Cannot update tracking on a % voucher', v_rec.status;
  END IF;
  IF p_action = 'released' THEN
    UPDATE payment_vouchers SET status = 'released', date_released = COALESCE(p_date, CURRENT_DATE),
      released_by = auth.uid(), remarks = COALESCE(p_remarks, remarks), updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_voucher_id;
  ELSIF p_action = 'cleared' THEN
    UPDATE payment_vouchers SET status = 'cleared', date_cleared = COALESCE(p_date, CURRENT_DATE),
      cleared_by = auth.uid(), updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_voucher_id;
  ELSIF p_action = 'stale' THEN
    UPDATE payment_vouchers SET status = 'stale', updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_voucher_id;
  ELSE
    RAISE EXCEPTION 'Unknown action: %', p_action;
  END IF;
END;
$$;

-- Also update the status check on payment_vouchers to allow new tracking states
ALTER TABLE payment_vouchers DROP CONSTRAINT IF EXISTS payment_vouchers_status_check;
ALTER TABLE payment_vouchers ADD CONSTRAINT payment_vouchers_status_check
  CHECK (status IN ('draft','posted','released','cleared','stale','cancelled'));

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_save_purchase_order(UUID, JSONB, JSONB)         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_purchase_order(UUID)                    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_purchase_order(UUID)                     TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_receiving_report(UUID, JSONB, JSONB)       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_confirm_receiving_report(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_cash_purchase(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_cash_purchase(UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_vendor_credit(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_supplier_debit_memo(UUID, JSONB, JSONB)    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_send_supplier_debit_memo(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_acknowledge_supplier_debit_memo(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_purchase_return(UUID, JSONB, JSONB)        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ship_purchase_return(UUID)                      TO authenticated;
GRANT EXECUTE ON FUNCTION fn_complete_purchase_return(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_update_payment_tracking(UUID, TEXT, DATE, TEXT) TO authenticated;
