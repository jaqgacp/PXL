-- PXL-AUD-043: cash purchases support AP-side EWT at payment time.
-- Advances/down-payments remain a separate document-design slice; this migration
-- closes the cash-purchase gap by carrying line ATC/base/amount, posting EWT
-- payable, and writing source-line tax-detail rows for QAP/2307 evidence.

ALTER TABLE cash_purchases
  ADD COLUMN IF NOT EXISTS total_ewt_amount NUMERIC(15,2) NOT NULL DEFAULT 0;

ALTER TABLE cash_purchase_lines
  ADD COLUMN IF NOT EXISTS ewt_atc_code_id UUID REFERENCES atc_codes(id),
  ADD COLUMN IF NOT EXISTS ewt_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS ewt_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ewt_income_nature TEXT,
  ADD COLUMN IF NOT EXISTS ewt_variance_reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'cash_purchases_total_ewt_amount_nonnegative'
  ) THEN
    ALTER TABLE cash_purchases
      ADD CONSTRAINT cash_purchases_total_ewt_amount_nonnegative
      CHECK (total_ewt_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'cash_purchase_lines_ewt_tax_base_nonnegative'
  ) THEN
    ALTER TABLE cash_purchase_lines
      ADD CONSTRAINT cash_purchase_lines_ewt_tax_base_nonnegative
      CHECK (ewt_tax_base IS NULL OR ewt_tax_base >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'cash_purchase_lines_ewt_amount_nonnegative'
  ) THEN
    ALTER TABLE cash_purchase_lines
      ADD CONSTRAINT cash_purchase_lines_ewt_amount_nonnegative
      CHECK (ewt_amount >= 0);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_cpl_ewt_atc
  ON cash_purchase_lines (ewt_atc_code_id)
  WHERE ewt_atc_code_id IS NOT NULL;

CREATE OR REPLACE FUNCTION fn_apply_cash_purchase_line_ewt_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_document_date DATE;
  v_rate NUMERIC(8,4);
  v_description TEXT;
  v_has_ewt BOOLEAN;
  v_gross NUMERIC(15,2);
BEGIN
  SELECT transaction_date
  INTO v_document_date
  FROM cash_purchases
  WHERE id = NEW.cp_id;

  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Cash purchase header is required before EWT validation.';
  END IF;

  IF NEW.ewt_atc_code_id IS NOT NULL THEN
    SELECT ac.rate, ac.description
    INTO v_rate, v_description
    FROM atc_codes ac
    WHERE ac.id = NEW.ewt_atc_code_id
      AND ac.is_active = true
      AND ac.deprecated_at IS NULL
      AND ac.tax_category = 'ewt'
      AND ac.effective_from <= v_document_date
      AND (ac.effective_to IS NULL OR ac.effective_to >= v_document_date);

    IF v_rate IS NULL THEN
      RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on cash purchase date %.',
        v_document_date;
    END IF;

    NEW.ewt_tax_base := ROUND(COALESCE(NEW.ewt_tax_base, NEW.net_amount, 0), 2);
    IF COALESCE(NEW.ewt_amount, 0) = 0 AND COALESCE(NEW.ewt_tax_base, 0) > 0 THEN
      NEW.ewt_amount := ROUND(NEW.ewt_tax_base * v_rate / 100.0, 2);
    END IF;
    NEW.ewt_income_nature := COALESCE(
      NULLIF(BTRIM(NEW.ewt_income_nature), ''),
      NULLIF(BTRIM(NEW.description), ''),
      v_description
    );
  END IF;

  NEW.ewt_amount := COALESCE(NEW.ewt_amount, 0);
  v_has_ewt := NEW.ewt_atc_code_id IS NOT NULL
            OR NEW.ewt_tax_base IS NOT NULL
            OR NEW.ewt_amount > 0;

  IF v_has_ewt THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Cash purchase');

    PERFORM fn_validate_payment_voucher_line_ewt(
      NEW.company_id,
      ROUND(COALESCE(NEW.net_amount, 0) + COALESCE(NEW.input_vat_amount, 0) - NEW.ewt_amount, 2),
      NEW.ewt_amount,
      NEW.ewt_atc_code_id,
      NEW.ewt_tax_base,
      NEW.ewt_variance_reason,
      v_document_date
    );
  END IF;

  v_gross := ROUND(COALESCE(NEW.net_amount, 0) + COALESCE(NEW.input_vat_amount, 0), 2);
  IF NEW.ewt_amount > v_gross + 0.02 THEN
    RAISE EXCEPTION 'Cash purchase line EWT % exceeds gross line amount %.',
      NEW.ewt_amount, v_gross;
  END IF;
  NEW.total_amount := ROUND(v_gross - NEW.ewt_amount, 2);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cpl_ewt_profile ON cash_purchase_lines;
