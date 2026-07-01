-- ══════════════════════════════════════════════════════════════════════════════
-- S16: WITHHOLDING TAX MODULE (Compliance)
-- BIR Forms 1601EQ (Quarterly EWT Return) + 1601FQ (Quarterly FWT Return) + 2306 (FWT Certificate)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1601EQ Working Papers: header + lines (manual schedule, quarter-based) ────
CREATE TABLE compliance_1601eq_working_papers_headers (
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

CREATE TABLE compliance_1601eq_working_papers_lines (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  header_id   UUID          NOT NULL REFERENCES compliance_1601eq_working_papers_headers(id) ON DELETE CASCADE,
  reference   TEXT,
  amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks     TEXT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── FWT Working Papers: header + lines (manual schedule, month-based) ─────────
CREATE TABLE compliance_fwt_working_papers_headers (
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

CREATE TABLE compliance_fwt_working_papers_lines (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  header_id   UUID          NOT NULL REFERENCES compliance_fwt_working_papers_headers(id) ON DELETE CASCADE,
  reference   TEXT,
  amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks     TEXT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── 1601FQ Working Papers: header + lines (manual schedule, quarter-based) ────
CREATE TABLE compliance_1601fq_working_papers_headers (
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

CREATE TABLE compliance_1601fq_working_papers_lines (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  header_id   UUID          NOT NULL REFERENCES compliance_1601fq_working_papers_headers(id) ON DELETE CASCADE,
  reference   TEXT,
  amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks     TEXT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- RLS + triggers for all three working-paper table pairs (identical shape)
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['compliance_1601eq_working_papers', 'compliance_fwt_working_papers', 'compliance_1601fq_working_papers']
  LOOP
    EXECUTE format('ALTER TABLE %I_headers ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "%1$s_h_read"   ON %1$s_headers FOR SELECT TO authenticated USING (is_company_member(company_id))', t);
    EXECUTE format('CREATE POLICY "%1$s_h_insert" ON %1$s_headers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id))', t);
    EXECUTE format('CREATE POLICY "%1$s_h_update" ON %1$s_headers FOR UPDATE TO authenticated USING (is_company_member(company_id))', t);

    EXECUTE format('ALTER TABLE %I_lines ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "%1$s_l_read"   ON %1$s_lines FOR SELECT TO authenticated USING (is_company_member((SELECT company_id FROM %1$s_headers WHERE id = header_id)))', t);
    EXECUTE format('CREATE POLICY "%1$s_l_insert" ON %1$s_lines FOR INSERT TO authenticated WITH CHECK (is_company_member((SELECT company_id FROM %1$s_headers WHERE id = header_id)))', t);
    EXECUTE format('CREATE POLICY "%1$s_l_update" ON %1$s_lines FOR UPDATE TO authenticated USING (is_company_member((SELECT company_id FROM %1$s_headers WHERE id = header_id)))', t);
    EXECUTE format('CREATE POLICY "%1$s_l_delete" ON %1$s_lines FOR DELETE TO authenticated USING (is_company_member((SELECT company_id FROM %1$s_headers WHERE id = header_id)))', t);

    EXECUTE format('CREATE TRIGGER trg_%1$s_h_updated_at BEFORE UPDATE ON %1$s_headers FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()', t);
  END LOOP;
END $$;

-- ── EWT Returns: computed 1601EQ (quarterly EWT remittance) ───────────────────
CREATE TABLE ewt_returns (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  period_year        INTEGER       NOT NULL,
  period_quarter     INTEGER       NOT NULL CHECK (period_quarter BETWEEN 1 AND 4),
  total_tax_base     NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_ewt_withheld NUMERIC(15,2) NOT NULL DEFAULT 0,
  remitted_prior     NUMERIC(15,2) NOT NULL DEFAULT 0,
  still_due          NUMERIC(15,2) NOT NULL DEFAULT 0,
  status             TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  filed_date         DATE,
  reference_no       TEXT,
  remarks            TEXT,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period_year, period_quarter)
);

-- ── FWT Returns: computed 1601FQ (quarterly FWT remittance) ───────────────────
CREATE TABLE fwt_returns (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  period_year        INTEGER       NOT NULL,
  period_quarter     INTEGER       NOT NULL CHECK (period_quarter BETWEEN 1 AND 4),
  total_tax_base     NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_fwt_withheld NUMERIC(15,2) NOT NULL DEFAULT 0,
  remitted_prior     NUMERIC(15,2) NOT NULL DEFAULT 0,
  still_due          NUMERIC(15,2) NOT NULL DEFAULT 0,
  status             TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  filed_date         DATE,
  reference_no       TEXT,
  remarks            TEXT,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period_year, period_quarter)
);

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['ewt_returns', 'fwt_returns']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "%1$s_read"   ON %1$s FOR SELECT TO authenticated USING (is_company_member(company_id))', t);
    EXECUTE format('CREATE POLICY "%1$s_insert" ON %1$s FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id))', t);
    EXECUTE format('CREATE POLICY "%1$s_update" ON %1$s FOR UPDATE TO authenticated USING (is_company_member(company_id))', t);
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$s FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()', t);
  END LOOP;
END $$;

-- ── Form 2306: FWT Certificates issued to banks on interest income ────────────
CREATE TABLE form_2306_issuances (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID          NOT NULL REFERENCES companies(id),
  bank_account_id       UUID          NOT NULL REFERENCES bank_accounts(id),
  period_year           INTEGER       NOT NULL,
  period_quarter        INTEGER       NOT NULL CHECK (period_quarter BETWEEN 1 AND 4),
  gross_interest_income NUMERIC(15,2) NOT NULL DEFAULT 0,
  fwt_rate              NUMERIC(5,2)  NOT NULL DEFAULT 20.00,
  fwt_withheld          NUMERIC(15,2) NOT NULL DEFAULT 0,
  certificate_number    TEXT,
  status                TEXT          NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','generated','sent','acknowledged')),
  date_generated        TIMESTAMPTZ,
  date_sent             TIMESTAMPTZ,
  date_acknowledged      TIMESTAMPTZ,
  remarks               TEXT,
  created_by            UUID,
  updated_by            UUID,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, bank_account_id, period_year, period_quarter)
);

ALTER TABLE form_2306_issuances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "f2306_read"   ON form_2306_issuances FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "f2306_insert" ON form_2306_issuances FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "f2306_update" ON form_2306_issuances FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_f2306_updated_at
  BEFORE UPDATE ON form_2306_issuances
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
