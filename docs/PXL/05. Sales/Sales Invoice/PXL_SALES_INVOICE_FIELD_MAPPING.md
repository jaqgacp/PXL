# PXL Sales Invoice Field Mapping

**Status:** Active summary companion
**Authority:** Tier 2 Implementation Specification; `../../04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` is the row-level field authority
**Last Reviewed:** 2026-07-18
**Applies To:** Sales Invoice create/edit and saved-document workspaces
**Read When:** A task changes Sales Invoice fields, source display, persistence, import/export, or view behavior
**Do Not Read For:** Universal transaction field-source rules; use the matrix

This file summarizes current Sales Invoice field behavior. The mandatory field-by-field source, storage, editability, appearance, business-use, implementation-status, and validation-status control is `../../04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`.

## Header Fields

| Field | User entered | Inherited | Computed | Posted/generated | Current source |
| --- | --- | --- | --- | --- | --- |
| Company | No | App context | No | RLS/source context | `sales_invoices.company_id` |
| Branch | Yes/defaulted | Context/default branch | No | Journal/tax branch | `sales_invoices.branch_id` |
| SI Number | No | Number series | Yes | No | `sales_invoices.si_number` |
| Invoice Date | Yes | Current date default | No | Posting/tax document date | `sales_invoices.date` |
| Due Date | Optional | Payment terms | Yes | AR aging | `sales_invoices.due_date` |
| Customer | Yes | Customer Master | No | Customer ledger/tax detail | `sales_invoices.customer_id` |
| Customer Name Snapshot | No | Customer Master at save | No | Reports/view | `sales_invoices.customer_name_snapshot` |
| Customer TIN Snapshot | No | Customer Master at save | Normalized display | VAT/BIR context | `sales_invoices.customer_tin_snapshot` |
| Customer Address Snapshot | No | Customer Master at save | No | Documents/reports | `sales_invoices.customer_address_snapshot` |
| Currency | Yes/defaulted | Customer/company default | No | No | `sales_invoices.currency_code` |
| Payment Terms | Optional | Customer default | Due-date dependency | No | `sales_invoices.payment_terms_id` |
| External Reference | Optional | No | No | No | `sales_invoices.reference` |
| Memo | Optional | No | No | No | `sales_invoices.memo` |
| VAT Price Basis | Yes | Future default policy | Server recomputation | Tax/amount basis | `sales_invoices.vat_price_basis` |
| Expected CWT | No direct amount entry | Customer CWT profile/ATC | Yes | Receipt workflow reference | `sales_invoices.cwt_amount_expected`, `cwt_tax_base`, `cwt_atc_code_id` |
| Department | Optional | Department Master | Effective line fallback | Journal dimensions | `sales_invoices.department_id` |
| Cost Center | Optional | Cost Center Master | Effective line fallback | Journal dimensions | `sales_invoices.cost_center_id` |
| Warehouse | Optional header default | Warehouse Master | Inventory-line inheritance only | Inventory movement context | `sales_invoices.warehouse_id` |
| Salesperson | Optional | Employee Master | Line inheritance | Reporting context | `sales_invoices.salesperson_id` |
| Account Owner | Optional | Employee Master | No | Reporting/relationship context | `sales_invoices.account_owner_id` |
| Status | Action-driven | Workflow | Yes | Lifecycle/audit | `sales_invoices.status` |
| Journal Entry | No | Posting engine | No | Yes | `sales_invoices.journal_entry_id` |

## Line Fields

| Field | User entered | Inherited | Computed | Posted/generated | Current source |
| --- | --- | --- | --- | --- | --- |
| Line Number | No | Line order | Yes | No | `sales_invoice_lines.line_number` |
| Item | Yes | Item Master | No | Reporting context | `sales_invoice_lines.item_id` |
| Description | Yes/defaulted | Item description | No | JE memo context | `sales_invoice_lines.description` |
| Quantity | Yes | No | No | Amount/inventory basis | `sales_invoice_lines.quantity` |
| UOM | Yes/defaulted | Item UOM | No | Reporting context | `sales_invoice_lines.uom_id` |
| Unit Price | Yes/defaulted | Item price | No | Amount basis | `sales_invoice_lines.unit_price` |
| Discount % | Yes | No | Discount amount | Revenue reduction | `sales_invoice_lines.discount_percent` |
| Discount Amount | Yes/computed | No | Server recomputed | Revenue reduction | `sales_invoice_lines.discount_amount` |
| Revenue Account | Yes/defaulted by permitted user | Item sales account | No | Revenue JE line | `sales_invoice_lines.revenue_account_id` |
| VAT Code | Yes/defaulted | Item/customer/company policy | VAT amount | VAT ledger | `sales_invoice_lines.vat_code_id` |
| Net Amount | No | No | Server recomputed from persisted VAT Price Basis | Revenue/tax base | `sales_invoice_lines.net_amount` |
| VAT Amount | No | No | Server recomputed | Output VAT/tax detail | `sales_invoice_lines.vat_amount` |
| Total Amount | No | No | Server recomputed | AR total | `sales_invoice_lines.total_amount` |
| Warehouse | Conditional | Header warehouse only for inventory items | No | Inventory issue/restoration | `sales_invoice_lines.warehouse_id` |
| Department | Optional | Header department fallback | Effective posting dimension | Journal dimensions | `sales_invoice_lines.department_id` |
| Cost Center | Optional | Header cost-center fallback | Effective posting dimension | Journal dimensions | `sales_invoice_lines.cost_center_id` |
| Salesperson | Optional | Header salesperson fallback | No | Reporting context | `sales_invoice_lines.salesperson_id` |
| Inventory Account | No direct manual standard entry | Item Master snapshot | No | Inventory JE credit | `sales_invoice_lines.inventory_account_id` |
| COGS Account | No direct manual standard entry | Item Master snapshot | No | COGS JE debit | `sales_invoice_lines.cogs_account_id` |
| Unit Cost | No | Posting engine valuation | No | Yes | `sales_invoice_lines.unit_cost` |
| Inventory Cost | No | Posting engine valuation | No | Yes | `sales_invoice_lines.inventory_cost` |
| Inventory Transaction | No | Posting engine | No | Yes | `sales_invoice_lines.inventory_transaction_id` |
| Remarks | Optional | No | No | Audit/printed context if supported | `sales_invoice_lines.remarks` |

## View-Only Fields

| Field | Source |
| --- | --- |
| Collected | Posted receipts/applications |
| Balance Due | AR ledger/receipt applications |
| Actual CWT Recognized | Posted receipt/application/certificate evidence |
| Posted GL Impact | Journal entries and lines |
| VAT Ledger Status | Tax detail entries |
| Inventory movement and cost | SI line posting evidence plus `inventory_transactions` |
| Audit timestamps | Invoice header and audit/event sources |

## Prohibited Field Behavior

- Do not display raw UUIDs as primary business labels.
- Do not show dimensions as business facts unless they are stored, derived by documented inheritance, or clearly unavailable.
- Do not compute posted COGS or margin from `items.standard_cost` on the client.
- Do not treat expected CWT as an SI-stage journal line.
- Do not reset unrelated draft fields when customer, item, warehouse, dimension, tax, or terms values change.
