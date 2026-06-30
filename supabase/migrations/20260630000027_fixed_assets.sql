-- ══════════════════════════════════════════════════════════════════════════════
-- S11: FIXED ASSETS MODULE
-- PAS 16 (Property, Plant & Equipment) + PAS 36 (Impairment)
-- Depreciation methods: Straight-Line (SLM), Declining Balance (DDB),
--   Sum-of-Years-Digits (SYD), None (non-depreciable assets like land)
-- Full-month convention: depreciation starts in the month of acquisition.
-- All financial transactions post atomic journal entries.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Asset Categories ───────────────────────────────────────────────────────
-- Defines the default depreciation parameters and GL accounts per asset class.

CREATE TABLE IF NOT EXISTS fixed_asset_categories (
  id                              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                      UUID        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  category_code                   TEXT        NOT NULL,
  category_name                   TEXT        NOT NULL,
  depreciation_method             TEXT        NOT NULL DEFAULT 'straight_line'
                                    CHECK (depreciation_method IN ('straight_line','declining_balance','sum_of_years','none')),
  useful_life_months              INT         NOT NULL DEFAULT 60 CHECK (useful_life_months > 0),
  salvage_rate                    NUMERIC(6,4) NOT NULL DEFAULT 0
                                    CHECK (salvage_rate >= 0 AND salvage_rate < 1),
  gl_asset_account_id             UUID        REFERENCES chart_of_accounts(id),
  gl_accum_depr_account_id        UUID        REFERENCES chart_of_accounts(id),
  gl_depr_expense_account_id      UUID        REFERENCES chart_of_accounts(id),
  gl_gain_on_disposal_account_id  UUID        REFERENCES chart_of_accounts(id),
  gl_loss_on_disposal_account_id  UUID        REFERENCES chart_of_accounts(id),
  gl_impairment_loss_account_id   UUID        REFERENCES chart_of_accounts(id),
  is_active                       BOOLEAN     NOT NULL DEFAULT true,
  created_by                      UUID        REFERENCES auth.users(id),
  updated_by                      UUID        REFERENCES auth.users(id),
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, category_code)
);

ALTER TABLE fixed_asset_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fac_read"   ON fixed_asset_categories FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "fac_insert" ON fixed_asset_categories FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "fac_update" ON fixed_asset_categories FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_fac_updated_at
  BEFORE UPDATE ON fixed_asset_categories
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 2. Fixed Assets Register ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS fixed_assets (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  branch_id               UUID        REFERENCES branches(id),
  department_id           UUID        REFERENCES departments(id),
  asset_number            TEXT        NOT NULL,
  asset_name              TEXT        NOT NULL,
  description             TEXT,
  category_id             UUID        NOT NULL REFERENCES fixed_asset_categories(id),
  acquisition_date        DATE        NOT NULL,
  depreciation_start_date DATE        NOT NULL,
  acquisition_cost        NUMERIC(18,2) NOT NULL CHECK (acquisition_cost > 0),
  salvage_value           NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (salvage_value >= 0),
  useful_life_months      INT         NOT NULL CHECK (useful_life_months > 0),
  depreciation_method     TEXT        NOT NULL
                            CHECK (depreciation_method IN ('straight_line','declining_balance','sum_of_years','none')),
  serial_number           TEXT,
  location                TEXT,
  supplier_id             UUID        REFERENCES suppliers(id),
  acquisition_je_id       UUID        REFERENCES journal_entries(id),
  fiscal_period_id        UUID        REFERENCES fiscal_periods(id),
  status                  TEXT        NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','fully_depreciated','disposed','impaired','draft')),
  notes                   TEXT,
  disposed_at             DATE,
  created_by              UUID        REFERENCES auth.users(id),
  updated_by              UUID        REFERENCES auth.users(id),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, asset_number)
);

CREATE INDEX IF NOT EXISTS idx_fa_company      ON fixed_assets (company_id, acquisition_date DESC);
CREATE INDEX IF NOT EXISTS idx_fa_category     ON fixed_assets (category_id);
CREATE INDEX IF NOT EXISTS idx_fa_branch       ON fixed_assets (branch_id);
CREATE INDEX IF NOT EXISTS idx_fa_status       ON fixed_assets (company_id, status);

