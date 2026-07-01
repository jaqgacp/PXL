-- ══════════════════════════════════════════════════════════════════════════════
-- S17: INCOME TAX MODULE (Compliance)
-- BIR Forms 1701Q/1701 (Individual) + 1702Q/1702RT (Corporate) + MCIT + NOLCO
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Income Tax Computations: Taxable Income (itemized) + OSD, quarterly/annual ─
CREATE TABLE income_tax_computations (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID          NOT NULL REFERENCES companies(id),
  period_type           TEXT          NOT NULL CHECK (period_type IN ('quarterly','annual')),
  period_year           INTEGER       NOT NULL,
  period_quarter        INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  deduction_method       TEXT          NOT NULL CHECK (deduction_method IN ('itemized','osd')),
  gross_income          NUMERIC(15,2) NOT NULL DEFAULT 0,
  allowable_deductions  NUMERIC(15,2) NOT NULL DEFAULT 0,
  taxable_income        NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_rate              NUMERIC(5,2)  NOT NULL DEFAULT 25.00,
  tax_due                NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  remarks               TEXT,
  created_by            UUID,
  updated_by            UUID,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (
    (period_type = 'quarterly' AND period_quarter IS NOT NULL) OR
    (period_type = 'annual' AND period_quarter IS NULL)
  ),
  UNIQUE (company_id, deduction_method, period_type, period_year, period_quarter)
);

-- ── Book-to-Tax Reconciliation ─────────────────────────────────────────────────
CREATE TABLE book_tax_reconciliation (
  id                      UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID          NOT NULL REFERENCES companies(id),
  period_type             TEXT          NOT NULL CHECK (period_type IN ('quarterly','annual')),
  period_year             INTEGER       NOT NULL,
  period_quarter          INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  book_income             NUMERIC(15,2) NOT NULL DEFAULT 0,
  addback_nondeductible   NUMERIC(15,2) NOT NULL DEFAULT 0,
  deduct_nontaxable       NUMERIC(15,2) NOT NULL DEFAULT 0,
  taxable_income          NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                  TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  remarks                 TEXT,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (
    (period_type = 'quarterly' AND period_quarter IS NOT NULL) OR
    (period_type = 'annual' AND period_quarter IS NULL)
  ),
  UNIQUE (company_id, period_type, period_year, period_quarter)
);

-- ── NOLCO Schedule: Net Operating Loss Carry-Over (3-year expiry) ─────────────
CREATE TABLE nolco_schedule (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID          NOT NULL REFERENCES companies(id),
  year_incurred     INTEGER       NOT NULL,
  nolco_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  applied_year1     NUMERIC(15,2) NOT NULL DEFAULT 0,
  applied_year2     NUMERIC(15,2) NOT NULL DEFAULT 0,
  applied_year3     NUMERIC(15,2) NOT NULL DEFAULT 0,
  expiry_year       INTEGER       NOT NULL,
  remarks           TEXT,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, year_incurred)
);

-- ── Tax Credits Schedule: CWT/2307, prior-year excess, foreign, other ─────────
CREATE TABLE tax_credits_schedule (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID          NOT NULL REFERENCES companies(id),
  period_year       INTEGER       NOT NULL,
  period_quarter    INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  credit_type       TEXT          NOT NULL CHECK (credit_type IN ('cwt_2307','prior_year_excess','foreign_tax_credit','other')),
  description       TEXT,
  amount            NUMERIC(15,2) NOT NULL DEFAULT 0,
  applied_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks           TEXT,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ── MCIT Computations: Minimum Corporate Income Tax (2% of Gross Income) ──────
CREATE TABLE mcit_computations (
  id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                UUID          NOT NULL REFERENCES companies(id),
  period_year               INTEGER       NOT NULL,
  gross_income              NUMERIC(15,2) NOT NULL DEFAULT 0,
  mcit_rate                 NUMERIC(5,2)  NOT NULL DEFAULT 2.00,
  mcit_due                  NUMERIC(15,2) NOT NULL DEFAULT 0,
  rcit_due                  NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_due_higher             NUMERIC(15,2) NOT NULL DEFAULT 0,
  excess_mcit_carryforward  NUMERIC(15,2) NOT NULL DEFAULT 0,
  status                    TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  remarks                   TEXT,
  created_by                UUID,
  updated_by                UUID,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, period_year)
);

-- ── ITR Filings: 1701Q / 1701 (individual) + 1702Q / 1702RT (corporate) ───────
CREATE TABLE itr_filings (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID          NOT NULL REFERENCES companies(id),
  form_type         TEXT          NOT NULL CHECK (form_type IN ('1701Q','1701','1702Q','1702RT')),
  period_year       INTEGER       NOT NULL,
  period_quarter    INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  gross_income      NUMERIC(15,2) NOT NULL DEFAULT 0,
  taxable_income    NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_due            NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_credits       NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_payable       NUMERIC(15,2) NOT NULL DEFAULT 0,
  status            TEXT          NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed')),
  filed_date        DATE,
  reference_no      TEXT,
  remarks           TEXT,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (
    (form_type IN ('1701Q','1702Q') AND period_quarter IS NOT NULL) OR
    (form_type IN ('1701','1702RT') AND period_quarter IS NULL)
  ),
  UNIQUE (company_id, form_type, period_year, period_quarter)
);

-- ── RLS + updated_at triggers for all seven tables (identical shape) ──────────
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['income_tax_computations', 'book_tax_reconciliation', 'nolco_schedule', 'tax_credits_schedule', 'mcit_computations', 'itr_filings']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "%1$s_read"   ON %1$s FOR SELECT TO authenticated USING (is_company_member(company_id))', t);
    EXECUTE format('CREATE POLICY "%1$s_insert" ON %1$s FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id))', t);
    EXECUTE format('CREATE POLICY "%1$s_update" ON %1$s FOR UPDATE TO authenticated USING (is_company_member(company_id))', t);
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$s FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()', t);
  END LOOP;
END $$;
