# PXL Product Execution Roadmap

**Status:** Active — canonical subordinate product execution plan
**Authority:** Tier 1 Product Planning, subordinate to
[`PXL_PRODUCT_ARCHITECTURE.md`](PXL_PRODUCT_ARCHITECTURE.md)
**Owner / Domain:** Product Architecture and Product Governance
**Applies To:** Product sequencing, maturity, definition of done, portfolio
measures, dependency management and production-readiness planning
**Read When:** Planning work, reporting product maturity, choosing the next
governed mission, or deciding whether a module or engine is complete
**Do Not Read For:** Product scope or naming (use the Product Architecture),
implementation authority (use `AI/AI_STATE.md` and the applicable gate), or
certification status (use the Certification Matrix)
**Date:** 2026-08-01
**Evidence baseline:** Current dirty working tree at base `4aef8b3`; no hosted
read or mutation was performed for this roadmap

> The Product Architecture defines what PXL is. This roadmap defines how that
> product is planned, sequenced, matured and completed. This roadmap cannot add
> scope, change canonical naming, certify anything or authorise implementation.

---

# 9.1 Executive Summary

PXL is a serious accounting foundation surrounded by an incomplete product. Its
best qualities are unusually strong: the General Ledger has one enforced posting
doorway; the Kernel Totality Guard is fully enforced; tenant isolation, audit
immutability, number series and dimensions are Certified; core sales, purchasing,
cash and journal transactions can post; GL, Trial Balance, several financial
statements, tax reviews and books read real posted data.

That is not the same as a finished ERP. No certification module is Certified.
No major operational module is M5 Workflow Complete. Banking and Fixed Assets are
UI skeletons over governed-empty data. A central Tax Engine does not exist.
Receiving Reports add stock without a journal, so Inventory valuation cannot
reconcile to the configured control account. Opening balances do not exist, so
an existing business cannot be onboarded. Backup and restore have never been
proven. Fifty-one local migrations after `20260716000005` are not on the hosted
project. PXL remains **Internal QA/demo only — not pilot-ready and not
production-ready**.

The visible product is ahead of runtime in thirty-three pure-deferred routes,
eighteen disabled placeholders and whole Banking/Fixed Asset/compliance-generator
clusters. The backend is ahead of the UI in party contacts, groups, item
extensions, financial-statement structure, inventory configuration, branch-scope
administration and the two complete-but-unlisted accounting trace routes. The
transaction workspace shell is structurally broad, but only Sales Invoice has a
source-reviewed workspace slice: **1 of 41** registry entries.

The recommended path is dependency-driven:

1. finish this consolidation;
2. repair the rejected WP-5 specification **in documentation only** and re-run
   its Authorisation Gate;
3. prove one complete Sales and one complete Purchasing accounting flow;
4. settle opening-balance, Tax Engine, Administration, backup and other owner
   decisions at the milestones where they become blocking;
5. place Tax Engine architecture before module certification that depends on it;
6. complete and certify Sales, Purchasing and Inventory before expanding Banking
   and Fixed Assets; and
7. require hosted parity, restore proof, user acceptance and operating support
   before pilot or production claims.

The roadmap deliberately prevents the dormant Inventory programme from running
far ahead of product value. WP-5 remains next because three precise documentation
defects block an already-open critical programme and the repair is small and
non-runtime. After its gate, continuation into later work packages is subject to
a product-value checkpoint; certification machinery must not become a substitute
for completing usable accounting workflows.

---

# 9.2 Current Product Baseline

## 9.2.1 Exact portfolio facts

| Measure | Current evidence-based value | Meaning and authority |
| --- | --- | --- |
| Canonical business modules | **11** | Product Architecture: Setup; Master Data; Sales; Purchasing; Inventory; Banking; Fixed Assets; Accounting; Compliance; Reports; Administration & Security. |
| Cross-product Dashboard | **1 Reporting Surface** | Not a business module and has no certification scope. |
| Certification module scopes | **11** | Certification standard; combines Setup/Master Data and separates Accounting Schedules. |
| Compliance workspaces | **6** | Percentage Tax; VAT; Withholding; Income Tax; BIR Books; Audit & CAS. |
| Engine assessment scopes | **19** | Engine certification standard; Accounting Kernel is nested inside Posting and not a twentieth engine. |
| Certified modules | **0 / 11 certification scopes** | No module certification exists. |
| Certified engines | **4 / 19** | Permissions/RLS, Audit & Immutability, Number Series, Dimension. |
| Certified work packages | **IA-5 ECC 4 / 9** | WP-1…WP-4 only; dormant bounded scopes; no engine/module certification. |
| Module maturity | **M1: 1 · M3: 2 · M4: 6 · M7: 2** | Eleven canonical business modules. Dashboard is separately M4. |
| Engine maturity | **M0: 2 · M1: 2 · M2: 1 · M4: 9 · M7: 1 · M8: 4** | Nineteen engine assessment scopes. |
| Source-reviewed transaction workspaces | **1 / 41** | Current registry: Sales Invoice reviewed slice; 40 are `transaction-matrix-only`. |
| UI-only pure scaffold routes | **33** | Reachable routes backed exclusively by `future-deferred` tables. |
| Disabled navigation placeholders | **18** | Four genuinely absent, two moved, ten backend-ahead-of-UI/configuration gaps, two other future items. |
| Distinct navigable routes | **169** | From 224 enabled navigation leaves; 55 labels duplicate existing routes. |
| Backend-only capability clusters | **7**, plus **2 unlisted routes** | Contacts; groups; item extensions; FS structure; inventory config; branch scopes; dashboard layouts/widgets; `/accounting-trace` and `/accounting-source`. |
| Base tables | **202** | 93 expected-populated; 109 explicitly deferred/empty. |
| Automated database test files | **110 pgTAP files** | Current test inventory. This documentation mission does not re-run database lanes. |
| Latest WP-5 prerequisite evidence | **7 focused files / 260 assertions** | Tests `104`…`110` passed at the rejected WP-5 gate. |
| Canonical portfolio workflows fully proven | **0 / 6** | The six reference flows in §9.5; many components work, but no whole flow meets the Product Definition of Done. |
| Critical reconciliations certified | **0 / 9** | Certification Matrix. VAT/WHT are known zero-variance and Inventory is known not to reconcile, but none of the nine is certified. |
| Hosted migration parity | **Through `20260716000005` only** | **51** later local migrations (`20260718000001`…`20260731000019`) are not hosted. |
| Backup / restore evidence | **NOT TESTED** | No successful restore test, runbook, RPO or RTO. |
| Audit findings | **92 Retested Passed / 0 open** | A closed findings register certifies no module. |
| Product readiness | **Internal QA/demo only** | Not Ready for pilot or production. |

## 9.2.2 What is genuinely working

- Guided company setup, core master data, live numbering and dimensional masters.
- Sales Invoice, Cash Sale, Official Receipt and Credit Memo posting lifecycles in
  meaningful local scope.
- Purchase Order, Vendor Bill, Cash Purchase, Payment Voucher and Vendor Credit in
  meaningful local scope.
- Manual Journal posting and reversal; GL, Account Detail Ledger and Trial Balance.
- Inventory adjustments, transfers, physical counts, stock balance and movements,
  subject to the valuation/reconciliation warning.
- Posted-data VAT and withholding reviews, BIR books, CAS logs and hashed export
  foundations; VAT and withholding ledger-to-GL zero-variance evidence exists.
- Four Certified engines and a fully enforced Posting Kernel guard.

## 9.2.3 Foundation only or dormant

- Inventory Accounting IA-5/ECC: M2, dormant, zero consumers, four certified
  work packages, C-01 still open, WP-5 rejected.
- COA Engine: foundation and partial consumer adoption, not engine-certified.
- Approval/Workflow: strong foundation, only import approval proven as consumer.
- Financial-statement structure, contact/group/item-extension and branch-scope
  data foundations without complete user workflows.

