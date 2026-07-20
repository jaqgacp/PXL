# PXL Product Completeness Checklist

**Status:** Active certification authority
**Authority:** Tier 1 Certification Governance for the PXL Production Certification Program
**Owner / Domain:** Testing and Validation
**Applies To:** Every supported module and its shared engines, applied before certification
**Read When:** Preparing to certify a module, scoping a certification phase, or deciding whether a capability gap is a blocker, a backlog item, or an accepted limitation
**Do Not Read For:** Certification method and status ladder (use the module/engine standards), defect content (use the findings register), or the current bounded task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-20 completeness-checklist creation

## Purpose

This is **not** another audit findings list and it does not duplicate [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md). It is the permanent **capability-expectation checklist** run before certifying any module under [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md) and [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md). It answers one question for every capability:

> "Would a professional ERP user reasonably expect this to exist before calling this module production-ready?"

It is written from the combined perspective of the people who actually depend on an ERP: **CPA, bookkeeper, auditor, business owner, operations manager, warehouse staff, sales team, and implementation consultant.** Where those perspectives disagree, the stricter expectation wins.

## How this checklist is used

This checklist feeds two module-standard gates: gate 1 ("intended workflows are implemented and reachable") and gate 22 ("any remaining limitations are explicitly documented and acceptable for controlled production use"). For each item, at certification time the assessor records one of: **Met**, **Partially Met**, **Not Met — accepted limitation**, or **Not Met — blocker**. A **Mandatory = Yes** item that is Not Met is a certification blocker for its module and must be raised as a finding, not silently deferred. A **Mandatory = No** item that is Not Met is a documented limitation or backlog entry; it never blocks certification but must be disclosed.

Column meanings:

- **Requirement** — the concrete capability a professional user expects.
- **Why it matters** — the operational, accounting, tax, control, or trust reason.
- **Mandatory for Certification?** — Yes = the owning module cannot be Certified until this is Met (or converted to a written, accepted limitation with owner sign-off). No = desirable, non-blocking.
- **Phase** — the certification phase (per the program phase order) in which this capability must exist. Cross-cutting standards are anchored to the earliest phase that consumes them.
- **Future enhancement?** — Yes = explicitly outside current supported production scope; tracked in `00. Governance/PXL_PRODUCT_BACKLOG.md`, never asserted as present.

Phase reference: 1 Setup/Master Data + foundational engines · 2 Sales/AR · 3 Purchasing/AP · 4 Inventory · 5 Banking/Treasury + Payments · 6 Fixed Assets + Schedules · 7 Compliance/Tax · 8 Reports/FS/Reconciliation · 9 Production Operations/Backup/Deployment/Pilot.

---

## 1. Master Data Completeness

