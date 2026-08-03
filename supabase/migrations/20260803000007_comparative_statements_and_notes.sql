-- ══════════════════════════════════════════════════════════════════════════════
-- Comparative financial statements and basic statement notes (Backlog 18e)
--
-- Completes the reporting path: posted transactions → general ledger → trial
-- balance → current-period statements → comparative statements → basic notes.
--
-- ── The defect this had to fix first ──────────────────────────────────────────
--
-- `fn_financial_statement_report` read every posted journal line regardless of
-- `entry_class`. Once a fiscal year is closed, its closing journal debits the
-- revenue accounts and credits the expense accounts, so:
--
--   * the Statement of Comprehensive Income of any CLOSED year reads as ALL
--     ZEROES — measured on a fresh company, revenue 50,000 became 0.00 the
--     moment the year closed; and
--   * the Statement of Cash Flows RE-LABELS the whole year — the same company's
--     30,000 of operating cash flow moved to financing, because the closing
--     entry's credit to Retained Earnings is an equity movement and equity is
--     financing.
--
-- Nobody had seen it because nothing had ever closed a year until yesterday, and
-- comparatives are the first feature that reads a closed year on purpose. A
-- comparative column drawn from a closed prior year would otherwise have been
-- blank, which is exactly the sort of statement that looks finished and is
-- wrong.
--
-- The rule is per statement, and it follows from what a closing entry *is*:
--
--   income statement, cash flow  — EXCLUDE closing entries. Revenue for a period
--                                  is what was earned, not what was closed out,
--                                  and closing moves no cash.
--   balance sheet, equity        — INCLUDE them. Retained earnings is only
--                                  correct because of them, and the movement in
--                                  equity IS the close.
--
-- ── What this migration adds ─────────────────────────────────────────────────
--
--   1. `fn_fs_presentation_sign` — the presentation sign, extracted from the
--      report so the line schedules below share it instead of restating it.
--   2. `fn_financial_statement_report` gains `p_presentation_asof`: the date at
--      which the account-to-line mapping is read, defaulting to the period end
--      so every existing caller is unchanged. The comparative passes the CURRENT
--      period end when it fetches the prior year, so both columns are presented
--      on today's structure — which is what a comparative is for.
--   3. `fn_resolve_comparative_period` — resolves the prior comparable period
--      from the company's own fiscal calendar and says plainly, in data, when
--      there isn't one.
--   4. `fn_comparative_financial_statement_report` — current, prior, variance
--      and percentage variance per governed line. It calls the one reporting
--      entry point twice. There is no second reporting engine.
--   5. `fn_financial_statement_line_accounts` — the accounts behind a statement
--      line, current and prior, for drill-down and for the supporting schedules.
--   6. `fn_financial_statement_notes` — company information, reporting period,
--      basis of preparation, significant accounting policies and supporting
--      schedules, emitted as rows sourced from configured data. Every item
--      carries where it came from and whether it is actually configured, so an
--      unconfigured policy reads as unconfigured rather than as a default.
--
-- Reporting still writes nothing. No posting, kernel or close change.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Presentation sign, in one place ────────────────────────────────────────
-- A parent line is the plain sum of its children, so each amount is signed the
-- way its statement reads it. Extracted from the report body because the line
-- schedules must sign identically or a drill-down would not add up to the line
-- it came from.