## 9.2.4 UI ahead of backend

Banking & Treasury, Fixed Assets, Accounting Schedules, returns/corrective
documents, statutory working papers/return generators, Income Tax, attachment
artifacts and several CAS export surfaces present as routes or pages while their
governed backing tables remain empty. A route/page is therefore evidence of
surface coverage only.

## 9.2.5 Backend ahead of UI

Accounting trace is complete but not in navigation. The certified dimensional
report is unused by management reports. Several governed masters/configuration
objects have no page. These are adoption and ownership gaps, not new-engine
requirements.

---

# 9.3 Product Maturity Model

## 9.3.1 Canonical ladder

| Level | Definition |
| --- | --- |
| **M0 — CONCEPT** | A product idea exists but has no accepted architecture. |
| **M1 — ARCHITECTURE** | Scope, ownership, and dependencies are governed. |
| **M2 — BACKEND FOUNDATION** | Core data structures or shared functions exist, but no complete business workflow is supported. |
| **M3 — UI SKELETON** | A route/page exists, but it is not a complete source-backed workflow. |
| **M4 — PARTIAL WORKFLOW** | Material portions work, but important lifecycle, accounting, reporting, security, or reconciliation steps remain incomplete. |
| **M5 — WORKFLOW COMPLETE** | The primary business workflow works end to end in the local governed environment. |
| **M6 — INTEGRATED** | Posting, accounting, tax, reporting, permissions, audit, and dependent modules are reconciled. |
| **M7 — GOVERNED** | Architecture, controls, evidence, rollback, and lifecycle requirements are complete. |
| **M8 — CERTIFIED** | The defined module or engine scope has passed its formal certification. |
| **M9 — PRODUCTION READY** | Hosted parity, backup/restore, operational monitoring, user acceptance, security, support, and release criteria pass. |

Placement is conservative: weaker evidence controls the level. A module with one
excellent transaction and one material empty lifecycle remains M4 or below.

## 9.3.2 Module placement

| Canonical module | Level | Decisive evidence |
| --- | --- | --- |
| Setup | **M7** | Formal combined review executed; 14 Pass, 3 Partial, 2 Blocked, 4 N/A, 0 Fail. Not M8 because backup/restore and browser evidence remain open. |
| Master Data | **M7** | Same review; major masters exercised and governed; certification scope still Blocked. |
| Sales & Receivables | **M4** | Several posting lifecycles work; conversion, returns-to-stock, attachments, broad approval, source review and certification remain incomplete. |
| Purchasing & Payables | **M4** | Core payable workflows work; Receiving Report accounting, three-way match and returns are unresolved. |
| Inventory | **M4** | Operational stock works in part; Goods Issue is deferred and valuation does not reconcile to control. |
| Banking & Treasury | **M3** | Routes/pages and routines exist; governed data is empty and no canonical workflow is exercised. |
| Fixed Assets | **M3** | Routes/pages and routines exist; governed data is empty and depreciation policy has no master. |
| Accounting | **M4** | Journals/ledgers/TB work; schedules, year-end close and consumer-wide posting/reconciliation proof remain incomplete. |
| Compliance | **M4** | Read/review/books half works; Tax Engine and persisted filing artifacts do not. |
| Reports | **M4** | Statements render; nine critical reconciliations, dimensional adoption and full drill/export evidence are not certified. |
| Administration & Security | **M1** | Need and certification target are governed; ownership decision remains and no UI exists. |
| Dashboard *(not a module)* | **M4** | Live readiness/deadline monitoring works; KPI grid, range, roll-up, export and owner are incomplete. |

## 9.3.3 Engine placement

| Engine assessment scope | Level | Certification standing and decisive evidence |
| --- | --- | --- |
| Posting | **M7** | Governed, Kernel fully enforced, blocked at P6; not Certified. |
| Inventory Accounting | **M2** | Dormant foundation only; C-01 open; not Certified. |
| AR | **M4** | As-of engine works; full scenario reconciliation not Certified. |
| AP | **M4** | As-of engine works; full scenario reconciliation not Certified. |
| Payment & Application | **M4** | Normal applications work; over-application/unapplied/reversal/concurrency scope incomplete. |
| Tax | **M0** | Absent; no accepted architecture or owner. |
| Document Conversion | **M1** | Product need/dependencies governed; implementation not started. |
| Number Series | **M8** | Certified 2026-07-23. |
| Approval & Workflow | **M4** | Foundation exists; only import consumer proven. |
| Period Lock & Closing | **M4** | Period locking works; year-end close/reopening incomplete. |
| Reversal, Void & Correction | **M4** | Reversal strong; void/correction coverage incomplete. |
| Audit & Immutability | **M8** | Certified 2026-07-23. |
| Permissions & RLS | **M8** | Certified 2026-07-22. |
| Dimension | **M8** | Certified 2026-07-23. |
| Currency | **M1** | PHP-only boundary governed; broader scope deferred. |
| Reporting & Reconciliation | **M4** | Views/exports exist; nine critical reconciliations not certified. |
| Attachment & Traceability | **M4** | Source trace works; attachment workflow absent. |
| Backup & Recovery | **M0** | No accepted operational architecture, owner, RPO/RTO or restore evidence. |
| COA | **M4** | Phase A and partial adoption exist; all-consumer adoption/certification incomplete. |

The Accounting Kernel is **M7**, fully enforced, and nested inside Posting. It
is not included in the 19-engine denominator.

---

# 9.4 Product Definition of Done

## 9.4.1 Universal criteria

A business module may be called **complete** only when every applicable criterion
passes across its whole governed scope:

1. Product scope approved
2. Architecture complete
3. Master data complete
4. Transaction lifecycle complete
5. UI source-backed
6. Validation complete
7. Approval/workflow complete where applicable
8. Posting complete
9. Accounting reconciliation complete
10. Tax treatment complete where applicable
11. Reports and registers complete
12. Permissions and segregation of duties complete
13. Audit trail complete
14. Attachments/traceability complete where applicable
15. Void/reversal/correction complete
16. Period controls complete
17. Error and failure handling complete
18. Tests complete
19. Canonical end-to-end workflow proven
20. Documentation complete
21. Brutal Audit passed
22. Certification passed
23. Hosted parity proven
24. Backup and restore proven
25. Product-owner/user acceptance complete
26. Production-readiness gate passed

“Complete,” “done,” “certified,” and “production-ready” are separate claims.
Certified work packages close none of these criteria for a whole module unless
the module certification evidence explicitly says so.

## 9.4.2 Applicability and open criteria by module

“Open” means the whole-module completion bar is not yet evidenced. A component
may work while its module-level criterion remains open. IDs not listed as
applicable are not applicable to that module's supported scope and require an
explicit certification justification.