*Lens: implementation consultant and bookkeeper — a new company must be usable on day one without hand-building reference data.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Guided company setup (legal name, trade name, entity type, taxpayer type, TIN + branch code, RDO, registered/reporting address, fiscal year, functional currency, VAT/non-VAT/exempt profile, status) | Every downstream document, tax behavior, and report depends on correct company identity | Yes | 1 | No |
| Seedable Philippine Chart of Accounts template(s) by entity type | Bookkeepers cannot be expected to build a COA from scratch; wrong classification breaks the financial statements | Yes | 1 | No |
| Chart of accounts controls: type, FS classification, normal balance, control-account flag, allow-manual-posting, allow-subledger, tax classification, cash-flow classification, active dates | Prevents posting to summary/inactive/prohibited/out-of-date accounts | Yes | 1 | No |
| Default Philippine tax codes (VAT 12%, VAT-exempt, zero-rated, percentage tax, EWT/CWT/FWT with ATCs) with effective dates | Tax must be sourced from configured codes, not typed; ATC/rate errors are statutory errors | Yes | 1 / 7 | No |
| Reference RDO code list | Required for BIR registration fields and statutory outputs | Yes | 1 | No |
| Bank reference / bank master list | Needed for bank accounts, checks, and reconciliation | Yes | 1 / 5 | No |
| Payment terms master (net days, due-date logic) | Drives due dates, aging, and cash-flow expectations | Yes | 1 | No |
| Units of measure (and, where used, UOM conversions) | Inventory, sales, and purchasing lines are meaningless without governed UOM | Yes | 1 / 4 | No |
| Number series per company/branch/document type with concurrency safety and CAS-compliant date semantics | Duplicate or gapped numbers fail audit and BIR CAS | Yes | 1 | No |
| Customer and supplier masters (unique code, TIN formatting, VAT class, terms, tax defaults, EWT/CWT applicability, currency, active status, duplicate detection) | Party master errors propagate into every transaction and tax report | Yes | 1 | No |
| Item/service master (item vs service, inventory vs non-inventory, sales/purchase/inventory/COGS/variance accounts, VAT defaults, costing method, negative-stock policy) | Missing account defaults cause posting failures; wrong costing corrupts valuation | Yes | 1 / 4 | No |
| Dimension masters (branch, department, location, project, cost center, warehouse, responsible person) with effective dates and valid combinations | Management and branch reporting depend on governed dimensions | Yes (branch/warehouse); No (project/cost center where deferred) | 1 | Partial |
| Users, roles, and permissions (admin, accountant, approver, encoder, viewer; company/branch scoping; SOD) | Access control and segregation of duties are non-negotiable for a financial system | Yes | 1 | No |
| Master-data import (customers, suppliers, items, COA, opening dimensions) via template | Onboarding a real client by hand-keying hundreds of records is not viable | No | 1 / 11 | No |
| Master-data change audit (who changed a rate/account/term and when) | Auditors require traceability of reference-data changes | Yes | 1 | No |

## 2. Transaction Completeness

*Lens: CPA and auditor — every document must have a full, controlled, traceable life.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Full lifecycle per transaction (draft → approved → posted → closed) with enforced status transitions | Uncontrolled status changes break immutability and approval control | Yes | 2–6 | No |
| Partial processing (partial delivery, partial billing, partial receipt, partial payment) with remaining-balance tracking | Real business rarely completes documents in one step | Yes | 2–5 | No |
| Reversal producing a linked, equal-and-opposite, period-aware journal | Corrections must never mutate the original posted document | Yes | 2–6 | No |
| Cancellation before posting (no GL/tax/inventory effect) | Encoders need a safe way to discard drafts | Yes | 2–6 | No |
| Void after posting where legally/operationally allowed, with tax and inventory restoration | Posted-document errors need a governed, audited remedy | Yes | 2–6 | No |
| Amendments via credit/debit memo, adjustment, or return rather than edit | Editing posted records is prohibited; amendments preserve history | Yes | 2–5 | No |
| Related-document linking and drill (quote → order → delivery/receipt → invoice → payment; source ↔ journal) | Auditors and users must trace a document to its origins and effects | Yes | 2–5 | No |
| Document attachments with access control and traceability | Supporting evidence (contracts, ORs, POs) must live with the document | Yes | 2–6 | No |
| Approval workflow with permissions distinct from posting, and SOD (creator cannot approve own where prohibited) | Segregation of duties is a core control | Yes | 1 / 2 | No |
| Audit trail on every document (created/approved/posted/void, actor, timestamp, before/after) | Immutable audit evidence is the point of an accounting system | Yes | 1 | No |
| Duplicate prevention (duplicate invoice number, duplicate supplier invoice, duplicate application) | Duplicates cause double-counting and payment errors | Yes | 2–5 | No |
| Backdating controls (period-aware, no silent historical corruption) | Backdated posts must respect period locks and costing | Yes | 1–5 | No |

## 3. Inventory Completeness

