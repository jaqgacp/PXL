-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery Plan Phase 5.7 — Financial Statement presentation.
--
-- THE GAP
--   The trial balance was correct and out of balance by ₱0.00 in every company,
--   and yet PXL could not produce a signed-off financial statement. `fs_structure`
--   and `account_fs_map` had existed since the schema was laid down and had
--   **never held a single row**, so no account was mapped to any statement line.
--   The four Financial Statement screens compensated by grouping postable
--   accounts by `account_type` in the browser — a flat list of every account
--   under Assets / Liabilities / Equity, with the layout hardcoded in TSX. That
--   is a trial balance with headings, not a Statement of Financial Position, and
--   a change in presentation meant a change in a React component.
--
-- WHAT THIS CHANGES
--   Presentation becomes configuration, held in the database, per company:
--
--     chart_of_accounts  →  account_fs_map  →  fs_structure  →  the statement
--
--   `fs_structure` holds the governed line hierarchy for each statement.
--   `account_fs_map` binds each account to exactly ONE line per statement —
--   already enforced by `uq_account_fs_map_active`. A subtotal is a parent line
--   and its amount is the plain sum of its children, so there is no formula
--   language to maintain and no layout in code.
--
--   `fn_financial_statement_report` is the single reporting entry point. It
--   returns, for every line of the requested statement, an opening balance, a
--   movement and a closing balance. Four presentations fall out of that one
--   contract: the Statement of Financial Position reads closing, the Statement
--   of Comprehensive Income reads movement, the Statement of Changes in Equity
--   reads all three, and the Statement of Cash Flows reads movement grouped by
--   the governed cash-flow classification.
--
-- WHAT THE COA ALREADY CARRIED
--   Almost everything: `fs_statement` (generated), `fs_group`, `fs_subgroup`,
--   `cash_flow_category`, `is_control_account`, `is_operating_expense`. Only two
--   pieces of structure were genuinely missing and both are added here:
--
--     * `chart_of_accounts.is_cash_equivalent` — a cash flow statement must know
--       which accounts ARE cash. `cash_flow_category` classifies a movement's
--       *purpose*; nothing said "this account is the cash being reconciled to".
--     * `fs_structure.line_role` — a line is a detail line, a subtotal, or one
--       of the two lines an account can never be mapped to: current-year
--       earnings (undistributed profit before closing) and the cash
--       reconciliation. Roles, not formulas.
--
--   `statement` also gains `equity_statement`, because the Statement of Changes
--   in Equity is one of the four the pilot must sign and it was not in the enum.
--
-- WHAT THIS DOES NOT CHANGE
--   No posting logic, no journal, no kernel, no tax. Reporting reads the ledger
--   and never writes it. Nothing here changes what a transaction does; a company
--   that re-maps its statements re-presents the same posted numbers, which is
--   the point — local GAAP and IFRS presentation changes must not touch posting.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. The two missing pieces of COA/structure metadata ────────────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS is_cash_equivalent BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE coa_template_lines
  ADD COLUMN IF NOT EXISTS is_cash_equivalent BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN chart_of_accounts.is_cash_equivalent IS
  'This account IS cash or a cash equivalent. The Statement of Cash Flows reconciles to the movement in these accounts; every other account explains that movement. Distinct from cash_flow_category, which classifies why a movement happened.';

UPDATE coa_template_lines SET is_cash_equivalent = true
WHERE account_code IN ('1010', '1020') AND is_cash_equivalent = false;

-- Existing companies: the accounts the company already treats as cash.
UPDATE chart_of_accounts c SET is_cash_equivalent = true
WHERE c.is_cash_equivalent = false
  AND c.account_type = 'asset'
  AND (
    EXISTS (SELECT 1 FROM company_accounting_config cfg
             WHERE cfg.company_id = c.company_id AND cfg.default_cash_account_id = c.id)
    OR EXISTS (SELECT 1 FROM account_mapping m
                WHERE m.company_id = c.company_id AND m.key_code = 'CASH_DEFAULT'
                  AND m.account_id = c.id)
    OR c.account_code IN ('1010', '1020')
  );

