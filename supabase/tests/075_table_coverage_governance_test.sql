-- PXL-AUD-059 coverage governance guard.
--
-- Governs every public base table with an explicit coverage class so product
-- readiness cannot be overstated by unexercised or ambiguously empty tables.
-- The authoritative human-readable matrix is
--   docs/PXL/13. Testing and Validation/PXL_TABLE_COVERAGE_MATRIX.md
-- and this file is the deterministic machine check that keeps it honest.
--
-- Coverage classes:
--   canonical-populated  Exercised (non-empty) by the canonical demo seed.
--   reference-populated  Seeded non-empty by migrations/reference data (always).
--   workflow-deferred    Populated only by a supported UI/RPC workflow that the
--                        canonical seed intentionally does not run yet.
--   future-deferred      Documented future/unimplemented module; intentionally empty.
--   reference-empty      Reference/config table intentionally empty in canonical
--                        (PHP-only FX, default-open flags, ungenerated exports,
--                        governed global BIR config).
--
-- The guard fails on UNEXPECTED active-table emptiness (an expected-populated
-- table that is empty) and on governance drift (a new unclassified table, a
-- stale registry entry, or a deferred table that silently became populated).
-- It never fails merely because an intentionally deferred module is empty.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

CREATE TEMP TABLE _coverage_registry (
  table_name     text PRIMARY KEY,
  coverage_class text NOT NULL
);

