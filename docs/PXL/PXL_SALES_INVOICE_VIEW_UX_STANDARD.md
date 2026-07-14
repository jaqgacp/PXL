# PXL Sales Invoice View UX Standard

**Status: Approved**

Date: 2026-07-14  
Scope: Existing Sales Invoice review, approval, posted-document view, collection monitoring, void/reversal review, drilldown, and audit UX  
Document type: Product and UX standard only  
Implementation boundary: This document does not implement code, modify components, change routes, edit database schemas, create migrations, change accounting logic, change tax logic, change posting logic, change permissions or RLS, refactor pages, or add unsupported fields.

## 1. Purpose and Scope

The Sales Invoice View is the canonical document-of-record workspace for an existing invoice.

It governs:

- `/sales-invoices/:id`
- Review of saved invoices
- Approval review
- Posted-document review
- Collection monitoring
- GL and tax truth
- Audit and lifecycle history
- Related-document trace
- Customer snapshot and current customer information
- Attachments and activity
- Void and reversal review
- Controlled downstream actions

The view must allow a user to answer, without leaving the workspace:

- What invoice is this?
- Who is the customer?
- What exact customer and tax information was used when this invoice was issued?
- What is its current posting, collection, and lock status?
- What is the invoice total?
- How much has been collected?
- What remains outstanding?
- What lines created the invoice?
- What GL entry did it create?
- What tax impact did it create?
- Is its accounting balanced?
- What validation, approval, and posting events occurred?
- Who created, edited, approved, posted, voided, reversed, printed, or emailed it?
- What documents came before and after it?
- What receipts, credit memos, journal entries, and tax records are linked?
- What customer information is current today?
- What customer information was captured on the invoice?
- What supporting files, notes, activities, and system metadata exist?
- What actions are still allowed based on status and permission?

The view must feel like an enterprise accounting document workspace, not a disabled CRUD form, customer-master page, GL report, tax report, technical debug screen, or dashboard of repeated summaries.

## 2. Authority and Precedence

Authority hierarchy:

1. `PXL_ACCOUNTING_RULES_MATRIX.md` governs accounting treatment, debit and credit behavior, account determination, reversal, void, cancellation, report impact, and accounting tests.
2. `PXL_TRANSACTION_MATRIX.md` governs transaction lifecycle, source relationships, statuses, applications, posting behavior, and document data contracts.
3. `PXL_SALES_INVOICE_UX_STANDARD.md` governs Sales Invoice creation and draft-edit UX.
4. `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md` governs Sales Invoice review, approval, posted-document view, collection monitoring, void/reversal review, drilldown, and audit UX.
5. `PXL_STANDARD_TRANSACTION_WORKSPACE.md` governs reusable transaction-workspace architecture across all PXL transaction types.
6. `PXL_TRANSACTION_EXPERIENCE_STANDARD.md` governs detailed implementation-level experience patterns, table behavior, auto-population, component contracts, maturity tracking, and rollout guidance.

Accounting and transaction matrices remain authoritative over all UX standards. This view standard defines presentation, interaction, field ownership, tab structure, role visibility, and view-mode experience only. It must not redefine accounting, tax, posting, lifecycle, or permission behavior.

If accounting, tax, master-data, lifecycle, or authoritative-source coverage is incomplete, the view must show a truthful unavailable or provisional state. It must not hide gaps through UI.

## 3. Relationship to the Sales Invoice Form UX Standard

The Sales Invoice Form UX Standard governs:

- `/sales-invoices/new`
- `/sales-invoices/:id/edit`
- Initial data entry
- Draft editing
- Auto-population
- Customer and item selection
- Line entry
- Live totals
- Draft GL preview
- Draft tax preview
- Readiness before submission or posting
- Controlled overrides
- Unsaved changes
- Form responsiveness

This Sales Invoice View UX Standard governs:

- `/sales-invoices/:id`
- Saved-invoice review
- Approval review
- Posted-document review
- Collection monitoring
- GL and tax truth
- Audit and lifecycle history
- Related-document trace
- Customer snapshot and current customer information
- Attachments and activity
- Void and reversal review
- Controlled downstream actions

Both standards use the same workspace language:

- Compact header
- Three-card information band
- Compact one-line tab system
- Shared table patterns
- Shared statuses
- Shared action hierarchy
- Shared component architecture

Information priority differs:

| Mode | Primary priority |
| --- | --- |
| Form mode | Entry, defaults, lines, validation, preview |
| View mode | Status, monetary position, accounting truth, tax truth, collection state, document trace, audit evidence |

## 4. Product Experience Objective

The Sales Invoice View must be one canonical document-of-record workspace. It must support review, approval, posting, collection monitoring, audit, and drilldown without scattering information across cards or forcing users to leave the invoice for basic truth checks.

The user should see the invoice's current state immediately, then drill into authoritative lines, financials, GL, tax, lifecycle, approval, audit, related documents, related party, attachments, activity, notes, and system metadata through predictable tabs.

## 5. Core View UX Principles

### One Canonical Document-Of-Record Page

An existing Sales Invoice has one canonical workspace:

`/sales-invoices/:id`

Do not create competing pages such as View Invoice, Open Invoice, Invoice Details, Accounting View, Audit View, or Read-Only View. Different roles may see different tabs and actions, but the document retains one canonical route and page architecture.

### View Is Not A Disabled Form

Do not render every editable input as a disabled text box. Saved and posted documents use clean read-only presentation:

- Labels and values
- Compact tables
- Status chips
- Links
- Totals
- Timeline or audit rows

Use input controls only when an action genuinely requires user entry.

### One Owner For Every Information Category

| Category | Detailed home |
| --- | --- |
| Document identity and current state | Header |
| Immediate invoice facts | Three information cards |
| Invoice lines | Lines |
| Complete financial detail | Financial |
| Accounting impact | GL Impact |
| Tax impact | Tax Impact |
| Readiness and integrity checks | Validation |
| Lifecycle | Workflow |
| Authorization | Approval |
| Change history | Audit |
| Document chain | Related Docs |
| Current customer profile | Related Party |
| Files | Attachments |
| Business/system events | Activity |
| Human notes | Notes |
| Technical metadata | System |

### Different-Level Context Is Allowed

Limited repetition is allowed only when level and purpose differ.

Examples:

- Header shows customer name and link only.
- Customer Information card shows invoice customer snapshot essentials.
- Related Party shows full current customer profile.
- Header shows Invoice Total, Collected, Balance Due.
- Financial tab shows full computation and collection detail.
- Header shows current posting, collection, and lock chips.
- Workflow and Approval show full lifecycle and authorization history.

### Table-First Presentation

Use professional tables for Lines, Financial, GL Impact, Tax Impact, Validation, Workflow, Approval, Audit, Related Docs, Related Party subsections, Attachments, Activity, Notes, and System metadata.

The top information band is the only permanent card-based area.

### No Permanent Right Sidebar

Do not use a permanent right rail containing Financial Summary, Customer Snapshot, Quick Actions, Validation, Audit Summary, Document Intelligence, or Transaction Health. These duplicate dedicated areas and reduce usable table width.

All document actions belong in the header toolbar.

### Truthful Unavailable States

Use:

- Not assigned
- Not configured
- Not applicable
- Not linked
- Not created
- Not yet posted
- Not recorded
- No approval workflow configured
- No attachments linked

Do not fabricate values or create decorative empty panels.

## 6. Current View Problems Identified

Current Sales Invoice review has useful foundations, including a routed saved-document page, header actions, lines, GL impact, tax impact, validation, workflow, approval, audit, related documents, related party, and system-oriented details.

Remaining view-standard risks to resolve during future implementation:

- The saved-document view and create/edit experience are not yet fully separated by canonical route behavior.
- View mode can inherit form-era assumptions unless the design explicitly avoids disabled-form presentation.
- Customer snapshot and current customer master facts must remain visibly distinct.
- Related Party must be structured and collapsible, not a large pile of cards.
- Workflow and Approval need separate responsibilities, while allowing an initial combined surface when workflow maturity is simple.
- System metadata must show only existing useful fields.
- Expected CWT and actual CWT/2307 evidence must remain distinct.
- GL and Tax Impact must distinguish preview from posted truth.
- Missing sources must be shown truthfully, not filled with invented values.

## 7. Canonical Route and View Model

Canonical route:

`/sales-invoices/:id`

The view route is review-oriented. Draft documents may offer an Edit action that opens the governed edit route or edit mode, but the canonical saved-document view remains the document-of-record surface.

Route rules:

- Existing invoices open through one canonical route.
- Posted, voided, reversed, and frozen invoices are read-only except for governed downstream actions.
- Deep links must work.
- Related document links open canonical workspaces.
- Do not create duplicate view routes for accounting, audit, or tax-only views.

## 8. Canonical Page Anatomy

Required hierarchy:

1. Route context or breadcrumb
2. Compact document header
3. Exactly three compact information cards
4. Compact one-line tab bar
5. Active tab content
6. Optional compact footer metadata

Active tab content uses one primary table or a small number of clearly structured table sections. Do not display several loosely related cards.

## 9. Header Standard

Required content:

- Document type: Sales Invoice
- Document number
- Posting status
- Collection status
- Lock status
- Customer name and canonical customer link
- Invoice Total
- Collected
- Balance Due
- Header toolbar

Recommended status chips:

Posting:

- Draft
- Submitted
- Approved
- Posted
- Voided
- Reversed
- Cancelled

Collection:

- Not Posted
- Open
- Partially Paid
- Paid
- Overpaid
- Written Off, only when supported

Lock:

- Editable
- Frozen
- Locked

The header must not permanently contain:

- Full workflow path
- Full approval history
- Created by
- Modified by
- Approved by
- Posted by
- Full customer identity
- Customer contact details
- Addresses
- Credit profile
- GL rows
- Tax rows
- Validation checklist
- Related-document chain
- Attachments
- Notes
- UUIDs
- Database IDs
- RPC names
- Engine versions

## 10. Toolbar and Action Hierarchy

