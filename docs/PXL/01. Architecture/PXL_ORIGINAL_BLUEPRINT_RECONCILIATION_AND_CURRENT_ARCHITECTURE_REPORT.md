# PXL Original Blueprint Reconciliation and Current Architecture Report

**Status:** Advisory architecture reconciliation — non-authoritative
**Authority:** None. This report proposes; it does not amend.
**Owner / Domain:** Architecture
**Applies To:** The original PXL ERP blueprint tree versus the current repository
**Read When:** Reconciling the original product blueprint against current repository reality, or planning a governance/taxonomy mission
**Do Not Read For:** Certification status (use `../13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md`), current bounded task (use `AI/AI_STATE.md`), navigation authority (use `src/components/AppShell.tsx`), or accounting rules (use `../02. Accounting Core/`)
**Date:** 2026-07-31
**Base commit:** `4aef8b3` (working tree dirty; all pre-existing changes preserved)

> **This report is advisory. It does not amend repository architecture, navigation, scope, certification, or implementation authority.**

---

## 1. Executive Summary

### 1.1 What was reconciled

Every leaf item of the original PXL ERP blueprint tree (**256 leaf items** across nine top-level
domains) was reconciled line by line against the current repository: 175 React pages, 179 route
declarations, 242 navigation leaf entries, 202 `public` base tables, 23 views, 398 functions,
324 triggers, 110 pgTAP test files, and the full governance register set.

### 1.2 The seven findings that matter

**F-1 — The blueprint is substantially present, but presence is mostly *surface*, not *supported workflow*.**
Of 256 original leaf items, only **4** sit inside any formal certification scope — the four Number
Series setup nodes, and even there what is certified is the **Number Series Engine allocator**, not
the setup surface and not a module. **No PXL module is Certified.** Meanwhile **65 leaf items
(25.4%) are UI / route only**, and **33 reachable routes are backed exclusively by tables the
coverage matrix classifies as unimplemented future modules**. A user can navigate to the Fixed Asset
Dashboard, the Depreciation Run, every Income Tax return, every compliance working paper, and the
CAS DAT File Generation page — and every one of them reads a governed-empty table.

**F-2 — The original "Assets" parent node has already been dissolved in the running product, and the
documentation has not caught up.** The blueprint places Cash Management, Inventory, and Fixed Assets
under a single `6. Assets` parent. The shipped navigation has **three independent top-level domains**
— `Inventory`, `Banking & Treasury`, `Fixed Assets` — each feature-gated separately
(`inventory_management`, `banking_module`, `fixed_assets`). The repository has already made the
architectural decision; no document records it. This is the single largest taxonomy divergence.

**F-3 — Navigation systematically overstates completion.** 242 navigation leaf entries resolve to only
**169 distinct routes**. 55 entries are duplicate labels pointing at an already-used route
(`tax-setup` carries 6 labels; `sales-registers` 5; `trial-balance`, `number-series`, `item-catalog`,
`ar-aging`, `ap-aging`, `inventory-movements` 4 each). A further **18 entries are permanently
disabled placeholders** with no page at all. Counting menu entries as delivered features inflates the
product by roughly 30%.

**F-4 — There is no Tax Engine, and the blueprint never asked for one.** The original tree has a
`Tax Setup` node and a large `Compliance` domain, but no engine. The repository confirms the same
absence at runtime (test `090`, Posting Engine P4): no tax-engine function, no `TaxComponent` type,
and the same VAT computation duplicated across **seven** document-save calculators. The certification
matrix records Tax Engine as *Blocked — does not exist*. The gap is architectural and sits *above*
the Posting Engine; it is invisible in the original blueprint and must be added to any current one.

**F-5 — Substantial certified and near-certified infrastructure exists that the blueprint never
named.** The Posting Engine (P1–P5.2 with a fully enforced Kernel Totality Guard), the COA Engine
(Phase A), the Permissions/RLS, Audit & Immutability, Number Series and Dimension Engines (all four
Certified), source-to-journal traceability (`/accounting-trace`, `/accounting-source` — reachable
routes with **no navigation entry at all**), the coverage-governance guard `075`, and the entire
IA-5/ECC dormant chronology foundation (20 `dormant-foundation` tables, WP-1…WP-4 certified) are all
repository additions absent from the original blueprint. Several of these are the *strongest* assets
in the product and none of them is visible to a user or to the headline progress figure.

**F-6 — Inventory is two different things wearing one name.** The user-facing **Inventory module**
(stock balances, movements, adjustments, transfers, physical count — canonically populated, exercised)
and the **Inventory Accounting Engine / IA-5 ECC chronology foundation** (dormant, zero rows, zero
consumers, four certified work packages, blocked at WP-5) share the label "Inventory" in the
certification matrix, in `AI_PROGRESS.md`, and in conversation. They have different lifecycles,
different evidence, and different readiness. The 44% "Inventory Engine" bar in `AI_PROGRESS.md`
measures the *dormant* one; a reader will assume it measures the visible one.

**F-7 — The 42% headline is a weighted average of certification statuses, not product completion, and
its inputs are not comparable.** It averages 11 modules and 19 engines on a Certified/In Progress/
Blocked/Not Started scale. It gives Payroll a row (0%) although Payroll is not a PXL module and has
no repository evidence beyond one comment line. It gives the Accounting Kernel 100% for a guard-scope
certification. It gives Inventory 44% from a work-package ratio of a dormant foundation. A single
number cannot carry those meanings; §11 recommends replacing it with nine exact counts.

### 1.3 The blueprint reconciliation in one table

| Primary status | Leaf items | Share |
| --- | ---: | ---: |
| ✅ CERTIFIED BOUNDED SCOPE | 4 | 1.6% |
| 🟢 IMPLEMENTED AND SOURCE-BACKED | 119 | 46.5% |
| 🟡 PARTIALLY IMPLEMENTED | 57 | 22.3% |
| 🔵 UI / ROUTE ONLY | 65 | 25.4% |
| 🟣 DOCUMENTATION / DESIGN ONLY | 7 | 2.7% |
| ⚪ FUTURE / DEFERRED | 0 | 0.0% |
| 🔴 MISSING / NO RELIABLE EVIDENCE | 2 | 0.8% |
| ⚫ SUPERSEDED / REMOVED | 2 | 0.8% |
| **Total** | **256** | **100%** |

Per top-level domain:

| Domain | Leaves | ✅ | 🟢 | 🟡 | 🔵 | 🟣 | 🔴 | ⚫ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1. Dashboard | 1 | | | 1 | | | | |
| 2. Setup | 45 | 4 | 15 | 15 | 2 | 6 | 1 | 2 |
| 3. Master Data | 18 | | 12 | 5 | | | 1 | |
| 4. Sales | 20 | | 12 | 6 | 2 | | | |
| 5. Purchasing | 18 | | 12 | 3 | 3 | | | |
| 6. Assets | 28 | | 7 | 1 | 19 | 1 | | |
| 7. Accounting | 17 | | 9 | 3 | 5 | | | |
| 8. Compliance | 66 | | 28 | 14 | 24 | | | |
| 9. Reports | 43 | | 24 | 9 | 10 | | | |
| **Total** | **256** | **4** | **119** | **57** | **65** | **7** | **2** | **2** |

Three readings of this table matter more than the totals.

- **⚪ FUTURE / DEFERRED is empty, and that is the finding.** PXL never defers a blueprint item by
  leaving it out. It defers by shipping a route, a page, and a full table set, then classifying the
  table `future-deferred` in a governance register the user never sees. Deferral in this product is
  invisible from the screen. That is precisely why 🔵 (65) is the second-largest bucket, and why
  §12 P0-1 recommends making deferral visible in navigation rather than only in a matrix.
- **Assets is the worst domain by a wide margin**: 19 of its 28 leaves are 🔵 — the entire Cash
  Management branch (10/10) and the entire Fixed Assets branch (8/9). Both are fully navigable and
  entirely unexercised.
- **Compliance is the largest domain (66 leaves, 26% of the blueprint) and is bimodal**: 28 leaves
  are genuinely source-backed (VAT reviews, BIR books over posted data, CAS audit logs), while 24
  are route-only shells (every working paper, every income tax computation, every statutory return
  generator). The domain's average tells you nothing; only the split does.

### 1.4 What must not be concluded from this report

- A route is not an implementation. 79 leaf items are 🔵 UI / ROUTE ONLY.
- A table is not a supported workflow. 61 base tables are `future-deferred` and 20 are
  `dormant-foundation`; both are empty by design and enforced empty by guard `075`.
- A test is not a module certification. 110 pgTAP files exist; no module is Certified.
- A work-package certification is not Inventory Engine certification. WP-1…WP-4 certify four bounded
  dormant change sets; C-01 remains open and the IA-5 permanent-foundation claim remains suspended.

---

## 2. Scope and Evidence

### 2.1 Mission type and boundary

Architecture reconciliation, read-only. No implementation, coding, migration, database, certification,
work-package authorisation, WP-5 Engineering Amendment, UI change, menu change, or repository
restructuring was performed. Exactly two files were written: this report and `AI_LAST_SESSION.md`.

### 2.2 Mandatory reading actually performed

| # | Required source | Status |
| --- | --- | --- |
| 1 | `AI/AI_STATE.md` | Read |
| 2 | `AI_LAST_SESSION.md` | Read |
| 3 | `AI_PROGRESS.md` | Read |
| 4 | **The completed PXL ERP Master Architecture Conformance Review** | **NOT FOUND — see §2.3** |
| 5 | `PXL_DOCUMENTATION_INDEX.md` | Read |
| 6 | `PXL_CERTIFICATION_MATRIX.md` | Read |
| 7 | `PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` | Read (purpose, gate mapping, phase reference) |
| 8 | `PXL_TABLE_COVERAGE_MATRIX.md` | Read in full (all 202 table rows) |
| 9 | `PXL_SCHEMA_SUMMARY.md` | Read (398 functions / 23 views / 202 tables / 324 triggers) |
| 10 | `PXL_TRANSACTION_MATRIX.md` | Read (orientation + all 50 transaction rows, status column) |
| 11 | Current menu/navigation definitions | `src/components/AppShell.tsx` read in full |
| 12 | Current application routes | `src/App.tsx` read in full |
| 13 | Transaction workspace coverage registry | `src/lib/transactionWorkspaceCoverage.ts` read in full |

### 2.3 Required baseline artifact does not exist — declared, not worked around

The mission instructs this reconciliation to "use the completed *PXL ERP Master Architecture
Conformance Review* as the factual evidence baseline" and not to repeat its repository census.

**No document by that name, or any recognisable equivalent, exists in this repository.** An
exhaustive search for `*CONFORMANCE*` and `*MASTER_ARCHITECTURE*` across the whole tree returns zero
files. The word "conformance" appears only as an adjective inside seven unrelated documents (UI
conformance, ADR-C01 §17 conformance evidence, ECC-01 conformance surface). `PXL_DOCUMENTATION_INDEX.md`
registers no such review, and neither `AI/AI_STATE.md` nor `AI_LAST_SESSION.md` records a mission that
produced one.

**Consequence and mitigation.** Because the named baseline is absent, the evidence baseline for this
mission was rebuilt directly from primary repository sources rather than inherited. This is a
*strengthening* substitution, not a weakening one — every conclusion below is anchored to executable
artifacts (migrations, page source, route table, navigation array, coverage classes, test files)
rather than to a prior report's summary. The cost is that this mission necessarily performed the
census the instruction hoped to avoid. **This absence is itself a governance finding** (see §10.E and
§12, P0-3): a mission-critical baseline was assumed to exist and does not.

### 2.4 Evidence method

Five independent evidence classes were collected and are kept distinct throughout:

1. **UI evidence** — navigation entry (`AppShell.tsx` `NAV` array, 242 leaves), route declaration
   (`App.tsx`, 179 `<Route>` elements), page component (`src/pages/*.tsx`, 175 files).
2. **Database evidence** — base table and its **coverage class** from `PXL_TABLE_COVERAGE_MATRIX.md`
   (the decisive signal: `canonical-populated` and `reference-populated` are exercised;
   `future-deferred`, `dormant-foundation`, `reference-empty` and `control-empty` are governed-empty);
   view; function; trigger; RLS; grants.
3. **Runtime evidence** — every `.from('table')` and `.rpc('fn_*')` call was extracted from all 175
   page components and cross-joined against the coverage classes. A page that calls a posting RPC
   against canonical tables is source-backed; a page that only selects from `future-deferred` tables
   is a rendered shell.
4. **Testing evidence** — the `Test` column of the coverage matrix, the pgTAP file numbers named in
   the certification matrix, and the canonical/regression lane results recorded in `AI/AI_STATE.md`.
5. **Governance evidence** — module lifecycle and engine lifecycle from `PXL_CERTIFICATION_MATRIX.md`,
   work-package certification chronology, deferred classification from the coverage matrix's
   Deferred-Module Register, and the production boundary from `AI/AI_STATE.md`.

### 2.5 Decisive quantitative facts established by this mission

| Fact | Value | Source |
| --- | ---: | --- |
| Original blueprint leaf items reconciled | 256 | This report §3 |
| React page components | 175 | `src/pages/` |
| Route declarations | 179 | `src/App.tsx` |
| Navigation leaf entries | 242 | `AppShell.tsx` `NAV` |
| — of which **disabled placeholders** (no page) | **18** | `s('Label')` with no page argument |
| — of which **duplicate labels** on an already-used route | **55** | 224 enabled entries → 169 distinct routes |
| Distinct routes reachable from navigation | 169 | `AppShell.tsx` |
| Routes reachable with **no navigation entry** | 2 | `/accounting-trace`, `/accounting-source` |
| `public` base tables | 202 | `PXL_SCHEMA_SUMMARY.md` |
| — expected-populated (`canonical-` + `reference-populated`) | 93 | Coverage matrix |
| — explicitly deferred or empty | 109 | Coverage matrix |
| — `future-deferred` (unimplemented module) | 61 | Coverage matrix |
| — `dormant-foundation` (IA-5/ECC, prohibited from populating) | 20 | Coverage matrix |
| **Reachable routes backed *only* by deferred tables** | **33** | Page-to-table cross-join, §6.3 |
| Views / functions / triggers | 23 / 398 / 324 | `PXL_SCHEMA_SUMMARY.md` |
| pgTAP test files | 110 | `PXL_SCHEMA_SUMMARY.md` |
| Certified modules | **0 of 11** | `PXL_CERTIFICATION_MATRIX.md` |
| Certified shared engines | **4 of 19** | `PXL_CERTIFICATION_MATRIX.md` |
| Certified Inventory ECC work packages | **4 of 9** | Certification chronology |
| Open audit findings | 0 (92 of 92 Retested Passed) | `AI/AI_STATE.md` |

### 2.6 Status legend used in §3

| Symbol | Meaning as applied here |
| --- | --- |
| ✅ | CERTIFIED BOUNDED SCOPE — a formal certification covers this exact scope. Bounded; implies nothing broader. |
| 🟢 | IMPLEMENTED AND SOURCE-BACKED — executable UI + exercised (canonical/reference-populated) data + runtime path. Not certified. |
| 🟡 | PARTIALLY IMPLEMENTED — material parts exist; the complete business workflow is not supported. |
| 🔵 | UI / ROUTE ONLY — page/route exists; backing tables are governed-empty or runtime evidence is absent. |
| 🟣 | DOCUMENTATION / DESIGN ONLY — specified in an active blueprint document; not executable. |
| ⚪ | FUTURE / DEFERRED — explicitly future, deferred, scaffolded, unauthorised, or outside the active phase. |
| 🔴 | MISSING / NO RELIABLE EVIDENCE — conceptually still relevant; no reliable repository evidence. |
| ⚫ | SUPERSEDED / REMOVED — intentionally replaced, merged, archived, or removed. |

Change flags: `[UNCHANGED]` `[RENAMED]` `[MOVED]` `[SPLIT]` `[MERGED]` `[NEW REPOSITORY ADDITION]`
`[DEFERRED]` `[DUPLICATED]` `[SUPERSEDED]` `[OUT OF CURRENT SCOPE]` `[UI AHEAD OF BACKEND]`
`[BACKEND AHEAD OF UI]` `[NEEDS ARCHITECTURAL DECISION]`

### 2.7 Evidence-block abbreviations used in §3

`UI` = navigation entry / route / page · `DB` = base tables with coverage class
(`cp` canonical-populated, `rp` reference-populated, `wd` workflow-deferred, `fd` future-deferred,
`df` dormant-foundation, `re` reference-empty, `ce` control-empty) · `RT` = runtime RPCs actually
called by the page · `T` = test / certification evidence · `C` = certified · `P` = production-ready ·
`X` = missing or blocked by.

---
## 3. Original Blueprint Item-by-Item Reconciliation Tree

The complete original tree is reproduced below. Every leaf carries a status, change flags, current
name/location, and a compact five-class evidence block. Abbreviations are defined in §2.7.

### 3.1 — `1. Dashboard`

```text
PXL ERP
│
├─ 1. Dashboard
│     🟡 PARTIALLY IMPLEMENTED   [RENAMED] [BACKEND AHEAD OF UI]
│     Now: "Executive Dashboard" · /dashboard · DashboardPage.tsx
│     UI  top-level nav button (not a menu leaf); route present; page renders
│     DB  reads companies·branches·customers·suppliers·items·chart_of_accounts·
│         number_series·approval_workflows·tax_calendar_events·compliance_profiles·
│         currencies·fiscal_years·tax_codes  (all cp/rp — real data)
│         DOES NOT read dashboard_layouts (rp,1) or dashboard_widgets (rp,4)
│     RT  read-only aggregation; no RPC; no widget persistence, no layout edit,
│         no global date range, no entity roll-up, no export/import
│     T   no dedicated test; covered only by the hosted report probe sweep
│     C   No   P   No
│     X   The shipped page is a setup-completeness + BIR-deadline monitor. The
│         blueprint's customizable KPI widget grid (cash position, AR/AP aging,
│         VAT estimate, revenue trend, critical-activity list) is not built even
│         though its two persistence tables exist and are reference-seeded.
```

### 3.2 — `2. Setup`

