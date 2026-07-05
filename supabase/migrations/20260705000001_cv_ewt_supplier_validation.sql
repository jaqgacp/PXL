-- ══════════════════════════════════════════════════════════════════════════════
-- CHECK VOUCHER EWT: supplier linkage + PV-parity validation + counter-row cancel
-- Finding coverage: PXL-AUD-032 / PXL-AUD-033.
--
-- The CV module predated the PV EWT hardening: fn_post_check_voucher wrote the
-- ewt_payable tax detail row with counterparty_id = NULL (free-text payee only),
-- tax_base = gross voucher amount, and a UI-snapshot rate — with no rate/base/
-- ATC validation anywhere on the path. Because fn_generate_form_2307_issued
-- aborted when ANY source row had supplier_id IS NULL, a single CV EWT row
-- blocked the whole quarter's 2307 batch for every supplier. Cancel inserted a
-- bare negative row (no reverses_tax_detail_id, dated on the ORIGINAL voucher
-- date), so vw_ewt_summary_ap kept showing the cancelled CV's original row —
-- a phantom certificate line that QAP/2307/1601EQ prefill all inherited.
--
-- Fix:
--  1. check_vouchers gains supplier_id / ewt_tax_base / ewt_variance_reason.
--     A supplier link is REQUIRED whenever EWT is withheld. Validation reuses
--     fn_validate_payment_voucher_line_ewt (current ATC, rate-on-base with the
--     0.02 tolerance, controlled variance reasons) via a header trigger, and
--     again inside fn_post_check_voucher.
--  2. fn_post_check_voucher writes counterparty_id + supplier master TIN/name
--     and the explicit taxable base (fallback: gross, the legacy convention);
--     the recorded rate comes from the ATC master, not the UI snapshot.
--  3. fn_cancel_check_voucher now uses fn_reverse_tax_detail_entries (the
--     PXL-AUD-027 counter-row convention: reverses link, dated on cancel date).
--  4. Legacy CV counter-rows are backfilled with the reverses link and re-dated
--     onto their reversal JE, matching the 20260702000009 backfill convention.
--  5. fn_generate_form_2307_issued SKIPS supplier-unlinked rows with a warning
--     count in its result instead of aborting the entire batch. Linked rows
--     missing TIN/ATC still abort (fixable data errors on known suppliers).
--
-- New columns are business columns on a PXL-DA-011-guarded header: they freeze
-- automatically once the CV leaves draft; no guard allowlist change is needed.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Schema: supplier link + explicit EWT base ────────────────────────────────
ALTER TABLE check_vouchers
  ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES suppliers(id),
  ADD COLUMN IF NOT EXISTS ewt_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS ewt_variance_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_cv_supplier ON check_vouchers (supplier_id);

COMMENT ON COLUMN check_vouchers.supplier_id IS
  'Required when total_ewt_amount > 0: EWT withheld by check must be certificate-traceable to a supplier (PXL-AUD-032).';
COMMENT ON COLUMN check_vouchers.ewt_tax_base IS
  'Explicit EWT taxable base. NULL falls back to the gross voucher amount (legacy convention).';

-- ── 2. Header validation trigger (PV parity) ────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_require_cv_ewt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.supplier_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM suppliers WHERE id = NEW.supplier_id AND company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF COALESCE(NEW.total_ewt_amount, 0) > 0 AND NEW.supplier_id IS NULL THEN
    RAISE EXCEPTION 'A supplier is required when EWT is withheld on a check voucher (Form 2307 traceability).';
  END IF;

  PERFORM fn_validate_payment_voucher_line_ewt(
    NEW.company_id,
    COALESCE(NEW.total_gross_amount, 0) - COALESCE(NEW.total_ewt_amount, 0),
    NEW.total_ewt_amount,
    NEW.atc_code_id,
    NEW.ewt_tax_base,
    NEW.ewt_variance_reason
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cv_ewt_validation ON check_vouchers;
CREATE TRIGGER trg_cv_ewt_validation
  BEFORE INSERT OR UPDATE OF company_id, supplier_id, total_gross_amount,
    total_ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
  ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_cv_ewt_validation();

-- ── 3. fn_post_check_voucher: validated, supplier-linked tax detail ─────────────
CREATE OR REPLACE FUNCTION fn_post_check_voucher(p_cv_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec      check_vouchers%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
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

    -- PV-parity validation against the recomputed gross (fallback base = gross)
    PERFORM fn_validate_payment_voucher_line_ewt(
      v_rec.company_id,
      v_gross - v_rec.total_ewt_amount,
      v_rec.total_ewt_amount,
      v_rec.atc_code_id,
      v_rec.ewt_tax_base,
      v_rec.ewt_variance_reason
    );

    SELECT rate INTO v_atc_rate FROM atc_codes WHERE id = v_rec.atc_code_id;
  END IF;

  v_net := v_gross - v_rec.total_ewt_amount;
  IF v_net <= 0 THEN RAISE EXCEPTION 'Net check amount must be greater than zero'; END IF;

  IF v_rec.total_ewt_amount > 0 THEN
    SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
    IF NOT FOUND OR v_cfg.ewt_payable_account_id IS NULL THEN
      RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
    END IF;
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

  -- DR each distinct expense account
  FOR v_line IN
    SELECT expense_account_id, SUM(amount) AS amt
    FROM check_voucher_lines WHERE cv_id = v_rec.id
    GROUP BY expense_account_id
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_line.expense_account_id, v_rec.particulars, v_line.amt, 0, auth.uid(), auth.uid());
    v_no := v_no + 1;
  END LOOP;

  -- CR bank (net) + CR EWT payable (if any)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_no, v_bank_gl, 'Check ' || v_rec.check_number || ' — ' || v_rec.payee, 0, v_net, auth.uid(), auth.uid());
  v_no := v_no + 1;

  IF v_rec.total_ewt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_no, v_cfg.ewt_payable_account_id, 'EWT withheld — ' || v_rec.cv_number, 0, v_rec.total_ewt_amount, auth.uid(), auth.uid());

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
$$;

