-- Keep AR/AP control-account reconciliation aligned with the established GL
-- reversal convention: the original `reversed` journal and its posted counter-
-- journal both remain in the books and net to zero.

CREATE OR REPLACE FUNCTION fn_ar_subledger_gl_reconciliation_asof(
  p_company_id UUID,
  p_as_of DATE
)
RETURNS TABLE (
  company_id UUID,
  as_of_date DATE,
  ledger_code TEXT,
  control_account_id UUID,
  control_account_code TEXT,
  control_account_name TEXT,
  subledger_balance NUMERIC(15,2),
  gl_balance NUMERIC(15,2),
  variance NUMERIC(15,2),
  is_reconciled BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_cfg company_accounting_config%ROWTYPE;
  v_subledger NUMERIC(15,2);
  v_gl NUMERIC(15,2);
BEGIN
  IF p_as_of IS NULL THEN
    RAISE EXCEPTION 'As-of date is required';
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_cfg
  FROM company_accounting_config cac
  WHERE cac.company_id = p_company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT COALESCE(SUM(l.debit_amount - l.credit_amount), 0)::NUMERIC(15,2)
  INTO v_subledger
  FROM fn_customer_ledger_asof(p_company_id, p_as_of, NULL) l;

  SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)::NUMERIC(15,2)
  INTO v_gl
  FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id = jel.je_id
  WHERE jel.company_id = p_company_id
    AND jel.account_id = v_cfg.ar_account_id
    AND je.status IN ('posted', 'reversed')
    AND je.je_date <= p_as_of;

  RETURN QUERY
  SELECT
    p_company_id,
    p_as_of,
    'AR'::TEXT,
    v_cfg.ar_account_id,
    coa.account_code,
    coa.account_name,
    v_subledger,
    v_gl,
    (v_subledger - v_gl)::NUMERIC(15,2),
    ABS(v_subledger - v_gl) <= 0.01
  FROM chart_of_accounts coa
  WHERE coa.id = v_cfg.ar_account_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_ap_subledger_gl_reconciliation_asof(
  p_company_id UUID,
  p_as_of DATE
)
RETURNS TABLE (
  company_id UUID,
  as_of_date DATE,
  ledger_code TEXT,
  control_account_id UUID,
  control_account_code TEXT,
  control_account_name TEXT,
  subledger_balance NUMERIC(15,2),
  gl_balance NUMERIC(15,2),
  variance NUMERIC(15,2),
  is_reconciled BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_cfg company_accounting_config%ROWTYPE;
  v_subledger NUMERIC(15,2);
  v_gl NUMERIC(15,2);
BEGIN
  IF p_as_of IS NULL THEN
    RAISE EXCEPTION 'As-of date is required';
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_cfg
  FROM company_accounting_config cac
  WHERE cac.company_id = p_company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT COALESCE(SUM(l.credit_amount - l.debit_amount), 0)::NUMERIC(15,2)
  INTO v_subledger
  FROM fn_supplier_ledger_asof(p_company_id, p_as_of, NULL) l;

  SELECT COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)::NUMERIC(15,2)
  INTO v_gl
  FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id = jel.je_id
  WHERE jel.company_id = p_company_id
    AND jel.account_id = v_cfg.ap_account_id
    AND je.status IN ('posted', 'reversed')
    AND je.je_date <= p_as_of;

  RETURN QUERY
  SELECT
    p_company_id,
    p_as_of,
    'AP'::TEXT,
    v_cfg.ap_account_id,
    coa.account_code,
    coa.account_name,
    v_subledger,
    v_gl,
    (v_subledger - v_gl)::NUMERIC(15,2),
    ABS(v_subledger - v_gl) <= 0.01
  FROM chart_of_accounts coa
  WHERE coa.id = v_cfg.ap_account_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION fn_ar_subledger_gl_reconciliation_asof(UUID, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_ap_subledger_gl_reconciliation_asof(UUID, DATE) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_ar_subledger_gl_reconciliation_asof(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_ap_subledger_gl_reconciliation_asof(UUID, DATE) TO authenticated, service_role;
