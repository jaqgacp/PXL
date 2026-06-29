-- ══════════════════════════════════════════════════════════════════════════════
-- HARDENING V2: Accounting Integrity Fixes
-- Covers: C0 FK patches for existing installs, reference_doc_type extension,
-- period enforcement, EWT/ATC validation, CWT bug fix, reversal JEs,
-- CM/DM GL posting, tax ledger, vendor credit applications, purchase return GL
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. FK patches for existing installs (017 migration had wrong table refs) ─

-- Drop the wrong constraint on vendor_bills.void_reason_id → void_reasons
-- and recreate pointing to void_reason_codes (global reference table)
ALTER TABLE vendor_bills
  DROP CONSTRAINT IF EXISTS vendor_bills_void_reason_id_fkey;
ALTER TABLE vendor_bills
  ADD CONSTRAINT vendor_bills_void_reason_id_fkey
    FOREIGN KEY (void_reason_id) REFERENCES void_reason_codes(id);

-- Drop the wrong constraint on payment_vouchers.payment_mode_id → payment_modes
-- and recreate pointing to ref_payment_modes (canonical global reference table)
ALTER TABLE payment_vouchers
  DROP CONSTRAINT IF EXISTS payment_vouchers_payment_mode_id_fkey;
ALTER TABLE payment_vouchers
  ADD CONSTRAINT payment_vouchers_payment_mode_id_fkey
    FOREIGN KEY (payment_mode_id) REFERENCES ref_payment_modes(id);

-- ── 2. Extend reference_doc_type to include AP document types ─────────────────

ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_reference_doc_type_check;
ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_reference_doc_type_check
    CHECK (reference_doc_type IN ('SI','OR','CM','DM','MANUAL','VB','PV','CP','VC','REV'));

-- ── 3. New tables ─────────────────────────────────────────────────────────────

-- tax_detail_entries: immutable tax ledger populated at posting time
CREATE TABLE IF NOT EXISTS tax_detail_entries (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID          NOT NULL REFERENCES companies(id),
  branch_id             UUID          REFERENCES branches(id),
  source_doc_type       TEXT          NOT NULL,
  source_doc_id         UUID          NOT NULL,
  tax_kind              TEXT          NOT NULL
                                      CHECK (tax_kind IN ('output_vat','input_vat','ewt_payable','cwt_receivable','percentage_tax')),
  tax_code_id           UUID          REFERENCES tax_codes(id),
  vat_code_id           UUID          REFERENCES vat_codes(id),
  atc_code_id           UUID          REFERENCES atc_codes(id),
  tax_base              NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_rate              NUMERIC(5,2),
  tax_amount            NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_period_id         UUID          REFERENCES fiscal_periods(id),
  posting_date          DATE          NOT NULL,
  document_date         DATE          NOT NULL,
  counterparty_id       UUID,
  counterparty_tin      TEXT,
  counterparty_name     TEXT,
  is_reversal           BOOLEAN       NOT NULL DEFAULT false,
  reverses_tax_detail_id UUID         REFERENCES tax_detail_entries(id),
  filing_status         TEXT          NOT NULL DEFAULT 'draft'
                                      CHECK (filing_status IN ('draft','final','filed','amended')),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tde_company_period ON tax_detail_entries (company_id, tax_period_id, tax_kind);
CREATE INDEX IF NOT EXISTS idx_tde_source         ON tax_detail_entries (source_doc_type, source_doc_id);

ALTER TABLE tax_detail_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tde_read"   ON tax_detail_entries FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "tde_insert" ON tax_detail_entries FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

-- vendor_credit_applications: track how vendor credits are applied to vendor bills
CREATE TABLE IF NOT EXISTS vendor_credit_applications (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID          NOT NULL REFERENCES companies(id),
  vendor_credit_id UUID          NOT NULL REFERENCES vendor_credits(id),
  vendor_bill_id   UUID          NOT NULL REFERENCES vendor_bills(id),
  applied_amount   NUMERIC(15,2) NOT NULL CHECK (applied_amount > 0),
  applied_date     DATE          NOT NULL,
  applied_by       UUID,
  remarks          TEXT,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (vendor_credit_id, vendor_bill_id)
);

CREATE INDEX IF NOT EXISTS idx_vca_credit ON vendor_credit_applications (vendor_credit_id);
CREATE INDEX IF NOT EXISTS idx_vca_bill   ON vendor_credit_applications (vendor_bill_id);

ALTER TABLE vendor_credit_applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vca_read"   ON vendor_credit_applications FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "vca_insert" ON vendor_credit_applications FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "vca_delete" ON vendor_credit_applications FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── 4. Column additions ───────────────────────────────────────────────────────

ALTER TABLE purchase_returns ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id);
ALTER TABLE credit_memos     ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id);
ALTER TABLE credit_memos     ADD COLUMN IF NOT EXISTS posted_at        TIMESTAMPTZ;
ALTER TABLE credit_memos     ADD COLUMN IF NOT EXISTS posted_by        UUID;
ALTER TABLE debit_memos      ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES journal_entries(id);
ALTER TABLE debit_memos      ADD COLUMN IF NOT EXISTS posted_at        TIMESTAMPTZ;
ALTER TABLE debit_memos      ADD COLUMN IF NOT EXISTS posted_by        UUID;

