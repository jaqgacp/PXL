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
**Date:** 2026-08-04
**Evidence baseline:** Current local repository and validation evidence through
commit `6b99d8b`; exact mutable counts live only in `AI/AI_STATE.md` and the
Product Architecture census. No hosted read or mutation was performed for this
roadmap.

> **Authority split, settled 2026-08-02.** `PXL_PRODUCT_ARCHITECTURE.md` defines
> **what** PXL is. `PXL_DELIVERY_PLAN.md` is the sole owner of **when and in what
> order** work ships — numbered phases, sequence, timeline and pilot roadmap.
> **This document explains why that order exists**: the dependencies between
> outcomes and the criteria for calling one complete.
>
> **This document carries no phase numbers**, and must never become a second
> delivery plan. It cannot add scope, change canonical naming, certify anything
> or authorise implementation.

> **Scope boundary (PAD-015, 2026-08-04).** The current product is Philippine SME
> accounting and compliance. FWT/1601FQ/2306, Payroll/2316, quarterly and annual
> Income Tax, MCIT/RCIT, NOLCO, OSD, Fringe Benefits Tax, Transfer Pricing,
> Consolidation Tax and specialized-industry tax features are future extensions,
> never blockers or required delivery items. After current compliance work,
> Banking & Treasury and then Fixed Assets are the ranked future priorities.

---

# 9.1 Executive Summary

PXL is a serious accounting foundation surrounded by an incomplete product. Its
best qualities are unusually strong: the General Ledger has one enforced posting
doorway; the Kernel Totality Guard is fully enforced; tenant isolation, audit
immutability, number series and dimensions are Certified; core sales, purchasing,
cash and journal transactions can post; GL, Trial Balance, several financial
statements, tax reviews and books read real posted data.

That is not the same as a finished ERP. No module is Certified. Banking and Fixed
Assets are UI skeletons over governed-empty data. The central Tax Engine now
exists as one guarded calculator for VAT, percentage tax and EWT/CWT, and six
registered compliance outputs use one Filing Artifact generator, working paper,
reconciliation and exporter. Exact purchasing quantity controls and ordered
receipt correction are locally proven; price variance remains undecided. The
receipt half of perpetual inventory was closed by `PXL-AUD-073` and inventory now
reconciles to its control account at ₱0.00. Opening balances, verified supplier
payees and restricted administration exist locally; operational onboarding
remains unproven. Recoverability is mechanised and scheduled but not operated
over anything real. Sixty-eight local migrations after `20260716000005` are not on
the hosted project. PXL remains **Internal QA/demo only — not pilot-ready and not
production-ready**.

> **Correction, 2026-08-02.** A previous edition of this summary stated that
> "sales-side COGS posting" was open. That was wrong and is withdrawn.
> `fn_post_sales_invoice` posts DR COGS / CR inventory through the shared
> Weighted Average, FIFO or Specific Identification authority, with an
> insufficient-stock guard and exact historical reversal; test
> `054` asserts it and the canonical ledger shows COGS debits equal to inventory
> credits in all three trading companies. Inventory could not tie out at ₱0.00 if
> the claim were true. **Every outbound entry point relieves stock as of
> 2026-08-03** — Cash Sale (test `119`), Delivery Receipt and Customer Return
> (test `120`) joined Sales Invoice, all through the same costing path. What *is*
> open on the sales side: document conversion beyond the delivery-to-invoice
> link. Delivery Receipt cancellation and all three production costing methods
> are now proven locally by tests `131`, `135`–`137` and committed lifecycles.

The visible product is ahead of runtime in **26** deferred routes, **17**
navigation labels with no page, and whole Banking/Fixed Asset/compliance-generator
clusters. The backend is ahead of the UI in party contacts, groups, item
extensions and inventory configuration. The
transaction workspace shell is structurally broad, but only Sales Invoice has a
source-reviewed workspace slice: **1 of 37** registry entries.

The dependency-forced order of outcomes is (§9.7):

1. **Customer-to-Cash** — document conversion, an AR-to-control guard and a
   fresh-data sales end-to-end test; cash-sale and delivery posting closed
   2026-08-03;
2. **Procure-to-Pay** — exact quantity matching and return costing are closed;
   price-variance policy, supplier-debit integration, AP reconciliation and the
   complete source-to-books proof remain;
3. ~~**Period Close**~~ — **closed 2026-08-03.** The statements are produced from
   governed configuration, the cycle closes into retained earnings, and the
   statements carry a comparative period and basic notes. What remains is a
   signature-ready note set, not a close;
4. **Tax Engine and Compliance** — calculator and Filing Artifact engine are
   delivered; finish the in-scope SLSP artifact migration and pilot proof;
5. then **Banking & Treasury**, followed by **Fixed Assets**. Excluded future
   extensions never displace them. Keep the frozen **Inventory Accounting**
   programme unbuilt until a real replay requirement exists; then
6. **Pilot Readiness** and **Production Readiness** require hosted parity,
   operated recovery, browser evidence, user acceptance and operating support.

For *when* each of these ships, read `PXL_DELIVERY_PLAN.md`; this document does
not schedule.

The dormant IA-5/ECC programme remains frozen. WP-5 is not next and must not
displace operated recovery, Tax ownership, usable accounting workflows or
onboarding evidence.

---

# 9.2 Current Product Baseline

## 9.2.1 Exact portfolio facts

**Deliberately not restated here.** Module counts, engine counts, certification
standing, finding counts, test counts, reconciliation standing, hosted parity and
backup standing live in `AI/AI_STATE.md`, and taxonomy lives in the Product
Architecture. This table previously duplicated all of them and drifted within a
single day of a code change — reporting inventory as unreconciled after it had
been fixed, and 110 tests after there were 111. A plan that restates status
becomes a trap for the next session.

Read `AI/AI_STATE.md` for where the product is. Read this document for the order
in which work should happen.

## 9.2.2 What is genuinely working

- Guided company setup, core master data, live numbering and dimensional masters.
- Sales Invoice, Cash Sale, Delivery Receipt/Customer Return, Official Receipt
  and Credit Memo posting lifecycles in meaningful local scope.
- Purchase Order, Vendor Bill, Cash Purchase, Payment Voucher and Vendor Credit in
  meaningful local scope.
- Manual Journal posting and reversal; GL, Account Detail Ledger and Trial Balance.
- Inventory adjustments, transfers, physical counts, stock balance and movements,
  subject to the valuation/reconciliation warning.
- Posted-data VAT, percentage-tax and withholding reviews; six governed Filing
  Artifacts and exports; BIR books, CAS logs and hashed evidence; three critical
  reconciliation families evidenced at 0.00.
- Four Certified engines and a fully enforced Posting Kernel guard.

## 9.2.3 Foundation only or dormant

- Inventory Accounting IA-5/ECC: M2, dormant, zero consumers, four certified
  work packages, C-01 still open, WP-5 rejected.
