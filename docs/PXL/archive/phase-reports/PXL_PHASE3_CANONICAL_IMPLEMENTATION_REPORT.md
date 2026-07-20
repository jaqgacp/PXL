# PXL Phase 3 Canonical Implementation and Validation Report

**Status:** Historical Snapshot
**Report Date:** 2026-07-16
**Environment:** Hosted project `bskjkogijpbhukjkagfj` and hosted-connected local frontend
**Not Current Source of Truth:** See `AI/AI_STATE.md`, `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, and `docs/PXL/13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md`
**Read When:** Historical Phase 3 evidence is specifically required

Date: 2026-07-16
Hosted project: `bskjkogijpbhukjkagfj` (`PXL`, authorized non-production development/demo)
Frontend: hosted-connected local application at `http://127.0.0.1:5173`

## Executive Result

Phase 3 preserved the existing hosted dataset and enriched it incrementally. No hosted reset or full reseed was performed. The five hosted companies are exactly the five originally designed canonical companies; none was replaced or duplicated. The original seed file is unchanged from its original canonical commit and was simply too narrow for an ERP implementation environment.

The hosted result now contains differentiated setup, masters, several months of governed transactions, 48 balanced journals including one original reversed journal, VAT/CWT/EWT evidence, reconciled AR/AP and inventory, and UI-visible records across all five companies. Hosted automation passed 48/48 company/master/document probes, 20/20 ABC report probes, and all current Sales Invoice detail tabs with zero page runtime errors.

This phase is **Partially Passed**, not fully complete. Banking operations, fixed assets, advanced schedules, approvals, returns, and statutory-return generation remain unsupported, unexercised, or blocked. PXL-AUD-055, PXL-AUD-059, PXL-AUD-061, PXL-AUD-063, PXL-AUD-066, and PXL-AUD-067 remain open.

## Environment And Preservation

| Check | Result |
| --- | --- |
| Frontend project | Passed: hosted URL/project ref resolves to `bskjkogijpbhukjkagfj` |
| Hosted migration history | Passed through `20260716000005` |
| Existing hosted data | Preserved and enriched in place |
| Hosted reset/reseed | Not performed |
| Backup for reset | Not required; prior hosted backups remain available |
| Git commit/push | None |

## Original Versus Hosted Companies

| Intended Canonical Company | Hosted Match | Difference Before Phase 3 | Phase 3 Result |
| --- | --- | --- | --- |
| DEMO-SP-NONVAT - Golden Retail Store | Exact identity/profile match | Setup and retail activity were minimal | Two branches, two warehouses, retail masters, opening stock, credit sale/partial receipt, purchase/receipt/bill/payment, transfer and shrinkage adjustment |
| DEMO-CORP-VAT - ABC Trading Corporation | Exact identity/profile match | Primary scenario existed but lifecycle breadth was narrow | Three branches, departments/cost centers/warehouses, quote-to-partial-collection chain, CM, vendor credit, cash purchase, physical count, void/reversal |
| DEMO-OPC-NONVAT - Northstar Digital Solutions OPC | Exact identity/profile match | Service company had minimal activity | Retainer and milestone billing, collection, cloud-service AP, manual accrual; inventory correctly absent |
| DEMO-SVC-VAT - Prime Business Advisory Inc. | Exact identity/profile match | VAT service scenarios were narrow | VAT-exclusive/inclusive fees, expected/actual CWT, professional/rent EWT, partial collection/payment |
| DEMO-PARTNERSHIP-VAT - Bayani Partners and Company | Exact identity/profile match | No customers, suppliers, warehouse, or transactions | Mixed goods/services masters, opening stock, partial purchasing, SO/DR/SI/OR chain, service CWT invoice, adjustment and partner drawing JE |

No important company identity was lost. The loss was functional breadth, not company replacement.

## Security Gate