| Module | Applicable criteria | Known open criteria at this baseline | Decisive reason |
| --- | --- | --- | --- |
| Setup | 1–7, 10–14, 16–26 | **4–7, 10–11, 14, 17–26** | Combined review is governed but backup/restore and browser evidence block certification; CAS/opening/rule configuration decisions remain. |
| Master Data | 1–7, 10–15, 17–26 | **4–7, 10–11, 14–15, 17–26** | Some masters lack UI, supplier bank details are absent, attachment/correction/operational proof incomplete. |
| Sales & Receivables | 1–26 | **3–26** | Product scope and architecture exist; complete source chain, returns, conversion, approvals, attachments, reconciliations, certification and operations do not. |
| Purchasing & Payables | 1–26 | **3–26** | Receiving accounting, matching, returns and complete downstream evidence remain open. |
| Inventory | 1–9, 11–26 | **3–9, 11–26** | Operational partial workflow; valuation/control mismatch; Inventory Accounting dormant; no module certification. |
| Banking & Treasury | 1–26 | **2–26** | Product scope is named, but ownership details, canonical data and every workflow/completion gate remain open. Tax applies to withholding-capable disbursement where used. |
| Fixed Assets | 1–26 | **2–26** | No policy master or canonical asset lifecycle; all completion evidence remains open. |
| Accounting | 1–9, 11–26 | **3–9, 11–26** | Working ledger core is insufficient for schedules, close, all-consumer posting, reconciliation and operations. |
| Compliance | 1–26 | **2–26** | Tax Engine architecture is absent and persisted statutory workflows remain deferred. |
| Reports | 1–2, 5–6, 9, 11–14, 17–26 | **5–6, 9, 11–14, 17–26** | Scope/architecture exist; reconciliations, drill/export contracts, source backing across all reports and operating proof remain open. |
| Administration & Security | 1–7, 12–15, 17–26 | **2–7, 12–15, 17–26** | Product need exists, but ownership decision, UI, workflows and evidence are absent. |
| Dashboard *(Reporting Surface)* | 1–2, 5–6, 11–14, 17–21, 23–26 | **1–2, 5–6, 11–14, 17–21, 23–26** | No owning module or governed KPI contract; it is excluded from module certification counts. |

The table is a product-planning view, not a certification decision. Only the
Certification Matrix may record certification status.

---

# 9.5 Dependency Map

## 9.5.1 Status legend

`[WORKING]` = source-backed component works in current local scope
`[PARTIAL]` = material capability exists but end-to-end proof is incomplete
`[CERTIFIED FOUNDATION]` = bounded engine/work-package certification only
`[STOP]` = current blocker
`[UNAUTHORISED]` = implementation may not begin
`[FUTURE]` = governed later stage

## 9.5.2 Sales to Financial Statements

```text
Customer                              [WORKING]
  ↓
Quotation                             [PARTIAL]
  ↓
Sales Order                           [PARTIAL]
  ↓
Delivery Receipt                      [PARTIAL]
  ↓
Sales Invoice / Cash Sale             [WORKING in bounded local scope]
  ↓
Official Receipt / Application        [WORKING in bounded local scope]
  ↓
Posting Engine                        [M7 GOVERNED; not Certified]
  ↓
Accounting Kernel                     [FULLY ENFORCED component]
  ↓
AR Subledger / General Ledger         [PARTIAL; scenario-wide proof open]
  ↓
Trial Balance                         [WORKING surface; certification open]
  ↓
Financial Statements                  [PARTIAL]
  ↓
VAT / Percentage Tax / Books          [PARTIAL; Tax Engine absent]

CURRENT STOP: the whole source chain, correction path, tax effect and report
drill have not been proven together as one canonical workflow.
```

## 9.5.3 Purchasing to Financial Statements

```text
Supplier                              [WORKING]
  ↓
Purchase Order                        [WORKING in bounded local scope]
  ↓
Receiving Report                      [PARTIAL]
  ↓                                   [STOP: stock increases without journal]
Vendor Bill / Cash Purchase           [WORKING in bounded local scope]
  ↓
Payment Voucher                       [WORKING in bounded local scope]
  ↓
Posting Engine / Kernel               [M7 / fully enforced component]
  ↓
AP Subledger / General Ledger         [PARTIAL; scenario-wide proof open]
  ↓
Trial Balance / Financial Statements  [PARTIAL]
  ↓
Input VAT / EWT / Books               [PARTIAL; Tax Engine absent]

CURRENT STOP: Receiving Report accounting, three-way match, corrections and
the complete source-to-books proof.
```

## 9.5.4 Inventory Accounting

```text
Item and Warehouse                    [WORKING]
  ↓
Inventory Business Transaction        [PARTIAL]
  ↓
Inventory Event Admission             [DORMANT FOUNDATION]
  ↓
Source Registry                       [WP-2 CERTIFIED FOUNDATION]
  ↓
Valuation Stream                      [WP-3 CERTIFIED FOUNDATION]
  ↓
Economic Order Key                    [WP-4 CERTIFIED FOUNDATION]
  ↓
Component Resolver                    [STOP: WP-5 REJECTED]
  ↓
Costing / Replay                      [UNAUTHORISED: WP-6…WP-9 / IA-6]
  ↓
Inventory Accounting Effect           [FUTURE]
  ↓
Posting / General Ledger              [FUTURE integration]
  ↓
Inventory Valuation & Reconciliation  [CURRENT LEGACY OUTPUT DOES NOT TIE]
```

No current business workflow consumes the certified dormant foundation. WP-5
must not be implemented until its Engineering Amendment closes WP5-AG-001…003
and a later gate explicitly authorises it.

## 9.5.5 Tax and Compliance

```text
Source Transaction                    [PARTIAL but real]
  ↓
Tax Classification / Calculation      [STOP: distributed; Tax Engine ABSENT]
  ↓
Tax Ledger / Working Paper            [ledger WORKING; workpapers mostly UI SKELETON]
  ↓
Reconciliation                        [VAT/WHT known zero variance; not certified]
  ↓
BIR Return                            [UI SKELETON / DEFERRED]
  ↓
Schedule / DAT / RELIEF Export        [mixed: review exports work; persisted artifacts deferred]
  ↓
Books and Audit Evidence              [PARTIAL; many read surfaces work]
```

**Central Tax Engine:** absent at M0. Tax reference masters, save-layer tax
calculation, the tax ledger and Compliance surfaces are real but distributed.
PAD-001 must establish architecture and ownership before engine work.

## 9.5.6 Banking and Cash

```text
Official Receipt or Payment Voucher   [WORKING in source modules]
  ↓
Bank / Cash Account                   [WORKING master]
  ↓
Deposit / Disbursement                [UI SKELETON]
  ↓
Bank Statement                        [FUTURE]
  ↓
Bank Reconciliation                   [UI SKELETON; ownership decision open]
  ↓
Adjustment                            [UI SKELETON; write-boundary decision open]
  ↓
General Ledger Reconciliation         [NOT PROVEN]
```

## 9.5.7 Fixed Assets

```text
Acquisition                           [UI SKELETON]
  ↓
Asset Recognition                     [UI SKELETON]
  ↓
Depreciation                          [STOP: no depreciation-profile authority]
  ↓
Transfer / Impairment / Disposal      [UI SKELETON]
  ↓
Posting                               [backend routines; no canonical workflow]
  ↓
Fixed Asset Register                  [UI SKELETON]
  ↓
Book / Tax Reconciliation             [NOT PROVEN]
```

---

# 9.6 Module Ownership Matrix

