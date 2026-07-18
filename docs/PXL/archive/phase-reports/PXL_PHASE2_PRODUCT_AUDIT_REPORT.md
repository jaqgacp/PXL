# PXL Phase 2 Product Audit Report

**Status:** Historical Snapshot
**Report Date:** 2026-07-16
**Environment:** Hosted-connected local frontend and non-production project `bskjkogijpbhukjkagfj`
**Not Current Source of Truth:** See `AI/AI_STATE.md`, `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, and `docs/PXL/PXL_CANONICAL_DEMO_DATASET.md`
**Read When:** Historical Phase 2 evidence is specifically required

Audit date: 2026-07-16

Scope: hosted canonical demo dataset visibility, access model, application route usability, hosted database assertions, table coverage, security, and documentation consistency.

## Environment Verification

Frontend used for hosted UI verification:

- Local app URL: `http://127.0.0.1:5173`
- Manual forwarded URL: `https://upgraded-waddle-x57x5xw4px5wcvpgv-5173.app.github.dev/`
- `.env.local` Supabase URL: `https://bskjkogijpbhukjkagfj.supabase.co`
- `.env.local` project ref: `bskjkogijpbhukjkagfj`

Hosted Supabase target:

- Project ref: `bskjkogijpbhukjkagfj`
- Database host: `db.bskjkogijpbhukjkagfj.supabase.co`
- Region: `ap-southeast-1`
- `supabase migration list --linked`: local and remote synchronized through `20260716000001`

`PXL-AUD-056` remains Retested Passed. The migration repair, hosted reset, and canonical seed were not repeated during this UI verification pass.

Phase 3 retest addendum (2026-07-16): migration `20260716000002_company_rls_membership_scope.sql` was pushed to the same hosted project without reset/reseed. Company selector/RLS retested passed under `PXL-AUD-062`; `demo.admin@pxl.local` now sees exactly the five canonical companies and hosted company SELECT/UPDATE policies are membership/admin-scoped. `StockBalancePage` was corrected to filter by `stock_balances.company_id` and sort client-side; the hosted UI probe now shows `ITEM-STOCK-001` and `WH-MAIN`. Remaining UI visibility gaps stay under `PXL-AUD-057`.

Phase 3 implementation addendum: the existing hosted companies were preserved and incrementally enriched. Hosted automation now passes 48/48 company/master/document probes and 20/20 ABC report probes; PXL-AUD-057 is Retested Passed for the canonical visibility root cause. Coverage improved to 82 populated / 66 classified empty tables. A fresh canonical-seeded lane passes 56 files / 1,014 assertions; the held-out CAS historical-package test retains two product failures under PXL-AUD-066.

## Test User Access

Current hosted test user:

- Email: `demo.admin@pxl.local`
- Auth user id: `10000000-0000-0000-0000-000000000001`
- Auth role: `authenticated`

Memberships:

- `DEMO-CORP-VAT` / ABC Trading Corporation: owner, 3 branches
- `DEMO-OPC-NONVAT` / Northstar Digital Solutions OPC: owner, 1 branch
- `DEMO-PARTNERSHIP-VAT` / Bayani Partners and Company: owner, 1 branch
- `DEMO-SP-NONVAT` / Golden Retail Store: owner, 2 branches
- `DEMO-SVC-VAT` / Prime Business Advisory Inc.: owner, 1 branch

Permission function result under the demo admin JWT: `is_company_member`, `can_admin_company`, and `fn_can_perform` for create/approve/post/master-data/export all returned true for the five canonical companies.

Company selector result during Phase 2: the UI showed the five canonical companies, but also showed active non-member company `PXL Demo Trading Corporation`. Hosted policies included `authenticated_select_companies USING (true)` and `authenticated_update_companies USING (true)` with `authenticated` UPDATE grant on `public.companies`. Finding: `PXL-AUD-062`.

Phase 3 retest result: fixed. Hosted UI selector options are now only `ABC Trading Corporation`, `Bayani Partners and Company`, `Golden Retail Store`, `Northstar Digital Solutions OPC`, and `Prime Business Advisory Inc.`. Hosted `pg_policies` now has `companies_read_own USING (is_company_member(id))` and `companies_update USING/WITH CHECK (can_admin_company(id))`; zero broad company SELECT/UPDATE policies remain.

## Website Verification Summary

Hosted browser audit result:

- Login: passed
- Context selected: ABC Trading Corporation / HO
- Branch selector: ABC Cebu, ABC Davao, ABC Head Office visible
- Period selector: 2026 periods visible
- Initial route probe: 16 Passed, 15 Partially Passed, 5 Failed

Passed through UI:

- Company setup, branches, departments, cost centers
- Warehouses, customers, suppliers, items/services
- Sales Orders
- Receiving Reports
- Journal Entries and General Ledger
- Inventory Valuation and Cost Center report
- Sales Invoice detail route opens for `TEST-SI-STANDALONE`

Passed after required interaction:

- Stock Transfer: visible after opening History
- Stock Adjustment: visible after opening History
- Inventory Movements: visible after changing date range to Jan-Dec 2026
- Trial Balance: visible after selecting Date Range and Apply
- AP Aging: aggregate balance visible after as-of `2026-12-31`

Partially passed:

- Sales Invoices list shows generated SI numbers but not all `TEST-*` references.
- Sales Invoice detail shows paid/frozen state, GL Impact, Tax Impact, Workflow, Audit, and Related Docs; Lines/Financial/Validation labels remain incomplete against the expected workspace evidence.
- Official Receipt, Purchase Order, Vendor Bill, and Payment Voucher show generated document numbers, but canonical references and linked source numbers are not consistently visible.
- AR Aging shows customer balances but not invoice numbers in the default aggregate view.
- AP Aging shows supplier total, but source bill number did not surface in the attempted expansion.
- Tax review pages show headings/totals but not seeded source-document references.
- Audit pages show route shells but not seeded source references.

Failed during Phase 2:

- Stock Balance shows 0 rows even though hosted DB has 8 stock balances. Browser captured PostgREST 400 `PGRST100`: `failed to parse order (warehouses.warehouse_code.asc)`.

Phase 3 retest: Stock Balance is visible after removing the invalid related-table order and sorting client-side; the hosted UI probe found `ITEM-STOCK-001` and `WH-MAIN`.

Finding: `PXL-AUD-057`.

## Hosted Database Assertions

Hosted canonical counts:

- Companies: 5 canonical demo companies
- Branches: 8
- Departments: 13
- Cost centers: 10
- Warehouses: 5
- Customers: 13
- Suppliers: 13
- Items/services: 53
- Sales invoices: 6
- Receipts: 1
- Purchase orders: 1
- Receiving reports: 1
- Vendor bills: 1
- Payment vouchers: 1
- Stock balances: 8
- Inventory transactions: 14
- Stock transfers: 1
- Stock adjustments: 2
- Journal entries: 12
- Tax detail entries: 7
- Audit log rows: 783

Read-only hosted assertions passed:

- Posted journals: 12; unbalanced: 0
- VAT-exclusive SI `TEST-SI-STANDALONE`: net 2,000.00, VAT 240.00, total 2,240.00, expected CWT 40.00
- VAT-inclusive SI `TEST-SI-VAT-INCLUSIVE`: net 1,000.00, VAT 120.00, total 1,120.00
- CWT timing: no SI tax-ledger CWT row; OR `TEST-OR-SI-STANDALONE` records CWT base 2,000.00 and CWT 40.00
- Vendor Bill tax: input VAT 288.00 and EWT payable 24.00 on base 2,400.00
- Negative stock rows: 0
- Stock balance vs inventory movement mismatches: 0
- AR Aging as of 2026-12-31: SI-000002 balance 1,120.00 and SI-000003 balance 1,568.00
- AP Aging as of 2026-12-31: VB-000001 balance 1,664.00
- Posted SI/OR/VB/PV/STX/ADJ rows have posted status/posting indicators
- OR-to-SI, PV-to-VB, PO-to-RR, and stock-transfer movement relationships exist

Hosted function catalog evidence confirms stock insufficiency guards are deployed in SI posting/readiness, cost-layer consumption, stock adjustment posting, and stock transfer posting. No hosted mutation was performed to test oversell or over-transfer.

## Functional Matrix

