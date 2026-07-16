# PXL Transaction Workspace Rollout Playbook

Status: Official operational rollout guide
Version: 1.0
Reference implementations: Sales Invoice Create/Edit Workspace and Sales Invoice Read-Only View Workspace
Typed registry: `src/lib/transactionWorkspaceRollout.ts`
Manifest: `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`
Field source matrix: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

## Purpose

This playbook makes future transaction workspace rollout predictable, auditable, and safe.

Future instructions may be as short as:

> Implement the next eligible transaction workspace from the approved PXL Transaction Workspace Manifest and Rollout Playbook.

The agent must still select the next eligible transaction, review dependencies, complete the definition, implement one transaction only, validate it, and update documentation.

## Non-Negotiable Scope Rules

Do not roll out multiple transactions in one pass.

Do not clone Sales Invoice business content into another transaction.

Do not redesign the approved workspace shell.

Do not place posting, tax, lifecycle, permission, or database logic inside presentational components.

Do not fabricate GL, tax, inventory, payment, approval, or audit data.

Do not mark a transaction validated until the applicable checklist has real evidence.

Do not move a transaction from `DEFINED` to `READY_FOR_IMPLEMENTATION` until its Field Source Matrix is complete enough to establish authoritative source, storage, editability, appearance, and business use for every required field.

## Mandatory Workflow

### Step 1 - Select The Next Transaction

Select the next eligible transaction from `PXL_TRANSACTION_WORKSPACE_MANIFEST.md` and `TRANSACTION_WORKSPACE_REGISTRY`.

Selection rules:

- Follow the approved rollout sequence.
- Do not select a random transaction.
- Do not skip ahead unless a documented dependency requires it.
- Do not start if the transaction is `NOT_DEFINED`, `BLOCKED`, or has unresolved critical behavior.
- Sales Invoice remains the reference and is not reimplemented as a rollout target.

### Step 2 - Review Dependencies

Review:

- master data
- `PXL_TRANSACTION_MATRIX.md`
- `PXL_ACCOUNTING_RULES_MATRIX.md`
- posting engine
- tax logic
- lifecycle
- permissions
- source documents
- target documents
- approval requirements
- audit requirements
- related compliance/report requirements

### Step 3 - Complete The Transaction Definition

Before implementation, the transaction must have a complete record in:

- `src/lib/transactionWorkspaceRollout.ts`
- `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`
- `PXL_TRANSACTION_DEFINITION_SCHEMA.md` if schema fields changed
- `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` or a transaction-specific field-source matrix file

The definition must identify fields, panels, tabs, KPIs, actions, status vocabulary, related documents, authoritative data sources, and documentation references.

The Field Source Matrix must identify:

- authoritative source;
- storage classification;
- editability and lifecycle lock behavior;
- snapshot versus live master behavior;
- appearance destinations;
- business uses;
- posting, tax, inventory, payment, report, API, import/export, printed-document, and BIR dependencies;
- implementation and validation status.

### Step 4 - Map The Approved Workspace Standard

Determine:

- which panels apply
- which tabs apply
- which KPIs apply
- which actions apply
- which line/grid columns apply
- which statuses apply
- which empty states apply
- which links and drilldowns apply
- which Field Source Matrix fields appear in each panel, tab, report, API, import/export, and printed document

Use the Sales Invoice form and view as structure references only. Do not copy Sales Invoice-specific fields, tax treatment, actions, or posting behavior.

### Step 5 - Implement Create/Edit

Use the approved editable workspace pattern when create/edit applies.

Create/Edit must:

- use shared design tokens and workspace components
- use enterprise lookup controls for master data
- preserve unsaved changes where applicable
- respect transaction-specific defaults and validation
- show only preview GL/tax data before posting
- keep business calculations in authoritative services

### Step 6 - Implement Read-Only View

Use the approved read-only workspace pattern when a saved-document view applies.

Read-only view must:

- use clean labels, values, links, tables, status chips, and totals
- avoid disabled-input imitation
- show posted truth from stored server results
- keep technical metadata in System or Audit
- preserve posted immutability
- link related documents and master records

### Step 7 - Connect Authoritative Business Data

Use real sources:

- saved document rows
- posting preview or posted journal data
- tax detail or tax ledger data
- workflow and approval sources
- transaction events and audit logs
- source/target document relationships
- inventory or payment application records

Posted transactions must not be recomputed client-side.

### Step 8 - Validate

Run applicable tests and manual review:

- business behavior
- visual consistency
- permissions
- lifecycle
- totals
- tax
- GL
- inventory
- payments
- related documents
- audit
- responsiveness

