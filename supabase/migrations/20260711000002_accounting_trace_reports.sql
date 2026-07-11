-- Report-wide accounting trace contracts (PXL-DA-002).
--
-- This migration is intentionally later than the posting-engine consolidation
-- migration.  It only extends read contracts: canonical source keys on report
-- views, hardened single-source trace resolution, and membership-scoped trace
-- sets for aggregate report rows.  Immutable report payloads and their hashes
-- are never rewritten; snapshot links are derived at read time.

-- ---------------------------------------------------------------------------
-- Canonical source keys on current report views. Existing columns retain their
-- names, order, and meaning; the canonical pair is appended.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW vw_customer_ledger
WITH (security_invoker = true) AS
SELECT
  si.company_id, si.customer_id, si.date AS transaction_date,
  'SI'::TEXT AS doc_type, si.si_number AS doc_number,
  COALESCE(si.memo, 'Sales Invoice') AS description,
  si.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  si.created_at,
  'SI'::TEXT AS source_doc_type,
  si.id AS source_doc_id
FROM sales_invoices si
WHERE si.status = 'posted'

UNION ALL

SELECT
  r.company_id, r.customer_id, r.receipt_date AS transaction_date,
  'OR'::TEXT AS doc_type, r.receipt_number AS doc_number,
  COALESCE(r.remarks, 'Official Receipt') AS description,
  0::NUMERIC AS debit_amount, (r.total_amount + r.total_cwt) AS credit_amount,
  r.created_at,
  'OR'::TEXT AS source_doc_type,
  r.id AS source_doc_id
FROM receipts r
WHERE r.status = 'posted'

UNION ALL

SELECT
  cm.company_id, cm.customer_id, cm.cm_date AS transaction_date,
  'CM'::TEXT AS doc_type, cm.cm_number AS doc_number,
  COALESCE(cm.remarks, 'Credit Memo') AS description,
  0::NUMERIC AS debit_amount, cm.total_amount AS credit_amount,
  cm.created_at,
  'CM'::TEXT AS source_doc_type,
  cm.id AS source_doc_id
FROM credit_memos cm
WHERE cm.status IN ('approved', 'applied')

UNION ALL

SELECT
  dm.company_id, dm.customer_id, dm.dm_date AS transaction_date,
  'DM'::TEXT AS doc_type, dm.dm_number AS doc_number,
  COALESCE(dm.remarks, 'Debit Memo') AS description,
  dm.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  dm.created_at,
  'DM'::TEXT AS source_doc_type,
  dm.id AS source_doc_id
FROM debit_memos dm
WHERE dm.status IN ('approved', 'paid');

CREATE OR REPLACE VIEW vw_supplier_ledger
WITH (security_invoker = true) AS
SELECT
  vb.company_id,
  vb.supplier_id,
  vb.bill_date        AS transaction_date,
  'vendor_bill'       AS document_type,
  vb.id               AS document_id,
  vb.bill_number      AS document_number,
  vb.supplier_invoice_number AS external_ref,
  vb.memo             AS description,
  0                   AS debit_amount,
  vb.total_amount     AS credit_amount,
  vb.created_at,
  'VB'::TEXT           AS source_doc_type,
  vb.id                AS source_doc_id
FROM vendor_bills vb
WHERE vb.status = 'posted'
UNION ALL
SELECT
  pv.company_id,
  pv.supplier_id,
  pv.voucher_date     AS transaction_date,
  'payment_voucher'   AS document_type,
  pv.id               AS document_id,
  pv.voucher_number   AS document_number,
  pv.reference_number AS external_ref,
  pv.remarks          AS description,
  pv.total_amount + pv.total_ewt AS debit_amount,
  0                   AS credit_amount,
  pv.created_at,
  'PV'::TEXT           AS source_doc_type,
  pv.id                AS source_doc_id
FROM payment_vouchers pv
WHERE pv.status = 'posted'
UNION ALL
SELECT
  vc.company_id,
  vc.supplier_id,
  vc.credit_date      AS transaction_date,
  'vendor_credit'     AS document_type,
  vc.id               AS document_id,
  vc.vc_number        AS document_number,
  vc.supplier_cm_no   AS external_ref,
  vc.remarks          AS description,
  vc.total_amount     AS debit_amount,
  0                   AS credit_amount,
  vc.created_at,
  'VC'::TEXT           AS source_doc_type,
  vc.id                AS source_doc_id
FROM vendor_credits vc
WHERE vc.status IN ('open','applied');

