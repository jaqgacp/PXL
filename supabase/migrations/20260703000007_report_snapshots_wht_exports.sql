-- Immutable report snapshots, fourth slice: withholding tax alphalist exports
-- (PXL-DA-015): SAWT (CWT withheld by customers, ITR attachment) and QAP
-- (EWT withheld from suppliers, 1601EQ attachment).
--
-- SAWT and QAP were previously browser-only CSV downloads; SAWT additionally
-- aggregated receipt_lines through sales_invoices, so cash-sale CWT rows never
-- reached the alphalist. This migration adds:
--   1. vw_cwt_summary_ar - ledger-backed CWT source view (mirror of
--      vw_ewt_summary_ap), so SAWT reads the same tax ledger evidence that
--      reconciles to the GL, including cash-sale CWT.
--   2. fn_wht_gl_reconciliation - tax-ledger-to-GL comparison for ewt_payable
--      (EWT Payable control account, credit-normal) and cwt_receivable
--      (CWT/EWT-withheld control account, debit-normal), same shape and
--      semantics as fn_vat_gl_reconciliation.
--   3. fn_snapshot_wht_export - append-only exported snapshot per company/
--      report/quarter with deterministic logical source id, incrementing
--      export versions, SHA-256 source hash, and reconciliation blocking on
--      the report's own control account.
--
-- Same caveat as the VAT slice: legitimate remittance JEs on the withholding
-- control accounts (0619-E/1601EQ payments) will surface as variance until a
-- controlled remittance flow exists; they require tax-detail support or a
-- controlled process by design.

-- ── 1. Ledger-backed CWT source view (SAWT) ────────────────────────────────────
-- Mirrors vw_ewt_summary_ap: active withholding only - reversed originals and
-- their counter-rows both disappear. security_invoker so base-table RLS applies.

CREATE OR REPLACE VIEW vw_cwt_summary_ar
WITH (security_invoker = true) AS
SELECT
  tde.source_doc_id     AS transaction_id,
  tde.source_doc_type,
  tde.company_id,
  tde.document_date     AS receipt_date,
  tde.counterparty_id   AS customer_id,
  tde.counterparty_tin  AS customer_tin,
  tde.counterparty_name AS customer_name,
  tde.atc_code_id,
  ac.code               AS atc_code,
  COALESCE(NULLIF(tde.income_nature, ''), ac.description) AS nature_of_income,
  tde.tax_rate,
  tde.tax_base          AS income_payment,
  tde.tax_amount        AS cwt_withheld
FROM tax_detail_entries tde
LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
WHERE tde.tax_kind = 'cwt_receivable'
  AND tde.is_reversal = false
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = tde.id
  );

GRANT SELECT ON vw_cwt_summary_ar TO authenticated;

COMMENT ON VIEW vw_cwt_summary_ar IS
  'Ledger-backed CWT-withheld-on-collections source rows (SAWT); active withholding only, reversed pairs excluded.';

-- ── 2. Withholding tax-ledger-to-GL reconciliation ─────────────────────────────