- COA Engine: foundation and partial consumer adoption, not engine-certified.
- Approval/Workflow: foundation and two configured workflows, but
  `approval_requests` and `approval_instances` have **never held a row** — the
  engine has never executed (corrected 2026-08-02).
- Financial-statement structure, contact/group/item-extension and branch-scope
  data foundations without complete user workflows.

## 9.2.4 UI ahead of backend

Banking & Treasury, Fixed Assets, Accounting Schedules, returns/corrective
documents, attachment artifacts and several CAS export surfaces present as routes
or pages while their governed backing tables remain empty. A route/page is
therefore evidence of surface coverage only.

The statutory working papers and return generators are **no longer** in this
category: since 2026-08-04 the VAT, EWT/1601EQ and percentage-tax working papers
are generated from the posted tax ledger through the Filing Artifact framework,
  and the four hand-keyed current-product screens were deleted. FWT/1601FQ and
  Income Tax are **excluded future extensions**, not surface or readiness gaps —
  see the Delivery Plan's exclusion table.

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
| Sales & Receivables | **M4** | SI, Cash Sale, Delivery Receipt and Customer Return all move inventory and COGS correctly (tests `054`, `119`, `120`). Held at M4 by: zero general document-conversion functions, no AR-to-control reconciliation guard, and no Quotation→SO→SI fresh-data proof. |
| Purchasing & Payables | **M4** | PO → RR → Bill is proven from first principles; exact receipt/bill quantity admission and ordered RR correction are concurrency-safe. Purchase Return is exercised through exact receipt-layer costing. Held at M4 by price-variance policy, supplier-debit integration and broad Product-DoD proof. |
| Inventory | **M4** | Inventory ties to control at **₱0.00**; Weighted Average, FIFO and Specific Identification are built, reachable, exercised and proven locally across production writers, exact reversal/return, transfer, identity selection and a concurrent serial race (`135`–`137` plus the committed lifecycle). Held at M4 by broad workflow/browser/hosted/certification evidence, not by a costing-method restriction. |
| Banking & Treasury | **M3** | Only `bank_accounts` holds data. `check_vouchers`, `fund_transfers`, `bank_reconciliations`, `petty_cash_vouchers`, `bank_adjustments` are **all empty**; their posting functions have never produced a journal. |
| Fixed Assets | **M3** | **All six tables empty**; five routes deferred; depreciation policy has no master. |
| Accounting | **M4** | 51 journals / 144 lines; trial balance out-of-balance **₱0.00 in all five companies**; 60 fiscal periods; all four statements produced from governed configuration, with comparatives and basic notes, since 2026-08-03; period close, year-end close and retained-earnings roll-forward all commit and are governed. Held at M4 by consumer-wide reconciliation proof — the close has never been operated over real books. |
| Compliance | **M5** | VAT, percentage tax and withholding all reconcile to the GL at 0.00 through **one** reconciliation. The Tax Engine shipped 2026-08-03; the Filing Artifact framework, its export and the 1601EQ/QAP/SAWT migration shipped 2026-08-04, and the legacy VAT/EWT/1601EQ/PT working-paper architecture was retired with them — `vat_returns`, `pt_returns` and `ewt_returns` are now projections of the artifact, not typed records. Held below M6 by the fact that **nothing has ever been filed with the Bureau**, by the SLSP screen's monthly-versus-quarterly evidence model (Backlog 8c / 8e ii), and by hosted operation being absent. FWT is **out of product scope** and is not counted here. |
| Reports | **M4** | 23 views plus the statement reporting entry point read posted data; comparatives, statement-line drill-down and basic notes shipped 2026-08-03. Held at M4 by **3 of 9** critical reconciliations evidenced, and by a signature-ready note set (Backlog 18i). |
| Administration & Security | **M4** | PAD-003 selected restricted in-product administration; four guarded screens exist locally, while hosted invite/browser/UAT and operating evidence remain open. |
| Dashboard *(not a module)* | **M4** | Live readiness/deadline monitoring works; KPI grid, range, roll-up, export and owner are incomplete. |

## 9.3.3 Engine placement

| Engine assessment scope | Level | Certification standing and decisive evidence |
| --- | --- | --- |
| Posting | **M7** | Governed, Kernel fully enforced; not Certified. **24 entry points defined, 15 have produced a journal.** IA-5/P6 remains frozen. |
| Inventory Accounting | **M2** | **Frozen.** 21 ECC tables, all empty, zero consumers; C-01 open; not Certified. WP-5…WP-9 and IA-6 unauthorised. |
| AR | **M4** | As-of engine works; full scenario reconciliation not Certified. |
| AP | **M4** | As-of engine works; full scenario reconciliation not Certified. |
| Payment & Application | **M4** | Normal applications work; over-application/unapplied/reversal/concurrency scope incomplete. |
| Tax | **M5** | Implemented 2026-08-03 (PAD-001). `fn_calculate_tax` is the only tax arithmetic in the schema; all **eleven** former calculators migrated. VAT, percentage tax and EWT/CWT are current scope. Not certified. |
| Document Conversion | **M1** | **Zero conversion or copy-forward functions** among 437. Implementation not started. |
| Number Series | **M8** | Certified 2026-07-23. 264 series, 218 CAS issuances. |
| Approval & Workflow | **M4** | 2 workflows defined; **`approval_requests` = 0, `approval_instances` = 0 — never executed.** No notification model exists anywhere in the product. |
| Period Lock & Closing | **M4** | Monthly/quarterly close, year-end close, controlled reopening and retained-earnings roll-forward are implemented and guarded; no real-books operation. |
| Reversal, Void & Correction | **M4** | Reversal strong; void/correction coverage incomplete. |
| Audit & Immutability | **M8** | Certified 2026-07-23. 2,358 audit rows; 110 tables carry guard/immutability triggers. |
| Permissions & RLS | **M8** | Certified 2026-07-22. **208 of 208 tables RLS-enabled, 501 policies, zero tables without a policy.** |
| Dimension | **M8** | Certified 2026-07-23. Line-level guards on both ledger tables; `vw_gl_dimension_summary`. |
| Currency | **M1** | PHP-only (PAD-005). 9 currencies listed, **`exchange_rates` empty**, non-PHP fails closed. |
| Reporting & Reconciliation | **M4** | 23 views plus `fn_financial_statement_report` read posted data. **3 of 9** critical reconciliations evidenced at 0.00; comparatives and basic notes are implemented. |
| Attachment & Traceability | **M4** | Source trace works and is now routed; **`cas_attachment_register` empty** — no file lifecycle. PAD-008 undecided. |
| Backup & Recovery | **M5** | Tooling complete and scheduled: fail-closed `backup:operate`, weekly drill workflow, **replicated copy restored independently** (93 tables / 0 mismatches / 6s), retention 30/12/7 enforced, all refusals exercised. PAD-007 decided (S3-compatible). **No bucket, no escrowed passphrase, schedule never fired, no hosted/PITR proof.** |
| COA | **M4** | 215 accounts, 55 mappings, cert test `081`. FS classification seeded and mapped with every chart since 2026-08-03; all-consumer adoption incomplete. |