-- ── 4. fn_cancel_check_voucher: counter-row convention (PXL-AUD-027) ────────────
CREATE OR REPLACE FUNCTION fn_cancel_check_voucher(p_cv_id UUID, p_memo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec   check_vouchers%ROWTYPE;
  v_fp_id UUID;
BEGIN
  SELECT * INTO v_rec FROM check_vouchers WHERE id = p_cv_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Check voucher not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('posted','released') THEN
    RAISE EXCEPTION 'Only posted or released check vouchers can be cancelled (current: %)', v_rec.status;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for today to process this cancellation'; END IF;

  PERFORM fn_bt_reverse_je(v_rec.company_id, v_rec.branch_id, v_rec.journal_entry_id,
    'CV', v_rec.id, 'JE-CV-REV-' || v_rec.cv_number, p_memo);

  -- Negating counter-row with reverses link, dated on the cancellation date,
  -- so vw_ewt_summary_ap drops both rows and each period keeps its own activity.
  PERFORM fn_reverse_tax_detail_entries('CV', v_rec.id, CURRENT_DATE, v_fp_id);

  UPDATE check_vouchers SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── 5. Backfill legacy CV counter-rows ──────────────────────────────────────────
-- Old cancels inserted bare negative rows (is_reversal = true, no reverses link,
-- dated on the ORIGINAL voucher date). Link each to its original and re-date it
-- onto the reversal JE, matching the 20260702000009 backfill convention. A CV
-- writes at most one ewt_payable row, so the source_doc_id + amount match is
-- unambiguous. tax_detail_entries is not a PXL-DA-011-guarded table.
UPDATE tax_detail_entries r
SET reverses_tax_detail_id = t.id,
    document_date = COALESCE(rev.je_date, r.document_date),
    tax_period_id = COALESCE(rev.fiscal_period_id, r.tax_period_id)
FROM tax_detail_entries t
LEFT JOIN LATERAL (
  SELECT je.je_date, je.fiscal_period_id
  FROM journal_entries je
  WHERE je.reference_doc_type = 'CV'
    AND je.reference_doc_id = t.source_doc_id
    AND je.je_number LIKE 'JE-CV-REV-%'
  ORDER BY je.created_at DESC
  LIMIT 1
) rev ON true
WHERE r.source_doc_type = 'CV'
  AND r.is_reversal = true
  AND r.reverses_tax_detail_id IS NULL
  AND t.source_doc_type = 'CV'
  AND t.source_doc_id = r.source_doc_id
  AND t.tax_kind = r.tax_kind
  AND t.is_reversal = false
  AND t.tax_amount = -r.tax_amount;

-- ── 6. fn_generate_form_2307_issued: skip unlinked rows with a warning ──────────
CREATE OR REPLACE FUNCTION fn_generate_form_2307_issued(
  p_company_id UUID,
  p_tax_year INT,
  p_tax_quarter INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_date DATE;
  v_end_exclusive DATE;
  v_rows INT := 0;
  v_generated INT := 0;
  v_locked INT := 0;
  v_unlinked INT := 0;
  v_unlinked_ewt NUMERIC(15,2) := 0;
BEGIN
  IF p_tax_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid tax quarter: %', p_tax_quarter;
  END IF;

  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: owner/admin role required to generate Form 2307 certificates';
  END IF;

  v_start_date := make_date(p_tax_year, ((p_tax_quarter - 1) * 3) + 1, 1);
  v_end_exclusive := v_start_date + INTERVAL '3 months';

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_source;
  CREATE TEMP TABLE tmp_f2307_source ON COMMIT DROP AS
  SELECT
    supplier_id,
    supplier_name,
    supplier_tin,
    atc_code_id,
    atc_code,
    nature_of_payment,
    COALESCE(tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
    SUM(COALESCE(tax_base, 0))::NUMERIC(15,2) AS tax_base,
    SUM(COALESCE(tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld
  FROM vw_ewt_summary_ap
  WHERE company_id = p_company_id
    AND invoice_date >= v_start_date
    AND invoice_date < v_end_exclusive
  GROUP BY supplier_id, supplier_name, supplier_tin, atc_code_id, atc_code, nature_of_payment, COALESCE(tax_rate, 0);

  -- Supplier-unlinked rows cannot receive a certificate: skip them with a
  -- warning instead of aborting the whole quarter's batch (PXL-AUD-032).
  SELECT COUNT(*), COALESCE(SUM(tax_withheld), 0)
  INTO v_unlinked, v_unlinked_ewt
  FROM tmp_f2307_source
  WHERE supplier_id IS NULL;

  DELETE FROM tmp_f2307_source WHERE supplier_id IS NULL;

  SELECT COUNT(*) INTO v_rows FROM tmp_f2307_source;
  IF v_rows = 0 THEN
    IF v_unlinked > 0 THEN
      RAISE EXCEPTION 'Cannot generate Form 2307: every EWT row in Q% % is missing a supplier link. Link the source documents to suppliers first.',
        p_tax_quarter, p_tax_year;
    END IF;
    RAISE EXCEPTION 'No EWT data found for Q% %', p_tax_quarter, p_tax_year;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_f2307_source
    WHERE NULLIF(BTRIM(COALESCE(supplier_tin, '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(atc_code, '')), '') IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot generate Form 2307: supplier TIN and ATC are required for every EWT detail row';
  END IF;

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_supplier_totals;
  CREATE TEMP TABLE tmp_f2307_supplier_totals ON COMMIT DROP AS
  SELECT
    supplier_id,
    SUM(tax_base)::NUMERIC(15,2) AS total_tax_base,
    SUM(tax_withheld)::NUMERIC(15,2) AS total_ewt
  FROM tmp_f2307_source
  GROUP BY supplier_id;

  SELECT COUNT(*) INTO v_locked
  FROM tmp_f2307_supplier_totals st
  JOIN form_2307_issuances f
    ON f.company_id = p_company_id
   AND f.supplier_id = st.supplier_id
   AND f.tax_year = p_tax_year
   AND f.tax_quarter = p_tax_quarter
   AND f.status <> 'superseded'
  WHERE f.status IN ('sent', 'acknowledged');

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_written;
  CREATE TEMP TABLE tmp_f2307_written ON COMMIT DROP AS
  WITH writeable AS (
    SELECT st.*
    FROM tmp_f2307_supplier_totals st
    LEFT JOIN form_2307_issuances f
      ON f.company_id = p_company_id
     AND f.supplier_id = st.supplier_id
     AND f.tax_year = p_tax_year
     AND f.tax_quarter = p_tax_quarter
     AND f.status <> 'superseded'
    WHERE f.id IS NULL OR f.status IN ('pending', 'generated')
  ),
  upserted AS (
    INSERT INTO form_2307_issuances (
      company_id, supplier_id, tax_year, tax_quarter,
      total_tax_base, total_ewt, status, date_generated,
      date_sent, date_acknowledged, created_by, updated_by
    )
    SELECT
      p_company_id, supplier_id, p_tax_year, p_tax_quarter,
      total_tax_base, total_ewt, 'generated', NOW(),
      NULL, NULL, auth.uid(), auth.uid()
    FROM writeable
    ON CONFLICT (company_id, supplier_id, tax_year, tax_quarter)
      WHERE status <> 'superseded'
    DO UPDATE SET
      total_tax_base = EXCLUDED.total_tax_base,
      total_ewt = EXCLUDED.total_ewt,
      status = 'generated',
      date_generated = NOW(),
      date_sent = NULL,
      date_acknowledged = NULL,
      updated_by = auth.uid()
    WHERE form_2307_issuances.status IN ('pending', 'generated')
    RETURNING id, supplier_id
  )
  SELECT id, supplier_id FROM upserted;

  SELECT COUNT(*) INTO v_generated FROM tmp_f2307_written;

  DELETE FROM form_2307_issuance_lines l
  USING tmp_f2307_written w
  WHERE l.issuance_id = w.id;

  INSERT INTO form_2307_issuance_lines (
    issuance_id, company_id, atc_code_id, atc_code, nature_of_income,
    tax_base, tax_rate, tax_withheld
  )
  SELECT
    w.id, p_company_id, s.atc_code_id, s.atc_code,
    COALESCE(s.nature_of_payment, ''),
    s.tax_base, s.tax_rate, s.tax_withheld
  FROM tmp_f2307_source s
  JOIN tmp_f2307_written w ON w.supplier_id = s.supplier_id;

  RETURN jsonb_build_object(
    'generated_count', v_generated,
    'skipped_locked_count', v_locked,
    'skipped_unlinked_count', v_unlinked,
    'skipped_unlinked_ewt', v_unlinked_ewt
  );
END;
$$;
