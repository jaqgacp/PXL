# PXL ERP Blueprint: Form 2307 Management

## Module Overview
The Form 2307 Management module is a centralized clearinghouse for tracking Creditable Withholding Taxes (CWT) under Philippine BIR regulations. It tracks BIR Form 2307s from two critical perspectives: 
1. **Issued (Payables):** Certificates the company must print and give to Vendors when paying Bills that were subjected to Expanded Withholding Tax (EWT).
2. **Collected (Receivables):** Certificates the company must collect from Customers who withheld tax upon paying their Sales Invoices.
This module ensures the company never misses claiming a tax credit (SAWT) and never faces penalties for failing to issue certificates to suppliers.

## Dashboard UI
### The Action Bar
* **Log Collected 2307:** Records a physical/scanned 2307 received from a customer.
* **Generate 2307 (Batch):** Generates print-ready PDFs for all selected Vendor Bills.
* **Filter by Status:** `Pending Collection`, `Collected`, `Pending Issuance`, `Issued`.

### The Data List
A split-view dashboard separating "To Collect (Customers)" and "To Issue (Vendors)".

---

## Data Fields

### Section 1: Form 2307 Registry (Line Items mapping to Invoices/Bills)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Type | Indicates if this is a Customer (CWT) or Vendor (EWT) certificate. | Read-only Computed Field | Yes |
| Source Document | The Sales Invoice or Vendor Bill reference. | Dropdown linked to Transactions | Yes |
| Business Partner | The Customer or Vendor name. | Auto-filled from Source Document | Yes |
| Tax Amount | The exact amount withheld. | Auto-filled from Source Document | Yes |
| ATC Code | Alphanumeric Tax Code (e.g., WC158 for 1% Goods). | Auto-filled from Source Document | Yes |
| Quarter / Year | The tax period the transaction falls under. | Read-only Computed Field | Yes |
| Status | `Pending`, `Collected/Issued`. | Dropdown Menu | Yes |
| Attachment | Scanned copy of the physical 2307 (Critical for SAWT). | File Upload | Optional |

---

## Supabase Database Architecture

**Critical Database Rule:** Composite Unique Constraint required on `(company_id, source_doc_id, type)` to prevent duplicate logging of certificates for the same transaction.

### Table: `form_2307_registry`
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `type` | Text | Required | 'COLLECT' (Customer) or 'ISSUE' (Vendor). |
| `source_doc_id` | UUID | Required | Links to `sales_invoices.id` or `vendor_bills.id`. |
| `partner_id` | UUID | Required, Foreign Key | Links to `customers.id` or `vendors.id`. |
| `tax_amount` | Numeric | Required | The actual withheld amount. |
| `atc_code` | Text | Required | Alphanumeric Tax Code. |
| `tax_year` | Integer | Required | e.g., 2024. |
| `tax_quarter` | Integer | Required | 1, 2, 3, or 4. |
| `status` | Text | Required, Default: 'Pending' | 'Pending', 'Completed'. |
| `attachment_url` | Text | Nullable | Link to uploaded file. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