```text
├─ 2. Setup                                   Now: "Setup" (top-level, unchanged)
│  │
│  ├─ Organization
│  │  ├─ Company Setup
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /company-setup · CompanySetupPage.tsx
│  │  │     DB  companies (cp,5) · user_company_memberships (cp,25) ·
│  │  │         ref_rdo_codes (rp,100) · company_provisioning_* (rp,1/10/10)
│  │  │     RT  fn_provision_company, fn_validate_company_provisioning,
│  │  │         fn_grant_creator_company_ownership; guided provisioning wizard
│  │  │         (MDP-08) atomically creates fiscal year + 12 periods (MDP-06)
│  │  │     T   073 (orchestration + rollback); readiness 8/8; canonical lane
│  │  │     C   No — Setup & Master Data is Blocked   P   No
│  │  │     X   Gate 23 backup/restore + RPO/RTO absent; Gate 20 browser
│  │  │         evidence recorded-only. Transaction Matrix status: Partial.
│  │  │
│  │  ├─ Branch Setup
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /branch-setup · BranchSetupPage.tsx
│  │  │     DB  branches (cp,8) · companies · ref_rdo_codes
│  │  │     RT  direct PostgREST writes under can_admin_company; branch feeds
│  │  │         numbering, tax detail, and the certified Dimension Engine
│  │  │     T   Dimension Engine test 080; canonical lane
│  │  │     C   No (branch as a *dimension* is inside the Certified Dimension
│  │  │         Engine scope; the setup surface is not)   P   No
│  │  │     X   Module-level certification not executed. Matrix: Implemented.
│  │  │
│  │  ├─ Department Setup
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED] [MERGED]
│  │  │     /department-setup · DepartmentSetupPage.tsx (label
│  │  │     "Departments & Cost Centers")
│  │  │     DB  departments (cp,13) · branches · companies
│  │  │     RT  hierarchy guards (no self-parent / cross-company parent / cycle),
│  │  │         effective dating, fn_is_valid_dimension
│  │  │     T   080 (43 assertions, Dimension Engine certification)
│  │  │     C   Bounded — Dimension Engine Certified 2026-07-23   P   No
│  │  │     X   Shares one page with Cost Centers (see next).
│  │  │
│  │  ├─ Cost Centers
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     /department-setup (same route as Department Setup)
│  │  │     DB  cost_centers (cp,10)
│  │  │     RT  same guards; propagates to posted journal lines
│  │  │     T   080; cost_center reaches posted JE lines (proven non-vacuous)
│  │  │     C   Bounded — Dimension Engine only   P   No
│  │  │     X   Two blueprint nodes → one surface. This is a deliberate,
│  │  │         reasonable merge but it is undocumented: nothing states that
│  │  │         "Cost Centers" is an alias of the Departments page.
│  │  │
│  │  ├─ CAS Registrations
│  │  │     🔴 MISSING / NO RELIABLE EVIDENCE   [NEEDS ARCHITECTURAL DECISION]
│  │  │     Nav entry exists but is a DISABLED placeholder (no page)
│  │  │     UI  s('CAS Registrations') — no page argument → greyed, unclickable
│  │  │     DB  NO cas_registrations table exists. The only CAS-permit-adjacent
│  │  │         storage is number_series.atp_series_start/_end/_alert_threshold
│  │  │         plus cas_document_number_issuances (cp,215)
│  │  │     RT  none — no permit number, issue date, validity period, machine
│  │  │         identification, or accreditation record can be stored
│  │  │     T   none   C  No   P  No
│  │  │     X   An active blueprint doc exists (03. Master Data/00. Organization
│  │  │         Setup/05. CAS Registrations.md) but no schema. For a
│  │  │         Philippine CAS-compliant ERP this is a substantive gap, not a
│  │  │         cosmetic one: BIR CAS accreditation details have nowhere to live.
│  │  │
│  │  ├─ Company Bank Accounts
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MOVED] [DUPLICATED]
│  │  │     Setup entry is a DISABLED placeholder; the real surface is
│  │  │     Master Data ▸ Banking ▸ Bank Accounts → /bank-accounts
│  │  │     DB  bank_accounts (cp,10) · chart_of_accounts · currencies · ref_banks (rp,14)
│  │  │     RT  BankAccountsPage CRUD; gl_account_id binds each account to COA
│  │  │     T   canonical lane; Transaction Matrix "Bank Account" = Implemented
│  │  │     C   No   P   No
│  │  │     X   The capability moved to Master Data but the Setup placeholder
│  │  │         was left behind disabled — a user looking under Setup concludes
│  │  │         the feature is missing. One of the 18 dead placeholders.
│  │  │
│  │  └─ Compliance Profile
│  │        🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │        /compliance-profile · ComplianceProfilePage.tsx
│  │        DB  compliance_profiles (cp,5) — VAT/PT/EWT/FWT registration, TWA
│  │            status, eFPS group, filing frequencies, income-tax regime,
│  │            corporate rate
│  │        RT  drives tax-code availability, calendar generation, and which
│  │            compliance dashboards/returns are applicable (DEC-005)
│  │        T   canonical; consumed by PT/VAT/WT/IncomeTax dashboards
│  │        C   No   P   No
│  │        X   Philippine Compliance and Tax module is Blocked (Phase 7).
│  │
│  ├─ System Controls
│  │  ├─ Number Series
│  │  │  ├─ Sales Documents
│  │  │  ├─ Purchasing Documents
│  │  │  ├─ Accounting Documents
│  │  │  └─ Compliance Documents
│  │  │        ✅ CERTIFIED BOUNDED SCOPE (all four)   [MERGED] [DUPLICATED]
│  │  │        All four nav labels → ONE page: /number-series · NumberSeriesPage
│  │  │        DB  number_series (cp,264) · ref_document_types (rp,33) ·
│  │  │            cas_document_number_issuances (cp,215) ·
│  │  │            cas_document_void_events (cp,1)
│  │  │        RT  fn_next_document_number(company,branch,code) — FOR UPDATE row
│  │  │            lock, membership-checked, active-only, ATP-bounded, forward-
│  │  │            only evidence bound by 24 fn_bind_cas_document_number triggers;
│  │  │            ~25 document codes consume it
│  │  │        T   079 (17/17 contract guard), 030, 032; concurrency proven
│  │  │            empirically 10×20 → 200 distinct, zero duplicates
│  │  │        C   YES — but ONLY the **Number Series Engine** (3rd Certified
│  │  │            engine, 2026-07-23). This certifies the ALLOCATOR. It does
│  │  │            NOT certify this setup page, and the owning module (Setup &
│  │  │            Master Data) is Blocked.   P   No
│  │  │        X   The blueprint's four document-class groupings do not exist as
│  │  │            separate surfaces — one flat series list serves all four.
│  │  │            Documented limitation: default auto-provisioning (MDP-06)
│  │  │            covers only BIR-registered SI/CS/OR; every other code needs
│  │  │            explicit setup and fails closed if absent.
│  │  │
│  │  ├─ ATP Monitoring
│  │  │     🟡 PARTIALLY IMPLEMENTED   [MOVED] [BACKEND AHEAD OF UI]
│  │  │     Setup entry is a DISABLED placeholder. The live surface is
│  │  │     Compliance ▸ Audit & CAS ▸ ATP Usage Log → /cas-atp-usage-log
│  │  │     DB  number_series.atp_series_start/_end/_alert_threshold ·
│  │  │         vw_cas_atp_usage over cas_document_number_issuances (cp,215)
│  │  │     RT  allocator refuses to issue past atp_series_end; series-shrink and
│  │  │         start/end-consistency guards (20260712000004); usage view renders
│  │  │     T   079; 030; the ATP bound is part of the certified allocator
│  │  │     C   Bounded — the ATP *bound* is inside the Certified Number Series
│  │  │         Engine   P   No
│  │  │     X   atp_alert_threshold is stored but NO alerting, no threshold
│  │  │         dashboard, and no Setup-side monitoring screen exists. The
│  │  │         blueprint asked for monitoring; the product delivers a log.
│  │  │
│  │  ├─ Feature Settings
│  │  │  ├─ Inventory Settings
│  │  │  │     🟣 DOCUMENTATION / DESIGN ONLY   [BACKEND AHEAD OF UI]
│  │  │  │     DISABLED placeholder. Doc: 04. Transaction Framework/00. System
│  │  │  │     Controls/03. Feature Settings/01. Inventory Settings.md
│  │  │  │     DB  company_inventory_config (wd,0) EXISTS with RLS(3) but has
│  │  │  │         no page and is not exercised by the canonical seed
│  │  │  │     RT  none   T  075 only   C  No   P  No
│  │  │  │     X   Table without a surface; costing-method / negative-stock /
│  │  │  │         valuation policy cannot be configured by a user.
│  │  │  ├─ Fixed Assets Settings
│  │  │  │     🟣 DOCUMENTATION / DESIGN ONLY
│  │  │  │     DISABLED placeholder. No table, no page, no RPC. Doc exists.
│  │  │  │     C   No   P   No   X  Fixed Assets module is Not Started.
│  │  │  ├─ Petty Cash Settings
│  │  │  │     🟣 DOCUMENTATION / DESIGN ONLY
│  │  │  │     DISABLED placeholder. No settings table; petty_cash_funds (fd,0)
│  │  │  │     carries per-fund config only. Doc exists.   C No  P No
│  │  │  ├─ Bank Reconciliation Settings
│  │  │  │     🟣 DOCUMENTATION / DESIGN ONLY
│  │  │  │     DISABLED placeholder. No table, no page. Doc exists.
│  │  │  │     X   Banking and Treasury is Not Started (Phase 5).
│  │  │  └─ Budget Settings
│  │  │        🟣 DOCUMENTATION / DESIGN ONLY   [OUT OF CURRENT SCOPE]
│  │  │        DISABLED placeholder. Doc exists, but there is NO budget table
│  │  │        anywhere in the 202-table schema, no budget page, no budget RPC,
│  │  │        and no budget row in the Transaction Matrix or coverage matrix.
│  │  │        X   Budgeting is absent from PXL end to end. It should be stated
│  │  │            as future roadmap, not left as a Setup menu entry.
│  │  │
│  │  │  NOTE — a REPOSITORY ADDITION sits in this group: "Global Feature
│  │  │  Enablement" (/feature-enablement, ref_feature_definitions rp,16 +
│  │  │  sys_feature_enablement re,0) is 🟢 and gates whole top-level menus
│  │  │  (accounts_receivable, accounts_payable, inventory_management,
│  │  │  banking_module, fixed_assets). The blueprint has no such node. See §5.
│  │  │
│  │  └─ Approval Matrix
│  │     ├─ Sales Approval
│  │     │     🟡 PARTIALLY IMPLEMENTED   [MERGED] [RENAMED]
│  │     │     Now: "Unified Approval Workflow" → /approval-workflow
│  │     │     DB  approval_workflows (cp,2) · approval_workflow_steps (cp,2) ·
│  │     │         approval_requests (wd,0) · approval_instances (wd,0)
│  │     │     RT  fn_approve_sales_invoice exists and is called by
│  │     │         SalesInvoicePage — but it is a DIRECT approve, not matrix-
│  │     │         routed. fn_approval_inbox / fn_approve_approval_request /
│  │     │         fn_reject_approval_request exist (MDP-14)
│  │     │     T   074 (MDP-14 foundation)
│  │     │     C   No — Approval and Workflow Engine is In Progress   P  No
│  │     │     X   No sales approval RULE is configured; approval_requests is
│  │     │         empty in canonical. Matrix-driven sales approval is unproven.
│  │     ├─ Purchasing Approval
│  │     │     🟡 PARTIALLY IMPLEMENTED   [MERGED]
│  │     │     Same surface. fn_approve_vendor_bill and fn_approve_purchase_order
│  │     │     exist and are called, again as direct approvals.
│  │     │     C   No   P   No   X  Same as above.
│  │     ├─ Payment Approval
│  │     │     🔵 UI / ROUTE ONLY   [MERGED]
│  │     │     Same surface; NO payment-specific approval RPC and no configured
│  │     │     rule. Payment Vouchers post without matrix approval.
│  │     │     C   No   P   No
│  │     ├─ Journal Approval
│  │     │     🔵 UI / ROUTE ONLY   [MERGED]
│  │     │     Same surface; NO journal approval RPC or rule. fn_post_manual_je
│  │     │     posts directly (gated by fn_assert_manual_postable, not approval).
│  │     │     C   No   P   No
│  │     └─ Master Data Approval
│  │           🟡 PARTIALLY IMPLEMENTED   [MERGED]
│  │           The one PROVEN consumer: MDP-15 master-data import commits are
│  │           approval-gated via fn_approval_source_permission_action +
│  │           fn_approval_rule_guard, with SOD from master_data_sod_conflicts
│  │           (rp,116) and permissions from master_data_permissions (rp,301) /
│  │           master_data_role_permissions (rp,616).
│  │           T   074   C  No   P  No
│  │           X   Bounded to master-data import; not a general MD approval flow.
│  │
│  ├─ Document & Validation
│  │  │  ALL EIGHT leaves below are DISABLED placeholders with no page. In every
│  │  │  case the RULE IS ENFORCED IN THE DATABASE but is NOT CONFIGURABLE. The
│  │  │  blueprint asked for configuration surfaces; the repository hardcoded the
│  │  │  behaviour. This is the single most consistent [BACKEND AHEAD OF UI]
│  │  │  pattern in the product and needs one architectural decision, not eight.
│  │  │
│  │  ├─ Document Controls
│  │  │  ├─ Status Controls
│  │  │  │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │  │     DB/RT  draft→approved→posted→cancelled/voided enforced inside each
│  │  │  │     fn_save_*/fn_post_* RPC; 42 header + 18 line posted-document guards
│  │  │  │     T   020/041/061/009/010/012; guard 078
│  │  │  │     C   Bounded — inside the Certified Audit & Immutability Engine
│  │  │  │     X   No status-control configuration surface exists.
│  │  │  ├─ Posting Controls
│  │  │  │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │  │     RT  fn_assert_manual_postable, fn_assert_postable_leaf,
│  │  │  │         fn_assert_posting_source, fn_assert_source_journal_link,
│  │  │  │         fn_begin_source_posting; Kernel Totality Guard ENABLE ALWAYS
│  │  │  │     T   102 (P5.2: 48 bypass attempts all reject — 12×42501, 36×23514)
│  │  │  │     C   No — Posting Engine is Blocked at P6   P  No
│  │  │  ├─ Void Controls
│  │  │  │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │  │     DB  void_reason_codes (rp,7) · cas_document_void_events (cp,1)
│  │  │  │     RT  fn_void_sales_invoice, fn_void_vendor_bill; void evidence is
│  │  │  │         immutable; voided numbers are never reused
│  │  │  │     X   Void policy is per-RPC, not configurable; only SI and VB have
│  │  │  │         a void path.
│  │  │  └─ Reversal Controls
│  │  │        🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │        RT  fn_reverse_je, fn_reverse_posted_journal_entry (preserves all
│  │  │            six dimensions — proven in 080); /reversal-review page exists
│  │  │        C   No — Reversal, Void and Correction Engine is In Progress
│  │  │        X   Coverage not proven across all correction paths.
│  │  │
│  │  └─ Validation Rules
│  │     ├─ Master Data Rules
│  │     │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │     │     DB  master_data_permissions (rp,301) · master_data_role_permissions
│  │     │         (rp,616) · master_data_sod_conflicts (rp,116) — substantial and
│  │     │         reference-seeded (MDP-03)
│  │     │     RT  enforced on every master-data write; PH TIN normalization
│  │     │         (fn_format_ph_tin) is CHECK-constrained on both party masters
│  │     │     T   MDP tests; 011/013/014/056/072 permission+SOD (90 assertions)
│  │     │     X   No rules-configuration page; rules are seeded, not authored.
│  │     ├─ Transaction Rules
│  │     │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │     │     RT  validation lives inside each fn_save_* RPC (server-side
│  │     │         recomputation of amounts, membership, period, readiness)
│  │     │     X   Not configurable; each transaction re-implements its own rules
│  │     │         — the same structural weakness as the seven tax calculators.
│  │     ├─ Posting Validation Rules
│  │     │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │     │     UI  a PostingValidationPanel.tsx COMPONENT exists and is embedded
│  │     │         in transaction workspaces — but there is no rules SETUP page
│  │     │     RT  balanced-JE enforcement, postable-leaf assertion, COA resolver
│  │     │         fail-closed behaviour (fn_resolve_account)
│  │     │     T   081 (COA Engine Phase A); 102
│  │     ├─ Period Controls
│  │     │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │     │     DB  fiscal_periods (cp,60) with is_locked
│  │     │     RT  posting RPCs resolve and check the period; /period-closing
│  │     │         exposes lock/unlock
│  │     │     C   No — Period Lock and Closing Engine is In Progress
│  │     │     X   Year-end close and audited reopening not certified.
│  │
│  ├─ Accounting Setup
│  │  ├─ Fiscal Years
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /fiscal-years · FiscalYearsPage.tsx
│  │  │     DB  fiscal_years (cp,5) · fiscal_periods (cp,60)
│  │  │     RT  fn_create_fiscal_year, fn_generate_fiscal_periods (12 periods +
│  │  │         lock flag, MDP-06), invoked atomically by fn_provision_company
│  │  │     T   064 (fiscal generation), 073 (orchestration/rollback)
│  │  │     C   No   P   No   X  Matrix: Partial (close certification is Phase 8)
│  │  ├─ Fiscal Calendar
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     Same route /fiscal-years. The 12 generated periods ARE the calendar.
│  │  │     X   Two blueprint nodes → one page; alias undocumented.
│  │  ├─ Chart of Accounts
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /chart-of-accounts · ChartOfAccountsPage.tsx
│  │  │     DB  chart_of_accounts (cp,215) · coa_templates (rp,1) ·
│  │  │         coa_template_lines (rp,41) · account_mapping (cp,45) ·
│  │  │         ref_mapping_key (rp,9)
│  │  │     RT  COA Engine Phase A: fn_resolve_account (deterministic, fail-
│  │  │         closed, ambiguity-rejecting), account lifecycle draft/active/
│  │  │         deprecated/archived/locked with transition guard, immutable-once-
│  │  │         used account_type/normal_balance, no-delete-with-posted-history,
│  │  │         fn_provision_pxl_standard_coa canonical PH-SME fixture
│  │  │     T   081; Sales (P2A) and Purchasing (P2B) writers now resolve through
│  │  │         fn_resolve_account, each proven equivalence-identical
│  │  │     C   No — COA Engine In Progress; gates 2/4 need Phase B   P  No
│  │  ├─ Currency Setup
│  │  │     🟡 PARTIALLY IMPLEMENTED   [DEFERRED]
│  │  │     /currency-setup · CurrencySetupPage.tsx
│  │  │     DB  currencies (rp,9) exercised · exchange_rates (re,0) INTENTIONALLY
│  │  │         EMPTY
│  │  │     C   No — Currency Engine is **Deferred**: multi-currency is not
│  │  │         supported for production   P  No
│  │  │     X   Currency list works; FX revaluation, multi-currency posting, and
│  │  │         rate-driven translation do not exist.
│  │  ├─ Opening Balances
│  │  │     🟣 DOCUMENTATION / DESIGN ONLY   [NEEDS ARCHITECTURAL DECISION]
│  │  │     DISABLED placeholder. Docs exist (02. Accounting Core/Setup/05.
│  │  │     Opening Balances.md + Opening Balances Migration Utility.md).
│  │  │     DB  NO opening_balances table anywhere in the 202-table schema
│  │  │     RT  the only mechanism is a hand-keyed manual journal entry. Posting
│  │  │         Engine P6 evidence explicitly attributes part of the Inventory
│  │  │         reconciliation variance to "one opening balance"
│  │  │     C   No   P   No
│  │  │     X   Migrating a real client onto PXL has no supported path. This is a
│  │  │         production-readiness blocker, not a cosmetic gap (§10.L).
│  │  ├─ Financial Statement Fields
│  │  │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │     DISABLED placeholder — but substantial backend exists.
│  │  │     DB  chart_of_accounts.fs_statement / fs_group (MDP-04) ·
│  │  │         fs_structure (wd,0) · account_fs_map (wd,0) — the COA Engine
│  │  │         Phase A FS registry with one-active-mapping-per-statement and
│  │  │         effective dating
│  │  │     T   081   C  No   P  No
│  │  │     X   The registry is built and empty; the provisioning workflow that
│  │  │         fills it is Phase B; no user surface exists. FS rendering still
│  │  │         reads account codes, not the registry.
│  │  └─ GL Posting Configuration
│  │        🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │        /gl-posting-config · GLPostingConfigPage.tsx
│  │        DB  company_accounting_config (cp,5) — the single writable account
│  │            authority in COA Phase A · vw_company_accounting_config compat view
│  │        RT  config→mapping sync keeps fn_resolve_account equivalence-identical
│  │        T   081   C  No   P  No
│  │
│  └─ Tax Setup
│     ├─ BIR Form Configuration
│     │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│     │     /bir-form-config · BIRFormConfigPage.tsx
│     │     DB  page reads ref_compliance_forms (rp,14) — populated. But the
│     │         actual config tables bir_forms (re,0), bir_form_mappings (re,0),
│     │         bir_config_maintainers (re,0) are ALL intentionally empty
│     │     RT  governed maintainer-only RPCs exist: fn_bir_form_upsert,
│     │         fn_bir_form_set_active, fn_bir_form_mapping_upsert/_delete
│     │         (PXL-AUD-063 read-only RLS + audited SECURITY DEFINER writes)
│     │     T   075; PXL-AUD-063 closed
│     │     C   No   P   No
│     │     X   The page lists reference forms; it cannot configure a form
│     │         mapping because no maintainer is provisioned in canonical.
│     ├─ Tax Codes
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│     │     /tax-setup · TaxSetupPage.tsx (one page serves six nav labels)
│     │     DB  tax_codes (rp,8) · vw_tax_reference_catalog
│     │     RT  fn_tax_code_upsert / fn_tax_code_set_active (MDP-01 governed:
│     │         read-only RLS + audited RPC writes); effective_from/_to,
│     │         deprecated_at, supersedes_*, overlap + successor guards,
│     │         immutability-after-use, fn_tax_code_version_asof
│     │     T   MDP-01/MDP-12 tests   C  No   P  No
│     ├─ VAT Codes
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│     │     Same page. DB vat_codes (rp,6). RT fn_vat_code_upsert /
│     │     fn_vat_code_set_active, same versioning governance.
│     │     X   VAT-inclusive treatment exists in only ONE of the seven
│     │         save-layer calculators (Posting Engine P4 census).
│     ├─ EWT Codes
│     │     ⚫ SUPERSEDED / REMOVED   [MERGED] [DUPLICATED]
│     │     The ewt_codes table was CONSOLIDATED AWAY by
│     │     20260714000003_withholding_master_consolidation.sql. EWT is now
│     │     represented by the global atc_codes master.
│     │     UI  the nav label survives and points at /tax-setup — a correct
│     │         alias, but nothing documents that "EWT Codes" now means ATC
│     │     DB  atc_codes (rp,18)   T  MDP-12 verified the consolidation
│     │     X   Deliberate, sound consolidation with NO alias mapping recorded
│     │         anywhere a reader would find it (§12 P1-2).
│     ├─ FWT Codes
│     │     ⚫ SUPERSEDED / REMOVED   [MERGED] [DUPLICATED]
│     │     Identical to EWT Codes: fwt_codes consolidated into atc_codes by the
│     │     same migration. Nav label survives as an alias to /tax-setup.
│     ├─ Percentage Tax Codes
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│     │     Same page. DB percentage_tax_codes (cp,2) — company-scoped,
│     │     member-gated, audited. RT rate feeds PT review and 2551Q.
│     ├─ ATC Codes
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│     │     Same page. DB atc_codes (rp,18) — now the SINGLE authoritative
│     │     withholding reference (absorbed ref_atc_codes, ewt_codes, fwt_codes).
│     │     RT  fn_atc_code_upsert/_set_active, fn_atc_version_asof,
│     │         fn_atc_code_is_current, fn_atc_code_used (immutability-after-use)
│     │     T   049 (master defaults drive VB EWT and OR CWT end to end)
│     │     X   Posting Engine P4 census: the 5 writers reading atc_codes.rate
│     │         use it as **provenance only** — they do not compute from it.
│     └─ Tax Calendar
│           🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│           /tax-calendar · TaxCalendarPage.tsx
│           DB  tax_calendar_events (cp,248) · ref_compliance_forms (rp,14)
│           RT  fn_generate_tax_calendar (profile-driven), fn_mark_tax_event_filed
│           T   canonical; consumed by the Dashboard and all four compliance
│               dashboards (PT/VAT/WT/Income Tax)
│           C   No   P   No   X  Matrix: Implemented.
```

### 3.3 — `3. Master Data`

```text
├─ 3. Master Data                             Now: "Master Data" (unchanged)
│  │
│  ├─ Parties
│  │  ├─ Customers
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /customers · CustomersPage.tsx
│  │  │     DB  customers (cp,66) — registered_name, trade_name, business_style,
│  │  │         TIN (canonical XXX-XXX-XXX-XXXXX, CHECK-constrained),
│  │  │         tin_branch_code, default_tax_type, default ATC/CWT, terms,
│  │  │         currency, GL account, credit_limit, addresses
│  │  │     RT  PostgREST CRUD under member RLS + MDP-03 permissions; snapshots
│  │  │         onto sales documents (master edits never rewrite history)
│  │  │     T   049 (customer CWT default WC140 → OR CWT tax detail → 2307
│  │  │         received evidence, executed)
│  │  │     C   No   P   No   X  Matrix: Implemented. Module Blocked.
│  │  ├─ Suppliers
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /suppliers · SuppliersPage.tsx · suppliers (cp,56)
│  │  │     RT  supplier default ATC drives source-basis VB EWT and payment-basis
│  │  │         PV EWT (PXL-AUD-037 basis policy)
│  │  │     T   049 (executed end to end)   C  No   P  No
│  │  └─ Personnel / Employees Lite
│  │        🟢 IMPLEMENTED AND SOURCE-BACKED   [RENAMED]
│  │        Now: "Employees" · /employees · EmployeesPage.tsx
│  │        DB  employees (cp,26) — "lite" master holding BIR-required
│  │            identifiers and payroll-relevant fields, branch/department linked
│  │        RT  read/write CRUD; consumed as a Sales Invoice dimension (salesman)
│  │            and by the Department Report
│  │        C   No   P   No
│  │        X   Correctly scoped as a lite master. It is NOT a payroll module and
│  │            must not be read as one (§7.I).
│  │
│  ├─ Customer Profile
│  │  ├─ Customer Addresses
│  │  │     🟡 PARTIALLY IMPLEMENTED   [MERGED]
│  │  │     No address master exists. Two embedded columns on customers carry it:
│  │  │     registered_address (required) and delivery_address (required).
│  │  │     X   One billing + one delivery address per customer. Multiple
│  │  │         ship-to sites, address effectivity, and per-branch addresses are
│  │  │         not supported.
│  │  ├─ Customer Contacts
│  │  │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │     DB  party_contacts (wd,0) EXISTS — a real multi-contact master
│  │  │         (customer XOR supplier, at-most-one-primary, RLS(4), audited),
│  │  │         built by MDP-10 which states explicitly "Backend only — no UI"
│  │  │     UI  CustomersPage does NOT read party_contacts. The live capability
│  │  │         is the single embedded customers.contact_person column
│  │  │     T   075 only — never exercised by canonical
│  │  │     C   No   P   No
│  │  │     X   A complete master with zero surface: the clearest single instance
│  │  │         of backend-ahead-of-UI in Master Data.
│  │  ├─ Customer Tax Profiles
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│  │  │     Embedded on customers: default_tax_type (vat_registered / non_vat /
│  │  │     vat_exempt / zero_rated), TIN + tin_branch_code, CWT-subject flag,
│  │  │     default active ATC.
│  │  │     RT  drives receipt CWT/ATC defaults and governed 2307-received evidence
│  │  │     T   049 executed   C  No   P  No
│  │  └─ Customer Credit Profiles
│  │        🟡 PARTIALLY IMPLEMENTED   [MERGED]
│  │        Embedded: customers.credit_limit (NUMERIC(15,2), default 0) only.
│  │        A 'credit_limit_exceeded' approval trigger_condition_type EXISTS in
│  │        the approval_workflows schema but no rule is configured.
│  │        X   No credit exposure calculation, no credit hold, no blocking on
│  │            over-limit sales, no ageing-based credit review.
│  │
│  ├─ Supplier Profile
│  │  ├─ Supplier Addresses
│  │  │     🟡 PARTIALLY IMPLEMENTED   [MERGED]
│  │  │     Embedded suppliers.registered_address only — suppliers do not even
│  │  │     have the second (delivery) address customers have.
│  │  ├─ Supplier Contacts
│  │  │     🟡 PARTIALLY IMPLEMENTED   [BACKEND AHEAD OF UI]
│  │  │     Same party_contacts (wd,0) master; SuppliersPage does not read it.
│  │  │     Live capability is the embedded suppliers.contact_person.
│  │  ├─ Supplier Tax Profiles
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│  │  │     Embedded: default_tax_type, TIN, EWT-subject flag, default ATC.
│  │  │     RT  drives source-basis VB accrual EWT and payment-basis PV EWT
│  │  │     T   049 executed
│  │  └─ Supplier Bank Details
│  │        🔴 MISSING / NO RELIABLE EVIDENCE
│  │        No supplier bank columns, no supplier_bank_accounts table, no page
│  │        section. Verified against the suppliers DDL and the full 202-table
│  │        list. The only bank_accounts rows are the COMPANY's own accounts.
│  │        X   Supplier remittance details cannot be stored. Payment Vouchers
│  │            and Check Vouchers therefore cannot carry a validated payee bank
│  │            account. Material for any real disbursement workflow.
│  │
│  ├─ Items & Services
│  │  ├─ Item Categories
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     /item-catalog (one page serves all four nav labels) ·
│  │  │     item_categories (cp,30)
│  │  ├─ Units of Measure
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     Same page. units_of_measure (cp,40). item_uom_conversions (wd,0)
│  │  │     exists but is unexercised — multi-UoM conversion is not proven.
│  │  ├─ Items
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     Same page. items (cp,91) — item_type, category, UoM, prices,
│  │  │     price_is_vat_inclusive, default sales/purchase VAT, default ATC,
│  │  │     sales/COGS/inventory/purchase-expense accounts, costing_method,
│  │  │     min_stock_level. item_barcodes (wd,0) and item_media (wd,0) exist
│  │  │     unexercised.
│  │  │     X   ALSO appears as Assets ▸ Inventory ▸ Items — see §3.6.
│  │  └─ Services
│  │        🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │        Not a separate master: items.item_type IN
│  │        ('inventory_item','service','non_inventory'). Correct design; the
│  │        blueprint's separate "Services" node no longer exists as a surface.
│  │
│  ├─ Inventory Master
│  │  ├─ Warehouses
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     /warehouses · WarehousesPage.tsx · warehouses (cp,6)
│  │  │     warehouse_zones (re,0) intentionally empty.
│  │  │     X   The SAME label + SAME route appears twice in navigation:
│  │  │         Master Data ▸ Inventory Master ▸ Warehouses AND
│  │  │         Inventory ▸ Setup ▸ Warehouses. Exact duplicate entry.
│  │  └─ Warehouse Stock Settings
│  │        🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │        /warehouse-stock-settings · warehouse_item_settings (cp,87)
│  │        Per-item-per-warehouse reorder/min/max settings; reads items,
│  │        stock_balances, suppliers, warehouses — all canonical.
│  │
│  └─ Shared
│     └─ Payment Terms
│           🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│           /payment-terms · payment_terms (cp,25); consumed as customer and
│           supplier defaults and as a due-date driver on AR/AP documents.
```

---
### 3.4 — `4. Sales`

```text
├─ 4. Sales                    Now: "Sales" (feature-gated: accounts_receivable)
│  │
│  ├─ Transactions
│  │  ├─ Sales Invoices
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /sales-invoices · /sales-invoices/new · /sales-invoices/:id ·
│  │  │     /sales-invoices/:id/edit — the ONLY dedicated routed form/view pair
│  │  │     in the product. SalesInvoicePage + SalesInvoiceDocumentPage.
│  │  │     DB  sales_invoices (cp,75) · sales_invoice_lines (cp,135) ·
│  │  │         vw_sales_invoice_register
│  │  │     RT  fn_save_sales_invoice, fn_approve_sales_invoice,
│  │  │         fn_post_sales_invoice, fn_void_sales_invoice,
│  │  │         fn_revert_si_to_draft, fn_preview_gl_impact, fn_ar_aging_asof;
│  │  │         all six governed dimensions propagate to posted JE lines
│  │  │     T   AUD-053 completeness migration 20260722000010; test 080 (all six
│  │  │         dimensions); posting P2A resolves accounts via fn_resolve_account
│  │  │     C   No   P   No
│  │  │     X   The strongest implemented core in PXL, and still not certified.
│  │  │         PXL-AUD-053 SI completeness is the named Phase-2 blocker; it is
│  │  │         the ONLY transaction with a 'sales-invoice-reviewed-slice' field-
│  │  │         source gate — every other transaction is 'transaction-matrix-only'.
│  │  │         Matrix: Partial.
│  │  ├─ Cash Sales
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /cash-sales · CashSalesPage.tsx (creates a settled Sales Invoice;
│  │  │     the resulting document uses the SI view — pattern A, in-page mode)
│  │  │     DB  sales_invoices (cp) · ref_payment_modes (rp,5)
│  │  │     RT  fn_save_cash_sale
│  │  │     C   No   P   No
│  │  │     X   fn_save_cash_sale is the **sole computing tax writer** in the
│  │  │         entire product (Posting Engine P4 census). Separating its
│  │  │         calculation from its posting is an explicit Tax Engine
│  │  │         prerequisite. Matrix: Partial.
│  │  ├─ Receipts
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [RENAMED]
│  │  │     Now labelled "Receipts"; the Transaction Matrix row is "Official
│  │  │     Receipt / Customer Collection"; the workspace registry calls it
│  │  │     "Sales Receipt / Official Receipt". THREE names, one object.
│  │  │     /receipts · ReceiptsPage.tsx · receipts (cp,6) · receipt_lines (cp,6)
│  │  │     RT  fn_save_receipt, fn_post_receipt, fn_bounce_receipt; applications
│  │  │         against invoices and credit memos; CWT capture with ATC
│  │  │     T   049 (CWT default → tax detail → 2307 received)
│  │  │     C   No   P   No   X  Naming collision — see §4.J and §12 P1-2.
│  │  ├─ Credit Memos
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /credit-memos · credit_memos (cp,1) · credit_memo_lines (cp,1) ·
│  │  │     vw_credit_memo_register · RT fn_save_credit_memo · ref_reason_codes (rp,10)
│  │  │     C   No   P   No   X  Only one canonical row; returns/credit
│  │  │         reconciliation is the named Sales/AR certification blocker.
│  │  ├─ Debit Memos
│  │  │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │     /debit-memos · DebitMemosPage.tsx — page and RPC BOTH exist
│  │  │     DB  debit_memos (fd,0) · debit_memo_lines (fd,0) — classified
│  │  │         **future-deferred: "Future module (unimplemented)"**
│  │  │     RT  fn_save_debit_memo exists and is wired to the page
│  │  │     T   referenced by tests but never populated in canonical
│  │  │     C   No   P   No
│  │  │     X   A reachable, fully-built customer debit memo surface whose tables
│  │  │         the governance register declares unimplemented. Either the page
│  │  │         should be hidden or the tables promoted with a fixture — the two
│  │  │         registers currently contradict each other (§10.J).
│  │  └─ Customer Returns
│  │        🟡 PARTIALLY IMPLEMENTED   [RENAMED] [MERGED]
│  │        /customer-returns · CustomerReturnsPage.tsx
│  │        DB  NO customer_returns table. The page is a CONVERSION SURFACE that
│  │            reads delivery_receipts/delivery_receipt_lines/sales_invoices and
│  │            writes a draft Credit Memo
│  │        RT  fn_save_credit_memo (shared with Credit Memos)
│  │        C   No   P   No
│  │        X   A physical goods return has no inventory effect on this path —
│  │            returned stock is not received back. Non-posting by design.
│  │
│  ├─ Sales Cycle                              [MOVED — now inside "Transactions"]
│  │  │  The blueprint separates a "Sales Cycle" group from "Transactions". The
│  │  │  shipped nav MERGED all three into Sales ▸ Transactions, ordered
│  │  │  Quotation → SO → DR → SI → Cash Sale → Receipt → CM → DM → Return.
│  │  │  This is a better ordering than the blueprint's; it is undocumented.
│  │  ├─ Quotations
│  │  │     🟡 PARTIALLY IMPLEMENTED   [MOVED]
│  │  │     /quotations · sales_quotations (cp,1) · sales_quotation_lines (cp,1)
│  │  │     RT  fn_next_document_number then direct insert (client-side RPC
│  │  │         pattern, not a server-side save RPC); non-posting, pattern E
│  │  │     C   No   P   No
│  │  │     X   Conversion Quote→SO/SI is NOT verified; Document Conversion
│  │  │         Engine is **Not Started**. Matrix: Partial.
│  │  ├─ Sales Orders
│  │  │     🟡 PARTIALLY IMPLEMENTED   [MOVED]
│  │  │     /sales-orders · sales_orders (cp,3) · sales_order_lines (cp,3)
│  │  │     RT  fn_next_document_number + direct insert; non-posting
│  │  │     X   No inventory reservation, no verified fulfilment/billing state
│  │  │         machine, no accounting effect. Matrix: Partial.
│  │  └─ Delivery Receipts
│  │        🟡 PARTIALLY IMPLEMENTED   [MOVED]
│  │        /delivery-receipts · delivery_receipts (cp,2) ·
│  │        delivery_receipt_lines (cp,2) · RT fn_next_document_number
│  │        X   "Current confirmation has no direct JE" (workspace registry).
│  │            The goods-out inventory and COGS consequence of a delivery is not
│  │            established — the mirror image of the Receiving Report defect in
│  │            Purchasing. Matrix: Partial.
│  │
│  ├─ Receivables
│  │  ├─ Customer Ledger
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     Merged with AR Aging onto ONE page: /ar-aging (label "AR Aging /
│  │  │     Customer Ledger", page title "AR Aging & Customer Ledger")
│  │  │     DB  vw_customer_ledger · customers (cp,66)
│  │  │     X   This one route carries FOUR nav labels across three domains:
│  │  │         Sales ▸ AR Aging/Customer Ledger; Accounting ▸ Customer Ledger
│  │  │         (Accounting View); Compliance ▸ AR Subsidiary Ledger;
│  │  │         Reports ▸ AR Aging. See §4.J.
│  │  ├─ AR Aging
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│  │  │     Same page. RT fn_ar_aging_asof (true as-of aging, reversal-aware);
│  │  │     fn_ar_subledger_gl_reconciliation_asof exists
│  │  │     C   No — "AR subledger equals AR control" is on the Critical
│  │  │         Reconciliations list and is NOT yet evidenced   P  No
│  │  └─ Collection Monitoring
│  │        🟡 PARTIALLY IMPLEMENTED
│  │        /collection-monitoring · reads customers, receipt_lines,
│  │        sales_invoices (all cp) — real data, read-only
│  │        X   A monitoring view only: no dunning, no promise-to-pay, no
│  │            collection assignment, no follow-up state. No RPC.
│  │
│  ├─ Tax Review
│  │  ├─ Output VAT Review
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     /sales-tax-review · SalesTaxReviewPage (reads sales_invoices +
│  │  │     credit_memos, cp). The view-based twin vw_output_vat_review is
│  │  │     rendered by Compliance ▸ Output VAT Summary and Reports ▸ Output VAT
│  │  │     Summary (both → /vat-output-summary)
│  │  │     T   VAT-ledger-to-GL reconciliation variance is exactly 0.00 (P4)
│  │  │     C   No   P   No
│  │  ├─ Percentage Tax Review
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED
│  │  │     /pt-review · reads sales_invoice_lines (cp,135)
│  │  │     X   Read-only review; the 2551Q generator behind it is deferred.
│  │  └─ 2307 Received Review
│  │        🟡 PARTIALLY IMPLEMENTED   [DUPLICATED]
│  │        /2307-received-review · Form2307ReceivedPage
│  │        DB  form_2307_tracking (fd,0) — DEFERRED — plus receipts (cp,6) and
│  │            receipt_lines (cp,6) and atc_codes (rp,18)
│  │        RT  fn_claim_form2307_received, fn_record_form2307_received
│  │        X   The claim/record RPCs are real and the receipt-side CWT data is
│  │            real, but the certificate tracking table is governed-empty, so the
│  │            received-certificate lifecycle is not exercised. Same route is
│  │            also Compliance ▸ 2307 Certificates Received and Reports ▸ 2307
│  │            Received Listing. Matrix: Partial.
│  │
│  └─ Registers
│     ├─ Sales Invoice Register
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│     │     /sales-registers · SalesRegistersPage renders FOUR views in one page:
│     │     vw_sales_invoice_register, vw_receipt_register,
│     │     vw_credit_memo_register, vw_debit_memo_register
│     ├─ Receipt Register        🟢 [MERGED] — same page, vw_receipt_register
│     ├─ Credit Memo Register    🟢 [MERGED] — same page, vw_credit_memo_register
│     ├─ Debit Memo Register
│     │     🔵 UI / ROUTE ONLY   [MERGED] [DEFERRED]
│     │     Same page. vw_debit_memo_register reads debit_memos (fd,0) → the
│     │     register renders but can never return a row in the current dataset.
│     └─ SLS
│           🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│           /sls · SLSPage reads sales_invoices (cp,75)
│           X   The identical label + route also appears under Compliance ▸ VAT ▸
│               SLS. Two menu entries, one page.
│
│  Nav note: the five blueprint Register leaves collapse to ONE route carrying
│  FIVE labels (`sales-registers` ×5 including the group entry). See §6.4.
```

