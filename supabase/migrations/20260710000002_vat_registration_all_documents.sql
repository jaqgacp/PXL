-- Complete VAT-registration enforcement across every VAT-bearing document.
--
-- The original PXL-AUD-006 gate covered sales invoices and vendor bills only.
-- This migration centralizes the same registration and direction checks for
-- credit/debit memos, cash purchases, and vendor credits. Cash sales use the
-- sales invoice tables and therefore inherit the sales-invoice triggers.
-- Direct line/header VAT amounts are also guarded so a zero-rate or NULL code
-- cannot be paired with a positive VAT amount for a non-VAT/exempt company.

-- ── Shared validation helpers ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_validate_company_vat_amount(
  p_company_id UUID,
  p_vat_amount NUMERIC,
  p_context TEXT DEFAULT 'VAT amount'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tax_registration TEXT;
BEGIN
  SELECT tax_registration
  INTO v_tax_registration
  FROM companies
  WHERE id = p_company_id;

  IF v_tax_registration IS NULL THEN
    RAISE EXCEPTION 'Company not found';
  END IF;

  IF v_tax_registration <> 'vat' AND ABS(COALESCE(p_vat_amount, 0)) > 0.005 THEN
    RAISE EXCEPTION 'Non-VAT or exempt companies cannot record a non-zero %.', p_context;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_document_vat_registration(
  p_company_id UUID,
  p_document_id UUID,
  p_line_table REGCLASS,
  p_parent_column NAME,
  p_line_vat_amount_column NAME,
  p_transaction_type TEXT,
  p_header_vat_amount NUMERIC,
  p_context TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
BEGIN
  PERFORM fn_validate_company_vat_amount(
    p_company_id,
    p_header_vat_amount,
    p_context || ' header VAT amount'
  );

  FOR v_line IN EXECUTE format(
    'SELECT company_id, vat_code_id, %I AS vat_amount FROM %s WHERE %I = $1',
    p_line_vat_amount_column,
    p_line_table,
    p_parent_column
  ) USING p_document_id
  LOOP
    IF v_line.company_id IS DISTINCT FROM p_company_id THEN
      RAISE EXCEPTION '% line company does not match its document company', p_context;
    END IF;

    PERFORM fn_validate_company_vat_code(
      p_company_id,
      v_line.vat_code_id,
      p_transaction_type,
      p_context || ' VAT code'
    );
    PERFORM fn_validate_company_vat_amount(
      p_company_id,
      v_line.vat_amount,
      p_context || ' line VAT amount'
    );
  END LOOP;
END;
$$;

-- Generic parent-aware line trigger. Trigger arguments:
-- transaction type, parent table, parent FK, VAT amount column, context.
CREATE OR REPLACE FUNCTION fn_require_document_line_vat_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := to_jsonb(NEW);
  v_parent_id UUID;
  v_line_company_id UUID;
  v_parent_company_id UUID;
  v_vat_code_id UUID;
  v_vat_amount NUMERIC;
BEGIN
  IF TG_NARGS <> 5 THEN
    RAISE EXCEPTION 'VAT line trigger is misconfigured on %', TG_TABLE_NAME;
  END IF;

  v_parent_id := NULLIF(v_row ->> TG_ARGV[2], '')::UUID;
  v_line_company_id := NULLIF(v_row ->> 'company_id', '')::UUID;
  v_vat_code_id := NULLIF(v_row ->> 'vat_code_id', '')::UUID;
  v_vat_amount := COALESCE(NULLIF(v_row ->> TG_ARGV[3], '')::NUMERIC, 0);

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION '% parent document is required', TG_ARGV[4];
  END IF;

  EXECUTE format('SELECT company_id FROM %I WHERE id = $1', TG_ARGV[1])
  INTO v_parent_company_id
  USING v_parent_id;

  IF v_parent_company_id IS NULL THEN
    RAISE EXCEPTION '% parent document was not found', TG_ARGV[4];
  END IF;
  IF v_line_company_id IS DISTINCT FROM v_parent_company_id THEN
    RAISE EXCEPTION '% line company does not match its document company', TG_ARGV[4];
  END IF;

  PERFORM fn_validate_company_vat_code(
    v_parent_company_id,
    v_vat_code_id,
    TG_ARGV[0],
    TG_ARGV[4] || ' VAT code'
  );
  PERFORM fn_validate_company_vat_amount(
    v_parent_company_id,
    v_vat_amount,
    TG_ARGV[4] || ' line VAT amount'
  );

  RETURN NEW;
END;
$$;

-- Generic header trigger. Trigger arguments:
-- line table, parent FK, line VAT amount column, transaction type,
-- header VAT amount column, context.
CREATE OR REPLACE FUNCTION fn_require_document_header_vat_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := to_jsonb(NEW);
  v_header_vat_amount NUMERIC;
BEGIN
  IF TG_NARGS <> 6 THEN
    RAISE EXCEPTION 'VAT header trigger is misconfigured on %', TG_TABLE_NAME;
  END IF;

  v_header_vat_amount := COALESCE(NULLIF(v_row ->> TG_ARGV[4], '')::NUMERIC, 0);

  PERFORM fn_validate_document_vat_registration(
    NEW.company_id,
    NEW.id,
    TG_ARGV[0]::REGCLASS,
    TG_ARGV[1]::NAME,
    TG_ARGV[2]::NAME,
    TG_ARGV[3],
    v_header_vat_amount,
    TG_ARGV[5]
  );

  RETURN NEW;
END;
$$;

-- ── Line enforcement ──────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_si_line_vat_registration ON sales_invoice_lines;
CREATE TRIGGER trg_si_line_vat_registration
  BEFORE INSERT OR UPDATE OF sales_invoice_id, company_id, vat_code_id, vat_amount
  ON sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'output_vat', 'sales_invoices', 'sales_invoice_id', 'vat_amount', 'Sales invoice'
  );

DROP TRIGGER IF EXISTS trg_vb_line_vat_registration ON vendor_bill_lines;
CREATE TRIGGER trg_vb_line_vat_registration
  BEFORE INSERT OR UPDATE OF vendor_bill_id, company_id, vat_code_id, input_vat_amount
  ON vendor_bill_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'input_vat', 'vendor_bills', 'vendor_bill_id', 'input_vat_amount', 'Vendor bill'
  );

