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

Display: Document Number, Status, Workflow Status, Posting Status, Lock Status, Document Date, Posting Period, Branch, Functional Entity, Currency, Exchange Rate.
Toolbar: Save, Submit, Approve, Reject, Post, Void, Reverse, Print, Email, Actions.

### 2. Party Snapshot

Customer (sales) / Supplier (purchasing) / Company-subsidiary context (JE). Shows the party's name, TIN, address, contact, payment/credit terms, tax profile, VAT type, ATC defaults, withholding profile, outstanding balance, credit limit, available credit, salesperson, currency, price list, warehouse, project — as applicable.

### 3. Financial Summary

Server-computed whenever possible. Per-document contracts, for example:

- **Sales Invoice:** Subtotal, Discount, VAT Base, VAT, Gross, Expected Customer Withholding, Net Receivable, Paid, Balance Due
- **Vendor Bill:** Subtotal, Input VAT, Supplier EWT, Gross, Net Payable, Paid, Outstanding
- **Receipt:** Invoice Amount, Collected, Applied CWT, Remaining
- **Payment Voucher:** Bill Amount, Applied EWT, Cash Paid, Outstanding
- **Journal Entry:** Debit, Credit, Difference, Balanced

### 4. Posting Validation

Company Ready · Branch Ready · Fiscal Period Open · Approval Complete · Number Series Ready · GL Mapping Ready · Tax Configuration Ready · Workflow Ready · Balanced · **Ready To Post** · Blocked Reason.

### 5. Workflow Strip

Visual document lifecycle, e.g. Draft → Submitted → Approved → Posted → Applied → Paid → Closed. Each module uses its own appropriate workflow.

### 6. ERP-Style Tabs

A defining characteristic of PXL (NetSuite-style). Tabs are perspectives on the same transaction: Lines, Financial Summary, GL Impact, Tax Impact, Approval, Audit Trail, Related Documents, Attachments, Activity Timeline, Notes, Workflow, System, Compliance Evidence (future). Hide irrelevant tabs per document type.

### 7. Professional Line Grid

Enterprise-grade grid. Column pool: Item, Service, Description, Quantity, Unit, Warehouse, Lot, Serial, Unit Price, Discount %/Amount, VAT Code, VAT Amount, ATC, EWT %, Expected Withholding, Net Amount, Revenue/Expense/Inventory Account, Department, Branch, Location, Cost Center, Project, Functional Entity, Customer, Supplier, Reference, Remarks, Attachment Indicator, Approval Status, Posting Status. **Visibility depends on transaction type and user role.**

### 8. Line Detail Panel

Selecting a line exposes: General, Tax Details, Dimensions, Account Determination, Inventory Details, Notes, Attachments, Related Documents, Audit. Avoid overcrowding the main grid.

### 9. Right Sidebar

Contextual cards without leaving the document: Financial Summary, Posting Validation, GL Preview, Tax Summary, Party Snapshot, Audit Summary, Workflow, Warnings, Quick Actions.

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

TransactionHeader · PartySnapshotCard · FinancialSummaryPanel · PostingValidationPanel · WorkflowStrip · TransactionTabs · ProfessionalLineGrid · LineDetailPanel · GLImpactPanel · TaxImpactPanel · AuditTrailPanel · RelatedDocumentsPanel · AttachmentPanel · ActivityTimeline · QuickActionSidebar · SystemInformationPanel

Existing inventory (see blueprint §2 for adoption state): `GLImpactPanel`, `SetupReadinessBanner` (→ PostingValidationPanel), `VATReconciliationPanel`, `StatusBadge`, `AuditTrailSection` (→ AuditTrailPanel), plus built-but-unadopted `DataTable`, `LookupDialog`, `FormSection`, `ConfirmDialog`, `EmptyState`. Extend and rename toward the target names as pages are touched; never fork a second implementation of an existing panel.

## Success Criteria

Every transactional page in PXL feels like a single, intelligent ERP workspace rather than a collection of disconnected forms. Users can understand, validate, approve, post, audit, reconcile, and navigate an entire business transaction from one consistent interface. This is the official long-term UI/UX vision of PXL and guides all module development after production readiness is achieved.

## Maintenance

Whenever architecture decisions affect transaction pages, update this document. Keep the session-48 blueprint (`PXL_TRANSACTION_EXPERIENCE_STANDARD.md`) synchronized as the implementation-detail layer; keep per-feature rows in `PXL_PRODUCT_BACKLOG.md`.
