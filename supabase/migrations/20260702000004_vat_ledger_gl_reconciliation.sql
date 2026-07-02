-- ══════════════════════════════════════════════════════════════════════════════
-- VAT tax-ledger-to-GL reconciliation (PXL-AUD-014 / PXL-DA-008)
--
-- 1. fn_vat_gl_reconciliation: server-side comparison of tax_detail_entries
--    (output_vat / input_vat) against the configured GL VAT control accounts
--    for a date range. Uses je.status = 'posted' to match the reporting
--    surfaces (vw_general_ledger / vw_trial_balance), and the tax ledger's
--    document_date, which is the accounting date aligned with je_date
--    (posting_date holds the system date at posting time, not the period).
-- 2. trg_vat_returns_status_reconciled: a VAT return cannot be marked
--    final/filed unless (a) the tax ledger reconciles to the GL VAT control
--    accounts for the return period and (b) the return's own output/input VAT
--    figures match the tax ledger within tolerance.
-- ══════════════════════════════════════════════════════════════════════════════

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
                    AND je.status = 'posted'
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

GRANT EXECUTE ON FUNCTION fn_vat_gl_reconciliation(UUID, DATE, DATE) TO authenticated;

-- ── Gate: VAT returns must reconcile before final/filed ────────────────────────

CREATE OR REPLACE FUNCTION fn_require_vat_return_reconciled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from DATE;
  v_to   DATE;
  v_row  RECORD;
  v_ledger_output NUMERIC(15,2) := 0;
  v_ledger_input  NUMERIC(15,2) := 0;
BEGIN
  IF NEW.status NOT IN ('final', 'filed') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status = NEW.status
     AND OLD.output_vat = NEW.output_vat
     AND OLD.input_vat = NEW.input_vat THEN
    RETURN NEW;  -- metadata-only update of an already-validated return
  END IF;

  IF NEW.return_type = '2550M' THEN
    v_from := make_date(NEW.period_year, NEW.period_month, 1);
    v_to   := (v_from + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  ELSE
    v_from := make_date(NEW.period_year, (NEW.period_quarter - 1) * 3 + 1, 1);
    v_to   := (v_from + INTERVAL '3 months' - INTERVAL '1 day')::DATE;
  END IF;

  FOR v_row IN
    SELECT * FROM fn_vat_gl_reconciliation(NEW.company_id, v_from, v_to)
  LOOP
    IF v_row.gl_account_id IS NULL AND v_row.ledger_tax_amount <> 0 THEN
      RAISE EXCEPTION
        'VAT return cannot be marked %: the % GL control account is not configured in GL Posting Configuration but the tax ledger has % for % to %.',
        NEW.status, v_row.tax_kind, v_row.ledger_tax_amount, v_from, v_to;
    END IF;
    IF NOT v_row.is_reconciled THEN
      RAISE EXCEPTION
        'VAT return cannot be marked %: % tax ledger (%) does not reconcile to GL account % (%) for % to %. Variance: %.',
        NEW.status, v_row.tax_kind, v_row.ledger_tax_amount,
        v_row.gl_account_code, v_row.gl_amount, v_from, v_to, v_row.variance;
    END IF;
    IF v_row.tax_kind = 'output_vat' THEN v_ledger_output := v_row.ledger_tax_amount; END IF;
    IF v_row.tax_kind = 'input_vat'  THEN v_ledger_input  := v_row.ledger_tax_amount; END IF;
  END LOOP;

  IF ABS(NEW.output_vat - v_ledger_output) > 0.01 THEN
    RAISE EXCEPTION
      'VAT return cannot be marked %: return output VAT % does not match the tax ledger output VAT % for % to %.',
      NEW.status, NEW.output_vat, v_ledger_output, v_from, v_to;
  END IF;
  IF ABS(NEW.input_vat - v_ledger_input) > 0.01 THEN
    RAISE EXCEPTION
      'VAT return cannot be marked %: return input VAT % does not match the tax ledger input VAT % for % to %.',
      NEW.status, NEW.input_vat, v_ledger_input, v_from, v_to;
  END IF;

  RETURN NEW;
END;
$$;

-- Fires after trg_vat_returns_registration (alphabetical BEFORE-trigger order),
-- so non-VAT companies are rejected with the registration error first.
DROP TRIGGER IF EXISTS trg_vat_returns_status_reconciled ON vat_returns;
CREATE TRIGGER trg_vat_returns_status_reconciled
  BEFORE INSERT OR UPDATE ON vat_returns
  FOR EACH ROW EXECUTE FUNCTION fn_require_vat_return_reconciled();
