-- ══════════════════════════════════════════════════════════════════════════════
-- Controlled EWT remittance / CWT application flow (PXL-AUD-041)
--
-- The problem this closes: fn_wht_gl_reconciliation compares the quarter's
-- withholding tax-ledger sum to the NET GL movement on the control account.
-- A legitimate EWT remittance (0619-E, debiting EWT Payable) or a CWT
-- application (crediting CWT Receivable against income tax due) posted inside
-- the same quarter drives GL <> ledger, which made fn_snapshot_wht_export
-- HARD-BLOCK the QAP/SAWT export and fn_require_ewt_return_reconciled block
-- 1601EQ finalization — for any filer that remits mid-quarter, every quarter's
-- BIR export deadlocked (the 20260703000007 migration acknowledged this).
--
-- The fix is a governed remittance document (withholding_remittances) whose
-- posting JE is classified by the reference_doc_type 'WHTREM'. The
-- reconciliation then EXCLUDES WHTREM movements from the GL side, so the GL
-- reflects only the withholding accrual and reconciles to the tax ledger by
-- construction. Uncontrolled MANUAL remittance JEs are still (correctly)
-- treated as variance — only the controlled document is trusted.
--
--   1. withholding_remittances — governed header; controlled writes only
--      (RLS SELECT-only for members; all writes go through the SECURITY
--      DEFINER RPCs below). A posted row must carry its JE (CHECK).
--   2. ref_posting_source_types 'WHTREM' + ux_journal_entries_live_source
--      extension so a remittance owns at most one live JE.
--   3. fn_save/post/void_withholding_remittance — draft lifecycle + posting.
--      EWT: DR EWT Payable / CR settlement (cash-bank). CWT: DR settlement
--      (income tax payable) / CR CWT Receivable. Remittances settle the
--      payable/receivable and DO NOT write tax_detail_entries (that would
--      double-count the withholding).
--   4. fn_compute_ewt_remitted_prior — 1601EQ remitted_prior derived from the
--      posted EWT remittances covering the first two months of the quarter
--      (the monthly 0619-E filings netted on the quarterly return).
--   5. fn_wht_gl_reconciliation — GL side excludes WHTREM JEs.
--   6. fn_require_ewt_return_reconciled — remitted_prior must equal the derived
--      remittances (closes the PXL-AUD-034 free-entry residue).
--
-- Design (DEC-019): remittance_number is caller-supplied and unique per
-- company (compliance filings reference the actual eFPS/0619-E number);
-- governed auto-numbering can be layered later. remitted_prior for a quarterly
-- 1601EQ = EWT remitted for months 1 and 2 of that quarter; month 3 is remitted
-- with the 1601EQ itself (still_due).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Governed remittance header ──────────────────────────────────────────────

CREATE TABLE withholding_remittances (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID          NOT NULL REFERENCES companies(id),
  branch_id             UUID          REFERENCES branches(id),
  remittance_number     TEXT          NOT NULL,
  remittance_kind       TEXT          NOT NULL
                                      CHECK (remittance_kind IN ('ewt_payable','cwt_receivable')),
  form_type             TEXT,
  period_year           INTEGER       NOT NULL,
  period_month          INTEGER       CHECK (period_month BETWEEN 1 AND 12),
  period_quarter        INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  remittance_date       DATE          NOT NULL,
  amount                NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  settlement_account_id UUID          NOT NULL REFERENCES chart_of_accounts(id),
  reference_no          TEXT,
  particulars           TEXT,
  status                TEXT          NOT NULL DEFAULT 'draft'
                                      CHECK (status IN ('draft','posted','voided')),
  journal_entry_id      UUID          REFERENCES journal_entries(id),
  fiscal_period_id      UUID          REFERENCES fiscal_periods(id),
  void_reason           TEXT,
  posted_at             TIMESTAMPTZ,
  posted_by             UUID,
  voided_at             TIMESTAMPTZ,
  voided_by             UUID,
  created_by            UUID,
  updated_by            UUID,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, remittance_number),
  -- A posted remittance must carry its governed journal entry.
  CHECK (status <> 'posted' OR journal_entry_id IS NOT NULL)
);

CREATE INDEX idx_wht_remit_company_period
  ON withholding_remittances (company_id, period_year, period_quarter, period_month);
CREATE INDEX idx_wht_remit_kind_status
  ON withholding_remittances (company_id, remittance_kind, status);

ALTER TABLE withholding_remittances ENABLE ROW LEVEL SECURITY;

