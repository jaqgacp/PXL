-- ============================================================
-- Sprint 2 Tax & Compliance: New tables and functions
-- ============================================================

-- ── FWT Codes: Per-company Final Withholding Tax ──────────────
CREATE TABLE fwt_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  tax_code_id UUID NOT NULL REFERENCES tax_codes(id),
  fwt_code TEXT NOT NULL,
  description TEXT NOT NULL,
  atc_id UUID NOT NULL REFERENCES atc_codes(id),
  rate NUMERIC(5,2) NOT NULL,
  form_type TEXT NOT NULL DEFAULT '1601FQ' CHECK (form_type IN ('1601FQ')),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, fwt_code)
);

-- ── Percentage Tax Codes: Per-company ─────────────────────────
CREATE TABLE percentage_tax_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  tax_code_id UUID NOT NULL REFERENCES tax_codes(id),
  pt_code TEXT NOT NULL,
  description TEXT NOT NULL,
  atc_id UUID NOT NULL REFERENCES atc_codes(id),
  rate NUMERIC(5,2) NOT NULL,
  form_type TEXT NOT NULL DEFAULT '2551Q' CHECK (form_type IN ('2551Q')),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, pt_code)
);

-- ── Compliance Profiles: One per company ──────────────────────
CREATE TABLE compliance_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) UNIQUE,
  -- General / eFPS
  efps_enrolled BOOLEAN NOT NULL DEFAULT false,
  efps_group TEXT CHECK (efps_group IN ('A','B','C','D','E')),
  -- VAT
  vat_registered BOOLEAN NOT NULL DEFAULT false,
  vat_effective_date DATE,
  vat_filing_frequency TEXT CHECK (vat_filing_frequency IN ('monthly','quarterly')),
  vat_threshold_monitoring BOOLEAN DEFAULT false,
  -- Percentage Tax
  percentage_tax_registered BOOLEAN NOT NULL DEFAULT false,
  percentage_tax_rate NUMERIC(5,2),
  pt_effective_date DATE,
  pt_filing_frequency TEXT CHECK (pt_filing_frequency IN ('quarterly')),
  -- EWT
  ewt_registered BOOLEAN NOT NULL DEFAULT false,
  is_twa BOOLEAN NOT NULL DEFAULT false,
  twa_effective_date DATE,
  twa_auto_ewt_enabled BOOLEAN NOT NULL DEFAULT false,
  files_0619e BOOLEAN NOT NULL DEFAULT false,
  qap_required BOOLEAN DEFAULT false,
  requires_1604e BOOLEAN DEFAULT false,
  -- FWT
  fwt_registered BOOLEAN NOT NULL DEFAULT false,
  files_0619f BOOLEAN NOT NULL DEFAULT false,
  -- Income Tax
  income_tax_regime TEXT NOT NULL DEFAULT 'rcit'
    CHECK (income_tax_regime IN ('rcit','mcit','preferential','osd','itemized')),
  corporate_tax_rate NUMERIC(5,2) NOT NULL DEFAULT 25.00,
  mcit_applicable BOOLEAN DEFAULT false,
  nolco_applicable BOOLEAN DEFAULT false,
  -- System Compliance
  sawt_required BOOLEAN DEFAULT false,
  slsp_required BOOLEAN DEFAULT false,
  relief_required BOOLEAN DEFAULT false,
  dat_file_required BOOLEAN DEFAULT false,
  -- Metadata
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Reference: BIR Forms (pre-seeded) ─────────────────────────
CREATE TABLE ref_compliance_forms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  form_code TEXT NOT NULL UNIQUE,
  form_name TEXT NOT NULL,
  compliance_type TEXT NOT NULL
    CHECK (compliance_type IN ('vat','ewt','fwt','income_tax','alphalist','information','lgu')),
  statutory_deadline_rule TEXT NOT NULL,
  efps_eligible BOOLEAN DEFAULT true,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO ref_compliance_forms (form_code, form_name, compliance_type, statutory_deadline_rule) VALUES
  ('2550M',        'Monthly VAT Declaration',                       'vat',         '20th of following month'),
  ('2550Q',        'Quarterly VAT Return',                          'vat',         '25th of month following the quarter'),
  ('0619-E',       'Monthly EWT Remittance',                        'ewt',         '10th of following month'),
  ('1601EQ',       'Quarterly EWT Return',                          'ewt',         'Last day of month following the quarter'),
  ('QAP',          'Quarterly Alphalist of Payees',                 'alphalist',   'Attached to 1601EQ filing'),
  ('1604-E',       'Annual Information Return of EWT',              'alphalist',   'March 1 of following year'),
  ('0619-F',       'Monthly FWT Remittance',                        'fwt',         '10th of following month'),
  ('1601FQ',       'Quarterly FWT Return',                          'fwt',         'Last day of month following the quarter'),
  ('1702Q',        'Quarterly Income Tax Return',                   'income_tax',  '60th day after close of taxable quarter'),
  ('1702',         'Annual Income Tax Return',                      'income_tax',  'April 15 of following year'),
  ('SLSP',         'Summary List of Sales and Purchases',           'information', '25th of month following the quarter'),
  ('RELIEF',       'Reconciliation of Listings for Enforcement',    'information', '25th of month following the quarter'),
  ('SAWT',         'Summary Alphalist of Withholding Taxes',        'alphalist',   'Attached to quarterly/annual ITR'),
  ('MAYOR_PERMIT', 'Mayor''s Permit Renewal',                       'lgu',         'January 20 of each year');

