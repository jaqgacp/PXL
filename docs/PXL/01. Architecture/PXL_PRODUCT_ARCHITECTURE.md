# PXL Product Architecture

## The Constitutional Blueprint of PXL ERP

**Status:** Active — the canonical product architecture of PXL ERP
**Authority:** Tier 1 Product Architecture. This document defines *what PXL is*.
It does not define how anything is built.
**Owner / Domain:** Architecture
**Applies To:** The whole product — every module, engine, workspace, and report
**Read When:** **FIRST**, before any work that touches modules, menus, scope, roadmap, progress reporting, or architectural naming
**Do Not Read For:** Implementation detail (use the domain specifications), current bounded task (use `AI/AI_STATE.md`), defect status (use `PXL_END_TO_END_AUDIT_FINDINGS.md`), or certification decisions (use `PXL_CERTIFICATION_MATRIX.md`)
**Date:** 2026-08-01
**Evidence base:** Repository state at commit `4aef8b3` (working tree dirty; all pre-existing changes preserved)

---

### How this document relates to everything else

This is the **product** constitution. `00. Governance/PXL_PRINCIPLES.md` is the
**engineering** constitution. They do not compete:

- **PXL_PRINCIPLES.md** says *how PXL must be built* — 27 non-negotiable rules.
- **This document** says *what PXL is* — which modules exist, what each one is
  for, how mature each one is, and what is deliberately not built yet.
- **`PXL_PRODUCT_EXECUTION_ROADMAP.md`** says *how the canonical product is
  sequenced, matured, evidenced, and completed*. It is subordinate to this
  document and cannot add scope or grant implementation authority.

Where this document and the original 2026 product blueprint disagree, **this
document is canonical**, and §8 records every difference and the reason for it.
Where this document and **executed database behaviour** disagree, the executed
behaviour wins and this document is a defect to be corrected — that ordering is
fixed by `PXL_DOCUMENTATION_INDEX.md` §1 and is not modified here.

**A note on placement.** This document was requested at `docs/PXL/00. PXL_PRODUCT_ARCHITECTURE.md`.
It lives in `docs/PXL/01. Architecture/` instead, because two active repository
standards forbid the suggested path: the documentation index reserves the
`docs/PXL/` root for exactly two files (the master index and the findings
register), and a leading `00.` numeric prefix denotes a **folder** in this
repository (`00. Governance/`), never a file. Placing a file named `00. …` beside
the folder `00. Governance/` would create two different meanings for the same
prefix. `01. Architecture/` is the registered home for architecture authority and
is where the schema summary, architecture summary, and permissions blueprint
already live.

---

# 1. Executive Summary

## 1.1 What PXL is

PXL is an **accounting-first, Philippine-compliance-first ERP for multi-company
use.**

It is not an operations tool that happens to keep books. It is a financial system
that happens to have operations attached to it. Every sale, purchase, stock
movement, bank transaction, and asset event exists in PXL for one reason: to
resolve into a balanced, permanent, auditable double-entry journal in the General
Ledger — and from there into financial statements and BIR filings that will
survive an audit.

The target user is a Philippine business that must satisfy the Bureau of Internal
Revenue: VAT or percentage tax, expanded and final withholding, Form 2307 and
2306, SLSP and RELIEF exports, the statutory Books of Accounts, and Computerized
Accounting System (CAS) accreditation. Generic international ERPs fail here
because Philippine taxation is withheld at source, certificate-driven, and
form-specific. PXL treats that as the primary requirement, not a localisation
layer.

## 1.2 Purpose

PXL exists to let a Philippine business:

1. **Run its operations** — quote, order, deliver, invoice, collect, purchase,
   receive, pay, hold stock, manage cash and assets.
2. **Keep perfect books automatically** — every operational document produces its
   own accounting entry, with no parallel bookkeeping and no manual journal
   translation step.
3. **File correctly and on time** — VAT, percentage tax, withholding, and income
   tax outputs generated from the same posted data the financial statements use.
4. **Prove everything** — from any figure on any statement, reach the source
   document, the user, and the timestamp, with no gaps and no ability to have
   quietly altered anything along the way.

## 1.3 Design philosophy

Six commitments shape every architectural decision in PXL. They are stated here
in business terms; their engineering form is the 27 principles.

**1 — Accounting is the centre, not a consequence.**
There is exactly one doorway into the General Ledger, and every transaction must
walk through it. Nothing writes to the ledger by any other route. This is not a
convention — it is enforced, and the enforcement is proven.

**2 — The ledger is immutable.**
Once posted, a document is never edited and never deleted. Corrections happen by
reversal, void, credit memo, or debit memo, so the original entry and its
correction both remain visible forever. This is a BIR requirement and an audit
requirement, and PXL treats it as physics rather than policy.

**3 — Compliance is native, not bolted on.**
Withholding, VAT treatment, ATC codes, certificate tracking, and the statutory
books are part of the transaction model itself. A company's tax profile decides
which taxes apply, which forms are available, and which dashboards appear.

**4 — Configuration over customisation.**
A business that starts as a non-VAT sole proprietorship and grows into a
VAT-registered corporation must not need a developer. Feature enablement, number
series, approval rules, account mapping, and tax applicability are all data.

**5 — Multi-tenant isolation is absolute.**
Company, branch, department, cost centre, project, location, and functional
entity form a real hierarchy. One company cannot see another company's books —
not by convention, not by screen filtering, but at the data layer, and this has
been formally certified.

**6 — Nothing counts until it is proven.**
PXL distinguishes, rigorously and in writing, between *a screen exists*, *data
can be stored*, *the workflow runs*, *the workflow is governed*, and *the workflow
is certified*. A route is not a feature. A table is not a workflow. A test is not
a certification. This document is built entirely on that distinction.

## 1.4 Business scope

**In scope today.** Multi-company setup and master data · sales and receivables ·
purchasing and payables · inventory operations · banking and treasury ·
fixed assets · general accounting and period management · Philippine tax
compliance and BIR books · financial and management reporting.

**In scope, deliberately not built yet.** Multi-currency and FX revaluation ·
budgeting · document conversion automation · statutory return *generation* (the
review and computation surfaces exist; the filing artifacts do not) · inventory
cost replay under a governed economic chronology.

**Explicitly out of current PXL ERP scope.** **Payroll is a future separate
product, not a PXL ERP module.** The `Employees` master in PXL is a *lite* BIR
identifier master used for document attribution and department reporting — it is
not a payroll foundation and must never be counted in PXL ERP progress. Also out
of scope: any AI or assistant integration (none exists in the application).

## 1.5 Overall architecture philosophy

PXL is built as **three layers that must never be confused with each other**, and
most of the confusion in this repository's history has come from mixing them.

```text
   LAYER 1 — MODULES          What a user opens. Business capability.
                              "Sales", "Inventory", "Compliance".
                              Certified through the MODULE certification standard.
        │  uses
        ▼
   LAYER 2 — SHARED ENGINES   Mechanisms every module borrows. Invisible.
                              Posting, Permissions, Numbering, Dimensions, Audit.
                              Certified through the ENGINE certification standard.
        │  writes through
        ▼
   LAYER 3 — ACCOUNTING       The ledger and its guard. One doorway, sealed.
             INFRASTRUCTURE   Never a menu entry. Never a user concept.
```

Three consequences follow, and they are the operating rules of this document:

- **A module is not an engine.** "Sales" is a module. "Posting" is an engine.
  Certifying an engine certifies a mechanism used by many modules; it does not
  certify any module that uses it.
- **A work package is neither.** The Inventory chronology work packages
  (WP-1…WP-4) each certify one bounded, dormant change set. Four certified work
  packages do not add up to a certified engine, and certainly not to a certified
  module.
- **Progress in one layer is not progress in another.** Four certified engines and
  a fully enforced ledger guard coexist with **zero certified modules**. Both
  statements are true; neither implies the other.

### 1.5.1 Canonical product-versus-certification boundary

PXL has **eleven canonical business modules**: Setup; Master Data; Sales &
Receivables; Purchasing & Payables; Inventory; Banking & Treasury; Fixed Assets;
Accounting; Compliance; Reports; and Administration & Security. **Dashboard is
a cross-product Reporting Surface, not a business module.** This corrects the
previous twelve-module classification, which counted Dashboard as a module.

The Production Certification Program also contains **eleven assessment scopes**,
but its boundaries are not the product taxonomy: it combines Setup and Master
Data, and it separates Accounting Schedules from Accounting. Those issued
certification boundaries remain valid for evidence and chronology. They must not
be used to rename or recount the canonical product modules. §10.1 maps the two
views explicitly.

## 1.6 The honest position, in one paragraph

PXL has an unusually strong accounting foundation and an unusually weak claim to
completion. The ledger is sealed and provably single-doorway — and the guard
survives a restore into a fresh database. Multi-tenant isolation (209 of 209
tables, 519 policies, none unprotected), audit immutability, document numbering
and dimensional accounting are formally certified. The trial balance is out of
balance by ₱0.00 in all five companies, inventory ties to its control account,
and VAT and withholding reconcile to the General Ledger at exactly zero variance.

Against that: **no business module is certified**; the Tax Engine now exists as
one calculator (PAD-001, 2026-08-03) but **percentage tax is still calculated
nowhere and nothing has ever been filed**; **`account_fs_map` is empty**, so no
financial-statement presentation exists; **12 of 24 posting entry points have never produced a
journal**; every Banking and Fixed Asset transaction table is empty; and all
twelve compliance working-paper tables are empty, so nothing has ever been filed.
Of 209 tables, **116 have never held a row**. Opening balances, verified supplier
payee accounts and minimum administration exist locally; recoverability is
mechanised and scheduled but not operated over anything real. PXL is suitable for
**internal QA and demonstration only. It is not production-ready and not
pilot-ready.**

---

# 2. Product Architecture

The complete PXL ERP hierarchy as it exists in the repository, with every child
menu expanded. This tree is derived from the shipped navigation, the route table,
the page components, and the governed data-coverage register — not from the
original blueprint.

**Product-state markers.** Every tree item carries exactly one of the governed
product-state labels below. These labels describe the current product surface;
they do not certify the item and do not replace the M0–M9 maturity ladder in §6.

| Marker | Canonical product-state label |
| --- | --- |
| `[C]` | **CURRENT PRODUCT SURFACE** — source-backed today; any certification is stated separately. |
| `[W]` | **CURRENT PRODUCT SURFACE** — source-backed today; not a claim that its whole module is complete. |
| `[G]` | **CURRENT BUT PARTIAL** — governed or substantially working, with material product gaps. |
| `[P]` | **CURRENT BUT PARTIAL** — material portions work; the whole capability does not. |
| `[B]` | **BACKEND FOUNDATION ONLY** — governed structures or functions exist without a complete surface. |
| `[U]` | **UI SKELETON** — a route/page exists over unexercised or governed-empty backing data. |
| `[PL]` | **DEFERRED** — accepted current-product requirement intentionally postponed. |
| `[X]` | **DESIGN ONLY** — named requirement with no implemented product capability. |

**FUTURE ROADMAP**, **OUT OF CURRENT SCOPE**, and **SUPERSEDED** items are
recorded in §§8 and 10.5 rather than presented as current navigation children.

```text
PXL ERP
│
├── Dashboard                                                        [P]
│   ├── Setup completeness monitor                                   [W]
│   ├── Master-data and configuration counts                         [W]
│   ├── BIR deadline monitor (from the Tax Calendar)                 [W]
│   └── Configurable KPI widget grid                                 [PL]
│
├── Setup                                                            [G]
│   ├── Organization                                                   [P]
│   │   ├── Company Setup                                            [W]
│   │   ├── Branch Setup                                             [W]
│   │   ├── Departments & Cost Centers                               [W]
│   │   ├── Compliance Profile                                       [W]
│   │   └── CAS Registrations                                        [X]
│   ├── System Controls                                                [P]
│   │   ├── Number Series                                            [C]
│   │   ├── Feature Enablement                                       [W]
│   │   ├── Approval Workflow                                        [P]
│   │   ├── ATP Monitoring          → see Compliance ▸ ATP Usage Log [P]
│   │   └── Module Feature Settings (inventory, FA, petty cash, bank reconciliation, budget) [PL]
│   ├── Document & Validation                                          [B]
│   │   ├── Status Controls                                          [B]
│   │   ├── Posting Controls                                         [B]
│   │   ├── Void Controls                                            [B]
│   │   ├── Reversal Controls                                        [B]
│   │   ├── Master Data Rules                                        [B]
│   │   ├── Transaction Rules                                        [B]
│   │   ├── Posting Validation Rules                                 [B]
│   │   └── Period Controls                                          [B]
│   ├── Accounting Setup                                                [P]
│   │   ├── Fiscal Years & Calendar                                  [W]
│   │   ├── Chart of Accounts                                        [W]
│   │   ├── GL Posting Configuration                                 [W]
│   │   ├── Currency Setup                                           [P]
│   │   ├── Financial Statement Structure                            [B]
│   │   └── Opening Balances                                         [W]
│   └── Tax Setup                                                       [P]
│       ├── Tax Codes                                                [W]
│       ├── VAT Codes                                                [W]
│       ├── Percentage Tax Codes                                     [W]
│       ├── ATC Codes  (absorbed the former EWT and FWT code masters)[W]
│       ├── BIR Form Configuration                                   [P]
│       └── Tax Calendar                                             [W]
│
├── Master Data                                                      [G]
│   ├── Parties                                                         [P]
│   │   ├── Customers                                                [W]
│   │   ├── Suppliers                                                [W]
│   │   ├── Employees (lite BIR identifier master)                   [W]
│   │   ├── Party Contacts (multi-contact master)                    [B]
│   │   ├── Customer / Supplier Groups                               [B]
│   │   └── Supplier Bank Details                                    [W]
│   ├── Items & Services                                                [P]
│   │   ├── Item Catalog (items, services, non-inventory)            [W]
│   │   ├── Item Categories                                          [W]
│   │   ├── Units of Measure                                         [W]
│   │   └── UoM Conversions · Barcodes · Media                       [B]
│   ├── Inventory Master                                                [P]
│   │   ├── Warehouses                                               [W]
│   │   └── Warehouse Stock Settings                                 [W]
│   ├── Banking                                                         [P]
│   │   └── Bank Accounts                                            [W]
│   └── Shared                                                          [P]
│       └── Payment Terms                                            [W]
│
├── Sales & Receivables                                              [P]
│   ├── Transactions                                                    [P]
│   │   ├── Quotation                                                [P]
│   │   ├── Sales Order                                              [P]
│   │   ├── Delivery Receipt                                         [P]
│   │   ├── Sales Invoice                                            [W]
│   │   ├── Cash Sale                                                [W]
│   │   ├── Official Receipt (customer collection)                   [W]
│   │   ├── Credit Memo                                              [W]
│   │   ├── Debit Memo                                               [U]
│   │   └── Customer Return                                          [P]
│   ├── Receivables                                                     [P]
│   │   ├── AR Aging & Customer Ledger                               [W]
│   │   └── Collection Monitoring                                    [P]
│   ├── Tax Review                                                      [P]
│   │   ├── Output VAT Review                                        [W]
│   │   ├── Percentage Tax Review                                    [W]
│   │   └── 2307 Received Review                                     [P]
│   └── Registers                                                       [P]
│       ├── Sales Registers (invoice · receipt · credit · debit)     [W]
│       └── Summary List of Sales (SLS)                              [W]
│
├── Purchasing & Payables                                            [P]
│   ├── Transactions                                                    [P]
│   │   ├── Purchase Order                                           [W]
│   │   ├── Receiving Report (goods receipt)                         [P]
│   │   ├── Vendor Bill                                              [W]
│   │   ├── Cash Purchase                                            [W]
│   │   ├── Payment Voucher (vendor payment)                         [W]
│   │   ├── Vendor Credit                                            [W]
│   │   ├── Supplier Debit Memo                                      [U]
│   │   └── Purchase Return                                          [U]
│   ├── Payables                                                        [P]
│   │   ├── AP Aging & Supplier Ledger                               [W]
│   │   └── Payment Monitoring                                       [P]
│   ├── Tax Review                                                      [P]
│   │   ├── Input VAT Review                                         [W]
│   │   ├── EWT Summary                                              [W]
│   │   └── 2307 Issued Review                                       [P]
│   └── Registers                                                       [P]
│       ├── Purchase Registers (bill · payment · supplier DM)        [W]
│       └── Summary List of Purchases (SLP)                          [W]
│
├── Inventory                                                        [P]
│   ├── Overview                                                        [P]
│   │   ├── Inventory Dashboard                                      [W]
│   │   ├── Stock Balance                                            [W]
│   │   ├── Inventory Movements                                      [W]
│   │   └── Inventory Valuation                                      [P]
│   ├── Transactions                                                    [P]
│   │   ├── Stock Adjustment                                         [W]
│   │   ├── Stock Transfer                                           [W]
│   │   ├── Physical Count                                           [W]
│   │   └── Goods Issue                                              [U]
│   └── Setup                                                           [P]
│       └── Warehouses            → owned by Master Data             [W]
│
├── Banking & Treasury                                               [U]
│   ├── Petty Cash                                                      [U]
│   │   ├── Petty Cash Fund Setup                                    [U]
│   │   ├── Petty Cash Voucher                                       [U]
│   │   ├── Petty Cash Replenishment                                 [U]
│   │   └── Cash Count Sheet                                         [U]
│   ├── Bank Operations                                                 [U]
│   │   ├── Fund Transfer                                            [U]
│   │   ├── Inter-Branch Transfer                                    [U]
│   │   ├── Bank Adjustment                                          [U]
│   │   ├── Bank Reconciliation                                      [U]
│   │   ├── Outstanding Checks                                       [U]
│   │   └── Deposits in Transit                                      [U]
│   └── Disbursements                                                   [U]
│       └── Check Voucher                                            [U]
│
├── Fixed Assets                                                     [U]
│   ├── Overview                                                        [U]
│   │   ├── Fixed Asset Dashboard                                    [U]
│   │   └── Asset Register                                           [U]
│   ├── Transactions                                                    [U]
│   │   ├── Asset Acquisition                                        [U]
│   │   ├── Depreciation Run                                         [U]
│   │   ├── Asset Disposal                                           [U]
│   │   ├── Asset Transfer                                           [U]
│   │   └── Asset Impairment (PAS 36)                                [U]
│   └── Setup                                                           [U]
│       ├── Asset Categories                                         [U]
│       └── Depreciation Profiles                                    [X]
│
├── Accounting                                                       [P]
│   ├── Journal Entries                                                 [P]
│   │   ├── Journal Entry                                            [W]
│   │   └── Recurring Journal Template                               [U]
│   ├── Ledgers                                                         [P]
│   │   ├── General Ledger                                           [W]
│   │   ├── Account Detail Ledger                                    [W]
│   │   └── Trial Balance                                            [W]
│   ├── Subsidiary Ledgers                                              [P]
│   │   ├── Customer Ledger      → same surface as AR Aging          [W]
│   │   ├── Supplier Ledger      → same surface as AP Aging          [W]
│   │   └── Control Account Reconciliation                           [P]
│   ├── Accounting Trace                                                [P]
│   │   ├── Source-to-Journal Trace                                  [W]
│   │   └── Accounting Source Drillback                              [W]
│   ├── Schedules                                                       [U]
│   │   ├── Amortization Schedule                                    [U]
│   │   └── Revenue Recognition Schedule                             [U]
│   └── Period Management                                               [P]
│       ├── Period Closing & Fiscal Locks                            [P]
│       ├── Posting Review                                           [W]
│       ├── Reversal Review                                          [W]
│       ├── Auto Reversal Run                                        [W]
│       ├── Amortization Run                                         [U]
│       └── Revenue Recognition Run                                  [U]
│
├── Compliance                                                       [P]
│   ├── Value-Added Tax                                                 [P]
│   │   ├── VAT Dashboard                                            [W]
│   │   ├── Output VAT Summary                                       [W]
│   │   ├── Input VAT Summary                                        [W]
│   │   ├── SLS · SLP                                                [W]
│   │   ├── SLSP Export · RELIEF Export                              [W]
│   │   ├── VAT Working Papers                                       [U]
│   │   ├── VAT Reconciliation                                       [P]
│   │   └── VAT Return 2550M · 2550Q                                 [P]
│   ├── Withholding Tax                                                 [P]
│   │   ├── WT Dashboard                                             [W]
│   │   ├── EWT Payable Summary                                      [W]
│   │   ├── EWT Receivable Summary                                   [W]
│   │   ├── ATC Summary                                              [W]
│   │   ├── 2307 Certificates Issued · Received                      [P]
│   │   ├── QAP · SAWT                                               [P]
│   │   ├── EWT / 1601EQ Working Papers                              [U]
│   │   ├── 1601EQ Quarterly Return                                  [U]
│   │   └── Final Withholding Tax                                       [U]
│   │       ├── FWT Working Papers                                   [U]
│   │       ├── 1601FQ Working Papers · Return                       [U]
│   │       └── 2306 Certificates                                    [U]
│   ├── Percentage Tax                                                  [P]
│   │   ├── PT Dashboard                                             [P]
│   │   ├── PT Review                                                [W]
│   │   ├── PT Working Papers                                        [U]
│   │   ├── PT Quarterly Return 2551Q                                [P]
│   │   ├── PT Reconciliation                                        [P]
│   │   └── PT Summary Register                                      [U]
│   ├── Income Tax                                                      [U]
│   │   ├── Income Tax Dashboard                                     [P]
│   │   ├── Taxable Income Computation                               [U]
│   │   ├── Book-to-Tax Reconciliation                               [U]
│   │   ├── OSD Computation                                          [U]
│   │   ├── NOLCO Schedule                                           [U]
│   │   ├── Tax Credits Schedule                                     [U]
│   │   ├── 1701Q · 1701 (individual / sole proprietor)              [U]
│   │   ├── 1702Q · 1702RT (corporate / OPC / partnership)           [U]
│   │   └── MCIT Computation                                         [U]
│   ├── BIR Books of Accounts                                           [P]
│   │   ├── Books Dashboard                                          [W]
│   │   ├── General Journal                                          [W]
│   │   ├── General Ledger Book                                      [W]
│   │   ├── Cash Receipts Book                                       [W]
│   │   ├── Cash Disbursements Book                                  [P]
│   │   ├── Sales Journal · Cash Sales Journal                       [W]
│   │   ├── Purchase Journal · Cash Purchases Journal                [W]
│   │   ├── AR · AP · Inventory Subsidiary Ledgers                   [W]
│   │   └── Fixed Asset Register                                     [U]
│   └── Audit & CAS                                                     [P]
│       ├── CAS Dashboard                                            [P]
│       ├── Transaction Audit Log                                    [W]
│       ├── Master Data Change Log                                   [W]
│       ├── System Parameter Logs                                    [W]
│       ├── User Activity Log                                        [W]
│       ├── Document Void Register                                   [W]
│       ├── ATP Usage Log                                            [W]
│       ├── CAS Audit Report                                         [P]
│       ├── Attachment Register                                      [U]
│       ├── DAT File Generation                                      [U]
│       ├── Export History                                           [U]
│       └── Report Snapshots                                         [U]
│
├── Reports                                                          [P]
│   ├── Financial Statements                                            [P]
│   │   ├── Balance Sheet                                            [W]
│   │   ├── Income Statement                                         [W]
│   │   ├── Statement of Changes in Equity                           [W]
│   │   ├── Comparative Financial Statements                         [W]
│   │   └── Statement of Cash Flows                                  [P]
│   ├── Trial Balance                                                   [P]
│   │   ├── Trial Balance                                            [W]
│   │   └── Adjusted · Post-Closing Trial Balance                    [PL]
│   ├── Management Reports                                              [P]
│   │   ├── Branch P&L                                               [W]
│   │   ├── Gross Margin Analysis                                    [W]
│   │   ├── Department Report                                        [P]
│   │   └── Cost Center Report                                       [P]
│   ├── Inventory Reports                                               [P]
│   │   └── Slow Moving Inventory                                    [W]
│   ├── Bank Reports                                                    [P]
│   │   └── Bank Position Report                                     [W]
│   ├── Audit Reports                                                   [P]
│   │   └── Audit Support Package                                    [W]
│   └── Fixed Asset Reports                                             [U]
│       ├── Depreciation Schedule                                    [U]
│       ├── Book vs Tax Depreciation                                 [U]
│       └── Asset Disposal Report                                    [U]
│
└── Administration & Security                                        [G]
    ├── Users & Memberships                                          [W]
    ├── Roles & Permissions                                          [W]
    ├── Branch Scope Assignment                                      [W]
    ├── Master Data Import / Export                                  [W]
    └── System Audit Log                                             [W]
```

