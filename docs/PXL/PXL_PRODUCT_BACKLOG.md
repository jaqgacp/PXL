# PXL Product Backlog

Purpose: future enhancements that make PXL a better ERP, kept separate from release blockers.

Separation of concerns (DEC-012):

- **Audit findings** (`PXL_END_TO_END_AUDIT_FINDINGS.md`) = production defects and release blockers. Genuine accounting/tax/security/posting/GL/data-integrity/architecture bugs become NEW findings there, never backlog entries.
- **Architecture documents** = how the system works today.
- **Product backlog** (this file) = enhancements. Documentation only until a phase is scheduled; backlog work must never delay or expand an audit session.

Whenever a module is touched during audit work, perform a lightweight architectural review: identify extension points, prepare the architecture only when doing so has negligible risk and avoids future refactoring, otherwise record the opportunity here.

Priority: High / Medium / Low (product value, independent of audit P0–P2). Complexity: S / M / L. Phase: `Alongside audit` (negligible-risk preparation only) or `Phase 2` (post-audit implementation).

## Target: Standard Transaction Experience

Every financial transaction page should converge toward one consistent layout. New or reworked pages should adopt this shape rather than inventing their own:

1. **Transaction Header** — document no, status, date, company, branch, counterparty, payment terms, currency.
2. **Business Information** — transaction-specific fields; master data (TIN, address, tax profile, VAT registration, ATC/EWT profile, default terms, default cash/bank, default revenue/expense mapping) auto-populates; users never re-encode master data.
3. **Line Items** — future support for item, description, UOM, warehouse, tax code, discount, dimensions, revenue/expense determination, GL mapping.
4. **Financial Summary** — consistent per-type totals (e.g. Sales: net / output VAT / gross / less CWT / cash received; Purchasing: net / input VAT / gross / less EWT / net payment; Receipt: invoice / applied payment / applied CWT / balance; PV: bill / applied EWT / net payment / balance; CM/VC: applied / remaining / application history).
5. **GL Impact** — draft GL preview, posted journal, journal number, debit/credit, balancing validation, drilldown.
6. **Tax Impact** — VAT, EWT, ATC, 2307 tracking, SAWT/QAP linkage, tax ledger rows, tax status, tax reconciliation.
7. **Posting Validation** — company/branch ready, fiscal period open, number series ready, approval complete, counterparty active, tax/posting/GL configuration, audit and compliance requirements.

## Cross-Module Transaction Experience

| Feature | Business Value | Accounting Value | Compliance Value | UX Value | Dependencies | Priority | Complexity | Current Readiness | Phase | UI Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Standard transaction layout convergence | One learnable pattern across all documents | Consistent placement of accounting evidence | Consistent placement of tax evidence | Users predict where everything is | Section components below | High | L | Core pages share header/lines/GL-impact patterns informally; no shared layout component | Phase 2 | Seven-section shell (see Target above); adopt on new pages first |
| GL Impact Panel on every posting page | Trust in what posting will do | Preview + posted JE + balancing validation at source | JE evidence for CAS | No surprises at post time | PXL-DA-001 server-side preview RPC | High | M | `GLImpactPanel` exists on SI/OR/VB/PV pages; preview is client-computed | Phase 2 | Draft preview above post button; posted JE with drilldown after |
| Financial Summary Panel | At-a-glance document economics | Totals derived server-side, consistent with JE | VAT/EWT arithmetic visible | No mental math | Server-computed totals (PXL-DA-008 direction) | High | M | Totals shown ad hoc per page; no shared component or contract | Phase 2 | Right-hand card per document type (see Target §4) |
| Tax Impact Panel | Tax consequences visible per document | Ties document to tax ledger rows | Shows VAT/EWT/ATC/2307/SAWT/QAP linkage and reconciliation state | Tax literacy at capture time | Tax ledger (exists); snapshot reader (PXL-DA-015) | High | M | `tax_detail_entries` + reconciliation RPCs exist (`fn_vat_gl_reconciliation`, `fn_wht_gl_reconciliation`); no per-document panel | Phase 2 | Tab next to GL Impact; row per tax kind with ledger link |
| Posting Validation Panel | Blocked postings explained before the attempt | Readiness checks match server triggers | Compliance prerequisites enforced visibly | Checklist instead of error roulette | `useTransactionReadiness` (exists), `fn_can_perform`, approval SoD | Medium | M | Readiness preflights exist on core pages (PXL-AUD-002/016 In Progress); presentation is per-page | Phase 2 | Green/red checklist (see Target §7) |
| Smart defaults / master-data auto-population | Faster capture, fewer errors | Correct accounts and terms by default | Correct TIN/ATC/VAT profile by default | Users never re-encode master data | Customer/supplier defaults (partially exist: ATC, CWT) | High | M | Supplier ATC and customer CWT defaults implemented; address/terms/account defaults partial | Alongside audit | Prefill on counterparty select; show provenance of each default |
| Account determination engine | Non-accountants can transact safely | Accounts derived from item/service/tax profile/posting rules, not user choice | Deterministic mapping is auditable | Normal users never pick GL accounts | Posting-engine primitives (PXL-DA-004); item/service master | High | L | Users currently select revenue/expense accounts per line; `company_accounting_config` covers control accounts only | Phase 2 | Account field hidden behind an "override" affordance with permission gate |
| Payment-method-driven behaviour | Correct capture per payment channel | Settlement account derived from method | Reference trail per channel (cheque no, GCash/Maya ref, card approval) | Only relevant fields shown | Payment modes master; banking module | Medium | M | `ref_payment_modes` exists; no per-method field rules or settlement mapping | Phase 2 | Dynamic field group under payment mode select |
| Drilldown / drillback everywhere | Trace any number to its source | Report → GL → journal → source doc → line → supporting document and back | Auditor navigation without SQL | Click-through everywhere | PXL-DA-002 (Open finding defines the contract) | High | L | GL/JE pages link partially; no uniform contract | Phase 2 | Every amount is a link; breadcrumb back-trail |
| Dimension summary on documents | Branch/department/cost-center visibility | Dimensions propagate to JE lines | BIR branch reporting accuracy | See allocation before posting | PXL-DA-017 (Open finding) | Medium | M | Dimensions exist on documents; JE-line propagation not yet implemented | Phase 2 | Chip row in header; per-line dimension column |
| Transaction / audit timeline | Who did what, when | Lifecycle evidence beside the document | CAS user-activity narrative per document | Story view instead of log tables | PXL-DA-016 `transaction_events` (Open finding) | Medium | M | Row-level audit triggers exist; no semantic event log or UI | Phase 2 | Vertical timeline tab: created → approved → posted → voided |