### 3.5 — `5. Purchasing`

```text
├─ 5. Purchasing            Now: "Purchasing" (feature-gated: accounts_payable)
│  │
│  ├─ Transactions
│  │  ├─ Purchase Orders
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /purchase-orders · purchase_orders (cp,33) · purchase_order_lines (cp,33)
│  │  │     RT  fn_save_purchase_order, fn_approve_purchase_order,
│  │  │         fn_cancel_purchase_order; carries department/cost-centre/warehouse
│  │  │     C   No   P   No   X  Non-posting commitment; three-way match unproven.
│  │  ├─ Receiving Reports
│  │  │     🟡 PARTIALLY IMPLEMENTED   [RENAMED] [NEEDS ARCHITECTURAL DECISION]
│  │  │     Now: "Receiving Reports"; the workspace registry name is "Receiving
│  │  │     Report / Goods Receipt" — the blueprint's term and the ERP-standard
│  │  │     term coexist.
│  │  │     /receiving-reports · receiving_reports (cp,3) ·
│  │  │     receiving_report_lines (cp,3)
│  │  │     RT  fn_save_receiving_report, fn_confirm_receiving_report
│  │  │     C   No   P   No
│  │  │     X   **This is the Posting Engine P6 blocker.** Confirming a Receiving
│  │  │         Report INCREASES STOCK WITHOUT WRITING A JOURNAL, while the
│  │  │         corresponding Vendor Bill debits purchase clearing. Measured
│  │  │         movement/stock-value versus configured Inventory-control GL
│  │  │         divergence: 2,400.00 (ABC), 21,000.00 (Bayani), 6,630.00 (Golden).
│  │  │         Remedying it requires prohibited engine or certified-data changes,
│  │  │         so P6 is Blocked and the Posting Engine cannot advance.
│  │  ├─ Vendor Bills
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /vendor-bills · vendor_bills (cp,36) · vendor_bill_lines (cp,36) ·
│  │  │     vw_vendor_bill_register
│  │  │     RT  fn_save_vendor_bill, fn_approve_vendor_bill, fn_post_vendor_bill,
│  │  │         fn_void_vendor_bill, fn_revert_vendor_bill_to_draft;
│  │  │         fn_apply_vendor_bill_line_ewt_profile (source-basis EWT);
│  │  │         accounts resolve through fn_resolve_account (COA Phase B / P2B)
│  │  │     T   049; dimension propagation in 080
│  │  │     C   No   P   No   X  Matrix: Partial. Three-way match unproven.
│  │  ├─ Cash Purchases
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /cash-purchases · cash_purchases (cp,1) · cash_purchase_lines (cp,1)
│  │  │     RT  fn_save_cash_purchase, fn_post_cash_purchase, fn_preview_gl_impact,
│  │  │         fn_apply_cash_purchase_line_ewt_profile (PXL-AUD-043)
│  │  │     C   No   P   No
│  │  ├─ Payment Vouchers
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [RENAMED]
│  │  │     Blueprint "Payment Vouchers"; workspace registry name is "Payment
│  │  │     Voucher / Vendor Payment" — two names for one object.
│  │  │     /payment-vouchers · payment_vouchers (cp,5) · payment_voucher_lines
│  │  │     (cp,5) · vw_payment_register
│  │  │     RT  fn_save_payment_voucher, fn_post_payment_voucher,
│  │  │         fn_cancel_payment_voucher; bill application + payment-basis EWT
│  │  │     C   No — Payment and Application Engine In Progress   P  No
│  │  │     X   Over-application and unapplied-cash controls not certified.
│  │  │         Cannot carry a validated payee bank account (no supplier bank
│  │  │         details exist — §3.3).
│  │  ├─ Vendor Credits
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /vendor-credits · vendor_credits (cp,1) · vendor_credit_lines (cp,1) ·
│  │  │     vendor_credit_applications (cp,1)
│  │  │     RT  fn_save_vendor_credit, fn_post_vendor_credit, fn_apply_vendor_credit
│  │  │     X   P6 evidence attributes part of the Inventory GL variance to a
│  │  │         Vendor Credit.
│  │  ├─ Debit Memos to Suppliers
│  │  │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │     /supplier-debit-memos · SupplierDebitMemosPage · vw_sdm_register
│  │  │     DB  supplier_debit_memos (fd,0) · supplier_debit_memo_lines (fd,0)
│  │  │     RT  fn_save_supplier_debit_memo, fn_send_supplier_debit_memo,
│  │  │         fn_acknowledge_supplier_debit_memo — a full send/acknowledge
│  │  │         lifecycle exists in the database
│  │  │     T   075 only — never populated
│  │  │     C   No   P   No
│  │  │     X   Three RPCs, a page, a register view, and a governance register
│  │  │         that says "Future module (unimplemented)". Non-posting by design.
│  │  └─ Purchase Returns
│  │        🔵 UI / ROUTE ONLY   [DEFERRED]
│  │        /purchase-returns · PurchaseReturnsPage
│  │        DB  purchase_returns (fd,0) · purchase_return_lines (fd,0)
│  │        RT  fn_save_purchase_return, fn_ship_purchase_return,
│  │            fn_complete_purchase_return, fn_preview_gl_impact — declared
│  │            'posting' in the workspace registry
│  │        C   No   P   No
│  │        X   A posting transaction with a governed-empty table. Matrix:
│  │            Partial. Listed in the Deferred-Module Register under "Returns &
│  │            Corrective Documents".
│  │
│  ├─ Payables
│  │  ├─ Supplier Ledger
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     Merged with AP Aging onto /ap-aging (label "AP Aging / Supplier
│  │  │     Ledger"). DB vw_supplier_ledger · suppliers (cp,56)
│  │  │     X   Same four-label pattern as AR: Purchasing ▸ AP Aging/Supplier
│  │  │         Ledger; Accounting ▸ Supplier Ledger (Accounting View);
│  │  │         Compliance ▸ AP Subsidiary Ledger; Reports ▸ AP Aging.
│  │  ├─ AP Aging
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED]
│  │  │     Same page. RT fn_ap_aging_asof; vw_ap_aging;
│  │  │     fn_ap_subledger_gl_reconciliation_asof exists (reversal-aware)
│  │  │     C   No — "AP subledger equals AP control" not yet evidenced   P  No
│  │  └─ Payment Monitoring
│  │        🟡 PARTIALLY IMPLEMENTED
│  │        /payment-monitoring · payment_vouchers (cp,5) ·
│  │        RT fn_update_payment_tracking
│  │        X   Tracking-status maintenance only; no scheduling, no payment run,
│  │            no cash-requirement forecast.
│  │
│  ├─ Tax Review
│  │  ├─ Input VAT Review
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     /input-vat-review · vw_input_vat_review (over posted purchase data)
│  │  │     X   Also rendered at /vat-input-summary from Compliance and Reports.
│  │  ├─ EWT Summary
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     /ewt-summary · vw_ewt_summary_ap
│  │  │     T   EWT/CWT ledger-to-GL reconciliation variance exactly 0.00 (P4)
│  │  │     X   THREE nav labels point here: Purchasing ▸ EWT Summary;
│  │  │         Compliance ▸ EWT Payable Summary; Reports ▸ EWT Summary.
│  │  └─ 2307 Issued Review
│  │        🟡 PARTIALLY IMPLEMENTED   [DUPLICATED] [NEEDS ARCHITECTURAL DECISION]
│  │        /2307-issued-review · Form2307IssuedPage
│  │        DB  form_2307_issuances (fd,0) — the ONLY table this page reads, and
│  │            it is classified future-deferred
│  │        RT  fn_generate_form_2307_issued, fn_supersede_form_2307_issued,
│  │            fn_update_form_2307_issued_status — a complete generate/supersede
│  │            lifecycle
│  │        C   No   P   No
│  │        X   **Direct register contradiction.** The Transaction Matrix records
│  │            "Form 2307 Issued" as **Implemented**; the Table Coverage Matrix
│  │            records form_2307_issuances as **future-deferred / "Future module
│  │            (unimplemented)"**. Both are Tier-1/Tier-2 governance artifacts.
│  │            One of them is wrong and must be reconciled (§10.H, §12 P0-2).
│  │
│  └─ Registers
│     ├─ Vendor Bill Register
│     │     🟢 [MERGED] [DUPLICATED] — /purchase-registers · PurchaseRegistersPage
│     │     renders vw_vendor_bill_register, vw_payment_register, vw_sdm_register,
│     │     vw_slp_export in one page
│     ├─ Payment Register    🟢 [MERGED] — same page, vw_payment_register
│     ├─ Debit Memo Register
│     │     🔵 UI / ROUTE ONLY   [MERGED] [DEFERRED]
│     │     Same page, vw_sdm_register over supplier_debit_memos (fd,0) — cannot
│     │     return a row.
│     │     X   The label "Debit Memo Register" appears in BOTH Sales ▸ Registers
│     │         (→ /sales-registers, customer DM) and Purchasing ▸ Registers
│     │         (→ /purchase-registers, supplier DM). Identical label, different
│     │         business object, different route. Actively misleading (§4.J).
│     └─ SLP
│           🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│           Same page, vw_slp_export. Also standalone at /vat-slp from
│           Compliance ▸ VAT ▸ SLP.
```

### 3.6 — `6. Assets`  ⚠ **the parent node no longer exists**

```text
├─ 6. Assets
│     ⚫/[SPLIT]  THE "Assets" PARENT IS GONE FROM THE RUNNING PRODUCT.
│     The blueprint groups Cash Management + Inventory + Fixed Assets under one
│     "Assets" domain. The shipped navigation has THREE INDEPENDENT TOP-LEVEL
│     DOMAINS, each with its own feature gate:
│         Inventory          (feature: inventory_management)
│         Banking & Treasury (feature: banking_module)
│         Fixed Assets       (feature: fixed_assets)
│     The documentation tree agrees with the split (07. Inventory /
│     08. Banking and Treasury / 09. Fixed Assets are separate folders), and the
│     certification matrix treats them as three separate modules (#5, #6, #7).
│     NO DOCUMENT RECORDS THE DECISION TO DISSOLVE "Assets". This is the single
│     largest taxonomy divergence between blueprint and repository.
│     Recommended treatment: ratify the split; retire "Assets" as a node name.
│
│  ├─ Cash Management   →  now "Banking & Treasury" (top-level)  [SPLIT][RENAMED]
│  │  │  ALL TEN leaves below are 🔵 UI / ROUTE ONLY. Every Banking/Treasury base
│  │  │  table is `future-deferred` with 0 canonical rows, and the module is
│  │  │  "Not Started" (Phase 5) in the certification matrix and named first in
│  │  │  the Deferred-Module Register. Ten fully navigable, fully unexercised
│  │  │  screens — the largest single block of route-only surface in PXL.
│  │  │
│  │  ├─ Petty Cash
│  │  │  ├─ Petty Cash Fund Setup
│  │  │  │     🔵 UI / ROUTE ONLY   [DEFERRED] [DUPLICATED]
│  │  │  │     /petty-cash-funds · petty_cash_funds (fd,0)
│  │  │  │     X   Appears TWICE in nav: Setup ▸ Treasury ▸ Petty Cash Fund Setup
│  │  │  │         and Banking & Treasury ▸ Petty Cash ▸ Petty Cash Fund Setup —
│  │  │  │         same label, same route, two domains.
│  │  │  ├─ Petty Cash Vouchers
│  │  │  │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │  │     /petty-cash-vouchers · petty_cash_vouchers (fd,0)
│  │  │  │     RT  fn_next_document_number, fn_preview_gl_impact,
│  │  │  │         fn_approve_petty_cash_voucher exists in the catalog
│  │  │  │     X   Declared 'posting' in the workspace registry; zero rows ever.
│  │  │  ├─ Petty Cash Replenishment
│  │  │  │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │  │     /petty-cash-replenishment · petty_cash_replenishments (fd,0)
│  │  │  │     RT  fn_post_petty_cash_replenishment, fn_preview_gl_impact
│  │  │  └─ Cash Count Sheet
│  │  │        🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │        /cash-count-sheet · cash_count_sheets (fd,0) — one of the 33
│  │  │        routes backed EXCLUSIVELY by deferred tables. Non-posting.
│  │  │
│  │  └─ Bank                              → now "Bank Operations" [RENAMED]
│  │     ├─ Fund Transfers
│  │     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │     │     /fund-transfers · fund_transfers (fd,0)
│  │     │     RT  fn_post_fund_transfer, fn_cancel_fund_transfer,
│  │     │         fn_preview_gl_impact — full posting path exists, never used
│  │     ├─ Inter-Branch Transfers
│  │     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │     │     /inter-branch-transfers · inter_branch_transfers (fd,0)
│  │     │     RT  fn_post_inter_branch_transfer, fn_cancel_inter_branch_transfer
│  │     │     X   Due-to/due-from inter-branch accounting is unexercised.
│  │     ├─ Bank Adjustments
│  │     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │     │     /bank-adjustments · bank_adjustments (fd,0)
│  │     │     RT  fn_post_bank_adjustment, fn_cancel_bank_adjustment
│  │     ├─ Bank Reconciliation
│  │     │     🔵 UI / ROUTE ONLY   [DEFERRED] [NEEDS ARCHITECTURAL DECISION]
│  │     │     /bank-reconciliation · bank_reconciliations (fd,0) ·
│  │     │     bank_recon_items (fd,0)
│  │     │     X   bank_recon_items is one of only TWO tables **excluded from the
│  │     │         Posting Engine P5.0 write-surface closure** because it is
│  │     │         UI-written (the other is book_tax_reconciliation). A UI-written
│  │     │         table inside an otherwise sealed accounting perimeter is a
│  │     │         standing architectural exception that needs a decision.
│  │     ├─ Outstanding Checks
│  │     │     🔵 UI / ROUTE ONLY   [DEFERRED] [DUPLICATED]
│  │     │     /outstanding-checks · vw_outstanding_checks over check_vouchers
│  │     │     (fd,0) — cannot return a row. Also Reports ▸ Outstanding Checks
│  │     │     Report → same route.
│  │     └─ Deposits in Transit
│  │           🔵 UI / ROUTE ONLY   [DEFERRED]
│  │           /deposits-in-transit · vw_deposits_in_transit · bank_accounts (cp)
│  │           X   The view exists; the reconciliation data behind it does not.
│  │
│  │  ADDITION IN THIS BRANCH (not in the blueprint): Banking & Treasury ▸
│  │  Payables ▸ **Check Vouchers** (/check-vouchers, check_vouchers fd,0 +
│  │  check_voucher_lines fd,0). A whole disbursement instrument the blueprint
│  │  never named, sitting in Banking rather than Purchasing. See §5.
│  │
│  ├─ Inventory                       → now "Inventory" (top-level)  [SPLIT]
│  │  ├─ Inventory Dashboard
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /inventory-dashboard · inventory_transactions (cp,26) ·
│  │  │     stock_balances (cp,11)
│  │  │     C   No   P   No
│  │  ├─ Items
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     Not a separate Inventory surface — the blueprint's Assets ▸ Inventory
│  │  │     ▸ Items is the SAME /item-catalog page as Master Data ▸ Items. The
│  │  │     shipped Inventory menu does not even list it (it lists Stock Balance
│  │  │     instead), so the duplication was silently resolved in favour of
│  │  │     Master Data. Correct outcome, unrecorded decision.
│  │  ├─ Warehouses
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     /warehouses — the duplication SURVIVES here: the identical label and
│  │  │     route appear in Master Data ▸ Inventory Master AND Inventory ▸ Setup.
│  │  ├─ Stock Adjustment
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /stock-adjustment · stock_adjustments (cp,4) ·
│  │  │     stock_adjustment_lines (cp,4) · RT fn_post_stock_adjustment,
│  │  │     fn_preview_gl_impact — a real posting transaction
│  │  │     X   Scoped OUT of Dimension Engine analytical attribution by design
│  │  │         (adjustment movements are branch-attributed only).
│  │  ├─ Stock Transfer
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /stock-transfer · stock_transfers (cp,2) · stock_transfer_lines (cp,2)
│  │  │     RT  fn_post_stock_transfer, fn_preview_gl_impact
│  │  ├─ Goods Issue
│  │  │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │     /goods-issue · GoodsIssuePage
│  │  │     DB  goods_issues (fd,0) · goods_issue_lines (fd,0)
│  │  │     RT  fn_post_goods_issue, fn_preview_gl_impact — and the Dimension
│  │  │         Engine certification explicitly proves Goods Issue carries ALL
│  │  │         SIX dimensions onto GL lines and the inventory movement
│  │  │     C   No   P   No
│  │  │     X   **A governance-vocabulary collision.** A table the coverage
│  │  │         matrix calls "Future module (unimplemented)" is simultaneously
│  │  │         named as proven evidence in a CERTIFIED engine (Dimension
│  │  │         Engine, test 080). Both are most likely literally true — 080
│  │  │         builds a transient fixture, while the coverage class describes
│  │  │         only the CANONICAL SEED — but the two registers use
│  │  │         "implemented" to mean different things, and nothing on either
│  │  │         document says so. A reader cannot tell whether Goods Issue works.
│  │  │         This is a taxonomy defect, not necessarily a code defect
│  │  │         (§10.H, §12 P0-2).
│  │  ├─ Physical Count
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /physical-count · physical_count_sheets (cp,1) ·
│  │  │     physical_count_sheet_lines (cp,1) · RT fn_post_physical_count
│  │  │     Declared 'mixed' posting (count → generated adjustment).
│  │  ├─ Inventory Movements
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │  │     /inventory-movements · inventory_transactions (cp,26)
│  │  │     X   FOUR nav labels → this one route: Inventory ▸ Inventory
│  │  │         Movements; Compliance ▸ Inventory Subsidiary Ledger; Reports ▸
│  │  │         Stock Movement; Reports ▸ Inventory Ledger. A BIR subsidiary
│  │  │         ledger and a management stock report are NOT the same artifact.
│  │  └─ Inventory Valuation
│  │        🟡 PARTIALLY IMPLEMENTED   [DUPLICATED] [NEEDS ARCHITECTURAL DECISION]
│  │        /inventory-valuation · inventory_cost_layers (cp,12) ·
│  │        stock_balances (cp,11)
│  │        C   No   P   No
│  │        X   **It does not reconcile.** Posting Engine P6 measured, against
│  │            the canonical dataset: movement/stock value vs configured
│  │            Inventory-control GL differs by 2,400.00 / 21,000.00 / 6,630.00
│  │            across three companies, and remaining cost layers exceed stock by
│  │            2,420.00 / 12,600.00 / 3,930.00 and 9 / 6 / 14 units. "Inventory
│  │            valuation equals inventory control" is on the Critical
│  │            Reconciliations list and currently FAILS. The page renders a
│  │            number that the GL does not agree with.
│  │
│  │  ADDITION IN THIS BRANCH: Inventory ▸ Overview ▸ **Stock Balance**
│  │  (/stock-balance, stock_balances cp,11 + inventory_cost_layers cp,12) — a
│  │  real, exercised surface the blueprint never named. See §5.
│  │
│  └─ Fixed Assets                → now "Fixed Assets" (top-level)  [SPLIT]
│     │  EIGHT of nine leaves are 🔵 UI / ROUTE ONLY. Every fixed-asset base
│     │  table is `future-deferred` with 0 canonical rows; the module is "Not
│     │  Started" (Phase 6); it is named in the Deferred-Module Register. Yet the
│     │  Dimension Engine certification cites Fixed Asset acquisition /
│     │  depreciation / disposal as proven dimension-bearing posting transactions
│     │  — the same fixture-versus-canonical contradiction as Goods Issue.
│     ├─ Fixed Asset Dashboard
│     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│     │     /fixed-asset-dashboard · fixed_assets (fd,0) ·
│     │     asset_depreciation_entries (fd,0) — pure-deferred page
│     ├─ Asset Register
│     │     🔵 UI / ROUTE ONLY   [DEFERRED] [DUPLICATED]
│     │     /asset-register · pure-deferred. THREE labels → this route:
│     │     Fixed Assets ▸ Asset Register; Compliance ▸ Fixed Asset Register;
│     │     Reports ▸ Fixed Asset Register.
│     ├─ Asset Acquisition
│     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│     │     /asset-acquisition · fixed_asset_categories (fd,0) + branches/
│     │     departments/suppliers/COA (cp) · RT fn_register_fixed_asset
│     ├─ Depreciation
│     │     🔵 UI / ROUTE ONLY   [RENAMED] [DEFERRED]
│     │     Now "Depreciation Run" · /depreciation-run ·
│     │     asset_depreciation_entries (fd,0) — pure-deferred
│     │     RT  fn_post_depreciation_entry, fn_preview_gl_impact
│     ├─ Disposal
│     │     🔵 UI / ROUTE ONLY   [RENAMED] [DEFERRED]
│     │     Now "Asset Disposal" · /asset-disposal · asset_disposals (fd,0)
│     │     RT  fn_dispose_fixed_asset
│     ├─ Transfer
│     │     🔵 UI / ROUTE ONLY   [RENAMED] [DEFERRED]
│     │     Now "Asset Transfer" · /asset-transfer · asset_transfers (fd,0)
│     │     RT  fn_transfer_fixed_asset — declared non-posting
│     ├─ Impairment
│     │     🔵 UI / ROUTE ONLY   [RENAMED] [DEFERRED]
│     │     Now "Asset Impairment (PAS 36)" · /asset-impairment ·
│     │     asset_impairments (fd,0) · RT fn_record_impairment
│     └─ Setup
│        ├─ Asset Categories
│        │     🔵 UI / ROUTE ONLY   [DEFERRED]
│        │     /asset-categories · fixed_asset_categories (fd,0) + COA (cp)
│        └─ Depreciation Profiles
│              🟣 DOCUMENTATION / DESIGN ONLY
│              No table (verified against all 202), no page, no nav entry.
│              Doc exists: 09. Fixed Assets/02. Setup/02. Depreciation Profiles.md
│              X   Depreciation method/life/convention policy has nowhere to
│                  live; whatever fn_post_depreciation_entry uses is embedded in
│                  the asset row or the function, not in a governed profile.
```

---
### 3.7 — `7. Accounting`