-- Read for members; every write goes through the SECURITY DEFINER RPCs so the
-- controlled flow is the only way a remittance reaches 'posted' (and thus the
-- only way remitted_prior is fed / a WHTREM JE is classified).
CREATE POLICY wht_remit_read ON withholding_remittances
  FOR SELECT TO authenticated USING (is_company_member(company_id));

GRANT SELECT ON withholding_remittances TO authenticated;

CREATE TRIGGER trg_withholding_remittances_updated_at
  BEFORE UPDATE ON withholding_remittances
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- PXL-DA-011 header immutability: once out of draft only controlled lifecycle
-- metadata may change; business columns freeze; DELETE outside draft blocked.
CREATE TRIGGER trg_guard_header_withholding_remittances
  BEFORE UPDATE OR DELETE ON withholding_remittances
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header(
    'status', 'draft',
    'journal_entry_id,fiscal_period_id,posted_at,posted_by,voided_at,voided_by,void_reason',
    '', 'same_txn');

COMMENT ON TABLE withholding_remittances IS
  'Governed EWT (0619-E/1601EQ) remittance and CWT-application documents; posting JEs are classified WHTREM so withholding reconciliation excludes them (PXL-AUD-041).';

-- ── 2. Register the posting source type ────────────────────────────────────────

INSERT INTO ref_posting_source_types (
  document_type, source_table, document_number_column, document_date_column,
  status_column, route_path, display_name, allows_multiple_journal_entries
) VALUES
  ('WHTREM', 'withholding_remittances', 'remittance_number', 'remittance_date',
   'status', '/withholding-remittances', 'Withholding Remittance', false);

-- A remittance owns at most one live (non-reversal) JE.
DROP INDEX IF EXISTS ux_journal_entries_live_source;
CREATE UNIQUE INDEX ux_journal_entries_live_source
  ON journal_entries (company_id, reference_doc_type, reference_doc_id)
  WHERE reference_doc_id IS NOT NULL
    AND status IN ('posted', 'reversed')
    AND je_number NOT LIKE '%-REV-%'
    AND je_number NOT LIKE 'JE-VOID-%'
    AND reference_doc_type IN (
      'SI','OR','CM','DM','VB','PV','CP','VC','FT','IBT','BADJ','PCV','PCR','CV',
      'PR','INV_ADJ','INV_STX','INV_GI','INV_COUNT',
      'FA','FA_DEPR','FA_DISP','FA_IMP','AMORT','REVREC','WHTREM'
    );

