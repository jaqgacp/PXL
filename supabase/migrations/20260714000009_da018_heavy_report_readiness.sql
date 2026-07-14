-- PXL-DA-018: server-side heavy report readiness.
--
-- General Ledger, Account Detail Ledger, and Trial Balance are the highest-risk
-- report family because they sit on vw_general_ledger and grow with every posted
-- transaction. These RPCs move filtering, aggregation, opening/running balances,
-- total row counts, and report totals into PostgreSQL so the UI can page through
-- large ledgers without client-side materialization.

CREATE INDEX IF NOT EXISTS idx_je_report_company_status_date
  ON journal_entries (company_id, status, je_date, je_number, id);

CREATE INDEX IF NOT EXISTS idx_je_report_company_status_class_date
  ON journal_entries (company_id, status, entry_class, je_date, id);

CREATE INDEX IF NOT EXISTS idx_jel_report_company_account_je
  ON journal_entry_lines (company_id, account_id, je_id, id);

CREATE OR REPLACE FUNCTION fn_gl_report_limit(p_limit INT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500);
$$;

CREATE OR REPLACE FUNCTION fn_gl_report_offset(p_offset INT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT GREATEST(COALESCE(p_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION fn_general_ledger_report(
  p_company_id          UUID,
  p_date_from           DATE DEFAULT NULL,
  p_date_to             DATE DEFAULT NULL,
  p_account_id          UUID DEFAULT NULL,
  p_je_id               UUID DEFAULT NULL,
  p_reference_doc_type  TEXT DEFAULT NULL,
  p_reference_doc_id    UUID DEFAULT NULL,
  p_account_types       TEXT[] DEFAULT NULL,
  p_branch_id           UUID DEFAULT NULL,
  p_department_id       UUID DEFAULT NULL,
  p_cost_center_id      UUID DEFAULT NULL,
  p_entry_classes       TEXT[] DEFAULT NULL,
  p_limit               INT DEFAULT 200,
  p_offset              INT DEFAULT 0
)
RETURNS TABLE (
  line_id            UUID,
  je_id              UUID,
  company_id         UUID,
  branch_id          UUID,
  fiscal_period_id   UUID,
  period_name        TEXT,
  period_start       DATE,
  period_end         DATE,
  je_date            DATE,
  je_number          TEXT,
  je_description     TEXT,
  reference_doc_type TEXT,
  reference_doc_id   UUID,
  je_status          TEXT,
  is_auto_reversal   BOOLEAN,
  reversed_by_je_id  UUID,
  account_id         UUID,
  account_code       TEXT,
  account_name       TEXT,
  account_type       TEXT,
  normal_balance     TEXT,
  line_number        INT,
  line_description   TEXT,
  debit_amount       NUMERIC(15,2),
  credit_amount      NUMERIC(15,2),
  department_id      UUID,
  cost_center_id     UUID,
  entry_class        TEXT,
  total_rows         BIGINT,
  period_debit       NUMERIC(15,2),
  period_credit      NUMERIC(15,2)
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH params AS (
    SELECT fn_gl_report_limit(p_limit) AS row_limit,
           fn_gl_report_offset(p_offset) AS row_offset
  ),
  filtered AS (
    SELECT
      jel.id AS line_id,
      jel.je_id,
      jel.company_id,
      COALESCE(jel.branch_id, je.branch_id) AS branch_id,
      je.fiscal_period_id,
      fp.period_name,
      fp.start_date AS period_start,
      fp.end_date AS period_end,
      je.je_date,
      je.je_number,
      je.description AS je_description,
      je.reference_doc_type,
      je.reference_doc_id,
      je.status AS je_status,
      je.is_auto_reversal,
      je.reversed_by_je_id,
      jel.account_id,
      coa.account_code,
      coa.account_name,
      coa.account_type,
      coa.normal_balance,
      jel.line_number,
      jel.description AS line_description,
      jel.debit_amount::NUMERIC(15,2) AS debit_amount,
      jel.credit_amount::NUMERIC(15,2) AS credit_amount,
      jel.department_id,
      jel.cost_center_id,
      je.entry_class
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
    WHERE je.company_id = p_company_id
      AND jel.company_id = p_company_id
      AND je.status IN ('posted', 'reversed')
      AND is_company_member(p_company_id)
      AND (p_date_from IS NULL OR je.je_date >= p_date_from)
      AND (p_date_to IS NULL OR je.je_date <= p_date_to)
      AND (p_account_id IS NULL OR jel.account_id = p_account_id)
      AND (p_je_id IS NULL OR je.id = p_je_id)
      AND (NULLIF(p_reference_doc_type, '') IS NULL OR je.reference_doc_type = UPPER(NULLIF(p_reference_doc_type, '')))
      AND (p_reference_doc_id IS NULL OR je.reference_doc_id = p_reference_doc_id)
      AND (p_account_types IS NULL OR cardinality(p_account_types) = 0 OR coa.account_type = ANY(p_account_types))
      AND (p_branch_id IS NULL OR COALESCE(jel.branch_id, je.branch_id) = p_branch_id)
      AND (p_department_id IS NULL OR jel.department_id = p_department_id)
      AND (p_cost_center_id IS NULL OR jel.cost_center_id = p_cost_center_id)
      AND (p_entry_classes IS NULL OR cardinality(p_entry_classes) = 0 OR je.entry_class = ANY(p_entry_classes))
  ),
  totals AS (
    SELECT
      COUNT(*)::BIGINT AS total_rows,
      COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2) AS period_debit,
      COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2) AS period_credit
    FROM filtered
  ),
  ordered AS (
    SELECT
      f.*,
      ROW_NUMBER() OVER (ORDER BY f.je_date, f.je_number, f.line_number, f.line_id) AS rn
    FROM filtered f
  )
  SELECT
    o.line_id,
    o.je_id,
    o.company_id,
    o.branch_id,
    o.fiscal_period_id,
    o.period_name,
    o.period_start,
    o.period_end,
    o.je_date,
    o.je_number,
    o.je_description,
    o.reference_doc_type,
    o.reference_doc_id,
    o.je_status,
    o.is_auto_reversal,
    o.reversed_by_je_id,
    o.account_id,
    o.account_code,
    o.account_name,
    o.account_type,
    o.normal_balance,
    o.line_number,
    o.line_description,
    o.debit_amount,
    o.credit_amount,
    o.department_id,
    o.cost_center_id,
    o.entry_class,
    t.total_rows,
    t.period_debit,
    t.period_credit
  FROM ordered o
  CROSS JOIN totals t
  CROSS JOIN params p
  WHERE o.rn > p.row_offset
    AND o.rn <= p.row_offset + p.row_limit
  ORDER BY o.rn;
$$;

CREATE OR REPLACE FUNCTION fn_gl_account_ledger_summary(
  p_company_id UUID,
  p_account_id UUID,
  p_date_from  DATE,
  p_date_to    DATE,
  p_je_id      UUID DEFAULT NULL
)
RETURNS TABLE (
  account_id       UUID,
  normal_balance   TEXT,
  opening_balance  NUMERIC(15,2),
  period_debit     NUMERIC(15,2),
  period_credit    NUMERIC(15,2),
  closing_balance  NUMERIC(15,2),
  total_rows       BIGINT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH account_ref AS (
    SELECT coa.id AS account_id, coa.normal_balance
    FROM chart_of_accounts coa
    WHERE coa.company_id = p_company_id
      AND coa.id = p_account_id
      AND is_company_member(p_company_id)
  ),
  opening_raw AS (
    SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)::NUMERIC(15,2) AS net_amount
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = p_company_id
      AND jel.company_id = p_company_id
      AND jel.account_id = p_account_id
      AND je.status IN ('posted', 'reversed')
      AND je.je_date < p_date_from
      AND is_company_member(p_company_id)
  ),
  movements AS (
    SELECT
      jel.debit_amount::NUMERIC(15,2) AS debit_amount,
      jel.credit_amount::NUMERIC(15,2) AS credit_amount
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = p_company_id
      AND jel.company_id = p_company_id
      AND jel.account_id = p_account_id
      AND je.status IN ('posted', 'reversed')
      AND je.je_date BETWEEN p_date_from AND p_date_to
      AND (p_je_id IS NULL OR je.id = p_je_id)
      AND is_company_member(p_company_id)
  ),
  period AS (
    SELECT
      COUNT(*)::BIGINT AS total_rows,
      COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2) AS period_debit,
      COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2) AS period_credit
    FROM movements
  )
  SELECT
    ar.account_id,
    ar.normal_balance,
    CASE WHEN ar.normal_balance = 'credit' THEN -o.net_amount ELSE o.net_amount END::NUMERIC(15,2) AS opening_balance,
    p.period_debit,
    p.period_credit,
    (
      CASE WHEN ar.normal_balance = 'credit' THEN -o.net_amount ELSE o.net_amount END
      + CASE WHEN ar.normal_balance = 'credit'
             THEN p.period_credit - p.period_debit
             ELSE p.period_debit - p.period_credit
        END
    )::NUMERIC(15,2) AS closing_balance,
    p.total_rows
  FROM account_ref ar
  CROSS JOIN opening_raw o
  CROSS JOIN period p;