CREATE OR REPLACE FUNCTION public.fn_fs_presentation_sign(
  p_statement          TEXT,
  p_is_cash_equivalent BOOLEAN,
  p_normal_balance     TEXT
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    -- Cash flow: an account's contribution to cash is the NEGATIVE of its own
    -- debit movement — stock bought (a debit) consumes cash — while the cash
    -- accounts carry their own movement, which the two must match.
    WHEN p_statement = 'cash_flow' AND NOT COALESCE(p_is_cash_equivalent, false) THEN -1
    WHEN p_statement = 'cash_flow'                                               THEN  1
    -- Comprehensive income reads credit-minus-debit for every line, so revenue is
    -- positive, expenses are negative, and the roll-up IS the net income rather
    -- than something a subtotal has to re-derive.
    WHEN p_statement = 'income_statement'                                        THEN -1
    -- Position and equity: assets debit-positive; liabilities and equity are
    -- credit-normal and shown positive, so their net is negated.
    WHEN p_normal_balance = 'credit'                                             THEN -1
    ELSE 1
  END;
$function$;

COMMENT ON FUNCTION public.fn_fs_presentation_sign(TEXT, BOOLEAN, TEXT) IS
  'The one presentation sign rule, shared by the statement report and the line-level account schedules so a drill-down always sums to the line it opened from.';

REVOKE ALL ON FUNCTION public.fn_fs_presentation_sign(TEXT, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fs_presentation_sign(TEXT, BOOLEAN, TEXT) TO authenticated, service_role;

-- ── 2. The one reporting entry point, corrected and re-presentable ────────────
-- The 5-argument form is dropped rather than overloaded: a defaulted sixth
-- argument beside it would make every existing five-argument call ambiguous.

DROP FUNCTION IF EXISTS public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID);

CREATE FUNCTION public.fn_financial_statement_report(
  p_company_id        UUID,
  p_statement         TEXT,
  p_period_start      DATE,
  p_period_end        DATE,
  p_branch_id         UUID DEFAULT NULL,
  -- The date at which the account-to-line mapping is read. NULL means the period
  -- end, which is what every single-period caller wants. A comparative passes the
  -- CURRENT period end when fetching a prior year so the two columns are
  -- presented identically; a comparative shown on two different structures
  -- compares nothing.
  p_presentation_asof DATE DEFAULT NULL
)
RETURNS TABLE (
  line_code       TEXT,
  line_label      TEXT,
  parent_code     TEXT,
  depth           INTEGER,
  line_role       TEXT,
  is_subtotal     BOOLEAN,
  display_order   INTEGER,
  opening_amount  NUMERIC(18,2),
  movement_amount NUMERIC(18,2),
  closing_amount  NUMERIC(18,2)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_map_asof        DATE;
  v_exclude_closing BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_statement NOT IN ('balance_sheet', 'income_statement', 'cash_flow', 'equity_statement') THEN
    RAISE EXCEPTION 'Unknown financial statement %', p_statement USING ERRCODE = '22023';
  END IF;
  IF p_period_end < p_period_start THEN
    RAISE EXCEPTION 'Period end cannot be before period start.';
  END IF;

  v_map_asof := COALESCE(p_presentation_asof, p_period_end);

  -- A closing journal moves the year's result out of the profit-and-loss
  -- accounts and into equity. It is part of the position and part of the
  -- movement in equity; it is not revenue, not an expense, and not a cash flow.
  v_exclude_closing := (p_statement IN ('income_statement', 'cash_flow'));

  RETURN QUERY
  WITH RECURSIVE
  -- Every posted debit-minus-credit movement, split into what happened before
  -- the period and what happened inside it.
  gl AS (
    SELECT jel.account_id,
           SUM(CASE WHEN je.je_date < p_period_start
                    THEN jel.debit_amount - jel.credit_amount ELSE 0 END) AS opening_net,
           SUM(CASE WHEN je.je_date BETWEEN p_period_start AND p_period_end
                    THEN jel.debit_amount - jel.credit_amount ELSE 0 END) AS movement_net
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    WHERE jel.company_id = p_company_id
      AND je.status IN ('posted', 'reversed')
      AND je.je_date <= p_period_end
      AND (NOT v_exclude_closing OR je.entry_class <> 'closing')
      AND (p_branch_id IS NULL OR jel.branch_id = p_branch_id)
    GROUP BY jel.account_id
  ),
  -- The statement's own line hierarchy, with depth for indentation.
  tree AS (
    SELECT f.id, f.line_code, f.line_label, f.parent_id, f.display_order,
           f.is_subtotal, f.line_role, 0 AS depth
    FROM fs_structure f
    WHERE f.company_id = p_company_id AND f.statement = p_statement AND f.parent_id IS NULL
    UNION ALL
    SELECT c.id, c.line_code, c.line_label, c.parent_id, c.display_order,
           c.is_subtotal, c.line_role, t.depth + 1
    FROM fs_structure c
    JOIN tree t ON t.id = c.parent_id
    WHERE c.company_id = p_company_id AND c.statement = p_statement
  ),
  mapped AS (
    SELECT m.fs_structure_id,
           SUM(COALESCE(gl.opening_net, 0)
               * fn_fs_presentation_sign(p_statement, coa.is_cash_equivalent, coa.normal_balance))
             AS opening_amount,
           SUM(COALESCE(gl.movement_net, 0)
               * fn_fs_presentation_sign(p_statement, coa.is_cash_equivalent, coa.normal_balance))
             AS movement_amount
    FROM account_fs_map m
    JOIN chart_of_accounts coa ON coa.id = m.account_id
    LEFT JOIN gl ON gl.account_id = m.account_id
    WHERE m.company_id = p_company_id
      AND m.statement = p_statement
      AND (m.effective_from IS NULL OR m.effective_from <= v_map_asof)
      AND (m.effective_to IS NULL OR m.effective_to >= v_map_asof)
    GROUP BY m.fs_structure_id
  ),
  -- Undistributed profit. Revenue and expense balances are not posted to equity
  -- until the year is closed, so a mid-year Statement of Financial Position does
  -- not balance without this line. It is computed from the income-statement
  -- accounts themselves — never mapped, never posted — and it DOES read the
  -- closing entries, which is what makes it fall to zero once the year closes.
  earnings AS (
    SELECT
      SUM(CASE WHEN je.je_date < p_period_start
               THEN jel.credit_amount - jel.debit_amount ELSE 0 END) AS opening_amount,
      SUM(CASE WHEN je.je_date BETWEEN p_period_start AND p_period_end
               THEN jel.credit_amount - jel.debit_amount ELSE 0 END) AS movement_amount
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    WHERE jel.company_id = p_company_id
      AND je.status IN ('posted', 'reversed')
      AND je.je_date <= p_period_end
      AND coa.account_type IN ('revenue', 'expense')
      AND (p_branch_id IS NULL OR jel.branch_id = p_branch_id)
  ),
  own AS (
    SELECT t.*,
           CASE t.line_role
             WHEN 'current_year_earnings' THEN COALESCE((SELECT e.opening_amount FROM earnings e), 0)
             ELSE COALESCE(mp.opening_amount, 0) END AS own_opening,
           CASE t.line_role
             WHEN 'current_year_earnings' THEN COALESCE((SELECT e.movement_amount FROM earnings e), 0)
             ELSE COALESCE(mp.movement_amount, 0) END AS own_movement
    FROM tree t
    LEFT JOIN mapped mp ON mp.fs_structure_id = t.id
  ),
  -- A subtotal is the sum of everything beneath it. The hierarchy already says
  -- what a line totals, so no line ever needs a formula.
  rolled AS (
    SELECT o.id, o.line_code, o.line_label, o.parent_id, o.display_order,
           o.is_subtotal, o.line_role, o.depth,
           o.own_opening + COALESCE((
             SELECT SUM(d.own_opening) FROM own d
             WHERE d.id <> o.id AND fn_fs_line_is_descendant(d.parent_id, o.id)
           ), 0) AS opening_amount,
           o.own_movement + COALESCE((
             SELECT SUM(d.own_movement) FROM own d
             WHERE d.id <> o.id AND fn_fs_line_is_descendant(d.parent_id, o.id)
           ), 0) AS movement_amount
    FROM own o
  )
  SELECT r.line_code::TEXT,
         r.line_label::TEXT,
         (SELECT p.line_code FROM fs_structure p WHERE p.id = r.parent_id)::TEXT,
         r.depth,
         r.line_role::TEXT,
         r.is_subtotal,
         r.display_order,
         ROUND(r.opening_amount, 2)::NUMERIC(18,2),
         ROUND(r.movement_amount, 2)::NUMERIC(18,2),
         ROUND(r.opening_amount + r.movement_amount, 2)::NUMERIC(18,2)
  FROM rolled r
  ORDER BY r.display_order, r.line_code;
END;
$function$;

COMMENT ON FUNCTION public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID, DATE) IS
  'The single financial-statement reporting entry point. Returns opening/movement/closing per governed line: the position reads closing, comprehensive income and cash flows read movement, changes in equity reads all three. Closing journals are excluded from the income statement and the cash flow statement and included in the position and in equity, because a closed year must still show the revenue it earned and the cash it generated. p_presentation_asof re-presents a prior period on the current account mapping. Reads the ledger; writes nothing.';

REVOKE ALL ON FUNCTION public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID, DATE) TO authenticated, service_role;