The header toolbar is the only permanent source of document actions. Do not add a duplicate Quick Actions card.

Allow no more than three prominent actions plus `More`.

Actions must be:

- Status-aware
- Permission-aware
- Lifecycle-aware
- Lock-aware
- Idempotent where applicable
- Disabled with a reason when useful
- Confirmed when destructive

Recommended actions by state:

| State | Recommended actions |
| --- | --- |
| Draft | Edit, Submit for Approval or Post, Print Preview when supported, More |
| Submitted | Approve or Reject for authorized approvers, Return to Draft when governed, Print, More |
| Approved | Post, Return to Draft when governed, Print, More |
| Posted and Open | Create Receipt, Print, Email, More |
| Posted and Partially Paid | Create Receipt, Print, Email, More |
| Posted and Paid | Print, Email, More |
| Voided or Reversed | Open Reversal Journal, Print, More |

Possible `More` actions:

- Edit, only when editable
- Duplicate
- Create Credit Memo
- Create Debit Memo
- View Customer
- View Customer Ledger
- Open Journal Entry
- Open Full Accounting Trace
- Open Tax Ledger
- Void
- Reverse
- Cancel
- Export
- Generate E-Invoice, only when configured
- Download PDF
- View Print History
- View Email History

Destructive actions require confirmation, reason code when governed, explanation or memo when required, permission validation, and server-side enforcement.

Do not show normal Edit for posted, frozen, voided, or reversed invoices.

## 11. Three-Card Information Band

Use exactly three compact cards:

1. Document Information
2. Customer Information
3. Sales Context

The cards must be compact, aligned, and visually consistent. They must not become mini dashboards.

### Document Information

Purpose: show immediate invoice facts needed to understand the document.

Fields:

- Invoice Date
- Due Date
- Branch
- Currency
- Payment Terms
- Customer Reference
- External Reference
- Price Basis, when applicable

Optional fields only when relevant:

- Exchange Rate
- Tax Point Date
- Service Period
- Delivery Date
- Source Channel, only when governed

Do not include Customer lookup, Source Type, Document Series, Created By, Posted By, Journal Entry, Receipt links, UUID, or internal database ID. Number Series belongs in System unless it is a legitimate business-visible fact.

### Customer Information

Purpose: confirm the customer snapshot used by this invoice.

Fields:

- Customer Name
- Customer Code
- Registered Name, when different
- TIN
- TIN Branch Code
- VAT Classification
- Business Style, when relevant

Include a clear contextual label such as `Invoice Snapshot`.

The customer name links to the canonical Customer master page.

Do not display full contact details, all addresses, credit limit, current aging, recent transactions, recent payments, current available credit, customer group history, or full tax registration profile here. Those belong in Related Party.

### Sales Context

Purpose: show operational and reporting dimensions used by the invoice.

Fields when configured:

- Salesperson
- Project
- Department
- Cost Center
- Location
- Business Unit

Only display dimensions that exist and are applicable. Do not hardcode unsupported values. If a field was unassigned, show `Not assigned`.

Do not include customer profile data, source Sales Order, Delivery Receipt, receipts, payments, audit information, campaign, or opportunity unless a governed CRM integration exists. Source and downstream links belong in Related Docs.

## 12. Invoice Snapshot vs Current Customer Master

The view must explicitly distinguish Invoice Snapshot from Current Customer Master.

### Invoice Snapshot

Represents facts used by the invoice at the relevant transaction stage.

Possible fields:

- Customer registered name used
- Trade or business name used
- Customer code
- TIN used
- TIN branch code used
- VAT classification used
- Billing address used
- Delivery address used
- Payment terms used
- Currency used
- Price basis used
- Tax treatment used

The invoice snapshot controls:

- Historical invoice display
- Reprinting
- Customer-facing invoice output
- Audit evidence
- Tax support
- Future e-invoice payload reconstruction

A posted invoice must not silently change because the customer master was updated later.

### Current Customer Master

Represents the customer's current operational information.

Possible fields:

- Current customer status
- Current customer group
- Current contacts
- Current addresses
- Current credit limit
- Current outstanding AR
- Current available credit
- Current aging
- Current salesperson
- Current payment terms
- Current price level
- Recent transactions
- Recent payments

Current customer information belongs in Related Party.

Use visible labels where appropriate:

- Invoice Snapshot
- Current Customer Master

If the current data model does not preserve a required snapshot field, record it as a data-model gap. Do not pretend live master data is the historical transaction snapshot.

## 13. Lines Tab

Purpose: show the authoritative business lines of the invoice.

In draft view:

- Lines may be editable only through governed Edit mode.
- The normal `/sales-invoices/:id` route remains review-oriented.

In approved or posted view:

- Lines are read-only.
- No editable-looking disabled inputs.
- Use a professional table.

Default columns:

- `#`
- Item or Service
- Description
- Quantity
- UOM
- Warehouse, when applicable
- Unit Price
- Discount
- VAT Code
- VAT Rate
- Net Amount
- VAT Amount
- Gross Amount
- Department
- Project

Optional or hidden columns:

- Location
- Cost Center
- Business Unit
- Salesperson
- Revenue Account
- Inventory Account
- COGS Account
- Price Source
- Tax Source
- Posting Rule
- Source Document
- Source Line
- Remarks
- Created By
- Modified By
- Internal ID

Required table behavior:

- Sticky header
- Sticky totals
- Right-aligned amounts
- Tabular numbers
- Pinned identity columns
- Column resizing
- Column chooser
- Saved views
- Sorting
- Filtering
- Horizontal scroll
- Row expansion
- CSV export
- Compact density
- Clear empty states

Recommended saved views:

- Default
- Sales
- Accounting
- Tax
- Inventory
- Audit
- Custom

Line expansion may show pricing source, tax breakdown, account determination, dimensions, inventory allocation, serial or lot information, cost and margin when authoritative, posting rule, source document, line audit history, related documents, and remarks.

Do not display unsupported sections as empty decorative cards.

## 14. Financial Tab

Purpose: provide the full financial and collection interpretation of the invoice.

Use one structured table.

Recommended columns:

- Financial Component
- Basis or Explanation
- Amount

Possible rows:

- Gross Line Amount
- Line Discounts
- Header Discount
- Net Sales
- VATable Sales
- Zero-Rated Sales
- VAT-Exempt Sales
- Output VAT
- Other Charges
- Invoice Total
- Expected CWT
- Expected Net Collectible
- Amount Collected
- Payment Applications
- Credit Memo Applications
- Write-Offs, when supported
- Balance Due
- Rounding Difference
- Foreign Exchange Difference
- Revenue Recognized, when authoritative
- Deferred Revenue, when authoritative
- COGS, when authoritative
- Gross Margin, when authoritative

Do not fabricate COGS, margin, revenue recognition, deferred revenue, or FX difference. If data is unavailable, omit the row or show `Not available` only when useful.

The header metrics do not replace the Financial tab. The Financial tab must not simply repeat the three header amounts without supporting detail.

Provide drill actions where applicable:

- Collected opens Related Docs or payment applications.
- Output VAT opens Tax Impact.
- Journal-linked figures open GL Impact.
- Balance Due opens customer ledger or open applications.

## 15. GL Impact Tab

Purpose: provide the authoritative accounting truth of the invoice.

Use one primary table.

Top metadata strip:

- State: Posting Preview or Posted
- Posting Date
- Fiscal Period
- Branch
- Journal Entry link
- Balanced or Out-of-Balance status

Recommended columns:

- GL Account
- Account Name
- Description
- Debit
- Credit
- Source
- Posting Rule
- Branch
- Department
- Cost Center
- Project
- Journal Entry
- Status

Bottom totals:

- Total Debit
- Total Credit
- Difference

Rules:

- Draft values must be labeled `Posting Preview`.
- Posted values must come from the authoritative journal entry.
- Client-only calculations must never be treated as posted truth.
- Account codes link to account detail or ledger where supported.
- Journal number links to the canonical Journal Entry workspace.
- Do not display raw UUIDs as Branch values.
- Do not expose internal IDs in normal columns.
- Do not display vague technical text such as `document or module posting rule` when a business-facing explanation is available.
- Technical provenance belongs in expandable row detail or System.
- Balanced state must be factual and derived from authoritative data.

Possible expandable row detail:

- Account determination source
- Posting rule identifier
- Source line
- Tax source
- Configuration source
- Internal references
- Created-by-rule information

The primary table must remain readable to accountants and auditors.

## 16. Tax Impact Tab

Purpose: show the authoritative tax effect and compliance linkage of the invoice.

Use one clear table.

Top summary:

- VAT Classification
- Customer tax registration state
- Tax computation state
- Preview or Posted indicator
- Reconciliation state, when authoritative

Recommended columns:

- Tax Type
- Tax Code
- ATC
- Tax Base
- Rate
- Tax Amount
- Tax Treatment
- Ledger Status
- Return or Report
- Source Rule
- Related Certificate

Possible rows:

- Output VAT
- VATable Sales
- Zero-Rated Sales
- VAT-Exempt Sales
- Expected CWT
- Actual CWT Recognized
- Adjustments
- Reversals

Required terminology:

- Expected CWT
- Expected Net Collectible
- Actual CWT Recognized
- 2307 Status

Include this explanatory note when Expected CWT is shown:

> Expected CWT is an estimate based on the customer profile, applicable ATC, and authoritative invoice tax base. Actual CWT is recognized through the applicable receipt, payment application, or certificate workflow according to governed accounting and tax rules.

Rules:

- Do not imply the invoice itself finalizes actual CWT.
- Actual CWT links to receipt, payment application, or certificate source.
- Expected CWT is informational unless governed accounting rules state otherwise.
- Posted tax rows come from authoritative tax-detail or ledger records.
- Draft values are labeled as preview.
- Current customer tax profile belongs in Related Party.
- Transaction-specific tax effect belongs here.
- If authoritative expected CWT logic is unavailable, show a truthful unavailable or provisional state.

## 17. Validation Tab

Purpose: show the integrity and readiness state of the saved document.

Use two levels.