*Lens: warehouse staff and operations manager — stock truth must be reproducible and never silently negative.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Goods receipt (purchase receipt) increasing quantity and value with source traceability | Inventory value enters through receipts; wrong cost corrupts COGS | Yes | 3 / 4 | No |
| Goods issue / delivery decreasing quantity with correct COGS at the approved costing method | The other half of inventory truth and margin | Yes | 2 / 4 | No |
| Warehouse-to-warehouse transfers reconciling source and destination without artificial profit/loss | Multi-warehouse operations are standard | Yes | 4 | No |
| In-transit tracking for transfers where applicable | Stock in motion must be visible, not lost | No | 4 | No |
| Inventory adjustment (increase/decrease) requiring reason, permission, and audit | Adjustments are high-risk and must be controlled | Yes | 4 | No |
| Physical count / stock count producing controlled variance adjustments | Period counts are a mandatory inventory control | Yes | 4 | No |
| Opening inventory balances (quantity + value) on migration | A real client starts with existing stock | Yes | 1 / 4 / 11 | No |
| Customer returns restoring quantity and appropriate cost | Returns are routine and must reverse both quantity and value | Yes | 2 / 4 | No |
| Purchase returns removing the correct cost | Vendor returns must not distort valuation | Yes | 3 / 4 | No |
| Reservation / commitment / allocation against orders | Prevents overselling committed stock | No | 4 | No |
| Server-side negative-stock prevention (default block), enforced under concurrency and backdating | Frontend-only checks are bypassable; negative stock corrupts costing | Yes | 4 | No |
| Item ledger / movement history reproducing quantity on hand from posted movements | Auditability of stock is mandatory | Yes | 4 | No |
| Lot/serial tracking | Regulated goods and traceability | No | 4 | Yes |
| Landed cost / cost allocation on receipts | Accurate inventory valuation for imports | No | 4 | Yes |
| Future production/manufacturing compatibility (BOM, work orders) in the inventory model | Avoids a costing rewrite when manufacturing is added | No | — | Yes |

## 4. Banking Completeness

*Lens: bookkeeper and CPA — the bank is where errors surface, so reconciliation must be first-class.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Bank and cash account setup with GL mapping | Cash movements must post to the correct ledger | Yes | 1 / 5 | No |
| Receipts and payments (OR, payment voucher, check voucher) applied to invoices/bills with unapplied-cash tracking | Core cash cycle; over-application must be blocked | Yes | 5 | No |
| Fund transfers and inter-branch transfers with reconciling due-to/due-from entries | Multi-account/branch cash handling | Yes | 5 | No |
| Petty cash and replenishment | Standard small-cash control | Yes | 5 | No |
| Bank reconciliation (statement vs book) with outstanding checks and outstanding deposits | The single most-expected accounting control; auditors require it | Yes | 5 | No |
| Bank statement CSV/Excel import | Manual re-keying statements is impractical at scale | No | 5 / 11 | No |
| Auto-matching of imported statement lines to book entries | Reconciliation speed and accuracy | No | 5 | No |
| Manual matching and un-matching | Auto-match never covers everything | Yes (if reconciliation shipped) | 5 | No |
| Split transactions (one bank line to multiple book entries) | Combined deposits/payments are common | No | 5 | No |
| Bank charges and interest handling during reconciliation | These originate on the statement, not in the books | Yes (if reconciliation shipped) | 5 | No |
| Check lifecycle (issued, cleared, stale, cancelled, bounced) | PDC and check control are standard in PH practice | No | 5 | No |
| Payment reversal restoring open balances | Cash errors need a governed remedy | Yes | 5 | No |

## 5. Reporting Completeness

*Lens: business owner, CPA, and auditor — a report that cannot be filtered, drilled, or reconciled is not usable.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Drill-down: FS line → account → journal → source document | Trust requires tracing any number to its origin | Yes | 8 | No |
| Company and branch filters on all financial reports | Branch reporting and consolidation are expected | Yes | 8 | No |
| Department / cost center / project / location filters | Management reporting and cost attribution | No (project/CC where deferred) | 8 | Partial |
| Date-basis clarity (document / posting / due date) and period selection (MTD/QTD/YTD/custom) | Ambiguous date semantics produce wrong numbers | Yes | 8 | No |
| Comparative reports (current vs prior period, current vs prior year) | Standard analytical expectation | Yes | 8 | No |
| Posting-status basis (posted only; drafts excluded unless explicitly requested) | Draft data must never leak into financials | Yes | 8 | No |
| Reconciliation targets stated and proven (subledger↔control, control↔GL, GL↔TB, TB↔FS, tax ledger↔GL, inventory↔control, branch↔company) | A report must reconcile to be certifiable | Yes | 8 | No |
| Export to Excel/CSV and PDF with values matching on-screen | Users live in Excel; exports must not diverge | Yes | 8 | No |
| Empty-state and zero-balance handling (and suppression option) | Professional presentation and correctness | Yes | 8 | No |
| Saved report parameters / scheduled report delivery | Convenience for recurring reporting | No | 8 | Yes |

