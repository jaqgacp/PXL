-- ══════════════════════════════════════════════════════════════════════════════
-- VAT LEDGER COMPLETENESS (PXL-AUD-014 / PXL-DA-008)
--
-- The tax ledger (tax_detail_entries) previously recorded VAT only as a single
-- lump row per document, and only when tax_amount > 0:
--   - zero-rated and exempt documents of VAT companies wrote NO rows at all,
--   - mixed documents lost their zero-rated/exempt bases (the lump row carried
--     only total_taxable_amount, with no vat_code_id),
--   - cash sales wrote no output VAT or CWT rows and mis-stored zero-rated/
--     exempt header totals as 0,
--   - cash purchases wrote no input VAT rows.
-- SLSP/RELIEF and the 2550 zero-rated/exempt lines therefore could never be
-- ledger-backed.
--
-- Also fixes a latent runtime-fatal defect found by this migration's seeded
-- test (first execution of fn_save_cash_sale ever): the function inserted into
-- non-existent sales_invoices columns `remarks` (the column is `memo`) and
-- `total_net_amount` (the very column PXL-AUD-023 removed from
-- fn_post_sales_invoice), passed NULL payment_mode_id into the NOT NULL
-- receipts column (now defaulted to the seeded CASH mode), and inserted the
-- receipt as 'posted' before its lines, which the line-immutability trigger
-- rightly blocks (now draft -> lines -> posted, like the SI half). Every cash
-- sale failed at runtime — the same lazy-plpgsql-compile class as
-- PXL-AUD-023. Logged as PXL-AUD-028.
--
-- This migration makes the posting writers per-VAT-code:
--   one output_vat/input_vat row per (document, vat_code_id), tax_base = sum of
--   line net amounts, tax_amount = sum of line VAT (0 for zero-rated/exempt).
-- Writers are gated on companies.tax_registration = 'vat' and on the line
-- carrying a vat_code_id: the VAT subledger describes VAT-registered activity
-- only, so non-VAT/exempt companies keep writing nothing (PXL-AUD-006 gating,
-- asserted by NON-VAT-GATING-001).
-- Legacy lump rows (vat_code_id IS NULL) remain untouched as evidence and by
-- definition carry the document's regular VAT (20260702000002); consumers must
-- treat NULL vat_code_id as 'regular'.
--
-- Void/cancel/bounce netting needs no change: fn_reverse_tax_detail_entries
-- (20260702000009) copies and negates every non-reversal row of the document,
-- including the new zero-amount classification rows.
--
-- A backfill adds the missing per-code rows for already-posted documents
-- (skipping regular codes where a legacy lump row already carries them, and
-- skipping non-posted documents so void netting stays exact), plus CWT
-- receivable rows for posted cash-sale receipts.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Sales invoice posting: per-VAT-code output rows ─────────────────────────
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
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.date AND end_date >= v_rec.date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for invoice date %. Create or unlock a fiscal period first.', v_rec.date;
  END IF;

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

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ar_account_id, 'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, auth.uid(), auth.uid());
  v_line_no := 2;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum, sil.description AS ln_desc
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id, 'Revenue — ' || v_line.ln_desc, 0, v_line.net_sum, auth.uid(), auth.uid());
    v_line_no  := v_line_no + 1;
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.vat_payable_account_id, 'Output VAT — ' || v_rec.si_number, 0, v_rec.total_vat_amount, auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check that all lines have revenue accounts assigned.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Output VAT tax ledger: one row per VAT code, including zero-rated/exempt
  -- bases with zero tax (PXL-AUD-014).
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id,
    'output_vat', sil.vat_code_id,
    SUM(sil.net_amount), COALESCE(SUM(sil.vat_amount), 0), v_fp_id,
    NOW()::DATE, v_rec.date,
    v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
  FROM sales_invoice_lines sil
  WHERE sil.sales_invoice_id = v_rec.id
    AND sil.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat')
  GROUP BY sil.vat_code_id
  HAVING SUM(sil.net_amount) <> 0 OR COALESCE(SUM(sil.vat_amount), 0) <> 0;
END;
$$;

-- ── 2. Vendor bill posting: per-VAT-code input rows ────────────────────────────
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

  -- Input VAT tax ledger: one row per VAT code, including zero-rated/exempt
  -- bases with zero tax (PXL-AUD-014).
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id,
    'input_vat', vbl.vat_code_id,
    SUM(vbl.net_amount), COALESCE(SUM(vbl.input_vat_amount), 0), v_fp_id,
    NOW()::DATE, v_rec.bill_date,
    v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
  FROM vendor_bill_lines vbl
  WHERE vbl.vendor_bill_id = v_rec.id
    AND vbl.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat')
  GROUP BY vbl.vat_code_id
  HAVING SUM(vbl.net_amount) <> 0 OR COALESCE(SUM(vbl.input_vat_amount), 0) <> 0;
