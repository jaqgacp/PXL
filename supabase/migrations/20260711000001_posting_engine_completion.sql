-- Posting-engine completion slice (PXL-DA-004 / PXL-DA-005 / PXL-DA-007).
--
-- This migration deliberately layers on top of the deployed 20260710000003
-- contract.  It does not depend on, redefine, or otherwise take ownership of
-- the held-out ATC/CAS migrations 20260710000004/00005. It leaves ATC-date,
-- numbering, and check-voucher posting logic intact while preserving the CAS
-- reason convention when hardening the shared banking/check reversal boundary.

-- ---------------------------------------------------------------------------
-- 1. Registry-backed source resolution, locking, and deferred JE integrity.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_resolve_posting_source(
  p_document_type TEXT,
  p_source_id UUID,
  p_lock BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_document_type, '')));
  v_ref ref_posting_source_types%ROWTYPE;
  v_source JSONB;
  v_candidate_source JSONB;
  v_candidate RECORD;
  v_match_count INTEGER := 0;
  v_match_tables TEXT[] := ARRAY[]::TEXT[];
  v_sql TEXT;
BEGIN
  IF v_type = '' THEN
    RAISE EXCEPTION 'A registered posting source type is required';
  END IF;

  SELECT * INTO v_ref
  FROM ref_posting_source_types
  WHERE document_type = v_type
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or inactive posting source type %', v_type;
  END IF;

  -- A standalone manual JE is the only posted entry without a physical source.
  IF v_type = 'MANUAL' AND p_source_id IS NULL THEN
    RETURN jsonb_build_object('document_type', v_type, 'source_id', NULL);
  END IF;

  IF p_source_id IS NULL THEN
    RAISE EXCEPTION 'Posting source id is required for source type %', v_type;
  END IF;

  IF v_ref.source_table IS NOT NULL THEN
    v_sql := format(
      'SELECT to_jsonb(s) FROM %s s WHERE s.id = $1%s',
      v_ref.source_table,
      CASE WHEN p_lock THEN ' FOR UPDATE' ELSE '' END
    );
    EXECUTE v_sql INTO v_source USING p_source_id;
  ELSIF v_type = 'REV' THEN
    -- Historical reversal writers did not use one source-id convention: manual
    -- reversals reference the original JE, while source-document voids reference
    -- the operational row.  Resolve either form through the governed registry.
    -- New shared reversals preserve the caller's existing convention so the CAS
    -- void-capture contract remains intact.
    FOR v_candidate IN
      SELECT source_table
      FROM (
        SELECT DISTINCT source_table
        FROM ref_posting_source_types
        WHERE source_table IS NOT NULL
          AND is_active = true
      ) registered_sources
      ORDER BY source_table::TEXT
    LOOP
      v_sql := format(
        'SELECT to_jsonb(s) FROM %s s WHERE s.id = $1%s',
        v_candidate.source_table,
        CASE WHEN p_lock THEN ' FOR UPDATE' ELSE '' END
      );
      EXECUTE v_sql INTO v_candidate_source USING p_source_id;
      IF v_candidate_source IS NOT NULL THEN
        v_match_count := v_match_count + 1;
        v_match_tables := array_append(v_match_tables, v_candidate.source_table::TEXT);
        v_source := v_candidate_source;
      END IF;
    END LOOP;
    IF v_match_count > 1 THEN
      RAISE EXCEPTION 'Reversal source % is ambiguous across registered tables: %',
        p_source_id, array_to_string(v_match_tables, ', ');
    END IF;
  END IF;

  IF v_source IS NULL THEN
    RAISE EXCEPTION 'Posting source %.% does not exist', v_type, p_source_id;
  END IF;

  IF NULLIF(v_source->>'company_id', '') IS NULL THEN
    RAISE EXCEPTION 'Posting source %.% has no company ownership', v_type, p_source_id;
  END IF;

  RETURN v_source || jsonb_build_object(
    'document_type', v_type,
    'source_id', p_source_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_assert_posting_source(
  p_document_type TEXT,
  p_source_id UUID,
  p_company_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source JSONB;
  v_source_company UUID;
BEGIN
  v_source := fn_resolve_posting_source(p_document_type, p_source_id, false);

  IF UPPER(BTRIM(COALESCE(p_document_type, ''))) = 'MANUAL'
     AND p_source_id IS NULL THEN
    RETURN v_source;
  END IF;

  v_source_company := NULLIF(v_source->>'company_id', '')::UUID;
  IF v_source_company IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Posting source company % does not match journal company %',
      v_source_company, p_company_id;
  END IF;

  RETURN v_source;
END;
$$;

CREATE OR REPLACE FUNCTION fn_begin_source_posting(
  p_document_type TEXT,
  p_source_id UUID,
  p_ready_statuses TEXT[] DEFAULT NULL,
  p_done_statuses TEXT[] DEFAULT ARRAY['posted']::TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_document_type, '')));
  v_ref ref_posting_source_types%ROWTYPE;
  v_source JSONB;
  v_company_id UUID;
  v_status TEXT;
  v_existing_je UUID;
  v_source_date DATE;
BEGIN
  SELECT * INTO v_ref
  FROM ref_posting_source_types
  WHERE document_type = v_type
    AND is_active = true;
  IF NOT FOUND OR v_ref.source_table IS NULL THEN
    RAISE EXCEPTION 'Source type % cannot use the saved-source posting protocol', v_type;
  END IF;

  -- The row lock is acquired before any module writer reads status or mutates
  -- stock, schedules, tax rows, or subsidiary balances.
  v_source := fn_resolve_posting_source(v_type, p_source_id, true);
  v_company_id := NULLIF(v_source->>'company_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Posting source not found or access denied';
  END IF;

  IF v_ref.status_column IS NOT NULL THEN
    v_status := v_source->>v_ref.status_column::TEXT;
  END IF;

  IF NOT v_ref.allows_multiple_journal_entries THEN
    SELECT id INTO v_existing_je
    FROM journal_entries
    WHERE company_id = v_company_id
      AND reference_doc_type = v_type
      AND reference_doc_id = p_source_id
      AND status IN ('posted', 'reversed')
      AND je_number NOT LIKE '%-REV-%'
      AND je_number NOT LIKE 'JE-VOID-%'
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_existing_je IS NOT NULL
     OR (p_done_statuses IS NOT NULL AND v_status = ANY (p_done_statuses)) THEN
    RETURN jsonb_build_object(
      'should_post', false,
      'existing_journal_entry_id', v_existing_je,
      'company_id', v_company_id,
      'source_status', v_status,
      'source', v_source
    );
  END IF;

  IF p_ready_statuses IS NOT NULL
     AND (v_status IS NULL OR NOT (v_status = ANY (p_ready_statuses))) THEN
    RAISE EXCEPTION 'Source % is not ready to post (current status: %)',
      v_type, COALESCE(v_status, '<none>');
  END IF;

  IF v_type <> 'RECURRING' AND v_ref.document_date_column IS NOT NULL THEN
    v_source_date := NULLIF(v_source->>v_ref.document_date_column::TEXT, '')::DATE;
    IF v_source_date IS NOT NULL THEN
      PERFORM fn_require_open_fiscal_period(v_company_id, v_source_date, true);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'should_post', true,
    'existing_journal_entry_id', NULL,
    'company_id', v_company_id,
    'source_status', v_status,
    'source', v_source
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_assert_source_journal_link(
  p_document_type TEXT,
  p_source_id UUID,
  p_journal_entry_id UUID,
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_document_type, '')));
BEGIN
  IF p_journal_entry_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM journal_entries je
    WHERE je.id = p_journal_entry_id
      AND je.company_id = p_company_id
      AND je.reference_doc_type = v_type
      AND je.reference_doc_id = p_source_id
      AND je.je_number NOT LIKE '%-REV-%'
      AND je.je_number NOT LIKE 'JE-VOID-%'
  ) THEN
    RAISE EXCEPTION 'Journal entry does not belong to source %.%', v_type, p_source_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_invoice_posting_totals(
  p_document_type TEXT,
  p_source_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_document_type, '')));
  v_header_total NUMERIC;
  v_header_vat NUMERIC;
  v_line_net NUMERIC;
  v_line_vat NUMERIC;
