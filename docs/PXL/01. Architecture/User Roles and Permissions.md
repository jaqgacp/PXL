# PXL ERP Blueprint: User Roles & Permissions

**Status:** Retained security/permission blueprint; verify against implementation
**Authority:** Tier 2 Implementation Blueprint; current RLS/code policies prevail
**Owner / Domain:** Architecture
**Applies To:** Architecture
**Read When:** Permission architecture or role-management task
**Do Not Read For:** Current user access proof without code/database inspection
**Last Reviewed:** 2026-07-18 documentation cleanup

## Module Overview
The User Roles and Permissions module is the core of the ERP's security architecture. It establishes a robust Role-Based Access Control (RBAC) schema that restricts UI visibility, enforces segregation of duties, and powers the Maker-Checker workflow. By mapping standard ERP roles (e.g., Administrator, Sales Encoder, AP Clerk, Approver) to precise permission sets, the system ensures that users only interact with data and actions relevant to their operational duties. This prevents unauthorized access and maintains strict audit compliance.

## Dashboard UI
The module is accessed by Administrators to manage security boundaries.

### The Action Bar
* **Create New Role:** Opens the role configuration builder.
* **Import/Export:** Allows bulk importing or auditing of role definitions.
* **Assign Users:** A shortcut to map active users to defined roles.

### The Data List
Displays all active roles in the system. Clicking a role opens the permission matrix for detailed configuration.

---

## Data Fields

### Section 1: Role Header
| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Role Name | The canonical name of the role (e.g., "AP Clerk", "Sales Manager"). | Text Input | Yes |
| Description | A brief explanation of the role's scope and duties. | Text Area | Optional |
| Is Active | Toggles if the role can be assigned to users. | Boolean Toggle Switch | Yes |

### Section 2: Permission Matrix (Line Items)
A massive grid displaying all system modules and the granular rights associated with them. This matrix explicitly defines the Maker-Checker logic (e.g., Maker has "Create", Checker has "Approve").

| Field Name | Description | UI Component | Required? |
| :--- | :--- | :--- | :--- |
| Module | The target ERP module (e.g., "Sales Orders", "Journal Entries"). | Read-only Computed Field | Yes |
| Read | Grants visibility to the module and its records. | Checkbox | Yes |
| Create | Grants the ability to draft new records (Maker right). | Checkbox | Yes |
| Update | Grants the ability to edit unapproved records. | Checkbox | Yes |
| Delete | Grants the ability to delete unposted/draft records. | Checkbox | Yes |
| Approve | Grants the ability to authorize transactions (Checker right). | Checkbox | Yes |
| Void | Grants the ability to void posted transactions. | Checkbox | Yes |

---

## Supabase Database Architecture

**Critical Database Rule:** A composite unique constraint must be enforced on `(company_id, role_name)` in the `roles` table, and `(role_id, module_name)` in the `role_permissions` table to ensure strict RBAC integrity.

### Table 1: `roles` (Header)
Defines the high-level access profiles.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the role. |
| `company_id` | UUID | Required, Foreign Key | Links to `companies.id`. |
| `role_name` | Text | Required | Name of the role (e.g., "Sales Encoder"). |
| `description` | Text | Nullable | Role explanation. |
| `is_active` | Boolean | Required, Default: true | System status. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |

### Table 2: `role_permissions` (Line Items)
Maps the granular Maker-Checker rights to specific modules for each role.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | System ID for the permission map. |
| `role_id` | UUID | Required, Foreign Key | Links to `roles.id`. |
| `module_name` | Text | Required | The target module/resource. |
| `can_read` | Boolean | Required, Default: false | Visibility right. |
| `can_create` | Boolean | Required, Default: false | Maker draft right. |
| `can_update` | Boolean | Required, Default: false | Edit right. |
| `can_delete` | Boolean | Required, Default: false | Deletion right. |
| `can_approve` | Boolean | Required, Default: false | Checker authorization right. |
| `can_void` | Boolean | Required, Default: false | Void/Reversal right. |
| `created_by` | UUID | Required, Foreign Key | Links to `users.id`. |
| `updated_by` | UUID | Nullable, Foreign Key | Links to `users.id`. |
| `created_at` | Timestamp | Auto | Timestamp of creation. |
| `updated_at` | Timestamp | Auto | Timestamp of last update. |
