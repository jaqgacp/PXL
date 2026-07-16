# PXL Transaction Draft State Standard

Status: Mandatory platform standard
Last updated: 2026-07-15
Reference implementation: Sales Invoice Create/Edit Workspace

## Purpose

Every transaction create/edit workspace must preserve valid unsaved user input while the user edits header fields, context fields, line selectors, tabs, previews, or related panels.

Changing one field may update only:

1. that field,
2. documented dependent defaults, and
3. derived preview state affected by the change.

It must never recreate, clear, or reset the full transaction draft unless the user explicitly starts a new document, switches to another record, resets/discards the draft, or confirms a destructive action.

## Authoritative Draft State

Each transaction form must have one authoritative editable draft state owned by the transaction workspace or a shared transaction draft controller. Sections, tabs, lookup controls, grids, previews, and validation panels must read from and update that same draft.

Do not let child components independently initialize overlapping transaction fields.

The draft state includes document/header fields, primary party snapshot, operational context, header dimensions, transaction lines, line-level dimensions, pricing and tax selections, notes and attachment metadata where supported, and dirty-state metadata.

Derived previews are separate from editable draft state.

## Initialization Rules

Initialize editable draft state only when opening a brand-new transaction, loading an existing draft for the first time, explicitly switching to a different transaction record, or explicitly resetting/discarding the draft.

Do not reinitialize because customer, item, warehouse, dimension, tax, or terms options load; a selector changes; a tab changes; a preview refreshes; the page rerenders; or a callback identity changes.

Route-based initialization must be keyed to the route/company/document identity, not to live draft fields or mutable reference-data arrays.

## Partial Update Rules

All field changes must use immutable partial updates.

- Header field changes update that header field only.
- Customer selection merges customer snapshot/defaults into documented customer-owned fields only.
- Item selection updates the selected line and documented item-derived fields only.
- Line dimension changes update only that line dimension.
- Add, copy, and remove line actions affect only the intended line list operation.
- Preview responses must not replace editable draft values.

## Master-Data Merge Rules

Master data may default or refresh only fields it owns.

Customer selection may update customer id, name, TIN, TIN branch, registered address, payment terms, withholding profile, and documented customer pricing/tax defaults.

Item selection may update item id, description, UOM, unit price or price source, VAT code/rate, revenue account, inventory account, COGS account, and default warehouse for eligible inventory lines.

Unrelated document fields, other lines, notes, attachments, sales context, and user-entered quantities must remain.

## Header-To-Line Inheritance

Header defaults may provide effective line values for Warehouse, Department, Cost Center, Project, Location, Functional Entity, and Salesperson.

Standard behavior:

- New lines may inherit current eligible header defaults.
- Existing lines retain their current explicit values.
- Blank line dimension values mean `Header/default` and must resolve to the effective header value at save/posting time.
- Changing a header default must not silently overwrite explicit line-level overrides.
- Propagation to existing lines requires an explicit user action such as `Apply to unmodified lines` or `Apply to all lines`.
- If no valid effective value exists for a required field, show a validation blocker.

## Preview-State Separation

Financial, GL, tax, inventory, validation, and workflow previews are derived state.

Preview services receive the draft or saved document identity and return computed preview data only. They must not return a replacement editable transaction record. Posted views must use authoritative posted records and ledgers rather than recomputing editable draft values.

## Asynchronous Lookup Safety

Asynchronous customer, item, dimension, pricing, tax, posting-preview, and reference-data requests must be scoped.

- Stale responses must not overwrite newer selections.
- Loading reference options must not clear selected values.
- Errors must preserve current draft input.
- Retrying a lookup or preview must preserve current draft input.
- Selecting Item B after Item A must not allow Item A data to overwrite Item B.

Use request tokens, route keys, cancellation flags, query keys, or equivalent safeguards.

## Dirty State and Discard Protection

Transaction forms must track whether the current draft differs from the last persisted or initialized draft.

Warn before discarding unsaved changes through browser refresh, route navigation, cancel/back actions, switching records, or switching company context where applicable. Do not warn when no changes exist.

## Tab Persistence

Tab changes must not reconstruct the transaction draft. Tabs may mount/unmount panels, but editable state remains in the authoritative draft state.

## Development Diagnostics

In development or test mode, transaction forms should log non-sensitive diagnostics when initialization repeats for the same route/document key, stale async data attempts to apply after a newer request, a preview response tries to replace editable state, or a partial field update removes unrelated draft fields.

Do not log sensitive customer or commercial values.

## Future Transaction Requirement

Every future transaction create/edit form must comply with this standard before it can move to `READY_FOR_IMPLEMENTATION`, `VALIDATED`, or `APPROVED_REFERENCE`.

The Field Source Matrix must document which fields are entered, inherited, computed, generated, preview-only, or posted authoritative results.