ALTER TABLE fixed_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fa_read"   ON fixed_assets FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "fa_insert" ON fixed_assets FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "fa_update" ON fixed_assets FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_fa_updated_at
  BEFORE UPDATE ON fixed_assets
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 3. Depreciation Entries ───────────────────────────────────────────────────
-- Auto-generated on asset registration, one row per month of useful life.

CREATE TABLE IF NOT EXISTS asset_depreciation_entries (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID        NOT NULL REFERENCES companies(id),
  asset_id              UUID        NOT NULL REFERENCES fixed_assets(id) ON DELETE CASCADE,
  period_number         INT         NOT NULL CHECK (period_number > 0),
  entry_date            DATE        NOT NULL,
  depreciation_amount   NUMERIC(18,2) NOT NULL CHECK (depreciation_amount >= 0),
  accumulated_depr_after NUMERIC(18,2) NOT NULL DEFAULT 0,
  net_book_value_after  NUMERIC(18,2) NOT NULL DEFAULT 0,
  status                TEXT        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','posted','skipped')),
  journal_entry_id      UUID        REFERENCES journal_entries(id),
  posted_at             TIMESTAMPTZ,
  posted_by             UUID        REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(asset_id, period_number)
);

CREATE INDEX IF NOT EXISTS idx_ade_asset   ON asset_depreciation_entries (asset_id, period_number);
CREATE INDEX IF NOT EXISTS idx_ade_company ON asset_depreciation_entries (company_id, entry_date, status);

ALTER TABLE asset_depreciation_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ade_read"   ON asset_depreciation_entries FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "ade_insert" ON asset_depreciation_entries FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "ade_update" ON asset_depreciation_entries FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- ── 4. Asset Disposals ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS asset_disposals (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID        NOT NULL REFERENCES companies(id),
  asset_id              UUID        NOT NULL REFERENCES fixed_assets(id),
  disposal_date         DATE        NOT NULL,
  disposal_type         TEXT        NOT NULL
                          CHECK (disposal_type IN ('sale','write_off','donation','trade_in')),
  proceeds_amount       NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (proceeds_amount >= 0),
  proceeds_account_id   UUID        REFERENCES chart_of_accounts(id),
  cost_at_disposal      NUMERIC(18,2) NOT NULL,
  accum_depr_at_disposal NUMERIC(18,2) NOT NULL DEFAULT 0,
  net_book_value        NUMERIC(18,2) NOT NULL,
  gain_loss_amount      NUMERIC(18,2) NOT NULL DEFAULT 0,
  journal_entry_id      UUID        REFERENCES journal_entries(id),
  fiscal_period_id      UUID        REFERENCES fiscal_periods(id),
  notes                 TEXT,
  created_by            UUID        REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ad_company ON asset_disposals (company_id, disposal_date DESC);
CREATE INDEX IF NOT EXISTS idx_ad_asset   ON asset_disposals (asset_id);

ALTER TABLE asset_disposals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ad_read"   ON asset_disposals FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "ad_insert" ON asset_disposals FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

