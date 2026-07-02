-- ══════════════════════════════════════════════════════════════════════════════
-- AS-OF AR/AP AGING RPCS (PXL-AUD-011, PXL-AUD-012, PXL-AUD-019, PXL-DA-013)
--
-- Moves the as-of aging computation from client-side page code into the
-- database so reports, tests, and future callers share one implementation.
-- Semantics mirror the audited scoped fixes in ARAgingPage/APAgingPage:
--
-- AR: posted sales invoices dated <= as-of, reduced by receipt lines of posted
--     receipts with receipt_date <= as-of (payment + CWT) and by applied
--     credit memos with cm_date <= as-of. Rows with residual > 0.005 only.
-- AP: posted vendor bills dated <= as-of, reduced by payment voucher lines of
--     posted vouchers with voucher_date <= as-of (payment + EWT) and by
--     non-reversed vendor credit applications with applied_date <= as-of whose
--     vendor credit is open/applied. Rows with residual > 0.005 only.
--
-- days_overdue is signed (negative/zero = not yet due) so callers can bucket.
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_ar_aging_asof(
  p_company_id  UUID,
  p_as_of       DATE,
  p_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  invoice_id      UUID,
  si_number       TEXT,
  invoice_date    DATE,
  due_date        DATE,
  customer_id     UUID,
  customer_name   TEXT,
  original_amount NUMERIC(15,2),
  balance_due     NUMERIC(15,2),
  days_overdue    INT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    si.id,
    si.si_number,
    si.date,
    si.due_date,
    si.customer_id,
    si.customer_name_snapshot,
    si.total_amount,
    (si.total_amount - COALESCE(pay.applied, 0) - COALESCE(cm.applied, 0))::NUMERIC(15,2),
    COALESCE(p_as_of - si.due_date, 0)
  FROM sales_invoices si
  LEFT JOIN LATERAL (
    SELECT SUM(rl.payment_amount + rl.cwt_amount) AS applied
    FROM receipt_lines rl
    JOIN receipts r ON r.id = rl.receipt_id
    WHERE rl.invoice_id = si.id
      AND r.status = 'posted'
      AND r.receipt_date <= p_as_of
  ) pay ON true
  LEFT JOIN LATERAL (
    SELECT SUM(c.total_amount) AS applied
    FROM credit_memos c
    WHERE c.invoice_id = si.id
      AND c.status = 'applied'
      AND c.cm_date <= p_as_of
  ) cm ON true
  WHERE is_company_member(p_company_id)
    AND si.company_id = p_company_id
    AND si.status = 'posted'
    AND si.date <= p_as_of
    AND (p_customer_id IS NULL OR si.customer_id = p_customer_id)
    AND (si.total_amount - COALESCE(pay.applied, 0) - COALESCE(cm.applied, 0)) > 0.005
  ORDER BY si.customer_name_snapshot, si.date, si.si_number;
$$;

CREATE OR REPLACE FUNCTION fn_ap_aging_asof(
  p_company_id  UUID,
  p_as_of       DATE,
  p_supplier_id UUID DEFAULT NULL
)
RETURNS TABLE (
  bill_id         UUID,
  bill_number     TEXT,
  bill_date       DATE,
  due_date        DATE,
  supplier_id     UUID,
  supplier_name   TEXT,
  original_amount NUMERIC(15,2),
  balance_due     NUMERIC(15,2),
  days_overdue    INT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    vb.id,
    vb.bill_number,
    vb.bill_date,
    vb.due_date,
    vb.supplier_id,
    vb.supplier_name_snapshot,
    vb.total_amount,
    (vb.total_amount - COALESCE(pay.applied, 0) - COALESCE(vc.applied, 0))::NUMERIC(15,2),
    COALESCE(p_as_of - vb.due_date, 0)
  FROM vendor_bills vb
  LEFT JOIN LATERAL (
    SELECT SUM(pvl.payment_amount + pvl.ewt_amount) AS applied
    FROM payment_voucher_lines pvl
    JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.vendor_bill_id = vb.id
      AND pv.status = 'posted'
      AND pv.voucher_date <= p_as_of
  ) pay ON true
  LEFT JOIN LATERAL (
    SELECT SUM(vca.applied_amount) AS applied
    FROM vendor_credit_applications vca
    JOIN vendor_credits c ON c.id = vca.vendor_credit_id
    WHERE vca.vendor_bill_id = vb.id
      AND vca.reversed_at IS NULL
      AND vca.applied_date <= p_as_of
      AND c.status IN ('open', 'applied')
  ) vc ON true
  WHERE is_company_member(p_company_id)
    AND vb.company_id = p_company_id
    AND vb.status = 'posted'
    AND vb.bill_date <= p_as_of
    AND (p_supplier_id IS NULL OR vb.supplier_id = p_supplier_id)
    AND (vb.total_amount - COALESCE(pay.applied, 0) - COALESCE(vc.applied, 0)) > 0.005
  ORDER BY vb.supplier_name_snapshot, vb.bill_date, vb.bill_number;
$$;

REVOKE EXECUTE ON FUNCTION fn_ar_aging_asof(UUID, DATE, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_ar_aging_asof(UUID, DATE, UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION fn_ap_aging_asof(UUID, DATE, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_ap_aging_asof(UUID, DATE, UUID) TO authenticated;