Level 1: compact readiness indicator in the header area or near actions:

- Ready to Approve
- Ready to Post
- Posted Successfully
- 2 Warnings
- 3 Integrity Issues

Clicking the compact indicator opens the Validation tab. Do not create a permanent Validation sidebar.

Level 2: full validation table.

Columns:

- Validation
- Status
- Message
- Resolution
- Source

Possible statuses:

- Passed
- Warning
- Blocked
- Informational
- Not Applicable

Possible checks:

- Customer exists and is active
- Customer snapshot complete
- Invoice date valid
- Fiscal period valid
- Branch active
- Number series valid
- Lines present
- Quantities valid
- Prices valid
- Tax codes valid
- Posting accounts determined
- Required dimensions assigned
- Inventory availability valid, when applicable
- Document balanced
- Approval requirements satisfied
- User action permitted
- GL posting complete
- Tax posting complete
- Collection state consistent
- Related journal exists for posted invoice
- Posted document is frozen
- Reversal or void state consistent

The validation view must mirror server-side truth.

## 18. Workflow

Purpose: show document lifecycle.

Use a compact table or disciplined timeline.

Columns:

- Step
- Status
- User
- Role
- Date and Time
- Remarks

Possible stages:

- Draft
- Submitted
- Approved
- Posted
- Partially Paid
- Paid
- Voided
- Reversed
- Cancelled

The header shows current state only. Complete lifecycle belongs here. Do not fabricate actors or timestamps that are not stored.

## 19. Approval

Purpose: show authorization requirements and approval evidence.

Columns:

- Approval Level
- Approver
- Role
- Required Action
- Status
- Date and Time
- Remarks
- Delegation, when supported

Possible statuses:

- Not Required
- Pending
- Approved
- Rejected
- Returned for Revision
- Delegated
- Cancelled

When no approval workflow exists, show:

`No approval workflow is configured for this transaction.`

If current PXL approval is only single-step, Workflow and Approval may render as one combined `Workflow & Approval` tab. Keep responsibilities logically separable for future multi-step approval.

## 20. Audit

Purpose: provide chronological, immutable evidence trail.

Use one table.

Columns:

- Date and Time
- User
- Action
- Field or Entity
- Old Value
- New Value
- Reason
- Source
- Device or IP, when stored and appropriate

Possible events:

- Created
- Saved
- Customer Changed
- Line Added
- Line Edited
- Line Removed
- Price Overridden
- Tax Overridden
- Account Overridden
- Submitted
- Approved
- Rejected
- Returned to Draft
- Posted
- Printed
- Emailed
- Receipt Applied
- Credit Memo Applied
- Voided
- Reversed
- Restored

Rules:

- Do not repeat audit history in the header.
- Do not place created, modified, approved, or posted metadata permanently in information cards.
- Audit records must come from authoritative audit sources.
- Audit evidence must remain immutable where required.
- If old and new values are unavailable, do not fabricate them.

## 21. Related Documents

Purpose: show the complete upstream and downstream transaction chain.

Use one authoritative relationship table.

Columns:

- Relationship
- Document Type
- Document Number
- Date
- Status
- Amount
- Applied Amount
- Open Balance
- Direction
- Action

Potential upstream relationships:

- Quotation
- Sales Order
- Delivery Receipt
- Contract
- Customer Purchase Order

Potential downstream relationships:

- Official Receipt
- Customer Payment
- Credit Memo
- Debit Memo
- Customer Return
- Deposit
- Journal Entry
- Reversal Journal
- Tax Certificate
- 2307
- E-Invoice
- Compliance Report or Snapshot

Rules:

- Every existing document number is clickable.
- Links open canonical workspaces.
- Do not open competing read-only pages.
- Show expected but missing stages truthfully: `Not linked`, `Not created`, or `Not applicable`.
- Do not hide missing expected stages silently.
- Related journal entries are visible.
- Payment applications are visible.
- Credit and debit applications are visible.
- Reversal links are visible.
- A graphical chain may be added only as supplemental secondary view.
- The table remains authoritative.

## 22. Related Party

Purpose: show current customer profile relevant to collections, credit, tax review, and customer service.

The Related Party tab must not become another scattered dashboard.

Use compact collapsible sections or internal sub-navigation.

Recommended sections:

1. Summary
2. Tax and Registration
3. Credit and Aging
4. Contacts and Addresses
5. Recent Transactions
6. Recent Payments

Default expanded:

- Summary
- Credit and Aging

Default collapsed:

- Contacts and Addresses
- Recent Transactions
- Recent Payments

Tax and Registration may default open for accountant, tax, and auditor roles.

Summary uses a two-column field table:

- Customer Name
- Customer Code
- Current Status
- Customer Group
- Default Terms
- Salesperson
- Price Level

Tax and Registration uses a two-column field table:

- Current TIN
- Current TIN Branch Code
- Current VAT Classification
- Current Withholding Status
- Default ATC
- Registration Status

Credit and Aging:

- Credit Limit
- Outstanding AR
- Available Credit
- Overdue Amount
- Last Payment
- Average Collection Days
- Oldest Open Invoice