| Capability | Owner and business purpose | Shared-engine / accounting / tax dependencies | Upstream dependencies | Downstream outputs and reports | Maturity / certification | Current blocker | Next governed action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dashboard | Product/Reports; show readiness and attention items | Reporting; no posting; tax calendar read | Every source module | Readiness, deadlines, future KPIs | M4 / no scope | Owner and KPI contract | PAD ownership decision; retain as surface, not module metric |
| Setup | Setup; make a company operable | Permissions, Audit, Number Series, COA; tax references | Product decisions | Configuration and readiness checklist | M7 / combined scope Blocked | Restore and browser evidence | Resolve PAD-007; prepare certification evidence without claiming M9 |
| Master Data | Master Data; govern reusable business entities | Permissions, Audit, Approval, COA | Setup | Parties/items/warehouses/accounts consumed by all modules | M7 / combined scope Blocked | Evidence plus missing/unsurfaced masters | Decide supplier bank details; source-back required masters |
| Sales & Receivables | Sales; revenue and collection cycle | Posting, COA, Dimension, AR, Payment, Approval, Correction, Reporting; Tax absent | Setup, Master Data, Inventory availability | AR ledger, sales registers, VAT/PT/CWT/books, GL/FS | M4 / In Progress | Full chain/source/correction/reconciliation | Select canonical Sales flow and prove §9.4 |
| Purchasing & Payables | Purchasing; procurement, receipt, liability and payment | Posting, COA, Dimension, AP, Payment, Approval, Correction, Reporting; Tax absent | Setup, Master Data | AP ledger, purchase registers, input VAT/EWT/books, Inventory, GL/FS | M4 / In Progress | Receiving-to-journal and matching | Govern Receiving accounting design; prove canonical Purchase flow |
| Inventory | Inventory Operations; quantity, custody and value | Posting, Dimension, Inventory Accounting, Reporting | Items/warehouses; Sales/Purchasing sources | Stock ledger, valuation, COGS, inventory control | M4 / In Progress | Control mismatch; dormant chronology; Goods Issue deferred | Complete bounded WP-5 decision, then reconcile operational design before activation |
| Banking & Treasury | Treasury; cash custody and bank reconciliation | Payment, Posting, Period, Correction, Reporting; tax on applicable disbursements | Bank accounts, Sales receipts, Purchasing payments | Bank position, check register, cash books, bank/GL reconciliation | M3 / Not Started | Empty canonical data; PAD-004 | Product Architecture Decision then module architecture/evidence |
| Fixed Assets | Fixed Assets; capitalise, depreciate and dispose | Posting, Dimension, Period, Correction, Reporting; book/tax | Suppliers, COA, dimensions | Asset register, depreciation, disposal, FS/cash flow | M3 / Not Started | No policy master or canonical lifecycle | Define depreciation profiles and source chain before implementation |
| Accounting | Accounting; own GL, periods and close | Posting/Kernel, COA, Dimension, Period, Correction, Reporting | Every posting module | GL, TB, control reconciliations, FS source | M4 / Core In Progress; Schedules Not Started | All-consumer invariants, schedules, close | Prove canonical Sales/Purchase flows; then close/schedules |
| Compliance | Compliance; review, file and prove PH obligations | Missing Tax Engine; Number Series, Audit, Reporting, Posting boundary | Sales, Purchasing, Accounting, tax setup | Returns, certificates, SLS/SLP/RELIEF, books, CAS evidence | M4 / Blocked | PAD-001 and deferred artifacts | Product Architecture Decision for Tax Engine, then governed design |
| Reports | Reporting; financial and cross-domain decision support | Reporting/Reconciliation, COA, Dimension | Accounting and all source modules | FS, management reports, audit support | M4 / In Progress | Nine reconciliations; weak dimensional/FS-registry adoption | Rebuild on certified sources and execute reconciliation pack |
| Administration & Security | Product/Security decision; administer access | Certified Permissions/Audit, Approval | Product ownership decision | User/access review and support operations | M1 / Not Started | PAD-003; no UI | Decide visible vs external administration before design |

---

# 9.7 Development Roadmap

The order below targets a functional accounting ERP, not a high count of pages,
tables or work packages. Calendar commitments are intentionally absent.

## Phase A — Architecture and Planning Consolidation

- **Objective:** Establish this constitution/roadmap operating model, exact
  measures, reading order and next mission.
- **Business value:** Stops scope, taxonomy and progress-report drift before more
  implementation.
- **Prerequisites:** Current repository evidence and authority chain.
- **Included:** Product Architecture, this roadmap, AI_PROGRESS, AI_STATE, index,
  hand-off.
- **Excluded:** SQL, runtime, tests, UI/navigation, certification and hosted work.
- **Entry criteria:** Canonical Product Architecture exists.
- **Exit criteria:** Documents registered; M0–M9, DoD, dashboard and next mission
  agree; validation passes.
- **Proof required:** `docs:check`, links, authority/startup review, diff/scope
  verification.
- **Risks:** Creating another authority or carrying stale denominators.
- **Relative effort:** **Medium**.
- **Unlocks:** A governed return to engineering.

## Phase B — Resolve the Current Inventory Engineering Frontier

- **Objective:** Close WP5-AG-001…003 in documentation, re-run the gate, and—only
  if authorised—execute the bounded WP-5 lifecycle.
- **Business value:** Establishes the resolver contract needed for defensible,
  replayable inventory chronology and eventual COGS/valuation correctness.
- **Prerequisites:** Phase A; ADR-C01 frozen; ECC-01 accepted; WP-1…WP-4 certified
  and dormant.
- **Included:** WP-5 Engineering Amendment; Authorisation Gate; later
  implementation/audit/fix/certification only if separately authorised.
- **Excluded:** WP-6+, IA-6, production activation, Posting/Kernel changes, hosted
  application, operational Inventory changes.
- **Entry criteria:** Current rejection and three findings remain unchanged.
- **Exit criteria:** Minimum exit is an unambiguous gate decision. Product-value
  checkpoint required before continuing beyond WP-5.
- **Proof required:** Exact writer/resolver/trigger/rollback and dormant-fixture
  contracts; applicable gate evidence.
- **Risks:** Dormant foundation work outruns usable accounting value; excessive
  work-package granularity.
- **Relative effort:** **Small** for amendment/gate; **Medium** if later authorised
  implementation lifecycle is included.
- **Unlocks:** Safe decision on WP-5 and a governed choice whether later ECC work
  belongs in Phase G rather than continuing automatically.

## Phase C — Functional Accounting Core Proof

- **Objective:** Prove one complete Sales and one complete Purchasing workflow
  from source through books, tax and financial statements.
- **Business value:** First demonstrable evidence that PXL is an accounting ERP,
  not a set of pages and foundations.
- **Prerequisites:** Phase A; bounded Phase-B gate result recorded; current Posting
  and certified foundation engines green.
- **Included:** Select exact canonical scenarios; source review; posting,
  subledger, GL, TB, FS, VAT/WHT/books, correction and trace evidence; owner
  decisions PAD-002 and PAD-001 initiated.
- **Excluded:** Whole-module certification, Banking, Fixed Assets, IA-6, broad UI
  rollout.
- **Entry criteria:** Scenario scope and governing rules approved; no prohibited
  behavior change hidden in an evidence mission.
- **Exit criteria:** Two repeatable local workflows produce correct, reconciled,
  traceable outcomes and all gaps are recorded.
- **Proof required:** Numeric journals/reconciliations, source-to-report trace,
  positive/negative/correction cases, canonical data and browser evidence.
- **Risks:** Existing parts may not compose; Tax Engine absence may force a stop
  rather than a workaround.
- **Relative effort:** **Large**.
- **Unlocks:** Evidence-led Sales/Purchasing completion scope and a real product
  critical path.

## Phase D — Tax and Compliance Architecture

- **Objective:** Decide PAD-001 and define one authoritative Tax Engine and its
  ownership, inputs, outputs, versioning and migration boundary.
- **Business value:** Prevents seven calculators from drifting and enables
  trustworthy filing workflows.
- **Prerequisites:** Phase C exposes the exact source/tax/report seams; Product
  Owner and CPA authority available.
- **Included:** Product Architecture Amendment if scope changes; Tax Engine
  architecture; PHP/VAT/PT/EWT/CWT/FWT boundaries; adoption sequence; explicit
  unsupported scope.
- **Excluded:** Implementation until architecture and engineering authority pass;
  unsupported tax forms invented from convention.
- **Entry criteria:** PAD-001 owner assigned and current calculation census
  refreshed.
- **Exit criteria:** Accepted architecture with one owner, lifecycle and
  certification plan.
- **Proof required:** Contract mapping to source transactions, tax ledger, GL,
  corrections, reports and BIR outputs.
- **Risks:** Regulatory error; duplication preserved behind a new name; scope
  expansion into unsupported forms.
- **Relative effort:** **Large**.
- **Unlocks:** Sales/Purchasing/Compliance integration and certification.

## Phase E — Sales & Receivables Completion and Certification

- **Objective:** Move Sales from M4 through M5/M6/M7 to M8 within an explicitly
  supported scope.
