# PXL Executive Product Dashboard

## 1. Date

**2026-08-01**

## 2. Product Goal

PXL is an accounting-first, Philippine-compliance-first ERP for multi-company
businesses. A successful PXL workflow starts with a valid business transaction
and ends with the correct subsidiary ledger, General Ledger, Trial Balance,
financial statements, Philippine tax/books effect and audit trail.

Payroll: **Future separate product — excluded from current PXL ERP progress.**

## 3. Current Product Standing

**Internal QA/demo only. PXL is not pilot-ready and not production-ready.**

What is strong today:

- one enforced doorway into the General Ledger;
- a fully enforced Accounting Kernel guard;
- Certified Permissions/RLS, Audit & Immutability, Number Series and Dimension
  engines;
- meaningful local Sales, Purchasing, Journal, ledger, tax-review and books
  capabilities; and
- 92 of 92 audit findings Retested Passed.

What prevents a completion claim:

- no certification module is Certified;
- no transactional module is M5 Workflow Complete;
- Inventory valuation does not reconcile to the configured control account;
- a central Tax Engine does not exist;
- no opening-balance workflow exists;
- backup/restore has not been tested;
- hosted parity stops at migration `20260716000005`, with 51 later local
  migrations not hosted; and
- only 1 of 41 transaction workspace registry entries has a source-reviewed
  slice.

The canonical product taxonomy is **11 business modules plus the Dashboard as a
cross-product Reporting Surface**. The certification program has 11 differently
bounded module scopes; those evidence boundaries do not redefine the product.

## 4. Module Dashboard

| Module | Maturity | What currently works | What does not yet work | Certification | Main blocker | Next milestone | Production-ready |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Setup | M7 | Guided setup and core configuration | CAS/opening/rule decisions; operational proof | Combined Setup/Master scope Blocked | Restore + browser evidence | Certification evidence | No |
| Master Data | M7 | Core parties, items, warehouses, bank accounts and terms | Some masters have no UI; supplier bank details absent | Combined scope Blocked | Evidence and scope gaps | Source-backed onboarding set | No |
| Sales & Receivables | M4 | SI, Cash Sale, Official Receipt and Credit Memo cores | Full conversion, returns, broad source review, reconciliation | In Progress | Whole revenue-cycle proof | Canonical Sales flow | No |
| Purchasing & Payables | M4 | PO, Vendor Bill, Cash Purchase, Payment Voucher, Vendor Credit cores | Receiving journal, three-way match, returns | In Progress | Receiving-to-journal asymmetry | Canonical Purchase flow | No |
| Inventory | M4 | Stock balance/movements, adjustment, transfer, count | Goods Issue, governed costing/replay, control tie-out | In Progress | C-01 and valuation variance | WP-5 gate re-run, then value checkpoint | No |
| Banking & Treasury | M3 | Bank-account master; source receipts/payments | Canonical treasury and bank reconciliation | Not Started | Governed-empty data; ownership decision | Product architecture decision | No |
| Fixed Assets | M3 | Routes and backend routines only | Canonical lifecycle and depreciation policy | Not Started | Policy master absent | Module architecture | No |
| Accounting | M4 | JE/reversal, GL, ADL, TB, reviews, trace backend | All-consumer proof, schedules, year-end close | Core In Progress; Schedules Not Started | Integrated flow evidence | Functional accounting proof | No |
| Compliance | M4 | Posted-data reviews, ledgers, books and audit surfaces | Tax Engine, working papers, returns and certificates | Blocked | Tax architecture absent | Tax Engine decision/design | No |
| Reports | M4 | Primary FS and several real reports | Nine reconciliations, complete drill/export, dimensional adoption | In Progress | Source/reconciliation proof | Reconciliation pack | No |
| Administration & Security | M1 | Certified enforcement engines exist | No product administration workflow | Not Started | Visible-module versus external-admin decision | Ownership decision | No |
| Dashboard *(surface)* | M4 | Setup/count/deadline monitoring | KPI grid, roll-up, export and owner | No certification scope | Ownership/KPI contract | Product decision | No |

## 5. Shared Engine Dashboard