-- ── 2. The statement enum learns the fourth statement ──────────────────────
ALTER TABLE fs_structure   DROP CONSTRAINT IF EXISTS fs_structure_statement_check;
ALTER TABLE account_fs_map DROP CONSTRAINT IF EXISTS account_fs_map_statement_check;
ALTER TABLE fs_structure ADD CONSTRAINT fs_structure_statement_check
  CHECK (statement IN ('balance_sheet', 'income_statement', 'cash_flow', 'equity_statement'));
ALTER TABLE account_fs_map ADD CONSTRAINT account_fs_map_statement_check
  CHECK (statement IN ('balance_sheet', 'income_statement', 'cash_flow', 'equity_statement'));

ALTER TABLE fs_structure
  ADD COLUMN IF NOT EXISTS line_role TEXT NOT NULL DEFAULT 'detail';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fs_structure_line_role_chk' AND conrelid = 'public.fs_structure'::regclass
  ) THEN
    ALTER TABLE fs_structure ADD CONSTRAINT fs_structure_line_role_chk
      CHECK (line_role IN ('detail', 'subtotal', 'current_year_earnings', 'cash_reconciliation'));
  END IF;
END $$;

COMMENT ON COLUMN fs_structure.line_role IS
  'detail: accounts map here. subtotal: the plain sum of its child lines. current_year_earnings: undistributed profit, computed from income-statement accounts because it is not posted to equity until closing. cash_reconciliation: the cash movement the Statement of Cash Flows must tie to. Roles, not formulas — a subtotal never needs an expression because the hierarchy already says what it totals.';

