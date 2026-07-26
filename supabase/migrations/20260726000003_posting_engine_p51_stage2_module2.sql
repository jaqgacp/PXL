-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 2, Module 2 (memo posters: line persistence)
--
-- Completes the memo module begun in Stage 1. Stage 1 moved the CM / DM / VC
-- header INSERTs into the sanctioned kernel; this migration moves their nine
-- direct `journal_entry_lines` INSERTs into the sanctioned persistence helper.
-- After it, the three memo posters touch neither ledger table directly.
--
-- THE GUARD REMAINS OBSERVE-ONLY. Nothing is armed here; `c_enforce` is untouched.
--
-- ── WHY fn_add_posting_line_push (and not fn_add_posting_line) ────────────────
-- The memo lines carry `line_role` ('base' | 'tax' | 'control'), which
-- fn_add_posting_line cannot express. fn_add_posting_line_push — the push-based
-- helper P1/P3A built for exactly the §4.2 additive line columns (`line_role`,
-- `source_line_id`) — carries it and was until now unreferenced.
--
-- It is also the only choice that preserves behaviour: fn_add_posting_line adds
-- `fn_require_postable_account` and a debit/credit-exclusivity check that the raw
-- INSERTs being replaced do NOT perform. Routing through it would introduce two
-- new rejection paths — a validation change the phase contract forbids. The push
-- helper performs the same single INSERT these writers already performed, so the
-- persisted row is identical: same columns, same values, same NULL dimensions,
-- same audit row from `fn_audit_trigger`.
--
-- ── TRANSFORMATION METHOD ─────────────────────────────────────────────────────
-- Mechanical, not hand-written. Each function body was read from `pg_proc`, each
-- `INSERT INTO journal_entry_lines (...) VALUES (...)` block was parsed by paren
-- matching, `company_id` and the two trailing `auth.uid()` audit columns were
-- dropped (the helper supplies all three), and the remaining seven arguments were
-- emitted in helper order. A line-level diff confirms the only changes are those
-- nine call sites.
--
-- ACCOUNTING CONTRACT: journal header, lines, ordering, line_role, tax detail,
-- dimensions, numbering, audit, and document status all unchanged.
-- ══════════════════════════════════════════════════════════════════════════════

-- The push helper joins the sanctioned set. It is a persistence helper owned by
-- the engine, unreferenced until now, and callable by no client role.
CREATE OR REPLACE FUNCTION public.fn_posting_kernel_origin(p_context TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  -- The two sanctioned kernels of the frozen §4.7 census, plus the line-persistence
  -- helpers they and the migrated writers delegate to, and the finalizer that owns
  -- the header total update. Nothing else is kernel-origin.
  SELECT p_context ~ ('fn_create_posted_journal_entry'
                   || '|fn_reverse_posted_journal_entry'
                   || '|fn_finalize_journal_entry'
                   || '|fn_add_posting_line'
                   || '|fn_add_posting_line_push'
                   || '|fn_add_sales_invoice_posting_line');
$$;

REVOKE EXECUTE ON FUNCTION public.fn_posting_kernel_origin(TEXT) FROM PUBLIC;


CREATE OR REPLACE FUNCTION public.fn_post_credit_memo_vat_lump_impl(p_cm_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       credit_memos%ROWTYPE;
  v_ar        UUID;
  v_vat       UUID;
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

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.cm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.cm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  -- P5.1 Module 1: the direct header INSERT is replaced by the sanctioned kernel.
  -- Every value below is the one this function previously wrote itself.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount, v_rec.total_amount, 'system'
  );

  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_line.revenue_account_id, 'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, 'base');
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_vat, 'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, 'tax');
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  PERFORM fn_add_posting_line_push(
    v_je_id, v_line_no, v_ar, 'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, 'control');

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;

  -- Negative output VAT in tax ledger (reversal of original SI output VAT)
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CM', v_rec.id,
      'output_vat', -v_rec.total_taxable_amount, -v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.cm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      true
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_post_debit_memo_vat_lump_impl(p_dm_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       debit_memos%ROWTYPE;
  v_ar        UUID;
  v_vat       UUID;
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

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.dm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.dm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.dm_date
    AND end_date >= v_rec.dm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for DM date %. Create or unlock a fiscal period first.', v_rec.dm_date;
  END IF;

  -- P5.1 Module 1: the direct header INSERT is replaced by the sanctioned kernel.
  -- Every value below is the one this function previously wrote itself.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-DM-' || v_rec.dm_number, v_rec.dm_date,
    'Debit Memo ' || v_rec.dm_number || ' — ' || v_rec.customer_name_snapshot,
    'DM', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount, v_rec.total_amount, 'system'
  );

  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_ar, 'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, 'control');

  FOR v_line IN
    SELECT account_id, SUM(amount) AS amt_sum, description AS ln_desc
    FROM debit_memo_lines
    WHERE debit_memo_id = v_rec.id AND account_id IS NOT NULL
    GROUP BY account_id, description
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_line.account_id, 'DM charge — ' || v_line.ln_desc, 0, v_line.amt_sum, 'base');
    v_total_cr := v_total_cr + v_line.amt_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_vat, 'Output VAT — ' || v_rec.dm_number, 0, v_rec.total_vat_amount, 'tax');
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

  -- Positive output VAT in tax ledger
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'DM', v_rec.id,
      'output_vat', v_rec.total_taxable_amount, v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.dm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      false
    );
  END IF;
END;
$function$;

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

  -- P5.1 Module 1: the direct header INSERT is replaced by the sanctioned kernel.
  -- Every value below is the one this function previously wrote itself.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'VC', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount, v_rec.total_amount, 'system'
  );

  PERFORM fn_add_posting_line_push(
    v_je_id, 1, v_ap, 'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, 'control');

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_line.expense_account_id, 'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, 'base');
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    v_line_no := v_line_no + 1;
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_input_vat, 'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, 'tax');
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