```text
├─ 7. Accounting                              Now: "Accounting" (unchanged)
│  │
│  ├─ Journal Entries
│  │  ├─ Journal Entries
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED] [DUPLICATED]
│  │  │     /journal-entries · JournalEntriesPage.tsx
│  │  │     DB  journal_entries (cp,48) · journal_entry_lines (cp,138) ·
│  │  │         fiscal_periods (cp,60) · chart_of_accounts (cp,215)
│  │  │     RT  fn_post_manual_je (gated by fn_assert_manual_postable, wired in
│  │  │         Posting P3), fn_reverse_je; all six dimensions per line; the
│  │  │         JE-line guard fn_je_line_dimensions_guard rejects every
│  │  │         cross-company dimension (proven non-vacuous in 080)
│  │  │     T   080 (43 assertions); 102 (Kernel Totality Guard, P5.2)
│  │  │     C   Bounded — the DIMENSION behaviour is inside the Certified
│  │  │         Dimension Engine; the module (Accounting Core) is In Progress
│  │  │     P   No   X  Matrix: Implemented (the only "Implemented" posting
│  │  │         transaction in the whole matrix).
│  │  │     NOTE  Nav shows "General Ledger Entries" AND "Journal Entries" as two
│  │  │         entries in the SAME group pointing at the SAME route. The
│  │  │         blueprint's own docs folder also carries "00. General Ledger
│  │  │         Entries.md" beside "01. Journal Entries.md". These are the same
│  │  │         object under two names (§4.J).
│  │  └─ Recurring Journal Templates
│  │        🔵 UI / ROUTE ONLY   [DEFERRED]
│  │        /recurring-journal-templates · RecurringJournalTemplatesPage
│  │        DB  recurring_journal_templates (fd,0) ·
│  │            recurring_journal_template_lines (fd,0)
│  │        RT  fn_execute_recurring_template, fn_preview_gl_impact
│  │        C   No   P   No   X  Matrix: Partial. Deferred-Module Register:
│  │            "Schedules & Revenue Recognition — future workflow".
│  │
│  ├─ Ledgers
│  │  ├─ General Ledger
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED] [DUPLICATED]
│  │  │     /general-ledger · GeneralLedgerPage.tsx
│  │  │     DB  vw_general_ledger (5 defs — the central reporting view) ·
│  │  │         vw_gl_dimension_summary (Dimension Engine)
│  │  │     RT  fn_general_ledger_report, fn_gl_account_ledger_page,
│  │  │         fn_gl_account_ledger_summary, fn_report_gl_by_dimension
│  │  │     T   080 proves dimensional totals reconcile EXACTLY to the
│  │  │         undimensioned control total (no double counting)
│  │  │     C   No   P   No
│  │  │     X   Also serves Compliance ▸ BIR Books ▸ General Ledger Book.
│  │  ├─ Account Detail Ledger
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [UNCHANGED]
│  │  │     /account-detail-ledger · RT fn_gl_account_ledger_page /
│  │  │     fn_gl_account_ledger_summary (paged, per-account drill)
│  │  └─ Trial Balance
│  │        🟢 IMPLEMENTED AND SOURCE-BACKED   [DUPLICATED]
│  │        /trial-balance · vw_trial_balance · RT fn_trial_balance_report
│  │        C   No — "Trial Balance debit equals credit" is on the Critical
│  │            Reconciliations list and is not yet formally evidenced   P  No
│  │        X   FOUR nav labels → this one route (Accounting ▸ Trial Balance;
│  │            Reports ▸ Unadjusted / Adjusted / Post-Closing). See §3.9.
│  │
│  ├─ Subsidiary Ledgers
│  │  ├─ Customer Ledger (Accounting View)
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     → /ar-aging. There is NO separate "accounting view": the business
│  │  │     view and the accounting view are literally the same page.
│  │  │     X   The blueprint deliberately separated an operational customer
│  │  │         ledger from an accounting subsidiary ledger. The product merged
│  │  │         them. That is defensible (one source of truth) but it means the
│  │  │         accounting-view requirements — control-account tie-out, posting-
│  │  │         state basis, period cut-off — were never separately satisfied.
│  │  ├─ Supplier Ledger (Accounting View)
│  │  │     🟢 IMPLEMENTED AND SOURCE-BACKED   [MERGED] [DUPLICATED]
│  │  │     → /ap-aging. Same merge, same consequence.
│  │  └─ Control Account Reconciliation
│  │        🟡 PARTIALLY IMPLEMENTED
│  │        /control-account-recon · ControlAccountReconciliationPage
│  │        DB  chart_of_accounts · company_accounting_config · sales_invoices ·
│  │            credit_memos · receipt_lines (all cp) · vw_ap_aging ·
│  │            vw_general_ledger
│  │        RT  fn_ar_subledger_gl_reconciliation_asof and
│  │            fn_ap_subledger_gl_reconciliation_asof exist (reversal-aware)
│  │        C   No   P   No
│  │        X   The page computes; the RESULT is not certified. Four of the nine
│  │            Critical Reconciliations run through here and none is evidenced.
│  │
│  ├─ Schedules
│  │  ├─ Amortization Schedules
│  │  │     🔵 UI / ROUTE ONLY   [DEFERRED]
│  │  │     /amortization-schedules · amortization_schedules (fd,0) ·
│  │  │     amortization_entries (fd,0)
│  │  │     RT  fn_create_amortization_schedule, fn_cancel_amortization_schedule,
│  │  │         fn_post_amortization_entry, fn_preview_gl_impact
│  │  │     C   No — "Accounting Schedules" module is Not Started (Phase 6)
│  │  └─ Revenue Recognition Schedules
│  │        🔵 UI / ROUTE ONLY   [DEFERRED]
│  │        /revenue-recognition-schedules · revenue_recognition_schedules (fd,0)
│  │        · revenue_recognition_entries (fd,0)
│  │        RT  fn_create_revenue_recognition_schedule,
│  │            fn_cancel_revenue_recognition_schedule,
│  │            fn_post_revenue_recognition_entry
│  │        X   Generation, duplicate-run, and closed-period behaviour unproven.
│  │
│  └─ Period Management
│     ├─ Period Closing
│     │     🟡 PARTIALLY IMPLEMENTED
│     │     /period-closing · PeriodClosingPage (label "Period Closing & Fiscal
│     │     Locks")
│     │     DB  fiscal_periods (cp,60) + journal_entries (cp) — real; BUT the
│     │         page also reads bank_reconciliations (fd,0) and
│     │         recurring_journal_templates (fd,0), so two of its close checks
│     │         can never fire
│     │     C   No — Period Lock and Closing Engine In Progress   P  No
│     │     X   Year-end close and audited reopening are NOT certified. Posting-
│     │         period enforcement and close remain Phase 8.
│     ├─ Fiscal Locks
│     │     🟡 PARTIALLY IMPLEMENTED   [MERGED] [DUPLICATED]
│     │     Same route /period-closing. is_locked on fiscal_periods is the
│     │     mechanism; lock/unlock auditing is called for but not certified.
│     ├─ Posting Review
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED
│     │     /posting-review · journal_entries + journal_entry_lines +
│     │     fiscal_periods (all cp); read-only review of posted activity
│     ├─ Reversal Review
│     │     🟢 IMPLEMENTED AND SOURCE-BACKED
│     │     /reversal-review · journal_entries (cp); GL reversal visibility is
│     │     covered by a dedicated migration + test
│     ├─ Amortization Run
│     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│     │     /amortization-run · amortization_entries + amortization_schedules
│     │     (fd,0) + journal_entries (cp) · RT fn_post_amortization_entry
│     ├─ Revenue Recognition Run
│     │     🔵 UI / ROUTE ONLY   [DEFERRED]
│     │     /revenue-recognition-run · revenue_recognition_* (fd,0) +
│     │     journal_entries (cp) · RT fn_post_revenue_recognition_entry
│     └─ Auto Reversal Run
│           🟢 IMPLEMENTED AND SOURCE-BACKED
│           /auto-reversal-run · journal_entries (cp,48) + fiscal_periods (cp,60)
│           RT  fn_reverse_je against eligible source journals
│           C   No — Reversal, Void and Correction Engine In Progress
```

### 3.8 — `8. Compliance`

```text
├─ 8. Compliance                              Now: "Compliance" (unchanged)
│  │  Largest blueprint domain: 66 leaves, 26% of the tree. It is BIMODAL —
│  │  28 leaves read posted data and work; 24 are shells over governed-empty
│  │  tables. The dividing line is exact: anything that READS posted
│  │  transactions (VAT reviews, BIR books, CAS logs) is source-backed; anything
│  │  that PERSISTS a statutory artifact (returns, working papers, certificates,
│  │  income-tax computations) is future-deferred.
│  │
│  ├─ Percentage Tax
│  │  ├─ PT Dashboard        🟡 /pt-dashboard · compliance_profiles (cp,5) +
│  │  │                      tax_calendar_events (cp,248) real; pt_returns (fd,0)
│  │  ├─ PT Working Papers   🔵 /pt-working-papers · compliance_pt_working_papers_
│  │  │                      headers/lines (fd,0) ONLY — pure-deferred route
│  │  ├─ PT Quarterly Return 2551Q
│  │  │                      🟡 /pt-return-2551q · pt_returns (fd,0) +
│  │  │                      sales_invoice_lines (cp,135); computes from real
│  │  │                      sales but cannot persist a filed return
│  │  ├─ PT Reconciliation   🟡 /pt-reconciliation · pt_returns (fd,0) +
│  │  │                      compliance_profiles + sales_invoice_lines (cp)
│  │  └─ PT Summary Register 🔵 /pt-summary-register · pt_returns (fd,0) ONLY —
│  │                         pure-deferred. Also Reports ▸ Percentage Tax Summary.
│  │     C for all five: No — Philippine Compliance and Tax module is **Blocked**
│  │
│  ├─ VAT
│  │  ├─ VAT Dashboard       🟢 /vat-dashboard · vw_input_vat_review +
│  │  │                      vw_output_vat_review + compliance_profiles +
│  │  │                      tax_calendar_events — all backed by posted data
│  │  ├─ VAT Working Papers  🔵 /vat-working-papers · compliance_vat_working_
│  │  │                      papers_headers/lines (fd,0) ONLY — pure-deferred
│  │  ├─ Output VAT Summary  🟢 /vat-output-summary · vw_output_vat_review
│  │  │                      [DUPLICATED with Reports ▸ Output VAT Summary]
│  │  │                      T: VAT ledger-to-GL variance = 0.00 (P4)
│  │  ├─ Input VAT Summary   🟢 /vat-input-summary · vw_input_vat_review
│  │  │                      [DUPLICATED with Reports ▸ Input VAT Summary]
│  │  ├─ VAT Reconciliation  🟡 /vat-reconciliation · vat_returns (fd,0) + both
│  │  │                      VAT views; a VATReconciliationPanel component exists
│  │  ├─ VAT Return 2550M    🟡 /vat-return-2550m · vat_returns (fd,0) + views +
│  │  │                      companies. Matrix says "Implemented"; the persistence
│  │  │                      table is future-deferred → register conflict (§10.H)
│  │  ├─ VAT Return 2550Q    🟡 /vat-return-2550q · identical to 2550M
│  │  ├─ SLS                 🟢 /sls · sales_invoices (cp,75)
│  │  │                      [DUPLICATED with Sales ▸ Registers ▸ SLS]
│  │  ├─ SLP                 🟢 /vat-slp · vw_slp_export
│  │  │                      [DUPLICATED with Purchasing ▸ Registers ▸ SLP]
│  │  ├─ SLSP Export         🟢 /vat-slsp-export · vw_output_vat_review +
│  │  │                      vw_slp_export · RT fn_snapshot_vat_export →
│  │  │                      report_snapshots (wd,0), server-attested + hashed
│  │  └─ RELIEF Export       🟢 /vat-relief-export · both VAT views ·
│  │                         RT fn_snapshot_vat_export
│  │     C for all eleven: No — module Blocked (Phase 7 not executed)
│  │
│  ├─ Withholding Tax
│  │  ├─ WT Dashboard        🟢 /wt-dashboard · vw_ewt_summary_ap +
│  │  │                      receipt_lines (cp) + compliance_profiles +
│  │  │                      tax_calendar_events
│  │  ├─ EWT Working Papers  🔵 /ewt-working-papers · compliance_ewt_working_
│  │  │                      papers_headers/lines (fd,0) ONLY — pure-deferred
│  │  │                      [reached from BOTH Sales and Compliance menus]
│  │  ├─ EWT Payable Summary 🟢 /ewt-summary · vw_ewt_summary_ap
│  │  │                      [DUPLICATED ×3 — see §3.5]
│  │  ├─ EWT Receivable Summary
│  │  │                      🟢 /wt-ewt-receivable-summary · receipt_lines (cp,6)
│  │  │                      — customer-withheld CWT from real receipts
│  │  ├─ ATC Summary         🟢 /wt-atc-summary · vw_ewt_summary_ap
│  │  ├─ 1601EQ Working Papers
│  │  │                      🔵 /wt-1601eq-working-papers · compliance_1601eq_*
│  │  │                      (fd,0) ONLY — pure-deferred
│  │  ├─ 1601EQ Quarterly Return
│  │  │                      🔵 /wt-1601eq-return · ewt_returns (fd,0) ONLY ·
│  │  │                      RT fn_compute_ewt_return exists. Matrix: Partial.
│  │  ├─ QAP                 🟡 /wt-qap · vw_ewt_summary_ap (real) +
│  │  │                      report_snapshots (wd,0) · RT fn_snapshot_wht_export
│  │  ├─ SAWT                🟡 /wt-sawt · vw_cwt_summary_ar (real) +
│  │  │                      report_snapshots (wd,0) · RT fn_snapshot_wht_export
│  │  │                      Matrix: "Form 2307 Received / SAWT" = Partial
│  │  ├─ 2307 Certificates Issued
│  │  │                      🟡 [DUPLICATED] → /2307-issued-review (see §3.5 —
│  │  │                      register conflict: Matrix "Implemented" vs table fd)
│  │  ├─ 2307 Certificates Received
│  │  │                      🟡 [DUPLICATED] → /2307-received-review (see §3.4)
│  │  ├─ 2306 Certificates   🔵 /wt-2306-certificates · form_2306_issuances (fd,0)
│  │  │                      + bank_adjustments (fd,0) — pure-deferred
│  │  └─ Final Withholding Tax
│  │     ├─ FWT Working Papers
│  │     │                   🔵 /wt-fwt-working-papers · compliance_fwt_working_
│  │     │                   papers_headers/lines (fd,0) — pure-deferred
│  │     ├─ 1601FQ Working Papers
│  │     │                   🔵 /wt-1601fq-working-papers · compliance_1601fq_*
│  │     │                   (fd,0) — pure-deferred
│  │     └─ 1601FQ Quarterly Return
│  │                         🔵 /wt-1601fq-return · fwt_returns (fd,0) +
│  │                         form_2306_issuances (fd,0) — pure-deferred
│  │     X  FWT has NO named owner in the certification matrix and NO engine.
│  │        Four of its five surfaces are pure shells. See §12 P1-4.
│  │
│  ├─ Income Tax
│  │  │  TEN of eleven leaves are 🔵 pure-deferred. This is the least-implemented
│  │  │  branch of the entire blueprint. Every income-tax table
│  │  │  (income_tax_computations, itr_filings, mcit_computations, nolco_schedule,
│  │  │  tax_credits_schedule, book_tax_reconciliation) is future-deferred with
│  │  │  zero rows, and the Deferred-Module Register names "Income Tax" outright.
│  │  ├─ Income Tax Dashboard      🟡 /inc-tax-dashboard · compliance_profiles +
│  │  │                            tax_calendar_events (cp) real; income_tax_
│  │  │                            computations + nolco_schedule (fd,0)
│  │  ├─ Taxable Income Computation 🔵 /inc-tax-computation (pure-deferred)
│  │  ├─ Book-to-Tax Reconciliation 🔵 /inc-tax-book-to-tax-recon (pure-deferred)
│  │  │                            X book_tax_reconciliation is the SECOND table
│  │  │                            excluded from Posting Engine P5.0 write-surface
│  │  │                            closure because it is UI-written (§10.L)
│  │  ├─ OSD Computation           🔵 /inc-tax-osd (pure-deferred)
│  │  ├─ NOLCO Schedule            🔵 /inc-tax-nolco (pure-deferred)
│  │  ├─ Tax Credits Schedule      🔵 /inc-tax-credits (pure-deferred)
│  │  ├─ Individual / Sole Proprietor
│  │  │  ├─ 1701Q Quarterly ITR    🔵 /inc-tax-1701q · itr_filings (fd,0)
│  │  │  └─ 1701 Annual ITR        🔵 /inc-tax-1701 · itr_filings (fd,0)
│  │  └─ Corporate / OPC / Partnership
│  │     ├─ 1702Q Quarterly ITR    🔵 /inc-tax-1702q · itr_filings (fd,0)
│  │     ├─ 1702RT Annual ITR      🔵 /inc-tax-1702rt · itr_filings (fd,0)
│  │     └─ MCIT Computation       🔵 /inc-tax-mcit · mcit_computations (fd,0)
│  │        NOTE  all four ITR variants share ONE table (itr_filings) — a sound
│  │        design, but four routes over one empty table read as four features.
│  │
│  ├─ BIR Books of Accounts
│  │  │  The STRONGEST compliance branch: 11 of 13 leaves are source-backed
│  │  │  because every book reads posted transaction data, and every book export
│  │  │  is server-attested and hashed via fn_snapshot_books_export.
│  │  ├─ Books Dashboard      🟢 /books-dashboard · fiscal_periods + journal_
│  │  │                       entries (cp)
│  │  ├─ General Journal      🟢 /books-general-journal · vw_general_ledger ·
│  │  │                       RT fn_snapshot_books_export
│  │  │                       [DUPLICATED with Reports ▸ Journal Register]
│  │  ├─ General Ledger Book  🟢 [DUPLICATED] → /general-ledger (same page as
│  │  │                       Accounting ▸ General Ledger)
│  │  ├─ Cash Receipts Book   🟢 /books-cash-receipts · receipts (cp,6) +
│  │  │                       sales_invoices (cp,75)
│  │  ├─ Cash Disbursements Book
│  │  │                       🟡 /books-cash-disbursements · cash_purchases (cp,1)
│  │  │                       + payment_vouchers (cp,5) real, BUT check_vouchers
│  │  │                       (fd,0) — every check disbursement is structurally
│  │  │                       absent from the BIR cash disbursements book
│  │  ├─ Sales Journal        🟢 /books-sales-journal · sales_invoices (cp,75)
│  │  ├─ Cash Sales Journal   🟢 /books-cash-sales-journal · sales_invoices (cp)
│  │  ├─ Purchase Journal     🟢 /books-purchase-journal · vendor_bills (cp,36)
│  │  ├─ Cash Purchases Journal
│  │  │                       🟢 /books-cash-purchases-journal · cash_purchases (cp)
│  │  ├─ AR Subsidiary Ledger 🟢 [DUPLICATED] → /ar-aging
│  │  ├─ AP Subsidiary Ledger 🟢 [DUPLICATED] → /ap-aging
│  │  ├─ Inventory Subsidiary Ledger
│  │  │                       🟢 [DUPLICATED] → /inventory-movements
│  │  │                       X  A BIR subsidiary ledger pointed at a management
│  │  │                       movement list. Different artifacts, one route.
│  │  └─ Fixed Asset Register 🔵 [DUPLICATED] → /asset-register (fd,0) — the BIR
│  │                          fixed-asset book can never render a row.
│  │     C for all thirteen: No — module Blocked. CAS DAT byte layout, books
│  │     source/GL reconciliation, and CAS audit-package evidence are delivered
│  │     per the Transaction Matrix, but the module review has not run.
│  │
│  └─ Audit & CAS
│     ├─ CAS Dashboard        🟡 /cas-dashboard · sys_audit_logs (cp,2161) +
│     │                       vw_cas_atp_usage real; cas_attachment_register (fd,0)
│     ├─ Transaction Audit Log
│     │                       🟢 /cas-transaction-audit-log · sys_audit_logs
│     │                       (cp,2161) · 79 tables carry fn_audit_trigger
│     │                       C  Bounded — **Audit & Immutability Engine
│     │                       CERTIFIED** 2026-07-23 (capture + tamper-proofing).
│     │                       The VIEWER page is not itself certified.
│     ├─ Master Data Change Log
│     │                       🟢 /cas-master-data-change-log · sys_audit_logs
│     ├─ System Parameter Logs
│     │                       🟢 /cas-system-parameter-logs · sys_audit_logs
│     ├─ User Activity Log    🟢 /cas-user-activity-log · sys_audit_logs
│     │                       [DUPLICATED with Reports ▸ User Activity Report]
│     ├─ Attachment Register  🔵 /cas-attachment-register · cas_attachment_
│     │                       register (fd,0) ONLY — pure-deferred
│     │                       X  Attachment and Document Traceability Engine is
│     │                       In Progress; no attachment can be registered.
│     ├─ Document Void Register
│     │                       🟢 /cas-document-void-register ·
│     │                       cas_document_void_events (cp,1) — immutable void
│     │                       evidence, part of the Certified Number Series chain
│     ├─ ATP Usage Log        🟢 /cas-atp-usage-log · vw_cas_atp_usage over
│     │                       cas_document_number_issuances (cp,215)
│     │                       [the real home of blueprint "ATP Monitoring"]
│     ├─ DAT File Generation  🔵 /cas-dat-file-generation · cas_export_log (fd,0)
│     │                       ONLY · RT fn_snapshot_cas_export. Matrix records
│     │                       CAS DAT byte layout as delivered → register conflict
│     ├─ CAS Audit Report     🟡 /cas-audit-report · cas_document_void_events +
│     │                       sys_audit_logs + vw_cas_atp_usage real;
│     │                       cas_export_log (fd,0)
│     └─ Export History       🔵 /cas-export-history · cas_export_log (fd,0) ONLY
│        ADDITION: Compliance ▸ Audit & CAS ▸ **Report Snapshots**
│        (/report-snapshots, report_snapshots wd,0) — not in the blueprint. §5.
```

### 3.9 — `9. Reports`

```text
└─ 9. Reports                                 Now: "Reports" (unchanged)
   │  43 leaves, of which **31 point at a route that another menu already owns**.
   │  Reports is largely an ALTERNATE INDEX over surfaces that live in the
   │  business domains, not a distinct reporting layer. Only 12 leaves resolve to
   │  a route reachable exclusively from Reports.
   │
   ├─ Financial Statements
   │  ├─ Balance Sheet        🟢 /balance-sheet · vw_general_ledger +
   │  │                       chart_of_accounts (cp,215) + fiscal_years (cp,5)
   │  │                       C  No — "FS net income equals GL" not evidenced
   │  ├─ Income Statement     🟢 /income-statement · vw_general_ledger + COA
   │  ├─ Statement of Cash Flows
   │  │                       🟡 /statement-of-cash-flows · vw_general_ledger +
   │  │                       company_accounting_config real, BUT fixed_assets,
   │  │                       asset_depreciation_entries and asset_disposals are
   │  │                       ALL fd,0 → the entire investing/depreciation
   │  │                       add-back section is structurally empty
   │  ├─ Statement of Changes in Equity
   │  │                       🟢 /statement-of-changes-in-equity ·
   │  │                       vw_general_ledger + COA + fiscal_years
   │  └─ Comparative Financial Statements
   │                          🟢 /comparative-financial-statements ·
   │                          vw_general_ledger + COA
   │     X  FS classification metadata exists (chart_of_accounts.fs_statement /
   │        fs_group, MDP-04) and an FS REGISTRY exists (fs_structure,
   │        account_fs_map — both wd,0), but the statements render from account
   │        codes, not from the registry. Configurable statement grouping is
   │        built and unused (§10.E).
   │
   ├─ Trial Balance
   │  ├─ Unadjusted Trial Balance    🟢 [DUPLICATED] → /trial-balance
   │  ├─ Adjusted Trial Balance      🟡 [DUPLICATED] → /trial-balance
   │  └─ Post-Closing Trial Balance  🟡 [DUPLICATED] → /trial-balance
   │     X  THREE distinct accounting artifacts → ONE undifferentiated page with
   │        no adjustment-state or closing-state parameter. "Adjusted" and
   │        "Post-Closing" cannot be produced because closing entries and the
   │        year-end close are not certified. Three menu entries promise three
   │        reports; one report exists.
   │
   ├─ Tax Reports
   │  ├─ Output VAT Summary       🟢 [DUPLICATED] → /vat-output-summary
   │  ├─ Input VAT Summary        🟢 [DUPLICATED] → /vat-input-summary
   │  ├─ Percentage Tax Summary   🔵 [DUPLICATED] → /pt-summary-register (fd,0)
   │  ├─ EWT Summary              🟢 [DUPLICATED] → /ewt-summary
   │  ├─ FWT Summary              🔵 /reports-fwt-summary · form_2306_issuances
   │  │                           (fd,0) ONLY — pure-deferred
   │  ├─ 2307 Issued Listing      🟡 [DUPLICATED] → /2307-issued-review
   │  └─ 2307 Received Listing    🟡 [DUPLICATED] → /2307-received-review
   │
   ├─ Aging Reports
   │  ├─ AR Aging                 🟢 [DUPLICATED] → /ar-aging (4th label)
   │  └─ AP Aging                 🟢 [DUPLICATED] → /ap-aging (4th label)
   │
   ├─ Bank Reports
   │  ├─ Bank Position Report     🟢 /reports-bank-position · bank_accounts
   │  │                           (cp,10) + vw_general_ledger — genuinely backed
   │  │                           (it reads the GL, not the deferred bank tables)
   │  ├─ Bank Reconciliation Summary
   │  │                           🔵 [DUPLICATED] → /bank-reconciliation (fd,0)
   │  └─ Outstanding Checks Report
   │                              🔵 [DUPLICATED] → /outstanding-checks (fd,0)
   │
   ├─ Inventory Reports
   │  ├─ Inventory Valuation      🟡 [DUPLICATED] → /inventory-valuation
   │  │                           X  does not reconcile to the GL (see §3.6)
   │  ├─ Stock Movement           🟢 [DUPLICATED] → /inventory-movements
   │  ├─ Inventory Ledger         🟢 [DUPLICATED] → /inventory-movements
   │  │                           X  "Stock Movement" and "Inventory Ledger" are
   │  │                           two labels for the same page inside the SAME
   │  │                           report group — pure menu padding.
   │  └─ Slow Moving Inventory    🟢 /reports-slow-moving-inventory ·
   │                              stock_balances (cp,11)
   │
   ├─ Fixed Asset Reports         ALL FOUR 🔵 — every backing table is fd,0
   │  ├─ Fixed Asset Register     🔵 [DUPLICATED] → /asset-register
   │  ├─ Depreciation Schedule    🔵 /reports-depreciation-schedule (pure-deferred)
   │  ├─ Book vs Tax Depreciation 🔵 /reports-book-vs-tax-depreciation (pure-def.)
   │  └─ Asset Disposal Report    🔵 /reports-asset-disposal (pure-deferred)
   │
   ├─ Management Reports
   │  ├─ Branch P&L               🟢 /reports-branch-pnl · branches (cp,8) +
   │  │                           vw_general_ledger — a real dimensional P&L
   │  ├─ Department Report        🟡 /reports-department · departments (cp,13) +
   │  │                           employees (cp,26) real, but fixed_assets (fd,0)
   │  ├─ Cost Center Report       🟡 /reports-cost-center · reads cost_centers
   │  │                           (cp,10) **and nothing else** — NO GL join at
   │  │                           all. It lists cost centres; it cannot produce a
   │  │                           cost-centre P&L. The weakest page in Reports.
   │  └─ Gross Margin Analysis    🟢 /reports-gross-margin · items (cp,91) +
   │                              vw_general_ledger
   │     X  A certified dimensional GL report EXISTS (vw_gl_dimension_summary +
   │        fn_report_gl_by_dimension, Dimension Engine) and reconciles exactly
   │        to the control total — but NONE of these four management reports
   │        calls it. Certified capability, unused by the surfaces that need it.
   │
   ├─ Transaction Registers
   │  ├─ Journal Register         🟢 [DUPLICATED] → /books-general-journal
   │  ├─ Sales Invoice Register   🟢 [DUPLICATED] → /sales-registers
   │  ├─ Receipt Register         🟢 [DUPLICATED] → /sales-registers
   │  ├─ Purchase Register        🟢 [DUPLICATED] → /purchase-registers
   │  ├─ Payment Register         🟢 [DUPLICATED] → /purchase-registers
   │  ├─ Credit Memo Register     🟢 [DUPLICATED] → /sales-registers
   │  ├─ Debit Memo Register      🔵 [DUPLICATED] → /sales-registers (fd,0)
   │  └─ Check Register           🔵 /reports-check-register · check_vouchers
   │                              (fd,0) ONLY — pure-deferred
   │     X  All eight registers are re-pointers into three pages. The Reports
   │        register group adds zero capability over the domain registers.
   │
   └─ Audit Reports
      ├─ Period Close Checklist   🟡 [DUPLICATED] → /period-closing
      ├─ Audit Support Package    🟢 /reports-audit-support-package ·
      │                           RT fn_snapshot_cas_audit_package over
      │                           bank_accounts + chart_of_accounts +
      │                           fiscal_periods + sales_invoices (all cp) —
      │                           server-attested, hashed
      └─ User Activity Report     🟢 [DUPLICATED] → /cas-user-activity-log
```

