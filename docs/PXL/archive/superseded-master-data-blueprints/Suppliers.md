# PXL ERP Blueprint: Suppliers

**Status:** Historical Superseded Snapshot
**Authority:** Non-authoritative; retained for provenance only
**Owner / Domain:** Master Data
**Applies To:** Master Data
**Read When:** Historical provenance or cleanup review only
**Do Not Read For:** Current implementation authority
**Last Reviewed:** 2026-07-18 documentation cleanup

## Module Overview
The Suppliers module stores the master records for all vendors and service providers from whom the business purchases goods or services. In the Philippines, accuracy here is essential for generating the Summary List of Purchases (SLP), tracking Input VAT, and correctly applying Expanded Withholding Tax (EWT) on payments. Proper setup ensures that BIR Form 2307 (Certificate of Creditable Tax Withheld at Source) can be automatically generated and accurately reflects the supplier's TIN and registered details.

## What You Will See on the Screen (The Dashboard)
When you open the "Suppliers" page, a comprehensive list of vendors will be displayed.

### The Action Bar (Top of the page):
* **Search Bar:** Search for suppliers using their Name, Trade Name, or TIN.
* **Filter:** Dropdown options for "Supplier Group", "Tax Type", and "Status" (Active/Inactive).
* **Customize View:** Allows users to select which columns to display.
* **Export Button:** Exports the filtered supplier list to CSV/Excel format.
* **Print Button:** Generates a printable vendor directory.
* **Create New Supplier Button:** The main action button to add a new vendor.
* **Import Button:** Allows bulk import of supplier records via CSV/Excel.

### The Data List (The main table):
Default columns displayed are:
* Supplier Code
* Registered Name
* Trade Name
* TIN
* Tax Type
* Contact Person
* Status (Active/Inactive)

At the end of every row, there will be buttons to "Edit" or "View" details.

---

## What Information We Need to Capture (The Data Fields)
Creating or editing a Supplier record opens a form divided into the following sections.

### Section 1: Basic Information
| Field Name | Description | Required? |
| :--- | :--- | :--- |
| Supplier Code | Text Input. Unique identifier for the vendor (e.g., VEN-001). | Yes |
| Supplier Group | Dropdown for categorization (e.g., Inventory, Services, Utilities). | Optional |
| Registered Name | Text Input. Exact legal name matching their BIR Form 2303. | Yes |
| Trade Name | Text Input. "Doing Business As" name. | Optional |
| Business Style | Text Input. The business style as indicated in their BIR registration. | Optional |

### Section 2: Tax & Compliance Details
| Field Name | Description | Required? |
| :--- | :--- | :--- |
| TIN | Text Input. Taxpayer Identification Number (000-000-000-00000). | Yes |
| Default Tax Type | Dropdown linked to Tax Types master. Dictates Input VAT behavior. | Yes |
| Default AP Withholding ATC | Dropdown linked directly to ATC master. | Optional |

### Section 3: Contact & Address Information
| Field Name | Description | Required? |
| :--- | :--- | :--- |
| Registered Address | Text Area. Full legal address for BIR purposes and Form 2307 generation. | Yes |
| Contact Person | Text Input. Primary contact person for purchasing or payables. | Optional |
| Email | Email Input. Email address for sending purchase orders or payment advices. | Optional |
| Phone Number | Text Input. Landline or mobile contact number. | Optional |

### Section 4: Commercial Terms
| Field Name | Description | Required? |
| :--- | :--- | :--- |
| Default Payment Terms | Dropdown linked to Payment Terms master. | Yes |
| Default Currency | Dropdown linked to Currencies master. | Yes |
| Default GL Account | Dropdown linked to Chart of Accounts (AP Account). | Yes |

---

## The Supabase Database Architecture


**Critical Database Rule:** A composite unique constraint must be enforced on (company_id, `supplier_code`) to ensure multi-tenant data integrity.

### Table: `suppliers`

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the supplier. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `supplier_code` | Text | Required, Unique | The unique vendor identifier. |
| `supplier_group_id` | UUID | Nullable, Foreign Key | Links to a `supplier_groups` table. |
| `registered_name` | Text | Required | Legal name. |
| `trade_name` | Text | Nullable | Trade name. |
| `business_style` | Text | Nullable | Business style. |
| `tin` | Text | Required | Philippine TIN in `NNN-NNN-NNN-NNNNN` format. |
| `default_tax_type` | UUID | Required, Foreign Key | Links to `tax_types` table. |
| `default_atc_code_id` | UUID | Nullable, Foreign Key | Links to `atc_codes` table for supplier AP withholding defaults. |
| `registered_address` | Text | Required | Full legal address. |
| `contact_person` | Text | Nullable | Name of primary contact. |
| `email` | Text | Nullable | Contact email. |
| `phone_number` | Text | Nullable | Contact number. |
| `default_terms_id` | UUID | Nullable, Foreign Key | Links to `payment_terms` table. |
| `default_currency_id` | UUID | Required, Foreign Key | Links to `currencies` table. |
| `default_gl_account_id` | UUID | Required, Foreign Key | Links to `chart_of_accounts` table. |
| `is_active` | Boolean | Default: `true` | Active status. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Creation date. |
| `updated_at` | Timestamp | Auto | Last edit date. |
