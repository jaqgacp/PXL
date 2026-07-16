# PXL Component Library Standard

Status: OFFICIAL PLATFORM COMPONENT STANDARD

PXL components must be reusable, token-driven, and consistent across modules.

## Required Shared Components

| Component | Standard |
| --- | --- |
| Transaction Workspace | `pxl-transaction-workspace`, `DocumentLayout` |
| Header | `pxl-transaction-header` |
| Card / Panel | `pxl-transaction-card`, `TransactionPanel` |
| Read-only Information Panel | `PrimaryInformationPanel` |
| Button | `pxl-button` variants |
| Table | `pxl-data-grid`, `LineGrid` |
| Tabs | `pxl-transaction-tabs`, `pxl-transaction-tab` |
| GL Impact View | `GLImpactPanel` |
| Tax Impact View | `TaxImpactPanel` |
| Related Documents View | `RelatedDocumentsTab` |
| Audit Trail View | `AuditTrailSection` |
| Status Badge | `pxl-status-badge` |
| Input / Dropdown / Date Picker | `pxl-input` |
| Readonly Field | `pxl-readonly-field` |
| Dialog / Popover | `pxl-dialog` |
| Side Panel | `pxl-side-panel` |
| Validation Message | `pxl-validation-message` |
| Empty State | `pxl-empty-state` |
| Loading State | `pxl-loading-state` |

## Rules

- Build future transaction screens with shared components first.
- Start transaction rollout from `src/lib/transactionWorkspaceRollout.ts`, `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`, and `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`.
- Add props or variants when a legitimate new pattern appears.
- Do not duplicate visual CSS inside page modules.
- Component variants must preserve keyboard, hover, focus, disabled, and responsive states.
- Do not place transaction-specific posting, tax, permission, or lifecycle rules inside shared presentational components.