-- ── 3. Seed the governed default structure for a company ───────────────────
-- Built from the company's own COA vocabulary (`fs_subgroup`), not from a layout
-- written in code. A company that wants a different presentation edits these
-- rows; the report follows whatever is there.
CREATE OR REPLACE FUNCTION public.fn_seed_company_fs_structure(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INTEGER := 0;
  r       RECORD;
  v_id    UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed financial statement structure for company %', p_company_id
      USING ERRCODE = '42501';
  END IF;

  FOR r IN
    SELECT * FROM (VALUES
      -- statement,        line_code,  parent_code, label,                             order, role
      ('balance_sheet',    'BS-A',     NULL,        'ASSETS',                             10, 'subtotal'),
      ('balance_sheet',    'BS-A-CUR', 'BS-A',      'Current Assets',                     20, 'detail'),
      ('balance_sheet',    'BS-A-NON', 'BS-A',      'Non-current Assets',                 30, 'detail'),
      ('balance_sheet',    'BS-A-OTH', 'BS-A',      'Other Assets',                       40, 'detail'),
      ('balance_sheet',    'BS-L',     NULL,        'LIABILITIES',                        50, 'subtotal'),
      ('balance_sheet',    'BS-L-CUR', 'BS-L',      'Current Liabilities',                60, 'detail'),
      ('balance_sheet',    'BS-L-NON', 'BS-L',      'Non-current Liabilities',            70, 'detail'),
      ('balance_sheet',    'BS-L-OTH', 'BS-L',      'Other Liabilities',                  80, 'detail'),
      ('balance_sheet',    'BS-E',     NULL,        'EQUITY',                             90, 'subtotal'),
      ('balance_sheet',    'BS-E-CAP', 'BS-E',      'Contributed Capital and Reserves',  100, 'detail'),
      ('balance_sheet',    'BS-E-CYE', 'BS-E',      'Current Year Earnings',             110, 'current_year_earnings'),

      ('income_statement', 'IS-NI',    NULL,        'NET INCOME',                         10, 'subtotal'),
      ('income_statement', 'IS-GP',    'IS-NI',     'GROSS PROFIT',                       20, 'subtotal'),
      ('income_statement', 'IS-REV',   'IS-GP',     'Revenue',                            30, 'detail'),
      ('income_statement', 'IS-COS',   'IS-GP',     'Cost of Sales',                      40, 'detail'),
      ('income_statement', 'IS-OPEX',  'IS-NI',     'Operating Expenses',                 50, 'detail'),
      ('income_statement', 'IS-OTHI',  'IS-NI',     'Other Income',                       60, 'detail'),
      ('income_statement', 'IS-OTHE',  'IS-NI',     'Other Expenses',                     70, 'detail'),

      ('cash_flow',        'CF-NET',   NULL,        'NET INCREASE (DECREASE) IN CASH',    10, 'subtotal'),
      ('cash_flow',        'CF-OP',    'CF-NET',    'Cash Flows from Operating Activities',20, 'detail'),
      ('cash_flow',        'CF-INV',   'CF-NET',    'Cash Flows from Investing Activities',30, 'detail'),
      ('cash_flow',        'CF-FIN',   'CF-NET',    'Cash Flows from Financing Activities',40, 'detail'),
      ('cash_flow',        'CF-CASH',  NULL,        'Cash and Cash Equivalents',          50, 'cash_reconciliation'),

      ('equity_statement', 'EQ-TOT',   NULL,        'TOTAL EQUITY',                       10, 'subtotal'),
      ('equity_statement', 'EQ-CAP',   'EQ-TOT',    'Contributed Capital and Reserves',   20, 'detail'),
      ('equity_statement', 'EQ-CYE',   'EQ-TOT',    'Current Year Earnings',              30, 'current_year_earnings')
    ) AS t(statement, line_code, parent_code, line_label, display_order, line_role)
    ORDER BY t.statement, t.display_order
  LOOP
    SELECT id INTO v_id FROM fs_structure
    WHERE company_id = p_company_id AND statement = r.statement AND line_code = r.line_code;

    IF v_id IS NULL THEN
      INSERT INTO fs_structure (company_id, statement, line_code, line_label,
                                parent_id, display_order, is_subtotal, line_role,
                                created_by, updated_by)
      VALUES (p_company_id, r.statement, r.line_code, r.line_label,
              (SELECT id FROM fs_structure
                WHERE company_id = p_company_id AND statement = r.statement
                  AND line_code = r.parent_code),
              r.display_order, r.line_role = 'subtotal', r.line_role,
              auth.uid(), auth.uid());
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION public.fn_seed_company_fs_structure(UUID) IS
  'Seeds the governed default statement line hierarchy for a company. Idempotent: an existing line is never overwritten, so an administrator''s re-presentation survives re-seeding.';

REVOKE ALL ON FUNCTION public.fn_seed_company_fs_structure(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_seed_company_fs_structure(UUID) TO authenticated, service_role;

-- ── 4. Map every account to exactly one line per statement ─────────────────
-- Derived from the metadata the account already carries. Never overwrites an
-- existing active mapping: an administrator who re-maps an account keeps it.
CREATE OR REPLACE FUNCTION public.fn_map_company_fs_accounts(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INTEGER := 0;
  a       RECORD;
  v_code  TEXT;
  v_stmt  TEXT;
  v_line  UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to map financial statement accounts for company %', p_company_id
      USING ERRCODE = '42501';
  END IF;

  PERFORM fn_seed_company_fs_structure(p_company_id);

  FOR a IN
    SELECT c.id, c.account_type, c.fs_subgroup, c.fs_statement,
           c.cash_flow_category, c.is_cash_equivalent, c.is_operating_expense,
           c.account_code
    FROM chart_of_accounts c
    WHERE c.company_id = p_company_id
      AND c.is_postable = true
    ORDER BY c.account_code
  LOOP
    -- ── Statement of Financial Position / Comprehensive Income ─────────────
    IF a.fs_statement = 'balance_sheet' THEN
      v_stmt := 'balance_sheet';
      v_code := CASE a.account_type
        WHEN 'asset' THEN CASE
          WHEN a.fs_subgroup = 'Current Assets'     THEN 'BS-A-CUR'
          WHEN a.fs_subgroup = 'Non-current Assets' THEN 'BS-A-NON'
          ELSE 'BS-A-OTH' END
        WHEN 'liability' THEN CASE
          WHEN a.fs_subgroup = 'Current Liabilities'     THEN 'BS-L-CUR'
          WHEN a.fs_subgroup = 'Non-current Liabilities' THEN 'BS-L-NON'
          ELSE 'BS-L-OTH' END
        ELSE 'BS-E-CAP' END;
    ELSE
      v_stmt := 'income_statement';
      v_code := CASE
        WHEN a.account_type = 'revenue' AND a.fs_subgroup = 'Other Income' THEN 'IS-OTHI'
        WHEN a.account_type = 'revenue'                                    THEN 'IS-REV'
        WHEN a.fs_subgroup = 'Cost of Sales'                               THEN 'IS-COS'
        WHEN a.fs_subgroup = 'Operating Expenses' OR a.is_operating_expense THEN 'IS-OPEX'
        ELSE 'IS-OTHE' END;
    END IF;

    SELECT id INTO v_line FROM fs_structure
    WHERE company_id = p_company_id AND statement = v_stmt AND line_code = v_code;
    IF v_line IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM account_fs_map m
      WHERE m.company_id = p_company_id AND m.account_id = a.id
        AND m.statement = v_stmt AND m.effective_to IS NULL
    ) THEN
      INSERT INTO account_fs_map (company_id, account_id, fs_structure_id, statement,
                                  display_order, created_by, updated_by)
      VALUES (p_company_id, a.id, v_line, v_stmt, 0, auth.uid(), auth.uid());
      v_count := v_count + 1;
    END IF;

    -- ── Statement of Cash Flows ────────────────────────────────────────────
    -- Cash accounts are what the statement reconciles TO. Every other account
    -- explains the movement, classified by why it moved: the account's own
    -- cash_flow_category when set, otherwise its balance-sheet position —
    -- working capital is operating, non-current assets investing, long-term
    -- funding and equity financing.
    v_code := CASE
      WHEN a.is_cash_equivalent THEN 'CF-CASH'
      WHEN a.cash_flow_category = 'operating' THEN 'CF-OP'
      WHEN a.cash_flow_category = 'investing' THEN 'CF-INV'
      WHEN a.cash_flow_category = 'financing' THEN 'CF-FIN'
      WHEN a.account_type IN ('revenue', 'expense') THEN 'CF-OP'
      WHEN a.fs_subgroup IN ('Current Assets', 'Current Liabilities') THEN 'CF-OP'
      WHEN a.fs_subgroup = 'Non-current Assets' THEN 'CF-INV'
      WHEN a.account_type = 'equity' OR a.fs_subgroup = 'Non-current Liabilities' THEN 'CF-FIN'
      ELSE 'CF-OP' END;

    SELECT id INTO v_line FROM fs_structure
    WHERE company_id = p_company_id AND statement = 'cash_flow' AND line_code = v_code;
    IF v_line IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM account_fs_map m
      WHERE m.company_id = p_company_id AND m.account_id = a.id
        AND m.statement = 'cash_flow' AND m.effective_to IS NULL
    ) THEN
      INSERT INTO account_fs_map (company_id, account_id, fs_structure_id, statement,
                                  display_order, created_by, updated_by)
      VALUES (p_company_id, a.id, v_line, 'cash_flow', 0, auth.uid(), auth.uid());
      v_count := v_count + 1;
    END IF;

    -- ── Statement of Changes in Equity ─────────────────────────────────────
    IF a.account_type = 'equity' THEN
      SELECT id INTO v_line FROM fs_structure
      WHERE company_id = p_company_id AND statement = 'equity_statement' AND line_code = 'EQ-CAP';
      IF v_line IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM account_fs_map m
        WHERE m.company_id = p_company_id AND m.account_id = a.id
          AND m.statement = 'equity_statement' AND m.effective_to IS NULL
      ) THEN
        INSERT INTO account_fs_map (company_id, account_id, fs_structure_id, statement,
                                    display_order, created_by, updated_by)
        VALUES (p_company_id, a.id, v_line, 'equity_statement', 0, auth.uid(), auth.uid());
        v_count := v_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION public.fn_map_company_fs_accounts(UUID) IS
  'Binds every postable account to exactly one governed statement line per statement, derived from the metadata the account already carries. Idempotent and non-destructive: an existing active mapping is never replaced.';

