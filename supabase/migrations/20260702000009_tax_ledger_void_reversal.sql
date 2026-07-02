-- ══════════════════════════════════════════════════════════════════════════════
-- Tax ledger void/cancel counter-entries (PXL-AUD-027)
--
-- Voiding a posted SI, voiding a VB, cancelling a posted PV, and bouncing a
-- posted OR all post a reversing counter-JE on the GL side, but the tax ledger
-- was left un-netted: SI void, PV cancel, and OR bounce never touched
-- tax_detail_entries at all, and VB void mutated the original row in place
-- (is_reversal = true, filing_status = 'amended') instead of preserving it.
-- Because fn_vat_gl_reconciliation sums all rows, a voided SI/VB produced a
-- false variance that blocked legitimate VAT returns (the session-23 gate),
-- a cancelled PV's EWT kept feeding vw_ewt_summary_ap and 2307 certificates,
-- and a bounced OR's CWT stayed claimable.
--
-- Fix, following DEC-002 and the session-24 GL convention (original and
-- corrective entries both preserved): reversal paths now INSERT a negating
-- counter-row (is_reversal = true, reverses_tax_detail_id -> original) dated
-- on the reversal date, mirroring the counter-JE. Originals are never mutated.
--
-- is_reversal semantics (now uniform): TRUE marks a negative/corrective row —
-- CM business reversals and void/cancel/bounce counter-rows. Reversed
-- originals stay is_reversal = FALSE and are identified by an incoming
-- reverses_tax_detail_id link.
-- ══════════════════════════════════════════════════════════════════════════════

COMMENT ON COLUMN tax_detail_entries.is_reversal IS
  'TRUE on negative/corrective rows only (credit memo reversals and void/cancel/bounce counter-rows). Originals are never flagged; a reversed original is found via an incoming reverses_tax_detail_id link.';
COMMENT ON COLUMN tax_detail_entries.reverses_tax_detail_id IS
  'On a counter-row: the original tax detail row this row negates. Dated on the reversal date so each period retains its own activity, matching the GL reversal JE.';

-- ── 1. Shared counter-row helper ───────────────────────────────────────────────
-- Called only from SECURITY DEFINER void/cancel/bounce RPCs; not user-callable.
CREATE OR REPLACE FUNCTION fn_reverse_tax_detail_entries(
  p_source_doc_type  TEXT,
  p_source_doc_id    UUID,
  p_reversal_date    DATE,
  p_fiscal_period_id UUID
)
RETURNS VOID LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, tax_code_id, vat_code_id, atc_code_id,
    tax_base, tax_rate, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name, income_nature,
    is_reversal, reverses_tax_detail_id, filing_status
  )
  SELECT
    t.company_id, t.branch_id, t.source_doc_type, t.source_doc_id,
    t.tax_kind, t.tax_code_id, t.vat_code_id, t.atc_code_id,
    -t.tax_base, t.tax_rate, -t.tax_amount, p_fiscal_period_id,
    NOW()::DATE, p_reversal_date,
    t.counterparty_id, t.counterparty_tin, t.counterparty_name, t.income_nature,
    true, t.id, 'draft'
  FROM tax_detail_entries t
  WHERE t.source_doc_type = p_source_doc_type
    AND t.source_doc_id   = p_source_doc_id
    AND t.is_reversal     = false
    AND NOT EXISTS (
      SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = t.id
    );
END;
$$;

REVOKE ALL ON FUNCTION fn_reverse_tax_detail_entries(TEXT, UUID, DATE, UUID) FROM PUBLIC, authenticated, anon;

-- ── 2. fn_void_sales_invoice: add tax ledger counter-rows ──────────────────────
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

    -- Net the tax ledger with counter-rows dated on the reversal date
    PERFORM fn_reverse_tax_detail_entries('SI', v_rec.id, CURRENT_DATE, v_fp_id);
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

-- ── 3. fn_void_vendor_bill: counter-rows instead of mutating originals ─────────
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

    -- Net the tax ledger with counter-rows; the original rows stay untouched
    PERFORM fn_reverse_tax_detail_entries('VB', v_rec.id, CURRENT_DATE, v_fp_id);
  END IF;

  UPDATE vendor_bills SET status = 'cancelled', void_reason_id = p_void_reason_id,
    memo = COALESCE(p_memo, memo), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_bill_id;
END;
$$;

