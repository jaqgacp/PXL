-- PXL-AUD-040: Form 2307 issued monthly breakdown.
--
-- The certificate line contract used to store only the quarter total per
-- supplier + ATC + income nature + rate. BIR Form 2307 needs the income payment
-- split across the 1st, 2nd, and 3rd months of the quarter, so generated and
-- superseded certificates now retain those buckets directly on the line.

ALTER TABLE form_2307_issuance_lines
  ADD COLUMN IF NOT EXISTS month_1_tax_base NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS month_1_tax_withheld NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS month_2_tax_base NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS month_2_tax_withheld NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS month_3_tax_base NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS month_3_tax_withheld NUMERIC(15,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION fn_generate_form_2307_issued(
  p_company_id UUID,
  p_tax_year INT,
  p_tax_quarter INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_date DATE;
  v_month_2_start DATE;
  v_month_3_start DATE;
  v_end_exclusive DATE;
  v_rows INT := 0;
  v_generated INT := 0;
  v_locked INT := 0;
  v_unlinked INT := 0;
  v_unlinked_ewt NUMERIC(15,2) := 0;
BEGIN
  IF p_tax_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid tax quarter: %', p_tax_quarter;
  END IF;

  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: owner/admin role required to generate Form 2307 certificates';
  END IF;

  v_start_date := make_date(p_tax_year, ((p_tax_quarter - 1) * 3) + 1, 1);
  v_month_2_start := (v_start_date + INTERVAL '1 month')::DATE;
  v_month_3_start := (v_start_date + INTERVAL '2 months')::DATE;
  v_end_exclusive := (v_start_date + INTERVAL '3 months')::DATE;

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_source;
  CREATE TEMP TABLE tmp_f2307_source ON COMMIT DROP AS
  SELECT
    supplier_id,
    supplier_name,
    supplier_tin,
    atc_code_id,
    atc_code,
    nature_of_payment,
    COALESCE(tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
    SUM(COALESCE(tax_base, 0))::NUMERIC(15,2) AS tax_base,
    SUM(COALESCE(tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld,
    SUM(CASE WHEN invoice_date >= v_start_date AND invoice_date < v_month_2_start
             THEN COALESCE(tax_base, 0) ELSE 0 END)::NUMERIC(15,2) AS month_1_tax_base,
    SUM(CASE WHEN invoice_date >= v_start_date AND invoice_date < v_month_2_start
             THEN COALESCE(tax_withheld, 0) ELSE 0 END)::NUMERIC(15,2) AS month_1_tax_withheld,
    SUM(CASE WHEN invoice_date >= v_month_2_start AND invoice_date < v_month_3_start
             THEN COALESCE(tax_base, 0) ELSE 0 END)::NUMERIC(15,2) AS month_2_tax_base,
    SUM(CASE WHEN invoice_date >= v_month_2_start AND invoice_date < v_month_3_start
             THEN COALESCE(tax_withheld, 0) ELSE 0 END)::NUMERIC(15,2) AS month_2_tax_withheld,
    SUM(CASE WHEN invoice_date >= v_month_3_start AND invoice_date < v_end_exclusive
             THEN COALESCE(tax_base, 0) ELSE 0 END)::NUMERIC(15,2) AS month_3_tax_base,
    SUM(CASE WHEN invoice_date >= v_month_3_start AND invoice_date < v_end_exclusive
             THEN COALESCE(tax_withheld, 0) ELSE 0 END)::NUMERIC(15,2) AS month_3_tax_withheld
  FROM vw_ewt_summary_ap
  WHERE company_id = p_company_id
    AND invoice_date >= v_start_date
    AND invoice_date < v_end_exclusive
  GROUP BY supplier_id, supplier_name, supplier_tin, atc_code_id, atc_code, nature_of_payment, COALESCE(tax_rate, 0);

  SELECT COUNT(*), COALESCE(SUM(tax_withheld), 0)
  INTO v_unlinked, v_unlinked_ewt
  FROM tmp_f2307_source
  WHERE supplier_id IS NULL;

  DELETE FROM tmp_f2307_source WHERE supplier_id IS NULL;

  SELECT COUNT(*) INTO v_rows FROM tmp_f2307_source;
  IF v_rows = 0 THEN
    IF v_unlinked > 0 THEN
      RAISE EXCEPTION 'Cannot generate Form 2307: every EWT row in Q% % is missing a supplier link. Link the source documents to suppliers first.',
        p_tax_quarter, p_tax_year;
    END IF;
    RAISE EXCEPTION 'No EWT data found for Q% %', p_tax_quarter, p_tax_year;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_f2307_source
    WHERE NULLIF(BTRIM(COALESCE(supplier_tin, '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(atc_code, '')), '') IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot generate Form 2307: supplier TIN and ATC are required for every EWT detail row';
  END IF;

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_supplier_totals;
  CREATE TEMP TABLE tmp_f2307_supplier_totals ON COMMIT DROP AS
  SELECT
    supplier_id,
    SUM(tax_base)::NUMERIC(15,2) AS total_tax_base,
    SUM(tax_withheld)::NUMERIC(15,2) AS total_ewt
  FROM tmp_f2307_source
  GROUP BY supplier_id;

  SELECT COUNT(*) INTO v_locked
  FROM tmp_f2307_supplier_totals st
  JOIN form_2307_issuances f
    ON f.company_id = p_company_id
   AND f.supplier_id = st.supplier_id
   AND f.tax_year = p_tax_year
   AND f.tax_quarter = p_tax_quarter
   AND f.status <> 'superseded'
  WHERE f.status IN ('sent', 'acknowledged');

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_written;
  CREATE TEMP TABLE tmp_f2307_written ON COMMIT DROP AS
  WITH writeable AS (
    SELECT st.*
    FROM tmp_f2307_supplier_totals st
    LEFT JOIN form_2307_issuances f
      ON f.company_id = p_company_id
     AND f.supplier_id = st.supplier_id
     AND f.tax_year = p_tax_year
     AND f.tax_quarter = p_tax_quarter
     AND f.status <> 'superseded'
    WHERE f.id IS NULL OR f.status IN ('pending', 'generated')
  ),
  upserted AS (
    INSERT INTO form_2307_issuances (
      company_id, supplier_id, tax_year, tax_quarter,
      total_tax_base, total_ewt, status, date_generated,
      date_sent, date_acknowledged, created_by, updated_by
    )
    SELECT
      p_company_id, supplier_id, p_tax_year, p_tax_quarter,
      total_tax_base, total_ewt, 'generated', NOW(),
      NULL, NULL, auth.uid(), auth.uid()
    FROM writeable
    ON CONFLICT (company_id, supplier_id, tax_year, tax_quarter)
      WHERE status <> 'superseded'
    DO UPDATE SET
      total_tax_base = EXCLUDED.total_tax_base,
      total_ewt = EXCLUDED.total_ewt,
      status = 'generated',
      date_generated = NOW(),
      date_sent = NULL,
      date_acknowledged = NULL,
      updated_by = auth.uid()
    WHERE form_2307_issuances.status IN ('pending', 'generated')
    RETURNING id, supplier_id
  )
  SELECT id, supplier_id FROM upserted;

  SELECT COUNT(*) INTO v_generated FROM tmp_f2307_written;

  DELETE FROM form_2307_issuance_lines l
  USING tmp_f2307_written w
  WHERE l.issuance_id = w.id;

  INSERT INTO form_2307_issuance_lines (
    issuance_id, company_id, atc_code_id, atc_code, nature_of_income,
    month_1_tax_base, month_1_tax_withheld,
    month_2_tax_base, month_2_tax_withheld,
    month_3_tax_base, month_3_tax_withheld,
    tax_base, tax_rate, tax_withheld
  )
  SELECT
    w.id, p_company_id, s.atc_code_id, s.atc_code,
    COALESCE(s.nature_of_payment, ''),
    s.month_1_tax_base, s.month_1_tax_withheld,
    s.month_2_tax_base, s.month_2_tax_withheld,
    s.month_3_tax_base, s.month_3_tax_withheld,
    s.tax_base, s.tax_rate, s.tax_withheld
  FROM tmp_f2307_source s
  JOIN tmp_f2307_written w ON w.supplier_id = s.supplier_id;

  RETURN jsonb_build_object(
    'generated_count', v_generated,
    'skipped_locked_count', v_locked,
    'skipped_unlinked_count', v_unlinked,
    'skipped_unlinked_ewt', v_unlinked_ewt
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_supersede_form_2307_issued(
  p_issuance_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old form_2307_issuances%ROWTYPE;
  v_new_id UUID;
  v_start_date DATE;
  v_month_2_start DATE;
  v_month_3_start DATE;
  v_end_exclusive DATE;
  v_rows INT;
BEGIN
  SELECT *
  INTO v_old
  FROM form_2307_issuances
  WHERE id = p_issuance_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Form 2307 issuance not found: %', p_issuance_id;
  END IF;
  IF NOT can_admin_company(v_old.company_id) THEN
    RAISE EXCEPTION 'Access denied: owner/admin role required to supersede Form 2307 certificates';
  END IF;
  IF v_old.status NOT IN ('sent', 'acknowledged') THEN
    RAISE EXCEPTION 'Only sent or acknowledged Form 2307 certificates can be superseded (current status: %). Regenerate the quarter instead.',
      v_old.status;
  END IF;

  v_start_date := make_date(v_old.tax_year, ((v_old.tax_quarter - 1) * 3) + 1, 1);
  v_month_2_start := (v_start_date + INTERVAL '1 month')::DATE;
  v_month_3_start := (v_start_date + INTERVAL '2 months')::DATE;
  v_end_exclusive := (v_start_date + INTERVAL '3 months')::DATE;

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_ss_source;
  CREATE TEMP TABLE tmp_f2307_ss_source ON COMMIT DROP AS
  SELECT
    atc_code_id,
    atc_code,
    supplier_tin,
    nature_of_payment,
    COALESCE(tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
    SUM(COALESCE(tax_base, 0))::NUMERIC(15,2) AS tax_base,
    SUM(COALESCE(tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld,
    SUM(CASE WHEN invoice_date >= v_start_date AND invoice_date < v_month_2_start
             THEN COALESCE(tax_base, 0) ELSE 0 END)::NUMERIC(15,2) AS month_1_tax_base,
    SUM(CASE WHEN invoice_date >= v_start_date AND invoice_date < v_month_2_start
             THEN COALESCE(tax_withheld, 0) ELSE 0 END)::NUMERIC(15,2) AS month_1_tax_withheld,
    SUM(CASE WHEN invoice_date >= v_month_2_start AND invoice_date < v_month_3_start
             THEN COALESCE(tax_base, 0) ELSE 0 END)::NUMERIC(15,2) AS month_2_tax_base,
    SUM(CASE WHEN invoice_date >= v_month_2_start AND invoice_date < v_month_3_start
             THEN COALESCE(tax_withheld, 0) ELSE 0 END)::NUMERIC(15,2) AS month_2_tax_withheld,
    SUM(CASE WHEN invoice_date >= v_month_3_start AND invoice_date < v_end_exclusive
             THEN COALESCE(tax_base, 0) ELSE 0 END)::NUMERIC(15,2) AS month_3_tax_base,
    SUM(CASE WHEN invoice_date >= v_month_3_start AND invoice_date < v_end_exclusive
             THEN COALESCE(tax_withheld, 0) ELSE 0 END)::NUMERIC(15,2) AS month_3_tax_withheld
  FROM vw_ewt_summary_ap
  WHERE company_id = v_old.company_id
    AND supplier_id = v_old.supplier_id
    AND invoice_date >= v_start_date
    AND invoice_date < v_end_exclusive
  GROUP BY atc_code_id, atc_code, supplier_tin, nature_of_payment, COALESCE(tax_rate, 0);

  SELECT COUNT(*) INTO v_rows FROM tmp_f2307_ss_source;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Cannot supersede: no EWT detail remains for this supplier in Q% %',
      v_old.tax_quarter, v_old.tax_year;
  END IF;

  IF EXISTS (
    SELECT 1 FROM tmp_f2307_ss_source
    WHERE NULLIF(BTRIM(COALESCE(supplier_tin, '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(atc_code, '')), '') IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot supersede Form 2307: supplier TIN and ATC are required for every EWT detail row';
  END IF;

  UPDATE form_2307_issuances
  SET status = 'superseded',
      superseded_at = NOW(),
      updated_by = auth.uid()
  WHERE id = v_old.id;

  INSERT INTO form_2307_issuances (
    company_id, supplier_id, tax_year, tax_quarter,
    total_tax_base, total_ewt, status, date_generated,
    version, supersedes_issuance_id, remarks,
    created_by, updated_by
  )
  SELECT
    v_old.company_id, v_old.supplier_id, v_old.tax_year, v_old.tax_quarter,
    SUM(tax_base), SUM(tax_withheld), 'generated', NOW(),
    v_old.version + 1, v_old.id, NULLIF(BTRIM(COALESCE(p_reason, '')), ''),
    auth.uid(), auth.uid()
  FROM tmp_f2307_ss_source
  RETURNING id INTO v_new_id;

  INSERT INTO form_2307_issuance_lines (
    issuance_id, company_id, atc_code_id, atc_code, nature_of_income,
    month_1_tax_base, month_1_tax_withheld,
    month_2_tax_base, month_2_tax_withheld,
    month_3_tax_base, month_3_tax_withheld,
    tax_base, tax_rate, tax_withheld
  )
  SELECT
    v_new_id, v_old.company_id, atc_code_id, atc_code,
    COALESCE(nature_of_payment, ''),
    month_1_tax_base, month_1_tax_withheld,
    month_2_tax_base, month_2_tax_withheld,
    month_3_tax_base, month_3_tax_withheld,
    tax_base, tax_rate, tax_withheld
  FROM tmp_f2307_ss_source;

  UPDATE form_2307_issuances
  SET superseded_by_issuance_id = v_new_id
  WHERE id = v_old.id;

  RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_form2307_issued()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start DATE;
  v_end DATE;
  v_report_payload JSONB;
  v_source_payload JSONB;
  v_source_hash TEXT;
  v_row_count INTEGER;
BEGIN
  IF NEW.status NOT IN ('sent', 'acknowledged') THEN
    RETURN NEW;
  END IF;

  SELECT period_start, period_end
  INTO v_start, v_end
  FROM fn_form2307_period_bounds(NEW.tax_year, NEW.tax_quarter);

  v_report_payload := fn_form2307_report_payload(NEW);

  WITH
  cert_lines AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.atc_code, l.nature_of_income, l.id), '[]'::jsonb) AS payload,
           COUNT(*)::INTEGER AS row_count
    FROM (
      SELECT id, atc_code_id, atc_code, nature_of_income,
             month_1_tax_base, month_1_tax_withheld,
             month_2_tax_base, month_2_tax_withheld,
             month_3_tax_base, month_3_tax_withheld,
             tax_base, tax_rate, tax_withheld
      FROM form_2307_issuance_lines
      WHERE issuance_id = NEW.id
    ) l
  ),
  source_rows AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.invoice_date, s.atc_code, s.tax_base, s.tax_withheld), '[]'::jsonb) AS payload
    FROM (
      SELECT transaction_id, invoice_date, supplier_id, supplier_tin, supplier_name,
             atc_code_id, atc_code, nature_of_payment, tax_rate, tax_base, tax_withheld
      FROM vw_ewt_summary_ap
      WHERE company_id = NEW.company_id
        AND supplier_id = NEW.supplier_id
        AND invoice_date BETWEEN v_start AND v_end
    ) s
  )
  SELECT jsonb_build_object(
           'report', v_report_payload,
           'certificate_lines', cert_lines.payload,
           'ewt_source_rows', source_rows.payload
         ),
         cert_lines.row_count
  INTO v_source_payload, v_row_count
  FROM cert_lines, source_rows;

  v_source_hash := encode(extensions.digest(convert_to(v_source_payload::text, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO report_snapshots (
    company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count,
    generated_by
  )
  VALUES (
    NEW.company_id, 'FORM_2307_ISSUED', 'form_2307_issuances', NEW.id,
    NEW.status, NEW.version, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  )
  ON CONFLICT (source_table, source_id, snapshot_status, snapshot_version)
  DO NOTHING;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_generate_form_2307_issued(UUID, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_supersede_form_2307_issued(UUID, TEXT) TO authenticated;
