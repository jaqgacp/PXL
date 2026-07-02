-- ══════════════════════════════════════════════════════════════════════════════
-- FORM 2307 ISSUED: certificate version/supersede workflow (PXL-AUD-015)
--
-- Sent/acknowledged certificates are locked from regeneration, but withholding
-- data can legitimately change after issuance (late PV, correction). This adds
-- a controlled supersede: a new version is generated from current EWT detail,
-- the old certificate is preserved as immutable evidence in 'superseded'
-- status, and both are linked. Uniqueness moves from all certificates to the
-- single active (non-superseded) certificate per company/supplier/quarter.
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE form_2307_issuances
  ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS supersedes_issuance_id UUID REFERENCES form_2307_issuances(id),
  ADD COLUMN IF NOT EXISTS superseded_by_issuance_id UUID REFERENCES form_2307_issuances(id),
  ADD COLUMN IF NOT EXISTS superseded_at TIMESTAMPTZ;

ALTER TABLE form_2307_issuances DROP CONSTRAINT IF EXISTS form_2307_issuances_status_check;
ALTER TABLE form_2307_issuances ADD CONSTRAINT form_2307_issuances_status_check
  CHECK (status IN ('pending', 'generated', 'sent', 'acknowledged', 'superseded'));

-- Replace whole-history uniqueness with active-certificate uniqueness.
DO $$
DECLARE v_name TEXT;
BEGIN
  SELECT conname INTO v_name
  FROM pg_constraint
  WHERE conrelid = 'form_2307_issuances'::regclass
    AND contype = 'u';
  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE form_2307_issuances DROP CONSTRAINT %I', v_name);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_f2307_active_certificate
  ON form_2307_issuances (company_id, supplier_id, tax_year, tax_quarter)
  WHERE status <> 'superseded';

-- ── Generation: superseded certificates are history, not conflicts ─────────────

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

-- ── Controlled supersede: new version from current EWT detail ──────────────────

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
  v_end_exclusive DATE;
  v_rows INT := 0;
BEGIN
  SELECT * INTO v_old
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
  v_end_exclusive := v_start_date + INTERVAL '3 months';

  DROP TABLE IF EXISTS pg_temp.tmp_f2307_ss_source;
  CREATE TEMP TABLE tmp_f2307_ss_source ON COMMIT DROP AS
  SELECT
    atc_code_id,
    atc_code,
    supplier_tin,
    nature_of_payment,
    COALESCE(tax_rate, 0)::NUMERIC(5,2) AS tax_rate,
    SUM(COALESCE(tax_base, 0))::NUMERIC(15,2) AS tax_base,
    SUM(COALESCE(tax_withheld, 0))::NUMERIC(15,2) AS tax_withheld
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

  -- Retire the old certificate first so the active-certificate unique index
  -- accepts the replacement version.
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
    tax_base, tax_rate, tax_withheld
  )
  SELECT
    v_new_id, v_old.company_id, atc_code_id, atc_code,
    COALESCE(nature_of_payment, ''),
    tax_base, tax_rate, tax_withheld
  FROM tmp_f2307_ss_source;

  UPDATE form_2307_issuances
  SET superseded_by_issuance_id = v_new_id
  WHERE id = v_old.id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_supersede_form_2307_issued(UUID, TEXT) TO authenticated;