- **Business value:** Trustworthy quote-to-cash, receivables and revenue/tax books.
- **Prerequisites:** Phase C canonical Sales proof; Phase D tax contract; required
  engines certified or explicitly blocking.
- **Included:** Conversion, partials, returns-to-stock, credit/debit correction,
  applications, attachments, approval, periods, reports, source review and all
  applicable DoD gates.
- **Excluded:** Multi-currency unless PAD-005 expands scope; deferred sales
  features not accepted into the module.
- **Entry criteria:** Supported workflow inventory frozen; engines/dependencies
  mapped.
- **Exit criteria:** Certification Matrix records the formal decision; M8 only if
  all mandatory gates pass.
- **Proof required:** Full revenue-cycle scenarios, AR-control equality,
  tax-ledger equality, inventory/COGS where applicable, correction and browser
  evidence.
- **Risks:** Declaring Sales Invoice success equal to module success.
- **Relative effort:** **Very Large**.
- **Unlocks:** A dependable revenue cycle and downstream reporting.

## Phase F — Purchasing & Payables Completion and Certification

- **Objective:** Move Purchasing from M4 to a certified procure-to-pay scope.
- **Business value:** Correct liabilities, input tax/EWT, stock receipts and
  supplier payments.
- **Prerequisites:** Phase C canonical Purchasing proof; Receiving accounting
  architecture authorised; Phase D tax contract.
- **Included:** Three-way match, over-receipt/over-bill controls, partials,
  returns, credits, payments, supplier bank decision, attachments, approvals,
  source review and all DoD gates.
- **Excluded:** Unauthorised Inventory Accounting activation and broad Treasury
  features.
- **Entry criteria:** Receiving-to-journal asymmetry has a governed design.
- **Exit criteria:** AP/control, input tax/EWT and source-to-books proof pass; formal
  certification decision recorded.
- **Proof required:** Positive/negative/concurrency/correction scenarios and
  canonical reconciliations.
- **Risks:** Fixing Inventory variance heuristically instead of correcting source
  accounting.
- **Relative effort:** **Very Large**.
- **Unlocks:** Reliable procurement, Inventory integration and payables.

## Phase G — Inventory Operational and Accounting Integration

- **Objective:** Make quantity and value reproducible, reconcile Inventory to GL,
  and activate governed costing only after evidence permits it.
- **Business value:** Trustworthy COGS, gross margin and inventory balance.
- **Prerequisites:** Phase F Receiving accounting; WP-5 decision; explicit
  product-value checkpoint; PAD-006 activation decision.
- **Included:** Remaining authorised ECC packages as needed, final IA-5 evidence,
  IA-6 only after authority, operational events, negative-stock/concurrency,
  returns, UOM, valuation and GL reconciliation.
- **Excluded:** Production source enablement before its gate; Posting/Kernel
  deviation; lot/serial/landed cost unless separately accepted.
- **Entry criteria:** Operational source and costing scope approved; no non-zero
  dormant event contamination.
- **Exit criteria:** Quantity and value replay; inventory subledger equals GL;
  costing and corrections deterministic; formal engine/module decisions.
- **Proof required:** ADR-C01 executable evidence, replay permutations,
  concurrency, FIFO/WAC rules, rollback, posting and reconciliation.
- **Risks:** Highest technical complexity; over-engineering; historical/backdate
  correctness; performance.
- **Relative effort:** **Very Large**.
- **Unlocks:** Reliable gross margin, Inventory certification and Posting P6.

## Phase H — Banking & Treasury

- **Objective:** Convert the M3 shell into controlled cash/bank operations and
  reconciliation.
- **Business value:** Cash custody, statement reconciliation and controlled
  disbursement.
- **Prerequisites:** PAD-004; Sales/Purchasing payments stable; bank account and
  supplier bank boundaries decided.
- **Included:** Petty cash, transfers, adjustments, check lifecycle, statement
  import/manual match minimum, outstanding items, reversals and bank-to-GL proof.
- **Excluded:** Auto-match and split sophistication unless needed by pilot.
- **Entry criteria:** Ownership and sealed-write-boundary architecture accepted.
- **Exit criteria:** Canonical bank workflow and reconciliation pass; certification
  decision recorded.
- **Proof required:** Statement-to-book-to-GL equality, negative/concurrency,
  reversal and period cases.
- **Risks:** Direct-write exceptions and cash control failures.
- **Relative effort:** **Very Large**.
- **Unlocks:** Complete cash position and stronger balance sheet.

## Phase I — Fixed Assets

- **Objective:** Complete acquisition-through-disposal and book/tax depreciation.
- **Business value:** Correct non-current assets, depreciation, gains/losses and
  cash-flow classification.
- **Prerequisites:** Depreciation-profile architecture; Purchasing and Accounting
  stable.
- **Included:** Asset master/register, acquisition, depreciation, transfer,
  impairment, disposal, duplicate-run/period rules and reconciliation.
- **Excluded:** Unsupported specialist asset classes unless explicitly accepted.
- **Entry criteria:** Policy master and source-chain architecture governed.
- **Exit criteria:** Asset register equals GL; book/tax schedule reconciles; module
  decision recorded.
- **Proof required:** Full lifecycle, closed-period, reversal and repeat-run cases.
- **Risks:** Accounting-policy ambiguity and test-fixture evidence mistaken for
  operational maturity.
- **Relative effort:** **Large**.
- **Unlocks:** Complete balance sheet and cash-flow investing section.

## Phase J — Financial Statements and Management Reporting

- **Objective:** Make every decision-grade report reconcile, drill and export from
  certified sources.
- **Business value:** Trustworthy financial statements and management insight.
- **Prerequisites:** Sales, Purchasing, Inventory and material balance-sheet
  modules stable; COA/Dimension consumers ready.
- **Included:** FS registry adoption, nine reconciliation pack, adjusted and
  post-closing TB, dimensional management reports, drill-down and export parity.
- **Excluded:** Parallel report data stores and unsupported scheduled delivery.
- **Entry criteria:** Source modules define report contracts and period semantics.
- **Exit criteria:** All applicable report gates and nine reconciliations pass;
  Reports certification decision recorded.
- **Proof required:** Explicit numbers from canonical data and source-to-FS trace.
- **Risks:** Beautiful reports over incomplete source modules; double counting.
- **Relative effort:** **Large**.
- **Unlocks:** Month-end close, audit support and management acceptance.

## Phase K — Administration, Backup, Security and Operational Readiness

- **Objective:** Make PXL operable and recoverable by accountable humans.
- **Business value:** Deployability, security administration, recoverability and
  support.
- **Prerequisites:** PAD-003 and PAD-007; target hosting/support model.
- **Included:** User/role/scope administration or explicit external procedure;
  backup/restore; RPO/RTO; monitoring; support/runbooks; performance; migration
  parity; security review.
- **Excluded:** Pilot claim until all exit evidence passes.
- **Entry criteria:** Operations and Security owners assigned.
- **Exit criteria:** Successful restore, hosted parity, monitoring/support and
  operational gates pass.
- **Proof required:** Timed restore, integrity checks, access tests, incident and
  deployment runbooks, realistic-volume evidence.
- **Risks:** Treating provider defaults as evidence; hidden manual operations.
- **Relative effort:** **Large**.
- **Unlocks:** Pilot gate consideration.

## Phase L — Pilot and Production Readiness

- **Objective:** Validate PXL with a low-risk real client under parallel control,
  then decide production readiness.
- **Business value:** Converts engineering confidence into accountable business
  acceptance.
- **Prerequisites:** Applicable module/engine certification; opening balances;
  Phase K; no unresolved Critical/High defects.
- **Included:** Controlled onboarding, opening-balance reconciliation, roles,
  parallel/shadow period, month-end, correction, restore and user acceptance.