DROP TRIGGER IF EXISTS trg_cm_line_vat_registration ON credit_memo_lines;
CREATE TRIGGER trg_cm_line_vat_registration
  BEFORE INSERT OR UPDATE OF credit_memo_id, company_id, vat_code_id, vat_amount
  ON credit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'output_vat', 'credit_memos', 'credit_memo_id', 'vat_amount', 'Credit memo'
  );

DROP TRIGGER IF EXISTS trg_dm_line_vat_registration ON debit_memo_lines;
CREATE TRIGGER trg_dm_line_vat_registration
  BEFORE INSERT OR UPDATE OF debit_memo_id, company_id, vat_code_id, vat_amount
  ON debit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'output_vat', 'debit_memos', 'debit_memo_id', 'vat_amount', 'Debit memo'
  );

DROP TRIGGER IF EXISTS trg_cp_line_vat_registration ON cash_purchase_lines;
CREATE TRIGGER trg_cp_line_vat_registration
  BEFORE INSERT OR UPDATE OF cp_id, company_id, vat_code_id, input_vat_amount
  ON cash_purchase_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'input_vat', 'cash_purchases', 'cp_id', 'input_vat_amount', 'Cash purchase'
  );

DROP TRIGGER IF EXISTS trg_vc_line_vat_registration ON vendor_credit_lines;
CREATE TRIGGER trg_vc_line_vat_registration
  BEFORE INSERT OR UPDATE OF vc_id, company_id, vat_code_id, input_vat_amount
  ON vendor_credit_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'input_vat', 'vendor_credits', 'vc_id', 'input_vat_amount', 'Vendor credit'
  );

-- ── Header enforcement ────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_si_vat_registration_status ON sales_invoices;
CREATE TRIGGER trg_si_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_vat_amount
  ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'sales_invoice_lines', 'sales_invoice_id', 'vat_amount', 'output_vat',
    'total_vat_amount', 'Sales invoice'
  );

DROP TRIGGER IF EXISTS trg_vb_vat_registration_status ON vendor_bills;
CREATE TRIGGER trg_vb_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_input_vat_amount
  ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'vendor_bill_lines', 'vendor_bill_id', 'input_vat_amount', 'input_vat',
    'total_input_vat_amount', 'Vendor bill'
  );

DROP TRIGGER IF EXISTS trg_cm_vat_registration_status ON credit_memos;
CREATE TRIGGER trg_cm_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_vat_amount
  ON credit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'credit_memo_lines', 'credit_memo_id', 'vat_amount', 'output_vat',
    'total_vat_amount', 'Credit memo'
  );

DROP TRIGGER IF EXISTS trg_dm_vat_registration_status ON debit_memos;
CREATE TRIGGER trg_dm_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_vat_amount
  ON debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'debit_memo_lines', 'debit_memo_id', 'vat_amount', 'output_vat',
    'total_vat_amount', 'Debit memo'
  );

