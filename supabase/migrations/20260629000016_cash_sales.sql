-- ══════════════════════════════════════════════════════════════════════════════
-- CASH SALES: is_cash_sale flag + atomic fn_save_cash_sale RPC
-- Cash Sale = SI posted immediately with a matching OR, both in one transaction.
-- Requires company_accounting_config (same as fn_post_sales_invoice).
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS is_cash_sale BOOLEAN NOT NULL DEFAULT false;

-- Document series for Cash Sales uses separate prefix 'CS' so BIR cash sales
-- journal is distinct from credit sales journal.
-- (Add 'CS' to document_series via existing number series setup.)

CREATE OR REPLACE FUNCTION fn_save_cash_sale(
  p_header       JSONB,  -- SI header fields + bank_account_id + payment_mode_id
  p_lines        JSONB,  -- SI line items
  p_cwt_amount   NUMERIC DEFAULT 0
)
RETURNS JSONB            -- { si_id, receipt_id, si_number, receipt_number }
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
  v_line          JSONB;
  v_vat_class     TEXT;
  v_vat_rate      NUMERIC(5,2);
  v_qty           NUMERIC(15,4);
  v_price         NUMERIC(15,4);
  v_disc          NUMERIC(15,2);
  v_net           NUMERIC(15,2);
  v_vat_amt       NUMERIC(15,2);
  v_total_line    NUMERIC(15,2);
  v_line_no       INT;
  v_taxable       NUMERIC(15,2) := 0;
  v_zero_rated    NUMERIC(15,2) := 0;
  v_exempt        NUMERIC(15,2) := 0;
  v_total_vat     NUMERIC(15,2) := 0;
  v_grand_total   NUMERIC(15,2) := 0;
  v_has_lines     BOOLEAN := false;
  v_total_cr      NUMERIC(15,2) := 0;
  v_rev_line      RECORD;
  v_rev_line_no   INT;
  v_ar_cr         NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- GL config is mandatory for cash sales (must post immediately)
  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in Setup → GL Posting Configuration.';
  END IF;
  IF p_cwt_amount > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in Setup → GL Posting Configuration.';
  END IF;

  v_cash_acct := COALESCE(
    NULLIF(p_header->>'bank_account_id', '')::UUID,
    v_cfg.default_cash_account_id
  );
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'No cash/bank account specified and no default cash account configured.';
  END IF;

  -- Resolve fiscal period
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= (p_header->>'date')::DATE
    AND end_date >= (p_header->>'date')::DATE AND is_locked = false LIMIT 1;

  -- Generate numbers
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Create SI header
  INSERT INTO sales_invoices (
    company_id, branch_id, si_number, date, fiscal_period_id,
    customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
    payment_terms_id, due_date, currency_code, reference, memo,
    total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
    total_vat_amount, total_amount, cwt_amount_expected,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, v_si_number, (p_header->>'date')::DATE, v_fp_id,
    (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot', ''),
    NULLIF(p_header->>'customer_address_snapshot', ''),
    NULLIF(p_header->>'payment_terms_id', '')::UUID,
    (p_header->>'date')::DATE, -- due immediately for cash sale
    COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
    NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
    0, 0, 0, 0, 0, p_cwt_amount,
    true, 'approved', auth.uid(), auth.uid() -- skip draft, go straight to approved
  ) RETURNING id INTO v_si_id;

  -- Insert lines with server-side VAT computation
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount, net_amount, vat_code_id, vat_amount, total_amount,
      revenue_account_id, created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID, auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one non-empty line is required'; END IF;

  -- Update SI totals
  UPDATE sales_invoices SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_vat_amount = v_total_vat, total_amount = v_grand_total
  WHERE id = v_si_id;

  IF v_grand_total <= 0 THEN RAISE EXCEPTION 'Cash sale total must be greater than zero'; END IF;

  -- ── Post SI: create JE ──────────────────────────────────────

  IF v_cfg.vat_payable_account_id IS NULL AND v_total_vat > 0 THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-SI-' || v_si_number, (p_header->>'date')::DATE, v_fp_id,
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
    v_total_cr := v_total_cr + v_rev_line.net_sum;
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

  -- ── Create and Post Receipt ──────────────────────────────────

  v_ar_cr := v_grand_total + p_cwt_amount;

  INSERT INTO receipts (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    receipt_number, receipt_date, payment_mode_id, bank_account_id,
    total_amount, total_cwt, remarks, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
    v_or_number, (p_header->>'date')::DATE,
    NULLIF(p_header->>'payment_mode_id', '')::UUID, v_cash_acct,
    v_grand_total, p_cwt_amount, 'Cash Sale — ' || v_si_number,
    'posted', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total, p_cwt_amount, auth.uid(), auth.uid());

  -- Post receipt JE
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-OR-' || v_or_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id, 'posted', v_ar_cr, v_ar_cr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_or_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, 1, v_cash_acct, 'Cash received — ' || v_or_number, v_grand_total, 0, auth.uid(), auth.uid());

  IF p_cwt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_or_id, v_company_id, 2, v_cfg.ewt_withheld_account_id, 'EWT withheld — ' || v_or_number, p_cwt_amount, 0, auth.uid(), auth.uid());
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_cfg.ar_account_id, 'AR cleared — ' || v_or_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts SET journal_entry_id = v_je_or_id, posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_cash_sale(JSONB, JSONB, NUMERIC) TO authenticated;
