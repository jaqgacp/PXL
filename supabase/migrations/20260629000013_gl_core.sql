-- ══════════════════════════════════════════════════════════════════════════════
-- GL CORE: Journal Entries + Company Accounting Config
-- "Posted" now means posted to the books with a balanced journal entry.
-- Posting RPCs require company_accounting_config to be set up before any
-- document can move to posted status.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── company_accounting_config ─────────────────────────────────────────────────
-- Stores the canonical GL account IDs needed for automated journal entry creation.
-- Each company must configure this before posting is allowed.

CREATE TABLE IF NOT EXISTS company_accounting_config (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL UNIQUE REFERENCES companies(id),
  ar_account_id          UUID        REFERENCES chart_of_accounts(id),
  vat_payable_account_id UUID        REFERENCES chart_of_accounts(id),
  ewt_withheld_account_id UUID       REFERENCES chart_of_accounts(id),
  default_cash_account_id UUID       REFERENCES chart_of_accounts(id),
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_company_accounting_config_updated_at
  BEFORE UPDATE ON company_accounting_config
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE company_accounting_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cac_read"   ON company_accounting_config FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cac_insert" ON company_accounting_config FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "cac_update" ON company_accounting_config FOR UPDATE TO authenticated USING (can_admin_company(company_id));

-- ── journal_entries ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS journal_entries (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID        NOT NULL REFERENCES companies(id),
  branch_id               UUID        REFERENCES branches(id),
  je_number               TEXT        NOT NULL,
  je_date                 DATE        NOT NULL,
  fiscal_period_id        UUID        REFERENCES fiscal_periods(id),
  description             TEXT,
  reference_doc_type      TEXT        CHECK (reference_doc_type IN ('SI','OR','CM','DM','MANUAL')),
  reference_doc_id        UUID,
  status                  TEXT        NOT NULL DEFAULT 'posted'
                                      CHECK (status IN ('draft','posted','reversed')),
  total_debit             NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_credit            NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, je_number)
);

CREATE TABLE IF NOT EXISTS journal_entry_lines (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  je_id         UUID          NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  company_id    UUID          NOT NULL REFERENCES companies(id),
  line_number   INT           NOT NULL,
  account_id    UUID          NOT NULL REFERENCES chart_of_accounts(id),
  description   TEXT,
  debit_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  credit_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by    UUID,
  updated_by    UUID,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (debit_amount >= 0 AND credit_amount >= 0),
  CHECK (debit_amount = 0 OR credit_amount = 0)
);

CREATE INDEX idx_je_company_date ON journal_entries (company_id, je_date DESC);
CREATE INDEX idx_jel_je_id       ON journal_entry_lines (je_id);
CREATE INDEX idx_jel_account_id  ON journal_entry_lines (account_id);

CREATE TRIGGER trg_journal_entries_updated_at
  BEFORE UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_journal_entry_lines_updated_at
  BEFORE UPDATE ON journal_entry_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE journal_entries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry_lines  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "je_read"   ON journal_entries     FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "jel_read"  ON journal_entry_lines FOR SELECT TO authenticated
  USING (je_id IN (SELECT id FROM journal_entries WHERE is_company_member(company_id)));

-- ── Update fn_post_sales_invoice: create real journal entry ───────────────────

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec      sales_invoices%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_line_no  INT := 1;
  v_total_dr NUMERIC(15,2) := 0;
  v_total_cr NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved invoices can be posted (current status: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.date AND end_date >= v_rec.date AND is_locked = false LIMIT 1;

  -- Create journal entry header
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date, v_fp_id,
    'Sales Invoice ' || v_rec.si_number || ' — ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Receivable for total invoice amount
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id, 'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());
  v_line_no := 2;

  -- CR: Revenue per line (net_amount per revenue account)
  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum, sil.description AS ln_desc
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id, 'Revenue — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_line_no := v_line_no + 1;
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  -- CR: VAT Payable if any
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_rec.si_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  -- Verify the entry is balanced (debit = credit); if not, surface the issue
  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check that all lines have revenue accounts assigned.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── Update fn_post_receipt: create real journal entry ─────────────────────────

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       receipts%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ar_cr     NUMERIC(15,2);
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_cwt > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in GL Posting Configuration.';
  END IF;

  -- Determine cash/bank account: prefer bank_account_id (already a COA id), else default_cash_account_id
  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.receipt_date AND end_date >= v_rec.receipt_date AND is_locked = false LIMIT 1;

  v_ar_cr := v_rec.total_amount + v_rec.total_cwt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date, v_fp_id,
    'Official Receipt ' || v_rec.receipt_number || ' — ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id, 'posted',
    v_ar_cr, v_ar_cr,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Cash / Bank
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cash_acct, 'Cash received — ' || v_rec.receipt_number, v_rec.total_amount, 0, auth.uid(), auth.uid());

  -- DR: EWT Withheld (if applicable)
  IF v_rec.total_cwt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 2, v_cfg.ewt_withheld_account_id, 'EWT withheld — ' || v_rec.receipt_number, v_rec.total_cwt, 0, auth.uid(), auth.uid());
  END IF;

  -- CR: Accounts Receivable (total cash + CWT clears the full invoice)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
          v_cfg.ar_account_id, 'AR cleared — ' || v_rec.receipt_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- Grant execute
GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID)        TO authenticated;
