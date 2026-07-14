-- PXL-DA-013: as-of customer/supplier ledgers and period-end subledger-to-GL
-- reconciliation reports.
--
-- The current ledger views remain useful for simple browsing, but they do not
-- accept a cutoff date and they predate advance-payment/source-EWT settlement
-- rules. These RPCs provide report-safe as-of ledgers that match the posting
-- engine's AR/AP control-account movements.

CREATE OR REPLACE FUNCTION fn_customer_ledger_asof(
  p_company_id  UUID,
  p_as_of       DATE,
  p_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  company_id       UUID,
  customer_id      UUID,
  customer_name    TEXT,
  transaction_date DATE,
  document_type    TEXT,
  document_id      UUID,
  document_number  TEXT,
  description      TEXT,
  debit_amount     NUMERIC(15,2),
  credit_amount    NUMERIC(15,2),
  running_balance  NUMERIC(15,2),
  source_doc_type  TEXT,
  source_doc_id    UUID,
  created_at       TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH ledger AS (
    SELECT
      si.company_id,
      si.customer_id,
      si.customer_name_snapshot AS customer_name,
      si.date AS transaction_date,
      'SI'::TEXT AS document_type,
      si.id AS document_id,
      si.si_number AS document_number,
      COALESCE(si.memo, 'Sales Invoice') AS description,
      si.total_amount::NUMERIC(15,2) AS debit_amount,
      0::NUMERIC(15,2) AS credit_amount,
      'SI'::TEXT AS source_doc_type,
      si.id AS source_doc_id,
      si.created_at
    FROM sales_invoices si
    WHERE si.company_id = p_company_id
      AND si.status = 'posted'
      AND si.date <= p_as_of
      AND (p_customer_id IS NULL OR si.customer_id = p_customer_id)

    UNION ALL

    SELECT
      r.company_id,
      r.customer_id,
      r.customer_name_snapshot,
      r.receipt_date,
      'OR'::TEXT,
      r.id,
      r.receipt_number,
      COALESCE(r.remarks, 'Official Receipt'),
      0::NUMERIC(15,2),
      SUM(rl.payment_amount + rl.cwt_amount)::NUMERIC(15,2),
      'OR'::TEXT,
      r.id,
      r.created_at
    FROM receipts r
    JOIN receipt_lines rl ON rl.receipt_id = r.id
    WHERE r.company_id = p_company_id
      AND r.status = 'posted'
      AND r.receipt_date <= p_as_of
      AND rl.line_type = 'invoice_application'
      AND (p_customer_id IS NULL OR r.customer_id = p_customer_id)
    GROUP BY r.company_id, r.customer_id, r.customer_name_snapshot,
             r.receipt_date, r.id, r.receipt_number, r.remarks, r.created_at
    HAVING SUM(rl.payment_amount + rl.cwt_amount) > 0.005

    UNION ALL

    SELECT
      cm.company_id,
      cm.customer_id,
      cm.customer_name_snapshot,
      cm.cm_date,
      'CM'::TEXT,
      cm.id,
      cm.cm_number,
      COALESCE(cm.remarks, 'Credit Memo'),
      0::NUMERIC(15,2),
      cm.total_amount::NUMERIC(15,2),
      'CM'::TEXT,
      cm.id,
      cm.created_at
    FROM credit_memos cm
    WHERE cm.company_id = p_company_id
      AND cm.status = 'applied'
      AND cm.cm_date <= p_as_of
      AND (p_customer_id IS NULL OR cm.customer_id = p_customer_id)

    UNION ALL

    SELECT
      dm.company_id,
      dm.customer_id,
      dm.customer_name_snapshot,
      dm.dm_date,
      'DM'::TEXT,
      dm.id,
      dm.dm_number,
      COALESCE(dm.remarks, 'Debit Memo'),
      dm.total_amount::NUMERIC(15,2),
      0::NUMERIC(15,2),
      'DM'::TEXT,
      dm.id,
      dm.created_at
    FROM debit_memos dm
    WHERE dm.company_id = p_company_id
      AND dm.status = 'paid'
      AND dm.dm_date <= p_as_of
      AND (p_customer_id IS NULL OR dm.customer_id = p_customer_id)
  )
  SELECT
    l.company_id,
    l.customer_id,
    l.customer_name,
    l.transaction_date,
    l.document_type,
    l.document_id,
    l.document_number,
    l.description,
    l.debit_amount,
    l.credit_amount,
    SUM(l.debit_amount - l.credit_amount) OVER (
      PARTITION BY l.customer_id
      ORDER BY l.transaction_date, l.created_at, l.source_doc_type, l.source_doc_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )::NUMERIC(15,2) AS running_balance,
    l.source_doc_type,
    l.source_doc_id,
    l.created_at
  FROM ledger l
  WHERE p_as_of IS NOT NULL
    AND is_company_member(p_company_id)
  ORDER BY l.customer_name, l.transaction_date, l.created_at,
           l.source_doc_type, l.document_number, l.source_doc_id;
$$;

CREATE OR REPLACE FUNCTION fn_supplier_ledger_asof(
  p_company_id  UUID,
  p_as_of       DATE,
  p_supplier_id UUID DEFAULT NULL
)
RETURNS TABLE (
  company_id       UUID,
  supplier_id      UUID,
  supplier_name    TEXT,
  transaction_date DATE,
  document_type    TEXT,
  document_id      UUID,
  document_number  TEXT,
  external_ref     TEXT,
  description      TEXT,
  debit_amount     NUMERIC(15,2),
  credit_amount    NUMERIC(15,2),
  running_balance  NUMERIC(15,2),
  source_doc_type  TEXT,
  source_doc_id    UUID,
  created_at       TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH ledger AS (
    SELECT
      vb.company_id,
      vb.supplier_id,
      vb.supplier_name_snapshot AS supplier_name,
      vb.bill_date AS transaction_date,
      'VB'::TEXT AS document_type,
      vb.id AS document_id,
      vb.bill_number AS document_number,
      vb.supplier_invoice_number AS external_ref,
      COALESCE(vb.memo, 'Vendor Bill') AS description,
      0::NUMERIC(15,2) AS debit_amount,
      (vb.total_amount - fn_vendor_bill_accrued_ewt_amount(vb.id))::NUMERIC(15,2) AS credit_amount,
      'VB'::TEXT AS source_doc_type,
      vb.id AS source_doc_id,
      vb.created_at
    FROM vendor_bills vb
    WHERE vb.company_id = p_company_id
      AND vb.status = 'posted'
      AND vb.bill_date <= p_as_of
      AND (p_supplier_id IS NULL OR vb.supplier_id = p_supplier_id)
      AND (vb.total_amount - fn_vendor_bill_accrued_ewt_amount(vb.id)) > 0.005

    UNION ALL

    SELECT
      pv.company_id,
      pv.supplier_id,
      pv.supplier_name_snapshot,
      pv.voucher_date,
      'PV'::TEXT,
      pv.id,
      pv.voucher_number,
      pv.reference_number,
      COALESCE(pv.remarks, 'Payment Voucher'),
      SUM(pvl.payment_amount + pvl.ewt_amount)::NUMERIC(15,2),
      0::NUMERIC(15,2),
      'PV'::TEXT,
      pv.id,
      pv.created_at
    FROM payment_vouchers pv
    JOIN payment_voucher_lines pvl ON pvl.payment_voucher_id = pv.id
    WHERE pv.company_id = p_company_id
      AND pv.status = 'posted'
      AND pv.voucher_date <= p_as_of
      AND pvl.line_type = 'bill_application'
      AND (p_supplier_id IS NULL OR pv.supplier_id = p_supplier_id)
    GROUP BY pv.company_id, pv.supplier_id, pv.supplier_name_snapshot,
             pv.voucher_date, pv.id, pv.voucher_number, pv.reference_number,
             pv.remarks, pv.created_at
    HAVING SUM(pvl.payment_amount + pvl.ewt_amount) > 0.005

    UNION ALL

    SELECT
      vc.company_id,
      vc.supplier_id,
      vc.supplier_name_snapshot,
      vc.credit_date,
      'VC'::TEXT,
      vc.id,
      vc.vc_number,
      vc.supplier_cm_no,
      COALESCE(vc.remarks, 'Vendor Credit'),
      vc.total_amount::NUMERIC(15,2),
      0::NUMERIC(15,2),
      'VC'::TEXT,
      vc.id,
      vc.created_at
    FROM vendor_credits vc
    WHERE vc.company_id = p_company_id
      AND vc.status IN ('open', 'applied')
      AND vc.credit_date <= p_as_of
      AND (p_supplier_id IS NULL OR vc.supplier_id = p_supplier_id)
  )
  SELECT
    l.company_id,
    l.supplier_id,
    l.supplier_name,
    l.transaction_date,
    l.document_type,
    l.document_id,
    l.document_number,
    l.external_ref,
    l.description,
    l.debit_amount,
    l.credit_amount,
    SUM(l.credit_amount - l.debit_amount) OVER (
      PARTITION BY l.supplier_id
      ORDER BY l.transaction_date, l.created_at, l.source_doc_type, l.source_doc_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )::NUMERIC(15,2) AS running_balance,
    l.source_doc_type,
    l.source_doc_id,
    l.created_at
  FROM ledger l
  WHERE p_as_of IS NOT NULL
    AND is_company_member(p_company_id)
  ORDER BY l.supplier_name, l.transaction_date, l.created_at,
           l.source_doc_type, l.document_number, l.source_doc_id;
$$;

CREATE OR REPLACE FUNCTION fn_ar_subledger_gl_reconciliation_asof(
  p_company_id UUID,
  p_as_of      DATE
)
RETURNS TABLE (
  company_id            UUID,
  as_of_date            DATE,
  ledger_code           TEXT,
  control_account_id    UUID,
  control_account_code  TEXT,
  control_account_name  TEXT,
  subledger_balance     NUMERIC(15,2),
  gl_balance            NUMERIC(15,2),
  variance              NUMERIC(15,2),
  is_reconciled         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_cfg company_accounting_config%ROWTYPE;
  v_subledger NUMERIC(15,2);
  v_gl NUMERIC(15,2);
BEGIN
  IF p_as_of IS NULL THEN
    RAISE EXCEPTION 'As-of date is required';
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_cfg
  FROM company_accounting_config cac
  WHERE cac.company_id = p_company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT COALESCE(SUM(l.debit_amount - l.credit_amount), 0)::NUMERIC(15,2)
  INTO v_subledger
  FROM fn_customer_ledger_asof(p_company_id, p_as_of, NULL) l;

  SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)::NUMERIC(15,2)
  INTO v_gl
  FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id = jel.je_id
  WHERE jel.company_id = p_company_id
    AND jel.account_id = v_cfg.ar_account_id
    AND je.status = 'posted'
    AND je.je_date <= p_as_of;

  RETURN QUERY
  SELECT
    p_company_id,
    p_as_of,
    'AR'::TEXT,
    v_cfg.ar_account_id,
    coa.account_code,
    coa.account_name,
    v_subledger,
    v_gl,
    (v_subledger - v_gl)::NUMERIC(15,2),
    ABS(v_subledger - v_gl) <= 0.01
  FROM chart_of_accounts coa
  WHERE coa.id = v_cfg.ar_account_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_ap_subledger_gl_reconciliation_asof(
  p_company_id UUID,
  p_as_of      DATE
)
RETURNS TABLE (
  company_id            UUID,
  as_of_date            DATE,
  ledger_code           TEXT,
  control_account_id    UUID,
  control_account_code  TEXT,
  control_account_name  TEXT,
  subledger_balance     NUMERIC(15,2),
  gl_balance            NUMERIC(15,2),
  variance              NUMERIC(15,2),
  is_reconciled         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_cfg company_accounting_config%ROWTYPE;
  v_subledger NUMERIC(15,2);
  v_gl NUMERIC(15,2);
BEGIN
  IF p_as_of IS NULL THEN
    RAISE EXCEPTION 'As-of date is required';
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_cfg
  FROM company_accounting_config cac
  WHERE cac.company_id = p_company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;

  SELECT COALESCE(SUM(l.credit_amount - l.debit_amount), 0)::NUMERIC(15,2)
  INTO v_subledger
  FROM fn_supplier_ledger_asof(p_company_id, p_as_of, NULL) l;

  SELECT COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)::NUMERIC(15,2)
  INTO v_gl
  FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id = jel.je_id
  WHERE jel.company_id = p_company_id
    AND jel.account_id = v_cfg.ap_account_id
    AND je.status = 'posted'
    AND je.je_date <= p_as_of;

  RETURN QUERY
  SELECT
    p_company_id,
    p_as_of,
    'AP'::TEXT,
    v_cfg.ap_account_id,
    coa.account_code,
    coa.account_name,
    v_subledger,
    v_gl,
    (v_subledger - v_gl)::NUMERIC(15,2),
    ABS(v_subledger - v_gl) <= 0.01
  FROM chart_of_accounts coa
  WHERE coa.id = v_cfg.ap_account_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION fn_customer_ledger_asof(UUID, DATE, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_supplier_ledger_asof(UUID, DATE, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_ar_subledger_gl_reconciliation_asof(UUID, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_ap_subledger_gl_reconciliation_asof(UUID, DATE) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_customer_ledger_asof(UUID, DATE, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_supplier_ledger_asof(UUID, DATE, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_ar_subledger_gl_reconciliation_asof(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_ap_subledger_gl_reconciliation_asof(UUID, DATE) TO authenticated, service_role;
