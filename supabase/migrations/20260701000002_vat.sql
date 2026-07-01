-- ══════════════════════════════════════════════════════════════════════════════
-- S15: VAT MODULE (Compliance)
-- BIR Forms 2550M (Monthly VAT Declaration) + 2550Q (Quarterly VAT Return)
-- Working papers (manual schedule) + computed returns + output VAT review view
-- ══════════════════════════════════════════════════════════════════════════════

-- ── VAT Working Papers: header + lines (manual schedule, month-based) ─────────
CREATE TABLE compliance_vat_working_papers_headers (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID          NOT NULL REFERENCES companies(id),
  period          DATE          NOT NULL,
  description     TEXT,
  status          TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period)
);

CREATE TABLE compliance_vat_working_papers_lines (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  header_id   UUID          NOT NULL REFERENCES compliance_vat_working_papers_headers(id) ON DELETE CASCADE,
  reference   TEXT,
  amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks     TEXT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE compliance_vat_working_papers_headers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vat_wp_h_read"   ON compliance_vat_working_papers_headers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "vat_wp_h_insert" ON compliance_vat_working_papers_headers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "vat_wp_h_update" ON compliance_vat_working_papers_headers FOR UPDATE TO authenticated USING (is_company_member(company_id));

ALTER TABLE compliance_vat_working_papers_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vat_wp_l_read"   ON compliance_vat_working_papers_lines FOR SELECT TO authenticated USING (
  is_company_member((SELECT company_id FROM compliance_vat_working_papers_headers WHERE id = header_id)));
CREATE POLICY "vat_wp_l_insert" ON compliance_vat_working_papers_lines FOR INSERT TO authenticated WITH CHECK (
  is_company_member((SELECT company_id FROM compliance_vat_working_papers_headers WHERE id = header_id)));
CREATE POLICY "vat_wp_l_update" ON compliance_vat_working_papers_lines FOR UPDATE TO authenticated USING (
  is_company_member((SELECT company_id FROM compliance_vat_working_papers_headers WHERE id = header_id)));
CREATE POLICY "vat_wp_l_delete" ON compliance_vat_working_papers_lines FOR DELETE TO authenticated USING (
  is_company_member((SELECT company_id FROM compliance_vat_working_papers_headers WHERE id = header_id)));

CREATE TRIGGER trg_vat_wp_h_updated_at
  BEFORE UPDATE ON compliance_vat_working_papers_headers
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── VAT Returns: computed 2550M (monthly) or 2550Q (quarterly) ────────────────
CREATE TABLE vat_returns (
  id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                UUID          NOT NULL REFERENCES companies(id),
  return_type               TEXT          NOT NULL CHECK (return_type IN ('2550M','2550Q')),
  period_year               INTEGER       NOT NULL,
  period_month              INTEGER       CHECK (period_month BETWEEN 1 AND 12),
  period_quarter            INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  output_taxable_sales      NUMERIC(15,2) NOT NULL DEFAULT 0,
  output_vat                NUMERIC(15,2) NOT NULL DEFAULT 0,
  zero_rated_sales          NUMERIC(15,2) NOT NULL DEFAULT 0,
  exempt_sales              NUMERIC(15,2) NOT NULL DEFAULT 0,
  input_taxable_purchases   NUMERIC(15,2) NOT NULL DEFAULT 0,
  input_vat                 NUMERIC(15,2) NOT NULL DEFAULT 0,
  input_vat_carried_over    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_available_input_vat NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_vat_payable           NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_paid_prior_months     NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_still_due             NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                    TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  filed_date                DATE,
  reference_no              TEXT,
  remarks                   TEXT,
  created_by                UUID,
  updated_by                UUID,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (
    (return_type = '2550M' AND period_month IS NOT NULL AND period_quarter IS NULL) OR
    (return_type = '2550Q' AND period_quarter IS NOT NULL AND period_month IS NULL)
  ),
  UNIQUE (company_id, return_type, period_year, period_month, period_quarter)
);

ALTER TABLE vat_returns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vat_returns_read"   ON vat_returns FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "vat_returns_insert" ON vat_returns FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "vat_returns_update" ON vat_returns FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_vat_returns_updated_at
  BEFORE UPDATE ON vat_returns
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE INDEX idx_vat_returns_company_period ON vat_returns (company_id, return_type, period_year, period_month, period_quarter);