- **Excluded:** Immediate broad launch and unsupported modules.
- **Entry criteria:** Product Owner approves pilot scope and fallback plan.
- **Exit criteria:** Pilot acceptance with zero unexplained GL, subledger,
  inventory, tax or report variance; Production Readiness Gate decision.
- **Proof required:** Signed acceptance, reconciled cut-over and month-end,
  operational evidence and support readiness.
- **Risks:** Pilot scope creep, incomplete opening data, support dependency.
- **Relative effort:** **Very Large**.
- **Unlocks:** M9 only for the explicitly proven scope.

---

# 9.8 Critical Path

## 9.8.1 Target milestone

> A user creates a valid business transaction, the system posts the correct
> journal, updates the proper subsidiary ledger, balances the General Ledger,
> appears correctly in the Trial Balance and Financial Statements, and produces
> the correct Philippine tax and books-of-accounts effects with full audit
> traceability.

## 9.8.2 Shortest safe route

```text
Phase A architecture/roadmap truth
  ↓
WP-5 documentation amendment and gate (clear active frontier; no automatic WP-6+)
  ↓
Choose one Sales + one Purchasing canonical scenario
  ↓
Prove source fields, lifecycle and correction
  ↓
Resolve Receiving Report accounting asymmetry
  ↓
Prove Posting → AR/AP → GL → TB → FS
  ↓
Decide and govern the Tax Engine boundary
  ↓
Prove VAT/WHT/books and source-to-report trace
  ↓
Close module/engine evidence gates
  ↓
Opening balances + hosted parity + restore + UAT
```

## 9.8.3 What already exists

- Strong core source transactions, the Posting doorway and fully enforced Kernel.
- AR/AP as-of functions, GL, Trial Balance and financial-statement surfaces.
- Tax detail/ledger and substantial BIR books/read/report surfaces.
- Certified Permissions, Audit, Number Series and Dimension engines.
- Source-to-journal trace RPCs and audit history.

## 9.8.4 What must be completed

- Whole-flow source qualification, lifecycle/correction and numeric
  reconciliation for one Sales and one Purchasing scenario.
- Receiving-to-journal correctness and Inventory-to-control reconciliation.
- Tax Engine ownership/architecture and one authoritative calculation contract.
- The applicable module/engine gates, hosted parity, opening balances,
  backup/restore and user acceptance.

## 9.8.5 What can wait

- Broad Banking and Fixed Asset functionality if the first accounting-core proof
  and pilot scope exclude them explicitly.
- Multi-currency, budgeting, notifications, lot/serial, landed cost, automated
  statement matching and dashboard personalization.
- Navigation cleanup and cosmetic duplicate removal, unless pilot usability makes
  deferred-state labelling necessary.

## 9.8.6 What must not be built yet

- WP-5 implementation before a successful Authorisation Gate.
- WP-6…WP-9, IA-6 or production Inventory source activation without their own
  authority.
- A Tax Engine implementation before PAD-001 and accepted architecture.
- Multi-currency behavior before PAD-005.
- Bank Reconciliation before PAD-004.
- UI/navigation redesign under an accounting implementation mission.

## 9.8.7 Over-engineering warning

The IA-5/ECC programme solves a real, high-severity determinism problem. WP-5's
specification repair is justified because it is small, bounded and prevents an
unsafe implementation. **Automatically executing WP-6…WP-9 because the programme
exists would be over-engineering** if Sales/Purchasing source proof, Receiving
accounting, Tax authority, opening balances or backup remain unattended. Each
later package must demonstrate that it advances Inventory-to-GL and the target
milestone, not merely that it completes another foundation artifact.

## 9.8.8 More urgent than additional foundation after WP-5

Receiving Report accounting, canonical Sales/Purchase flow proof, Tax Engine
authority, opening-balance strategy and restore evidence yield more direct
product value than continuing dormant foundation work without an activation
path. These items must control the value checkpoint after the WP-5 gate.

---

# 9.9 Risk Register

| ID | Risk | Severity | Likelihood | Evidence | Consequence | Mitigation | Owner | Resolve by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PR-01 | Scope size exceeds delivery capacity | High | High | 11 modules, 19 engine scopes, 202 tables, large visible surface | Endless partial product | Freeze supported pilot scope; use DoD and dependency gates | Product Owner | Phase C entry |
| PR-02 | Product architecture drift | High | Medium | Historical blueprint, routes and certification boundaries diverged | Contradictory work and rework | Product Architecture is canonical; amendment required for scope change | Product Architect | Continuous; first review Phase C |
| PR-03 | Documentation proliferation | High | High | Many active specifications and prior assumed missing review | Readers choose wrong authority | One constitution, one roadmap, one dashboard; index routes only | Governance Lead | Phase A exit |
| PR-04 | Certification detaches from product value | High | High | 4 work packages certified while no module is certified | Foundation throughput masks unusable ERP | Value checkpoint after WP-5; require workflow outcome per programme | Product Owner | Phase B exit |
| PR-05 | UI ahead of runtime | High | High | 33 pure-deferred routes; 18 placeholders | Users mistake shells for features | Governed state labels; PAD-012; pilot UX check | Product + UX | Before Phase L entry |
| PR-06 | Backend ahead of usable workflows | Medium | High | Seven backend-only clusters; two unlisted trace routes | Valuable work unused; duplicate rebuilds | Adoption backlog tied to owning module and DoD | Module Owners | Relevant module phase |
| PR-07 | Excessive work-package granularity | High | Medium | Repeated IA-5 amendments/gates around dormant structures | Governance cost exceeds product value | Package only independent rollback/risk units; merge inseparable work; value gate | Architecture Owner | Phase B exit |
| PR-08 | No canonical end-to-end workflow | Critical | High | 0/6 portfolio reference flows meet DoD | Cannot demonstrate ERP correctness | Phase C proves Sales and Purchasing flows first | CPA + Product | Phase C exit |
| PR-09 | Tax Engine authority absent | Critical | High | M0; seven duplicated calculators | Inconsistent tax and incomplete compliance | PAD-001 then Phase D architecture | Product + CPA | Phase D exit |
| PR-10 | Inventory complexity consumes roadmap | Critical | High | C-01, WP-5 rejected, legacy variance, future IA-6 | Delayed product with continued valuation risk | Bound Phase B; operational/value checkpoint; Phase G only after prerequisites | Inventory Owner | Phase B and G gates |
| PR-11 | Hosted parity gap | Critical | High | 51 local migrations not hosted | Local evidence does not describe hosted product | Explicit authorised migration/rehearsal plan; no hosted claim until proven | Operations | Phase K exit |
| PR-12 | Backup/restore absent | Critical | High | No runbook, RPO/RTO or restore test | Permanent loss; no certification/pilot | PAD-007; timed restore test | Operations + Security | Before Setup certification / Phase K |
| PR-13 | Dirty/uncommitted repository obscures provenance | High | High | Working tree contains many modified/untracked files | Change attribution and rollback risk | Preserve tree; mission-start/end manifests; intentional commits only by owner | Repository Owner | Before implementation branch/release |
| PR-14 | AI-generated implementation lacks accountable review | High | High | Repository work is heavily AI-driven; human review evidence limited | Subtle accounting/security defects | CPA + engineer review gates; executed evidence; small bounded changes | Product Owner | Every authorisation/certification |
| PR-15 | Limited human engineering review | High | Medium | Independent reviews are mainly repository missions | Architectural blind spots persist | Assign named human reviewers for accounting, security and operations | Product Owner | Phase C entry |
| PR-16 | Security/tenant regression | Critical | Medium | Prior critical reporting leak and immutability bypass found during certification | Cross-company disclosure or altered history | Preserve certified guards; cross-tenant browser/API tests; hosted security proof | Security Owner | Every release; Phase K |
| PR-17 | Philippine compliance error | Critical | High | Tax Engine absent; forms/artifacts deferred | Penalties, invalid books/returns | CPA-owned tax architecture; versioned rules; reconciled filing scenarios | CPA Owner | Phase D/G and before pilot |
| PR-18 | Support/operations unavailable | High | High | No production operations programme completed | Users cannot recover or get help | Runbooks, monitoring, incident/support ownership and service boundaries | Operations Owner | Phase K exit |
| PR-19 | Performance fails at realistic volume | High | Medium | High-volume demo exists but production-volume certification is incomplete | Slow posting/reports, adoption failure | Targets, profiling, concurrency/load evidence on critical paths | Engineering Owner | Phases G/J/K |
| PR-20 | Opening-balance strategy absent | Critical | High | No workflow/table/import | Existing businesses cannot onboard | PAD-002; governed cut-over design and reconciliation | Product + CPA | Phase C decision; Phase L entry |
| PR-21 | Receiving accounting asymmetry persists | Critical | High | Receipt raises stock without journal; Vendor Bill debits clearing | Inventory/GL and COGS unreliable | Govern source accounting; test and reconcile rather than heuristic adjustment | Purchasing + Inventory + CPA | Phase F entry/exit |
| PR-22 | Maturity metrics are gamed | High | Medium | Prior 42% combined modules/engines/absences | False confidence and bad sequencing | Exact denominators only; methodology in §9.10 | Governance Lead | Continuous |
| PR-23 | Direct-write exceptions breach architecture | High | Medium | `bank_recon_items`, `book_tax_reconciliation` excluded from P5.0 | Unsealed accounting effects | Resolve in PAD-004/Tax architecture; keep explicit until closed | Accounting Architect | Phases D/H |
| PR-24 | Historical chronology is rewritten | High | Low | Many issued audits/specs with later corrections | Loss of audit provenance | Prospective correction and supersession only | Governance Lead | Every documentation mission |