## Sales / AR

| Feature | Business Value | Accounting Value | Compliance Value | UX Value | Dependencies | Priority | Complexity | Current Readiness | Phase | UI Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Customer insights panel | Credit decisions at capture time | Balance, aging, open documents from AR views | CWT history and 2307-received status | Context without leaving the invoice | AR aging views (exist), receipts, 2307 tracking | Medium | M | Data exists across views; no aggregation endpoint or panel | Phase 2 | Sidebar on customer select: balance, aging buckets, recent docs, CWT profile |

## Purchasing / AP

| Feature | Business Value | Accounting Value | Compliance Value | UX Value | Dependencies | Priority | Complexity | Current Readiness | Phase | UI Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Supplier insights panel | Payment planning per supplier | Balance, aging, open bills, credits | EWT/ATC profile, 2307-issued history | Context without leaving the bill/PV | AP aging views (exist), `vw_ewt_summary_ap`, 2307 issuances | Medium | M | Data exists across views; no aggregation endpoint or panel | Phase 2 | Sidebar on supplier select: balance, aging, ATC defaults, recent 2307s |

## Reports / Reconciliation

| Feature | Business Value | Accounting Value | Compliance Value | UX Value | Dependencies | Priority | Complexity | Current Readiness | Phase | UI Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Automatic reconciliation suite | System proves its own integrity | AR aging = AR control; AP aging = AP control; inventory = inventory GL; assets = asset GL; FS = TB; TB = JE | VAT ledger = GL and 2307 = EWT ledger already enforced; extend the pattern | One dashboard of green checks | `fn_vat_gl_reconciliation` / `fn_wht_gl_reconciliation` as the pattern; PXL-DA-013 as-of views | High | L | VAT and WHT reconciliation RPCs delivered and gate returns/exports; other pairs unimplemented | Phase 2 | Reconciliation dashboard: pair, ledger amount, GL amount, variance, drill |
| Snapshot integrity re-verification & file re-download | Auditor can prove a downloaded file matches its snapshot years later | Hash re-check proves frozen evidence untampered | BIR audit defense: recompute SHA-256 over the frozen payload and regenerate the exact exported file | One-click "Verify hash" / "Re-download file" on the snapshot reader | `ReportSnapshotsPage` (delivered, PXL-DA-015); Web Crypto for client-side SHA-256 or a server RPC | Medium | S | Reader shows stored hash and frozen rows; no recompute or re-download action yet | Phase 2 | Buttons in the snapshot detail header; green/red verify badge with recomputed hash |

## Notes

- pgTAP discipline: whenever accounting behaviour changes, decide whether a regression test should exist; if yes, record the scenario in `PXL_ACCOUNTING_TEST_BOOK.md` (existing rule, restated here because backlog features that touch posting inherit it).
- Entries graduate out of this file into the work queue only when the user schedules a phase or an audit finding absorbs them (e.g. drilldown is also PXL-DA-002; the finding governs the release-blocking part, this file the product part).