Aging table:

- Current
- 1-30 Days
- 31-60 Days
- 61-90 Days
- Over 90 Days

Contacts table:

- Contact Type
- Name
- Email
- Telephone
- Mobile

Addresses table:

- Address Type
- Complete Address
- Status

Recent Transactions columns:

- Date
- Document
- Amount
- Status
- Balance
- Action

Recent Payments columns:

- Date
- Receipt
- Amount
- Applied
- Unapplied
- Action

Rules:

- Customer name links to Customer master.
- Normal invoice view must not allow uncontrolled customer-master editing.
- Live customer information and invoice snapshot remain distinguishable.
- Use tables and collapsible sections, not many floating cards.
- Credit and aging figures come from authoritative AR sources.
- Do not display incorrect negative available credit caused by bad application or paid-invoice logic.

## 23. Attachments

Use one table.

Columns:

- File Name
- Document Type
- Description
- Uploaded By
- Upload Date
- File Size
- OCR Status
- Preview
- Download

Possible attachment types:

- Customer Purchase Order
- Contract
- Delivery Receipt
- Signed Invoice
- Tax Document
- Supporting Schedule
- Email
- Other

Empty state:

`No attachments are linked to this invoice.`

Do not pretend OCR, preview, download, or storage functionality exists when it is not configured.

## 24. Activity

Purpose: show operational and communication events. Activity is not a duplicate of Audit.

Use a compact table or timeline.

Columns:

- Date and Time
- Event Type
- User or System
- Description
- Related Record
- Action

Possible events:

- Invoice emailed
- Reminder sent
- Customer contacted
- Collection follow-up recorded
- Comment added
- Approval requested
- Payment confirmed
- Integration completed
- API event received
- Print generated

Use Audit for immutable evidence. Use Activity for business and operational context.

## 25. Notes

Use a structured notes table or thread.

Columns:

- Date and Time
- User
- Category
- Visibility
- Note
- Action

Possible categories:

- Internal
- Customer-Facing
- Accounting
- Collection
- Tax
- Approval

Clearly separate customer-facing notes from internal notes. Internal notes must never appear on customer-facing printed output. Do not display a large empty rich-text editor in normal read-only view.

## 26. System

Purpose: show useful technical and data-lineage information only.

Possible fields when they already exist:

- Document UUID
- Database ID
- Source Module
- Source Type
- Number Series
- Authoritative RPC or Process
- Journal Reference
- Integration Reference
- Created Timestamp
- Updated Timestamp
- Internal References
- Document Hash
- Posting Engine Version
- Tax Engine Version
- Migration or Schema Version

Required rule:

> System fields are displayed only when they already exist and provide real operational, support, audit, integration, or troubleshooting value. This UX standard does not require new technical metadata fields or storage merely to populate the System tab.

Do not place normal business actions here. Do not show meaningless implementation details to ordinary users. Allow role-based visibility when appropriate.

## 27. Draft, Submitted, Approved, Posted, Partially Paid, Paid, Voided, and Reversed View Behavior

### Draft View

Draft view is review-oriented. It may expose Edit as a governed action, but it should not render as a disabled form.

### Submitted View

Submitted view emphasizes approval readiness, submitted status, validation, workflow, approval requirements, and restricted actions.

### Approved View

Approved view emphasizes posting readiness, approval evidence, GL/tax preview, and Post action for authorized users.

### Posted View

Posted view emphasizes authoritative GL, tax records, immutable lines, collection state, related documents, audit trail, and downstream actions.

### Partially Paid View

Partially paid view emphasizes remaining balance, applied receipts, actual CWT recognized where applicable, related payment applications, and Create Receipt where permitted.

### Paid View

Paid view emphasizes closed balance, full collection evidence, related receipts, audit trail, and print/email history where available.

### Voided Or Reversed View

A voided or reversed Sales Invoice remains visible as a historical document. Do not delete or silently transform it.

Header shows:

- Voided or Reversed status
- Lock status
- Collection state
- Original Invoice Total
- Remaining or adjusted balance, when applicable

State summary shows:

- Reason
- User
- Date and time
- Reversal journal
- Replacement document, when applicable
- Related credit memo or corrective transaction, when applicable

The original document remains read-only.

Related Docs exposes original journal, reversal journal, replacement invoice, credit memo, receipt reversals, and tax reversals when authoritative links exist.

GL Impact shows authoritative reversal relationships. Tax Impact shows authoritative tax reversal rows when supported. Audit shows the void or reversal event and reason.

## 28. Role-Based View Experience

| Role | View experience |
| --- | --- |
| Encoder | Read-only business details, lines, basic financial status, basic workflow, related documents, permitted notes |
| Accountant | Full financial detail, GL Impact, Tax Impact, Validation, accounting trace, posting and reversal actions where permitted |
| Approver | Financial, GL preview, tax preview, Validation, Workflow and Approval, Attachments, audit evidence relevant to approval |
| Collections User | Collection status, Balance Due, related receipts/payments, customer credit and aging, Activity/Notes, Create Receipt where permitted |
| Tax User | Tax Impact, customer tax profile, tax ledger links, expected versus actual CWT, 2307 status, compliance report links |
| Auditor | Read-only full document, GL Impact, Tax Impact, Validation, Workflow, Approval, Audit, Related Docs, Attachments, System trace, snapshot evidence |
| Administrator or Support | Setup diagnostics, System metadata, integration trace, controlled actions based on permission |