| Finding | Result |
| --- | --- |
| PXL-AUD-055 service-role exposure | Open: client variable removed and static/pre/post-build guard passes; external key rotation is not confirmed |
| PXL-AUD-062 company RLS/selector | Retested Passed: five member companies only; owner/admin update scope; 11/11 local and hosted pgTAP |
| PXL-AUD-063 BIR global policies | Open: broad authenticated `ALL` policies remain on empty `bir_forms` and `bir_form_mappings` |

## Test User And Permissions

`demo.admin@pxl.local` is owner in all five companies and sees all eight active canonical branches through membership-wide branch access. The schema has no separate branch-authorization table, so branch access is company-membership scoped rather than individually assigned.

| Canonical User | Role In Five Companies | Intended Use |
| --- | --- | --- |
| `demo.admin@pxl.local` | owner | implementation/admin verification |
| `demo.accountant@pxl.local` | admin | accounting/setup operations |
| `demo.approver@pxl.local` | admin | approval/posting verification |
| `demo.sales@pxl.local` | member | operational sales/member lane |
| `demo.warehouse@pxl.local` | member | warehouse/member lane |

The current role model is owner/admin/member/viewer plus `fn_can_perform`; the requested named CPA/bookkeeper/cashier/auditor role catalog is not implemented as separate persisted roles. No broad access was added for demo convenience.

## Hosted Setup And Master Counts

| Company | Branch | Dept | Cost Ctr | WH | Customer | Supplier | Employee | Item/Service | Bank Acct |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ABC Trading Corporation | 3 | 5 | 5 | 3 | 10 | 10 | 6 | 18 | 2 |
| Bayani Partners and Company | 1 | 2 | 1 | 1 | 4 | 4 | 5 | 10 | 2 |
| Golden Retail Store | 2 | 2 | 2 | 2 | 4 | 4 | 5 | 19 | 2 |
| Northstar Digital Solutions OPC | 1 | 2 | 1 | 0 | 4 | 4 | 5 | 10 | 2 |
| Prime Business Advisory Inc. | 1 | 2 | 1 | 0 | 4 | 4 | 5 | 10 | 2 |

All companies also have legal/tax profiles, FY2026 with 12 open periods, entity-appropriate COA/equity accounts, payment terms, number series, compliance profiles, cash/bank accounts, and GL mappings. Golden and Northstar use PT010/3% Section 116 reference setup; VAT requirements are not forced on them. Service-only companies intentionally have no warehouse.

## Company Setup Checklist

The table records the ten checks the current UI actually implements. `Ready` means core accounting readiness only; PXL-AUD-067 records the missing operational-readiness scope.

| Company | Checklist Step | Applicable? | Expected | Actual | Source Record | UI | Finding |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Golden | Legal profile | Yes | Ready | Ready | `companies` | Passed | - |
| Golden | Active branch | Yes | Ready | Ready | `branches` | Passed | - |
| Golden | Fiscal year | Yes | Ready | Ready | `fiscal_years` | Passed | - |
| Golden | Open period | Yes | Ready | Ready | `fiscal_periods` | Passed | - |
| Golden | Chart of Accounts | Yes | Ready | Ready | `chart_of_accounts` | Passed | - |
| Golden | Core number series | Yes | Ready | Ready | `number_series` | Passed | - |
| Golden | Compliance profile | Yes | Ready | Ready | `compliance_profiles` | Passed | - |
| Golden | VAT codes | No | Not Applicable | Not Applicable | company tax registration | Passed | - |
| Golden | Withholding/ATC | Yes | Ready | Ready | PT010/ATC reference | Passed | - |
| Golden | GL posting config | Yes | Ready | Ready | `company_accounting_config` | Passed | PXL-AUD-067 scope only |
| ABC | Legal/branch/FY/period/COA | Yes | Ready | Ready | setup tables | Passed | - |
| ABC | Core number series | Yes | Ready | Ready | `number_series` | Passed | - |
| ABC | Compliance/VAT/ATC | Yes | Ready | Ready | compliance/tax tables | Passed | - |
| ABC | GL posting config | Yes | Ready | Ready | accounting config | Passed | PXL-AUD-067 scope only |
| Northstar | Legal/branch/FY/period/COA | Yes | Ready | Ready | setup tables | Passed | - |
| Northstar | Core number series | Yes | Ready | Ready | `number_series` | Passed | - |
| Northstar | VAT codes | No | Not Applicable | Not Applicable | company tax registration | Passed | - |
| Northstar | Compliance/ATC/GL | Yes | Ready | Ready | compliance/PT/accounting | Passed | PXL-AUD-067 scope only |
| Prime | Legal/branch/FY/period/COA | Yes | Ready | Ready | setup tables | Passed | - |
| Prime | Core series/compliance/VAT/ATC/GL | Yes | Ready | Ready | setup/tax/accounting | Passed | PXL-AUD-067 scope only |
| Bayani | Legal/branch/FY/period/COA | Yes | Ready | Ready | setup tables | Passed | - |
| Bayani | Core series/compliance/VAT/ATC/GL | Yes | Ready | Ready | setup/tax/accounting | Passed | PXL-AUD-067 scope only |