END;
$$;

-- ── 3. Cash sale: classification header totals + output VAT and CWT rows ───────
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
  v_total_taxable NUMERIC(15,2) := 0;
  v_total_zero    NUMERIC(15,2) := 0;
  v_total_exempt  NUMERIC(15,2) := 0;
  v_total_cr      NUMERIC(15,2) := 0;
  v_rev_line      RECORD;
  v_rev_line_no   INT;
  v_line          JSONB;
  v_qty           NUMERIC;
  v_price         NUMERIC;
  v_disc          NUMERIC;
  v_net           NUMERIC(15,2);
  v_vat           NUMERIC(15,2);
  v_class         TEXT;
  v_rate          NUMERIC;
  v_has_lines     BOOLEAN := false;
  v_cwt_atc       UUID;
  v_cwt_rate      NUMERIC;
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
  -- CWT requires an ATC (PXL-AUD-007 rules, enforced by the receipt-line
  -- validator); the ATC travels in the header as cwt_atc_id.
  v_cwt_atc := NULLIF(p_header->>'cwt_atc_id','')::UUID;
  IF p_cwt_amount > 0 THEN
    SELECT rate INTO v_cwt_rate FROM atc_codes WHERE id = v_cwt_atc;
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

  -- Recompute amounts from source, like fn_save_sales_invoice — UI preview
  -- values are not trusted (the previous version read net_amount/vat_amount
  -- from the payload, which CashSalesPage never sends, so every UI cash sale
  -- would have carried zero totals). Header totals are split by VAT
  -- classification (PXL-AUD-014: zero-rated/exempt were stored as 0).
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_class, v_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id','')::UUID;
    v_class := COALESCE(v_class, 'exempt');
    v_rate  := COALESCE(v_rate, 0);

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat   := CASE WHEN v_class = 'regular' THEN ROUND(v_net * v_rate / 100, 2) ELSE 0 END;

    v_grand_total := v_grand_total + v_net + v_vat;
    v_total_vat   := v_total_vat + v_vat;
    CASE v_class
      WHEN 'regular'    THEN v_total_taxable := v_total_taxable + v_net;
      WHEN 'zero_rated' THEN v_total_zero    := v_total_zero + v_net;
      ELSE                   v_total_exempt  := v_total_exempt + v_net;
    END CASE;
    v_has_lines := true;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'Cash sale must have at least one line with a description.';
  END IF;

  -- Insert SI
  INSERT INTO sales_invoices (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    si_number, date, due_date, currency_code, memo,
    total_amount, total_vat_amount, total_taxable_amount,
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
    v_grand_total, v_total_vat, v_total_taxable,
    v_total_zero, v_total_exempt,
    true, 'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_si_id;

  -- Insert SI lines with the same recomputed amounts
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_class, v_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id','')::UUID;
    v_class := COALESCE(v_class, 'exempt');
    v_rate  := COALESCE(v_rate, 0);

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat   := CASE WHEN v_class = 'regular' THEN ROUND(v_net * v_rate / 100, 2) ELSE 0 END;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description,
      quantity, unit_price, discount_amount, net_amount,
      vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no_si,
      NULLIF(v_line->>'item_id','')::UUID,
      v_line->>'description',
      v_qty, v_price, v_disc, v_net,
      NULLIF(v_line->>'vat_code_id','')::UUID,
      v_vat, v_net + v_vat,
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

  -- Output VAT tax ledger: one row per VAT code (previously cash sales wrote
  -- no tax ledger rows at all — PXL-AUD-014).
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_company_id, v_branch_id, 'SI', v_si_id,
    'output_vat', sil.vat_code_id,
    SUM(sil.net_amount), COALESCE(SUM(sil.vat_amount), 0), v_fp_id,
    NOW()::DATE, (p_header->>'date')::DATE,
    (p_header->>'customer_id')::UUID,
    NULLIF(p_header->>'customer_tin_snapshot',''),
    p_header->>'customer_name_snapshot'
  FROM sales_invoice_lines sil
  WHERE sil.sales_invoice_id = v_si_id
    AND sil.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_company_id AND c.tax_registration = 'vat')
  GROUP BY sil.vat_code_id
  HAVING SUM(sil.net_amount) <> 0 OR COALESCE(SUM(sil.vat_amount), 0) <> 0;

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
    COALESCE(NULLIF(p_header->>'payment_mode_id','')::UUID,
             (SELECT id FROM ref_payment_modes WHERE code = 'CASH')), v_cash_acct,
    v_grand_total, p_cwt_amount, 'Cash Sale — ' || v_si_number,
    'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  -- payment + cwt must equal the amount applied to the invoice (gross); the
  -- previous version put the gross in payment_amount, over-applying the SI by
  -- the CWT and failing the PXL-AUD-007 basis validator.
  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, atc_code_id, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total - p_cwt_amount, p_cwt_amount, v_cwt_atc, auth.uid(), auth.uid());

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

  UPDATE receipts SET status = 'posted', journal_entry_id = v_je_or_id,
    posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  -- CWT receivable tax ledger row (previously cash-sale receipts wrote none;
  -- normal ORs write it in fn_post_receipt). Base = payment + cwt = gross,
  -- matching the fn_post_receipt convention.
  IF p_cwt_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', v_cwt_atc, v_grand_total, v_cwt_rate, p_cwt_amount, v_fp_id,
      NOW()::DATE, (p_header->>'date')::DATE,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    );
  END IF;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number
  );
