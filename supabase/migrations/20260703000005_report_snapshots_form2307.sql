-- Immutable report snapshots, second slice: Form 2307 issued (PXL-DA-015).
--
-- Generated certificates remain refreshable until sent. Once a Form 2307
-- certificate is sent or acknowledged, a report_snapshots row captures:
--   - the frozen certificate header,
--   - certificate ATC lines,
--   - current EWT source rows for the supplier/quarter,
--   - a SHA-256 source hash over that canonical payload.
--
-- After a sent/acknowledged snapshot exists, certificate identity and amount
-- fields are immutable. Supersede metadata remains allowed so controlled
-- replacement can preserve the old certificate and create a new active version.

CREATE OR REPLACE FUNCTION fn_form2307_period_bounds(
  p_year INTEGER,
  p_quarter INTEGER,
  OUT period_start DATE,
  OUT period_end DATE
)
RETURNS RECORD
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid Form 2307 quarter: %', p_quarter;
  END IF;

  period_start := make_date(p_year, (p_quarter - 1) * 3 + 1, 1);
  period_end := (period_start + INTERVAL '3 months' - INTERVAL '1 day')::DATE;
END;
$$;

CREATE OR REPLACE FUNCTION fn_form2307_report_payload(p_issuance form_2307_issuances)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', p_issuance.id,
    'company_id', p_issuance.company_id,
    'supplier_id', p_issuance.supplier_id,
    'tax_year', p_issuance.tax_year,
    'tax_quarter', p_issuance.tax_quarter,
    'total_tax_base', p_issuance.total_tax_base,
    'total_ewt', p_issuance.total_ewt,
    'status', p_issuance.status,
    'version', p_issuance.version,
    'date_generated', p_issuance.date_generated,
    'date_sent', p_issuance.date_sent,
    'date_acknowledged', p_issuance.date_acknowledged,
    'supersedes_issuance_id', p_issuance.supersedes_issuance_id,
    'superseded_by_issuance_id', p_issuance.superseded_by_issuance_id,
    'superseded_at', p_issuance.superseded_at
  );
$$;

CREATE OR REPLACE FUNCTION fn_guard_form2307_snapshot_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM report_snapshots
    WHERE source_table = 'form_2307_issuances'
      AND source_id = OLD.id
      AND snapshot_status IN ('sent', 'acknowledged')
  ) AND (
    NEW.company_id IS DISTINCT FROM OLD.company_id OR
    NEW.supplier_id IS DISTINCT FROM OLD.supplier_id OR
    NEW.tax_year IS DISTINCT FROM OLD.tax_year OR
    NEW.tax_quarter IS DISTINCT FROM OLD.tax_quarter OR
    NEW.total_tax_base IS DISTINCT FROM OLD.total_tax_base OR
    NEW.total_ewt IS DISTINCT FROM OLD.total_ewt OR
    NEW.version IS DISTINCT FROM OLD.version OR
    NEW.supersedes_issuance_id IS DISTINCT FROM OLD.supersedes_issuance_id
  ) THEN
    RAISE EXCEPTION 'Form 2307 issuance % has an immutable report snapshot; supersede instead of changing issued certificate amounts or identity.', OLD.id;
  END IF;

  RETURN NEW;
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

ALTER TABLE report_snapshots DROP CONSTRAINT IF EXISTS report_snapshots_snapshot_status_check;
ALTER TABLE report_snapshots ADD CONSTRAINT report_snapshots_snapshot_status_check
  CHECK (snapshot_status IN ('final','filed','sent','acknowledged','exported','superseded'));

DROP TRIGGER IF EXISTS trg_form2307_snapshot_guard ON form_2307_issuances;
CREATE TRIGGER trg_form2307_snapshot_guard
  BEFORE UPDATE ON form_2307_issuances
  FOR EACH ROW EXECUTE FUNCTION fn_guard_form2307_snapshot_immutable();

DROP TRIGGER IF EXISTS trg_form2307_snapshot ON form_2307_issuances;
CREATE TRIGGER trg_form2307_snapshot
  AFTER INSERT OR UPDATE ON form_2307_issuances
  FOR EACH ROW EXECUTE FUNCTION fn_snapshot_form2307_issued();