DROP TRIGGER IF EXISTS trg_cp_vat_registration_status ON cash_purchases;
CREATE TRIGGER trg_cp_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_input_vat_amount
  ON cash_purchases
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'cash_purchase_lines', 'cp_id', 'input_vat_amount', 'input_vat',
    'total_input_vat_amount', 'Cash purchase'
  );

DROP TRIGGER IF EXISTS trg_vc_vat_registration_status ON vendor_credits;
CREATE TRIGGER trg_vc_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_input_vat_amount
  ON vendor_credits
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'vendor_credit_lines', 'vc_id', 'input_vat_amount', 'input_vat',
    'total_input_vat_amount', 'Vendor credit'
  );

-- ── Per-code VAT ledger rows for CM / DM / VC ────────────────────────────────

-- The existing post functions write one legacy lump VAT row without a
-- vat_code_id, and write no row for zero-rated/exempt-only documents. Keep the
-- posting implementations intact behind wrappers, then replace only the rows
-- created by that same posting transaction with canonical per-code rows.
CREATE OR REPLACE FUNCTION fn_rebuild_document_vat_details(
  p_source_doc_type TEXT,
  p_source_doc_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cm credit_memos%ROWTYPE;
  v_dm debit_memos%ROWTYPE;
  v_vc vendor_credits%ROWTYPE;
  v_fp_id UUID;
BEGIN
  IF p_source_doc_type = 'CM' THEN
    SELECT * INTO v_cm FROM credit_memos WHERE id = p_source_doc_id;
    IF NOT FOUND OR v_cm.status <> 'applied' THEN
      RAISE EXCEPTION 'Posted credit memo not found';
    END IF;

    SELECT id INTO v_fp_id
    FROM fiscal_periods
    WHERE company_id = v_cm.company_id
      AND v_cm.cm_date BETWEEN start_date AND end_date
    ORDER BY start_date DESC
    LIMIT 1;

    DELETE FROM tax_detail_entries
    WHERE source_doc_type = 'CM'
      AND source_doc_id = v_cm.id
      AND tax_kind = 'output_vat';

    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    )
    SELECT
      v_cm.company_id, v_cm.branch_id, 'CM', v_cm.id,
      'output_vat', cml.vat_code_id,
      -SUM(cml.net_amount), -COALESCE(SUM(cml.vat_amount), 0), v_fp_id,
      COALESCE(v_cm.posted_at::DATE, CURRENT_DATE), v_cm.cm_date,
      v_cm.customer_id, v_cm.customer_tin_snapshot, v_cm.customer_name_snapshot,
      true
    FROM credit_memo_lines cml
    WHERE cml.credit_memo_id = v_cm.id
      AND cml.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_cm.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY cml.vat_code_id
    HAVING SUM(cml.net_amount) <> 0 OR COALESCE(SUM(cml.vat_amount), 0) <> 0;

  ELSIF p_source_doc_type = 'DM' THEN
    SELECT * INTO v_dm FROM debit_memos WHERE id = p_source_doc_id;
    IF NOT FOUND OR v_dm.status <> 'paid' THEN
      RAISE EXCEPTION 'Posted debit memo not found';
    END IF;

    SELECT id INTO v_fp_id
    FROM fiscal_periods
    WHERE company_id = v_dm.company_id
      AND v_dm.dm_date BETWEEN start_date AND end_date
    ORDER BY start_date DESC
    LIMIT 1;

    DELETE FROM tax_detail_entries
    WHERE source_doc_type = 'DM'
      AND source_doc_id = v_dm.id
      AND tax_kind = 'output_vat';

    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    )
    SELECT
      v_dm.company_id, v_dm.branch_id, 'DM', v_dm.id,
      'output_vat', dml.vat_code_id,
      SUM(dml.amount), COALESCE(SUM(dml.vat_amount), 0), v_fp_id,
      COALESCE(v_dm.posted_at::DATE, CURRENT_DATE), v_dm.dm_date,
      v_dm.customer_id, v_dm.customer_tin_snapshot, v_dm.customer_name_snapshot,
      false
    FROM debit_memo_lines dml
    WHERE dml.debit_memo_id = v_dm.id
      AND dml.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_dm.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY dml.vat_code_id
    HAVING SUM(dml.amount) <> 0 OR COALESCE(SUM(dml.vat_amount), 0) <> 0;

  ELSIF p_source_doc_type = 'VC' THEN
    SELECT * INTO v_vc FROM vendor_credits WHERE id = p_source_doc_id;
    IF NOT FOUND OR v_vc.status NOT IN ('open', 'applied') THEN
      RAISE EXCEPTION 'Posted vendor credit not found';
    END IF;

    SELECT id INTO v_fp_id
    FROM fiscal_periods
    WHERE company_id = v_vc.company_id
      AND v_vc.credit_date BETWEEN start_date AND end_date
    ORDER BY start_date DESC
    LIMIT 1;

    DELETE FROM tax_detail_entries
    WHERE source_doc_type = 'VC'
      AND source_doc_id = v_vc.id
      AND tax_kind = 'input_vat';

    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    )
    SELECT
      v_vc.company_id, v_vc.branch_id, 'VC', v_vc.id,
      'input_vat', vcl.vat_code_id,
      -SUM(vcl.net_amount), -COALESCE(SUM(vcl.input_vat_amount), 0), v_fp_id,
      COALESCE(v_vc.posted_at::DATE, CURRENT_DATE), v_vc.credit_date,
      v_vc.supplier_id, v_vc.supplier_tin_snapshot, v_vc.supplier_name_snapshot,
      true
    FROM vendor_credit_lines vcl
    WHERE vcl.vc_id = v_vc.id
      AND vcl.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_vc.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY vcl.vat_code_id
    HAVING SUM(vcl.net_amount) <> 0 OR COALESCE(SUM(vcl.input_vat_amount), 0) <> 0;
  ELSE
    RAISE EXCEPTION 'Unsupported VAT detail source type: %', p_source_doc_type;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_rebuild_document_vat_details(TEXT, UUID)
  FROM PUBLIC, anon, authenticated;