The Accounting Kernel is **M7**, fully enforced, and nested inside Posting. It
is not included in the 19-engine denominator.

---

# 9.4 Product Definition of Done

## 9.4.0 The Pilot Bar — the operative gate for v1

The 26-criterion Production Bar below is correct and it is **not achievable
first**. Twenty-six criteria across eleven modules is 286 gates, with zero modules
past gate 3 after months of work. A bar nobody can clear stops functioning as a
bar and starts functioning as a reason nothing ships.

There are therefore **two bars**, and a module is measured against the Pilot Bar
until a pilot is running:

| # | Pilot Bar criterion | Production Bar equivalent |
| ---: | --- | --- |
| P1 | Transaction lifecycle works end to end (draft → post → correct → void) | 4, 15 |
| P2 | Posting is correct and goes through the sealed doorway | 8 |
| P3 | The module reconciles to the General Ledger, evidenced by a guard test | 9 |
| P4 | Philippine tax treatment is correct where applicable | 10 |
| P5 | Permissions and segregation of duties hold | 12 |
| P6 | Audit trail is complete and posted records are immutable | 13 |
| P7 | Period controls are enforced | 16 |
| P8 | One canonical end-to-end workflow is proven with real data | 19 |
| P9 | Automated tests cover the above and run in the regression lane | 18 |
| P10 | Backup and restore are proven for the whole product | 24 |

Deferred to the Production Bar, explicitly and without apology: hosted parity,
attachments, approval routing, user acceptance, the release gate, full
documentation completeness, and the Brutal Audit and certification ceremonies.

**Rule.** A module that passes all ten Pilot Bar criteria may be used in a
controlled pilot with a named client and a parallel manual process. It may not be
called *Certified*, *Complete*, or *Production Ready* — those words remain
reserved for the Production Bar. Nothing in this section lowers the Production
Bar; it only stops the Production Bar from being the only bar.

## 9.4.1 Universal criteria — the Production Bar

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
| Setup | 1–7, 10–14, 16–26 | **4–7, 10–11, 14, 17–26** | Combined review is governed but operated recovery and browser evidence block certification; CAS/rule configuration and real cut-over proof remain. |
| Master Data | 1–7, 10–15, 17–26 | **4–7, 10–11, 14–15, 17–26** | Supplier bank details and import navigation exist locally; some extension masters lack UI and attachment/correction/operational proof remains incomplete. |
| Sales & Receivables | 1–26 | **3–26** | Product scope and architecture exist; complete source chain, returns, conversion, approvals, attachments, reconciliations, certification and operations do not. |
| Purchasing & Payables | 1–26 | **3–26** | Receiving, exact quantity matching, ordered correction and exact-cost Purchase Return are closed locally; price variance, supplier-debit integration and complete downstream evidence remain open. |
| Inventory | 1–9, 11–26 | **3–9, 11–26** | Valuation/control reconciles locally; the operational workflow remains partial, Inventory Accounting is dormant, and no module certification exists. |
| Banking & Treasury | 1–26 | **2–26** | Product scope is named, but ownership details, canonical data and every workflow/completion gate remain open. Tax applies to withholding-capable disbursement where used. |
| Fixed Assets | 1–26 | **2–26** | No policy master or canonical asset lifecycle; all completion evidence remains open. |
| Accounting | 1–9, 11–26 | **3–9, 11–26** | Working ledger core is insufficient for schedules, close, all-consumer posting, reconciliation and operations. |
| Compliance | 1–26 | **2–26** | Tax Engine architecture is absent and persisted statutory workflows remain deferred. |
| Reports | 1–2, 5–6, 9, 11–14, 17–26 | **5–6, 9, 11–14, 17–26** | Scope/architecture exist; reconciliations, drill/export contracts, source backing across all reports and operating proof remain open. |
| Administration & Security | 1–7, 12–15, 17–26 | **2–7, 12–15, 17–26** | PAD-003 and four guarded local screens establish a partial workflow; hosted invite, browser/UAT, access review, support and certification evidence remain absent. |
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
VAT / Percentage Tax / Books          [PARTIAL; governed Tax Engine path implemented]

CURRENT STOP: the whole source chain, correction path, tax effect and report
drill have not been proven together as one canonical workflow.
```

## 9.5.3 Purchasing to Financial Statements

```text
Supplier                              [WORKING]
  ↓
Purchase Order                        [WORKING in bounded local scope]
  ↓
Receiving Report                      [WORKING in bounded local scope]
  ↓                                   [DR Inventory / CR Purchase Clearing]
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
Input VAT / EWT / Books               [PARTIAL; governed Tax Engine path implemented]

