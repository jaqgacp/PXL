-- ══════════════════════════════════════════════════════════════════════════════
-- FORM 2307 ISSUED: server-side generation and status transitions
-- Finding coverage: PXL-AUD-015.
-- ══════════════════════════════════════════════════════════════════════════════

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
  v_end_exclusive DATE;
  v_rows INT := 0;
  v_generated INT := 0;
  v_locked INT := 0;
BEGIN
  IF p_tax_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid tax quarter: %', p_tax_quarter;
  END IF;

  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: owner/admin role required to generate Form 2307 certificates';
  END IF;

  v_start_date := make_date(p_tax_year, ((p_tax_quarter - 1) * 3) + 1, 1);
  v_end_exclusive := v_start_date + INTERVAL '3 months';

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
    SUM(COALESCE(tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld
  FROM vw_ewt_summary_ap
  WHERE company_id = p_company_id
    AND invoice_date >= v_start_date
    AND invoice_date < v_end_exclusive
  GROUP BY supplier_id, supplier_name, supplier_tin, atc_code_id, atc_code, nature_of_payment, COALESCE(tax_rate, 0);

  SELECT COUNT(*) INTO v_rows FROM tmp_f2307_source;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'No EWT data found for Q% %', p_tax_quarter, p_tax_year;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_f2307_source
    WHERE supplier_id IS NULL
       OR NULLIF(BTRIM(COALESCE(supplier_tin, '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(atc_code, '')), '') IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot generate Form 2307: supplier, supplier TIN, and ATC are required for every EWT detail row';
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
    tax_base, tax_rate, tax_withheld
  )
  SELECT
    w.id, p_company_id, s.atc_code_id, s.atc_code,
    COALESCE(s.nature_of_payment, ''),
    s.tax_base, s.tax_rate, s.tax_withheld
  FROM tmp_f2307_source s
  JOIN tmp_f2307_written w ON w.supplier_id = s.supplier_id;

  RETURN jsonb_build_object(
    'generated_count', v_generated,
    'skipped_locked_count', v_locked
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_update_form_2307_issued_status(
  p_issuance_id UUID,
  p_status TEXT,
  p_action_date DATE DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_issuance form_2307_issuances%ROWTYPE;
BEGIN
  IF p_status NOT IN ('sent', 'acknowledged') THEN
    RAISE EXCEPTION 'Invalid Form 2307 status transition: %', p_status;
  END IF;

  SELECT * INTO v_issuance
  FROM form_2307_issuances
  WHERE id = p_issuance_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Form 2307 issuance not found: %', p_issuance_id;
  END IF;

  IF NOT can_admin_company(v_issuance.company_id) THEN
    RAISE EXCEPTION 'Access denied: owner/admin role required to update Form 2307 status';
  END IF;

  IF p_status = 'sent' AND v_issuance.status <> 'generated' THEN
    RAISE EXCEPTION 'Only generated Form 2307 certificates can be marked sent';
  END IF;

  IF p_status = 'acknowledged' AND v_issuance.status <> 'sent' THEN
    RAISE EXCEPTION 'Only sent Form 2307 certificates can be acknowledged';
  END IF;

  IF p_status = 'sent' THEN
    UPDATE form_2307_issuances
    SET status = 'sent',
        date_sent = p_action_date,
        updated_by = auth.uid()
    WHERE id = p_issuance_id;
  ELSE
    UPDATE form_2307_issuances
    SET status = 'acknowledged',
        date_acknowledged = p_action_date,
        updated_by = auth.uid()
    WHERE id = p_issuance_id;
  END IF;

  RETURN p_issuance_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_generate_form_2307_issued(UUID, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_update_form_2307_issued_status(UUID, TEXT, DATE) TO authenticated;

-- Direct writes are intentionally closed; generation/status changes must route
-- through the RPCs above so sent/acknowledged certificates remain locked.
DROP POLICY IF EXISTS "f2307_insert" ON form_2307_issuances;
DROP POLICY IF EXISTS "f2307_update" ON form_2307_issuances;
DROP POLICY IF EXISTS "f2307_insert_rpc_only" ON form_2307_issuances;
CREATE POLICY "f2307_insert_rpc_only" ON form_2307_issuances
  FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS "f2307_update_rpc_only" ON form_2307_issuances;
CREATE POLICY "f2307_update_rpc_only" ON form_2307_issuances
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS "f2307l_insert" ON form_2307_issuance_lines;
DROP POLICY IF EXISTS "f2307l_delete" ON form_2307_issuance_lines;
DROP POLICY IF EXISTS "f2307l_insert_rpc_only" ON form_2307_issuance_lines;
CREATE POLICY "f2307l_insert_rpc_only" ON form_2307_issuance_lines
  FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS "f2307l_delete_rpc_only" ON form_2307_issuance_lines;
CREATE POLICY "f2307l_delete_rpc_only" ON form_2307_issuance_lines
  FOR DELETE TO authenticated USING (false);

DO $$
BEGIN
  IF to_regprocedure('fn_audit_trigger()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_audit_form_2307_issuances ON form_2307_issuances;
    CREATE TRIGGER trg_audit_form_2307_issuances
      AFTER INSERT OR UPDATE OR DELETE ON form_2307_issuances
      FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

    DROP TRIGGER IF EXISTS trg_audit_form_2307_issuance_lines ON form_2307_issuance_lines;
    CREATE TRIGGER trg_audit_form_2307_issuance_lines
      AFTER INSERT OR UPDATE OR DELETE ON form_2307_issuance_lines
      FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();
  END IF;
END;
$$;