Record gaps as blockers, not as silent assumptions.

### Step 9 - Update Documentation

Update:

- `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`
- `PXL_TRANSACTION_MATRIX.md`
- `PXL_ACCOUNTING_RULES_MATRIX.md` when accounting behavior changes
- `PXL_STANDARD_TRANSACTION_WORKSPACE.md` when workspace architecture changes
- `PXL_TRANSACTION_EXPERIENCE_STANDARD.md` when implementation guidance changes
- transaction-specific UX docs when they exist
- `PXL_END_TO_END_AUDIT_FINDINGS.md` only for new real risks or findings

### Step 10 - Approve Before Moving Next

A transaction must be validated before the next rollout begins unless a documented dependency requires parallel work.

Stop after completing and validating one transaction.

## Standard Implementation Checklist

Every transaction must pass applicable items.

### General

- Workspace uses shared shell.
- No page-specific duplicate design system.
- Typography matches PXL standard.
- Header hierarchy is correct.
- Information panels are correct.
- Tabs are in approved order.
- Empty states are present.
- Loading and error states are present.
- Responsive behavior is acceptable.
- No raw UUID is a primary business display value.

### Create/Edit

- Required fields are correct.
- Defaults are correct.
- Master-data selectors work.
- Dependent values auto-fill correctly.
- Line entry works.
- Validation is user-friendly.
- Save Draft works.
- Create/edit draft state follows `PXL_TRANSACTION_DRAFT_STATE_STANDARD.md`.
- Selector, tab, lookup, and preview changes preserve unrelated unsaved fields.
- Route initialization runs only for new document, first draft load, record switch, or explicit reset/discard.
- Submit works where applicable.
- Post works only when permitted.
- Unsaved-change behavior is handled.
- No posted values are recomputed incorrectly.
- Every field shown in create/edit is present in the Field Source Matrix.
- Every editable field has a source, storage, editability, validation, and audit rule.

### View

- Read-only values are business-readable.
- No disabled-input imitation unless intentionally approved.
- Status is correct.
- KPIs are authoritative.
- Actions respect status and permissions.
- Customer, supplier, employee, account, item, asset, bank, or related-party links work.
- Related documents are clickable.
- Audit users display names instead of raw IDs where display names are available.
- Technical metadata is moved to System or Audit.
- Posted values come from stored server truth.
- Every field shown in view is present in the Field Source Matrix.
- No field is displayed as a business fact without a valid source.

### Accounting

- Debit and credit reconcile.
- Correct accounts are shown.
- Dimensions are preserved.
- Dimensions match the Field Source Matrix header/line inheritance and posting-propagation rules.
- Journal entry is traceable.
- Posted impact is authoritative.
- Reversal or correction flow is correct.
- Posting period is visible where applicable.

### Tax

- Tax codes are correct.
- Tax base is correct.
- Tax amount is correct.
- VAT classification is correct.
- Withholding treatment is correct.
- TIN uses `XXX-XXX-XXX-XXXXX`.
- BIR-related values use normalized source data.
- Tax fields match the Field Source Matrix snapshot and authoritative-ledger rules.
- Informational tax values are clearly separated from authoritative ledger values.

### Document Relationships

- Created From is correct.
- Applied To is correct.
- Converted To is correct.
- Reversal links are correct.
- Payment links are correct.
- Source documents are clickable.
- Duplicate processing is prevented where required.

### Security And Audit

- Permissions are enforced by real controls, not by UI only.
- Posted immutability is preserved.
- Audit trail is complete.
- Status transitions are recorded.
- Approval history is preserved.
- Technical identifiers are secondary or System-only.
- Field Source Matrix validation status is updated before approval.

## Testing Strategy

### Visual Consistency Tests

- header
- panels
- tabs
- grids
- totals
- buttons
- empty states
- loading states
- error states

### Interaction Tests

- navigation
- selectors
- tabs
- actions
- row inspection
- related links
- filters
- exports
- action-menu overflow

### Lifecycle Tests

- draft
- submitted
- approved
- posted
- partially processed
- completed
- cancelled
- voided
- reversed

### Accounting Tests

- totals
- GL reconciliation
- dimensions
- posting period
- journal links
- correction/reversal links

### Tax Tests

- tax base
- rate
- tax amount
- TIN
- VAT classification
- withholding recognition
- authoritative versus informational tax display

### Security Tests

- permissions
- action visibility
- action execution guards
- immutability
- role restrictions
- cross-company access

### Audit Tests

- actors
- timestamps
- field changes
- status transitions
- document relationships
- technical metadata placement

