-- ══════════════════════════════════════════════════════════════════════════════
-- 1601EQ server-computed figures + reconciliation gate (PXL-AUD-034)
--
-- 1. fn_compute_ewt_return: server-side quarterly EWT totals from the tax
--    ledger (tax_kind = 'ewt_payable', document_date within the quarter).
--    Reversal counter-rows are included so cancelled withholding nets out —
--    the same population fn_wht_gl_reconciliation compares against the GL,
--    so a return computed here reconciles by construction when the GL does.
-- 2. trg_ewt_returns_status_reconciled: an EWT return cannot be marked
--    final/filed unless (a) the WHT tax ledger reconciles to the EWT Payable
--    GL control account for the quarter (fn_wht_gl_reconciliation), (b) the
--    return's total_tax_base / total_ewt_withheld match the tax ledger within
--    0.01, and (c) still_due = total_ewt_withheld - remitted_prior with a
--    non-negative remitted_prior. Mirrors trg_vat_returns_status_reconciled.
--
-- remitted_prior stays operator-entered until the controlled remittance flow
-- (PXL-AUD-041) exists to derive it from 0619-E remittances; the arithmetic
-- gate at least pins still_due to the entered figures.
--
-- fwt_returns (1601FQ) shares the free-entry pattern, but nothing posts
-- fwt-kind tax detail rows yet, so a ledger gate there would force all-zero
-- returns; it stays under the withholding backlog with PXL-AUD-041.
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_compute_ewt_return(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER
)
RETURNS TABLE (
  total_tax_base     NUMERIC(15,2),
  total_ewt_withheld NUMERIC(15,2)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from DATE;
  v_to   DATE;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_quarter IS NULL OR p_quarter NOT BETWEEN 1 AND 4 OR p_year IS NULL THEN
    RAISE EXCEPTION 'Invalid 1601EQ period: year %, quarter %', p_year, p_quarter;
  END IF;

  v_from := make_date(p_year, (p_quarter - 1) * 3 + 1, 1);
  v_to   := (v_from + INTERVAL '3 months' - INTERVAL '1 day')::DATE;

  RETURN QUERY
  SELECT COALESCE(SUM(tde.tax_base), 0)::NUMERIC(15,2),
         COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2)
  FROM tax_detail_entries tde
  WHERE tde.company_id = p_company_id
    AND tde.tax_kind = 'ewt_payable'
    AND tde.document_date BETWEEN v_from AND v_to;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_compute_ewt_return(UUID, INTEGER, INTEGER) TO authenticated;

COMMENT ON FUNCTION fn_compute_ewt_return(UUID, INTEGER, INTEGER) IS
  'Server-computed 1601EQ quarterly totals from the ewt_payable tax ledger (net of reversal counter-rows).';

-- ── Gate: EWT returns must reconcile before final/filed ────────────────────────

CREATE OR REPLACE FUNCTION fn_require_ewt_return_reconciled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from DATE;
  v_to   DATE;
  v_row  RECORD;
  v_ledger_base     NUMERIC(15,2) := 0;
  v_ledger_withheld NUMERIC(15,2) := 0;
BEGIN
  IF NEW.status NOT IN ('final', 'filed') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status = NEW.status
     AND OLD.total_tax_base = NEW.total_tax_base
     AND OLD.total_ewt_withheld = NEW.total_ewt_withheld
     AND OLD.remitted_prior = NEW.remitted_prior
     AND OLD.still_due = NEW.still_due THEN
    RETURN NEW;  -- metadata-only update of an already-validated return
  END IF;

  IF NEW.remitted_prior < 0 THEN
    RAISE EXCEPTION
      '1601EQ return cannot be marked %: remitted prior (0619-E) cannot be negative (%).',
      NEW.status, NEW.remitted_prior;
  END IF;
  IF ABS(NEW.still_due - (NEW.total_ewt_withheld - NEW.remitted_prior)) > 0.01 THEN
    RAISE EXCEPTION
      '1601EQ return cannot be marked %: still due % does not equal EWT withheld % less remitted prior %.',
      NEW.status, NEW.still_due, NEW.total_ewt_withheld, NEW.remitted_prior;
  END IF;

  v_from := make_date(NEW.period_year, (NEW.period_quarter - 1) * 3 + 1, 1);
  v_to   := (v_from + INTERVAL '3 months' - INTERVAL '1 day')::DATE;

  FOR v_row IN
    SELECT * FROM fn_wht_gl_reconciliation(NEW.company_id, v_from, v_to)
  LOOP
    CONTINUE WHEN v_row.tax_kind <> 'ewt_payable';
    IF v_row.gl_account_id IS NULL AND v_row.ledger_tax_amount <> 0 THEN
      RAISE EXCEPTION
        '1601EQ return cannot be marked %: the EWT Payable GL control account is not configured in GL Posting Configuration but the tax ledger has % for % to %.',
        NEW.status, v_row.ledger_tax_amount, v_from, v_to;
    END IF;
    IF NOT v_row.is_reconciled THEN
      RAISE EXCEPTION
        '1601EQ return cannot be marked %: the ewt_payable tax ledger (%) does not reconcile to GL account % (%) for % to %. Variance: %.',
        NEW.status, v_row.ledger_tax_amount,
        v_row.gl_account_code, v_row.gl_amount, v_from, v_to, v_row.variance;
    END IF;
    v_ledger_base     := v_row.ledger_tax_base;
    v_ledger_withheld := v_row.ledger_tax_amount;
  END LOOP;

  IF ABS(NEW.total_ewt_withheld - v_ledger_withheld) > 0.01 THEN
    RAISE EXCEPTION
      '1601EQ return cannot be marked %: return EWT withheld % does not match the tax ledger EWT % for % to %.',
      NEW.status, NEW.total_ewt_withheld, v_ledger_withheld, v_from, v_to;
  END IF;
  IF ABS(NEW.total_tax_base - v_ledger_base) > 0.01 THEN
    RAISE EXCEPTION
      '1601EQ return cannot be marked %: return tax base % does not match the tax ledger base % for % to %.',
      NEW.status, NEW.total_tax_base, v_ledger_base, v_from, v_to;
  END IF;

  RETURN NEW;
END;
$$;

-- Fires before trg_guard_header_ewt_returns (alphabetical BEFORE-trigger
-- order), so a final/filed transition is reconciliation-checked first and the
-- PXL-DA-011 guard then freezes the validated figures.
DROP TRIGGER IF EXISTS trg_ewt_returns_status_reconciled ON ewt_returns;
CREATE TRIGGER trg_ewt_returns_status_reconciled
  BEFORE INSERT OR UPDATE ON ewt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_require_ewt_return_reconciled();
