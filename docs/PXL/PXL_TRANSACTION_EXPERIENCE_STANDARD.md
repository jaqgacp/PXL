# PXL Transaction Experience Standard

Status: DESIGN BLUEPRINT subordinate to `PXL_STANDARD_TRANSACTION_WORKSPACE.md`, the governed accounting/transaction matrices, and the approved Sales Invoice pilot standards. This file carries implementation-level detail: route/mode behavior, tab specs, line-grid patterns, auto-population rules, view data sourcing, component contracts, maturity tracking, and rollout guidance. Nothing here implements code, changes schema, changes posting/tax/accounting behavior, or requires a page change until scheduled.

Active sequencing gate: `PXL_ACCOUNTING_CORE_READINESS.md` (DEC-017). Transaction-experience rollout remains reference-only during accounting-core hardening unless a task explicitly targets UX standardization.

Rollout framework: future transaction workspace implementations must start from `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`, `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`, `PXL_TRANSACTION_DEFINITION_SCHEMA.md`, and `src/lib/transactionWorkspaceRollout.ts`. The Sales Invoice create/edit workspace and Sales Invoice read-only view are the approved structural references; other documents inherit the shell and components, not Sales Invoice-specific business content.

Completeness gate: the Sales Invoice reference pair is governed by the Sales Invoice functional, field, dimension, GL, posting, and tax mappings. A future transaction rollout must copy the source-backed pattern, not unresolved Sales Invoice gaps.

## 1. Purpose and Normative Status

Every accounting document in PXL must eventually expose enough accounting, tax, audit, workflow, and operational information to satisfy accountants, approvers, collections users, tax reviewers, support teams, and auditors while remaining capturable by non-accountants.

This document defines implementation-level experience patterns for future transaction workspaces. It does not replace the Sales Invoice pilot standards.

Precedence when documents disagree:

1. `PXL_ACCOUNTING_RULES_MATRIX.md` governs posting behavior, account determination, tax impact, reversal/void/cancel, report impact, and test expectations.
2. `PXL_TRANSACTION_MATRIX.md` governs lifecycle, source relationships, statuses, applications, posting behavior, and document data contracts.
3. `PXL_SALES_INVOICE_UX_STANDARD.md` governs Sales Invoice create and draft-edit UX.
4. `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md` governs Sales Invoice saved-document view, approval, posted, collection, audit, void, and reversal UX.
5. `PXL_STANDARD_TRANSACTION_WORKSPACE.md` governs reusable transaction-workspace architecture.
6. `PXL_TRANSACTION_WORKSPACE_MANIFEST.md` and `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md` govern rollout selection, implementation workflow, validation, and status updates.
7. `PXL_TRANSACTION_DEFINITION_SCHEMA.md` and `src/lib/transactionWorkspaceRollout.ts` define the typed transaction-definition model.
8. This document governs detailed implementation-level experience patterns and maturity tracking.
9. `UI_UX_PRINCIPLES.md` defines broad visual/interaction principles.
10. `PXL_PRODUCT_BACKLOG.md` holds feature-level rollout planning.

When the Sales Invoice pilot standards conflict with older implementation guidance in this document, the approved Sales Invoice pilot standards govern. This document must be updated rather than interpreted as an exception.

## 2. Relationship To The Sales Invoice Pilot Pair

PXL has two canonical Sales Invoice pilot standards:

| Pilot standard | Governs |
| --- | --- |
| `PXL_SALES_INVOICE_UX_STANDARD.md` | `/sales-invoices/new`, `/sales-invoices/:id/edit`, capture, defaults, line entry, live totals, previews, readiness, controlled overrides, unsaved changes |
| `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md` | `/sales-invoices/:id`, saved-document review, approval review, posted view, collection monitoring, GL/tax truth, traceability, audit, void/reversal review, downstream actions |

Both modes share:

- Compact document header
- Three-card information band
- Compact one-line tab system
- Shared table patterns
- Shared status vocabulary
- Header-only action hierarchy
- Existing PXL component architecture
- No permanent right sidebar
- Truthful unavailable states
- Source-backed field presentation

