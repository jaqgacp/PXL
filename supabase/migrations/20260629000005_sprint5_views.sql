-- ============================================================
-- Sprint 5: Reporting Views
-- S5.6 Customer Ledger | S5.7 Output VAT | S5.8 SI Register
-- ============================================================

-- ── Customer Ledger (UNION of posted AR transactions) ─────────
CREATE OR REPLACE VIEW vw_customer_ledger AS
SELECT
  si.company_id, si.customer_id, si.date AS transaction_date,
  'SI'::TEXT AS doc_type, si.si_number AS doc_number,
  COALESCE(si.memo, 'Sales Invoice') AS description,
  si.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  si.created_at
FROM sales_invoices si
WHERE si.status = 'posted'

UNION ALL

SELECT
  r.company_id, r.customer_id, r.receipt_date AS transaction_date,
  'OR'::TEXT AS doc_type, r.receipt_number AS doc_number,
  COALESCE(r.remarks, 'Official Receipt') AS description,
  0::NUMERIC AS debit_amount, r.total_amount AS credit_amount,
  r.created_at
FROM receipts r
WHERE r.status = 'posted'

UNION ALL

SELECT
  cm.company_id, cm.customer_id, cm.cm_date AS transaction_date,
  'CM'::TEXT AS doc_type, cm.cm_number AS doc_number,
  COALESCE(cm.remarks, 'Credit Memo') AS description,
  0::NUMERIC AS debit_amount, cm.total_amount AS credit_amount,
  cm.created_at
FROM credit_memos cm
WHERE cm.status IN ('approved', 'applied')

UNION ALL

SELECT
  dm.company_id, dm.customer_id, dm.dm_date AS transaction_date,
  'DM'::TEXT AS doc_type, dm.dm_number AS doc_number,
  COALESCE(dm.remarks, 'Debit Memo') AS description,
  dm.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  dm.created_at
FROM debit_memos dm
WHERE dm.status IN ('approved', 'paid');

-- ── Sales Invoice Register ────────────────────────────────────
CREATE OR REPLACE VIEW vw_sales_invoice_register AS
SELECT
  si.company_id, si.branch_id, si.date,
  si.si_number, si.customer_name_snapshot, si.customer_tin_snapshot,
  si.total_taxable_amount, si.total_zero_rated_amount, si.total_exempt_amount,
  si.total_vat_amount, si.total_amount, si.status,
  si.void_reason_id, si.memo, si.reference,
  si.id AS invoice_id
FROM sales_invoices si;

-- ── Receipt Register ──────────────────────────────────────────
CREATE OR REPLACE VIEW vw_receipt_register AS
SELECT
  r.company_id, r.branch_id, r.receipt_date,
  r.receipt_number, r.customer_name_snapshot, r.customer_tin_snapshot,
  r.total_amount, r.total_cwt, r.remarks, r.status,
  r.reference_number, r.id AS receipt_id
FROM receipts r;

-- ── Credit Memo Register ──────────────────────────────────────
CREATE OR REPLACE VIEW vw_credit_memo_register AS
SELECT
  cm.company_id, cm.branch_id, cm.cm_date,
  cm.cm_number, cm.customer_name_snapshot, cm.customer_tin_snapshot,
  cm.total_net_amount, cm.total_vat_amount, cm.total_amount,
  cm.remarks, cm.status, cm.id AS cm_id,
  rc.description AS reason_description
FROM credit_memos cm
LEFT JOIN ref_reason_codes rc ON rc.id = cm.reason_code_id;

-- ── Debit Memo Register ───────────────────────────────────────
CREATE OR REPLACE VIEW vw_debit_memo_register AS
SELECT
  dm.company_id, dm.branch_id, dm.dm_date,
  dm.dm_number, dm.customer_name_snapshot, dm.customer_tin_snapshot,
  dm.total_net_amount, dm.total_vat_amount, dm.total_amount,
  dm.remarks, dm.status, dm.id AS dm_id,
  rc.description AS reason_description
FROM debit_memos dm
LEFT JOIN ref_reason_codes rc ON rc.id = dm.reason_code_id;