### Responsive Tests

- desktop widths
- moderate-width laptop
- tab overflow
- horizontal grid scrolling
- action collapse
- card stacking

## Component Reuse Rules

Use composition and configuration.

Good patterns:

- shared header component with transaction-specific KPIs
- shared panel component with transaction-specific fields
- shared tab framework with transaction-specific tabs
- shared grid with transaction-specific columns
- shared validation display with transaction-specific validation results
- shared audit display with transaction-specific audit events

Avoid:

- one giant component containing conditions for every transaction
- hundreds of nested document-type checks
- duplicating the full Sales Invoice page
- placing business logic inside presentational components
- transaction-specific CSS files that recreate the design system
- universal posting logic that incorrectly treats all transactions alike
- hiding business differences behind generic labels

## Document Family Rules

### Sales Family

May share:

- Customer Information
- Sales Context
- customer-related documents
- sales dimensions
- sales status vocabulary

Must keep transaction-specific:

- quote/order/delivery/invoice/receipt/credit behavior
- fulfillment and invoicing quantities
- posting and tax recognition timing

### Purchasing Family

May share:

- Supplier Information
- Purchase Context
- receiving relationships
- supplier-related documents
- procurement dimensions

Must keep transaction-specific:

- request/order/receipt/bill/payment/credit behavior
- receiving and billing quantities
- AP EWT policy

### Inventory Family

May share:

- warehouse context
- source warehouse
- destination warehouse
- item movement fields
- quantity impact

Must keep transaction-specific:

- valuation method
- reason codes
- count freeze behavior
- cost and GL impact

### Banking Family

May share:

- bank account
- checkbook
- value date
- clearing status
- reconciliation state

Must keep transaction-specific:

- cash movement direction
- check/payment rules
- reconciliation locking

### Accounting Family

May share:

- posting period
- journal status
- debit/credit control
- reversal information

Must keep transaction-specific:

- source system
- recurring/template behavior
- reversal rules

## Master Data Dependency Rule

When a transaction requires a field not properly supported by master data:

- do not hardcode the field
- do not create isolated dropdown values
- do not place temporary values only inside the transaction
- identify the appropriate master-data source
- extend master data if necessary
- document the dependency
- validate permissions and lifecycle
- update related standards

Examples:

- customer payment terms
- supplier tax profile
- branch TIN
- department
- cost center
- project
- location
- functional entity
- warehouse
- bank account
- tax code
- posting profile
- item accounting profile

## Change Control

PXL Transaction Workspace Standard v1.0 is the baseline.

Any future platform-level workspace change must document:

- reason
- affected components
- affected transactions
- migration impact
- regression risk
- approval
- rollout plan

When shared components change, validate all transactions already using them.

## Future Prompt Template

Use this exact prompt for the next rollout:

```text
Implement the next eligible transaction workspace from the approved PXL Transaction Workspace Manifest and Rollout Playbook.

Before implementation:

1. Identify the next eligible transaction.
2. State the selected transaction.
3. State why it is next.
4. List its dependencies.
5. List the documentation and code areas to review.
6. Confirm whether its transaction definition is complete.
7. Do not start if critical business behavior is undefined.

Implementation requirements:

- Reuse the approved PXL Transaction Workspace Shell.
- Reuse the approved design system and shared components.
- Do not copy Sales Invoice-specific content.
- Implement both Create/Edit and Read-Only View when applicable.
- Use the transaction-specific definition for fields, lines, KPIs, lifecycle, actions, tabs, posting, tax, and related documents.
- Preserve posted immutability.
- Use authoritative server-side accounting and tax data.
- Update the manifest, transaction matrix, rollout playbook, related standards, and implementation status.
- Validate using the standard checklist.
- Stop after completing and validating this single transaction.
- Do not proceed to the next transaction without a new instruction.

At completion, report:

- transaction implemented
- create/edit status
- read-only view status
- shared components reused
- new components created
- business rules connected
- tests performed
- remaining blockers
- documentation updated
- recommended next transaction
```

## Current Next Candidate

Sales Order is the first rollout test candidate after this foundation is approved because it tests:

- non-posting lifecycle
- partial fulfillment
- partial invoicing
- customer commitment
- open quantity
- fulfilled quantity
- invoiced quantity
- remaining quantity
- conversion to Delivery Receipt
- conversion to Sales Invoice
- related-document chains
- approval
- hold and cancellation
- different KPIs from Sales Invoice
- different actions from Sales Invoice

Do not implement Sales Order until a future explicit rollout instruction is given.