---
## 4. Change Register

Grouped A–J as required. "Recommended treatment" is advisory only.

### A. Unchanged

Items whose name, location, and intent survived intact. Sixty-one leaves qualify; the
architecturally significant ones are listed.

| Original item | Original location | Current name | Current location | Reason | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- | --- | --- |
| Company Setup | 2 ▸ Organization | Company Setup | Setup ▸ Organization | Core tenant boundary | `/company-setup`, companies cp,5, fn_provision_company, test 073 | Keep. Certify with the module. |
| Branch Setup | 2 ▸ Organization | Branch Setup | Setup ▸ Organization | Core dimension | branches cp,8; Dimension Engine Certified | Keep. |
| Compliance Profile | 2 ▸ Organization | Compliance Profile | Setup ▸ Organization | Drives all tax applicability | compliance_profiles cp,5 | Keep; make it the Tax Engine's policy input. |
| Chart of Accounts | 2 ▸ Accounting Setup | Chart of Accounts | Setup ▸ Accounting Setup | Core | chart_of_accounts cp,215; COA Engine Phase A, test 081 | Keep. Complete Phase B. |
| GL Posting Configuration | 2 ▸ Accounting Setup | GL Posting Configuration | Setup ▸ Accounting Setup | Single writable account authority | company_accounting_config cp,5 | Keep until COA Phase B moves authority to `account_mapping`. |
| Tax Calendar | 2 ▸ Tax Setup | Tax Calendar | Setup ▸ Tax Setup | Statutory deadlines | tax_calendar_events cp,248; fn_generate_tax_calendar | Keep. |
| Customers / Suppliers | 3 ▸ Parties | Customers / Suppliers | Master Data ▸ Parties | Core masters | cp 66 / 56; test 049 executed | Keep. |
| Sales Invoices | 4 ▸ Transactions | Sales Invoices | Sales ▸ Transactions | Strongest core | cp 75/135; 5 lifecycle RPCs; dedicated routed workspace | Keep. Certify first (Phase 2). |
| Vendor Bills | 5 ▸ Transactions | Vendor Bills | Purchasing ▸ Transactions | Strongest AP core | cp 36/36; 5 lifecycle RPCs | Keep. Certify (Phase 3). |
| Journal Entries | 7 ▸ Journal Entries | Journal Entries | Accounting ▸ Journal Entries | Core | cp 48/138; fn_post_manual_je; test 080/102 | Keep. |
| General Ledger / Trial Balance | 7 ▸ Ledgers | same | Accounting ▸ Ledgers | Core | vw_general_ledger, vw_trial_balance | Keep; deduplicate the Reports copies. |
| Payment Terms | 3 ▸ Shared | Payment Terms | Master Data ▸ Shared | Core | payment_terms cp,25 | Keep. |
| Warehouse Stock Settings | 3 ▸ Inventory Master | Warehouse Stock Settings | Master Data ▸ Inventory Master | Core | warehouse_item_settings cp,87 | Keep. |

### B. Renamed

| Original item | Original location | Current name | Current location | Reason | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- | --- | --- |
| Dashboard | 1 | **Executive Dashboard** | top-level | Doc blueprint uses the longer name | PAGE_LABELS `dashboard: 'Executive Dashboard'` | Adopt one name; the page is not yet an executive dashboard (§3.1). |
| Personnel / Employees Lite | 3 ▸ Parties | **Employees** | Master Data ▸ Parties | Simplification | `/employees`, employees cp,26 | Keep "Employees"; retain "lite" scope note so it is never read as payroll. |
| Receipts | 4 ▸ Transactions | **Receipts** / "Official Receipt / Customer Collection" / "Sales Receipt / Official Receipt" | Sales ▸ Transactions | Three registers named it differently | AppShell `s('Receipts','receipts')`; Transaction Matrix row; workspace registry row | **P1** — pick ONE canonical name and record the aliases. |
| Receiving Reports | 5 ▸ Transactions | **Receiving Report / Goods Receipt** | Purchasing ▸ Transactions | ERP-standard term added | workspace registry `transaction:'Receiving Report / Goods Receipt'` | Keep "Receiving Report" (PH practice); record "Goods Receipt" as an alias. |
| Payment Vouchers | 5 ▸ Transactions | **Payment Voucher / Vendor Payment** | Purchasing ▸ Transactions | Same | workspace registry | Same treatment. |
| Cash Management | 6 ▸ Assets | **Banking & Treasury** | top-level | Broader, accurate | NAV label; docs folder `08. Banking and Treasury` | Ratify. |
| Bank (sub-group) | 6 ▸ Cash Management | **Bank Operations** | Banking & Treasury | Clarity | NAV group label | Ratify. |
| Depreciation / Disposal / Transfer / Impairment | 6 ▸ Fixed Assets | **Depreciation Run / Asset Disposal / Asset Transfer / Asset Impairment (PAS 36)** | Fixed Assets | Explicit verbs + standard citation | NAV + PAGE_LABELS | Ratify. |
| Feature Settings (group) | 2 ▸ System Controls | **Global Feature Enablement** (one page) | Setup ▸ System Controls | Five per-module screens became one global switchboard | `/feature-enablement`, ref_feature_definitions rp,16 | Ratify; retire the five dead child placeholders. |
| Approval Matrix (group) | 2 ▸ System Controls | **Unified Approval Workflow** | Setup ▸ System Controls | Five matrices became one engine | `/approval-workflow`, MDP-14 | Ratify; document that the five blueprint matrices are now rule rows. |

### C. Moved

| Original item | Original location | Current name | Current location | Reason | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- | --- | --- |
| Company Bank Accounts | 2 ▸ Organization | Bank Accounts | **Master Data ▸ Banking** | Bank accounts are a master, not a setup step | `/bank-accounts`, bank_accounts cp,10; Setup entry left DISABLED | Remove the dead Setup placeholder. |
| ATP Monitoring | 2 ▸ System Controls | ATP Usage Log | **Compliance ▸ Audit & CAS** | Usage evidence belongs with CAS | `/cas-atp-usage-log`, vw_cas_atp_usage; Setup entry DISABLED | Remove the Setup placeholder; add threshold alerting if monitoring is still wanted. |
| Petty Cash Fund Setup | 6 ▸ Petty Cash | Petty Cash Fund Setup | **BOTH** Setup ▸ Treasury AND Banking & Treasury ▸ Petty Cash | Partial move, not completed | identical label + route in two menus | Pick one home (Banking & Treasury). |
| Quotations / Sales Orders / Delivery Receipts | 4 ▸ Sales Cycle | same | **Sales ▸ Transactions** | Merged into one ordered pipeline | NAV Sales ▸ Transactions ordering | Ratify — the shipped ordering is better than the blueprint's. |
| Items / Warehouses | 6 ▸ Inventory | Item Catalog / Warehouse Setup | **Master Data** (canonical home) | Masters belong in Master Data | `/item-catalog`, `/warehouses` | Ratify for Items (already resolved); resolve Warehouses (still duplicated). |

### D. Split

| Original item | Original location | Current | Reason | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- | --- |
| **Assets** | 6 (parent) | **THREE top-level domains**: Inventory, Banking & Treasury, Fixed Assets | Independent lifecycles, independent feature gates, independent certification phases (4, 5, 6) | NAV has no "Assets" node; docs folders 07/08/09; certification matrix modules #5/#6/#7 | **P0** — ratify the split in writing and retire "Assets" as a taxonomy node. It is the largest undocumented architectural change in the product. |
| Sales Invoice (as a UI) | 4 ▸ Transactions | `/sales-invoices` (register) + `/sales-invoices/new` (form) + `/sales-invoices/:id` (document) + `/:id/edit` | Transaction Workspace Standard | `App.tsx` 4 routes; workspace registry `form: dedicated-route, view: dedicated-route` | Keep; it is the reference pattern the other 32 workspaces have not adopted. |

### E. Merged

| Original items | Merged into | Reason | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- |
| Department Setup + Cost Centers | `/department-setup` | Both are dimension masters | 2 nav labels → 1 route | Ratify; label the page "Departments & Cost Centers" in the menu too. |
| Fiscal Years + Fiscal Calendar | `/fiscal-years` | Periods generated with the year | 2 labels → 1 route | Ratify. |
| Currency Setup + Exchange Rates | `/currency-setup` | One config surface | 2 labels → 1 route; exchange_rates re,0 | Ratify; mark FX deferred (Currency Engine Deferred). |
| Number Series ×4 doc classes | `/number-series` | One allocator, one list | 4 labels → 1 route | Ratify; drop the four class labels or filter the page by class. |
| Tax Codes + VAT + EWT + FWT + PT + ATC | `/tax-setup` | One tax reference surface | 6 labels → 1 route | Ratify; EWT/FWT are aliases of ATC (see F). |
| Customer Ledger + AR Aging | `/ar-aging` | One AR view | 4 labels across 3 domains → 1 route | Ratify but rationalise labels (§4.J). |
| Supplier Ledger + AP Aging | `/ap-aging` | One AP view | 4 labels across 3 domains → 1 route | Same. |
| 5 Sales registers | `/sales-registers` | One tabbed register page | 5 labels → 1 route | Ratify. |
| 4 Purchasing registers | `/purchase-registers` | Same | 4 labels → 1 route | Ratify. |
| 5 Approval matrices | `/approval-workflow` | One rules engine (MDP-14) | 5 labels → 1 route | Ratify. |
| Services → Items | `items.item_type` | Services are an item type | items cp,91 CHECK constraint | Ratify; drop the separate "Services" node. |
| Customer/Supplier addresses, contacts, tax, credit | columns on `customers`/`suppliers` | Simpler master | DDL verified | Ratify for tax; escalate contacts (party_contacts exists unused) and supplier bank (missing). |

### F. Superseded

| Original item | Superseded by | Reason | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- |
| **EWT Codes** | `atc_codes` | Withholding masters consolidated | `20260714000003_withholding_master_consolidation.sql`; MDP-12 header states ewt_codes/fwt_codes "were also consolidated away"; `ref_atc_codes` dropped in `20260629000014` | **P1** — publish an alias map: EWT Codes → ATC Codes. The nav label still exists with no explanation. |
| **FWT Codes** | `atc_codes` | Same | Same migration | Same. |
| *(latent)* `ref_atc_codes` | `atc_codes` | Duplicate ATC representation removed | `to_regclass('ref_atc_codes') IS NULL` verified in MDP-12 | Already resolved; record it in the alias map for provenance. |

### G. Deferred

Twenty-nine leaf items are formally deferred by the coverage matrix's Deferred-Module Register while
remaining fully navigable. Summarised by cluster:

| Cluster | Leaves | Tables | Evidence | Recommended treatment |
| --- | ---: | --- | --- | --- |
| Banking / Treasury (all) | 10 | 12 tables, all `future-deferred`, 0 rows | Module "Not Started" (Phase 5); named first in Deferred-Module Register | **P0** — mark visibly deferred in navigation or hide until Phase 5. |
| Fixed Assets (all but Depreciation Profiles) | 8 | 6 tables, all `future-deferred`, 0 rows | Module "Not Started" (Phase 6) | Same. |
| Income Tax | 10 | 6 tables, all `future-deferred` | "Income Tax — unsupported in canonical activity" | Same. |
| Compliance working papers (PT/VAT/EWT/FWT/1601EQ/1601FQ) | 6 | 12 tables, all `future-deferred` | "Statutory Tax Returns, Certificates & Working Papers" | Same. |
| Statutory return generators (2551Q, 2550M/Q, 1601EQ, 1601FQ, 2306) | 6 | pt/vat/ewt/fwt_returns, form_2306_issuances | Same register entry | Same. |
| Returns & corrective documents (Debit Memos, Supplier Debit Memos, Purchase Returns, Goods Issue) | 4 | 8 tables `future-deferred` | "Returns & Corrective Documents … remain unexercised" | Same. |
| Schedules (amortization, revenue recognition, recurring journals) | 5 | 6 tables `future-deferred` | "Schedules & Revenue Recognition — future workflow" | Same. |
| CAS export artifacts (Attachment Register, DAT Generation, Export History) | 3 | 3 tables `future-deferred` | "CAS Export Artifacts" | Same. |

### H. Missing

| Original item | Location | What exists | What is absent | Evidence | Recommended treatment |
| --- | --- | --- | --- | --- | --- |
| **CAS Registrations** | 2 ▸ Organization | ATP bounds on `number_series`; issuance evidence | No permit/accreditation record: no permit number, issue date, validity, machine ID, accreditation reference | No `cas_registrations` table in 202; nav DISABLED | **P1** — decide: build it, or state that CAS accreditation data is held outside PXL. A PH CAS-compliant ERP cannot leave this undecided. |
| **Supplier Bank Details** | 3 ▸ Supplier Profile | Company `bank_accounts` only | No supplier bank columns or table | `suppliers` DDL; 202-table list | **P1** — required before Payment/Check Voucher disbursement can be certified. |
| **Opening Balances** | 2 ▸ Accounting Setup | Manual JE workaround; doc + migration-utility doc | No `opening_balances` table, no page, no import | 202-table list; nav DISABLED; P6 cites "one opening balance" as a variance source | **P0** — no supported client-migration path exists. Production-readiness blocker. |
| **Depreciation Profiles** | 6 ▸ Fixed Assets ▸ Setup | Doc only | No table, no page, no nav entry | 202-table list | Fold into the Phase-6 Fixed Assets scope. |
| **Budget Settings** | 2 ▸ Feature Settings | Doc only | No budget table anywhere; no budget row in any matrix | 202-table list; grep `budget` → no table | **P1** — classify explicitly as Future Roadmap; remove the Setup menu entry. |
| **Customizable dashboard widgets** | 1 ▸ Dashboard | `dashboard_layouts` (rp,1), `dashboard_widgets` (rp,4) | No page reads them; no layout editor, date range, entity roll-up, export/import | DashboardPage table census | Decide: build the widget grid, or drop the two tables. |

### I. Duplicated

The full duplicate-route census (55 duplicate labels over 169 distinct routes). The 31 routes carrying
more than one label:

| Route | Labels | The labels |
| --- | ---: | --- |
| `/tax-setup` | 6 | Tax Codes · VAT Codes · EWT Codes · FWT Codes · Percentage Tax Codes · ATC Codes |
| `/sales-registers` | 5 | Sales Registers · Sales Invoice Register · Receipt Register · Credit Memo Register · Debit Memo Register |
| `/trial-balance` | 4 | Trial Balance · Unadjusted TB · Adjusted TB · Post-Closing TB |
| `/number-series` | 4 | Number Series — Sales / Purchasing / Accounting / Compliance |
| `/item-catalog` | 4 | Item Categories · Units of Measure · Items · Services |
| `/inventory-movements` | 4 | Inventory Movements · Inventory Subsidiary Ledger · Stock Movement · Inventory Ledger |
| `/ar-aging` | 4 | AR Aging / Customer Ledger · Customer Ledger (Accounting View) · AR Subsidiary Ledger · AR Aging |
| `/ap-aging` | 4 | AP Aging / Supplier Ledger · Supplier Ledger (Accounting View) · AP Subsidiary Ledger · AP Aging |
| `/purchase-registers` | 3 | Purchase Registers · Purchase Register · Payment Register |
| `/period-closing` | 3 | Period Closing · Fiscal Locks · Period Close Checklist |
| `/ewt-summary` | 3 | EWT Summary · EWT Payable Summary · EWT Summary *(same label twice)* |
| `/asset-register` | 3 | Asset Register · Fixed Asset Register · Fixed Asset Register *(same label twice)* |
| `/2307-received-review` | 3 | 2307 Received Review · 2307 Certificates Received · 2307 Received Listing |
| `/2307-issued-review` | 3 | 2307 Issued Review · 2307 Certificates Issued · 2307 Issued Listing |
| `/warehouses` | 2 | Warehouses · Warehouses *(identical label, two menus)* |
| `/vat-output-summary` | 2 | Output VAT Summary ×2 *(identical label)* |
| `/vat-input-summary` | 2 | Input VAT Summary ×2 *(identical label)* |
| `/sls` | 2 | SLS ×2 *(identical label)* |
| `/petty-cash-funds` | 2 | Petty Cash Fund Setup ×2 *(identical label)* |
| `/inventory-valuation` | 2 | Inventory Valuation ×2 *(identical label)* |
| `/journal-entries` | 2 | **General Ledger Entries · Journal Entries** |
| `/department-setup` | 2 | Department Setup · Cost Centers |
| `/fiscal-years` | 2 | Fiscal Years · Fiscal Calendar |
| `/currency-setup` | 2 | Currency Setup · Exchange Rates |
| `/general-ledger` | 2 | General Ledger · General Ledger Book |
| `/pt-summary-register` | 2 | PT Summary Register · Percentage Tax Summary |
| `/outstanding-checks` | 2 | Outstanding Checks · Outstanding Checks Report |
| `/books-general-journal` | 2 | General Journal · Journal Register |
| `/bank-reconciliation` | 2 | Bank Reconciliation · Bank Reconciliation Summary |
| `/cas-user-activity-log` | 2 | User Activity Log · User Activity Report |

**Seven routes carry the IDENTICAL label twice** (`warehouses`, `vat-output-summary`,
`vat-input-summary`, `sls`, `petty-cash-funds`, `inventory-valuation`, and — with a one-word
difference — `ewt-summary`, `asset-register`). These are pure menu padding with no informational
value and should be removed outright.

### J. Requires architectural decision

The mission's named ambiguities, resolved against evidence:

| # | Question | Evidence | Finding | Recommended treatment |
| --- | --- | --- | --- | --- |
| J-1 | Should **Assets** parent Cash Management, Inventory, and Fixed Assets? | NAV has three top-level domains with three feature gates; docs folders 07/08/09; certification modules #5/#6/#7 | **Already answered NO by the repository.** Documentation never recorded it. | **P0** — ratify the split; retire "Assets". |
| J-2 | Should **Banking/Treasury** be its own top-level domain? | It already is (`banking_module` gate); 12 tables; own doc folder; own certification phase (5) | **Already YES.** | Ratify. Keep it separate from Purchasing/AP even though Check Vouchers pay suppliers. |
| J-3 | **Duplicated Items and Warehouses** | Items: resolved silently in favour of Master Data (Inventory menu lists Stock Balance instead). Warehouses: NOT resolved — identical label + route in two menus | Half-resolved. | Resolve Warehouses the same way: Master Data owns the master; Inventory links to it. |
| J-4 | **Customer/Supplier Ledger in business and accounting views** | Both "views" are literally the same page (`/ar-aging`, `/ap-aging`); four labels each | The blueprint's separation was dropped without deciding whether the accounting view's distinct requirements (control tie-out, posting-state basis, cut-off) still apply. | **P1** — either build a real accounting-basis subsidiary ledger, or state that the merged view IS the subsidiary ledger and certify it as such. |
| J-5 | **Trial Balance under Accounting and Reports** | One route, four labels; no adjusted/post-closing state exists | Duplication is cosmetic; the real gap is that Adjusted and Post-Closing TB cannot be produced. | Keep one TB page; remove the two unachievable labels until closing is certified. |
| J-6 | **VAT/EWT summaries under modules, Compliance, and Reports** | `/vat-output-summary` ×2, `/vat-input-summary` ×2, `/ewt-summary` ×3 | Triplication by design intent (module review vs statutory summary vs report) but implemented as one page each. | Decide once: either three purpose-built surfaces, or one surface referenced from three menus with an explicit "same page" affordance. |
| J-7 | **General Ledger Entries vs Journal Entries** | Two nav labels → `/journal-entries`; two doc files (`00. General Ledger Entries.md`, `01. Journal Entries.md`) | Same object, two names, two documents. | **P1** — retire "General Ledger Entries" as a transaction name; reserve "General Ledger" for the ledger view. |
| J-8 | **Receipts vs Official Receipts vs Collections** | Three names across nav, Transaction Matrix, and workspace registry | One object, three names. In PH practice "Official Receipt" is the statutory term. | **P1** — canonical name "Official Receipt (OR)"; alias "Receipt", "Customer Collection". |
| J-9 | **Receiving Report vs Goods Receipt** | Workspace registry carries both | One object, two names. | Canonical "Receiving Report"; alias "Goods Receipt". |
| J-10 | **Payment Voucher vs Vendor Payment** | Workspace registry carries both | One object, two names. | Canonical "Payment Voucher"; alias "Vendor Payment". |
| J-11 | **Department Setup and Cost Centers on one surface** | One route, two labels, two tables (departments cp,13; cost_centers cp,10), both certified dimensions | Sound merge. | Ratify; rename the menu group to match the page title. |
| J-12 | **Inventory module vs Inventory Accounting Engine** | Module: stock_balances/inventory_transactions cp, real posting RPCs. Engine: 20 `dormant-foundation` tables, 0 rows, 0 consumers, WP-1…WP-4 certified, WP-5 rejected | **Two different things sharing one name.** `AI_PROGRESS.md` shows "Inventory Engine 44%" which measures the DORMANT one. | **P0** — name them distinctly everywhere: "Inventory Module" vs "Inventory Accounting Engine (IA-5/ECC)". |
| J-13 | **Accounting Core vs Posting Engine vs Kernel** | Accounting Core = module #2 (In Progress). Posting Engine = engine #1 (Blocked at P6). Kernel Totality Guard = the P5.2 enforcement layer inside the Posting Engine (fully enforced, `ENABLE ALWAYS`, 6 sanctioned mutators) | Three distinct scopes, routinely conflated. `AI_PROGRESS.md` shows "Accounting Kernel 100%" beside "Posting Engine 25%" — the same subsystem at two numbers. | **P0** — define the containment relationship once: Kernel ⊂ Posting Engine ⊂ Accounting Core. |
| J-14 | **Tax module vs Compliance workspace vs missing Tax Engine** | No Tax Engine exists (test 090). Tax Setup = reference masters. Compliance = 66 read/report surfaces. Calculation lives in **seven duplicated save-layer calculators** | The blueprint has no Tax Engine node, so the gap is invisible in it. | **P0** — add "Tax Engine" to the authoritative architecture as an explicitly ABSENT component with a named owner. |

---

## 5. Repository Features Absent From the Original Blueprint