CREATE TRIGGER trg_cpl_ewt_profile
  BEFORE INSERT OR UPDATE OF company_id, cp_id, description, net_amount,
    input_vat_amount, total_amount, ewt_atc_code_id, ewt_tax_base, ewt_amount,
    ewt_income_nature, ewt_variance_reason
  ON cash_purchase_lines
  FOR EACH ROW EXECUTE FUNCTION fn_apply_cash_purchase_line_ewt_profile();

CREATE OR REPLACE FUNCTION fn_validate_cash_purchase_ewt_ready(p_cp_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec cash_purchases%ROWTYPE;
  v_line RECORD;
  v_header_gross NUMERIC(15,2);
  v_line_gross NUMERIC(15,2);
  v_line_cash NUMERIC(15,2);
  v_line_ewt NUMERIC(15,2);
  v_has_ewt BOOLEAN;
BEGIN
  SELECT * INTO v_rec
  FROM cash_purchases
  WHERE id = p_cp_id;

  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Cash purchase not found or access denied';
  END IF;

  SELECT
    COALESCE(SUM(cpl.net_amount + cpl.input_vat_amount), 0)::NUMERIC(15,2),
    COALESCE(SUM(cpl.total_amount), 0)::NUMERIC(15,2),
    COALESCE(SUM(cpl.ewt_amount), 0)::NUMERIC(15,2),
    EXISTS (
      SELECT 1
      FROM cash_purchase_lines e
      WHERE e.cp_id = p_cp_id
        AND (
          COALESCE(e.ewt_amount, 0) > 0
          OR e.ewt_atc_code_id IS NOT NULL
          OR e.ewt_tax_base IS NOT NULL
        )
    )
  INTO v_line_gross, v_line_cash, v_line_ewt, v_has_ewt
  FROM cash_purchase_lines cpl
  WHERE cpl.cp_id = p_cp_id;

  v_header_gross := ROUND(
    COALESCE(v_rec.total_taxable_amount, 0)
    + COALESCE(v_rec.total_zero_rated_amount, 0)
    + COALESCE(v_rec.total_exempt_amount, 0)
    + COALESCE(v_rec.total_input_vat_amount, 0),
    2
  );

  IF ABS(v_header_gross - v_line_gross) > 0.02 THEN
    RAISE EXCEPTION 'Cash purchase gross total % does not match line gross total %.',
      v_header_gross, v_line_gross;
  END IF;

  IF ABS(COALESCE(v_rec.total_ewt_amount, 0) - v_line_ewt) > 0.02 THEN
    RAISE EXCEPTION 'Cash purchase total EWT % does not match line EWT total %.',
      COALESCE(v_rec.total_ewt_amount, 0), v_line_ewt;
  END IF;

  IF ABS(COALESCE(v_rec.total_amount, 0) - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION 'Cash purchase total amount % does not match line cash total %.',
      COALESCE(v_rec.total_amount, 0), v_line_cash;
  END IF;

  IF ABS(v_line_cash - (v_line_gross - v_line_ewt)) > 0.02 THEN
    RAISE EXCEPTION 'Cash purchase cash total % must equal gross % less EWT %.',
      v_line_cash, v_line_gross, v_line_ewt;
  END IF;

  IF v_has_ewt THEN
    PERFORM fn_require_company_ewt_payable_enabled(v_rec.company_id, 'Cash purchase posting');

    IF v_rec.supplier_id IS NULL THEN
      RAISE EXCEPTION 'Supplier is required when cash purchase EWT is recorded.';
    END IF;
  END IF;

  FOR v_line IN
    SELECT company_id, net_amount, input_vat_amount, ewt_amount,
           ewt_atc_code_id, ewt_tax_base, ewt_variance_reason
    FROM cash_purchase_lines
    WHERE cp_id = p_cp_id
  LOOP
    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id,
      ROUND(COALESCE(v_line.net_amount, 0) + COALESCE(v_line.input_vat_amount, 0)
        - COALESCE(v_line.ewt_amount, 0), 2),
      v_line.ewt_amount,
      v_line.ewt_atc_code_id,
      v_line.ewt_tax_base,
      v_line.ewt_variance_reason,
      v_rec.transaction_date
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_cash_purchase_post_ewt_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND (
       COALESCE(NEW.total_ewt_amount, 0) > 0
       OR EXISTS (
         SELECT 1
         FROM cash_purchase_lines cpl
         WHERE cpl.cp_id = NEW.id
           AND (
             COALESCE(cpl.ewt_amount, 0) > 0
             OR cpl.ewt_atc_code_id IS NOT NULL
             OR cpl.ewt_tax_base IS NOT NULL
           )
       )
     ) THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Cash purchase posting');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cash_purchase_post_ewt_profile ON cash_purchases;
CREATE TRIGGER trg_cash_purchase_post_ewt_profile
  BEFORE UPDATE OF status ON cash_purchases
  FOR EACH ROW EXECUTE FUNCTION fn_require_cash_purchase_post_ewt_profile();

CREATE OR REPLACE FUNCTION fn_save_cash_purchase(
  p_cp_id  UUID,
  p_header JSONB,
  p_lines  JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cp_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_cp_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_doc_date     DATE;
  v_supplier_id  UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_vat_rate     NUMERIC(5,2);
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_line_gross   NUMERIC(15,2);
  v_line_cash    NUMERIC(15,2);
  v_ewt_atc_id   UUID;
  v_ewt_base     NUMERIC(15,2);
  v_ewt_amt      NUMERIC(15,2);
  v_ewt_rate     NUMERIC(8,4);
  v_ewt_nature   TEXT;
  v_ewt_reason   TEXT;
  v_taxable      NUMERIC(15,2) := 0;
  v_zero_rated   NUMERIC(15,2) := 0;
  v_exempt       NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_gross_total  NUMERIC(15,2) := 0;
  v_total_ewt    NUMERIC(15,2) := 0;
  v_cash_total   NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  v_doc_date   := (p_header->>'transaction_date')::DATE;
  v_supplier_id := NULLIF(p_header->>'supplier_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_doc_date
    AND end_date   >= v_doc_date
    AND is_locked = false LIMIT 1;

  IF p_cp_id IS NULL THEN
    v_cp_number := fn_next_document_number(v_company_id, v_branch_id, 'CP');
    INSERT INTO cash_purchases (
      company_id, branch_id, cp_number, transaction_date,
      supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      payment_account_id, payment_method, reference_number,
      fiscal_period_id, remarks, total_taxable_amount, total_zero_rated_amount,
      total_exempt_amount, total_input_vat_amount, total_ewt_amount, total_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_cp_number, v_doc_date,
      v_supplier_id,
      NULLIF(p_header->>'supplier_name_snapshot', ''),
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'payment_account_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      NULLIF(p_header->>'reference_number', ''),
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_cp_id;
  ELSE
    SELECT id, status INTO v_cp_id, v_cur_status
    FROM cash_purchases WHERE id = p_cp_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash purchase not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % cash purchase', v_cur_status; END IF;
    UPDATE cash_purchases SET
      transaction_date = v_doc_date,
      supplier_id = v_supplier_id,
      supplier_name_snapshot = NULLIF(p_header->>'supplier_name_snapshot', ''),
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      payment_account_id = NULLIF(p_header->>'payment_account_id', '')::UUID,
      payment_method = COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      reference_number = NULLIF(p_header->>'reference_number', ''),
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0,
      total_exempt_amount = 0, total_input_vat_amount = 0,
      total_ewt_amount = 0, total_amount = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cp_id;
  END IF;

  DELETE FROM cash_purchase_lines WHERE cp_id = v_cp_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;
    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_line->>'unit_price', '')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_line_gross := ROUND(v_net + v_vat_amt, 2);

    v_ewt_atc_id := COALESCE(
      NULLIF(v_line->>'ewt_atc_code_id', '')::UUID,
      NULLIF(v_line->>'atc_code_id', '')::UUID
    );
    v_ewt_base := NULLIF(v_line->>'ewt_tax_base', '')::NUMERIC;
    v_ewt_amt := COALESCE(NULLIF(v_line->>'ewt_amount', '')::NUMERIC, 0);
    v_ewt_nature := NULLIF(v_line->>'ewt_income_nature', '');
    v_ewt_reason := NULLIF(v_line->>'ewt_variance_reason', '');

    IF v_ewt_atc_id IS NOT NULL AND v_ewt_base IS NULL THEN
      v_ewt_base := v_net;
    END IF;

    IF v_ewt_atc_id IS NOT NULL AND COALESCE(v_ewt_amt, 0) = 0 AND COALESCE(v_ewt_base, 0) > 0 THEN
      SELECT rate INTO v_ewt_rate
      FROM atc_codes
      WHERE id = v_ewt_atc_id
        AND is_active = true
        AND deprecated_at IS NULL
        AND tax_category = 'ewt'
        AND effective_from <= v_doc_date
        AND (effective_to IS NULL OR effective_to >= v_doc_date);
      IF v_ewt_rate IS NULL THEN
        RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on cash purchase date %.',
          v_doc_date;
      END IF;
      v_ewt_amt := ROUND(v_ewt_base * v_ewt_rate / 100.0, 2);
    END IF;

    IF v_ewt_atc_id IS NOT NULL OR v_ewt_base IS NOT NULL OR v_ewt_amt > 0 THEN
      PERFORM fn_require_company_ewt_payable_enabled(v_company_id, 'Cash purchase');
      PERFORM fn_validate_payment_voucher_line_ewt(
        v_company_id,
        ROUND(v_line_gross - v_ewt_amt, 2),
        v_ewt_amt,
        v_ewt_atc_id,
        v_ewt_base,
        v_ewt_reason,
        v_doc_date
      );
    END IF;

    IF v_ewt_amt > v_line_gross + 0.02 THEN
      RAISE EXCEPTION 'Cash purchase line EWT % exceeds gross line amount %.',
        v_ewt_amt, v_line_gross;
    END IF;
    v_line_cash := ROUND(v_line_gross - v_ewt_amt, 2);

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_gross_total := v_gross_total + v_line_gross;
    v_total_ewt   := v_total_ewt   + v_ewt_amt;
    v_cash_total  := v_cash_total  + v_line_cash;
    INSERT INTO cash_purchase_lines (
      cp_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, ewt_atc_code_id, ewt_tax_base, ewt_amount,
      ewt_income_nature, ewt_variance_reason, created_by, updated_by
    ) VALUES (
      v_cp_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_line_cash,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      v_ewt_atc_id, v_ewt_base, v_ewt_amt, v_ewt_nature, v_ewt_reason,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  IF v_total_ewt > 0 AND v_supplier_id IS NULL THEN
    RAISE EXCEPTION 'Supplier is required when cash purchase EWT is recorded.';
  END IF;

  UPDATE cash_purchases SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_input_vat_amount = v_total_vat,
    total_ewt_amount = v_total_ewt, total_amount = v_cash_total, updated_at = NOW()
  WHERE id = v_cp_id;

  PERFORM fn_validate_cash_purchase_ewt_ready(v_cp_id);
  RETURN v_cp_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_cash_purchase_source_locked_impl(p_cp_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cfg       company_accounting_config%ROWTYPE;
  v_cash_acct UUID;
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

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = v_rec.company_id;
  v_cash_acct := COALESCE(v_rec.payment_account_id, CASE WHEN FOUND THEN v_cfg.default_cash_account_id ELSE NULL END);
  IF v_cash_acct IS NULL THEN
    RAISE EXCEPTION 'Payment account not set. Add it on the form or configure a default cash account.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND (NOT FOUND OR v_cfg.input_vat_account_id IS NULL) THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it in GL Posting Configuration.';
  END IF;

  v_total_ewt := COALESCE(v_rec.total_ewt_amount, 0);
  IF v_total_ewt > 0 AND (NOT FOUND OR v_cfg.ewt_payable_account_id IS NULL) THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it in GL Posting Configuration.';
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
      v_je_id, v_line_no, v_cfg.input_vat_account_id,
      'Input VAT - ' || v_rec.cp_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  IF v_total_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ewt_payable_account_id,
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
$$;

GRANT EXECUTE ON FUNCTION fn_validate_cash_purchase_ewt_ready(UUID) TO authenticated, service_role;