Mode priority differs:

| Mode | Prioritizes |
| --- | --- |
| Create/Edit | Capture, defaults, auto-population, line entry, controlled overrides, compact live summary, preview, readiness |
| View/Review | Status, monetary position, posted truth, collection state, document trace, lifecycle, approval, audit evidence |

## 3. Route And Mode Model

Target route model:

| Route | Mode |
| --- | --- |
| `/module/documents` | Register/list |
| `/module/documents/new` | Create form |
| `/module/documents/:id` | Saved-document view |
| `/module/documents/:id/edit` | Draft edit form |

Rules:

- Existing documents have one canonical saved-document route.
- Do not create separate View/Open/Details/Accounting/Audit pages for the same document.
- Create/edit and view modes share the same workspace language and component architecture.
- View mode is not a disabled form.
- Posted, voided, reversed, frozen, or locked documents remain read-only except for governed downstream actions.
- Route behavior must never bypass server permissions or lifecycle rules.

## 4. Shared Workspace Shell

Every transaction workspace uses this anatomy:

1. Breadcrumb or route context
2. Compact document header
3. Exactly three compact information cards
4. Compact one-line tab bar
5. Active tab content
6. Optional compact footer metadata

Header owns:

- Document type and number
- Current status chips
- Counterparty link when applicable
- Primary monetary metrics
- Header toolbar
- Optional compact readiness indicator

Header and tab coloring is system-wide:

- Sales workspaces use a light blue tint.
- Purchase workspaces use a light green tint.
- Journal workspaces use a light amber tint.
- Inventory workspaces use a light purple tint.
- Banking and payment workspaces use a light teal tint.

The tint must be subtle, professional, and consistent with `PXL_STANDARD_TRANSACTION_WORKSPACE.md`. Use the color family to establish workspace hierarchy, not to indicate business status.

PXL Transaction Workspace Design System v1 is the shared visual baseline. The Sales Invoice Transaction Workspace is the reference implementation for reusable transaction tokens, typography, colors, cards, buttons, tabs, tables, forms, empty states, loading states, dialogs, and future collapsible panels. New transaction families must inherit the design system rather than creating page-specific styling.

Three-card band owns:

1. Document Information
2. Party Information
3. Transaction Context

Tabs own detailed structured data:

- Lines
- Financial
- GL Impact
- Tax Impact
- Validation
- Workflow
- Approval
- Audit
- Related Docs
- Related Party
- Attachments
- Activity
- Notes
- System

No permanent right rail or Quick Actions card is allowed.

## 5. Create/Edit Experience

Create/Edit mode is a form experience, but it should still feel like an intelligent ERP transaction workspace.

Create/Edit priorities:

- Capture only user-entered business facts.
- Derive, default, compute, or retrieve everything else.
- Keep the line grid visually dominant.
- Show one compact live summary, not a financial dashboard.
- Show draft GL/tax preview only as preview.
- Show a compact readiness indicator near primary actions.
- Preserve unsaved changes.
- Prevent duplicate saves/posts.
- Respect controlled overrides and provenance.
- Use enterprise lookup controls for master-data selection.

Normal Sales Invoice target:

- No more than five intentional header-level inputs for standard invoices.
- Fifteen header-level inputs is the maximum complexity guardrail, not the target.

Create/Edit must never silently overwrite user-entered or sourced line values when a master-derived field changes.

## 6. View/Review Experience

View mode is the document-of-record experience.

View/Review priorities:

- Identify the document and current state immediately.
- Show Invoice/Bill/Receipt total, collected/paid/applied amount, and balance or difference.
- Present read-only facts as labels, values, links, tables, status chips, timelines, and totals.
- Use authoritative posted journal data for posted GL.
- Use authoritative tax-detail or tax-ledger data for posted tax impact.
- Show document trace through Related Docs.
- Show immutable evidence through Audit.
- Keep current master profile separate from transaction snapshot.
- Keep technical metadata in System only when existing and useful.

