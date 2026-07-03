-- Immutable report snapshots, third slice: VAT export attachments (PXL-DA-015).
--
-- SLSP and RELIEF exports were previously browser-only CSV downloads over live
-- VAT review views. This RPC creates an append-only exported snapshot before a
-- file is produced, with a deterministic logical source id per company/report/
-- month/export part and incrementing export versions for history.

CREATE OR REPLACE FUNCTION fn_report_snapshot_key_uuid(p_key TEXT)
RETURNS UUID
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT (
    substr(md5(p_key), 1, 8) || '-' ||
    substr(md5(p_key), 9, 4) || '-' ||
    substr(md5(p_key), 13, 4) || '-' ||
    substr(md5(p_key), 17, 4) || '-' ||
    substr(md5(p_key), 21, 12)
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_vat_export(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_month INTEGER,
  p_export_part TEXT DEFAULT 'all'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report_type TEXT := upper(p_report_type);
  v_export_part TEXT := lower(COALESCE(p_export_part, 'all'));
  v_start DATE;
  v_end DATE;
  v_taxable_month TEXT;
  v_source_id UUID;
  v_snapshot_id UUID;
  v_snapshot_version INTEGER;
  v_report_payload JSONB;
  v_source_payload JSONB;
  v_source_hash TEXT;
  v_sales_count INTEGER := 0;
  v_purchase_count INTEGER := 0;
  v_recon_failures TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF v_report_type NOT IN ('SLSP', 'RELIEF') THEN
    RAISE EXCEPTION 'Unsupported VAT export report type: %', p_report_type;
  END IF;

  IF v_export_part NOT IN ('all', 'sales', 'purchases') THEN
    RAISE EXCEPTION 'Unsupported VAT export part: %', p_export_part;
  END IF;

  IF p_month NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Invalid VAT export month: %', p_month;
  END IF;

  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  v_taxable_month := to_char(v_start, 'MM/YYYY');

  SELECT string_agg(tax_kind || ' variance ' || variance::text, '; ' ORDER BY tax_kind)
  INTO v_recon_failures
  FROM fn_vat_gl_reconciliation(p_company_id, v_start, v_end)
  WHERE NOT is_reconciled;

  IF v_recon_failures IS NOT NULL THEN
    RAISE EXCEPTION 'VAT export period % to % does not reconcile to GL account: %',
      v_start, v_end, v_recon_failures;
  END IF;

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' || p_year::text || ':' ||
    p_month::text || ':' || v_export_part
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'vat_export_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'period_year', p_year,
    'period_month', p_month,
    'export_part', v_export_part,
    'taxable_month', v_taxable_month
  );

  IF v_report_type = 'SLSP' THEN
    WITH
    sales_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.customer_name, s.customer_tin), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT
          COALESCE(customer_tin, '') AS customer_tin,
          COALESCE(customer_name, 'Unknown') AS customer_name,
          SUM(gross_sales)::NUMERIC(15,2) AS gross_sales,
          SUM(exempt_sales)::NUMERIC(15,2) AS exempt_sales,
          SUM(zero_rated_sales)::NUMERIC(15,2) AS zero_rated_sales,
          SUM(taxable_base)::NUMERIC(15,2) AS taxable_base,
          SUM(output_vat)::NUMERIC(15,2) AS output_vat
        FROM vw_output_vat_review
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
        GROUP BY COALESCE(customer_tin, ''), COALESCE(customer_name, 'Unknown')
      ) s
    ),
    purchase_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.registered_name, p.supplier_tin, p.bill_date), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT taxable_month, bill_date, supplier_tin, registered_name, address,
               gross_purchases, exempt_purchases, zero_rated, taxable_base, input_vat
        FROM vw_slp_export
        WHERE company_id = p_company_id
          AND taxable_month = v_taxable_month
      ) p
    ),
    recon_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
      FROM (
        SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
               gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
        FROM fn_vat_gl_reconciliation(p_company_id, v_start, v_end)
      ) r
    )
    SELECT jsonb_build_object(
             'report', v_report_payload,
             'sales_summary_rows', CASE WHEN v_export_part IN ('all', 'sales') THEN sales_rows.payload ELSE '[]'::jsonb END,
             'purchase_summary_rows', CASE WHEN v_export_part IN ('all', 'purchases') THEN purchase_rows.payload ELSE '[]'::jsonb END,
             'vat_gl_reconciliation', recon_rows.payload
           ),
           CASE WHEN v_export_part IN ('all', 'sales') THEN sales_rows.row_count ELSE 0 END,
           CASE WHEN v_export_part IN ('all', 'purchases') THEN purchase_rows.row_count ELSE 0 END
    INTO v_source_payload, v_sales_count, v_purchase_count
    FROM sales_rows, purchase_rows, recon_rows;
  ELSE
    WITH
    sales_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.system_no, s.transaction_id), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, invoice_date, system_no, customer_tin, customer_name,
               gross_sales, taxable_base, output_vat
        FROM vw_output_vat_review
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
      ) s
    ),
    purchase_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.invoice_date, p.system_no, p.transaction_id), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, invoice_date, system_no, supplier_tin, supplier_name,
               gross_purchases, taxable_base, input_vat
        FROM vw_input_vat_review
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
      ) p
    ),
    recon_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
      FROM (
        SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
               gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
        FROM fn_vat_gl_reconciliation(p_company_id, v_start, v_end)
      ) r
    )
    SELECT jsonb_build_object(
             'report', v_report_payload,
             'sales_detail_rows', CASE WHEN v_export_part IN ('all', 'sales') THEN sales_rows.payload ELSE '[]'::jsonb END,
             'purchase_detail_rows', CASE WHEN v_export_part IN ('all', 'purchases') THEN purchase_rows.payload ELSE '[]'::jsonb END,
             'vat_gl_reconciliation', recon_rows.payload
           ),
           CASE WHEN v_export_part IN ('all', 'sales') THEN sales_rows.row_count ELSE 0 END,
           CASE WHEN v_export_part IN ('all', 'purchases') THEN purchase_rows.row_count ELSE 0 END
    INTO v_source_payload, v_sales_count, v_purchase_count
    FROM sales_rows, purchase_rows, recon_rows;
  END IF;

  v_source_hash := encode(extensions.digest(convert_to(v_source_payload::text, 'UTF8'), 'sha256'), 'hex');
  v_snapshot_id := gen_random_uuid();

  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count,
    generated_by
  )
  VALUES (
    v_snapshot_id, p_company_id, v_report_type, 'vat_export_periods', v_source_id,
    'exported', v_snapshot_version, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_sales_count + v_purchase_count,
    auth.uid()
  );

  RETURN v_snapshot_id;
END;
$$;

COMMENT ON FUNCTION fn_snapshot_vat_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'Creates an exported immutable report snapshot for SLSP/RELIEF VAT attachments, with source hash and reconciliation payload.';
