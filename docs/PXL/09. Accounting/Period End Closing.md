# PXL ERP Blueprint: Period End Closing

## Module Overview
The Period End Closing module provides strict timeline controls for the accounting ledger. It allows Financial Controllers to "Lock" specific months, preventing any user from posting, editing, or voiding transactions in backdated periods, which is critical for maintaining the integrity of published financial statements and tax returns. Additionally, it handles the massive "Year-End Closing" automated macro, which calculates the net profit/loss for the fiscal year and posts a closing journal entry to zero out all Revenue and Expense accounts, sweeping the balance into Retained Earnings.

## Dashboard UI
### The Action Bar
* **Lock/Unlock Period:** Toggles the state of a specific month. (Requires Admin/Controller privileges).
* **Execute Year-End Close:** Triggers the Retained Earnings sweep macro for a specific Fiscal Year.

### The Data List
Displays all defined Fiscal Periods (e.g., Jan 2024, Feb 2024) and their current status (`Open`, `Locked`, `Closed`).

---

## Data Fields

### Section 1: Fiscal Periods (Header)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Period Name | Display name (e.g., "January 2024"). | Text Input | Yes |
| Start Date | First day of the month/period. | Date Picker | Yes |
| End Date | Last day of the month/period. | Date Picker | Yes |
| Is Locked | If True, no transaction can be posted with a date falling between the Start and End dates. | Boolean Toggle Switch | Yes |

### Section 2: Year-End Closing Logs (Header)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Fiscal Year | The year being closed. | Text Input | Yes |
| Retained Earnings Account | The equity account receiving the sweep. | Dropdown linked to Chart of Accounts | Yes |
| Closing Journal Entry | The auto-generated system JE. | Read-only Computed Field | Yes |

---

## Supabase Database Architecture

**Critical Database Rule:** Composite Unique Constraint required on `(company_id, start_date, end_date)` to prevent overlapping fiscal periods.

### Table 1: `fiscal_periods`
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `period_name` | Text | Required | e.g., 'Jan 2024'. |
| `start_date` | Date | Required | Start bound. |
| `end_date` | Date | Required | End bound. |
| `is_locked` | Boolean | Required, Default: false | Prevents backdating. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |

### Table 2: `year_end_closings`
| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `fiscal_year` | Integer | Required | e.g., 2024. |
| `retained_earnings_id`| UUID | Required, Foreign Key | Links to `chart_of_accounts.id`. |
| `journal_entry_id` | UUID | Required, Foreign Key | Links to `journal_entries.id`. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