---

# 9.10 Executive Progress Dashboard

## 9.10.1 Module dashboard

| Module | Maturity | What currently works | What does not yet work | Certification | Main blocker | Next milestone | Production-ready |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Setup | M7 | Provisioning, company/branch/calendar/COA/series/tax setup | CAS/opening/rule decisions; operational evidence | Combined scope Blocked | Restore + browser evidence | Setup/Master certification evidence | **No** |
| Master Data | M7 | Core parties/items/UOM/warehouses/bank/payment terms | Some masters have no UI; supplier bank absent | Combined scope Blocked | Same evidence plus scope gaps | Source-backed onboarding set | **No** |
| Sales & Receivables | M4 | SI/CS/OR/CM core lifecycles, AR/read reports | Conversion, returns, broad source review, attachments, full reconciliation | In Progress | Whole-cycle evidence | Canonical Sales flow | **No** |
| Purchasing & Payables | M4 | PO/VB/CP/PV/VC core workflows | Receiving journal, match, returns, full evidence | In Progress | Receiving asymmetry | Canonical Purchase flow | **No** |
| Inventory | M4 | Balance, movements, adjustments, transfers, counts | Goods Issue, reliable valuation/replay, control tie-out | In Progress | C-01 + valuation variance | WP-5 gate, then value checkpoint | **No** |
| Banking & Treasury | M3 | Bank-account master; source-module receipts/payments | Canonical treasury and reconciliation workflows | Not Started | Empty governed data; PAD-004 | Architecture/ownership decision | **No** |
| Fixed Assets | M3 | Routes and backend routines only | Canonical asset lifecycle and policy master | Not Started | Depreciation authority absent | Phase-I architecture | **No** |
| Accounting | M4 | JE/reversal, GL, ADL, TB, reviews, trace backend | All-consumer proof, schedules, close, reconciliations | Core In Progress; Schedules Not Started | Integrated flow evidence | Phase-C proof | **No** |
| Compliance | M4 | Reviews, ledgers, books and audit surfaces in part | Tax Engine, workpapers/returns/certificates/filed artifacts | Blocked | PAD-001 | Tax architecture | **No** |
| Reports | M4 | Primary FS and several source-backed reports | Nine reconciliations, complete drill/export and dimensional adoption | In Progress | Source/reconciliation proof | Phase-J report pack | **No** |
| Administration & Security | M1 | Certified enforcement engines exist | No product administration workflow | Not Started | PAD-003 | Ownership decision | **No** |
| Dashboard *(surface)* | M4 | Setup/count/deadline monitoring | KPI grid, roll-up, export, owner | No scope | Ownership/KPI contract | Product decision | **No** |

## 9.10.2 Shared-engine dashboard

| Engine | Maturity | Certified scope | Consumers | Main blocker | Next milestone |
| --- | --- | --- | --- | --- | --- |
| Posting | M7 | None as whole engine; Kernel P5.2 enforced | All posting modules | Inventory P6 reconciliation | Phase-C flows / later P6 |
| Inventory Accounting | M2 | WP-1…WP-4 work packages only | Future Inventory/Posting | WP-5 rejected; C-01 | WP-5 amendment and gate |
| AR | M4 | None | Sales, Accounting, Reports | Scenario-wide control proof | Canonical Sales flow |
| AP | M4 | None | Purchasing, Accounting, Reports | Scenario-wide control proof | Canonical Purchase flow |
| Payment & Application | M4 | None | Sales, Purchasing, Banking | Over/unapplied/reversal/concurrency proof | Phase C/E/F/H evidence |
| Tax | M0 | None; absent | Sales, Purchasing, Compliance | PAD-001 | Phase-D architecture |
| Document Conversion | M1 | None | Sales, Purchasing | No implementation | Phase-E/F design |
| Number Series | M8 | **Certified** | Transaction modules | Broader provisioning limitation | Preserve; consumer module evidence |
| Approval & Workflow | M4 | None | Imports; future transactions | One proven consumer | Transaction rollout plan |
| Period Lock & Closing | M4 | None | Posting modules | Year-end close/reopen | Phase C/J |
| Reversal/Void/Correction | M4 | None | Posting modules | Incomplete transaction coverage | Canonical flows then module phases |
| Audit & Immutability | M8 | **Certified** | Every module | Hosted parity later | Preserve; hosted proof Phase K |
| Permissions & RLS | M8 | **Certified** | Every module | Hosted/browser strengthening | Preserve; Phase-K proof |
| Dimension | M8 | **Certified** | Posting modules, Reports | Management reports do not consume certified report | Phase-J adoption |
| Currency | M1 | None; deferred | Future modules | PAD-005 | PHP-only scope maintained |
| Reporting & Reconciliation | M4 | None | Every module | 0/9 certified reconciliations | Phase-C then J pack |
| Attachment & Traceability | M4 | None | Transactions/reports | File workflow absent; trace unlisted | PAD-008 and module adoption |
| Backup & Recovery | M0 | None | Whole product | No architecture/evidence | PAD-007 and Phase K |
| COA | M4 | None | Posting, Accounting, Reports | Consumer migration incomplete | Complete adoption/certification |

## 9.10.3 Exact portfolio metrics

- **Certified modules:** 0 / 11 certification scopes.
- **Certified engines:** 4 / 19 engine assessment scopes.
- **Certified work packages:** IA-5 ECC 4 / 9; no other programme ratio is
  asserted here.
- **Modules by maturity:** M1 1; M3 2; M4 6; M7 2. Dashboard separately M4.
- **Engines by maturity:** M0 2; M1 2; M2 1; M4 9; M7 1; M8 4.
- **Canonical workflows proven:** 0 / 6 portfolio reference flows in §9.5.
- **Source-backed transaction workspaces:** 1 / 41 source-reviewed registry
  entries. The other 40 are structurally registered but transaction-matrix-only;
  they are not all equivalent to UI-only routes.
