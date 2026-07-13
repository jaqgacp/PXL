# PXL Standard Transaction Workspace

Status: **OFFICIAL PRODUCT VISION — canonical Phase 2 transaction architecture** (user directive 2026-07-10, session 60; DEC-013). This is the single highest product priority immediately after production-critical audit findings are complete. It is NOT permission to stop, delay, or de-prioritize audit work: critical accounting, tax, posting, security, immutability, audit-trail, and compliance findings always outrank it (DEC-012).

Every AI agent (Claude, Codex, Gemini, Fable, GPT, etc.) must follow this document for every business transaction page in PXL.

## Document Hierarchy

1. `PXL_TRANSACTION_MATRIX.md` + migrations — what transactions DO (behavior; always wins).
2. **This document** — the official vision: what every transaction page must become.
3. `PXL_TRANSACTION_EXPERIENCE_STANDARD.md` (session 48) — the detailed design blueprint subordinate to this vision: tab specs, line-grid column groups, auto-population matrix, account-determination ladder, panel contracts, current-state maturity table. When the two disagree, this document wins; update the blueprint to match.
4. `UI_UX_PRINCIPLES.md` — visual/interaction language (its stack notes remain aspirational; selective adoption per the backlog governs).
5. `PXL_PRODUCT_BACKLOG.md` — per-feature priority/complexity rows for incremental adoption.

Routing rule for anything discovered while aligning pages to this standard:

- Functional bugs → `PXL_END_TO_END_AUDIT_FINDINGS.md`
- Architectural enhancements → this document (vision-level) or the backlog (feature-level)
- Permanent architectural decisions → `AI/AI_DECISIONS.md`

## Product Vision

PXL must not look or behave like a traditional CRUD accounting application. It should feel like a modern ERP — Oracle NetSuite, Microsoft Dynamics 365 Business Central, SAP Business One. Every transaction page becomes a complete business workspace where users understand, validate, post, audit, and navigate the entire document lifecycle without leaving the page.

**The objective is consistency:** a user who understands one transaction page immediately understands every other transaction page.

Every transaction page should answer, without navigating elsewhere:

- What is this document? Who is involved?
- What is the financial / accounting / tax impact?
- Is it valid and ready to post? What workflow stage is it in?
- Who created, edited, approved, posted it?
- What documents came before and after it?
- What journal entry and taxes will be generated?
- What actions are still pending?

## Applies To

All posting transactions, present and future:

- **Sales:** Quotation, Sales Order, Delivery Receipt, Sales Invoice, Cash Sale, Receipt, Credit Memo, Debit Memo, Customer Return
- **Purchasing:** Purchase Request, Purchase Quotation, Purchase Order, Receiving Report, Vendor Bill, Cash Purchase, Payment Voucher, Vendor Credit, Supplier Debit Memo, Purchase Return
- **Accounting:** Journal Entry, Recurring Journal, Accrual Entry, Reversal Entry
- **Banking & Treasury:** Bank Deposit, Bank Transfer, Check Issuance, Outstanding Checks, Bank Reconciliation, Bank Adjustment
- **Inventory:** Stock Adjustment, Transfer, Goods Receipt, Goods Issue, Physical Count, Inventory Reclassification, Write-off
- **Fixed Assets:** Acquisition, Depreciation, Transfer, Disposal, Impairment

## Standard Page Structure

Every transaction page eventually contains these sections. The layout must remain consistent across all modules.

### 1. Document Header

Display only the facts needed to immediately identify and process the transaction: document number, compact Posting / Collection / Lock state chips, clickable party name, primary metrics, and the status-aware toolbar. Keep the header short. Actions live here only; do not duplicate them in cards or tabs. Do not permanently display workflow history, audit metadata, system configuration, related-document links, accounting detail, tax detail, or full party-master fields here.

### 2. Related Party Snapshot

Customer (sales) / Supplier (purchasing) / Company-subsidiary context (JE) belongs in the **Related Party** tab, not in a permanent sidebar or expanded header. This tab is the embedded live party profile: identity, contacts, addresses, tax profile, credit profile, outstanding AR/AP, recent payments/invoices/bills, aging summary, payment information, and sales/purchasing information.

