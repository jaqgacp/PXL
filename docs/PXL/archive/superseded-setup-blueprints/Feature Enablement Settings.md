# PXL ERP Blueprint: Feature Enablement Settings

**Status:** Historical Superseded Snapshot
**Authority:** Non-authoritative; retained for provenance only
**Owner / Domain:** Transaction Framework
**Applies To:** Transaction Framework
**Read When:** Historical provenance or cleanup review only
**Do Not Read For:** Current implementation authority
**Last Reviewed:** 2026-07-18 documentation cleanup

## Module Overview
The Feature Enablement Settings module is the master configuration page that drives Progressive Disclosure across the entire PXL ERP platform. Inspired by enterprise systems like NetSuite, this module allows administrators to toggle major functional modules, simplify downstream workflows, and dictate approval modes based on the company's operational maturity. By dynamically hiding unused features (e.g., hiding Purchase Requests for companies that only do direct Bills), the UI remains pristine, reducing cognitive load without breaking the underlying accounting logic.

## Dashboard UI
When an Administrator accesses "Feature Enablement," they are presented with a master toggle dashboard.

### The Action Bar
* **Save Configuration:** Commits all toggle changes and immediately updates the system-wide UI rendering logic.
* **Audit History:** Displays a log of who enabled or disabled specific features and when.

### The Data List (Configuration Form)
A sectioned form categorized by business area, heavily utilizing boolean toggle switches to enable or disable global behaviors.

---

## Data Fields

### Section 1: Global Modules
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Enable Inventory Management | Toggles the entire `06. Inventory` module. If off, items are treated as non-inventory/services. | Boolean Toggle Switch | Yes |
| Enable Multi-Warehouse | Enables transfer workflows and location-based tracking. | Boolean Toggle Switch | Yes |
| Enable Fixed Assets | Toggles the `08. Fixed Assets` module for depreciation tracking. | Boolean Toggle Switch | Yes |
| Enable Budgeting | Enables budget vs. actuals tracking in the GL. | Boolean Toggle Switch | Yes |
| Enable Multi-Currency | Enables foreign exchange rates and currency translations. | Boolean Toggle Switch | Yes |
| Enable Petty Cash | Toggles the Petty Cash management module in Treasury. | Boolean Toggle Switch | Yes |

### Section 2: Workflow Simplification
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Require Sales Quotes & Orders | If OFF, hides Quotations and SOs. Allows direct creation of Delivery Receipts or Invoices (Direct Cash Sales). | Boolean Toggle Switch | Yes |
| Require Purchase Requests | If OFF, hides PRs. Allows direct creation of Purchase Orders or Vendor Bills. | Boolean Toggle Switch | Yes |
| Require Delivery Receipts | If OFF, Invoices directly handle stock out (if Inventory is enabled). | Boolean Toggle Switch | Yes |
| Require Receiving Reports | If OFF, Vendor Bills directly handle stock in (if Inventory is enabled). | Boolean Toggle Switch | Yes |

### Section 3: Approval Mode
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Enforce Maker-Checker Workflow | If OFF (Single-User Mode), all transactions bypass approval routing and are auto-approved. If ON (Multi-User Mode), strict approval workflows are enforced. | Boolean Toggle Switch | Yes |

---

## Supabase Database Architecture

**Critical Database Rule:** A composite unique constraint must be enforced on `(company_id)` to ensure this table acts as a strict singleton configuration record per tenant.

### Table: `sys_feature_enablement`
This table acts as a singleton per company. It dictates global application state.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the configuration record. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `enable_inventory` | Boolean | Required, Default: false | Toggles Inventory module. |
| `enable_multi_warehouse` | Boolean | Required, Default: false | Toggles multiple locations. |
| `enable_fixed_assets` | Boolean | Required, Default: false | Toggles Fixed Assets module. |
| `enable_budgeting` | Boolean | Required, Default: false | Toggles Budgeting module. |
| `enable_multi_currency` | Boolean | Required, Default: false | Toggles Foreign Currency features. |
| `enable_petty_cash` | Boolean | Required, Default: false | Toggles Petty Cash module. |
| `req_sales_flow` | Boolean | Required, Default: true | Forces Quote -> SO -> DR -> SI. |
| `req_purchase_requests`| Boolean | Required, Default: true | Forces PR -> PO -> RR -> Bill. |
| `req_delivery_receipts`| Boolean | Required, Default: true | Forces explicit DR generation. |
| `req_receiving_reports`| Boolean | Required, Default: true | Forces explicit RR generation. |
| `enforce_maker_checker`| Boolean | Required, Default: true | Toggles strict approval routing. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
