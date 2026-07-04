-- ══════════════════════════════════════════════════════════════════════════════
-- Dimension propagation to journal entry lines (PXL-DA-017, DEC-011)
--
-- DEC-011: company is the tenant/security boundary; branch, department, and
-- cost center are reporting dimensions that must be validated for company
-- consistency and propagated from source documents to JE lines so branch P&L
-- and cost-center reports reconcile to the GL.
--
-- Design: every JE writer already stamps the source document's branch on the
-- journal_entries header (except stock transfers, which span warehouses and
-- stay unattributed). Rather than touching all 34 writers, lines inherit the
-- header branch centrally in a BEFORE trigger, so every current and future
-- writer propagates automatically. Department/cost center are line-level
-- capture-ready (documents do not carry them yet); manual JEs can set them
-- per line and reversals preserve them.
--
--   1. journal_entry_lines gains branch_id / department_id / cost_center_id.
--   2. journal_entries guard: header branch must belong to the JE company.
--   3. journal_entry_lines guard: line company must equal the JE company
--      (new integrity check); branch inherits from the header when absent;
--      all three dimensions must belong to the line company.
--   4. Backfill: existing lines inherit their header branch (only where the
--      branch verifiably belongs to the line company).
--   5. vw_general_ledger.branch_id becomes line-accurate
--      (COALESCE(line, header) — same name/type/position, so Branch P&L and
--      every other consumer upgrades transparently); line department_id /
--      cost_center_id are appended.
--   6. fn_post_manual_je accepts optional per-line branch_id / department_id /
--      cost_center_id in p_lines; fn_reverse_je copies line dimensions onto
--      the reversal lines.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Line dimension columns ──────────────────────────────────────────────────

ALTER TABLE journal_entry_lines
  ADD COLUMN IF NOT EXISTS branch_id      UUID REFERENCES branches(id),
  ADD COLUMN IF NOT EXISTS department_id  UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);

CREATE INDEX IF NOT EXISTS idx_jel_branch
  ON journal_entry_lines (branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_jel_department
  ON journal_entry_lines (department_id) WHERE department_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_jel_cost_center
  ON journal_entry_lines (cost_center_id) WHERE cost_center_id IS NOT NULL;

-- ── 2. Header guard: branch must belong to the JE company ──────────────────────

CREATE OR REPLACE FUNCTION fn_je_dimensions_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches b
    WHERE b.id = NEW.branch_id AND b.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'Journal entry branch % does not belong to company %',
      NEW.branch_id, NEW.company_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_je_dimensions_guard ON journal_entries;
CREATE TRIGGER trg_je_dimensions_guard
  BEFORE INSERT OR UPDATE OF branch_id, company_id ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_je_dimensions_guard();

-- ── 3. Line guard: company integrity, branch inheritance, dimension validity ───

CREATE OR REPLACE FUNCTION fn_je_line_dimensions_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je_company UUID;
  v_je_branch  UUID;
BEGIN
  SELECT company_id, branch_id INTO v_je_company, v_je_branch
  FROM journal_entries WHERE id = NEW.je_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Journal entry % not found for line', NEW.je_id;
  END IF;

  IF NEW.company_id IS DISTINCT FROM v_je_company THEN
    RAISE EXCEPTION 'JE line company % does not match journal entry company %',
      NEW.company_id, v_je_company;
  END IF;

  -- Lines inherit the header branch unless the writer sets one explicitly.
  IF TG_OP = 'INSERT' AND NEW.branch_id IS NULL THEN
    NEW.branch_id := v_je_branch;
  END IF;

  IF NEW.branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches b
    WHERE b.id = NEW.branch_id AND b.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line branch % does not belong to company %',
      NEW.branch_id, NEW.company_id;
  END IF;

  IF NEW.department_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM departments d
    WHERE d.id = NEW.department_id AND d.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line department % does not belong to company %',
      NEW.department_id, NEW.company_id;
  END IF;

  IF NEW.cost_center_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM cost_centers cc
    WHERE cc.id = NEW.cost_center_id AND cc.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line cost center % does not belong to company %',
      NEW.cost_center_id, NEW.company_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_je_line_dimensions_guard ON journal_entry_lines;
CREATE TRIGGER trg_je_line_dimensions_guard
  BEFORE INSERT OR UPDATE ON journal_entry_lines
  FOR EACH ROW EXECUTE FUNCTION fn_je_line_dimensions_guard();

-- ── 4. Backfill: lines inherit their header branch ─────────────────────────────
-- Only where the header branch verifiably belongs to the line's company, so a
-- hypothetical legacy cross-company branch cannot abort the migration.

UPDATE journal_entry_lines jel
SET branch_id = je.branch_id
FROM journal_entries je
JOIN branches b ON b.id = je.branch_id
WHERE je.id = jel.je_id
  AND jel.branch_id IS NULL
  AND je.branch_id IS NOT NULL
  AND b.company_id = jel.company_id;

-- ── 5. vw_general_ledger: line-accurate branch + line dimensions ───────────────
-- branch_id keeps its name/type/position (COALESCE(line, header)), so Branch
-- P&L and all other consumers become line-accurate transparently.
-- department_id / cost_center_id are appended.

CREATE OR REPLACE VIEW vw_general_ledger
WITH (security_invoker = true) AS
SELECT
  jel.id            AS line_id,
  jel.je_id,
  jel.company_id,
  COALESCE(jel.branch_id, je.branch_id) AS branch_id,
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
  jel.credit_amount,
  jel.department_id,
  jel.cost_center_id
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.je_id
JOIN chart_of_accounts coa ON coa.id = jel.account_id
LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
WHERE je.status IN ('posted', 'reversed');

-- ── 6a. fn_post_manual_je: optional per-line dimensions in p_lines ─────────────

CREATE OR REPLACE FUNCTION public.fn_post_manual_je(p_company_id uuid, p_branch_id uuid, p_je_date date, p_description text, p_reference_doc_type text, p_auto_reverse boolean, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      debit_amount, credit_amount, branch_id, department_id, cost_center_id,
      created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no,
      (v_line->>'account_id')::UUID,
      NULLIF(v_line->>'description', ''),
      COALESCE((v_line->>'debit_amount')::NUMERIC, 0),
      COALESCE((v_line->>'credit_amount')::NUMERIC, 0),
      NULLIF(v_line->>'branch_id', '')::UUID,
      NULLIF(v_line->>'department_id', '')::UUID,
      NULLIF(v_line->>'cost_center_id', '')::UUID,
      auth.uid(), auth.uid()
    );
  END LOOP;

  RETURN v_je_id;
END;
$function$;

-- ── 6b. fn_reverse_je: reversal lines carry the original line dimensions ───────

CREATE OR REPLACE FUNCTION public.fn_reverse_je(p_je_id uuid, p_reversal_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Swap debit/credit on every line; dimensions travel with the line
  FOR v_line IN
    SELECT line_number, account_id, description, debit_amount, credit_amount,
           branch_id, department_id, cost_center_id
    FROM journal_entry_lines WHERE je_id = v_je.id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, branch_id, department_id, cost_center_id,
      created_by, updated_by
    ) VALUES (
      v_new_id, v_je.company_id, v_line.line_number, v_line.account_id,
      'Reversal — ' || COALESCE(v_line.description, ''),
      v_line.credit_amount, v_line.debit_amount,
      v_line.branch_id, v_line.department_id, v_line.cost_center_id,
      auth.uid(), auth.uid()
    );
  END LOOP;

  UPDATE journal_entries
  SET status = 'reversed', reversed_by_je_id = v_new_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_je.id;

  RETURN v_new_id;
END;
$function$;