### 3. Financial Summary

Server-computed whenever possible. Per-document contracts, for example:

- **Sales Invoice:** Subtotal, Discount, VAT Base, VAT, Gross, Expected Customer Withholding, Net Receivable, Paid, Balance Due
- **Vendor Bill:** Subtotal, Input VAT, Supplier EWT, Gross, Net Payable, Paid, Outstanding
- **Receipt:** Invoice Amount, Collected, Applied CWT, Remaining
- **Payment Voucher:** Bill Amount, Applied EWT, Cash Paid, Outstanding
- **Journal Entry:** Debit, Credit, Difference, Balanced

### 4. Posting Validation

Company Ready · Branch Ready · Fiscal Period Open · Approval Complete · Number Series Ready · GL Mapping Ready · Tax Configuration Ready · Workflow Ready · Balanced · **Ready To Post** · Blocked Reason.

### 5. Workflow Tab

Visual document lifecycle, e.g. Draft → Submitted → Approved → Posted → Applied → Paid → Closed. Each module uses its own appropriate workflow. The lifecycle belongs in the Workflow / Approval area, not as a permanent strip under the header.

### 6. ERP-Style Tabs

A defining characteristic of PXL (NetSuite-style). Tabs are perspectives on the same transaction: Lines, Financial Summary, GL Impact, Tax Impact, Validation, Workflow, Approval, Audit Trail, Related Documents, Related Party, Attachments, Activity Timeline, Notes, System, Compliance Evidence (future). Hide irrelevant tabs per document type.

### 7. Professional Line Grid

Enterprise-grade grid. Column pool: Item, Service, Description, Quantity, Unit, Warehouse, Lot, Serial, Unit Price, Discount %/Amount, VAT Code, VAT Amount, ATC, EWT %, Expected Withholding, Net Amount, Revenue/Expense/Inventory Account, Department, Branch, Location, Cost Center, Project, Functional Entity, Customer, Supplier, Reference, Remarks, Attachment Indicator, Approval Status, Posting Status. **Visibility depends on transaction type and user role.**

The grid includes a reusable saved-view system. Every transaction table must support the same baseline views: **Default, Accounting, Tax, Audit, Inventory, Sales, Custom**. Users can save, update, rename, and delete custom views. The table persists selected view, visible columns, column order, pinned columns, column widths, density, sorting, and filters per workspace key. Compact density is the default.

The table toolbar order is: View Selector · Choose Columns · Filter · Export · Refresh. The Choose Columns panel groups fields by General, Sales, Inventory, Tax, Accounting, Dimensions, Audit, and System; includes search, Select All, Clear All, Reset to Current View, and Reset to System Default; and exposes drag-and-drop ordering plus pin/unpin controls. Wide accounting tables use sticky headers, sticky totals where present, and sticky pinned identity columns.

### 8. Line Detail Panel

Selecting a line exposes: General, Tax Details, Dimensions, Account Determination, Inventory Details, Notes, Attachments, Related Documents, Audit. Avoid overcrowding the main grid.

### 9. Three-Card Information Band (final standard, 2026-07-13 refinement)

The workspace has no right sidebar. Directly below the header it renders exactly three compact white cards: **Document Information · Customer/Vendor Information · Transaction Context**. Quick Actions is not a card; the header toolbar is the single source of document actions. Financial Summary, Posting Validation, customer snapshot, workflow, audit summary, related-document links, tax detail, GL detail, and system metadata belong in their dedicated tabs and must not be duplicated in cards or a rail.

The three cards are intentionally small:

- **Document Information:** document date, due date, branch, currency, payment terms, and reference if present. Source type, document series, document hash, posting engine, created by, and modified by belong in System/Audit.
- **Customer/Vendor Information:** clickable party, party code, TIN, and VAT/tax classification only. The full master-record snapshot belongs in Related Party.
- **Transaction Context:** only dimensions that directly affect posting, such as salesperson, project, cost center, and department. Source documents belong in Related Documents/System; price list, payment method, and delivery terms belong in Related Party; marketing fields belong in the future marketing module; detailed dimensions belong in line detail or a future Dimensions tab.

