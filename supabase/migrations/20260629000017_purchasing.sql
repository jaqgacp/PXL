-- ══════════════════════════════════════════════════════════════════════════════
-- PURCHASING MODULE: Vendor Bills + Payment Vouchers
-- AP mirror of the SI/Receipt cycle. GL entries are balanced double-entry.
-- Posting requires company_accounting_config (ap_account_id at minimum).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Extend company_accounting_config for AP ───────────────────────────────────
ALTER TABLE company_accounting_config
  ADD COLUMN IF NOT EXISTS ap_account_id        UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS input_vat_account_id UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS ewt_payable_account_id UUID REFERENCES chart_of_accounts(id);

-- ── vendor_bills ──────────────────────────────────────────────────────────────
CREATE TABLE vendor_bills (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               UUID        NOT NULL REFERENCES companies(id),
  branch_id                UUID        REFERENCES branches(id),
  supplier_id              UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot   TEXT        NOT NULL,
  supplier_tin_snapshot    TEXT,
  bill_number              TEXT        NOT NULL,          -- internal VB number
  supplier_invoice_number  TEXT,                          -- supplier's own ref
  bill_date                DATE        NOT NULL,
  due_date                 DATE,
  fiscal_period_id         UUID        REFERENCES fiscal_periods(id),
  payment_terms_id         UUID        REFERENCES payment_terms(id),
  currency_code            TEXT        NOT NULL DEFAULT 'PHP',
  reference                TEXT,
  memo                     TEXT,
  total_taxable_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_zero_rated_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_exempt_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_input_vat_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount             NUMERIC(15,2) NOT NULL DEFAULT 0,
  ewt_amount_expected      NUMERIC(15,2),
  status                   TEXT        NOT NULL DEFAULT 'draft'
                                       CHECK (status IN ('draft','approved','posted','cancelled')),
  void_reason_id           UUID        REFERENCES void_reasons(id),
  journal_entry_id         UUID        REFERENCES journal_entries(id),
  posted_by                UUID,
  posted_at                TIMESTAMPTZ,
  approved_by              UUID,
  approved_at              TIMESTAMPTZ,
  created_by               UUID,
  updated_by               UUID,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, bill_number)
);

CREATE TABLE vendor_bill_lines (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_bill_id    UUID        NOT NULL REFERENCES vendor_bills(id) ON DELETE CASCADE,
  company_id        UUID        NOT NULL REFERENCES companies(id),
  line_number       INT         NOT NULL,
  item_id           UUID        REFERENCES items(id),
  description       TEXT        NOT NULL,
  quantity          NUMERIC(15,4) NOT NULL DEFAULT 1,
  uom_id            UUID        REFERENCES units_of_measure(id),
  unit_price        NUMERIC(15,4) NOT NULL DEFAULT 0,
  discount_percent  NUMERIC(5,2) NOT NULL DEFAULT 0,
  discount_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  vat_code_id       UUID        REFERENCES vat_codes(id),
  input_vat_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  expense_account_id UUID       REFERENCES chart_of_accounts(id),
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_vendor_bills_company   ON vendor_bills (company_id, bill_date DESC);
CREATE INDEX idx_vendor_bills_supplier  ON vendor_bills (supplier_id);
CREATE INDEX idx_vbl_bill_id            ON vendor_bill_lines (vendor_bill_id);

CREATE TRIGGER trg_vendor_bills_updated_at
  BEFORE UPDATE ON vendor_bills FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_vendor_bill_lines_updated_at
  BEFORE UPDATE ON vendor_bill_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE vendor_bills      ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_bill_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vb_read"   ON vendor_bills      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "vb_insert" ON vendor_bills      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "vb_update" ON vendor_bills      FOR UPDATE TO authenticated
  USING (status IN ('draft','approved') AND is_company_member(company_id));
CREATE POLICY "vbl_read"  ON vendor_bill_lines FOR SELECT TO authenticated
  USING (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));
CREATE POLICY "vbl_write" ON vendor_bill_lines FOR INSERT TO authenticated
  WITH CHECK (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));
