-- Block direct line mutation after core AR/AP documents leave draft.
-- Controlled reversals/voids should change document status or create reversal entries,
-- not rewrite source document lines after approval/posting/cancellation.

CREATE OR REPLACE FUNCTION fn_block_si_line_mutation_after_draft()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.sales_invoice_id;
  ELSE
    v_parent_id := NEW.sales_invoice_id;
  END IF;

  SELECT status INTO v_status
  FROM sales_invoices
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Sales invoice not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Sales invoice lines cannot be changed when the invoice status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION fn_block_receipt_line_mutation_after_draft()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.receipt_id;
  ELSE
    v_parent_id := NEW.receipt_id;
  END IF;

  SELECT status INTO v_status
  FROM receipts
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Receipt not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Receipt lines cannot be changed when the receipt status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION fn_block_vb_line_mutation_after_draft()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.vendor_bill_id;
  ELSE
    v_parent_id := NEW.vendor_bill_id;
  END IF;

  SELECT status INTO v_status
  FROM vendor_bills
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Vendor bill lines cannot be changed when the bill status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION fn_block_pv_line_mutation_after_draft()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.payment_voucher_id;
  ELSE
    v_parent_id := NEW.payment_voucher_id;
  END IF;

  SELECT status INTO v_status
  FROM payment_vouchers
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Payment voucher lines cannot be changed when the voucher status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_block_si_line_mutation_after_draft ON sales_invoice_lines;
CREATE TRIGGER trg_block_si_line_mutation_after_draft
  BEFORE INSERT OR UPDATE OR DELETE ON sales_invoice_lines
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_si_line_mutation_after_draft();

DROP TRIGGER IF EXISTS trg_block_receipt_line_mutation_after_draft ON receipt_lines;
CREATE TRIGGER trg_block_receipt_line_mutation_after_draft
  BEFORE INSERT OR UPDATE OR DELETE ON receipt_lines
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_receipt_line_mutation_after_draft();

DROP TRIGGER IF EXISTS trg_block_vb_line_mutation_after_draft ON vendor_bill_lines;
CREATE TRIGGER trg_block_vb_line_mutation_after_draft
  BEFORE INSERT OR UPDATE OR DELETE ON vendor_bill_lines
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_vb_line_mutation_after_draft();

DROP TRIGGER IF EXISTS trg_block_pv_line_mutation_after_draft ON payment_voucher_lines;
CREATE TRIGGER trg_block_pv_line_mutation_after_draft
  BEFORE INSERT OR UPDATE OR DELETE ON payment_voucher_lines
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_pv_line_mutation_after_draft();
