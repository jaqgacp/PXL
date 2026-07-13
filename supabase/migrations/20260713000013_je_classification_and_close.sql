-- ══════════════════════════════════════════════════════════════════════════════
-- Journal-entry classification, year-end close, and trial-balance modes
-- (PXL-AUD-013 + PXL-DA-014 — financial-statement / close readiness gate)
--
-- Before this migration every posted journal entry was undifferentiated, the
-- Trial Balance had no real unadjusted/adjusted/post-closing definition (the
-- "Adjusted TB" checkbox only hid zero balances), and there was no closing
-- process moving net income into retained earnings.
--
-- This migration adds:
--   1. journal_entries.entry_class ('regular' | 'adjusting' | 'closing' |
--      'opening'), defaulting existing rows to 'regular'.
--   2. A 'CLOSE' posting-source type so closing journals reconcile through the
--      standard reference_doc_type FK.
--   3. vw_general_ledger exposes entry_class so reports can define TB modes:
--        unadjusted  = regular + opening
--        adjusted    = regular + opening + adjusting
--        post-closing= regular + opening + adjusting + closing
--   4. fn_post_manual_je gains an optional p_entry_class so users can post
--      adjusting (and opening) entries; 'closing' stays reserved for the close
--      engine.
--   5. fn_close_fiscal_year: posts one balanced closing journal that zeroes the
--      year's revenue/expense accounts and carries net income (or loss) to the
--      fiscal year's retained-earnings account, then locks the year's periods
--      and marks the fiscal year 'closed'. Income is closed DIRECTLY to
--      retained earnings (no intermediate Income Summary account) — see DEC-019.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Entry classification column ─────────────────────────────────────────────

ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS entry_class TEXT NOT NULL DEFAULT 'regular'
  CHECK (entry_class IN ('regular','adjusting','closing','opening'));

CREATE INDEX IF NOT EXISTS idx_je_company_class
  ON journal_entries (company_id, entry_class);

COMMENT ON COLUMN journal_entries.entry_class IS
  'Accounting classification: regular (operational), adjusting (period-end adjustments), closing (year-end close of P&L to retained earnings, engine-only), opening (opening balances). Drives Trial Balance modes.';

-- ── 2. CLOSE posting-source type ───────────────────────────────────────────────

INSERT INTO ref_posting_source_types (
  document_type, source_table, document_number_column, document_date_column,
  status_column, route_path, display_name, allows_multiple_journal_entries
) VALUES
  ('CLOSE', 'journal_entries', 'je_number', 'je_date', 'status', '/trial-balance', 'Year-End Closing Entry', true)
ON CONFLICT (document_type) DO NOTHING;

-- ── 3. Expose entry_class on the general-ledger view ───────────────────────────
-- A replace of an existing view can only append columns at the end, so
-- entry_class is added last; every existing column keeps its position.

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
  jel.cost_center_id,
  je.entry_class
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.je_id
JOIN chart_of_accounts coa ON coa.id = jel.account_id
LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
WHERE je.status IN ('posted', 'reversed');

-- ── 4. fn_post_manual_je: optional entry classification ────────────────────────
-- Replaces the 7-argument function with an 8-argument version whose trailing
-- p_entry_class defaults to 'regular', so existing 7-argument callers still bind.
-- 'closing' is rejected here — only fn_close_fiscal_year may post closing entries.

DROP FUNCTION IF EXISTS fn_post_manual_je(uuid, uuid, date, text, text, boolean, jsonb);

CREATE OR REPLACE FUNCTION public.fn_post_manual_je(
  p_company_id uuid,
  p_branch_id uuid,
  p_je_date date,
  p_description text,
  p_reference_doc_type text,
  p_auto_reverse boolean,
  p_lines jsonb,
  p_entry_class text DEFAULT 'regular'
)
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
  v_entry_class  TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  IF p_lines IS NULL OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'Journal entry must have at least 2 lines';
  END IF;

  v_ref_type := COALESCE(NULLIF(p_reference_doc_type, ''), 'MANUAL');

  v_entry_class := COALESCE(NULLIF(p_entry_class, ''), 'regular');
  IF v_entry_class NOT IN ('regular','adjusting','opening') THEN
    RAISE EXCEPTION 'Manual journal entries may only be classified regular, adjusting, or opening (got %). Closing entries are posted by the year-end close.', v_entry_class;
  END IF;

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
    description, reference_doc_type, reference_doc_id, status, entry_class,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID, v_je_number, p_je_date, v_fp_id,
    COALESCE(p_description, 'Manual Journal Entry'), v_ref_type, NULL, 'posted', v_entry_class,
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