| Area | Hosted DB Result | Hosted UI Result | Status |
| --- | --- | --- | --- |
| 5 canonical companies | Present | Visible, plus one extra non-member company | Partially Passed |
| Branches | 8 active branches | ABC branches visible | Passed |
| Departments | Seeded | Visible | Passed |
| Cost centers | Seeded | Visible on Cost Centers tab/report | Passed |
| Warehouses | Seeded | Visible | Passed |
| Customers | Seeded | Visible | Passed |
| Suppliers | Seeded | Visible | Passed |
| Items/services | Seeded | Visible | Passed |
| Sales Orders | Seeded | Visible | Passed |
| Sales Invoices | 6 rows | Numbers visible; canonical references partial | Partially Passed |
| Sales Invoice detail | Posted SI opens | Core tabs visible; some tab evidence partial | Partially Passed |
| Official Receipt | Posted OR linked to SI | Number visible; reference/amount partial | Partially Passed |
| Purchase Orders | Seeded PO/RR chain | PO number visible; reference/status partial | Partially Passed |
| Receiving Reports | Seeded | Visible | Passed |
| Vendor Bill | Posted with tax detail | Opens; reference missing | Partially Passed |
| Payment Voucher | Posted and linked to VB | Opens; source bill/reference partial | Partially Passed |
| Stock Balance | Rows reconciled; 0 negative-stock rows and 0 stock-balance-vs-movement mismatches on Phase 3 hosted read-only validation | Phase 3 UI retest shows canonical stock across inventory companies | Passed |
| Inventory Movements | 14 rows | Visible after date range change | Passed |
| Stock Transfer | Posted transfer | Visible after History tab | Passed |
| Stock Adjustment | 2 posted adjustments | Visible after History tab | Passed |
| Journal Entries | 12 balanced posted JEs | Visible | Passed |
| GL Impact | Accounting trace data exists | SI detail GL Impact passed | Passed |
| Tax Impact | Tax detail rows exist | SI detail Tax Impact passed; review pages partial | Partially Passed |
| Related Docs | OR/SI/PV/VB/STX links exist | SI Related Docs passed | Passed |
| Audit records | 783 audit rows | Audit route partial | Partially Passed |
| AR/AP reports | RPCs return expected balances | AR/AP aggregates visible; source refs partial | Partially Passed |
| Inventory reports | Valuation route visible | Inventory Valuation passed | Passed |

## Security Audit

Critical:

- `PXL-AUD-055`: previously exposed service-role credential still requires external rotation confirmation; Phase 3 static/build guard is implemented and passed.
- `PXL-AUD-063`: broad authenticated BIR form configuration policies remain open pending governed write posture.

Security controls still requiring a dedicated UI pass:

- Lower-privilege company isolation
- Branch isolation and hidden data states
- Unauthorized approve/post controls
- Posted document edit/delete prevention through UI

## Table Coverage

Hosted coverage query result:

- Public tables: 148
- Populated tables: 68
- Empty tables: 80
- Total public rows after hosted seed: 2,853
- Company-scoped tables: 124

Empty active examples include `approval_instances`, `delivery_receipts`, `vendor_credits`, `purchase_returns`, `physical_count_sheets`, `bank_reconciliations`, `bank_adjustments`, `check_vouchers`, `cash_purchases`, `petty_cash_vouchers`, fixed assets, VAT/EWT/PT/FWT returns, `warehouse_item_settings`, and `withholding_remittances`.

Finding: `PXL-AUD-059`.

## Reassessed Findings

- `PXL-AUD-055`: Open, Critical. Local exposure removed; static/build guard implemented and passed; external key rotation still required.
- `PXL-AUD-056`: Retested Passed. Hosted migration history and seed are synchronized; not repeated in this pass.
- `PXL-AUD-057`: Retested Passed, High. Final canonical hosted UI probes pass.
- `PXL-AUD-059`: Open, High. Hosted coverage is 82 populated / 66 classified empty tables.
- `PXL-AUD-061`: Open, High. The 56-file deterministic lane is green; held-out CAS remains isolated under PXL-AUD-066.
- `PXL-AUD-062`: Retested Passed, Critical. Hosted company selector/RLS finding fixed in Phase 3.
- `PXL-AUD-063`: Open, High. Broad BIR form configuration policies need governed write posture.
- `PXL-AUD-064`: Retested Passed, High. Reversal-aware AR/AP reconciliation is fixed.
- `PXL-AUD-065`: Retested Passed, High. Locked-period SI preview parity is fixed.
- `PXL-AUD-066`: Open, High. Historical CAS evidence uses mixed date semantics.
- `PXL-AUD-067`: Open, Medium. Setup Checklist is core-accounting-only.

## Product Readiness Assessment

PXL remains unsuitable for production data or an unrestricted external demo until external key rotation is confirmed. Hosted canonical UI visibility is now materially aligned with database truth; remaining blockers are `PXL-AUD-055`, `PXL-AUD-059`, `PXL-AUD-061`, `PXL-AUD-063`, and `PXL-AUD-066`.

## Recommended Roadmap

1. Rotate the previously exposed service-role credential after the Phase 3 static/build guard.
2. Tighten or explicitly govern broad BIR form configuration policies.
3. Add route empty-state diagnostics and canonical-reference columns for remaining UI gaps.
4. Surface canonical `TEST-*` business references and drillbacks in SI/OR/PO/VB/PV/aging/tax/audit pages.
5. Convert hosted UI probes into Playwright regression tests with required filters/history interactions.
6. Produce a maintained table coverage matrix with owner module, expected population source, RLS status, and deferral decision.
7. Split pgTAP into deterministic fresh-schema, canonical-seeded, and held-out/experimental lanes.