- **UI-only/scaffold workspaces:** 33 pure-deferred reachable routes.
- **Disabled/deferred navigation features:** 18 disabled placeholders; 33
  pure-deferred reachable routes; 55 duplicate labels. These sets overlap in
  purpose and must not be summed as unique capabilities.
- **Deferred features:** 18 explicitly disabled navigation placeholders. This
  is a navigation-entry count, not a count of all deferred product requirements.
- **Deferred backing structures:** 61 `future-deferred` tables and 21
  `workflow-deferred` tables. These are homogeneous table-class measures, not
  feature counts.
- **Hosted migration parity:** through migration `20260716000005`; 51 later
  local migrations are not hosted.
- **Backup/restore evidence:** **Not Tested**.
- **Product readiness:** **Not Ready — Internal QA/demo only**.

No “Overall ERP” percentage is permitted. Any percentage used in future must
state a homogeneous numerator, denominator and meaning.

---

# 9.11 Repository Health Assessment

| Area | Evidence-based assessment |
| --- | --- |
| Product vision | Strong, differentiated and valuable: accounting-first PH compliance for multi-company businesses. It is broader than current delivery capacity and needs a pilot scope. |
| Accounting architecture | The strongest part of PXL. The sealed posting doorway and immutable, traceable ledger are excellent. Receiving accounting and Inventory valuation are serious unresolved exceptions. |
| Engineering architecture | Strong database controls and evidence discipline. Complexity is high, local/hosted states diverge, and dormant architecture risks outrunning product workflows. |
| Repository structure | Generally governed and navigable, but the dirty tree, large active-doc set and prior missing/assumed review create provenance risk. |
| Code maturity | Substantial local implementation with many guarded RPCs and tests. Maturity is uneven: strong transaction cores coexist with empty module scaffolds. |
| Module maturity | No module is M8 or M9; no transactional module is M5. Setup/Master are closest to certification. |
| Certification maturity | Engine certification is meaningful and has found critical defects. Module certification has produced no certified module; work-package throughput must not become the goal. |
| Documentation quality | Deep and evidence-rich, but historically fragmented and repetitive. This constitution/roadmap/index model should reduce reconstruction work. |
| Test quality | Strong pgTAP breadth, negative controls and governance guards. Test presence is sometimes mistaken for workflow maturity; browser and restore evidence remain weak/absent. |
| UI/runtime alignment | Poor in deferred clusters: 33 pure empty routes and 18 placeholders. Backend/UI adoption gaps also exist. |
| Security | Locally strong in certified RLS/immutability scope. Hosted parity and operational administration remain unproven. |
| Auditability | Strong source/journal/audit foundations; attachments and some persisted statutory artifacts are absent. |
| Production readiness | **Not ready.** Hosted parity, restore, operations, opening balances, module certification and UAT are missing. |
| Biggest strength | The database-enforced accounting/security control foundation, especially the single Posting doorway and independently certified engines. |
| Biggest weakness | No fully proven business-to-financial-statements-to-tax workflow, despite a very large surface and foundation programme. |
| Most dangerous assumption | That green tests, closed findings, rendered routes or certified work packages imply a deployable ERP. They do not. |
| Most valuable next investment | After the bounded WP-5 documentation repair, prove the two Phase-C canonical accounting flows and resolve Receiving/Tax/opening/restore decisions. |
| Activities that should stop | Mixed-unit percentages; page/table counts as progress; automatic continuation of dormant work packages; duplicate authority documents; unsupported hosted claims; cosmetic expansion before workflow proof. |
| Activities that should continue | Database-enforced invariants; small governed scopes; independent negative evidence; exact reconciliations; explicit dormancy; preserved chronology; CPA/security review. |

---

# 9.12 Recommended Operating Model

```text
Product Need
  ↓
Product Architecture Review
  ↓
Canonical Module / Engine Ownership
  ↓
Dependency and Scope Review
  ↓
Architecture or Engineering Design
  ↓
Authorisation
  ↓
Implementation
  ↓
Brutal Audit
  ↓
Brutal Fix if needed
  ↓
Audit Re-run
  ↓
Certification
  ↓
Hosted Parity
  ↓
User Acceptance
  ↓
Production Readiness
```

## 9.12.1 Decision rules

- **Product Architecture Amendment required:** product scope, product boundary,
  module/engine ownership or taxonomy, canonical naming, supported currency/tax
  boundary, visible-versus-hidden classification, product maturity model or
  production-readiness contract changes.
- **Engineering Amendment sufficient:** an accepted product scope remains
  unchanged and only an implementation contract, object shape, rollback,
  evidence allocation or technical design needs correction.
- **Work package justified:** the change has an independent risk/rollback/evidence
  boundary, can be certified without implying a broader capability, and its
  completion unlocks a named dependency.
- **Granularity is excessive:** packages divide inseparable objects, repeat full
  governance with no distinct risk, certify dormant structure without moving a
  product dependency, or cost more to govern than to implement/review safely.
- **Exceptional root-cause mission permitted:** current evidence conflicts,
  accounting/security correctness is uncertain, or a gate fails for a cause that
  cannot safely be inferred. It is read-only until root cause is proven.
- **Implementation must stop:** Tier-1 authorities conflict; owner decisions are
  missing; the Authorisation Gate rejects; a stop condition fires; scope would
  expand; accounting/security behavior would change without authority; dormancy
  would be broken; or hosted work lacks explicit approval.
- **Module may be called complete:** every applicable criterion in §9.4 passes.
  M5 means workflow complete only; M8 means certified; M9 means production ready.
- **Product may be piloted:** required modules/engines are certified for the pilot
  scope; opening balances and hosted parity reconcile; restore/security/support
  evidence passes; a low-risk client has a parallel fallback; Product Owner and
  users accept the scope.

## 9.12.2 Permanent reading order

Every future AI agent begins with:

1. `AI/AGENT_SYSTEM_PROMPT.md`
2. `AI/AI_STATE.md`
3. `AI_LAST_SESSION.md`
4. `docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`
5. this roadmap when planning, sequencing, reporting maturity or selecting work
6. only the exact certification/domain authorities named by the active mission

The Product Architecture is the first product authority. This roadmap is not an
implementation instruction.

---

# 9.13 Selected Next Governed Mission

**Selected mission:** **WP-5 Engineering Amendment — documentation only, limited
to WP5-AG-001 through WP5-AG-003.**

Why it remains next:

1. Phase A is complete when this mission validates; product taxonomy and roadmap
   no longer need reconstruction.
2. WP-5 is the current rejected engineering frontier and its three blockers are
   exact documentation defects, not unknown product scope.
3. The amendment is the smallest safe mission: it changes no runtime and grants
   no implementation authority.
4. Deterministic Inventory economic order is ultimately required for reliable
   COGS, valuation, Inventory-to-GL reconciliation and Posting P6, so clearing the
   unsafe contract advances a real accounting dependency.
5. Higher-value product blockers—Tax ownership, opening balances, backup,
   Receiving accounting—need Product Owner/CPA/Operations decisions or broader
   architecture. They are sequenced and cannot be guessed into implementation.
6. WP-5 is **not** authority to continue WP-6…WP-9 automatically. A value
   checkpoint after its gate prevents over-engineering and moves priority to the
   Phase-C accounting flows if later dormant work is not immediately necessary.

The next mission must not implement WP-5, resolve the three findings by inference,
alter ADR-C01/ECC-01, activate Inventory, touch Posting/Kernel, begin IA-6 or make
hosted changes. After the amendment, a separate WP-5 Authorisation Gate must
decide whether implementation may begin.

---

# 9.14 Maintenance and Non-Authority

Update this roadmap when evidence changes a maturity placement, phase dependency,
DoD state, risk, denominator, hosted high-water mark or next governed mission.
Do not use it to rewrite issued certification chronology or silently amend the
Product Architecture.

Creating this roadmap changes no runtime, certification, authorization, product
surface or hosted state. PXL remains Internal QA/demo only.