| Engine | Maturity | Certified scope | Main blocker / next milestone |
| --- | --- | --- | --- |
| Posting | M7 | None as whole engine; Kernel fully enforced | Inventory P6 reconciliation; prove canonical flows |
| Inventory Accounting | M2 | WP-1…WP-4 work packages only | EA-008 repaired WP-5 specification; separate gate re-run required |
| AR | M4 | None | Scenario-wide AR-control proof |
| AP | M4 | None | Scenario-wide AP-control proof |
| Payment & Application | M4 | None | Over/unapplied/reversal/concurrency proof |
| Tax | M0 | None; **absent** | Product Architecture Decision then accepted design |
| Document Conversion | M1 | None | No implementation; later Sales/Purchasing design |
| Number Series | M8 | **Certified** | Preserve; prove consuming modules |
| Approval & Workflow | M4 | None | Only import is a proven consumer |
| Period Lock & Closing | M4 | None | Year-end close and audited reopening |
| Reversal/Void/Correction | M4 | None | Complete transaction coverage |
| Audit & Immutability | M8 | **Certified** | Preserve; hosted parity later |
| Permissions & RLS | M8 | **Certified** | Preserve; hosted/browser strengthening later |
| Dimension | M8 | **Certified** | Adopt certified report in management surfaces |
| Currency | M1 | None; deferred | Maintain PHP-only boundary until owner decision |
| Reporting & Reconciliation | M4 | None | 0 of 9 critical reconciliations certified |
| Attachment & Traceability | M4 | None | Trace unlisted; attachment workflow absent |
| Backup & Recovery | M0 | None | No architecture, RPO/RTO or restore test |
| COA | M4 | None | Consumer migration and certification incomplete |

The Accounting Kernel is a fully enforced component inside Posting, not a
twentieth engine and not a separate progress measure.

## 6. Inventory Programme Dashboard

| Scope | Standing | Product meaning |
| --- | --- | --- |
| ADR-C01 | Frozen | Economic versus accepted chronology decision is binding. |
| ECC-01 | Owner accepted, not frozen | Governs deterministic economic order. |
| WP-1 | Certified work package | Dormant policy/version foundation. |
| WP-2 | Certified work package | Dormant source-registry authority. |
| WP-3 | Certified work package | Dormant valuation stream/allocator. |
| WP-4 | Certified work package | Dormant persisted order-key evidence. |
| WP-5 | **Specification repaired; unauthorised** | EA-008 closes WP5-AG-001…003 at specification level; a separate gate must decide authority. No implementation exists. |
| WP-6…WP-9 | Unauthorised | No work may begin. |
| IA-5 permanent foundation | Claim suspended | C-01 remains open until final executable evidence. |
| Inventory Accounting Engine | Not Certified | Four work packages do not certify the engine. |
| Inventory Module | Not Certified | Operational Inventory is a separate product scope. |
| IA-6 | Unauthorised | Costing/layers/FIFO/WAC may not begin. |

**Homogeneous programme measure:** IA-5 ECC work-package certification is **4 of
9**. This means four bounded dormant packages passed their own certification; it
does not measure Inventory product usability.

## 7. End-to-End Accounting Flow

```text
Business transaction                PARTIAL — several strong cores
  ↓
Posting Engine                      M7 — Kernel fully enforced; engine not Certified
  ↓
AR / AP / Inventory subledger       PARTIAL — scenario-wide proof incomplete
  ↓
General Ledger                      WORKING surface; module evidence incomplete
  ↓
Trial Balance                       WORKING surface; certification incomplete
  ↓
Financial Statements                PARTIAL
  ↓
Tax ledger / BIR books              PARTIAL — Tax Engine absent
  ↓
Full source-to-report audit trace   PARTIAL — backend trace works; attachments absent
```

**Canonical portfolio workflows fully proven:** 0 of 6 reference flows (Sales,
Purchasing, Inventory, Tax/Compliance, Banking/Cash, Fixed Assets). Components
work, but no whole flow meets the Product Definition of Done.

## 8. Current Critical Path

1. Product Architecture consolidation is complete and registered.
2. WP-5 Engineering Amendment EA-008 is complete; no authority was granted.
3. Run **WP-5 Authorisation Gate Re-run — Lifecycle Step 2**; do not implement
   during the gate or infer authority from specification readiness.