-- ── 3. Which period is the comparative? ───────────────────────────────────────
-- Answered from the company's own fiscal calendar, not from the browser's idea
-- of last year. Returns data rather than raising, because "there is no prior
-- year yet" is a normal answer for a company in its first year and the screen
-- has to say so plainly.

CREATE OR REPLACE FUNCTION public.fn_resolve_comparative_period(
  p_company_id   UUID,
  p_period_start DATE,
  p_period_end   DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_fy          fiscal_years%ROWTYPE;
  v_prior       fiscal_years%ROWTYPE;
  v_start       DATE;
  v_end         DATE;
  v_pn_from     INTEGER;
  v_pn_to       INTEGER;
  v_basis       TEXT;
  v_activity    BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_period_end < p_period_start THEN
    RAISE EXCEPTION 'Period end cannot be before period start.';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years
  WHERE company_id = p_company_id
    AND start_date <= p_period_end AND end_date >= p_period_end
  ORDER BY start_date DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'available', false,
      'reason', format('No fiscal year covers %s, so there is nothing to compare against.', p_period_end));
  END IF;

  IF p_period_start < v_fy.start_date THEN
    RETURN jsonb_build_object(
      'available', false,
      'fiscal_year_name', v_fy.year_name,
      'reason', format(
        'The reporting period %s to %s crosses a fiscal-year boundary (%s begins %s). Report within one fiscal year to get a comparative.',
        p_period_start, p_period_end, v_fy.year_name, v_fy.start_date));
  END IF;

  SELECT * INTO v_prior FROM fiscal_years
  WHERE company_id = p_company_id AND end_date < v_fy.start_date
  ORDER BY end_date DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'available', false,
      'fiscal_year_name', v_fy.year_name,
      'reason', format('%s is the earliest fiscal year on record, so no prior comparable period exists.', v_fy.year_name));
  END IF;

  IF v_prior.start_date = (v_fy.start_date - INTERVAL '1 year')::DATE THEN
    -- The ordinary case: consecutive twelve-month years. Shifting by a calendar
    -- year lands on the same month and day, which is what an accountant means by
    -- the comparable period, and it handles February correctly.
    v_start := GREATEST(v_prior.start_date, (p_period_start - INTERVAL '1 year')::DATE);
    v_end   := LEAST(v_prior.end_date,      (p_period_end   - INTERVAL '1 year')::DATE);
    v_basis := 'calendar_year_offset';
  ELSE
    -- An irregular calendar — a short first year, or a gap between years. Fall
    -- back to the fiscal period NUMBERS the current range covers and take the
    -- same numbers in the prior year.
    SELECT MIN(period_number), MAX(period_number) INTO v_pn_from, v_pn_to
    FROM fiscal_periods
    WHERE company_id = p_company_id AND fiscal_year_id = v_fy.id
      AND end_date >= p_period_start AND start_date <= p_period_end;

    IF v_pn_from IS NULL THEN
      RETURN jsonb_build_object(
        'available', false,
        'fiscal_year_name', v_fy.year_name,
        'prior_fiscal_year_name', v_prior.year_name,
        'reason', 'The reporting period covers no fiscal period, so the comparable period cannot be located.');
    END IF;

    SELECT MIN(start_date), MAX(end_date) INTO v_start, v_end
    FROM fiscal_periods
    WHERE company_id = p_company_id AND fiscal_year_id = v_prior.id
      AND period_number BETWEEN v_pn_from AND v_pn_to;

    IF v_start IS NULL THEN
      RETURN jsonb_build_object(
        'available', false,
        'fiscal_year_name', v_fy.year_name,
        'prior_fiscal_year_name', v_prior.year_name,
        'reason', format('%s has no periods %s to %s to compare against.', v_prior.year_name, v_pn_from, v_pn_to));
    END IF;
    v_basis := 'fiscal_period_number';
  END IF;

  IF v_end < v_start THEN
    RETURN jsonb_build_object(
      'available', false,
      'fiscal_year_name', v_fy.year_name,
      'prior_fiscal_year_name', v_prior.year_name,
      'reason', format('%s does not extend far enough to cover the comparable period.', v_prior.year_name));
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = p_company_id AND status IN ('posted', 'reversed')
      AND je_date BETWEEN v_start AND v_end
  ) INTO v_activity;

  RETURN jsonb_build_object(
    'available', true,
    'basis', v_basis,
    'period_start', p_period_start,
    'period_end', p_period_end,
    'fiscal_year_id', v_fy.id,
    'fiscal_year_name', v_fy.year_name,
    'fiscal_year_status', v_fy.status,
    'prior_period_start', v_start,
    'prior_period_end', v_end,
    'prior_fiscal_year_id', v_prior.id,
    'prior_fiscal_year_name', v_prior.year_name,
    'prior_fiscal_year_status', v_prior.status,
    'prior_year_closed', (v_prior.status = 'closed'),
    'prior_has_activity', v_activity);