-- ── vw_output_vat_review: mirrors vw_input_vat_review shape for the sales side ─
-- Sales invoices (incl. cash sales, is_cash_sale flag reuses same table) + CM (negative) + DM (positive, VAT-bearing only)
CREATE OR REPLACE VIEW vw_output_vat_review AS
SELECT
  si.id                    AS transaction_id,
  'sales_invoice'          AS source_module,
  si.company_id,
  si.date                  AS invoice_date,
  si.customer_tin_snapshot AS customer_tin,
  si.customer_name_snapshot AS customer_name,
  si.si_number             AS system_no,
  COALESCE(SUM(sil.net_amount + sil.vat_amount), 0) AS gross_sales,
  COALESCE(SUM(CASE WHEN vc.vat_classification = 'exempt'     THEN sil.net_amount ELSE 0 END), 0) AS exempt_sales,
  COALESCE(SUM(CASE WHEN vc.vat_classification = 'zero_rated' THEN sil.net_amount ELSE 0 END), 0) AS zero_rated_sales,
  COALESCE(SUM(CASE WHEN vc.vat_classification = 'regular'    THEN sil.net_amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(sil.vat_amount), 0) AS output_vat
FROM sales_invoices si
JOIN sales_invoice_lines sil ON sil.sales_invoice_id = si.id
LEFT JOIN vat_codes vc ON vc.id = sil.vat_code_id
WHERE si.status = 'posted'
GROUP BY si.id, si.company_id, si.date, si.customer_tin_snapshot, si.customer_name_snapshot, si.si_number

UNION ALL

SELECT
  cm.id                    AS transaction_id,
  'credit_memo'            AS source_module,
  cm.company_id,
  cm.cm_date                AS invoice_date,
  cm.customer_tin_snapshot AS customer_tin,
  cm.customer_name_snapshot AS customer_name,
  cm.cm_number              AS system_no,
  -COALESCE(SUM(cml.net_amount + cml.vat_amount), 0) AS gross_sales,
  -COALESCE(SUM(CASE WHEN vc2.vat_classification = 'exempt'     THEN cml.net_amount ELSE 0 END), 0) AS exempt_sales,
  -COALESCE(SUM(CASE WHEN vc2.vat_classification = 'zero_rated' THEN cml.net_amount ELSE 0 END), 0) AS zero_rated_sales,
  -COALESCE(SUM(CASE WHEN vc2.vat_classification = 'regular'    THEN cml.net_amount ELSE 0 END), 0) AS taxable_base,
  -COALESCE(SUM(cml.vat_amount), 0) AS output_vat
FROM credit_memos cm
JOIN credit_memo_lines cml ON cml.credit_memo_id = cm.id
LEFT JOIN vat_codes vc2 ON vc2.id = cml.vat_code_id
WHERE cm.status = 'applied'
GROUP BY cm.id, cm.company_id, cm.cm_date, cm.customer_tin_snapshot, cm.customer_name_snapshot, cm.cm_number

UNION ALL

SELECT
  dm.id                    AS transaction_id,
  'debit_memo'             AS source_module,
  dm.company_id,
  dm.dm_date                AS invoice_date,
  dm.customer_tin_snapshot AS customer_tin,
  dm.customer_name_snapshot AS customer_name,
  dm.dm_number              AS system_no,
  COALESCE(SUM(dml.amount + dml.vat_amount), 0) AS gross_sales,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'exempt'     THEN dml.amount ELSE 0 END), 0) AS exempt_sales,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'zero_rated' THEN dml.amount ELSE 0 END), 0) AS zero_rated_sales,
  COALESCE(SUM(CASE WHEN vc3.vat_classification = 'regular'    THEN dml.amount ELSE 0 END), 0) AS taxable_base,
  COALESCE(SUM(dml.vat_amount), 0) AS output_vat
FROM debit_memos dm
JOIN debit_memo_lines dml ON dml.debit_memo_id = dm.id
LEFT JOIN vat_codes vc3 ON vc3.id = dml.vat_code_id
WHERE dm.status = 'paid'
GROUP BY dm.id, dm.company_id, dm.dm_date, dm.customer_tin_snapshot, dm.customer_name_snapshot, dm.dm_number;