## 2.1 Reading notes on the tree

**Reports is an index, not a layer.** Most report names a user expects — the
registers, the aging reports, the tax summaries, the subsidiary ledgers — are
owned by their business module and are *linked* from Reports, not duplicated
there. The tree above lists each surface once, under its owning module. Only
genuinely cross-domain analysis appears under Reports.

**Some surfaces are deliberately shared.** AR Aging is simultaneously the Sales
receivables view, the Accounting customer subsidiary ledger, and the BIR AR
Subsidiary Ledger. That is one surface serving three purposes by design, not
three features. The same applies to AP Aging and to Inventory Movements.

**Administration & Security is now a partial product module.** Four restricted
screens manage users/invites, company memberships, roles and branch scopes, while
security enforcement remains owned by the certified Permissions engine. Hosted
invite delivery, browser evidence, access review and support operations remain
unproven.

---
# 3. Canonical Module Definitions

Eleven canonical business modules plus the cross-product Dashboard reporting
surface. Each definition states business scope, users, workflows, dependencies,
evidence standing, exclusions, and what comes next. Certification status remains
controlled by `PXL_CERTIFICATION_MATRIX.md`; this section maps but does not alter
that status.

---

## 3.1 Dashboard

| | |
| --- | --- |
| **Purpose** | Give an owner or manager one screen that answers "is my system set up correctly, and what do I owe the BIR next?" |
| **Scope** | Company setup completeness, master-data counts, and upcoming statutory deadlines. It is a **monitoring** surface — it originates no transaction and posts nothing. |
| **Primary users** | Business owner · General Manager · Accountant |
| **Major business processes** | Setup readiness review · compliance deadline watch |
| **Major transactions** | None |
| **Major reports** | Setup checklist · tax deadline list with overdue/due-soon flags |
| **Dependencies** | Company/Branch masters · Compliance Profile · Tax Calendar · Chart of Accounts · Number Series |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Not certified. It is not one of the eleven certification modules — **no module owns the Dashboard.** |
| **Implementation** | The shipped page reads live company, branch, customer, supplier, item, account, workflow, and tax-calendar data. It works. It is not the product that was specified: the configurable KPI widget grid, global date range, entity roll-up, and export/import do not exist, even though the two tables that would store user dashboard layouts exist and are seeded. |
| **Roadmap** | Assign an owning module. Then decide the widget grid: build it, or retire the two unused layout tables. Cash position, AR/AP aging, and VAT estimate widgets all have working data sources already. |

---

## 3.2 Setup

| | |
| --- | --- |
| **Purpose** | Make a company operable: legal identity, structure, calendar, accounts, numbering, tax profile, and the switches that decide which parts of PXL apply to this business. |
| **Scope** | Organization · System Controls · Document & Validation · Accounting Setup · Tax Setup. Excludes user/role administration, which belongs to Administration & Security. |
| **Primary users** | Implementation consultant · Accountant · System administrator |
| **Major business processes** | Company provisioning (guided wizard that creates the company, fiscal year, twelve periods, and standard accounts in one atomic step) · chart of accounts maintenance · document numbering setup · tax profile declaration · feature enablement · period locking |
| **Major transactions** | None — Setup produces configuration, not documents |
| **Major reports** | Company setup checklist with explicit Core Accounting / Operational / Production readiness stages |
| **Dependencies** | Permissions engine (admin-only writes) · Number Series engine · Audit engine · COA engine |
| **Maturity** | **M7 — GOVERNED** |
| **Certification** | Certification module #1 *"Setup and Master Data"* — **Blocked.** Its review has been executed: 14 gates Pass, 3 Partial, 2 Blocked, 4 not applicable, **0 Fail, and zero open defects**. All four foundational engines it depends on are Certified. |
| **Implementation** | The strongest-governed module in PXL. Backup and restore are demonstrated locally with measured RPO/RTO, but not operated on a schedule or offsite; browser-workflow evidence remains absent. Opening balances now provide a governed cut-over surface and lifecycle. |
| **Roadmap** | Operate backup/restore and add an automated browser lane. CAS Registrations remain the genuine setup gap; validate the opening-balance cut-over against a real onboarding before any pilot claim. |

---

## 3.3 Master Data

| | |
| --- | --- |
| **Purpose** | Hold the entities every transaction refers to — who you sell to, who you buy from, what you sell, where you keep it, and how you get paid. |
| **Scope** | Parties (customers, suppliers, employees) · Items and services · Inventory masters · Bank accounts · Payment terms. Master data is *snapshotted* onto documents, so editing a master never rewrites posted history. |
| **Primary users** | Accountant · Sales and purchasing staff · Implementation consultant |
| **Major business processes** | Party onboarding with TIN validation and duplicate-TIN detection · item catalogue maintenance with default accounts and tax codes · warehouse and stock-setting maintenance · bulk import and export with batch provenance |
| **Major transactions** | None |
| **Major reports** | Master data change log (via Compliance ▸ Audit & CAS) |
| **Dependencies** | Permissions engine (a governed permission and segregation-of-duties model) · Audit engine · Approval engine (import commits are approval-gated) · Chart of Accounts |
| **Maturity** | **M7 — GOVERNED** |
| **Certification** | Shares certification module #1 with Setup — **Blocked**, same reasons. |
| **Implementation** | Party, item, warehouse, and payment-term masters are complete and exercised. Philippine TIN is normalised and constraint-enforced on both party masters. Customer and supplier tax profiles drive withholding end to end. Suppliers now carry verified bank accounts; bank-transfer Payment Vouchers snapshot the selected payee and fail closed at posting without one. Multi-contact, groups, and item-extension foundations still lack complete screens. The existing governed importer is now navigable with preview-before-commit. |
| **Roadmap** | Surface the contacts, groups and item-extension masters; validate supplier-bank and import workflows in the browser and hosted environment. |

---

## 3.4 Sales & Receivables

| | |
| --- | --- |
| **Purpose** | Run the revenue cycle and keep receivables accurate — quote, commit, deliver, invoice, collect, and correct. |
| **Scope** | The full customer-facing document chain, receivables monitoring, output-tax review, and the sales registers that feed VAT reporting and the BIR sales books. |
| **Primary users** | Sales staff · Billing clerk · Accountant · Collections officer |
| **Major business processes** | Quote → order → delivery → invoice · cash sale with immediate settlement · collection with creditable withholding capture · credit memo correction · customer return · receivables ageing and collection follow-up |
| **Major transactions** | Sales Invoice · Cash Sale · Official Receipt · Credit Memo · Quotation · Sales Order · Delivery Receipt · Debit Memo · Customer Return |
| **Major reports** | AR Aging & Customer Ledger · Sales Registers · Summary List of Sales · Output VAT Review · Percentage Tax Review · 2307 Received Review |
| **Dependencies** | Customers · Items · Payment Terms · Number Series · Posting engine · Dimension engine · Approval engine · COA engine · **Tax Engine** (since PAD-001; tax calculation left the save routines on 2026-08-03) |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #3 — **In Progress.** Named blockers: Sales Invoice completeness, and returns/credit reconciliation. |
| **Implementation** | Sales Invoice is the strongest transaction in PXL: a full draft → approve → post → void → revert lifecycle, all six analytical dimensions reaching the posted journal, saved-source GL preview, immutability after posting, and the only dedicated form/document route pair in the product. Cash Sale, Official Receipt, and Credit Memo have complete posting lifecycles. Against that: **Debit Memo is a finished screen over a data table the governance register classifies as an unimplemented future module**; Customer Return is a conversion surface that produces a credit memo but returns no stock; and Quotation → Order → Invoice conversion is not verified because the Document Conversion engine has not been started. |
| **Roadmap** | Under the certification programme it is Phase 2 and the nearest module-level win; the Roadmap places full module work under the **Customer-to-Cash** outcome (Delivery Plan Phase 5) after cross-cycle proof and Tax architecture. Then close returns and credit reconciliation, then the conversion chain. |

---

## 3.5 Purchasing & Payables

| | |
| --- | --- |
| **Purpose** | Run the procurement cycle and keep payables accurate — order, receive, record the bill, withhold correctly, and pay. |
| **Scope** | The full supplier-facing document chain, payables monitoring, input-tax and withholding review, and the purchase registers that feed VAT reporting and the BIR purchase books. |
| **Primary users** | Purchasing staff · Warehouse receiver · Accounts payable clerk · Accountant |
| **Major business processes** | Purchase order → goods receipt → vendor bill → payment · cash purchase · expanded withholding at source or at payment · supplier credit application · 2307 certificate issuance |
| **Major transactions** | Purchase Order · Receiving Report · Vendor Bill · Cash Purchase · Payment Voucher · Vendor Credit · Supplier Debit Memo · Purchase Return |
| **Major reports** | AP Aging & Supplier Ledger · Purchase Registers · Summary List of Purchases · Input VAT Review · EWT Summary · 2307 Issued Review |
| **Dependencies** | Suppliers · Items · Payment Terms · Number Series · Posting engine · Dimension engine · Approval engine · COA engine · tax calculation in the save layer |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #4 — **In Progress.** Named blockers: three-way match, returns, over-receipt controls. |
| **Implementation** | Vendor Bill, Cash Purchase, Payment Voucher, and Vendor Credit have complete posting lifecycles with correct withholding basis (at source for accruals, at payment for disbursements). The structural defect that dominated this module — a Receiving Report increasing stock without creating any journal — was closed by PXL-AUD-073 on 2026-08-02: the receipt now posts DR inventory control / CR purchase clearing, which the Vendor Bill's existing debit to the same account clears. Three-way match, over-receipt control and returns remain open. Supplier Debit Memo and Purchase Return are finished screens over governed-empty tables. |
| **Roadmap** | Resolve the receiving-to-journal asymmetry — it is the highest-value accounting fix in the product. Then three-way match, then returns. |

---

## 3.6 Inventory

> **Read this first.** "Inventory" means two different things in PXL. This module
> is the **operational** one — stock on hand, movements, adjustments, counts. The
> **Inventory Accounting Engine** (§4.12) is a separate, dormant costing
> foundation. They have different lifecycles, different evidence, and different
> readiness. Never quote one's progress for the other.

| | |
| --- | --- |
| **Purpose** | Know what stock exists, where it is, what it is worth, and why it moved. |
| **Scope** | Stock balances and movements, warehouse-to-warehouse transfers, adjustments, physical counts, and inventory valuation. Costing *method* behaviour (FIFO, moving average, specific identification) is owned by the Inventory Accounting Engine, not by this module. |
| **Primary users** | Warehouse staff · Inventory controller · Accountant |
| **Major business processes** | Receive into stock (from Purchasing) · issue out of stock · transfer between warehouses · adjust for damage, loss, or correction · count physically and post the variance |
| **Major transactions** | Stock Adjustment · Stock Transfer · Physical Count · Goods Issue |
| **Major reports** | Inventory Dashboard · Stock Balance · Inventory Movements (which also serves as the BIR Inventory Subsidiary Ledger) · Inventory Valuation · Slow Moving Inventory |
| **Dependencies** | Items · Warehouses · Warehouse Stock Settings · Posting engine · Dimension engine · Purchasing (receiving) · Sales (delivery) |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #5 — **In Progress.** |
| **Implementation** | Adjustments, transfers, and physical counts post real journals and are exercised with live data. Goods Issue is a finished screen over a governed-empty table. **Inventory now ties out.** PXL-AUD-073 (2026-08-02) closed the receiving-to-journal gap: a confirmed Receiving Report posts DR inventory control / CR purchase clearing through the sealed doorway, and inventory value equals its configured control account at **₱0.00 variance** in every stock-holding company, enforced by guard test `111`. The previously recorded variances of ₱2,400.00 / ₱21,000.00 / ₱6,630.00 were never re-measured and were wrong; the true pre-fix variances were **₱380.00 / ₱2,100.00 / ₱330.00**. The cost-layer excess of ₱2,420.00 / ₱12,600.00 / ₱3,930.00 and 9 / 6 / 14 units was correct and is also closed: layers are no longer created for weighted-average items, because no outflow path could consume them. **Correction 2026-08-02:** an earlier edition recorded "sales-side COGS posting remains open". That was wrong. `fn_post_sales_invoice` posts DR COGS / CR inventory per inventory line, consuming weighted-average cost or FIFO layers, decrementing `stock_balances` and refusing to post on insufficient stock; test `054` asserts it and the canonical ledger shows COGS debits equal to inventory credits in all three trading companies. Inventory could not tie out at ₱0.00 if it were true. **Every outbound entry point relieves stock as of 2026-08-03** — Cash Sale, then Delivery Receipt and Customer Return — all through the same `fn_ensure_stock_balance` / `fn_consume_cost_layers` and `fn_receive_inventory` paths, so no second costing implementation exists. A delivery parks its cost in Goods Delivered Not Invoiced and the invoice clears it rather than relieving twice. Genuinely open: three-way match, over-receipt control, Delivery Receipt cancellation/reversal, and the FIFO layer path (`inventory_cost_layers` has never held a row). |
| **Roadmap** | Reconcile inventory to the control account (this requires the Purchasing receiving fix first). Then activate governed costing through the Inventory Accounting Engine — which is itself blocked several stages upstream. |