## 6. Print & Document Presentation

*Lens: sales team, business owner, and auditor — every printable must be good enough to send outward unedited.*

Every printable document (invoice, OR, PO, vendor bill, statement, ledger, financial statement, CAS/BIR output) must be professional enough to send directly to **customers, suppliers, banks, auditors, and government** without manual touch-up.

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Company branding (logo, registered name, TIN, address, contact) on document header | Legitimacy and BIR requirements | Yes | 2 | No |
| Consistent header/footer with document type, number, date, page numbering | Professional, auditable presentation | Yes | 2 | No |
| Clean line-item tables with aligned amounts, subtotals, tax lines, and grand totals | Misaligned totals read as amateurish and cause disputes | Yes | 2 | No |
| Correct tax presentation (VAT breakdown, VAT-inclusive/exclusive, withholding) and amount-in-words where required | Statutory and commercial requirement | Yes | 2 / 7 | No |
| Signatory blocks (prepared/checked/approved/received) where applicable | Required for many PH commercial and statutory documents | Yes | 2 | No |
| BIR-compliant invoice/receipt formatting and required legends | Non-compliant printouts are a statutory failure | Yes | 7 | No |
| QR code / machine-readable reference where mandated or useful | Emerging BIR and verification expectations | No | 7 | Yes |
| Controlled page breaks (no split totals, repeated headers on multi-page) | Long documents must remain readable | Yes | 2 | No |
| Consistent typography and print-safe layout | Brand and legibility | Yes | 2 | No |
| High-quality, selectable-text PDF output (not rasterized) | Auditors and banks need searchable, crisp PDFs | Yes | 2 | No |

## 7. UX Completeness

*Lens: implementation consultant and daily user — one universal shell is not enough; each transaction type needs a governed UX spec.*

The transaction workspace standard (`../12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md`) provides the shell. Certification additionally requires a **transaction-specific UX specification** per document type, so that field placement, actions, and states match how that document is actually worked.

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Per-transaction UX spec for each shipped document type (e.g. Sales Invoice, Official Receipt, Purchase Order, Vendor Bill, Payment Voucher, Journal Entry, Inventory Adjustment) | Generic layouts hide document-specific needs and cause errors | Yes | 2–6 | No |
| Master-data and report UX specs (list, detail, filter, edit patterns) | Setup and reporting are used constantly and must be coherent | Yes | 1 / 8 | No |
| Defined layout, header, sidebar, and tab structure per spec | Consistency and learnability across the product | Yes | 2–6 | No |
| Quick actions (save, approve, post, print, duplicate, void) surfaced per lifecycle state | Speed and correctness of daily work | Yes | 2–6 | No |
| Inline, field-level validation messages with clear remediation | Users must know exactly why a save/post is blocked | Yes | 2–6 | No |
| Empty states with guidance (what to do first) | New companies and modules start empty | Yes | 1–8 | No |
| Loading and saving states / optimistic feedback | Perceived reliability during posting | Yes | 2–6 | No |
| Keyboard-friendly data entry (tab order, shortcuts) | Encoders are power users | No | 2–6 | No |
| Accessibility (labels, focus, error semantics, contrast) | Inclusive use and login accessibility (tracked separately) | No | 1–8 | No |

## 8. Search & Productivity

*Lens: operations manager and daily user — finding a document in seconds is a baseline expectation.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Global and per-list search (by number, party, amount, date) | Users must locate any document quickly | Yes | 2–8 | No |
| Filtering, sorting, and pagination on all document/master lists | Long lists are unusable otherwise | Yes | 1–8 | No |
| Duplicate/similar-record detection during entry | Prevents duplicate parties and documents | No | 1–5 | No |
| Recent items and quick navigation | Everyday productivity | No | — | No |
| Bulk actions (bulk approve/print/export) where safe | Efficiency for high-volume operators | No | 2–8 | Yes |
| Saved views / personal filters | Tailored workflows | No | — | Yes |

