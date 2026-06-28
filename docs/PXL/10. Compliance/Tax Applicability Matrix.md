# PXL ERP Blueprint: Tax Applicability Matrix

## Module Overview
The Tax Applicability Matrix is the brain of the PXL ERP compliance engine. Updated to strictly adhere to the Philippine **EOPT Act (RA 11976)**, **CREATE Law**, and **TRAIN Law**, this configuration module dictates exactly which tax reports and UI elements are generated based on the company's specific taxpayer profile. By establishing strict rules on Entity Type, VAT Registration, Deduction Methods, and Withholding Agent status, the system dynamically hides irrelevant tax forms—preventing compliance errors and dramatically simplifying the user experience.

## Dashboard UI
Accessed primarily during initial company setup or when the BIR updates a taxpayer's Certificate of Registration (COR / BIR Form 2303).

### The Action Bar
* **Update Compliance Profile:** Locks in the configuration and triggers the frontend logic to conditionally render the correct BIR forms in the `10. Compliance` module.
* **View Form Visibility Map:** A read-only modal summarizing exactly which reports (e.g., 2550Q, 1702Q, SLSP) are currently active based on the toggles.

---

## Data Fields

### Section 1: Entity & Income Tax Configuration
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Entity Type | Sole Proprietorship (triggers 1701 series) vs. Corporation/Partnership/OPC (triggers 1702 series). | Dropdown Menu | Yes |
| Income Tax Regime | Regular Corporate Income Tax (RCIT - triggers standard forms) vs. Special/Preferential (PEZA/BOI - triggers 1702-EX/MX). | Dropdown Menu | Yes |
| Deduction Method | OSD (Optional Standard Deduction) vs. Itemized. Dictates the requirement to attach detailed Financial Statements and SAWT to the ITR. | Dropdown Menu | Yes |

### Section 2: Business Tax Configuration (EOPT Compliant)
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Registration Type | VAT Registered vs. Non-VAT Registered. | Dropdown Menu | Yes |
| File Quarterly VAT (2550Q) | Auto-enabled if VAT. Per EOPT RA 11976, monthly 2550M is abolished, and strictly quarterly filing is enforced. | Read-only Computed Field | Yes |
| Require SLSP | Auto-enabled if VAT. Requires Summary List of Sales and Purchases. | Read-only Computed Field | Yes |
| File Percentage Tax (2551Q) | Auto-enabled if Non-VAT. | Read-only Computed Field | Yes |

### Section 3: Withholding Tax Configuration
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Top Withholding Agent (TWA) | If enabled, the system automatically computes and deducts 1% (Goods) or 2% (Services) Expanded Withholding Tax (EWT) on all AP Bills. | Boolean Toggle Switch | Yes |
| Engaged in Services | Under EOPT, dictates that output VAT on services must be declared upon accrual (billing) rather than upon collection. | Boolean Toggle Switch | Yes |

---

## Supabase Database Architecture

**Critical Database Rule for Lovable:** A composite unique constraint must be enforced on `(company_id)` to ensure this table functions as a strict singleton settings record per company profile.

### Table: `tax_applicability_matrix`
This table stores the boolean/enum rules that frontend components will read to conditionally render the Compliance dashboards.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the tax profile. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `entity_type` | Text | Required | 'SOLE_PROP' or 'CORP_PARTNERSHIP'. |
| `tax_regime` | Text | Required | 'RCIT', 'PEZA', 'BOI', 'BMBE'. |
| `deduction_method` | Text | Required | 'OSD' or 'ITEMIZED'. |
| `registration_type` | Text | Required | 'VAT' or 'NON_VAT'. |
| `is_twa` | Boolean | Required, Default: false | Triggers auto 1%/2% EWT withholding. |
| `is_service_provider` | Boolean | Required, Default: false | Triggers EOPT accrual VAT logic for services. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