## Governed Business Activity

| Company | SI | OR | PO | RR | VB | PV | Inventory Tx | JE | Tax Rows | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ABC | 5 | 2 | 1 | 1 | 1 | 1 | 13 | 17 | 12 | Passed; includes one cancelled SI and reversal |
| Bayani | 2 | 1 | 1 | 1 | 1 | 1 | 4 | 8 | 4 | Passed; partial goods lifecycle plus open service invoice |
| Golden | 2 | 1 | 1 | 1 | 1 | 1 | 9 | 7 | 0 | Passed; non-VAT retail and branch inventory |
| Northstar | 3 | 1 | 0 | 0 | 1 | 1 | 0 | 8 | 0 | Passed; service-only/non-VAT |
| Prime | 3 | 1 | 0 | 0 | 2 | 1 | 0 | 8 | 8 | Passed; VAT/CWT/EWT service scenarios |

Downstream journals, tax detail, inventory movements, AR/AP applications, and document relationships were generated by existing RPCs/posting engines. Direct inserts were limited to setup/master data and header/line workflows where the current application itself has no posting RPC. The seed is idempotent and passed two consecutive replays.

Unsupported or incomplete transaction families were not fabricated: purchase/customer returns, debit/supplier debit memos, banking transactions/reconciliation, fixed assets, recurring journals, amortization/revenue-recognition schedules, statutory returns, and approval instances remain empty.

## Hosted UI Validation

| Module | Hosted Result | Evidence / Boundary |
| --- | --- | --- |
| Company selector and RLS | Passed | exactly five companies; non-member PXL Demo Trading absent |
| Branches/departments/cost centers | Passed | company-specific probes across all five |
| Customers/suppliers/items/services | Passed | company-specific master tokens across all five |
| Warehouses | Passed / Not Applicable | inventory companies passed; service-only companies intentionally have none |
| Sales Quotations/SO/DR | Passed where populated | ABC quote/SO/DR and Bayani SO/DR visible |
| Sales Invoices | Passed for current implementation | references searchable; posted detail read-only; approved UX standards not claimed implemented |
| Official Receipts | Passed | references visible; SI Related Docs shows actual linked OR |
| PO/RR/VB/PV | Passed where populated | references/notes visible and documents open |
| Credit Memo/Vendor Credit/Cash Purchase | Passed through hosted data probes and DB workflow tests | broad detail UX not independently audited |
| Stock Balance/Movements/Transfer/Adjustment/Count | Passed | history/date filters applied; no runtime query error |
| Journal Entries and GL Impact | Passed | balanced source-linked journals and SI GL tab |
| Tax Impact/Audit/Related Docs | Passed for focused SI | broader tax/audit source drilldown remains route-specific |
| Banking operations | Unsupported/Not Implemented in canonical activity | bank accounts exist; no transfer/reconciliation transactions |
| Fixed Assets | Unsupported in canonical activity | categories exist globally; no governed Phase 3 asset lifecycle |

## Report Coverage

All listed ABC reports returned hosted data after the UI's required Apply/date controls. Source-row drilldown was not independently proven on every report, so data visibility and drilldown are reported separately.