CREATE OR REPLACE VIEW vw_output_vat_review
WITH (security_invoker = true) AS
SELECT
  tde.source_doc_id AS transaction_id,
  CASE
    WHEN tde.source_doc_type = 'SI' AND COALESCE(si.is_cash_sale, false) THEN 'cash_sale'
    WHEN tde.source_doc_type = 'SI' THEN 'sales_invoice'
    ELSE lower(tde.source_doc_type)
  END AS source_module,
  tde.company_id,
  tde.document_date AS invoice_date,
  tde.counterparty_tin AS customer_tin,
  tde.counterparty_name AS customer_name,
  COALESCE(si.si_number, tde.source_doc_id::text) AS system_no,
  COALESCE(SUM(tde.tax_base + tde.tax_amount), 0)::NUMERIC(15,2) AS gross_sales,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'exempt'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS exempt_sales,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'zero_rated'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS zero_rated_sales,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'regular'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS taxable_base,
  COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS output_vat,
  tde.source_doc_type,
  tde.source_doc_id
FROM tax_detail_entries tde
LEFT JOIN vat_codes vc ON vc.id = tde.vat_code_id
LEFT JOIN sales_invoices si
  ON tde.source_doc_type = 'SI'
 AND si.id = tde.source_doc_id
WHERE tde.tax_kind = 'output_vat'
GROUP BY
  tde.source_doc_id,
  tde.source_doc_type,
  COALESCE(si.is_cash_sale, false),
  tde.company_id,
  tde.document_date,
  tde.counterparty_tin,
  tde.counterparty_name,
  COALESCE(si.si_number, tde.source_doc_id::text);

CREATE OR REPLACE VIEW vw_input_vat_review
WITH (security_invoker = true) AS
SELECT
  tde.source_doc_id AS transaction_id,
  CASE tde.source_doc_type
    WHEN 'VB' THEN 'vendor_bill'
    WHEN 'CP' THEN 'cash_purchase'
    ELSE lower(tde.source_doc_type)
  END AS source_module,
  tde.company_id,
  tde.document_date AS invoice_date,
  tde.counterparty_tin AS supplier_tin,
  tde.counterparty_name AS supplier_name,
  COALESCE(s.registered_address, '') AS supplier_address,
  COALESCE(vb.supplier_invoice_number, cp.reference_number, '') AS invoice_no,
  COALESCE(vb.bill_number, cp.cp_number, tde.source_doc_id::text) AS system_no,
  COALESCE(SUM(tde.tax_base + tde.tax_amount), 0)::NUMERIC(15,2) AS gross_purchases,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'exempt'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS exempt_purchases,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'zero_rated'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS zero_rated,
  COALESCE(SUM(CASE WHEN COALESCE(vc.vat_classification, 'regular') = 'regular'
                    THEN tde.tax_base ELSE 0 END), 0)::NUMERIC(15,2) AS taxable_base,
  COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS input_vat,
  tde.source_doc_type,
  tde.source_doc_id
FROM tax_detail_entries tde
LEFT JOIN vat_codes vc ON vc.id = tde.vat_code_id
LEFT JOIN vendor_bills vb
  ON tde.source_doc_type = 'VB'
 AND vb.id = tde.source_doc_id
LEFT JOIN cash_purchases cp
  ON tde.source_doc_type = 'CP'
 AND cp.id = tde.source_doc_id
LEFT JOIN suppliers s
  ON s.id = COALESCE(vb.supplier_id, cp.supplier_id, tde.counterparty_id)
WHERE tde.tax_kind = 'input_vat'
GROUP BY
  tde.source_doc_id,
  tde.source_doc_type,
  tde.company_id,
  tde.document_date,
  tde.counterparty_tin,
  tde.counterparty_name,
  COALESCE(s.registered_address, ''),
  COALESCE(vb.supplier_invoice_number, cp.reference_number, ''),
  COALESCE(vb.bill_number, cp.cp_number, tde.source_doc_id::text);

CREATE OR REPLACE VIEW vw_ewt_summary_ap
WITH (security_invoker = true) AS
SELECT
  tde.source_doc_id     AS transaction_id,
  tde.company_id,
  tde.document_date     AS invoice_date,
  tde.counterparty_id   AS supplier_id,
  tde.counterparty_tin  AS supplier_tin,
  tde.counterparty_name AS supplier_name,
  tde.atc_code_id,
  ac.code               AS atc_code,
  COALESCE(NULLIF(tde.income_nature, ''), ac.description) AS nature_of_payment,
  tde.tax_rate,
  tde.tax_base,
  tde.tax_amount        AS tax_withheld,
  tde.source_doc_type,
  tde.source_doc_id