-- ── 5. Fix fn_save_cash_sale: CWT accounting bug ──────────────────────────────
-- Bug: receipt JE debited Cash at gross + CWT and credited AR at gross + CWT.
-- Fix: DR Cash = gross − CWT (net received), DR CWT Receivable = CWT, CR AR = gross.

CREATE OR REPLACE FUNCTION fn_save_cash_sale(
  p_header       JSONB,
  p_lines        JSONB,
  p_cwt_amount   NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id    UUID;
  v_branch_id     UUID;
  v_si_id         UUID;
  v_receipt_id    UUID;
  v_si_number     TEXT;
  v_or_number     TEXT;
  v_cfg           company_accounting_config%ROWTYPE;
  v_cash_acct     UUID;
  v_fp_id         UUID;
  v_je_si_id      UUID;
  v_je_or_id      UUID;
  v_grand_total   NUMERIC(15,2) := 0;
  v_total_vat     NUMERIC(15,2) := 0;
  v_total_cr      NUMERIC(15,2) := 0;
  v_rev_line      RECORD;
  v_rev_line_no   INT;
  v_line          JSONB;
  v_net           NUMERIC(15,2);
  v_vat           NUMERIC(15,2);
  v_line_no_si    INT := 1;
  v_cash_received NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id','')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := NULLIF(p_header->>'bank_account_id','')::UUID;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := v_cfg.default_cash_account_id;
  END IF;
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No cash/bank account specified and no default cash account configured.';
  END IF;
  IF p_cwt_amount > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld (CWT Receivable) account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for date %. Create or unlock a fiscal period.', (p_header->>'date')::DATE;
  END IF;

  -- Number series
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'CS');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Compute totals from lines
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_net         := COALESCE((v_line->>'net_amount')::NUMERIC, 0);
    v_vat         := COALESCE((v_line->>'vat_amount')::NUMERIC, 0);
    v_grand_total := v_grand_total + v_net + v_vat;
    v_total_vat   := v_total_vat + v_vat;
  END LOOP;

  -- Insert SI
  INSERT INTO sales_invoices (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    si_number, date, due_date, currency_code, remarks,
    total_amount, total_vat_amount, total_net_amount, total_taxable_amount,
    total_zero_rated_amount, total_exempt_amount,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot',''),
    v_si_number,
    (p_header->>'date')::DATE,
    (p_header->>'date')::DATE,
    COALESCE(NULLIF(p_header->>'currency_code',''),'PHP'),
    NULLIF(p_header->>'memo',''),
    v_grand_total, v_total_vat, v_grand_total - v_total_vat, v_grand_total - v_total_vat,
    0, 0,
    true, 'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_si_id;

  -- Insert SI lines
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description,
      quantity, unit_price, discount_amount, net_amount,
      vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no_si,
      NULLIF(v_line->>'item_id','')::UUID,
      v_line->>'description',
      COALESCE((v_line->>'quantity')::NUMERIC,1),
      COALESCE((v_line->>'unit_price')::NUMERIC,0),
      COALESCE((v_line->>'discount_amount')::NUMERIC,0),
      COALESCE((v_line->>'net_amount')::NUMERIC,0),
      NULLIF(v_line->>'vat_code_id','')::UUID,
      COALESCE((v_line->>'vat_amount')::NUMERIC,0),
      COALESCE((v_line->>'total_amount')::NUMERIC,0),
      NULLIF(v_line->>'revenue_account_id','')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no_si := v_line_no_si + 1;
  END LOOP;

  -- Post SI JE: DR AR, CR Revenue lines, CR VAT Payable
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id, 'posted', v_grand_total, v_grand_total, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_si_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_si_id, v_company_id, 1, v_cfg.ar_account_id, 'AR — ' || (p_header->>'customer_name_snapshot'), v_grand_total, 0, auth.uid(), auth.uid());

  v_rev_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_rev_line.revenue_account_id, 'Revenue — ' || v_rev_line.ln_desc, 0, v_rev_line.net_sum, auth.uid(), auth.uid());
    v_total_cr    := v_total_cr + v_rev_line.net_sum;
    v_rev_line_no := v_rev_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_si_number, 0, v_total_vat, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_total_vat;
  END IF;

  UPDATE sales_invoices SET
    status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_si_id, approved_by = auth.uid(), approved_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- ── Receipt JE (CWT fix) ─────────────────────────────────────────────────
  -- v_grand_total = full invoice amount (what AR carries)
  -- p_cwt_amount  = portion withheld by customer as EWT/CWT
  -- v_cash_received = actual cash deposited = grand_total − cwt
  v_cash_received := v_grand_total - p_cwt_amount;

  INSERT INTO receipts (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    receipt_number, receipt_date, payment_mode_id, bank_account_id,
    total_amount, total_cwt, remarks, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot',''),
    v_or_number, (p_header->>'date')::DATE,
    NULLIF(p_header->>'payment_mode_id','')::UUID, v_cash_acct,
    v_grand_total, p_cwt_amount, 'Cash Sale — ' || v_si_number,
    'posted', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total, p_cwt_amount, auth.uid(), auth.uid());

  -- Post receipt JE: DR Cash (net) + DR CWT Receivable = CR AR (gross)
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-OR-' || v_or_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id, 'posted', v_grand_total, v_grand_total, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_or_id;

  -- DR: Cash / Bank (net of CWT)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, 1, v_cash_acct, 'Cash received — ' || v_or_number, v_cash_received, 0, auth.uid(), auth.uid());

  -- DR: CWT Receivable (tax withheld by customer, to be reclaimed)
  IF p_cwt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_or_id, v_company_id, 2, v_cfg.ewt_withheld_account_id, 'CWT receivable — ' || v_or_number, p_cwt_amount, 0, auth.uid(), auth.uid());
  END IF;

  -- CR: Accounts Receivable (full invoice amount)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_cfg.ar_account_id, 'AR cleared — ' || v_or_number, 0, v_grand_total, auth.uid(), auth.uid());

  UPDATE receipts SET journal_entry_id = v_je_or_id, posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number
  );