4. Prove one canonical Sales and one canonical Purchasing flow through source,
   posting, subledger, GL, TB, FS, tax, books, correction and trace.
5. Resolve Receiving Report accounting, Tax Engine ownership, opening balances
   and backup/restore at their governed decision gates.
6. Continue later Inventory work packages only if the product-value checkpoint
   shows they advance Inventory-to-GL and the target workflow.

## 9. Top Product Blockers

1. **No fully proven business-to-financial-statements-to-tax workflow.**
2. **Receiving Report raises stock without a journal**, so Inventory does not tie.
3. **Tax Engine absent**; tax calculation is distributed.
4. **Opening balances absent**; existing businesses cannot onboard safely.
5. **Backup/restore not tested**; no RPO/RTO or operating owner.
6. **No module Certified**; closed findings and certified engines are not module
   completion.
7. **Hosted parity gap:** 51 local-only migrations.
8. **UI/runtime mismatch:** 33 pure-deferred routes and 18 disabled placeholders.
9. **Source-review gap:** 1 of 41 transaction workspaces.
10. **Dirty/uncommitted repository:** preserve provenance and isolate future work.

## 10. Production Readiness

| Gate | Standing |
| --- | --- |
| Required module certification | **Fail — 0 / 11** |
| Required engine certification | **Fail — 4 / 19; required dependencies remain open** |
| Canonical end-to-end workflows | **Fail — 0 / 6** |
| Critical reconciliations | **Fail — 0 / 9 certified** |
| Hosted parity | **Fail — through `20260716000005` only** |
| Backup and restore | **Not Tested** |
| Opening-balance/cut-over | **Absent** |
| User acceptance | **Not performed** |
| Support/monitoring | **Not proven** |
| Overall readiness class | **Not Ready — Internal QA/demo only** |

## 11. Immediate Next Mission

**WP-5 Authorisation Gate Re-run — Lifecycle Step 2.**

It remains next because EA-008 cannot authorise itself and deterministic
Inventory chronology is a real prerequisite for future COGS/valuation and
Posting P6. The gate itself does **not** implement WP-5 or authorise automatic
continuation to WP-6…WP-9. After the gate, a product-value checkpoint must place
canonical Sales/Purchasing proof, Receiving accounting, Tax authority, opening
balances and restore evidence ahead of further dormant foundation work unless a
later package is demonstrably necessary.

## 12. Measures and Methodology

- **Modules:** canonical product maturity uses 11 business modules; certification
  counts use the 11 issued certification scopes. The boundary is stated whenever
  the count is used.
- **Engines:** denominator is the 19 certification scopes. Kernel is nested and
  excluded from the denominator.
- **Work packages:** reported only within their named programme and denominator.
- **Maturity:** uses M0–M9 from the Product Architecture and Roadmap; weaker
  evidence controls placement.
- **Workspaces:** current registry has 41 entries; exactly one row is
  `sales-invoice-reviewed-slice`, 40 are `transaction-matrix-only`.
- **Scaffolds:** 33 means routes backed only by `future-deferred` tables. It does
  not mean the 40 transaction-matrix-only workspaces are all UI-only.
- **Hosted parity:** compare migration filenames after hosted high-water mark
  `20260716000005`; current count is 51.
- **Tests:** 110 pgTAP files is an inventory count, not certification. The latest
  bounded WP-5 prerequisite result is 7 files / 260 assertions.
- **No mixed-unit overall percentage.** A percentage is allowed only for a
  homogeneous measure with an explicit denominator and meaning.
- **No future-scope inflation.** Payroll, dormant tables, absent engines, routes,
  closed findings and planned features do not count as delivered module progress.

Canonical authorities:

- Product identity and taxonomy:
  `docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`
- Execution sequence, maturity and DoD:
  `docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`
- Certification status:
  `docs/PXL/13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md`
- Coverage classes:
  `docs/PXL/13. Testing and Validation/PXL_TABLE_COVERAGE_MATRIX.md`

This dashboard reports status only. It grants no architecture, implementation,
certification, deployment or hosted authority.
