-- PXL-AUD-049: withholding tax drilldowns.
--
-- Keep the existing PXL-DA-002 trace surface, but let callers pass the same
-- dimensions used by QAP/Form 2307 rows so EWT/CWT amounts resolve to the
-- exact source tax-detail group instead of a broad payee/date trace.

CREATE OR REPLACE FUNCTION fn_get_report_trace_set(
  p_company_id UUID,
  p_report_family TEXT,
  p_filters JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
  report_family TEXT,
  report_record_id UUID,
  source_doc_type TEXT,
  source_doc_id UUID,
  journal_entry_id UUID,
  source_number TEXT,
  source_date DATE,
  source_route TEXT,
  module_route TEXT,
  accounting_trace_route TEXT,
  journal_route TEXT,
  general_ledger_route TEXT,
  trace_context JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family TEXT := LOWER(REPLACE(BTRIM(COALESCE(p_report_family, '')), '-', '_'));
  v_date_from DATE := NULLIF(p_filters->>'date_from', '')::DATE;
  v_date_to DATE := NULLIF(p_filters->>'date_to', '')::DATE;
  v_account_id UUID := NULLIF(p_filters->>'account_id', '')::UUID;
  v_counterparty_id UUID := NULLIF(p_filters->>'counterparty_id', '')::UUID;
  v_record_id UUID := NULLIF(p_filters->>'record_id', '')::UUID;
  v_ledger TEXT := UPPER(BTRIM(COALESCE(p_filters->>'ledger', '')));
  v_tax_kind TEXT := NULLIF(LOWER(BTRIM(COALESCE(p_filters->>'tax_kind', ''))), '');
  v_source_doc_type TEXT := fn_normalize_report_source_type(NULLIF(p_filters->>'source_doc_type', ''));
  v_source_doc_id UUID := NULLIF(p_filters->>'source_doc_id', '')::UUID;
  v_atc_code_id UUID := NULLIF(p_filters->>'atc_code_id', '')::UUID;
  v_atc_code TEXT := NULLIF(UPPER(BTRIM(COALESCE(p_filters->>'atc_code', ''))), '');
  v_income_nature TEXT := NULLIF(BTRIM(COALESCE(
    p_filters->>'income_nature',
    p_filters->>'nature_of_payment',
    p_filters->>'nature_of_income',
    ''
  )), '');
  v_tax_rate NUMERIC := NULLIF(p_filters->>'tax_rate', '')::NUMERIC;
  v_active_only BOOLEAN := COALESCE(NULLIF(p_filters->>'active_only', '')::BOOLEAN, FALSE);
  v_issue form_2307_issuances%ROWTYPE;
  v_start DATE;
  v_end DATE;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_filters IS NULL OR jsonb_typeof(p_filters) <> 'object' THEN
    RAISE EXCEPTION 'Report trace filters must be a JSON object';
  END IF;
  IF v_date_from IS NOT NULL AND v_date_to IS NOT NULL AND v_date_from > v_date_to THEN
    RAISE EXCEPTION 'Invalid report trace date range';
  END IF;

  IF v_family IN ('financial', 'financial_account') THEN
    IF v_account_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM chart_of_accounts
      WHERE id = v_account_id AND company_id = p_company_id
    ) THEN
      RAISE EXCEPTION 'Financial report account not found or access denied';
    END IF;

    RETURN QUERY
    WITH candidates AS (
      SELECT DISTINCT gl.je_id
      FROM vw_general_ledger gl
      WHERE gl.company_id = p_company_id
        AND gl.account_id = v_account_id
        AND (v_date_from IS NULL OR gl.je_date >= v_date_from)
        AND (v_date_to IS NULL OR gl.je_date <= v_date_to)
    ), traces AS (
      SELECT c.je_id AS record_id,
             fn_get_accounting_trace(NULL, NULL, c.je_id) AS payload
      FROM candidates c
    )
    SELECT
      'financial'::TEXT,
      t.record_id,
      t.payload->>'source_doc_type',
      (t.payload->>'source_doc_id')::UUID,
      NULLIF(t.payload->>'journal_entry_id', '')::UUID,
      t.payload->>'source_number',
      NULLIF(t.payload->>'source_date', '')::DATE,
      t.payload->>'source_route',
      t.payload->>'module_route',
      '/accounting-trace?jeId=' || t.record_id::TEXT,
      t.payload->>'journal_route',
      t.payload->>'general_ledger_route',
      jsonb_build_object('account_id', v_account_id,
                         'date_from', v_date_from, 'date_to', v_date_to)
    FROM traces t;
    RETURN;

  ELSIF v_family = 'subledger' THEN
    IF v_ledger NOT IN ('AR', 'AP') OR v_counterparty_id IS NULL THEN
      RAISE EXCEPTION 'Subledger traces require ledger AR/AP and counterparty_id';
    END IF;
    IF v_ledger = 'AR' AND NOT EXISTS (
      SELECT 1 FROM customers WHERE id = v_counterparty_id AND company_id = p_company_id
    ) THEN
      RAISE EXCEPTION 'Subledger counterparty not found or access denied';
    ELSIF v_ledger = 'AP' AND NOT EXISTS (
      SELECT 1 FROM suppliers WHERE id = v_counterparty_id AND company_id = p_company_id
    ) THEN
      RAISE EXCEPTION 'Subledger counterparty not found or access denied';
    END IF;

    IF v_ledger = 'AR' THEN
      RETURN QUERY
      WITH candidates AS (
        SELECT l.source_doc_type, l.source_doc_id, l.transaction_date
        FROM vw_customer_ledger l
        WHERE l.company_id = p_company_id
          AND l.customer_id = v_counterparty_id
          AND (v_date_from IS NULL OR l.transaction_date >= v_date_from)
          AND (v_date_to IS NULL OR l.transaction_date <= v_date_to)
      ), traces AS (
        SELECT c.*,
               fn_get_accounting_trace(c.source_doc_type, c.source_doc_id, NULL) AS payload
        FROM candidates c
      )
      SELECT
        'subledger'::TEXT, t.source_doc_id,
        t.payload->>'source_doc_type', (t.payload->>'source_doc_id')::UUID,
        NULLIF(t.payload->>'journal_entry_id', '')::UUID,
        t.payload->>'source_number', NULLIF(t.payload->>'source_date', '')::DATE,
        t.payload->>'source_route', t.payload->>'module_route',
        '/accounting-trace?sourceType=' || (t.payload->>'source_doc_type')
          || '&sourceId=' || (t.payload->>'source_doc_id'),
        t.payload->>'journal_route', t.payload->>'general_ledger_route',
        jsonb_build_object('ledger', 'AR', 'counterparty_id', v_counterparty_id,
                           'transaction_date', t.transaction_date)
      FROM traces t;
    ELSE
      RETURN QUERY
      WITH candidates AS (
        SELECT l.source_doc_type, l.source_doc_id, l.transaction_date
        FROM vw_supplier_ledger l
        WHERE l.company_id = p_company_id
          AND l.supplier_id = v_counterparty_id
          AND (v_date_from IS NULL OR l.transaction_date >= v_date_from)
          AND (v_date_to IS NULL OR l.transaction_date <= v_date_to)
      ), traces AS (
        SELECT c.*,
               fn_get_accounting_trace(c.source_doc_type, c.source_doc_id, NULL) AS payload
        FROM candidates c
      )
      SELECT
        'subledger'::TEXT, t.source_doc_id,
        t.payload->>'source_doc_type', (t.payload->>'source_doc_id')::UUID,
        NULLIF(t.payload->>'journal_entry_id', '')::UUID,
        t.payload->>'source_number', NULLIF(t.payload->>'source_date', '')::DATE,
        t.payload->>'source_route', t.payload->>'module_route',
        '/accounting-trace?sourceType=' || (t.payload->>'source_doc_type')
          || '&sourceId=' || (t.payload->>'source_doc_id'),
        t.payload->>'journal_route', t.payload->>'general_ledger_route',
        jsonb_build_object('ledger', 'AP', 'counterparty_id', v_counterparty_id,
                           'transaction_date', t.transaction_date)
      FROM traces t;
    END IF;
    RETURN;

  ELSIF v_family = 'tax' THEN
    IF v_tax_kind IS NULL THEN
      RAISE EXCEPTION 'Tax traces require tax_kind';
    END IF;

    RETURN QUERY
    WITH candidates AS (
      SELECT
        MIN(tde.id::TEXT)::UUID AS record_id,
        tde.source_doc_type,
        tde.source_doc_id,
        MIN(tde.document_date) AS document_date,
        tde.atc_code_id,
        ac.code AS atc_code,
        COALESCE(NULLIF(tde.income_nature, ''), ac.description, '') AS income_nature,
        tde.tax_rate,
        SUM(tde.tax_base)::NUMERIC(15,2) AS tax_base,
        SUM(tde.tax_amount)::NUMERIC(15,2) AS tax_amount,
        jsonb_agg(tde.id ORDER BY tde.id) AS tax_detail_ids
      FROM tax_detail_entries tde
      LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
      WHERE tde.company_id = p_company_id
        AND tde.tax_kind = v_tax_kind
        AND (v_counterparty_id IS NULL OR tde.counterparty_id = v_counterparty_id)
        AND (v_source_doc_type IS NULL OR tde.source_doc_type = v_source_doc_type)
        AND (v_source_doc_id IS NULL OR tde.source_doc_id = v_source_doc_id)
        AND (v_atc_code_id IS NULL OR tde.atc_code_id = v_atc_code_id)
        AND (v_atc_code IS NULL OR UPPER(COALESCE(ac.code, '')) = v_atc_code)
        AND (v_income_nature IS NULL OR COALESCE(NULLIF(tde.income_nature, ''), ac.description, '') = v_income_nature)
        AND (v_tax_rate IS NULL OR ROUND(COALESCE(tde.tax_rate, 0)::NUMERIC, 2) = ROUND(v_tax_rate, 2))
        AND (v_date_from IS NULL OR tde.document_date >= v_date_from)
        AND (v_date_to IS NULL OR tde.document_date <= v_date_to)
        AND (
          NOT v_active_only OR (
            COALESCE(tde.is_reversal, FALSE) = FALSE
            AND NOT EXISTS (
              SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = tde.id
            )
          )
        )
      GROUP BY
        tde.source_doc_type, tde.source_doc_id, tde.atc_code_id, ac.code,
        COALESCE(NULLIF(tde.income_nature, ''), ac.description, ''), tde.tax_rate
    ), traces AS (
      SELECT c.*,
             fn_get_accounting_trace(c.source_doc_type, c.source_doc_id, NULL) AS payload
      FROM candidates c
    )
    SELECT
      'tax'::TEXT, t.record_id,
      t.payload->>'source_doc_type', (t.payload->>'source_doc_id')::UUID,
      NULLIF(t.payload->>'journal_entry_id', '')::UUID,
      t.payload->>'source_number', NULLIF(t.payload->>'source_date', '')::DATE,
      t.payload->>'source_route', t.payload->>'module_route',
      '/accounting-trace?sourceType=' || (t.payload->>'source_doc_type')
        || '&sourceId=' || (t.payload->>'source_doc_id'),
      t.payload->>'journal_route', t.payload->>'general_ledger_route',
      jsonb_build_object('tax_kind', v_tax_kind,
                         'counterparty_id', v_counterparty_id,
                         'source_doc_type', t.source_doc_type,
                         'source_doc_id', t.source_doc_id,
                         'document_date', t.document_date,
                         'atc_code_id', t.atc_code_id,
                         'atc_code', t.atc_code,
                         'income_nature', NULLIF(t.income_nature, ''),
                         'tax_rate', t.tax_rate,
                         'tax_base', t.tax_base,
                         'tax_amount', t.tax_amount,
                         'tax_detail_ids', t.tax_detail_ids)
    FROM traces t;
    RETURN;

  ELSIF v_family = 'form_2307_issued' THEN
    IF v_record_id IS NULL THEN
      RAISE EXCEPTION 'Form 2307 issued traces require record_id';
    END IF;
    SELECT * INTO v_issue
    FROM form_2307_issuances
    WHERE id = v_record_id AND company_id = p_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Form 2307 issuance not found or access denied';
    END IF;
    v_start := make_date(v_issue.tax_year, (v_issue.tax_quarter - 1) * 3 + 1, 1);
    v_end := (v_start + INTERVAL '3 months' - INTERVAL '1 day')::DATE;

    RETURN QUERY
    WITH candidates AS (
      SELECT
        e.source_doc_type,
        e.source_doc_id,
        MIN(e.invoice_date) AS invoice_date,
        e.atc_code_id,
        e.atc_code,
        COALESCE(e.nature_of_payment, '') AS income_nature,
        e.tax_rate,
        SUM(e.tax_base)::NUMERIC(15,2) AS tax_base,
        SUM(e.tax_withheld)::NUMERIC(15,2) AS tax_withheld
      FROM vw_ewt_summary_ap e
      WHERE e.company_id = p_company_id
        AND e.supplier_id = v_issue.supplier_id
        AND e.invoice_date BETWEEN v_start AND v_end
        AND (v_atc_code_id IS NULL OR e.atc_code_id = v_atc_code_id)
        AND (v_atc_code IS NULL OR UPPER(COALESCE(e.atc_code, '')) = v_atc_code)
        AND (v_income_nature IS NULL OR COALESCE(e.nature_of_payment, '') = v_income_nature)
        AND (v_tax_rate IS NULL OR ROUND(COALESCE(e.tax_rate, 0)::NUMERIC, 2) = ROUND(v_tax_rate, 2))
      GROUP BY e.source_doc_type, e.source_doc_id, e.atc_code_id, e.atc_code,
               COALESCE(e.nature_of_payment, ''), e.tax_rate
    ), traces AS (
      SELECT c.*,
             fn_get_accounting_trace(c.source_doc_type, c.source_doc_id, NULL) AS payload
      FROM candidates c
    )
    SELECT
      'form_2307_issued'::TEXT, v_issue.id,
      t.payload->>'source_doc_type', (t.payload->>'source_doc_id')::UUID,
      NULLIF(t.payload->>'journal_entry_id', '')::UUID,
      t.payload->>'source_number', NULLIF(t.payload->>'source_date', '')::DATE,
      t.payload->>'source_route', t.payload->>'module_route',
      '/accounting-trace?sourceType=' || (t.payload->>'source_doc_type')
        || '&sourceId=' || (t.payload->>'source_doc_id'),
      t.payload->>'journal_route', t.payload->>'general_ledger_route',
      jsonb_build_object('supplier_id', v_issue.supplier_id,
                         'tax_year', v_issue.tax_year,
                         'tax_quarter', v_issue.tax_quarter,
                         'atc_code_id', t.atc_code_id,
                         'atc_code', t.atc_code,
                         'income_nature', NULLIF(t.income_nature, ''),
                         'tax_rate', t.tax_rate,
                         'tax_base', t.tax_base,
                         'tax_withheld', t.tax_withheld,
                         'document_date', t.invoice_date)
    FROM traces t;
    RETURN;

  ELSIF v_family = 'form_2307_received' THEN
    IF v_record_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM form_2307_tracking ft
      WHERE ft.id = v_record_id AND ft.company_id = p_company_id
    ) THEN
      RAISE EXCEPTION 'Form 2307 received record not found or access denied';
    END IF;

    RETURN QUERY
    WITH candidate AS (
      SELECT ft.id AS record_id, r.id AS source_id
      FROM form_2307_tracking ft
      JOIN receipt_lines rl ON rl.id = ft.receipt_line_id
      JOIN receipts r ON r.id = rl.receipt_id
      WHERE ft.id = v_record_id
        AND ft.company_id = p_company_id
        AND r.company_id = p_company_id
    ), trace AS (
      SELECT c.*,
             fn_get_accounting_trace('OR', c.source_id, NULL) AS payload
      FROM candidate c
    )
    SELECT
      'form_2307_received'::TEXT, t.record_id,
      t.payload->>'source_doc_type', (t.payload->>'source_doc_id')::UUID,
      NULLIF(t.payload->>'journal_entry_id', '')::UUID,
      t.payload->>'source_number', NULLIF(t.payload->>'source_date', '')::DATE,
      t.payload->>'source_route', t.payload->>'module_route',
      '/accounting-trace?sourceType=OR&sourceId=' || (t.payload->>'source_doc_id'),
      t.payload->>'journal_route', t.payload->>'general_ledger_route',
      jsonb_build_object('tracking_id', t.record_id)
    FROM trace t;
    RETURN;

  ELSIF v_family = 'report_snapshot' THEN
    IF v_record_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM report_snapshots rs
      WHERE rs.id = v_record_id AND rs.company_id = p_company_id
    ) THEN
      RAISE EXCEPTION 'Report snapshot not found or access denied';
    END IF;

    RETURN QUERY
    SELECT
      'report_snapshot'::TEXT,
      l.report_snapshot_id,
      l.source_doc_type,
      l.source_doc_id,
      l.journal_entry_id,
      l.source_number,
      l.source_date,
      l.source_route,
      l.module_route,
      l.accounting_trace_route,
      l.journal_route,
      l.general_ledger_route,
      l.trace_context
    FROM fn_get_report_snapshot_trace_links(v_record_id) l;
    RETURN;
  ELSE
    RAISE EXCEPTION 'Unsupported report trace family %', COALESCE(p_report_family, '<null>');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_report_trace_set(UUID, TEXT, JSONB) TO authenticated;

COMMENT ON FUNCTION fn_get_report_trace_set(UUID, TEXT, JSONB) IS
  'Membership-scoped canonical accounting source/JE route set for financial, subledger, tax, Form 2307, and immutable report snapshot rows. Tax/Form 2307 filters support exact ATC/nature/rate/source drilldowns for PXL-AUD-049.';
