-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 026: Amortization Schedules & Revenue Recognition Schedules
-- Each schedule auto-generates monthly entries; posting entries creates JEs.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Amortization Schedules ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS amortization_schedules (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID          NOT NULL REFERENCES companies(id),
  branch_id           UUID          REFERENCES branches(id),
  schedule_name       TEXT          NOT NULL,
  description         TEXT,
  asset_account_id    UUID          NOT NULL REFERENCES chart_of_accounts(id),
  expense_account_id  UUID          NOT NULL REFERENCES chart_of_accounts(id),
  total_amount        NUMERIC(15,2) NOT NULL CHECK (total_amount > 0),
  start_date          DATE          NOT NULL,
  total_periods       INT           NOT NULL CHECK (total_periods BETWEEN 1 AND 360),
  posted_periods      INT           NOT NULL DEFAULT 0,
  status              TEXT          NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','completed','cancelled')),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by          UUID,
  updated_by          UUID,
  UNIQUE (company_id, schedule_name)
);

CREATE TABLE IF NOT EXISTS amortization_entries (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id   UUID          NOT NULL REFERENCES amortization_schedules(id) ON DELETE CASCADE,
  company_id    UUID          NOT NULL REFERENCES companies(id),
  period_number INT           NOT NULL,
  entry_date    DATE          NOT NULL,
  amount        NUMERIC(15,2) NOT NULL,
  je_id         UUID          REFERENCES journal_entries(id),
  status        TEXT          NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','posted','skipped')),
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (schedule_id, period_number)
);

-- ── Revenue Recognition Schedules ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS revenue_recognition_schedules (
  id                           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                   UUID          NOT NULL REFERENCES companies(id),
  branch_id                    UUID          REFERENCES branches(id),
  schedule_name                TEXT          NOT NULL,
  description                  TEXT,
  deferred_revenue_account_id  UUID          NOT NULL REFERENCES chart_of_accounts(id),
  revenue_account_id           UUID          NOT NULL REFERENCES chart_of_accounts(id),
  total_amount                 NUMERIC(15,2) NOT NULL CHECK (total_amount > 0),
  start_date                   DATE          NOT NULL,
  total_periods                INT           NOT NULL CHECK (total_periods BETWEEN 1 AND 360),
  posted_periods               INT           NOT NULL DEFAULT 0,
  status                       TEXT          NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active','completed','cancelled')),
  created_at                   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by                   UUID,
  updated_by                   UUID,
  UNIQUE (company_id, schedule_name)
);

CREATE TABLE IF NOT EXISTS revenue_recognition_entries (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id   UUID          NOT NULL REFERENCES revenue_recognition_schedules(id) ON DELETE CASCADE,
  company_id    UUID          NOT NULL REFERENCES companies(id),
  period_number INT           NOT NULL,
  entry_date    DATE          NOT NULL,
  amount        NUMERIC(15,2) NOT NULL,
  je_id         UUID          REFERENCES journal_entries(id),
  status        TEXT          NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','posted','skipped')),
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (schedule_id, period_number)
);

-- ── Indexes ────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_amort_sched_company   ON amortization_schedules(company_id);
CREATE INDEX IF NOT EXISTS idx_amort_entries_sched   ON amortization_entries(schedule_id);
CREATE INDEX IF NOT EXISTS idx_amort_entries_company ON amortization_entries(company_id);
CREATE INDEX IF NOT EXISTS idx_rr_sched_company      ON revenue_recognition_schedules(company_id);
CREATE INDEX IF NOT EXISTS idx_rr_entries_sched      ON revenue_recognition_entries(schedule_id);
CREATE INDEX IF NOT EXISTS idx_rr_entries_company    ON revenue_recognition_entries(company_id);

-- ── RLS ────────────────────────────────────────────────────────────────────────
ALTER TABLE amortization_schedules        ENABLE ROW LEVEL SECURITY;
ALTER TABLE amortization_entries          ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_recognition_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_recognition_entries   ENABLE ROW LEVEL SECURITY;

CREATE POLICY "amort_sched_r"   ON amortization_schedules FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "amort_sched_i"   ON amortization_schedules FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "amort_sched_u"   ON amortization_schedules FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "amort_entry_r"   ON amortization_entries FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "amort_entry_i"   ON amortization_entries FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "amort_entry_u"   ON amortization_entries FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "rr_sched_r"      ON revenue_recognition_schedules FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "rr_sched_i"      ON revenue_recognition_schedules FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "rr_sched_u"      ON revenue_recognition_schedules FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "rr_entry_r"      ON revenue_recognition_entries FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "rr_entry_i"      ON revenue_recognition_entries FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "rr_entry_u"      ON revenue_recognition_entries FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- ── Updated-at triggers ────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_amort_sched_updated_at ON amortization_schedules;
CREATE TRIGGER trg_amort_sched_updated_at
  BEFORE UPDATE ON amortization_schedules FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_rr_sched_updated_at ON revenue_recognition_schedules;