BEGIN
  IF v_type = 'SI' THEN
    SELECT total_amount, total_vat_amount
    INTO v_header_total, v_header_vat
    FROM sales_invoices
    WHERE id = p_source_id;

    SELECT COALESCE(SUM(net_amount), 0), COALESCE(SUM(vat_amount), 0)
    INTO v_line_net, v_line_vat
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_source_id;
  ELSIF v_type = 'VB' THEN
    SELECT total_amount, total_input_vat_amount
    INTO v_header_total, v_header_vat
    FROM vendor_bills
    WHERE id = p_source_id;

    SELECT COALESCE(SUM(net_amount), 0), COALESCE(SUM(input_vat_amount), 0)
    INTO v_line_net, v_line_vat
    FROM vendor_bill_lines
    WHERE vendor_bill_id = p_source_id;
  ELSE
    RAISE EXCEPTION 'Unsupported invoice posting-total type %', v_type;
  END IF;

  IF v_header_total IS NULL THEN
    RAISE EXCEPTION 'Posting source %.% does not exist', v_type, p_source_id;
  END IF;
  IF ABS(COALESCE(v_header_vat, 0) - v_line_vat) > 0.02 THEN
    RAISE EXCEPTION '% header VAT % does not match line VAT %',
      v_type, COALESCE(v_header_vat, 0), v_line_vat;
  END IF;
  IF ABS(v_header_total - (v_line_net + v_line_vat)) > 0.02 THEN
    RAISE EXCEPTION '% header total % does not match line total %',
      v_type, v_header_total, v_line_net + v_line_vat;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_settlement_posting(
  p_document_type TEXT,
  p_source_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(COALESCE(p_document_type, '')));
  v_company_id UUID;
  v_counterparty_id UUID;
  v_header_cash NUMERIC;
  v_header_tax NUMERIC;
  v_line_cash NUMERIC;
  v_line_tax NUMERIC;
  v_application RECORD;
  v_document_total NUMERIC;
  v_other_applied NUMERIC;
