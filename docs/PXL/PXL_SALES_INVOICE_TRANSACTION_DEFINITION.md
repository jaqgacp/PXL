# PXL Sales Invoice Transaction Definition

Status: Completeness Audit v1
Last updated: 2026-07-15

## Transaction Identity

| Attribute | Definition |
| --- | --- |
| Transaction key | `sales-invoice` |
| Module | Sales / Accounts Receivable |
| Document family | Sales |
| Primary party | Customer |
| Posting transaction | Yes |
| Create/edit workspace | `SalesInvoicePage` |
| Read-only view workspace | `SalesInvoiceDocumentPage` |
| List/register route | `/sales-invoices` |
| Create route | `/sales-invoices/new` |
| View route | `/sales-invoices/:id` |

## Lifecycle

Current source-backed lifecycle:

1. Draft
2. Approved
3. Posted
4. Cancelled/voided where governed
5. Open, partially paid, or paid through collection state

Future lifecycle relationships must preserve standalone Sales Invoice encoding. Source documents may be offered but must not be mandatory.

## Header KPIs

Default view header KPIs:

- Invoice Total
- Collected
- Balance Due

Do not add COGS, Gross Profit, or Gross Margin to the header until inventory cost is authoritative and reconciled to GL.

## Information Panels

Required panels:

- Document Information
- Customer Information
- Sales Context

Sales Context displays only configured, source-backed dimensions. If no dimensions are assigned, show `No operational dimensions assigned.`

## Standard Tabs

The Sales Invoice view uses the approved tab set:

Lines, Financial, GL Impact, Tax Impact, Validation, Workflow, Approval, Audit, Related Docs, Related Party, Attachments, Activity, Notes, System.

Each tab must show source-backed data, concise empty states, or explicit unavailability. It must not expose raw technical identifiers as primary business values.

## Current Data Sources

| Definition area | Current source |
| --- | --- |
| Header | `sales_invoices` |
| Lines | `sales_invoice_lines` |
| Customer snapshot | `sales_invoices.customer_*_snapshot` |
| Current customer context | `customers` |
| Items | `items` |
| UOM | `units_of_measure` |
| VAT codes | `vat_codes` |
| Revenue accounts | `chart_of_accounts` |
| GL impact | `journal_entries`, `journal_entry_lines`, `fn_preview_gl_impact` |
| Tax impact | `tax_detail_entries` |
| Collections | `receipts`, `receipt_lines`, AR ledger/aging RPCs |
| Audit/workflow | header audit columns, approvals, transaction/audit surfaces |

## Explicit Non-Definitions

The Sales Invoice transaction definition does not own:

- inventory valuation rules,
- generic posting logic for all transaction types,
- master-data definitions for project/location/functional entity,
- payment/CWT recognition rules that belong to receipt/application workflows,
- document chaining requirements that would block standalone invoice creation.

Those must remain explicit transaction or master-data definitions.

## Accounting Impact Presentation

Sales Invoice GL Impact and Financial Summary use the `Separated Commercial and Inventory Accounting Impact` pattern.

| Section | Applies to | Source |
| --- | --- | --- |
| Commercial / Revenue Accounting Impact | AR, revenue, output VAT, invoice-side discounts/rounding/deferred revenue when supported | `fn_preview_gl_impact('SI', ...)` |
| Inventory / Cost Accounting Impact | COGS, Inventory, inventory movement/valuation lines for eligible inventory items | `fn_preview_gl_impact('SI', ...)` and inventory ledger evidence |
| Expected Withholding - Informational | Expected CWT only until receipt/payment recognition | SI expected CWT fields and related receipt/application evidence |

The sections are visual groupings only. Sales Invoice remains one balanced posting result. Future transactions may reuse this presentation pattern only when their transaction definition explicitly identifies commercial and inventory/cost effects.

## Draft State Control

Create/edit draft state is owned by the Sales Invoice workspace as one editable draft object. The route initializer is keyed by company, route mode, and invoice id. It runs only for a new document, first draft load, explicit record switch, or explicit reset/discard.

Customer, item, header-context, line-dimension, VAT basis, and note changes are partial immutable updates. Reference-data loads, lookup dropdown activity, tab changes, validation refresh, GL preview refresh, and tax preview refresh must not replace the editable draft.

Header defaults provide effective line values but do not silently overwrite existing line overrides. Blank line dimension values mean `Header/default` and resolve at save/posting time.