CURRENT STOP: price-variance policy, supplier-debit integration, AP
reconciliation and the complete source-to-books proof. Exact quantity matching,
ordered receipt correction and Purchase Return inventory/AP posting are proven
locally.
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
Inventory Valuation & Reconciliation  [NOT AN IA-5/ECC CONSUMER]
```

No current business workflow consumes the certified dormant foundation. The
production inventory-costing authority is separate: it now proves Weighted
Average, FIFO and Specific Identification against stock, cost layers,
allocations and the GL without writing an IA-5/ECC event. WP-5 must not be
implemented until its Engineering Amendment closes WP5-AG-001…003 and a later
gate explicitly authorises it.

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

**Central Tax Engine:** implemented at M5 on 2026-08-03. PAD-001 settled it as
Accounting-owned and exactly one calculator; tax calculation is no longer
distributed across the save layer. Tax reference masters, the tax ledger and the
Compliance surfaces are unchanged. Percentage tax remains uncalculated, and the
filing artifacts remain unbuilt.

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
| Master Data | Master Data; govern reusable business entities | Permissions, Audit, Approval, COA | Setup | Parties/items/warehouses/accounts consumed by all modules | M7 / combined scope Blocked | Operated recovery/browser evidence plus unsurfaced extension masters | Validate supplier-bank/import browser paths; source-back remaining masters |
| Sales & Receivables | Sales; revenue and collection cycle | Posting, COA, Dimension, AR, Payment, Approval, Correction, Reporting; Tax absent | Setup, Master Data, Inventory availability | AR ledger, sales registers, VAT/PT/CWT/books, GL/FS | M4 / In Progress | Full chain/source/correction/reconciliation | Select canonical Sales flow and prove §9.4 |
| Purchasing & Payables | Purchasing; procurement, receipt, liability and payment | Posting, COA, Dimension, AP, Payment, Approval, Correction, Reporting; Tax absent | Setup, Master Data | AP ledger, purchase registers, input VAT/EWT/books, Inventory, GL/FS | M4 / In Progress | Price-variance policy, supplier-debit integration and complete Product-DoD proof | Prove the remaining canonical Purchase controls without duplicating matching/costing authorities |
| Inventory | Inventory Operations; quantity, custody and value | Posting, Dimension, production Inventory Costing, Reporting; IA-5/ECC separate and dormant | Items/warehouses; Sales/Purchasing sources | Stock ledger, valuation, COGS, inventory control | M4 / In Progress | Broad Product-DoD, browser/hosted operation and certification | Preserve all three proven production costing methods and keep separate IA-5/ECC frozen unless economic replay is authorised |
| Banking & Treasury | Treasury; cash custody and bank reconciliation | Payment, Posting, Period, Correction, Reporting; tax on applicable disbursements | Bank accounts, Sales receipts, Purchasing payments | Bank position, check register, cash books, bank/GL reconciliation | M3 / Not Started | Empty canonical data; PAD-004 | Product Architecture Decision then module architecture/evidence |
| Fixed Assets | Fixed Assets; capitalise, depreciate and dispose | Posting, Dimension, Period, Correction, Reporting; book/tax | Suppliers, COA, dimensions | Asset register, depreciation, disposal, FS/cash flow | M3 / Not Started | No policy master or canonical lifecycle | Define depreciation profiles and source chain before implementation |
| Accounting | Accounting; own GL, periods and close | Posting/Kernel, COA, Dimension, Period, Correction, Reporting | Every posting module | GL, TB, control reconciliations, FS source | M4 / Core In Progress; Schedules Not Started | All-consumer invariants, schedules, close | Prove canonical Sales/Purchase flows; then close/schedules |
| Compliance | Compliance; review, file and prove PH obligations | Missing Tax Engine; Number Series, Audit, Reporting, Posting boundary | Sales, Purchasing, Accounting, tax setup | Returns, certificates, SLS/SLP/RELIEF, books, CAS evidence | M4 / Blocked | PAD-001 and deferred artifacts | Product Architecture Decision for Tax Engine, then governed design |
| Reports | Reporting; financial and cross-domain decision support | Reporting/Reconciliation, COA, Dimension | Accounting and all source modules | FS, management reports, audit support | M4 / In Progress | Nine reconciliations; weak dimensional/FS-registry adoption | Rebuild on certified sources and execute reconciliation pack |
| Administration & Security | Product/Security; administer access | Certified Permissions/Audit, Approval | PAD-003 decided restricted in-product | User/access review and support operations | M4 / In Progress | Hosted invite, browser/UAT and operating access review | Validate the implemented local boundary before certification |

---

# 9.7 Execution Order and Outcome Dependencies

**This section carries no phase numbers, deliberately.** Numbered phases, the
delivery sequence, the target timeline and the pilot roadmap are owned by
`PXL_DELIVERY_PLAN.md` and appear nowhere else. From 2026-08-01 to 2026-08-02
this document also numbered its phases, which produced two incompatible meanings
for "Phase 4" in two active documents. That ambiguity is removed here.

What this section owns: **why** the order is what it is, and what depends on
what. It describes outcomes, never dates and never sequence numbers. Where an
outcome is scheduled, it cites the Delivery Plan phase that ships it rather than
defining one.

An outcome is complete when it is true for a real company, proven by a fresh-data
end-to-end test in the style of `112` — never against the demo seed.

**Status legend.** ✅ Working · 🟡 Partial · ⚪ Skeleton/UI only · 🔴 Not started
· ⏸ Deferred by decision.

## 9.7.0 Where every module and engine completes

Every canonical module and engine appears exactly once, against the outcome that
completes it. A component may contribute to earlier outcomes; this records where
it finishes. The right-hand column cites the **Delivery Plan** phase that ships
it — a reference to that document's numbering, not a second scheme.

| Module | Status | Completing outcome | Shipped by (Delivery Plan) |
| --- | --- | --- | --- |
| Dashboard | 🟡 Partial | Reporting and Administration | Phase 6 |
| Setup | ✅ Working | Foundation | predates this plan; complete |
| Master Data | ✅ Working | Foundation | predates this plan; complete |
| Sales & Receivables | 🟡 Partial | **Customer-to-Cash** | Phase 5 |
| Purchasing & Payables | 🟡 Partial | **Procure-to-Pay** | Phase 5 |
| Inventory | 🟡 Partial | Procure-to-Pay (receipt half already closed) | Phase 1 / Phase 5 |
| Banking & Treasury | ⚪ Skeleton | Asset and Treasury Management | Check Voucher Phase 5.8 (Cash Disbursements Book); remainder ⏸ v2 |
| Fixed Assets | ⏸ Deferred | Asset and Treasury Management | ⏸ v2 (Phase 8) |
| Accounting | ✅ Core working | **Period Close** | Phase 5 |
| Compliance | 🟡 Partial | **Tax Engine and Compliance** | Calculator Phase 4; filing artifacts Phase 5.8 |
| Reports | 🟡 Partial | Period Close (statements), Reporting and Administration (management) | Phase 5 / Phase 6 |
| Administration & Security | 🟡 Partial | Reporting and Administration | Phase 6 |

| Engine | Status | Completing outcome | Shipped by (Delivery Plan) |
| --- | --- | --- | --- |
| Accounting Kernel | ✅ Enforced | Foundation | done |
| Permissions / RLS | ✅ Certified | Foundation | done |
| Audit & Immutability | ✅ Certified | Foundation | done |
| Number Series | ✅ Certified | Foundation | done |
| Dimensions | ✅ Certified | Foundation | done |
| Chart of Accounts | 🟡 all-consumer resolver adoption | **Period Close** | Phase 5 |
| Posting Engine | 🟡 15 of 24 entry points exercised | Every transactional outcome | Phases 4–6 |
| AR Engine | 🟡 Partial | Customer-to-Cash | Phase 5 |
| AP Engine | 🟡 Partial | Procure-to-Pay | Phase 5 |
| Payment & Application | 🟡 Partial | Customer-to-Cash and Procure-to-Pay | Phase 5 |
| Document Conversion | 🔴 Zero functions | **Customer-to-Cash** | Phase 5 |
| Period Lock & Closing | 🟡 Governed period/quarter/year close and reopen shipped 2026-08-03; never operated over real books | Period Close | Phase 5 |
| Reversal, Void & Correction | 🟡 Partial | Period Close | Phase 5 |
| Reporting & Reconciliation | 🟡 3 of 9 reconciliations, all at 0.00; comparatives and basic notes shipped 2026-08-03 | Period Close | Phase 5 |
| Tax Engine | 🟡 One calculator (PAD-001, 2026-08-03) covering VAT, **percentage tax** (2026-08-04) and EWT/CWT; not certified | **Tax Engine and Compliance** | Phase 4 (calculator only) |
| Inventory Accounting (IA-5/ECC) | ⏸ Frozen, 21 empty tables, zero consumers | **Inventory Accounting — not scheduled** | none |
| Approval Engine | ⚪ Defined, never executed | Reporting and Administration | Phase 6 |
| Attachment & Traceability | 🟡 Trace works, attachments absent | Reporting and Administration | Phase 6 |
| Currency | ⏸ PHP-only | Post-v1 | none |
| Backup & Recovery | ✅ Tooling; not operated | Pilot Readiness | Phase 2 |

## 9.7.1 Dependency order, and why

The order is forced by dependency, not preference. Each arrow is a real
constraint, not a convention.

```text
  Foundation
      │  a ledger that cannot be corrupted must exist before anything posts into it
      │
      ├──────────────► Tax calculator ────────────┐   no Period Close dependency:
      │                (one authority for VAT,    │   it runs at document-save time
      │                 PT, EWT, FWT)             │
      │                                           ▼
      ├──────────────► Customer-to-Cash ──┐   (flows are worth more once tax is
      │                                    │    computed in one place)
      │                                    ├──► Period Close ──► Filing artifacts
      └──────────────► Procure-to-Pay ────┘         │            (returns, working
                                                    │             papers, 2307,
                                                    │             SLS/SLP, CDB)
                              Asset and Treasury ◄──┘                    │
                              (deferred; needs Period Close semantics)   │
                                                                         ▼
                              Reporting and Administration ──► Pilot Readiness
                                                                         │
                                                                         ▼
                                                             Production Readiness