END;
$$;

-- ── 6. Fix fn_post_vendor_bill: period enforcement + correct doc type ─────────

CREATE OR REPLACE FUNCTION fn_post_vendor_bill(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec      vendor_bills%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_line_no  INT;
  v_total_dr NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved bills can be posted (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.bill_date
    AND end_date >= v_rec.bill_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for bill date %. Create or unlock a fiscal period first.', v_rec.bill_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date, v_fp_id,
    'Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
    'VB', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  v_line_no := 1;
  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_bill_lines
    WHERE vendor_bill_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.bill_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE vendor_bills SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Populate tax ledger for input VAT
  IF v_rec.total_input_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id,
      'input_vat', v_rec.total_taxable_amount, v_rec.total_input_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END IF;
END;
$$;

-- ── 7. Fix fn_post_payment_voucher: period enforcement, EWT/ATC, doc type ─────

CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_ap_dr     NUMERIC(15,2);
  v_line_no   INT := 1;
  v_pvl       RECORD;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft vouchers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_ewt > 0 AND v_cfg.ewt_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on voucher and no default cash account configured.';
  END IF;

  -- Validate: EWT amount > 0 requires ATC code per line
  FOR v_pvl IN
    SELECT id, ewt_amount, atc_code_id FROM payment_voucher_lines
    WHERE payment_voucher_id = p_voucher_id AND ewt_amount > 0
  LOOP
    IF v_pvl.atc_code_id IS NULL THEN
      RAISE EXCEPTION 'ATC code is required on payment voucher line when EWT amount is specified. Set the ATC code before posting.';
    END IF;
  END LOOP;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for voucher date %. Create or unlock a fiscal period first.', v_rec.voucher_date;
  END IF;

  v_ap_dr := v_rec.total_amount + v_rec.total_ewt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date, v_fp_id,
    'Payment Voucher ' || v_rec.voucher_number || ' — ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id, 'posted',
    v_ap_dr, v_ap_dr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP cleared — ' || v_rec.voucher_number, v_ap_dr, 0, auth.uid(), auth.uid());

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 2, v_cash_acct,
          'Cash paid — ' || v_rec.voucher_number, 0, v_rec.total_amount, auth.uid(), auth.uid());
  v_line_no := 3;

  IF v_rec.total_ewt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ewt_payable_account_id,
            'EWT withheld — ' || v_rec.voucher_number, 0, v_rec.total_ewt, auth.uid(), auth.uid());
    v_line_no := v_line_no + 1;
  END IF;

  UPDATE payment_vouchers SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Populate EWT tax ledger
  IF v_rec.total_ewt > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id,
      'ewt_payable', v_rec.total_amount, v_rec.total_ewt, v_fp_id,
      NOW()::DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END IF;
