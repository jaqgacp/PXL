-- ══════════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE (Migration 025)
-- Manual journal entries, reversals, recurring templates, GL/TB views.
-- Audit rules: every JE must balance, post only to an OPEN fiscal period,
-- posted entries are immutable (reverse only, never delete), no double reversal.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Step 1: Extend journal_entries ────────────────────────────────────────────
ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS auto_reverse        BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_auto_reversal    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reversed_by_je_id   UUID REFERENCES journal_entries(id);

ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_reference_doc_type_check;
ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_reference_doc_type_check
  CHECK (reference_doc_type IN (
    'SI','OR','CM','DM','MANUAL','VB','PV','CP','VC','REV',
    'FT','IBT','BADJ','PCV','PCR','CV','RECURRING'
  ));

-- ── Step 2: Recurring journal templates ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS recurring_journal_templates (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID          NOT NULL REFERENCES companies(id),
  branch_id         UUID          REFERENCES branches(id),
  template_name     TEXT          NOT NULL,
  description       TEXT,
  recurrence_type   TEXT          NOT NULL DEFAULT 'monthly'
                    CHECK (recurrence_type IN ('monthly','quarterly','semi_annual','annual')),
  day_of_month      INT           NOT NULL DEFAULT 1 CHECK (day_of_month BETWEEN 1 AND 28),
  next_run_date     DATE,
  last_run_date     DATE,
  start_date        DATE          NOT NULL,
  end_date          DATE,
  auto_reverse      BOOLEAN       NOT NULL DEFAULT false,
  is_active         BOOLEAN       NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by        UUID,
  updated_by        UUID,
  UNIQUE (company_id, template_name)
);