CREATE OR REPLACE FUNCTION fn_wht_gl_reconciliation(
  p_company_id UUID,
  p_date_from  DATE,
  p_date_to    DATE
)
RETURNS TABLE (
  tax_kind          TEXT,
  ledger_tax_base   NUMERIC(15,2),
  ledger_tax_amount NUMERIC(15,2),
  gl_account_id     UUID,
  gl_account_code   TEXT,
  gl_account_name   TEXT,
  gl_amount         NUMERIC(15,2),
  variance          NUMERIC(15,2),
  is_reconciled     BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg company_accounting_config%ROWTYPE;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid reconciliation date range % to %', p_date_from, p_date_to;
  END IF;

  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = p_company_id;

  RETURN QUERY
  WITH ledger AS (
    SELECT tde.tax_kind AS kind,
           COALESCE(SUM(tde.tax_base), 0)::NUMERIC(15,2)   AS base_sum,
           COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS tax_sum
    FROM tax_detail_entries tde
    WHERE tde.company_id = p_company_id
      AND tde.tax_kind IN ('ewt_payable', 'cwt_receivable')
      AND tde.document_date BETWEEN p_date_from AND p_date_to
    GROUP BY tde.tax_kind
  ),
  kinds AS (
    SELECT 'cwt_receivable'::TEXT AS kind, v_cfg.ewt_withheld_account_id AS account_id, 'debit'::TEXT AS normal
    UNION ALL
    SELECT 'ewt_payable'::TEXT,            v_cfg.ewt_payable_account_id,               'credit'::TEXT
  ),
  gl AS (
    SELECT k.kind,
           k.account_id,
           CASE WHEN k.account_id IS NULL THEN NULL
                ELSE (
                  SELECT COALESCE(SUM(
                    CASE WHEN k.normal = 'credit'
                         THEN jel.credit_amount - jel.debit_amount
                         ELSE jel.debit_amount - jel.credit_amount END), 0)
                  FROM journal_entry_lines jel
                  JOIN journal_entries je ON je.id = jel.je_id
                  WHERE jel.account_id = k.account_id
                    AND jel.company_id = p_company_id
                    AND je.status = 'posted'
                    AND je.je_date BETWEEN p_date_from AND p_date_to
                )
           END::NUMERIC(15,2) AS gl_sum
    FROM kinds k
  )
  SELECT
    g.kind,
    COALESCE(l.base_sum, 0)::NUMERIC(15,2),
    COALESCE(l.tax_sum, 0)::NUMERIC(15,2),
    g.account_id,
    coa.account_code,
    coa.account_name,
    g.gl_sum,
    (COALESCE(l.tax_sum, 0) - COALESCE(g.gl_sum, 0))::NUMERIC(15,2),
    CASE WHEN g.account_id IS NULL
         THEN COALESCE(l.tax_sum, 0) = 0
         ELSE ABS(COALESCE(l.tax_sum, 0) - g.gl_sum) <= 0.01
    END
  FROM gl g
  LEFT JOIN ledger l ON l.kind = g.kind
  LEFT JOIN chart_of_accounts coa ON coa.id = g.account_id
  ORDER BY g.kind;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_wht_gl_reconciliation(UUID, DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_wht_gl_reconciliation(UUID, DATE, DATE) IS
  'Compares ewt_payable/cwt_receivable tax ledger sums to the configured GL withholding control accounts for a date range.';

-- ── 3. SAWT/QAP exported snapshots ─────────────────────────────────────────────

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

  -- Block export while the report's own control account does not reconcile.
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
      SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.invoice_date, d.transaction_id), '[]'::jsonb) AS payload,
             COUNT(*)::INTEGER AS row_count
      FROM (
        SELECT transaction_id, invoice_date, supplier_id, supplier_tin, supplier_name,
               atc_code, nature_of_payment, tax_rate, tax_base, tax_withheld
        FROM vw_ewt_summary_ap
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
      ) d
    ),
    summary_rows AS (
      SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.supplier_name, s.supplier_tin), '[]'::jsonb) AS payload
      FROM (
        SELECT
          COALESCE(supplier_tin, '') AS supplier_tin,
          COALESCE(supplier_name, 'Unknown') AS supplier_name,
          string_agg(DISTINCT atc_code, '; ' ORDER BY atc_code) AS atc_codes,
          SUM(tax_base)::NUMERIC(15,2) AS tax_base,
          SUM(tax_withheld)::NUMERIC(15,2) AS tax_withheld
        FROM vw_ewt_summary_ap
        WHERE company_id = p_company_id
          AND invoice_date BETWEEN v_start AND v_end
        GROUP BY COALESCE(supplier_tin, ''), COALESCE(supplier_name, 'Unknown')
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
             'payee_detail_rows', detail_rows.payload,
             'payee_summary_rows', summary_rows.payload,
             'wht_gl_reconciliation', recon_rows.payload
           ),
           detail_rows.row_count
    INTO v_source_payload, v_row_count
    FROM detail_rows, summary_rows, recon_rows;
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
  'Creates an exported immutable report snapshot for SAWT/QAP withholding alphalists, with source hash and WHT/GL reconciliation payload.';
