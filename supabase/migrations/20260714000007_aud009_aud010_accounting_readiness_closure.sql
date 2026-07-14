-- PXL-AUD-009 / PXL-AUD-010: close SI/VB posting readiness with seeded
-- approval/posting validation evidence, and require supplier identity snapshots
-- before AP-side EWT can reach tax-detail posting.

CREATE OR REPLACE FUNCTION fn_default_ap_supplier_tin_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.supplier_tin_snapshot := COALESCE(
    NULLIF(BTRIM(COALESCE(NEW.supplier_tin_snapshot, '')), ''),
    (
      SELECT NULLIF(BTRIM(COALESCE(s.tin, '')), '')
      FROM suppliers s
      WHERE s.id = NEW.supplier_id
        AND s.company_id = NEW.company_id
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_default_vendor_bill_supplier_tin_snapshot ON vendor_bills;
CREATE TRIGGER trg_default_vendor_bill_supplier_tin_snapshot
  BEFORE INSERT OR UPDATE OF company_id, supplier_id, supplier_tin_snapshot ON vendor_bills
  FOR EACH ROW
  EXECUTE FUNCTION fn_default_ap_supplier_tin_snapshot();

DROP TRIGGER IF EXISTS trg_default_payment_voucher_supplier_tin_snapshot ON payment_vouchers;
CREATE TRIGGER trg_default_payment_voucher_supplier_tin_snapshot
  BEFORE INSERT OR UPDATE OF company_id, supplier_id, supplier_tin_snapshot ON payment_vouchers
  FOR EACH ROW
  EXECUTE FUNCTION fn_default_ap_supplier_tin_snapshot();

CREATE OR REPLACE FUNCTION fn_validate_vendor_bill_accounting_ready(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_supplier_tin TEXT;
BEGIN
  SELECT company_id, supplier_tin_snapshot
  INTO v_company_id, v_supplier_tin
  FROM vendor_bills
  WHERE id = p_bill_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Vendor bill must have at least one line before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND expense_account_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill line must have an expense account before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines vbl
    LEFT JOIN chart_of_accounts coa
      ON coa.id = vbl.expense_account_id
     AND coa.company_id = v_company_id
     AND coa.is_active = true
     AND coa.is_postable = true
    WHERE vbl.vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(vbl.description), '') IS NOT NULL
      AND coa.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill expense account must be active, postable, and belong to the bill company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND vat_code_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill line must have a VAT code before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_bill_lines vbl
    LEFT JOIN vat_codes vc
      ON vc.id = vbl.vat_code_id
     AND vc.is_active = true
     AND vc.transaction_type = 'input_vat'
    WHERE vbl.vendor_bill_id = p_bill_id
      AND NULLIF(TRIM(vbl.description), '') IS NOT NULL
      AND vc.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every vendor bill VAT code must be active and valid for input VAT.';
  END IF;

  IF NULLIF(BTRIM(COALESCE(v_supplier_tin, '')), '') IS NULL
     AND EXISTS (
       SELECT 1
       FROM vendor_bill_lines vbl
       WHERE vbl.vendor_bill_id = p_bill_id
         AND (
           COALESCE(vbl.ewt_amount, 0) > 0
           OR vbl.ewt_atc_code_id IS NOT NULL
           OR vbl.ewt_tax_base IS NOT NULL
         )
     ) THEN
    RAISE EXCEPTION 'Supplier TIN is required when vendor bill has EWT withholding.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_ewt_ready(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line          RECORD;
  v_company_id    UUID;
  v_supplier_tin  TEXT;
  v_header_ewt    NUMERIC(15,2);
  v_line_ewt      NUMERIC(15,2);
  v_header_cash   NUMERIC(15,2);
  v_line_cash     NUMERIC(15,2);
  v_document_date DATE;
BEGIN
  SELECT company_id, supplier_tin_snapshot, COALESCE(total_ewt, 0), COALESCE(total_amount, 0), voucher_date
  INTO v_company_id, v_supplier_tin, v_header_ewt, v_header_cash, v_document_date
  FROM payment_vouchers WHERE id = p_voucher_id;

  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found.';
  END IF;

  SELECT COALESCE(SUM(ewt_amount), 0), COALESCE(SUM(payment_amount), 0)
  INTO v_line_ewt, v_line_cash
  FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id;

  IF v_header_ewt > 0
     OR EXISTS (
       SELECT 1
       FROM payment_voucher_lines pvl
       WHERE pvl.payment_voucher_id = p_voucher_id
         AND (
           COALESCE(pvl.ewt_amount, 0) > 0
           OR pvl.atc_code_id IS NOT NULL
           OR pvl.ewt_tax_base IS NOT NULL
         )
     ) THEN
    IF NULLIF(BTRIM(COALESCE(v_supplier_tin, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Supplier TIN is required when payment voucher has EWT withholding.';
    END IF;

    PERFORM fn_require_company_ewt_payable_enabled(v_company_id, 'Payment voucher posting');
  END IF;

  IF ABS(v_header_ewt - v_line_ewt) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total EWT % does not match line EWT total %.', v_header_ewt, v_line_ewt;
  END IF;

  IF ABS(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total amount % does not match line payment total %.', v_header_cash, v_line_cash;
  END IF;

  FOR v_line IN
    SELECT company_id, vendor_bill_id, payment_amount, ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
    FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id
  LOOP
    IF v_line.vendor_bill_id IS NOT NULL
       AND fn_vendor_bill_has_accrued_ewt(v_line.vendor_bill_id)
       AND (
         COALESCE(v_line.ewt_amount, 0) > 0
         OR v_line.atc_code_id IS NOT NULL
         OR v_line.ewt_tax_base IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Vendor bill % already accrued EWT at source; do not withhold EWT again on the payment voucher.',
        v_line.vendor_bill_id;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.ewt_amount,
      v_line.atc_code_id,
      v_line.ewt_tax_base,
      v_line.ewt_variance_reason,
      v_document_date
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_validate_vendor_bill_accounting_ready(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_ewt_ready(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_default_ap_supplier_tin_snapshot() TO authenticated, service_role;
