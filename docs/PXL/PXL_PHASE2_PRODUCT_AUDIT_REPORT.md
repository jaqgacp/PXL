# PXL Phase 2 Product Audit Report

Audit date: 2026-07-16

Scope: canonical demo dataset visibility, implementation readiness, database coverage, deployment safety, UI/UX, accounting, inventory, tax, security, and documentation consistency.

## Environment Verification

Local canonical validation environment:

- Git branch: `main`
- Local Supabase database host: `127.0.0.1:54322`
- Local database name: `postgres`
- Local database user: `postgres`
- Local app URL used for browser audit: `http://127.0.0.1:5173`
- Local Supabase API URL used by app: `http://127.0.0.1:54321`

Hosted Supabase target discovered from the supplied access token:

- Project ref: `bskjkogijpbhukjkagfj`
- Project name: `PXL`
- Database host: `db.bskjkogijpbhukjkagfj.supabase.co`
- Region: `ap-southeast-1`
- Current linked project ref: `bskjkogijpbhukjkagfj`

Hosted project safety was not proven as non-production. No destructive hosted reset and no hosted migration push were performed.

## Deployment Verification

The exact requested command did not run because the installed Supabase CLI does not support `supabase db push --project-ref`.

Additional deployment blockers:

- `supabase migration list --linked` requires a database password or db-url.
- `supabase db push --dry-run --linked` reports held-out local migrations `20260710000004_atc_document_date_versioning.sql` and `20260710000005_cas_numbering_void_dat_controls.sql` would need `--include-all` before later remote history.
- The hosted project has not been explicitly classified as dev/test/preview/demo.

Finding: `PXL-AUD-056`.

## Website Verification Summary

Browser audit command:

```bash
AUDIT_BASE_URL='http://127.0.0.1:5173' NODE_PATH='/home/codespace/.npm/_npx/e41f203b7505f1fb/node_modules' node scripts/audit_canonical_ui.mjs
```

Result:

- Login: passed after local Auth seed and dev CSP fixes.
- Company selector: visible; 5 canonical companies shown.
- Branch selector: visible; ABC HO, Cebu, and Davao shown.
- Period selector: visible; 2026 periods shown.

Visible:

- Company setup, branch setup, customers, suppliers, items/services, warehouses
- Sales quotations, sales orders, delivery-receipt route shell, credit-memo route shell
- Receiving-report route shell, payment voucher `TEST-PV-PARTIAL`, vendor-credit route shell
- Physical-count route shell
- Journal entry opening balance, general ledger accounts
- VAT output summary, balance sheet, income statement

Partially visible:

- Department setup shows department data but not cost-center reference `CC-FIN`.
- Number series shows `SI` and `OR` but not seeded `VB`/`PV` tokens.
- Sales/input tax review pages show tax headings but not seeded source documents.

Missing from expected canonical routes:

- Sales invoices `TEST-SI-STANDALONE`, `TEST-SI-VAT-INCLUSIVE`
- Receipt `TEST-OR-SI-STANDALONE`
- Purchase order `TEST-PO-PARTIAL-RECEIPT`
- Vendor bill `TEST-VB-PARTIAL-PAYMENT`
- Stock balances/movements/transfers/adjustments
- Bank account display tokens
- Trial balance, AR aging, AP aging seeded references
- EWT summary source and amount references

Finding: `PXL-AUD-057`.

## Database Verification Summary

Canonical reset and seed were rerun against local Supabase only.

Seed summary after reset:

- Companies: 5 canonical demo companies
- Branches: 8 canonical demo branches plus one pre-existing/non-canonical company branch row in local DB
- Customers: 13 canonical customers
- Suppliers: 13 canonical suppliers
- Items/services: 53
- Posted sales invoices: 6
- Posted vendor bills: 1
- Inventory transactions: 14

Auth verification:

- Demo users exist in `auth.users`.
- Demo users have email identities.
- Password login for `demo.admin@pxl.local` returns HTTP 200 locally.

## Functional Test Matrix

Executed locally through the canonical pgTAP suite and browser route audit:

| Area | Database Result | Website Result | Status |
| --- | --- | --- | --- |
| Company setup | Seeded and regression-tested | Visible | Usable for demo |
| Branch setup | Seeded and visible | Visible | Usable for demo |
| Customers/suppliers/items | Seeded | Visible | Usable for demo |
| Sales invoice | Posted rows and tests exist | Seeded references missing from route | Product-visible gap |
| Official receipt | Posted row and CWT test exists | Seeded reference missing from route | Product-visible gap |
| Purchase order/receiving/vendor bill | Rows and tests exist | PO/VB refs missing; RR shell visible | Product-visible gap |
| Payment voucher | Posted row exists | `TEST-PV-PARTIAL` visible | Partially usable |
| Inventory stock/transfer/adjustment | Rows and tests exist | Seeded refs missing | Product-visible gap |
| Journal entries/GL | Rows and tests exist | JE and GL visible | Usable for demo |
| TB/AR/AP aging | Tests exist | Seeded refs missing | Product-visible gap |
| VAT/EWT reviews | Tax detail exists | VAT headings visible; EWT source missing | Product-visible gap |
| Security/RLS | pgTAP coverage exists from prior suite | UI role scenarios not exhaustively replayed in this phase | Needs UI security pass |