## 9. Dashboard & Notifications

*Lens: business owner and operations manager — the system should surface what needs attention.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Company/branch dashboard with cash, AR, AP, and key balances | Owners expect an at-a-glance financial picture | No | 8 | No |
| Actionable work queues (drafts to approve, bills due, overdue AR) | Drives daily operations and cash management | No | 8 | No |
| Statutory/tax calendar and deadline reminders | Missed BIR deadlines carry penalties | Yes | 7 | No |
| Exception alerts (negative stock attempts, failed posting, reconciliation variances) | Early warning on control breaks | No | 8 / 9 | No |
| In-app and/or email notifications for approvals and assignments | Keeps workflows moving | No | — | Yes |

## 10. Import / Export

*Lens: implementation consultant and CPA — data must be able to get in, and must never be trapped.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Templated import for master data and opening balances | Onboarding real clients is otherwise impractical | No (Yes for a real pilot client) | 1 / 11 | No |
| Transaction import for migration (historical documents/balances) | Mid-year cutovers need history | No | 11 | No |
| Export of master data, GL, journals, AR, AP, inventory, tax ledgers, and reports | Client data must not be trapped; supports audit and exit | Yes | 8 / 9 | No |
| Attachment export where practical | Complete record portability | No | 9 | No |
| Import validation with error reporting and safe rollback | Bad imports must fail cleanly, not corrupt data | Yes (if import shipped) | 11 | No |

## 11. Opening Balance & Migration

*Lens: implementation consultant and CPA — go-live correctness depends entirely on clean opening balances.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Opening GL balances producing a balanced opening trial balance | Every migration starts here; must balance | Yes | 1 / 11 | No |
| Opening AR/AP subledger balances reconciling to control accounts | Aging and statements must tie out from day one | Yes | 11 | No |
| Opening inventory quantities and values reconciling to the inventory control account | Stock and valuation cutover integrity | Yes | 4 / 11 | No |
| Opening fixed-asset cost and accumulated depreciation | Depreciation continuity for existing assets | Yes | 6 / 11 | No |
| Opening bank balances and outstanding items for first reconciliation | First bank rec must be possible | Yes | 5 / 11 | No |
| Documented, repeatable cutover procedure with validation checklist | Go-live must be controlled and reversible | Yes | 11 | No |
| Parallel/shadow-run support for a pilot period | Safe validation against existing official records | Yes (for pilot) | 9 / 11 | No |

## 12. Month-End & Year-End Closing

*Lens: CPA and auditor — closing is where control and correctness are proven each period.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Period open / soft-close / hard-close enforced on posting date | The core temporal control of accounting | Yes | 1 | No |
| Controlled, audited period reopening | Reopening must be rare, permissioned, and logged | Yes | 1 | No |
| Recurring journals, accruals, and auto-reversals | Standard period-end mechanics | Yes | 6 | No |
| Amortization and revenue-recognition schedules with duplicate-run prevention | Deferred items must recognize on schedule, once | No | 6 | No |
| Depreciation run with duplicate-run prevention and closed-period behavior | Fixed-asset period-end must be safe | Yes | 6 | No |
| Year-end close producing correct retained earnings / current-year profit treatment | The annual close must be correct or the balance sheet is wrong | Yes | 8 | No |
| Closing/post-closing trial balance and adjusted trial balance | Auditors expect these standard artifacts | Yes | 8 | No |
| Month-end reconciliation pack (control accounts, tax, inventory, bank) | Proves the period is clean before it is locked | Yes | 8 | No |

## 13. Security & Audit