```

**Foundation before everything.** A ledger that can be corrupted makes every
downstream proof worthless. This is why the sealed doorway, RLS and immutability
came first and are the only certified parts of the product.

**Customer-to-Cash and Procure-to-Pay are independent of each other** and can run
in parallel. Both depend only on Foundation. Procure-to-Pay is further along —
it has a fresh-data end-to-end proof (`112`) and Customer-to-Cash does not.

**Period Close depends on both.** A close is meaningless until the subledgers
that feed it are correct; reconciling AR and AP to their control accounts
requires those flows to be trustworthy first.

**Tax and Compliance splits across the dependency line, and this is the single
most important edge in the graph to get right.** The two halves do not share a
dependency:

- The **tax calculator** depends only on Foundation. It runs at document-save
  time, before anything is posted or closed, so it can and should be built early
  — it is the fix for seven independent VAT implementations, and every flow proof
  afterwards is worth more once tax is computed in one place.
- The **filing artifacts** depend on Period Close. A return is generated from
  posted, *closed* data; building one over an unclosed period produces filings
  that change after submission.

Reversing this was a real error in the 2026-08-01 documents, which put all of
Tax before the flows. Corrected 2026-08-02.

**Asset and Treasury Management depends on Period Close semantics** — depreciation
and bank reconciliation are period-bound activities. Deferred to v2 regardless,
so this dependency is currently inert.

**Inventory Accounting (IA-5/ECC) sits outside the chain entirely.** It is
frozen, has 21 empty tables and zero consumers. Nothing above depends on it, and
inventory reconciles to its control account at ₱0.00 without it. It is listed
here only so its absence from the sequence is explicit rather than accidental.
Resume only if costing replay becomes a real requirement.

**Pilot Readiness depends on everything above** plus operated recoverability,
hosted parity and browser evidence.

## 9.7.2 Foundation · ✅ SUBSTANTIALLY COMPLETE

- **Outcome:** A company can be stood up, and the ledger cannot be corrupted by
  any route.
- **Owns:** Setup, Master Data · Accounting Kernel, Permissions/RLS, Audit &
  Immutability, Number Series, Dimensions.
- **Evidence:** 208 of 208 tables RLS-enabled with 501 policies and **zero tables
  without a policy** (re-measured 2026-08-05; the invariant, not the count, is
  what was certified); 110 tables carry guard/immutability triggers; kernel origin
  triggers on both ledger tables, and enforcement **survives a restore into a
  fresh database**; 264 number series; 215 accounts; trial balance ₱0.00 in all
  five companies.
- **Carried forward:** `user_company_branch_scopes` and `sys_feature_enablement`
  empty → Reporting and Administration. Period close is no longer carried: the
  retained-earnings roll shipped 2026-08-03.

## 9.7.3 Customer-to-Cash · 🟡 IN PROGRESS

- **Outcome:** A company sells, invoices, collects, and receivables tie to the AR
  control account with correct tax and cost of sales.
- **Depends on:** Foundation.
- **Already true:** `fn_post_sales_invoice` posts AR, revenue, output VAT **and**
  DR COGS / CR inventory through the shared Weighted Average, FIFO or Specific
  Identification authority, with insufficient-stock admission and exact
  historical reversal (tests `054`, `135`–`137`; canonical COGS
  debits equal inventory credits in all three trading companies). Official
  Receipt and Credit Memo post. AR ageing and customer ledger read posted data.
- **Closed 2026-08-03:** Cash Sale relieves inventory and posts COGS with
  per-line business and withholding tax (test `119`); Delivery Receipt relieves
  stock into Goods Delivered Not Invoiced and the invoice clears it instead of
  relieving twice; Customer Return puts stock and cost back (test `120`). Both
  are fresh-data proofs, not seed-backed.
- **Blocking the outcome:** **zero general document-conversion functions** (the
  delivery-to-invoice link is the only one, and it is deliberately the only
  supported billing path); no AR-to-control reconciliation guard; and no
  Quotation → Sales Order → Sales Invoice fresh-data proof.

## 9.7.4 Procure-to-Pay · 🟡 IN PROGRESS

- **Outcome:** A company buys, receives, bills, pays, and payables and inventory
  both tie to their control accounts.
- **Depends on:** Foundation.
- **Already true:** Fresh-data test `112` proves PO → RR → Bill from first
  principles. Receiving posts DR inventory control / CR purchase clearing, and
  **inventory ties to control at ₱0.00 in every stock-holding company** (guard
  `111`). Payment Voucher carries verified supplier bank accounts and immutable
  payee snapshots.
- **Closed 2026-08-08:** exact PO-line receipt and receipt-linked bill quantity
  admission; ordered Receiving Report correction for all three costing methods;
  and exact receipt-layer Purchase Return inventory/AP posting.
- **Blocking the outcome:** price-variance/account-determination policy,
  supplier-debit integration, no AP-to-control guard, and broad Product-DoD
  proof.

## 9.7.5 Period Close · 🟡 CLOSE AND STATEMENTS WORK, NEVER OPERATED

- **Outcome:** A month closes, cannot be reopened silently, and produces
  financial statements from posted data.
- **Depends on:** Customer-to-Cash and Procure-to-Pay.
- **Already true:** trial balance out of balance by **₱0.00 in all five
  companies**; 60 fiscal periods; **period locking against posting works**;
  23 reporting views; reversal and void paths post and are tested.
- **Closed 2026-08-03:** all four financial statements are produced from governed
  `fs_structure` / `account_fs_map` configuration through one reporting entry
  point, with the position balancing and the cash flow tying to cash movement
  (test `121`). Presentation is a data change, not a release.
- **Closed 2026-08-03:** the close itself. Period, quarter and year-end close
  commit, retained earnings rolls forward automatically into the next fiscal
  year, and reopening counter-posts through the kernel (test `122`). The
  statements gained a comparative period and basic notes the same day (test
  `123`), which is also when a defect was found and fixed: a closed year's income
  statement had read as all zeroes and its operating cash flow had been
  reclassified as financing.
- **Blocking the outcome:** eight of nine critical reconciliations remain
  unevidenced, and the close has never been operated over real books.
- **Deliberately not a pilot blocker:** **audited reopening over real books** is
  unproven and is **not** scheduled before the pilot. A pilot is a
  one-quarter parallel run (Delivery Plan Phase 7), which needs monthly and
  quarterly close, not a year-end roll. This was stated when year-end close did
  not exist; it now does, and the statement stands for a different reason —
  the mechanism is built and tested but has never run over a real company's
  books, so operating it is pilot work rather than build work.

## 9.7.6 Tax Engine and Compliance · 🟡 GOVERNED PIPELINE; PILOT PROOF OPEN

- **Outcome:** A company files correct BIR returns generated from the same posted
  data as its financial statements.
- **Depends on:** split. The **calculator** depends only on Foundation and ships
  first (Delivery Plan Phase 4). The **filing artifacts** depend on Period Close
  and ship after the statements (Delivery Plan Phase 5.8). Treating these as one
  unit is what produced the 2026-08-01 sequencing error.
- **Already true:** VAT, percentage tax and withholding reconcile to the GL at
  zero variance. Six outputs—2550Q, 2551Q, 1601EQ, SLSP, SAWT and QAP—use one
  locked path: Posted Transactions → Tax Engine → Tax Ledger → Reconciliation →
  Working Paper → Filing Artifact → Export → Filed Record. The Filing Artifact
  is the system of record; current-product legacy working-paper screens/tables
  were retired.
- **Blocking the outcome:** nothing has ever been filed by an accountant from
  PXL; hosted and browser/UAT evidence is absent. The SLSP screen moved onto the
  quarterly artifact on 2026-08-05 and is no longer a blocker. FWT and Income Tax
  are excluded future extensions and are not blockers.

## 9.7.7 Inventory Accounting · ⏸ FROZEN, NOT SCHEDULED

- **Outcome:** Inventory cost can be replayed under a governed economic
  chronology.
- **Depends on:** nothing in the chain depends on **it**, which is the point.
- **Measured state:** 21 `inventory_*` ECC tables, **all empty, zero consumers**.
  WP-1…WP-4 certified and dormant; WP-5…WP-9 and IA-6 unauthorised.
- **Why it is not scheduled:** inventory reconciles to its control account at
  ₱0.00 without it. The programme once consumed the capacity that should have
  shipped product. Resume only when a real costing-replay requirement exists,
  and only under a governance decision — not as foundation work.

## 9.7.8 Asset and Treasury Management · ⏸ NEXT AFTER CURRENT COMPLIANCE

- **Outcome:** Assets depreciate and treasury instruments settle into the ledger.
- **Depends on:** Period Close semantics.
- **Measured state:** **all six fixed-asset tables empty**; in Banking only
  `bank_accounts` holds data, while `check_vouchers`, `fund_transfers`,
  `bank_reconciliations`, `petty_cash_vouchers` and `bank_adjustments` are all
  empty and their posting functions have never produced a journal.
- **Scope ruling:** Banking & Treasury is the highest-priority future capability;
  Fixed Assets is second. Both are v2, with two exceptions — Check Voucher (needed by the Cash
  Disbursements Book) and a minimal straight-line depreciation run **only if the
  pilot client holds assets**. PAD-004 must be decided before any bank
  reconciliation work.

## 9.7.9 Reporting and Administration · 🟡 PARTIAL

- **Outcome:** A stranger can administer the system and read management reports
  without help.
- **Depends on:** Period Close for its data.
- **Already true:** four administration routes, an `admin-invite` Edge Function,
  contract test `115`, 25 memberships; the accounting trace is complete and
  routed; the dimensional report is certified.
- **Blocking the outcome:** approval routing has **never executed**
  (`approval_requests` and `approval_instances` both zero) and **no notification
  model exists anywhere in the product** (PAD-013); `cas_attachment_register` is
  empty so there is no file lifecycle (PAD-008); branch scoping is unexercised;
  and 26 deferred routes plus 17 page-less navigation labels still present as
  capability (PAD-012, PAD-014).

## 9.7.10 Pilot Readiness · 🔴 LARGELY NOT STARTED

- **Outcome:** A named client can run real books in a controlled pilot.
- **Depends on:** every outcome above.
- **Already true:** the backup service is built, scheduled and proven — the
  replicated copy restored independently at 93 tables / 0 mismatches / 6s.
- **Blocking the outcome:** no bucket and no escrowed passphrase, and the
  schedule has never fired; 68 migrations undeployed and the invite function
  never deployed; **no automated browser lane**; no
  monitoring and no daily reconciliation alert.

## 9.7.11 Production Readiness · 🔴 NOT STARTED

- **Outcome:** A quarter closes correctly on PXL and the client's accountant
  signs the financial statements.
- **Depends on:** a surviving pilot.
- **Requires:** one full quarter parallel run; **year-end close and audited
  reopening**; point-in-time recovery for the 1-hour production RPO; CAS
  accreditation; support and user acceptance proven. Until all of it holds, the
  words *Certified*, *Complete* and *Production Ready* remain reserved.

## 9.7.12 Mapping from the retired Phase A–L plan

The 2026-08-01 edition of this document sequenced twelve work packages. They are
re-homed under the outcome each serves; no work is discarded.

| Retired work package | Now |
| --- | --- |
| A — Architecture and Planning Consolidation | Complete; absorbed into governance |
| B — Inventory Engineering Frontier (WP-5) | **Removed from the sequence.** See §9.7.7 |
| C — Functional Accounting Core Proof | Foundation and Period Close |
| D — Tax and Compliance Architecture | Tax Engine and Compliance |
| E — Sales & Receivables Completion | Customer-to-Cash |
| F — Purchasing & Payables Completion | Procure-to-Pay |
| G — Inventory Operational and Accounting Integration | Procure-to-Pay |
| H — Banking & Treasury | Asset and Treasury Management |
| I — Fixed Assets | Asset and Treasury Management |
| J — Financial Statements and Management Reporting | Period Close and Reporting and Administration |
| K — Administration, Backup, Security, Operational Readiness | Reporting and Administration, Pilot Readiness |
| L — Pilot and Production Readiness | Pilot Readiness and Production Readiness |

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
Finish Phase 2: choose PAD-007 and operate scheduled offsite recovery
  ↓
Validate the local Phase 3 onboarding build in an explicitly authorised target
  ↓
Choose one Sales + one Purchasing canonical scenario
  ↓
Prove source fields, lifecycle and correction
  ↓
Prove Posting → AR/AP → GL → TB → FS
  ↓
Decide and govern the Tax Engine boundary
  ↓
Prove VAT/WHT/books and source-to-report trace
  ↓
Close module/engine evidence gates
  ↓
Hosted parity + operated restore + real cut-over + browser/UAT
```

