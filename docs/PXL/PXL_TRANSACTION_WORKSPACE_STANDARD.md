# PXL Transaction Workspace Standard v1.0

Status: Official versioned workspace rollout standard
Canonical architecture: `PXL_STANDARD_TRANSACTION_WORKSPACE.md`
Operational playbook: `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`
Manifest: `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`
Schema: `PXL_TRANSACTION_DEFINITION_SCHEMA.md`
Reference implementations: Sales Invoice Create/Edit Workspace and Sales Invoice Read-Only View Workspace

Reference qualification: these are the approved workspace UI references. Their business completeness is controlled by `PXL_SALES_INVOICE_FUNCTIONAL_SPECIFICATION.md` and the Sales Invoice field/dimension/GL/tax/posting maps. Do not copy any unresolved Sales Invoice gap into another transaction rollout.

Mandatory field-source gate: every transaction must have a Field Source Matrix under `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` or a transaction-specific matrix file. A transaction cannot move from `DEFINED` to `READY_FOR_IMPLEMENTATION` until the matrix is complete enough to establish source, storage, editability, appearance, and business use for every required field.

Mandatory draft-state gate: every transaction create/edit workspace must comply with `PXL_TRANSACTION_DRAFT_STATE_STANDARD.md`. A workspace cannot be treated as validated if changing a selector, tab, preview, or reference-data load can reset unrelated unsaved draft fields.

## Purpose

This document is the versioned control point for rolling the approved transaction workspace pattern across PXL one transaction at a time.

It does not replace `PXL_STANDARD_TRANSACTION_WORKSPACE.md`. It records the v1.0 rollout framework and change-control expectations for future transaction implementations.

## v1.0 Principle

All PXL transactions share the same workspace experience, but they do not share inappropriate business content.

Standardized across transactions:

- workspace shell
- page hierarchy
- typography
- colors
- spacing
- cards and panels
- tabs
- tables
- buttons
- status badges
- validation presentation
- workflow presentation
- approval presentation
- audit trail presentation
- related-document presentation
- attachments
- activity
- notes
- system metadata
- responsive behavior
- create/edit behavior pattern
- read-only view behavior pattern

Transaction-specific per document:

- document fields
- primary party
- operational dimensions
- line structure
- lifecycle statuses
- available actions
- validation rules
- approval rules
- posting logic
- GL impact
- tax impact
- inventory impact
- payment impact
- source and target documents
- header KPIs
- permissions
- correction and reversal behavior

The shared layer is presentation architecture. Business, tax, posting, lifecycle, and security rules remain explicit per transaction.

## Reference Implementations

Official references:

1. Sales Invoice Create/Edit Workspace
2. Sales Invoice Read-Only View Workspace

Use these references for:

- component structure
- visual hierarchy
- spacing
- typography
- action placement
- field presentation
- tab behavior
- grid behavior
- status treatment
- totals presentation
- empty states
- audit presentation
- related-document behavior

Do not copy Sales Invoice-specific fields, actions, tax rules, posting behavior, or related-document assumptions into other transactions.

Also do not copy Sales Invoice-specific gaps. If a field, dimension, cost value, tax fact, or relationship is not source-backed in Sales Invoice, future transaction definitions must either provide their own authoritative source or omit the field from primary presentation.

## Shared Architecture

The standard transaction workspace supports:

1. Breadcrumbs or route context.
2. Transaction Header.
3. Information Panels.
4. Transaction Tabs.
5. Active Tab Content.
6. Footer Metadata.

Header left side:

- back navigation
- document type
- document number
- primary party or contextual title
- status badges

Header right side:

- transaction-specific KPIs
- permitted actions

Information panel examples:

- Document Information
- Customer Information
- Supplier Information
- Sales Context
- Purchase Context
- Accounting Context
- Inventory Context
- Payment Context
- Banking Context
- Asset Context
- Tax Context

Reusable tabs:

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

Not every transaction displays every tab. The transaction definition specifies applicable tabs.

Primary business pages must not emphasize raw UUIDs. Technical identifiers belong in System or Audit.

## Separated Accounting Impact Pattern

Inventory-affecting transactions may separate accounting impact visually into commercial/revenue and inventory/cost sections when this improves review clarity. This is a presentation pattern only:

- both sections must come from one authoritative preview or posted accounting-impact service,
- the transaction remains one balanced accounting event unless an approved posting architecture explicitly uses linked journals,
- section subtotals must roll up to one combined debit/credit reconciliation,
- no line may be duplicated between sections,
- expected withholding remains informational until the approved recognition transaction.