CREATE TABLE IF NOT EXISTS recurring_journal_template_lines (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   UUID          NOT NULL REFERENCES recurring_journal_templates(id) ON DELETE CASCADE,
  company_id    UUID          NOT NULL REFERENCES companies(id),
  line_number   INT           NOT NULL,
  account_id    UUID          NOT NULL REFERENCES chart_of_accounts(id),
  description   TEXT,
  debit_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  credit_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rjt_company       ON recurring_journal_templates (company_id);
CREATE INDEX IF NOT EXISTS idx_rjtl_template     ON recurring_journal_template_lines (template_id);
CREATE INDEX IF NOT EXISTS idx_rjtl_company      ON recurring_journal_template_lines (company_id);

ALTER TABLE recurring_journal_templates      ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_journal_template_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rjt_read"   ON recurring_journal_templates FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "rjt_insert" ON recurring_journal_templates FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "rjt_update" ON recurring_journal_templates FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "rjtl_read"   ON recurring_journal_template_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "rjtl_insert" ON recurring_journal_template_lines FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "rjtl_update" ON recurring_journal_template_lines FOR UPDATE TO authenticated USING (is_company_member(company_id));

DROP TRIGGER IF EXISTS trg_rjt_updated_at ON recurring_journal_templates;
CREATE TRIGGER trg_rjt_updated_at
  BEFORE UPDATE ON recurring_journal_templates FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Step 3: Views ─────────────────────────────────────────────────────────────

-- Full GL detail view — used by General Ledger and Account Detail Ledger pages
CREATE OR REPLACE VIEW vw_general_ledger
WITH (security_invoker = true) AS
SELECT
  jel.id            AS line_id,
  jel.je_id,
  jel.company_id,
  je.branch_id,
  je.fiscal_period_id,
  fp.period_name,
  fp.start_date     AS period_start,
  fp.end_date       AS period_end,
  je.je_date,
  je.je_number,
  je.description    AS je_description,
  je.reference_doc_type,
  je.reference_doc_id,
  je.status         AS je_status,
  je.is_auto_reversal,
  je.reversed_by_je_id,
  jel.account_id,
  coa.account_code,
  coa.account_name,
  coa.account_type,
  coa.normal_balance,
  jel.line_number,
  jel.description   AS line_description,
  jel.debit_amount,
  jel.credit_amount
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.je_id
JOIN chart_of_accounts coa ON coa.id = jel.account_id
LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
WHERE je.status = 'posted';

-- Trial balance view — aggregated by account and fiscal period
CREATE OR REPLACE VIEW vw_trial_balance
WITH (security_invoker = true) AS
SELECT
  jel.company_id,
  je.fiscal_period_id,
  fp.period_name,
  fp.period_number,
  fp.start_date   AS period_start,
  fp.end_date     AS period_end,
  jel.account_id,
  coa.account_code,
  coa.account_name,
  coa.account_type,
  coa.normal_balance,
  coa.parent_id,
  SUM(jel.debit_amount)                             AS total_debit,
  SUM(jel.credit_amount)                            AS total_credit,
  SUM(jel.debit_amount) - SUM(jel.credit_amount)   AS net_movement
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.je_id
JOIN chart_of_accounts coa ON coa.id = jel.account_id
LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
WHERE je.status = 'posted'
GROUP BY jel.company_id, je.fiscal_period_id, fp.period_name, fp.period_number,
         fp.start_date, fp.end_date,
         jel.account_id, coa.account_code, coa.account_name,
         coa.account_type, coa.normal_balance, coa.parent_id;

-- ── Step 4: Functions ─────────────────────────────────────────────────────────

-- fn_post_manual_je: balanced, postable accounts only, open period required.
CREATE OR REPLACE FUNCTION fn_post_manual_je(
  p_company_id         UUID,
  p_branch_id          UUID,
  p_je_date            DATE,
  p_description        TEXT,
  p_reference_doc_type TEXT,
  p_auto_reverse       BOOLEAN,
  p_lines              JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_debit  NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
  v_fp_id        UUID;
  v_je_id        UUID;
  v_je_number    TEXT;
  v_seq          INT;
  v_line         JSONB;
  v_line_no      INT := 0;
  v_dr           NUMERIC(15,2);
  v_cr           NUMERIC(15,2);
  v_account_id   UUID;
  v_postable     BOOLEAN;
  v_active       BOOLEAN;
  v_ref_type     TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  IF p_lines IS NULL OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'Journal entry must have at least 2 lines';
  END IF;

  v_ref_type := COALESCE(NULLIF(p_reference_doc_type, ''), 'MANUAL');

  -- Validate each line and accumulate totals
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
  LOOP
    v_account_id := NULLIF(v_line->>'account_id', '')::UUID;
    v_dr := COALESCE((v_line->>'debit_amount')::NUMERIC, 0);
    v_cr := COALESCE((v_line->>'credit_amount')::NUMERIC, 0);

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'Every line must reference an account';
    END IF;
    IF v_dr < 0 OR v_cr < 0 THEN
      RAISE EXCEPTION 'Line amounts cannot be negative';
    END IF;
    IF v_dr > 0 AND v_cr > 0 THEN
      RAISE EXCEPTION 'A line cannot have both a debit and a credit amount';
    END IF;
    IF v_dr = 0 AND v_cr = 0 THEN
      RAISE EXCEPTION 'A line must have a non-zero debit or credit amount';
    END IF;

    SELECT is_postable, is_active INTO v_postable, v_active
    FROM chart_of_accounts
    WHERE id = v_account_id AND company_id = p_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Account % does not belong to this company', v_account_id;
    END IF;
    IF NOT v_postable THEN
      RAISE EXCEPTION 'Account % is not postable (header / summary account)', v_account_id;
    END IF;
    IF NOT v_active THEN
      RAISE EXCEPTION 'Account % is inactive', v_account_id;
    END IF;

    v_total_debit  := v_total_debit + v_dr;
    v_total_credit := v_total_credit + v_cr;
  END LOOP;

  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Journal entry must balance: total debit % <> total credit %', v_total_debit, v_total_credit;
  END IF;
  IF v_total_debit <= 0 THEN
    RAISE EXCEPTION 'Journal entry must have at least one non-zero amount';
  END IF;

  -- Open fiscal period required
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = p_company_id
    AND start_date <= p_je_date AND end_date >= p_je_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers % — posting is not allowed', p_je_date;
  END IF;

  -- Generate a unique JE number for this company
  SELECT COUNT(*) + 1 INTO v_seq
  FROM journal_entries
  WHERE company_id = p_company_id AND je_number LIKE 'MJE-' || TO_CHAR(p_je_date, 'YYYYMM') || '-%';
  LOOP
    v_je_number := 'MJE-' || TO_CHAR(p_je_date, 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM journal_entries WHERE company_id = p_company_id AND je_number = v_je_number
    );
    v_seq := v_seq + 1;
  END LOOP;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID, v_je_number, p_je_date, v_fp_id,
    COALESCE(p_description, 'Manual Journal Entry'), v_ref_type, NULL, 'posted',
    v_total_debit, v_total_credit, COALESCE(p_auto_reverse, false), false,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no,
      (v_line->>'account_id')::UUID,
      NULLIF(v_line->>'description', ''),
      COALESCE((v_line->>'debit_amount')::NUMERIC, 0),
      COALESCE((v_line->>'credit_amount')::NUMERIC, 0),
      auth.uid(), auth.uid()
    );
  END LOOP;

  RETURN v_je_id;
END;
$$;

-- fn_reverse_je: only posted, only once, into an open period for the reversal date.
CREATE OR REPLACE FUNCTION fn_reverse_je(
  p_je_id          UUID,
  p_reversal_date  DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je       journal_entries%ROWTYPE;
  v_rev_date DATE;
  v_fp_id    UUID;
  v_new_id   UUID;
  v_new_no   TEXT;
  v_line     RECORD;
BEGIN
  SELECT * INTO v_je FROM journal_entries WHERE id = p_je_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Journal entry not found'; END IF;
  IF NOT is_company_member(v_je.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_je.status <> 'posted' THEN
    RAISE EXCEPTION 'Only posted journal entries can be reversed (current status: %)', v_je.status;
  END IF;
  IF v_je.reversed_by_je_id IS NOT NULL THEN
    RAISE EXCEPTION 'Journal entry % has already been reversed', v_je.je_number;
  END IF;

  v_rev_date := COALESCE(p_reversal_date, CURRENT_DATE);

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_je.company_id
    AND start_date <= v_rev_date AND end_date >= v_rev_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers reversal date % — reversal is not allowed', v_rev_date;
  END IF;

  v_new_no := 'REV-' || v_je.je_number;
  IF EXISTS (SELECT 1 FROM journal_entries WHERE company_id = v_je.company_id AND je_number = v_new_no) THEN
    v_new_no := 'REV-' || v_je.je_number || '-' || TO_CHAR(NOW(), 'HH24MISS');
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    v_je.company_id, v_je.branch_id, v_new_no, v_rev_date, v_fp_id,
    'Reversal of ' || v_je.je_number || COALESCE(' — ' || v_je.description, ''),
    'REV', v_je.id, 'posted',
    v_je.total_credit, v_je.total_debit, false, false,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_new_id;

  -- Swap debit/credit on every line
  FOR v_line IN
    SELECT line_number, account_id, description, debit_amount, credit_amount
    FROM journal_entry_lines WHERE je_id = v_je.id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_new_id, v_je.company_id, v_line.line_number, v_line.account_id,
      'Reversal — ' || COALESCE(v_line.description, ''),
      v_line.credit_amount, v_line.debit_amount, auth.uid(), auth.uid()
    );
  END LOOP;

  UPDATE journal_entries
  SET status = 'reversed', reversed_by_je_id = v_new_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_je.id;

  RETURN v_new_id;
END;
$$;

-- fn_execute_recurring_template: materialize a template into a posted JE.
CREATE OR REPLACE FUNCTION fn_execute_recurring_template(
  p_template_id UUID,
  p_je_date     DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl          recurring_journal_templates%ROWTYPE;
  v_total_debit  NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
  v_fp_id        UUID;
  v_je_id        UUID;
  v_je_number    TEXT;
  v_seq          INT;
  v_line         RECORD;
  v_next         DATE;
BEGIN
  SELECT * INTO v_tpl FROM recurring_journal_templates WHERE id = p_template_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recurring template not found'; END IF;
  IF NOT is_company_member(v_tpl.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NOT v_tpl.is_active THEN RAISE EXCEPTION 'Template % is inactive', v_tpl.template_name; END IF;

  SELECT COALESCE(SUM(debit_amount), 0), COALESCE(SUM(credit_amount), 0)
    INTO v_total_debit, v_total_credit
  FROM recurring_journal_template_lines WHERE template_id = p_template_id;

  IF v_total_debit <= 0 THEN
    RAISE EXCEPTION 'Template has no posting lines';
  END IF;
  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Template does not balance: total debit % <> total credit %', v_total_debit, v_total_credit;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_tpl.company_id
    AND start_date <= p_je_date AND end_date >= p_je_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers % — posting is not allowed', p_je_date;
  END IF;

  SELECT COUNT(*) + 1 INTO v_seq
  FROM journal_entries
  WHERE company_id = v_tpl.company_id AND je_number LIKE 'RJE-' || TO_CHAR(p_je_date, 'YYYYMM') || '-%';
  LOOP
    v_je_number := 'RJE-' || TO_CHAR(p_je_date, 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM journal_entries WHERE company_id = v_tpl.company_id AND je_number = v_je_number
    );
    v_seq := v_seq + 1;
  END LOOP;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    v_tpl.company_id, v_tpl.branch_id, v_je_number, p_je_date, v_fp_id,
    COALESCE(v_tpl.description, v_tpl.template_name), 'RECURRING', v_tpl.id, 'posted',
    v_total_debit, v_total_credit, v_tpl.auto_reverse, false,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT line_number, account_id, description, debit_amount, credit_amount
    FROM recurring_journal_template_lines WHERE template_id = p_template_id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, v_tpl.company_id, v_line.line_number, v_line.account_id,
      v_line.description, v_line.debit_amount, v_line.credit_amount, auth.uid(), auth.uid()
    );
  END LOOP;

  -- Auto-reverse at the start of next month if requested
  IF v_tpl.auto_reverse THEN
    PERFORM fn_reverse_je(v_je_id, (date_trunc('month', p_je_date) + INTERVAL '1 month')::DATE);
    UPDATE journal_entries SET is_auto_reversal = true
    WHERE reference_doc_id = v_je_id AND reference_doc_type = 'REV';
  END IF;

  -- Advance the schedule
  v_next := CASE v_tpl.recurrence_type
    WHEN 'monthly'     THEN (p_je_date + INTERVAL '1 month')
    WHEN 'quarterly'   THEN (p_je_date + INTERVAL '3 months')
    WHEN 'semi_annual' THEN (p_je_date + INTERVAL '6 months')
    WHEN 'annual'      THEN (p_je_date + INTERVAL '1 year')
    ELSE (p_je_date + INTERVAL '1 month')
  END::DATE;

  UPDATE recurring_journal_templates
  SET last_run_date = p_je_date, next_run_date = v_next, updated_at = NOW(), updated_by = auth.uid()
  WHERE id = p_template_id;

  RETURN v_je_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_post_manual_je(UUID, UUID, DATE, TEXT, TEXT, BOOLEAN, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_reverse_je(UUID, DATE)                                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_execute_recurring_template(UUID, DATE)                        TO authenticated;