## 9.8.3 What already exists

- Strong core source transactions, the Posting doorway and fully enforced Kernel.
- AR/AP as-of functions, GL, Trial Balance and financial-statement surfaces.
- Tax detail/ledger and substantial BIR books/read/report surfaces.
- Certified Permissions, Audit, Number Series and Dimension engines.
- Source-to-journal trace RPCs and audit history.
- Receiving-to-journal and Inventory-to-control reconciliation.
- A local Phase 3 onboarding build: governed opening balances, verified supplier
  payee accounts, restricted administration and navigable master-data import.

## 9.8.4 What must be completed

- Whole-flow source qualification, lifecycle/correction and numeric
  reconciliation for one Sales and one Purchasing scenario.
- Tax Engine ownership/architecture and one authoritative calculation contract.
- The applicable module/engine gates, hosted parity, operated backup/restore,
  a real opening cut-over, browser evidence and user acceptance.

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
- Tax Engine scope beyond PAD-001's decided boundary (VAT and ATC withholding);
  percentage tax needs its own document consumer and a posting change.
- Multi-currency behavior before PAD-005.
- Bank Reconciliation before PAD-004.
- UI/navigation redesign under an accounting implementation mission.

## 9.8.7 Over-engineering warning

The IA-5/ECC programme solves a real, high-severity determinism problem, but it is
frozen with no consumer. **Resuming WP-5…WP-9 because the programme exists would
be over-engineering** while operated recovery, Sales/Purchasing source proof, Tax
authority and Phase 3 operational acceptance remain open. Any later package must
receive fresh authority and demonstrate that it advances the target milestone.