-- ── 4. fn_cancel_payment_voucher: add EWT counter-rows ─────────────────────────
CREATE OR REPLACE FUNCTION fn_cancel_payment_voucher(
  p_voucher_id UUID,
  p_memo       TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec       payment_vouchers%ROWTYPE;
  v_orig_je   journal_entries%ROWTYPE;
  v_fp_id     UUID;
  v_rev_je_id UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
BEGIN
  SELECT * INTO v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted payment vouchers can be voided (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_orig_je FROM journal_entries WHERE id = v_rec.journal_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original journal entry not found for this payment voucher'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for today. Create or unlock a fiscal period to process this void.';
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VOID-' || v_rec.voucher_number, CURRENT_DATE, v_fp_id,
    'VOID: ' || v_orig_je.description || COALESCE(' — ' || p_memo, ''),
    'PV', v_rec.id, 'posted',
    v_orig_je.total_debit, v_orig_je.total_credit,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_rev_je_id;

  FOR v_line IN
    SELECT * FROM journal_entry_lines WHERE je_id = v_orig_je.id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_rev_je_id, v_rec.company_id, v_line_no, v_line.account_id,
      'VOID — ' || v_line.description,
      v_line.credit_amount, v_line.debit_amount,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE journal_entries SET status = 'reversed', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_orig_je.id;

  -- Net the EWT tax ledger so cancelled vouchers stop feeding 2307/QAP/1601EQ
  PERFORM fn_reverse_tax_detail_entries('PV', v_rec.id, CURRENT_DATE, v_fp_id);

  UPDATE payment_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 5. fn_bounce_receipt: add CWT counter-rows ─────────────────────────────────
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

    -- Net the CWT tax ledger so bounced receipts stop claiming tax credits
    PERFORM fn_reverse_tax_detail_entries('OR', v_rec.id, CURRENT_DATE, v_fp_id);
  END IF;

  UPDATE receipts SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- ── 6. vw_ewt_summary_ap: exclude reversed originals as well as counter-rows ───
-- Certificate/report source data shows only active withholding: a reversed
-- original and its counter-row both disappear (they net to zero in the raw
-- ledger, which reconciliation reads directly).
CREATE OR REPLACE VIEW vw_ewt_summary_ap AS
SELECT
  tde.source_doc_id     AS transaction_id,
  tde.company_id,
  tde.document_date     AS invoice_date,
  tde.counterparty_id   AS supplier_id,
  tde.counterparty_tin  AS supplier_tin,
  tde.counterparty_name AS supplier_name,
  tde.atc_code_id,
  ac.code               AS atc_code,
  COALESCE(NULLIF(tde.income_nature, ''), ac.description) AS nature_of_payment,
  tde.tax_rate,
  tde.tax_base,
  tde.tax_amount        AS tax_withheld
FROM tax_detail_entries tde
LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
WHERE tde.tax_kind = 'ewt_payable'
  AND tde.is_reversal = false
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = tde.id
  );

-- ── 7. Backfill existing environments ──────────────────────────────────────────
-- 7a. Undo the old VB void mutation: restore flipped originals. Only rows the
--     old fn_void_vendor_bill flipped match this signature (VB source, flagged,
--     'amended', no reverses link, cancelled parent). Born-negative rows (CM/VC)
--     have other source types and future counter-rows carry a reverses link.
UPDATE tax_detail_entries t
SET is_reversal = false, filing_status = 'draft'
WHERE t.source_doc_type = 'VB'
  AND t.is_reversal = true
  AND t.filing_status = 'amended'
  AND t.reverses_tax_detail_id IS NULL
  AND EXISTS (SELECT 1 FROM vendor_bills d WHERE d.id = t.source_doc_id AND d.status = 'cancelled');

-- 7b. Insert missing counter-rows for already-voided/cancelled/bounced documents,
--     dated on the reversal JE so each period nets exactly like the GL.
INSERT INTO tax_detail_entries (
  company_id, branch_id, source_doc_type, source_doc_id,
  tax_kind, tax_code_id, vat_code_id, atc_code_id,
  tax_base, tax_rate, tax_amount, tax_period_id,
  posting_date, document_date,
  counterparty_id, counterparty_tin, counterparty_name, income_nature,
  is_reversal, reverses_tax_detail_id, filing_status
)
SELECT
  t.company_id, t.branch_id, t.source_doc_type, t.source_doc_id,
  t.tax_kind, t.tax_code_id, t.vat_code_id, t.atc_code_id,
  -t.tax_base, t.tax_rate, -t.tax_amount, rev.fiscal_period_id,
  NOW()::DATE, rev.je_date,
  t.counterparty_id, t.counterparty_tin, t.counterparty_name, t.income_nature,
  true, t.id, 'draft'
FROM tax_detail_entries t
JOIN LATERAL (
  SELECT je.je_date, je.fiscal_period_id
  FROM journal_entries je
  WHERE je.company_id = t.company_id
    AND je.reference_doc_id = t.source_doc_id
    AND je.status = 'posted'
    AND (je.reference_doc_type = 'REV' OR je.je_number LIKE 'JE-VOID-%')
  ORDER BY je.created_at DESC
  LIMIT 1
) rev ON true
WHERE t.is_reversal = false
  AND NOT EXISTS (SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = t.id)
  AND (
       (t.source_doc_type = 'SI' AND EXISTS (SELECT 1 FROM sales_invoices   d WHERE d.id = t.source_doc_id AND d.status = 'cancelled'))
    OR (t.source_doc_type = 'VB' AND EXISTS (SELECT 1 FROM vendor_bills     d WHERE d.id = t.source_doc_id AND d.status = 'cancelled'))
    OR (t.source_doc_type = 'PV' AND EXISTS (SELECT 1 FROM payment_vouchers d WHERE d.id = t.source_doc_id AND d.status = 'cancelled'))
    OR (t.source_doc_type = 'OR' AND EXISTS (SELECT 1 FROM receipts         d WHERE d.id = t.source_doc_id AND d.status = 'bounced'))
  );