---

## 3.7 Banking & Treasury

| | |
| --- | --- |
| **Purpose** | Control cash — bank accounts, petty cash, transfers, disbursements, and reconciliation against bank statements. |
| **Scope** | Petty cash lifecycle, bank operations, check disbursement, and bank reconciliation. Bank *accounts* themselves are a master and live in Master Data. |
| **Primary users** | Cashier · Treasury officer · Accountant · Auditor |
| **Major business processes** | Establish and replenish petty cash funds · issue and liquidate petty cash vouchers · count cash · transfer between own accounts and between branches · record bank charges and credits · issue check vouchers · reconcile the bank statement and identify outstanding checks and deposits in transit |
| **Major transactions** | Petty Cash Voucher · Petty Cash Replenishment · Cash Count Sheet · Fund Transfer · Inter-Branch Transfer · Bank Adjustment · Check Voucher · Bank Reconciliation |
| **Major reports** | Bank Position Report · Outstanding Checks · Deposits in Transit · Check Register · Bank Reconciliation Summary |
| **Dependencies** | Bank Accounts · Chart of Accounts · Suppliers (check payees) · Number Series · Posting engine · Period controls |
| **Maturity** | **M3 — UI SKELETON** |
| **Certification** | Certification module #6 — **Not Started** (Phase 5). Named first in the governed deferred-module register. |
| **Implementation** | **Every screen in this module exists and every one of its twelve data tables is empty by governance design.** Posting routines exist for transfers, adjustments, and replenishments but have never been exercised. This is the largest block of navigable-but-unproven surface in PXL — ten menu entries that look finished and are not. One extra instrument, the Check Voucher, exists here that the original blueprint never named. |
| **Roadmap** | Certification-programme Phase 5; the Roadmap's **Asset and Treasury Management** outcome (Delivery Plan Phase 8, v2). Bank reconciliation carries an additional architectural debt: its working table is one of only two tables allowed to be written directly by the interface rather than through the sealed accounting doorway, and that exception needs resolving. |

---

## 3.8 Fixed Assets

| | |
| --- | --- |
| **Purpose** | Track capital assets from acquisition to disposal, and produce depreciation that is correct for both book and tax. |
| **Scope** | Asset register, acquisition, depreciation, transfer, impairment, disposal, and asset categories. |
| **Primary users** | Accountant · Auditor · Asset custodian |
| **Major business processes** | Capitalise an acquisition · run periodic depreciation · transfer custody between branches or departments · recognise impairment under PAS 36 · dispose and compute gain or loss · maintain the statutory fixed asset register |
| **Major transactions** | Asset Acquisition · Depreciation Run · Asset Transfer · Asset Impairment · Asset Disposal |
| **Major reports** | Asset Register (also the BIR Fixed Asset Register) · Depreciation Schedule · Book vs Tax Depreciation · Asset Disposal Report · Fixed Asset Dashboard |
| **Dependencies** | Chart of Accounts · Suppliers · Branches and Departments · Number Series · Posting engine · Dimension engine · Period controls |
| **Maturity** | **M3 — UI SKELETON** |
| **Certification** | Certification module #7 — **Not Started** (Phase 6). |
| **Implementation** | Eight screens, eight posting routines, six data tables — and every table is empty by governance design. Depreciation policy has no governed home at all: there is no depreciation profile master, so method, useful life, and convention have nowhere to be configured. Note that the certified Dimension engine cites fixed-asset acquisition, depreciation, and disposal as proven dimension-bearing transactions; that evidence comes from test fixtures, not from exercised business data, and the two statements must not be read as the same claim. |
| **Roadmap** | Certification-programme Phase 6; the Roadmap's **Asset and Treasury Management** outcome (Delivery Plan Phase 8, v2), alongside the dependent reporting work. Build the depreciation profile master first. |

---

## 3.9 Accounting

| | |
| --- | --- |
| **Purpose** | Own the General Ledger and the accounting period — the place where everything the business does becomes a permanent, balanced, auditable record. |
| **Scope** | Manual journals, the ledgers, subsidiary-ledger reconciliation, source-to-journal tracing, accounting schedules, and period management. |
| **Primary users** | Accountant · Controller · Auditor |
| **Major business processes** | Post and reverse manual journals · review posted activity by period · reconcile subsidiary ledgers to control accounts · trace any figure back to its source document · close and lock a period · generate recurring, amortisation, and revenue-recognition entries |
| **Major transactions** | Journal Entry · Recurring Journal Template · Amortization Schedule and Run · Revenue Recognition Schedule and Run · Auto Reversal Run |
| **Major reports** | General Ledger · Account Detail Ledger · Trial Balance · Control Account Reconciliation · Posting Review · Reversal Review |
| **Dependencies** | Chart of Accounts · Fiscal calendar · Posting engine · Dimension engine · COA engine · every transactional module (as sources) |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #2 *"Accounting Core"* — **In Progress.** Blocker: posting invariants not proven across all posting transactions. |
| **Implementation** | The ledger core is genuinely strong. Manual journals post and reverse with all six dimensions preserved, and the journal-line guard rejects any cross-company dimension. The General Ledger, Account Detail Ledger, and Trial Balance are live over posted data. Source-to-journal tracing is complete and works in both directions — **but it has no menu entry anywhere, so no user can find it.** Schedules (amortisation, revenue recognition, recurring journals) are finished screens over governed-empty tables. Period closing works for locking but year-end close and audited reopening are not certified. |
| **Roadmap** | Prove posting invariants across every posting transaction. Surface the accounting trace in the menu. Then the certification programme's Phase 6 schedules and Phase 8 Accounting Core evidence; the execution sequence is controlled by Roadmap Phases C and J. |

---

## 3.10 Compliance

| | |
| --- | --- |
| **Purpose** | Satisfy the BIR — compute, review, file, and prove Philippine tax obligations from the same posted data the financial statements use. |
| **Scope** | VAT · Withholding tax (expanded and final) · Percentage tax · Income tax · the statutory Books of Accounts · CAS audit artifacts. This is the largest module in PXL by surface area. |
| **Primary users** | Accountant · Tax practitioner · Auditor · BIR examiner (indirectly, through the books and CAS exports) |
| **Major business processes** | Review output and input VAT against posted transactions · summarise withholding by payee and ATC · issue and receive Form 2307 · produce SLSP and RELIEF exports · maintain the statutory books · compute income tax · maintain the CAS audit trail and export artifacts |
| **Major transactions** | 2307 issuance and receipt · statutory return preparation · export snapshot generation |
| **Major reports** | VAT dashboards and summaries · SLS · SLP · SLSP and RELIEF exports · EWT payable and receivable summaries · ATC summary · QAP · SAWT · all thirteen BIR books · CAS logs and audit report |
| **Dependencies** | Compliance Profile (decides what applies) · Tax Codes / VAT Codes / ATC Codes · Tax Calendar · Sales and Purchasing (as sources) · Posting engine · Number Series engine · Audit engine |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #9 *"Philippine Compliance and Tax"* — **Blocked.** Phase 7 has not been executed. |
| **Implementation** | **This module is sharply bimodal, and the split is the single most useful fact about it.** Everything that *reads posted data* works and is trustworthy: VAT reviews, the withholding summaries, all thirteen BIR books, the CAS audit logs, and the server-attested hashed exports. VAT and withholding ledgers reconcile to the General Ledger with **exactly zero variance**. Everything that *persists a statutory artifact* is an empty shell: every working paper, every return generator, every certificate register, and the entire income tax branch. Ten of the eleven income tax screens have never held a row. |
| **Roadmap** | The Roadmap's **Tax Engine and Compliance** outcome governs Tax architecture. The calculator ships first (Delivery Plan Phase 4); **return generation ships after Period Close and the statements, at Delivery Plan Phase 5.8**, because a return is generated from posted, closed data. Certification-programme Phase 7 later completes the module. Build return generation on top of the working review surfaces — the computation inputs already exist and reconcile. The Tax Engine prerequisite is met (§4.18); the filing artifacts remain the blocker. |

---

## 3.11 Reports

| | |
| --- | --- |
| **Purpose** | Present the financial position and cross-domain analysis that no single module owns. |
| **Scope** | Financial statements, trial balance, and management reporting. Registers, ageing reports, tax summaries, and subsidiary ledgers belong to their owning modules and are linked from here rather than duplicated. |
| **Primary users** | Business owner · Accountant · Auditor · Management |
| **Major business processes** | Produce statutory financial statements · analyse profitability by branch, department, cost centre, and product · assemble an audit support package |
| **Major transactions** | None |
| **Major reports** | Balance Sheet · Income Statement · Statement of Changes in Equity · Comparative Financial Statements · Statement of Cash Flows · Trial Balance · Branch P&L · Gross Margin Analysis · Department and Cost Center Reports · Slow Moving Inventory · Bank Position · Audit Support Package |
| **Dependencies** | General Ledger · Chart of Accounts (statement classification) · Dimension engine · Reporting engine · every transactional module |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #10 *"Reports and Financial Statements"* — **In Progress.** Blocker: reconciliation and drill-down not certified. |
| **Implementation** | The four primary statements render from posted ledger data and work. The Statement of Cash Flows has a structurally empty investing and depreciation section because fixed assets are unexercised. Three weaknesses matter: financial statements render from account codes rather than from the **financial statement structure registry that was built for exactly this purpose and is unused**; the Cost Center Report performs no ledger join at all and therefore cannot produce a cost-centre profit and loss; and none of the four management reports uses the **certified dimensional ledger report** that already reconciles exactly to the control total. |
| **Roadmap** | Certification-programme Phase 8; the Roadmap's **Period Close** and **Reporting and Administration** outcomes (Delivery Plan Phases 5–6). Rebuild the management reports on the certified dimensional report, adopt the statement structure registry, and evidence the nine critical reconciliations. |

---

## 3.12 Administration & Security

| | |
| --- | --- |
| **Purpose** | Administer who may use the system, in which company, in which branch, and with what authority. |
| **Scope** | Users and company memberships · roles and permissions · branch scope assignment · master-data import and export governance · system audit log access. |
| **Primary users** | System administrator · Company owner · Auditor |
| **Major business processes** | Grant and revoke company membership · assign roles · restrict a user to specific branches · review privileged activity · govern bulk data import |
| **Major transactions** | None |
| **Major reports** | System Audit Log · User Activity Log |
| **Dependencies** | Permissions engine · Audit engine · Approval engine |
| **Maturity** | **M4 — PARTIAL WORKFLOW** |
| **Certification** | Certification module #11 — **Not Started.** |
| **Implementation** | Four restricted screens now list/invite users, manage company memberships and roles, and assign branch scopes through company-scoped RPCs. Owner protections prevent an administrator from demoting/removing owners, duplicate branch input is normalized, and invite credentials remain server-side in an Edge Function. The master-data importer is navigable and the System Audit Log remains reachable under Setup. |
| **Roadmap** | Deploy and exercise invite delivery only with explicit hosted authority; add browser/UAT evidence, access-review workflow and operating support before certification or pilot claims. |

## 3.13 Canonical module operating matrix

The detailed definitions above and this matrix are one definition set. The
matrix supplies the fields that are easiest to compare across modules. A blank
or absent workflow is never implied by a route, table, or test.

| Capability | Major master data | Major transactions and workflows | Reviews, reconciliations, reports, compliance outputs |
| --- | --- | --- | --- |
| **Dashboard** *(Reporting Surface)* | Company, branch, compliance profile, tax calendar; customer/supplier/item/account counts | Monitoring only; no transaction | Setup readiness and BIR deadline review. Planned cash, AR/AP and KPI views are not built. |
| **Setup** | Company, branch, fiscal year/period, COA, number series, tax profile/codes | Company provisioning; configuration; period lock; governed opening-balance cut-over | Setup checklist; configuration and cut-over audit. CAS registration remains absent. |
| **Master Data** | Customer, supplier, supplier bank account, employee-lite, item/service, UOM, warehouse, bank account, payment terms, dimensions | Party/item onboarding; governed maintenance; preview/commit import and export | Duplicate TIN and change review; verified payee controls; master-data export. |
| **Sales & Receivables** | Customer, item, warehouse, payment terms, dimensions, tax defaults | Quote → order → delivery → Sales Invoice/Cash Sale → Official Receipt/application → memo/return | AR ageing/customer ledger, collection monitoring, sales registers, SLS, output VAT, percentage tax, 2307 received. |
| **Purchasing & Payables** | Supplier, item, warehouse, payment terms, dimensions, tax defaults | PO → Receiving Report → Vendor Bill/Cash Purchase → Payment Voucher → credit/return | AP ageing/supplier ledger, payment monitoring, purchase registers, SLP, input VAT, EWT, 2307 issued. |
| **Inventory** | Item, UOM, warehouse, warehouse-item settings, costing/negative-stock policy | Receipt/issue, adjustment, transfer, physical count; governed costing activation remains separate | Stock balance/movements/valuation/slow-moving; quantity-to-movement and valuation-to-GL reconciliation. |
| **Banking & Treasury** | Bank/cash accounts, petty-cash funds, suppliers/payees | Receipt/payment settlement, deposits/disbursements, transfers, petty cash, bank adjustment and reconciliation | Bank position, check register, outstanding checks, deposits in transit, bank-to-GL reconciliation. |
| **Fixed Assets** | Asset categories and the missing depreciation-profile master | Acquisition → recognition → depreciation → transfer/impairment/disposal | Asset register, depreciation schedule, book/tax reconciliation, disposal report, asset-register-to-GL reconciliation. |
| **Accounting** | COA, fiscal calendar, dimensions, posting mappings | Journal/reversal, source trace, recurring/amortisation/revenue schedules, period close | GL, account ledger, trial balance, control reconciliations, posting/reversal review, financial-statement source. |
| **Compliance** | Compliance profile, VAT/PT/ATC/tax codes, tax calendar, BIR form configuration | Review posted tax; prepare working papers/returns/certificates/exports when implemented | VAT/WHT/PT reviews, books, SLS/SLP/RELIEF, BIR returns/certificates, CAS and audit evidence. The central Tax Engine exists; the filing artifacts do not. |
| **Reports** | COA statement classification, financial-statement structure, dimensions | Read-only financial and management reporting | Financial statements, comparative reports, branch/department/cost-centre analysis, audit support and drill-down. |
| **Administration & Security** | Users, memberships, roles, permissions, branch scope | Invite/list users; provision/revoke access; assign roles/scopes; review privileged activity | User/system activity and access review; hosted invite delivery and browser/UAT remain unproven. |

| Capability | Shared-engine and accounting dependencies | Maturity | Certification / production readiness | Current blocker | Explicit exclusions and future roadmap |
| --- | --- | --- | --- | --- | --- |
| **Dashboard** | Reporting/Reconciliation; all source modules; no posting | **M4 — PARTIAL WORKFLOW** | No owning certification scope / **No** | Ownership and required KPI contract undecided | No transaction origination. Widget grid, roll-up and export are deferred. |
| **Setup** | Permissions, Audit, Number Series, COA; opening cut-over posts through the Kernel | **M7 — GOVERNED** | Setup & Master Data scope **Blocked** / **No** | Operated backup/offsite and automated browser evidence | User administration belongs to Administration & Security; opening cut-over needs real onboarding/UAT proof. |
| **Master Data** | Permissions, Audit, Approval, COA | **M7 — GOVERNED** | Setup & Master Data scope **Blocked** / **No** | Same evidence gates; some extension masters have no UI | Payroll processing excluded. Surface contacts/groups/UOM extensions; validate supplier-bank/import browser paths. |
| **Sales & Receivables** | Number Series, Posting, COA, Dimension, AR, Payment, Approval, Correction, Tax Engine | **M4 — PARTIAL WORKFLOW** | In Progress / **No** | Statement presentation absent (`account_fs_map` empty); document conversion absent beyond the delivery-to-invoice link; Delivery Receipt has no cancellation/reversal path | Foreign currency unsupported. **All outbound inventory entry points now relieve stock** (2026-08-03): Sales Invoice, Cash Sale, Delivery Receipt, with Customer Return putting it back. Cost leaves inventory once, reaches COGS with the revenue, and returns with the goods; test `120` proves the chain end to end. |
| **Purchasing & Payables** | Number Series, Posting, COA, Dimension, AP, Payment, Approval, Correction, Tax Engine | **M4 — PARTIAL WORKFLOW** | In Progress / **No** | Three-way match and over-receipt control absent; `purchase_returns` and `supplier_debit_memos` empty | Foreign currency unsupported. PO → RR → Bill is proven from first principles by fresh-data test `112`; receiving posts to the GL since PXL-AUD-073. |
| **Inventory** | Posting, Dimension, Purchasing/Sales, Inventory Accounting | **M4 — PARTIAL WORKFLOW** | In Progress / **No** | `inventory_cost_layers` never exercised (FIFO path unproven, only weighted average runs); `goods_issues` empty | IA-5/ECC is hidden costing infrastructure, not this module, and is frozen with zero consumers. Inventory ties to control at **₱0.00** in every stock-holding company (guard `111`). Lot/serial and landed cost remain future. |
| **Banking & Treasury** | Payment, Posting, Period, Reversal, Reporting | **M3 — UI SKELETON** | Not Started / **No** | Only `bank_accounts` holds data. `check_vouchers`, `fund_transfers`, `bank_reconciliations`, `petty_cash_vouchers`, `bank_adjustments` are **all empty**; posting functions exist but have never produced a journal. PAD-004 unresolved | v2 by Delivery Plan decision, except Check Voucher for the Cash Disbursements Book. No production banking claim. |
| **Fixed Assets** | Posting, Dimension, Period, Reversal, Reporting | **M3 — UI SKELETON** | Not Started / **No** | **All six tables empty** (`fixed_assets`, `fixed_asset_categories`, depreciation entries, disposals, impairments, transfers); five routes on the deferred list; no depreciation-profile master | v2 by Delivery Plan decision, except a minimal straight-line run if the pilot client holds assets. |
| **Accounting** | Posting/Kernel, COA, Dimension, Period, Reversal, Reporting; all source modules | **M4 — PARTIAL WORKFLOW** | Accounting Core In Progress; Schedules Not Started / **No** | Posting invariants across all consumers, schedules and year-end close unproven | Operational source workflows remain owned by their modules. Close and reconciliation proof are next. |
| **Compliance** | Tax Engine, Posting boundary, Number Series, Audit, Reporting; Sales/Purchasing/Accounting | **M4 — PARTIAL WORKFLOW** | Blocked / **No** | Tax Engine shipped (PAD-001, 2026-08-03); percentage tax still uncalculated. **All twelve `compliance_*` working-paper tables are empty**, as are `bir_forms`, `form_2306/2307_*`, `vat_returns` and `withholding_remittances`. Nothing has ever been filed | Review surfaces read real posted data (tax calendar 248 rows, tax detail entries, VAT/EWT reconcile to GL); the **filing artifacts** do not exist. Income tax is v2. Do not claim filing readiness. |
| **Reports** | Reporting/Reconciliation, COA, Dimension, GL and every source module | **M4 — PARTIAL WORKFLOW** | In Progress / **No** | Eight of nine critical reconciliations unevidenced; **`account_fs_map` empty**, so no financial-statement presentation mapping exists | Trial balance and GL read real posted data across 23 views. Reports is a cross-domain index where stated; no parallel books. |
| **Administration & Security** | Certified Permissions and Audit; Approval | **M4 — PARTIAL WORKFLOW** | Not Started / **No** | `user_company_branch_scopes` **empty** — branch scoping never exercised; the `admin-invite` Edge Function is written but **never deployed**; browser/UAT unproven | Restricted in-product administration is the decided PAD-003 boundary; enforcement remains engine-owned. |

