# PXL ERP Blueprint: Opening Balances

## Module Overview
The Opening Balances module is the critical data migration utility used exclusively during system go-live. It provides a structured interface to upload historical starting points for Sub-Ledgers (Accounts Receivable, Accounts Payable, Inventory Valuation) and the General Ledger Trial Balance. To ensure the double-entry accounting equation remains balanced during piecemeal uploads, all opening balance transactions are dynamically routed through a specific suspense account (`Opening Balance Equity`). Once all migration is complete, this suspense account must net to zero.

## Dashboard UI
### The Action Bar
* **Upload Sub-Ledger:** Triggers the CSV import mapping tool for AR, AP, or Inventory.
* **Upload Trial Balance:** Triggers the CSV import for the GL starting balances.
* **Post Balances:** Locks the uploaded draft and posts the entries to the GL.

### The Data List
Displays all historical migration batches, showing their Type (`AR`, `AP`, `INV`, `GL`), Status (`Draft`, `Posted`), and Total Amount.

---

## Data Fields

### Section 1: Opening Balance Upload (Header)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Upload Batch ID | Auto-generated ID (e.g., MIG-2024-001). | Read-only Computed Field | Yes |
| Migration Type | Type of data being migrated. | Dropdown Menu (`AR`, `AP`, `Inventory`, `Trial Balance`) | Yes |
| As Of Date | The cutoff date for the historical balances. | Date Picker | Yes |
| Suspense Account | The GL account used to balance the entry. | Auto-filled (Opening Balance Equity) | Yes |
| Total Debit | Sum of debit lines. | Read-only Computed Field | Yes |
| Total Credit | Sum of credit lines. | Read-only Computed Field | Yes |

### Section 2: Upload Details (Line Items)
*Note: Fields dynamically change based on Migration Type.*
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Entity / Item | The Customer, Vendor, or Item being migrated. | Dropdown Menu | Yes |
| Reference Number | Historical invoice or bill number. | Text Input | Optional |
| Amount | The outstanding balance or valuation. | Number Input | Yes |

---

## Supabase Database Architecture

**Critical Database Rule for Lovable:** Composite Unique Constraint required on `(company_id, batch_id)` to ensure migration batch integrity.

### Table: `opening_balance_uploads`
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `batch_id` | Text | Required | Document control number. |
| `migration_type` | Text | Required | 'AR', 'AP', 'INV', 'GL'. |
| `as_of_date` | Date | Required | Cutoff date. |
| `total_amount` | Numeric | Required | Sum of the batch. |
| `status` | Text | Required, Default: 'Draft' | 'Draft', 'Posted'. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