CREATE POLICY "vbl_update" ON vendor_bill_lines FOR UPDATE TO authenticated
  USING (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));
CREATE POLICY "vbl_delete" ON vendor_bill_lines FOR DELETE TO authenticated
  USING (vendor_bill_id IN (SELECT id FROM vendor_bills WHERE is_company_member(company_id)));

-- ── payment_vouchers ──────────────────────────────────────────────────────────
CREATE TABLE payment_vouchers (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID        NOT NULL REFERENCES companies(id),
  branch_id              UUID        REFERENCES branches(id),
  supplier_id            UUID        NOT NULL REFERENCES suppliers(id),
  supplier_name_snapshot TEXT        NOT NULL,
  supplier_tin_snapshot  TEXT,
  voucher_number         TEXT        NOT NULL,
  voucher_date           DATE        NOT NULL,
  payment_mode_id        UUID        REFERENCES payment_modes(id),
  reference_number       TEXT,
  bank_account_id        UUID        REFERENCES chart_of_accounts(id),
  total_amount           NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_ewt              NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks                TEXT,
  status                 TEXT        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft','posted','cancelled')),
  journal_entry_id       UUID        REFERENCES journal_entries(id),
  posted_by              UUID,
  posted_at              TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, voucher_number)
);

CREATE TABLE payment_voucher_lines (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_voucher_id  UUID        NOT NULL REFERENCES payment_vouchers(id) ON DELETE CASCADE,
  company_id          UUID        NOT NULL REFERENCES companies(id),
  vendor_bill_id      UUID        REFERENCES vendor_bills(id),
  payment_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  ewt_amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
  atc_code_id         UUID        REFERENCES atc_codes(id),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_vouchers_company  ON payment_vouchers (company_id, voucher_date DESC);
CREATE INDEX idx_pvl_voucher_id            ON payment_voucher_lines (payment_voucher_id);
CREATE INDEX idx_pvl_bill_id               ON payment_voucher_lines (vendor_bill_id);

CREATE TRIGGER trg_payment_vouchers_updated_at
  BEFORE UPDATE ON payment_vouchers FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_payment_voucher_lines_updated_at
  BEFORE UPDATE ON payment_voucher_lines FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE payment_vouchers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_voucher_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pv_read"   ON payment_vouchers      FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pv_insert" ON payment_vouchers      FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pv_update" ON payment_vouchers      FOR UPDATE TO authenticated
  USING (status = 'draft' AND is_company_member(company_id));
CREATE POLICY "pvl_read"  ON payment_voucher_lines FOR SELECT TO authenticated
  USING (payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE is_company_member(company_id)));
CREATE POLICY "pvl_write" ON payment_voucher_lines FOR INSERT TO authenticated
  WITH CHECK (payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE is_company_member(company_id)));
CREATE POLICY "pvl_delete" ON payment_voucher_lines FOR DELETE TO authenticated
  USING (payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE is_company_member(company_id)));

-- ── Audit triggers ────────────────────────────────────────────────────────────
DO $$
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_vendor_bills ON vendor_bills;
    CREATE TRIGGER trg_audit_vendor_bills AFTER INSERT OR UPDATE OR DELETE ON vendor_bills
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
  EXECUTE 'DROP TRIGGER IF EXISTS trg_audit_payment_vouchers ON payment_vouchers;
    CREATE TRIGGER trg_audit_payment_vouchers AFTER INSERT OR UPDATE OR DELETE ON payment_vouchers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();';
END;
$$;

-- ── fn_save_vendor_bill ───────────────────────────────────────────────────────
-- Atomic save of header + lines. Recomputes input VAT server-side.
-- Rejects edits on non-draft bills (must revert first).