---
# 4. Shared Engines

An **engine** is a mechanism that many modules borrow. It is never a menu entry
and never a user concept. Users experience an engine only through the module
surfaces it powers.

The certification program recognises **nineteen** engine assessment scopes. Four
are certified. The Posting Engine is blocked; the Tax Engine now **exists at M5
and is not certified** — it was absent at M0 until PAD-001 on 2026-08-03. This
section documents each in business terms and labels absence explicitly.

> **The rule that must never be broken:** certifying an engine certifies a
> mechanism. It certifies **no module** that uses that mechanism. PXL has four
> certified engines and **zero certified modules**, and both statements are true
> simultaneously.

## 4.0 Canonical shared-engine register

This register uses the nineteen certification scopes without pretending that
all nineteen are the same kind of product component. Backup and Recovery is an
operational capability assessed under the engine standard; the Accounting
Kernel is nested within Posting and is not a twentieth engine.

Every **Measured evidence** cell below was verified against the live database and
repository on 2026-08-02.

| # | Canonical name | Purpose / visibility | Principal consumers | Maturity and certification | Measured evidence (2026-08-02) | Blocker / future responsibility / must not be confused with |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | **Posting Engine** | Single governed doorway to the GL; hidden | Every posting module | **M7 GOVERNED; Blocked at P6; not Certified** | **24** `fn_post_*` entry points defined; **12** have ever produced a journal. P1–P5.2 staged and armed | Twelve entry points have never posted. Kernel is its guard component, not a peer; future consumer-wide certification. |
| 2 | **Inventory Accounting Engine** | Economic chronology and future costing; hidden | Inventory, Purchasing, Sales, Posting | **M2 BACKEND FOUNDATION; not Certified; C-01 suspended claim** | **21 `inventory_*` ECC tables, all empty. Zero consumers.** WP-1…WP-4 certified | **Frozen** by Delivery Plan decision. WP-5 rejected; WP-5…WP-9 and IA-6 unauthorised. Not the user-facing Inventory Module. |
| 3 | **AR Engine** | Receivable position and ageing; visible only through AR surfaces | Sales, Accounting, Reports | **M4 PARTIAL WORKFLOW; not Certified** | `vw_ap_aging`/`vw_ar` equivalents and `vw_customer_ledger` live; as-of ageing test `052`; 75 invoices / 6 receipts posted | Prove every scenario to AR control and corrections. Not the Sales module. |
| 4 | **AP Engine** | Payable position and ageing; visible only through AP surfaces | Purchasing, Accounting, Reports | **M4 PARTIAL WORKFLOW; not Certified** | `vw_ap_aging`, `vw_supplier_ledger`; as-of ageing test `050`; 36 bills / 5 payment vouchers posted | Prove every scenario to AP control and corrections. Not the Purchasing module. |
| 5 | **Payment and Application Engine** | Applies receipts/payments and tracks residuals; surfaced inside transactions | Sales, Purchasing, Banking, AR/AP | **M4 PARTIAL WORKFLOW; not Certified** | Receipt and Payment Voucher post; vendor-credit application controls tested; settlement authority test `109` | Over-application, unapplied cash, reversal and concurrency proof. Not a Banking module. |
| 6 | **Tax Engine** | One authoritative PH-tax calculator; hidden | Sales, Purchasing, Compliance, Posting boundary | **M5 IMPLEMENTED; not Certified** | `fn_calculate_tax` is the only function in the schema performing tax arithmetic (test `090` assertion 6, was 11 functions). All **eleven** former calculators migrated. `fn_resolve_vat_code` is the only place a VAT code's validity is decided. Guards `117` (31) and `118` (25) | **PAD-001 decided 2026-08-03.** VAT (both bases, effective-dated since `20260803000002`) and ATC withholding only — **percentage tax is calculated nowhere**. The company tax profile is not yet effective-dated (Backlog 11). A calculator is not filing capability; do not confuse it with Tax Setup/Compliance. |
| 7 | **Document Conversion Engine** | Preserves source chains and remaining quantities; hidden | Sales, Purchasing, Inventory | **M1 ARCHITECTURE; Not Started** | **Zero conversion or copy-forward functions** among 437 | Quote → SO → SI carry-forward absent; nothing prevents double conversion. Not the document lifecycle/workspace framework. |
| 8 | **Number Series Engine** | Unique, ATP-bounded document numbers; setup surface only | About 25 document types | **M8 CERTIFIED** | 264 series configured, 218 CAS number issuances, 1 governed void event; cert test `079` | Future explicit provisioning beyond SI/CS/OR; engine certification does not certify document workflows. |
| 9 | **Approval and Workflow Engine** | Governed approval routing and SOD; config/inbox surfaces | Imports now; future transactions | **M4 PARTIAL WORKFLOW; not Certified** | 2 workflows and 2 steps defined; **`approval_requests` = 0 and `approval_instances` = 0 — never executed.** No notification model exists anywhere in the product | Routing cannot notify an approver. PAD-013 undecided. Approval and Workflow are aliases for one engine. |
| 10 | **Period Lock and Closing Engine** | Posting-period control and close lifecycle; period surfaces | All posting modules, Accounting | **M4 PARTIAL WORKFLOW; not Certified** | 60 fiscal periods across 5 fiscal years; financial-close readiness test `053` | Year-end close and audited reopening unproven. Not the Accounting module. |
| 11 | **Reversal, Void and Correction Engine** | Preserves corrections without editing history; review surfaces | All posting modules | **M4 PARTIAL WORKFLOW; not Certified** | Reversal journals present in the ledger; GL reversal visibility test `049`; tax-ledger void/reversal test `048` | Void/correction coverage across every transaction. Not a module-specific credit memo workflow. |
| 12 | **Audit and Immutability Engine** | Append-only change evidence and posted locks; log viewers only | Every module | **M8 CERTIFIED** | 2,358 audit rows; **110 tables carry guard/immutability/status triggers**; 627 user triggers total | Extend only through governed consumer coverage. Log pages are surfaces, not the engine. |
| 13 | **Permissions and RLS Engine** | Tenant isolation and authorization; hidden | Every module | **M8 CERTIFIED** | **209 of 209 tables RLS-enabled; 519 policies; zero tables without a policy.** Default deny holds | Operational user administration remains separate. Do not confuse enforcement with Administration & Security UI. |
| 14 | **Dimension Engine** | Valid, company-safe analytical attribution; master/report surfaces only | Posting modules, Accounting, Reports | **M8 CERTIFIED** | Cert test `080`; dimension-push test `087`; line-level guards on both ledger tables; `vw_gl_dimension_summary` | Adopt its certified report in management surfaces. Dimension masters are not the engine itself. |
| 15 | **Currency Engine** | FX transaction, revaluation and translation authority; hidden | Future transactional modules and Reports | **M1 ARCHITECTURE; Deferred** | 9 currencies listed; **`exchange_rates` empty**; non-PHP fails closed | PAD-005: PHP-only. A currency list is not multi-currency capability. |
| 16 | **Reporting and Reconciliation Engine** | Posted-data views, exports and tie-outs; visible through reports | Every module | **M4 PARTIAL WORKFLOW; not Certified** | **23 views** (trial balance, GL, AR/AP ageing, ledgers, 6 registers, SLP export, dimension summary); tenant-isolation and security guard tests | **1 of 9** critical reconciliations evidenced; `account_fs_map` empty so no statement presentation exists. Not the Reports module. |
| 17 | **Attachment and Document Traceability Engine** | Source/journal/document/file trace; trace surface partly visible | Every transaction and report | **M4 PARTIAL WORKFLOW; not Certified** | Accounting trace works and is now routed; **`cas_attachment_register` empty** | No file lifecycle exists. PAD-008 undecided. Do not infer attachments from empty tabs. |
| 18 | **Backup and Recovery Process** | Restore books after loss; hidden operational capability | Whole product | **M5 TOOLING COMPLETE; operated: No; not Certified** | Fail-closed cycle `backup:operate`; weekly `backup-drill.yml`; **replicated copy restored independently** (93 tables, 0 mismatches, 6s RTO); retention 30/12/7 enforced; all four refusals exercised | PAD-007 decided (S3-compatible). **No bucket, no escrowed passphrase, schedule never fired.** Governance infrastructure, not a user module. |
| 19 | **Chart of Accounts (COA) Engine** | Deterministic account authority and account lifecycle; COA/config surfaces | Posting, Accounting, Reports | **M4 PARTIAL WORKFLOW; not Certified** | 215 accounts, 55 account mappings, cert test `081` | `account_fs_map` empty — no FS classification. Do not confuse COA master screens with resolver adoption. |

**Accounting Kernel / Kernel Totality Guard.** Hidden component inside engine 1;
**M7 GOVERNED, fully enforced, not separately certified**. It prevents every
unsanctioned ledger mutation. Reporting it as a twentieth engine, a module, or a
separate percentage is prohibited.

*Measured 2026-08-02:* `fn_posting_kernel_origin` plus
`zz_trg_journal_entries_kernel_origin` and `zz_trg_journal_entry_lines_kernel_origin`
on both ledger tables. Enforcement **survives a restore into a fresh database** —
deleting ledger rows in a restored copy is still rejected — which is the
strongest available evidence that the guard is structural rather than procedural.

---

## 4.1 Security Engine — *"Permissions and RLS Engine"* · ✅ **CERTIFIED**

**Business meaning.** One company can never see another company's books. Not by
screen filtering, not by convention — at the data layer, mathematically.

**What it does.** Every company-owned record is scoped to its company. Access is
decided by the user's membership, role, and (optionally) branch scope. A user who
is not a member of a company cannot read, write, or discover its data through any
route — the application, the API, or a report view.

**Certified** 2026-07-22 as the program's **first** certified engine. Every
applicable gate passed with executed evidence: row-level security on every base
table with default-deny, an anonymous role with zero data privileges, and every
reporting view running under the caller's own identity. A critical cross-company
leak found *during* its own review was remediated and permanently guarded.

**Documented limitation.** Branch-level isolation is opt-in by design — a user
with no branch scope rows sees the whole company. This is intentional, proven,
and documented.

---

## 4.2 Audit Engine — *"Audit and Immutability Engine"* · ✅ **CERTIFIED**

**Business meaning.** Nothing can be quietly changed, and everything that changes
is recorded — who, when, what, and the exact before and after values.

**What it does.** Every master-data and transaction change writes an append-only
audit record. Posted documents are locked against editing and deletion by
database-level guards, not by hiding buttons. The audit log itself cannot be
altered or deleted by any ordinary user.

**Certified** 2026-07-23 as the **second** certified engine. Its review found and
remediated a critical bypass — a maintenance switch that an ordinary member could
set to defeat the posted-document guards. The bypass is now gated on a privileged
system identity and permanently regression-guarded.

---

## 4.3 Number Series Engine · ✅ **CERTIFIED**

**Business meaning.** Document numbers are unique, sequential, never reused, and
bounded by the BIR Authority to Print range — which is a CAS accreditation
requirement, not a convenience.

**What it does.** Issues numbers per company, per branch, per document type under
an exclusive lock, refuses to issue past the ATP ceiling, and writes permanent
forward-only issuance evidence bound to the source document. Voided numbers are
never reissued.

**Certified** 2026-07-23 as the **third** certified engine. Concurrency was proven
empirically: ten simultaneous clients making twenty allocations each produced two
hundred distinct, contiguous numbers with zero duplicates. About twenty-five
document types consume it.

**Documented limitation.** Automatic series provisioning covers only the
BIR-registered sales invoice, cash sale, and official receipt. Every other
document type needs explicit setup and fails closed if it is missing.

---

## 4.4 Dimension Engine · ✅ **CERTIFIED**

**Business meaning.** Every peso can be attributed to a branch, department, cost
centre, project, location, and functional entity — and the analysed totals still
add up exactly to the company total, with no double counting.

**What it does.** Governs six analytical masters, validates every dimension on
every document (exists, same company, active, within its effective window,
branch-consistent), carries all six through to the posted journal line, preserves
all six through reversal, and rejects any cross-company attribution outright.

**Certified** 2026-07-23 as the **fourth** certified engine. A line-level
dimensional ledger report was built and proven to reconcile exactly to the
undimensioned control total for department, project, and functional entity.

**Unexploited today.** None of the four management reports uses that certified
dimensional report — a finished, certified capability that the surfaces which need
it do not call.

---

## 4.5 Posting Engine · 🟡 **Governed — blocked**

**Business meaning.** There is exactly one doorway into the General Ledger, and
every transaction must walk through it.

**What it does.** Accepts a source document, determines the correct accounts,
builds a balanced journal, and writes it. Nothing else in the system is permitted
to write to the ledger.

**Maturity: Governed.** It has advanced through six formally recorded phases
covering infrastructure, account-resolver adoption, persistence discipline, the
tax boundary, external write-surface closure, and full guard enforcement.

**Blocked** at its inventory-reconciliation phase. The blocker is not in the
engine: receiving goods increases stock without producing a journal, while the
matching vendor bill posts to purchase clearing, so inventory cannot satisfy the
engine's independent-recomputation requirement. Fixing it requires changes that
current governance prohibits without further authorisation.

---

## 4.6 Accounting Kernel — *the Totality Guard*

**This is not a separate engine. It is the enforcement layer inside the Posting
Engine, and conflating the two has caused real reporting confusion** — the
executive dashboard currently shows the Kernel at 100% beside the Posting Engine
at 25%, which reads as two components at odds when they are one component
described twice.

**Business meaning.** It is not merely discouraged to write to the ledger by
another route — it is impossible.

**What it does.** Enforcement is compile-time permanent and cannot be switched
off. Both totality triggers are always active, including for privileged
maintenance identities. Client-side ledger writes and guard execution are revoked
outright. Forty-eight distinct bypass attempts were tested and all forty-eight
were rejected. A dedicated control register exists whose healthy state is *empty*
— a single row in it is evidence of a ledger write that escaped the doorway.

**Status: fully enforced.** Not separately certified, because it is a component
of the Posting Engine, not a peer of it.

---

## 4.7 Chart of Accounts Engine · 🟡 **Partially Implemented**

**Business meaning.** One governed answer to "which account does this post to?",
so that account determination is never a user guess and never duplicated in code.

**What it does.** Resolves the correct account deterministically, fails closed if
no mapping exists, and refuses to guess when a mapping is ambiguous. Governs the
account lifecycle (draft, active, deprecated, archived, locked), prevents changing
an account's fundamental nature once it has been used, prevents deleting an
account with posted history, and holds the financial-statement structure registry.

**Status.** Its foundation phase has landed and the sales and purchasing posting
routines now resolve accounts through it, each proven to produce byte-identical
results. It is **not certified**, because a foundation that no consumer relies on
cannot demonstrate the invariants certification requires. Consumer migration is
in progress.

---

## 4.8 Approval and Workflow Engine · 🟡 **Partially Implemented**

**Note on naming.** PXL has **one** engine here, not two. "Approval Engine" and
"Workflow Engine" are the same registered engine — *Approval and Workflow*. There
is no separate workflow orchestration engine, and none is planned.

**Business meaning.** The right person authorises the right thing before it takes
effect, with segregation of duties enforced.

**What it does.** Resolves which rule applies, routes to a role or a named user,
manages the request lifecycle with concurrency control, enforces
segregation-of-duties conflicts, audits every decision, and presents an approval
inbox.

**Status.** The engine is built. Its **only proven consumer is master-data import
approval.** No transaction-level approval rule is configured anywhere, and the
approval request tables have never held a row in the governed dataset. Sales
invoices, vendor bills, and purchase orders are approved by direct action, not by
matrix routing. The five separate approval matrices the original blueprint
described are now rule rows in one engine.

---

## 4.9 Reversal, Void and Correction Engine · 🟡 **Partially Implemented**

**Business meaning.** Mistakes are corrected in the open, never erased. Both the
original entry and its correction remain permanently visible.

**What it does.** Reverses a posted journal while preserving all six analytical
dimensions, voids a document with a governed reason code and permanent void
evidence, and never reuses a voided document number.

**Status.** Reversal is solid. **Voiding exists for only two document types** —
sales invoices and vendor bills. Coverage across all correction paths is unproven,
which is the engine's stated certification blocker.

---

## 4.10 Period Lock and Closing Engine · 🟡 **Partially Implemented**

**Business meaning.** Once a period is closed, nothing can post into it, and
reopening is a deliberate, audited act.

**What it does.** Generates a fiscal year with twelve periods automatically during
company provisioning, enforces the posting period on every posting routine, and
locks periods against further activity.

**Status.** Locking works. **Year-end closing and audited reopening are not
certified**, and no closing entries exist — which is why "Adjusted" and
"Post-Closing" trial balances cannot currently be produced.

---

## 4.11 Reporting and Reconciliation Engine · 🟡 **Partially Implemented**

**Business meaning.** Reports read from posted data only — never a parallel set of
books — and every report can be tied back to its source.

**What it does.** Provides the ledger, trial balance, subsidiary ledger, tax, and
register views that every reporting surface reads, plus server-attested,
content-hashed export snapshots for BIR books, VAT, withholding, and CAS
artifacts.