The document header uses the company-selected `companies.workspace_accent_color`; the workspace derives a subtle tint through CSS color mixing while cards remain white. The tab bar uses a very light tint from the same accent, and only the active tab uses the stronger accent. The preference is maintained in Company Setup and consumed by the reusable workspace rather than hardcoded per transaction.

Enterprise visual standard: every tab begins with a compact section header; all transaction tables share the same row height, header height, numeric alignment, borders, hover state, totals row, and compact empty state; corners stay sharp (2-4px), borders are thin/neutral, shadows are minimal, and color is reserved for state or interaction.

Single-responsibility rule: if a field or action appears in more than one permanent section, remove one occurrence. Actions live in the header toolbar; workflow lives in Workflow/Approval; master data lives in master records and the Related Party tab; transaction data lives in the transaction cards/tabs; accounting data lives in GL Impact; tax data lives in Tax Impact; audit data lives in Audit/System.

## GL Impact

Every posting transaction eventually exposes: draft GL preview, posted journal entries (debit, credit, journal number, posting date), and drilldown. **GL Impact must always come from the authoritative posting engine** (`fn_preview_gl_impact` / `fn_get_accounting_trace` are the current contracts).

## Tax Impact

Every tax-related transaction eventually exposes: VAT (input/output), EWT, FWT, ATC, 2307, 2306, SAWT, QAP, SLSP, tax ledger entries, tax posting status, tax snapshot.

## Related Documents

Complete bidirectional drill-through, e.g. Quotation → Sales Order → Delivery Receipt → Sales Invoice → Receipt → Journal Entry — navigable in both directions.

## Audit Trail

Every transaction exposes: Created/Edited/Submitted/Approved/Posted/Voided/Reversed By, timestamp history, system events. (`AuditTrailSection` + lifecycle facts; rollout tracked as PXL-AUD-050.)

## Activity Timeline

Chronological history: Created, Edited, Submitted, Approved, Printed, Emailed, Posted, Payment Applied, Credit Applied, Voided, Reversed.

## Smart Master Data (mandatory principle)

PXL minimizes manual encoding. Whenever a transaction form requires information that does not exist in master data, STOP and evaluate whether it belongs in master data. If the information is reusable across transactions, companies, or documents, promote it to master data instead of leaving it a manual field.

- Selecting a **Customer** populates: TIN, address, terms, VAT type, tax profile, ATC, expected withholding, currency, price list, salesperson, project, branch, dimensions, contact person, default delivery/billing address, credit limit.
- Selecting a **Supplier** populates: TIN, address, payment terms, supplier tax profile, EWT defaults, ATC, currency, expense defaults, bank details.
- Selecting an **Item/Service** populates: description, revenue/expense/inventory/COGS account, VAT code, ATC, default price, warehouse, unit, dimensions, project defaults, cost center, location.

If a transaction repeatedly asks users to manually encode the same information, that is a **Master Data design gap** — document it and resolve it through master data enhancement, not additional manual input.

## Account Determination

Normal users never manually select accounting accounts unless specifically permitted. Accounts derive automatically from: Item → Service → Item Group → Posting Rules → Accounting Mapping → Company Configuration. Only authorized accounting users may override mappings. (Detailed ladder in the session-48 blueprint §7.)

## Implementation Strategy

- DO NOT stop current audit work. DO NOT rewrite every screen. DO NOT create scope creep.
- Whenever a module is revisited after production-critical work: compare it against this standard, improve it incrementally ("adopt-on-touch"), reuse existing components, extract reusable components instead of duplicating, and record intentionally deferred gaps in the backlog.
- New pages adopt the standard from day one.

## Reusable Component Targets

TransactionHeader · PrimaryInformationPanel (three-card band) · FinancialSummaryPanel · PostingValidationPanel · WorkflowStrip/WorkflowPanel · TransactionTabsBar · ProfessionalLineGrid · LineDetailPanel · GLImpactPanel · TaxImpactPanel · AuditTrailPanel · RelatedDocumentsPanel · AttachmentPanel · ActivityTimeline · SystemInformationPanel

