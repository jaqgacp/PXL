-- Rebase VAT review views on the immutable tax ledger.
--
-- PXL-AUD-014 residue after 20260703000002:
--   - tax_detail_entries is now complete for SI/VB/CS/CP VAT writers,
--   - these review views were still recomputing from document lines/header totals.
--
-- Legacy rows with vat_code_id IS NULL are treated as regular VAT rows. Reversal
-- rows are not filtered; they net naturally by source document and period.

DROP VIEW IF EXISTS vw_output_vat_review;
CREATE OR REPLACE VIEW vw_output_vat_review AS
SELECT
  tde.source_doc_id AS transaction_id,
  CASE
    WHEN tde.source_doc_type = 'SI' AND COALESCE(si.is_cash_sale, false) THEN 'cash_sale'
    WHEN tde.source_doc_type = 'SI' THEN 'sales_invoice'
    ELSE lower(tde.source_doc_type)
  END AS source_module,
  tde.company_id,
  tde.document_date AS invoice_date,
  tde.counterparty_tin AS customer_tin,
  tde.counterparty_name AS customer_name,
  COALESCE(si.si_number, tde.source_doc_id::text) AS system_no,
  COALESCE(SUM(tde.tax_base + tde.tax_amount), 0)::NUMERIC(15,2) AS gross_sales,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'exempt'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS exempt_sales,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'zero_rated'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS zero_rated_sales,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'regular'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS taxable_base,
  COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS output_vat
FROM tax_detail_entries tde
LEFT JOIN vat_codes vc ON vc.id = tde.vat_code_id
LEFT JOIN sales_invoices si
  ON tde.source_doc_type = 'SI'
 AND si.id = tde.source_doc_id
WHERE tde.tax_kind = 'output_vat'
GROUP BY
  tde.source_doc_id,
  tde.source_doc_type,
  COALESCE(si.is_cash_sale, false),
  tde.company_id,
  tde.document_date,
  tde.counterparty_tin,
  tde.counterparty_name,
  COALESCE(si.si_number, tde.source_doc_id::text);

DROP VIEW IF EXISTS vw_input_vat_review;
CREATE OR REPLACE VIEW vw_input_vat_review AS
SELECT
  tde.source_doc_id AS transaction_id,
  CASE tde.source_doc_type
    WHEN 'VB' THEN 'vendor_bill'
    WHEN 'CP' THEN 'cash_purchase'
    ELSE lower(tde.source_doc_type)
  END AS source_module,
  tde.company_id,
  tde.document_date AS invoice_date,
  tde.counterparty_tin AS supplier_tin,
  tde.counterparty_name AS supplier_name,
  COALESCE(s.registered_address, '') AS supplier_address,
  COALESCE(vb.supplier_invoice_number, cp.reference_number, '') AS invoice_no,
  COALESCE(vb.bill_number, cp.cp_number, tde.source_doc_id::text) AS system_no,
  COALESCE(SUM(tde.tax_base + tde.tax_amount), 0)::NUMERIC(15,2) AS gross_purchases,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'exempt'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'zero_rated'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS zero_rated,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'regular'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS taxable_base,
  COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS input_vat
FROM tax_detail_entries tde
LEFT JOIN vat_codes vc ON vc.id = tde.vat_code_id
LEFT JOIN vendor_bills vb
  ON tde.source_doc_type = 'VB'
 AND vb.id = tde.source_doc_id
LEFT JOIN cash_purchases cp
  ON tde.source_doc_type = 'CP'
 AND cp.id = tde.source_doc_id
LEFT JOIN suppliers s
  ON s.id = COALESCE(vb.supplier_id, cp.supplier_id, tde.counterparty_id)
WHERE tde.tax_kind = 'input_vat'
GROUP BY
  tde.source_doc_id,
  tde.source_doc_type,
  tde.company_id,
  tde.document_date,
  tde.counterparty_tin,
  tde.counterparty_name,
  COALESCE(s.registered_address, ''),
  COALESCE(vb.supplier_invoice_number, cp.reference_number, ''),
  COALESCE(vb.bill_number, cp.cp_number, tde.source_doc_id::text);