END;
$$;

-- ── 8. Fix fn_post_cash_purchase: period enforcement + doc type ───────────────

CREATE OR REPLACE FUNCTION fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM cash_purchases WHERE id = p_cp_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft cash purchases can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  v_cash_acct := COALESCE(v_rec.payment_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'Payment account not set. Add it on the form or configure a default cash account.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND (NOT FOUND OR v_cfg.input_vat_account_id IS NULL) THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.transaction_date
    AND end_date >= v_rec.transaction_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for transaction date %. Create or unlock a fiscal period first.', v_rec.transaction_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CP-' || v_rec.cp_number, v_rec.transaction_date, v_fp_id,
    'Cash Purchase ' || v_rec.cp_number || COALESCE(' — ' || v_rec.supplier_name_snapshot, ''),
    'CP', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM cash_purchase_lines
    WHERE cp_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Expense — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.cp_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cash_acct,
          'Cash paid — ' || v_rec.cp_number, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE cash_purchases SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 9. Fix fn_post_vendor_credit: period enforcement + doc type ───────────────

CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.credit_date
    AND end_date >= v_rec.credit_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for credit date %. Create or unlock a fiscal period first.', v_rec.credit_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date, v_fp_id,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'VC', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 10. fn_void_sales_invoice: add reversing JE ───────────────────────────────

CREATE OR REPLACE FUNCTION fn_void_sales_invoice(
  p_invoice_id     UUID,
  p_void_reason_id UUID,
  p_memo           TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       sales_invoices%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_orig_line RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN RAISE EXCEPTION 'Invoice is already voided'; END IF;

  IF p_void_reason_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid or inactive void reason';
  END IF;

  -- Create reversing JE only if the SI was posted
  IF v_rec.status = 'posted' AND v_rec.journal_entry_id IS NOT NULL THEN
    SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;

    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for today. Cannot post reversal. Unlock a period first.';
    END IF;

    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_rec.company_id, v_rec.branch_id,
      'JE-REV-' || v_rec.si_number, CURRENT_DATE, v_fp_id,
      'Reversal of SI ' || v_rec.si_number || ' — ' || v_rec.customer_name_snapshot,
      'REV', v_rec.id, 'posted',
      v_rec.total_amount, v_rec.total_amount,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_rev_je_id;

    FOR v_orig_line IN
      SELECT * FROM journal_entry_lines WHERE je_id = v_rec.journal_entry_id ORDER BY line_number
    LOOP
      INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
      VALUES (v_rev_je_id, v_rec.company_id, v_line_no, v_orig_line.account_id,
              'Reversal: ' || COALESCE(v_orig_line.description,''),
              v_orig_line.credit_amount, v_orig_line.debit_amount,
              auth.uid(), auth.uid());
      v_line_no := v_line_no + 1;
    END LOOP;

    -- Mark original JE as reversed
    UPDATE journal_entries SET status = 'reversed', updated_at = NOW() WHERE id = v_rec.journal_entry_id;
  END IF;

  UPDATE sales_invoices SET
    status         = 'cancelled',
    void_reason_id = p_void_reason_id,
    memo           = COALESCE(NULLIF(p_memo,''), v_rec.memo),
    updated_by     = auth.uid(),
    updated_at     = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- ── 11. fn_bounce_receipt: add reversing JE ───────────────────────────────────

CREATE OR REPLACE FUNCTION fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       receipts%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_orig_line RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted receipts can be marked as bounced (current status: %)', v_rec.status;
  END IF;

  IF v_rec.journal_entry_id IS NOT NULL THEN
    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for today. Cannot post bounce reversal. Unlock a period first.';
    END IF;

    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_rec.company_id, v_rec.branch_id,
      'JE-REV-' || v_rec.receipt_number, CURRENT_DATE, v_fp_id,
      'Bounced Receipt ' || v_rec.receipt_number,
      'REV', v_rec.id, 'posted',
      v_rec.total_amount + v_rec.total_cwt,
      v_rec.total_amount + v_rec.total_cwt,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_rev_je_id;

    FOR v_orig_line IN
      SELECT * FROM journal_entry_lines WHERE je_id = v_rec.journal_entry_id ORDER BY line_number
    LOOP
      INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
      VALUES (v_rev_je_id, v_rec.company_id, v_line_no, v_orig_line.account_id,
              'Bounce reversal: ' || COALESCE(v_orig_line.description,''),
              v_orig_line.credit_amount, v_orig_line.debit_amount,
              auth.uid(), auth.uid());
      v_line_no := v_line_no + 1;
    END LOOP;

    UPDATE journal_entries SET status = 'reversed', updated_at = NOW() WHERE id = v_rec.journal_entry_id;
  END IF;

  UPDATE receipts SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- ── 12. fn_void_vendor_bill: add reversing JE ────────────────────────────────

CREATE OR REPLACE FUNCTION fn_void_vendor_bill(
  p_bill_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       vendor_bills%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_orig_line RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN RAISE EXCEPTION 'Bill is already cancelled'; END IF;

  IF v_rec.status = 'posted' AND v_rec.journal_entry_id IS NOT NULL THEN
    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for today. Cannot post void reversal. Unlock a period first.';
    END IF;

    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_rec.company_id, v_rec.branch_id,
      'JE-REV-' || v_rec.bill_number, CURRENT_DATE, v_fp_id,
      'Void of Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
      'REV', v_rec.id, 'posted',
      v_rec.total_amount, v_rec.total_amount,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_rev_je_id;

    FOR v_orig_line IN
      SELECT * FROM journal_entry_lines WHERE je_id = v_rec.journal_entry_id ORDER BY line_number
    LOOP
      INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
      VALUES (v_rev_je_id, v_rec.company_id, v_line_no, v_orig_line.account_id,
              'Void reversal: ' || COALESCE(v_orig_line.description,''),
              v_orig_line.credit_amount, v_orig_line.debit_amount,
              auth.uid(), auth.uid());
      v_line_no := v_line_no + 1;
    END LOOP;

    UPDATE journal_entries SET status = 'reversed', updated_at = NOW() WHERE id = v_rec.journal_entry_id;

    -- Mark tax detail entries as reversed
    UPDATE tax_detail_entries SET
      filing_status = 'amended',
      is_reversal   = true
    WHERE source_doc_type = 'VB' AND source_doc_id = p_bill_id AND is_reversal = false;
  END IF;

  UPDATE vendor_bills SET status = 'cancelled', void_reason_id = p_void_reason_id,
    memo = COALESCE(p_memo, memo), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_bill_id;
END;
$$;

-- ── 13. fn_post_credit_memo: GL posting ──────────────────────────────────────
-- DR: Sales Returns (per revenue_account_id) + DR: Output VAT reversal
-- CR: Accounts Receivable

CREATE OR REPLACE FUNCTION fn_post_credit_memo(p_cm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       credit_memos%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM credit_memos WHERE id = p_cm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Credit memo cannot be posted in status: %', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date, v_fp_id,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Sales Returns per revenue account (reversal of original revenue)
  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id,
            'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- DR: Output VAT reversal
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id,
            'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  -- CR: Accounts Receivable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ar_account_id,
          'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;
END;
$$;

-- ── 14. fn_post_debit_memo: GL posting ───────────────────────────────────────
-- DR: Accounts Receivable = CR: Revenue/Charge accounts + CR: Output VAT

CREATE OR REPLACE FUNCTION fn_post_debit_memo(p_dm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       debit_memos%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 2;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM debit_memos WHERE id = p_dm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Debit memo cannot be posted in status: %', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.dm_date
    AND end_date >= v_rec.dm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for DM date %. Create or unlock a fiscal period first.', v_rec.dm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-DM-' || v_rec.dm_number, v_rec.dm_date, v_fp_id,
    'Debit Memo ' || v_rec.dm_number || ' — ' || v_rec.customer_name_snapshot,
    'DM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Receivable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id,
          'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());

  -- CR: Revenue/Charge accounts per line
  FOR v_line IN
    SELECT account_id, SUM(amount) AS amt_sum, description AS ln_desc
    FROM debit_memo_lines
    WHERE debit_memo_id = v_rec.id AND account_id IS NOT NULL
    GROUP BY account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.account_id,
            'DM charge — ' || v_line.ln_desc, 0, v_line.amt_sum, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.amt_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  -- CR: Output VAT
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id,
            'Output VAT — ' || v_rec.dm_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'DM journal entry unbalanced: DR=% CR=%. Ensure all DM lines have GL accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE debit_memos SET
    status = 'paid', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_dm_id;
END;
$$;

-- ── 15. fn_complete_purchase_return: add GL effect ────────────────────────────
-- On completion, post a reversing GL entry:
-- DR: AP (if a vendor bill exists for the linked RR), otherwise expense accounts
-- CR: Expense accounts per line (reversal of original purchase)
-- CR: Input VAT reversal

CREATE OR REPLACE FUNCTION fn_complete_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec        purchase_returns%ROWTYPE;
  v_cfg        company_accounting_config%ROWTYPE;
  v_fp_id      UUID;
  v_je_id      UUID;
  v_vb_id      UUID;
  v_vb_posted  BOOLEAN := false;
  v_line       RECORD;
  v_line_no    INT := 1;
  v_total_cr   NUMERIC(15,2) := 0;
  v_total_vat  NUMERIC(15,2) := 0;
  v_ret_total  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM purchase_returns WHERE id = p_return_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Not found or access denied';
  END IF;
  IF v_rec.status != 'shipped' THEN
    RAISE EXCEPTION 'Only shipped returns can be completed (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;

  -- Find the linked vendor bill (if any, posted)
  SELECT vb.id, (vb.status = 'posted') INTO v_vb_id, v_vb_posted
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rec.rr_id AND vb.company_id = v_rec.company_id
  ORDER BY vb.created_at DESC LIMIT 1;

  -- Only post GL if we have an AP account and a posted vendor bill
  IF v_cfg.ap_account_id IS NOT NULL AND v_vb_posted THEN
    SELECT id INTO v_fp_id FROM fiscal_periods
    WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
      AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;

    IF v_fp_id IS NOT NULL THEN
      -- Compute return amounts from lines
      SELECT SUM(prl.return_qty * prl.unit_price) INTO v_ret_total
      FROM purchase_return_lines prl WHERE prl.return_id = p_return_id;

      IF v_ret_total > 0 THEN
        INSERT INTO journal_entries (
          company_id, branch_id, je_number, je_date, fiscal_period_id,
          description, reference_doc_type, reference_doc_id, status,
          total_debit, total_credit, created_by, updated_by
        ) VALUES (
          v_rec.company_id, v_rec.branch_id,
          'JE-PR-' || v_rec.return_number, CURRENT_DATE, v_fp_id,
          'Purchase Return ' || v_rec.return_number || ' — ' || v_rec.supplier_name_snapshot,
          'MANUAL', v_rec.id, 'posted',
          v_ret_total, v_ret_total,
          auth.uid(), auth.uid()
        ) RETURNING id INTO v_je_id;

        -- DR: AP (reduce liability for returned goods)
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
        VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
                'AP reversal — ' || v_rec.return_number, v_ret_total, 0, auth.uid(), auth.uid());

        -- CR: Expense accounts from original vendor bill lines (matched by item)
        FOR v_line IN
          SELECT vbl.expense_account_id,
                 SUM(LEAST(prl.return_qty, rrl.received_qty) * prl.unit_price) AS rev_amount,
                 vbl.description AS ln_desc
          FROM purchase_return_lines prl
          JOIN receiving_report_lines rrl ON rrl.id = prl.rr_line_id
          JOIN vendor_bill_lines vbl
            ON vbl.vendor_bill_id = v_vb_id AND vbl.item_id = prl.item_id
          WHERE prl.return_id = p_return_id AND vbl.expense_account_id IS NOT NULL
          GROUP BY vbl.expense_account_id, vbl.description
        LOOP
          v_line_no := v_line_no + 1;
          INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
          VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
                  'Return of: ' || v_line.ln_desc, 0, v_line.rev_amount, auth.uid(), auth.uid());
          v_total_cr := v_total_cr + v_line.rev_amount;
        END LOOP;

        -- Fallback: if no matched lines, credit AP directly (manual reconciliation needed)
        IF v_total_cr = 0 THEN
          UPDATE journal_entries SET total_debit = 0, total_credit = 0 WHERE id = v_je_id;
          DELETE FROM journal_entry_lines WHERE je_id = v_je_id;
          DELETE FROM journal_entries WHERE id = v_je_id;
          v_je_id := NULL;
        END IF;
      END IF;
    END IF;
  END IF;

  UPDATE purchase_returns SET
    status = 'completed',
    journal_entry_id = v_je_id,
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_return_id;
END;
$$;

-- ── 16. Grants ────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION fn_save_cash_sale(JSONB, JSONB, NUMERIC)         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_bill(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID)                     TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_cash_purchase(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_sales_invoice(UUID, UUID, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bounce_receipt(UUID)                           TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_vendor_bill(UUID, UUID, TEXT)             TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_credit_memo(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_debit_memo(UUID)                          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_complete_purchase_return(UUID)                 TO authenticated;