*Lens: auditor and business owner — access, isolation, and evidence must be provable, not assumed.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Company and branch isolation enforced server-side (RLS), through UI, direct queries, and RPC | Tenant data must never leak across companies | Yes | 1 | No |
| Role-based permissions and segregation of duties | Prevents unauthorized posting/approval | Yes | 1 | No |
| Posted-document immutability enforced at the database | Editing history is the cardinal sin of accounting software | Yes | 1 | No |
| Complete audit trail (create/approve/post/void/config change) with actor, timestamp, before/after | Auditability and dispute resolution | Yes | 1 | No |
| Protected admin and BIR/tax configuration writes with audit | Statutory configuration is high-risk | Yes | 1 / 7 | No |
| Secret hygiene: service-role credentials never reach the frontend | A leaked service key bypasses all security | Yes | 1 / 9 | No |
| Secure session/auth (expiry, revoked/inactive user behavior, provisioning) | Basic platform security | Yes | 9 | No |
| Export/print permission controls and attachment access boundaries | Data exfiltration control | No | 8 / 9 | No |

## 14. Localization (Philippines)

*Lens: CPA and auditor — PXL is Philippine-compliance-first; statutory fit is a certification gate, not a nicety.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| VAT (2550M/2550Q) sourced from transaction data with reconciliation to GL | Core PH indirect-tax compliance | Yes | 7 | No |
| Percentage tax for non-VAT taxpayers | Required for non-VAT entities | Yes | 7 | No |
| EWT/CWT/FWT with ATCs and correct recognition timing | Withholding is pervasive in PH transactions | Yes | 7 | No |
| BIR forms/certificates: 2307 (issued/received), 1601EQ, 1604E, SAWT, QAP | Statutory filing artifacts | Yes | 7 | No |
| SLSP / SLS / SLP (RELIEF) exports | Mandatory relief listings | Yes | 7 | No |
| BIR Books of Accounts and CAS-compliant exports with governed date semantics | CAS registration and audit | Yes | 7 | No |
| TIN and branch-code formatting standard | Data integrity for all statutory outputs | Yes | 1 / 7 | No |
| PHP currency, local date formatting, and amount-in-words | Presentation correctness | Yes | 2 / 7 | No |
| Income tax return support | Broader statutory coverage | No | 7 | Yes |
| e-Invoicing / EIS integration | Emerging BIR direction | No | — | Yes |

## 15. Performance & Scalability

*Lens: operations manager and implementation consultant — the system must stay responsive at real client volumes.*

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Acceptable response times for list, post, and report at realistic data volumes | Slow accounting software is abandoned | Yes | 9 | No |
| Pagination and server-side filtering on large datasets | Prevents client-side overload | Yes | 8 | No |
| Concurrency safety (no duplicate numbers, no negative-stock bypass, no double application under load) | Multi-user correctness | Yes | 1–5 | No |
| Report generation that scales with period size (indexing, set-based queries) | Year-end and multi-branch reports must complete | Yes | 8 | No |
| Storage growth and attachment-size management | Long-term operability | No | 9 | No |
| Load/scale testing evidence at target tenant counts | Confidence before broad rollout | No | 9 | Yes |

## 16. Future Expansion Readiness

*Lens: business owner and implementation consultant — today's data model should not block tomorrow's modules.*

All items here are **future enhancements** (not mandatory for current certification); the requirement is only that the current architecture does not preclude them.

| Requirement | Why it matters | Mandatory | Phase | Future |
| --- | --- | --- | --- | --- |
| Payroll module compatibility (employee master, statutory contributions, payroll journals) | Common next ERP need for PH businesses | No | — | Yes |
| CRM compatibility (leads, opportunities, customer 360 from sales data) | Sales growth beyond invoicing | No | — | Yes |
| Manufacturing/production compatibility (BOM, work orders, WIP costing) | Inventory model must anticipate production costing | No | — | Yes |
| POS integration (cash sales, shift/Z-reads, offline sync) | Retail expansion | No | — | Yes |
| Public/partner API and webhooks | Integrations and ecosystem | No | — | Yes |
| Multi-currency transactions and revaluation | Import/export and FX clients | No | — | Yes |
| Consolidation across multiple legal entities | Group reporting | No | — | Yes |

---

## Certification Note

Meeting this checklist is necessary but not sufficient for certification: a module is Certified only when it also passes the mandatory gates, reconciliations, security, correction, and operational evidence in [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md) and every engine it depends on passes [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md). Current module and engine status is tracked only in [`PXL_CERTIFICATION_MATRIX.md`](PXL_CERTIFICATION_MATRIX.md); this checklist assigns no statuses and certifies nothing on its own.
