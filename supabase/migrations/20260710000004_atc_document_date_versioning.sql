-- ATC document-date validation, effective-rate versioning, and ATC-level
-- withholding summaries (PXL-AUD-035 / PXL-AUD-036 / PXL-DA-009).

-- ---------------------------------------------------------------------------
-- 1. One official ATC code may have successive, non-overlapping versions.
-- ---------------------------------------------------------------------------

ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_atc_code_key;
ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_code_key;
DROP INDEX IF EXISTS atc_codes_atc_code_key;
DROP INDEX IF EXISTS atc_codes_code_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_atc_code_version_start
  ON atc_codes (code, tax_category, effective_from);

CREATE UNIQUE INDEX IF NOT EXISTS uq_atc_code_direct_successor
  ON atc_codes (supersedes_atc_code_id)
  WHERE supersedes_atc_code_id IS NOT NULL;

CREATE OR REPLACE FUNCTION fn_atc_code_used(p_atc_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM receipt_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM payment_voucher_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM check_vouchers WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM tax_detail_entries WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM form_2307_issuance_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM customers WHERE default_cwt_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM suppliers WHERE default_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM ewt_codes WHERE atc_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM fwt_codes WHERE atc_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM percentage_tax_codes WHERE atc_id = p_atc_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_atc_last_document_date(p_atc_id UUID)
RETURNS DATE
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT MAX(used_on)
  FROM (
    SELECT pv.voucher_date AS used_on
    FROM payment_voucher_lines pvl
    JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.atc_code_id = p_atc_id
    UNION ALL
    SELECT r.receipt_date
    FROM receipt_lines rl
    JOIN receipts r ON r.id = rl.receipt_id
    WHERE rl.atc_code_id = p_atc_id
    UNION ALL
    SELECT cv.voucher_date
    FROM check_vouchers cv
    WHERE cv.atc_code_id = p_atc_id
    UNION ALL
    SELECT tde.document_date
    FROM tax_detail_entries tde
    WHERE tde.atc_code_id = p_atc_id
  ) used_dates;
$$;

CREATE OR REPLACE FUNCTION fn_guard_atc_code_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF fn_atc_code_used(OLD.id) THEN
      RAISE EXCEPTION 'ATC code % is already used and cannot be deleted. End its effective window and create a successor version.', OLD.code;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND fn_atc_code_used(OLD.id) THEN
    IF NEW.code IS DISTINCT FROM OLD.code
       OR NEW.tax_category IS DISTINCT FROM OLD.tax_category
       OR NEW.rate IS DISTINCT FROM OLD.rate
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.supersedes_atc_code_id IS DISTINCT FROM OLD.supersedes_atc_code_id THEN
      RAISE EXCEPTION 'ATC code, category, rate, effective start, and predecessor are immutable after use. Create a successor version instead.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_enforce_atc_version_window()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_predecessor atc_codes%ROWTYPE;
  v_latest_predecessor UUID;
  v_last_document_date DATE;
  v_chain_changed BOOLEAN;
BEGIN
  NEW.code := UPPER(BTRIM(NEW.code));
  IF NEW.code IS NULL OR NEW.code = '' THEN
    RAISE EXCEPTION 'ATC code is required.';
  END IF;
  IF NEW.effective_to IS NOT NULL AND NEW.effective_to < NEW.effective_from THEN
    RAISE EXCEPTION 'ATC effective end cannot be before its effective start.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.tax_category || ':' || NEW.code, 0));

  IF TG_OP = 'UPDATE' THEN
    v_last_document_date := fn_atc_last_document_date(OLD.id);
    IF NEW.effective_to IS NOT NULL
       AND v_last_document_date IS NOT NULL
       AND NEW.effective_to < v_last_document_date THEN
      RAISE EXCEPTION 'ATC version % cannot end on % because it is selected by a document dated %.',
        OLD.code, NEW.effective_to, v_last_document_date;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_chain_changed := true;
  ELSE
    v_chain_changed := NEW.code IS DISTINCT FROM OLD.code
      OR NEW.tax_category IS DISTINCT FROM OLD.tax_category
      OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
      OR NEW.supersedes_atc_code_id IS DISTINCT FROM OLD.supersedes_atc_code_id;
  END IF;

  IF v_chain_changed THEN
    IF EXISTS (
      SELECT 1 FROM atc_codes a
      WHERE a.id <> NEW.id
        AND a.code = NEW.code
        AND a.tax_category = NEW.tax_category
    ) AND NEW.supersedes_atc_code_id IS NULL THEN
      RAISE EXCEPTION 'A new version of ATC % must identify the version it supersedes.', NEW.code;
    END IF;

    IF NEW.supersedes_atc_code_id IS NOT NULL THEN
      IF NEW.supersedes_atc_code_id = NEW.id THEN
        RAISE EXCEPTION 'An ATC version cannot supersede itself.';
      END IF;

      SELECT * INTO v_predecessor
      FROM atc_codes
      WHERE id = NEW.supersedes_atc_code_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Superseded ATC version was not found.';
      END IF;
      IF v_predecessor.code <> NEW.code
         OR v_predecessor.tax_category <> NEW.tax_category THEN
        RAISE EXCEPTION 'Successor ATC must keep the same official code and tax category as its predecessor.';
      END IF;
      IF v_predecessor.effective_from >= NEW.effective_from THEN
        RAISE EXCEPTION 'Successor ATC % must start after its predecessor.', NEW.code;
      END IF;

      SELECT a.id INTO v_latest_predecessor
      FROM atc_codes a
      WHERE a.id <> NEW.id
        AND a.code = NEW.code
        AND a.tax_category = NEW.tax_category
        AND a.effective_from < NEW.effective_from
      ORDER BY a.effective_from DESC
      LIMIT 1;

      IF v_latest_predecessor IS DISTINCT FROM NEW.supersedes_atc_code_id THEN
        RAISE EXCEPTION 'ATC % must supersede the immediately preceding effective version.', NEW.code;
      END IF;

      v_last_document_date := fn_atc_last_document_date(v_predecessor.id);
      IF v_last_document_date IS NOT NULL AND v_last_document_date >= NEW.effective_from THEN
        RAISE EXCEPTION 'ATC successor cannot start on % because predecessor % is selected by a document dated %.',
          NEW.effective_from, NEW.code, v_last_document_date;
      END IF;

      IF v_predecessor.effective_to IS NULL
         OR v_predecessor.effective_to >= NEW.effective_from THEN
        UPDATE atc_codes
        SET effective_to = NEW.effective_from - 1,
            updated_at = NOW(),
            updated_by = auth.uid()
        WHERE id = v_predecessor.id;
      END IF;
    END IF;
  END IF;

  IF COALESCE(NEW.is_active, false)
     AND NEW.deprecated_at IS NULL
     AND EXISTS (
       SELECT 1
       FROM atc_codes a
       WHERE a.id <> NEW.id
         AND a.code = NEW.code
         AND a.tax_category = NEW.tax_category
         AND COALESCE(a.is_active, false)
         AND a.deprecated_at IS NULL
         AND a.effective_from <= COALESCE(NEW.effective_to, DATE 'infinity')
         AND NEW.effective_from <= COALESCE(a.effective_to, DATE 'infinity')
     ) THEN
    RAISE EXCEPTION 'ATC % has an overlapping active effective window.', NEW.code;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_atc_version_window ON atc_codes;
CREATE TRIGGER trg_atc_version_window
  BEFORE INSERT OR UPDATE OF code, tax_category, effective_from, effective_to,
    is_active, deprecated_at, supersedes_atc_code_id
  ON atc_codes
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_atc_version_window();

GRANT EXECUTE ON FUNCTION fn_atc_last_document_date(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Date-aware transaction validators. Six-argument overloads remain for old
-- callers, but document writers and row triggers use the dated overloads.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_line_ewt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_ewt_amount NUMERIC,
  p_atc_code_id UUID,
  p_ewt_tax_base NUMERIC,
  p_ewt_variance_reason TEXT,
  p_document_date DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate NUMERIC(8,4);
  v_code TEXT;
  v_expected NUMERIC(15,2);
  v_base NUMERIC(15,2);
  v_reason TEXT;
  v_as_of DATE := COALESCE(p_document_date, CURRENT_DATE);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_ewt_amount, 0) < 0 OR COALESCE(p_ewt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, EWT, and EWT taxable base cannot be negative.';
  END IF;
  IF COALESCE(p_ewt_amount, 0) = 0 AND COALESCE(p_ewt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;
  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when EWT amount or taxable base is specified.';
  END IF;

  SELECT code, rate INTO v_code, v_rate
  FROM atc_codes
  WHERE id = p_atc_code_id
    AND is_active = true
    AND deprecated_at IS NULL
    AND tax_category = 'ewt'
    AND effective_from <= v_as_of
    AND (effective_to IS NULL OR effective_to >= v_as_of);

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on document date %.', v_as_of;
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive EWT rate.', v_code;
  END IF;

  v_base := ROUND(COALESCE(p_ewt_tax_base, p_payment_amount + p_ewt_amount, 0), 2);
  IF v_base <= 0 THEN
    RAISE EXCEPTION 'EWT taxable base is required when EWT is withheld.';
  END IF;
  v_expected := ROUND(v_base * v_rate / 100.0, 2);
  IF ABS(v_expected - COALESCE(p_ewt_amount, 0)) <= 0.02 THEN
    RETURN;
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_ewt_variance_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'EWT amount % does not match ATC % rate %%% on taxable base %. Expected EWT is %. Select a variance reason to proceed.',
      p_ewt_amount, v_code, v_rate, v_base, v_expected;
  END IF;
  IF v_reason NOT IN ('rounding', 'partial_non_taxable', 'bir_ruling', 'supplier_exempt', 'other_authorized') THEN
    RAISE EXCEPTION 'Invalid EWT variance reason: %', v_reason;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_line_ewt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_ewt_amount NUMERIC,
  p_atc_code_id UUID,
  p_ewt_tax_base NUMERIC DEFAULT NULL,
  p_ewt_variance_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_validate_payment_voucher_line_ewt(
    p_company_id, p_payment_amount, p_ewt_amount, p_atc_code_id,
    p_ewt_tax_base, p_ewt_variance_reason, CURRENT_DATE
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_receipt_line_cwt(
  p_company_id UUID,
  p_payment_amount NUMERIC,
  p_cwt_amount NUMERIC,
  p_atc_code_id UUID,
  p_cwt_tax_base NUMERIC,
  p_cwt_variance_reason TEXT,
  p_document_date DATE
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
  v_as_of DATE := COALESCE(p_document_date, CURRENT_DATE);
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
    AND effective_from <= v_as_of
    AND (effective_to IS NULL OR effective_to >= v_as_of);

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on document date %.', v_as_of;
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive withholding rate.', v_code;
  END IF;

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
BEGIN
  PERFORM fn_validate_receipt_line_cwt(
    p_company_id, p_payment_amount, p_cwt_amount, p_atc_code_id,
    p_cwt_tax_base, p_cwt_variance_reason, CURRENT_DATE
  );
END;
$$;

-- The save RPCs validate before their header rows exist, so they must pass the
-- payload's document date explicitly instead of falling back to CURRENT_DATE.
CREATE OR REPLACE FUNCTION fn_save_payment_voucher(
  p_voucher_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_voucher_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_voucher_number TEXT;
  v_current_status TEXT;
  v_document_date  DATE;
  v_line           JSONB;
  v_bill_id        UUID;
  v_pay_amt        NUMERIC(15,2);
  v_ewt_amt        NUMERIC(15,2);
  v_ewt_base       NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id := NULLIF(p_header->>'branch_id', '')::UUID;
  v_document_date := (p_header->>'voucher_date')::DATE;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM suppliers
    WHERE id = (p_header->>'supplier_id')::UUID
      AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_bill_id := NULLIF(v_line->>'vendor_bill_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_ewt_amt := COALESCE((v_line->>'ewt_amount')::NUMERIC, 0);
    v_ewt_base := NULLIF(v_line->>'ewt_tax_base', '')::NUMERIC;
    CONTINUE WHEN v_bill_id IS NULL OR (v_pay_amt + v_ewt_amt) <= 0;

    IF NOT EXISTS (
      SELECT 1 FROM vendor_bills
      WHERE id = v_bill_id AND company_id = v_company_id
    ) THEN
      RAISE EXCEPTION 'Vendor bill % does not belong to this company', v_bill_id;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_company_id,
      v_pay_amt,
      v_ewt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      v_ewt_base,
      NULLIF(v_line->>'ewt_variance_reason', ''),
      v_document_date
    );

    SELECT vb.total_amount - COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
    INTO v_outstanding
    FROM vendor_bills vb
    LEFT JOIN payment_voucher_lines pvl
      ON pvl.vendor_bill_id = vb.id
     AND pvl.payment_voucher_id <> COALESCE(
       p_voucher_id, '00000000-0000-0000-0000-000000000000'::UUID
     )
     AND pvl.payment_voucher_id IN (
       SELECT id FROM payment_vouchers WHERE status <> 'cancelled'
     )
    WHERE vb.id = v_bill_id
    GROUP BY vb.total_amount;

    IF (v_pay_amt + v_ewt_amt) > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % + EWT % exceeds outstanding AP balance of % for this bill',
        v_pay_amt, v_ewt_amt, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_voucher_id IS NULL THEN
    v_voucher_number := fn_next_document_number(v_company_id, v_branch_id, 'PV');
    INSERT INTO payment_vouchers (
      company_id, branch_id, supplier_id, supplier_name_snapshot,
      supplier_tin_snapshot, voucher_number, voucher_date, payment_mode_id,
      reference_number, bank_account_id, total_amount, total_ewt, remarks,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'supplier_id')::UUID, p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_voucher_number, v_document_date,
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
    FROM payment_vouchers
    WHERE id = p_voucher_id AND company_id = v_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Payment voucher not found or access denied';
    END IF;
    IF v_current_status <> 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % payment voucher', v_current_status;
    END IF;

    UPDATE payment_vouchers SET
      branch_id = v_branch_id,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      voucher_date = v_document_date,
      payment_mode_id = NULLIF(p_header->>'payment_mode_id', '')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_ewt = COALESCE((p_header->>'total_ewt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_voucher_id;
  END IF;

  DELETE FROM payment_voucher_lines WHERE payment_voucher_id = v_voucher_id;

  INSERT INTO payment_voucher_lines (
    payment_voucher_id, company_id, vendor_bill_id, payment_amount, ewt_amount,
    atc_code_id, ewt_tax_base, ewt_income_nature, ewt_variance_reason,
    created_by, updated_by
  )
  SELECT
    v_voucher_id, v_company_id,
    NULLIF(l->>'vendor_bill_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'ewt_amount')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    NULLIF(l->>'ewt_tax_base', '')::NUMERIC,
    NULLIF(l->>'ewt_income_nature', ''),
    NULLIF(l->>'ewt_variance_reason', ''),
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) > 0
     OR COALESCE((l->>'ewt_amount')::NUMERIC, 0) > 0;

  RETURN v_voucher_id;
END;
$$;

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
  v_document_date  DATE;
  v_line           JSONB;
  v_inv_id         UUID;
  v_pay_amt        NUMERIC(15,2);
  v_cwt_amt        NUMERIC(15,2);
  v_cwt_base       NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;
  v_document_date := (p_header->>'receipt_date')::DATE;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM customers
    WHERE id = (p_header->>'customer_id')::UUID
      AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_inv_id := NULLIF(v_line->>'invoice_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    v_cwt_amt := COALESCE((v_line->>'cwt_amount')::NUMERIC, 0);
    v_cwt_base := NULLIF(v_line->>'cwt_tax_base', '')::NUMERIC;
    CONTINUE WHEN v_inv_id IS NULL OR (v_pay_amt + v_cwt_amt) <= 0;

    IF NOT EXISTS (
      SELECT 1 FROM sales_invoices
      WHERE id = v_inv_id AND company_id = v_company_id
    ) THEN
      RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
    END IF;

    PERFORM fn_validate_receipt_line_cwt(
      v_company_id,
      v_pay_amt,
      v_cwt_amt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      v_cwt_base,
      NULLIF(v_line->>'cwt_variance_reason', ''),
      v_document_date
    );

    SELECT si.total_amount - COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
    INTO v_outstanding
    FROM sales_invoices si
    LEFT JOIN receipt_lines rl
      ON rl.invoice_id = si.id
     AND rl.receipt_id <> COALESCE(
       p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID
     )
     AND rl.receipt_id IN (
       SELECT id FROM receipts WHERE status <> 'bounced'
     )
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
      company_id, branch_id, customer_id, customer_name_snapshot,
      customer_tin_snapshot, receipt_number, receipt_date, payment_mode_id,
      reference_number, bank_account_id, total_amount, total_cwt, remarks,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number, v_document_date,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''),
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_receipt_id;
  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts
    WHERE id = p_receipt_id AND company_id = v_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Receipt not found or access denied';
    END IF;
    IF v_current_status <> 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date = v_document_date,
      payment_mode_id = (p_header->>'payment_mode_id')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(),
      updated_by = auth.uid()
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
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) <> 0
     OR COALESCE((l->>'cwt_amount')::NUMERIC, 0) <> 0;

  RETURN v_receipt_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_pvl_ewt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_document_date DATE;
BEGIN
  SELECT voucher_date INTO v_document_date
  FROM payment_vouchers
  WHERE id = NEW.payment_voucher_id;
  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found for EWT line validation.';
  END IF;

  PERFORM fn_validate_payment_voucher_line_ewt(
    NEW.company_id, NEW.payment_amount, NEW.ewt_amount, NEW.atc_code_id,
    NEW.ewt_tax_base, NEW.ewt_variance_reason, v_document_date
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_ewt_ready(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
  v_header_ewt NUMERIC(15,2);
  v_line_ewt NUMERIC(15,2);
  v_document_date DATE;
BEGIN
  SELECT COALESCE(total_ewt, 0), voucher_date
  INTO v_header_ewt, v_document_date
  FROM payment_vouchers
  WHERE id = p_voucher_id;
  IF v_header_ewt IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found.';
  END IF;

  SELECT COALESCE(SUM(ewt_amount), 0) INTO v_line_ewt
  FROM payment_voucher_lines
  WHERE payment_voucher_id = p_voucher_id;
  IF ABS(v_header_ewt - v_line_ewt) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total EWT % does not match line EWT total %.', v_header_ewt, v_line_ewt;
  END IF;

  FOR v_line IN
    SELECT company_id, payment_amount, ewt_amount, atc_code_id,
           ewt_tax_base, ewt_variance_reason
    FROM payment_voucher_lines
    WHERE payment_voucher_id = p_voucher_id
  LOOP
    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id, v_line.payment_amount, v_line.ewt_amount,
      v_line.atc_code_id, v_line.ewt_tax_base, v_line.ewt_variance_reason,
      v_document_date
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_receipt_line_cwt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_document_date DATE;
BEGIN
  SELECT receipt_date INTO v_document_date
  FROM receipts
  WHERE id = NEW.receipt_id;
  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Receipt not found for CWT line validation.';
  END IF;

  PERFORM fn_validate_receipt_line_cwt(
    NEW.company_id, NEW.payment_amount, NEW.cwt_amount, NEW.atc_code_id,
    NEW.cwt_tax_base, NEW.cwt_variance_reason, v_document_date
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_receipt_cwt_ready(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_header_cwt NUMERIC(15,2);
  v_line_cwt NUMERIC(15,2);
  v_document_date DATE;
  v_line RECORD;
BEGIN
  SELECT COALESCE(total_cwt, 0), receipt_date
  INTO v_header_cwt, v_document_date
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
    SELECT company_id, payment_amount, cwt_amount, atc_code_id,
           cwt_tax_base, cwt_variance_reason
    FROM receipt_lines
    WHERE receipt_id = p_receipt_id
  LOOP
    PERFORM fn_validate_receipt_line_cwt(
      v_line.company_id, v_line.payment_amount, v_line.cwt_amount,
      v_line.atc_code_id, v_line.cwt_tax_base, v_line.cwt_variance_reason,
      v_document_date
    );
  END LOOP;
END;
$$;

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
    NEW.ewt_variance_reason,
    NEW.voucher_date
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cv_ewt_validation ON check_vouchers;
CREATE TRIGGER trg_cv_ewt_validation
  BEFORE INSERT OR UPDATE OF company_id, supplier_id, voucher_date,
    total_gross_amount, total_ewt_amount, atc_code_id, ewt_tax_base,
    ewt_variance_reason
  ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_cv_ewt_validation();

-- Posting repeats validation after recomputing the gross from CV lines. Keep
-- that defense tied to the voucher date as well.
CREATE OR REPLACE FUNCTION fn_post_check_voucher(p_cv_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec      check_vouchers%ROWTYPE;
  v_cfg      company_accounting_config%ROWTYPE;
  v_supp     suppliers%ROWTYPE;
  v_bank_gl  UUID;
  v_gross    NUMERIC(15,2);
  v_net      NUMERIC(15,2);
  v_atc_rate NUMERIC(8,4);
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line     RECORD;
  v_no       INT := 1;
BEGIN
  SELECT * INTO v_rec FROM check_vouchers WHERE id = p_cv_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Check voucher not found';
  END IF;
  IF NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF v_rec.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft check vouchers can be posted (current: %)', v_rec.status;
  END IF;

  SELECT gl_account_id INTO v_bank_gl
  FROM bank_accounts
  WHERE id = v_rec.bank_account_id;
  IF v_bank_gl IS NULL THEN
    RAISE EXCEPTION 'Bank account has no GL account configured';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_gross
  FROM check_voucher_lines
  WHERE cv_id = v_rec.id;
  IF v_gross <= 0 THEN
    RAISE EXCEPTION 'Check voucher must have at least one expense line';
  END IF;

  IF v_rec.total_ewt_amount > 0 THEN
    IF v_rec.atc_code_id IS NULL THEN
      RAISE EXCEPTION 'An ATC code is required when EWT is withheld';
    END IF;
    IF v_rec.supplier_id IS NULL THEN
      RAISE EXCEPTION 'A supplier is required when EWT is withheld on a check voucher (Form 2307 traceability).';
    END IF;

    SELECT * INTO v_supp
    FROM suppliers
    WHERE id = v_rec.supplier_id AND company_id = v_rec.company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier does not belong to this company';
    END IF;

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
  IF v_net <= 0 THEN
    RAISE EXCEPTION 'Net check amount must be greater than zero';
  END IF;

  IF v_rec.total_ewt_amount > 0 THEN
    SELECT * INTO v_cfg
    FROM company_accounting_config
    WHERE company_id = v_rec.company_id;
    IF NOT FOUND OR v_cfg.ewt_payable_account_id IS NULL THEN
      RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
    END IF;
  END IF;

  SELECT id INTO v_fp_id
  FROM fiscal_periods
  WHERE company_id = v_rec.company_id
    AND start_date <= v_rec.voucher_date
    AND end_date >= v_rec.voucher_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for voucher date %', v_rec.voucher_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id, 'JE-CV-' || v_rec.cv_number,
    v_rec.voucher_date, v_fp_id,
    'Check Voucher ' || v_rec.cv_number || ' - ' || v_rec.payee,
    'CV', v_rec.id, 'posted', v_gross, v_gross, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT expense_account_id, SUM(amount) AS amt
    FROM check_voucher_lines
    WHERE cv_id = v_rec.id
    GROUP BY expense_account_id
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, v_rec.company_id, v_no, v_line.expense_account_id,
      v_rec.particulars, v_line.amt, 0, auth.uid(), auth.uid()
    );
    v_no := v_no + 1;
  END LOOP;

  INSERT INTO journal_entry_lines (
    je_id, company_id, line_number, account_id, description,
    debit_amount, credit_amount, created_by, updated_by
  ) VALUES (
    v_je_id, v_rec.company_id, v_no, v_bank_gl,
    'Check ' || v_rec.check_number || ' - ' || v_rec.payee,
    0, v_net, auth.uid(), auth.uid()
  );
  v_no := v_no + 1;

  IF v_rec.total_ewt_amount > 0 THEN
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      v_je_id, v_rec.company_id, v_no, v_cfg.ewt_payable_account_id,
      'EWT withheld - ' || v_rec.cv_number,
      0, v_rec.total_ewt_amount, auth.uid(), auth.uid()
    );

    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id, tax_kind,
      atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date, counterparty_id, counterparty_tin,
      counterparty_name
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CV', v_rec.id, 'ewt_payable',
      v_rec.atc_code_id, ROUND(COALESCE(v_rec.ewt_tax_base, v_gross), 2),
      v_atc_rate, v_rec.total_ewt_amount, v_fp_id, NOW()::DATE,
      v_rec.voucher_date, v_rec.supplier_id,
      COALESCE(NULLIF(BTRIM(v_supp.tin), ''), v_rec.payee_tin),
      COALESCE(NULLIF(BTRIM(v_supp.registered_name), ''), v_rec.payee)
    );
  END IF;

  UPDATE check_vouchers SET
    status = 'posted',
    journal_entry_id = v_je_id,
    fiscal_period_id = v_fp_id,
    total_gross_amount = v_gross,
    posted_at = NOW(),
    posted_by = auth.uid(),
    updated_by = auth.uid(),
    updated_at = NOW()
  WHERE id = v_rec.id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_line_ewt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_line_ewt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_receipt_line_cwt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_receipt_line_cwt(UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Snapshot summaries retain one row per taxpayer + official ATC code +
-- rate. Detail rows retain the selected version id and reconciliation semantics
-- remain unchanged.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_snapshot_wht_export(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_quarter INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report_type TEXT := upper(p_report_type);
  v_recon_kind TEXT;
  v_start DATE;
  v_end DATE;
  v_source_id UUID;
  v_snapshot_id UUID;
  v_snapshot_version INTEGER;
  v_report_payload JSONB;
  v_source_payload JSONB;
  v_source_hash TEXT;
  v_row_count INTEGER := 0;
  v_recon_failures TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF v_report_type NOT IN ('SAWT', 'QAP') THEN
    RAISE EXCEPTION 'Unsupported withholding export report type: %', p_report_type;
  END IF;
  IF p_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid withholding export quarter: %', p_quarter;
  END IF;

  v_recon_kind := CASE v_report_type WHEN 'QAP' THEN 'ewt_payable' ELSE 'cwt_receivable' END;
  v_start := make_date(p_year, (p_quarter - 1) * 3 + 1, 1);
  v_end := (v_start + INTERVAL '3 months' - INTERVAL '1 day')::DATE;

  SELECT string_agg(r.tax_kind || ' variance ' || r.variance::text, '; ' ORDER BY r.tax_kind)
  INTO v_recon_failures
  FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end) r
  WHERE r.tax_kind = v_recon_kind
    AND NOT r.is_reconciled;
  IF v_recon_failures IS NOT NULL THEN
    RAISE EXCEPTION '% export period % to % does not reconcile to GL account: %',
      v_report_type, v_start, v_end, v_recon_failures;
  END IF;

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' || p_year::text || ':Q' || p_quarter::text
  );
  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'wht_export_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'period_year', p_year,
    'period_quarter', p_quarter
  );

  IF v_report_type = 'QAP' THEN
    WITH detail_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.invoice_date, d.transaction_id, d.atc_code_id), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, invoice_date, supplier_id, supplier_tin, supplier_name,
               atc_code_id, atc_code, nature_of_payment, tax_rate, tax_base, tax_withheld
        FROM vw_ewt_summary_ap
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
      ) d
    ), summary_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.supplier_name, s.supplier_tin, s.atc_code, s.tax_rate), '[]'::jsonb) AS payload
      FROM (
        SELECT supplier_id,
               COALESCE(supplier_tin, '') AS supplier_tin,
               COALESCE(supplier_name, 'Unknown') AS supplier_name,
               COALESCE(atc_code, '') AS atc_code,
               tax_rate,
               SUM(tax_base)::NUMERIC(15,2) AS tax_base,
               SUM(tax_withheld)::NUMERIC(15,2) AS tax_withheld
        FROM vw_ewt_summary_ap
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
        GROUP BY supplier_id, COALESCE(supplier_tin, ''),
                 COALESCE(supplier_name, 'Unknown'), COALESCE(atc_code, ''),
                 tax_rate
      ) s
    ), recon_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
      FROM (
        SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
               gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
        FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end)
      ) r
    )
    SELECT jsonb_build_object(
             'report', v_report_payload,
             'payee_detail_rows', detail_rows.payload,
             'payee_summary_rows', summary_rows.payload,
             'wht_gl_reconciliation', recon_rows.payload
           ), detail_rows.row_count
    INTO v_source_payload, v_row_count
    FROM detail_rows, summary_rows, recon_rows;
  ELSE
    WITH detail_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.receipt_date, d.transaction_id, d.atc_code_id), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, source_doc_type, receipt_date, customer_id,
               customer_tin, customer_name, atc_code_id, atc_code,
               nature_of_income, tax_rate, income_payment, cwt_withheld
        FROM vw_cwt_summary_ar
        WHERE company_id = p_company_id
          AND receipt_date BETWEEN v_start AND v_end
      ) d
    ), summary_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.customer_name, s.customer_tin, s.atc_code, s.tax_rate), '[]'::jsonb) AS payload
      FROM (
        SELECT customer_id,
               COALESCE(customer_tin, '') AS customer_tin,
               COALESCE(customer_name, 'Unknown') AS customer_name,
               COALESCE(atc_code, '') AS atc_code,
               tax_rate,
               SUM(income_payment)::NUMERIC(15,2) AS income_payments,
               SUM(cwt_withheld)::NUMERIC(15,2) AS cwt_withheld
        FROM vw_cwt_summary_ar
        WHERE company_id = p_company_id
          AND receipt_date BETWEEN v_start AND v_end
        GROUP BY customer_id, COALESCE(customer_tin, ''),
                 COALESCE(customer_name, 'Unknown'), COALESCE(atc_code, ''),
                 tax_rate
      ) s
    ), recon_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
      FROM (
        SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
               gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
        FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end)
      ) r
    )
    SELECT jsonb_build_object(
             'report', v_report_payload,
             'payer_detail_rows', detail_rows.payload,
             'payer_summary_rows', summary_rows.payload,
             'wht_gl_reconciliation', recon_rows.payload
           ), detail_rows.row_count
    INTO v_source_payload, v_row_count
    FROM detail_rows, summary_rows, recon_rows;
  END IF;

  v_source_hash := encode(extensions.digest(convert_to(v_source_payload::text, 'UTF8'), 'sha256'), 'hex');
  v_snapshot_id := gen_random_uuid();
  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count,
    generated_by
  ) VALUES (
    v_snapshot_id, p_company_id, v_report_type, 'wht_export_periods', v_source_id,
    'exported', v_snapshot_version, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  );

  RETURN v_snapshot_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_wht_export(UUID, TEXT, INTEGER, INTEGER) TO authenticated;