Existing inventory (see blueprint §2 for adoption state): `GLImpactPanel`, `SetupReadinessBanner` (→ PostingValidationPanel), `VATReconciliationPanel`, `StatusBadge`, `AuditTrailSection` (→ AuditTrailPanel), plus built-but-unadopted `DataTable`, `LookupDialog`, `FormSection`, `ConfirmDialog`, `EmptyState`. Extend and rename toward the target names as pages are touched; never fork a second implementation of an existing panel.

## Success Criteria

Every transactional page in PXL feels like a single, intelligent ERP workspace rather than a collection of disconnected forms. Users can understand, validate, approve, post, audit, reconcile, and navigate an entire business transaction from one consistent interface. This is the official long-term UI/UX vision of PXL and guides all module development after production readiness is achieved.

## Pilot Reference Implementation (Sales Invoice)

Sales Invoice is the canonical pilot. Every other transaction adopts this shape.

- **Canonical route:** `/sales-invoices/:id` → `src/pages/SalesInvoiceDocumentPage.tsx` renders `DocumentLayout`. This is the single viewing/review/lifecycle surface for a saved invoice. The register (`SalesInvoicePage`) routes non-draft rows here; draft create/edit still uses the register editor until the form is relocated onto the route (the final consolidation step).
- **Lifecycle actions on the route:** Submit for Approval / Post / Return to Draft / Void (reason dialog) call the existing RPCs (`fn_approve_sales_invoice`, `fn_post_sales_invoice`, `fn_revert_si_to_draft`, `fn_void_sales_invoice`); the server enforces role/SoD. Toolbar actions are shown only for states that allow them; posted invoices are never editable.
- **Header:** company-accent header owns document number, compact Posting / Collection / Lock chips, clickable Customer, Invoice Total/Collected/Balance Due, and all document actions. The More menu renders through a portal so it is never clipped by container overflow.
- **Primary Information** (`PrimaryInformationPanel`) between header and tabs: exactly three independent cards — Document Information / Customer Information / Sales Context. Existing values come from the SI snapshot and governed master data with provenance hints. Unsupported schema fields render truthfully as unassigned and are not populated with static business values.
- **Tabs (compact fixed order):** Lines (`LineGrid` + `LineDetailPanel` on row-select) · Financial Summary (`FinancialSummaryPanel`, full contract incl. collection) · GL Impact (`GLImpactPanel`) · Tax Impact (`TaxImpactPanel`, VAT-only until PXL-AUD-031/032/033) · Posting Validation (`PostingValidationPanel` live preflight) · Workflow · Approval (`approval_instances` or empty state) · Audit Trail (`AuditTrailSection`) · Related Documents (`RelatedDocumentsTab`) · Related Party · Attachments (deferred empty state — no storage yet) · Activity Timeline (lifecycle facts; semantic stream pending PXL-DA-016) · Notes (memo; threaded notes deferred) · System.
- **No right rail:** duplicate Financial / Customer / Validation / Audit sidebar cards were removed by the final 2026-07-13 standard.
- **Professional Lines:** Operations / Accounting / Audit / All profiles, individual column chooser, the full requested column pool, inline expandable rows, and the compact totals band are reusable `LineGrid` capabilities. Unstored dimensions/EWT allocation remain blank rather than fabricated.
- **Master Data gaps found (SI pilot):** Salesperson, Price List, Project, Delivery Terms, Campaign, Opportunity, Customer Industry/Territory/Price Level, and transaction dimension links are not fully modeled on Customer/Item/SI. Department, Cost Center, and Warehouse masters exist but are not linked to SI. Resolve these through master-data entities and foreign keys before making them editable; do not add static transaction options. Company workspace accent is now governed by Company master via migration `20260713000001_company_workspace_appearance.sql`.

### Reusable RelatedDocumentsTab contract (§12 / spec §14)