| Report | Company | UI Result | Total Reconciles | Drilldown | Filter Issue | Finding |
| --- | --- | --- | --- | --- | --- | --- |
| Trial Balance / General Ledger / Journal Entries | ABC | Passed | Passed | Partial | date + Apply required | PXL-AUD-057 closed for visibility |
| AR Aging / AP Aging | ABC | Passed | Passed | Partial | as-of date required | source drilldown not exhaustively tested |
| Stock Balance / Inventory Movements / Valuation | ABC | Passed | Passed | Partial | movement date range required | Stock Balance defect fixed |
| Sales Register / Purchase Register | ABC | Passed | Passed | Partial | report controls required | - |
| Sales VAT / Input VAT / VAT Output / EWT | ABC | Passed | Passed | Partial | company/date controls | PXL-AUD-063 is policy, not report data |
| Balance Sheet / Income Statement / Cash Flow | ABC | Passed | GL-balanced | Partial | Apply required | financial layout breadth not audited |
| Branch / Department / Cost Center | ABC | Passed | Dimension rows present | Partial | context required | - |
| Equivalent reports | Other four companies | Partially Passed | DB reconciled | Not fully UI-exercised | company/date context | do not claim page-by-page completion |

## Reconciliation

| Control | Hosted Result |
| --- | --- |
| Journal balance | Passed: 0 unbalanced posted/reversed journals |
| VAT inclusive/exclusive | Passed: canonical VAT scenarios and test 057 |
| CWT timing | Passed: expected on SI, actual on OR |
| EWT timing | Passed: source-basis VB/PV scenarios per company profile |
| Negative stock | Passed: 0 rows |
| Stock balance vs movements | Passed: 0 mismatches |
| Oversell / over-transfer | Passed: governed rejection tests |
| AR/AP control reconciliation | Passed after PXL-AUD-064; zero variance all five |
| AR open balances | ABC 3,584.80; Bayani 16,800; Golden 2,650; Northstar 50,000; Prime 42,560 |
| AP open balances | ABC 1,440; Bayani 13,310; Golden 3,000; Northstar 0; Prime 43,400 |
| Posted immutability | Passed in tests and focused posted SI UI |

## Table Coverage

Hosted coverage is 82 populated / 66 empty of 148 public base tables. Populated tables are meaningfully generated setup, master, transaction, ledger, inventory, tax, audit, or global reference tables. Empty tables are classified below; none was populated artificially.

| Category | Empty Tables | Status / Expected Generator |
| --- | --- | --- |
| Approval execution | `approval_instances` | Incomplete; workflow setup exists but no governed canonical approval instance |
| Banking/treasury | `bank_adjustments`, `bank_recon_items`, `bank_reconciliations`, `cash_count_sheets`, `check_voucher_lines`, `check_vouchers`, `fund_transfers`, `inter_branch_transfers`, `petty_cash_replenishments`, `petty_cash_vouchers` | Implemented-looking but unexercised; open PXL-AUD-059 |
| Fixed assets | `fixed_assets`, `asset_depreciation_entries`, `asset_disposals`, `asset_impairments`, `asset_transfers` | Not implemented in canonical activity |
| Schedules | `amortization_entries`, `amortization_schedules`, `recurring_journal_template_lines`, `recurring_journal_templates`, `revenue_recognition_entries`, `revenue_recognition_schedules` | Future/unexercised workflow |
| Returns/corrective inventory | `debit_memos`, `debit_memo_lines`, `goods_issues`, `goods_issue_lines`, `purchase_returns`, `purchase_return_lines`, `supplier_debit_memos`, `supplier_debit_memo_lines` | Incomplete; CM/VC used instead of fabricated rows |
| CAS outputs | `cas_attachment_register`, `cas_export_artifacts`, `cas_export_log` | Generated only by explicit export workflow; not generated for demo counts |
| VAT/WHT/PT working papers | all `compliance_*_working_papers_*` tables | Generated only by compliance preparation workflow; not claimed complete |
| Statutory returns/certificates | `ewt_returns`, `fwt_returns`, `pt_returns`, `vat_returns`, `form_2306_issuances`, `form_2307_issuances`, `form_2307_issuance_lines`, `form_2307_tracking`, `withholding_remittances` | Not generated; tax ledger/report review only |
| Income tax | `book_tax_reconciliation`, `income_tax_computations`, `itr_filings`, `mcit_computations`, `nolco_schedule`, `tax_credits_schedule` | Unsupported in Phase 3 canonical activity |
| Global BIR configuration | `bir_forms`, `bir_form_mappings` | Empty and security policy open under PXL-AUD-063 |
| Technical/optional | `exchange_rates`, `report_snapshots`, `sys_feature_enablement`, `warehouse_zones` | Legitimately empty for PHP-only/default-open/no-export/no-zone scenarios |