## 9.8.8 More urgent than additional foundation

Operated/offsite recovery, Phase 3 target-environment acceptance, canonical
Sales/Purchase flow proof and Tax Engine authority yield more direct product value
than continuing dormant foundation work without an activation path.

---

# 9.9 Risk Register

| ID | Risk | Severity | Likelihood | Evidence | Consequence | Mitigation | Owner | Resolve by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PR-01 | Scope size exceeds delivery capacity | High | High | 11 modules, 19 engine scopes, 208 tables, large visible surface | Endless partial product | Enforce PAD-015 scope; use DoD and dependency gates | Product Owner | Customer-to-Cash entry |
| PR-02 | Product architecture drift | High | Medium | Historical blueprint, routes and certification boundaries diverged | Contradictory work and rework | Product Architecture is canonical; amendment required for scope change | Product Architect | Continuous; first review at Customer-to-Cash |
| PR-03 | Documentation proliferation | High | High | Many active specifications and prior assumed missing review | Readers choose wrong authority | One constitution, one roadmap, one dashboard; index routes only | Governance Lead | Done — governance consolidated |
| PR-04 | Certification detaches from product value | High | High | 4 work packages certified while no module is certified | Foundation throughput masks unusable ERP | Value checkpoint after WP-5; require workflow outcome per programme | Product Owner | Inventory Accounting freeze (standing) |
| PR-05 | UI ahead of runtime | High | High | 26 deferred routes; 17 page-less nav labels | Users mistake shells for features | Governed state labels; PAD-012; pilot UX check | Product + UX | Before Pilot Readiness |
| PR-06 | Backend ahead of usable workflows | Medium | High | Seven backend-only clusters; two unlisted trace routes | Valuable work unused; duplicate rebuilds | Adoption backlog tied to owning module and DoD | Module Owners | Relevant module phase |
| PR-07 | Excessive work-package granularity | High | Medium | Repeated IA-5 amendments/gates around dormant structures | Governance cost exceeds product value | Package only independent rollback/risk units; merge inseparable work; value gate | Architecture Owner | Inventory Accounting freeze (standing) |
| PR-08 | No canonical end-to-end workflow | Critical | High | 0/6 portfolio reference flows meet DoD | Cannot demonstrate ERP correctness | prove the Customer-to-Cash and Procure-to-Pay outcomes first | CPA + Product | Customer-to-Cash and Procure-to-Pay exit |
| PR-09 | ~~Tax Engine authority absent~~ **CLOSED 2026-08-03; downstream artifacts closed 2026-08-04** | Critical | Low | One calculator; percentage tax and six Filing Artifacts guarded through tests `090`, `117`–`129` | Residual: SLSP screen/evidence path and operational filing proof | Finish Backlog 8c/8e(ii); preserve the locked pipeline | Product + CPA | Tax Engine and Compliance exit |
| PR-10 | Inventory complexity consumes roadmap | Critical | High | C-01, WP-5 rejected, legacy variance, future IA-6 | Delayed product with continued valuation risk | Keep Inventory Accounting frozen; operational/value checkpoint; resume only after a real costing-replay requirement | Inventory Owner | Inventory Accounting freeze; Procure-to-Pay |
| PR-11 | Hosted parity gap | Critical | High | 68 local migrations not hosted | Local evidence does not describe hosted product | Explicit authorised migration/rehearsal plan; no hosted claim until proven | Operations | Pilot Readiness exit |
| PR-12 | Backup/restore not operated | Critical | High | Local drill/runbook/RPO/RTO exist; no schedule, offsite destination or hosted/PITR proof | Permanent loss; no certification/pilot | Decide PAD-007 and operate the demonstrated drill offsite | Operations + Security | Before Setup certification / Pilot Readiness |
| PR-13 | Dirty/uncommitted repository obscures provenance | High | High | Working tree contains many modified/untracked files | Change attribution and rollback risk | Preserve tree; mission-start/end manifests; intentional commits only by owner | Repository Owner | Before implementation branch/release |
| PR-14 | AI-generated implementation lacks accountable review | High | High | Repository work is heavily AI-driven; human review evidence limited | Subtle accounting/security defects | CPA + engineer review gates; executed evidence; small bounded changes | Product Owner | Every authorisation/certification |
| PR-15 | Limited human engineering review | High | Medium | Independent reviews are mainly repository missions | Architectural blind spots persist | Assign named human reviewers for accounting, security and operations | Product Owner | Customer-to-Cash entry |
| PR-16 | Security/tenant regression | Critical | Medium | Prior critical reporting leak and immutability bypass found during certification | Cross-company disclosure or altered history | Preserve certified guards; cross-tenant browser/API tests; hosted security proof | Security Owner | Every release; Pilot Readiness |
| PR-17 | Philippine compliance error | Critical | High | Governed local pipeline exists, but no accountant-operated filing, hosted proof or browser/UAT evidence | Penalties, invalid books/returns | Preserve the Filing Artifact system of record; CPA review and reconciled pilot filing scenarios | CPA Owner | Tax Engine and Compliance; Procure-to-Pay; before pilot |
| PR-18 | Support/operations unavailable | High | High | No production operations programme completed | Users cannot recover or get help | Runbooks, monitoring, incident/support ownership and service boundaries | Operations Owner | Pilot Readiness exit |
| PR-19 | Performance fails at realistic volume | High | Medium | High-volume demo exists but production-volume certification is incomplete | Slow posting/reports, adoption failure | Targets, profiling, concurrency/load evidence on critical paths | Engineering Owner | Procure-to-Pay, Period Close, Pilot Readiness |
| PR-20 | Opening cut-over unproven operationally | High | Medium | PAD-002 workflow passes fresh local proof; no real-company/hosted/browser/UAT rehearsal | Onboarding can still fail operationally | Rehearse one real cut-over and reconcile every control in the target environment | Product + CPA | Before pilot |
| PR-21 | Receiving accounting asymmetry | Closed locally | Low | PXL-AUD-073 posts inventory/purchase clearing and canonical inventory reconciles at zero | Preserve regression | Keep guards 111/112 and complete three-way/sales-side controls separately | Purchasing + Inventory + CPA | Continuous |
| PR-22 | Maturity metrics are gamed | High | Medium | Prior 42% combined modules/engines/absences | False confidence and bad sequencing | Exact denominators only; methodology in §9.10 | Governance Lead | Continuous |
| PR-23 | Direct-write exceptions breach architecture | High | Medium | `bank_recon_items`, `book_tax_reconciliation` excluded from P5.0 | Unsealed accounting effects | Resolve in PAD-004/Tax architecture; keep explicit until closed | Accounting Architect | Phases D/H |
| PR-24 | Historical chronology is rewritten | High | Low | Many issued audits/specs with later corrections | Loss of audit provenance | Prospective correction and supersession only | Governance Lead | Every documentation mission |