**Status.** The views and exports work. The engine is **not certified because none
of the nine critical reconciliations has been evidenced** — trial balance balance,
AR and AP subledger to control, inventory valuation to control, VAT and
withholding ledgers to their accounts, fixed-asset register to ledger, branch to
company, and financial-statement net income to ledger. Of those nine, VAT and
withholding are *known* to reconcile at zero variance and inventory is *known* not
to.

---

## 4.12 Inventory Accounting Engine — *the IA-5 / ECC chronology foundation* · 🔵 **Backend Foundation — dormant**

> **This is not the Inventory module (§3.6).** It is a separate costing
> foundation, and it is completely inactive.

**Business meaning.** Before inventory cost can be trusted, the system must be
able to answer one question permanently and defensibly: *when two stock movements
carry the same date and time, which one must accounting process first, and on what
authority?* Without a fixed answer, FIFO and moving-average costing cannot be
replayed and can produce different results on different runs.

**What it does today.** Nothing. It **stores** the evidence structure required to
answer that question. It creates no cost, no cost layer, no valuation, no journal,
and no ledger effect whatsoever. It has no consumers.

**Status.** Four bounded work packages are certified — the ordering-policy
foundation, the source registry, the valuation stream and its allocator, and the
persisted economic order key. The fifth — the component resolver that would
actually *derive* an order key when an event is admitted — had its authorisation
**rejected**, because the exact contract could not be safely inferred from the
accepted design. Work packages six through nine and the entire costing programme
remain unauthorised.

**Why the original foundation's claim is suspended.** The first implementation
allocated its accepted sequence by database lock order, so identical evidence
produced *opposite* orderings on different runs. That was never economic order.
The defect remains open and the permanent-foundation claim remains suspended.

**How to describe this engine correctly.** "Four of nine work packages certified"
is accurate. "The Inventory Engine is 44% complete" is **not** — it implies usable
capability where there is none. No Inventory module or engine certification
exists.

---

## 4.13 AR Engine · AP Engine · Payment and Application Engine · 🟡 **Partially Implemented** (three engines)

**Business meaning.** What customers owe and what you owe suppliers must always
equal the control accounts in the ledger, and payments must apply correctly
without over-applying or stranding unapplied cash.

**What they do.** Maintain receivable and payable positions, produce true as-of
ageing that accounts for reversals, apply receipts and payments against documents,
and expose subledger-to-ledger reconciliation.

**Status.** All three work in normal use. None is certified, because
subledger-to-control reconciliation has not been proven across the full range of
scenarios, and over-application and unapplied-cash controls are unproven end to
end.

---

## 4.14 Attachment and Document Traceability Engine · 🟡 **Partially Implemented**

**Business meaning.** An auditor can follow any figure to its source document and
to the supporting file, without gaps.

**What it does.** Source-to-journal tracing works completely in both directions,
document relationships are recorded, and every field change is preserved with its
before and after value. Bulk import and export carry batch provenance and content
hashes.

**Status.** The tracing half is genuinely finished — and **has no menu entry**, so
users cannot reach it. The attachment half does not function: every transaction
workspace displays an Attachments tab, but the attachment register has never held
a record and there is no file workflow behind it.

---

## 4.15 Document Conversion Engine · ⬜ **Planned — not started**

**Business meaning.** A quotation becomes an order, an order becomes a delivery, a
delivery becomes an invoice — carrying quantities, prices, and references forward
without rekeying, and without allowing a document to be converted twice.

**Status.** **Not started.** This is precisely why Quotation, Sales Order, and
Delivery Receipt are only partially implemented: they can each be created, but the
chain between them is unverified. The same applies on the purchasing side.

---

## 4.16 Currency Engine · ⬜ **Deferred**

**Business meaning.** Transacting and reporting in more than one currency.

**Status.** **Explicitly deferred — multi-currency is not supported for
production.** A currency list exists and is used for labelling. Exchange rates are
intentionally empty. There is no revaluation, no translation, and no
multi-currency posting.

---

## 4.17 Backup and Recovery · 🟡 **Mechanised and scheduled; not operated**

**Business meaning.** If the database is lost or corrupted, the business can get
its books back, within a known time, losing a known and acceptable amount of work.

**Status, measured 2026-08-02.** The earlier entry read "Nothing exists"; that is
superseded. `npm run backup:operate` runs one unattended, fail-closed cycle —
backup → restore-verify → encrypted offsite replication with read-back →
retention → journal — and `.github/workflows/backup-drill.yml` runs it weekly and
on any change to the recovery scripts.

**What is proven.** A restored database matches its manifest across every
populated table, all schema-object classes and every financial total; the
restored ledger balances at 0.00 and **remains kernel-protected**. The
*replicated* copy — not merely the local archive — was restored independently at
93 tables, 0 mismatches and a 6-second RTO. Retention of 30 daily / 12 monthly /
7 annual is enforced by a tested pure selector. All four refusals were exercised
and observed to refuse: no destination, no verification receipt, an unencrypted
archive, and a checksum mismatch on the copy. The verifier is proven able to fail
against a deliberately corrupted restore.

**What is not proven.** **No durable destination exists and no passphrase is
escrowed**; the weekly schedule has never fired; the replication proof used
separate storage on the same machine, which is explicitly *not* a separate
failure domain; nothing has run against a hosted database; point-in-time recovery
is untested; and no PXL database holds real books. PAD-007 is decided —
self-managed encrypted backups to S3-compatible object storage, no provider PITR
for the pilot — so what remains is owner action, not engineering.

Recoverability therefore no longer blocks engineering, but **every M9 and
"operated" claim still depends on the bucket, the escrowed passphrase and a
schedule that has actually run.**

---

## 4.18 Tax Engine · 🟡 **EXISTS — CALCULATOR ONLY, NOT CERTIFIED**

*Rewritten 2026-08-03. This entry previously recorded a named, owned absence.
PAD-001 closed it.*

**What it is.** `fn_calculate_tax(context) → SETOF tax_component` is the single
authority in PXL that turns a governed Philippine tax rate into a tax amount.
It is hidden infrastructure: no menu entry, no user concept. It calculates and
returns components; it never posts, never persists and never resolves an
account.

**Scope implemented.** VAT in both price bases — exclusive, and inclusive with
the residual rule that makes net + VAT reconstitute a quoted price exactly —
across regular, zero-rated and exempt classification, plus withholding by ATC
covering EWT/CWT and FWT. **Both families resolve the version in force on the
document date**; neither reads a rate by id alone.

**One configurable framework, not one per tax type.** VAT, non-VAT, Percentage
Tax, EWT and FWT are configuration over the same governed masters, not separate
architectures. The user selects a configured code on the transaction and the
database restricts and validates that selection against the company's tax
profile, the code's applicability, its effective dates and active status, the
transaction type and tax side, and the exact version resolved.
`fn_resolve_vat_code` is the single place a VAT code's validity is decided; the
engine, the line/header trigger backstop and the picker `fn_vat_codes_asof` all
ask it, so the frontend offers exactly what the database accepts and cannot
disagree with it. A BIR rate change is configured by closing the current
effective window and adding a successor version; historical rate records are
never edited in place, posted documents keep resolving the version that governed
them, and an unresolvable code is refused rather than degraded to exempt.
Migration `20260803000002_vat_effective_date_resolution.sql`; test `118`.

**Tax is a line-level fact, not a document-level one.** Business Tax (VAT, and in
future Percentage Tax) and Withholding Tax (EWT/CWT, FWT) are **both selectable
per transaction line**, because one document routinely mixes goods and services
with different treatments and different ATCs. The user selects the codes; PXL
derives everything else — taxable base, tax components, tax amounts, line total
and the document summaries — and stores the resolved version and rate on the
line so a posted document explains itself without re-resolving configuration.
Delivered for Cash Sale on 2026-08-03 (`sales_invoice_lines.withholding_*`); the
remaining sales and purchasing documents still carry withholding at header level
and are recorded for rollout in the Product Backlog.

Where a settlement record cannot express the mixture — `receipt_lines` is one row
per invoice and so cannot name two ATCs — the row declares where its detail lives
(`cwt_source`) rather than the settlement key being weakened.

**One known gap in that framework.** `companies.tax_registration` is a single
scalar with no history, so the *company tax profile* is not effective-dated: a
document's profile is resolved from today's registration. Every tax-profile read
in tax-code validation goes through `fn_company_tax_registration_asof(company,
date)`, which accepts the date it cannot yet honour, so the fix is that one
function plus a registration-history table. Product Backlog item 11.

**Scope deliberately excluded.** **Percentage tax is calculated nowhere in
PXL**, by the engine or otherwise, and was not calculated before it either. A
non-VAT, PT-registered company's sales produce no percentage tax, so the PT
review surfaces have no source. Adding a PT branch with no document calling it
would be foundation without a consumer. It requires a posting change and belongs
with the Delivery Plan Phase 5 flows.

**What changed structurally.** Calculation lived in **eleven** routines: seven
document-save routines, two withholding validators and two EWT profile
appliers. They agreed by coincidence rather than by construction, and
VAT-inclusive pricing existed in exactly one of them — so six document types
could not price tax-inclusively at all. All eleven now call the engine. The
schema-wide census of tax arithmetic in test `090` returns exactly one function.

**What is verified.** Test `117` proves the arithmetic on a company it
provisions itself through the current production RPCs, never against the
canonical seed. Test `118` proves the effective-dated VAT resolution the same
way, across a real deprecate-and-succeed 12% → 14% rate change, including that
the database — not only the save RPCs — refuses a superseded code on a directly
written document line. Test `090` proves the structure, and — importantly — its
output assertions passed **unchanged** across the migration: stored tax facts,
posted GL tax lines, tax-ledger rows, both GL reconciliations, reversal
provenance under a changed rate, and cross-calculator rounding agreement all
produced identical figures before and after.

**One defect was closed on the way.** `fn_save_cash_sale` resolved its CWT rate
with no active, deprecation or effective-date filter, so a cash sale could
withhold at a superseded ATC version. Every other withholding path already
refused this. Guarded by `090` assertion 47a.

**What is still true.** The boundary around the engine is unchanged and remains
correct: the Posting Engine computes no tax, the account resolver owns tax
accounts, the tax ledger owns tax detail and its reversal, and the tax ledger
reconciles to the General Ledger at exactly zero variance for both VAT and
withholding.

**Status.** **M5 — the engine exists, is exercised by every tax-bearing document
and is guarded. It is NOT certified**, and the Compliance module still cannot be
completed, because the filing artifacts (Delivery Plan Phase 5.8) do not exist
and nothing has ever been filed from PXL. A working calculator is not a filing
capability.

---

## 4.19 Engines that do not exist and are not planned

The mission brief asked about several engines by name. Where the repository has no
evidence for one, this document says so rather than inventing it.

| Named engine | Repository reality |
| --- | --- |
| **Validation Engine** | **Does not exist as an engine.** Validation is real and enforced, but it is distributed: each document-save routine re-implements its own rules, and master-data rules live in a seeded permission and segregation-of-duties model. There is no central validation authority and none is registered. This is the same structural weakness as the seven tax calculators, and it is the reason the eight "Document & Validation" setup screens are permanently disabled — the rules exist but nothing can configure them. |
| **Notification Engine** | **Does not exist and is not planned.** An exhaustive search of the entire codebase returns **zero** references to notifications, alerts, or messaging of any kind. PXL sends no email, produces no in-app notification, and has no notification data model. Approval routing works without notifying anyone. This should be recorded as a genuine product gap, not treated as an oversight in this document. |
| **Document Engine** | **Not a registered engine.** Two real things are sometimes called this. The first is the **Document Lifecycle framework** — the draft → approved → posted → voided model plus the standard transaction workspace with its fourteen required tabs — which is infrastructure shared by every module, not an engine. The second is the **Document Conversion Engine** (§4.15), which is registered and not started. |
| **Workflow Engine** | Not separate. It is the same engine as Approval (§4.8). |

---

# 5. Product Modules vs Engines vs Infrastructure

## 5.1 Canonical classification table

“User-facing” means a business user directly works with the capability. An
engine can have configuration or report surfaces without the engine itself
becoming a navigation node.

| Capability | Classification | User-facing? | Visible in navigation? | Owner | Consumers | Maturity | Certification standing |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dashboard | Reporting Surface | Yes | Yes | Product / Reports (owner decision open) | Owners, managers, accountants | M4 | No certification scope |
| Setup | Business Module | Yes | Yes | Product / Accounting Setup | All modules | M7 | Part of Setup & Master Data — Blocked |
| Master Data | Business Module | Yes | Yes | Product / Master Data | All operational modules | M7 | Part of Setup & Master Data — Blocked |
| Sales & Receivables | Business Module | Yes | Yes | Product / Sales | Accounting, Compliance, Reports | M4 | In Progress |
| Purchasing & Payables | Business Module | Yes | Yes | Product / Purchasing | Inventory, Accounting, Compliance, Reports | M4 | In Progress |
| Inventory | Business Module | Yes | Yes | Product / Inventory Operations | Purchasing, Sales, Accounting, Reports | M4 | In Progress |
| Banking & Treasury | Business Module | Yes | Yes | Product / Treasury | Accounting, Reports | M3 | Not Started |
| Fixed Assets | Business Module | Yes | Yes | Product / Fixed Assets | Accounting, Compliance, Reports | M3 | Not Started |
| Accounting | Business Module | Yes | Yes | Product / Accounting | Compliance, Reports | M4 | Accounting Core In Progress; Schedules Not Started |
| Compliance | Compliance Workspace | Yes | Yes | Product / Philippine Compliance | Tax users, Accounting, auditors | M4 | Philippine Compliance and Tax — Blocked |
| Reports | Reporting Surface | Yes | Yes | Product / Reporting | Owners, accountants, auditors | M4 | Reports and FS — In Progress |
| Administration & Security | Business Module | Yes | Yes, under Setup | Product / Security Administration | Every module | M4 | Not Started |
| Permissions and RLS | Shared Engine | No | No | Security | Every module | M8 | Certified |
| Audit and Immutability | Shared Engine | No; logs are visible | Only log surfaces | Audit / Platform | Every module | M8 | Certified |
| Number Series | Shared Engine | No; setup is visible | Setup surface only | Accounting Platform | Transaction modules | M8 | Certified |
| Dimension | Shared Engine | No; masters are visible | Master/report surfaces only | Accounting Platform | Posting modules, Reports | M8 | Certified |
| Posting | Shared Engine | No | No | Accounting Architecture | Every posting module | M7 | Blocked at P6; not Certified |
| Accounting Kernel / Totality Guard | Accounting Infrastructure | No | **Never** | Posting Engine | Posting Engine | M7 | Fully enforced; not separate certification scope |
| COA | Shared Engine | No; COA/config visible | Setup surfaces only | Accounting Architecture | Posting, Accounting, Reports | M4 | In Progress |
| Approval and Workflow | Shared Engine | Config/inbox only | Setup surface only | Transaction Framework | Imports; future transactions | M4 | In Progress |
| Period Lock and Closing | Shared Engine | Through period controls | Accounting surfaces only | Accounting | Posting modules | M4 | In Progress |
| Reversal, Void and Correction | Shared Engine | Through module actions/reviews | Review surfaces only | Accounting / Transaction Framework | Posting modules | M4 | In Progress |
| Reporting and Reconciliation | Shared Engine | Through reports | Report surfaces only | Reporting | Every module | M4 | In Progress |
| Inventory Accounting | Accounting Infrastructure | No | **Never** | Inventory Accounting | Inventory, Posting | M2 | In Progress; permanent claim suspended |
| AR | Shared Engine | Through ageing/ledger | Sales/Accounting surfaces | Sales Accounting | Sales, Accounting, Reports | M4 | In Progress |
| AP | Shared Engine | Through ageing/ledger | Purchasing/Accounting surfaces | Purchasing Accounting | Purchasing, Accounting, Reports | M4 | In Progress |
| Payment and Application | Shared Engine | Through payment documents | Transaction surfaces | Treasury / AR/AP | Sales, Purchasing, Banking | M4 | In Progress |
| Attachment and Document Traceability | Shared Engine | Trace yes; file flow absent | Trace currently unlisted | Audit / Platform | Transactions, reports | M4 | In Progress |
| Document Conversion | Shared Engine | No | No | Transaction Framework | Sales, Purchasing, Inventory | M1 | Not Started |
| Currency | Shared Engine | Setup label only | Setup surface only | Accounting Architecture | Future transaction modules | M1 | Deferred |
| Tax | Shared Engine | No | No | **Owner decision required** | Sales, Purchasing, Compliance | M0 | Absent; architecture required |
| Backup and Recovery | Governance Infrastructure | No | No | Operations (unassigned) | Whole product | M0 | Not Started |
| Certification standards, matrix, coverage guard, AI state | Governance Infrastructure | No | No | Product Governance | Product and engineering teams | M7 | Governance evidence; not product certification |
| Banking, Fixed Asset, schedule, return and statutory generator shells | Deferred Scaffold | Yes, but misleading | Yes | Owning future module | None until activated | M3 or lower | No certification |
| Payroll | Separate Product | No | No | Future product owner | None in PXL ERP | Outside ladder | Future separate product; excluded from PXL metrics |
| AI/assistant transaction capability | Out of Scope | No | No | None | None | Outside ladder | No repository capability |

## 5.2 Cross-Module Dependencies

Reading rule: an arrow means *cannot function correctly without*. A module also
inherits everything its dependencies depend on.

### 5.2.1 The universal foundation

**Every module in PXL depends on all five of these.** They are not repeated in the
per-module lists below.

```text
   Permissions & Security Engine   →  who may see and do what          ✅ Certified
   Audit & Immutability Engine     →  nothing changes silently         ✅ Certified
   Company & Branch masters        →  the tenant boundary itself
   Chart of Accounts               →  the accounting language
   Fiscal Calendar                 →  which period anything belongs to
```

### 5.2.2 Per-module dependencies

