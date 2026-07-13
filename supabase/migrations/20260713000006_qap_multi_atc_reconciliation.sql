-- PXL-DA-009: QAP multi-ATC supplier reconciliation
--
-- The QAP snapshot previously froze detail rows at ATC level, but its payee
-- summary collapsed all ATCs for a supplier into one row. That made the
-- exported alphalist weak evidence against Form 2307 issuance lines, which are
-- supplier + ATC + nature + rate rows. This migration aligns the QAP summary
-- with the 2307 line contract and stores an explicit QAP-to-2307 reconciliation
-- payload in every QAP snapshot.

CREATE OR REPLACE FUNCTION fn_qap_2307_reconciliation(
  p_company_id UUID,
  p_tax_year INT,
  p_tax_quarter INT
)
RETURNS TABLE (
  supplier_id UUID,
  supplier_tin TEXT,
  supplier_name TEXT,
  atc_code_id UUID,
  atc_code TEXT,
  nature_of_payment TEXT,
  tax_rate NUMERIC(5,2),
  qap_tax_base NUMERIC(15,2),
  qap_tax_withheld NUMERIC(15,2),
  form2307_tax_base NUMERIC(15,2),
  form2307_tax_withheld NUMERIC(15,2),
  base_variance NUMERIC(15,2),
  withheld_variance NUMERIC(15,2),
  form2307_status TEXT,
  form2307_version INT,
  is_reconciled BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start DATE;
  v_end_exclusive DATE;
BEGIN
  IF p_tax_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid tax quarter: %', p_tax_quarter;
  END IF;
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  v_start := make_date(p_tax_year, ((p_tax_quarter - 1) * 3) + 1, 1);
  v_end_exclusive := v_start + INTERVAL '3 months';

  RETURN QUERY
  WITH qap AS (
    SELECT
      e.supplier_id,
      COALESCE(e.supplier_tin, '') AS supplier_tin,
      COALESCE(e.supplier_name, 'Unknown') AS supplier_name,
      e.atc_code_id,
      COALESCE(e.atc_code, '') AS atc_code,
      COALESCE(e.nature_of_payment, '') AS nature_of_payment,
      COALESCE(e.tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
      SUM(COALESCE(e.tax_base, 0))::NUMERIC(15,2) AS tax_base,
      SUM(COALESCE(e.tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld
    FROM vw_ewt_summary_ap e
    WHERE e.company_id = p_company_id
      AND e.invoice_date >= v_start
      AND e.invoice_date < v_end_exclusive
    GROUP BY
      e.supplier_id,
      COALESCE(e.supplier_tin, ''),
      COALESCE(e.supplier_name, 'Unknown'),
      e.atc_code_id,
      COALESCE(e.atc_code, ''),
      COALESCE(e.nature_of_payment, ''),
      COALESCE(e.tax_rate, 0)
  ),
  cert AS (
    SELECT
      f.supplier_id,
      COALESCE(s.tin, '') AS supplier_tin,
      COALESCE(s.registered_name, 'Unknown') AS supplier_name,
      l.atc_code_id,
      COALESCE(l.atc_code, '') AS atc_code,
      COALESCE(l.nature_of_income, '') AS nature_of_payment,
      COALESCE(l.tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
      SUM(COALESCE(l.tax_base, 0))::NUMERIC(15,2) AS tax_base,
      SUM(COALESCE(l.tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld,
      string_agg(DISTINCT f.status, ', ' ORDER BY f.status) AS status,
      MAX(f.version) AS version
    FROM form_2307_issuances f
    JOIN form_2307_issuance_lines l ON l.issuance_id = f.id
    LEFT JOIN suppliers s ON s.id = f.supplier_id
    WHERE f.company_id = p_company_id
      AND f.tax_year = p_tax_year
      AND f.tax_quarter = p_tax_quarter
      AND f.status <> 'superseded'
    GROUP BY
      f.supplier_id,
      COALESCE(s.tin, ''),
      COALESCE(s.registered_name, 'Unknown'),
      l.atc_code_id,
      COALESCE(l.atc_code, ''),
      COALESCE(l.nature_of_income, ''),
      COALESCE(l.tax_rate, 0)
  )
  SELECT
    COALESCE(q.supplier_id, c.supplier_id),
    COALESCE(NULLIF(q.supplier_tin, ''), c.supplier_tin, '') AS supplier_tin,
    COALESCE(NULLIF(q.supplier_name, ''), c.supplier_name, 'Unknown') AS supplier_name,
    COALESCE(q.atc_code_id, c.atc_code_id),
    COALESCE(NULLIF(q.atc_code, ''), c.atc_code, '') AS atc_code,
    COALESCE(NULLIF(q.nature_of_payment, ''), c.nature_of_payment, '') AS nature_of_payment,
    COALESCE(q.tax_rate, c.tax_rate, 0)::NUMERIC(5,2),
    COALESCE(q.tax_base, 0)::NUMERIC(15,2),
    COALESCE(q.tax_withheld, 0)::NUMERIC(15,2),
    COALESCE(c.tax_base, 0)::NUMERIC(15,2),
    COALESCE(c.tax_withheld, 0)::NUMERIC(15,2),
    (COALESCE(q.tax_base, 0) - COALESCE(c.tax_base, 0))::NUMERIC(15,2),
    (COALESCE(q.tax_withheld, 0) - COALESCE(c.tax_withheld, 0))::NUMERIC(15,2),
    c.status,
    c.version,
    (
      q.supplier_id IS NOT NULL
      AND NULLIF(BTRIM(COALESCE(q.supplier_tin, '')), '') IS NOT NULL
      AND NULLIF(BTRIM(COALESCE(q.atc_code, '')), '') IS NOT NULL
      AND ABS(COALESCE(q.tax_base, 0) - COALESCE(c.tax_base, 0)) <= 0.01
      AND ABS(COALESCE(q.tax_withheld, 0) - COALESCE(c.tax_withheld, 0)) <= 0.01
    ) AS is_reconciled
  FROM qap q
  FULL OUTER JOIN cert c
    ON q.supplier_id IS NOT DISTINCT FROM c.supplier_id
   AND q.atc_code_id IS NOT DISTINCT FROM c.atc_code_id
   AND q.atc_code = c.atc_code
   AND q.nature_of_payment = c.nature_of_payment
   AND q.tax_rate = c.tax_rate
  ORDER BY
    COALESCE(NULLIF(q.supplier_name, ''), c.supplier_name, 'Unknown'),
    COALESCE(NULLIF(q.supplier_tin, ''), c.supplier_tin, ''),
    COALESCE(NULLIF(q.atc_code, ''), c.atc_code, ''),
    COALESCE(NULLIF(q.nature_of_payment, ''), c.nature_of_payment, '');
END;
$$;

GRANT EXECUTE ON FUNCTION fn_qap_2307_reconciliation(UUID, INT, INT) TO authenticated;

COMMENT ON FUNCTION fn_qap_2307_reconciliation(UUID, INT, INT) IS
  'Compares QAP source rows to the active non-superseded Form 2307 issuance lines at supplier + ATC + nature + rate granularity.';

CREATE OR REPLACE FUNCTION fn_snapshot_wht_export(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_quarter INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report_type TEXT := upper(p_report_type);
  v_recon_kind TEXT;
  v_start DATE;
  v_end DATE;
  v_source_id UUID;
  v_snapshot_id UUID;
  v_snapshot_version INTEGER;
  v_report_payload JSONB;
  v_source_payload JSONB;
  v_source_hash TEXT;
  v_row_count INTEGER := 0;
  v_recon_failures TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF v_report_type NOT IN ('SAWT', 'QAP') THEN
    RAISE EXCEPTION 'Unsupported withholding export report type: %', p_report_type;
  END IF;

  IF p_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid withholding export quarter: %', p_quarter;
  END IF;

  v_recon_kind := CASE v_report_type WHEN 'QAP' THEN 'ewt_payable' ELSE 'cwt_receivable' END;
  v_start := make_date(p_year, (p_quarter - 1) * 3 + 1, 1);
  v_end := (v_start + INTERVAL '3 months' - INTERVAL '1 day')::DATE;

  SELECT string_agg(r.tax_kind || ' variance ' || r.variance::text, '; ' ORDER BY r.tax_kind)
  INTO v_recon_failures
  FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end) r
  WHERE r.tax_kind = v_recon_kind
    AND NOT r.is_reconciled;

  IF v_recon_failures IS NOT NULL THEN
    RAISE EXCEPTION '% export period % to % does not reconcile to GL account: %',
      v_report_type, v_start, v_end, v_recon_failures;
  END IF;

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':' || v_report_type || ':' || p_year::text || ':Q' || p_quarter::text
  );

  SELECT COALESCE(MAX(snapshot_version), 0) + 1
  INTO v_snapshot_version
  FROM report_snapshots
  WHERE source_table = 'wht_export_periods'
    AND source_id = v_source_id
    AND snapshot_status = 'exported';

  v_report_payload := jsonb_build_object(
    'company_id', p_company_id,
    'report_type', v_report_type,
    'period_year', p_year,
    'period_quarter', p_quarter
  );

  IF v_report_type = 'QAP' THEN
    WITH
    detail_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.invoice_date, d.transaction_id, d.atc_code), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, invoice_date, supplier_id, supplier_tin, supplier_name,
               atc_code_id, atc_code, nature_of_payment, tax_rate, tax_base, tax_withheld
        FROM vw_ewt_summary_ap
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
      ) d
    ),
    summary_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.supplier_name, s.supplier_tin, s.atc_code, s.nature_of_payment), '[]'::jsonb) AS payload
      FROM (
        SELECT
          supplier_id,
          COALESCE(supplier_tin, '') AS supplier_tin,
          COALESCE(supplier_name, 'Unknown') AS supplier_name,
          atc_code_id,
          COALESCE(atc_code, '') AS atc_code,
          COALESCE(nature_of_payment, '') AS nature_of_payment,
          COALESCE(tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
          SUM(tax_base)::NUMERIC(15,2) AS tax_base,
          SUM(tax_withheld)::NUMERIC(15,2) AS tax_withheld,
          COUNT(*)::INTEGER AS source_row_count
        FROM vw_ewt_summary_ap
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
        GROUP BY supplier_id, COALESCE(supplier_tin, ''), COALESCE(supplier_name, 'Unknown'),
                 atc_code_id, COALESCE(atc_code, ''), COALESCE(nature_of_payment, ''), COALESCE(tax_rate, 0)
      ) s
    ),
    recon_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
      FROM (
        SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
               gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
        FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end)
      ) r
    ),
    f2307_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.supplier_name, r.supplier_tin, r.atc_code, r.nature_of_payment), '[]'::jsonb) AS payload
      FROM (
        SELECT *
        FROM fn_qap_2307_reconciliation(p_company_id, p_year, p_quarter)
      ) r
    )
    SELECT jsonb_build_object(
             'report', v_report_payload,
             'payee_detail_rows', detail_rows.payload,
             'payee_summary_rows', summary_rows.payload,
             'wht_gl_reconciliation', recon_rows.payload,
             'form2307_reconciliation', f2307_rows.payload
           ),
           detail_rows.row_count
    INTO v_source_payload, v_row_count
    FROM detail_rows, summary_rows, recon_rows, f2307_rows;
  ELSE
    WITH
    detail_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.receipt_date, d.transaction_id), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, source_doc_type, receipt_date, customer_id, customer_tin,
               customer_name, atc_code, nature_of_income, tax_rate, income_payment, cwt_withheld
        FROM vw_cwt_summary_ar
        WHERE company_id = p_company_id
          AND receipt_date BETWEEN v_start AND v_end
      ) d
    ),
    summary_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.customer_name, s.customer_tin), '[]'::jsonb) AS payload
      FROM (
        SELECT
          COALESCE(customer_tin, '') AS customer_tin,
          COALESCE(customer_name, 'Unknown') AS customer_name,
          SUM(income_payment)::NUMERIC(15,2) AS income_payments,
          SUM(cwt_withheld)::NUMERIC(15,2) AS cwt_withheld
        FROM vw_cwt_summary_ar
        WHERE company_id = p_company_id
          AND receipt_date BETWEEN v_start AND v_end
        GROUP BY COALESCE(customer_tin, ''), COALESCE(customer_name, 'Unknown')
      ) s
    ),
    recon_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
      FROM (
        SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
               gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
        FROM fn_wht_gl_reconciliation(p_company_id, v_start, v_end)
      ) r
    )
    SELECT jsonb_build_object(
             'report', v_report_payload,
             'payer_detail_rows', detail_rows.payload,
             'payer_summary_rows', summary_rows.payload,
             'wht_gl_reconciliation', recon_rows.payload
           ),
           detail_rows.row_count
    INTO v_source_payload, v_row_count
    FROM detail_rows, summary_rows, recon_rows;
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
    v_snapshot_id, p_company_id, v_report_type, 'wht_export_periods', v_source_id,
    'exported', v_snapshot_version, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  );

  RETURN v_snapshot_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_snapshot_wht_export(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

COMMENT ON FUNCTION fn_snapshot_wht_export(UUID, TEXT, INTEGER, INTEGER) IS
  'Creates an exported immutable report snapshot for SAWT/QAP withholding alphalists, with WHT/GL reconciliation; QAP summary rows are supplier+ATC+rate and include Form 2307 tie-out payload.';
