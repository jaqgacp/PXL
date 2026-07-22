# PXL Table Coverage Matrix

**Status:** Active authoritative coverage-governance register
**Authority:** Tier 2 governance artifact for PXL-AUD-059 coverage governance; accounting, tax, transaction, security, and findings sources prevail on product rules
**Last Verified:** 2026-07-22 deterministic local canonical lane (176 public base tables; 90 expected-populated, 86 explicitly deferred/empty)
**Applies To:** Every `public` base table; canonical/local validation coverage boundaries and product-readiness claims
**Read When:** Adding a table or workflow, classifying coverage, or reconciling readiness against PXL-AUD-059
**Do Not Read For:** Product accounting/tax rules (see the governing standards) or hosted credentials

## Purpose

This matrix is the maintained, per-table coverage register required by **PXL-AUD-059**. Every `public` base table is classified so product readiness cannot be overstated by tables that are empty for undocumented reasons. The deterministic guard `supabase/tests/075_table_coverage_governance_test.sql` enforces this register: it fails on an unclassified table, a stale entry, an expected-populated table that is empty, or a deferred table that silently became populated. It never fails merely because an intentionally deferred module is empty.

Row counts below are the deterministic **canonical baseline** (fresh migration replay + `canonical_demo_reset.sql` + `canonical_demo_seed.sql` + `canonical_phase3_enrichment.sql` + `canonical_demo_volume.sql`). Re-derive with `npm run test:canonical` and the hosted read-only profiler `supabase/verification/phase3_hosted_read_only.sql`.

## Coverage Classes

| Class | Meaning | Canonical baseline expectation |
| --- | --- | --- |
| `canonical-populated` | Exercised by the canonical demo seed. | Non-empty (guard fails if empty). |
| `reference-populated` | Seeded by migrations/reference data. | Non-empty always (guard fails if empty). |
| `workflow-deferred` | Populated only by a supported UI/RPC workflow the canonical seed does not run yet. | Empty in canonical; promote when exercised. |
| `future-deferred` | Documented future/unimplemented module. | Empty (intentional). |
| `reference-empty` | Reference/config table intentionally empty in canonical. | Empty (intentional). |

## Coverage Summary

| Class | Tables | Governance |
| --- | ---: | --- |
| `canonical-populated` | 66 | Expected non-empty; exercised by canonical regression |
| `reference-populated` | 24 | Expected non-empty; migration/reference seeded |
| `workflow-deferred` | 19 | Explicitly deferred; supported workflow not yet exercised |
| `future-deferred` | 61 | Explicitly deferred; module not implemented end-to-end |
| `reference-empty` | 6 | Intentionally empty reference/config |
| **Total** | **176** | 90 expected-populated / 86 explicitly deferred or empty |

All 176 tables have row-level security enabled with at least one policy. The `Test` column records prior pgTAP regression files that reference the table; guard 075 additionally governs every table's classification.

## Per-Module Coverage

### Company & Organization Setup

**Owner:** Setup / Master Data · **Primary surface:** /company-setup, /master-data

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `companies` | `canonical-populated` | 5 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `branches` | `canonical-populated` | 8 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `departments` | `canonical-populated` | 13 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `cost_centers` | `canonical-populated` | 10 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `company_accounting_config` | `canonical-populated` | 5 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `company_inventory_config` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (3) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `company_payment_modes` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `user_company_memberships` | `canonical-populated` | 25 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `user_company_branch_scopes` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `functional_entities` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `locations` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `projects` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `warehouses` | `canonical-populated` | 6 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `warehouse_zones` | `reference-empty` | 0 | Config/reference (intentionally empty) | on (2) | 075 only | Intentionally empty in canonical; populate only when the specific feature/export is configured. |
| `warehouse_item_settings` | `canonical-populated` | 87 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Master Data — Parties

**Owner:** Master Data · **Primary surface:** /master-data (customers, suppliers, employees)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `customers` | `canonical-populated` | 66 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `customer_groups` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `suppliers` | `canonical-populated` | 56 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `supplier_groups` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `party_contacts` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `employees` | `canonical-populated` | 26 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Master Data — Items & UoM

**Owner:** Master Data · **Primary surface:** /master-data (items, UoM)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `items` | `canonical-populated` | 91 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `item_categories` | `canonical-populated` | 30 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `item_barcodes` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `item_media` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `item_uom_conversions` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `units_of_measure` | `canonical-populated` | 40 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Chart of Accounts & Accounting Config