```text
DASHBOARD
   → Company · Branch · Compliance Profile · Tax Calendar
   → Customers · Suppliers · Items · Chart of Accounts · Number Series
   (read-only; depends on everything, is depended on by nothing)

SETUP
   → Number Series Engine · COA Engine · Approval Engine
   (depended on by: EVERY other module — Setup is the root)

MASTER DATA
   → Setup (company, branches, accounts, payment terms)
   → Approval Engine (import commits) · Permissions (governed field-level rules)
   (depended on by: Sales · Purchasing · Inventory · Banking · Fixed Assets)

SALES & RECEIVABLES
   → Customers · Items · Payment Terms · Warehouses
   → Number Series Engine · Posting Engine · Dimension Engine
   → COA Engine (account determination)
   → Approval Engine (configured but unused for sales)
   → Document Conversion Engine (NOT STARTED — this is why the quote-to-invoice
     chain is unproven)
   → Tax calculation (NO ENGINE — performed inside the save routines)
   → AR Engine · Payment & Application Engine
   (depended on by: Compliance VAT/withholding · BIR sales books · Reports)

PURCHASING & PAYABLES
   → Suppliers · Items · Payment Terms · Warehouses
   → Number Series · Posting · Dimension · COA Engines
   → Document Conversion Engine (NOT STARTED)
   → Tax calculation (NO ENGINE)
   → AP Engine · Payment & Application Engine
   → INVENTORY (receiving increases stock)
   (depended on by: Inventory · Compliance · BIR purchase books · Reports)

INVENTORY
   → Items · Warehouses · Warehouse Stock Settings
   → PURCHASING (goods receipt is the primary inflow)
   → SALES (delivery is the primary outflow)
   → Posting Engine · Dimension Engine
   → Inventory Accounting Engine (DORMANT — this is why costing cannot be
     replayed and why valuation does not tie to the control account)
   (depended on by: Compliance inventory subsidiary ledger · Reports · COGS)

BANKING & TREASURY
   → Bank Accounts · Chart of Accounts · Suppliers (check payees)
   → Number Series · Posting Engine · Period Controls
   → PURCHASING (payment vouchers settle bills)
   → SALES (receipts deposit funds)
   → Supplier Bank Details (verified master; Payment Voucher snapshot and posting guard)
   (depended on by: Reports bank position · BIR cash disbursements book)

FIXED ASSETS
   → Chart of Accounts · Suppliers · Branches · Departments
   → Number Series · Posting Engine · Dimension Engine · Period Controls
   → PURCHASING (acquisition usually originates from a bill)
   → Depreciation Profiles (ABSENT — no governed policy master)
   (depended on by: Reports cash flow statement · BIR fixed asset register)

ACCOUNTING
   → EVERY transactional module (they are its sources)
   → Posting Engine · Accounting Kernel · COA Engine · Dimension Engine
   → Period Lock & Closing Engine · Reversal & Correction Engine
   (depended on by: Compliance BIR books · Reports · every reconciliation)

COMPLIANCE
   → SALES (output tax, sales books, 2307 received)
   → PURCHASING (input tax, withholding, purchase books, 2307 issued)
   → ACCOUNTING (the ledger behind every book)
   → Compliance Profile (decides what applies) · Tax Codes · ATC Codes
   → Number Series Engine (CAS numbering and ATP evidence)
   → Audit Engine (the CAS audit trail)
   → Tax Engine (EXISTS since PAD-001; the binding constraint is now the
     filing artifacts, not the calculator)
   (depended on by: nothing — Compliance is a terminal consumer)

REPORTS
   → ACCOUNTING (the General Ledger is the source of every statement)
   → Chart of Accounts (statement classification)
   → Dimension Engine (management analysis)
   → Reporting & Reconciliation Engine
   → Financial Statement Structure registry (BUILT BUT UNUSED)
   (depended on by: nothing — Reports is a terminal consumer)

ADMINISTRATION & SECURITY
   → Permissions Engine (enforcement already exists and is certified)
   → Audit Engine · Approval Engine
   (depended on by: EVERY module implicitly — restricted administration screens
    now exist; hosted invite delivery and operating evidence remain external)
```

### 5.2.3 The four dependencies that constrain the whole product

Everything else can proceed in parallel. These four cannot be worked around:

| # | Constraint | What it blocks |
| --- | --- | --- |
| 1 | ~~Receiving increases stock without a journal~~ **CLOSED 2026-08-02 (PXL-AUD-073)** | Inventory now reconciles to its control account at ₱0.00. Posting Engine P6 is unblocked on this constraint; three-way match and over-receipt control remain. Cash Sale posting closed 2026-08-03. |
| 2 | ~~No Tax Engine~~ **CLOSED 2026-08-03 (PAD-001)** | One calculator, eleven callers migrated. The eleven-way rule-maintenance risk is gone. Compliance completion is now blocked by the filing artifacts alone; percentage tax remains uncalculated. |
| 3 | **No backup or restore evidence** | Every module's production readiness, including Setup & Master Data, which is otherwise ready to certify |
| 4 | ~~No opening balances~~ **CLOSED LOCALLY 2026-08-02 (PAD-002)** | Governed cut-over exists; real-company/hosted onboarding evidence remains required before pilot. |

---
# 6. Product Maturity

## 6.1 The maturity ladder

Use exactly these cumulative levels for modules and engines. A capability sits at
the highest level it can fully satisfy, never the highest level reached by one
of its parts.

| Level | Canonical definition |
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

**Two rules that govern every classification below.**

- *A route is not an implementation. A table is not a workflow. A test is not a
  certification. A work package is not an engine.*
- *When evidence conflicts, the weaker evidence wins the classification.* A module
  with one excellent workflow and one empty screen is Partially Implemented, not
  Workflow Complete.

## 6.2 Module and Dashboard placement

| Capability | Level | Why — with the evidence that decides it |
| --- | --- | --- |
| **Setup** | **M7 — GOVERNED** | Its combined certification review is complete with 14 Pass, 3 Partial, 2 Blocked, 4 N/A and 0 Fail; the remaining blockers are operational/browser evidence, so it is not M8. |
| **Master Data** | **M7 — GOVERNED** | Same review and evidence boundary as Setup; required masters are substantially exercised, but the combined certification scope remains Blocked. |
| **Accounting** | **M4 — PARTIAL WORKFLOW** | Journals, ledgers, trial balance and reviews work; schedules, year-end close, consumer-wide posting invariants and module reconciliation remain incomplete. |
| **Sales & Receivables** | **M4 — PARTIAL WORKFLOW** | Several posting lifecycles work; conversion, returns-to-stock, source review beyond Sales Invoice, attachments and module-wide reconciliation remain open. |
| **Purchasing & Payables** | **M4 — PARTIAL WORKFLOW** | Core purchase/payable transactions work, but Receiving Report accounting, three-way match and returns remain open. |
| **Inventory** | **M4 — PARTIAL WORKFLOW** | Operational stock workflows work in part; Goods Issue is deferred and valuation does not reconcile to the control account. |
| **Compliance** | **M4 — PARTIAL WORKFLOW** | Posted-data reviews and books work in part; the Tax Engine now exists, but persisted statutory artifacts are still mainly deferred. |
| **Reports** | **M4 — PARTIAL WORKFLOW** | Primary statements render, but critical reconciliation, statement structure use, dimensional management reports and fixed-asset content remain open. |
| **Dashboard** *(Reporting Surface)* | **M4 — PARTIAL WORKFLOW** | Live setup/master/tax-calendar monitoring works; KPI, roll-up, range and export behavior do not. |
| **Banking & Treasury** | **M3 — UI SKELETON** | Navigable pages exist, but its governed tables are empty and no canonical workflow has run. |
| **Fixed Assets** | **M3 — UI SKELETON** | Navigable pages and routines exist over governed-empty data; depreciation-policy authority is absent. |
| **Administration & Security** | **M4 — PARTIAL WORKFLOW** | PAD-003 selected restricted in-product administration; four screens and guarded RPCs exist locally, while hosted invite/browser/UAT and operating evidence remain open. |

## 6.3 Evidence-based distribution

| Level | Canonical business modules | Dashboard surface | Certification engines |
| --- | ---: | ---: | ---: |
| M0 | 0 | 0 | 2 |
| M1 | 0 | 0 | 2 |
| M2 | 0 | 0 | 1 |
| M3 | 2 | 0 | 0 |
| M4 | 7 | 1 | 9 |
| M5 | 0 | 0 | 0 |
| M6 | 0 | 0 | 0 |
| M7 | 2 | 0 | 1 |
| M8 | 0 | 0 | 4 |
| M9 | 0 | 0 | 0 |
| **Total** | **11** | **1** | **19** |

No canonical business module reaches M8 or M9. No transactional module reaches
M5 because each still has at least one material lifecycle, accounting, tax,
reporting, security, correction, attachment, or reconciliation gap. Setup and
Master Data are the nearest module evidence win, but their issued combined
certification scope remains Blocked, not Certified.

---

# 7. Certification Status

Four kinds of certification exist in PXL. **They are not interchangeable and must
never be summed, averaged, or substituted for one another.**

## 7.1 The four kinds, defined

| Kind | What it certifies | What it explicitly does NOT certify |
| --- | --- | --- |
| **Certified Work Package** | One bounded change set — a specific set of structures and rules delivered together and proven in isolation. | Any engine, any module, any usable capability. |
| **Certified Engine** | A shared mechanism, against the engine certification standard. | Any module that uses the mechanism. |
| **Certified Module** | A complete business capability, against the module certification standard's mandatory gates. | Production readiness. |
| **Production Ready** | A certified module plus proven production operations. | — |

## 7.2 Certified Work Packages — 4

All four belong to the dormant Inventory Accounting chronology foundation.

| # | Work package | Certified | What it means in business terms |
| --- | --- | --- | --- |
| 1 | Order policy and version foundation | 2026-07-29 | The rules that decide processing order are versioned and permanent. |
| 2 | Source registry authority | 2026-07-30 | Which document types may create an inventory economic event, and each one's ordering authority. |
| 3 | Valuation stream and accepted allocator | 2026-07-31 | Which independent costing timeline an event belongs to. |
| 4 | Persisted economic order key | 2026-07-31 | The permanent evidence of *why* one same-time event was processed before another. |

**All four are dormant.** They store structure. They produce no cost, no journal,
and no ledger effect. **Four certified work packages do not make a certified
engine**, and the fifth — the resolver that would actually create these keys — had
its authorisation **rejected**.

## 7.3 Certified Engines — 4 of 19

| # | Engine | Certified | One-line business guarantee |
| --- | --- | --- | --- |
| 1 | Permissions and Security | 2026-07-22 | One company cannot see another's books. |
| 2 | Audit and Immutability | 2026-07-23 | Nothing changes silently; posted records cannot be altered. |
| 3 | Number Series | 2026-07-23 | Document numbers are unique, sequential, never reused, ATP-bounded. |
| 4 | Dimension | 2026-07-23 | Analytical attribution is valid, complete, and reconciles exactly. |

Two of the four found and remediated a **critical defect during their own review**
— a cross-company data leak and an immutability bypass. That is the certification
programme working as intended.

## 7.4 Certified Certification Modules — 0 of 11

**No PXL business module is certified.** Not one.

The closest are **Setup** and **Master Data**, which share a certification review
that returned zero failures and zero open defects. Its historical decision remains
blocked: backup/restore has since been demonstrated locally but not operated, and
an automated browser lane remains absent. A certification re-run is required to
change that decision.

## 7.5 Blocked modules and engines

| Scope | Status | The specific blocker |
| --- | --- | --- |
| Setup & Master Data (module) | **Blocked** | Historical certification decision; recoverability is demonstrated but not operated, browser evidence is absent, and no re-run has changed the decision. **No defects.** |
| Compliance and Tax (module) | **Blocked** | Its certification phase has not been executed. The Tax Engine prerequisite is met; the filing artifacts are not. |
| Posting Engine | **Blocked** | Historical certification decision remains below P6. Receiving now posts through the sealed doorway and reconciles locally, but the full consumer/recomputation evidence gate has not been re-run. |
| Tax Engine | **M5 IMPLEMENTED — not certified** | PAD-001 decided 2026-08-03: one Accounting-owned calculator, `fn_calculate_tax`. VAT and ATC withholding only; percentage tax remains uncalculated. |

> **A caution about the word "Blocked".** In the certification matrix, the Tax
> Engine reads "Blocked", which naturally implies a component that exists and is
> stuck. It does not exist. This document carries it as a **named absence**
> precisely so that no reader draws the wrong inference.

## 7.6 Non-certified modules and engines

**Modules — In Progress (5):** Accounting Core · Sales and Accounts Receivable ·
Purchasing and Accounts Payable · Inventory · Reports and Financial Statements.

**Modules — Not Started (4):** Banking and Treasury · Fixed Assets · Accounting
Schedules · Administration and Security.

**Engines — In Progress (10):** Inventory Accounting · AR · AP · Payment and
Application · Approval and Workflow · Period Lock and Closing · Reversal, Void and
Correction · Reporting and Reconciliation · Attachment and Traceability · Chart of
Accounts.

**Engines — Not Started (2):** Document Conversion · Backup and Recovery.
**Engines — Deferred (1):** Currency.

## 7.7 Future scopes — authorised and unauthorised

| Scope | Product state | Standing |
| --- | --- | --- |
| Inventory work packages 5 through 9 | **DESIGN ONLY** | **Unauthorised.** Package 5 was formally rejected. |
| Inventory costing programme (layers, FIFO, moving average) | **DESIGN ONLY** | **Unauthorised.** |
| Posting Engine phases beyond current enforcement | **DEFERRED** | **Paused.** |
| Chart of Accounts consumer migration | **CURRENT BUT PARTIAL** | In progress. |
| Tax Engine | **CURRENT PRODUCT** | Implemented 2026-08-03 under PAD-001 as one hidden calculator; not certified. |
| Multi-currency · Budgeting · Notifications | **FUTURE ROADMAP** | No complete implementation; Budgeting and Notifications have no schema. |
| **Payroll** | **OUT OF CURRENT SCOPE** | **Future separate product. Not a PXL module. Must not appear in any PXL completion metric.** |

## 7.8 The certification statement, in one line

> **PXL: 0 of 11 certification modules certified · 4 of 19 engines certified · 4 of 9 Inventory
> work packages certified · 0 of 9 critical reconciliations evidenced · no backup
> or restore test on record. Not production-ready. Not pilot-ready. Suitable for
> internal QA and demonstration only.**

Any single-percentage summary of PXL's completeness will mislead, because it would
have to average modules against engines against work packages — three
incommensurable populations — and would give credit for components that do not
exist. **The counts above are the headline.**

---
# 8. Original Blueprint Reconciliation

The original PXL ERP blueprint is a **menu tree**. This document describes a
**layered system**. That difference is not cosmetic — it is why the two drifted
apart, and why reconciling them mechanically was never going to work.

The original blueprint has no way to express an engine, a certification scope, a
governed dormancy, or a deliberate deferral. It can only say "this menu item
exists". PXL grew several of its most important components — the sealed ledger
doorway, four certified engines, the coverage-governance control, the entire
chronology foundation — in a vocabulary the blueprint does not possess. Those
components were therefore invisible to it, and the parts of the blueprint that
*were* built drifted in name and location without anything recording it.

*(This section presents five groups. The mission brief asked for four and then
listed five headings; all five are given.)*

## 8.1 Unchanged — the blueprint got these right

Roughly sixty leaf items survived intact in name, location, and intent. The
structurally significant ones:

| Original item | Why it survived unchanged |
| --- | --- |
| Company · Branch · Compliance Profile | The tenant and tax-identity model was correct from the start and has needed no revision. |
| Chart of Accounts · GL Posting Configuration · Fiscal Years | The accounting setup spine was correctly identified. |
| Customers · Suppliers · Items · Payment Terms | The master-data model was correct. |
| Sales Invoice · Vendor Bill · Payment Voucher · Journal Entry | The four strongest transactions in PXL are exactly the four the blueprint put at the centre. |
| General Ledger · Trial Balance | Correctly identified as the accounting core. |
| The Compliance domain shape (VAT · Withholding · Percentage Tax · Income Tax · BIR Books · Audit & CAS) | Six workspaces, correctly scoped. This is the blueprint's best work — the *structure* is right even where the *implementation* is a shell. |

**Why this matters:** the blueprint's business analysis was sound. What it lacked
was architecture, not domain knowledge.

## 8.2 Renamed — and why

| Original | Now | Why the change was made |
| --- | --- | --- |
| Personnel / Employees Lite | **Employees** | Simpler. The "lite" scope is preserved in this document precisely so it is never mistaken for a payroll foundation. |
| Cash Management | **Banking & Treasury** | More accurate: the domain covers bank operations and disbursement, not just cash handling. |
| Bank *(sub-group)* | **Bank Operations** | Distinguishes the *activity* from the *master* (Bank Accounts). |
| Depreciation · Disposal · Transfer · Impairment | **Depreciation Run · Asset Disposal · Asset Transfer · Asset Impairment (PAS 36)** | Explicit verbs prevent confusing a policy screen with an action; the standard citation is added because impairment is judgement-heavy and auditors ask. |
| Feature Settings *(five per-module screens)* | **Feature Enablement** *(one global switchboard)* | Five separate settings screens were never built; one global enablement surface was, and it gates whole top-level menus. The consolidation is better design. |
| Approval Matrix *(five separate matrices)* | **Approval Workflow** *(one rules engine)* | Five hardcoded matrices became configurable rule rows in one engine — exactly the "configuration over customisation" principle. |
| Receipts | **Official Receipt** *(canonical)* | Three names for one object had accumulated across three registers: "Receipts", "Official Receipt / Customer Collection", and "Sales Receipt / Official Receipt". **This document fixes "Official Receipt (OR)" as canonical**, since that is the Philippine statutory term, with the others recorded as aliases. |
| Receiving Reports | **Receiving Report** *(canonical)*, alias "Goods Receipt" | The ERP-standard term "Goods Receipt" had crept in alongside. Philippine practice uses "Receiving Report". |
| Payment Vouchers | **Payment Voucher** *(canonical)*, alias "Vendor Payment" | Same pattern, same resolution. |
| General Ledger Entries | **Journal Entry** *(canonical)* | The blueprint carried both names for one object, and both appeared in the menu pointing at the same screen. "General Ledger" is now reserved for the *ledger view*; "Journal Entry" for the *document*. |

## 8.3 Moved — and why

| Original location | New location | Why |
| --- | --- | --- |
| Setup ▸ Company Bank Accounts | **Master Data ▸ Bank Accounts** | A bank account is a master record referenced by transactions, not a one-time setup step. The move is correct; the Setup entry was simply left behind as a dead placeholder. |
| Setup ▸ ATP Monitoring | **Compliance ▸ Audit & CAS ▸ ATP Usage Log** | Authority-to-Print consumption is audit evidence, and it belongs with the CAS artifacts an examiner reviews. The ATP *ceiling* remains a numbering control. |
| Sales ▸ Sales Cycle *(separate group)* | **Sales ▸ Transactions** *(one ordered pipeline)* | Quotation → Order → Delivery → Invoice → Receipt → Memo reads as one chain. Splitting "Sales Cycle" from "Transactions" made users hunt for the beginning of their own process. |
| Assets ▸ Inventory ▸ Items | **Master Data ▸ Item Catalog** | Items are a master, not an inventory feature. Resolved silently in favour of Master Data. |
| Assets ▸ Inventory ▸ Warehouses | **Master Data ▸ Inventory Master ▸ Warehouses** | Same reasoning. **This one is only half-resolved** — the duplicate still appears in both menus and needs finishing. |

