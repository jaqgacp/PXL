# PXL Transaction Workspace Design Standard

Status: OFFICIAL VISUAL STANDARD
Reference implementation: Sales Invoice Form and View Transaction Workspaces

This standard defines the enterprise ERP visual system for all transaction workspaces. It complements `PXL_STANDARD_TRANSACTION_WORKSPACE.md`, which governs architecture and information placement.

Rollout discipline is governed by `PXL_TRANSACTION_WORKSPACE_MANIFEST.md`, `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`, and `PXL_TRANSACTION_DEFINITION_SCHEMA.md`. This visual standard controls appearance and hierarchy only; transaction-specific fields, lifecycle, actions, accounting, tax, inventory, payment, and related-document behavior must remain explicit per transaction.

## Hierarchy

Transaction workspaces must guide the eye in this order:

1. Header
2. Document number, counterparty, totals
3. Primary information cards
4. Tabs
5. Active section content
6. Data grids
7. Captions and supporting metadata

Do not flatten all elements to the same weight. Header, totals, and counterparty identity must be instantly recognizable.

## Header

- Full-width transaction container.
- Family-specific subtle tint.
- Stronger border and elevation than cards.
- Rounded corners.
- Document number uses the workspace title scale.
- Counterparty uses 16px semi-bold brand text and is clearly clickable.
- Primary totals use 18px bold tabular numbers.
- Buttons use the shared button standard.

## Cards

Primary transaction cards use `pxl-transaction-card` and must feel like enterprise information panels:

- Very light neutral panel surface.
- Slightly darker border than generic cards.
- 8px radius.
- Subtle card shadow.
- 16px internal padding.
- 14px uppercase semi-bold section title.

Cards are not mini dashboards and must not use decorative graphics.

## Tabs

Tabs use `pxl-transaction-tabs` and `pxl-transaction-tab`.

- Text-only labels.
- Strong active state.
- Readable inactive state.
- Subtle hover state.
- Integrated with the workspace surface.
- No tab icons.

## Tables

Tables use `pxl-data-grid`.

- Header row must read clearly as a data grid.
- Numeric columns are right aligned and tabular.
- Text columns are left aligned.
- Totals rows are visually stronger.
- Hover and selected states are subtle.

## Reference Implementation

The Sales Invoice create/edit workspace is the baseline editable transaction pattern. The Sales Invoice saved-document workspace is the baseline read-only transaction pattern for posted, submitted, approved, partially paid, paid, voided, cancelled, and other presentation states. Future modules must inherit the shared tokens and components before adding module-specific behavior.