```text
PXL ERP — MATERIAL REPOSITORY ADDITIONS
│
├─ A. SHARED ENGINES  (hidden; must never appear as user menu entries)
│  │
│  ├─ Permissions / RLS Engine                    ✅ CERTIFIED 2026-07-22 (1st)
│  │     Business: no company can ever see another company's books.
│  │     Technical: RLS on 176/176 base tables, 473 policies, default-deny
│  │       (anon has zero data privileges), all 335 SECURITY DEFINER functions
│  │       pin search_path, all 21 authenticated views security_invoker.
│  │     Status: Certified · Nav: NO · Home: PXL SHARED ENGINES
│  │     Note: remediated Critical PXL-AUD-069 (cross-company reporting-view
│  │       leak) during its own review. Branch isolation is opt-in by design.
│  │
│  ├─ Audit & Immutability Engine                 ✅ CERTIFIED 2026-07-23 (2nd)
│  │     Business: posted records can never be silently changed.
│  │     Technical: sys_audit_logs (cp,2161) append-only, 79 tables carry
│  │       fn_audit_trigger, 42 header + 18 line posted-document guards,
│  │       transaction_events (cp,289) tamper-proof to authenticated.
│  │     Status: Certified · Nav: only its READ surfaces (CAS logs) · Engine hidden
│  │     Note: remediated Critical PXL-AUD-070 — the `pxl.allow_demo_reset` GUC
│  │       was settable by `authenticated`, letting a member mutate posted
│  │       documents. Now gated on a privileged session_user.
│  │
│  ├─ Number Series Engine                        ✅ CERTIFIED 2026-07-23 (3rd)
│  │     Business: BIR-acceptable, gap-free, never-reused document numbers.
│  │     Technical: fn_next_document_number under FOR UPDATE, ATP-bounded,
│  │       24 binding triggers, ~25 consumers, 10×20→200 distinct proven.
│  │     Status: Certified · Nav: its SETUP surface only (/number-series)
│  │
│  ├─ Dimension Engine                            ✅ CERTIFIED 2026-07-23 (4th)
│  │     Business: every peso can be attributed to branch, department, cost
│  │       centre, project, location, and functional entity — and the totals
│  │       still add up to the company total.
│  │     Technical: six governed dimension masters; fn_is_valid_dimension;
│  │       fn_je_line_dimensions_guard rejects cross-company (non-vacuous);
│  │       vw_gl_dimension_summary + fn_report_gl_by_dimension reconcile
│  │       EXACTLY to the undimensioned control total; reversal preserves all six.
│  │     Status: Certified · Nav: NO (masters appear; the engine does not)
│  │     Gap: the four Management Reports do NOT use fn_report_gl_by_dimension.
│  │
│  ├─ Posting Engine (P1 … P5.2)                  🟡 Blocked at P6
│  │     Business: one guarded doorway into the General Ledger.
│  │     Technical: P1 inert infra · P2 resolver adoption · P3 pure persistence
│  │       helper + manual-JE control + preview convergence · P4 tax boundary
│  │       certification (test 090) · P5.0 external write-surface closure ·
│  │       P5.1 all 24 forward writers + 4 legacy header paths drained of direct
│  │       ledger DML · P5.2 FULLY ENFORCED.
│  │     Status: engine In Progress / Blocked at P6 by Inventory reconciliation
│  │     Nav: NO · Home: PXL ACCOUNTING INFRASTRUCTURE
│  │
│  ├─ Kernel Totality Guard                       🟢 FULLY ENFORCED (P5.2)
│  │     Business: it is not possible to write to the ledger by any other route.
│  │     Technical: compile-time `true`; both totality triggers ENABLE ALWAYS;
│  │       client ledger DML and guard execution revoked; 48 bypass attempts all
│  │       reject (12×42501, 36×23514); exactly six sanctioned classifiers;
│  │       test 102 pins 418 app functions / 355 SECURITY DEFINER; zero violations.
│  │       Control table sys_posting_guard_violations is `control-empty` — ANY row
│  │       is evidence of a non-kernel ledger mutation.
│  │     Status: enforced, inside the Posting Engine scope; not separately certified
│  │     Nav: NO — and it must never be shown to users.
│  │     ⚠ `AI_PROGRESS.md` reports this as "Accounting Kernel 100%" as though it
│  │       were a peer of the Posting Engine. It is a component of it (§4 J-13).
│  │
│  ├─ COA Engine (Phase A)                        🟡 In Progress
│  │     Business: one governed answer to "which account does this post to?"
│  │     Technical: ref_mapping_key (rp,9) + account_mapping (cp,45) +
│  │       deterministic, fail-closed, ambiguity-rejecting fn_resolve_account;
│  │       account lifecycle draft/active/deprecated/archived/locked with a
│  │       transition guard; immutable-once-used account_type/normal_balance;
│  │       no-delete-with-posted-history; FS registry (fs_structure,
│  │       account_fs_map); fn_provision_pxl_standard_coa PH-SME fixture.
│  │     Status: NOT Certified — Phase A rewires no consumer, so gates 2/4 are
│  │       unsatisfiable; Phase B under way (Sales P2A, Purchasing P2B migrated,
│  │       each proven equivalence-identical).
│  │     Nav: only /chart-of-accounts + /gl-posting-config
│  │
│  ├─ AR Engine · AP Engine · Payment & Application Engine   🟡 In Progress ×3
│  │     Business: subledgers that tie to their control accounts.
│  │     Technical: fn_ar_aging_asof / fn_ap_aging_asof (reversal-aware as-of),
│  │       fn_ar_subledger_gl_reconciliation_asof / fn_ap_… exist.
│  │     Status: none certified — subledger-to-control reconciliation across
│  │       scenarios is unproven; over-application and unapplied cash uncertified.
│  │     Nav: NO (their surfaces are /ar-aging, /ap-aging, /payment-vouchers)
│  │
│  ├─ Approval / Workflow Engine                  🟡 In Progress
│  │     Technical: MDP-14 deterministic role/user routing, request lifecycle,
│  │       concurrency, SOD, audit RPCs, inbox; MDP-15 import integration is the
│  │       ONE proven consumer. approval_requests/approval_instances (wd,0).
│  │     Nav: /approval-workflow (config + inbox)
│  │
│  ├─ Period Lock & Closing Engine                🟡 In Progress
│  │     Technical: fiscal_periods.is_locked; automatic year + 12-period
│  │       generation (MDP-06). Year-end close and audited reopening uncertified.
│  │
│  ├─ Reversal / Void / Correction Engine         🟡 In Progress
│  │     Technical: fn_reverse_je, fn_reverse_posted_journal_entry (preserves all
│  │       six dimensions), fn_void_sales_invoice / fn_void_vendor_bill,
│  │       void_reason_codes (rp,7), immutable cas_document_void_events.
│  │     Gap: only SI and VB have a void path.
│  │
│  ├─ Reporting & Reconciliation Engine           🟡 In Progress
│  │     Technical: 23 views incl. vw_general_ledger, vw_trial_balance,
│  │       vw_customer_ledger, vw_supplier_ledger, the four VAT/WHT views, the
│  │       five registers; server-attested hashed snapshots
│  │       (fn_snapshot_books_export / _vat_export / _wht_export /
│  │       _cas_export / _cas_audit_package) into report_snapshots (wd,0).
│  │     Gap: NONE of the nine Critical Reconciliations is evidenced.
│  │
│  ├─ Attachment & Document Traceability Engine   🟡 In Progress
│  │     Technical: MDP-15 import/export batch provenance + content hashes;
│  │       cas_attachment_register (fd,0) has no workflow.
│  │
│  ├─ Document Conversion Engine                  ⚪ Not Started
│  │     Quote→Order→Delivery→Invoice and PO→RR→Bill chains are NOT certified.
│  │     This is why Quotations / Sales Orders / Delivery Receipts are all 🟡.
│  │
│  ├─ Currency Engine                             ⚪ Deferred
│  │     Multi-currency is explicitly NOT supported for production.
│  │     currencies (rp,9) usable; exchange_rates (re,0) intentionally empty.
│  │
│  └─ **Tax Engine**                              🔴 DOES NOT EXIST
│        Business: there is no single authority that computes Philippine tax.
│        Technical (verified against the live catalog, asserted permanently by
│          test 090): no tax-engine function, no central calculator, no
│          `TaxComponent` type. 20 tax-aware writers censused: 0 read
│          company_accounting_config, 19 do no tax arithmetic, the 5 reading
│          atc_codes.rate use it as PROVENANCE ONLY, and fn_save_cash_sale is
│          the SOLE computing writer. The same VAT computation is duplicated
│          across SEVEN save-layer calculators; VAT-inclusive treatment exists
│          in only ONE of the seven.
│        What IS certified: the BOUNDARY around the absent engine — the Posting
│          Engine computes no tax, the COA Resolver owns tax accounts, the Tax
│          Ledger owns tax detail and reversal, and ledger-to-GL reconciliation
│          is ZERO-VARIANCE for VAT and withholding on both fixture and canonical.
│        Status: Blocked — registered as a governed future program in the backlog.
│        Nav: NO. Home: PXL SHARED ENGINES (as an explicit absence).
│
├─ B. ACCOUNTING INFRASTRUCTURE  (hidden)
│  ├─ Source-to-journal traceability              🟢 REACHABLE WITH NO MENU ENTRY
│  │     /accounting-trace + /accounting-source — the ONLY two routes in the
│  │     product with no navigation entry at all.
│  │     RT fn_get_accounting_trace, fn_get_report_trace_set; supporting
│  │     components AccountingTraceLink.tsx, GLImpactPanel.tsx.
│  │     Business: from any report figure, reach the source document and back.
│  │     Verdict: a genuinely valuable, finished capability that is INVISIBLE.
│  │     Recommendation: surface it under Accounting (§8).
│  ├─ Document relationships                      🟢 RelatedDocumentsTab.tsx
│  ├─ Field-change history                        🟢 sys_audit_logs old/new JSONB
│  ├─ GL preview (Preview ≡ Actual)               🟡 fn_preview_gl_impact, used by
│  │     16 pages; full Preview ≡ Actual convergence is deferred to Posting P8.
│  ├─ Tax ledger                                  🟢 tax_detail_entries (cp,24),
│  │     fn_add_tax_detail; zero-variance to GL.
│  └─ Transaction workspace standard              🟢 33-row executable registry
│        (src/lib/transactionWorkspaceCoverage.ts) + 14 required tabs + A–E
│        patterns + dimension/sidebar sets. **32 of 33 rows carry
│        fieldSourceGate: 'transaction-matrix-only'** — only Sales Invoice has a
│        reviewed field-source slice.
│
├─ C. GOVERNANCE / CERTIFICATION INFRASTRUCTURE  (hidden; documentation-side)
│  ├─ Module Certification Standard (23 gates)    🟢 Tier 1
│  ├─ Engine Certification Standard               🟢 Tier 1
│  ├─ Product Completeness Checklist              🟢 Tier 1 (feeds gates 1 and 22)
│  ├─ Certification Matrix (11 modules, 19 engines) 🟢 dashboard only
│  ├─ Table Coverage Governance                   🟢 CERTIFIED-QUALITY CONTROL
│  │     PXL_TABLE_COVERAGE_MATRIX.md + deterministic guard
│  │     supabase/tests/075 — fails on an unclassified table, a stale entry, an
│  │     expected-populated table that is empty, or a deferred table that
│  │     silently became populated. This is the single most effective
│  │     anti-overstatement control in the repository and the blueprint has
│  │     nothing like it.
│  ├─ Findings register (92/92 Retested Passed)   🟢 Tier 1
│  ├─ Governance authority map (PG-01)            🟢 non-normative
│  └─ AI_STATE / AI_LAST_SESSION / AI_PROGRESS    🟢 Tier 0 hand-off layer
│        AI_STATE = bounded next task; AI_LAST_SESSION = full mission hand-off
│        (overwritten, never appended); AI_PROGRESS = executive dashboard.
│        Assessed in §11.
│
├─ D. USER-FACING ADDITIONS  (belong in navigation)
│  ├─ Global Feature Enablement    🟢 /feature-enablement — gates whole top-level
│  │     menus (accounts_receivable, accounts_payable, inventory_management,
│  │     banking_module, fixed_assets). ref_feature_definitions (rp,16).
│  ├─ Stock Balance                🟢 /stock-balance — stock_balances (cp,11) +
│  │     inventory_cost_layers (cp,12). Real, exercised, not in the blueprint.
│  ├─ Check Vouchers               🔵 /check-vouchers — check_vouchers (fd,0) +
│  │     check_voucher_lines (fd,0). A whole disbursement instrument the
│  │     blueprint never named, placed in Banking rather than Purchasing.
│  ├─ Report Snapshots             🔵 /report-snapshots — report_snapshots (wd,0);
│  │     server-attested hashed export evidence.
│  ├─ System Audit Log             🟢 /audit-log (Setup ▸ System) — a second
│  │     entry point to sys_audit_logs beside the four CAS log pages.
│  └─ Company Provisioning Wizard  🟢 CompanyProvisioningWizard.tsx +
│        CompanySetupChecklist.tsx + SetupReadiness.tsx — guided MDP-08
│        provisioning with explicit Core Accounting / Operational / Production
│        readiness stages (PXL-AUD-067). Not a blueprint concept at all.
│
├─ E. HIDDEN TECHNICAL FOUNDATION
│  ├─ 202-table schema with RLS on every base table and 473 policies
│  ├─ 398 functions / 324 triggers / 23 views
│  ├─ 110 pgTAP files across named lanes (fresh-schema, focused, regression,
│  │     local, canonical, hosted-read-only, hosted-ui, docs, lint, build, diff)
│  ├─ Canonical demo dataset (5 companies; ABC Trading high-volume)
│  ├─ Frontend secret guard (check_frontend_secrets.mjs, runs before AND after build)
│  └─ Generated schema summary + docs-consistency checker (docs:check)
│
└─ F. FUTURE / DEFERRED SCAFFOLD
   └─ IA-5 / ECC Inventory Accounting Chronology Foundation   ⚪ DORMANT
      │  Business: before inventory cost can be replayed reliably, the system
      │    must be able to answer "when two receipts, issues, or corrections
      │    carry the same date and time, which one must accounting process
      │    first, and why?" That is what this foundation stores.
      │  Technical: 20 `dormant-foundation` tables, ALL empty, ALL prohibited
      │    from population, zero consumers, zero accounting effect.
      ├─ IA-5 foundation (11 tables)  — landed dormant; claim SUSPENDED by C-01
      │     C-01 (Critical): the accepted sequence was allocated by ROW-LOCK
      │     ORDER, so identical same-time evidence produced OPPOSITE orders
      │     across schedules. Not economic order. Permanent-foundation defect.
      ├─ ADR-C01  — FROZEN (dual-chronology decision)
      ├─ ECC-01   — owner ACCEPTED 2026-07-26, **not frozen**
      ├─ WP-1 policy/version foundation (6 tables)   ✅ CERTIFIED 2026-07-29
      ├─ WP-2 source registry authority             ✅ CERTIFIED 2026-07-30
      ├─ WP-3 valuation stream + accepted allocator ✅ CERTIFIED 2026-07-31
      ├─ WP-4 persisted economic order key          ✅ CERTIFIED 2026-07-31
      ├─ WP-5 component resolver     ❌ AUTHORISATION REJECTED (WP5-AG-001…003)
      ├─ WP-6 … WP-9                 ⬜ UNAUTHORISED
      └─ IA-6 (costing, layers, FIFO/WAC)  ⬜ UNAUTHORISED
         Nav: NO — and must NEVER appear. Home: PXL ACCOUNTING INFRASTRUCTURE
           (dormant sub-tree).
         ⚠ These four work-package certifications certify four bounded dormant
           change sets. They do NOT lift C-01, do NOT certify the IA-5
           permanent foundation, and do NOT certify the Inventory module or the
           Inventory Engine.
```

---
## 6. UI vs Repository Reconciliation

### 6.1 Method

Every navigation entry was resolved to its route, its page component, the base tables that component
actually queries, the coverage class of each of those tables, the RPCs the component calls, and the
governing certification status. Verdicts use the allowed set only.

### 6.2 Reconciliation table — representative rows per verdict

The full 242-entry table is mechanically derivable from `AppShell.tsx` + `App.tsx` +
`PXL_TABLE_COVERAGE_MATRIX.md`; the rows below are the decision-bearing ones.

| Original blueprint item | Current nav entry | Current route | Current page | DB support | Runtime support | Tests | Certification | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sales Invoices | Sales ▸ Transactions ▸ Sales Invoices | `/sales-invoices` (+3) | SalesInvoicePage, SalesInvoiceDocumentPage | cp 75/135 | save/approve/post/void/revert | 080, AUD-053 | None | **Fully aligned** |
| Vendor Bills | Purchasing ▸ Vendor Bills | `/vendor-bills` | VendorBillsPage | cp 36/36 | save/approve/post/void/revert | 049, 080 | None | **Fully aligned** |
| Journal Entries | Accounting ▸ Journal Entries | `/journal-entries` | JournalEntriesPage | cp 48/138 | post/reverse | 080, 102 | Dimension Engine (bounded) | **Fully aligned** |
| Chart of Accounts | Setup ▸ Chart of Accounts | `/chart-of-accounts` | ChartOfAccountsPage | cp 215 | resolver, lifecycle | 081 | None | **Fully aligned** |
| Personnel / Employees Lite | Master Data ▸ Employees | `/employees` | EmployeesPage | cp 26 | CRUD | canonical | None | **Renamed but aligned** |
| Depreciation | Fixed Assets ▸ Depreciation Run | `/depreciation-run` | DepreciationRunPage | **fd 0** | fn_post_depreciation_entry | — | None | **Scaffold/deferred** |
| Cash Management | *(node gone)* → Banking & Treasury | — | — | 12 tables **fd 0** | — | 075 | Not Started | **Moved but aligned** *(node)* / **Scaffold** *(contents)* |
| Company Bank Accounts | *(disabled)* → Master Data ▸ Bank Accounts | `/bank-accounts` | BankAccountsPage | cp 10 | CRUD | canonical | None | **Moved but aligned** |
| ATP Monitoring | *(disabled)* → Compliance ▸ ATP Usage Log | `/cas-atp-usage-log` | CASATPUsageLogPage | cp 215 via view | allocator bound | 079, 030 | Number Series (bounded) | **Moved but aligned** |
| Customer Contacts | *(no entry)* | — | — | **wd 0** party_contacts | none | 075 | None | **Repository ahead of UI** |
| Financial Statement Fields | *(disabled)* | — | — | **wd 0** fs_structure/account_fs_map | none | 081 | None | **Repository ahead of UI** |
| Inventory Settings | *(disabled)* | — | — | **wd 0** company_inventory_config | none | 075 | None | **Repository ahead of UI** |
| *(none)* | *(no entry)* | `/accounting-trace`, `/accounting-source` | AccountingTracePage, AccountingSourcePage | cp via RPC | fn_get_accounting_trace | — | None | **Repository ahead of UI** |
| Debit Memos | Sales ▸ Debit Memos | `/debit-memos` | DebitMemosPage | **fd 0** | fn_save_debit_memo | — | None | **UI ahead of repository** |
| Goods Issue | Inventory ▸ Goods Issue | `/goods-issue` | GoodsIssuePage | **fd 0** | fn_post_goods_issue | 080 cites it | Dimension Engine cites it | **Needs architectural decision** |
| 2307 Issued Review | Purchasing / Compliance / Reports (×3) | `/2307-issued-review` | Form2307IssuedPage | **fd 0** | generate/supersede/status | — | Matrix says "Implemented" | **Needs architectural decision** |
| VAT Return 2550M | Compliance ▸ VAT | `/vat-return-2550m` | VATReturn2550MPage | **fd 0** vat_returns + real views | none | — | Matrix says "Implemented" | **Needs architectural decision** |
| Opening Balances | *(disabled)* | — | — | **none** | none | — | None | **Missing** |
| CAS Registrations | *(disabled)* | — | — | **none** | none | — | None | **Missing** |
| Supplier Bank Details | *(no entry)* | — | — | **none** | none | — | None | **Missing** |
| Budget Settings | *(disabled)* | — | — | **none** | none | — | None | **Missing** |
| EWT Codes | Setup ▸ Tax Setup ▸ EWT Codes | `/tax-setup` | TaxSetupPage | rp 18 (atc_codes) | upsert/set_active | MDP-12 | None | **Superseded** |
| FWT Codes | Setup ▸ Tax Setup ▸ FWT Codes | `/tax-setup` | TaxSetupPage | rp 18 (atc_codes) | upsert/set_active | MDP-12 | None | **Superseded** |
| Trial Balance ×4 labels | Accounting + Reports ×3 | `/trial-balance` | TrialBalancePage | cp via view | fn_trial_balance_report | — | None | **Duplicate navigation** |
| AR Aging / Customer Ledger ×4 | Sales + Accounting + Compliance + Reports | `/ar-aging` | ARAgingPage | cp 66 + view | fn_ar_aging_asof | — | None | **Duplicate navigation** |
| Warehouses ×2 (identical label) | Master Data + Inventory | `/warehouses` | WarehousesPage | cp 6 | CRUD | canonical | None | **Duplicate navigation** |
| Inventory Valuation | Inventory + Reports | `/inventory-valuation` | InventoryValuationPage | cp 12/11 | read-only | P6 investigation | None | **Needs architectural decision** *(does not reconcile)* |

### 6.3 The 33 reachable routes backed EXCLUSIVELY by deferred tables

Every page below queries **only** `future-deferred` tables. Each renders, and each can only ever show
an empty state under the governed dataset. This is the precise, executable answer to "reachable
routes backed only by future-deferred tables".

| # | Route | Page | Backing tables (all `future-deferred`, 0 rows) |
| ---: | --- | --- | --- |
| 1 | `/asset-register` | AssetRegisterPage | fixed_assets, asset_depreciation_entries |
| 2 | `/fixed-asset-dashboard` | FixedAssetDashboardPage | fixed_assets, asset_depreciation_entries |
| 3 | `/depreciation-run` | DepreciationRunPage | asset_depreciation_entries |
| 4 | `/reports-depreciation-schedule` | DepreciationScheduleReportPage | fixed_assets, asset_depreciation_entries |
| 5 | `/reports-book-vs-tax-depreciation` | BookVsTaxDepreciationReportPage | fixed_assets, asset_depreciation_entries |
| 6 | `/reports-asset-disposal` | AssetDisposalReportPage | asset_disposals |
| 7 | `/cash-count-sheet` | CashCountSheetPage | cash_count_sheets, petty_cash_funds, petty_cash_vouchers |
| 8 | `/reports-check-register` | CheckRegisterReportPage | check_vouchers |
| 9 | `/cas-attachment-register` | CASAttachmentRegisterPage | cas_attachment_register |
| 10 | `/cas-dat-file-generation` | CASDATFileGenerationPage | cas_export_log |
| 11 | `/cas-export-history` | CASExportHistoryPage | cas_export_log |
| 12 | `/ewt-working-papers` | EWTWorkingPapersPage | compliance_ewt_working_papers_headers/lines |
| 13 | `/wt-1601eq-working-papers` | EWT1601EQWorkingPapersPage | compliance_1601eq_working_papers_headers/lines |
| 14 | `/wt-1601eq-return` | EWT1601EQReturnPage | ewt_returns |
| 15 | `/wt-fwt-working-papers` | FWTWorkingPapersPage | compliance_fwt_working_papers_headers/lines |
| 16 | `/wt-1601fq-working-papers` | FWT1601FQWorkingPapersPage | compliance_1601fq_working_papers_headers/lines |
| 17 | `/wt-1601fq-return` | FWT1601FQReturnPage | fwt_returns, form_2306_issuances |
| 18 | `/wt-2306-certificates` | Form2306Page | form_2306_issuances, bank_adjustments |
| 19 | `/reports-fwt-summary` | FWTSummaryReportPage | form_2306_issuances |
| 20 | `/pt-working-papers` | PTWorkingPapersPage | compliance_pt_working_papers_headers/lines |
| 21 | `/pt-summary-register` | PTSummaryRegisterPage | pt_returns |
| 22 | `/vat-working-papers` | VATWorkingPapersPage | compliance_vat_working_papers_headers/lines |
| 23 | `/2307-issued-review` | Form2307IssuedPage | form_2307_issuances |
| 24 | `/inc-tax-computation` | TaxableIncomeComputationPage | income_tax_computations |
| 25 | `/inc-tax-book-to-tax-recon` | BookToTaxReconciliationPage | book_tax_reconciliation |
| 26 | `/inc-tax-osd` | OSDComputationPage | income_tax_computations |
| 27 | `/inc-tax-nolco` | NOLCOSchedulePage | nolco_schedule |
| 28 | `/inc-tax-credits` | TaxCreditsSchedulePage | tax_credits_schedule |
| 29 | `/inc-tax-1701q` | ITR1701QPage | itr_filings |
| 30 | `/inc-tax-1701` | ITR1701Page | itr_filings |
| 31 | `/inc-tax-1702q` | ITR1702QPage | itr_filings |
| 32 | `/inc-tax-1702rt` | ITR1702RTPage | itr_filings |
| 33 | `/inc-tax-mcit` | MCITComputationPage | mcit_computations |

A further ~20 routes are *mixed* — they read at least one canonical table plus at least one deferred
table, so they render partial data whose completeness the user cannot assess. The most
consequential are `/books-cash-disbursements` (check vouchers structurally absent from the BIR cash
disbursements book), `/statement-of-cash-flows` (the entire fixed-asset/depreciation section is
empty), and `/period-closing` (two close checks can never fire).

### 6.4 The 18 disabled navigation placeholders

Exact and complete. These render greyed and unclickable (`disabled={!mod.page}`).

| # | Menu path | Backend reality | Correct treatment |
| ---: | --- | --- | --- |
| 1 | Setup ▸ Organization ▸ CAS Registrations | **No table** | Missing — decide (§4.H) |
| 2 | Setup ▸ Organization ▸ Company Bank Accounts | Fully built at `/bank-accounts` | **Remove — the feature moved** |
| 3 | Setup ▸ System Controls ▸ ATP Monitoring | Built; lives at `/cas-atp-usage-log` | **Remove — the feature moved** |
| 4 | Setup ▸ System Controls ▸ Inventory Settings | `company_inventory_config` (wd,0) exists | Backend ahead of UI |
| 5 | Setup ▸ System Controls ▸ Fixed Assets Settings | No table | Future roadmap |
| 6 | Setup ▸ System Controls ▸ Petty Cash Settings | No settings table | Future roadmap |
| 7 | Setup ▸ System Controls ▸ Bank Reconciliation Settings | No table | Future roadmap |
| 8 | Setup ▸ System Controls ▸ Budget Settings | **No budget table anywhere** | Future roadmap — remove from Setup |
| 9 | Setup ▸ Document & Validation ▸ Status Controls | Enforced in RPCs + 60 guards | Backend ahead of UI |
| 10 | Setup ▸ Document & Validation ▸ Posting Controls | Enforced by Kernel + assertions | Backend ahead of UI |
| 11 | Setup ▸ Document & Validation ▸ Void Controls | `void_reason_codes` (rp,7) + void RPCs | Backend ahead of UI |
| 12 | Setup ▸ Document & Validation ▸ Reversal Controls | `fn_reverse_je` + `/reversal-review` | Backend ahead of UI |
| 13 | Setup ▸ Document & Validation ▸ Master Data Rules | 1,033 seeded permission/role/SOD rows | Backend ahead of UI |
| 14 | Setup ▸ Document & Validation ▸ Transaction Rules | Enforced inside each save RPC | Backend ahead of UI |
| 15 | Setup ▸ Document & Validation ▸ Posting Validation Rules | `PostingValidationPanel.tsx` embedded in workspaces | Backend ahead of UI |
| 16 | Setup ▸ Document & Validation ▸ Period Controls | `fiscal_periods.is_locked` + `/period-closing` | Backend ahead of UI |
| 17 | Setup ▸ Accounting Setup ▸ Opening Balances | **No table, no import** | **Missing — P0 blocker** |
| 18 | Setup ▸ Accounting Setup ▸ Financial Statement Fields | `fs_structure`/`account_fs_map` (wd,0) + COA fs metadata | Backend ahead of UI |

**Pattern:** only 4 of 18 are genuinely absent capabilities. **Two are features that already
shipped elsewhere** (2, 3) and should simply be deleted. **Ten are enforcement that exists but is
not configurable** (4, 9–16, 18). The placeholder set therefore misrepresents the product in both
directions at once.

### 6.5 Implemented backend engines with no user-facing page — correct and intended

These must **never** become menu entries. Listing them here is the reconciliation, not a request to
surface them.

Permissions/RLS Engine · Audit & Immutability Engine (capture side) · Number Series Engine
(allocator) · Dimension Engine · Posting Engine P1–P5.2 · Kernel Totality Guard · COA resolver
(`fn_resolve_account`) · AR/AP/Payment engines · Reversal/Correction engine internals · Coverage
governance guard `075` · all 20 IA-5/ECC dormant tables.

The **two exceptions** that *should* be surfaced are `/accounting-trace` and `/accounting-source`:
they are user-facing capabilities (drill from a figure to its source document and back) that are
reachable but have no menu entry at all.

### 6.6 Routes that should be hidden until their workflows are source-backed

All 33 routes in §6.3, plus the mixed routes whose primary object is deferred:
`/petty-cash-funds`, `/petty-cash-vouchers`, `/petty-cash-replenishment`, `/fund-transfers`,
`/inter-branch-transfers`, `/bank-adjustments`, `/bank-reconciliation`, `/outstanding-checks`,
`/deposits-in-transit`, `/check-vouchers`, `/asset-acquisition`, `/asset-disposal`,
`/asset-transfer`, `/asset-impairment`, `/asset-categories`, `/goods-issue`, `/debit-memos`,
`/supplier-debit-memos`, `/purchase-returns`, `/recurring-journal-templates`,
`/amortization-schedules`, `/amortization-run`, `/revenue-recognition-schedules`,
`/revenue-recognition-run`, `/pt-return-2551q`, `/pt-reconciliation`, `/vat-return-2550m`,
`/vat-return-2550q`, `/vat-reconciliation`, `/wt-qap`, `/wt-sawt`, `/report-snapshots`.

**Recommendation (advisory, not implemented):** rather than deleting routes, mark them
`Coming Later` in navigation and drive that label from the coverage class, so the menu cannot drift
from the governance register. That single mechanism would close §10.J permanently.

---

## 7. Module / Engine / Infrastructure Classification

Routes, pages, tables, engines, work packages, modules, and certification scopes are **not
interchangeable**. This section keeps them apart.

### A. User-Facing Business Modules (11 — matching the certification matrix)

| # | Module | Certification status | Blueprint origin | Current top-level nav home |
| ---: | --- | --- | --- | --- |
| 1 | Setup and Master Data | **Blocked** (14 Pass / 3 Partial / 2 Blocked / 4 N/A / 0 Fail) | 2 Setup + 3 Master Data | Setup, Master Data |
| 2 | Accounting Core | In Progress | 7 Accounting | Accounting |
| 3 | Sales and Accounts Receivable | In Progress | 4 Sales | Sales |
| 4 | Purchasing and Accounts Payable | In Progress | 5 Purchasing | Purchasing |
| 5 | Inventory | In Progress | 6 Assets ▸ Inventory | Inventory |
| 6 | Banking and Treasury | Not Started | 6 Assets ▸ Cash Management | Banking & Treasury |
| 7 | Fixed Assets | Not Started | 6 Assets ▸ Fixed Assets | Fixed Assets |
| 8 | Accounting Schedules | Not Started | 7 ▸ Schedules | Accounting ▸ Schedules |
| 9 | Philippine Compliance and Tax | **Blocked** | 8 Compliance + 2 ▸ Tax Setup | Compliance |
| 10 | Reports and Financial Statements | In Progress | 9 Reports | Reports |
| 11 | Administration and Security | Not Started | **NOT IN THE BLUEPRINT** | *(no nav home)* |

**Module #11 has no blueprint origin and no navigation home.** Administration and Security exists as
a certification target with no surface: user/role administration, membership management, and branch
scope assignment have no page (`user_company_memberships` is written by triggers and seeds;
`user_company_branch_scopes` is `workflow-deferred` with 0 rows). This is an ownership gap (§12 P1-4).

### B. Shared Engines (19 — matching the certification matrix)

**Certified (4):** Permissions/RLS · Audit & Immutability · Number Series · Dimension.
**In Progress (10):** Inventory Engine · AR · AP · Payment & Application · Approval/Workflow ·
Period Lock & Closing · Reversal/Void/Correction · Reporting & Reconciliation · Attachment &
Traceability · COA.
**Blocked (2):** Posting Engine (at P6) · **Tax Engine (does not exist)**.
**Not Started (2):** Document Conversion · Backup and Recovery.
**Deferred (1):** Currency.

None appears in navigation, and none should — except through the surfaces it powers.

### C. Accounting Infrastructure (hidden, non-module)

