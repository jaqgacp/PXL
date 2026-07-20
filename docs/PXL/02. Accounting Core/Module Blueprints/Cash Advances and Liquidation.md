# PXL ERP Blueprint: Cash Advances and Liquidation

**Status:** Retained accounting blueprint; verify against implementation
**Authority:** Tier 2 Implementation Blueprint; accounting rules matrix prevails
**Owner / Domain:** Accounting Core
**Applies To:** Accounting Core
**Read When:** Exact accounting setup/module task
**Do Not Read For:** Current posting authority without the accounting rules matrix
**Last Reviewed:** 2026-07-18 documentation cleanup

## Module Overview
The Cash Advances and Liquidation module tracks employee cash advances (CA) from initial disbursement to final settlement. It ensures strict accountability by forcing employees to submit liquidations (expense reports with attached receipts). The module dynamically handles complex accounting scenarios: if the employee spends less than the CA, the system generates a "Refund" back to Treasury; if the employee spends more, it generates a "Reimbursement" routing to Accounts Payable. This ensures employee ledgers remain balanced.

## Dashboard UI
### The Action Bar
* **New Cash Advance:** Drafts a request for funds.
* **New Liquidation:** Settles an outstanding Cash Advance.
* **Export PDF/Excel:** Generates print-ready CA and Liquidation forms.

### The Data List
Displays all Cash Advances with their statuses (`Draft`, `Approved`, `Released`, `Partially Liquidated`, `Fully Liquidated`).

---

## Data Fields

### Section 1: Cash Advance (Header)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| CA Number | Auto-generated document number (e.g., CA-2024-001). | Read-only Computed Field | Yes |
| Employee Name | The employee requesting the advance. | Dropdown linked to Employees | Yes |
| Requested Amount | Total cash requested. | Number Input | Yes |
| Purpose | Reason for the cash advance. | Text Area | Yes |
| Date Required | When the funds are needed. | Date Picker | Yes |
| Target Liquidation Date | Deadline for the employee to submit receipts. | Date Picker | Yes |

### Section 2: Liquidation (Header)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Liquidation Number | Auto-generated document number (e.g., LIQ-2024-001). | Read-only Computed Field | Yes |
| Reference CA | The specific Cash Advance being settled. | Dropdown linked to Cash Advances | Yes |
| Employee Name | Auto-filled from Cash Advance. | Read-only Computed Field | Yes |
| Advanced Amount | Auto-filled from Cash Advance. | Read-only Computed Field | Yes |
| Total Liquidated | Sum of all expense lines below. | Read-only Computed Field | Yes |
| Variance | Advanced Amount minus Total Liquidated. Positive = Refund due; Negative = Reimbursement due. | Read-only Computed Field | Yes |

### Section 3: Liquidation Expenses (Line Items)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Date Incurred | Date the expense was made. | Date Picker | Yes |
| Description | Details of the expense. | Text Input | Yes |
| Amount | Total amount spent. | Number Input | Yes |
| Expense Account | The GL Account to charge (e.g., Travel Expense). | Dropdown linked to Chart of Accounts | Yes |
| Receipt Attachment | Uploaded scanned receipt or photo. | File Upload | Yes |

---

## Supabase Database Architecture

**Critical Database Rule:** Composite Unique Constraint required on `(company_id, ca_number)` for Cash Advances, and `(company_id, liquidation_number)` for Liquidations.

### Table 1: `cash_advances` (Header)
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `ca_number` | Text | Required | Document control number. |
| `employee_id` | UUID | Required, Foreign Key | Links to `employees.id`. |
| `requested_amount`| Numeric | Required | Funds requested. |
| `purpose` | Text | Required | Reason for advance. |
| `date_required` | Date | Required | Target release date. |
| `target_liq_date` | Date | Required | Deadline to liquidate. |
| `status` | Text | Required, Default: 'Draft' | 'Draft', 'Approved', 'Released', 'Liquidated'. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |

### Table 2: `liquidations` (Header)
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `liquidation_number`| Text | Required | Document control number. |
| `ca_id` | UUID | Required, Foreign Key | Links to `cash_advances.id`. |
| `total_liquidated`| Numeric | Required | Sum of expenses. |
| `variance_amount` | Numeric | Required | Advanced minus Liquidated. |
| `status` | Text | Required, Default: 'Draft' | 'Draft', 'Approved', 'Posted'. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |

### Table 3: `liquidation_lines` (Line Items)
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `liquidation_id` | UUID | Required, Foreign Key | Links to `liquidations.id`. |
| `date_incurred` | Date | Required | Date of receipt. |
| `description` | Text | Required | Particulars. |
| `amount` | Numeric | Required | Cost of line item. |
| `account_id` | UUID | Required, Foreign Key | Links to `chart_of_accounts.id`. |
| `attachment_url` | Text | Required | Link to stored file. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