BEGIN
  IF v_type = 'OR' THEN
    SELECT company_id, customer_id, total_amount, total_cwt
    INTO v_company_id, v_counterparty_id, v_header_cash, v_header_tax
    FROM receipts
    WHERE id = p_source_id;

    SELECT COALESCE(SUM(payment_amount), 0), COALESCE(SUM(cwt_amount), 0)
    INTO v_line_cash, v_line_tax
    FROM receipt_lines
    WHERE receipt_id = p_source_id;

    PERFORM 1
    FROM sales_invoices si
    WHERE si.id IN (
      SELECT rl.invoice_id FROM receipt_lines rl
      WHERE rl.receipt_id = p_source_id AND rl.invoice_id IS NOT NULL
    )
    ORDER BY si.id
    FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM receipt_lines rl
      JOIN sales_invoices si ON si.id = rl.invoice_id
      WHERE rl.receipt_id = p_source_id
        AND (rl.company_id IS DISTINCT FROM v_company_id
             OR si.company_id IS DISTINCT FROM v_company_id
             OR si.customer_id IS DISTINCT FROM v_counterparty_id)
    ) THEN
      RAISE EXCEPTION 'Receipt application belongs to another company or customer';
    END IF;

    FOR v_application IN
      SELECT invoice_id, SUM(payment_amount + cwt_amount) AS applied
      FROM receipt_lines
      WHERE receipt_id = p_source_id AND invoice_id IS NOT NULL
      GROUP BY invoice_id
    LOOP
      SELECT total_amount INTO v_document_total
      FROM sales_invoices WHERE id = v_application.invoice_id;
      SELECT COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
      INTO v_other_applied
      FROM receipt_lines rl
      JOIN receipts r ON r.id = rl.receipt_id
      WHERE rl.invoice_id = v_application.invoice_id
        AND rl.receipt_id <> p_source_id
        AND r.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Receipt applications exceed invoice % outstanding balance',
          v_application.invoice_id;
      END IF;
    END LOOP;
  ELSIF v_type = 'PV' THEN
    SELECT company_id, supplier_id, total_amount, total_ewt
    INTO v_company_id, v_counterparty_id, v_header_cash, v_header_tax
    FROM payment_vouchers
    WHERE id = p_source_id;

    SELECT COALESCE(SUM(payment_amount), 0), COALESCE(SUM(ewt_amount), 0)
    INTO v_line_cash, v_line_tax
    FROM payment_voucher_lines
    WHERE payment_voucher_id = p_source_id;

    PERFORM 1
    FROM vendor_bills vb
    WHERE vb.id IN (
      SELECT pvl.vendor_bill_id FROM payment_voucher_lines pvl
      WHERE pvl.payment_voucher_id = p_source_id
        AND pvl.vendor_bill_id IS NOT NULL
    )
    ORDER BY vb.id
    FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM payment_voucher_lines pvl
      JOIN vendor_bills vb ON vb.id = pvl.vendor_bill_id
      WHERE pvl.payment_voucher_id = p_source_id
        AND (pvl.company_id IS DISTINCT FROM v_company_id
             OR vb.company_id IS DISTINCT FROM v_company_id
             OR vb.supplier_id IS DISTINCT FROM v_counterparty_id)
    ) THEN
      RAISE EXCEPTION 'Payment-voucher application belongs to another company or supplier';
    END IF;

    FOR v_application IN
      SELECT vendor_bill_id, SUM(payment_amount + ewt_amount) AS applied
      FROM payment_voucher_lines
      WHERE payment_voucher_id = p_source_id AND vendor_bill_id IS NOT NULL
      GROUP BY vendor_bill_id
    LOOP
      SELECT total_amount INTO v_document_total
      FROM vendor_bills WHERE id = v_application.vendor_bill_id;
      SELECT COALESCE(SUM(pvl.payment_amount + pvl.ewt_amount), 0)
      INTO v_other_applied
      FROM payment_voucher_lines pvl
      JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
      WHERE pvl.vendor_bill_id = v_application.vendor_bill_id
        AND pvl.payment_voucher_id <> p_source_id
        AND pv.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Payment-voucher applications exceed bill % outstanding balance',
          v_application.vendor_bill_id;
      END IF;
    END LOOP;
  ELSE
    RAISE EXCEPTION 'Unsupported settlement posting type %', v_type;
  END IF;

  IF v_header_cash IS NULL THEN
    RAISE EXCEPTION 'Posting source %.% does not exist', v_type, p_source_id;
  END IF;
  IF ABS(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION '% header cash amount % does not match line amount %',
      v_type, v_header_cash, v_line_cash;
  END IF;
  IF ABS(COALESCE(v_header_tax, 0) - v_line_tax) > 0.02 THEN
    RAISE EXCEPTION '% header withholding % does not match line withholding %',
      v_type, COALESCE(v_header_tax, 0), v_line_tax;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_enforce_journal_entry_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je journal_entries%ROWTYPE;
BEGIN
  -- Constraint-trigger tuples can be stale after the fixed-asset/schedule link
  -- triggers run, so always re-read the final row visible at constraint time.
  SELECT * INTO v_je FROM journal_entries WHERE id = NEW.id;
  IF NOT FOUND OR v_je.status NOT IN ('posted', 'reversed') THEN
    RETURN NULL;
  END IF;

  IF v_je.reference_doc_type IS NULL THEN
    RAISE EXCEPTION 'Posted journal entry % has no governed source type', v_je.je_number;
  END IF;

  PERFORM fn_assert_posting_source(
    v_je.reference_doc_type,
    v_je.reference_doc_id,
    v_je.company_id
  );
  RETURN NULL;
END;
$$;

DO $$
DECLARE
  v_je RECORD;
BEGIN
  FOR v_je IN
    SELECT id, je_number, company_id, reference_doc_type, reference_doc_id
    FROM journal_entries
    WHERE status IN ('posted', 'reversed')
  LOOP
    BEGIN
      PERFORM fn_assert_posting_source(
        v_je.reference_doc_type, v_je.reference_doc_id, v_je.company_id
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Cannot enforce posting source integrity for JE % (%): %',
        v_je.je_number, v_je.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

DROP TRIGGER IF EXISTS trg_journal_entry_source_integrity ON journal_entries;
CREATE CONSTRAINT TRIGGER trg_journal_entry_source_integrity
  AFTER INSERT OR UPDATE ON journal_entries
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_journal_entry_source();

-- Extend one-shot protection to fixed-asset sources now that the deferred
-- source contract sees the final linked source row.
DROP INDEX IF EXISTS ux_journal_entries_live_source;
CREATE UNIQUE INDEX ux_journal_entries_live_source
  ON journal_entries (company_id, reference_doc_type, reference_doc_id)
  WHERE reference_doc_id IS NOT NULL
    AND status IN ('posted', 'reversed')
    AND je_number NOT LIKE '%-REV-%'
    AND je_number NOT LIKE 'JE-VOID-%'
    AND reference_doc_type IN (
      'SI','OR','CM','DM','VB','PV','CP','VC','FT','IBT','BADJ','PCV','PCR','CV',
      'PR','INV_ADJ','INV_STX','INV_GI','INV_COUNT',
      'FA','FA_DEPR','FA_DISP','FA_IMP','AMORT','REVREC'
    );

CREATE UNIQUE INDEX ux_journal_entries_recurring_source_date
  ON journal_entries (company_id, reference_doc_id, je_date)
  WHERE reference_doc_type = 'RECURRING'
    AND reference_doc_id IS NOT NULL
    AND status IN ('posted', 'reversed')
    AND je_number NOT LIKE '%-REV-%';

-- ---------------------------------------------------------------------------
-- 2. Shared tax writer with stable source-line identity and safe uniqueness.
-- ---------------------------------------------------------------------------

ALTER TABLE tax_detail_entries
  ADD COLUMN IF NOT EXISTS source_line_id UUID;

CREATE UNIQUE INDEX ux_tde_single_counter_row
  ON tax_detail_entries (reverses_tax_detail_id)
  WHERE reverses_tax_detail_id IS NOT NULL;

CREATE UNIQUE INDEX ux_tde_vat_source_code
  ON tax_detail_entries (
    company_id, source_doc_type, source_doc_id, tax_kind, vat_code_id
  )
  WHERE reverses_tax_detail_id IS NULL
    AND vat_code_id IS NOT NULL
    AND tax_kind IN ('output_vat', 'input_vat');

CREATE UNIQUE INDEX ux_tde_source_line_kind
  ON tax_detail_entries (
    company_id, source_doc_type, source_doc_id, source_line_id, tax_kind
  )
  WHERE reverses_tax_detail_id IS NULL
    AND source_line_id IS NOT NULL;

CREATE OR REPLACE FUNCTION fn_add_tax_detail(
  p_company_id UUID,
  p_branch_id UUID,
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_source_line_id UUID,
  p_tax_kind TEXT,
  p_tax_code_id UUID,
  p_vat_code_id UUID,
  p_atc_code_id UUID,
  p_tax_base NUMERIC,
  p_tax_rate NUMERIC,
  p_tax_amount NUMERIC,
  p_tax_period_id UUID,
  p_posting_date DATE,
  p_document_date DATE,
  p_counterparty_id UUID,
  p_counterparty_tin TEXT,
  p_counterparty_name TEXT,
  p_income_nature TEXT DEFAULT NULL,
  p_is_reversal BOOLEAN DEFAULT false,
  p_reverses_tax_detail_id UUID DEFAULT NULL,
  p_filing_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  PERFORM fn_assert_posting_source(
    p_source_doc_type,
    p_source_doc_id,
    p_company_id
  );

  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches
    WHERE id = p_branch_id AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Tax-detail branch does not belong to the source company';
  END IF;

  IF p_tax_period_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM fiscal_periods
    WHERE id = p_tax_period_id
      AND company_id = p_company_id
      AND p_document_date BETWEEN start_date AND end_date
  ) THEN
    RAISE EXCEPTION 'Tax-detail period does not cover the document date';
  END IF;

  IF p_reverses_tax_detail_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM tax_detail_entries
    WHERE id = p_reverses_tax_detail_id
      AND company_id = p_company_id
      AND source_doc_type = UPPER(BTRIM(p_source_doc_type))
      AND source_doc_id = p_source_doc_id
  ) THEN
    RAISE EXCEPTION 'Reversed tax-detail row does not belong to this source';
  END IF;

  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id, source_line_id,
    tax_kind, tax_code_id, vat_code_id, atc_code_id,
    tax_base, tax_rate, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name, income_nature,
    is_reversal, reverses_tax_detail_id, filing_status
  ) VALUES (
    p_company_id, p_branch_id, UPPER(BTRIM(p_source_doc_type)), p_source_doc_id,
    p_source_line_id, p_tax_kind, p_tax_code_id, p_vat_code_id, p_atc_code_id,
    ROUND(COALESCE(p_tax_base, 0), 2), p_tax_rate,
    ROUND(COALESCE(p_tax_amount, 0), 2), p_tax_period_id,
    COALESCE(p_posting_date, CURRENT_DATE), p_document_date,
    p_counterparty_id, p_counterparty_tin, p_counterparty_name,
    NULLIF(BTRIM(COALESCE(p_income_nature, '')), ''),
    COALESCE(p_is_reversal, false), p_reverses_tax_detail_id,
    COALESCE(p_filing_status, 'draft')
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_reverse_tax_detail_entries(
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_reversal_date DATE,
  p_fiscal_period_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row tax_detail_entries%ROWTYPE;
BEGIN
  FOR v_row IN
    SELECT t.*
    FROM tax_detail_entries t
    WHERE t.source_doc_type = UPPER(BTRIM(p_source_doc_type))
      AND t.source_doc_id = p_source_doc_id
      AND t.is_reversal = false
      AND NOT EXISTS (
        SELECT 1 FROM tax_detail_entries r
        WHERE r.reverses_tax_detail_id = t.id
      )
    ORDER BY t.id
    FOR UPDATE
  LOOP
    PERFORM fn_add_tax_detail(
      v_row.company_id, v_row.branch_id,
      v_row.source_doc_type, v_row.source_doc_id, v_row.source_line_id,
      v_row.tax_kind, v_row.tax_code_id, v_row.vat_code_id, v_row.atc_code_id,
      -v_row.tax_base, v_row.tax_rate, -v_row.tax_amount,
      p_fiscal_period_id, CURRENT_DATE, p_reversal_date,
      v_row.counterparty_id, v_row.counterparty_tin, v_row.counterparty_name,
      v_row.income_nature, true, v_row.id, 'draft'
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Shared posting/reversal audit and reversal mutation primitive.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_record_posting_event(
  p_company_id UUID,
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_event_type TEXT,
  p_journal_entry_id UUID DEFAULT NULL,
  p_details JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF UPPER(BTRIM(COALESCE(p_event_type, ''))) NOT IN
     ('POSTED', 'REVERSED', 'VOIDED', 'CANCELLED', 'BOUNCED') THEN
    RAISE EXCEPTION 'Unsupported posting event %', p_event_type;
  END IF;

  PERFORM fn_assert_posting_source(
    p_source_doc_type,
    p_source_doc_id,
    p_company_id
  );

  INSERT INTO sys_audit_logs (
    company_id, table_name, record_id, action, old_data, new_data, changed_by
  ) VALUES (
    p_company_id,
    'posting_event',
    p_source_doc_id,
    'UPDATE',
    NULL,
    jsonb_build_object(
      'event_type', UPPER(BTRIM(p_event_type)),
      'source_doc_type', UPPER(BTRIM(p_source_doc_type)),
      'journal_entry_id', p_journal_entry_id,
      'details', COALESCE(p_details, '{}'::JSONB)
    ),
    auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_reverse_posted_journal_entry(
  p_original_je_id UUID,
  p_reversal_date DATE,
  p_reference_doc_type TEXT,
  p_reference_doc_id UUID,
  p_je_number TEXT,
  p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original journal_entries%ROWTYPE;
  v_reversal_id UUID;
  v_line RECORD;
BEGIN
  SELECT * INTO v_original
  FROM journal_entries
  WHERE id = p_original_je_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_original.company_id) THEN
    RAISE EXCEPTION 'Original journal entry not found or access denied';
  END IF;

  PERFORM fn_assert_posting_source(
    v_original.reference_doc_type,
    v_original.reference_doc_id,
    v_original.company_id
  );

  IF v_original.reversed_by_je_id IS NOT NULL THEN
    RETURN v_original.reversed_by_je_id;
  END IF;

  IF v_original.status <> 'posted' THEN
    RAISE EXCEPTION 'Only posted journal entries can be reversed (current status: %)',
      v_original.status;
  END IF;

  v_reversal_id := fn_create_posted_journal_entry(
    v_original.company_id,
    v_original.branch_id,
    p_je_number,
    COALESCE(p_reversal_date, CURRENT_DATE),
    p_description,
    UPPER(BTRIM(p_reference_doc_type)),
    p_reference_doc_id
  );

  FOR v_line IN
    SELECT *
    FROM journal_entry_lines
    WHERE je_id = v_original.id
    ORDER BY line_number
  LOOP
    PERFORM fn_add_posting_line(
      v_reversal_id, v_line.line_number, v_line.account_id,
      'REVERSAL — ' || COALESCE(v_line.description, ''),
      v_line.credit_amount, v_line.debit_amount,
      v_line.branch_id, v_line.department_id, v_line.cost_center_id
    );
  END LOOP;

  PERFORM fn_finalize_journal_entry(v_reversal_id);

  UPDATE journal_entries
  SET status = 'reversed',
      reversed_by_je_id = v_reversal_id,
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = v_original.id;

  RETURN v_reversal_id;
END;
$$;

-- Revalidate the source inside the central JE constructor.  The constraint
-- trigger remains the final backstop for two-phase fixed-asset/schedule writers.
CREATE OR REPLACE FUNCTION fn_create_posted_journal_entry(
  p_company_id UUID,
  p_branch_id UUID,
  p_je_number TEXT,
  p_je_date DATE,
  p_description TEXT,
  p_reference_doc_type TEXT,
  p_reference_doc_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id UUID;
  v_je_id UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  PERFORM fn_assert_posting_source(
    p_reference_doc_type,
    p_reference_doc_id,
    p_company_id
  );
  v_period_id := fn_require_open_fiscal_period(p_company_id, p_je_date, true);

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, p_je_date, v_period_id,
    p_description, UPPER(BTRIM(p_reference_doc_type)), p_reference_doc_id,
    'posted', 0, 0, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  RETURN v_je_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Core AR/AP writers migrated to create/add/finalize + shared tax writer.
-- Public signatures and posting/preview results remain unchanged.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec sales_invoices%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_tax RECORD;
  v_line_no INTEGER := 1;
  v_total_credit NUMERIC(15,2) := 0;
BEGIN
  v_begin := fn_begin_source_posting(
    'SI', p_invoice_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM sales_invoices WHERE id = p_invoice_id;
  PERFORM fn_validate_sales_invoice_accounting_ready(p_invoice_id);
  PERFORM fn_validate_sales_invoice_vat_registration(p_invoice_id);
  PERFORM fn_validate_invoice_posting_totals('SI', p_invoice_id);
  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date,
    'Sales Invoice ' || v_rec.si_number || ' — ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  PERFORM fn_add_posting_line(
    v_je_id, 1, v_cfg.ar_account_id,
    'AR — ' || v_rec.customer_name_snapshot,
    v_rec.total_amount, 0,
    v_rec.branch_id, NULL, NULL
  );
  v_line_no := 2;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum,
           sil.description AS line_description
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.revenue_account_id,
      'Revenue — ' || v_line.line_description,
      0, v_line.net_sum,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.vat_payable_account_id,
      'Output VAT — ' || v_rec.si_number,
      0, v_rec.total_vat_amount,
      v_rec.branch_id, NULL, NULL
    );
    v_total_credit := v_total_credit + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_credit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check that all lines have revenue accounts assigned.',
      v_rec.total_amount, v_total_credit;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT sil.vat_code_id,
           SUM(sil.net_amount) AS tax_base,
           COALESCE(SUM(sil.vat_amount), 0) AS tax_amount
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY sil.vat_code_id
    HAVING SUM(sil.net_amount) <> 0 OR COALESCE(SUM(sil.vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id, NULL,
      'output_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.date)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_vendor_bill(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec vendor_bills%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_tax RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
BEGIN
  v_begin := fn_begin_source_posting(
    'VB', p_bill_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM vendor_bills WHERE id = p_bill_id;
  PERFORM fn_validate_vendor_bill_accounting_ready(p_bill_id);
  PERFORM fn_validate_vendor_bill_vat_registration(p_bill_id);
  PERFORM fn_validate_invoice_posting_totals('VB', p_bill_id);
  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_input_vat_amount > 0 AND v_cfg.input_vat_account_id IS NULL THEN
    RAISE EXCEPTION 'Input VAT account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date,
    'Vendor Bill ' || v_rec.bill_number || ' — ' || v_rec.supplier_name_snapshot,
    'VB', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  FOR v_line IN
    SELECT vbl.expense_account_id, SUM(vbl.net_amount) AS net_sum,
           vbl.description AS line_description
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.expense_account_id IS NOT NULL
    GROUP BY vbl.expense_account_id, vbl.description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.expense_account_id,
      'Expense — ' || v_line.line_description,
      v_line.net_sum, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_debit := v_total_debit + v_line.net_sum;
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.input_vat_account_id,
      'Input VAT — ' || v_rec.bill_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_total_debit := v_total_debit + v_rec.total_input_vat_amount;
    v_line_no := v_line_no + 1;
  END IF;

  PERFORM fn_add_posting_line(
    v_je_id, v_line_no, v_cfg.ap_account_id,
    'AP — ' || v_rec.supplier_name_snapshot,
    0, v_rec.total_amount,
    v_rec.branch_id, NULL, NULL
  );

  IF ABS(v_rec.total_amount - v_total_debit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.',
      v_total_debit, v_rec.total_amount;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE vendor_bills
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT vbl.vat_code_id,
           SUM(vbl.net_amount) AS tax_base,
           COALESCE(SUM(vbl.input_vat_amount), 0) AS tax_amount
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY vbl.vat_code_id
    HAVING SUM(vbl.net_amount) <> 0 OR COALESCE(SUM(vbl.input_vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, NULL,
      'input_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'VB', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.bill_date)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec receipts%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_cash_account UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_ar_credit NUMERIC(15,2);
  v_line RECORD;
BEGIN
  v_begin := fn_begin_source_posting(
    'OR', p_receipt_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM receipts WHERE id = p_receipt_id;
  PERFORM fn_validate_receipt_cwt_ready(p_receipt_id);
  PERFORM fn_validate_settlement_posting('OR', p_receipt_id);

  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_cwt > 0 AND v_cfg.ewt_withheld_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Withheld account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_account := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_account IS NULL THEN
    RAISE EXCEPTION 'No bank account on receipt and no default cash account configured.';
  END IF;

  v_ar_credit := v_rec.total_amount + v_rec.total_cwt;
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date,
    'Official Receipt ' || v_rec.receipt_number || ' - ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  PERFORM fn_add_posting_line(
    v_je_id, 1, v_cash_account,
    'Cash received - ' || v_rec.receipt_number,
    v_rec.total_amount, 0,
    v_rec.branch_id, NULL, NULL
  );

  IF v_rec.total_cwt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, 2, v_cfg.ewt_withheld_account_id,
      'CWT receivable - ' || v_rec.receipt_number,
      v_rec.total_cwt, 0,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  PERFORM fn_add_posting_line(
    v_je_id, CASE WHEN v_rec.total_cwt > 0 THEN 3 ELSE 2 END,
    v_cfg.ar_account_id,
    'AR cleared - ' || v_rec.receipt_number,
    0, v_ar_credit,
    v_rec.branch_id, NULL, NULL
  );
  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_line IN
    SELECT rl.id, rl.payment_amount, rl.cwt_amount, rl.atc_code_id,
           rl.cwt_tax_base, ac.rate AS cwt_rate
    FROM receipt_lines rl
    LEFT JOIN atc_codes ac ON ac.id = rl.atc_code_id
    WHERE rl.receipt_id = v_rec.id
      AND rl.cwt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'OR', v_rec.id, v_line.id,
      'cwt_receivable', NULL, NULL, v_line.atc_code_id,
      ROUND(COALESCE(v_line.cwt_tax_base,
        v_line.payment_amount + v_line.cwt_amount), 2),
      v_line.cwt_rate, v_line.cwt_amount, v_fp_id,
      CURRENT_DATE, v_rec.receipt_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'OR', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.receipt_date)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_payment_voucher(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec payment_vouchers%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_cash_account UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_ap_debit NUMERIC(15,2);
  v_line_no INTEGER := 3;
  v_line RECORD;
BEGIN
  v_begin := fn_begin_source_posting(
    'PV', p_voucher_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM payment_vouchers WHERE id = p_voucher_id;
  PERFORM fn_validate_payment_voucher_ewt_ready(p_voucher_id);
  PERFORM fn_validate_settlement_posting('PV', p_voucher_id);

  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;
  IF NOT FOUND OR v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_ewt > 0 AND v_cfg.ewt_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'EWT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_cash_account := COALESCE(v_rec.bank_account_id, v_cfg.default_cash_account_id);
  IF v_cash_account IS NULL THEN
    RAISE EXCEPTION 'No bank account on voucher and no default cash account configured.';
  END IF;

  v_ap_debit := v_rec.total_amount + v_rec.total_ewt;
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-PV-' || v_rec.voucher_number, v_rec.voucher_date,
    'Payment Voucher ' || v_rec.voucher_number || ' - ' || v_rec.supplier_name_snapshot,
    'PV', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  PERFORM fn_add_posting_line(
    v_je_id, 1, v_cfg.ap_account_id,
    'AP cleared - ' || v_rec.voucher_number,
    v_ap_debit, 0,
    v_rec.branch_id, NULL, NULL
  );
  PERFORM fn_add_posting_line(
    v_je_id, 2, v_cash_account,
    'Cash paid - ' || v_rec.voucher_number,
    0, v_rec.total_amount,
    v_rec.branch_id, NULL, NULL
  );

  IF v_rec.total_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.ewt_payable_account_id,
      'EWT withheld - ' || v_rec.voucher_number,
      0, v_rec.total_ewt,
      v_rec.branch_id, NULL, NULL
    );
  END IF;
  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE payment_vouchers
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_line IN
    SELECT pvl.id, pvl.payment_amount, pvl.ewt_amount, pvl.atc_code_id,
           pvl.ewt_tax_base, pvl.ewt_income_nature,
           ac.rate AS ewt_rate
    FROM payment_voucher_lines pvl
    LEFT JOIN atc_codes ac ON ac.id = pvl.atc_code_id
    WHERE pvl.payment_voucher_id = v_rec.id
      AND pvl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'PV', v_rec.id, v_line.id,
      'ewt_payable', NULL, NULL, v_line.atc_code_id,
      ROUND(COALESCE(v_line.ewt_tax_base,
        v_line.payment_amount + v_line.ewt_amount), 2),
      v_line.ewt_rate, v_line.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.voucher_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_line.ewt_income_nature
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'PV', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.voucher_date)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Core reversal paths use the shared exact-opposite primitive.  Existing
-- reference_doc_type/id conventions are preserved for CAS/source compatibility.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_bt_reverse_je(
  p_company_id UUID,
  p_branch_id UUID,
  p_orig_je_id UUID,
  p_ref_type TEXT,
  p_ref_id UUID,
  p_je_number TEXT,
  p_memo TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original journal_entries%ROWTYPE;
  v_reversal_id UUID;
  v_reason TEXT := NULLIF(BTRIM(COALESCE(p_memo, '')), '');
BEGIN
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A cancellation reason is required';
  END IF;
  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  SELECT * INTO v_original
  FROM journal_entries
  WHERE id = p_orig_je_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_original.company_id) THEN
    RAISE EXCEPTION 'Original journal entry not found or access denied';
  END IF;
  IF v_original.company_id IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Original journal company does not match cancellation company';
  END IF;
  IF v_original.reversed_by_je_id IS NOT NULL THEN
    RETURN v_original.reversed_by_je_id;
  END IF;

  PERFORM fn_assert_source_journal_link(
    p_ref_type, p_ref_id, p_orig_je_id, p_company_id
  );

  v_reversal_id := fn_reverse_posted_journal_entry(
    p_orig_je_id,
    CURRENT_DATE,
    UPPER(BTRIM(p_ref_type)),
    p_ref_id,
    p_je_number,
    'REVERSAL: ' || COALESCE(v_original.description, v_original.je_number)
      || ' — ' || v_reason
  );

  PERFORM fn_record_posting_event(
    p_company_id, p_ref_type, p_ref_id, 'REVERSED', v_reversal_id,
    jsonb_build_object('reason', v_reason, 'original_journal_entry_id', p_orig_je_id)
  );
  RETURN v_reversal_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_reverse_je(
  p_je_id UUID,
  p_reversal_date DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je journal_entries%ROWTYPE;
  v_reversal_date DATE := COALESCE(p_reversal_date, CURRENT_DATE);
  v_number TEXT;
  v_reversal_id UUID;
BEGIN
  SELECT * INTO v_je FROM journal_entries WHERE id = p_je_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_je.company_id) THEN
    RAISE EXCEPTION 'Journal entry not found or access denied';
  END IF;
  IF v_je.reference_doc_type NOT IN ('MANUAL', 'RECURRING') THEN
    RAISE EXCEPTION 'Journal entry % belongs to source type %; use the source document void/cancel workflow',
      v_je.je_number, COALESCE(v_je.reference_doc_type, '<none>');
  END IF;
  IF v_je.reversed_by_je_id IS NOT NULL THEN
    RETURN v_je.reversed_by_je_id;
  END IF;

  v_number := 'REV-' || v_je.je_number;
  IF EXISTS (
    SELECT 1 FROM journal_entries
    WHERE company_id = v_je.company_id AND je_number = v_number
  ) THEN
    v_number := 'REV-' || v_je.je_number || '-' || TO_CHAR(clock_timestamp(), 'HH24MISSMS');
  END IF;

  v_reversal_id := fn_reverse_posted_journal_entry(
    v_je.id, v_reversal_date,
    'REV', v_je.id,
    v_number,
    'Reversal of ' || v_je.je_number || COALESCE(' — ' || v_je.description, '')
  );

  PERFORM fn_record_posting_event(
    v_je.company_id, 'REV', v_je.id, 'REVERSED', v_reversal_id,
    jsonb_build_object('reversal_date', v_reversal_date)
  );
  RETURN v_reversal_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_void_sales_invoice(
  p_invoice_id UUID,
  p_void_reason_id UUID,
  p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
  v_reason TEXT;
BEGIN
  SELECT * INTO v_rec
  FROM sales_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Sales invoice not found or access denied';
  END IF;
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Invoice is already voided';
  END IF;

  IF p_void_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason
    FROM void_reason_codes
    WHERE id = p_void_reason_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid or inactive void reason';
    END IF;
  END IF;
  v_reason := COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), v_reason);
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A void reason is required';
  END IF;
  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  IF v_rec.status = 'posted' THEN
    PERFORM fn_assert_source_journal_link(
      'SI', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
    );
    v_reversal_id := fn_reverse_posted_journal_entry(
      v_rec.journal_entry_id, CURRENT_DATE,
      'REV', v_rec.id,
      'JE-REV-' || v_rec.si_number,
      'Reversal of SI ' || v_rec.si_number || ' (' || v_rec.customer_name_snapshot || ') — ' || v_reason
    );
    SELECT fiscal_period_id INTO v_period_id
    FROM journal_entries WHERE id = v_reversal_id;
    PERFORM fn_reverse_tax_detail_entries('SI', v_rec.id, CURRENT_DATE, v_period_id);
  END IF;

  UPDATE sales_invoices
  SET status = 'cancelled',
      void_reason_id = p_void_reason_id,
      memo = COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), memo),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', v_rec.id, 'VOIDED', v_reversal_id,
    jsonb_build_object('void_reason_id', p_void_reason_id, 'reason', v_reason)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_void_vendor_bill(
  p_bill_id UUID,
  p_void_reason_id UUID,
  p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec vendor_bills%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
  v_reason TEXT;
BEGIN
  SELECT * INTO v_rec
  FROM vendor_bills
  WHERE id = p_bill_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Vendor bill not found or access denied';
  END IF;
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Bill is already cancelled';
  END IF;

  IF p_void_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason
    FROM void_reason_codes
    WHERE id = p_void_reason_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid or inactive void reason';
    END IF;
  END IF;
  v_reason := COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), v_reason);
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A void reason is required';
  END IF;
  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  IF v_rec.status = 'posted' THEN
    PERFORM fn_assert_source_journal_link(
      'VB', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
    );
    v_reversal_id := fn_reverse_posted_journal_entry(
      v_rec.journal_entry_id, CURRENT_DATE,
      'REV', v_rec.id,
      'JE-REV-' || v_rec.bill_number,
      'Void of Vendor Bill ' || v_rec.bill_number || ' (' || v_rec.supplier_name_snapshot || ') — ' || v_reason
    );
    SELECT fiscal_period_id INTO v_period_id
    FROM journal_entries WHERE id = v_reversal_id;
    PERFORM fn_reverse_tax_detail_entries('VB', v_rec.id, CURRENT_DATE, v_period_id);
  END IF;

  UPDATE vendor_bills
  SET status = 'cancelled',
      void_reason_id = p_void_reason_id,
      memo = COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), memo),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'VB', v_rec.id, 'VOIDED', v_reversal_id,
    jsonb_build_object('void_reason_id', p_void_reason_id, 'reason', v_reason)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_cancel_payment_voucher(
  p_voucher_id UUID,
  p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec payment_vouchers%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
  v_reason TEXT := NULLIF(BTRIM(COALESCE(p_memo, '')), '');
BEGIN
  SELECT * INTO v_rec
  FROM payment_vouchers
  WHERE id = p_voucher_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Payment voucher not found or access denied';
  END IF;
  IF v_rec.status <> 'posted' OR v_rec.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only posted payment vouchers can be voided (current: %)', v_rec.status;
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A cancellation reason is required';
  END IF;
  PERFORM fn_assert_source_journal_link(
    'PV', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
  );

  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  v_reversal_id := fn_reverse_posted_journal_entry(
    v_rec.journal_entry_id, CURRENT_DATE,
    'PV', v_rec.id,
    'JE-VOID-' || v_rec.voucher_number,
    'VOID: Payment Voucher ' || v_rec.voucher_number || ' — ' || v_reason
  );
  SELECT fiscal_period_id INTO v_period_id
  FROM journal_entries WHERE id = v_reversal_id;
  PERFORM fn_reverse_tax_detail_entries('PV', v_rec.id, CURRENT_DATE, v_period_id);

  UPDATE payment_vouchers
  SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'PV', v_rec.id, 'CANCELLED', v_reversal_id,
    jsonb_build_object('reason', v_reason)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec receipts%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
BEGIN
  SELECT * INTO v_rec
  FROM receipts
  WHERE id = p_receipt_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Receipt not found or access denied';
  END IF;
  IF v_rec.status <> 'posted' OR v_rec.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only posted receipts can be marked as bounced (current status: %)', v_rec.status;
  END IF;
  PERFORM fn_assert_source_journal_link(
    'OR', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
  );

  v_reversal_id := fn_reverse_posted_journal_entry(
    v_rec.journal_entry_id, CURRENT_DATE,
    'REV', v_rec.id,
    'JE-REV-' || v_rec.receipt_number,
    'Bounced Receipt ' || v_rec.receipt_number
  );
  SELECT fiscal_period_id INTO v_period_id
  FROM journal_entries WHERE id = v_reversal_id;
  PERFORM fn_reverse_tax_detail_entries('OR', v_rec.id, CURRENT_DATE, v_period_id);

  UPDATE receipts
  SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'OR', v_rec.id, 'BOUNCED', v_reversal_id,
    jsonb_build_object('reversal_date', CURRENT_DATE)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_cancel_check_voucher(
  p_cv_id UUID,
  p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec check_vouchers%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
  v_reason TEXT := NULLIF(BTRIM(COALESCE(p_memo, '')), '');
BEGIN
  SELECT * INTO v_rec
  FROM check_vouchers
  WHERE id = p_cv_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Check voucher not found or access denied';
  END IF;
  IF v_rec.status NOT IN ('posted', 'released') THEN
    RAISE EXCEPTION 'Only posted or released check vouchers can be cancelled (current: %)',
      v_rec.status;
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A cancellation reason is required';
  END IF;

  PERFORM fn_assert_source_journal_link(
    'CV', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
  );
  v_reversal_id := fn_bt_reverse_je(
    v_rec.company_id, v_rec.branch_id, v_rec.journal_entry_id,
    'CV', v_rec.id, 'JE-CV-REV-' || v_rec.cv_number, v_reason
  );
  SELECT fiscal_period_id INTO v_period_id
  FROM journal_entries WHERE id = v_reversal_id;
  PERFORM fn_reverse_tax_detail_entries('CV', v_rec.id, CURRENT_DATE, v_period_id);

  UPDATE check_vouchers
  SET status = 'cancelled', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'CV', v_rec.id, 'CANCELLED', v_reversal_id,
    jsonb_build_object('reason', v_reason)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Secondary saved-source writers: acquire the same source-row lock before
-- delegating to the historical implementation.  This is intentionally a thin
-- compatibility layer: module-specific calculations remain authoritative while
-- concurrency, final source normalization, balance checks, and event evidence
-- are shared.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_complete_secondary_posting(
  p_document_type TEXT,
  p_source_id UUID,
  p_journal_entry_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source JSONB;
  v_company_id UUID;
  v_je_id UUID := p_journal_entry_id;
BEGIN
  v_source := fn_resolve_posting_source(p_document_type, p_source_id, false);
  v_company_id := NULLIF(v_source->>'company_id', '')::UUID;

  IF v_je_id IS NULL THEN
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE company_id = v_company_id
      AND reference_doc_type = UPPER(BTRIM(p_document_type))
      AND reference_doc_id = p_source_id
      AND status IN ('posted', 'reversed')
      AND je_number NOT LIKE '%-REV-%'
      AND je_number NOT LIKE 'JE-VOID-%'
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    -- PR, AMORT, REVREC, and FA_DEPR historically attach the final source after
    -- inserting the JE.  Normalize explicitly in addition to their link trigger.
    UPDATE journal_entries
    SET reference_doc_type = UPPER(BTRIM(p_document_type)),
        reference_doc_id = p_source_id,
        updated_at = NOW()
    WHERE id = v_je_id
      AND (
        reference_doc_type IS DISTINCT FROM UPPER(BTRIM(p_document_type))
        OR reference_doc_id IS DISTINCT FROM p_source_id
      );
    PERFORM fn_finalize_journal_entry(v_je_id);
  END IF;

  PERFORM fn_record_posting_event(
    v_company_id, p_document_type, p_source_id, 'POSTED', v_je_id,
    jsonb_build_object('writer_protocol', 'source_lock_wrapper')
  );
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_credit_memo(UUID)
  RENAME TO fn_post_credit_memo_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_credit_memo(p_cm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting(
    'CM', p_cm_id, ARRAY['draft','approved'], ARRAY['applied']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_credit_memo_source_locked_impl(p_cm_id);
  PERFORM fn_complete_secondary_posting('CM', p_cm_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_debit_memo(UUID)
  RENAME TO fn_post_debit_memo_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_debit_memo(p_dm_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting(
    'DM', p_dm_id, ARRAY['draft','approved'], ARRAY['paid']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_debit_memo_source_locked_impl(p_dm_id);
  PERFORM fn_complete_secondary_posting('DM', p_dm_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_cash_purchase(UUID)
  RENAME TO fn_post_cash_purchase_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting('CP', p_cp_id, ARRAY['draft'], ARRAY['posted']);
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_cash_purchase_source_locked_impl(p_cp_id);
  PERFORM fn_complete_secondary_posting('CP', p_cp_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_vendor_credit(UUID)
  RENAME TO fn_post_vendor_credit_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting(
    'VC', p_vc_id, ARRAY['draft'], ARRAY['open','applied']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_vendor_credit_source_locked_impl(p_vc_id);
  PERFORM fn_complete_secondary_posting('VC', p_vc_id, NULL);
END;
$$;

ALTER FUNCTION fn_complete_purchase_return(UUID)
  RENAME TO fn_complete_purchase_return_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_complete_purchase_return(p_return_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'PR', p_return_id, ARRAY['shipped'], ARRAY['completed']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_complete_purchase_return_source_locked_impl(p_return_id);
  SELECT journal_entry_id INTO v_je_id FROM purchase_returns WHERE id = p_return_id;
  PERFORM fn_complete_secondary_posting('PR', p_return_id, v_je_id);
END;
$$;

ALTER FUNCTION fn_post_fund_transfer(UUID)
  RENAME TO fn_post_fund_transfer_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_fund_transfer(p_ft_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting('FT', p_ft_id, ARRAY['draft'], ARRAY['posted']);
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_fund_transfer_source_locked_impl(p_ft_id);
  PERFORM fn_complete_secondary_posting('FT', p_ft_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_inter_branch_transfer(UUID)
  RENAME TO fn_post_inter_branch_transfer_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_inter_branch_transfer(p_ibt_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting('IBT', p_ibt_id, ARRAY['draft'], ARRAY['posted']);
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_inter_branch_transfer_source_locked_impl(p_ibt_id);
  PERFORM fn_complete_secondary_posting('IBT', p_ibt_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_bank_adjustment(UUID)
  RENAME TO fn_post_bank_adjustment_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_bank_adjustment(p_ba_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting('BADJ', p_ba_id, ARRAY['draft'], ARRAY['posted']);
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_bank_adjustment_source_locked_impl(p_ba_id);
  PERFORM fn_complete_secondary_posting('BADJ', p_ba_id, NULL);
END;
$$;

ALTER FUNCTION fn_approve_petty_cash_voucher(UUID)
  RENAME TO fn_approve_petty_cash_voucher_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_approve_petty_cash_voucher(p_pcv_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting(
    'PCV', p_pcv_id, ARRAY['draft'], ARRAY['approved','replenished']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_approve_petty_cash_voucher_source_locked_impl(p_pcv_id);
  PERFORM fn_complete_secondary_posting('PCV', p_pcv_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_petty_cash_replenishment(UUID)
  RENAME TO fn_post_petty_cash_replenishment_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_petty_cash_replenishment(p_pcr_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB;
BEGIN
  v_begin := fn_begin_source_posting('PCR', p_pcr_id, ARRAY['draft'], ARRAY['posted']);
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN RETURN; END IF;
  PERFORM fn_post_petty_cash_replenishment_source_locked_impl(p_pcr_id);
  PERFORM fn_complete_secondary_posting('PCR', p_pcr_id, NULL);
END;
$$;

ALTER FUNCTION fn_post_stock_adjustment(UUID)
  RENAME TO fn_post_stock_adjustment_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_stock_adjustment(p_adjustment_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'INV_ADJ', p_adjustment_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_stock_adjustment_source_locked_impl(p_adjustment_id);
  PERFORM fn_complete_secondary_posting('INV_ADJ', p_adjustment_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_stock_transfer(UUID)
  RENAME TO fn_post_stock_transfer_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_stock_transfer(p_transfer_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  -- This lock is essential even when both warehouses map to the same inventory
  -- account and the historical implementation intentionally creates no JE.
  v_begin := fn_begin_source_posting(
    'INV_STX', p_transfer_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_stock_transfer_source_locked_impl(p_transfer_id);
  PERFORM fn_complete_secondary_posting('INV_STX', p_transfer_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_goods_issue(UUID)
  RENAME TO fn_post_goods_issue_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_goods_issue(p_issue_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'INV_GI', p_issue_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_goods_issue_source_locked_impl(p_issue_id);
  PERFORM fn_complete_secondary_posting('INV_GI', p_issue_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_physical_count(UUID)
  RENAME TO fn_post_physical_count_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_physical_count(p_sheet_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'INV_COUNT', p_sheet_id,
    ARRAY['draft','counting','variance_review'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_physical_count_source_locked_impl(p_sheet_id);
  PERFORM fn_complete_secondary_posting('INV_COUNT', p_sheet_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_depreciation_entry(UUID)
  RENAME TO fn_post_depreciation_entry_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_depreciation_entry(p_entry_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'FA_DEPR', p_entry_id, ARRAY['pending'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_depreciation_entry_source_locked_impl(p_entry_id);
  PERFORM fn_complete_secondary_posting('FA_DEPR', p_entry_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_amortization_entry(UUID)
  RENAME TO fn_post_amortization_entry_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_amortization_entry(p_entry_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'AMORT', p_entry_id, ARRAY['pending'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_amortization_entry_source_locked_impl(p_entry_id);
  PERFORM fn_complete_secondary_posting('AMORT', p_entry_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_post_revenue_recognition_entry(UUID)
  RENAME TO fn_post_revenue_recognition_entry_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_post_revenue_recognition_entry(p_entry_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'REVREC', p_entry_id, ARRAY['pending'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN NULLIF(v_begin->>'existing_journal_entry_id', '')::UUID;
  END IF;
  v_je_id := fn_post_revenue_recognition_entry_source_locked_impl(p_entry_id);
  PERFORM fn_complete_secondary_posting('REVREC', p_entry_id, v_je_id);
  RETURN v_je_id;
END;
$$;

ALTER FUNCTION fn_execute_recurring_template(UUID, DATE)
  RENAME TO fn_execute_recurring_template_source_locked_impl;
CREATE OR REPLACE FUNCTION fn_execute_recurring_template(
  p_template_id UUID,
  p_je_date DATE
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_begin JSONB; v_je_id UUID;
BEGIN
  v_begin := fn_begin_source_posting('RECURRING', p_template_id, NULL, NULL);

  SELECT id INTO v_je_id
  FROM journal_entries
  WHERE company_id = (v_begin->>'company_id')::UUID
    AND reference_doc_type = 'RECURRING'
    AND reference_doc_id = p_template_id
    AND je_date = p_je_date
    AND status IN ('posted','reversed')
    AND je_number NOT LIKE '%-REV-%'
  ORDER BY created_at DESC
  LIMIT 1;
  IF v_je_id IS NOT NULL THEN RETURN v_je_id; END IF;

  PERFORM fn_require_open_fiscal_period(
    (v_begin->>'company_id')::UUID, p_je_date, true
  );

  v_je_id := fn_execute_recurring_template_source_locked_impl(p_template_id, p_je_date);
  PERFORM fn_complete_secondary_posting('RECURRING', p_template_id, v_je_id);
  RETURN v_je_id;
END;
$$;

-- The held-out 00004 owns the CV function body.  Lock its source at the JE
-- boundary without redefining that body; CV creates its JE before tax/status
-- side effects, so a competing transaction cannot pass this lock and persist a
-- duplicate.  All other saved-source writers above lock before module work.
CREATE OR REPLACE FUNCTION fn_lock_unwrapped_posting_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source JSONB;
  v_company_id UUID;
BEGIN
  IF NEW.status = 'posted'
     AND NEW.reference_doc_type = 'CV'
     AND NEW.reference_doc_id IS NOT NULL THEN
    v_source := fn_resolve_posting_source('CV', NEW.reference_doc_id, true);
    v_company_id := NULLIF(v_source->>'company_id', '')::UUID;
    IF v_company_id IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'Posting source company % does not match journal company %',
        v_company_id, NEW.company_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_unwrapped_posting_source ON journal_entries;
CREATE TRIGGER trg_lock_unwrapped_posting_source
  BEFORE INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_lock_unwrapped_posting_source();

-- ---------------------------------------------------------------------------
-- 7. Privilege boundary.  Public posting RPCs remain callable; every helper
-- that can create a JE/line/tax row, reverse evidence, or mutate inventory cost
-- internals is owner-only and can be reached only through SECURITY DEFINER RPCs.
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION fn_resolve_posting_source(TEXT, UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_assert_posting_source(TEXT, UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_begin_source_posting(TEXT, UUID, TEXT[], TEXT[])
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_assert_source_journal_link(TEXT, UUID, UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_validate_invoice_posting_totals(TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_validate_settlement_posting(TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_enforce_journal_entry_source()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_lock_unwrapped_posting_source()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_add_tax_detail(
  UUID, UUID, TEXT, UUID, UUID, TEXT, UUID, UUID, UUID,
  NUMERIC, NUMERIC, NUMERIC, UUID, DATE, DATE, UUID, TEXT, TEXT,
  TEXT, BOOLEAN, UUID, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_record_posting_event(UUID, TEXT, UUID, TEXT, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_reverse_posted_journal_entry(UUID, DATE, TEXT, UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_complete_secondary_posting(TEXT, UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_create_posted_journal_entry(UUID, UUID, TEXT, DATE, TEXT, TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_finalize_journal_entry(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_reverse_tax_detail_entries(TEXT, UUID, DATE, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_bt_reverse_je(UUID, UUID, UUID, TEXT, UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION fn_ensure_stock_balance(UUID, UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_consume_cost_layers(UUID, UUID, UUID, NUMERIC, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_add_cost_layer(UUID, UUID, UUID, DATE, NUMERIC, NUMERIC, TEXT, UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_update_wac(UUID, UUID, NUMERIC, NUMERIC)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION fn_post_credit_memo_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_debit_memo_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_cash_purchase_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_vendor_credit_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_complete_purchase_return_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_fund_transfer_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_inter_branch_transfer_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_bank_adjustment_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_approve_petty_cash_voucher_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_petty_cash_replenishment_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_stock_adjustment_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_stock_transfer_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_goods_issue_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_physical_count_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_depreciation_entry_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_amortization_entry_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_post_revenue_recognition_entry_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION fn_execute_recurring_template_source_locked_impl(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_vendor_bill(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_payment_voucher(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_credit_memo(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_debit_memo(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_cash_purchase(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_complete_purchase_return(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_fund_transfer(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_inter_branch_transfer(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_bank_adjustment(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_approve_petty_cash_voucher(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_petty_cash_replenishment(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_stock_adjustment(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_stock_transfer(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_goods_issue(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_physical_count(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_depreciation_entry(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_amortization_entry(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_revenue_recognition_entry(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_execute_recurring_template(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_reverse_je(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_void_sales_invoice(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_void_vendor_bill(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_cancel_payment_voucher(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_bounce_receipt(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_cancel_check_voucher(UUID, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION fn_begin_source_posting(TEXT, UUID, TEXT[], TEXT[]) IS
  'Locks a governed saved source before module work and returns an idempotent should_post/existing-JE decision.';
COMMENT ON FUNCTION fn_add_tax_detail(
  UUID, UUID, TEXT, UUID, UUID, TEXT, UUID, UUID, UUID,
  NUMERIC, NUMERIC, NUMERIC, UUID, DATE, DATE, UUID, TEXT, TEXT,
  TEXT, BOOLEAN, UUID, TEXT
) IS
  'Internal tax-ledger writer with source/company/period validation and stable source-line identity.';