Kernel Totality Guard (inside the Posting Engine) · `vw_general_ledger` / `vw_trial_balance` ·
posting source registry (`ref_posting_source_types`, rp 30) · tax ledger (`tax_detail_entries`) ·
`transaction_events` · `sys_posting_guard_violations` (control-empty) · source-to-journal
traceability RPCs · GL preview · document relationships · field-change history · the entire
20-table IA-5/ECC dormant chronology sub-tree.

### D. Compliance Workspaces (not modules, not engines)

Six workspaces under one Blocked module: Percentage Tax (5 surfaces) · VAT (11) · Withholding Tax
(15, including FWT) · Income Tax (11) · BIR Books of Accounts (13) · Audit & CAS (11).
A workspace is a **read/report/generate surface over posted data**, not an engine. None owns
calculation; calculation lives in the seven save-layer calculators (§5.A Tax Engine).

### E. Reporting Surfaces

`Reports` is an **alternate index**, not a layer: 31 of its 43 leaves re-point at routes owned by
business domains; only 12 resolve to Reports-exclusive routes, and 8 of those 12 are pure-deferred.
The genuinely Reports-exclusive, source-backed surfaces are exactly four: Bank Position Report,
Slow Moving Inventory, Branch P&L, Gross Margin Analysis — plus Audit Support Package.

### F. Governance and Certification Infrastructure

Module Certification Standard (23 gates) · Engine Certification Standard · Product Completeness
Checklist · Certification Matrix · Table Coverage Matrix + guard `075` · Findings register ·
PG-01 authority map · Documentation Index · AI_STATE / AI_LAST_SESSION / AI_PROGRESS · the eleven
named validation lanes · frontend secret guard · docs-consistency checker.

### G. Scaffold / Deferred Features

The 33 pure-deferred routes (§6.3) · the 61 `future-deferred` tables · the 21 `workflow-deferred`
tables · Check Vouchers · Report Snapshots · the 18 disabled placeholders (§6.4).

### H. Future Roadmap

Tax Engine (governed future program in the backlog) · Currency/multi-currency · Budgeting (no
schema at all) · Document Conversion Engine · Backup and Recovery · IA-6 costing/layers/FIFO/WAC ·
IA-5 WP-5…WP-9 · Posting Engine P5.3B / P6 / P7 / P8 (full Preview ≡ Actual) · COA Engine Phase B/C ·
the customizable executive dashboard widget grid · the frontend adoption of TanStack Query /
Zustand / react-hook-form / Zod (installed, **not adopted** — must not be described as current
architecture).

### I. Separate Products / Out of Current Scope

**Payroll.** Verified: the string "payroll" appears exactly once in the entire codebase — a comment
in `20260630000029_master_data_completion.sql` describing the employees master as holding
"payroll-relevant" identifiers. There is **no payroll table, page, route, RPC, test, blueprint
document, or certification row**. The Transaction Matrix lists "Future Payroll Run" with status
`Planned`. The `employees` master is a *lite* BIR-identifier master and is not a payroll module.

**Therefore Payroll must not be an active PXL ERP module and must not affect any completion metric.**
`AI_PROGRESS.md` currently gives Payroll its own 0% progress bar, which drags the weighted headline
down for a product line that was never in scope. §11 removes it.

**Also out of scope:** "Future AI Transaction / Assistant Action" (Transaction Matrix, `Planned`).
The architecture summary states plainly that **no Claude/Anthropic API integration exists** in the
application code.

---
## 8. Recommended Current Authoritative PXL ERP Tree

Advisory. Legend for the recommended tree:

`[NOW]` in current runtime, source-backed · `[LATER]` visible but explicitly marked "Coming Later"
· `[HIDE]` remove from navigation until source-backed · `[ENGINE]` never a user menu entry ·
`[DECIDE]` blocked on an architectural decision · `[ROADMAP]` future · `[OUT]` outside PXL scope.

### 8.1 Recommended user navigation

```text
PXL ERP
│
├─ Dashboard                                                            [NOW]
│     Why: single landing surface. What moved in: nothing. What was removed:
│     nothing. Keep the current setup-readiness + BIR-deadline content and stop
│     calling it "Executive"; the widget grid is [ROADMAP].
│
├─ Setup & Administration                                               [NOW]
│  │  Why: the blueprint's "Setup" plus the homeless certification module
│  │  #11 (Administration and Security), which today has NO surface at all.
│  │  Moved in: Administration/Users/Roles/Branch Scopes (new).
│  │  Removed: Company Bank Accounts (moved to Master Data), ATP Monitoring
│  │  (moved to Compliance), and the eight Document & Validation placeholders.
│  ├─ Organization
│  │  ├─ Company Setup                                                   [NOW]
│  │  ├─ Branch Setup                                                    [NOW]
│  │  ├─ Departments & Cost Centers                                      [NOW]
│  │  ├─ Compliance Profile                                              [NOW]
│  │  └─ CAS Registrations                                            [DECIDE]
│  ├─ Administration & Security                                       [DECIDE]
│  │  ├─ Users & Memberships · Roles · Branch Scopes
│  │        (certification module #11 has no page today — see §7.A)
│  ├─ System Controls
│  │  ├─ Number Series                                                   [NOW]
│  │  ├─ Feature Enablement                                              [NOW]
│  │  └─ Approval Workflow                                               [NOW]
│  ├─ Accounting Setup
│  │  ├─ Fiscal Years & Calendar                                         [NOW]
│  │  ├─ Chart of Accounts                                               [NOW]
│  │  ├─ GL Posting Configuration                                        [NOW]
│  │  ├─ Currency Setup                                                [LATER]  (FX deferred)
│  │  ├─ Financial Statement Structure                                 [LATER]  (registry exists, no UI)
│  │  └─ Opening Balances                                             [DECIDE]  (**no schema — P0**)
│  └─ Tax Setup
│     ├─ Tax Codes · VAT Codes · Percentage Tax Codes · ATC Codes        [NOW]
│     │     (EWT Codes and FWT Codes are ALIASES of ATC Codes — publish the
│     │      alias map; do not keep them as separate menu entries)
│     ├─ BIR Form Configuration                                        [LATER]
│     └─ Tax Calendar                                                    [NOW]
│
├─ Master Data                                                          [NOW]
│  │  Why: one home for every master. Moved in: Bank Accounts (from Setup),
│  │  Warehouses (sole owner — Inventory links here). Removed: the duplicate
│  │  Items and Warehouses entries under Inventory.
│  ├─ Parties ▸ Customers · Suppliers · Employees                        [NOW]
│  │     └─ Contacts (party_contacts master exists, no UI)             [LATER]
│  │     └─ Supplier Bank Details                                     [DECIDE]  (**no schema**)
│  ├─ Items & Services ▸ Item Catalog (categories, UoM, items, services) [NOW]
│  ├─ Inventory Master ▸ Warehouses · Warehouse Stock Settings           [NOW]
│  ├─ Banking ▸ Bank Accounts                                            [NOW]
│  └─ Shared ▸ Payment Terms                                             [NOW]
│
├─ Sales & Receivables                                                  [NOW]
│  ├─ Transactions ▸ Quotation → Sales Order → Delivery Receipt →
│  │                 Sales Invoice → Cash Sale → Official Receipt →
│  │                 Credit Memo                                         [NOW]
│  │     └─ Debit Memo · Customer Return                               [LATER]
│  ├─ Receivables ▸ AR Aging & Customer Ledger · Collection Monitoring   [NOW]
│  ├─ Tax Review ▸ Output VAT · Percentage Tax · 2307 Received           [NOW]
│  └─ Registers ▸ Sales Registers (tabbed) · SLS                         [NOW]
│        Removed: the four redundant per-register labels.
│
├─ Purchasing & Payables                                                [NOW]
│  ├─ Transactions ▸ Purchase Order → Receiving Report → Vendor Bill →
│  │                 Cash Purchase → Payment Voucher → Vendor Credit     [NOW]
│  │     └─ Supplier Debit Memo · Purchase Return                      [LATER]
│  ├─ Payables ▸ AP Aging & Supplier Ledger · Payment Monitoring         [NOW]
│  ├─ Tax Review ▸ Input VAT · EWT Summary · 2307 Issued                 [NOW]
│  └─ Registers ▸ Purchase Registers (tabbed) · SLP                      [NOW]
│
├─ Inventory                                                            [NOW]
│  │  Why: independent lifecycle, own feature gate, own certification phase (4).
│  │  Moved in: nothing new. Removed: duplicate Items and Warehouses masters
│  │  (link to Master Data instead).
│  ├─ Overview ▸ Inventory Dashboard · Stock Balance · Inventory Movements [NOW]
│  │     └─ Inventory Valuation                                       [DECIDE]
│  │           **Does not reconcile to the Inventory-control GL** (§3.6).
│  │           Showing it as a finished report is the most consequential
│  │           overstatement in the current navigation.
│  ├─ Transactions ▸ Stock Adjustment · Stock Transfer · Physical Count  [NOW]
│  │     └─ Goods Issue                                               [DECIDE]
│  └─ Setup ▸ (link to Master Data ▸ Warehouses)
│
├─ Banking & Cash Management                                          [LATER]
│  │  Why: ratifies the split from "Assets"; own feature gate; Phase 5.
│  │  ENTIRE DOMAIN is currently unexercised (12 tables, 0 rows). Every leaf
│  │  should carry the "Coming Later" affordance until Phase 5 runs.
│  ├─ Petty Cash ▸ Fund Setup · Vouchers · Replenishment · Cash Count   [LATER]
│  ├─ Bank Operations ▸ Fund Transfers · Inter-Branch Transfers ·
│  │                    Bank Adjustments · Bank Reconciliation ·
│  │                    Outstanding Checks · Deposits in Transit        [LATER]
│  └─ Disbursements ▸ Check Vouchers                                    [LATER]
│        (a repository addition; not in the original blueprint)
│
├─ Fixed Assets                                                       [LATER]
│  │  Why: ratifies the split; own feature gate; Phase 6.
│  │  ENTIRE DOMAIN unexercised (6 tables, 0 rows).
│  ├─ Overview ▸ Dashboard · Asset Register                             [LATER]
│  ├─ Transactions ▸ Acquisition · Depreciation Run · Disposal ·
│  │                 Transfer · Impairment                              [LATER]
│  └─ Setup ▸ Asset Categories                                          [LATER]
│        └─ Depreciation Profiles                                    [ROADMAP]  (no schema)
│
├─ Accounting                                                           [NOW]
│  ├─ Journal Entries ▸ Journal Entries                                  [NOW]
│  │     (retire the duplicate label "General Ledger Entries")
│  │     └─ Recurring Journal Templates                                [LATER]
│  ├─ Ledgers ▸ General Ledger · Account Detail Ledger · Trial Balance   [NOW]
│  ├─ Reconciliation ▸ Control Account Reconciliation                    [NOW]
│  ├─ **Accounting Trace** (source ⇄ journal drilldown)                  [NOW]
│  │     NEW MENU ENTRY for /accounting-trace + /accounting-source — today
│  │     these are the only reachable routes with NO navigation entry.
│  ├─ Schedules ▸ Amortization · Revenue Recognition                   [LATER]
│  └─ Period Management ▸ Period Closing & Fiscal Locks · Posting Review ·
│                         Reversal Review · Auto Reversal Run            [NOW]
│        └─ Amortization Run · Revenue Recognition Run                 [LATER]
│
├─ Compliance                                                           [NOW]
│  │  Split every branch into "review over posted data" [NOW] and "statutory
│  │  artifact generation" [LATER]. Today they are interleaved and
│  │  indistinguishable.
│  ├─ VAT ▸ Dashboard · Output/Input Summary · SLS · SLP · SLSP Export ·
│  │        RELIEF Export                                                [NOW]
│  │     └─ Working Papers · 2550M · 2550Q · Reconciliation            [LATER]
│  ├─ Withholding Tax ▸ Dashboard · EWT Payable/Receivable Summary ·
│  │                    ATC Summary · 2307 Issued · 2307 Received        [NOW]
│  │     └─ Working Papers · 1601EQ · QAP · SAWT                       [LATER]
│  │     └─ FWT ▸ Working Papers · 1601FQ · 2306                       [LATER]
│  ├─ Percentage Tax ▸ Dashboard · Review                                [NOW]
│  │     └─ Working Papers · 2551Q · Reconciliation · Summary Register [LATER]
│  ├─ Income Tax ▸ Dashboard                                             [NOW]
│  │     └─ everything else (10 leaves, all shells)                    [LATER]
│  ├─ BIR Books ▸ Dashboard · General Journal · General Ledger Book ·
│  │              Cash Receipts · Sales · Cash Sales · Purchase ·
│  │              Cash Purchases · AR/AP/Inventory Subsidiary Ledgers    [NOW]
│  │     └─ Cash Disbursements Book                                   [DECIDE]  (check vouchers absent)
│  │     └─ Fixed Asset Register                                       [LATER]
│  └─ Audit & CAS ▸ Dashboard · Transaction Audit Log · Master Data
│                   Change Log · System Parameter Logs · User Activity
│                   Log · Document Void Register · ATP Usage Log         [NOW]
│        └─ Attachment Register · DAT Generation · Export History ·
│           CAS Audit Report · Report Snapshots                        [LATER]
│
├─ Reports                                                              [NOW]
│  │  Why it shrinks: 31 of 43 blueprint leaves were re-pointers into other
│  │  domains. Reports should carry ONLY cross-domain analysis; every register
│  │  and ledger stays in its owning domain and is linked, not duplicated.
│  ├─ Financial Statements ▸ Balance Sheet · Income Statement ·
│  │                         Changes in Equity · Comparative FS           [NOW]
│  │     └─ Statement of Cash Flows                                   [DECIDE]  (FA section empty)
│  ├─ Trial Balance ▸ Trial Balance                                       [NOW]
│  │     └─ Adjusted TB · Post-Closing TB                              [LATER]  (closing uncertified)
│  ├─ Management ▸ Branch P&L · Gross Margin Analysis                     [NOW]
│  │     └─ Department Report · Cost Center Report                    [DECIDE]
│  │           Cost Center Report reads cost_centers and NOTHING else —
│  │           it cannot produce a P&L. Rebuild both on the CERTIFIED
│  │           fn_report_gl_by_dimension, which already reconciles exactly.
│  ├─ Inventory ▸ Slow Moving Inventory                                   [NOW]
│  ├─ Bank ▸ Bank Position Report                                         [NOW]
│  ├─ Audit ▸ Audit Support Package                                       [NOW]
│  └─ Fixed Asset Reports (4)                                           [LATER]
│        Removed from Reports entirely: all 8 Transaction Registers, both
│        Aging reports, all 7 Tax Reports, User Activity Report, Period Close
│        Checklist, Stock Movement, Inventory Ledger, Inventory Valuation,
│        Bank Reconciliation Summary, Outstanding Checks Report — each is a
│        link into its owning domain, not a separate report.
│
└─ Coming Later                                                        [LATER]
      A single, honest disclosure surface listing every deferred capability with
      its governing phase. Driven from the coverage class so it can never drift
      from `PXL_TABLE_COVERAGE_MATRIX.md`. This is what the 18 dead placeholders
      and the 33 empty routes should become.
```

### 8.2 Hidden architecture — must never appear in user navigation

```text
PXL SHARED ENGINES                                                   [ENGINE]
├─ Permissions / RLS Engine                       ✅ Certified
├─ Audit & Immutability Engine                    ✅ Certified
├─ Number Series Engine                           ✅ Certified
├─ Dimension Engine                               ✅ Certified
├─ COA Engine (Phase A landed, Phase B under way) 🟡 In Progress
├─ AR Engine · AP Engine · Payment & Application  🟡 In Progress
├─ Approval / Workflow Engine                     🟡 In Progress
├─ Period Lock & Closing Engine                   🟡 In Progress
├─ Reversal / Void / Correction Engine            🟡 In Progress
├─ Reporting & Reconciliation Engine              🟡 In Progress
├─ Attachment & Document Traceability Engine      🟡 In Progress
├─ Inventory Accounting Engine (IA-5 / ECC)       🟡 In Progress — DORMANT
├─ Document Conversion Engine                     ⚪ Not Started
├─ Currency Engine                                ⚪ Deferred
├─ Backup and Recovery Process                    ⚪ Not Started — NO restore test
└─ **Tax Engine**                                 🔴 DOES NOT EXIST
      Must be carried explicitly as an ABSENT component with a named owner.
      Today its work is done by seven duplicated save-layer calculators.

PXL ACCOUNTING INFRASTRUCTURE                                        [ENGINE]
├─ Posting Engine  P1 · P2 · P3 · P4 · P5.0 · P5.1 · P5.2 (enforced)
│     └─ Kernel Totality Guard — the enforcement layer INSIDE the Posting
│        Engine, not a peer of it
├─ General Ledger / Trial Balance views
├─ Posting source registry · Tax ledger · transaction_events
├─ sys_posting_guard_violations (control-empty: any row = a breach)
├─ Source-to-journal traceability · GL preview · document relationships ·
│  field-change history
└─ IA-5 / ECC dormant chronology sub-tree (20 tables, 0 rows, 0 consumers)
      WP-1…WP-4 certified · WP-5 rejected · WP-6…WP-9 and IA-6 unauthorised
      C-01 open; IA-5 permanent-foundation claim SUSPENDED

PXL CERTIFICATION AND GOVERNANCE                                     [ENGINE]
├─ Module Certification Standard (23 gates) · Engine Certification Standard
├─ Product Completeness Checklist · Certification Matrix
├─ Table Coverage Matrix + deterministic guard 075
├─ Findings register (92/92 Retested Passed) · PG-01 authority map
├─ Documentation Index
├─ AI_STATE (bounded next task) · AI_LAST_SESSION (mission hand-off) ·
│  AI_PROGRESS (executive dashboard)
└─ Eleven named validation lanes + frontend secret guard + docs:check
```

### 8.3 Why each recommended top-level node exists

| Node | Why it exists | What moved in | What was removed | Duplicate by design | Must not be shown |
| --- | --- | --- | --- | --- | --- |
| Dashboard | One landing surface | — | "Executive" claim | — | — |
| Setup & Administration | Setup + the homeless Administration/Security module | Users/Roles/Branch Scopes | Company Bank Accounts, ATP Monitoring, 8 Document&Validation placeholders | — | Engine internals |
| Master Data | One home for every master | Bank Accounts; sole Warehouses | Duplicate Items/Warehouses under Inventory | — | party_contacts until it has a UI |
| Sales & Receivables | AR value chain | Sales Cycle merged into Transactions | 4 redundant register labels | AR Aging is also linked from Accounting/Compliance/Reports | — |
| Purchasing & Payables | AP value chain | — | 2 redundant register labels | AP Aging likewise | — |
| Inventory | Independent lifecycle + feature gate + Phase 4 | — | Duplicate Items/Warehouses | Movements is also the BIR Inventory Subsidiary Ledger | IA-5/ECC dormant tables |
| Banking & Cash Management | Ratifies the Assets split; Phase 5 | Check Vouchers | — | — | — |
| Fixed Assets | Ratifies the Assets split; Phase 6 | — | — | Asset Register is also the BIR FA book | — |
| Accounting | GL, ledgers, periods, trace | **Accounting Trace (new entry)** | "General Ledger Entries" duplicate label | Customer/Supplier ledgers link to Sales/Purchasing | Posting Engine, Kernel, COA resolver |
| Compliance | Statutory workspaces over posted data | — | — | VAT/EWT summaries deliberately reachable from module and Compliance | Tax calculators |
| Reports | Cross-domain analysis only | — | 31 re-pointer leaves | — | — |
| Coming Later | Makes deferral visible | The 18 placeholders + 33 empty routes | — | — | — |

---

## 9. Accounting Flow Maps

Written for a CPA or business owner, not for an engineer.

### 9.A Current active / legacy runtime

```text
                        BUSINESS DOCUMENT
                               │
   ┌───────────────────────────┼───────────────────────────┐
   │                           │                           │
 SALES                     PURCHASING                 OTHER
 Sales Invoice      🟢    Vendor Bill          🟢    Manual Journal   🟢
 Cash Sale          🟢    Cash Purchase        🟢    Stock Adjustment 🟢
 Official Receipt   🟢    Payment Voucher      🟢    Stock Transfer   🟢
 Credit Memo        🟢    Vendor Credit        🟢    Physical Count   🟢
 Debit Memo         🔵    Supplier Debit Memo  🔵    Goods Issue      🔵
 Customer Return    🟡    Purchase Return      🔵    Fixed Assets ×5  🔵
 Quotation/SO/DR    🟡    Purchase Order       🟢    Banking ×10      🔵
                          Receiving Report     🟡    Schedules ×5     🔵
                               │
                               ▼
                    SAVE RPC  (fn_save_*)
   Server-side recomputation of amounts and tax. ⚠ TAX IS COMPUTED HERE, in
   SEVEN duplicated calculators, because NO TAX ENGINE EXISTS. VAT-inclusive
   handling exists in only ONE of the seven.
                               │
                               ▼
                    APPROVE  (where implemented)
   ⚠ Direct approve RPCs only (SI, VB, PO). The Approval Matrix engine exists
   (MDP-14) but no transaction rule is configured; approval_requests is empty.
                               │
                               ▼
                    POST RPC  (fn_post_*)
   Account determination via the COA resolver fn_resolve_account (Sales and
   Purchasing writers migrated; fail-closed, ambiguity-rejecting).
                               │
                               ▼
              ┌──── KERNEL TOTALITY GUARD ────┐   🟢 FULLY ENFORCED
              │  The ONLY doorway to the GL.  │   Six sanctioned mutators.
              │  48 bypass attempts rejected. │   Both triggers ENABLE ALWAYS.
              └───────────────┬───────────────┘   Zero violations.
                              ▼
                    JOURNAL ENTRY  🟢
   Balanced; carries all six dimensions; links back to its source document;
   reversible with dimensions preserved.
                              │
                              ▼
                    GENERAL LEDGER  🟢   vw_general_ledger
                              │
                              ▼
                    TRIAL BALANCE  🟢   vw_trial_balance
   ⚠ "Debit equals credit" is on the Critical Reconciliations list and has NOT
     been formally evidenced.
                              │
                              ▼
      ┌───────────────────────┼───────────────────────┐
      ▼                       ▼                       ▼
 FINANCIAL              SUBSIDIARY              TAX LEDGER  🟢
 STATEMENTS  🟡         LEDGERS  🟡             tax_detail_entries
 BS/IS/SCE/Comp 🟢      AR/AP    🟢             VAT ↔ GL variance = 0.00
 Cash Flows     🟡      Inventory 🟡            EWT/CWT ↔ GL variance = 0.00
 (FA section empty)     (does NOT tie to GL)          │
      │                       │                       ▼
      └───────────────────────┴──────────► COMPLIANCE OUTPUTS
                                           VAT reviews / BIR books /
                                           CAS logs        🟢
                                           Returns / working papers /
                                           certificates    🔵 (empty tables)
```

**What currently works, in plain terms.** A business can raise a quotation, a sales order, a
delivery receipt, a sales invoice or cash sale, collect on an official receipt, and issue a credit
memo — and every posting step lands a balanced, dimensioned, auditable journal entry in a General
Ledger that no other code path can write to. The same is true on the buying side for purchase
orders, receiving reports, vendor bills, cash purchases, payment vouchers, and vendor credits. VAT
and withholding detail reconcile to the General Ledger with **exactly zero variance**. The BIR books
of accounts and the CAS audit logs read from that posted data and export with server-attested hashes.

**What is incomplete, in plain terms.**

1. **Inventory does not tie out.** Confirming a Receiving Report increases stock **without writing a
   journal**, while the matching Vendor Bill debits purchase clearing. Measured against the canonical
   dataset, inventory value differs from the Inventory-control account by **2,400.00**, **21,000.00**,
   and **6,630.00** across three companies, and remaining cost layers exceed stock by **2,420.00 /
   12,600.00 / 3,930.00** and **9 / 6 / 14 units**. Until that is settled the Posting Engine cannot
   advance past P6, and the Inventory Valuation report shows a number the General Ledger disagrees with.
2. **No tax engine.** Tax is computed inside seven separate document-save routines. They agree today
   (variance is zero), but nothing structurally *makes* them agree, and only one of the seven handles
   VAT-inclusive pricing.
3. **Banking, fixed assets, schedules, returns, and corrective documents are navigable but
   unexercised.** Every one of their tables is empty by governance design.
4. **No opening balances.** There is no supported way to bring an existing company's balances in.
5. **No backup or restore evidence.** No successful restore test exists on record.

### 9.B Dormant IA-5 / ECC future runtime

```text
             ═══ NONE OF THIS IS RUNNING ═══
   20 tables · 0 rows · 0 consumers · 0 accounting effect · 0 journal entries

  INVENTORY ADMISSION                 ⚪ dormant
     A receipt, issue, or correction is accepted as an economic event.
     Today: the only writer is the 11-argument
     fn_ia5_record_dormant_inventory_occurrence(...), owner-only, and the only
     registered source type is IA5_CERTIFICATION — certification-only and
     PRODUCTION-DISABLED. No business workflow can reach it.
              │
              ▼
  SOURCE REGISTRY                     ✅ WP-2 CERTIFIED 2026-07-30
     "Which kinds of documents may create an inventory economic event, and what
     is each one's ordering authority?" Exactly six NOT NULL, no-default columns
     plus six governed CHECKs. One row exists; it is disabled.
              │
              ▼
  VALUATION STREAM                    ✅ WP-3 CERTIFIED 2026-07-31
     "Which independent costing timeline does this event belong to?" — the
     partition (company/item/scope) within which order must be total. Two
     dormant tables: the stream identity and its accepted allocator.
              │
              ▼
  ECONOMIC ORDER KEY                  ✅ WP-4 CERTIFIED 2026-07-31
     "Given two events with the SAME date and time, which one must accounting
     process first, and why?" A 31-column persisted evidence contract with 24
     governed keys/constraints and a supersession lifecycle. Empty.
              │
              ▼
  COMPONENT RESOLVER                  ❌ ═══ CURRENT STOP POINT ═══
     WP-5 AUTHORISATION **REJECTED** 2026-07-31 on three findings:
       WP5-AG-001  the exact writer/resolver SQL contract is absent
       WP5-AG-002  dormant certification admission conflicts with ECC-01 V-10
                   (production enablement is mandatory before economic
                   processing, yet the only source is production-disabled)
       WP5-AG-003  the constraint-trigger object and rollback contract is
                   incomplete
     Nothing can derive and write an order key during event admission.
              │
              ▼
  COSTING / REPLAY                    ⬜ UNAUTHORISED (WP-6…WP-9)
  INVENTORY ACCOUNTING EFFECT         ⬜ UNAUTHORISED
  POSTING                             ⬜ UNAUTHORISED
  GENERAL LEDGER                      ⬜ UNAUTHORISED (IA-6)
```

**Governance facts that must travel with this diagram.**

- **Certified bounded work packages:** WP-1 (order policy/version foundation), WP-2 (source registry
  authority), WP-3 (valuation stream + accepted allocator), WP-4 (persisted economic order key).
  Each certifies **one bounded dormant change set** — nothing more.
- **Current stop point:** the Component Resolver (WP-5). The repository can *store* the required
  chronology evidence but cannot *derive* it.
- **Unauthorised stages:** WP-5 through WP-9, and all of IA-6 (cost layers, FIFO, moving weighted
  average, method state, valuation, reporting, reconciliation).
- **No production activation:** the sole source type is certification-only and disabled. A non-zero
  `inventory_events` count is an explicit governance stop condition.
- **No Inventory Engine certification exists.** C-01 remains open: the original IA-5 accepted
  sequence was allocated by **row-lock order**, so identical same-time evidence produced **opposite
  orders across schedules** — it was never economic order. The IA-5 permanent-foundation claim is
  **suspended**.