Do not render view mode as a page of disabled text boxes.

## 7. Tab Responsibilities

| Tab | Responsibility | Form mode | View mode |
| --- | --- | --- | --- |
| Lines | Business lines or application rows | Editable grid when allowed | Authoritative read-only table |
| Financial | Complete financial and collection/payment detail | Preview where unsaved; server values after save | Authoritative detail and applications |
| GL Impact | Accounting preview or posted journal | Clearly labeled preview | Authoritative posted JE when posted |
| Tax Impact | Tax preview or tax ledger/detail | Clearly labeled preview | Authoritative tax records when posted |
| Validation | Readiness and integrity | Compact indicator plus full table | Compact state plus integrity table |
| Workflow | Lifecycle | Expected or current lifecycle | Actual lifecycle history |
| Approval | Authorization | Expected/current approval requirement | Approval evidence |
| Audit | Change evidence | Draft events if available | Chronological authoritative evidence |
| Related Docs | Source/downstream chain | Selected source docs | Complete relationship table |
| Related Party | Current master profile | Available after party selection | Current master profile, separate from snapshot |
| Attachments | Supporting files | Usable when supported | Evidence table |
| Activity | Business/system events | Operational events | Operational events, not audit duplicate |
| Notes | Human notes | Structured notes when supported | Structured notes/read-only where locked |
| System | Technical metadata | Minimal | Useful existing technical metadata |

Workflow and Approval may be combined as `Workflow & Approval` during simple workflow maturity, but lifecycle and authorization responsibilities must remain logically separable.

## 8. Line Grid Standard

The line grid has two related but distinct states.

Editable form grid:

- Fast item/service lookup
- Keyboard navigation
- Copy/paste where supported
- Batch insertion/import where supported
- Cell and row validation
- Controlled overrides with provenance
- Live calculations
- Unsaved-change preservation

Item/service lookup must show full item code and description, UOM where available, future available quantity only when authoritative, and a scrollable dropdown that is not clipped by parent containers.

Read-only view grid:

- Clean authoritative table
- No disabled-form styling
- Sticky header
- Sticky totals where applicable
- Pinned identity columns
- Column chooser
- Saved views
- Sorting/filtering
- Horizontal scroll
- Row expansion
- CSV export
- Compact density

Standard saved views:

- Default
- Sales
- Accounting
- Tax
- Inventory
- Audit
- Custom

Common line detail sections:

- Pricing source
- Tax breakdown
- Account determination
- Dimensions
- Inventory allocation
- Serial or lot information
- Cost and margin when authoritative
- Posting rule
- Source document
- Line audit history
- Related documents
- Remarks

Do not display unsupported sections as empty decorative panels.

## 9. Auto-Population And Customer-Change Policy

Auto-population applies mainly to form mode.

Principle:

> The user enters a fact once; everything derivable is derived visibly from authoritative sources.

Typical sources:

| Source | Populates |
| --- | --- |
| Company context | Company, active branch, currency, default date, open-period checks |
| Customer | Snapshot identity, terms, tax type, withholding flag, default ATC, AR account/defaults, addresses where governed |
| Supplier | Snapshot identity, terms, tax type, withholding flag/default ATC, AP/defaults |
| Item or Service | Description, UOM, price, VAT code, account, item type, inventory defaults |
| Applied document | Balance, application amount, withholding base, source relationship |
| Accounting config | Control accounts and posting defaults |
| Number series | Document number at save/reservation through governed process |
| Compliance profile | Which tax fields/tabs are applicable |

Lookup controls:

- Customer, Supplier, Item, Employee, Project, Cost Center, Location, and GL Account selectors use the same enterprise lookup behavior.
- Clicking inside the field or dropdown icon opens the list.
- Typing filters in real time.
- Arrow keys navigate.
- Enter selects.
- Escape closes.
- Dropdowns must render above surrounding containers and must not be clipped by grid or card overflow.
- Recent selections may be added later without changing the contract.

Customer and party TIN display:

- Full TIN values display as `XXX-XXX-XXX-XXXXX`.
- The first 9 digits are the taxpayer number.
- `TIN Branch`, when shown separately, is exactly 5 digits.
- Do not display or persist 3-digit or 4-digit branch identifiers.
- Follow `PXL_PHILIPPINE_TIN_STANDARD.md` for UI, search, storage, import/export, API, reporting, and future BIR modules.

Customer or party change after lines exist must use controlled refresh options:

1. Refresh terms and customer defaults only.
2. Refresh pricing and tax on all eligible lines.
3. Refresh only lines without manual overrides.
4. Keep all current line values.
5. Cancel customer change.

Do not silently replace manually entered prices, approved discounts, manual tax overrides, account overrides, user-entered descriptions, or existing source-document values.

Preserve provenance for price source, tax source, account source, dimension source, and manual overrides.

## 9.1 Optional Source Conversion Pattern

Create/Edit mode must allow standalone transaction entry.

When a selected party has open source documents, the form may offer a compact optional prompt with source document number, date, remaining amount, status, and action.

Supported source documents include:

- Quotation
- Sales Order
- Purchase Order
- Vendor Bill
- Delivery Receipt
- Service Order, future

Users must be able to continue with an empty transaction or convert from a source document. Never force chaining.

## 10. View-Mode Data Sourcing

View mode uses authoritative saved sources, not form defaults.

| View data | Source expectation |
| --- | --- |
| Transaction snapshot | Saved document snapshot columns or governed snapshot source |
| Current master profile | Customer/supplier/party master and governed AR/AP/credit/aging sources |
| Posted GL | Linked journal entries and posting trace |
| Draft GL | Governed preview source, clearly labeled preview |
| Posted tax | Tax detail entries or governed tax ledger |
| Expected CWT | Customer profile, ATC, and authoritative invoice tax base; informational |
| Actual CWT | Receipt/payment/certificate workflow |
| Collections/payments | Application rows and posted receipt/payment headers |
| Credit/debit applications | Governed application rows |
| Workflow | Status fields, approval instances, transaction events |
| Audit | `sys_audit_logs`, lifecycle stamps, transaction events where applicable |
| Related docs | Source IDs, application links, JE links, report snapshots |
| Attachments | Governed attachment storage |
| Activity | Transaction events, email/API/notification logs |
| Notes | Document memo or note entities |
| System | Existing useful technical metadata |

If a source is unavailable, show `Not configured`, `Not recorded`, `Not available`, `Not linked`, `Planned`, or `Requires authoritative source`.

## 11. Financial Summary And Financial Tab

Form mode has one compact live summary near or below the line grid.

Allowed live-summary rows:

- Subtotal
- Discount
- VAT
- Other Charges
- Invoice Total
- Expected CWT, when applicable
- Expected Net Collectible

View mode uses the Financial tab for full interpretation.

Financial tab rows may include:

- Gross line amount
- Discounts
- Net sales or net amount
- VATable/zero-rated/exempt splits
- Output/Input VAT
- Other charges
- Total
- Expected withholding
- Expected net collectible/payable
- Amount collected/paid/applied
- Payment applications
- Credit/debit applications
- Balance due
- Rounding or FX differences when authoritative
- Revenue recognition, deferred revenue, COGS, or margin only when authoritative

Do not fabricate profitability, costing, revenue-recognition, or FX values.

## 11.1 VAT Price Basis

VAT Price Basis is a reusable transaction component.

Supported values:

- VAT Exclusive
- VAT Inclusive

Future transactions must use the same behavior when applicable:

- Quotation
- Sales Order
- Purchase Order
- Vendor Bill
- Purchase Invoice
- Credit Memo
- Debit Memo

## 12. GL Impact Standard

Use `GLImpactPanel` as the shared GL surface.

Rules:

- Draft values are labeled `Posting Preview`.
- Posted values come from authoritative journal entries.
- Client-only calculations never become production truth.
- Account codes open account detail or ledger where supported.
- Journal numbers open canonical Journal Entry or Accounting Trace.
- Do not display raw UUIDs as branch values.
- Keep internal IDs in expandable detail or System, not normal columns.
- Use business-facing posting rule descriptions where available.