-- ── 3. Draft lifecycle + posting ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_save_withholding_remittance(
  p_id                    UUID,
  p_company_id            UUID,
  p_branch_id             UUID,
  p_remittance_number     TEXT,
  p_remittance_kind       TEXT,
  p_form_type             TEXT,
  p_period_year           INTEGER,
  p_period_month          INTEGER,
  p_period_quarter        INTEGER,
  p_remittance_date       DATE,
  p_amount                NUMERIC,
  p_settlement_account_id UUID,
  p_reference_no          TEXT,
  p_particulars           TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_kind   TEXT := lower(btrim(COALESCE(p_remittance_kind, '')));
  v_cfg    company_accounting_config%ROWTYPE;
  v_id     UUID;
  v_status TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF v_kind NOT IN ('ewt_payable', 'cwt_receivable') THEN
    RAISE EXCEPTION 'Invalid remittance kind %; expected ewt_payable or cwt_receivable', p_remittance_kind;
  END IF;
  IF btrim(COALESCE(p_remittance_number, '')) = '' THEN
    RAISE EXCEPTION 'A remittance number is required';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Remittance amount must be greater than zero';
  END IF;
  IF p_period_year IS NULL THEN
    RAISE EXCEPTION 'A period year is required';
  END IF;
  IF p_remittance_date IS NULL THEN
    RAISE EXCEPTION 'A remittance date is required';
  END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = p_branch_id AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;

  -- Settlement (cash/bank for EWT; income-tax-due for CWT) must be a postable
  -- account of this company.
  PERFORM fn_require_postable_account(p_company_id, p_settlement_account_id,
    'Remittance settlement account');

  -- The relevant withholding control account must be configured.
  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = p_company_id;
  IF v_kind = 'ewt_payable' AND (NOT FOUND OR v_cfg.ewt_payable_account_id IS NULL) THEN
    RAISE EXCEPTION 'EWT Payable control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_kind = 'cwt_receivable' AND (NOT FOUND OR v_cfg.ewt_withheld_account_id IS NULL) THEN
    RAISE EXCEPTION 'CWT Receivable (EWT withheld) control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO withholding_remittances (
      company_id, branch_id, remittance_number, remittance_kind, form_type,
      period_year, period_month, period_quarter, remittance_date, amount,
      settlement_account_id, reference_no, particulars, status,
      created_by, updated_by
    ) VALUES (
      p_company_id, p_branch_id, btrim(p_remittance_number), v_kind, NULLIF(btrim(COALESCE(p_form_type,'')), ''),
      p_period_year, p_period_month, p_period_quarter, p_remittance_date, ROUND(p_amount, 2),
      p_settlement_account_id, NULLIF(btrim(COALESCE(p_reference_no,'')), ''), NULLIF(btrim(COALESCE(p_particulars,'')), ''), 'draft',
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_id;
  ELSE
    SELECT status INTO v_status FROM withholding_remittances
    WHERE id = p_id AND company_id = p_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Withholding remittance not found';
    END IF;
    IF v_status <> 'draft' THEN
      RAISE EXCEPTION 'Only draft remittances can be edited (current status: %)', v_status;
    END IF;
    UPDATE withholding_remittances SET
      branch_id = p_branch_id,
      remittance_number = btrim(p_remittance_number),
      remittance_kind = v_kind,
      form_type = NULLIF(btrim(COALESCE(p_form_type,'')), ''),
      period_year = p_period_year,
      period_month = p_period_month,
      period_quarter = p_period_quarter,
      remittance_date = p_remittance_date,
      amount = ROUND(p_amount, 2),
      settlement_account_id = p_settlement_account_id,
      reference_no = NULLIF(btrim(COALESCE(p_reference_no,'')), ''),
      particulars = NULLIF(btrim(COALESCE(p_particulars,'')), ''),
      updated_by = auth.uid(), updated_at = NOW()
    WHERE id = p_id;
    v_id := p_id;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_withholding_remittance(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec         withholding_remittances%ROWTYPE;
  v_cfg         company_accounting_config%ROWTYPE;
  v_control_id  UUID;
  v_je_id       UUID;
  v_desc        TEXT;
BEGIN
  SELECT * INTO v_rec FROM withholding_remittances WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withholding remittance not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft remittances can be posted (current status: %)', v_rec.status;
  END IF;
  IF v_rec.amount <= 0 THEN
    RAISE EXCEPTION 'Remittance amount must be greater than zero';
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF v_rec.remittance_kind = 'ewt_payable' THEN
    v_control_id := v_cfg.ewt_payable_account_id;
    IF v_control_id IS NULL THEN
      RAISE EXCEPTION 'EWT Payable control account not configured.';
    END IF;
  ELSE
    v_control_id := v_cfg.ewt_withheld_account_id;
    IF v_control_id IS NULL THEN
      RAISE EXCEPTION 'CWT Receivable (EWT withheld) control account not configured.';
    END IF;
  END IF;

  v_desc := 'Withholding remittance ' || v_rec.remittance_number
            || ' (' || v_rec.remittance_kind || ')';

  -- Uses the governed posting engine: source integrity, postable accounts,
  -- open fiscal period, and balance are all enforced by the helpers.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-WHTREM-' || v_rec.remittance_number,
    v_rec.remittance_date, v_desc, 'WHTREM', v_rec.id
  );

  IF v_rec.remittance_kind = 'ewt_payable' THEN
    -- Remit withheld EWT to the BIR: clear the payable, pay from cash/bank.
    PERFORM fn_add_posting_line(v_je_id, 1, v_control_id,
      'EWT remitted to BIR — ' || v_rec.remittance_number, v_rec.amount, 0, v_rec.branch_id);
    PERFORM fn_add_posting_line(v_je_id, 2, v_rec.settlement_account_id,
      'Payment of EWT — ' || v_rec.remittance_number, 0, v_rec.amount, v_rec.branch_id);
  ELSE
    -- Apply CWT withheld by customers against income tax due.
    PERFORM fn_add_posting_line(v_je_id, 1, v_rec.settlement_account_id,
      'CWT applied to income tax due — ' || v_rec.remittance_number, v_rec.amount, 0, v_rec.branch_id);
    PERFORM fn_add_posting_line(v_je_id, 2, v_control_id,
      'CWT receivable applied — ' || v_rec.remittance_number, 0, v_rec.amount, v_rec.branch_id);
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE withholding_remittances SET
    status = 'posted', journal_entry_id = v_je_id,
    fiscal_period_id = (SELECT fiscal_period_id FROM journal_entries WHERE id = v_je_id),
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_void_withholding_remittance(p_id UUID, p_reason TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec        withholding_remittances%ROWTYPE;
  v_reversal   UUID;
BEGIN
  SELECT * INTO v_rec FROM withholding_remittances WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withholding remittance not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status <> 'posted' THEN
    RAISE EXCEPTION 'Only posted remittances can be voided (current status: %)', v_rec.status;
  END IF;
  IF btrim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'A void reason is required';
  END IF;

  v_reversal := fn_reverse_posted_journal_entry(
    v_rec.journal_entry_id, CURRENT_DATE, 'WHTREM', v_rec.id,
    'JE-WHTREM-REV-' || v_rec.remittance_number,
    'Void remittance ' || v_rec.remittance_number || ' — ' || btrim(p_reason)
  );

  UPDATE withholding_remittances SET
    status = 'voided', void_reason = btrim(p_reason),
    voided_at = NOW(), voided_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  RETURN v_reversal;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_withholding_remittance(
  UUID, UUID, UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER, DATE, NUMERIC, UUID, TEXT, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_withholding_remittance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_withholding_remittance(UUID, TEXT) TO authenticated;

-- ── 4. Derive 1601EQ remitted_prior from controlled remittances ────────────────

CREATE OR REPLACE FUNCTION fn_compute_ewt_remitted_prior(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER
)
RETURNS NUMERIC(15,2)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_month1 INTEGER;
  v_month2 INTEGER;
  v_total  NUMERIC(15,2);
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_quarter IS NULL OR p_quarter NOT BETWEEN 1 AND 4 OR p_year IS NULL THEN
    RAISE EXCEPTION 'Invalid period: year %, quarter %', p_year, p_quarter;
  END IF;

  -- Months 1 and 2 of the quarter are remitted monthly (0619-E) and netted as
  -- "remitted prior" on the quarterly 1601EQ; month 3 is paid with the return.
  v_month1 := (p_quarter - 1) * 3 + 1;
  v_month2 := (p_quarter - 1) * 3 + 2;

  SELECT COALESCE(SUM(amount), 0)::NUMERIC(15,2)
  INTO v_total
  FROM withholding_remittances
  WHERE company_id = p_company_id
    AND remittance_kind = 'ewt_payable'
    AND status = 'posted'
    AND period_year = p_year
    AND period_month IN (v_month1, v_month2);

  RETURN v_total;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_compute_ewt_remitted_prior(UUID, INTEGER, INTEGER) TO authenticated;

COMMENT ON FUNCTION fn_compute_ewt_remitted_prior(UUID, INTEGER, INTEGER) IS
  '1601EQ remitted_prior derived from posted EWT remittances covering months 1-2 of the quarter (PXL-AUD-041/034).';

-- ── 5. Reconciliation excludes controlled remittance/application JEs ───────────
-- Only WHTREM (the governed document) is excluded; uncontrolled MANUAL
-- remittance JEs still surface as variance, exactly as before.

CREATE OR REPLACE FUNCTION fn_wht_gl_reconciliation(
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
      AND tde.tax_kind IN ('ewt_payable', 'cwt_receivable')
      AND tde.document_date BETWEEN p_date_from AND p_date_to
    GROUP BY tde.tax_kind
  ),
  kinds AS (
    SELECT 'cwt_receivable'::TEXT AS kind, v_cfg.ewt_withheld_account_id AS account_id, 'debit'::TEXT AS normal
    UNION ALL
    SELECT 'ewt_payable'::TEXT,            v_cfg.ewt_payable_account_id,               'credit'::TEXT
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
                    -- Exclude the controlled remittance/application document: its
                    -- movement settles the control account and must not appear as
                    -- withholding-vs-GL variance (PXL-AUD-041).
                    AND je.reference_doc_type IS DISTINCT FROM 'WHTREM'
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

GRANT EXECUTE ON FUNCTION fn_wht_gl_reconciliation(UUID, DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_wht_gl_reconciliation(UUID, DATE, DATE) IS
  'Compares ewt_payable/cwt_receivable tax ledger sums to the GL withholding control accounts, excluding controlled WHTREM remittance/application JEs (PXL-AUD-041).';

-- ── 6. 1601EQ gate: remitted_prior must equal the derived remittances ──────────

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
  v_remitted_prior  NUMERIC(15,2);
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

  -- remitted_prior must match the controlled 0619-E remittances for the quarter
  -- (PXL-AUD-041 closes the PXL-AUD-034 free-entry residue).
  v_remitted_prior := fn_compute_ewt_remitted_prior(
    NEW.company_id, NEW.period_year, NEW.period_quarter);
  IF ABS(NEW.remitted_prior - v_remitted_prior) > 0.01 THEN
    RAISE EXCEPTION
      '1601EQ return cannot be marked %: remitted prior % does not match the controlled 0619-E remittances % for the quarter (record them as posted withholding remittances).',
      NEW.status, NEW.remitted_prior, v_remitted_prior;
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
