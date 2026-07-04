-- ══════════════════════════════════════════════════════════════════════════════
-- RECEIPT CWT: explicit VAT-exclusive taxable base + variance reason
-- Finding coverage: PXL-AUD-031 (session 49). Mirrors the PV explicit-basis
-- design (20260701000016).
--
-- Before this migration the receipt CWT base was DERIVED as payment + CWT
-- (VAT-inclusive) with no explicit-base column and no variance escape, so the
-- statutorily correct CWT (rate x VAT-exclusive income payment per RR 2-98)
-- was rejected by fn_validate_receipt_line_cwt, and tax_detail_entries /
-- SAWT income payments were overstated by the VAT.
--
-- Changes:
--   1. receipt_lines.cwt_tax_base + cwt_variance_reason (nullable; existing
--      rows keep NULL and retain the legacy payment+CWT fallback semantics).
--   2. fn_validate_receipt_line_cwt: new explicit-base signature with the PV
--      tolerance/variance mechanics (0.02 tolerance; controlled reason list).
--      The legacy 4-argument overload is dropped.
--   3. Trigger + fn_validate_receipt_cwt_ready + fn_save_receipt thread the
--      new columns through; fn_post_receipt writes the explicit base to the
--      tax ledger.
--   4. fn_save_cash_sale: CWT accepted on either the VAT-exclusive base
--      (preferred) or the legacy gross; the matching base is recorded.
--
-- ATC validity remains evaluated as of CURRENT_DATE — the as-of-document-date
-- anchor is a separate finding (PXL-AUD-035) and changes PV and OR together.
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE receipt_lines
  ADD COLUMN IF NOT EXISTS cwt_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS cwt_variance_reason TEXT;

COMMENT ON COLUMN receipt_lines.cwt_tax_base IS
  'Explicit CWT taxable base (VAT-exclusive income payment). NULL on legacy rows: consumers fall back to payment_amount + cwt_amount (gross). PXL-AUD-031.';
COMMENT ON COLUMN receipt_lines.cwt_variance_reason IS
  'Controlled reason when cwt_amount deviates from rate x base beyond 0.02 (same list as payment_voucher_lines.ewt_variance_reason).';

