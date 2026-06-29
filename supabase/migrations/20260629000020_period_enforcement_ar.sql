-- ══════════════════════════════════════════════════════════════════════════════
-- Period enforcement for AR posting functions (migration 013 gap)
-- fn_post_sales_invoice and fn_post_receipt previously allowed null fiscal_period_id,
-- meaning transactions could post outside any accounting period.
-- ══════════════════════════════════════════════════════════════════════════════

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

  -- Populate output VAT tax ledger
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id,
      'output_vat', v_rec.total_net_amount, v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END IF;
END;
$$;

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

  v_cash_acct := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.receipt_date AND end_date >= v_rec.receipt_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for receipt date %. Create or unlock a fiscal period first.', v_rec.receipt_date;
  END IF;

  -- AR is cleared at cash collected + CWT withheld (equals the original invoice balance applied)
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

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cash_acct, 'Cash received — ' || v_rec.receipt_number, v_rec.total_amount, 0, auth.uid(), auth.uid());

  IF v_rec.total_cwt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 2, v_cfg.ewt_withheld_account_id, 'CWT receivable — ' || v_rec.receipt_number, v_rec.total_cwt, 0, auth.uid(), auth.uid());
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
          v_cfg.ar_account_id, 'AR cleared — ' || v_rec.receipt_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID)        TO authenticated;