INSERT INTO _coverage_registry (table_name, coverage_class) VALUES
  ('amortization_entries', 'future-deferred'),
  ('amortization_schedules', 'future-deferred'),
  ('approval_instances', 'workflow-deferred'),
  ('approval_requests', 'workflow-deferred'),
  ('approval_workflow_steps', 'canonical-populated'),
  ('approval_workflows', 'canonical-populated'),
  ('asset_depreciation_entries', 'future-deferred'),
  ('asset_disposals', 'future-deferred'),
  ('asset_impairments', 'future-deferred'),
  ('asset_transfers', 'future-deferred'),
  ('atc_codes', 'reference-populated'),
  ('bank_accounts', 'canonical-populated'),
  ('bank_adjustments', 'future-deferred'),
  ('bank_recon_items', 'future-deferred'),
  ('bank_reconciliations', 'future-deferred'),
  ('bir_config_maintainers', 'reference-empty'),
  ('bir_form_mappings', 'reference-empty'),
  ('bir_forms', 'reference-empty'),
  ('book_tax_reconciliation', 'future-deferred'),
  ('branches', 'canonical-populated'),
  ('cas_attachment_register', 'future-deferred'),
  ('cas_document_number_issuances', 'canonical-populated'),
  ('cas_document_void_events', 'canonical-populated'),
  ('cas_export_artifacts', 'future-deferred'),
  ('cas_export_log', 'future-deferred'),
  ('cash_count_sheets', 'future-deferred'),
  ('cash_purchase_lines', 'canonical-populated'),
  ('cash_purchases', 'canonical-populated'),
  ('chart_of_accounts', 'canonical-populated'),
  ('check_voucher_lines', 'future-deferred'),
  ('check_vouchers', 'future-deferred'),
  ('coa_template_lines', 'reference-populated'),
  ('coa_templates', 'reference-populated'),
  ('companies', 'canonical-populated'),
  ('company_accounting_config', 'canonical-populated'),
  ('company_inventory_config', 'workflow-deferred'),
  ('company_payment_modes', 'workflow-deferred'),
  ('company_provisioning_modules', 'reference-populated'),
  ('company_provisioning_runs', 'workflow-deferred'),
  ('company_provisioning_template_modules', 'reference-populated'),
  ('company_provisioning_templates', 'reference-populated'),
  ('compliance_1601eq_working_papers_headers', 'future-deferred'),
  ('compliance_1601eq_working_papers_lines', 'future-deferred'),
  ('compliance_1601fq_working_papers_headers', 'future-deferred'),
  ('compliance_1601fq_working_papers_lines', 'future-deferred'),
  ('compliance_ewt_working_papers_headers', 'future-deferred'),
  ('compliance_ewt_working_papers_lines', 'future-deferred'),
  ('compliance_fwt_working_papers_headers', 'future-deferred'),
  ('compliance_fwt_working_papers_lines', 'future-deferred'),
  ('compliance_profiles', 'canonical-populated'),
  ('compliance_pt_working_papers_headers', 'future-deferred'),
  ('compliance_pt_working_papers_lines', 'future-deferred'),
  ('compliance_vat_working_papers_headers', 'future-deferred'),
  ('compliance_vat_working_papers_lines', 'future-deferred'),
  ('cost_centers', 'canonical-populated'),
  ('credit_memo_lines', 'canonical-populated'),
  ('credit_memos', 'canonical-populated'),
  ('currencies', 'reference-populated'),
  ('customer_groups', 'workflow-deferred'),
  ('customers', 'canonical-populated'),
  ('dashboard_layouts', 'reference-populated'),
  ('dashboard_widgets', 'reference-populated'),
  ('debit_memo_lines', 'future-deferred'),
  ('debit_memos', 'future-deferred'),
  ('delivery_receipt_lines', 'canonical-populated'),
  ('delivery_receipts', 'canonical-populated'),
  ('departments', 'canonical-populated'),
  ('employees', 'canonical-populated'),
  ('ewt_returns', 'future-deferred'),
  ('exchange_rates', 'reference-empty'),
  ('fiscal_periods', 'canonical-populated'),
  ('fiscal_years', 'canonical-populated'),
  ('fixed_asset_categories', 'future-deferred'),
  ('fixed_assets', 'future-deferred'),
  ('form_2306_issuances', 'future-deferred'),
  ('form_2307_issuance_lines', 'future-deferred'),
  ('form_2307_issuances', 'future-deferred'),
  ('form_2307_tracking', 'future-deferred'),
  ('functional_entities', 'workflow-deferred'),
  ('fund_transfers', 'future-deferred'),
  ('fwt_returns', 'future-deferred'),
  ('goods_issue_lines', 'future-deferred'),
  ('goods_issues', 'future-deferred'),
  ('income_tax_computations', 'future-deferred'),
  ('inter_branch_transfers', 'future-deferred'),
  ('inventory_cost_layers', 'canonical-populated'),
  ('inventory_transactions', 'canonical-populated'),
  ('item_barcodes', 'workflow-deferred'),
  ('item_categories', 'canonical-populated'),
  ('item_media', 'workflow-deferred'),
  ('item_uom_conversions', 'workflow-deferred'),
  ('items', 'canonical-populated'),
  ('itr_filings', 'future-deferred'),
  ('journal_entries', 'canonical-populated'),
  ('journal_entry_lines', 'canonical-populated'),
  ('locations', 'workflow-deferred'),
  ('master_data_export_logs', 'workflow-deferred'),
  ('master_data_import_batches', 'workflow-deferred'),
  ('master_data_import_registry', 'reference-populated'),
  ('master_data_import_rows', 'workflow-deferred'),
  ('master_data_permissions', 'reference-populated'),
  ('master_data_role_permissions', 'reference-populated'),
  ('master_data_sod_conflicts', 'reference-populated'),
  ('mcit_computations', 'future-deferred'),
  ('nolco_schedule', 'future-deferred'),
  ('number_series', 'canonical-populated'),
  ('party_contacts', 'workflow-deferred'),
  ('payment_terms', 'canonical-populated'),
  ('payment_voucher_lines', 'canonical-populated'),
  ('payment_vouchers', 'canonical-populated'),
  ('percentage_tax_codes', 'canonical-populated'),
  ('petty_cash_funds', 'future-deferred'),
  ('petty_cash_replenishments', 'future-deferred'),
  ('petty_cash_vouchers', 'future-deferred'),
  ('physical_count_sheet_lines', 'canonical-populated'),
  ('physical_count_sheets', 'canonical-populated'),
  ('projects', 'workflow-deferred'),
  ('pt_returns', 'future-deferred'),
  ('purchase_order_lines', 'canonical-populated'),
  ('purchase_orders', 'canonical-populated'),
  ('purchase_return_lines', 'future-deferred'),
  ('purchase_returns', 'future-deferred'),
  ('receipt_lines', 'canonical-populated'),
  ('receipts', 'canonical-populated'),
  ('receiving_report_lines', 'canonical-populated'),
  ('receiving_reports', 'canonical-populated'),
  ('recurring_journal_template_lines', 'future-deferred'),
  ('recurring_journal_templates', 'future-deferred'),
  ('ref_banks', 'reference-populated'),
  ('ref_compliance_forms', 'reference-populated'),
  ('ref_document_types', 'reference-populated'),
  ('ref_feature_definitions', 'reference-populated'),
  ('ref_payment_modes', 'reference-populated'),
  ('ref_posting_source_types', 'reference-populated'),
  ('ref_rdo_codes', 'reference-populated'),
  ('ref_reason_codes', 'reference-populated'),
  ('report_snapshots', 'workflow-deferred'),
  ('revenue_recognition_entries', 'future-deferred'),
  ('revenue_recognition_schedules', 'future-deferred'),
  ('sales_invoice_lines', 'canonical-populated'),
  ('sales_invoices', 'canonical-populated'),
  ('sales_order_lines', 'canonical-populated'),
  ('sales_orders', 'canonical-populated'),
  ('sales_quotation_lines', 'canonical-populated'),
  ('sales_quotations', 'canonical-populated'),
  ('stock_adjustment_lines', 'canonical-populated'),
  ('stock_adjustments', 'canonical-populated'),
  ('stock_balances', 'canonical-populated'),
  ('stock_transfer_lines', 'canonical-populated'),
  ('stock_transfers', 'canonical-populated'),
  ('supplier_debit_memo_lines', 'future-deferred'),
  ('supplier_debit_memos', 'future-deferred'),
  ('supplier_groups', 'workflow-deferred'),
  ('suppliers', 'canonical-populated'),
  ('sys_audit_logs', 'canonical-populated'),
  ('sys_feature_enablement', 'reference-empty'),
  ('tax_calendar_events', 'canonical-populated'),
  ('tax_codes', 'reference-populated'),
  ('tax_credits_schedule', 'future-deferred'),
  ('tax_detail_entries', 'canonical-populated'),
  ('transaction_events', 'canonical-populated'),
  ('units_of_measure', 'canonical-populated'),
  ('user_company_branch_scopes', 'workflow-deferred'),
  ('user_company_memberships', 'canonical-populated'),
  ('vat_codes', 'reference-populated'),
  ('vat_returns', 'future-deferred'),
  ('vendor_bill_lines', 'canonical-populated'),
  ('vendor_bills', 'canonical-populated'),
  ('vendor_credit_applications', 'canonical-populated'),
  ('vendor_credit_lines', 'canonical-populated'),
  ('vendor_credits', 'canonical-populated'),
  ('void_reason_codes', 'reference-populated'),
  ('warehouse_item_settings', 'canonical-populated'),
  ('warehouse_zones', 'reference-empty'),
  ('warehouses', 'canonical-populated'),
  ('withholding_remittances', 'future-deferred');