-- ── 5. Asset Transfers ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS asset_transfers (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID        NOT NULL REFERENCES companies(id),
  asset_id            UUID        NOT NULL REFERENCES fixed_assets(id),
  transfer_date       DATE        NOT NULL,
  from_branch_id      UUID        REFERENCES branches(id),
  from_department_id  UUID        REFERENCES departments(id),
  to_branch_id        UUID        REFERENCES branches(id),
  to_department_id    UUID        REFERENCES departments(id),
  notes               TEXT,
  created_by          UUID        REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_at_company ON asset_transfers (company_id, transfer_date DESC);
CREATE INDEX IF NOT EXISTS idx_at_asset   ON asset_transfers (asset_id);

ALTER TABLE asset_transfers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "atf_read"   ON asset_transfers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "atf_insert" ON asset_transfers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

-- ── 6. Asset Impairments ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS asset_impairments (
  id                            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                    UUID        NOT NULL REFERENCES companies(id),
  asset_id                      UUID        NOT NULL REFERENCES fixed_assets(id),
  impairment_date               DATE        NOT NULL,
  carrying_amount_before        NUMERIC(18,2) NOT NULL,
  recoverable_amount            NUMERIC(18,2) NOT NULL DEFAULT 0,
  impairment_loss               NUMERIC(18,2) NOT NULL CHECK (impairment_loss > 0),
  gl_impairment_loss_account_id UUID        REFERENCES chart_of_accounts(id),
  gl_accum_impairment_account_id UUID       REFERENCES chart_of_accounts(id),
  journal_entry_id              UUID        REFERENCES journal_entries(id),
  fiscal_period_id              UUID        REFERENCES fiscal_periods(id),
  notes                         TEXT,
  created_by                    UUID        REFERENCES auth.users(id),
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_company ON asset_impairments (company_id, impairment_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_asset   ON asset_impairments (asset_id);

ALTER TABLE asset_impairments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aim_read"   ON asset_impairments FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "aim_insert" ON asset_impairments FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

-- ══════════════════════════════════════════════════════════════════════════════
-- FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Helper: compute depreciation schedule rows ────────────────────────────────
-- Returns a set of (period_number, entry_date, depr_amount, accum_after, nbv_after)

CREATE OR REPLACE FUNCTION fn_compute_depr_schedule(
  p_cost           NUMERIC,
  p_salvage        NUMERIC,
  p_months         INT,
  p_method         TEXT,
  p_start_date     DATE
)
RETURNS TABLE (
  period_number         INT,
  entry_date            DATE,
  depreciation_amount   NUMERIC,
  accumulated_depr_after NUMERIC,
  net_book_value_after  NUMERIC
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_depreciable    NUMERIC := p_cost - p_salvage;
  v_slm_monthly    NUMERIC;
  v_ddb_rate       NUMERIC;
  v_nbv            NUMERIC := p_cost;
  v_accum          NUMERIC := 0;
  v_depr           NUMERIC;
  v_entry_date     DATE;
  i                INT;
  -- SYD variables
  v_syd_sum        INT;
  v_remaining      INT;
BEGIN
  IF p_method = 'none' THEN RETURN; END IF;

  v_slm_monthly := ROUND(v_depreciable / p_months, 2);
  v_ddb_rate    := 2.0 / p_months;
  v_syd_sum     := p_months * (p_months + 1) / 2;

  FOR i IN 1..p_months LOOP
    -- Entry date = last day of the i-th month from start
    v_entry_date := (DATE_TRUNC('month', p_start_date) + ((i) * INTERVAL '1 month') - INTERVAL '1 day')::DATE;

    IF p_method = 'straight_line' THEN
      -- Last period gets remainder to avoid rounding accumulation error
      IF i = p_months THEN
        v_depr := v_nbv - p_salvage;
      ELSE
        v_depr := v_slm_monthly;
      END IF;

    ELSIF p_method = 'declining_balance' THEN
      v_depr := ROUND(v_nbv * v_ddb_rate, 2);
      -- Switch to SLM in final periods when SLM would give more
      IF p_months - i > 0 THEN
        DECLARE v_remaining_slm NUMERIC := ROUND((v_nbv - v_depr - p_salvage) / (p_months - i), 2);
        BEGIN
          IF v_remaining_slm > v_ddb_rate * (v_nbv - v_depr) THEN
            v_depr := ROUND((v_nbv - p_salvage) / (p_months - i + 1), 2);
          END IF;
        END;
      END IF;
      -- Do not depreciate below salvage
      IF v_nbv - v_depr < p_salvage THEN
        v_depr := v_nbv - p_salvage;
      END IF;

    ELSIF p_method = 'sum_of_years' THEN
      v_remaining := p_months - i + 1;
      v_depr := ROUND(v_depreciable * v_remaining / v_syd_sum, 2);
    END IF;

    v_depr  := GREATEST(v_depr, 0);
    v_accum := v_accum + v_depr;
    v_nbv   := v_nbv - v_depr;

    period_number          := i;
    entry_date             := v_entry_date;
    depreciation_amount    := v_depr;
    accumulated_depr_after := v_accum;
    net_book_value_after   := GREATEST(v_nbv, p_salvage);
    RETURN NEXT;
  END LOOP;
END;
$$;

-- ── fn_register_fixed_asset ───────────────────────────────────────────────────
-- Creates asset record, generates depreciation schedule, posts acquisition JE.

CREATE OR REPLACE FUNCTION fn_register_fixed_asset(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id   UUID := (p_data->>'company_id')::UUID;
  v_asset_id     UUID;
  v_je_id        UUID;
  v_cat          fixed_asset_categories%ROWTYPE;
  v_fp_id        UUID;
  v_asset_number TEXT;
  v_cost         NUMERIC := (p_data->>'acquisition_cost')::NUMERIC;
  v_salvage      NUMERIC := COALESCE((p_data->>'salvage_value')::NUMERIC, 0);
  v_months       INT     := (p_data->>'useful_life_months')::INT;
  v_method       TEXT    := p_data->>'depreciation_method';
  v_start_date   DATE    := (p_data->>'depreciation_start_date')::DATE;
  v_acq_date     DATE    := (p_data->>'acquisition_date')::DATE;
  v_branch_id    UUID    := (p_data->>'branch_id')::UUID;
  v_cat_id       UUID    := (p_data->>'category_id')::UUID;
  v_credit_acct  UUID    := (p_data->>'credit_account_id')::UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_cat_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset category not found'; END IF;
  IF v_cat.gl_asset_account_id IS NULL THEN RAISE EXCEPTION 'Asset category is missing GL asset account'; END IF;

  -- Get or generate asset number
  v_asset_number := COALESCE(NULLIF(p_data->>'asset_number',''), fn_next_document_number(v_company_id, 'FA'));

  -- Find open fiscal period for acquisition date
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= v_acq_date AND end_date >= v_acq_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found covering acquisition date %', v_acq_date;
  END IF;

  -- Post acquisition JE: DR Asset Account / CR Credit Account (cash/AP/bank)
  IF v_credit_acct IS NOT NULL THEN
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status, total_debit, total_credit,
      created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      fn_next_document_number(v_company_id, 'JE'),
      v_acq_date, v_fp_id,
      'FA Acquisition: ' || (p_data->>'asset_name'),
      'FA', 'posted', v_cost, v_cost,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES
      (v_je_id, v_company_id, 1, v_cat.gl_asset_account_id, 'Acquisition — ' || (p_data->>'asset_name'), v_cost, 0, auth.uid(), auth.uid()),
      (v_je_id, v_company_id, 2, v_credit_acct, 'Acquisition — ' || (p_data->>'asset_name'), 0, v_cost, auth.uid(), auth.uid());
  END IF;

  -- Insert asset record
  INSERT INTO fixed_assets (
    company_id, branch_id, department_id, asset_number, asset_name, description,
    category_id, acquisition_date, depreciation_start_date, acquisition_cost,
    salvage_value, useful_life_months, depreciation_method, serial_number,
    location, supplier_id, acquisition_je_id, fiscal_period_id, status,
    notes, created_by, updated_by
  ) VALUES (
    v_company_id,
    v_branch_id,
    (p_data->>'department_id')::UUID,
    v_asset_number,
    p_data->>'asset_name',
    p_data->>'description',
    v_cat_id,
    v_acq_date,
    v_start_date,
    v_cost,
    v_salvage,
    v_months,
    v_method,
    p_data->>'serial_number',
    p_data->>'location',
    (p_data->>'supplier_id')::UUID,
    v_je_id,
    v_fp_id,
    'active',
    p_data->>'notes',
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_asset_id;

  -- Generate depreciation schedule
  INSERT INTO asset_depreciation_entries (company_id, asset_id, period_number, entry_date, depreciation_amount, accumulated_depr_after, net_book_value_after, status)
  SELECT v_company_id, v_asset_id, s.period_number, s.entry_date, s.depreciation_amount, s.accumulated_depr_after, s.net_book_value_after, 'pending'
  FROM fn_compute_depr_schedule(v_cost, v_salvage, v_months, v_method, v_start_date) s;

  RETURN v_asset_id;
END;
$$;

-- ── fn_post_depreciation_entry ────────────────────────────────────────────────
-- Posts one depreciation period for an asset: DR Depr Expense / CR Accum Depr.

CREATE OR REPLACE FUNCTION fn_post_depreciation_entry(p_entry_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry  asset_depreciation_entries%ROWTYPE;
  v_asset  fixed_assets%ROWTYPE;
  v_cat    fixed_asset_categories%ROWTYPE;
  v_fp_id  UUID;
  v_je_id  UUID;
BEGIN
  SELECT * INTO v_entry FROM asset_depreciation_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Depreciation entry not found'; END IF;
  IF NOT is_company_member(v_entry.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_entry.status = 'posted' THEN RAISE EXCEPTION 'Entry already posted'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_entry.asset_id;
  SELECT * INTO v_cat   FROM fixed_asset_categories WHERE id = v_asset.category_id;

  IF v_cat.gl_depr_expense_account_id IS NULL THEN RAISE EXCEPTION 'Category missing Depreciation Expense account'; END IF;
  IF v_cat.gl_accum_depr_account_id IS NULL   THEN RAISE EXCEPTION 'Category missing Accumulated Depreciation account'; END IF;

  -- Find open fiscal period covering entry_date
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_entry.company_id AND start_date <= v_entry.entry_date AND end_date >= v_entry.entry_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found covering %', v_entry.entry_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_entry.company_id, v_asset.branch_id,
    fn_next_document_number(v_entry.company_id, 'JE'),
    v_entry.entry_date, v_fp_id,
    'Depreciation — ' || v_asset.asset_name || ' (Period ' || v_entry.period_number || ')',
    'FA_DEPR', v_entry.asset_id, 'posted',
    v_entry.depreciation_amount, v_entry.depreciation_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_entry.company_id, 1, v_cat.gl_depr_expense_account_id,
     'Depr — ' || v_asset.asset_name, v_entry.depreciation_amount, 0, auth.uid(), auth.uid()),
    (v_je_id, v_entry.company_id, 2, v_cat.gl_accum_depr_account_id,
     'Accum Depr — ' || v_asset.asset_name, 0, v_entry.depreciation_amount, auth.uid(), auth.uid());

  UPDATE asset_depreciation_entries
  SET status = 'posted', journal_entry_id = v_je_id, posted_at = NOW(), posted_by = auth.uid()
  WHERE id = p_entry_id;

  -- Auto-mark asset as fully depreciated if last entry
  IF v_entry.period_number = v_asset.useful_life_months THEN
    UPDATE fixed_assets SET status = 'fully_depreciated', updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_asset.id;
  END IF;

  RETURN v_je_id;
END;
$$;

-- ── fn_dispose_fixed_asset ────────────────────────────────────────────────────
-- Records disposal, posts JE: DR Accum Depr + DR Cash/proceeds / CR Asset Cost
-- Gain = proceeds > NBV → CR Gain on Disposal
-- Loss = proceeds < NBV → DR Loss on Disposal

CREATE OR REPLACE FUNCTION fn_dispose_fixed_asset(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id     UUID    := (p_data->>'company_id')::UUID;
  v_asset_id       UUID    := (p_data->>'asset_id')::UUID;
  v_disposal_date  DATE    := (p_data->>'disposal_date')::DATE;
  v_proceeds       NUMERIC := COALESCE((p_data->>'proceeds_amount')::NUMERIC, 0);
  v_asset          fixed_assets%ROWTYPE;
  v_cat            fixed_asset_categories%ROWTYPE;
  v_fp_id          UUID;
  v_je_id          UUID;
  v_disposal_id    UUID;
  v_accum_depr     NUMERIC;
  v_nbv            NUMERIC;
  v_gain_loss      NUMERIC;
  v_line           INT := 1;
  v_proceeds_acct  UUID := (p_data->>'proceeds_account_id')::UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_asset_id AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF v_asset.status = 'disposed' THEN RAISE EXCEPTION 'Asset already disposed'; END IF;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_asset.category_id;

  IF v_cat.gl_asset_account_id IS NULL       THEN RAISE EXCEPTION 'Category missing Asset account'; END IF;
  IF v_cat.gl_accum_depr_account_id IS NULL  THEN RAISE EXCEPTION 'Category missing Accumulated Depreciation account'; END IF;

  -- Compute accumulated depreciation from posted entries
  SELECT COALESCE(SUM(depreciation_amount), 0) INTO v_accum_depr
  FROM asset_depreciation_entries
  WHERE asset_id = v_asset_id AND status = 'posted';

  -- Add impairment losses
  SELECT v_accum_depr + COALESCE(SUM(impairment_loss), 0) INTO v_accum_depr
  FROM asset_impairments WHERE asset_id = v_asset_id;

  v_nbv       := v_asset.acquisition_cost - v_accum_depr;
  v_gain_loss := v_proceeds - v_nbv; -- positive = gain, negative = loss

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= v_disposal_date AND end_date >= v_disposal_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for disposal date %', v_disposal_date; END IF;

  -- Build disposal JE
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, 'JE'),
    v_disposal_date, v_fp_id,
    'FA Disposal: ' || v_asset.asset_name || ' (' || (p_data->>'disposal_type') || ')',
    'FA_DISP', 'posted',
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR Accumulated Depreciation
  IF v_accum_depr > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_accum_depr_account_id,
      'Accum Depr — ' || v_asset.asset_name, v_accum_depr, 0, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- DR Cash/Receivable (proceeds)
  IF v_proceeds > 0 AND v_proceeds_acct IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_proceeds_acct,
      'Proceeds — ' || v_asset.asset_name, v_proceeds, 0, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- DR Loss on Disposal (if loss)
  IF v_gain_loss < 0 AND v_cat.gl_loss_on_disposal_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_loss_on_disposal_account_id,
      'Loss on Disposal — ' || v_asset.asset_name, ABS(v_gain_loss), 0, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- CR Asset Cost
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_company_id, v_line, v_cat.gl_asset_account_id,
    'Asset Cost — ' || v_asset.asset_name, 0, v_asset.acquisition_cost, auth.uid(), auth.uid());
  v_line := v_line + 1;

  -- CR Gain on Disposal (if gain)
  IF v_gain_loss > 0 AND v_cat.gl_gain_on_disposal_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_gain_on_disposal_account_id,
      'Gain on Disposal — ' || v_asset.asset_name, 0, v_gain_loss, auth.uid(), auth.uid());
  END IF;

  -- Record disposal
  INSERT INTO asset_disposals (
    company_id, asset_id, disposal_date, disposal_type, proceeds_amount,
    proceeds_account_id, cost_at_disposal, accum_depr_at_disposal,
    net_book_value, gain_loss_amount, journal_entry_id, fiscal_period_id, notes, created_by
  ) VALUES (
    v_company_id, v_asset_id, v_disposal_date, p_data->>'disposal_type',
    v_proceeds, v_proceeds_acct, v_asset.acquisition_cost, v_accum_depr,
    v_nbv, v_gain_loss, v_je_id, v_fp_id, p_data->>'notes', auth.uid()
  ) RETURNING id INTO v_disposal_id;

  -- Update asset status
  UPDATE fixed_assets
  SET status = 'disposed', disposed_at = v_disposal_date, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_asset_id;

  -- Skip remaining pending depreciation entries
  UPDATE asset_depreciation_entries SET status = 'skipped'
  WHERE asset_id = v_asset_id AND status = 'pending';

  RETURN v_je_id;
END;
$$;

-- ── fn_transfer_fixed_asset ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_transfer_fixed_asset(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := (p_data->>'company_id')::UUID;
  v_asset_id   UUID := (p_data->>'asset_id')::UUID;
  v_asset      fixed_assets%ROWTYPE;
  v_xfer_id    UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_asset_id AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF v_asset.status NOT IN ('active','fully_depreciated') THEN
    RAISE EXCEPTION 'Asset must be active or fully depreciated to transfer';
  END IF;

  INSERT INTO asset_transfers (
    company_id, asset_id, transfer_date,
    from_branch_id, from_department_id, to_branch_id, to_department_id, notes, created_by
  ) VALUES (
    v_company_id, v_asset_id, (p_data->>'transfer_date')::DATE,
    v_asset.branch_id, v_asset.department_id,
    (p_data->>'to_branch_id')::UUID,
    (p_data->>'to_department_id')::UUID,
    p_data->>'notes', auth.uid()
  ) RETURNING id INTO v_xfer_id;

  UPDATE fixed_assets
  SET branch_id     = COALESCE((p_data->>'to_branch_id')::UUID, branch_id),
      department_id = COALESCE((p_data->>'to_department_id')::UUID, department_id),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_asset_id;

  RETURN v_xfer_id;
END;
$$;

-- ── fn_record_impairment ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_record_impairment(p_data JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id       UUID    := (p_data->>'company_id')::UUID;
  v_asset_id         UUID    := (p_data->>'asset_id')::UUID;
  v_imp_date         DATE    := (p_data->>'impairment_date')::DATE;
  v_recoverable      NUMERIC := COALESCE((p_data->>'recoverable_amount')::NUMERIC, 0);
  v_asset            fixed_assets%ROWTYPE;
  v_cat              fixed_asset_categories%ROWTYPE;
  v_carrying         NUMERIC;
  v_accum_depr       NUMERIC;
  v_loss             NUMERIC;
  v_fp_id            UUID;
  v_je_id            UUID;
  v_imp_loss_acct    UUID := (p_data->>'gl_impairment_loss_account_id')::UUID;
  v_accum_imp_acct   UUID := (p_data->>'gl_accum_impairment_account_id')::UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_asset_id AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF v_asset.status = 'disposed' THEN RAISE EXCEPTION 'Cannot impair a disposed asset'; END IF;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_asset.category_id;

  -- Use category accounts if not overridden
  v_imp_loss_acct  := COALESCE(v_imp_loss_acct,  v_cat.gl_impairment_loss_account_id);
  v_accum_imp_acct := COALESCE(v_accum_imp_acct, v_cat.gl_accum_depr_account_id);

  IF v_imp_loss_acct IS NULL  THEN RAISE EXCEPTION 'No Impairment Loss GL account specified'; END IF;
  IF v_accum_imp_acct IS NULL THEN RAISE EXCEPTION 'No Accumulated Impairment GL account specified'; END IF;

  -- Current carrying amount (cost - accumulated depr - prior impairments)
  SELECT COALESCE(SUM(depreciation_amount), 0) INTO v_accum_depr
  FROM asset_depreciation_entries WHERE asset_id = v_asset_id AND status = 'posted';

  SELECT v_accum_depr + COALESCE(SUM(impairment_loss), 0) INTO v_accum_depr
  FROM asset_impairments WHERE asset_id = v_asset_id;

  v_carrying := v_asset.acquisition_cost - v_accum_depr;

  IF v_recoverable >= v_carrying THEN
    RAISE EXCEPTION 'Recoverable amount (%) must be less than carrying amount (%) for impairment to exist', v_recoverable, v_carrying;
  END IF;

  v_loss := v_carrying - v_recoverable;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= v_imp_date AND end_date >= v_imp_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for impairment date %', v_imp_date; END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, 'JE'),
    v_imp_date, v_fp_id,
    'Impairment Loss — ' || v_asset.asset_name,
    'FA_IMP', 'posted', v_loss, v_loss,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_company_id, 1, v_imp_loss_acct,  'Impairment Loss — ' || v_asset.asset_name, v_loss, 0, auth.uid(), auth.uid()),
    (v_je_id, v_company_id, 2, v_accum_imp_acct, 'Accum Impairment — ' || v_asset.asset_name, 0, v_loss, auth.uid(), auth.uid());

  INSERT INTO asset_impairments (
    company_id, asset_id, impairment_date,
    carrying_amount_before, recoverable_amount, impairment_loss,
    gl_impairment_loss_account_id, gl_accum_impairment_account_id,
    journal_entry_id, fiscal_period_id, notes, created_by
  ) VALUES (
    v_company_id, v_asset_id, v_imp_date,
    v_carrying, v_recoverable, v_loss,
    v_imp_loss_acct, v_accum_imp_acct,
    v_je_id, v_fp_id, p_data->>'notes', auth.uid()
  );

  UPDATE fixed_assets SET status = 'impaired', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_asset_id;

  RETURN v_je_id;
END;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION fn_compute_depr_schedule(NUMERIC, NUMERIC, INT, TEXT, DATE)   TO authenticated;
GRANT EXECUTE ON FUNCTION fn_register_fixed_asset(JSONB)                                TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_depreciation_entry(UUID)                              TO authenticated;
GRANT EXECUTE ON FUNCTION fn_dispose_fixed_asset(JSONB)                                 TO authenticated;
GRANT EXECUTE ON FUNCTION fn_transfer_fixed_asset(JSONB)                                TO authenticated;
GRANT EXECUTE ON FUNCTION fn_record_impairment(JSONB)                                   TO authenticated;