The Sales Invoice workspace is the reference implementation for this pattern. Do not roll the pattern out to other transactions until their transaction definition identifies the applicable commercial, tax, inventory, payment, and correction effects.

## Shared Component Targets

Existing anchors:

- `DocumentLayout`
- `PrimaryInformationPanel`
- `LineGrid`
- `LineDetailPanel`
- `FinancialSummaryPanel`
- `GLImpactPanel`
- `TaxImpactPanel`
- `PostingValidationPanel`
- `WorkflowStrip`
- `RelatedDocumentsTab`
- `AuditTrailSection`
- `ErpSection`

Formal component names for future extraction or wrappers:

- TransactionWorkspaceShell
- TransactionBreadcrumbs
- TransactionHeader
- TransactionIdentity
- TransactionStatusBadges
- TransactionKpiGroup
- TransactionActionBar
- TransactionInformationGrid
- TransactionInformationPanel
- TransactionReadOnlyField
- TransactionEditableField
- TransactionTabs
- TransactionTabPanel
- EnterpriseDataGrid
- GridColumnChooser
- GridFilters
- GridExport
- GridRowInspector
- TransactionTotalsBar
- FinancialSummaryPanel
- GLImpactTable
- TaxImpactTable
- ValidationPanel
- WorkflowPanel
- ApprovalPanel
- AuditTrailTable
- RelatedDocumentsTable
- RelatedPartyPanel
- AttachmentsPanel
- ActivityTimeline
- NotesPanel
- SystemMetadataPanel
- EmptyState
- LoadingState
- ErrorState
- PermissionDeniedState

Use existing shared components first. Extract formal wrappers only when reuse justifies it.

## Rollout Control

Every transaction rollout must use:

- `src/lib/transactionWorkspaceRollout.ts`
- `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`
- `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`
- `PXL_TRANSACTION_DEFINITION_SCHEMA.md`
- `PXL_TRANSACTION_MATRIX.md`
- `PXL_ACCOUNTING_RULES_MATRIX.md`

Transactions are implemented one at a time. A future prompt must not automatically proceed beyond the selected transaction.

## Initial Sequence

Phase 0 - Reference Foundation:

1. Sales Invoice Create/Edit
2. Sales Invoice View
3. Shared workspace components
4. Transaction definitions
5. Registry
6. Manifest
7. Rollout playbook

Phase 1 - Sales Document Family:

1. Sales Order
2. Delivery Receipt
3. Sales Quotation
4. Sales Receipt / Official Receipt
5. Credit Memo

Phase 2 - Purchasing Document Family:

1. Purchase Order
2. Goods Receipt
3. Vendor Bill
4. Vendor Payment
5. Vendor Credit
6. Purchase Return
7. Purchase Request, if included in scope

Phase 3 - Accounting and Receivables/Payables:

1. Journal Entry
2. Recurring Journal Entry
3. Customer Payment
4. Vendor Payment
5. Customer Credit Application
6. Vendor Credit Application
7. Reversal Entry

Phase 4 - Inventory:

1. Inventory Receipt
2. Inventory Issue
3. Inventory Transfer
4. Inventory Adjustment
5. Stock Count
6. Assembly or Production Transactions, if in scope

Phase 5 - Banking and Treasury:

1. Bank Deposit
2. Bank Withdrawal
3. Bank Transfer
4. Check Payment
5. Bank Adjustment
6. Reconciliation Transaction Views

Phase 6 - Fixed Assets:

1. Asset Acquisition
2. Capitalization
3. Depreciation Run
4. Asset Transfer
5. Asset Disposal
6. Asset Adjustment

Phase 7 - Compliance and Specialized Transactions:

Implement only after core operational, accounting, and audit workspace patterns are stable.

## Change Control

Any future platform-level change must document:

- reason
- affected components
- affected transactions
- migration impact
- regression risk
- approval
- rollout plan

Do not silently change shared components in a way that breaks previously implemented transactions.

When shared components change, validate all transactions already using them.

## Current Next Prompt

Recommended exact next prompt:

```text
Implement the next eligible transaction workspace from the approved PXL Transaction Workspace Manifest and Rollout Playbook.
```

The next eligible candidate is Sales Order, subject to the dependency review and explicit instruction required by the playbook.