CREATE OR REPLACE FUNCTION fn_save_vendor_bill(
  p_bill_id UUID,
  p_header  JSONB,
  p_lines   JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bill_id        UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_bill_number    TEXT;
  v_current_status TEXT;
  v_fiscal_period  UUID;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= (p_header->>'bill_date')::DATE
    AND end_date >= (p_header->>'bill_date')::DATE AND is_locked = false LIMIT 1;

  IF p_bill_id IS NULL THEN
    v_bill_number := fn_next_document_number(v_company_id, v_branch_id, 'VB');
    INSERT INTO vendor_bills (
      company_id, branch_id, supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      bill_number, supplier_invoice_number, bill_date, due_date, fiscal_period_id,
      payment_terms_id, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_input_vat_amount, total_amount, ewt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'supplier_id')::UUID, p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_bill_number, NULLIF(p_header->>'supplier_invoice_number', ''),
      (p_header->>'bill_date')::DATE, NULLIF(p_header->>'due_date', '')::DATE,
      v_fiscal_period, NULLIF(p_header->>'payment_terms_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0,
      NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_bill_id;
  ELSE
    SELECT id, status INTO v_bill_id, v_current_status
    FROM vendor_bills WHERE id = p_bill_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % vendor bill. Revert to draft first.', v_current_status;
    END IF;
    UPDATE vendor_bills SET
      branch_id = v_branch_id, supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_invoice_number = NULLIF(p_header->>'supplier_invoice_number', ''),
      bill_date = (p_header->>'bill_date')::DATE,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      fiscal_period_id = v_fiscal_period,
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      ewt_amount_expected = NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_input_vat_amount = 0, total_amount = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_bill_id;
  END IF;

  DELETE FROM vendor_bill_lines WHERE vendor_bill_id = v_bill_id;

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

    INSERT INTO vendor_bill_lines (
      vendor_bill_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_bill_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one non-empty line is required'; END IF;

  UPDATE vendor_bills SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, updated_at = NOW()
  WHERE id = v_bill_id;

  RETURN v_bill_id;
END;
$$;

-- ── fn_approve_vendor_bill ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_approve_vendor_bill(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft bills can be approved (current: %)', v_rec.status; END IF;
  UPDATE vendor_bills SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(),
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_bill_id;
END;
$$;

-- ── fn_revert_vendor_bill_to_draft ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_revert_vendor_bill_to_draft(p_bill_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN RAISE EXCEPTION 'Only approved bills can be reverted (current: %)', v_rec.status; END IF;
  UPDATE vendor_bills SET status = 'draft', approved_by = NULL, approved_at = NULL,
    updated_by = auth.uid(), updated_at = NOW() WHERE id = p_bill_id;
END;
$$;

-- ── fn_post_vendor_bill ───────────────────────────────────────────────────────
-- DR Expense accounts (per line) + DR Input VAT = CR Accounts Payable
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

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date, v_fp_id,
    'Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
    'MANUAL', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Expense accounts per line (grouped by expense_account_id)
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

  -- DR: Input VAT (if any)
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.input_vat_account_id,
            'Input VAT — ' || v_rec.bill_number, v_rec.total_input_vat_amount, 0, auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  -- CR: Accounts Payable
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ap_account_id,
          'AP — ' || v_rec.supplier_name_snapshot, 0, v_rec.total_amount, auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE vendor_bills SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── fn_void_vendor_bill ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_void_vendor_bill(
  p_bill_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status = 'cancelled' THEN RAISE EXCEPTION 'Bill is already cancelled'; END IF;
  UPDATE vendor_bills SET status = 'cancelled', void_reason_id = p_void_reason_id,
    memo = COALESCE(p_memo, memo), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_bill_id;
END;
$$;

-- ── fn_save_payment_voucher ───────────────────────────────────────────────────
-- Saves PV header + lines. Validates that payment doesn't exceed outstanding AP balance.
CREATE OR REPLACE FUNCTION fn_save_payment_voucher(
  p_voucher_id UUID,
  p_header     JSONB,
  p_lines      JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_voucher_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_voucher_number TEXT;
  v_current_status TEXT;
  v_line           JSONB;
  v_bill_id        UUID;
  v_pay_amt        NUMERIC(15,2);
  v_ewt_amt        NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  -- Validate each line: no over-payment
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_bill_id := NULLIF(v_line->>'vendor_bill_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_ewt_amt := COALESCE((v_line->>'ewt_amount')::NUMERIC, 0);
    CONTINUE WHEN v_bill_id IS NULL OR (v_pay_amt + v_ewt_amt) <= 0;

    IF NOT EXISTS (SELECT 1 FROM vendor_bills WHERE id = v_bill_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Vendor bill % does not belong to this company', v_bill_id;
    END IF;

    SELECT vb.total_amount - COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
    INTO v_outstanding
    FROM vendor_bills vb
    LEFT JOIN payment_voucher_lines pvl ON pvl.vendor_bill_id = vb.id
      AND pvl.payment_voucher_id != COALESCE(p_voucher_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND pvl.payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE status != 'cancelled')
    WHERE vb.id = v_bill_id GROUP BY vb.total_amount;

    IF (v_pay_amt + v_ewt_amt) > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % + EWT % exceeds outstanding AP balance of % for this bill',
        v_pay_amt, v_ewt_amt, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_voucher_id IS NULL THEN
    v_voucher_number := fn_next_document_number(v_company_id, v_branch_id, 'PV');
    INSERT INTO payment_vouchers (
      company_id, branch_id, supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      voucher_number, voucher_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_ewt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'supplier_id')::UUID, p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_voucher_number, (p_header->>'voucher_date')::DATE,
      NULLIF(p_header->>'payment_mode_id', '')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_voucher_id;
  ELSE
    SELECT id, status INTO v_voucher_id, v_current_status
    FROM payment_vouchers WHERE id = p_voucher_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment voucher not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % payment voucher', v_current_status; END IF;
    UPDATE payment_vouchers SET
      branch_id = v_branch_id, supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      voucher_date = (p_header->>'voucher_date')::DATE,
      payment_mode_id = NULLIF(p_header->>'payment_mode_id', '')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_ewt = COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_voucher_id;
  END IF;

  DELETE FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id;

  INSERT INTO payment_voucher_lines (payment_voucher_id, company_id, vendor_bill_id, payment_amount, ewt_amount, atc_code_id, created_by, updated_by)
  SELECT v_voucher_id, v_company_id,
    NULLIF(l->>'vendor_bill_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'ewt_amount')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) > 0;

  RETURN v_voucher_id;
END;
$$;

-- ── fn_post_payment_voucher ───────────────────────────────────────────────────
-- DR Accounts Payable = CR Cash/Bank + CR EWT Payable
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

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date AND is_locked = false LIMIT 1;

  v_ap_dr := v_rec.total_amount + v_rec.total_ewt;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date, v_fp_id,
    'Payment Voucher ' || v_rec.voucher_number || ' — ' || v_rec.supplier_name_snapshot,
    'MANUAL', v_rec.id, 'posted',
    v_ap_dr, v_ap_dr, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR: Accounts Payable (total cash + EWT clears the full AP balance)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
          'AP cleared — ' || v_rec.voucher_number, v_ap_dr, 0, auth.uid(), auth.uid());

  -- CR: Cash / Bank
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 2, v_cash_acct,
          'Cash paid — ' || v_rec.voucher_number, 0, v_rec.total_amount, auth.uid(), auth.uid());
  v_line_no := 3;

  -- CR: EWT Payable (amount withheld from supplier, to be remitted to BIR)
  IF v_rec.total_ewt > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_cfg.ewt_payable_account_id,
            'EWT withheld — ' || v_rec.voucher_number, 0, v_rec.total_ewt, auth.uid(), auth.uid());
  END IF;

  UPDATE payment_vouchers SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_save_vendor_bill(UUID, JSONB, JSONB)              TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_vendor_bill(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_revert_vendor_bill_to_draft(UUID)                 TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_vendor_bill(UUID)                            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_vendor_bill(UUID, UUID, TEXT)                TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_payment_voucher(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID)                        TO authenticated;