CREATE TRIGGER trg_rr_sched_updated_at
  BEFORE UPDATE ON revenue_recognition_schedules FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── fn_create_amortization_schedule ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_create_amortization_schedule(
  p_company_id         UUID,
  p_branch_id          UUID,
  p_schedule_name      TEXT,
  p_description        TEXT,
  p_asset_account_id   UUID,
  p_expense_account_id UUID,
  p_total_amount       NUMERIC,
  p_start_date         DATE,
  p_total_periods      INT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id            UUID;
  v_period_amount NUMERIC(15,2);
  v_last_amount   NUMERIC(15,2);
  i               INT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  v_period_amount := ROUND(p_total_amount / p_total_periods, 2);
  v_last_amount   := p_total_amount - (v_period_amount * (p_total_periods - 1));

  INSERT INTO amortization_schedules (
    company_id, branch_id, schedule_name, description,
    asset_account_id, expense_account_id, total_amount, start_date, total_periods,
    created_by, updated_by
  ) VALUES (
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID, p_schedule_name, NULLIF(p_description, ''),
    p_asset_account_id, p_expense_account_id, p_total_amount, p_start_date, p_total_periods,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_id;

  FOR i IN 1..p_total_periods LOOP
    INSERT INTO amortization_entries (schedule_id, company_id, period_number, entry_date, amount)
    VALUES (
      v_id, p_company_id, i,
      (p_start_date + ((i - 1) * INTERVAL '1 month'))::DATE,
      CASE WHEN i = p_total_periods THEN v_last_amount ELSE v_period_amount END
    );
  END LOOP;

  RETURN v_id;
END;
$$;

-- ── fn_post_amortization_entry ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_amortization_entry(p_entry_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry  amortization_entries%ROWTYPE;
  v_sched  amortization_schedules%ROWTYPE;
  v_fp_id  UUID;
  v_je_id  UUID;
  v_je_num TEXT;
  v_seq    INT;
BEGIN
  SELECT * INTO v_entry FROM amortization_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Amortization entry not found'; END IF;
  IF v_entry.status = 'posted' THEN RAISE EXCEPTION 'Entry is already posted'; END IF;

  SELECT * INTO v_sched FROM amortization_schedules WHERE id = v_entry.schedule_id;
  IF NOT is_company_member(v_sched.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_sched.status = 'cancelled' THEN RAISE EXCEPTION 'Schedule is cancelled'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_sched.company_id
    AND start_date <= v_entry.entry_date AND end_date >= v_entry.entry_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers %', v_entry.entry_date;
  END IF;

  SELECT COUNT(*) + 1 INTO v_seq FROM journal_entries
  WHERE company_id = v_sched.company_id
    AND je_number LIKE 'AMT-' || TO_CHAR(v_entry.entry_date, 'YYYYMM') || '-%';
  LOOP
    v_je_num := 'AMT-' || TO_CHAR(v_entry.entry_date, 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE company_id = v_sched.company_id AND je_number = v_je_num);
    v_seq := v_seq + 1;
  END LOOP;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_sched.company_id, v_sched.branch_id, v_je_num, v_entry.entry_date, v_fp_id,
    COALESCE(v_sched.description, v_sched.schedule_name) || ' — Period ' || v_entry.period_number || '/' || v_sched.total_periods,
    'MANUAL', 'posted', v_entry.amount, v_entry.amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_sched.company_id, 1, v_sched.expense_account_id,
     v_sched.schedule_name || ' amortization — period ' || v_entry.period_number,
     v_entry.amount, 0, auth.uid(), auth.uid()),
    (v_je_id, v_sched.company_id, 2, v_sched.asset_account_id,
     v_sched.schedule_name || ' amortization — period ' || v_entry.period_number,
     0, v_entry.amount, auth.uid(), auth.uid());

  UPDATE amortization_entries SET status = 'posted', je_id = v_je_id WHERE id = p_entry_id;

  UPDATE amortization_schedules
  SET posted_periods = posted_periods + 1,
      status         = CASE WHEN posted_periods + 1 >= total_periods THEN 'completed' ELSE status END,
      updated_at     = NOW(),
      updated_by     = auth.uid()
  WHERE id = v_sched.id;

  RETURN v_je_id;
END;
$$;

-- ── fn_cancel_amortization_schedule ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_amortization_schedule(p_schedule_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM amortization_schedules WHERE id = p_schedule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Schedule not found'; END IF;
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  UPDATE amortization_schedules SET status = 'cancelled', updated_at = NOW(), updated_by = auth.uid()
  WHERE id = p_schedule_id AND status = 'active';
  UPDATE amortization_entries SET status = 'skipped'
  WHERE schedule_id = p_schedule_id AND status = 'pending';
END;
$$;

-- ── fn_create_revenue_recognition_schedule ────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_create_revenue_recognition_schedule(
  p_company_id                  UUID,
  p_branch_id                   UUID,
  p_schedule_name               TEXT,
  p_description                 TEXT,
  p_deferred_revenue_account_id UUID,
  p_revenue_account_id          UUID,
  p_total_amount                NUMERIC,
  p_start_date                  DATE,
  p_total_periods               INT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id            UUID;
  v_period_amount NUMERIC(15,2);
  v_last_amount   NUMERIC(15,2);
  i               INT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  v_period_amount := ROUND(p_total_amount / p_total_periods, 2);
  v_last_amount   := p_total_amount - (v_period_amount * (p_total_periods - 1));

  INSERT INTO revenue_recognition_schedules (
    company_id, branch_id, schedule_name, description,
    deferred_revenue_account_id, revenue_account_id, total_amount, start_date, total_periods,
    created_by, updated_by
  ) VALUES (
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID, p_schedule_name, NULLIF(p_description, ''),
    p_deferred_revenue_account_id, p_revenue_account_id, p_total_amount, p_start_date, p_total_periods,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_id;

  FOR i IN 1..p_total_periods LOOP
    INSERT INTO revenue_recognition_entries (schedule_id, company_id, period_number, entry_date, amount)
    VALUES (
      v_id, p_company_id, i,
      (p_start_date + ((i - 1) * INTERVAL '1 month'))::DATE,
      CASE WHEN i = p_total_periods THEN v_last_amount ELSE v_period_amount END
    );
  END LOOP;

  RETURN v_id;
END;
$$;

-- ── fn_post_revenue_recognition_entry ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_post_revenue_recognition_entry(p_entry_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry  revenue_recognition_entries%ROWTYPE;
  v_sched  revenue_recognition_schedules%ROWTYPE;
  v_fp_id  UUID;
  v_je_id  UUID;
  v_je_num TEXT;
  v_seq    INT;
BEGIN
  SELECT * INTO v_entry FROM revenue_recognition_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Revenue recognition entry not found'; END IF;
  IF v_entry.status = 'posted' THEN RAISE EXCEPTION 'Entry is already posted'; END IF;

  SELECT * INTO v_sched FROM revenue_recognition_schedules WHERE id = v_entry.schedule_id;
  IF NOT is_company_member(v_sched.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_sched.status = 'cancelled' THEN RAISE EXCEPTION 'Schedule is cancelled'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_sched.company_id
    AND start_date <= v_entry.entry_date AND end_date >= v_entry.entry_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers %', v_entry.entry_date;
  END IF;

  SELECT COUNT(*) + 1 INTO v_seq FROM journal_entries
  WHERE company_id = v_sched.company_id
    AND je_number LIKE 'RR-' || TO_CHAR(v_entry.entry_date, 'YYYYMM') || '-%';
  LOOP
    v_je_num := 'RR-' || TO_CHAR(v_entry.entry_date, 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE company_id = v_sched.company_id AND je_number = v_je_num);
    v_seq := v_seq + 1;
  END LOOP;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_sched.company_id, v_sched.branch_id, v_je_num, v_entry.entry_date, v_fp_id,
    COALESCE(v_sched.description, v_sched.schedule_name) || ' — Period ' || v_entry.period_number || '/' || v_sched.total_periods,
    'MANUAL', 'posted', v_entry.amount, v_entry.amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR Deferred Revenue, CR Revenue
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_sched.company_id, 1, v_sched.deferred_revenue_account_id,
     v_sched.schedule_name || ' recognition — period ' || v_entry.period_number,
     v_entry.amount, 0, auth.uid(), auth.uid()),
    (v_je_id, v_sched.company_id, 2, v_sched.revenue_account_id,
     v_sched.schedule_name || ' recognition — period ' || v_entry.period_number,
     0, v_entry.amount, auth.uid(), auth.uid());

  UPDATE revenue_recognition_entries SET status = 'posted', je_id = v_je_id WHERE id = p_entry_id;

  UPDATE revenue_recognition_schedules
  SET posted_periods = posted_periods + 1,
      status         = CASE WHEN posted_periods + 1 >= total_periods THEN 'completed' ELSE status END,
      updated_at     = NOW(),
      updated_by     = auth.uid()
  WHERE id = v_sched.id;

  RETURN v_je_id;
END;
$$;

-- ── fn_cancel_revenue_recognition_schedule ────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_revenue_recognition_schedule(p_schedule_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM revenue_recognition_schedules WHERE id = p_schedule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Schedule not found'; END IF;
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  UPDATE revenue_recognition_schedules SET status = 'cancelled', updated_at = NOW(), updated_by = auth.uid()
  WHERE id = p_schedule_id AND status = 'active';
  UPDATE revenue_recognition_entries SET status = 'skipped'
  WHERE schedule_id = p_schedule_id AND status = 'pending';
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_amortization_schedule(UUID,UUID,TEXT,TEXT,UUID,UUID,NUMERIC,DATE,INT)  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_amortization_entry(UUID)                                                 TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_amortization_schedule(UUID)                                            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_create_revenue_recognition_schedule(UUID,UUID,TEXT,TEXT,UUID,UUID,NUMERIC,DATE,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_revenue_recognition_entry(UUID)                                          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cancel_revenue_recognition_schedule(UUID)                                     TO authenticated;