Role-based visibility is for usability only. Server permissions remain authoritative.

## 29. Visual Design Rules

The Sales Invoice View must feel professional, calm, dense, precise, enterprise-grade, accounting-focused, and audit-ready.

Use:

- Small border radius
- Thin neutral borders
- White content surfaces
- Very subtle company-accent tint
- Compact uppercase table headers
- Right-aligned amounts
- Tabular numbers
- Consistent row heights
- Sticky table headers
- Subtle totals rows
- Clear status chips
- Color only for state, warning, error, success, and interaction

Avoid:

- Consumer dashboard styling
- Decorative widgets
- Excessive cards
- Large rounded panels
- Heavy shadows
- Oversized headings
- Neon colors
- Unnecessary icons
- Marketing-style visuals
- Large blank panels
- Repeated summaries
- Permanent right sidebar
- Disabled form fields as the primary read-only design

## 30. Responsive and Accessibility Rules

Desktop is the primary accounting workspace.

On narrower screens:

- Header sections may stack compactly.
- The three information cards may collapse to fewer columns.
- Tables scroll horizontally.
- Pinned identity columns remain visible where practical.
- Tabs remain on one line where practical.
- Labels truncate before wrapping excessively.
- Complex accounting tables must not become unreadable card lists.

Accessibility requirements:

- Status must not rely on color alone.
- Tabs expose selected state.
- Expandable rows expose expanded state.
- Icon-only actions have accessible labels.
- Links are identifiable.
- Disabled actions explain why when useful.
- Monetary values use consistent formatting.
- Dates use company-locale formatting.
- Keyboard navigation remains usable.
- Focus states remain visible.
- Empty states are concise and professional.

## 31. Performance and Reliability Targets

Practical UX targets:

- Opening a saved invoice does not require several full-page reloads.
- Tab changes do not reload the entire document unnecessarily.
- Header, lines, and essential facts load first.
- Secondary tabs may load on demand when appropriate.
- Customer and related-document links respond quickly.
- Large line grids remain usable.
- Repeated action clicks do not create duplicate receipts, emails, posts, or reversals.
- Action progress is visible.
- Failed downstream actions do not corrupt the document view.
- Refreshing the page preserves the canonical document route.
- Deep links to the invoice work.
- Permission failures show a user-friendly explanation.
- Network errors do not display raw database or RPC messages to normal users.

Suggested product targets under normal conditions:

- Essential invoice view becomes usable quickly without waiting for every secondary tab.
- Tab switching feels immediate when data is already loaded.
- Lines table remains usable with at least 100 lines.
- Header actions prevent duplicate submission.
- Related-document links open canonical routes.
- Failed print, email, receipt, void, or reverse actions leave invoice state unchanged unless server confirms success.

Treat these as UX targets, not formal infrastructure service-level agreements unless adopted separately.

## 32. Existing Reusable Component Alignment

Do not create a competing component architecture.

Use and extend existing PXL shared transaction components where available:

- `DocumentLayout`
- `PrimaryInformationPanel`
- `LineGrid`
- `LineDetailPanel`
- `FinancialSummaryPanel`
- `PostingValidationPanel`
- `GLImpactPanel`
- `TaxImpactPanel`
- `RelatedDocumentsTab`
- `WorkflowStrip`
- Shared audit components
- Shared ERP table primitives
- Shared status badges
- Shared amount and date cells

New shared components may be documented only when the responsibility does not already exist.

Possible missing shared components:

- Related Party structured profile
- Attachments table
- Activity feed or table
- Notes thread
- System metadata table
- Snapshot-versus-current indicator
- Collection application table

Do not rename existing components casually. Any rename requires a deliberate architecture decision and migration plan.

## 33. Missing Data, Rules, and Authoritative Sources