-- Returns registry tables of a class that currently hold zero rows.
CREATE FUNCTION pg_temp.coverage_empty_in_class(p_class text)
RETURNS TABLE(table_name text)
LANGUAGE plpgsql AS $fn$
DECLARE
  r record;
  c bigint;
BEGIN
  FOR r IN
    SELECT reg.table_name FROM _coverage_registry reg
    WHERE reg.coverage_class = p_class
    ORDER BY reg.table_name
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', r.table_name) INTO c;
    IF c = 0 THEN
      table_name := r.table_name;
      RETURN NEXT;
    END IF;
  END LOOP;
END
$fn$;

-- Returns registry tables of a class that currently hold at least one row.
CREATE FUNCTION pg_temp.coverage_nonempty_in_class(p_class text)
RETURNS TABLE(table_name text)
LANGUAGE plpgsql AS $fn$
DECLARE
  r record;
  c bigint;
BEGIN
  FOR r IN
    SELECT reg.table_name FROM _coverage_registry reg
    WHERE reg.coverage_class = p_class
    ORDER BY reg.table_name
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', r.table_name) INTO c;
    IF c > 0 THEN
      table_name := r.table_name;
      RETURN NEXT;
    END IF;
  END LOOP;
END
$fn$;

SELECT (SELECT count(*) FROM companies WHERE trade_name LIKE 'DEMO-%') >= 5 AS seed_loaded \gset

SELECT plan(8);

-- Structural governance (independent of the canonical seed) ------------------

SELECT is_empty(
  $$SELECT t.table_name
      FROM information_schema.tables t
      WHERE t.table_schema = 'public'
        AND t.table_type = 'BASE TABLE'
        AND NOT EXISTS (
          SELECT 1 FROM _coverage_registry r WHERE r.table_name = t.table_name
        )$$,
  'every public base table is classified in the coverage registry'
);

SELECT is_empty(
  $$SELECT r.table_name
      FROM _coverage_registry r
      WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.tables t
        WHERE t.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
          AND t.table_name = r.table_name
      )$$,
  'every coverage registry entry maps to an existing public base table'
);

SELECT is_empty(
  $$SELECT table_name FROM _coverage_registry
      WHERE coverage_class NOT IN (
        'canonical-populated','reference-populated',
        'workflow-deferred','future-deferred','reference-empty'
      )$$,
  'every coverage registry entry uses a governed coverage class'
);

SELECT is_empty(
  $$SELECT * FROM pg_temp.coverage_empty_in_class('reference-populated')$$,
  'all reference-populated tables retain their governed migration/reference rows'
);

-- Canonical-seed baseline governance -----------------------------------------

\if :seed_loaded

SELECT is_empty(
  $$SELECT * FROM pg_temp.coverage_empty_in_class('canonical-populated')$$,
  'all canonical-populated tables are exercised by the canonical seed (no unexpected active-table emptiness)'
);

SELECT is_empty(
  $$SELECT * FROM pg_temp.coverage_nonempty_in_class('workflow-deferred')$$,
  'workflow-deferred tables remain unexercised by the canonical seed until their workflow runs'
);

SELECT is_empty(
  $$SELECT * FROM pg_temp.coverage_nonempty_in_class('future-deferred')$$,
  'future-deferred tables remain intentionally empty under the canonical baseline'
);

SELECT is_empty(
  $$SELECT * FROM pg_temp.coverage_nonempty_in_class('reference-empty')$$,
  'reference-empty tables remain intentionally empty under the canonical baseline'
);

\else

SELECT skip(4, 'canonical demo seed not loaded; run the canonical lane before the seed-gated coverage checks');

\endif

SELECT * FROM finish();
ROLLBACK;
