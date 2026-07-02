-- Enforce vendor credit application dates server-side and route inserts through
-- fn_apply_vendor_credit so the stored applied_date cannot bypass accounting checks.

CREATE OR REPLACE FUNCTION fn_apply_vendor_credit(
  p_credit_id UUID,
  p_bill_id   UUID,
  p_amount    NUMERIC,
  p_date      DATE    DEFAULT CURRENT_DATE,
  p_remarks   TEXT    DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vc               vendor_credits%ROWTYPE;
  v_bill             vendor_bills%ROWTYPE;
  v_bill_paid        NUMERIC(15,2);
  v_bill_applied     NUMERIC(15,2);
  v_bill_outstanding NUMERIC(15,2);
  v_new_balance      NUMERIC(15,2);
  v_app_id           UUID;
  v_period_id        UUID;
BEGIN
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'Application date is required';
  END IF;

  SELECT * INTO v_vc FROM vendor_credits WHERE id = p_credit_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor credit not found'; END IF;
  IF NOT is_company_member(v_vc.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_vc.status != 'open' THEN
    RAISE EXCEPTION 'Vendor credit must be in open status to apply (current: %)', v_vc.status;
  END IF;

  SELECT * INTO v_bill FROM vendor_bills WHERE id = p_bill_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor bill not found'; END IF;
  IF v_bill.company_id != v_vc.company_id THEN
    RAISE EXCEPTION 'Credit and bill must belong to the same company';
  END IF;
  IF v_bill.supplier_id != v_vc.supplier_id THEN
    RAISE EXCEPTION 'Credit and bill must be for the same supplier';
  END IF;
  IF v_bill.status != 'posted' THEN
    RAISE EXCEPTION 'Vendor bill must be posted to apply credits (current: %)', v_bill.status;
  END IF;
  IF p_date < v_vc.credit_date THEN
    RAISE EXCEPTION 'Application date % cannot be before vendor credit date %', p_date, v_vc.credit_date;
  END IF;
  IF p_date < v_bill.bill_date THEN
    RAISE EXCEPTION 'Application date % cannot be before vendor bill date %', p_date, v_bill.bill_date;
  END IF;

  SELECT id INTO v_period_id
  FROM fiscal_periods
  WHERE company_id = v_vc.company_id
    AND start_date <= p_date
    AND end_date >= p_date
    AND is_locked = false
  LIMIT 1;
  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for application date %. Create or unlock a fiscal period first.', p_date;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Application amount must be greater than zero';
  END IF;
  IF p_amount > v_vc.remaining_balance THEN
    RAISE EXCEPTION 'Amount (%) exceeds vendor credit remaining balance (%)', p_amount, v_vc.remaining_balance;
  END IF;

  SELECT COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
  INTO v_bill_paid
  FROM payment_voucher_lines pvl
  JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
  WHERE pvl.vendor_bill_id = p_bill_id AND pv.status = 'posted';

  SELECT COALESCE(SUM(applied_amount), 0)
  INTO v_bill_applied
  FROM vendor_credit_applications
  WHERE vendor_bill_id = p_bill_id;

  v_bill_outstanding := v_bill.total_amount - v_bill_paid - v_bill_applied;

  IF v_bill_outstanding <= 0 THEN
    RAISE EXCEPTION 'Vendor bill has no outstanding balance';
  END IF;
  IF p_amount > v_bill_outstanding THEN
    RAISE EXCEPTION 'Amount (%) exceeds bill outstanding balance (%)', p_amount, v_bill_outstanding;
  END IF;

  INSERT INTO vendor_credit_applications (
    company_id, vendor_credit_id, vendor_bill_id, applied_amount, applied_date, applied_by, remarks
  ) VALUES (
    v_vc.company_id, p_credit_id, p_bill_id, p_amount, p_date, auth.uid(), p_remarks
  ) RETURNING id INTO v_app_id;

  v_new_balance := v_vc.remaining_balance - p_amount;
  UPDATE vendor_credits SET
    remaining_balance = v_new_balance,
    status = CASE WHEN v_new_balance = 0 THEN 'applied' ELSE status END,
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_credit_id;

  RETURN v_app_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_apply_vendor_credit(UUID, UUID, NUMERIC, DATE, TEXT) TO authenticated;

DROP POLICY IF EXISTS "vca_insert" ON vendor_credit_applications;
DROP POLICY IF EXISTS "vca_insert_no_direct" ON vendor_credit_applications;
CREATE POLICY "vca_insert_no_direct"
ON vendor_credit_applications
FOR INSERT
TO authenticated
WITH CHECK (false);