---

# 9.10 Executive Progress Dashboard

**Removed on 2026-08-02, deliberately.** This section restated module maturity,
engine maturity and portfolio metrics that are owned by `AI/AI_STATE.md` and the
Product Architecture. Three copies of the same numbers guaranteed that at least
one was wrong at any moment, and that is precisely what happened.

There is exactly one status authority: **`AI/AI_STATE.md`**.

If an executive view is needed, generate it from the repository at the time it is
asked for — exercised posting entry points, evidenced reconciliations, passing
test counts — rather than maintaining a copy by hand.

# 9.11 Repository Health Assessment

| Area | Evidence-based assessment |
| --- | --- |
| Product vision | Strong, differentiated and valuable: accounting-first PH compliance for multi-company businesses. It is broader than current delivery capacity and needs a pilot scope. |
| Accounting architecture | The strongest part of PXL. The sealed posting doorway and immutable, traceable ledger are excellent. Receiving, all outbound inventory entry points, exact quantity matching, all three inventory costing methods, financial statement presentation, period close and comparatives now work locally; price-variance policy and broad Product-DoD proof remain open. |
| Engineering architecture | Strong database controls and evidence discipline. Complexity is high, local/hosted states diverge, and dormant architecture risks outrunning product workflows. |
| Repository structure | Generally governed and navigable, but the dirty tree, large active-doc set and prior missing/assumed review create provenance risk. |
| Code maturity | Substantial local implementation with many guarded RPCs and tests. Maturity is uneven: strong transaction cores coexist with empty module scaffolds. |
| Module maturity | No module is M8 or M9; no transactional module is M5. Setup/Master are closest to certification. |
| Certification maturity | Engine certification is meaningful and has found critical defects. Module certification has produced no certified module; work-package throughput must not become the goal. |
| Documentation quality | Deep and evidence-rich, but historically fragmented and repetitive. This constitution/roadmap/index model should reduce reconstruction work. |
| Test quality | Strong pgTAP breadth (128 files / 3,079 assertions), negative controls and governance guards, plus 69 frontend source tests. Test presence is sometimes mistaken for workflow maturity; **there is no automated browser lane**, and restore evidence is mechanised but not operated over real books. |
| UI/runtime alignment | Poor in deferred clusters: 26 deferred routes and 17 page-less labels. Backend/UI adoption gaps also exist. |
| Security | Locally strong in certified RLS/immutability scope. Hosted parity and operational administration remain unproven. |
| Auditability | Strong source/journal/audit foundations and persisted Filing Artifacts; attachment lifecycle and operated filing evidence remain absent. |
| Production readiness | **Not ready.** Hosted parity, operated/offsite recovery, real cut-over/browser/UAT, module certification and support operations are missing. |
| Biggest strength | The database-enforced accounting/security control foundation, especially the single Posting doorway and independently certified engines. |
| Biggest weakness | No fully proven business-to-financial-statements-to-tax workflow, despite a very large surface and foundation programme. |
| Most dangerous assumption | That green tests, closed findings, rendered routes or certified work packages imply a deployable ERP. They do not. |
| Most valuable next investment | Finish the SLSP Filing Artifact migration, then obtain operated recovery/onboarding/pilot evidence. After current compliance work: Banking & Treasury, then Fixed Assets. |
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
4. `docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`
5. this roadmap when planning, sequencing, reporting maturity or selecting work
6. only the exact certification/domain authorities named by the active mission

The Product Architecture is the first product authority. This roadmap is not an
implementation instruction.

---

# 9.13 Selected Next Governed Mission

This roadmap no longer selects current work; `AI/AI_STATE.md` is the sole work
selection and status authority. The dependency rationale is:

1. finish the current-scope compliance architecture by moving the SLSP screen and
   evidence snapshot onto the quarterly Filing Artifact;
2. obtain owner-operated recovery, hosted parity, browser/UAT and real filing
   evidence before any pilot/readiness claim; and
3. after current compliance work, prioritize Banking & Treasury and then Fixed
   Assets. Excluded PAD-015 extensions do not compete for delivery priority.

**Superseded on 2026-08-02.** The previously selected mission was the WP-5
Engineering Amendment and its Authorisation Gate. That programme is **frozen**.
The reasoning that made it next — that deterministic economic order is required
for Inventory-to-GL reconciliation — was wrong: `PXL-AUD-073` reconciled inventory
to its control account at 0.00 variance with no chronology work at all, because
the actual defect was a missing journal entry on goods receipt. Deterministic
same-timestamp ordering is a scale and audit-replay refinement, not a correctness
prerequisite under weighted-average valuation. WP-5…WP-9 and IA-6 remain
unauthorised and must not resume without a demonstrated costing-replay
requirement.

# 9.14 Maintenance and Non-Authority

Update this roadmap when evidence changes a maturity placement, phase dependency,
DoD state, risk, denominator, hosted high-water mark or next governed mission.
Do not use it to rewrite issued certification chronology or silently amend the
Product Architecture.

Creating this roadmap changes no runtime, certification, authorization, product
surface or hosted state. PXL remains Internal QA/demo only.