**Owner:** Accounting Core · **Primary surface:** /company-setup (COA, series, calendar)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `chart_of_accounts` | `canonical-populated` | 215 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `coa_templates` | `reference-populated` | 1 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `coa_template_lines` | `reference-populated` | 41 | Migration / reference seed | on (1) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `number_series` | `canonical-populated` | 264 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `payment_terms` | `canonical-populated` | 25 | Canonical demo seed | on (4) | 075 only | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `fiscal_years` | `canonical-populated` | 5 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `fiscal_periods` | `canonical-populated` | 60 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Sales / Accounts Receivable

**Owner:** Sales / AR · **Primary surface:** /sales/* (quotation → SI → OR → CM)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `sales_quotations` | `canonical-populated` | 1 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `sales_quotation_lines` | `canonical-populated` | 1 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `sales_orders` | `canonical-populated` | 3 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `sales_order_lines` | `canonical-populated` | 3 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `delivery_receipts` | `canonical-populated` | 2 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `delivery_receipt_lines` | `canonical-populated` | 2 | Canonical demo seed | on (4) | 075 only | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `sales_invoices` | `canonical-populated` | 75 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `sales_invoice_lines` | `canonical-populated` | 135 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `receipts` | `canonical-populated` | 6 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `receipt_lines` | `canonical-populated` | 6 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `credit_memos` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `credit_memo_lines` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Purchasing / Accounts Payable

**Owner:** Purchasing / AP · **Primary surface:** /purchasing/* (PO → RR → VB → PV)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `purchase_orders` | `canonical-populated` | 33 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `purchase_order_lines` | `canonical-populated` | 33 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `receiving_reports` | `canonical-populated` | 3 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `receiving_report_lines` | `canonical-populated` | 3 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `vendor_bills` | `canonical-populated` | 36 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `vendor_bill_lines` | `canonical-populated` | 36 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `payment_vouchers` | `canonical-populated` | 5 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `payment_voucher_lines` | `canonical-populated` | 5 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `cash_purchases` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `cash_purchase_lines` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `vendor_credits` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `vendor_credit_lines` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `vendor_credit_applications` | `canonical-populated` | 1 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `debit_memos` | `future-deferred` | 0 | Future module (unimplemented) | on (1) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `debit_memo_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (1) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `purchase_returns` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `purchase_return_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `supplier_debit_memos` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `supplier_debit_memo_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### Inventory

**Owner:** Inventory · **Primary surface:** /inventory/* (movements, transfers, adjustments, counts)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `inventory_transactions` | `canonical-populated` | 26 | Canonical demo seed | on (2) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `inventory_cost_layers` | `canonical-populated` | 12 | Canonical demo seed | on (3) | 075 only | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `stock_balances` | `canonical-populated` | 11 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `stock_transfers` | `canonical-populated` | 2 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `stock_transfer_lines` | `canonical-populated` | 2 | Canonical demo seed | on (2) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `stock_adjustments` | `canonical-populated` | 4 | Canonical demo seed | on (3) | 075 only | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `stock_adjustment_lines` | `canonical-populated` | 4 | Canonical demo seed | on (2) | 075 only | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `physical_count_sheets` | `canonical-populated` | 1 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `physical_count_sheet_lines` | `canonical-populated` | 1 | Canonical demo seed | on (2) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `goods_issues` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `goods_issue_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (2) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### General Ledger & Journals

**Owner:** Accounting Core · **Primary surface:** /accounting/journals, GL reports

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `journal_entries` | `canonical-populated` | 48 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `journal_entry_lines` | `canonical-populated` | 138 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `recurring_journal_templates` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `recurring_journal_template_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `transaction_events` | `canonical-populated` | 289 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Banking / Treasury

**Owner:** Banking / Treasury · **Primary surface:** /banking/* (not yet implemented end-to-end)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `bank_accounts` | `canonical-populated` | 10 | Canonical demo seed | on (3) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `bank_adjustments` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `bank_reconciliations` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `bank_recon_items` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `cash_count_sheets` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `check_vouchers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `check_voucher_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `fund_transfers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `inter_branch_transfers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `petty_cash_funds` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `petty_cash_vouchers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `petty_cash_replenishments` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### Fixed Assets

**Owner:** Fixed Assets · **Primary surface:** /fixed-assets/* (not yet implemented)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `fixed_assets` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `fixed_asset_categories` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `asset_depreciation_entries` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `asset_disposals` | `future-deferred` | 0 | Future module (unimplemented) | on (2) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `asset_impairments` | `future-deferred` | 0 | Future module (unimplemented) | on (2) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `asset_transfers` | `future-deferred` | 0 | Future module (unimplemented) | on (2) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### Schedules & Revenue Recognition

**Owner:** Accounting Core · **Primary surface:** /accounting/schedules (not yet implemented)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `amortization_schedules` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `amortization_entries` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `revenue_recognition_schedules` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `revenue_recognition_entries` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### Tax — Codes, Details & Calendar

**Owner:** Compliance / Tax · **Primary surface:** /tax-setup, tax detail on transactions

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `tax_codes` | `reference-populated` | 8 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `vat_codes` | `reference-populated` | 6 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `percentage_tax_codes` | `canonical-populated` | 2 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `atc_codes` | `reference-populated` | 18 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `tax_detail_entries` | `canonical-populated` | 24 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `tax_calendar_events` | `canonical-populated` | 248 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `compliance_profiles` | `canonical-populated` | 5 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |

### Tax — Returns & Certificates

**Owner:** Compliance / Tax · **Primary surface:** /compliance/* (statutory generators, not implemented)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `ewt_returns` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `fwt_returns` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `pt_returns` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `vat_returns` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `form_2306_issuances` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `form_2307_issuances` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `form_2307_issuance_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `form_2307_tracking` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `withholding_remittances` | `future-deferred` | 0 | Future module (unimplemented) | on (1) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### Tax — Compliance Working Papers

**Owner:** Compliance / Tax · **Primary surface:** /compliance/working-papers (prep workflow, not implemented)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `compliance_1601eq_working_papers_headers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_1601eq_working_papers_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_1601fq_working_papers_headers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_1601fq_working_papers_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_ewt_working_papers_headers` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_ewt_working_papers_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_fwt_working_papers_headers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_fwt_working_papers_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_pt_working_papers_headers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_pt_working_papers_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_vat_working_papers_headers` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `compliance_vat_working_papers_lines` | `future-deferred` | 0 | Future module (unimplemented) | on (4) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### Income Tax

**Owner:** Compliance / Tax · **Primary surface:** /compliance/income-tax (not implemented)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `book_tax_reconciliation` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `income_tax_computations` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `itr_filings` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `mcit_computations` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `nolco_schedule` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `tax_credits_schedule` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### CAS Numbering & Export Artifacts

**Owner:** Compliance / CAS · **Primary surface:** CAS number issuance (auto) + export workflow

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `cas_document_number_issuances` | `canonical-populated` | 215 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `cas_document_void_events` | `canonical-populated` | 1 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `cas_attachment_register` | `future-deferred` | 0 | Future module (unimplemented) | on (3) | 075 only | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `cas_export_artifacts` | `future-deferred` | 0 | Future module (unimplemented) | on (1) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |
| `cas_export_log` | `future-deferred` | 0 | Future module (unimplemented) | on (2) | ✓ | Deferred module — implement the workflow before certification; do not cite as implemented from schema presence. |

### BIR Global Configuration

**Owner:** Compliance / BIR Config · **Primary surface:** /bir-setup (governed maintainer RPCs, PXL-AUD-063)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `bir_forms` | `reference-empty` | 0 | Config/reference (intentionally empty) | on (1) | ✓ | Intentionally empty in canonical; populate only when the specific feature/export is configured. |
| `bir_form_mappings` | `reference-empty` | 0 | Config/reference (intentionally empty) | on (1) | ✓ | Intentionally empty in canonical; populate only when the specific feature/export is configured. |
| `bir_config_maintainers` | `reference-empty` | 0 | Config/reference (intentionally empty) | on (1) | ✓ | Intentionally empty in canonical; populate only when the specific feature/export is configured. |

### Approvals

**Owner:** Transaction Framework / Approvals · **Primary surface:** /approval-workflow (config + inbox)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `approval_workflows` | `canonical-populated` | 2 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `approval_workflow_steps` | `canonical-populated` | 2 | Canonical demo seed | on (4) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `approval_requests` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (1) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `approval_instances` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (1) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |

### Master Data Governance (MDP)

**Owner:** Master Data Governance · **Primary surface:** /master-data (permissions, SOD, import/export)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `master_data_permissions` | `reference-populated` | 301 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `master_data_role_permissions` | `reference-populated` | 616 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `master_data_sod_conflicts` | `reference-populated` | 116 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `master_data_import_registry` | `reference-populated` | 43 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `master_data_import_batches` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (1) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `master_data_import_rows` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (1) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `master_data_export_logs` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (1) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |

### Guided Company Provisioning

**Owner:** Setup / Provisioning · **Primary surface:** /company-setup provisioning wizard (MDP-08)

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `company_provisioning_templates` | `reference-populated` | 1 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `company_provisioning_template_modules` | `reference-populated` | 10 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `company_provisioning_modules` | `reference-populated` | 10 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `company_provisioning_runs` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (1) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |

### Platform, Reference & Audit

**Owner:** Platform / Reference · **Primary surface:** global reference, dashboards, audit log

| Table | Class | Canonical rows | Population mechanism | RLS (policies) | Test | Next action |
| --- | --- | ---: | --- | --- | --- | --- |
| `currencies` | `reference-populated` | 9 | Migration / reference seed | on (1) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `exchange_rates` | `reference-empty` | 0 | Config/reference (intentionally empty) | on (4) | 075 only | Intentionally empty in canonical; populate only when the specific feature/export is configured. |
| `ref_banks` | `reference-populated` | 14 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_compliance_forms` | `reference-populated` | 14 | Migration / reference seed | on (1) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_document_types` | `reference-populated` | 33 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_feature_definitions` | `reference-populated` | 16 | Migration / reference seed | on (1) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_payment_modes` | `reference-populated` | 5 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_posting_source_types` | `reference-populated` | 30 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_rdo_codes` | `reference-populated` | 100 | Migration / reference seed | on (1) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `ref_reason_codes` | `reference-populated` | 10 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `void_reason_codes` | `reference-populated` | 7 | Migration / reference seed | on (1) | ✓ | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `sys_feature_enablement` | `reference-empty` | 0 | Config/reference (intentionally empty) | on (4) | 075 only | Intentionally empty in canonical; populate only when the specific feature/export is configured. |
| `sys_audit_logs` | `canonical-populated` | 2161 | Canonical demo seed | on (1) | ✓ | Maintain canonical coverage; guard 075 keeps it non-empty. |
| `report_snapshots` | `workflow-deferred` | 0 | Supported UI/RPC workflow (not run in canonical) | on (4) | ✓ | Exercise the supported workflow and add a governed fixture + route/RLS evidence to promote to canonical-populated. |
| `dashboard_layouts` | `reference-populated` | 1 | Migration / reference seed | on (2) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |
| `dashboard_widgets` | `reference-populated` | 4 | Migration / reference seed | on (2) | 075 only | Maintain migration/reference seed; guard 075 keeps it non-empty. |

## Deferred-Module Register

The following modules are explicitly deferred. Route presence or schema presence alone must not be cited as implementation (per PXL-AUD-059 and PXL-AUD-067).

- **Banking / Treasury** — reconciliation, check vouchers, fund transfers, inter-branch transfers, petty cash. No governed workflow or fixture.
- **Fixed Assets** — asset register, depreciation, disposal, impairment, transfer. Not implemented in canonical activity.
- **Schedules & Revenue Recognition** — amortization, recurring journals, revenue recognition. Future workflow.
- **Returns & Corrective Documents** — debit memos, supplier debit memos, purchase returns, goods issues. Credit/vendor-credit paths are used instead; these remain unexercised.
- **Statutory Tax Returns, Certificates & Working Papers** — VAT/EWT/FWT/PT returns, 2306/2307 issuances, and all compliance working papers. Tax **detail** is exercised; statutory **generators** are not.
- **Income Tax** — ITR, MCIT, NOLCO, book-tax reconciliation, tax-credit schedules. Unsupported in canonical activity.
- **CAS Export Artifacts** — attachment register and export log/artifacts generate only from an explicit export workflow.
- **BIR Global Configuration** — `bir_forms`/`bir_form_mappings` governed by maintainer RPCs under PXL-AUD-063; empty in canonical by design.
- **Approval Execution** — workflow definitions exist; no approval rule is configured, so `approval_requests`/`approval_instances` stay empty (PXL-AUD-053/MDP-14 govern the foundation).
- **Dimension & optional masters** — `projects`, `locations`, `functional_entities`, party groups/contacts, and item barcode/media/UoM extensions exist but are not seeded (PXL-AUD-053 governs Sales Invoice dimension propagation).

## Maintenance Protocol

1. Adding a `public` base table **requires** a matching row here and in guard 075's registry, or the guard fails on the unclassified table.
2. When a deferred workflow becomes exercised by the canonical seed, promote its tables to `canonical-populated` in both this matrix and guard 075.
3. Removing a table requires deleting its registry entry, or the guard fails on the stale entry.
4. Re-derive counts with `npm run test:canonical`; run `supabase test db --local supabase/tests/075_table_coverage_governance_test.sql` after any schema or seed change.
5. Official status stays in `PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-AUD-059). Do not restate finding status here.