Full-suite regression status:

- `supabase test db --local supabase/tests/055_canonical_demo_dataset_test.sql`: passed 34/34.
- `npm test`: failed after canonical seed, 55 files / 882 executed tests, with 10 failing files.

The full-suite failures are not hidden by this report. They indicate that the repo still needs deterministic test lanes for fresh-schema tests, canonical-seeded tests, and held-out/experimental migration tests. Finding: `PXL-AUD-061`.

## UI / UX Audit

Confirmed UX issues:

- Login labels are not programmatically associated with inputs; finding `PXL-AUD-060`.
- Product routes can render global navigation and headings while hiding canonical rows, which makes empty/filtered states indistinguishable from missing data.
- Several modules expose route shells before full canonical data traceability is present.
- Route output needs explicit empty-state diagnostics: hidden by company, branch, period, permissions, status, or missing implementation.
- During the audit session, React reported missing unique list keys in `ARAgingPage` and `APAgingPage`; fix when addressing the aging visibility gaps under `PXL-AUD-057`.

## Accounting Audit

Database-level canonical assertions continue to pass for:

- Balanced posted journals in the canonical test.
- Opening balance JE.
- Sales invoice VAT-exclusive and VAT-inclusive calculations.
- Expected CWT versus actual CWT timing.
- Vendor bill input VAT and source EWT.
- GL/tax/inventory source references covered by canonical pgTAP.

Product-visible accounting gaps:

- Trial Balance route did not surface expected account tokens in the browser audit.
- AR/AP aging did not surface seeded source references.
- Sales invoice and vendor bill source rows were not visible from their list routes, blocking source-to-GL walkthrough from UI.

## Inventory Audit

Confirmed fixed control:

- Stock transfer over-availability is blocked server-side by `20260716000001_stock_transfer_availability_guard.sql`.
- Canonical test covers valid transfer, blocked over-transfer, oversell blocking, stock movement, and balance expectations.

Remaining inventory gaps:

- Stock balance, movement, stock transfer, and stock adjustment route probes did not display seeded canonical references.
- Physical count tables and several return/adjustment edge cases remain unpopulated.
- Inactive warehouse/item, downstream dependency voids, and complete valuation reporting are not yet canonicalized.

## Tax Audit

Confirmed database-level scenarios:

- VAT-exclusive sale: 1,000 net + 120 VAT.
- VAT-inclusive sale: 1,120 gross = 1,000 net + 120 VAT.
- Output VAT and input VAT tax-detail assertions.
- Expected CWT on SI remains informational; actual CWT is recognized through OR/tax detail.
- EWT source-basis vendor bill/payment behavior is represented.

Product-visible tax gaps:

- Sales/input tax review pages showed headings but not seeded source references.
- EWT summary did not show the expected seeded supplier/amount probe.
- Return and working-paper tables remain empty and require explicit support/deferral classification.

## Security Audit

Critical issue:

- A service-role credential is exposed through a `VITE_` environment variable in the browser-visible Vite environment. Finding `PXL-AUD-055`.

Security controls that still need Phase 2 UI replay:

- Company isolation from the UI using lower-privilege demo users.
- Branch isolation and permission-hidden data states.
- Unauthorized approval/posting.
- Creator approving own document where SoD is configured.
- Posted document edit/delete prevention through the app, not only SQL tests.

## Table Coverage Report

Coverage query result:

- Public tables: 148
- Populated tables: 69
- Empty tables: 79
- Total public rows after seed: 5,080
- Company-scoped tables: 124
- Non-company-scoped tables: 24

Populated core coverage includes:

- Setup/master: `companies`, `branches`, `departments`, `cost_centers`, `chart_of_accounts`, `company_accounting_config`, `compliance_profiles`, `fiscal_years`, `fiscal_periods`, `number_series`, `payment_terms`, `units_of_measure`, `customers`, `suppliers`, `items`, `item_categories`, `warehouses`, `employees`, `bank_accounts`
- Sales/purchasing: `sales_quotations`, `sales_orders`, `sales_invoices`, `sales_invoice_lines`, `receipts`, `receipt_lines`, `credit_memos`, `credit_memo_lines`, `purchase_orders`, `purchase_order_lines`, `receiving_reports`, `receiving_report_lines`, `vendor_bills`, `vendor_bill_lines`, `payment_vouchers`, `payment_voucher_lines`
- Inventory/accounting/tax: `stock_balances`, `inventory_transactions`, `inventory_cost_layers`, `stock_transfers`, `stock_transfer_lines`, `stock_adjustments`, `stock_adjustment_lines`, `journal_entries`, `journal_entry_lines`, `tax_detail_entries`, `transaction_events`, `sys_audit_logs`
- References/system: `atc_codes`, `vat_codes`, `tax_codes`, `currencies`, `ref_document_types`, `ref_payment_modes`, `ref_posting_source_types`, `ref_rdo_codes`, `ref_feature_definitions`, `ref_compliance_forms`, `ref_reason_codes`, `void_reason_codes`

