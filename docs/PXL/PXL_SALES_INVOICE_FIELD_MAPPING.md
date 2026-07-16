# PXL Sales Invoice Field Mapping

Status: Completeness Audit v1
Last updated: 2026-07-15
Canonical matrix: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

This file is a summary companion. The mandatory field-by-field source, storage, editability, appearance, business-use, implementation-status, and validation-status control is `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`.

## Header Fields

| Field | User entered | Inherited | Computed | Posted/generated | Current source |
| --- | --- | --- | --- | --- | --- |
| Company | No | App context | No | No | `companyId` context |
| Branch | Yes/defaulted | Context/default branch | No | Journal line branch | `sales_invoices.branch_id` |
| SI Number | No | Number series | Yes | No | `sales_invoices.si_number` |
| Invoice Date | Yes | Current date default | No | Posting/tax document date | `sales_invoices.date` |
| Due Date | Optional | Payment terms | Yes | AR aging | `sales_invoices.due_date` |
| Customer | Yes | Customer Master | No | Customer ledger/tax detail | `sales_invoices.customer_id` |
| Customer Name Snapshot | No | Customer Master at save | No | Reports/view | `sales_invoices.customer_name_snapshot` |
| Customer TIN Snapshot | No | Customer Master at save | Normalized display | VAT/BIR context | `sales_invoices.customer_tin_snapshot` |
| Customer Address Snapshot | No | Customer Master at save | No | Documents/reports | `sales_invoices.customer_address_snapshot` |
| Currency | Yes/defaulted | Customer/company default | No | No | `sales_invoices.currency_code` |
| Payment Terms | Optional | Customer default | Due date dependency | No | `sales_invoices.payment_terms_id` |
| External Reference | Optional | No | No | No | `sales_invoices.reference` |
| Memo | Optional | No | No | No | `sales_invoices.memo` |
| VAT Price Basis | Yes | Future default policy | Preview recomputation | Future required | UI state only; not persisted |
| Expected CWT | No direct amount entry | Customer CWT profile/ATC | Yes | Receipt workflow reference | `sales_invoices.cwt_*` |
| Status | Action-driven | Workflow | Yes | Lifecycle/audit | `sales_invoices.status` |
| Journal Entry | No | Posting engine | No | Yes | `sales_invoices.journal_entry_id` |

## Line Fields

| Field | User entered | Inherited | Computed | Posted/generated | Current source |
| --- | --- | --- | --- | --- | --- |
| Line Number | No | Line order | Yes | No | `sales_invoice_lines.line_number` |
| Item | Yes | Item Master | No | Reporting context | `sales_invoice_lines.item_id` |
| Description | Yes/defaulted | Item description | No | JE memo context | `sales_invoice_lines.description` |
| Quantity | Yes | No | No | Amount basis | `sales_invoice_lines.quantity` |
| UOM | Yes/defaulted | Item UOM | No | Reporting context | `sales_invoice_lines.uom_id` |
| Unit Price | Yes/defaulted | Item price | No | Amount basis | `sales_invoice_lines.unit_price` |
| Discount % | Yes | No | Discount amount | Revenue reduction | `sales_invoice_lines.discount_percent` |
| Discount Amount | Yes/computed | No | Yes | Revenue reduction | `sales_invoice_lines.discount_amount` |
| Revenue Account | Yes/defaulted | Item sales account | No | Revenue JE line | `sales_invoice_lines.revenue_account_id` |
| VAT Code | Yes/defaulted | Item/customer/company policy | VAT amount | VAT ledger | `sales_invoice_lines.vat_code_id` |
| Net Amount | No | No | Server recomputed | Revenue/tax base | `sales_invoice_lines.net_amount` |
| VAT Amount | No | No | Server recomputed | Output VAT/tax detail | `sales_invoice_lines.vat_amount` |
| Total Amount | No | No | Server recomputed | AR total | `sales_invoice_lines.total_amount` |
| Warehouse | Future | Item/customer/branch policy future | No | Inventory issue future | Not stored |
| Cost/COGS | No | Inventory valuation future | Future | COGS JE future | Not stored |
| Remarks | Future optional | No | No | No | Not stored |

## View-Only Fields

| Field | Source |
| --- | --- |
| Collected | Posted receipts/applications |
| Balance Due | AR ledger/receipt applications |
| Actual CWT Recognized | Posted receipt/application/certificate evidence |
| Posted GL Impact | Journal entries and lines |
| VAT Ledger Status | Tax detail entries |
| Audit timestamps | Invoice header and audit/event sources |

## Prohibited Field Behavior

- Do not display raw UUIDs as primary business labels.
- Do not show dimensions as business facts unless they are stored or derived.
- Do not compute COGS or margin from `items.standard_cost` on the client.
- Do not persist VAT-inclusive invoices until VAT Price Basis is stored and server recomputation is governed.
