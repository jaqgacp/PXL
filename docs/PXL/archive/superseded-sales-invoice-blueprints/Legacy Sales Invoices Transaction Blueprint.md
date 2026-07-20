# Sales Invoices

**Status:** Historical Superseded Snapshot
**Authority:** Non-authoritative; current Sales Invoice specifications live in docs/PXL/05. Sales/Sales Invoice/
**Last Reviewed:** 2026-07-18 documentation cleanup
**Read When:** Historical provenance only
**Do Not Read For:** Current Sales Invoice implementation authority

## Module Overview
The Sales Invoice (SI) is the paramount document for BIR compliance in the Philippines (especially with the Ease of Paying Taxes or EOPT Act making the Invoice the primary basis for Output VAT for both goods and services). It formally bills the customer, recognizes Sales Revenue in the General Ledger, recognizes Output VAT, and sets up Accounts Receivable.

### Document Flow & Data Inheritance
* **Source:** Can be billed from a **Delivery Receipt** (for goods) or directly from a **Sales Order** (for services/billing ahead).
* **Inheritance:** When inherited from a DR, the invoice pulls the exact items and quantities delivered, along with the original SO pricing. When inherited from an SO, it bills based on the SO quantities. Taxes (VAT) are computed upon generating the SI lines.

## Dashboard UI
The central hub for the billing department to manage accounts receivable creation.

### The Action Bar
* **Search Bar:** Search by SI Number, Customer Name, or TIN.
* **Filter:** Dropdown for Payment Status (Unpaid, Partially Paid, Paid) and Posting Status (Draft, Posted).
* **Customize View:** Select visible columns.
* **Export Button:** Export to Excel/CSV for month-end VAT relief preparation.
* **Print Button:** BIR-compliant printout format.
* **Create Invoice Button:** Draft a new invoice.
* **Import Button:** Bulk generate invoices from external billing systems.

### The Data List
Default columns displayed:
* Invoice Date
* SI Number
* Customer Name
* TIN
* Due Date
* Total Amount
* VAT Amount
* Status

## Data Fields (Header & Line Items)

### Header Information
| Field Name | Component Type | Inheritance / Data Source | Required? |
| :--- | :--- | :--- | :--- |
| Source Document | Dropdown (Searchable)| Links to DRs or SOs. | Optional |
| Customer | Dropdown linked to Master Data. UPON SELECTION, system MUST instantly auto-fill: Address, TIN, Credit Terms, and Tax Type. | Auto-filled from source, or manual.  | Yes  |
| SI Number | Auto-computed | System-generated sequence (BIR approved series). | Yes |
| Invoice Date | Date Picker | Defaults to current date. | Yes |
| Terms | Dropdown linked to Payment Terms | Auto-filled from Customer Master (e.g., Net 30).  | Yes  |
| Due Date | Auto-computed | `Invoice Date + Terms`. | Yes |
| Currency | Dropdown | Default PHP. | Yes |
| Remarks | Text Area | Manual input. | Optional |


**Critical UX/GL Rule:** The system MUST auto-fetch the Item's default Revenue, Expense, COGS, and Inventory GL accounts in the background to auto-generate the Journal Entry. Encoders MUST NEVER manually select a GL account for standard items.

### Line Items
| Field Name | Component Type | Inheritance / Data Source | Required? |
| :--- | :--- | :--- | :--- |
| Item/Service | Dropdown linked to Items. UPON SELECTION, instantly auto-fills Description, UOM, Unit Price/Cost, and Tax Code. | Auto-filled from source.  | Yes  |
| Description | Text Input | Auto-filled from source. | Yes |
| Quantity | Number Input | Auto-filled from source. | Yes |
| UOM | Dropdown linked to UOM | Auto-filled from source.  | Yes  |
| Unit Price | Number Input | Auto-filled from SO/Item Master. | Yes |
| Discount Amount | Number Input | Auto-filled from SO. | Optional |
| Tax Type | Dropdown linked to Tax Types | Vatable, Zero-Rated, Exempt.  | Yes  |
| Tax Amount | Auto-computed | 12% of Net if Vatable. | Yes |
| Total Amount | Auto-computed | `(Qty * Price) - Discount + Tax`. | Yes |

## Supabase Database Architecture


**Critical Database Rule:**
- Every transactional table MUST include a `company_id` to ensure tenant isolation.
- Composite unique constraints MUST be established (e.g., `company_id` + document number) to prevent duplicate documents within the same company.

### Table 1: `sales_invoices` (Header)
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the invoice. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `source_doc_type` | Text | Nullable | `delivery_receipt` or `sales_order`. |
| `source_doc_id` | UUID | Nullable | Polymorphic ID pointing to the source. |
| `customer_id` | UUID | Required, Foreign Key | Links to `customers.id`. |
| `si_number` | Text | Required, Unique | Formatted document number (e.g., SI-2023-0001). |
| `invoice_date` | Date | Required | Date of the invoice. |
| `terms_id` | UUID | Required, Foreign Key | Links to `ref_payment_terms.id`. |
| `due_date` | Date | Required | Target payment date. |
| `currency_id` | UUID | Required, Foreign Key | Links to `ref_currencies.id`. |
| `gross_amount` | Numeric | Required | Total before VAT and discounts. |
| `total_discount` | Numeric | Default 0 | Total discounts applied. |
| `vat_amount` | Numeric | Required | Total VAT output. |
| `net_amount` | Numeric | Required | Grand total to be paid. |
| `posting_status` | Text | Required | `draft`, `posted`, `voided`. |
| `payment_status` | Text | Required | `unpaid`, `partial`, `paid`. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Date record was created. |
| `updated_at` | Timestamp | Auto | Date record was last edited. |

### Table 2: `sales_invoice_lines` (Line Items)
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the line item. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `invoice_id` | UUID | Required, Foreign Key | Links to `sales_invoices.id`. |
| `source_line_id` | UUID | Nullable | Links to DR line or SO line. |
| `item_id` | UUID | Required, Foreign Key | Links to `items.id`. |
| `description` | Text | Required | Item description. |
| `quantity` | Numeric | Required | Invoiced quantity. |
| `uom_id` | UUID | Required, Foreign Key | Links to `ref_uom.id`. |
| `unit_price` | Numeric | Required | Price per unit. |
| `discount_amount`| Numeric | Default 0 | Discount applied. |
| `tax_code_id` | UUID | Required, Foreign Key | Links to `ref_tax_codes.id`. |
| `tax_amount` | Numeric | Required | Computed VAT for the line. |
| `line_total` | Numeric | Required | Final computed line amount. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Date record was created. |
| `updated_at` | Timestamp | Auto | Date record was last edited. |