Empty active or potentially active tables requiring classification:

- Approval and lifecycle: `approval_instances`
- Delivery/returns/credits: `delivery_receipts`, `delivery_receipt_lines`, `vendor_credits`, `vendor_credit_lines`, `vendor_credit_applications`, `purchase_returns`, `purchase_return_lines`, `debit_memos`, `debit_memo_lines`, `supplier_debit_memos`, `supplier_debit_memo_lines`
- Banking/cash: `bank_adjustments`, `bank_reconciliations`, `bank_recon_items`, `check_vouchers`, `check_voucher_lines`, `fund_transfers`, `inter_branch_transfers`, `cash_purchases`, `cash_purchase_lines`, `petty_cash_funds`, `petty_cash_vouchers`, `petty_cash_replenishments`, `cash_count_sheets`
- Inventory: `physical_count_sheets`, `physical_count_sheet_lines`, `goods_issues`, `goods_issue_lines`, `warehouse_item_settings`, `warehouse_zones`
- Fixed assets and schedules: `fixed_assets`, `fixed_asset_categories`, `asset_depreciation_entries`, `asset_disposals`, `asset_impairments`, `asset_transfers`, `amortization_schedules`, `amortization_entries`, `revenue_recognition_schedules`, `revenue_recognition_entries`, `recurring_journal_templates`, `recurring_journal_template_lines`
- Tax/compliance: `vat_returns`, `ewt_returns`, `pt_returns`, `fwt_returns`, `withholding_remittances`, `form_2307_issuances`, `form_2307_issuance_lines`, `form_2307_tracking`, `form_2306_issuances`, `compliance_*_working_papers_*`, `income_tax_computations`, `book_tax_reconciliation`, `tax_credits_schedule`, `nolco_schedule`, `mcit_computations`, `itr_filings`, `bir_forms`, `bir_form_mappings`
- Reporting/system: `report_snapshots`, `cas_export_artifacts`, `cas_export_log`, `cas_attachment_register`, `sys_feature_enablement`, `exchange_rates`, `percentage_tax_codes`

Finding: `PXL-AUD-059`.

## Documentation Updates

Updated:

- `PXL_END_TO_END_AUDIT_FINDINGS.md`
- `PXL_TRANSACTION_MATRIX.md`
- `PXL_CANONICAL_DEMO_DATASET.md`

Created:

- `PXL_PHASE2_PRODUCT_AUDIT_REPORT.md`

## Critical Defects

- `PXL-AUD-055`: service-role credential exposed to browser-visible Vite environment.

## High-Priority Defects

- `PXL-AUD-056`: hosted migration push blocked by environment safety and migration drift.
- `PXL-AUD-057`: canonical dataset not consistently visible in application routes.
- `PXL-AUD-059`: active table coverage incomplete and not fully classified.
- `PXL-AUD-053`: Sales Invoice gold-standard residual remains in progress.
- `PXL-AUD-061`: full pgTAP regression suite is not deterministic against the canonical seeded state.

## Medium Defects

- `PXL-AUD-060`: login form labels not programmatically associated.

## Product Readiness Assessment

PXL is not production-ready for paying clients. The database-level canonical regression is materially stronger than the product-visible experience. The highest immediate blockers are credential exposure, hosted migration governance, canonical route visibility, and table coverage classification.

Recommended readiness status: internal QA/demo only, local non-production environment only, no production data.

## Recommended Roadmap

1. Remove and rotate client-exposed service-role credential; add static secret checks.
2. Prove hosted environment classification and reconcile migration history before any push.
3. Fix route-level visibility for canonical sales, purchasing, inventory, banking, aging, and tax-review probes.
4. Convert `scripts/audit_canonical_ui.mjs` into a CI Playwright smoke test after routes are fixed.
5. Produce a maintained table coverage matrix with module owner, purpose, row-count status, workflow source, RLS status, and next action.
6. Split the regression suite into deterministic fresh-schema, canonical-seeded, and held-out/experimental lanes.
7. Expand canonical fixtures for delivery receipts, vendor credits, purchase returns, physical counts, bank reconciliation, fixed assets, returns, compliance returns, and working papers where the product claims support.
8. Replay lower-privilege UI security scenarios against the canonical dataset.
