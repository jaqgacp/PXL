# PXL Transaction Definition Schema

Status: Official rollout schema
Version: 1.0
Implementation anchor: `src/lib/transactionWorkspaceRollout.ts`
Reference implementations: Sales Invoice Create/Edit Workspace and Sales Invoice Read-Only View Workspace
Field source control: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

## Purpose

This document defines the metadata structure used to roll out PXL transaction workspaces one transaction at a time.

The definition describes workspace presentation, route shape, component needs, lifecycle vocabulary, documentation references, and authoritative data-source connections. It does not contain posting calculations, tax calculations, workflow rules, permissions, or database validation logic.

## Core Principle

The shared layer is the transaction workspace and presentation architecture.

Transaction-specific rules remain explicit in:

- `PXL_TRANSACTION_MATRIX.md`
- `PXL_ACCOUNTING_RULES_MATRIX.md`
- transaction services and RPCs
- tax and posting engines
- permission/RLS definitions
- document-specific lifecycle code

Do not build a universal business transaction engine from this definition.

## TypeScript Model

The canonical typed model is `TransactionWorkspaceDefinition` in `src/lib/transactionWorkspaceRollout.ts`.

Required top-level fields:

| Field | Purpose |
| --- | --- |
| `key` | Stable transaction key used by registry and manifest. |
| `name` | User-facing transaction name. |
| `module` | ERP module such as Sales, Purchasing, Accounting, Inventory, Banking, Fixed Assets, or Compliance. |
| `family` | Workspace family used for rollout grouping and visual tone. |
| `documentPrefix` | Numbering/document prefix when applicable. |
| `routes` | List/create/edit/view route contract. |
| `primaryParty` | Counterparty or contextual party shown in header and related party views. |
| `lifecycleStatuses` | Supported status vocabulary. |
| `headerKpis` | Transaction-specific KPI labels shown in the header. |
| `actionGroupsByStatus` | Action labels by lifecycle status. This is display planning only, not permission enforcement. |
| `informationPanels` | Applicable information panels. |
| `tabs` | Applicable transaction tabs in approved order. |
| `relatedDocuments` | Expected source, target, application, reversal, and trace relationships. |
| `impacts` | Posting, GL, tax, inventory, and payment impact levels. |
| `behaviorReferences` | Pointers to authoritative posting, tax, inventory, correction, reversal, void, or cancellation references. |
| `fieldSourceMatrix` | Mandatory Field Source Matrix document, completion status, validation status, and blockers. |
| `documentation` | Applicable standards and matrix references. |
| `rollout` | Rollout phase, sequence, implementation statuses, blockers, and notes. |

## Allowed Status Values

Definition/rollout status:

- `NOT_DEFINED`
- `DEFINED`
- `READY_FOR_IMPLEMENTATION`
- `IN_PROGRESS`
- `IMPLEMENTED`
- `VALIDATED`
- `APPROVED_REFERENCE`
- `BLOCKED`

Mode status:

- `NOT_REQUIRED`
- `NOT_STARTED`
- `PARTIAL`
- `IMPLEMENTED`
- `VALIDATED`

Field Source Matrix status:

- `NOT_STARTED`
- `DRAFT`
- `COMPLETE`
- `VALIDATED`
- `BLOCKED`

Field Source Matrix validation status:

- `NOT_TESTED`
- `DOCUMENT_REVIEWED`
- `IMPLEMENTATION_REVIEWED`
- `END_TO_END_VALIDATED`
- `BLOCKED`

Impact level:

- `none`
- `informational`
- `preview`
- `authoritative`
- `posting`
- `pending-definition`

## Standard Tabs

The default reusable tab order is:

1. Lines
2. Financial
3. GL Impact
4. Tax Impact
5. Validation
6. Workflow
7. Approval
8. Audit
9. Related Docs
10. Related Party
11. Attachments
12. Activity
13. Notes
14. System

Transactions may hide non-applicable tabs, but they must not invent arbitrary tab ordering without documentation.

## Standard Panel Kinds

Supported information panel kinds:

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
- Related Party

Panels must display only configured and applicable fields. Do not display placeholder dimensions.

## Component Contract

Definitions map to reusable workspace components:

| Workspace need | Component anchor |
| --- | --- |
| Shell/header/tabs/actions | `DocumentLayout` |
| Information panels | `PrimaryInformationPanel` |
| Editable/read-only line grid | `LineGrid` |
| Row inspector | `LineDetailPanel` |
| GL impact | `GLImpactPanel` |
| Tax impact | `TaxImpactPanel` |
| Validation | `PostingValidationPanel` |
| Related documents | `RelatedDocumentsTab` |
| Audit | `AuditTrailSection` |
| Section/table primitives | `ErpSection` |

Create new shared components only when the pattern is needed by more than one transaction or is clearly platform-level.

## Prohibited Content In Definitions

Do not place the following inside the definition:

- debit/credit calculations
- tax-rate calculation logic
- posting implementation logic
- permission checks
- RLS rules
- database mutation logic
- SQL snippets
- client-side recomputation of posted truth
- Sales Invoice-specific fields copied into unrelated documents
- static dropdown values that should come from governed master data

## Registry Functions

The registry exports:

- `TRANSACTION_WORKSPACE_REGISTRY`
- `STANDARD_TRANSACTION_TABS`
- `STANDARD_TRANSACTION_COMPONENTS`
- `getTransactionWorkspaceDefinitions()`
- `getTransactionWorkspaceDefinition(key)`
- `getNextEligibleTransaction()`
- `getTransactionsByRolloutStatus(status)`

`getNextEligibleTransaction()` is planning support only. It does not override user approval, accounting core gates, transaction dependencies, or business readiness.

`getNextEligibleTransaction()` must not return a transaction whose Field Source Matrix status is below `COMPLETE`. A transaction cannot move from `DEFINED` to `READY_FOR_IMPLEMENTATION` until the matrix establishes authoritative source, storage, editability, appearance, and business use for every required field.

## Change Control

Any change to the schema must update:

- this document
- `src/lib/transactionWorkspaceRollout.ts`
- `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`
- `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`
- `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` when field-source status, rules, or matrix requirements change
- `PXL_STANDARD_TRANSACTION_WORKSPACE.md` when workspace behavior changes
- `PXL_TRANSACTION_MATRIX.md` or `PXL_ACCOUNTING_RULES_MATRIX.md` when transaction behavior changes

Shared schema changes must be validated against every transaction already using the registry.