## 8.4 Removed — and why

| Original item | Disposition | Why |
| --- | --- | --- |
| **The "Assets" parent node** | **Dissolved into three top-level domains** | This is the single largest architectural change between blueprint and product, and until now **nothing recorded it.** Inventory, Banking & Treasury, and Fixed Assets have independent lifecycles, independent feature gates, independent documentation folders, and independent certification phases (4, 5, and 6). Grouping them under "Assets" implies a shared lifecycle that does not exist and mis-scopes three separate phases of work. **This document ratifies the split. "Assets" is retired as an architectural node.** |
| EWT Codes · FWT Codes | **Merged into ATC Codes** | Philippine withholding is driven by Alphanumeric Tax Codes. Maintaining three parallel code masters meant three places to get a rate wrong. They were consolidated into one governed, effective-dated ATC master. The menu labels survive as aliases; **the alias map in §8.6 is now the record of that.** |
| Services *(as a separate master)* | **Merged into Items** | An item carries a type — inventory, service, or non-inventory. One master, one set of defaults, one place to maintain. |
| Customer / Supplier Addresses, Tax Profiles, Credit Profiles *(as separate entities)* | **Merged into the party masters** | Correct simplification for tax profiles. **Less correct for addresses** (one billing and one delivery address per customer; suppliers get only one) and **for credit** (a credit limit field with no exposure calculation and no credit hold). Recorded here as a known simplification, not as a completed capability. |
| Trial Balance ▸ Adjusted · Post-Closing | **Not produced** | Three blueprint reports collapsed to one screen with no adjustment or closing state, because closing entries and year-end close do not exist. The two unachievable labels should not be presented as available reports. |

## 8.5 Added — features the blueprint never imagined

These are the components PXL grew that the original tree has no vocabulary for.
Several are the strongest assets in the product.

| Addition | Why it exists | Business value |
| --- | --- | --- |
| **The sealed ledger doorway** (Posting Engine + Totality Guard) | The blueprint assumed transactions would post correctly. It provided no mechanism to *guarantee* it. | It is now impossible to write to the General Ledger by any route other than the sanctioned one — proven against forty-eight bypass attempts. This is the single most valuable thing in PXL. |
| **Four certified engines** | The blueprint had no concept of a shared, separately-assured mechanism. | Tenant isolation, audit immutability, document numbering, and dimensional accounting are each formally proven once and reused everywhere. |
| **Chart of Accounts Engine** | The blueprint let each transaction choose accounts. | One governed, fail-closed answer to "which account?", with a full account lifecycle and change policy. |
| **Coverage governance** | The blueprint had no way to say "this exists but is deliberately not used yet". | Every data structure is classified, and an automated control fails if an expected-to-be-used structure is empty, or a deliberately-empty one silently fills. **This is what makes the honesty in this document possible.** |
| **Source-to-journal tracing** | The blueprint asked for drill-down; it did not specify a tracing mechanism. | From any figure, reach the source document and back. Complete — and currently unreachable from the menu. |
| **The certification programme** | Entirely absent from the blueprint. | Two certification standards, a capability checklist, and a status matrix. It is the reason PXL knows what it does not know. |
| **Transaction Workspace standard** | The blueprint described screens; it did not standardise them. | One consistent document layout with fourteen required tabs across every transaction. |
| **Inventory Accounting chronology foundation** | The blueprint assumed inventory costing "just works". | The structure required to make FIFO and moving-average costing *replayable*. Dormant, four work packages certified. |
| **Guided company provisioning** | The blueprint listed setup screens individually. | One wizard creates the company, fiscal year, twelve periods, and standard accounts atomically, with explicit Core Accounting / Operational / Production readiness stages. |
| **Stock Balance · Check Voucher · Report Snapshots · Feature Enablement** | Practical gaps found during construction. | Real surfaces the blueprint simply never named. |

## 8.6 Canonical naming record

Where PXL has more than one name for one thing, this table fixes the canonical
name. **These aliases are correct and intentional; only the absence of a record
was wrong.**

| Canonical name | Recorded aliases | Notes |
| --- | --- | --- |
| **Sales Invoice** | Invoice | “Invoice” may be used conversationally; product and accounting records use Sales Invoice. |
| **Cash Sale** | Cash Sales | Immediate-settlement sales transaction; not an Official Receipt. |
| **Official Receipt (OR)** | Receipt · Customer Collection · Sales Receipt | Philippine statutory term wins. |
| **Receiving Report (RR)** | Goods Receipt | Philippine practice wins. |
| **Payment Voucher (PV)** | Vendor Payment | — |
| **Customer Return** | Sales Return | Customer-facing return; distinct from Credit Memo until conversion/accounting is proven. |
| **Purchase Return** | Vendor Return · Return to Supplier | Supplier-facing inventory return. |
| **Journal Entry (JE)** | General Ledger Entry | "General Ledger" now means only the ledger view. |
| **ATC Codes** | EWT Codes · FWT Codes | Two masters were merged into this one. |
| **Departments & Cost Centers** | Department Setup · Cost Centers | One surface, two dimension masters. |
| **Fiscal Years & Calendar** | Fiscal Years · Fiscal Calendar | Periods are generated with the year. |
| **AR Aging & Customer Ledger** | Customer Ledger · Customer Ledger (Accounting View) · AR Subsidiary Ledger | One surface serving operations, accounting, and BIR. |
| **AP Aging & Supplier Ledger** | Supplier Ledger · Supplier Ledger (Accounting View) · AP Subsidiary Ledger | Same. |
| **Inventory Movements** | Stock Movement · Inventory Ledger · Inventory Subsidiary Ledger | Same. |
| **Inventory Module** | *(never "Inventory Engine")* | Operational stock. |
| **Inventory Accounting Engine** | IA-5 / ECC chronology foundation | Dormant costing foundation. **Never abbreviate to "Inventory".** |
| **Banking & Treasury** | Bank · Banking · Cash Management | Canonical module name. “Bank Accounts” remains a Master Data capability. |
| **Compliance** | Tax Module | User-facing reviews, books, workpapers and filing surfaces; not the Tax Engine itself, which is hidden infrastructure. |
| **Posting Engine** | Posting pipeline | Canonical shared-engine name. |
| **Accounting Kernel / Kernel Totality Guard** | Kernel | A hidden component inside the Posting Engine, never a peer engine or module. |

## 8.7 Which architecture becomes canonical, and why

**This document is canonical.** The original blueprint becomes historical
reference. The reasoning, stated plainly:

1. **The repository is the evidence.** Executed behaviour outranks documented
   intention — a rule this repository already holds. Where the blueprint says a
   feature exists and no working code does, the blueprint is aspiration.
2. **The blueprint cannot express what PXL actually is.** It has no vocabulary for
   engines, certification scopes, governed dormancy, or deliberate deferral.
   Roughly a third of PXL's most important architecture is invisible to it.
3. **The repository already decided the big questions.** Assets is dissolved.
   EWT and FWT are merged into ATC. Services are an item type. Bank accounts are
   masters. Those decisions are implemented, load-bearing, and correct. What was
   missing was the record — not the decision.
4. **But the blueprint is not simply wrong.** Its domain analysis is sound, and in
   several places it is *more* correct than the earlier shipped product: it asked
   for opening balances, CAS registrations, supplier bank details, an adjusted
   and post-closing trial balance, and a real executive dashboard. Opening
   balances and supplier bank details were delivered locally on 2026-08-02; the
   remaining requirements stay carried forward in §9 and §10.5.

**The rule going forward:** where the repository has decided something, this
document records it. Where the blueprint asked for something the repository never
built, this document keeps it as a requirement — it does not quietly delete it.

## 8.8 Architecture change-history classification

The historical blueprint remains preserved. This table classifies the material
change without rewriting the earlier record.

| Change class | Material items | Why the current architecture differs |
| --- | --- | --- |
| **Unchanged** | Company/Branch, COA, customer/supplier/item masters, Sales Invoice, Vendor Bill, Payment Voucher, Journal Entry, GL, Trial Balance, the Compliance domain shape | The original business-domain analysis was sound and remains current. |
| **Renamed** | Cash Management → Banking & Treasury; Receipt/Collection → Official Receipt; Goods Receipt → Receiving Report; Vendor Payment → Payment Voucher; General Ledger Entry → Journal Entry | Canonical PH business terms and clearer module boundaries remove accumulated aliases. |
| **Moved** | Bank Accounts to Master Data; ATP Usage to Compliance; Items/Warehouses to Master Data ownership; quote/order/delivery into one Sales pipeline | Ownership follows the business object rather than the first menu in which it appeared. |
| **Split** | Assets parent → Inventory, Banking & Treasury, Fixed Assets | The three domains have separate feature gates, lifecycles, owners and certification phases. |
| **Merged** | EWT/FWT masters → ATC Codes; Services → Item Catalog; five approval matrices → one Approval and Workflow Engine; duplicate ledgers/registers → shared surfaces | One governed authority is simpler and reduces contradictory configuration. |
| **SUPERSEDED** | Admission-order “deterministic” Inventory chronology; EWT/FWT code masters; General Ledger Entry transaction name | Executed evidence or a stronger governed design proved the old authority or name inadequate. Historical records remain intact. |
| **Deferred** | Banking/Fixed Asset workflows, schedules, returns, statutory generators, multi-currency, document conversion, IA-6 costing | Routes or foundations may exist, but end-to-end supported workflows and authority do not. |
| **Removed from canonical product tree** | Assets parent; duplicate menu concepts; Payroll as a current ERP module | The parent and duplicates misstate ownership; Payroll is a future separate product. No historical file is deleted. |
| **Newly introduced** | Shared-engine layer, sealed Posting doorway and Kernel, certification program, coverage governance, source trace, IA-5/ECC chronology foundation, guided provisioning | The repository developed load-bearing architecture the menu-only blueprint could not express. |
| **Still owed** | CAS registration authority, depreciation profiles, adjusted/post-closing TB, configurable dashboard, decided rule configuration | The original blueprint identified valid product needs that implementation never completed. Opening balances and supplier bank details moved to current product on 2026-08-02. |

---

# 9. Constitutional Product Evolution Constraints

This section records product outcomes and dependency constraints, not the active
execution plan. The subordinate
[`PXL_PRODUCT_EXECUTION_ROADMAP.md`](PXL_PRODUCT_EXECUTION_ROADMAP.md) owns phase
sequence, entry/exit evidence, the critical path, dashboard measures, risks, and
the next governed mission. If that roadmap conflicts with this constitution,
this document wins and the roadmap must be corrected.

```text
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 0 — TRUSTWORTHY FOUNDATION            ◑ nearly done   │
   └──────────────────────────────────────────────────────────────┘
      A company can be set up, secured, and audited.
      DONE  multi-company setup · master data · numbering ·
            dimensions · audit immutability · tenant isolation
      LEFT  prove backup and restore · automate browser evidence
      GIVES the first certified modules in PXL — the cheapest
            certification available, blocked on evidence not software
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 1 — SELL, BUY, AND KEEP THE BOOKS     ◑ in progress   │
   └──────────────────────────────────────────────────────────────┘
      A business can trade and its ledger is correct.
      DONE  invoice · collect · bill · pay · journal · ledger ·
            trial balance · sealed posting doorway
      LEFT  certify Sales Invoice · certify Vendor Bill ·
            complete returns and credit reconciliation ·
            evidence the subledger-to-control reconciliations
      GIVES a business that can operate and close its books
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 2 — ONBOARD A REAL CLIENT             ◑ local build   │
   └──────────────────────────────────────────────────────────────┘
      An existing business can move onto PXL.
      DONE  opening balances · surfaced master-data import ·
            verified supplier bank details · administration screens
      LEFT  hosted parity/invite deployment · real-company cut-over ·
            browser/UAT and operated recoverability proof
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 3 — INVENTORY THAT TIES OUT           ○ blocked       │
   └──────────────────────────────────────────────────────────────┘
      Stock value on the report equals stock value in the ledger.
      NEEDS fix receiving-to-journal · reconcile inventory to control ·
            authorise and build governed costing chronology ·
            activate FIFO and moving average replay
      GIVES a trustworthy cost of sales and gross margin
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 4 — CASH AND ASSETS                   ○ not started   │
   └──────────────────────────────────────────────────────────────┘
      Bank, petty cash, disbursement, and capital assets.
      NEEDS exercise all ten banking workflows · bank reconciliation ·
            asset lifecycle · depreciation profiles ·
            book-versus-tax depreciation
      GIVES a complete balance sheet
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 5 — FILE WITH CONFIDENCE              ○ blocked       │
   └──────────────────────────────────────────────────────────────┘
      Every BIR obligation produced from posted data.
      NEEDS statutory return generation · working papers ·
            certificate registers · income tax · percentage-tax
            calculation · complete CAS export artifacts
            (the Tax Engine calculator itself now exists)
      NOTE  the review and reconciliation surfaces already work at
            zero variance — this stage builds the *filing* half
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 6 — DECISION-GRADE REPORTING          ○ not started   │
   └──────────────────────────────────────────────────────────────┘
      Management can steer the business from PXL.
      NEEDS statement structure registry adopted · dimensional
            management reporting · adjusted and post-closing trial
            balance · the executive dashboard as specified
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  STAGE 7 — RUN IT FOR REAL                   ○ not started   │
   └──────────────────────────────────────────────────────────────┘
      NEEDS backup and restore proven · deployment governed ·
            monitoring · notifications · controlled pilot
      GIVES **Production Ready**
```

## 9.1 Roadmap notes a product owner should read

**Stage 0 is nearly free and nobody is claiming it.** Setup and Master Data have a
completed review with zero defects, blocked only on backup evidence and an
automated browser lane. Neither is software. This is the fastest route to PXL's
first certified module and should be prioritised over new capability.

**Stage 2 is the one everybody skips.** Its local build now exists, including
opening settlement through normal Receipts and Payment Vouchers. It still cannot
support a pilot claim until hosted deployment, invite delivery, real cut-over,
browser/UAT and operated recovery are evidenced.

**Stage 5's calculator prerequisite is met; its filing prerequisite is not.**
The Tax Engine shipped on 2026-08-03 (PAD-001), so the eleven duplicated
calculators no longer accumulate risk. What Compliance still cannot do is
produce a statutory artifact: every working paper, return generator and
certificate register is empty, and nothing has ever been filed.

**Stages are not strictly sequential.** Stage 4 (cash and assets) is independent of
Stage 3 (inventory) and can run in parallel. Stage 6 depends on Stages 1, 3, and 4
for its data. Stage 7 depends on everything.

---
# 10. Appendix

## 10.1 Module inventory

| # | Canonical business module | Maturity | Mapped certification scope | Certification | Navigation |
| ---: | --- | --- | --- | --- | --- |
| 1 | Setup | M7 | Setup and Master Data | Blocked | Yes |
| 2 | Master Data | M7 | Setup and Master Data | Blocked | Yes |
| 3 | Sales & Receivables | M4 | Sales and Accounts Receivable | In Progress | Yes |
| 4 | Purchasing & Payables | M4 | Purchasing and Accounts Payable | In Progress | Yes |
| 5 | Inventory | M4 | Inventory | In Progress | Yes |
| 6 | Banking & Treasury | M3 | Banking and Treasury | Not Started | Yes |
| 7 | Fixed Assets | M3 | Fixed Assets | Not Started | Yes |
| 8 | Accounting | M4 | Accounting Core **and** Accounting Schedules | In Progress / Not Started | Yes |
| 9 | Compliance | M4 | Philippine Compliance and Tax | Blocked | Yes |
| 10 | Reports | M4 | Reports and Financial Statements | In Progress | Yes |
| 11 | Administration & Security | M4 | Administration and Security | Not Started | Yes, under Setup ▸ Administration |

**Dashboard** is a cross-product Reporting Surface at M4 with no owning
certification scope. The certification program still has exactly eleven issued
module scopes: it combines product modules 1–2 and splits schedules out of
product module 8. That is an evidence boundary, not a second product taxonomy.

## 10.2 Engine inventory

| # | Engine | Status | User-visible? |
| ---: | --- | --- | --- |
| 1 | Permissions and Security | ✅ **Certified** | No |
| 2 | Audit and Immutability | ✅ **Certified** | Only its log-viewer surfaces |
| 3 | Number Series | ✅ **Certified** | Only its setup surface |
| 4 | Dimension | ✅ **Certified** | Only its dimension masters |
| 5 | Posting Engine | Blocked at inventory reconciliation | No |
| — | *Accounting Kernel (Totality Guard)* | *Fully enforced — a component of #5, not a peer* | **Never** |
| 6 | Chart of Accounts | In Progress | Only its COA and posting-config surfaces |
| 7 | AR | In Progress | Only its ageing surface |
| 8 | AP | In Progress | Only its ageing surface |
| 9 | Payment and Application | In Progress | Only its payment surfaces |
| 10 | Approval and Workflow | In Progress | Only its config and inbox |
| 11 | Period Lock and Closing | In Progress | Only its period-closing surface |
| 12 | Reversal, Void and Correction | In Progress | Only its review surfaces |
| 13 | Reporting and Reconciliation | In Progress | Only the reports it feeds |
| 14 | Attachment and Traceability | In Progress | Tracing exists but has **no menu entry** |
| 15 | Inventory Accounting (IA-5/ECC) | In Progress — **dormant** | **Never** |
| 16 | Document Conversion | Not Started | No |
| 17 | Currency | **Deferred** | Only its currency list |
| 18 | Backup and Recovery | Not Started | No |
| 19 | **Tax Engine** | 🟡 **Implemented, not certified** | No |

## 10.3 Repository inventory

| Dimension | Count |
| --- | ---: |
| Screens (page components) | 175 |
| Route declarations | 179 |
| Navigation leaf entries | 242 |
| — disabled placeholders | 18 |
| — duplicate labels on an already-used route | 55 |
| Distinct routes reachable from navigation | 169 |
| Routes reachable with **no** navigation entry | 2 |
| Transaction workspace registry entries | 41 |
| — source-reviewed workspaces | 1 (Sales Invoice) |
| — transaction-matrix-only workspaces | 40 |
| Reachable routes backed only by deferred tables | 33 |
| Data structures (base tables) | 202 |
| — exercised with real data | 93 |
| — deliberately empty or deferred | 109 |
| — of which: unimplemented future modules | 61 |
| — of which: dormant inventory chronology | 20 |
| Reporting views | 23 |
| Business rules and routines | 398 |
| Automatic guards and triggers | 324 |
| Automated test files | 110 |
| Documentation domains | 14 |
| Open defects | **0** (93 of 93 retested and passed) |

