-- Immutable report snapshots, first slice: VAT returns (PXL-DA-015).
--
-- A final/filed VAT return now creates an append-only snapshot containing:
--   - the frozen return payload,
--   - the ledger-backed output/input VAT review source rows,
--   - VAT tax-ledger-to-GL reconciliation rows,
--   - a SHA-256 source hash over the canonical payload.
--
-- After any snapshot exists, period identity and amount fields on the return are
-- immutable. Metadata updates such as final -> filed, filed_date, reference_no,
-- and remarks remain allowed and create a separate filed snapshot.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS report_snapshots (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID NOT NULL REFERENCES companies(id),
  report_type         TEXT NOT NULL,
  source_table        TEXT NOT NULL,
  source_id           UUID NOT NULL,
  snapshot_status     TEXT NOT NULL CHECK (snapshot_status IN ('final','filed','exported','superseded')),
  snapshot_version    INTEGER NOT NULL DEFAULT 1,
  period_start        DATE NOT NULL,
  period_end          DATE NOT NULL,
  report_payload      JSONB NOT NULL,
  source_payload      JSONB NOT NULL,
  source_hash         TEXT NOT NULL,
  source_row_count    INTEGER NOT NULL DEFAULT 0,
  generated_by        UUID,
  generated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (source_table, source_id, snapshot_status, snapshot_version)
);