## 13. Tax Impact Standard

Use `TaxImpactPanel` as the shared tax surface.

Rows may include VAT, EWT/CWT, ATC, tax base, rate, tax amount, tax treatment, ledger status, return/report, source rule, and certificate/report links.

Sales Invoice terminology:

- Expected CWT
- Expected Net Collectible
- Actual CWT Recognized
- 2307 Status

Expected CWT is informational unless governed accounting rules state otherwise. Actual CWT must link to receipt, payment application, or certificate workflow. Do not display a generic `CWT Receivable` row on Sales Invoice unless the governed accounting policy and posting engine recognize it at the invoice stage.

## 14. Validation Experience

Validation uses two levels.

Level 1: compact readiness indicator near relevant actions:

- Ready to Save
- Ready to Submit
- Ready to Post
- Posted Successfully
- 2 Warnings
- 3 Integrity Issues

Level 2: full Validation tab:

- Validation
- Status
- Message
- Resolution
- Source

The UI validation state must mirror server-side rules. Never show Ready to Post when the server will reject the transaction. Do not create a permanent Validation sidebar.

## 15. Workflow And Approval

Workflow shows lifecycle. Approval shows authorization.

Workflow examples:

- Draft
- Submitted
- Approved
- Posted
- Partially Paid
- Paid
- Voided
- Reversed
- Cancelled

Approval examples:

- Approval level
- Approver
- Role
- Required action
- Status
- Date/time
- Remarks
- Delegation when supported

When no workflow exists, show a compact truthful state. Workflow and Approval may combine temporarily when workflow maturity is simple.

## 16. Related Documents

Use `RelatedDocumentsTab` for relationship tables.

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

Every existing document number opens a canonical workspace. Missing expected stages show `Not linked`, `Not created`, or `Not applicable`.

## 17. Related Party

Related Party is the current master profile, not the transaction snapshot.

Use collapsible sections or internal sub-navigation:

1. Summary
2. Tax and Registration
3. Credit and Aging
4. Contacts and Addresses
5. Recent Transactions
6. Recent Payments

Default expanded sections should be Summary and Credit/Aging. Contacts, Addresses, Recent Transactions, and Recent Payments may default collapsed. Tax and Registration may default open for accountants, tax users, and auditors.

Use compact two-column field tables and compact data tables, not many floating cards.

## 18. Audit, Attachments, Activity, Notes, And System

Audit:

- Chronological authoritative evidence.
- Do not repeat in header/cards.
- Use old/new values only when available.

Attachments:

- File table only.
- Do not fake OCR/storage/preview/download.

Activity:

- Operational event stream.
- Not a duplicate of Audit.

Notes:

- Structured notes or memo display.
- Separate internal and customer-facing notes.

System:

- Technical metadata only when it already exists and provides operational, audit, integration, support, or troubleshooting value.
- Do not create technical metadata fields merely to populate the tab.

## 19. Existing Component Contracts

Use and extend existing component responsibilities:

| Responsibility | Component |
| --- | --- |
| Transaction shell, header, toolbar, tabs | `DocumentLayout` |
| Three-card information band | `PrimaryInformationPanel` |
| Enterprise line/application table | `LineGrid` |
| Expandable line detail | `LineDetailPanel` |
| Financial detail | `FinancialSummaryPanel` |
| Validation/readiness | `PostingValidationPanel` |
| GL impact | `GLImpactPanel` |
| Tax impact | `TaxImpactPanel` |
| Related documents | `RelatedDocumentsTab` |
| Lifecycle visualization | `WorkflowStrip` |
| Audit trail | `AuditTrailSection` |
| Shared ERP table primitives | `ErpSection` helpers |
| Status, amount, date atoms | `StatusBadge`, `AmountCell`, `DateCell` |

Possible missing shared components:

- Related Party structured profile
- Attachments table
- Activity feed/table
- Notes thread
- System metadata table
- Snapshot-versus-current indicator
- Collection application table

Do not rename existing components casually. Any rename requires a deliberate architecture decision and migration plan.

## 20. Performance And Interaction Targets

Form mode:

- Customer and item lookup begins showing usable results within 500 milliseconds under normal conditions.
- Local line calculations update effectively immediately.
- Expensive server previews are debounced.
- Save and Post prevent duplicate submission.
- Unsaved changes are protected.
- Failed saves preserve form data.
- Customer changes do not reload the full page.
- Line grid remains usable with at least 100 lines.

View mode:

- Essential header, cards, and lines become usable before every secondary tab finishes loading.
- Tab changes do not reload the full document unnecessarily.
- Related-document links open canonical routes.
- Header actions prevent duplicate post/receipt/email/void/reverse submissions.
- Failed actions leave the document state unchanged unless server confirms success.
- Permission and network errors show user-friendly explanations.

These are UX targets, not infrastructure SLAs unless adopted elsewhere.

## 21. Maturity And Rollout Tracking

Track form and view separately.

| Area | Target | Current status note |
| --- | --- | --- |
| Sales Invoice Form UX | Canonical create/draft-edit standard in `PXL_SALES_INVOICE_UX_STANDARD.md` | Approved; current create/edit workspace is the editable reference implementation |
| Sales Invoice View UX | Canonical saved-document view standard in `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md` | Approved; current saved-document page is the read-only reference implementation with data-source boundaries |
| Transaction Definition Schema | Typed transaction workspace rollout model | Implemented in `src/lib/transactionWorkspaceRollout.ts` and documented in `PXL_TRANSACTION_DEFINITION_SCHEMA.md` |
| Transaction Workspace Manifest | Rollout sequence, statuses, blockers, and next candidate | Implemented in `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`; Sales Order is the next eligible candidate after explicit instruction |
| Transaction Workspace Rollout Playbook | One-transaction-at-a-time implementation workflow and validation checklist | Implemented in `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md` |
| Core transaction views | Reuse Sales Invoice View architecture | Adopt-on-touch after accounting-core gate |
| Core transaction forms | Reuse Sales Invoice Form architecture | Adopt-on-touch after accounting-core gate |
| Related Party profile | Structured current master profile | Implemented in Sales Invoice view as the page-local reference; extract shared component when reused |
| Attachments | Governed attachment table | Depends on attachment storage/source availability |
| Activity | Operational stream | Depends on transaction events plus email/API/notification sources |
| System metadata | Useful existing technical metadata only | Do not add fields solely for display |

Rollout rule:

- Do not mass-refactor working pages just to match this standard.
- New transaction work should start from the standard.
- Existing transaction pages converge when they are next touched for planned work.
- Accounting/tax/lifecycle correctness outranks visual rollout.

## 22. Cross-Document Consistency Rules

When updating this or related standards, check for contradictions in:

- Route ownership
- Form versus view behavior
- Customer field location
- Three-card information band
- Header contents and metrics
- Toolbar actions
- Right sidebar prohibition
- Validation visibility
- Workflow and Approval
- Related Party structure
- Related Documents format
- Snapshot versus live master data
- Expected versus actual CWT
- Compact live summary versus Financial tab
- GL preview versus posted truth
- Tax preview versus posted truth
- System metadata scope
- Component naming
- Role visibility
- Posted-document immutability
- Void and reversal presentation
- Performance targets

When contradictions appear, revise the older general guidance to match the approved Sales Invoice pilot standards and the workspace standard.

## 23. Cross-References

- `PXL_ACCOUNTING_RULES_MATRIX.md`
- `PXL_TRANSACTION_MATRIX.md`
- `PXL_SALES_INVOICE_UX_STANDARD.md`
- `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md`
- `PXL_STANDARD_TRANSACTION_WORKSPACE.md`
- `PXL_ACCOUNTING_CORE_READINESS.md`
- `PXL_PRODUCT_BACKLOG.md`
