-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P2B (Purchasing resolver adoption; = COA Engine Phase B, group 2)
--
-- Migrates ONLY the Purchasing posting writers to consume the certified COA resolver
-- fn_resolve_account (COA Engine, frozen contract) through the P2A adapter
-- fn_resolve_posting_account. No accounting behavior change: account_mapping is a
-- config-synced projection (COA Phase A), so fn_resolve_account(company, KEY) ==
-- the previously-read company_accounting_config account for every configured key —
-- equivalence-identical for all canonical companies. Journal amounts, posting dates,
-- numbering, tax, dimensions, references, AP/inventory behavior, and audit are
-- preserved byte-for-byte; only account SELECTION now flows through one resolver.
--
-- Scope (Purchasing family only): fn_post_vendor_bill,
-- fn_post_cash_purchase_source_locked_impl, fn_post_vendor_credit_vat_lump_impl.
-- OUT OF SCOPE (unchanged): Sales (already P2A), Payment Voucher, Check Voucher,
-- Withholding Remittance, Purchase Return, inventory, fixed assets, recurring,
-- fiscal close, manual JE, petty cash, banking, and every other writer. No Totality
-- Guard, no tax contract, no dimension push, no subledger reconciliation, no reversal
-- consolidation.
--
-- Metadata (P1): posting_origin='system' is populated on every Purchasing journal.
-- line_role is populated on the direct-insert Purchasing writer (Vendor Credit);
-- Vendor Bill and Cash Purchase line_role is deferred to P3 (push-builder wiring /
-- dimension push), exactly as SI and Receipt were in P2A.
-- Key→config mapping (COA Phase A): AP_TRADE↔ap_account_id, VAT_INPUT↔input_vat_account_id,
-- EWT_PAYABLE↔ewt_payable_account_id, CASH_DEFAULT↔default_cash_account_id.
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- Vendor Bill
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_vendor_bill(p_bill_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec vendor_bills%ROWTYPE;
  v_ap UUID;
  v_input_vat UUID;
  v_ewt UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_tax RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
  v_accrued_ewt NUMERIC(15,2) := 0;
  v_ap_credit NUMERIC(15,2) := 0;
BEGIN
  v_begin := fn_begin_source_posting(
    'VB', p_bill_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM vendor_bills WHERE id = p_bill_id;
  PERFORM fn_validate_vendor_bill_accounting_ready(p_bill_id);
  PERFORM fn_validate_vendor_bill_vat_registration(p_bill_id);
  PERFORM fn_validate_invoice_posting_totals('VB', p_bill_id);

  -- COA resolver adoption (P2B): AP control + Input VAT + EWT Payable via fn_resolve_account.
  v_ap := fn_resolve_posting_account(v_rec.company_id, 'AP_TRADE', v_rec.bill_date,
            'AP control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_input_vat_amount > 0 THEN
    v_input_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_INPUT', v_rec.bill_date,
                     'Input VAT account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT COALESCE(SUM(vbl.ewt_amount), 0)::NUMERIC(15,2)
  INTO v_accrued_ewt
  FROM vendor_bill_lines vbl
  WHERE vbl.vendor_bill_id = v_rec.id;

  IF v_accrued_ewt > 0 THEN
    v_ewt := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.bill_date,
               'EWT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_ap_credit := ROUND(v_rec.total_amount - v_accrued_ewt, 2);
  IF v_ap_credit <= 0 THEN
    RAISE EXCEPTION 'Vendor bill source EWT % cannot equal or exceed bill total %.',
      v_accrued_ewt, v_rec.total_amount;
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date,
    'Vendor Bill ' || v_rec.bill_number || ' - ' || v_rec.supplier_name_snapshot,
    'VB', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;

  FOR v_line IN
    SELECT vbl.expense_account_id, SUM(vbl.net_amount) AS net_sum,
           vbl.description AS line_description
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.expense_account_id IS NOT NULL
    GROUP BY vbl.expense_account_id, vbl.description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.expense_account_id,
      'Expense - ' || v_line.line_description,
      v_line.net_sum, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_debit := v_total_debit + v_line.net_sum;
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_input_vat,
      'Input VAT - ' || v_rec.bill_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_debit := v_total_debit + v_rec.total_input_vat_amount;
    v_line_no := v_line_no + 1;
  END IF;

  PERFORM fn_add_posting_line(
    v_je_id, v_line_no, v_ap,
    'AP - ' || v_rec.supplier_name_snapshot,
    0, v_ap_credit,
    v_rec.branch_id, NULL, NULL
  );
  v_line_no := v_line_no + 1;

  IF v_accrued_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ewt,
      'EWT accrued - ' || v_rec.bill_number,
      0, v_accrued_ewt,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  IF ABS((v_ap_credit + v_accrued_ewt) - v_total_debit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.',
      v_total_debit, v_ap_credit + v_accrued_ewt;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE vendor_bills
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT vbl.vat_code_id,
           SUM(vbl.net_amount) AS tax_base,
           COALESCE(SUM(vbl.input_vat_amount), 0) AS tax_amount
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY vbl.vat_code_id
    HAVING SUM(vbl.net_amount) <> 0 OR COALESCE(SUM(vbl.input_vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, NULL,
      'input_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END LOOP;

  FOR v_tax IN
    SELECT vbl.id, vbl.ewt_atc_code_id, vbl.ewt_tax_base, vbl.ewt_amount,
           vbl.ewt_income_nature, ac.rate AS ewt_rate
    FROM vendor_bill_lines vbl
    LEFT JOIN atc_codes ac ON ac.id = vbl.ewt_atc_code_id
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, v_tax.id,
      'ewt_payable', NULL, NULL, v_tax.ewt_atc_code_id,
      v_tax.ewt_tax_base, v_tax.ewt_rate, v_tax.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_tax.ewt_income_nature
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'VB', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.bill_date, 'ewt_recognition', 'accrual_at_source')
  );
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Cash Purchase
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_cash_purchase_source_locked_impl(p_cp_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cash_acct UUID;
  v_input_vat UUID;
  v_ewt       UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_tax       RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
  v_gross_total NUMERIC(15,2) := 0;
  v_total_ewt NUMERIC(15,2) := 0;
  v_cash_total NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM cash_purchases WHERE id = p_cp_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft cash purchases can be posted (current: %)', v_rec.status; END IF;

  PERFORM fn_validate_cash_purchase_ewt_ready(p_cp_id);

  -- COA resolver adoption (P2B): cash (form account or CASH_DEFAULT), Input VAT, EWT Payable.
  v_cash_acct := v_rec.payment_account_id;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := fn_resolve_posting_account(v_rec.company_id, 'CASH_DEFAULT', v_rec.transaction_date,
                     'Payment account not set. Add it on the form or configure a default cash account.');
  END IF;
  IF v_rec.total_input_vat_amount > 0 THEN
    v_input_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_INPUT', v_rec.transaction_date,
                     'Input VAT account not configured. Set it in GL Posting Configuration.');
  END IF;

  v_total_ewt := COALESCE(v_rec.total_ewt_amount, 0);
  IF v_total_ewt > 0 THEN
    v_ewt := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.transaction_date,
               'EWT Payable account not configured. Set it in GL Posting Configuration.');
  END IF;
  IF v_total_ewt > 0 AND v_rec.supplier_id IS NULL THEN
    RAISE EXCEPTION 'Supplier is required when cash purchase EWT is recorded.';
  END IF;

  v_gross_total := ROUND(
    COALESCE(v_rec.total_taxable_amount, 0)
    + COALESCE(v_rec.total_zero_rated_amount, 0)
    + COALESCE(v_rec.total_exempt_amount, 0)
    + COALESCE(v_rec.total_input_vat_amount, 0),
    2
  );
  v_cash_total := COALESCE(v_rec.total_amount, 0);

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-CP-' || v_rec.cp_number, v_rec.transaction_date,
    'Cash Purchase ' || v_rec.cp_number || COALESCE(' - ' || v_rec.supplier_name_snapshot, ''),
    'CP', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM cash_purchase_lines
    WHERE cp_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.expense_account_id,
      'Expense - ' || v_line.ln_desc,
      v_line.net_sum, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_input_vat,
      'Input VAT - ' || v_rec.cp_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  IF v_total_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ewt,
      'EWT withheld - ' || v_rec.cp_number,
      0, v_total_ewt,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_cash_total > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cash_acct,
      'Cash paid - ' || v_rec.cp_number,
      0, v_cash_total,
      v_rec.branch_id, NULL, NULL
    );
  ELSIF v_cash_total < 0 THEN
    RAISE EXCEPTION 'Cash purchase cash total cannot be negative.';
  END IF;

  IF ABS(v_gross_total - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% expected gross %. Ensure all lines have expense accounts.',
      v_total_dr, v_gross_total;
  END IF;
  IF ABS(v_gross_total - (v_cash_total + v_total_ewt)) > 0.02 THEN
    RAISE EXCEPTION 'Cash purchase gross % must equal cash % plus EWT %.',
      v_gross_total, v_cash_total, v_total_ewt;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE cash_purchases SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

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

  FOR v_tax IN
    SELECT cpl.id, cpl.ewt_atc_code_id, cpl.ewt_tax_base, cpl.ewt_amount,
           cpl.ewt_income_nature, cpl.net_amount, cpl.input_vat_amount,
           ac.rate AS ewt_rate
    FROM cash_purchase_lines cpl
    LEFT JOIN atc_codes ac ON ac.id = cpl.ewt_atc_code_id
    WHERE cpl.cp_id = v_rec.id
      AND cpl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'CP', v_rec.id, v_tax.id,
      'ewt_payable', NULL, NULL, v_tax.ewt_atc_code_id,
      ROUND(COALESCE(v_tax.ewt_tax_base, v_tax.net_amount), 2),
      v_tax.ewt_rate, v_tax.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.transaction_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_tax.ewt_income_nature
    );
  END LOOP;
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Vendor Credit (direct-insert; line_role tagged like the P2A CM/DM writers)
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_vendor_credit_vat_lump_impl(p_vc_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_ap        UUID;
  v_input_vat UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  v_ap := fn_resolve_posting_account(v_rec.company_id, 'AP_TRADE', v_rec.credit_date,
            'AP control account not configured. Set it in GL Posting Configuration.');
  IF v_rec.total_input_vat_amount > 0 THEN
    v_input_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_INPUT', v_rec.credit_date,
                     'Input VAT account not configured. Set it in GL Posting Configuration.');
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
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date, v_fp_id,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'VC', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount, 'system',
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_ap,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, 'control', auth.uid(), auth.uid());

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, 'base', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_input_vat,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, 'tax', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Negative input VAT in tax ledger (reversal of original bill input VAT)
  IF v_rec.total_input_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'VC', v_rec.id,
      'input_vat', -v_rec.total_taxable_amount, -v_rec.total_input_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.credit_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      true
    );
  END IF;
END;
$function$;
