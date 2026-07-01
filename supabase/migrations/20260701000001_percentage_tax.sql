-- ══════════════════════════════════════════════════════════════════════════════
-- S14: PERCENTAGE TAX MODULE (Compliance)
-- BIR Form 2551Q — Quarterly Percentage Tax Return (non-VAT registered / PT-liable sales)
-- Working papers (manual schedule) + computed return (from posted SI exempt/zero-rated lines)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── PT Working Papers: header + lines (manual schedule, quarter-based) ────────
CREATE TABLE compliance_pt_working_papers_headers (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID          NOT NULL REFERENCES companies(id),
  period_year     INTEGER       NOT NULL,
  period_quarter  INTEGER       NOT NULL CHECK (period_quarter BETWEEN 1 AND 4),
  description     TEXT,
  status          TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period_year, period_quarter)
);

CREATE TABLE compliance_pt_working_papers_lines (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  header_id   UUID          NOT NULL REFERENCES compliance_pt_working_papers_headers(id) ON DELETE CASCADE,
  reference   TEXT,
  amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks     TEXT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE compliance_pt_working_papers_headers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pt_wp_h_read"   ON compliance_pt_working_papers_headers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pt_wp_h_insert" ON compliance_pt_working_papers_headers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pt_wp_h_update" ON compliance_pt_working_papers_headers FOR UPDATE TO authenticated USING (is_company_member(company_id));

ALTER TABLE compliance_pt_working_papers_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pt_wp_l_read"   ON compliance_pt_working_papers_lines FOR SELECT TO authenticated USING (
  is_company_member((SELECT company_id FROM compliance_pt_working_papers_headers WHERE id = header_id)));
CREATE POLICY "pt_wp_l_insert" ON compliance_pt_working_papers_lines FOR INSERT TO authenticated WITH CHECK (
  is_company_member((SELECT company_id FROM compliance_pt_working_papers_headers WHERE id = header_id)));
CREATE POLICY "pt_wp_l_update" ON compliance_pt_working_papers_lines FOR UPDATE TO authenticated USING (
  is_company_member((SELECT company_id FROM compliance_pt_working_papers_headers WHERE id = header_id)));
CREATE POLICY "pt_wp_l_delete" ON compliance_pt_working_papers_lines FOR DELETE TO authenticated USING (
  is_company_member((SELECT company_id FROM compliance_pt_working_papers_headers WHERE id = header_id)));

CREATE TRIGGER trg_pt_wp_h_updated_at
  BEFORE UPDATE ON compliance_pt_working_papers_headers
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── PT Returns: computed quarterly 2551Q, one row per company+quarter ─────────
CREATE TABLE pt_returns (
  id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                UUID          NOT NULL REFERENCES companies(id),
  period_year               INTEGER       NOT NULL,
  period_quarter            INTEGER       NOT NULL CHECK (period_quarter BETWEEN 1 AND 4),
  gross_sales_exempt        NUMERIC(15,2) NOT NULL DEFAULT 0,
  gross_sales_zero_rated    NUMERIC(15,2) NOT NULL DEFAULT 0,
  taxable_base              NUMERIC(15,2) NOT NULL DEFAULT 0,
  pt_rate                   NUMERIC(5,2)  NOT NULL DEFAULT 3.00,
  pt_due                    NUMERIC(15,2) NOT NULL DEFAULT 0,
  pt_paid_prior_quarters    NUMERIC(15,2) NOT NULL DEFAULT 0,
  pt_still_due              NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                    TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  filed_date                DATE,
  reference_no              TEXT,
  remarks                   TEXT,
  created_by                UUID,
  updated_by                UUID,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period_year, period_quarter)
);

ALTER TABLE pt_returns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pt_returns_read"   ON pt_returns FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pt_returns_insert" ON pt_returns FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pt_returns_update" ON pt_returns FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_pt_returns_updated_at
  BEFORE UPDATE ON pt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE INDEX idx_pt_returns_company_period ON pt_returns (company_id, period_year, period_quarter);