$$;

CREATE OR REPLACE FUNCTION fn_gl_account_ledger_page(
  p_company_id UUID,
  p_account_id UUID,
  p_date_from  DATE,
  p_date_to    DATE,
  p_je_id      UUID DEFAULT NULL,
  p_limit      INT DEFAULT 200,
  p_offset     INT DEFAULT 0
)
RETURNS TABLE (
  line_id            UUID,
  je_id              UUID,
  company_id         UUID,
  branch_id          UUID,
  fiscal_period_id   UUID,
  period_name        TEXT,
  period_start       DATE,
  period_end         DATE,
  je_date            DATE,
  je_number          TEXT,
  je_description     TEXT,
  reference_doc_type TEXT,
  reference_doc_id   UUID,
  je_status          TEXT,
  is_auto_reversal   BOOLEAN,
  reversed_by_je_id  UUID,
  account_id         UUID,
  account_code       TEXT,
  account_name       TEXT,
  account_type       TEXT,
  normal_balance     TEXT,
  line_number        INT,
  line_description   TEXT,
  debit_amount       NUMERIC(15,2),
  credit_amount      NUMERIC(15,2),
  department_id      UUID,
  cost_center_id     UUID,
  entry_class        TEXT,
  running_balance    NUMERIC(15,2)
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH params AS (
    SELECT fn_gl_report_limit(p_limit) AS row_limit,
           fn_gl_report_offset(p_offset) AS row_offset
  ),
  account_ref AS (
    SELECT coa.id AS account_id, coa.normal_balance
    FROM chart_of_accounts coa
    WHERE coa.company_id = p_company_id
      AND coa.id = p_account_id
      AND is_company_member(p_company_id)
  ),
  opening_raw AS (
    SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)::NUMERIC(15,2) AS net_amount
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = p_company_id
      AND jel.company_id = p_company_id
      AND jel.account_id = p_account_id
      AND je.status IN ('posted', 'reversed')
      AND je.je_date < p_date_from
      AND is_company_member(p_company_id)
  ),
  opening AS (
    SELECT
      ar.normal_balance,
      CASE WHEN ar.normal_balance = 'credit' THEN -o.net_amount ELSE o.net_amount END::NUMERIC(15,2) AS opening_balance
    FROM account_ref ar
    CROSS JOIN opening_raw o
  ),
  movements AS (
    SELECT
      jel.id AS line_id,
      jel.je_id,
      jel.company_id,
      COALESCE(jel.branch_id, je.branch_id) AS branch_id,
      je.fiscal_period_id,
      fp.period_name,
      fp.start_date AS period_start,
      fp.end_date AS period_end,
      je.je_date,
      je.je_number,
      je.description AS je_description,
      je.reference_doc_type,
      je.reference_doc_id,
      je.status AS je_status,
      je.is_auto_reversal,
      je.reversed_by_je_id,
      jel.account_id,
      coa.account_code,
      coa.account_name,
      coa.account_type,
      coa.normal_balance,
      jel.line_number,
      jel.description AS line_description,
      jel.debit_amount::NUMERIC(15,2) AS debit_amount,
      jel.credit_amount::NUMERIC(15,2) AS credit_amount,
      jel.department_id,
      jel.cost_center_id,
      je.entry_class,
      ROW_NUMBER() OVER (ORDER BY je.je_date, je.je_number, jel.line_number, jel.id) AS rn,
      SUM(
        CASE WHEN coa.normal_balance = 'credit'
             THEN jel.credit_amount - jel.debit_amount
             ELSE jel.debit_amount - jel.credit_amount
        END
      ) OVER (ORDER BY je.je_date, je.je_number, jel.line_number, jel.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::NUMERIC(15,2) AS running_delta
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
    WHERE je.company_id = p_company_id
      AND jel.company_id = p_company_id
      AND jel.account_id = p_account_id
      AND je.status IN ('posted', 'reversed')
      AND je.je_date BETWEEN p_date_from AND p_date_to
      AND (p_je_id IS NULL OR je.id = p_je_id)
      AND is_company_member(p_company_id)
  )
  SELECT
    m.line_id,
    m.je_id,
    m.company_id,
    m.branch_id,
    m.fiscal_period_id,
    m.period_name,
    m.period_start,
    m.period_end,
    m.je_date,
    m.je_number,
    m.je_description,
    m.reference_doc_type,
    m.reference_doc_id,
    m.je_status,
    m.is_auto_reversal,
    m.reversed_by_je_id,
    m.account_id,
    m.account_code,
    m.account_name,
    m.account_type,
    m.normal_balance,
    m.line_number,
    m.line_description,
    m.debit_amount,
    m.credit_amount,
    m.department_id,
    m.cost_center_id,
    m.entry_class,
    (o.opening_balance + m.running_delta)::NUMERIC(15,2) AS running_balance
  FROM movements m
  CROSS JOIN opening o
  CROSS JOIN params p
  WHERE m.rn > p.row_offset
    AND m.rn <= p.row_offset + p.row_limit
  ORDER BY m.rn;
$$;

CREATE OR REPLACE FUNCTION fn_trial_balance_report(
  p_company_id    UUID,
  p_date_from     DATE,
  p_date_to       DATE,
  p_entry_classes TEXT[] DEFAULT ARRAY['regular','opening']::TEXT[],
  p_include_zero  BOOLEAN DEFAULT FALSE,
  p_account_id    UUID DEFAULT NULL
)
RETURNS TABLE (
  account_id     UUID,
  account_code   TEXT,
  account_name   TEXT,
  account_type   TEXT,
  normal_balance TEXT,
  opening_net    NUMERIC(15,2),
  period_debit   NUMERIC(15,2),
  period_credit  NUMERIC(15,2),
  closing_net    NUMERIC(15,2)
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH accounts AS (
    SELECT
      coa.id AS account_id,
      coa.account_code,
      coa.account_name,
      coa.account_type,
      coa.normal_balance
    FROM chart_of_accounts coa
    WHERE coa.company_id = p_company_id
      AND coa.is_active = true
      AND coa.is_postable = true
      AND (p_account_id IS NULL OR coa.id = p_account_id)
      AND is_company_member(p_company_id)
  ),
  gl AS (
    SELECT
      jel.account_id,
      je.je_date,
      je.entry_class,
      jel.debit_amount::NUMERIC(15,2) AS debit_amount,
      jel.credit_amount::NUMERIC(15,2) AS credit_amount
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = p_company_id
      AND jel.company_id = p_company_id
      AND je.status IN ('posted', 'reversed')
      AND je.entry_class = ANY(COALESCE(p_entry_classes, ARRAY['regular','opening']::TEXT[]))
      AND je.je_date <= p_date_to
      AND is_company_member(p_company_id)
  ),
  balances AS (
    SELECT
      a.account_id,
      a.account_code,
      a.account_name,
      a.account_type,
      a.normal_balance,
      COALESCE(SUM(gl.debit_amount - gl.credit_amount) FILTER (WHERE gl.je_date < p_date_from), 0)::NUMERIC(15,2) AS opening_net,
      COALESCE(SUM(gl.debit_amount) FILTER (WHERE gl.je_date BETWEEN p_date_from AND p_date_to), 0)::NUMERIC(15,2) AS period_debit,
      COALESCE(SUM(gl.credit_amount) FILTER (WHERE gl.je_date BETWEEN p_date_from AND p_date_to), 0)::NUMERIC(15,2) AS period_credit
    FROM accounts a
    LEFT JOIN gl ON gl.account_id = a.account_id
    GROUP BY a.account_id, a.account_code, a.account_name, a.account_type, a.normal_balance
  )
  SELECT
    b.account_id,
    b.account_code,
    b.account_name,
    b.account_type,
    b.normal_balance,
    b.opening_net,
    b.period_debit,
    b.period_credit,
    (b.opening_net + b.period_debit - b.period_credit)::NUMERIC(15,2) AS closing_net
  FROM balances b
  WHERE p_include_zero
     OR ABS(b.opening_net) > 0.005
     OR b.period_debit > 0.005
     OR b.period_credit > 0.005
     OR ABS(b.opening_net + b.period_debit - b.period_credit) > 0.005
  ORDER BY b.account_code;
$$;

REVOKE ALL ON FUNCTION fn_gl_report_limit(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_gl_report_offset(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_general_ledger_report(UUID, DATE, DATE, UUID, UUID, TEXT, UUID, TEXT[], UUID, UUID, UUID, TEXT[], INT, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_gl_account_ledger_summary(UUID, UUID, DATE, DATE, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_gl_account_ledger_page(UUID, UUID, DATE, DATE, UUID, INT, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_trial_balance_report(UUID, DATE, DATE, TEXT[], BOOLEAN, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_general_ledger_report(UUID, DATE, DATE, UUID, UUID, TEXT, UUID, TEXT[], UUID, UUID, UUID, TEXT[], INT, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_gl_account_ledger_summary(UUID, UUID, DATE, DATE, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_gl_account_ledger_page(UUID, UUID, DATE, DATE, UUID, INT, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_trial_balance_report(UUID, DATE, DATE, TEXT[], BOOLEAN, UUID) TO authenticated, service_role;

COMMENT ON FUNCTION fn_general_ledger_report(UUID, DATE, DATE, UUID, UUID, TEXT, UUID, TEXT[], UUID, UUID, UUID, TEXT[], INT, INT) IS
  'PXL-DA-018 server-side paginated general ledger report with filtered row count and debit/credit totals.';

COMMENT ON FUNCTION fn_gl_account_ledger_summary(UUID, UUID, DATE, DATE, UUID) IS
  'PXL-DA-018 account ledger summary for opening, period, closing, and row count without materializing movement rows client-side.';

COMMENT ON FUNCTION fn_gl_account_ledger_page(UUID, UUID, DATE, DATE, UUID, INT, INT) IS
  'PXL-DA-018 paginated account-detail ledger with server-computed normal-balance running balances.';

COMMENT ON FUNCTION fn_trial_balance_report(UUID, DATE, DATE, TEXT[], BOOLEAN, UUID) IS
  'PXL-DA-018 server-side Trial Balance aggregation by account and entry-class mode.';