-- ── Tax Calendar Events ───────────────────────────────────────
CREATE TABLE tax_calendar_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  compliance_form_id UUID NOT NULL REFERENCES ref_compliance_forms(id),
  coverage_period_start DATE NOT NULL,
  coverage_period_end DATE NOT NULL,
  statutory_deadline DATE NOT NULL,
  efps_adjusted_deadline DATE,
  effective_deadline DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','filed','late')),
  date_filed DATE,
  efps_reference_no TEXT,
  assigned_to_user_id UUID,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, compliance_form_id, coverage_period_start)
);

CREATE INDEX idx_tax_calendar_company_deadline ON tax_calendar_events (company_id, effective_deadline);
CREATE INDEX idx_tax_calendar_company_status   ON tax_calendar_events (company_id, status);
CREATE INDEX idx_tax_calendar_form             ON tax_calendar_events (company_id, compliance_form_id);

-- ── BIR Forms ─────────────────────────────────────────────────
CREATE TABLE bir_forms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  form_number TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  frequency TEXT NOT NULL CHECK (frequency IN ('monthly','quarterly','annual')),
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE bir_form_mappings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  form_id UUID NOT NULL REFERENCES bir_forms(id),
  line_identifier TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('gl_account','tax_code','calc')),
  source_id UUID,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── fn_generate_tax_calendar ──────────────────────────────────