| Required capability | Intended authoritative source | Current availability if known | UX behavior until available |
| --- | --- | --- | --- |
| Customer invoice-snapshot fields | `sales_invoices` snapshot columns or governed document snapshot source | Partial: name, TIN, address, terms/currency exist; full snapshot coverage must be confirmed | Label existing snapshot facts; mark missing snapshot facts as data-model gaps |
| Authoritative collection status | Posted receipt/payment applications and credit/write-off applications | Partial via receipt lines and posted receipts | Show only computed status from authoritative applications; otherwise `Not available` |
| Receipt and payment applications | Receipt headers/lines and application tables | Present for invoice-applied receipts | Link to receipts where available; show `Not linked` when none |
| Credit memo applications | Credit Memo application source | Must be confirmed | Show `Not linked` or `Not available` until authoritative |
| Outstanding balance | AR application ledger or governed aging/as-of RPC | AR aging/reconciliation RPCs exist; exact SI view source must be confirmed | Use governed source only; avoid ad hoc paid-invoice logic |
| Current customer credit and aging | Customer master plus AR aging/as-of RPCs | AR aging source exists; credit computation must be confirmed | Show values only from authoritative source |
| Posted journal source | Journal entries linked by source type/id | Present | Posted GL uses linked JE only |
| Tax-detail source | `tax_detail_entries` or governed tax ledger | Present for governed tax rows; coverage must be confirmed per row | Posted Tax Impact uses authoritative tax rows only |
| Expected CWT source | Customer profile, ATC, authoritative invoice tax base | Expected CWT flow exists; view source must be confirmed | Label as Expected CWT; mark provisional if source incomplete |
| Actual CWT and 2307 source | Receipt/payment/certificate workflow and 2307 records | Receipt CWT and 2307 lifecycle exists; exact view joins must be confirmed | Link actual CWT to receipt/certificate source only |
| Workflow and approval source | Status fields, approval instances, transaction events | Partial depending on workflow maturity | Show compact empty state when no workflow configured |
| Audit-log source | `sys_audit_logs` and transaction events | Present | Show authoritative audit rows; no fabricated old/new values |
| Related-document graph source | Source IDs, application rows, JE links, report snapshots | Partial; source relationships vary by document | Show known links and truthful missing states |
| Attachment storage source | Governed storage/attachment tables | Not broadly configured | Show `No attachments are linked to this invoice.` |
| Activity-stream source | `transaction_events`, email/API/notification logs | Transaction events exist; activity sources vary | Show only available operational events |
| Notes persistence source | Existing notes/memo or future notes table | Memo exists; threaded notes must be confirmed | Show existing memo or `Not recorded` |
| Void and reversal relationship source | Void/reversal RPC outputs, JE reversal links, reason codes | Void reason and reversal links exist in some flows | Show only authoritative reversal relationships |
| Print and email history source | Print/email event records | Must be confirmed | Show `Not recorded` until source exists |
| E-invoice provider and status source | Configured provider/status records | Not configured | Show `Not configured` |
| System metadata fields | Existing IDs, timestamps, series, process metadata | Partial | Show only existing useful fields |

Do not add fields solely to satisfy the visual design.

## 34. Acceptance Checklist

The Sales Invoice View UX standard is successful when:

1. Existing invoices open through one canonical route.
2. The view is not presented as a disabled form.
3. The header clearly shows document number, status, customer, invoice total, collected amount, and balance due.
4. The header contains no full audit, GL, tax, customer, or related-document detail.
5. There is no permanent right sidebar.
6. Header actions are the only permanent action source.
7. Exactly three compact information cards are used.
8. The Customer Information card displays invoice snapshot essentials.
9. The Related Party tab displays current customer-master information.
10. Invoice Snapshot and Current Customer Master are visibly distinguishable.
11. Posted invoice presentation does not change silently when customer master data changes.
12. Lines are displayed through the standard enterprise table.
13. Financial detail does not duplicate the header without adding explanation.
14. Posted GL Impact comes from the authoritative journal entry.
15. Draft GL Impact is labeled as preview.
16. Posted Tax Impact comes from authoritative tax records.
17. Expected CWT and Actual CWT are clearly distinguished.
18. Validation has both a compact readiness indicator and a full table.
19. Workflow and Approval have clear separate responsibilities.
20. Workflow and Approval may combine temporarily when workflow is simple.
21. Audit is chronological and authoritative.
22. Related Documents uses a professional relationship table.
23. All linked document numbers open canonical workspaces.
24. Missing expected document relationships are shown truthfully.
25. Related Party uses collapsible structured sections rather than scattered cards.
26. Attachments, Activity, Notes, and System use consistent tables or structured sections.
27. System does not require new technical fields merely for display.
28. Posted, voided, and reversed documents remain read-only.
29. Reversal and corrective relationships are visible.
30. Role-based visibility does not replace server-side permission enforcement.
31. Existing shared PXL components are reused and extended.
32. The form and view standards do not contradict each other.
33. The general transaction standards correctly summarize both pilot standards.
34. The Sales Invoice view can serve as the pilot for future transaction views.
35. No accounting, tax, or lifecycle rule is invented by UX documentation.

## 35. Rollout Rules for Future Transaction Views

Future transaction views must inherit this view architecture:

- One canonical saved-document route.
- Clean read-only presentation, not disabled forms.
- Compact header with identity, status, metrics, and actions.
- Exactly three compact information cards.
- One-line tab system with single-responsibility tabs.
- Table-first structured detail.
- No permanent right sidebar.
- Header toolbar as the only permanent action source.
- Snapshot versus current master distinction where a counterparty or governed entity can change over time.
- Preview versus posted truth distinction for accounting and tax.
- Related-document relationship table as the authoritative chain.
- Audit as the chronological evidence surface.
- System metadata only when existing and useful.
- Existing PXL shared transaction components reused before new components are proposed.

Transaction-specific differences are allowed for business-specific fields, line types, actions, statuses, validations, and related-document relationships. They must not change the shared workspace language without a deliberate architecture decision.
