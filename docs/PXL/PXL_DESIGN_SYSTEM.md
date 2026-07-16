# PXL Design System

Status: OFFICIAL PLATFORM UI STANDARD
Reference implementation: Sales Invoice Form and View Transaction Workspaces
Implementation anchors: `src/index.css`, `src/lib/transactionWorkspace.ts`, `src/components/document/*`, `src/components/ui/*`

The PXL Design System governs visual hierarchy, typography, color, spacing, cards, buttons, forms, tabs, tables, status states, dialogs, side panels, empty states, loading states, focus states, disabled states, responsive behavior, and future dark-mode readiness across the ERP.

The Sales Invoice create/edit workspace is the reference editable transaction surface. The Sales Invoice saved-document view is the reference read-only transaction surface. Future Sales, Purchasing, Inventory, Banking, Accounting, Compliance, and reporting workspaces must inherit this system rather than introducing page-specific CSS or one-off component styling.

Transaction rollout must follow `PXL_TRANSACTION_WORKSPACE_MANIFEST.md` and `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`. The design system may be reused across future workspaces, but transaction-specific business fields, posting rules, tax rules, lifecycle actions, and related-document chains must come from that transaction's definition and authoritative services.

Field presentation must follow `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`. A component may style a field, but it must not invent the field source, formula, editability, or empty-state meaning. Technical IDs are secondary/System metadata unless the Field Source Matrix explicitly approves them as the business value.

Form components must follow `PXL_TRANSACTION_DRAFT_STATE_STANDARD.md`. Design-system inputs, lookups, tabs, grids, and previews may emit scoped changes, but they must not initialize, reset, or replace transaction draft state on their own.

## Core Tokens

| Token group | Standard |
| --- | --- |
| Typography | Inter, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif |
| Text | Primary `#1F2937`, Secondary `#4B5563`, Muted `#6B7280` |
| Brand | Primary navy/blue-gray, Accent burgundy |
| State | Success green, Warning amber, Danger red, Neutral gray |
| Surfaces | Page, panel, raised, header, tabs, table header, hover, selected |
| Borders | Subtle, medium, strong |
| Spacing | 4, 8, 12, 16, 24, 32 |
| Radius | 4, 6, 8 |
| Shadows | Card, header, tabs, popover |

## Component Contract

Use shared `pxl-*` classes and transaction helpers for ERP surfaces:

- `pxl-transaction-workspace`
- `pxl-transaction-header`
- `pxl-transaction-card`
- `pxl-transaction-tabs`
- `pxl-transaction-tab`
- `pxl-button`
- `pxl-input`
- `pxl-readonly-field`
- `pxl-data-grid`
- `pxl-status-badge`
- `pxl-empty-state`
- `pxl-dialog`
- `pxl-side-panel`

Do not create page-specific visual standards unless a platform standard is being piloted and documented.

Readonly fields must present source-backed values as readable text, links, badges, or tables. Missing source-backed values use concise matrix-approved empty states such as `Not recorded`, `Not linked`, `Not configured`, or `Not available`; do not fill gaps with placeholder business values.

## Visual Hierarchy

Visual weight decreases in this order:

1. Workspace Header
2. Document Number, Customer Name, Transaction Totals
3. Document Cards
4. Tabs
5. Section Content
6. Tables
7. Supporting Text

## Accounting Impact Sections

When a transaction definition approves separated accounting impact, render the GL Impact tab as:

1. Commercial / Revenue Accounting Impact
2. Inventory / Cost Accounting Impact, when applicable
3. Expected Withholding - Informational, when applicable
4. Combined Journal Reconciliation

Use plain section headers, concise subtitles, enterprise tables, section subtotal bars, and one final combined reconciliation. Do not use decorative color blocks or imply that visual sections are separate journals. Missing non-applicable inventory impact uses the empty state `No inventory or cost-of-goods-sold impact applies to this invoice.`

## Future Readiness

Information panels must be compatible with future collapsible behavior. Draft documents may default expanded; posted documents may default collapsed. This is a UI behavior enhancement only and must not alter transaction logic.