-- ── 1. Validator: explicit base + variance mechanics ──────────────────────────
-- The old 4-arg overload must go, otherwise 4-arg calls become ambiguous.
DROP FUNCTION IF EXISTS fn_validate_receipt_line_cwt(UUID, NUMERIC, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION fn_validate_receipt_line_cwt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_cwt_amount NUMERIC,
  p_atc_code_id UUID,
  p_cwt_tax_base NUMERIC DEFAULT NULL,
  p_cwt_variance_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate NUMERIC(8,4);
  v_code TEXT;
  v_base NUMERIC(15,2);
  v_expected NUMERIC(15,2);
  v_reason TEXT;
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_cwt_amount, 0) < 0 OR COALESCE(p_cwt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, CWT, and CWT taxable base cannot be negative.';
  END IF;

  IF COALESCE(p_cwt_amount, 0) = 0 AND COALESCE(p_cwt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when CWT amount or taxable base is specified.';
  END IF;

  SELECT code, rate INTO v_code, v_rate
  FROM atc_codes
  WHERE id = p_atc_code_id
    AND is_active = true
    AND deprecated_at IS NULL
    AND tax_category = 'ewt'
    AND effective_from <= CURRENT_DATE
    AND (effective_to IS NULL OR effective_to >= CURRENT_DATE);

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not valid for withholding.';
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive withholding rate.', v_code;
  END IF;

  -- Explicit base preferred (VAT-exclusive income payment); legacy fallback
  -- is payment + CWT (gross) so pre-existing rows and gross-convention
  -- withholding remain recordable.
  v_base := ROUND(COALESCE(p_cwt_tax_base, COALESCE(p_payment_amount, 0) + COALESCE(p_cwt_amount, 0)), 2);
  IF v_base <= 0 THEN
    RAISE EXCEPTION 'CWT taxable base is required when CWT is recorded.';
  END IF;

  v_expected := ROUND(v_base * v_rate / 100.0, 2);
  IF ABS(v_expected - COALESCE(p_cwt_amount, 0)) <= 0.02 THEN
    RETURN;
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_cwt_variance_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'CWT amount % does not match ATC % rate %%% on taxable base %. Expected CWT is %. Select a variance reason to proceed.',
      p_cwt_amount, v_code, v_rate, v_base, v_expected;
  END IF;

  IF v_reason NOT IN ('rounding', 'partial_non_taxable', 'bir_ruling', 'supplier_exempt', 'other_authorized') THEN
    RAISE EXCEPTION 'Invalid CWT variance reason: %', v_reason;
  END IF;
END;
$$;

-- ── 2. Row trigger threads the new columns ────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_require_receipt_line_cwt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_validate_receipt_line_cwt(
    NEW.company_id,
    NEW.payment_amount,
    NEW.cwt_amount,
    NEW.atc_code_id,
    NEW.cwt_tax_base,
    NEW.cwt_variance_reason
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_receipt_line_cwt_validation ON receipt_lines;
CREATE TRIGGER trg_receipt_line_cwt_validation
  BEFORE INSERT OR UPDATE OF company_id, payment_amount, cwt_amount, atc_code_id, cwt_tax_base, cwt_variance_reason
  ON receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_receipt_line_cwt_validation();

-- ── 3. Posting readiness re-validates every line with the new columns ─────────
CREATE OR REPLACE FUNCTION fn_validate_receipt_cwt_ready(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_header_cwt NUMERIC(15,2);
  v_line_cwt NUMERIC(15,2);
  v_line RECORD;
BEGIN
  SELECT COALESCE(total_cwt, 0) INTO v_header_cwt
  FROM receipts
  WHERE id = p_receipt_id;

  IF v_header_cwt IS NULL THEN
    RAISE EXCEPTION 'Receipt not found.';
  END IF;

  SELECT COALESCE(SUM(cwt_amount), 0) INTO v_line_cwt
  FROM receipt_lines
  WHERE receipt_id = p_receipt_id;

  IF ABS(v_header_cwt - v_line_cwt) > 0.02 THEN
    RAISE EXCEPTION 'Receipt total CWT % does not match line CWT total %.', v_header_cwt, v_line_cwt;
  END IF;

  FOR v_line IN
    SELECT company_id, payment_amount, cwt_amount, atc_code_id, cwt_tax_base, cwt_variance_reason
    FROM receipt_lines
    WHERE receipt_id = p_receipt_id
  LOOP
    PERFORM fn_validate_receipt_line_cwt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.cwt_amount,
      v_line.atc_code_id,
      v_line.cwt_tax_base,
      v_line.cwt_variance_reason
    );
  END LOOP;
END;
$$;

-- ── 4. fn_save_receipt: accept and validate the explicit base per line ────────
CREATE OR REPLACE FUNCTION fn_save_receipt(
  p_receipt_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_receipt_number TEXT;
  v_current_status TEXT;
  v_line           JSONB;
  v_inv_id         UUID;
  v_pay_amt        NUMERIC(15,2);
  v_cwt_amt        NUMERIC(15,2);
  v_cwt_base       NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_inv_id := NULLIF(v_line->>'invoice_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_cwt_amt := COALESCE((v_line->>'cwt_amount')::NUMERIC, 0);
    v_cwt_base := NULLIF(v_line->>'cwt_tax_base', '')::NUMERIC;
    CONTINUE WHEN v_inv_id IS NULL OR (v_pay_amt + v_cwt_amt) <= 0;

    IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE id = v_inv_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
    END IF;

    PERFORM fn_validate_receipt_line_cwt(
      v_company_id,
      v_pay_amt,
      v_cwt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      v_cwt_base,
      NULLIF(v_line->>'cwt_variance_reason', '')
    );

    SELECT si.total_amount - COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
    INTO v_outstanding
    FROM sales_invoices si
    LEFT JOIN receipt_lines rl
      ON rl.invoice_id = si.id
      AND rl.receipt_id != COALESCE(p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND rl.receipt_id IN (SELECT id FROM receipts WHERE status != 'bounced')
    WHERE si.id = v_inv_id
    GROUP BY si.total_amount;

    IF v_pay_amt + v_cwt_amt > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % plus CWT % exceeds outstanding balance of % for invoice',
        v_pay_amt, v_cwt_amt, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_receipt_id IS NULL THEN
    v_receipt_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

    INSERT INTO receipts (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      receipt_number, receipt_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_cwt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number, (p_header->>'receipt_date')::DATE,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''), NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''), 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_receipt_id;
  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts WHERE id = p_receipt_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id = v_branch_id, customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date = (p_header->>'receipt_date')::DATE,
      payment_mode_id = (p_header->>'payment_mode_id')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount,
    forex_adjustment, atc_code_id, cwt_tax_base, cwt_variance_reason,
    created_by, updated_by
  )
  SELECT
    v_receipt_id, v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    NULLIF(l->>'cwt_tax_base', '')::NUMERIC,
    NULLIF(l->>'cwt_variance_reason', ''),
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0
     OR COALESCE((l->>'cwt_amount')::NUMERIC, 0) != 0;

  RETURN v_receipt_id;
END;
$$;

-- ── 5. fn_post_receipt: tax ledger row carries the explicit base ──────────────
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
  v_rl        RECORD;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  PERFORM fn_validate_receipt_cwt_ready(p_receipt_id);

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

  v_ar_cr := v_rec.total_amount + v_rec.total_cwt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date, v_fp_id,
    'Official Receipt ' || v_rec.receipt_number || ' - ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id, 'posted',
    v_ar_cr, v_ar_cr,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cash_acct, 'Cash received - ' || v_rec.receipt_number, v_rec.total_amount, 0, auth.uid(), auth.uid());

  IF v_rec.total_cwt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, 2, v_cfg.ewt_withheld_account_id, 'CWT receivable - ' || v_rec.receipt_number, v_rec.total_cwt, 0, auth.uid(), auth.uid());
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
          v_cfg.ar_account_id, 'AR cleared - ' || v_rec.receipt_number, 0, v_ar_cr, auth.uid(), auth.uid());

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_rl IN
    SELECT rl.payment_amount, rl.cwt_amount, rl.atc_code_id, rl.cwt_tax_base, ac.rate AS cwt_rate
    FROM receipt_lines rl
    LEFT JOIN atc_codes ac ON ac.id = rl.atc_code_id
    WHERE rl.receipt_id = p_receipt_id
      AND rl.cwt_amount > 0
  LOOP
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'OR', v_rec.id,
      'cwt_receivable', v_rl.atc_code_id,
      ROUND(COALESCE(v_rl.cwt_tax_base, v_rl.payment_amount + v_rl.cwt_amount), 2),
      v_rl.cwt_rate, v_rl.cwt_amount, v_fp_id,
      NOW()::DATE, v_rec.receipt_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;
END;
$$;

-- ── 6. fn_save_cash_sale: net-or-gross base determination ─────────────────────
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
  v_net_of_vat    NUMERIC(15,2);
  v_cwt_base      NUMERIC(15,2);
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

  -- ── Receipt JE ───────────────────────────────────────────────────────────
  -- v_grand_total = full invoice amount (what AR carries)
  -- p_cwt_amount  = portion withheld by customer as EWT/CWT
  -- v_cash_received = actual cash deposited = grand_total − cwt
  v_cash_received := v_grand_total - p_cwt_amount;

  -- CWT taxable base (PXL-AUD-031): the statutory base is the VAT-exclusive
  -- income payment. Accept the net convention first; accept the legacy gross
  -- convention only when the amount matches that instead; otherwise reject
  -- with both expected values so the cashier can correct the entry.
  IF p_cwt_amount > 0 THEN
    IF v_cwt_rate IS NULL OR v_cwt_rate <= 0 THEN
      RAISE EXCEPTION 'CWT ATC code is missing, inactive, or has no positive rate.';
    END IF;
    v_net_of_vat := v_grand_total - v_total_vat;
    IF ABS(ROUND(v_net_of_vat * v_cwt_rate / 100.0, 2) - p_cwt_amount) <= 0.02 THEN
      v_cwt_base := v_net_of_vat;
    ELSIF ABS(ROUND(v_grand_total * v_cwt_rate / 100.0, 2) - p_cwt_amount) <= 0.02 THEN
      v_cwt_base := v_grand_total;
    ELSE
      RAISE EXCEPTION 'CWT % does not match ATC rate %%% on the VAT-exclusive base % (expected %) or on the gross % (expected %).',
        p_cwt_amount, v_cwt_rate,
        v_net_of_vat, ROUND(v_net_of_vat * v_cwt_rate / 100.0, 2),
        v_grand_total, ROUND(v_grand_total * v_cwt_rate / 100.0, 2);
    END IF;
  END IF;

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
  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, atc_code_id, cwt_tax_base, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total - p_cwt_amount, p_cwt_amount, v_cwt_atc,
          CASE WHEN p_cwt_amount > 0 THEN v_cwt_base ELSE NULL END, auth.uid(), auth.uid());

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

  -- CWT receivable tax ledger row. Base = the explicit CWT taxable base
  -- determined above (VAT-exclusive when the net convention was used), so
  -- SAWT income payments no longer overstate by the VAT (PXL-AUD-031).
  IF p_cwt_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', v_cwt_atc, v_cwt_base, v_cwt_rate, p_cwt_amount, v_fp_id,
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

GRANT EXECUTE ON FUNCTION fn_validate_receipt_line_cwt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_receipt_cwt_ready(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_cash_sale(JSONB, JSONB, NUMERIC) TO authenticated;