CREATE OR REPLACE FUNCTION fn_generate_tax_calendar(
  p_company_id UUID,
  p_fiscal_year INTEGER
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_profile compliance_profiles%ROWTYPE;
  v_efps_days INTEGER;
  v_month INTEGER;
  v_quarter INTEGER;
  v_period_start DATE;
  v_period_end DATE;
  v_statutory DATE;
  v_efps_adj DATE;
  v_effective DATE;
  v_form_id UUID;
BEGIN
  SELECT * INTO v_profile FROM compliance_profiles WHERE company_id = p_company_id AND is_active = true;
  IF NOT FOUND THEN RETURN; END IF;

  v_efps_days := CASE
    WHEN NOT v_profile.efps_enrolled THEN 0
    WHEN v_profile.efps_group = 'A' THEN 5
    WHEN v_profile.efps_group = 'B' THEN 4
    WHEN v_profile.efps_group = 'C' THEN 3
    WHEN v_profile.efps_group = 'D' THEN 2
    WHEN v_profile.efps_group = 'E' THEN 1
    ELSE 0
  END;

  -- Delete pending events for this year only (preserve filed events)
  DELETE FROM tax_calendar_events
  WHERE company_id = p_company_id
    AND EXTRACT(YEAR FROM coverage_period_start)::INTEGER = p_fiscal_year
    AND status = 'pending';

  -- Helper: upsert a single event
  -- (inline via direct inserts below)

  -- 2550M: Monthly VAT (months 1–12)
  IF v_profile.vat_registered AND v_profile.vat_filing_frequency = 'monthly' THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '2550M';
    FOR v_month IN 1..12 LOOP
      v_period_start := make_date(p_fiscal_year, v_month, 1);
      v_period_end   := (v_period_start + INTERVAL '1 month - 1 day')::DATE;
      v_statutory    := make_date(p_fiscal_year + CASE WHEN v_month = 12 THEN 1 ELSE 0 END,
                                  CASE WHEN v_month = 12 THEN 1 ELSE v_month + 1 END, 20);
      v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
      v_effective    := COALESCE(v_efps_adj, v_statutory);
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- 2550Q: Quarterly VAT (4 quarters)
  IF v_profile.vat_registered THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '2550Q';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (v_period_end + INTERVAL '25 days')::DATE;
      v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
      v_effective    := COALESCE(v_efps_adj, v_statutory);
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- 0619-E: Months 1 & 2 of each quarter (EWT monthly remittance)
  IF v_profile.ewt_registered AND v_profile.files_0619e THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '0619-E';
    FOR v_quarter IN 1..4 LOOP
      FOR v_month IN 0..1 LOOP
        v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1 + v_month, 1);
        v_period_end   := (v_period_start + INTERVAL '1 month - 1 day')::DATE;
        v_statutory    := (v_period_end + INTERVAL '10 days')::DATE;
        v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
        v_effective    := COALESCE(v_efps_adj, v_statutory);
        INSERT INTO tax_calendar_events
          (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
           statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
        VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
        ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
      END LOOP;
    END LOOP;
  END IF;

  -- 1601EQ: Quarterly EWT Return
  IF v_profile.ewt_registered THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '1601EQ';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (date_trunc('month', v_period_end) + INTERVAL '1 month' + INTERVAL '1 month - 1 day')::DATE;
      v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
      v_effective    := COALESCE(v_efps_adj, v_statutory);
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- QAP: Same periods as 1601EQ
  IF v_profile.ewt_registered AND v_profile.qap_required THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = 'QAP';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (date_trunc('month', v_period_end) + INTERVAL '1 month' + INTERVAL '1 month - 1 day')::DATE;
      v_efps_adj     := NULL;
      v_effective    := v_statutory;
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- 1604-E: Annual alphalist
  IF v_profile.ewt_registered AND v_profile.requires_1604e THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '1604-E';
    v_period_start := make_date(p_fiscal_year, 1, 1);
    v_period_end   := make_date(p_fiscal_year, 12, 31);
    v_statutory    := make_date(p_fiscal_year + 1, 3, 1);
    v_effective    := v_statutory;
    INSERT INTO tax_calendar_events
      (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
       statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
    VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, NULL, v_effective, 'pending')
    ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
  END IF;

  -- 0619-F: Monthly FWT (months 1 & 2 of each quarter)
  IF v_profile.fwt_registered AND v_profile.files_0619f THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '0619-F';
    FOR v_quarter IN 1..4 LOOP
      FOR v_month IN 0..1 LOOP
        v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1 + v_month, 1);
        v_period_end   := (v_period_start + INTERVAL '1 month - 1 day')::DATE;
        v_statutory    := (v_period_end + INTERVAL '10 days')::DATE;
        v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
        v_effective    := COALESCE(v_efps_adj, v_statutory);
        INSERT INTO tax_calendar_events
          (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
           statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
        VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
        ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
      END LOOP;
    END LOOP;
  END IF;

  -- 1601FQ: Quarterly FWT
  IF v_profile.fwt_registered THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '1601FQ';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (date_trunc('month', v_period_end) + INTERVAL '1 month' + INTERVAL '1 month - 1 day')::DATE;
      v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
      v_effective    := COALESCE(v_efps_adj, v_statutory);
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- 1702Q: Quarterly ITR (Q1, Q2, Q3 only)
  SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '1702Q';
  FOR v_quarter IN 1..3 LOOP
    v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
    v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
    v_statutory    := (v_period_end + INTERVAL '60 days')::DATE;
    v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
    v_effective    := COALESCE(v_efps_adj, v_statutory);
    INSERT INTO tax_calendar_events
      (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
       statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
    VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
    ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
  END LOOP;

  -- 1702: Annual ITR
  SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = '1702';
  v_period_start := make_date(p_fiscal_year, 1, 1);
  v_period_end   := make_date(p_fiscal_year, 12, 31);
  v_statutory    := make_date(p_fiscal_year + 1, 4, 15);
  v_efps_adj     := CASE WHEN v_efps_days > 0 THEN v_statutory + (v_efps_days || ' days')::INTERVAL ELSE NULL END;
  v_effective    := COALESCE(v_efps_adj, v_statutory);
  INSERT INTO tax_calendar_events
    (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
     statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
  VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, v_efps_adj, v_effective, 'pending')
  ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;

  -- SLSP
  IF v_profile.slsp_required THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = 'SLSP';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (v_period_end + INTERVAL '25 days')::DATE;
      v_effective    := v_statutory;
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, NULL, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- RELIEF
  IF v_profile.relief_required THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = 'RELIEF';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (v_period_end + INTERVAL '25 days')::DATE;
      v_effective    := v_statutory;
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, NULL, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- SAWT
  IF v_profile.sawt_required THEN
    SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = 'SAWT';
    FOR v_quarter IN 1..4 LOOP
      v_period_start := make_date(p_fiscal_year, (v_quarter - 1) * 3 + 1, 1);
      v_period_end   := (v_period_start + INTERVAL '3 months - 1 day')::DATE;
      v_statutory    := (date_trunc('month', v_period_end) + INTERVAL '1 month' + INTERVAL '1 month - 1 day')::DATE;
      v_effective    := v_statutory;
      INSERT INTO tax_calendar_events
        (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
         statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
      VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, NULL, v_effective, 'pending')
      ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;
    END LOOP;
  END IF;

  -- Mayor's Permit (January 20)
  SELECT id INTO v_form_id FROM ref_compliance_forms WHERE form_code = 'MAYOR_PERMIT';
  v_period_start := make_date(p_fiscal_year, 1, 1);
  v_period_end   := make_date(p_fiscal_year, 1, 31);
  v_statutory    := make_date(p_fiscal_year, 1, 20);
  v_effective    := v_statutory;
  INSERT INTO tax_calendar_events
    (company_id, compliance_form_id, coverage_period_start, coverage_period_end,
     statutory_deadline, efps_adjusted_deadline, effective_deadline, status)
  VALUES (p_company_id, v_form_id, v_period_start, v_period_end, v_statutory, NULL, v_effective, 'pending')
  ON CONFLICT (company_id, compliance_form_id, coverage_period_start) DO NOTHING;

END;
$$;

-- ── Trigger wrapper for compliance_profiles changes ───────────
CREATE OR REPLACE FUNCTION fn_generate_tax_calendar_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM fn_generate_tax_calendar(NEW.company_id, EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER);
  PERFORM fn_generate_tax_calendar(NEW.company_id, EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER + 1);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_generate_calendar_on_profile_change
  AFTER INSERT OR UPDATE ON compliance_profiles
  FOR EACH ROW
  EXECUTE FUNCTION fn_generate_tax_calendar_trigger();

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE fwt_codes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE percentage_tax_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_compliance_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_calendar_events  ENABLE ROW LEVEL SECURITY;
ALTER TABLE bir_forms            ENABLE ROW LEVEL SECURITY;
ALTER TABLE bir_form_mappings    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_all_fwt_codes"            ON fwt_codes            FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_pt_codes"             ON percentage_tax_codes FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_compliance_profiles"  ON compliance_profiles  FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_read_ref_forms"           ON ref_compliance_forms FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_read_tax_calendar"        ON tax_calendar_events  FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_update_pending_calendar"  ON tax_calendar_events  FOR UPDATE TO authenticated USING (status = 'pending');
CREATE POLICY "auth_insert_tax_calendar"      ON tax_calendar_events  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "auth_all_bir_forms"            ON bir_forms            FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_all_bir_form_mappings"    ON bir_form_mappings    FOR ALL    TO authenticated USING (true);

-- ── updated_at triggers ───────────────────────────────────────
CREATE TRIGGER fwt_codes_updated_at            BEFORE UPDATE ON fwt_codes            FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER pt_codes_updated_at             BEFORE UPDATE ON percentage_tax_codes FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER compliance_profiles_updated_at  BEFORE UPDATE ON compliance_profiles  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tax_calendar_events_updated_at  BEFORE UPDATE ON tax_calendar_events  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER bir_forms_updated_at            BEFORE UPDATE ON bir_forms            FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER bir_form_mappings_updated_at    BEFORE UPDATE ON bir_form_mappings    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
