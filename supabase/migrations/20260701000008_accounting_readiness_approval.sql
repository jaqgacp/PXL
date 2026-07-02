-- Enforce posting-account readiness before SI/VB approval or posting.
-- This keeps draft entry flexible but prevents approved documents that cannot post.

CREATE OR REPLACE FUNCTION fn_validate_sales_invoice_accounting_ready(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM sales_invoices WHERE id = p_invoice_id;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Sales invoice not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Sales invoice must have at least one line before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND revenue_account_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice line must have a revenue account before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    LEFT JOIN chart_of_accounts coa
      ON coa.id = sil.revenue_account_id
     AND coa.company_id = v_company_id
     AND coa.is_active = true
     AND coa.is_postable = true
    WHERE sil.sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(sil.description), '') IS NOT NULL
      AND coa.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice revenue account must be active, postable, and belong to the invoice company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND vat_code_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice line must have a VAT code before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    LEFT JOIN vat_codes vc
      ON vc.id = sil.vat_code_id
     AND vc.is_active = true
     AND vc.transaction_type = 'output_vat'
    WHERE sil.sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(sil.description), '') IS NOT NULL
      AND vc.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice VAT code must be active and valid for output VAT.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_vendor_bill_accounting_ready(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM vendor_bills WHERE id = p_bill_id;
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
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_si_accounting_ready_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('approved', 'posted')
     AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
    PERFORM fn_validate_sales_invoice_accounting_ready(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_vb_accounting_ready_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('approved', 'posted')
     AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
    PERFORM fn_validate_vendor_bill_accounting_ready(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sales_invoice_accounting_ready_status ON sales_invoices;
CREATE TRIGGER trg_sales_invoice_accounting_ready_status
  BEFORE INSERT OR UPDATE OF status ON sales_invoices
  FOR EACH ROW
  EXECUTE FUNCTION fn_require_si_accounting_ready_status();

DROP TRIGGER IF EXISTS trg_vendor_bill_accounting_ready_status ON vendor_bills;
CREATE TRIGGER trg_vendor_bill_accounting_ready_status
  BEFORE INSERT OR UPDATE OF status ON vendor_bills
  FOR EACH ROW
  EXECUTE FUNCTION fn_require_vb_accounting_ready_status();

CREATE OR REPLACE FUNCTION fn_approve_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft invoices can be approved (current status: %)', v_rec.status;
  END IF;

  PERFORM fn_validate_sales_invoice_accounting_ready(p_invoice_id);

  UPDATE sales_invoices
  SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_approve_vendor_bill(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec vendor_bills%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft bills can be approved (current: %)', v_rec.status;
  END IF;

  PERFORM fn_validate_vendor_bill_accounting_ready(p_bill_id);

  UPDATE vendor_bills
  SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_bill_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_validate_sales_invoice_accounting_ready(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_validate_vendor_bill_accounting_ready(UUID) TO authenticated;
