-- ── EWT Working Papers ───────────────────────────────────────────────────────
-- Stores Expanded Withholding Tax schedule and reconciliation working papers,
-- one document per company per period.

-- Header: one per period per company (unique constraint enforced)
CREATE TABLE IF NOT EXISTS compliance_ewt_working_papers_headers (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID        NOT NULL REFERENCES companies(id),
  period      DATE        NOT NULL,
  description TEXT,
  status      TEXT        NOT NULL DEFAULT 'draft'
              CHECK (status IN ('draft','final','filed')),
  created_by  UUID,
  updated_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period)
);

CREATE TRIGGER trg_ewt_wp_headers_updated_at
  BEFORE UPDATE ON compliance_ewt_working_papers_headers
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Lines: individual EWT entries for the period
CREATE TABLE IF NOT EXISTS compliance_ewt_working_papers_lines (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  header_id      UUID         NOT NULL REFERENCES compliance_ewt_working_papers_headers(id) ON DELETE CASCADE,
  transaction_id UUID,
  reference      TEXT,
  amount         NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks        TEXT,
  created_by     UUID,
  updated_by     UUID,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_ewt_wp_lines_updated_at
  BEFORE UPDATE ON compliance_ewt_working_papers_lines
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Row-Level Security ────────────────────────────────────────────────────────
ALTER TABLE compliance_ewt_working_papers_headers ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_ewt_working_papers_lines   ENABLE ROW LEVEL SECURITY;

-- Headers: full access for authenticated users (company scoping enforced in app)
CREATE POLICY "read_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "insert_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "update_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR UPDATE TO authenticated USING (true);

CREATE POLICY "delete_ewt_wp_headers" ON compliance_ewt_working_papers_headers
  FOR DELETE TO authenticated USING (status = 'draft');

-- Lines: accessible while parent header is accessible
CREATE POLICY "read_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "insert_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "update_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR UPDATE TO authenticated USING (true);

CREATE POLICY "delete_ewt_wp_lines" ON compliance_ewt_working_papers_lines
  FOR DELETE TO authenticated USING (true);
