-- ══════════════════════════════════════════════════════════════════════════════
-- S19: AUDIT & CAS MODULE
-- Expands audit trigger coverage to transaction, master-data, and system-
-- parameter tables for BIR CAS (Computerized Accounting System) compliance.
-- Adds Attachment Register and DAT/Export log tables.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Expand audit trigger coverage (fn_audit_trigger already exists) ────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- Master data
    'departments', 'cost_centers', 'chart_of_accounts', 'payment_terms',
    'warehouses', 'employees', 'bank_accounts',
    -- Transactions
    'purchase_orders', 'vendor_bills', 'payment_vouchers', 'cash_purchases',
    'vendor_credits', 'purchase_returns', 'journal_entries', 'bank_adjustments',
    'check_vouchers', 'petty_cash_vouchers', 'stock_adjustments', 'stock_transfers',
    'goods_issues', 'fixed_assets', 'asset_disposals',
    -- System parameters
    'number_series', 'approval_workflows', 'sys_feature_enablement',
    'compliance_profiles', 'tax_codes', 'vat_codes', 'atc_codes'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
       CREATE TRIGGER trg_audit_%1$s
         AFTER INSERT OR UPDATE OR DELETE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();',
      t
    );
  END LOOP;
END;
$$;

-- ── 2. Attachment Register: manual log of supporting documents ────────────────
CREATE TABLE cas_attachment_register (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID          NOT NULL REFERENCES companies(id),
  document_type     TEXT          NOT NULL CHECK (document_type IN ('receipt','contract','permit','invoice_scan','id_document','other')),
  reference_no      TEXT,
  source_doc_type   TEXT,
  source_doc_ref    TEXT,
  file_name         TEXT          NOT NULL,
  description       TEXT,
  remarks           TEXT,
  uploaded_by       UUID,
  uploaded_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE cas_attachment_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cas_ar_read"   ON cas_attachment_register FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cas_ar_insert" ON cas_attachment_register FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "cas_ar_update" ON cas_attachment_register FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE TRIGGER trg_cas_ar_updated_at
  BEFORE UPDATE ON cas_attachment_register
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 3. CAS Export Log: DAT file generations + general export history ──────────
CREATE TABLE cas_export_log (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     UUID          NOT NULL REFERENCES companies(id),
  export_type    TEXT          NOT NULL CHECK (export_type IN ('dat_file','csv_export','report')),
  report_name    TEXT          NOT NULL,
  period_year    INTEGER,
  period_month   INTEGER       CHECK (period_month BETWEEN 1 AND 12),
  period_quarter INTEGER       CHECK (period_quarter BETWEEN 1 AND 4),
  file_name      TEXT          NOT NULL,
  row_count      INTEGER       NOT NULL DEFAULT 0,
  generated_by   UUID,
  generated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  remarks        TEXT
);

ALTER TABLE cas_export_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cas_el_read"   ON cas_export_log FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cas_el_insert" ON cas_export_log FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));

CREATE INDEX idx_cas_export_log_company ON cas_export_log (company_id, generated_at DESC);
