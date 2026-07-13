-- PXL-DA-019: exported-byte evidence for CAS DAT and BIR books exports.
--
-- Earlier CAS/books snapshots hashed the canonical JSON source payload and
-- returned frozen rows for the browser to render as CSV. That proved the rows,
-- but not the exact file bytes downloaded by the user. This slice renders the
-- export text server-side, stores the text + SHA-256 in the immutable snapshot
-- payload, mirrors the hash/byte size onto cas_export_log, and returns the same
-- text to the UI for download.

ALTER TABLE cas_export_log
  ADD COLUMN IF NOT EXISTS file_sha256 TEXT,
  ADD COLUMN IF NOT EXISTS file_size_bytes INTEGER;

COMMENT ON COLUMN cas_export_log.file_sha256 IS
  'SHA-256 of the exact UTF-8 export file text returned by the snapshot RPC.';
COMMENT ON COLUMN cas_export_log.file_size_bytes IS
  'UTF-8 byte length of the exact export file text returned by the snapshot RPC.';

CREATE OR REPLACE FUNCTION fn_export_decimal(p_value NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT to_char(COALESCE(p_value, 0), 'FM999999999999990.00')
$$;

CREATE OR REPLACE FUNCTION fn_export_csv_line(p_cells TEXT[])
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_to_string(
    array_agg('"' || replace(COALESCE(u.cell, ''), '"', '""') || '"' ORDER BY u.ord),
    ','
  )
  FROM unnest(p_cells) WITH ORDINALITY AS u(cell, ord)
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_cas_export_unchecked(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_month INTEGER,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key TEXT := lower(p_report_type);
  v_report_type TEXT;
  v_report_name TEXT;
  v_start DATE;
  v_end DATE;
  v_source_id UUID;
  v_snapshot_id UUID;
  v_snapshot_version INTEGER;
  v_report_payload JSONB;
  v_rows JSONB;
  v_row_count INTEGER := 0;
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

  IF v_key NOT IN ('slsp', 'relief', 'general_ledger', 'alphalist_payees') THEN
    RAISE EXCEPTION 'Unsupported CAS export report type: %', p_report_type;
  END IF;

  IF p_month NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Invalid CAS export month: %', p_month;
  END IF;

  IF COALESCE(btrim(p_file_name), '') = '' THEN
    RAISE EXCEPTION 'CAS export file name is required';
  END IF;

  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  v_report_type := CASE v_key
    WHEN 'slsp' THEN 'CAS_SLSP'
    WHEN 'relief' THEN 'CAS_RELIEF'
    WHEN 'general_ledger' THEN 'CAS_GL'
    ELSE 'CAS_QAP'
  END;
  v_report_name := CASE v_key
    WHEN 'slsp' THEN 'SLSP (Sales & Purchases)'
    WHEN 'relief' THEN 'RELIEF Listing'
    WHEN 'general_ledger' THEN 'General Ledger'
    ELSE 'Alphalist of Payees (QAP)'
  END;

  IF v_key IN ('slsp', 'relief') THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb),
           string_agg(r.tax_kind || ' variance ' || r.variance::text, '; ' ORDER BY r.tax_kind)
             FILTER (WHERE NOT r.is_reconciled)
    INTO v_recon, v_recon_failures
    FROM fn_vat_gl_reconciliation(p_company_id, v_start, v_end) r;
  ELSIF v_key = 'alphalist_payees' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb),
           string_agg(r.tax_kind || ' variance ' || r.variance::text, '; ' ORDER BY r.tax_kind)
             FILTER (WHERE r.tax_kind = 'ewt_payable' AND NOT r.is_reconciled)
    INTO v_recon, v_recon_failures
    FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end) r;
  ELSE
    SELECT COALESCE(SUM(debit_amount), 0)::NUMERIC(15,2),
           COALESCE(SUM(credit_amount), 0)::NUMERIC(15,2)
    INTO v_debits, v_credits
    FROM vw_general_ledger
    WHERE company_id = p_company_id
      AND je_date BETWEEN v_start AND v_end;
    v_recon := jsonb_build_array(jsonb_build_object(
      'check', 'gl_balance', 'debits', v_debits, 'credits', v_credits,
      'is_reconciled', v_debits = v_credits));
    IF v_debits <> v_credits THEN
      v_recon_failures := format('GL debits %s <> credits %s', v_debits, v_credits);
    END IF;
  END IF;

  IF v_recon_failures IS NOT NULL THEN
    RAISE EXCEPTION 'CAS export % period % to % does not reconcile: %',
      v_report_name, v_start, v_end, v_recon_failures;
  END IF;

  IF v_key = 'slsp' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.system_no, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, system_no, customer_tin, customer_name,
             taxable_base, output_vat
      FROM vw_output_vat_review
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'Doc No.', 'TIN', 'Name', 'Taxable Base', 'VAT']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'invoice_date',
               e.row ->> 'system_no',
               e.row ->> 'customer_tin',
               e.row ->> 'customer_name',
               fn_export_decimal((e.row ->> 'taxable_base')::numeric),
               fn_export_decimal((e.row ->> 'output_vat')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSIF v_key = 'relief' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.system_no, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, system_no, supplier_tin, supplier_name,
             taxable_base, input_vat
      FROM vw_input_vat_review
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'Doc No.', 'TIN', 'Name', 'Taxable Base', 'VAT']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'invoice_date',
               e.row ->> 'system_no',
               e.row ->> 'supplier_tin',
               e.row ->> 'supplier_name',
               fn_export_decimal((e.row ->> 'taxable_base')::numeric),
               fn_export_decimal((e.row ->> 'input_vat')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSIF v_key = 'general_ledger' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.je_date, s.je_number, s.line_number, s.line_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT line_id, je_id, je_date, je_number, je_status, line_number,
             account_code, account_name, debit_amount, credit_amount
      FROM vw_general_ledger
      WHERE company_id = p_company_id
        AND je_date BETWEEN v_start AND v_end
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'JE No.', 'Account Code', 'Account Name', 'Debit', 'Credit']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'je_date',
               e.row ->> 'je_number',
               e.row ->> 'account_code',
               e.row ->> 'account_name',
               fn_export_decimal((e.row ->> 'debit_amount')::numeric),
               fn_export_decimal((e.row ->> 'credit_amount')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  ELSE
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.transaction_id), '[]'::jsonb),
           COUNT(*)::INTEGER
    INTO v_rows, v_row_count
    FROM (
      SELECT transaction_id, invoice_date, supplier_tin, supplier_name,
             atc_code, tax_base, tax_withheld
      FROM vw_ewt_summary_ap
      WHERE company_id = p_company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s;

    SELECT string_agg(line, E'\n' ORDER BY ord)
    INTO v_export_text
    FROM (
      SELECT 0::bigint AS ord, fn_export_csv_line(ARRAY['Date', 'TIN', 'Name', 'ATC', 'Tax Base', 'Tax Withheld']) AS line
      UNION ALL
      SELECT e.ord,
             fn_export_csv_line(ARRAY[
               e.row ->> 'invoice_date',
               e.row ->> 'supplier_tin',
               e.row ->> 'supplier_name',
               e.row ->> 'atc_code',
               fn_export_decimal((e.row ->> 'tax_base')::numeric),
               fn_export_decimal((e.row ->> 'tax_withheld')::numeric)
             ])
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row, ord)
    ) csv;
  END IF;

  v_export_sha256 := encode(extensions.digest(convert_to(v_export_text, 'UTF8'), 'sha256'), 'hex');
  v_export_size := octet_length(convert_to(v_export_text, 'UTF8'));

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'report_name', v_report_name,
    'period_year', p_year,
    'period_month', p_month,
    'file_name', p_file_name
  );

  v_source_payload := jsonb_build_object(
    'report', v_report_payload,
    'export_rows', v_rows,
    'export_file_text', v_export_text,
    'export_file_sha256', v_export_sha256,
    'export_file_size_bytes', v_export_size,
    'reconciliation', v_recon
  );

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' || p_year::text || ':' || p_month::text
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'cas_export_periods'
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
    v_snapshot_id, p_company_id, v_report_type, 'cas_export_periods', v_source_id,
    'exported', v_snapshot_version, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  );

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year, period_month,
    file_name, row_count, generated_by, snapshot_id, file_sha256, file_size_bytes
  )
  VALUES (
    p_company_id, 'dat_file', v_report_name, p_year, p_month,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id, v_export_sha256, v_export_size
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_snapshot_version,
    'source_hash', v_source_hash,
    'export_sha256', v_export_sha256,
    'export_size_bytes', v_export_size,
    'export_text', v_export_text,
    'row_count', v_row_count,
    'rows', v_rows
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
      SELECT si.id AS transaction_id, si.date, si.si_number,
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
      SELECT vb.id AS transaction_id, vb.bill_date, vb.bill_number,
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
      SELECT cp.id AS transaction_id, cp.transaction_date, cp.cp_number,
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
      SELECT r.id AS transaction_id, r.receipt_date AS date, 'OR'::text AS doc_type,
             r.receipt_number AS doc_number, r.customer_name_snapshot AS payor,
             (r.total_amount + COALESCE(r.total_cwt, 0))::NUMERIC(15,2) AS amount
      FROM receipts r
      WHERE r.company_id = p_company_id
        AND r.status = 'posted'
        AND r.receipt_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT si.id, si.date, 'CS'::text, si.si_number,
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
      SELECT pv.id AS transaction_id, pv.voucher_date AS date, 'PV'::text AS doc_type,
             pv.voucher_number AS doc_number, pv.supplier_name_snapshot AS payee,
             (pv.total_amount - COALESCE(pv.total_ewt, 0))::NUMERIC(15,2) AS amount
      FROM payment_vouchers pv
      WHERE pv.company_id = p_company_id
        AND pv.status = 'posted'
        AND pv.voucher_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT cv.id, cv.voucher_date, 'CV'::text, cv.cv_number, cv.payee,
             cv.net_check_amount::NUMERIC(15,2)
      FROM check_vouchers cv
      WHERE cv.company_id = p_company_id
        AND cv.status = 'posted'
        AND cv.voucher_date BETWEEN p_date_from AND p_date_to
      UNION ALL
      SELECT cp.id, cp.transaction_date, 'CP'::text, cp.cp_number,
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

    v_recon := jsonb_build_array(jsonb_build_object(
      'check', 'gl_balance', 'debits', v_debits, 'credits', v_credits,
      'is_reconciled', true));

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
    'row_count', v_row_count,
    'rows', v_rows
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_books_export(UUID, TEXT, DATE, DATE, TEXT) TO authenticated;