END;
$$;

-- ── 4. Cash purchase posting: per-VAT-code input rows ──────────────────────────
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

  -- Input VAT tax ledger: one row per VAT code (previously cash purchases
  -- wrote no tax ledger rows at all — PXL-AUD-014).
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_rec.company_id, v_rec.branch_id, 'CP', v_rec.id,
    'input_vat', cpl.vat_code_id,
    SUM(cpl.net_amount), COALESCE(SUM(cpl.input_vat_amount), 0), v_fp_id,
    NOW()::DATE, v_rec.transaction_date,
    v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
  FROM cash_purchase_lines cpl
  WHERE cpl.cp_id = v_rec.id
    AND cpl.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat')
  GROUP BY cpl.vat_code_id
  HAVING SUM(cpl.net_amount) <> 0 OR COALESCE(SUM(cpl.input_vat_amount), 0) <> 0;
END;
$$;

-- ── 5. Backfill posted documents in existing environments ──────────────────────
-- Adds only what is missing, never mutates existing rows:
--   - per-code rows are skipped where a row for that (doc, vat_code) exists,
--   - regular codes are skipped where a legacy lump row (vat_code_id IS NULL)
--     already carries the document's regular VAT,
--   - only 'posted' documents: voided/cancelled/bounced docs were netted by
--     20260702000009 against the rows that existed then; adding new originals
--     would break that netting.
INSERT INTO tax_detail_entries (
  company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
  posting_date, document_date, counterparty_id, counterparty_tin, counterparty_name
)
SELECT si.company_id, si.branch_id, 'SI', si.id,
       'output_vat', pc.vat_code_id, pc.base, pc.vat, fp.fp_id,
       NOW()::DATE, si.date, si.customer_id, si.customer_tin_snapshot, si.customer_name_snapshot
FROM sales_invoices si
JOIN LATERAL (
  SELECT sil.vat_code_id, vc.vat_classification,
         SUM(sil.net_amount) AS base, COALESCE(SUM(sil.vat_amount), 0) AS vat
  FROM sales_invoice_lines sil
  JOIN vat_codes vc ON vc.id = sil.vat_code_id
  WHERE sil.sales_invoice_id = si.id
  GROUP BY sil.vat_code_id, vc.vat_classification
) pc ON TRUE
LEFT JOIN LATERAL (
  SELECT id AS fp_id FROM fiscal_periods
  WHERE company_id = si.company_id AND start_date <= si.date AND end_date >= si.date
  LIMIT 1
) fp ON TRUE
WHERE si.status = 'posted'
  AND EXISTS (SELECT 1 FROM companies c WHERE c.id = si.company_id AND c.tax_registration = 'vat')
  AND (pc.base <> 0 OR pc.vat <> 0)
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries t
    WHERE t.source_doc_type = 'SI' AND t.source_doc_id = si.id
      AND t.tax_kind = 'output_vat' AND t.vat_code_id = pc.vat_code_id
      AND t.is_reversal = false)
  AND NOT (pc.vat_classification = 'regular' AND EXISTS (
    SELECT 1 FROM tax_detail_entries t
    WHERE t.source_doc_type = 'SI' AND t.source_doc_id = si.id
      AND t.tax_kind = 'output_vat' AND t.vat_code_id IS NULL
      AND t.is_reversal = false));

