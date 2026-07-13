-- PXL-DA-019: books export reconciliation and CAS audit package snapshots.
--
-- Earlier books exports froze rows and exact CSV bytes, but only the general
-- journal carried an explicit reconciliation block. This slice adds a
-- reusable reconciliation payload for every BIR book export:
--   * exported row count/total matches the posted source rows,
--   * every exported source document has a linked posted journal entry,
--   * linked journal entries are debit=credit balanced.
-- It also adds a server-attested CAS audit package snapshot that gathers
-- numbering, void, export, artifact, audit-log, GL, and books-reconciliation
-- evidence for a date range and blocks if core package checks fail.

CREATE OR REPLACE FUNCTION fn_books_export_reconciliation(
  p_company_id UUID,
  p_book_type TEXT,
  p_date_from DATE,
  p_date_to DATE,
  p_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key TEXT := lower(p_book_type);
  v_rows JSONB := COALESCE(p_rows, '[]'::jsonb);
  v_export_count INTEGER := 0;
  v_export_total NUMERIC(15,2) := 0;
  v_export_debits NUMERIC(15,2) := 0;
  v_export_credits NUMERIC(15,2) := 0;
  v_source_count INTEGER := 0;
  v_source_total NUMERIC(15,2) := 0;
  v_missing_je_count INTEGER := 0;
  v_linked_je_count INTEGER := 0;
  v_gl_line_count INTEGER := 0;
  v_gl_debits NUMERIC(15,2) := 0;
  v_gl_credits NUMERIC(15,2) := 0;
  v_count_ok BOOLEAN;
  v_total_ok BOOLEAN;
  v_je_ok BOOLEAN;
  v_gl_ok BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF v_key NOT IN ('sales_journal', 'purchase_journal', 'cash_receipts',
                   'cash_disbursements', 'general_journal',
                   'cash_sales_journal', 'cash_purchases_journal') THEN
    RAISE EXCEPTION 'Unsupported books export type: %', p_book_type;
  END IF;

  IF jsonb_typeof(v_rows) <> 'array' THEN
    RAISE EXCEPTION 'Books export rows must be a JSON array';
  END IF;

  v_export_count := jsonb_array_length(v_rows);

  IF v_key = 'general_journal' THEN
    SELECT COALESCE(SUM(fn_export_dat_numeric(e.row ->> 'debit_amount')), 0)::NUMERIC(15,2),
           COALESCE(SUM(fn_export_dat_numeric(e.row ->> 'credit_amount')), 0)::NUMERIC(15,2)
    INTO v_export_debits, v_export_credits
    FROM jsonb_array_elements(v_rows) AS e(row);

    SELECT COUNT(*)::INTEGER,
           COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2),
           COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2)
    INTO v_gl_line_count, v_gl_debits, v_gl_credits
    FROM vw_general_ledger
    WHERE company_id = p_company_id
      AND je_date BETWEEN p_date_from AND p_date_to;

    v_count_ok := v_export_count = v_gl_line_count;
    v_total_ok := ABS(v_export_debits - v_gl_debits) <= 0.01
              AND ABS(v_export_credits - v_gl_credits) <= 0.01;
    v_gl_ok := ABS(v_gl_debits - v_gl_credits) <= 0.01;

    RETURN jsonb_build_array(jsonb_build_object(
      'check', 'books_gl_to_export',
      'book_type', v_key,
      'export_row_count', v_export_count,
      'gl_line_count', v_gl_line_count,
      'export_debits', v_export_debits,
      'export_credits', v_export_credits,
      'gl_debits', v_gl_debits,
      'gl_credits', v_gl_credits,
      'row_count_reconciled', v_count_ok,
      'amounts_reconciled', v_total_ok,
      'gl_balance_reconciled', v_gl_ok,
      'is_reconciled', v_count_ok AND v_total_ok AND v_gl_ok
    ));
  END IF;

  SELECT COALESCE(SUM(
           CASE WHEN v_key IN ('sales_journal', 'cash_sales_journal',
                               'purchase_journal', 'cash_purchases_journal')
                THEN fn_export_dat_numeric(e.row ->> 'total_amount')
                ELSE fn_export_dat_numeric(e.row ->> 'amount')
           END
         ), 0)::NUMERIC(15,2)
  INTO v_export_total
  FROM jsonb_array_elements(v_rows) AS e(row);

  IF v_key IN ('sales_journal', 'cash_sales_journal') THEN
    WITH source AS (
      SELECT si.id AS source_id, si.journal_entry_id,
             si.total_amount::NUMERIC(15,2) AS amount
      FROM sales_invoices si
      WHERE si.company_id = p_company_id
        AND si.status = 'posted'
        AND si.is_cash_sale = (v_key = 'cash_sales_journal')
        AND si.date BETWEEN p_date_from AND p_date_to
    )
    SELECT COUNT(*)::INTEGER,
           COALESCE(SUM(amount), 0)::NUMERIC(15,2),
           (COUNT(DISTINCT journal_entry_id) FILTER (WHERE journal_entry_id IS NOT NULL))::INTEGER,
           (COUNT(*) FILTER (WHERE journal_entry_id IS NULL))::INTEGER,
           COALESCE((SELECT COUNT(*) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::INTEGER,
           COALESCE((SELECT SUM(gl.debit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2),
           COALESCE((SELECT SUM(gl.credit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2)
    INTO v_source_count, v_source_total, v_linked_je_count, v_missing_je_count,
         v_gl_line_count, v_gl_debits, v_gl_credits
    FROM source;
  ELSIF v_key = 'purchase_journal' THEN
    WITH source AS (
      SELECT vb.id AS source_id, vb.journal_entry_id,
             vb.total_amount::NUMERIC(15,2) AS amount
      FROM vendor_bills vb
      WHERE vb.company_id = p_company_id
        AND vb.status = 'posted'
        AND vb.bill_date BETWEEN p_date_from AND p_date_to
    )
    SELECT COUNT(*)::INTEGER,
           COALESCE(SUM(amount), 0)::NUMERIC(15,2),
           (COUNT(DISTINCT journal_entry_id) FILTER (WHERE journal_entry_id IS NOT NULL))::INTEGER,
           (COUNT(*) FILTER (WHERE journal_entry_id IS NULL))::INTEGER,
           COALESCE((SELECT COUNT(*) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::INTEGER,
           COALESCE((SELECT SUM(gl.debit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2),
           COALESCE((SELECT SUM(gl.credit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2)
    INTO v_source_count, v_source_total, v_linked_je_count, v_missing_je_count,
         v_gl_line_count, v_gl_debits, v_gl_credits
    FROM source;
  ELSIF v_key = 'cash_purchases_journal' THEN
    WITH source AS (
      SELECT cp.id AS source_id, cp.journal_entry_id,
             cp.total_amount::NUMERIC(15,2) AS amount
      FROM cash_purchases cp
      WHERE cp.company_id = p_company_id
        AND cp.status = 'posted'
        AND cp.transaction_date BETWEEN p_date_from AND p_date_to
    )
    SELECT COUNT(*)::INTEGER,
           COALESCE(SUM(amount), 0)::NUMERIC(15,2),
           (COUNT(DISTINCT journal_entry_id) FILTER (WHERE journal_entry_id IS NOT NULL))::INTEGER,
           (COUNT(*) FILTER (WHERE journal_entry_id IS NULL))::INTEGER,
           COALESCE((SELECT COUNT(*) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::INTEGER,
           COALESCE((SELECT SUM(gl.debit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2),
           COALESCE((SELECT SUM(gl.credit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2)
    INTO v_source_count, v_source_total, v_linked_je_count, v_missing_je_count,
         v_gl_line_count, v_gl_debits, v_gl_credits
    FROM source;
  ELSIF v_key = 'cash_receipts' THEN
    WITH source AS (
      SELECT r.id AS source_id, r.journal_entry_id,
             (r.total_amount + COALESCE(r.total_cwt, 0))::NUMERIC(15,2) AS amount
      FROM receipts r
      WHERE r.company_id = p_company_id
        AND r.status = 'posted'
        AND r.receipt_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT si.id, si.journal_entry_id, si.total_amount::NUMERIC(15,2)
      FROM sales_invoices si
      WHERE si.company_id = p_company_id
        AND si.status = 'posted'
        AND si.is_cash_sale = true
        AND si.date BETWEEN p_date_from AND p_date_to
    )
    SELECT COUNT(*)::INTEGER,
           COALESCE(SUM(amount), 0)::NUMERIC(15,2),
           (COUNT(DISTINCT journal_entry_id) FILTER (WHERE journal_entry_id IS NOT NULL))::INTEGER,
           (COUNT(*) FILTER (WHERE journal_entry_id IS NULL))::INTEGER,
           COALESCE((SELECT COUNT(*) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::INTEGER,
           COALESCE((SELECT SUM(gl.debit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2),
           COALESCE((SELECT SUM(gl.credit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2)
    INTO v_source_count, v_source_total, v_linked_je_count, v_missing_je_count,
         v_gl_line_count, v_gl_debits, v_gl_credits
    FROM source;
  ELSE
    WITH source AS (
      SELECT pv.id AS source_id, pv.journal_entry_id,
             (pv.total_amount - COALESCE(pv.total_ewt, 0))::NUMERIC(15,2) AS amount
      FROM payment_vouchers pv
      WHERE pv.company_id = p_company_id
        AND pv.status = 'posted'
        AND pv.voucher_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT cv.id, cv.journal_entry_id, cv.net_check_amount::NUMERIC(15,2)
      FROM check_vouchers cv
      WHERE cv.company_id = p_company_id
        AND cv.status = 'posted'
        AND cv.voucher_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT cp.id, cp.journal_entry_id, cp.total_amount::NUMERIC(15,2)
      FROM cash_purchases cp
      WHERE cp.company_id = p_company_id
        AND cp.status = 'posted'
        AND cp.transaction_date BETWEEN p_date_from AND p_date_to
    )
    SELECT COUNT(*)::INTEGER,
           COALESCE(SUM(amount), 0)::NUMERIC(15,2),
           (COUNT(DISTINCT journal_entry_id) FILTER (WHERE journal_entry_id IS NOT NULL))::INTEGER,
           (COUNT(*) FILTER (WHERE journal_entry_id IS NULL))::INTEGER,
           COALESCE((SELECT COUNT(*) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::INTEGER,
           COALESCE((SELECT SUM(gl.debit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2),
           COALESCE((SELECT SUM(gl.credit_amount) FROM vw_general_ledger gl
                     WHERE gl.company_id = p_company_id
                       AND gl.je_id IN (SELECT journal_entry_id FROM source WHERE journal_entry_id IS NOT NULL)), 0)::NUMERIC(15,2)
    INTO v_source_count, v_source_total, v_linked_je_count, v_missing_je_count,
         v_gl_line_count, v_gl_debits, v_gl_credits
    FROM source;
  END IF;

  v_count_ok := v_export_count = v_source_count;
  v_total_ok := ABS(v_export_total - v_source_total) <= 0.01;
  v_je_ok := v_missing_je_count = 0 AND v_linked_je_count = v_source_count;
  v_gl_ok := ABS(v_gl_debits - v_gl_credits) <= 0.01;

  RETURN jsonb_build_array(
    jsonb_build_object(
      'check', 'books_source_to_export',
      'book_type', v_key,
      'export_row_count', v_export_count,
      'source_row_count', v_source_count,
      'export_total', v_export_total,
      'source_total', v_source_total,
      'linked_journal_entries', v_linked_je_count,
      'missing_journal_entries', v_missing_je_count,
      'row_count_reconciled', v_count_ok,
      'amounts_reconciled', v_total_ok,
      'journal_entry_coverage_reconciled', v_je_ok,
      'is_reconciled', v_count_ok AND v_total_ok AND v_je_ok
    ),
    jsonb_build_object(
      'check', 'books_linked_gl_balance',
      'book_type', v_key,
      'linked_gl_line_count', v_gl_line_count,
      'linked_gl_debits', v_gl_debits,
      'linked_gl_credits', v_gl_credits,
      'is_reconciled', v_gl_ok
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_books_export(
  p_company_id UUID,
  p_book_type TEXT,
  p_date_from DATE,
  p_date_to DATE,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key TEXT := lower(p_book_type);
  v_report_type TEXT;
  v_report_name TEXT;
  v_source_id UUID;
  v_snapshot_id UUID;
  v_snapshot_version INTEGER;
  v_rows JSONB;
  v_row_count INTEGER := 0;
  v_total NUMERIC(15,2) := 0;
  v_report_payload JSONB;
  v_source_payload JSONB;
  v_source_hash TEXT;
  v_export_text TEXT;
  v_export_sha256 TEXT;
  v_export_size INTEGER;
  v_recon JSONB := '[]'::jsonb;
  v_recon_failures TEXT;
  v_debits NUMERIC(15,2);
  v_credits NUMERIC(15,2);
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF v_key NOT IN ('sales_journal', 'purchase_journal', 'cash_receipts',
                   'cash_disbursements', 'general_journal',
                   'cash_sales_journal', 'cash_purchases_journal') THEN
    RAISE EXCEPTION 'Unsupported books export type: %', p_book_type;
  END IF;

  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid books export date range % to %', p_date_from, p_date_to;
  END IF;

  IF COALESCE(btrim(p_file_name), '') = '' THEN
    RAISE EXCEPTION 'Books export file name is required';
  END IF;

  v_report_type := 'BOOKS_' || upper(v_key);
  v_report_name := CASE v_key
    WHEN 'sales_journal'          THEN 'Sales Journal'
    WHEN 'purchase_journal'       THEN 'Purchase Journal'
    WHEN 'cash_receipts'          THEN 'Cash Receipts Book'
    WHEN 'cash_disbursements'     THEN 'Cash Disbursements Book'
    WHEN 'general_journal'        THEN 'General Journal'
    WHEN 'cash_sales_journal'     THEN 'Cash Sales Journal'
    ELSE 'Cash Purchases Journal'
  END;

  IF v_key IN ('sales_journal', 'cash_sales_journal') THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.date, s.si_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER, COALESCE(SUM(s.total_amount), 0)::NUMERIC(15,2)
    INTO v_rows, v_row_count, v_total
    FROM (
      SELECT si.id AS transaction_id, si.journal_entry_id, si.date, si.si_number,
             si.customer_name_snapshot AS customer_name,
             si.customer_tin_snapshot AS customer_tin,
             si.total_vat_amount, si.total_amount
      FROM sales_invoices si
      WHERE si.company_id = p_company_id
        AND si.status = 'posted'
        AND si.is_cash_sale = (v_key = 'cash_sales_journal')
        AND si.date BETWEEN p_date_from AND p_date_to
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'SI No.', 'Customer', 'TIN', 'VAT', 'Total Amount']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'date',
               e.row ->> 'si_number',
               e.row ->> 'customer_name',
               e.row ->> 'customer_tin',
               fn_export_decimal((e.row ->> 'total_vat_amount')::numeric),
               fn_export_decimal((e.row ->> 'total_amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSIF v_key = 'purchase_journal' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.bill_date, s.bill_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER, COALESCE(SUM(s.total_amount), 0)::NUMERIC(15,2)
    INTO v_rows, v_row_count, v_total
    FROM (
      SELECT vb.id AS transaction_id, vb.journal_entry_id, vb.bill_date, vb.bill_number,
             vb.supplier_name_snapshot AS supplier_name,
             vb.supplier_tin_snapshot AS supplier_tin,
             vb.total_input_vat_amount, vb.total_amount
      FROM vendor_bills vb
      WHERE vb.company_id = p_company_id
        AND vb.status = 'posted'
        AND vb.bill_date BETWEEN p_date_from AND p_date_to
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'VB No.', 'Supplier', 'TIN', 'Input VAT', 'Total Amount']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'bill_date',
               e.row ->> 'bill_number',
               e.row ->> 'supplier_name',
               e.row ->> 'supplier_tin',
               fn_export_decimal((e.row ->> 'total_input_vat_amount')::numeric),
               fn_export_decimal((e.row ->> 'total_amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSIF v_key = 'cash_purchases_journal' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.transaction_date, s.cp_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER, COALESCE(SUM(s.total_amount), 0)::NUMERIC(15,2)
    INTO v_rows, v_row_count, v_total
    FROM (
      SELECT cp.id AS transaction_id, cp.journal_entry_id, cp.transaction_date, cp.cp_number,
             cp.supplier_name_snapshot AS supplier_name,
             cp.supplier_tin_snapshot AS supplier_tin,
             cp.total_input_vat_amount, cp.total_amount
      FROM cash_purchases cp
      WHERE cp.company_id = p_company_id
        AND cp.status = 'posted'
        AND cp.transaction_date BETWEEN p_date_from AND p_date_to
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'CP No.', 'Supplier', 'TIN', 'Input VAT', 'Total Amount']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'transaction_date',
               e.row ->> 'cp_number',
               e.row ->> 'supplier_name',
               e.row ->> 'supplier_tin',
               fn_export_decimal((e.row ->> 'total_input_vat_amount')::numeric),
               fn_export_decimal((e.row ->> 'total_amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSIF v_key = 'cash_receipts' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.date, s.doc_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER, COALESCE(SUM(s.amount), 0)::NUMERIC(15,2)
    INTO v_rows, v_row_count, v_total
    FROM (
      SELECT r.id AS transaction_id, r.journal_entry_id, r.receipt_date AS date,
             'OR'::text AS doc_type, r.receipt_number AS doc_number,
             r.customer_name_snapshot AS payor,
             (r.total_amount + COALESCE(r.total_cwt, 0))::NUMERIC(15,2) AS amount
      FROM receipts r
      WHERE r.company_id = p_company_id
        AND r.status = 'posted'
        AND r.receipt_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT si.id, si.journal_entry_id, si.date, 'CS'::text, si.si_number,
             si.customer_name_snapshot, si.total_amount::NUMERIC(15,2)
      FROM sales_invoices si
      WHERE si.company_id = p_company_id
        AND si.status = 'posted'
        AND si.is_cash_sale = true
        AND si.date BETWEEN p_date_from AND p_date_to
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'Type', 'Doc No.', 'Payor', 'Amount']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'date',
               e.row ->> 'doc_type',
               e.row ->> 'doc_number',
               e.row ->> 'payor',
               fn_export_decimal((e.row ->> 'amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSIF v_key = 'cash_disbursements' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.date, s.doc_number, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER, COALESCE(SUM(s.amount), 0)::NUMERIC(15,2)
    INTO v_rows, v_row_count, v_total
    FROM (
      SELECT pv.id AS transaction_id, pv.journal_entry_id, pv.voucher_date AS date,
             'PV'::text AS doc_type, pv.voucher_number AS doc_number,
             pv.supplier_name_snapshot AS payee,
             (pv.total_amount - COALESCE(pv.total_ewt, 0))::NUMERIC(15,2) AS amount
      FROM payment_vouchers pv
      WHERE pv.company_id = p_company_id
        AND pv.status = 'posted'
        AND pv.voucher_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT cv.id, cv.journal_entry_id, cv.voucher_date, 'CV'::text, cv.cv_number,
             cv.payee, cv.net_check_amount::NUMERIC(15,2)
      FROM check_vouchers cv
      WHERE cv.company_id = p_company_id
        AND cv.status = 'posted'
        AND cv.voucher_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT cp.id, cp.journal_entry_id, cp.transaction_date, 'CP'::text, cp.cp_number,
             COALESCE(cp.supplier_name_snapshot, 'Cash Purchase'),
             cp.total_amount::NUMERIC(15,2)
      FROM cash_purchases cp
      WHERE cp.company_id = p_company_id
        AND cp.status = 'posted'
        AND cp.transaction_date BETWEEN p_date_from AND p_date_to
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'Type', 'Doc No.', 'Payee', 'Amount']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'date',
               CASE e.row ->> 'doc_type'
                 WHEN 'PV' THEN 'Payment Voucher'
                 WHEN 'CV' THEN 'Check Voucher'
                 ELSE 'Cash Purchase'
               END,
               e.row ->> 'doc_number',
               e.row ->> 'payee',
               fn_export_decimal((e.row ->> 'amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSE
    SELECT COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2),
           COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2)
    INTO v_debits, v_credits
    FROM vw_general_ledger
    WHERE company_id = p_company_id
      AND je_date BETWEEN p_date_from AND p_date_to;

    IF v_debits <> v_credits THEN
      RAISE EXCEPTION 'General journal export % to % does not balance: debits % <> credits %',
        p_date_from, p_date_to, v_debits, v_credits;
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.je_date, s.je_number, s.line_number, s.line_id), '[]'::jsonb),
           COUNT(*)::INTEGER, COALESCE(SUM(s.debit_amount), 0)::NUMERIC(15,2)
    INTO v_rows, v_row_count, v_total
    FROM (
      SELECT line_id, je_id, je_date, je_number, je_description, line_number,
             account_code, account_name, line_description, debit_amount, credit_amount
      FROM vw_general_ledger
      WHERE company_id = p_company_id
        AND je_date BETWEEN p_date_from AND p_date_to
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'JE No.', 'Description', 'Account Code', 'Account Name', 'Line Description', 'Debit', 'Credit']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'je_date',
               e.row ->> 'je_number',
               e.row ->> 'je_description',
               e.row ->> 'account_code',
               e.row ->> 'account_name',
               e.row ->> 'line_description',
               fn_export_decimal((e.row ->> 'debit_amount')::numeric),
               fn_export_decimal((e.row ->> 'credit_amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  END IF;

  v_recon := fn_books_export_reconciliation(p_company_id, v_key, p_date_from, p_date_to, v_rows);
  SELECT string_agg(r.value ->> 'check', ', ' ORDER BY r.ord)
  INTO v_recon_failures
  FROM jsonb_array_elements(v_recon) WITH ORDINALITY AS r(value, ord)
  WHERE COALESCE((r.value ->> 'is_reconciled')::BOOLEAN, false) = false;

  IF v_recon_failures IS NOT NULL THEN
    RAISE EXCEPTION 'Books export % period % to % does not reconcile: %',
      v_report_name, p_date_from, p_date_to, v_recon_failures;
  END IF;

  v_export_sha256 := encode(extensions.digest(convert_to(v_export_text, 'UTF8'), 'sha256'), 'hex');
  v_export_size := octet_length(convert_to(v_export_text, 'UTF8'));

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'report_name', v_report_name,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'file_name', p_file_name
  );

  v_source_payload := jsonb_build_object(
    'report', v_report_payload,
    'export_rows', v_rows,
    'export_file_text', v_export_text,
    'export_file_sha256', v_export_sha256,
    'export_file_size_bytes', v_export_size,
    'integrity', jsonb_build_object('row_count', v_row_count, 'total', v_total),
    'reconciliation', v_recon
  );

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' ||
    p_date_from::text || ':' || p_date_to::text
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'books_export_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_source_hash := encode(extensions.digest(convert_to(v_source_payload::text, 'UTF8'), 'sha256'), 'hex');
  v_snapshot_id := gen_random_uuid();

  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count,
    generated_by
  )
  VALUES (
    v_snapshot_id, p_company_id, v_report_type, 'books_export_periods', v_source_id,
    'exported', v_snapshot_version, p_date_from, p_date_to,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  );

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year,
    file_name, row_count, generated_by, snapshot_id, remarks,
    file_sha256, file_size_bytes
  )
  VALUES (
    p_company_id, 'csv_export', v_report_name, EXTRACT(YEAR FROM p_date_from)::INTEGER,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id,
    p_date_from::text || '..' || p_date_to::text,
    v_export_sha256, v_export_size
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_snapshot_version,
    'source_hash', v_source_hash,
    'export_sha256', v_export_sha256,
    'export_size_bytes', v_export_size,
    'export_text', v_export_text,
    'reconciliation', v_recon,
    'row_count', v_row_count,
    'rows', v_rows
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_cas_audit_package(
  p_company_id UUID,
  p_date_from DATE,
  p_date_to DATE,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source_id UUID;
  v_version INTEGER;
  v_payload JSONB;
  v_checks JSONB;
  v_hash TEXT;
  v_snapshot_id UUID := gen_random_uuid();
  v_row_count INTEGER;
  v_debits NUMERIC(15,2);
  v_credits NUMERIC(15,2);
  v_books JSONB;
  v_books_count INTEGER;
  v_books_all_reconciled BOOLEAN;
  v_exports JSONB;
  v_export_count INTEGER;
  v_missing_export_hashes INTEGER;
  v_missing_dat_artifacts INTEGER;
  v_dat_artifacts JSONB;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid CAS audit package date range';
  END IF;

  IF NULLIF(btrim(COALESCE(p_file_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'CAS audit package file name is required';
  END IF;

  SELECT COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2),
         COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2)
  INTO v_debits, v_credits
  FROM vw_general_ledger
  WHERE company_id = p_company_id
    AND je_date BETWEEN p_date_from AND p_date_to;

  WITH book_snapshots AS (
    SELECT rs.id, rs.report_type, rs.period_start, rs.period_end,
           rs.snapshot_version, rs.source_hash, rs.source_row_count,
           rs.source_payload -> 'reconciliation' AS reconciliation,
           NOT EXISTS (
             SELECT 1
             FROM jsonb_array_elements(COALESCE(rs.source_payload -> 'reconciliation', '[]'::jsonb)) AS r(value)
             WHERE COALESCE((r.value ->> 'is_reconciled')::BOOLEAN, false) = false
           )
           AND jsonb_array_length(COALESCE(rs.source_payload -> 'reconciliation', '[]'::jsonb)) > 0
             AS is_reconciled
    FROM report_snapshots rs
    WHERE rs.company_id = p_company_id
      AND rs.snapshot_status = 'exported'
      AND rs.report_type LIKE 'BOOKS_%'
      AND rs.period_start >= p_date_from
      AND rs.period_end <= p_date_to
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(book_snapshots) ORDER BY report_type, period_start, snapshot_version), '[]'::jsonb),
         COUNT(*)::INTEGER,
         COALESCE(bool_and(is_reconciled), false)
  INTO v_books, v_books_count, v_books_all_reconciled
  FROM book_snapshots;

  WITH export_evidence AS (
    SELECT e.*, rs.period_start AS evidence_period_start,
           rs.period_end AS evidence_period_end,
           rs.report_type AS evidence_report_type
    FROM cas_export_log e
    LEFT JOIN report_snapshots rs ON rs.id = e.snapshot_id
    WHERE e.company_id = p_company_id
      AND e.export_type IN ('dat_file', 'csv_export')
      AND (
        (rs.id IS NOT NULL
         AND rs.period_start >= p_date_from
         AND rs.period_end <= p_date_to)
        OR
        (rs.id IS NULL AND e.generated_at::date BETWEEN p_date_from AND p_date_to)
      )
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.generated_at, e.id), '[]'::jsonb),
         COUNT(*)::INTEGER,
         (COUNT(*) FILTER (
           WHERE e.export_type IN ('dat_file', 'csv_export')
             AND (e.file_sha256 IS NULL OR e.file_size_bytes IS NULL)
         ))::INTEGER,
         (COUNT(*) FILTER (
           WHERE e.export_type = 'dat_file'
             AND (e.artifact_id IS NULL OR e.file_hash IS NULL OR e.layout_version IS NULL)
         ))::INTEGER
  INTO v_exports, v_export_count, v_missing_export_hashes, v_missing_dat_artifacts
  FROM export_evidence e;

  WITH dat_artifact_evidence AS (
    SELECT DISTINCT a.*
    FROM cas_export_artifacts a
    JOIN cas_export_log e ON e.artifact_id = a.id
    LEFT JOIN report_snapshots rs ON rs.id = e.snapshot_id
    WHERE e.company_id = p_company_id
      AND e.export_type = 'dat_file'
      AND (
        (rs.id IS NOT NULL
         AND rs.period_start >= p_date_from
         AND rs.period_end <= p_date_to)
        OR
        (rs.id IS NULL AND e.generated_at::date BETWEEN p_date_from AND p_date_to)
      )
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.generated_at, a.file_name), '[]'::jsonb)
  INTO v_dat_artifacts
  FROM dat_artifact_evidence a;

  v_checks := jsonb_build_array(
    jsonb_build_object(
      'check', 'gl_balance',
      'debits', v_debits,
      'credits', v_credits,
      'is_reconciled', ABS(v_debits - v_credits) <= 0.01
    ),
    jsonb_build_object(
      'check', 'books_reconciliation',
      'snapshot_count', v_books_count,
      'is_reconciled', v_books_count > 0 AND v_books_all_reconciled
    ),
    jsonb_build_object(
      'check', 'export_hash_evidence',
      'export_count', v_export_count,
      'missing_hashes', COALESCE(v_missing_export_hashes, 0),
      'missing_dat_artifacts', COALESCE(v_missing_dat_artifacts, 0),
      'is_reconciled', v_export_count > 0
        AND COALESCE(v_missing_export_hashes, 0) = 0
        AND COALESCE(v_missing_dat_artifacts, 0) = 0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_checks) AS c(value)
    WHERE COALESCE((c.value ->> 'is_reconciled')::BOOLEAN, false) = false
  ) THEN
    RAISE EXCEPTION 'CAS audit package % to % does not reconcile: %',
      p_date_from, p_date_to,
      (SELECT string_agg(c.value ->> 'check', ', ' ORDER BY c.ord)
       FROM jsonb_array_elements(v_checks) WITH ORDINALITY AS c(value, ord)
       WHERE COALESCE((c.value ->> 'is_reconciled')::BOOLEAN, false) = false);
  END IF;

  SELECT jsonb_build_object(
    'checks', v_checks,
    'gl_control', jsonb_build_object('total_debit', v_debits, 'total_credit', v_credits),
    'books_reconciliation', v_books,
    'number_issuances', COALESCE((
      SELECT jsonb_agg(to_jsonb(i) ORDER BY allocated_at, document_code, document_number)
      FROM cas_document_number_issuances i
      WHERE i.company_id = p_company_id
        AND i.allocated_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'void_events', COALESCE((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY occurred_at, document_code, document_number)
      FROM cas_document_void_events v
      WHERE v.company_id = p_company_id
        AND v.occurred_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'exports', v_exports,
    'dat_artifacts', v_dat_artifacts,
    'audit_events', COALESCE((
      SELECT jsonb_agg(to_jsonb(a) ORDER BY changed_at, id)
      FROM sys_audit_logs a
      WHERE a.company_id = p_company_id
        AND a.changed_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb)
  )
  INTO v_payload;

  v_row_count := jsonb_array_length(v_payload -> 'number_issuances')
               + jsonb_array_length(v_payload -> 'void_events')
               + jsonb_array_length(v_payload -> 'exports')
               + jsonb_array_length(v_payload -> 'dat_artifacts')
               + jsonb_array_length(v_payload -> 'audit_events')
               + jsonb_array_length(v_payload -> 'books_reconciliation');

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':CAS_AUDIT_PACKAGE:' || p_date_from || ':' || p_date_to
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_version
  FROM report_snapshots
  WHERE source_table = 'cas_audit_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count, generated_by
  ) VALUES (
    v_snapshot_id, p_company_id, 'CAS_AUDIT_PACKAGE', 'cas_audit_periods', v_source_id,
    'exported', v_version, p_date_from, p_date_to,
    jsonb_build_object('file_name', p_file_name, 'date_from', p_date_from, 'date_to', p_date_to),
    v_payload, v_hash, v_row_count, auth.uid()
  );

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year,
    file_name, row_count, generated_by, snapshot_id, remarks,
    file_sha256, file_size_bytes
  ) VALUES (
    p_company_id, 'audit_package', 'CAS Audit Support Package',
    EXTRACT(YEAR FROM p_date_from)::INTEGER,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id,
    p_date_from::text || '..' || p_date_to::text,
    v_hash, octet_length(convert_to(v_payload::text, 'UTF8'))
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_version,
    'source_hash', v_hash,
    'row_count', v_row_count,
    'checks', v_checks
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_books_export(UUID, TEXT, DATE, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_books_export_reconciliation(UUID, TEXT, DATE, DATE, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_snapshot_cas_audit_package(UUID, DATE, DATE, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_books_export_reconciliation(UUID, TEXT, DATE, DATE, JSONB) IS
  'Builds source-row, linked-journal-entry, and GL-balance reconciliation evidence for a BIR books export.';
COMMENT ON FUNCTION fn_snapshot_books_export(UUID, TEXT, DATE, DATE, TEXT) IS
  'Builds a BIR books-of-accounts export payload server-side, gates it on source/GL reconciliation, freezes exact file bytes in a versioned snapshot, and writes the server-attested export log.';
COMMENT ON FUNCTION fn_snapshot_cas_audit_package(UUID, DATE, DATE, TEXT) IS
  'Creates a server-attested CAS audit package snapshot with numbering, void, export, artifact, GL, audit-log, and books-reconciliation evidence.';
