# PXL ERP Blueprint: Tax Applicability Matrix

**Status:** Retained compliance blueprint; verify against implementation and findings
**Authority:** Tier 2 Compliance Specification unless Tier 1 accounting/tax/security authority conflicts
**Owner / Domain:** Compliance
**Applies To:** Compliance
**Read When:** Exact BIR/compliance task routed by README.md
**Do Not Read For:** Unrelated startup, UI, inventory, or Sales Invoice work
**Last Reviewed:** 2026-08-04 product-scope alignment

## Module Overview
For the current product, tax applicability governs VAT versus percentage tax and
EWT/CWT obligations. FWT and quarterly/annual Income Tax—including MCIT/RCIT,
NOLCO and OSD—are 🔮 excluded future extensions under PAD-015. Their retained
fields below are future-reference material, not current setup requirements,
delivery items or readiness blockers.

## Dashboard UI
Accessed primarily during initial company setup or when the BIR updates a taxpayer's Certificate of Registration (COR / BIR Form 2303).

### The Action Bar
* **Update Compliance Profile:** Locks in the configuration and triggers the frontend logic to conditionally render the correct BIR forms in the `10. Compliance` module.
* **View Form Visibility Map:** A read-only modal summarizing which current-scope reports (e.g., 2550Q, 2551Q, SLSP) are active based on the profile.

---

## Data Fields

### 🔮 Section 1: Future Income Tax Configuration — excluded
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Entity Type | Future Income Tax routing reference only. | Dropdown Menu | No — excluded |
| Income Tax Regime | Future RCIT/preferential routing reference only. | Dropdown Menu | No — excluded |
| Deduction Method | Future OSD/itemized routing reference only. | Dropdown Menu | No — excluded |

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

**Critical Database Rule:** A composite unique constraint must be enforced on `(company_id)` to ensure this table functions as a strict singleton settings record per company profile.

### Table: `tax_applicability_matrix`
This retained schema proposal mixes current-scope business-tax/withholding fields
with excluded future Income Tax fields. It is not current implementation proof;
future-only columns carry no PXL readiness weight.

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