**In accounting language.** This work exists to guarantee that FIFO and moving-average costing can
be *replayed* and will produce the same answer every time. If two stock movements share a timestamp,
the system must record — permanently and defensibly — which one accounting processed first and on
what authority. Until the resolver is built, PXL can store that evidence but cannot produce it, so
no inventory cost computed today is replay-guaranteed. **None of this affects the current ledger:
the dormant foundation creates no cost, no cost layer, no projection, no journal entry, and no
General Ledger effect whatsoever.**

---
## 10. Gap Analysis

Each gap is typed: **[PA]** product architecture · **[NAV]** navigation · **[RT]** runtime ·
**[CERT]** certification · **[TAX]** documentation taxonomy · **[FUT]** future roadmap.

### A. Original blueprint items missing from the repository — 6

| Item | Type | Impact |
| --- | --- | --- |
| Opening Balances (no table, no import, no page) | **[PA]** | **Highest.** No supported path exists to migrate an existing company onto PXL. Manual JE is the only workaround, and P6 already attributes part of the Inventory variance to "one opening balance". |
| Supplier Bank Details | **[PA]** | Payment and Check Vouchers cannot carry a validated payee bank account. |
| CAS Registrations | **[PA]** | BIR CAS accreditation/permit data has nowhere to live in a CAS-compliant ERP. |
| Depreciation Profiles | **[PA]** | Depreciation policy is not a governed master. Absorb into Phase 6. |
| Budget Settings | **[FUT]** | Budgeting is absent end to end; it should not be a Setup menu entry. |
| Customizable dashboard widget grid | **[FUT]** | Two tables exist and are seeded; no page reads them. |

### B. Original blueprint items represented only by UI — 65 (25.4%)

All 🔵 leaves. Concentrated in exactly four clusters: Banking & Treasury (10/10), Fixed Assets (8/9),
Income Tax (10/11), and compliance working papers + statutory generators (12). Type **[NAV]** +
**[CERT]**: the software is not lying about its schema, it is lying about its *readiness*, and the
lie is only detectable by reading a governance matrix.

### C. Original blueprint items represented only by schema — 4

`company_inventory_config` (Inventory Settings) · `fs_structure` + `account_fs_map` (Financial
Statement Fields) · `party_contacts` (Customer/Supplier Contacts) · `dashboard_layouts` +
`dashboard_widgets` (Dashboard widgets). Type **[PA]**: complete, RLS-protected, audited tables with
zero surface.

### D. Repository additions missing from the original blueprint — the material ones

**[PA]** Tax Engine (as an explicit absence) · Posting Engine + Kernel Totality Guard · COA Engine ·
Permissions/RLS · Audit & Immutability · Dimension Engine · Document Conversion Engine ·
Backup & Recovery · Administration and Security module (#11) · IA-5/ECC chronology foundation ·
source-to-journal traceability · transaction workspace standard · coverage governance · the
certification program itself · Check Vouchers · Stock Balance · Global Feature Enablement ·
Report Snapshots · Company Provisioning Wizard.

The blueprint is a **menu tree**; the repository is a **layered system**. The blueprint has no
vocabulary for engines, kernels, certification scopes, or governed dormancy — which is precisely why
progress reporting against it keeps producing misleading numbers (§11).

### E. Backend features missing UI — 7

**[PA]** `party_contacts` · `fs_structure`/`account_fs_map` · `company_inventory_config` ·
`customer_groups`/`supplier_groups` · `item_uom_conversions`/`item_barcodes`/`item_media` ·
`user_company_branch_scopes` (branch-scope assignment has no page) · `dashboard_layouts`/`_widgets`.

**Plus two reachable-but-unlisted routes:** `/accounting-trace` and `/accounting-source` — finished,
valuable capabilities with **no navigation entry anywhere**. **[NAV]**

**Plus one certified capability nothing calls:** `fn_report_gl_by_dimension` +
`vw_gl_dimension_summary` reconcile exactly to the control total, yet none of the four Management
Reports uses them; Cost Center Report does not touch the GL at all. **[RT]**

### F. UI features missing backend — 33 pure + ~20 mixed

Enumerated exactly in §6.3. Type **[NAV]**.

### G. Duplicated navigation — 55 duplicate labels over 31 routes

Enumerated exactly in §4.I. Seven routes carry a **literally identical** label twice. Type **[NAV]**.
Effect: 242 menu entries suggest ~242 capabilities; 169 distinct routes exist; of those, 33 are
empty. A reasonable observer inspecting the menu would overstate delivered scope by roughly 30%.

### H. Ambiguous module ownership — and three direct register contradictions

**Ownership gaps [PA]:**

| Area | Problem |
| --- | --- |
| **Banking** | Module #6 "Not Started" but 10 navigable screens + a Check Voucher instrument the blueprint never named. No owner is driving it. |
| **Fixed Assets** | Module #7 "Not Started" but 8 navigable screens, 8 RPCs, and Dimension-Engine certification evidence citing FA acquisition/depreciation/disposal. |
| **FWT** | Five surfaces, four of them empty shells, no certification row of its own, no engine, no named owner. Buried inside Withholding Tax. |
| **Attachments** | Attachment & Traceability Engine is "In Progress" but `cas_attachment_register` is `future-deferred` with no workflow. |
| **Dashboard** | No module owns it. It is not in any of the 11 certification modules. |
| **Imports** | MDP-15 import/export exists (`master_data_import_registry` rp,43) with no menu entry and no owning module. |
| **Administration & Security** | Certification module #11 with **no navigation home and no page**. |
| **Tax Engine** | Does not exist; no owner assigned to make it exist. |

**Register contradictions [TAX] — three, all requiring reconciliation:**

1. **Form 2307 Issued.** Transaction Matrix: **Implemented**. Coverage Matrix: `form_2307_issuances`
   = `future-deferred` / "Future module (unimplemented)". Both are governance authorities.
2. **VAT Return 2550M/2550Q.** Transaction Matrix: **Implemented**. Coverage Matrix: `vat_returns` =
   `future-deferred`.
3. **Goods Issue and Fixed Assets.** Coverage Matrix: `future-deferred` / "Future module
   (unimplemented)". Dimension Engine certification: named as **proven dimension-bearing posting
   transactions** in test 080. Both are probably literally true — 080 builds transient fixtures while
   the coverage class describes only the canonical seed — but the two registers use "implemented" to
   mean different things and neither says so.

There is also a **stale count**: the Table Coverage Matrix states "All 193 tables have row-level
security enabled" while its own summary totals **202**, and the Permissions/RLS certification cites
"176/176 base tables". Three different table counts appear across three active governance documents.
**[TAX]**

### I. Uncertified but substantial workflows — 9

Sales Invoice (5 lifecycle RPCs, dedicated routed workspace, all six dimensions, AUD-053) ·
Vendor Bill (5 lifecycle RPCs, EWT profile) · Official Receipt (save/post/bounce, CWT, applications) ·
Payment Voucher (applications, payment-basis EWT) · Manual Journal (post/reverse, dimension guard) ·
Cash Sale · Cash Purchase · Vendor Credit · the Posting Engine P1–P5.2 chain with a fully enforced
Kernel. **[CERT]** — these are the strongest assets in the product and none is certified. They should
be the *first* certification targets, not the last.

### J. Scaffolds currently presented as product features — 33 + 18 + 55

The 33 pure-deferred routes, the 18 disabled placeholders, and the 55 duplicate labels. Type
**[NAV]**. Root cause: **deferral is recorded in a governance matrix but has no representation in
the product surface**. `PXL_TABLE_COVERAGE_MATRIX.md` and guard `075` are excellent controls that
the user interface never consults.

### K. Future items incorrectly affecting progress — 3

1. **Payroll** carries a 0% row in `AI_PROGRESS.md`'s Overall ERP Progress block and is therefore
   dragging the weighted headline down, although it is not a PXL module, has no schema, no page, no
   test, and no certification row. **[TAX]**
2. **Inventory Engine 44%** is the IA-5 hardening work-package ratio (4 of 9) for a **dormant**
   foundation. Placed beside "Sales and AR 50%", it reads as "Inventory is 44% usable". **[TAX]**
3. **Accounting Kernel 100%** reports a guard-scope enforcement state as though it were a completed
   peer of the Posting Engine (25%) — the same subsystem shown at two numbers. **[TAX]**

### L. Production-readiness blockers — 8

| # | Blocker | Type | Evidence |
| ---: | --- | --- | --- |
| 1 | **No backup/restore evidence.** Gate 23 (+ RPO/RTO) has no artifact; no successful restore test on record; no backup script exists in `package.json` or `scripts/`. | **[CERT]** | Certification matrix engine #18 "Not Started"; grep found no backup tooling |
| 2 | **Inventory does not reconcile to the GL.** Three companies, six measured variances. | **[RT]** | Posting Engine §5.4.1 / P6 |
| 3 | **No Tax Engine**; seven duplicated calculators; VAT-inclusive in only one. | **[PA]** | Test 090; P4 census |
| 4 | **No opening balances.** No client can be migrated onto the product. | **[PA]** | §10.A |
| 5 | **No module is Certified.** Zero of eleven. | **[CERT]** | Certification matrix |
| 6 | **Nine Critical Reconciliations, none evidenced** (TB debit=credit, AR/AP subledger to control, inventory valuation to control, VAT/EWT ledgers to accounts, FA register to GL, branch to company, FS net income to GL). | **[CERT]** | Certification matrix §"Critical Reconciliations" |
| 7 | **Two UI-written tables inside the sealed accounting perimeter** — `bank_recon_items` and `book_tax_reconciliation` were explicitly EXCLUDED from Posting Engine P5.0 write-surface closure. | **[PA]** | P5.0 record |
| 8 | **Browser-workflow evidence is recorded-only** (Gate 20 Partial); no automated cross-tenant browser E2E. | **[CERT]** | Certification matrix module #1 |

### M. Hosted parity gaps

**51 local migrations (`20260718000001` … `20260731000019`) are unapplied to hosted project
`bskjkogijpbhukjkagfj`, which is synchronized only through `20260716000005`.** Type **[RT]**.

Everything landed since 2026-07-18 exists **only locally**: the entire COA Engine Phase A, the whole
Posting Engine P1–P5.2 chain including the Kernel Totality Guard, all four engine certifications
(Permissions/RLS remediation `20260723000001`, Number Series guard `20260723000002`, Dimension Engine
`20260723000003`), AUD-053 Sales Invoice completeness, the MDP master-data packages, and every IA-5
/ ECC migration.

**The four Certified engines are certified against a local database whose defining migrations the
hosted environment has never seen.** No hosted parity claim may be made, and none is made in this
report. Hosted application requires explicit operator approval.

### N. Backup and recovery gaps

Total. No backup schedule, no restore procedure, no restore test, no RPO/RTO target, no
point-in-time-recovery evidence, and no tooling anywhere in the repository. This alone prevents
**Setup and Master Data** — the module closest to certification, with 14 of 23 gates passing and
zero open defects — from being certified, and it prevents **any** module from reaching Phase 9.
Type **[CERT]** + **[PA]**.

---

## 11. AI_PROGRESS Assessment

`AI_PROGRESS.md` was **not edited by this mission.** This is an assessment only.

### 11.1 What it gets right

It is honest in prose. It states plainly that no module is certified, that the product is internal
QA/demo only, that work-package certification is not engine certification, that the Inventory
percentage is a work-package ratio and "does not mean that 44% of production Inventory behavior is
available", and that the 42% figure "is a planning indicator, not a certification claim". Its
Inventory roadmap, accounting flow, governance limits, and next-target sections are accurate and
well written.

**The problem is not honesty. It is that the prose disclaims exactly what the bar charts assert**,
and readers of a dashboard read the bars.

### 11.2 Content classification against the reconciled tree

**1. Current repository runtime.** Sales (SI, Cash Sale, OR, CM), Purchasing (PO, RR, VB, Cash
Purchase, PV, VC), Accounting (JE, GL, ADL, TB, posting/reversal review, auto-reversal), Inventory
module (dashboard, stock balance, movements, adjustment, transfer, physical count), Master Data (12
leaves), Setup (15 leaves), Compliance read surfaces (VAT reviews, BIR books, CAS logs), Reports
(24 leaves). **119 source-backed leaves + 4 certified-bounded.**

**2. Current module lifecycle.** The 11 modules with statuses **exactly as the certification matrix
records them** — 0 Certified, 5 In Progress, 2 Blocked, 4 Not Started.

**3. Engine lifecycle.** The 19 engines — 4 Certified, 10 In Progress, 2 Blocked (including a Tax
Engine that **does not exist**), 2 Not Started, 1 Deferred.

**4. Certified work packages.** IA-5 ECC WP-1…WP-4. **These belong in their own count and must never
be averaged into module or engine progress.**

**5. Scaffold / deferred.** The 33 pure-deferred routes, 61 `future-deferred` + 21 `workflow-deferred`
tables, 18 disabled placeholders, 55 duplicate labels.

**6. Future roadmap.** Tax Engine, Currency/multi-currency, Budgeting, Document Conversion, Backup &
Recovery, IA-6, WP-5…WP-9, Posting P5.3B/P6/P7/P8, COA Phase B/C, the dashboard widget grid.

**7. Must be EXCLUDED from every current-progress calculation.**
   - **Payroll** — not a PXL module (§7.I). Remove the row entirely.
   - **"Future AI Transaction / Assistant Action"** — Planned; no integration exists.
   - **The 20 dormant IA-5/ECC tables** — must never contribute to product completion.
   - **`future-deferred` tables** — presence is not progress.
   - **Route counts** — a route is not an implementation.
   - **The 92 closed findings** — a closed findings register certifies nothing.

### 11.3 Should the 42% be removed, renamed, or retained?

**Recommendation: REMOVE it. Do not rename it.**

Four independent reasons, in order of weight:

1. **Its inputs are not commensurable.** It averages a *module* (a business capability), an *engine*
   (a shared mechanism), an *absent* engine (Tax, at 25% "Blocked"), a *guard* (Kernel, at 100%), a
   *dormant work-package ratio* (Inventory, 44%), and a *non-module* (Payroll, 0%). Averaging those
   six kinds of thing produces a number that measures nothing.
2. **Its weighting rewards the wrong state.** "Blocked = 25%" means a module with a known
   unresolvable defect scores higher than one not yet started. The Tax Engine — which *does not
   exist* — contributes 25%. Discovering that a component is missing should not raise the score.
3. **It contradicts the certification program.** The program's own rule is binary per gate, and its
   headline result is "**Partially Ready — Blocked**, not production-ready, not pilot-ready, zero
   modules Certified". A 42% number invites "roughly halfway", which is the one inference the
   governance framework exists to prevent.
4. **Renaming cannot save it.** Any accurate name — "weighted average of certification-status
   ordinals across two incommensurable populations" — is longer and less useful than the nine exact
   counts below, all of which are already maintained.

**If the owner insists on a single headline**, the only defensible one is the count itself:

> **Certified: 0 of 11 modules · 4 of 19 engines. Not production-ready. Not pilot-ready.**

### 11.4 Recommended reproducible dashboard methodology

Every measure below has a named source, a fixed denominator, and a mechanical derivation. No
weighting, no judgment, no averaging across populations.

| # | Measure | Current value | Source of truth | How to reproduce |
| ---: | --- | --- | --- | --- |
| 1 | Certified modules | **0 / 11** | `PXL_CERTIFICATION_MATRIX.md` §Module Certification Status | Count rows with Status = Certified |
| 2 | Certified engines | **4 / 19** | Same, §Engine Certification Status | Count rows with Status = Certified |
| 3 | Modules by lifecycle | Certified 0 · In Progress 5 · Blocked 2 · Not Started 4 | Same | Tally the Status column |
| 4 | Engines by lifecycle | Certified 4 · In Progress 10 · Blocked 2 · Not Started 2 · Deferred 1 | Same | Tally the Status column |
| 5 | Source-reviewed transaction workflows | **1 / 33** | `src/lib/transactionWorkspaceCoverage.ts` | Count `fieldSourceGate: 'sales-invoice-reviewed-slice'`; the other 32 are `transaction-matrix-only` |
| 6 | Expected-populated tables | **93 / 202** | `PXL_TABLE_COVERAGE_MATRIX.md` §Coverage Summary | `canonical-populated` (67) + `reference-populated` (26) |
| 7 | Deferred / dormant tables | **109 / 202** | Same | `workflow-deferred` 21 + `future-deferred` 61 + `reference-empty` 6 + `control-empty` 1 + `dormant-foundation` 20 |
| 8 | Reachable routes with no exercised backing | **33 / 169** | Page-to-table cross-join (§6.3) | Extract `.from(...)` per page; join to coverage class; flag pages whose tables are all deferred |
| 9 | IA-5 ECC work packages certified | **4 / 9** | `PXL_CERTIFICATION_MATRIX.md` §Certification Chronology | Count Kind = "Work package" rows |
| 10 | Hosted migration parity | **51 migrations behind** | `AI/AI_STATE.md` + `supabase/migrations/` | Count files after the hosted high-water mark `20260716000005` |
| 11 | Backup / restore status | **NO restore test on record** | Certification matrix engine #18 | Binary: does a passed restore test exist? |
| 12 | Critical reconciliations evidenced | **0 / 9** | Certification matrix §Critical Reconciliations | Count reconciliations with executed numeric evidence |
| 13 | Open audit findings | **0 open / 92 Retested Passed** | `PXL_END_TO_END_AUDIT_FINDINGS.md` | Findings Status Index checksum |
| 14 | Production readiness | **Internal QA/demo only** | `AI/AI_STATE.md` | Binary statement, never a percentage |

**Rules for the dashboard.**

- No percentage may combine modules with engines, or either with work packages.
- No percentage may include a component that does not exist (Tax Engine) or is out of scope (Payroll).
- "Blocked" must never score above "Not Started".
- Dormant scopes report as **dormant**, never as partial progress.
- Every number carries its denominator and its source file.
- Measures 1, 2, 6, 7, 9, and 13 are already machine-derivable today; 5, 8, and 10 become so with a
  short script. That is the whole methodology — no new registers, no new judgment.

### 11.5 Two specific corrections regardless of the headline decision

1. **Delete the Payroll row** from Overall ERP Progress. It is not a PXL module (§7.I).
2. **Rename the two Inventory lines** to make the split in §4 J-12 unmissable:
   *"Inventory Module — implemented, uncertified"* and
   *"Inventory Accounting Engine (IA-5/ECC) — dormant; 4 of 9 work packages certified"*.

---

## 12. Prioritized Governance Recommendations

Documentation and governance only. **No source-code change is recommended by this mission.**

### P0 — required to prevent engineering misdirection

| # | Recommendation | Why it is P0 | Deliverable |
| --- | --- | --- | --- |
| **P0-1** | Publish **one authoritative PXL Product Blueprint** that replaces the original tree, and make **deferral visible in it**. Every node carries: status, owning module, owning engine, governing certification phase, and whether it is currently reachable. | Today the only place deferral is recorded is a table-coverage matrix no product reader consults, while 33 empty routes and 18 dead placeholders present as features. Every future estimate built on the menu will be wrong by ~30%. | New Tier-1 doc under `01. Architecture/` |
| **P0-2** | Publish **one canonical Module and Engine Taxonomy** that fixes the four conflations: Kernel ⊂ Posting Engine ⊂ Accounting Core; Inventory Module ≠ Inventory Accounting Engine; module ≠ engine ≠ work package ≠ certification scope; "implemented" means one thing. Reconcile the three register contradictions in §10.H and the three different table counts (176/193/202). | Two Tier-1 registers currently disagree in writing about whether Form 2307 Issued, VAT Returns, and Goods Issue are implemented. Engineers will act on whichever they read first. | New Tier-1 doc under `01. Architecture/` + errata to the two matrices |
| **P0-3** | **Record that the "PXL ERP Master Architecture Conformance Review" does not exist**, and either commission it or remove every reference to it from mission briefs. | This mission was instructed to treat it as its evidence baseline (§2.3). A future mission will make the same assumption and may proceed on an imagined baseline instead of rebuilding evidence. | Entry in `PXL_DOCUMENTATION_INDEX.md` |
| **P0-4** | **Ratify the dissolution of "Assets"** into Inventory, Banking & Treasury, and Fixed Assets. | The repository, the docs folders, the feature gates, and the certification phases all already assume the split; only the blueprint does not. Continuing to plan against "Assets" mis-scopes Phases 4/5/6. | Section in the new Product Blueprint |
| **P0-5** | **Carry the Tax Engine as an explicit, named ABSENCE** in the authoritative architecture, with an owner. | Its absence is invisible in the blueprint (which has no engine vocabulary) and easy to miss in the certification matrix (where it reads "Blocked", implying it exists). Seven duplicated calculators are accruing debt in the meantime. | Row in the Module and Engine Taxonomy |
| **P0-6** | **Fix the executive dashboard**: remove the 42% headline and the Payroll row; adopt the fourteen exact measures in §11.4. | The current dashboard is the single most-read status artifact and it overstates in three independent ways (§10.K). | Revision of `AI_PROGRESS.md` (a later mission — **not this one**) |
| **P0-7** | **Record Opening Balances as a production-readiness blocker** in the findings register or the completeness checklist. | No client can be migrated onto PXL. It is currently only a greyed-out menu item. | Finding or checklist row |

### P1 — required before the next module certification phase

| # | Recommendation | Deliverable |
| --- | --- | --- |
| **P1-1** | Publish **one Navigation Architecture**: what appears, what is hidden, what shows "Coming Later", and the rule that the label is driven by the coverage class so the menu can never drift from the register. | New doc under `12. UI and UX/` |
| **P1-2** | Publish an **alias map for renamed and superseded transactions**: Official Receipt ⇄ Receipt ⇄ Customer Collection · Receiving Report ⇄ Goods Receipt · Payment Voucher ⇄ Vendor Payment · Journal Entry ⇄ General Ledger Entries · EWT Codes → ATC Codes · FWT Codes → ATC Codes · `ref_atc_codes`/`ewt_codes`/`fwt_codes` → `atc_codes` · Cost Centers → Departments page · Fiscal Calendar → Fiscal Years page. | Appendix to the Product Blueprint |
| **P1-3** | Publish **one executive-dashboard standard** codifying §11.4's rules (no cross-population averaging, no non-existent components, Blocked never above Not Started, dormant reports as dormant, every number carries its denominator and source). | New doc under `13. Testing and Validation/` |
| **P1-4** | **Assign explicit ownership** for the eight homeless areas: Banking, Fixed Assets, FWT, Attachments, Dashboard, Imports, Administration & Security, Tax Engine. Administration & Security is a certification module with no page at all. | Ownership table in the Taxonomy |
| **P1-5** | Publish the rule **"a route is not an implemented module"** and the companion rule **"a table is not a supported workflow; a test is not a certification; a work package is not an engine."** | Section in `00. Governance/PXL_PRINCIPLES.md` |
| **P1-6** | **Decide CAS Registrations and Supplier Bank Details**: build, or state explicitly that the data lives outside PXL. | Two rows in the completeness checklist |
| **P1-7** | Record the **Customer/Supplier Ledger accounting-view decision** (J-4): either build a true accounting-basis subsidiary ledger or declare the merged view canonical and certify it as such. | Decision record |

### P2 — useful cleanup

| # | Recommendation |
| --- | --- |
| **P2-1** | Remove the seven literally-identical duplicate nav labels (§4.I) and the two dead placeholders whose features already shipped elsewhere (Company Bank Accounts, ATP Monitoring). |
| **P2-2** | Give `/accounting-trace` and `/accounting-source` a navigation entry under Accounting — finished capabilities that are currently unreachable from the menu. |
| **P2-3** | Reconcile the three table counts (176 / 193 / 202) across the Permissions certification, the coverage matrix prose, and the coverage matrix summary. |
| **P2-4** | Decide the eight Document & Validation placeholders as **one** architectural question — "is rule configuration in scope?" — rather than eight independent gaps. |
| **P2-5** | Record that the four Management Reports do not use the certified `fn_report_gl_by_dimension`, and that Cost Center Report performs no GL join at all. |
| **P2-6** | Note the two UI-written tables (`bank_recon_items`, `book_tax_reconciliation`) as standing exceptions to the P5.0 sealed write surface, with an intended resolution. |

### P3 — optional

| # | Recommendation |
| --- | --- |
| **P3-1** | Formally classify **Payroll as a future/separate product** in the backlog, so the question stops recurring. |
| **P3-2** | Decide the dashboard widget grid: build it, or drop `dashboard_layouts`/`dashboard_widgets`. |
| **P3-3** | Record that TanStack Query, Zustand, react-hook-form, and Zod are installed but **not adopted**, so they are never described as current architecture. |
| **P3-4** | Consider whether "Reports" should survive as a domain at all, given that 31 of its 43 leaves are re-pointers (§7.E). |

---

## 13. Recommended Next Governance Mission

**Mission: PXL Authoritative Product Blueprint and Taxonomy — documentation only.**

Deliver P0-1 through P0-5 as **two** new Tier-1 documents under `docs/PXL/01. Architecture/`:

1. **`PXL_PRODUCT_BLUEPRINT.md`** — the single authoritative product tree, with the Assets split
   ratified, deferral visible per node, and the alias map attached.
2. **`PXL_MODULE_AND_ENGINE_TAXONOMY.md`** — the canonical separation of module / engine /
   infrastructure / workspace / work package / certification scope, with the Tax Engine carried as a
   named absence, ownership assigned for the eight homeless areas, and the three register
   contradictions in §10.H reconciled.

**Scope boundaries for that mission:** documentation only. No source, SQL, migration, test,
navigation, route, certification, or IA-5/ECC change. It must not touch WP-5, and it must not be
merged with the WP-5 Engineering Amendment.

**Sequencing against the existing engineering queue.** `AI/AI_STATE.md` and `AI_LAST_SESSION.md`
both name the **WP-5 Engineering Amendment (documentation only, bounded to WP5-AG-001…003)** as the
next engineering mission. That remains correct and is **not** displaced by this recommendation: the
two are independent documentation missions in different domains. Recommended order — run the WP-5
Engineering Amendment first (it unblocks a rejected authorisation gate on the critical path), then
the Blueprint and Taxonomy mission, then the `AI_PROGRESS.md` dashboard revision (P0-6), which
depends on the taxonomy existing.

---

## 14. Explicit Non-Authority Statement

**This report is advisory. It does not amend repository architecture, navigation, scope,
certification, or implementation authority.**

Specifically, this report:

- **does not** certify, decertify, or alter the status of any module, engine, or work package;
- **does not** authorise, reject, or modify any IA-5 / ECC work package, and leaves WP-5 rejected
  and WP-6…WP-9 and IA-6 unauthorised;
- **does not** change ADR-C01 (frozen), ECC-01 (owner accepted, not frozen), the Posting Engine, the
  Kernel Totality Guard, the COA Engine, or any accounting, tax, or posting rule;
- **does not** amend `PXL_CERTIFICATION_MATRIX.md`, `PXL_TABLE_COVERAGE_MATRIX.md`,
  `PXL_TRANSACTION_MATRIX.md`, `PXL_SCHEMA_SUMMARY.md`, `PXL_DOCUMENTATION_INDEX.md`,
  `AI/AI_STATE.md`, or `AI_PROGRESS.md`;
- **does not** change any navigation entry, route, page, component, migration, test, or RPC;
- **does not** create, lift, or modify any production-readiness claim. PXL remains **not
  production-ready and not pilot-ready**, suitable for internal QA/demo only;
- **does not** make or imply any hosted-environment claim. 51 local migrations remain unapplied to
  the hosted project, and no hosted read or mutation was performed by this mission.

The recommended tree in §8 is a **proposal**. It becomes architecture only if a separate, properly
authorised governance mission adopts it. Until then, `src/components/AppShell.tsx` remains the
navigation authority, `PXL_CERTIFICATION_MATRIX.md` remains the certification authority,
`PXL_TABLE_COVERAGE_MATRIX.md` remains the coverage authority, and executed database behaviour
outranks every document including this one.
