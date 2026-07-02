-- ══════════════════════════════════════════════════════════════════════════════
-- GL reversal visibility fix (PXL-AUD-024)
--
-- Every reversal/void path (fn_reverse_je, SI/OR/VB void, PV cancel, banking
-- fn_reverse_journal_entry) posts a swapped-line counter-JE with status
-- 'posted' and marks the original 'reversed'. vw_general_ledger and
-- vw_trial_balance filtered WHERE je.status = 'posted', which excluded the
-- original but included the counter-JE — applying every reversal twice in
-- GL/TB (the account flips sign instead of returning to zero).
--
-- Convention adopted: both the original ('reversed') and its counter-JE
-- ('posted') stay visible in the books, so reversed activity nets to zero and
-- the audit trail remains on the ledger. Draft JEs stay excluded.
-- fn_vat_gl_reconciliation is updated to the same rule.
-- ══════════════════════════════════════════════════════════════════════════════

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
WHERE je.status IN ('posted', 'reversed');

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
WHERE je.status IN ('posted', 'reversed')
GROUP BY jel.company_id, je.fiscal_period_id, fp.period_name, fp.period_number,
         fp.start_date, fp.end_date,
         jel.account_id, coa.account_code, coa.account_name,
         coa.account_type, coa.normal_balance, coa.parent_id;

-- ── fn_vat_gl_reconciliation: adopt the same visibility rule ───────────────────

CREATE OR REPLACE FUNCTION fn_vat_gl_reconciliation(
  p_company_id UUID,
  p_date_from  DATE,
  p_date_to    DATE
)
RETURNS TABLE (
  tax_kind          TEXT,
  ledger_tax_base   NUMERIC(15,2),
  ledger_tax_amount NUMERIC(15,2),
  gl_account_id     UUID,
  gl_account_code   TEXT,
  gl_account_name   TEXT,
  gl_amount         NUMERIC(15,2),
  variance          NUMERIC(15,2),
  is_reconciled     BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg company_accounting_config%ROWTYPE;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid reconciliation date range % to %', p_date_from, p_date_to;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = p_company_id;

  RETURN QUERY
  WITH ledger AS (
    SELECT tde.tax_kind AS kind,
           COALESCE(SUM(tde.tax_base), 0)::NUMERIC(15,2)   AS base_sum,
           COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS tax_sum
    FROM tax_detail_entries tde
    WHERE tde.company_id = p_company_id
      AND tde.tax_kind IN ('output_vat', 'input_vat')
      AND tde.document_date BETWEEN p_date_from AND p_date_to
    GROUP BY tde.tax_kind
  ),
  kinds AS (
    SELECT 'input_vat'::TEXT  AS kind, v_cfg.input_vat_account_id   AS account_id, 'debit'::TEXT  AS normal
    UNION ALL
    SELECT 'output_vat'::TEXT,         v_cfg.vat_payable_account_id,               'credit'::TEXT
  ),
  gl AS (
    SELECT k.kind,
           k.account_id,
           CASE WHEN k.account_id IS NULL THEN NULL
                ELSE (
                  SELECT COALESCE(SUM(
                    CASE WHEN k.normal = 'credit'
                         THEN jel.credit_amount - jel.debit_amount
                         ELSE jel.debit_amount - jel.credit_amount END), 0)
                  FROM journal_entry_lines jel
                  JOIN journal_entries je ON je.id = jel.je_id
                  WHERE jel.account_id = k.account_id
                    AND jel.company_id = p_company_id
                    AND je.status IN ('posted', 'reversed')
                    AND je.je_date BETWEEN p_date_from AND p_date_to
                )
           END::NUMERIC(15,2) AS gl_sum
    FROM kinds k
  )
  SELECT
    g.kind,
    COALESCE(l.base_sum, 0)::NUMERIC(15,2),
    COALESCE(l.tax_sum, 0)::NUMERIC(15,2),
    g.account_id,
    coa.account_code,
    coa.account_name,
    g.gl_sum,
    (COALESCE(l.tax_sum, 0) - COALESCE(g.gl_sum, 0))::NUMERIC(15,2),
    CASE WHEN g.account_id IS NULL
         THEN COALESCE(l.tax_sum, 0) = 0
         ELSE ABS(COALESCE(l.tax_sum, 0) - g.gl_sum) <= 0.01
    END
  FROM gl g
  LEFT JOIN ledger l ON l.kind = g.kind
  LEFT JOIN chart_of_accounts coa ON coa.id = g.account_id
  ORDER BY g.kind;
END;
$$;