GRANT EXECUTE ON FUNCTION fn_post_manual_je(UUID, UUID, DATE, TEXT, TEXT, BOOLEAN, JSONB, TEXT) TO authenticated;

-- ── 5. fn_close_fiscal_year: post the closing entry and finalize the year ──────

CREATE OR REPLACE FUNCTION public.fn_close_fiscal_year(
  p_company_id uuid,
  p_fiscal_year_id uuid,
  p_close_date date DEFAULT NULL
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_year         fiscal_years%ROWTYPE;
  v_re_id        UUID;
  v_re_postable  BOOLEAN;
  v_re_active    BOOLEAN;
  v_re_type      TEXT;
  v_close_date   DATE;
  v_fp_id        UUID;
  v_je_id        UUID;
  v_je_number    TEXT;
  v_seq          INT;
  v_line_no      INT := 0;
  v_close_debit  NUMERIC(15,2) := 0;
  v_close_credit NUMERIC(15,2) := 0;
  v_net_dr       NUMERIC(15,2) := 0;
  v_net_income   NUMERIC(15,2);
  v_re_debit     NUMERIC(15,2);
  v_re_credit    NUMERIC(15,2);
  v_total_debit  NUMERIC(15,2);
  v_total_credit NUMERIC(15,2);
  r              RECORD;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: closing a fiscal year requires company admin rights';
  END IF;

  SELECT * INTO v_year FROM fiscal_years
  WHERE id = p_fiscal_year_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal year % not found for this company', p_fiscal_year_id;
  END IF;
  IF v_year.status = 'closed' THEN
    RAISE EXCEPTION 'Fiscal year % is already closed', v_year.year_name;
  END IF;

  -- Retained earnings destination must be a postable, active equity account.
  v_re_id := v_year.retained_earnings_id;
  IF v_re_id IS NULL THEN
    RAISE EXCEPTION 'Fiscal year % has no retained earnings account configured', v_year.year_name;
  END IF;
  SELECT is_postable, is_active, account_type
    INTO v_re_postable, v_re_active, v_re_type
  FROM chart_of_accounts WHERE id = v_re_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Retained earnings account does not belong to this company';
  END IF;
  IF v_re_type <> 'equity' THEN
    RAISE EXCEPTION 'Retained earnings account must be an equity account';
  END IF;
  IF NOT v_re_postable THEN
    RAISE EXCEPTION 'Retained earnings account is not postable';
  END IF;
  IF NOT v_re_active THEN
    RAISE EXCEPTION 'Retained earnings account is inactive';
  END IF;

  v_close_date := COALESCE(p_close_date, v_year.end_date);
  IF v_close_date < v_year.start_date OR v_close_date > v_year.end_date THEN
    RAISE EXCEPTION 'Close date % must fall within fiscal year % (% to %)',
      v_close_date, v_year.year_name, v_year.start_date, v_year.end_date;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = p_company_id AND fiscal_year_id = p_fiscal_year_id
    AND start_date <= v_close_date AND end_date >= v_close_date
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No fiscal period covers the close date %', v_close_date;
  END IF;

  -- Aggregate this year's profit-and-loss close amounts (regular + adjusting +
  -- opening only) so a re-close can never double-count prior closing entries.
  SELECT
    COALESCE(SUM(CASE WHEN t.net_dr < 0 THEN -t.net_dr ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN t.net_dr > 0 THEN  t.net_dr ELSE 0 END), 0),
    COALESCE(SUM(t.net_dr), 0)
  INTO v_close_debit, v_close_credit, v_net_dr
  FROM (
    SELECT SUM(jel.debit_amount) - SUM(jel.credit_amount) AS net_dr
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    WHERE jel.company_id = p_company_id
      AND je.status IN ('posted','reversed')
      AND je.entry_class IN ('regular','adjusting','opening')
      AND je.je_date BETWEEN v_year.start_date AND v_year.end_date
      AND coa.account_type IN ('revenue','expense')
    GROUP BY jel.account_id
    HAVING ABS(SUM(jel.debit_amount) - SUM(jel.credit_amount)) > 0.005
  ) t;

  -- net_dr = Sum(debit - credit) over P&L accounts = expenses - revenue.
  v_net_income := -v_net_dr;

  IF v_close_debit = 0 AND v_close_credit = 0 THEN
    -- No P&L activity to close; still finalize the year.
    UPDATE fiscal_periods SET is_locked = true, updated_at = NOW()
    WHERE fiscal_year_id = p_fiscal_year_id;
    UPDATE fiscal_years SET status = 'closed', updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_fiscal_year_id;
    RETURN NULL;
  END IF;

  v_re_debit  := CASE WHEN v_net_income < 0 THEN -v_net_income ELSE 0 END;
  v_re_credit := CASE WHEN v_net_income > 0 THEN  v_net_income ELSE 0 END;
  v_total_debit  := v_close_debit  + v_re_debit;
  v_total_credit := v_close_credit + v_re_credit;

  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Internal error: closing entry does not balance (% vs %)', v_total_debit, v_total_credit;
  END IF;

  SELECT COUNT(*) + 1 INTO v_seq FROM journal_entries
  WHERE company_id = p_company_id AND je_number LIKE 'CLOSE-' || TO_CHAR(v_close_date, 'YYYY') || '-%';
  LOOP
    v_je_number := 'CLOSE-' || TO_CHAR(v_close_date, 'YYYY') || '-' || LPAD(v_seq::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE company_id = p_company_id AND je_number = v_je_number);
    v_seq := v_seq + 1;
  END LOOP;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status, entry_class,
    total_debit, total_credit, auto_reverse, is_auto_reversal, created_by, updated_by
  ) VALUES (
    p_company_id, NULL, v_je_number, v_close_date, v_fp_id,
    'Year-end closing of ' || v_year.year_name, 'CLOSE', NULL, 'posted', 'closing',
    v_total_debit, v_total_credit, false, false, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- One line per P&L account, posted on the side that zeroes its balance.
  FOR r IN
    SELECT jel.account_id,
           SUM(jel.debit_amount) - SUM(jel.credit_amount) AS net_dr,
           MIN(coa.account_code) AS account_code
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    WHERE jel.company_id = p_company_id
      AND je.status IN ('posted','reversed')
      AND je.entry_class IN ('regular','adjusting','opening')
      AND je.je_date BETWEEN v_year.start_date AND v_year.end_date
      AND coa.account_type IN ('revenue','expense')
    GROUP BY jel.account_id
    HAVING ABS(SUM(jel.debit_amount) - SUM(jel.credit_amount)) > 0.005
    ORDER BY MIN(coa.account_code)
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no, r.account_id, 'Year-end close',
      CASE WHEN r.net_dr < 0 THEN -r.net_dr ELSE 0 END,
      CASE WHEN r.net_dr > 0 THEN  r.net_dr ELSE 0 END,
      auth.uid(), auth.uid()
    );
  END LOOP;

  -- Retained-earnings balancing line: net income increases equity (credit),
  -- a net loss decreases it (debit).
  IF v_re_debit > 0.005 OR v_re_credit > 0.005 THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no, v_re_id,
      CASE WHEN v_net_income >= 0 THEN 'Net income to retained earnings' ELSE 'Net loss to retained earnings' END,
      v_re_debit, v_re_credit, auth.uid(), auth.uid()
    );
  END IF;

  -- Lock all periods of the year and mark the year closed.
  UPDATE fiscal_periods SET is_locked = true, updated_at = NOW()
  WHERE fiscal_year_id = p_fiscal_year_id;
  UPDATE fiscal_years SET status = 'closed', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_fiscal_year_id;

  RETURN v_je_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION fn_close_fiscal_year(UUID, UUID, DATE) TO authenticated;

COMMENT ON FUNCTION fn_close_fiscal_year(UUID, UUID, DATE) IS
  'Year-end close: posts one balanced closing journal (entry_class=closing, reference_doc_type=CLOSE) that zeroes the year''s revenue/expense accounts and carries net income/loss to fiscal_years.retained_earnings_id, then locks the year''s periods and sets the fiscal year status to closed. Direct-to-retained-earnings close (no Income Summary) per DEC-019.';
