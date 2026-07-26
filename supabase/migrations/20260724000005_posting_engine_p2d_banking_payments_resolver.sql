-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P2D (Banking / Payments / Purchase-return resolver adoption;
--                            = COA Engine Phase B, group 4)
--
-- Migrates the remaining forward posting writers that still read
-- company_accounting_config directly onto the certified COA resolver
-- fn_resolve_account (via the P2A adapter fn_resolve_posting_account). No accounting
-- behavior change: account_mapping is a config-synced projection (COA Phase A), so
-- fn_resolve_account(company, KEY) == the previously-read company_accounting_config
-- account for every configured key. Journal lines, amounts, posting dates, numbering,
-- tax, dimensions, references, posting_origin, and audit are preserved BYTE-FOR-BYTE;
-- only account SELECTION now flows through one resolver. (Unlike P2A/P2B, this phase
-- makes NO metadata change — posting_origin/line_role are left exactly as they were,
-- per the P2D byte-for-byte-equivalent constraint.)
--
-- Scope (4 writers) and their config→key adoption:
--   • fn_post_payment_voucher                         AP_TRADE, SUPPLIER_DOWNPAYMENTS, EWT_PAYABLE, CASH_DEFAULT
--   • fn_post_check_voucher                           EWT_PAYABLE
--   • fn_complete_purchase_return_source_locked_impl  AP_TRADE
--   • fn_post_withholding_remittance                  EWT_PAYABLE, EWT_WITHHELD
--
-- Investigated and CERTIFIED WITHOUT CHANGE (already zero company_accounting_config):
--   • Banking forward writers  fn_post_bank_adjustment/_fund_transfer/_inter_branch_transfer
--                              (accounts from bank_accounts.gl_account_id)
--   • Reversal/void writers    fn_cancel_payment_voucher, fn_cancel_check_voucher,
--                              fn_void_withholding_remittance, fn_cancel_bank_adjustment,
--                              fn_cancel_fund_transfer, fn_cancel_inter_branch_transfer
--                              (reverse the original posted journal; resolve no accounts)
-- OUT OF SCOPE (not posting writers, unchanged): the *_gl_reconciliation_asof /
--   vat/wht reconciliation reports and GL-impact previews (read config to identify
--   control accounts for reporting), and fn_save_withholding_remittance (a save-time
--   config-presence validator that writes no journal).
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- Payment Voucher
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_payment_voucher(p_voucher_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec payment_vouchers%ROWTYPE;
  v_ap UUID;
  v_down_payment UUID;
  v_ewt UUID;
  v_cash_account UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_ap_debit NUMERIC(15,2);
  v_down_payment_debit NUMERIC(15,2);
  v_line_no INTEGER := 1;
  v_line RECORD;
BEGIN
  v_begin := fn_begin_source_posting(
    'PV', p_voucher_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  PERFORM fn_validate_payment_voucher_ewt_ready(p_voucher_id);
  PERFORM fn_validate_settlement_posting('PV', p_voucher_id);

  SELECT
    COALESCE(SUM(payment_amount + ewt_amount) FILTER (WHERE line_type = 'bill_application'), 0),
    COALESCE(SUM(payment_amount + ewt_amount) FILTER (WHERE line_type = 'supplier_down_payment'), 0)
  INTO v_ap_debit, v_down_payment_debit
  FROM payment_voucher_lines
  WHERE payment_voucher_id = v_rec.id;

  -- COA resolver adoption (P2D): resolve only the accounts this voucher needs.
  IF v_ap_debit > 0 THEN
    v_ap := fn_resolve_posting_account(v_rec.company_id, 'AP_TRADE', v_rec.voucher_date,
              'AP control account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_down_payment_debit > 0 THEN
    v_down_payment := fn_resolve_posting_account(v_rec.company_id, 'SUPPLIER_DOWNPAYMENTS', v_rec.voucher_date,
                        'Supplier down-payments account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_rec.total_ewt > 0 THEN
    v_ewt := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.voucher_date,
               'EWT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_cash_account := v_rec.bank_account_id;
  IF v_rec.total_amount > 0 AND v_cash_account IS NULL THEN
    v_cash_account := fn_resolve_posting_account(v_rec.company_id, 'CASH_DEFAULT', v_rec.voucher_date,
                        'No bank account on voucher and no default cash account configured.');
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date,
    'Payment Voucher ' || v_rec.voucher_number || ' - ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  IF v_ap_debit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ap,
      'AP cleared - ' || v_rec.voucher_number,
      v_ap_debit, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_down_payment_debit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_down_payment,
      'Supplier down-payment - ' || v_rec.voucher_number,
      v_down_payment_debit, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_rec.total_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cash_account,
      'Cash paid - ' || v_rec.voucher_number,
      0, v_rec.total_amount,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_rec.total_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ewt,
      'EWT withheld - ' || v_rec.voucher_number,
      0, v_rec.total_ewt,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE payment_vouchers
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_line IN
    SELECT pvl.id, pvl.payment_amount, pvl.ewt_amount, pvl.atc_code_id,
           pvl.ewt_tax_base, pvl.ewt_income_nature,
           ac.rate AS ewt_rate
    FROM payment_voucher_lines pvl
    LEFT JOIN atc_codes ac ON ac.id = pvl.atc_code_id
    WHERE pvl.payment_voucher_id = v_rec.id
      AND pvl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id, v_line.id,
      'ewt_payable', NULL, NULL, v_line.atc_code_id,
      ROUND(COALESCE(v_line.ewt_tax_base,
        v_line.payment_amount + v_line.ewt_amount), 2),
      v_line.ewt_rate, v_line.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_line.ewt_income_nature
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'PV', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.voucher_date)
  );
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Check Voucher (direct-insert; metadata left exactly as-is per P2D constraint)
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_check_voucher(p_cv_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec      check_vouchers%ROWTYPE;
  v_ewt      UUID;
  v_supp     suppliers%ROWTYPE;
  v_bank_gl  UUID;
  v_gross    NUMERIC(15,2);
  v_net      NUMERIC(15,2);
  v_atc_rate NUMERIC(8,4);
  v_fp_id    UUID; v_je_id UUID;
  v_line     RECORD;
  v_no       INT := 1;
BEGIN
  SELECT * INTO v_rec FROM check_vouchers WHERE id = p_cv_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Check voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft check vouchers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT gl_account_id INTO v_bank_gl FROM bank_accounts WHERE id = v_rec.bank_account_id;
  IF v_bank_gl IS NULL THEN RAISE EXCEPTION 'Bank account has no GL account configured'; END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_gross FROM check_voucher_lines WHERE cv_id = v_rec.id;
  IF v_gross <= 0 THEN RAISE EXCEPTION 'Check voucher must have at least one expense line'; END IF;

  IF v_rec.total_ewt_amount > 0 THEN
    IF v_rec.atc_code_id IS NULL THEN
      RAISE EXCEPTION 'An ATC code is required when EWT is withheld';
    END IF;
    IF v_rec.supplier_id IS NULL THEN
      RAISE EXCEPTION 'A supplier is required when EWT is withheld on a check voucher (Form 2307 traceability).';
    END IF;
    SELECT * INTO v_supp FROM suppliers
    WHERE id = v_rec.supplier_id AND company_id = v_rec.company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier does not belong to this company'; END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_rec.company_id,
      v_gross - v_rec.total_ewt_amount,
      v_rec.total_ewt_amount,
      v_rec.atc_code_id,
      v_rec.ewt_tax_base,
      v_rec.ewt_variance_reason,
      v_rec.voucher_date
    );

    SELECT rate INTO v_atc_rate FROM atc_codes WHERE id = v_rec.atc_code_id;
  END IF;

  v_net := v_gross - v_rec.total_ewt_amount;
  IF v_net <= 0 THEN RAISE EXCEPTION 'Net check amount must be greater than zero'; END IF;

  -- COA resolver adoption (P2D): EWT Payable via fn_resolve_account.
  IF v_rec.total_ewt_amount > 0 THEN
    v_ewt := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.voucher_date,
               'EWT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for voucher date %', v_rec.voucher_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-CV-' || v_rec.cv_number, v_rec.voucher_date, v_fp_id,
    'Check Voucher ' || v_rec.cv_number || ' — ' || v_rec.payee,
    'CV', v_rec.id, 'posted', v_gross, v_gross, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT expense_account_id, SUM(amount) AS amt
    FROM check_voucher_lines WHERE cv_id = v_rec.id
    GROUP BY expense_account_id
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_line.expense_account_id, v_rec.particulars, v_line.amt, 0, auth.uid(), auth.uid());
    v_no := v_no + 1;
  END LOOP;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_no, v_bank_gl, 'Check ' || v_rec.check_number || ' — ' || v_rec.payee, 0, v_net, auth.uid(), auth.uid());
  v_no := v_no + 1;

  IF v_rec.total_ewt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_ewt, 'EWT withheld — ' || v_rec.cv_number, 0, v_rec.total_ewt_amount, auth.uid(), auth.uid());

    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id, tax_kind, atc_code_id,
      tax_base, tax_rate, tax_amount, tax_period_id, posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CV', v_rec.id, 'ewt_payable', v_rec.atc_code_id,
      ROUND(COALESCE(v_rec.ewt_tax_base, v_gross), 2), v_atc_rate, v_rec.total_ewt_amount,
      v_fp_id, NOW()::DATE, v_rec.voucher_date,
      v_rec.supplier_id,
      COALESCE(NULLIF(BTRIM(v_supp.tin), ''), v_rec.payee_tin),
      COALESCE(NULLIF(BTRIM(v_supp.registered_name), ''), v_rec.payee)
    );
  END IF;

  UPDATE check_vouchers SET status = 'posted', journal_entry_id = v_je_id, fiscal_period_id = v_fp_id,
    total_gross_amount = v_gross, posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Purchase Return completion (direct-insert; metadata left exactly as-is per P2D)
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_complete_purchase_return_source_locked_impl(p_return_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec        purchase_returns%ROWTYPE;
  v_ap         UUID;
  v_fp_id      UUID;
  v_je_id      UUID;
  v_vb_id      UUID;
  v_vb_count   INTEGER := 0;
  v_line       RECORD;
  v_line_no    INT := 1;
  v_total_cr   NUMERIC(15,2) := 0;
  v_ret_total  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec
  FROM purchase_returns
  WHERE id = p_return_id;

  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Not found or access denied';
  END IF;
  IF v_rec.status != 'shipped' THEN
    RAISE EXCEPTION 'Only shipped returns can be completed (current: %)', v_rec.status;
  END IF;

  SELECT COUNT(*)::INTEGER
  INTO v_vb_count
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rec.rr_id
    AND vb.company_id = v_rec.company_id
    AND vb.supplier_id = v_rec.supplier_id
    AND vb.status = 'posted';

  IF v_vb_count = 0 THEN
    RAISE EXCEPTION
      'Purchase return % cannot complete: its receiving report has no linked posted vendor bill',
      v_rec.return_number;
  ELSIF v_vb_count > 1 THEN
    RAISE EXCEPTION
      'Purchase return % cannot complete: its receiving report is linked to % posted vendor bills; an unambiguous bill link is required',
      v_rec.return_number, v_vb_count;
  END IF;

  SELECT vb.id INTO v_vb_id
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rec.rr_id
    AND vb.company_id = v_rec.company_id
    AND vb.supplier_id = v_rec.supplier_id
    AND vb.status = 'posted';

  -- COA resolver adoption (P2D): AP control via fn_resolve_account. Resolved
  -- unconditionally (as the legacy AP null check was), so it raises even when the
  -- return produces no journal, preserving the original error behavior.
  v_ap := fn_resolve_posting_account(v_rec.company_id, 'AP_TRADE', v_rec.return_date,
            'AP account is not configured for purchase return ' || v_rec.return_number);

  -- A return against a posted bill reverses AP on the return's accounting date.
  IF v_vb_id IS NOT NULL THEN
    SELECT id INTO v_fp_id
    FROM fiscal_periods
    WHERE company_id = v_rec.company_id
      AND start_date <= v_rec.return_date
      AND end_date >= v_rec.return_date
      AND is_locked = false
    LIMIT 1;

    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for purchase return date %', v_rec.return_date;
    END IF;

    SELECT COALESCE(SUM(prl.return_qty * prl.unit_price), 0)
    INTO v_ret_total
    FROM purchase_return_lines prl
    WHERE prl.return_id = p_return_id;

    IF v_ret_total > 0 THEN
      INSERT INTO journal_entries (
        company_id, branch_id, je_number, je_date, fiscal_period_id,
        description, reference_doc_type, reference_doc_id, status,
        total_debit, total_credit, created_by, updated_by
      ) VALUES (
        v_rec.company_id, v_rec.branch_id,
        fn_next_document_number(v_rec.company_id, v_rec.branch_id, 'JE'),
        v_rec.return_date, v_fp_id,
        'Purchase Return ' || v_rec.return_number || ' — ' || v_rec.supplier_name_snapshot,
        'PR', v_rec.id, 'posted',
        v_ret_total, v_ret_total,
        auth.uid(), auth.uid()
      ) RETURNING id INTO v_je_id;

      INSERT INTO journal_entry_lines (
        je_id, company_id, line_number, account_id, description,
        debit_amount, credit_amount, created_by, updated_by
      ) VALUES (
        v_je_id, v_rec.company_id, 1, v_ap,
        'AP reversal — ' || v_rec.return_number,
        v_ret_total, 0, auth.uid(), auth.uid()
      );

      FOR v_line IN
        SELECT vbl.expense_account_id,
               SUM(LEAST(prl.return_qty, rrl.received_qty) * prl.unit_price) AS rev_amount,
               vbl.description AS ln_desc
        FROM purchase_return_lines prl
        JOIN receiving_report_lines rrl ON rrl.id = prl.rr_line_id
        JOIN vendor_bill_lines vbl
          ON vbl.vendor_bill_id = v_vb_id
         AND vbl.item_id = prl.item_id
        WHERE prl.return_id = p_return_id
          AND vbl.expense_account_id IS NOT NULL
        GROUP BY vbl.expense_account_id, vbl.description
      LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO journal_entry_lines (
          je_id, company_id, line_number, account_id, description,
          debit_amount, credit_amount, created_by, updated_by
        ) VALUES (
          v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
          'Return of: ' || v_line.ln_desc,
          0, v_line.rev_amount, auth.uid(), auth.uid()
        );
        v_total_cr := v_total_cr + v_line.rev_amount;
      END LOOP;

      -- Preserve the historical no-JE fallback when none of the returned items
      -- can be mapped to an expense account on the linked posted bill.
      IF v_total_cr = 0 THEN
        UPDATE journal_entries
        SET total_debit = 0, total_credit = 0
        WHERE id = v_je_id;
        DELETE FROM journal_entry_lines WHERE je_id = v_je_id;
        DELETE FROM journal_entries WHERE id = v_je_id;
        v_je_id := NULL;
      END IF;
    END IF;
  END IF;

  UPDATE purchase_returns SET
    status = 'completed',
    journal_entry_id = v_je_id,
    updated_by = auth.uid(),
    updated_at = NOW()
  WHERE id = p_return_id;
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Withholding Remittance
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_withholding_remittance(p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec         withholding_remittances%ROWTYPE;
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

  -- COA resolver adoption (P2D): the withholding control account via fn_resolve_account.
  IF v_rec.remittance_kind = 'ewt_payable' THEN
    v_control_id := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.remittance_date,
                      'EWT Payable control account not configured.');
  ELSE
    v_control_id := fn_resolve_posting_account(v_rec.company_id, 'EWT_WITHHELD', v_rec.remittance_date,
                      'CWT Receivable (EWT withheld) control account not configured.');
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
$function$;