INSERT INTO tax_detail_entries (
  company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
  posting_date, document_date, counterparty_id, counterparty_tin, counterparty_name
)
SELECT vb.company_id, vb.branch_id, 'VB', vb.id,
       'input_vat', pc.vat_code_id, pc.base, pc.vat, fp.fp_id,
       NOW()::DATE, vb.bill_date, vb.supplier_id, vb.supplier_tin_snapshot, vb.supplier_name_snapshot
FROM vendor_bills vb
JOIN LATERAL (
  SELECT vbl.vat_code_id, vc.vat_classification,
         SUM(vbl.net_amount) AS base, COALESCE(SUM(vbl.input_vat_amount), 0) AS vat
  FROM vendor_bill_lines vbl
  JOIN vat_codes vc ON vc.id = vbl.vat_code_id
  WHERE vbl.vendor_bill_id = vb.id
  GROUP BY vbl.vat_code_id, vc.vat_classification
) pc ON TRUE
LEFT JOIN LATERAL (
  SELECT id AS fp_id FROM fiscal_periods
  WHERE company_id = vb.company_id AND start_date <= vb.bill_date AND end_date >= vb.bill_date
  LIMIT 1
) fp ON TRUE
WHERE vb.status = 'posted'
  AND EXISTS (SELECT 1 FROM companies c WHERE c.id = vb.company_id AND c.tax_registration = 'vat')
  AND (pc.base <> 0 OR pc.vat <> 0)
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries t
    WHERE t.source_doc_type = 'VB' AND t.source_doc_id = vb.id
      AND t.tax_kind = 'input_vat' AND t.vat_code_id = pc.vat_code_id
      AND t.is_reversal = false)
  AND NOT (pc.vat_classification = 'regular' AND EXISTS (
    SELECT 1 FROM tax_detail_entries t
    WHERE t.source_doc_type = 'VB' AND t.source_doc_id = vb.id
      AND t.tax_kind = 'input_vat' AND t.vat_code_id IS NULL
      AND t.is_reversal = false));

INSERT INTO tax_detail_entries (
  company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
  posting_date, document_date, counterparty_id, counterparty_tin, counterparty_name
)
SELECT cp.company_id, cp.branch_id, 'CP', cp.id,
       'input_vat', pc.vat_code_id, pc.base, pc.vat, fp.fp_id,
       NOW()::DATE, cp.transaction_date, cp.supplier_id, cp.supplier_tin_snapshot, cp.supplier_name_snapshot
FROM cash_purchases cp
JOIN LATERAL (
  SELECT cpl.vat_code_id,
         SUM(cpl.net_amount) AS base, COALESCE(SUM(cpl.input_vat_amount), 0) AS vat
  FROM cash_purchase_lines cpl
  JOIN vat_codes vc ON vc.id = cpl.vat_code_id
  WHERE cpl.cp_id = cp.id
  GROUP BY cpl.vat_code_id
) pc ON TRUE
LEFT JOIN LATERAL (
  SELECT id AS fp_id FROM fiscal_periods
  WHERE company_id = cp.company_id AND start_date <= cp.transaction_date AND end_date >= cp.transaction_date
  LIMIT 1
) fp ON TRUE
WHERE cp.status = 'posted'
  AND EXISTS (SELECT 1 FROM companies c WHERE c.id = cp.company_id AND c.tax_registration = 'vat')
  AND (pc.base <> 0 OR pc.vat <> 0)
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries t
    WHERE t.source_doc_type = 'CP' AND t.source_doc_id = cp.id
      AND t.tax_kind = 'input_vat' AND t.vat_code_id = pc.vat_code_id
      AND t.is_reversal = false);

-- Cash-sale receipts: CWT receivable rows (normal ORs already write them in
-- fn_post_receipt, so the NOT EXISTS guard leaves those untouched).
INSERT INTO tax_detail_entries (
  company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, tax_base, tax_amount, tax_period_id,
  posting_date, document_date, counterparty_id, counterparty_tin, counterparty_name
)
SELECT r.company_id, r.branch_id, 'OR', r.id,
       'cwt_receivable', r.total_amount, r.total_cwt, fp.fp_id,
       NOW()::DATE, r.receipt_date, r.customer_id, r.customer_tin_snapshot, r.customer_name_snapshot
FROM receipts r
LEFT JOIN LATERAL (
  SELECT id AS fp_id FROM fiscal_periods
  WHERE company_id = r.company_id AND start_date <= r.receipt_date AND end_date >= r.receipt_date
  LIMIT 1
) fp ON TRUE
WHERE r.status = 'posted'
  AND r.total_cwt > 0
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries t
    WHERE t.source_doc_type = 'OR' AND t.source_doc_id = r.id
      AND t.tax_kind = 'cwt_receivable' AND t.is_reversal = false);