## 10.4 High-level statistics

All figures below were **re-measured against the repository and a live canonical
database on 2026-08-02**. The previous edition of this section carried five
counts that no longer matched the code; they are corrected here rather than
restated.

**Certification**

```text
   Certified modules          0 of 11    ░░░░░░░░░░
   Certified engines          4 of 19    ██░░░░░░░░
   Certified work packages    4 of  9    ████░░░░░░   (dormant inventory only)
   Critical reconciliations   1 of  9    █░░░░░░░░░   evidenced (inventory→control, test 111)
   Open defects               0 of 93    ██████████   all retested and passed
```

**Implementation census** (live database, 176 migrations applied)

```text
   Tables                          209   all 209 RLS-enabled; 0 without a policy
   Tables holding data              93   ← 45%; 116 have never held a row
   Views                            23
   Functions                       437
   User triggers                   627
   RLS policies                    519
   pgTAP files / assertions   116 / 2,709
   Frontend source tests            60
```

**Posting reach — the honest completion measure**

```text
   Posting entry points defined     24   fn_post_* functions
   Entry points that have posted    12   SI, OR, VB, PV, RR, CP, CM, VC,
                                          INV_ADJ, INV_COUNT, manual JE, reversal
   Never produced a journal         12   check voucher, fund transfer, bank
                                          adjustment, petty cash, goods issue,
                                          inter-branch transfer, stock transfer,
                                          depreciation, amortisation, revenue
                                          recognition, WHT remittance, debit memo
```

**Product surface honesty**

```text
   Navigation leaf entries         247
   Entries carrying a route        230
   Disabled placeholders            17   ← nav labels with no page at all
   Distinct routes behind nav      175   ← 55 entries are duplicate labels
   Routes declared in App.tsx      185
   Deferred routes ("Not built")    30   ← finished screens over empty tables
   Routes backed by real data      145
```

**Reading these figures.** Counting menu entries overstates delivered capability
by roughly forty percent. The honest surface count is **145 routes backed by real
data**, not 247 menu entries. This is not a criticism of the navigation — it is a
consequence of PXL deferring by *building the whole surface then leaving the data
empty*, which is defensible engineering but invisible to a user. The product now
labels those 30 routes "Not built" in the navigation itself.

## 10.5 Requirements the blueprint asked for that PXL still owes

Carried forward deliberately (see §8.7 rule 4). None of these is discarded.

| Requirement | Product state | Standing |
| --- | --- | --- |
| **CAS Registrations** | **DESIGN ONLY** | No home for BIR accreditation, permit, or machine identification data. Material for a CAS-accredited ERP. |
| **Depreciation Profiles** | **DESIGN ONLY** | Absent. Depreciation policy has no governed master. |
| **Adjusted / Post-Closing Trial Balance** | **DEFERRED** | Cannot be produced — no closing entries, close not certified. |
| **Executive dashboard widget grid** | **DEFERRED** | Storage exists and is seeded; no screen uses it. |
| **Module feature settings** (inventory, fixed assets, petty cash, bank reconciliation) | **DEFERRED** | Only global enablement exists; per-module policy cannot be configured. |
| **Budgeting** | **FUTURE ROADMAP** | No data model anywhere in PXL. |
| **Notifications** | **FUTURE ROADMAP** | No data model, no messaging, no email. Approval routing notifies nobody. |
| **Configurable document and validation rules** | **BACKEND FOUNDATION ONLY** | Rules are enforced but seeded — eight setup screens are permanently disabled because nothing can author them. |

## 10.6 Navigation summary

| Top-level domain | Groups | Leaf entries | Feature-gated | Notes |
| --- | ---: | ---: | --- | --- |
| Dashboard | 0 | 0 | No | Direct link, no submenu |
| Setup | 8 | 49 | No | Contains most of the 17 disabled placeholders plus the Administration group |
| Master Data | 5 | 12 | No | Owns Bank Accounts, Warehouses and Master Data Import |
| Sales | 4 | 16 | `accounts_receivable` | — |
| Purchasing | 4 | 14 | `accounts_payable` | — |
| Inventory | 3 | 9 | `inventory_management` | Duplicates Warehouses from Master Data |
| Banking & Treasury | 3 | 11 | `banking_module` | Every leaf unexercised |
| Fixed Assets | 3 | 8 | `fixed_assets` | Every leaf unexercised |
| Accounting | 5 | 18 | No | Tracing exists but is not in this menu |
| Compliance | 6 | 67 | No | Largest domain; bimodal (real reviews / empty generators) |
| Reports | 10 | 43 | No | 31 leaves re-point into other domains |
| **Total** | **51** | **247** | 5 gated | Administration is grouped under Setup |
| **Administration module** | — | 4 | No | Restricted screens counted under Setup; not a separate top-level menu |

**Feature gating.** Five top-level domains are switched on or off per company by
Feature Enablement. Setup, Master Data, Accounting, Compliance, and Reports are
always visible. A company with inventory disabled therefore never sees the
Inventory menu at all — which is the correct behaviour and a genuine strength.

---

# 11. Canonical Determination Record

The three questions a governance reader needs answered directly.

## 11.1 What changed from the original blueprint

| Change | Extent |
| --- | --- |
| **Dissolved** | The "Assets" parent → three independent top-level domains |
| **Merged away** | EWT Codes and FWT Codes → ATC Codes · Services → Items · four customer/supplier profile entities → columns on the party masters |
| **Renamed** | 10 items, including four transactions that had accumulated two or three names each |
| **Moved** | 5 items, most consequentially Bank Accounts (Setup → Master Data) and ATP Monitoring (Setup → Compliance) |
| **Added** | ~19 material components the blueprint had no vocabulary for, including the sealed ledger doorway, four certified engines, coverage governance, and the entire certification programme |
| **Still owed** | 10 blueprint requirements never built (§10.5) |
| **Unchanged** | ~60 leaf items, including the entire Compliance domain shape and the four core transactions |

## 11.2 What is now canonical

1. **This document** is the canonical product architecture. The original blueprint
   is historical reference.
2. **Eleven canonical business modules plus the Dashboard reporting surface**, as
   structured in §2 — with Assets dissolved, Administration & Security
   recognised as a real (unbuilt) module, and Dashboard explicitly not counted
   as a business or certification module.
3. **Nineteen engines**, four certified, none non-existent since PAD-001 — with
   the Accounting Kernel recorded as a *component* of the Posting Engine, not a
   peer.
4. **The canonical naming record** in §8.6 governs every future document, menu
   label, and status report.
5. **The M0–M9 maturity ladder** in §6.1 is the only vocabulary for
   describing how complete anything in PXL is.
6. **The certification counts** in §7.8 are the headline — no single percentage
   may replace them.
7. **Payroll is a future separate product outside current PXL ERP scope** and
   must not appear in any PXL completion metric.

## 11.3 What still requires an architectural decision

### 11.3.1 Decisions settled by repository evidence

| Decision | Canonical conclusion |
| --- | --- |
| Cash Sale versus Official Receipt | **Distinct concepts.** Cash Sale is the immediate-settlement sales transaction; Official Receipt is the customer collection document. Neither is an alias of the other. |
| Product-level production readiness | **M9 plus the universal Product Definition of Done in the subordinate roadmap.** Certification alone is insufficient; hosted parity, backup/restore, monitoring/support, security, UAT and release evidence are mandatory. |
| Accounting Kernel status | A hidden Totality Guard component inside the Posting Engine, never a peer engine or module. |
| Tax Engine current state | **Implemented at M5** under PAD-001 (2026-08-03). Tax calculation is centralised in `fn_calculate_tax`; percentage tax is out of scope until a document calls it. |
| Payroll | Future separate product, outside current PXL ERP scope and metrics. |

### 11.3.2 Outstanding Product Architecture Decisions register

Open decisions are recorded rather than guessed; decided rows remain for durable
product boundaries. “Stop” applies only to implementation that depends on an
unresolved decision; unrelated governed work may continue.

| Decision ID | Question | Why it matters | Available options | Current evidence | Required owner | Required decision milestone | Consequence of deferral | Implementation stop? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **PAD-001 — DECIDED 2026-08-03** | The Tax Engine is Accounting-owned and is exactly one calculator. | Eleven routines each held their own copy of the Philippine tax rules, and only one of them handled VAT-inclusive pricing. | **Selected:** `fn_calculate_tax(context) → SETOF tax_component`, hidden behind the document-save layer; it calculates and returns components, it never posts and never persists. VAT (both price bases) and withholding by ATC (EWT/FWT) are in scope; **percentage tax is explicitly out** until a document calls it. | Migration `20260803000001`; guard `117` (31 assertions on a self-provisioned company); `090` re-scoped to assert one calculator and zero in the posting layer, its output assertions unchanged. | Product Owner + Chief Accounting Architect | Decided during Delivery Plan Phase 4 | Percentage-tax companies still have no calculated PT; filing (Phase 5.8) still unbuilt. | **Resolved** for the calculator. Compliance M5+ still gated on the filing artifacts, not on this. |
| **PAD-002 — DECIDED 2026-08-02** | PXL supports existing businesses through one governed PHP-only cut-over batch. | Opening GL, AR/AP, inventory and bank positions must reconcile by construction; fixed assets remain outside the current cut-over. | **Selected:** full governed opening-balance workflow with preview/save/post/reverse, one balanced Kernel journal, explicit subledger detail and ordinary AR/AP settlement. | Migration `20260802000002`; UI route; fresh guards 113 and 116 prove cut-over, controls, settlement, reversal and IA-5 dormancy. | Product Owner + CPA Owner | Decided during Delivery Plan Phase 3 | Hosted/real-company/browser/UAT proof remains required before pilot. | **Resolved** for implementation; operational evidence still gates pilot readiness. |
| **PAD-003 — DECIDED 2026-08-02** | Administration & Security is a restricted in-product module backed by the existing engines. | Users, memberships, roles and branch scope require a company-scoped product surface without exposing service credentials. | **Selected:** four restricted screens plus a server-side invite boundary; Permissions/Audit remain engine-owned. | Migration `20260802000004`, four routes, `admin-invite` Edge Function and guard 115; owner protections are database-enforced. | Product Owner + Security Owner | Decided during Delivery Plan Phase 3 | Hosted invite/browser/UAT and operating access review remain required. | **Resolved** for local implementation; no hosted or readiness claim. |
| **PAD-004** | Which module owns Bank Reconciliation and its adjustment boundary? | The workflow crosses Treasury, Accounting and the sealed posting perimeter. | Banking-owned with Accounting engine controls; Accounting-owned; split with an explicit hand-off | Banking is M3; `bank_recon_items` is a recorded UI-write exception. | Product Owner + CPA Owner | Before any Bank Reconciliation implementation (Delivery Plan Phase 8, v2) | One-sided adjustments or ambiguous responsibility | **Yes** for Bank Reconciliation implementation |
| **PAD-005** | What is the supported multi-currency boundary? | Current labels can be mistaken for FX support. | PHP-only current product; selected transaction currencies; full FX/revaluation roadmap | Currency list exists; exchange rates are empty; Sales Invoice fails closed outside PHP. | Product Owner + CPA Owner | Before any non-PHP customer commitment | Incorrect posting, revaluation or reporting promises | **Yes** for non-PHP transaction work; no for PHP-only work |
| **PAD-006** | What exact governance event permits Inventory Accounting production activation? | Dormant ECC structures must not populate prematurely. | Post-WP-9 evidence gate plus explicit source activation; later IA-6 gate; keep dormant | WP-1…WP-4 are certified; WP-5 rejected; C-01 open; production source types disabled. | Product Owner + Inventory Accounting Owner | Before any production source type or IA-6 activation | Dormancy continues; no trustworthy replay costing | **Yes** for activation, source enablement and IA-6 |
| **PAD-007 — DECIDED 2026-08-02** | PXL operates **self-managed encrypted backups replicated to S3-compatible object storage**, drilled weekly. | M9 and every module's operational gate require recoverability. | **Selected:** self-managed offsite to S3-compatible storage (R2/B2/S3), keeping the backups in a different failure domain from the database vendor. Provider-native PITR is **not** adopted for the pilot; the 24h pilot RPO is met by the daily cycle, and the 1h production RPO remains an open commitment to revisit before any production claim. | Implemented and proven 2026-08-02: `npm run backup:operate` runs backup → restore-verify → encrypted replication with read-back → retention → journal, fails closed at every stage, and the **replicated** copy restored independently (93 tables, 0 mismatches, 6s). `npm run backup:offsite:check` proves a destination's write/read/byte-fidelity/delete with a canary holding no client data. `.github/workflows/backup-drill.yml` runs both weekly. | Product Owner + Operations/Security Owner | Decided during Delivery Plan Phase 2 | — | **Resolved** for the operating model and mechanism. **Still Yes** for any *operated* or M9 claim: no bucket is configured, no passphrase is escrowed, the schedule has never fired, and no PXL database holds real books. |
| **PAD-008** | What attachment/document-management scope belongs in PXL? | Every workspace shows an Attachments tab without a working file lifecycle. | Governed attachments in PXL; external document system link; explicitly unsupported | Trace works; attachment register is future-deferred and empty. | Product Owner + Security/Audit Owner | Before any transaction module certification | Audit evidence remains incomplete or misleading | **Yes** for module certification where attachments are mandatory |
| **PAD-009** | Is configuration of status, posting, void, reversal and validation rules in product scope? | Eight placeholders imply configurability while rules are code/seed governed. | One governed rules console; configuration remains implementation-owned; selective configuration | Enforcement exists; authoring surfaces do not. | Product Owner + Architecture Owner | Before the Delivery Plan Phase 6 UX scope freeze | Persistent misleading placeholders and customization ambiguity | **Yes** for rule-configuration UI only |
| **PAD-010** | Is the merged AR/AP ageing surface the canonical accounting subsidiary ledger? | Operational ageing and accounting control/cut-off views have different proof duties. | One certified dual-purpose surface; separate accounting ledger; shared data with distinct views | One route serves all aliases; as-of and reconciliation RPCs exist but module certification is incomplete. | CPA Owner | Before Delivery Plan Phase 5 exit | Reconciliation ownership remains ambiguous | **Yes** for declaring Sales/Purchasing complete |
| **PAD-011** | Where does CAS accreditation/registration data live? | A PH CAS product needs an explicit system of record or external boundary. | PXL Setup; Compliance workspace; external register with governed reference | Numbering/ATP evidence exists; no CAS registration data model exists. | Product Owner + Compliance Owner | Before Delivery Plan Phase 4 exit | CAS readiness remains incomplete | **Yes** for CAS production-readiness claim |
| **PAD-012** | How should deferred surfaces be presented? | Thirty-three routes are backed only by future-deferred tables. | Hide; label Coming Later; feature-gate from coverage authority | Routes/pages exist; deferral is visible only in governance docs. | Product Owner + UX Owner | Before pilot UX review | Users continue to mistake scaffolds for working features | **Yes** for navigation redesign; no for backend work |
| **PAD-013** | Are notifications part of current PXL ERP? | Approval routing and deadlines may otherwise require manual polling. | In-app; email/in-app; explicitly external/out of scope | No notification model, integration or test exists. | Product Owner | Before Approval rollout or the Delivery Plan Phase 6 scope freeze | Usability limitation persists | **Yes** for notification implementation only |
| **PAD-014** | Does Reports remain a convenience index or become cross-domain reports only? | Thirty-one of forty-three labels redirect to module-owned surfaces. | Convenience index with explicit links; cross-domain only; remove domain | Current navigation mixes both silently. | Product Owner + UX Owner | Before Delivery Plan Phase 6 exit | Duplication and ownership ambiguity persist | **Yes** for navigation redesign only |

---

# 12. Authority and Maintenance

## 12.1 What this document is

The **product** constitution of PXL: what exists, what it is for, how mature it
is, and what is deliberately not built. It is the first document any contributor —
human or AI — should read before touching modules, menus, scope, roadmap,
progress reporting, or architectural naming.

## 12.2 What this document is not

It is **not** an implementation specification, a certification decision, a defect
register, a task list, or a licence to build anything. It records the
architecture; it does not authorise work.

## 12.3 Authority order

When sources disagree, resolve in this order:

1. **Executed system behaviour** and current test results.
2. **This document**, for what PXL *is* — modules, engines, naming, maturity and scope.
3. **`PXL_PRODUCT_EXECUTION_ROADMAP.md`**, for dependency-driven planning,
   definition of done, roadmap and executive maturity reporting. It is
   subordinate and cannot change product scope.
4. **`PXL_CERTIFICATION_MATRIX.md`**, for certification status.
5. **`PXL_TABLE_COVERAGE_MATRIX.md`**, for what data is exercised versus deferred.
6. **`PXL_END_TO_END_AUDIT_FINDINGS.md`**, for defects.
7. **`AI/AI_STATE.md`**, for the current bounded task.
8. **Domain specifications**, for implementation detail.
9. **The original product blueprint**, as historical reference only.

If this document and executed behaviour disagree, **this document is the defect**
and must be corrected — never the other way round.

## 12.4 When to update this document

Update it when a module is added, removed, renamed, split, or merged; when an
engine changes lifecycle status; when a module changes maturity level; when a
naming decision is made; when scope enters or leaves the product; or when one of
the nine open decisions in §11.3 is settled.

Do **not** update it for implementation detail, defect status, task progress, or
individual work packages — those have their own registers.

## 12.5 Change control

- Any change to product scope, module ownership, engine taxonomy, canonical
  naming, product boundaries, or the M0–M9 model requires a governed **Product
  Architecture Amendment** to this document.
- An Engineering Amendment may refine an authorised implementation contract but
  may not silently add, remove, rename, split, merge, activate or reassign a
  product capability.
- The Product Execution Roadmap may resequence work when evidence changes, but it
  may not override this constitution.
- Issued designs, decisions, audits and certification records retain their
  chronology. A correction is recorded prospectively in this document and the
  old record is described as historical or superseded; it is not rewritten as if
  the corrected position always existed.
- Every AI agent must read this document during startup before implementation,
  scope, navigation, roadmap or maturity work.

## 12.6 Non-authority statement

This document records the current canonical product architecture. Creating it
**changed no repository behaviour**: no source code, database structure,
migration, test, screen, route, navigation entry, or certification status was
modified. Nothing in it authorises, certifies, or de-certifies anything. Every
recommendation it contains is advisory until adopted by a properly authorised
decision.

**PXL remains not production-ready and not pilot-ready, suitable for internal QA
and demonstration only.**