END;
$function$;

COMMENT ON FUNCTION public.fn_resolve_comparative_period(UUID, DATE, DATE) IS
  'Resolves the prior comparable period from the company''s own fiscal calendar: a calendar-year offset for consecutive twelve-month years, otherwise the same fiscal period numbers in the prior year. Returns available=false with a readable reason rather than raising, because a company in its first year legitimately has no comparative. Reports the prior year''s close status so the reader knows whether the comparative is drawn from final or still-moving books.';

REVOKE ALL ON FUNCTION public.fn_resolve_comparative_period(UUID, DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolve_comparative_period(UUID, DATE, DATE) TO authenticated, service_role;

-- ── 4. The comparative statement ──────────────────────────────────────────────
-- Two calls to the one reporting entry point, joined on the governed line code.
-- The prior call is told to present itself on the CURRENT mapping, so a
-- re-presentation restates the comparative instead of leaving two statements
-- that cannot be read side by side.

CREATE OR REPLACE FUNCTION public.fn_comparative_financial_statement_report(
  p_company_id   UUID,
  p_statement    TEXT,
  p_period_start DATE,
  p_period_end   DATE,
  p_prior_start  DATE DEFAULT NULL,
  p_prior_end    DATE DEFAULT NULL,
  p_branch_id    UUID DEFAULT NULL
)
RETURNS TABLE (
  line_code         TEXT,
  line_label        TEXT,
  parent_code       TEXT,
  depth             INTEGER,
  line_role         TEXT,
  is_subtotal       BOOLEAN,
  display_order     INTEGER,
  comparison_basis  TEXT,
  current_opening   NUMERIC(18,2),
  current_movement  NUMERIC(18,2),
  current_closing   NUMERIC(18,2),
  prior_opening     NUMERIC(18,2),
  prior_movement    NUMERIC(18,2),
  prior_closing     NUMERIC(18,2),
  current_amount    NUMERIC(18,2),
  prior_amount      NUMERIC(18,2),
  variance_amount   NUMERIC(18,2),
  variance_percent  NUMERIC(12,2)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_resolved    JSONB;
  v_prior_start DATE := p_prior_start;
  v_prior_end   DATE := p_prior_end;
  v_basis       TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_statement NOT IN ('balance_sheet', 'income_statement', 'cash_flow', 'equity_statement') THEN
    RAISE EXCEPTION 'Unknown financial statement %', p_statement USING ERRCODE = '22023';
  END IF;

  -- The comparison column is a property of the statement, not of the screen: a
  -- position compares balances, a performance statement compares movements.
  v_basis := CASE
    WHEN p_statement IN ('balance_sheet', 'equity_statement') THEN 'closing'
    ELSE 'movement'
  END;

  IF v_prior_start IS NULL OR v_prior_end IS NULL THEN
    v_resolved := fn_resolve_comparative_period(p_company_id, p_period_start, p_period_end);
    IF NOT (v_resolved->>'available')::BOOLEAN THEN
      RAISE EXCEPTION 'No comparative period is available: %', v_resolved->>'reason'
        USING ERRCODE = 'no_data_found';
    END IF;
    v_prior_start := (v_resolved->>'prior_period_start')::DATE;
    v_prior_end   := (v_resolved->>'prior_period_end')::DATE;
  END IF;

  RETURN QUERY
  WITH
  cur AS (
    SELECT * FROM fn_financial_statement_report(
      p_company_id, p_statement, p_period_start, p_period_end, p_branch_id, p_period_end)
  ),
  pri AS (
    -- Presented as of the CURRENT period end: same structure, same mapping.
    SELECT * FROM fn_financial_statement_report(
      p_company_id, p_statement, v_prior_start, v_prior_end, p_branch_id, p_period_end)
  ),
  joined AS (
    SELECT
      COALESCE(c.line_code, p.line_code)         AS line_code,
      COALESCE(c.line_label, p.line_label)       AS line_label,
      COALESCE(c.parent_code, p.parent_code)     AS parent_code,
      COALESCE(c.depth, p.depth)                 AS depth,
      COALESCE(c.line_role, p.line_role)         AS line_role,
      COALESCE(c.is_subtotal, p.is_subtotal)     AS is_subtotal,
      COALESCE(c.display_order, p.display_order) AS display_order,
      COALESCE(c.opening_amount, 0)              AS current_opening,
      COALESCE(c.movement_amount, 0)             AS current_movement,
      COALESCE(c.closing_amount, 0)              AS current_closing,
      COALESCE(p.opening_amount, 0)              AS prior_opening,
      COALESCE(p.movement_amount, 0)             AS prior_movement,
      COALESCE(p.closing_amount, 0)              AS prior_closing
    FROM cur c
    FULL OUTER JOIN pri p ON p.line_code = c.line_code
  ),
  compared AS (
    SELECT j.*,
           CASE WHEN v_basis = 'closing' THEN j.current_closing ELSE j.current_movement END AS cur_amt,
           CASE WHEN v_basis = 'closing' THEN j.prior_closing   ELSE j.prior_movement   END AS pri_amt
    FROM joined j
  )
  SELECT
    x.line_code::TEXT, x.line_label::TEXT, x.parent_code::TEXT, x.depth,
    x.line_role::TEXT, x.is_subtotal, x.display_order, v_basis::TEXT,
    ROUND(x.current_opening, 2)::NUMERIC(18,2),
    ROUND(x.current_movement, 2)::NUMERIC(18,2),
    ROUND(x.current_closing, 2)::NUMERIC(18,2),
    ROUND(x.prior_opening, 2)::NUMERIC(18,2),
    ROUND(x.prior_movement, 2)::NUMERIC(18,2),
    ROUND(x.prior_closing, 2)::NUMERIC(18,2),
    ROUND(x.cur_amt, 2)::NUMERIC(18,2),
    ROUND(x.pri_amt, 2)::NUMERIC(18,2),
    ROUND(x.cur_amt - x.pri_amt, 2)::NUMERIC(18,2),
    -- A percentage against a zero base is not a large percentage, it is no
    -- percentage. NULL says so; a number would not.
    CASE WHEN ABS(x.pri_amt) >= 0.005
         THEN ROUND((x.cur_amt - x.pri_amt) / ABS(x.pri_amt) * 100, 2)
         ELSE NULL END::NUMERIC(12,2)
  FROM compared x
  ORDER BY x.display_order, x.line_code;
END;
$function$;

COMMENT ON FUNCTION public.fn_comparative_financial_statement_report(UUID, TEXT, DATE, DATE, DATE, DATE, UUID) IS
  'Current period and prior comparable period side by side per governed statement line, with amount and percentage variance. Calls fn_financial_statement_report twice — there is no second reporting engine — and presents the prior period on the CURRENT account mapping so the two columns are comparable. Raises with the resolver''s reason when no comparative period exists and none was supplied.';

REVOKE ALL ON FUNCTION public.fn_comparative_financial_statement_report(UUID, TEXT, DATE, DATE, DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_comparative_financial_statement_report(UUID, TEXT, DATE, DATE, DATE, DATE, UUID) TO authenticated, service_role;

-- ── 5. The accounts behind a statement line ───────────────────────────────────
-- Drill-down and supporting schedule are the same question, so they are the same
-- function. Signs through fn_fs_presentation_sign and applies the same
-- closing-entry rule, so the accounts listed here always add up to the line they
-- were opened from.

CREATE OR REPLACE FUNCTION public.fn_financial_statement_line_accounts(
  p_company_id   UUID,
  p_statement    TEXT,
  p_line_code    TEXT,
  p_period_start DATE,
  p_period_end   DATE,
  p_prior_start  DATE DEFAULT NULL,
  p_prior_end    DATE DEFAULT NULL,
  p_branch_id    UUID DEFAULT NULL
)
RETURNS TABLE (
  account_id       UUID,
  account_code     TEXT,
  account_name     TEXT,
  account_type     TEXT,
  comparison_basis TEXT,
  current_amount   NUMERIC(18,2),
  prior_amount     NUMERIC(18,2),
  variance_amount  NUMERIC(18,2),
  variance_percent NUMERIC(12,2)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_line_id         UUID;
  v_basis           TEXT;
  v_exclude_closing BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_statement NOT IN ('balance_sheet', 'income_statement', 'cash_flow', 'equity_statement') THEN
    RAISE EXCEPTION 'Unknown financial statement %', p_statement USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_line_id FROM fs_structure
  WHERE company_id = p_company_id AND statement = p_statement AND line_code = p_line_code;
  IF v_line_id IS NULL THEN
    RAISE EXCEPTION 'Statement line % does not exist on the % of this company', p_line_code, p_statement;
  END IF;

  v_basis := CASE
    WHEN p_statement IN ('balance_sheet', 'equity_statement') THEN 'closing'
    ELSE 'movement'
  END;
  v_exclude_closing := (p_statement IN ('income_statement', 'cash_flow'));

  RETURN QUERY
  WITH
  -- Every account mapped to this line, or to any line beneath it, so opening a
  -- subtotal shows the accounts that make it up.
  scoped AS (
    SELECT m.account_id, coa.account_code, coa.account_name, coa.account_type,
           fn_fs_presentation_sign(p_statement, coa.is_cash_equivalent, coa.normal_balance) AS sgn
    FROM account_fs_map m
    JOIN chart_of_accounts coa ON coa.id = m.account_id
    JOIN fs_structure f ON f.id = m.fs_structure_id
    WHERE m.company_id = p_company_id
      AND m.statement = p_statement
      AND (m.effective_from IS NULL OR m.effective_from <= p_period_end)
      AND (m.effective_to IS NULL OR m.effective_to >= p_period_end)
      AND (f.id = v_line_id OR fn_fs_line_is_descendant(f.parent_id, v_line_id))
  ),
  amounts AS (
    SELECT s.account_id, s.account_code, s.account_name, s.account_type,
           SUM(CASE
                 WHEN v_basis = 'closing' AND je.je_date <= p_period_end
                   THEN jel.debit_amount - jel.credit_amount
                 WHEN v_basis = 'movement' AND je.je_date BETWEEN p_period_start AND p_period_end
                   THEN jel.debit_amount - jel.credit_amount
                 ELSE 0 END) * MIN(s.sgn) AS cur_amt,
           SUM(CASE
                 WHEN p_prior_end IS NULL THEN 0
                 WHEN v_basis = 'closing' AND je.je_date <= p_prior_end
                   THEN jel.debit_amount - jel.credit_amount
                 WHEN v_basis = 'movement' AND p_prior_start IS NOT NULL
                      AND je.je_date BETWEEN p_prior_start AND p_prior_end
                   THEN jel.debit_amount - jel.credit_amount
                 ELSE 0 END) * MIN(s.sgn) AS pri_amt
    FROM scoped s
    LEFT JOIN journal_entry_lines jel
      ON jel.account_id = s.account_id
     AND jel.company_id = p_company_id
     AND (p_branch_id IS NULL OR jel.branch_id = p_branch_id)
    LEFT JOIN journal_entries je
      ON je.id = jel.je_id
     AND je.status IN ('posted', 'reversed')
     AND (NOT v_exclude_closing OR je.entry_class <> 'closing')
    GROUP BY s.account_id, s.account_code, s.account_name, s.account_type
  )
  SELECT a.account_id, a.account_code::TEXT, a.account_name::TEXT, a.account_type::TEXT,
         v_basis::TEXT,
         ROUND(COALESCE(a.cur_amt, 0), 2)::NUMERIC(18,2),
         ROUND(COALESCE(a.pri_amt, 0), 2)::NUMERIC(18,2),
         ROUND(COALESCE(a.cur_amt, 0) - COALESCE(a.pri_amt, 0), 2)::NUMERIC(18,2),
         CASE WHEN ABS(COALESCE(a.pri_amt, 0)) >= 0.005
              THEN ROUND((COALESCE(a.cur_amt, 0) - COALESCE(a.pri_amt, 0))
                         / ABS(COALESCE(a.pri_amt, 0)) * 100, 2)
              ELSE NULL END::NUMERIC(12,2)
  FROM amounts a
  WHERE ABS(COALESCE(a.cur_amt, 0)) >= 0.005 OR ABS(COALESCE(a.pri_amt, 0)) >= 0.005
  ORDER BY a.account_code;
END;
$function$;

COMMENT ON FUNCTION public.fn_financial_statement_line_accounts(UUID, TEXT, TEXT, DATE, DATE, DATE, DATE, UUID) IS
  'The accounts behind one governed statement line — the line''s own accounts plus every account beneath it — with current and prior amounts on the statement''s comparison basis. Serves both the statement drill-down and the supporting schedules in the notes, and signs through fn_fs_presentation_sign so the accounts always add up to the line they were opened from.';

REVOKE ALL ON FUNCTION public.fn_financial_statement_line_accounts(UUID, TEXT, TEXT, DATE, DATE, DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_financial_statement_line_accounts(UUID, TEXT, TEXT, DATE, DATE, DATE, DATE, UUID) TO authenticated, service_role;

-- ── 6. Basic statement notes ──────────────────────────────────────────────────
-- Rows, not prose. Every item names the configuration or the ledger fact it came
-- from and says whether that fact is actually configured, so an unset policy
-- reads as unset instead of silently reading as a default. This is deliberately
-- not a disclosure system: the last item of the basis note says so.

CREATE OR REPLACE FUNCTION public.fn_financial_statement_notes(
  p_company_id   UUID,
  p_period_start DATE,
  p_period_end   DATE,
  p_prior_start  DATE DEFAULT NULL,
  p_prior_end    DATE DEFAULT NULL
)
RETURNS TABLE (
  note_code     TEXT,
  note_title    TEXT,
  note_order    INTEGER,
  item_order    INTEGER,
  item_label    TEXT,
  item_value    TEXT,
  item_source   TEXT,
  is_configured BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_co        companies%ROWTYPE;
  v_rdo       TEXT;
  v_fy        fiscal_years%ROWTYPE;
  v_prior_fy  fiscal_years%ROWTYPE;
  v_inv       company_inventory_config%ROWTYPE;
  v_cmp       JSONB;
  v_ps        DATE := p_prior_start;
  v_pe        DATE := p_prior_end;
  v_closed_at DATE;
  v_close_je  TEXT;
  v_locked    INTEGER;
  v_periods   INTEGER;
  v_lines     INTEGER;
  v_mapped    INTEGER;
  v_postable  INTEGER;
  v_je_count  INTEGER;
  v_oob       NUMERIC(18,2);
  v_prior_oob NUMERIC(18,2);
  v_depr      INTEGER;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  SELECT * INTO v_co FROM companies WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Company % not found', p_company_id;
  END IF;

  SELECT r.rdo_code || ' — ' || r.rdo_name INTO v_rdo
  FROM ref_rdo_codes r WHERE r.id = v_co.rdo_id;

  SELECT * INTO v_fy FROM fiscal_years
  WHERE company_id = p_company_id AND start_date <= p_period_end AND end_date >= p_period_end
  ORDER BY start_date DESC LIMIT 1;

  IF v_ps IS NULL OR v_pe IS NULL THEN
    v_cmp := fn_resolve_comparative_period(p_company_id, p_period_start, p_period_end);
    IF (v_cmp->>'available')::BOOLEAN THEN
      v_ps := (v_cmp->>'prior_period_start')::DATE;
      v_pe := (v_cmp->>'prior_period_end')::DATE;
    END IF;
  END IF;

  IF v_ps IS NOT NULL THEN
    SELECT * INTO v_prior_fy FROM fiscal_years
    WHERE company_id = p_company_id AND start_date <= v_pe AND end_date >= v_pe
    ORDER BY start_date DESC LIMIT 1;
  END IF;

  SELECT * INTO v_inv FROM company_inventory_config WHERE company_id = p_company_id;

  SELECT r.effective_date, je.je_number INTO v_closed_at, v_close_je
  FROM fiscal_close_runs r
  LEFT JOIN journal_entries je ON je.id = r.closing_je_id
  WHERE r.company_id = p_company_id AND r.fiscal_year_id = v_fy.id
    AND r.close_type = 'year' AND r.action = 'close' AND r.superseded_by_id IS NULL;

  SELECT COUNT(*) FILTER (WHERE is_locked), COUNT(*) INTO v_locked, v_periods
  FROM fiscal_periods WHERE company_id = p_company_id AND fiscal_year_id = v_fy.id;

  SELECT COUNT(*) INTO v_lines FROM fs_structure WHERE company_id = p_company_id;
  SELECT COUNT(DISTINCT account_id) INTO v_mapped FROM account_fs_map WHERE company_id = p_company_id;
  SELECT COUNT(*) INTO v_postable FROM chart_of_accounts
  WHERE company_id = p_company_id AND is_postable AND is_active;

  SELECT COUNT(*) INTO v_je_count FROM journal_entries
  WHERE company_id = p_company_id AND status IN ('posted', 'reversed')
    AND je_date BETWEEN p_period_start AND p_period_end;

  SELECT COALESCE(ROUND(SUM(jel.debit_amount - jel.credit_amount), 2), 0) INTO v_oob
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
  WHERE jel.company_id = p_company_id AND je.status IN ('posted', 'reversed')
    AND je.je_date <= p_period_end;

  IF v_pe IS NOT NULL THEN
    SELECT COALESCE(ROUND(SUM(jel.debit_amount - jel.credit_amount), 2), 0) INTO v_prior_oob
    FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE jel.company_id = p_company_id AND je.status IN ('posted', 'reversed')
      AND je.je_date <= v_pe;
  END IF;

  SELECT COUNT(*) INTO v_depr FROM asset_depreciation_entries
  WHERE company_id = p_company_id AND entry_date BETWEEN p_period_start AND p_period_end;

  RETURN QUERY
  SELECT * FROM (VALUES
    -- ── Note 1: who the statements belong to ─────────────────────────────────
    ('NOTE-01', 'Company Information', 1, 1, 'Registered name', v_co.registered_name, 'companies.registered_name', true),
    ('NOTE-01', 'Company Information', 1, 2, 'Trade name', COALESCE(v_co.trade_name, 'Not set'), 'companies.trade_name', v_co.trade_name IS NOT NULL),
    ('NOTE-01', 'Company Information', 1, 3, 'Entity type', INITCAP(REPLACE(v_co.entity_type, '_', ' ')), 'companies.entity_type', true),
    ('NOTE-01', 'Company Information', 1, 4, 'Taxpayer identification number', v_co.tin, 'companies.tin', true),
    ('NOTE-01', 'Company Information', 1, 5, 'Revenue district office', COALESCE(v_rdo, 'Not set'), 'companies.rdo_id', v_rdo IS NOT NULL),
    ('NOTE-01', 'Company Information', 1, 6, 'Registered address',
      CONCAT_WS(', ', NULLIF(v_co.address_line_1, ''), NULLIF(v_co.address_line_2, ''), v_co.city, v_co.province, v_co.zip_code),
      'companies address fields', true),
    ('NOTE-01', 'Company Information', 1, 7, 'Line of business', v_co.line_of_business, 'companies.line_of_business', true),
    ('NOTE-01', 'Company Information', 1, 8, 'PSIC code', COALESCE(v_co.psic_code, 'Not set'), 'companies.psic_code', v_co.psic_code IS NOT NULL),
    ('NOTE-01', 'Company Information', 1, 9, 'BIR registration date', COALESCE(v_co.bir_reg_date::TEXT, 'Not set'), 'companies.bir_reg_date', v_co.bir_reg_date IS NOT NULL),
    ('NOTE-01', 'Company Information', 1, 10, 'CAS permit number', COALESCE(v_co.cas_permit_no, 'Not set'), 'companies.cas_permit_no', v_co.cas_permit_no IS NOT NULL),
    ('NOTE-01', 'Company Information', 1, 11, 'Authorised signatory',
      v_co.signatory_name || ' — ' || v_co.signatory_position, 'companies.signatory_name / signatory_position', true),

    -- ── Note 2: what period, and against what ────────────────────────────────
    ('NOTE-02', 'Reporting Period', 2, 1, 'Current reporting period',
      p_period_start::TEXT || ' to ' || p_period_end::TEXT, 'Report parameters', true),
    ('NOTE-02', 'Reporting Period', 2, 2, 'Fiscal year',
      COALESCE(v_fy.year_name, 'No fiscal year covers this period'), 'fiscal_years', v_fy.id IS NOT NULL),
    ('NOTE-02', 'Reporting Period', 2, 3, 'Fiscal year status',
      COALESCE(INITCAP(v_fy.status), 'Not applicable'), 'fiscal_years.status', v_fy.id IS NOT NULL),
    ('NOTE-02', 'Reporting Period', 2, 4, 'Accounting periods closed',
      COALESCE(v_locked::TEXT, '0') || ' of ' || COALESCE(v_periods::TEXT, '0'), 'fiscal_periods.is_locked', true),
    ('NOTE-02', 'Reporting Period', 2, 5, 'Year-end close',
      CASE WHEN v_closed_at IS NULL THEN 'The year has not been closed'
           ELSE 'Closed ' || v_closed_at::TEXT || COALESCE(' by journal ' || v_close_je, '') END,
      'fiscal_close_runs', v_closed_at IS NOT NULL),
    ('NOTE-02', 'Reporting Period', 2, 6, 'Comparative period',
      CASE WHEN v_ps IS NULL THEN COALESCE(v_cmp->>'reason', 'No comparative period is available')
           ELSE v_ps::TEXT || ' to ' || v_pe::TEXT END,
      'fn_resolve_comparative_period', v_ps IS NOT NULL),
    ('NOTE-02', 'Reporting Period', 2, 7, 'Comparative fiscal year',
      CASE WHEN v_prior_fy.id IS NULL THEN 'Not applicable'
           ELSE v_prior_fy.year_name || ' (' || v_prior_fy.status || ')' END,
      'fiscal_years', v_prior_fy.id IS NOT NULL),

    -- ── Note 3: on what basis ────────────────────────────────────────────────
    ('NOTE-03', 'Basis of Preparation', 3, 1, 'Measurement basis', 'Historical cost',
      'Every transaction is recorded at its transaction amount; PXL has no revaluation or fair-value measurement.', true),
    ('NOTE-03', 'Basis of Preparation', 3, 2, 'Recognition basis', 'Accrual',
      'Revenue and expenses are recognised when the source document posts to the general ledger, not when cash moves.', true),
    ('NOTE-03', 'Basis of Preparation', 3, 3, 'Functional currency', v_co.functional_currency_code, 'companies.functional_currency_code', true),
    ('NOTE-03', 'Basis of Preparation', 3, 4, 'Presentation currency', v_co.reporting_currency_code, 'companies.reporting_currency_code', true),
    ('NOTE-03', 'Basis of Preparation', 3, 5, 'Reporting calendar',
      CASE WHEN v_co.accounting_period = 'calendar' THEN 'Calendar year (January to December)'
           ELSE 'Fiscal year beginning month ' || COALESCE(v_co.fiscal_start_month::TEXT, 'not set') END,
      'companies.accounting_period / fiscal_start_month', true),
    ('NOTE-03', 'Basis of Preparation', 3, 6, 'Statement presentation',
      v_lines::TEXT || ' governed statement lines; ' || v_mapped::TEXT || ' of ' || v_postable::TEXT || ' postable accounts mapped',
      'fs_structure / account_fs_map — presentation is configuration, not code', v_lines > 0),
    ('NOTE-03', 'Basis of Preparation', 3, 7, 'Comparative information',
      'Comparative amounts are presented on the current statement structure and account mapping.',
      'fn_comparative_financial_statement_report presents the prior period as of the current period end', true),
    ('NOTE-03', 'Basis of Preparation', 3, 8, 'Scope of these notes',
      'System-generated from configured data. This is not a complete PFRS or PFRS for SMEs disclosure set and does not replace the notes an accountant must prepare.',
      'Product scope — see the Product Backlog', true),

    -- ── Note 4: the policies the system actually applies ─────────────────────
    ('NOTE-04', 'Significant Accounting Policies', 4, 1, 'Inventory costing',
      CASE WHEN v_inv.id IS NULL THEN 'Not configured'
           ELSE INITCAP(REPLACE(v_inv.default_costing_method, '_', ' ')) END,
      'company_inventory_config.default_costing_method', v_inv.id IS NOT NULL),
    ('NOTE-04', 'Significant Accounting Policies', 4, 2, 'Negative stock',
      CASE WHEN v_inv.id IS NULL THEN 'Not configured'
           ELSE INITCAP(v_inv.negative_stock_policy) END,
      'company_inventory_config.negative_stock_policy', v_inv.id IS NOT NULL),
    ('NOTE-04', 'Significant Accounting Policies', 4, 3, 'Revenue recognition',
      'Recognised when the sales document posts. A delivery relieves inventory into Goods Delivered Not Invoiced; the invoice recognises the revenue and that cost together.',
      'fn_post_sales_invoice / fn_post_delivery_receipt', true),
    ('NOTE-04', 'Significant Accounting Policies', 4, 4, 'Value-added tax',
      CASE WHEN v_co.tax_registration = 'vat' THEN 'VAT-registered; output and input VAT are recognised on the document date at the rate in force on that date.'
           ELSE INITCAP(REPLACE(v_co.tax_registration, '_', ' ')) || ' — no output VAT is recognised.' END,
      'companies.tax_registration / fn_resolve_vat_code', true),
    ('NOTE-04', 'Significant Accounting Policies', 4, 5, 'Withholding tax on purchases',
      CASE WHEN v_co.ap_ewt_recognition_policy = 'accrual_at_source' THEN 'Recognised when the payable is recorded'
           ELSE 'Recognised on payment' END,
      'companies.ap_ewt_recognition_policy', true),
    ('NOTE-04', 'Significant Accounting Policies', 4, 6, 'Depreciation',
      CASE WHEN v_depr = 0 THEN 'No depreciation has been recognised in this period'
           ELSE v_depr::TEXT || ' depreciation entries recognised in the period' END,
      'asset_depreciation_entries', v_depr > 0),
    ('NOTE-04', 'Significant Accounting Policies', 4, 7, 'Income tax',
      'Not computed. PXL recognises no current or deferred income tax provision.',
      'No income-tax module exists — see the Product Backlog', false),

    -- ── Note 5: where the numbers come from ──────────────────────────────────
    ('NOTE-05', 'Supporting Schedules', 5, 1, 'Drill-down',
      'Every statement line opens to the accounts mapped to it, and every account opens to its detailed ledger.',
      'fn_financial_statement_line_accounts', true),
    ('NOTE-05', 'Supporting Schedules', 5, 2, 'Journal entries in the period',
      v_je_count::TEXT, 'journal_entries posted or reversed within the reporting period', true),
    ('NOTE-05', 'Supporting Schedules', 5, 3, 'Trial balance agreement, current period',
      TO_CHAR(v_oob, 'FM999999999990.00') || ' out of balance',
      'Sum of debits less credits over all posted lines to the period end', ABS(v_oob) < 0.005),
    ('NOTE-05', 'Supporting Schedules', 5, 4, 'Trial balance agreement, comparative period',
      CASE WHEN v_prior_oob IS NULL THEN 'No comparative period'
           ELSE TO_CHAR(v_prior_oob, 'FM999999999990.00') || ' out of balance' END,
      'Sum of debits less credits over all posted lines to the comparative period end',
      v_prior_oob IS NOT NULL AND ABS(v_prior_oob) < 0.005),
    ('NOTE-05', 'Supporting Schedules', 5, 5, 'Closing entries in the statements',
      'Excluded from comprehensive income and cash flows; included in the position and in changes in equity.',
      'fn_financial_statement_report — a closed year still shows the revenue it earned', true)
  ) AS t(note_code, note_title, note_order, item_order, item_label, item_value, item_source, is_configured)
  ORDER BY t.note_order, t.item_order;
END;
$function$;

COMMENT ON FUNCTION public.fn_financial_statement_notes(UUID, DATE, DATE, DATE, DATE) IS
  'Basic statement notes as rows: company information, reporting period, basis of preparation, significant accounting policies and supporting schedules. Every item names the configuration or ledger fact behind it and flags whether that fact is configured, so an unset policy reads as unset rather than as a default. Deliberately not a complete disclosure set — the basis note says so in its own text.';

REVOKE ALL ON FUNCTION public.fn_financial_statement_notes(UUID, DATE, DATE, DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_financial_statement_notes(UUID, DATE, DATE, DATE, DATE) TO authenticated, service_role;