## Test Lanes

| Lane | Result |
| --- | --- |
| Fresh schema replay | Passed through migration `20260716000005` |
| Canonical seeded deterministic | Passed: base seed + enrichment twice; 56 files / 1,014 assertions |
| Canonical focused | Passed local and hosted: test 055 (34), 056 (11), 057 (38) |
| Hosted safe read-only | Passed accounting, tax, inventory, AR/AP, RLS and 148-table profiler |
| Hosted UI | Passed 48/48 company/master/document + 20/20 reports; focused SI tabs passed |
| Held-out CAS | Failed 2 of 31: historical number/void evidence under PXL-AUD-066 |

## Open Critical And High Remediation

| Finding | Severity | Plan |
| --- | --- | --- |
| PXL-AUD-055 | Critical | externally rotate the previously exposed service-role key, rerun guard/build, confirm frontend anon-only |
| PXL-AUD-059 | High | add governed banking/asset/return/approval/compliance scenarios only where the product path is authoritative |
| PXL-AUD-061 | High | formalize named CI commands for the green 56-file lane and held-out CAS lane; close after PXL-AUD-066 |
| PXL-AUD-063 | High | decide BIR configuration ownership, replace broad policies, add local/hosted RLS tests |
| PXL-AUD-066 | High | resolve CAS source document dates and void `document_date` semantics, then require 31/31 and 57-file green |

## Sales Invoice UX Classification

The current implementation was validated; the approved Sales Invoice Form/View UX standards are not claimed as rolled out.

| Observation | Classification |
| --- | --- |
| Canonical external reference absent from old list search | Current implementation defect; fixed |
| Linked OR shown only as an application count | Current implementation defect; fixed with actual OR number/date/amount |
| PO has no dedicated external-reference column | Missing persistence/schema support |
| Full approved form/view composition | Approved UX standard not yet implemented |
| Current posted SI read-only, GL/tax/audit/related evidence | Current implementation passed |

## Validation Commands

```bash
supabase db reset --local --no-seed
docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /dev/stdin < supabase/seeds/canonical_demo_seed.sql
docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /dev/stdin < supabase/seeds/canonical_phase3_enrichment.sql
supabase test db --local
supabase test db --local $(find supabase/tests -maxdepth 1 -name '*.sql' ! -name '027_cas_end_to_end_controls_test.sql' | sort)
supabase db push --linked --dry-run
supabase db push --linked
node scripts/audit_phase3_checklists.mjs
node scripts/audit_phase3_hosted_ui.mjs
npm run check:frontend-secrets
npm run build
```

## Files

Created: Phase 3 enrichment seed, hosted/UI/checklist audit scripts, hosted read-only verifier, migrations `20260716000003` through `00005`, pgTAP test 057, and this report.

Updated: transaction list/detail pages for canonical references and OR relationships; tests 016/017/020/025/026/027/042/050/055; and the five governed PXL audit/canonical/accounting/transaction documents.

Phase 3 used the hosted canonical PXL environment as a differentiated multi-company ERP implementation and audit platform. Company readiness, setup completeness, master data, transactions, reports, reconciliations, RLS, UI visibility, table coverage, findings, and remediation plans are reported independently and truthfully. Artificial table population and successful seeding alone are not treated as product readiness.