FROM tax_detail_entries tde
LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
WHERE tde.tax_kind = 'ewt_payable'
  AND tde.is_reversal = false
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = tde.id
  );

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
  tde.tax_amount        AS cwt_withheld,
  tde.source_doc_id
FROM tax_detail_entries tde
LEFT JOIN atc_codes ac ON ac.id = tde.atc_code_id
WHERE tde.tax_kind = 'cwt_receivable'
  AND tde.is_reversal = false
  AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries r WHERE r.reverses_tax_detail_id = tde.id
  );

GRANT SELECT ON
  vw_customer_ledger,
  vw_supplier_ledger,
  vw_output_vat_review,
  vw_input_vat_review,
  vw_ewt_summary_ap,
  vw_cwt_summary_ar
TO authenticated;

-- ---------------------------------------------------------------------------
-- Harden the single-source authority. A JE cannot be paired with an arbitrary,
-- orphaned, or cross-company polymorphic source. `source_route` is now the
-- generic working route; `module_route` preserves the registered module hint.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_accounting_trace(
  p_source_doc_type TEXT DEFAULT NULL,
  p_source_doc_id UUID DEFAULT NULL,
  p_journal_entry_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := NULLIF(UPPER(BTRIM(COALESCE(p_source_doc_type, ''))), '');
  v_je_id UUID := p_journal_entry_id;
  v_je journal_entries%ROWTYPE;
  v_ref ref_posting_source_types%ROWTYPE;
  v_source JSONB;
  v_source_company UUID;
  v_source_number TEXT;
  v_source_date DATE;
  v_source_status TEXT;
  v_linked_source_id UUID;
  v_sql TEXT;
  v_audit JSONB;
BEGIN
  IF v_je_id IS NULL AND v_type IS NOT NULL AND p_source_doc_id IS NOT NULL THEN
    IF v_type = 'MANUAL' THEN
      SELECT id INTO v_je_id
      FROM journal_entries
      WHERE id = p_source_doc_id
        AND reference_doc_type = 'MANUAL';
    ELSE
      SELECT id INTO v_je_id
      FROM journal_entries
      WHERE reference_doc_type = v_type
        AND reference_doc_id = p_source_doc_id
      ORDER BY
        CASE WHEN status IN ('posted', 'reversed') THEN 0 ELSE 1 END,
        created_at DESC
      LIMIT 1;
    END IF;
  END IF;

  IF v_je_id IS NOT NULL THEN
    SELECT * INTO v_je FROM journal_entries WHERE id = v_je_id;
    IF NOT FOUND OR NOT is_company_member(v_je.company_id) THEN
      RAISE EXCEPTION 'Journal entry not found or access denied';
    END IF;

    IF v_type IS NOT NULL AND v_type IS DISTINCT FROM v_je.reference_doc_type THEN
      RAISE EXCEPTION 'Journal entry source type does not match the requested accounting source';
    END IF;

    v_linked_source_id := CASE
      WHEN v_je.reference_doc_type = 'MANUAL' AND v_je.reference_doc_id IS NULL THEN v_je.id
      ELSE v_je.reference_doc_id
    END;

    IF p_source_doc_id IS NOT NULL
       AND p_source_doc_id IS DISTINCT FROM v_linked_source_id THEN
      RAISE EXCEPTION 'Journal entry source id does not match the requested accounting source';
    END IF;

    v_type := COALESCE(v_type, v_je.reference_doc_type);
    p_source_doc_id := COALESCE(p_source_doc_id, v_linked_source_id);
  END IF;

  SELECT * INTO v_ref
  FROM ref_posting_source_types
  WHERE document_type = v_type AND is_active = true;

  IF v_ref.document_type IS NULL THEN
    RAISE EXCEPTION 'Unknown accounting source type %', COALESCE(v_type, '<null>');
  END IF;

  IF v_ref.source_table IS NOT NULL THEN
    IF p_source_doc_id IS NULL THEN
      RAISE EXCEPTION 'Accounting source not found or access denied';
    END IF;

    v_sql := format('SELECT to_jsonb(t) FROM %s t WHERE t.id = $1', v_ref.source_table);
    EXECUTE v_sql INTO v_source USING p_source_doc_id;

    IF v_source IS NULL THEN
      RAISE EXCEPTION 'Accounting source not found or access denied';
    END IF;

    v_source_company := NULLIF(v_source->>'company_id', '')::UUID;
    IF v_source_company IS NULL OR NOT is_company_member(v_source_company) THEN
      RAISE EXCEPTION 'Accounting source not found or access denied';
    END IF;
    IF v_je_id IS NOT NULL AND v_source_company IS DISTINCT FROM v_je.company_id THEN
      RAISE EXCEPTION 'Journal entry company does not match the accounting source company';
    END IF;

    IF v_ref.document_number_column IS NOT NULL THEN
      v_source_number := v_source->>v_ref.document_number_column::text;
    END IF;
    IF v_ref.document_date_column IS NOT NULL THEN
      v_source_date := NULLIF(v_source->>v_ref.document_date_column::text, '')::DATE;
    END IF;
    IF v_ref.status_column IS NOT NULL THEN
      v_source_status := v_source->>v_ref.status_column::text;
    END IF;
  ELSIF v_je_id IS NULL THEN
    RAISE EXCEPTION 'Accounting source not found or access denied';
  ELSE
    v_source_company := v_je.company_id;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'action', action,
    'changed_by', changed_by,
    'changed_at', changed_at
  ) ORDER BY changed_at DESC), '[]'::jsonb)
  INTO v_audit
  FROM sys_audit_logs
  WHERE record_id = p_source_doc_id
    AND company_id = COALESCE(v_source_company, v_je.company_id);

  RETURN jsonb_build_object(
    'source_doc_type', v_type,
    'source_doc_id', p_source_doc_id,
    'source_display_name', v_ref.display_name,
    'source_number', v_source_number,
    'source_date', v_source_date,
    'source_status', v_source_status,
    'source_record', v_source,
    'source_route', CASE WHEN p_source_doc_id IS NOT NULL
                         THEN '/accounting-source?sourceType=' || v_type
                           || '&sourceId=' || p_source_doc_id::text END,
    'module_route', CASE WHEN v_ref.route_path IS NOT NULL AND p_source_doc_id IS NOT NULL
                         THEN v_ref.route_path || '?id=' || p_source_doc_id::text
                         ELSE v_ref.route_path END,
    'journal_entry_id', v_je_id,
    'journal_route', CASE WHEN v_je_id IS NOT NULL
                          THEN '/journal-entries?jeId=' || v_je_id::text END,
    'general_ledger_route', CASE WHEN v_je_id IS NOT NULL
                                 THEN '/general-ledger?jeId=' || v_je_id::text END,
    'gl_impact', CASE WHEN v_je_id IS NOT NULL THEN fn_gl_impact_payload(v_je_id, 'posted', NULL) END,
    'audit_events', v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_accounting_trace(TEXT, UUID, UUID) TO authenticated;

COMMENT ON FUNCTION fn_get_accounting_trace(TEXT, UUID, UUID) IS
  'Membership-scoped single-source authority. Rejects mismatched, orphaned, and cross-company JE/source pairs and returns the checked source record plus generic/module routes.';

-- ---------------------------------------------------------------------------
-- Snapshot link derivation. This deliberately reads but never mutates the
-- frozen payload. It supports both older payloads (transaction_id/je_id only)
-- and newer payloads that already carry canonical source keys.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_normalize_report_source_type(p_hint TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE UPPER(REPLACE(BTRIM(COALESCE(p_hint, '')), '-', '_'))
    WHEN 'SALES_INVOICE' THEN 'SI'
    WHEN 'CASH_SALE' THEN 'SI'
    WHEN 'SI' THEN 'SI'
    WHEN 'OFFICIAL_RECEIPT' THEN 'OR'
    WHEN 'RECEIPT' THEN 'OR'
    WHEN 'OR' THEN 'OR'
    WHEN 'CREDIT_MEMO' THEN 'CM'
    WHEN 'CM' THEN 'CM'
    WHEN 'DEBIT_MEMO' THEN 'DM'
    WHEN 'DM' THEN 'DM'
    WHEN 'VENDOR_BILL' THEN 'VB'
    WHEN 'VB' THEN 'VB'
    WHEN 'PAYMENT_VOUCHER' THEN 'PV'
    WHEN 'PV' THEN 'PV'
    WHEN 'CASH_PURCHASE' THEN 'CP'
    WHEN 'CP' THEN 'CP'
    WHEN 'VENDOR_CREDIT' THEN 'VC'
    WHEN 'VC' THEN 'VC'
    WHEN 'CHECK_VOUCHER' THEN 'CV'
    WHEN 'CV' THEN 'CV'
    WHEN 'PURCHASE_RETURN' THEN 'PR'
    WHEN 'PR' THEN 'PR'
    WHEN 'FUND_TRANSFER' THEN 'FT'
    WHEN 'FT' THEN 'FT'
    WHEN 'INTER_BRANCH_TRANSFER' THEN 'IBT'
    WHEN 'IBT' THEN 'IBT'
    WHEN 'BANK_ADJUSTMENT' THEN 'BADJ'
    WHEN 'BADJ' THEN 'BADJ'
    WHEN 'PETTY_CASH_VOUCHER' THEN 'PCV'
    WHEN 'PCV' THEN 'PCV'
    WHEN 'PETTY_CASH_REPLENISHMENT' THEN 'PCR'
    WHEN 'PCR' THEN 'PCR'
    WHEN 'MANUAL' THEN 'MANUAL'
    WHEN 'REV' THEN 'REV'
    ELSE NULLIF(UPPER(BTRIM(p_hint)), '')
  END;
$$;

REVOKE ALL ON FUNCTION fn_normalize_report_source_type(TEXT) FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION fn_get_report_snapshot_trace_links(p_report_snapshot_id UUID)
RETURNS TABLE (
  report_snapshot_id UUID,
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
  v_snapshot report_snapshots%ROWTYPE;
  v_candidate RECORD;
  v_type TEXT;
  v_source_id UUID;
  v_je_id UUID;
  v_raw_id TEXT;
  v_raw_je_id TEXT;
  v_trace JSONB;
  v_seen JSONB := '{}'::JSONB;
  v_key TEXT;
BEGIN
  SELECT * INTO v_snapshot
  FROM report_snapshots
  WHERE id = p_report_snapshot_id;

  IF NOT FOUND OR NOT is_company_member(v_snapshot.company_id) THEN
    RAISE EXCEPTION 'Report snapshot not found or access denied';
  END IF;

  FOR v_candidate IN
    WITH RECURSIVE walk(value) AS (
      SELECT v_snapshot.source_payload
      UNION ALL
      SELECT child.value
      FROM walk w
      CROSS JOIN LATERAL (
        SELECT e.value
        FROM jsonb_each(
          CASE WHEN jsonb_typeof(w.value) = 'object' THEN w.value ELSE '{}'::JSONB END
        ) e
        UNION ALL
        SELECT a.value
        FROM jsonb_array_elements(
          CASE WHEN jsonb_typeof(w.value) = 'array' THEN w.value ELSE '[]'::JSONB END
        ) a
      ) child
    )
    SELECT value AS obj
    FROM walk
    WHERE jsonb_typeof(value) = 'object'
      AND (
        value ? 'source_doc_id' OR value ? 'transaction_id' OR
        value ? 'document_id' OR value ? 'reference_doc_id' OR
        value ? 'journal_entry_id' OR value ? 'je_id'
      )
  LOOP
    v_type := fn_normalize_report_source_type(COALESCE(
      v_candidate.obj->>'source_doc_type',
      v_candidate.obj->>'reference_doc_type',
      v_candidate.obj->>'doc_type',
      v_candidate.obj->>'document_type',
      v_candidate.obj->>'source_module'
    ));
    v_raw_id := COALESCE(
      v_candidate.obj->>'source_doc_id',
      v_candidate.obj->>'transaction_id',
      v_candidate.obj->>'document_id',
      v_candidate.obj->>'reference_doc_id'
    );
    v_raw_je_id := COALESCE(
      v_candidate.obj->>'journal_entry_id',
      v_candidate.obj->>'je_id'
    );
    v_source_id := NULL;
    v_je_id := NULL;

    IF v_raw_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      v_source_id := v_raw_id::UUID;
    END IF;
    IF v_raw_je_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      v_je_id := v_raw_je_id::UUID;
    END IF;

    IF v_je_id IS NOT NULL THEN
      SELECT
        je.reference_doc_type,
        CASE WHEN je.reference_doc_type = 'MANUAL' AND je.reference_doc_id IS NULL
             THEN je.id ELSE je.reference_doc_id END
      INTO v_type, v_source_id
      FROM journal_entries je
      WHERE je.id = v_je_id
        AND je.company_id = v_snapshot.company_id;
    ELSIF v_source_id IS NOT NULL AND v_type IS NOT NULL THEN
      SELECT je.id INTO v_je_id
      FROM journal_entries je
      WHERE je.company_id = v_snapshot.company_id
        AND je.reference_doc_type = v_type
        AND je.reference_doc_id = v_source_id
      ORDER BY
        CASE WHEN je.status IN ('posted', 'reversed') THEN 0 ELSE 1 END,
        je.created_at DESC
      LIMIT 1;
    ELSIF v_source_id IS NOT NULL THEN
      SELECT je.reference_doc_type, je.id
      INTO v_type, v_je_id
      FROM journal_entries je
      WHERE je.company_id = v_snapshot.company_id
        AND je.reference_doc_id = v_source_id
        AND je.reference_doc_type <> 'REV'
      ORDER BY
        CASE WHEN je.status IN ('posted', 'reversed') THEN 0 ELSE 1 END,
        je.created_at DESC
      LIMIT 1;
    END IF;

    IF v_type IS NULL OR v_source_id IS NULL THEN
      CONTINUE;
    END IF;

    v_key := v_type || ':' || v_source_id::TEXT || ':' || COALESCE(v_je_id::TEXT, '');
    IF v_seen ? v_key THEN
      CONTINUE;
    END IF;

    BEGIN
      v_trace := fn_get_accounting_trace(v_type, v_source_id, v_je_id);
    EXCEPTION WHEN OTHERS THEN
      -- A frozen payload can outlive a source that was removed before source
      -- immutability was enforced. Keep the snapshot readable and omit only
      -- that unusable link; direct trace calls still fail closed.
      CONTINUE;
    END;

    v_seen := v_seen || jsonb_build_object(v_key, true);
    report_snapshot_id := v_snapshot.id;
    source_doc_type := v_trace->>'source_doc_type';
    source_doc_id := (v_trace->>'source_doc_id')::UUID;
    journal_entry_id := NULLIF(v_trace->>'journal_entry_id', '')::UUID;
    source_number := v_trace->>'source_number';
    source_date := NULLIF(v_trace->>'source_date', '')::DATE;
    source_route := v_trace->>'source_route';
    module_route := v_trace->>'module_route';
    accounting_trace_route := '/accounting-trace?sourceType=' || source_doc_type
      || '&sourceId=' || source_doc_id::TEXT;
    journal_route := v_trace->>'journal_route';
    general_ledger_route := v_trace->>'general_ledger_route';
    trace_context := jsonb_build_object(
      'report_type', v_snapshot.report_type,
      'snapshot_status', v_snapshot.snapshot_status,
      'snapshot_version', v_snapshot.snapshot_version,
      'source_hash', v_snapshot.source_hash
    );
    RETURN NEXT;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_report_snapshot_trace_links(UUID) TO authenticated;

COMMENT ON FUNCTION fn_get_report_snapshot_trace_links(UUID) IS
  'Derives membership-scoped accounting links from frozen legacy/new snapshot JSON without changing source_payload or source_hash.';

-- ---------------------------------------------------------------------------
-- Aggregate report trace set. `p_filters` keys by family:
-- financial: account_id, date_from?, date_to?
-- subledger: ledger (AR/AP), counterparty_id, date_from?, date_to?
-- tax: tax_kind, counterparty_id?, date_from?, date_to?
-- form_2307_issued / form_2307_received / report_snapshot: record_id
-- ---------------------------------------------------------------------------

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
        jsonb_agg(DISTINCT tde.tax_kind) AS tax_kinds
      FROM tax_detail_entries tde
      WHERE tde.company_id = p_company_id
        AND tde.tax_kind = v_tax_kind
        AND (v_counterparty_id IS NULL OR tde.counterparty_id = v_counterparty_id)
        AND (v_date_from IS NULL OR tde.document_date >= v_date_from)
        AND (v_date_to IS NULL OR tde.document_date <= v_date_to)
      GROUP BY tde.source_doc_type, tde.source_doc_id
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
                         'document_date', t.document_date)
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
      SELECT DISTINCT e.source_doc_type, e.source_doc_id
      FROM vw_ewt_summary_ap e
      WHERE e.company_id = p_company_id
        AND e.supplier_id = v_issue.supplier_id
        AND e.invoice_date BETWEEN v_start AND v_end
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
                         'tax_quarter', v_issue.tax_quarter)
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
  'Membership-scoped canonical accounting source/JE route set for financial, subledger, tax, Form 2307, and immutable report snapshot rows.';
