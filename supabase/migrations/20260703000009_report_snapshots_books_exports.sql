-- Immutable report snapshots, sixth slice: BIR books of accounts exports
-- (PXL-DA-015): sales journal, purchase journal, cash receipts book, cash
-- disbursements book, general journal, cash sales journal, cash purchases
-- journal.
--
-- The seven Books pages exported browser-assembled CSVs of posted documents /
-- GL lines with no provenance. fn_snapshot_books_export builds each book's
-- payload server-side over an arbitrary date range, freezes the rows in a
-- versioned exported snapshot with a SHA-256 hash, gates the general journal
-- on period debit=credit balance, writes a server-attested cas_export_log row
-- (export_type 'csv_export', linked via snapshot_id), and returns the frozen
-- rows so the downloaded file is provably the hashed payload — the same
-- contract as fn_snapshot_cas_export.

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
  ELSIF v_key = 'cash_receipts' THEN
    -- OR collections (gross of CWT) plus cash-sale invoices, one book.
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
  ELSIF v_key = 'cash_disbursements' THEN
    -- PV net of EWT, CV net check amount, CP totals, one book.
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
  ELSE
    -- General journal: every GL line in the range, gated on balance.
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
  END IF;

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
    file_name, row_count, generated_by, snapshot_id, remarks
  )
  VALUES (
    p_company_id, 'csv_export', v_report_name, EXTRACT(YEAR FROM p_date_from)::INTEGER,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id,
    p_date_from::text || '..' || p_date_to::text
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_snapshot_version,
    'source_hash', v_source_hash,
    'row_count', v_row_count,
    'rows', v_rows
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_books_export(UUID, TEXT, DATE, DATE, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_snapshot_books_export(UUID, TEXT, DATE, DATE, TEXT) IS
  'Builds a BIR books-of-accounts export payload server-side, freezes it in a versioned exported report snapshot with a SHA-256 hash, writes the cas_export_log evidence row, and returns the frozen rows for file generation.';