ALTER FUNCTION fn_post_credit_memo(UUID)
  RENAME TO fn_post_credit_memo_vat_lump_impl;
REVOKE ALL ON FUNCTION fn_post_credit_memo_vat_lump_impl(UUID)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION fn_post_credit_memo(p_cm_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_post_credit_memo_vat_lump_impl(p_cm_id);
  PERFORM fn_rebuild_document_vat_details('CM', p_cm_id);
END;
$$;

REVOKE ALL ON FUNCTION fn_post_credit_memo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_post_credit_memo(UUID) TO authenticated, service_role;

ALTER FUNCTION fn_post_debit_memo(UUID)
  RENAME TO fn_post_debit_memo_vat_lump_impl;
REVOKE ALL ON FUNCTION fn_post_debit_memo_vat_lump_impl(UUID)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION fn_post_debit_memo(p_dm_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_post_debit_memo_vat_lump_impl(p_dm_id);
  PERFORM fn_rebuild_document_vat_details('DM', p_dm_id);
END;
$$;

REVOKE ALL ON FUNCTION fn_post_debit_memo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_post_debit_memo(UUID) TO authenticated, service_role;

ALTER FUNCTION fn_post_vendor_credit(UUID)
  RENAME TO fn_post_vendor_credit_vat_lump_impl;
REVOKE ALL ON FUNCTION fn_post_vendor_credit_vat_lump_impl(UUID)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION fn_post_vendor_credit(p_vc_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_post_vendor_credit_vat_lump_impl(p_vc_id);
  PERFORM fn_rebuild_document_vat_details('VC', p_vc_id);
END;
$$;

REVOKE ALL ON FUNCTION fn_post_vendor_credit(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_post_vendor_credit(UUID) TO authenticated, service_role;

-- Normalize already-posted documents. Report snapshots remain immutable, while
-- the live tax ledger is rebuilt from the document lines that produced the GL.
DO $$
DECLARE
  v_doc RECORD;
BEGIN
  FOR v_doc IN
    SELECT 'CM'::TEXT AS source_type, cm.id
    FROM credit_memos cm
    WHERE cm.status = 'applied'
      AND EXISTS (
        SELECT 1 FROM credit_memo_lines l
        WHERE l.credit_memo_id = cm.id AND l.vat_code_id IS NOT NULL
      )
    UNION ALL
    SELECT 'DM'::TEXT, dm.id
    FROM debit_memos dm
    WHERE dm.status = 'paid'
      AND EXISTS (
        SELECT 1 FROM debit_memo_lines l
        WHERE l.debit_memo_id = dm.id AND l.vat_code_id IS NOT NULL
      )
    UNION ALL
    SELECT 'VC'::TEXT, vc.id
    FROM vendor_credits vc
    WHERE vc.status IN ('open', 'applied')
      AND EXISTS (
        SELECT 1 FROM vendor_credit_lines l
        WHERE l.vc_id = vc.id AND l.vat_code_id IS NOT NULL
      )
  LOOP
    PERFORM fn_rebuild_document_vat_details(v_doc.source_type, v_doc.id);
  END LOOP;
END;
$$;

-- tax_detail_entries is posting evidence, not an application-writable table.
-- SECURITY DEFINER posting/reversal functions continue to write it; direct
-- authenticated mutations are denied by RLS.
DROP POLICY IF EXISTS "tde_insert" ON tax_detail_entries;
DROP POLICY IF EXISTS "tde_update" ON tax_detail_entries;
DROP POLICY IF EXISTS "tde_delete" ON tax_detail_entries;
DROP POLICY IF EXISTS "tde_no_direct_insert" ON tax_detail_entries;
DROP POLICY IF EXISTS "tde_no_direct_update" ON tax_detail_entries;
DROP POLICY IF EXISTS "tde_no_direct_delete" ON tax_detail_entries;

CREATE POLICY "tde_no_direct_insert" ON tax_detail_entries
  FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "tde_no_direct_update" ON tax_detail_entries
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY "tde_no_direct_delete" ON tax_detail_entries
  FOR DELETE TO authenticated USING (false);

-- ── VAT export enforcement ────────────────────────────────────────────────────

-- Retain the existing implementations behind guarded public wrappers. This
-- keeps the PostgREST signatures stable and avoids duplicating the snapshot
-- builders, while ensuring registration is checked before reconciliation or
-- snapshot work begins.
ALTER FUNCTION fn_snapshot_vat_export(UUID, TEXT, INTEGER, INTEGER, TEXT)
  RENAME TO fn_snapshot_vat_export_unchecked;

REVOKE ALL ON FUNCTION fn_snapshot_vat_export_unchecked(UUID, TEXT, INTEGER, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION fn_snapshot_vat_export(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_month INTEGER,
  p_export_part TEXT DEFAULT 'all'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  PERFORM fn_require_vat_registered_company(
    p_company_id,
    upper(COALESCE(p_report_type, 'VAT')) || ' export'
  );

  RETURN fn_snapshot_vat_export_unchecked(
    p_company_id,
    p_report_type,
    p_year,
    p_month,
    p_export_part
  );
END;
$$;

REVOKE ALL ON FUNCTION fn_snapshot_vat_export(UUID, TEXT, INTEGER, INTEGER, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_snapshot_vat_export(UUID, TEXT, INTEGER, INTEGER, TEXT)
  TO authenticated, service_role;

ALTER FUNCTION fn_snapshot_cas_export(UUID, TEXT, INTEGER, INTEGER, TEXT)
  RENAME TO fn_snapshot_cas_export_unchecked;

REVOKE ALL ON FUNCTION fn_snapshot_cas_export_unchecked(UUID, TEXT, INTEGER, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION fn_snapshot_cas_export(
  p_company_id UUID,
  p_report_type TEXT,
  p_year INTEGER,
  p_month INTEGER,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF lower(COALESCE(p_report_type, '')) IN ('slsp', 'relief') THEN
    PERFORM fn_require_vat_registered_company(
      p_company_id,
      upper(p_report_type) || ' CAS export'
    );
  END IF;

  RETURN fn_snapshot_cas_export_unchecked(
    p_company_id,
    p_report_type,
    p_year,
    p_month,
    p_file_name
  );
END;
$$;

REVOKE ALL ON FUNCTION fn_snapshot_cas_export(UUID, TEXT, INTEGER, INTEGER, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_snapshot_cas_export(UUID, TEXT, INTEGER, INTEGER, TEXT)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION fn_require_vat_export_snapshot_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF upper(NEW.report_type) IN ('SLSP', 'RELIEF', 'CAS_SLSP', 'CAS_RELIEF') THEN
    PERFORM fn_require_vat_registered_company(
      NEW.company_id,
      NEW.report_type || ' snapshot'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_report_snapshot_vat_registration ON report_snapshots;
CREATE TRIGGER trg_report_snapshot_vat_registration
  BEFORE INSERT OR UPDATE OF company_id, report_type
  ON report_snapshots
  FOR EACH ROW EXECUTE FUNCTION fn_require_vat_export_snapshot_registration();

COMMENT ON FUNCTION fn_validate_document_vat_registration(UUID, UUID, REGCLASS, NAME, NAME, TEXT, NUMERIC, TEXT) IS
  'Validates a VAT document header and all lines against company registration, VAT-code direction, and parent-company consistency.';
COMMENT ON FUNCTION fn_snapshot_vat_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'Creates an SLSP/RELIEF snapshot only for VAT-registered companies, then delegates to the immutable export builder.';
COMMENT ON FUNCTION fn_snapshot_cas_export(UUID, TEXT, INTEGER, INTEGER, TEXT) IS
  'Builds CAS exports; SLSP/RELIEF variants require a VAT-registered company while non-VAT CAS report types remain available.';