REVOKE ALL ON FUNCTION public.fn_map_company_fs_accounts(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_map_company_fs_accounts(UUID) TO authenticated, service_role;

-- ── 5. The one reporting entry point ───────────────────────────────────────
-- Reads the ledger, writes nothing. Returns opening / movement / closing for
-- every line of the requested statement so all four presentations come from one
-- contract: the position reads closing, comprehensive income reads movement,
-- changes in equity reads all three, and cash flows reads movement.
CREATE OR REPLACE FUNCTION public.fn_financial_statement_report(
  p_company_id   UUID,
  p_statement    TEXT,
  p_period_start DATE,
  p_period_end   DATE,
  p_branch_id    UUID DEFAULT NULL
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
  v_sign_flip BOOLEAN;
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
  -- Presentation sign. A parent line must be the plain sum of its children, so
  -- each amount is signed the way the statement reads it:
  --   * balance sheet / equity: assets debit-positive; liabilities and equity
  --     are credit-normal and shown positive, so their net is negated;
  --   * income statement: revenue positive, expenses negative;
  --   * cash flow: an account's contribution to cash is the NEGATIVE of its own
  --     debit movement — stock bought (a debit) consumes cash — while the cash
  --     accounts themselves carry their own movement, which the two must match.
  mapped AS (
    SELECT m.fs_structure_id,
           SUM(COALESCE(gl.opening_net, 0)  * sgn.s) AS opening_amount,
           SUM(COALESCE(gl.movement_net, 0) * sgn.s) AS movement_amount
    FROM account_fs_map m
    JOIN chart_of_accounts coa ON coa.id = m.account_id
    LEFT JOIN gl ON gl.account_id = m.account_id
    CROSS JOIN LATERAL (
      SELECT CASE
        WHEN p_statement = 'cash_flow' AND NOT coa.is_cash_equivalent THEN -1
        WHEN p_statement = 'cash_flow'                                THEN  1
        -- Comprehensive income reads credit-minus-debit for every line, so
        -- revenue is positive, expenses are negative, and the roll-up IS the
        -- net income rather than something a subtotal has to re-derive.
        WHEN p_statement = 'income_statement'                         THEN -1
        WHEN coa.normal_balance = 'credit'                            THEN -1
        ELSE 1 END AS s
    ) sgn
    WHERE m.company_id = p_company_id
      AND m.statement = p_statement
      AND (m.effective_from IS NULL OR m.effective_from <= p_period_end)
      AND (m.effective_to IS NULL OR m.effective_to >= p_period_end)
    GROUP BY m.fs_structure_id
  ),
  -- Undistributed profit. Revenue and expense balances are not posted to equity
  -- until the year is closed, so a mid-year Statement of Financial Position does
  -- not balance without this line. It is computed from the income-statement
  -- accounts themselves — never mapped, never posted.
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

-- Ancestry test used by the subtotal roll-up. Kept as a function so the report
-- reads as the accounting statement it is rather than as a recursive join.
CREATE OR REPLACE FUNCTION public.fn_fs_line_is_descendant(p_line_id UUID, p_ancestor_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH RECURSIVE up AS (
    SELECT p_line_id AS id
    UNION ALL
    SELECT f.parent_id FROM fs_structure f JOIN up ON up.id = f.id WHERE f.parent_id IS NOT NULL
  )
  SELECT EXISTS (SELECT 1 FROM up WHERE up.id = p_ancestor_id);
$$;

COMMENT ON FUNCTION public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID) IS
  'The one financial statement reporting entry point. Returns opening, movement and closing for every governed line of a statement. Reads the posted ledger and writes nothing; presentation lives entirely in fs_structure and account_fs_map.';

REVOKE ALL ON FUNCTION public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_financial_statement_report(UUID, TEXT, DATE, DATE, UUID) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_fs_line_is_descendant(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fs_line_is_descendant(UUID, UUID) TO authenticated, service_role;

-- ── 6. Every company gets a statement structure ────────────────────────────
-- New companies through the guided provisioner, and every company that already
-- exists. Seeding runs as the owner because it is a provisioning step, not a
-- user action.
DO $$
DECLARE c RECORD; BEGIN
  FOR c IN SELECT id FROM companies LOOP
    PERFORM set_config('request.jwt.claims', json_build_object(
      'sub', COALESCE((SELECT user_id::text FROM user_company_memberships
                        WHERE company_id = c.id ORDER BY granted_at LIMIT 1),
                      '00000000-0000-0000-0000-000000000000'),
      'role', 'authenticated')::text, true);
    BEGIN
      PERFORM fn_map_company_fs_accounts(c.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'FS mapping skipped for company %: %', c.id, SQLERRM;
    END;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- ── 7. Provisioning a chart of accounts provisions its presentation ────────
-- A company that has accounts but no statement structure can post correctly and
-- still not produce a statement, which is exactly the state this migration
-- found. Seeding them together is what stops that recurring.
CREATE OR REPLACE FUNCTION public.fn_mdp08_module_coa(p_context jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count    INTEGER;
  v_company  UUID := (p_context->>'company_id')::UUID;
  v_fs_lines INTEGER;
BEGIN
  -- fn_seed_company_coa maps the statement lines itself; this reports how many
  -- bindings the company ended up with so provisioning evidence shows it.
  v_count := fn_seed_company_coa(v_company, p_context->>'coa_template_code');
  SELECT count(*)::INTEGER INTO v_fs_lines
  FROM account_fs_map WHERE company_id = v_company AND effective_to IS NULL;
  RETURN jsonb_build_object('account_count', v_count, 'fs_mapping_count', v_fs_lines);
END;
$function$;

-- ── 8. The chart seeder carries the cash marker ────────────────────────────
-- Only the column list changes: a company seeded from a template now knows
-- which of its accounts ARE cash, without which the cash flow statement has
-- nothing to reconcile to.
CREATE OR REPLACE FUNCTION public.fn_seed_company_coa(p_company_id uuid, p_template_code text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template_id UUID;
  v_code        TEXT := p_template_code;
  v_count       INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed defaults for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  -- Default template selection: resolve from the company's entity_type when the
  -- caller does not name one explicitly.
  IF v_code IS NULL THEN
    SELECT t.template_code INTO v_code
    FROM coa_templates t
    JOIN companies c ON c.id = p_company_id
    WHERE t.is_active AND c.entity_type = ANY (t.entity_types)
    ORDER BY t.template_code
    LIMIT 1;
  END IF;

  SELECT id INTO v_template_id FROM coa_templates WHERE template_code = v_code AND is_active;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'COA template % not found or inactive', COALESCE(v_code, '(none)') USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO chart_of_accounts (
    company_id, account_code, account_name, account_type, normal_balance, is_postable,
    fs_group, fs_subgroup, cash_flow_category, is_control_account, allow_subledger,
    subledger_type, is_tax_account, is_cash_equivalent, created_by, updated_by)
  SELECT p_company_id, l.account_code, l.account_name, l.account_type, l.normal_balance, l.is_postable,
         l.fs_group, l.fs_subgroup, l.cash_flow_category, l.is_control_account, l.allow_subledger,
         l.subledger_type, l.is_tax_account, l.is_cash_equivalent, auth.uid(), auth.uid()
  FROM coa_template_lines l
  WHERE l.template_id = v_template_id
  ON CONFLICT (company_id, account_code) DO NOTHING;

  -- Resolve parent hierarchy by account_code within the same company.
  UPDATE chart_of_accounts c
     SET parent_id = p.id
  FROM coa_template_lines l
  JOIN chart_of_accounts p
    ON p.company_id = p_company_id AND p.account_code = l.parent_account_code
  WHERE l.template_id = v_template_id
    AND c.company_id = p_company_id
    AND c.account_code = l.account_code
    AND l.parent_account_code IS NOT NULL
    AND c.parent_id IS NULL;

  SELECT count(*)::INTEGER INTO v_count
  FROM chart_of_accounts c
  WHERE c.company_id = p_company_id
    AND c.account_code IN (SELECT account_code FROM coa_template_lines WHERE template_id = v_template_id);
  RETURN v_count;
END;
$function$

;

-- ── 9. Seeding a chart provisions its presentation ─────────────────────────
-- fn_mdp08_module_coa is only one caller. Hooking the seeder itself means every
-- template-provisioned company gets a statement structure, whichever path
-- created it. A chart built by direct insert (the canonical demo seed) still
-- needs fn_map_company_fs_accounts run once — the seed does that itself.
CREATE OR REPLACE FUNCTION public.fn_seed_company_coa(p_company_id uuid, p_template_code text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template_id UUID;
  v_code        TEXT := p_template_code;
  v_count       INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed defaults for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  -- Default template selection: resolve from the company's entity_type when the
  -- caller does not name one explicitly.
  IF v_code IS NULL THEN
    SELECT t.template_code INTO v_code
    FROM coa_templates t
    JOIN companies c ON c.id = p_company_id
    WHERE t.is_active AND c.entity_type = ANY (t.entity_types)
    ORDER BY t.template_code
    LIMIT 1;
  END IF;

  SELECT id INTO v_template_id FROM coa_templates WHERE template_code = v_code AND is_active;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'COA template % not found or inactive', COALESCE(v_code, '(none)') USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO chart_of_accounts (
    company_id, account_code, account_name, account_type, normal_balance, is_postable,
    fs_group, fs_subgroup, cash_flow_category, is_control_account, allow_subledger,
    subledger_type, is_tax_account, is_cash_equivalent, created_by, updated_by)
  SELECT p_company_id, l.account_code, l.account_name, l.account_type, l.normal_balance, l.is_postable,
         l.fs_group, l.fs_subgroup, l.cash_flow_category, l.is_control_account, l.allow_subledger,
         l.subledger_type, l.is_tax_account, l.is_cash_equivalent, auth.uid(), auth.uid()
  FROM coa_template_lines l
  WHERE l.template_id = v_template_id
  ON CONFLICT (company_id, account_code) DO NOTHING;

  -- Resolve parent hierarchy by account_code within the same company.
  UPDATE chart_of_accounts c
     SET parent_id = p.id
  FROM coa_template_lines l
  JOIN chart_of_accounts p
    ON p.company_id = p_company_id AND p.account_code = l.parent_account_code
  WHERE l.template_id = v_template_id
    AND c.company_id = p_company_id
    AND c.account_code = l.account_code
    AND l.parent_account_code IS NOT NULL
    AND c.parent_id IS NULL;

  -- A company must never end up with accounts it cannot present.
  PERFORM fn_map_company_fs_accounts(p_company_id);

  SELECT count(*)::INTEGER INTO v_count
  FROM chart_of_accounts c
  WHERE c.company_id = p_company_id
    AND c.account_code IN (SELECT account_code FROM coa_template_lines WHERE template_id = v_template_id);
  RETURN v_count;
END;
$function$

;