`src/components/document/RelatedDocumentsTab.tsx` renders the FULL expected chain — existing stages are clickable, missing stages show "None / Not created" plus an allowed create action. The owning page supplies `RelatedDocRow[]` (`relationship`, `docType`, `direction` upstream/current/downstream, `number`, `date`, `status`, `amount`, `href`, `action`, `note`); the component hardcodes no chain, so sales, purchasing, and accounting chains all reuse it. Existing links resolved for SI today: **Journal Entry** (`journal_entries.reference_doc_type='SI'` + `reference_doc_id`) and **Receipts** (`receipt_lines.invoice_id`). Upstream Quotation/SO/DR and CM/DM are shown as chain-skeleton rows (not yet linked on the SI record).

Expected chains (drilldown/drillback both directions):
- **Sales:** Quotation → Sales Order → Delivery Receipt → **Sales Invoice** → Official Receipt → Journal Entry; Credit/Debit Memo branch off SI; 2307-received + VAT snapshot where applicable.
- **Purchasing:** Purchase Request → Purchase Order → Receiving Report → Vendor Bill → Payment Voucher → Vendor Credit → 2307 → Journal Entry.

### Rollout Matrix

Adoption: ✅ done · ⬜ not started. Fill per-page detail (tabs, line-grid profile, sidebar cards, gaps) as each page is adopted on-touch. All shared components below are built and ready to reuse.

| Transaction | Canonical route (target) | Workspace adoption | Related-doc chain |
| --- | --- | --- | --- |
| Sales Invoice | `/sales-invoices/:id` | ✅ final dense view/lifecycle template; draft-form relocation pending | Quo→SO→DR→SI→OR→JE; CM/DM |
| Cash Sale | `/cash-sales/:id` | ⬜ | Cash Sale→JE |
| Receipt (OR) | `/receipts/:id` | ⬜ | SI→OR→JE; 2307 recv |
| Credit Memo | `/credit-memos/:id` | ⬜ | SI→CM→JE |
| Debit Memo | `/debit-memos/:id` | ⬜ | SI→DM→JE |
| Quotation | `/quotations/:id` | ⬜ | Quo→SO |
| Sales Order | `/sales-orders/:id` | ⬜ | Quo→SO→DR→SI |
| Delivery Receipt | `/delivery-receipts/:id` | ⬜ | SO→DR→SI |
| Customer Return | `/customer-returns/:id` | ⬜ | SI→Return→JE |
| Purchase Order | `/purchase-orders/:id` | ⬜ | PR→PO→RR→VB |
| Receiving Report | `/receiving-reports/:id` | ⬜ | PO→RR→VB |
| Vendor Bill | `/vendor-bills/:id` | ⬜ (recommended next) | PO→RR→VB→PV→JE |
| Cash Purchase | `/cash-purchases/:id` | ⬜ | Cash Purchase→JE |
| Payment Voucher | `/payment-vouchers/:id` | ⬜ | VB→PV→JE; 2307 issued |
| Vendor Credit | `/vendor-credits/:id` | ⬜ | VB→VC→JE |
| Purchase Return | `/purchase-returns/:id` | ⬜ | RR/VB→Return→JE |
| Journal Entry | `/journal-entries/:id` | ⬜ | JE ↔ source ↔ reversal |

Reusable components available for adoption (`src/components/document/`): `DocumentLayout` (+ `WorkflowStrip`, `TransactionTabsBar`, `TransactionTabs`, `DocumentToolbar`), `PrimaryInformationPanel`, `FinancialSummaryPanel`, `PostingValidationPanel`, `LineGrid`, `LineDetailPanel`, `TaxImpactPanel`, `RelatedDocumentsTab`.

**Standard tab bar (`TransactionTabsBar`):** compact NetSuite/SAP-B1/Dynamics-BC density. The twelve tabs share width equally, shrink intelligently, truncate before overflow, and remain one line with no arrows or horizontal scrollbar. `DocumentLayout` renders it at full content width. This is the standard tab component for every Sales/Purchasing/Inventory/Banking/Fixed-Asset/Accounting workspace — do not fork it.

## Maintenance

Whenever architecture decisions affect transaction pages, update this document. Keep the session-48 blueprint (`PXL_TRANSACTION_EXPERIENCE_STANDARD.md`) synchronized as the implementation-detail layer; keep per-feature rows in `PXL_PRODUCT_BACKLOG.md`.