CREATE INDEX IF NOT EXISTS idx_report_snapshots_company_period
  ON report_snapshots (company_id, report_type, period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_report_snapshots_source
  ON report_snapshots (source_table, source_id);

ALTER TABLE report_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "report_snapshots_read" ON report_snapshots;
CREATE POLICY "report_snapshots_read" ON report_snapshots
  FOR SELECT TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS "report_snapshots_no_direct_insert" ON report_snapshots;
CREATE POLICY "report_snapshots_no_direct_insert" ON report_snapshots
  FOR INSERT TO authenticated WITH CHECK (false);

DROP POLICY IF EXISTS "report_snapshots_no_direct_update" ON report_snapshots;
CREATE POLICY "report_snapshots_no_direct_update" ON report_snapshots
  FOR UPDATE TO authenticated USING (false);

DROP POLICY IF EXISTS "report_snapshots_no_direct_delete" ON report_snapshots;
CREATE POLICY "report_snapshots_no_direct_delete" ON report_snapshots
  FOR DELETE TO authenticated USING (false);

GRANT SELECT, INSERT, UPDATE, DELETE ON report_snapshots TO authenticated;
GRANT ALL ON report_snapshots TO service_role;

CREATE OR REPLACE FUNCTION fn_vat_return_period_bounds(
  p_return_type TEXT,
  p_year INTEGER,
  p_month INTEGER,
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
  IF p_return_type = '2550M' THEN
    period_start := make_date(p_year, p_month, 1);
    period_end := (period_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  ELSIF p_return_type = '2550Q' THEN
    period_start := make_date(p_year, (p_quarter - 1) * 3 + 1, 1);
    period_end := (period_start + INTERVAL '3 months' - INTERVAL '1 day')::DATE;
  ELSE
    RAISE EXCEPTION 'Unsupported VAT return type: %', p_return_type;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_vat_return_report_payload(p_return vat_returns)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', p_return.id,
    'company_id', p_return.company_id,
    'return_type', p_return.return_type,
    'period_year', p_return.period_year,
    'period_month', p_return.period_month,
    'period_quarter', p_return.period_quarter,
    'output_taxable_sales', p_return.output_taxable_sales,
    'output_vat', p_return.output_vat,
    'zero_rated_sales', p_return.zero_rated_sales,
    'exempt_sales', p_return.exempt_sales,
    'input_taxable_purchases', p_return.input_taxable_purchases,
    'input_vat', p_return.input_vat,
    'input_vat_carried_over', p_return.input_vat_carried_over,
    'total_available_input_vat', p_return.total_available_input_vat,
    'net_vat_payable', p_return.net_vat_payable,
    'vat_paid_prior_months', p_return.vat_paid_prior_months,
    'vat_still_due', p_return.vat_still_due,
    'status', p_return.status,
    'filed_date', p_return.filed_date,
    'reference_no', p_return.reference_no
  );
$$;

CREATE OR REPLACE FUNCTION fn_guard_vat_return_snapshot_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM report_snapshots
    WHERE source_table = 'vat_returns'
      AND source_id = OLD.id
  ) AND (
    NEW.company_id IS DISTINCT FROM OLD.company_id OR
    NEW.return_type IS DISTINCT FROM OLD.return_type OR
    NEW.period_year IS DISTINCT FROM OLD.period_year OR
    NEW.period_month IS DISTINCT FROM OLD.period_month OR
    NEW.period_quarter IS DISTINCT FROM OLD.period_quarter OR
    NEW.output_taxable_sales IS DISTINCT FROM OLD.output_taxable_sales OR
    NEW.output_vat IS DISTINCT FROM OLD.output_vat OR
    NEW.zero_rated_sales IS DISTINCT FROM OLD.zero_rated_sales OR
    NEW.exempt_sales IS DISTINCT FROM OLD.exempt_sales OR
    NEW.input_taxable_purchases IS DISTINCT FROM OLD.input_taxable_purchases OR
    NEW.input_vat IS DISTINCT FROM OLD.input_vat OR
    NEW.input_vat_carried_over IS DISTINCT FROM OLD.input_vat_carried_over OR
    NEW.total_available_input_vat IS DISTINCT FROM OLD.total_available_input_vat OR
    NEW.net_vat_payable IS DISTINCT FROM OLD.net_vat_payable OR
    NEW.vat_paid_prior_months IS DISTINCT FROM OLD.vat_paid_prior_months OR
    NEW.vat_still_due IS DISTINCT FROM OLD.vat_still_due
  ) THEN
    RAISE EXCEPTION 'VAT return % has an immutable report snapshot; amend or supersede instead of changing filed/final source amounts.', OLD.id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_vat_return()
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
  IF NEW.status NOT IN ('final', 'filed') THEN
    RETURN NEW;
  END IF;

  SELECT period_start, period_end
  INTO v_start, v_end
  FROM fn_vat_return_period_bounds(
    NEW.return_type, NEW.period_year, NEW.period_month, NEW.period_quarter
  );

  v_report_payload := fn_vat_return_report_payload(NEW);

  WITH
  output_rows AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.invoice_date, o.source_module, o.system_no, o.transaction_id), '[]'::jsonb) AS payload
    FROM (
      SELECT transaction_id, source_module, invoice_date, customer_tin, customer_name,
             system_no, gross_sales, exempt_sales, zero_rated_sales, taxable_base, output_vat
      FROM vw_output_vat_review
      WHERE company_id = NEW.company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) o
  ),
  input_rows AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.invoice_date, i.source_module, i.system_no, i.transaction_id), '[]'::jsonb) AS payload
    FROM (
      SELECT transaction_id, source_module, invoice_date, supplier_tin, supplier_name,
             invoice_no, system_no, gross_purchases, exempt_purchases, zero_rated,
             taxable_base, input_vat
      FROM vw_input_vat_review
      WHERE company_id = NEW.company_id
        AND invoice_date BETWEEN v_start AND v_end
    ) i
  ),
  recon_rows AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.tax_kind), '[]'::jsonb) AS payload
    FROM (
      SELECT tax_kind, ledger_tax_base, ledger_tax_amount, gl_account_id,
             gl_account_code, gl_account_name, gl_amount, variance, is_reconciled
      FROM fn_vat_gl_reconciliation(NEW.company_id, v_start, v_end)
    ) r
  ),
  tax_rows AS (
    SELECT COUNT(*)::INTEGER AS row_count
    FROM tax_detail_entries
    WHERE company_id = NEW.company_id
      AND tax_kind IN ('output_vat', 'input_vat')
      AND document_date BETWEEN v_start AND v_end
  )
  SELECT jsonb_build_object(
           'report', v_report_payload,
           'output_vat_review', output_rows.payload,
           'input_vat_review', input_rows.payload,
           'vat_gl_reconciliation', recon_rows.payload
         ),
         tax_rows.row_count
  INTO v_source_payload, v_row_count
  FROM output_rows, input_rows, recon_rows, tax_rows;

  v_source_hash := encode(extensions.digest(convert_to(v_source_payload::text, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO report_snapshots (
    company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count,
    generated_by
  )
  VALUES (
    NEW.company_id, NEW.return_type, 'vat_returns', NEW.id,
    NEW.status, 1, v_start, v_end,
    v_report_payload, v_source_payload, v_source_hash, v_row_count,
    auth.uid()
  )
  ON CONFLICT (source_table, source_id, snapshot_status, snapshot_version)
  DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vat_return_snapshot_guard ON vat_returns;
CREATE TRIGGER trg_vat_return_snapshot_guard
  BEFORE UPDATE ON vat_returns
  FOR EACH ROW EXECUTE FUNCTION fn_guard_vat_return_snapshot_immutable();

DROP TRIGGER IF EXISTS trg_vat_return_snapshot ON vat_returns;
CREATE TRIGGER trg_vat_return_snapshot
  AFTER INSERT OR UPDATE ON vat_returns
  FOR EACH ROW EXECUTE FUNCTION fn_snapshot_vat_return();

COMMENT ON TABLE report_snapshots IS
  'Append-only compliance report snapshot table. PXL-DA-015 provenance source for filed/final/exported outputs.';
COMMENT ON COLUMN report_snapshots.source_hash IS
  'SHA-256 hash of the canonical source_payload JSONB text at snapshot creation time.';
