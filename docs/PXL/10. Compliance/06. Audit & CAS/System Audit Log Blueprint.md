# PXL ERP Blueprint: System Audit Log

**Status:** Retained compliance blueprint; verify against implementation and findings
**Authority:** Tier 2 Compliance Specification unless Tier 1 accounting/tax/security authority conflicts
**Owner / Domain:** Compliance
**Applies To:** Compliance
**Read When:** Exact BIR/compliance task routed by README.md
**Do Not Read For:** Unrelated startup, UI, inventory, or Sales Invoice work
**Last Reviewed:** 2026-07-18 documentation cleanup

## Module Overview
The System Audit Log is the constitutional backbone of PXL ERP's data integrity framework, directly mandated by **Principle 9: Audit Everything**. It is an immutable, append-only table that captures the exact WHO, WHEN, WHAT TABLE, WHAT ACTION, and BEFORE/AFTER JSON state of every data modification across the entire platform.

This table is **never written to by application code** — it is exclusively populated by PostgreSQL database triggers that fire automatically on every `INSERT`, `UPDATE`, and `DELETE` across all critical tables. No developer, administrator, or BIR examiner can edit or delete a row in this table.

**This is not a user-facing CRUD module.** It is a forensic evidence log accessible to System Administrators and BIR CAS auditors via a read-only UI panel.

---

## Why This Architecture Is Mandatory

Under Philippine CAS (Computerized Accounting System) accreditation requirements, an ERP must demonstrate:

1. **Data Integrity** — records cannot be altered without a traceable log of the alteration.
2. **Accountability** — every change is permanently associated with a specific authenticated user UUID.
3. **Non-Repudiation** — a user cannot deny having made a change. The `old_data` JSONB proves the before-state.

**Concrete Fraud Scenario:** A malicious controller changes a supplier's bank account number from BDO ****1234 to their personal account one hour before a ₱5,000,000 payment run. `sys_audit_logs` will contain the exact row before (`old_data → bank_account_number = '****1234'`) and after (`new_data → bank_account_number = '****9999'`), with the controller's `user_id`, their IP address, and the precise UTC timestamp. This is admissible forensic evidence in a BIR fraud investigation.

---

## Supabase Database Architecture

### Table 1: `sys_audit_logs`

This table is **INSERT-ONLY**. RLS policies block `UPDATE` and `DELETE` permanently — even for users with the `super_admin` role.

**Critical Database Rules:**
1. `company_id` must be indexed — required for RLS filtering without full table scans.
2. `(table_name, record_id)` must be jointly indexed — enables the forensic query "show all changes to this specific record."
3. `created_at` must be indexed — enables time-range audit queries during BIR examinations.
4. `old_data` and `new_data` are JSONB — full row snapshots capturing every column value, not column-by-column diffs.
5. This table must **NEVER** be truncated, archived off-platform, or partitioned in a way that discards data. Retention is permanent and non-negotiable.

| Column Name | Data Type | Rules | What it stores |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key, Default: `gen_random_uuid()` | System identifier for this log entry. |
| `company_id` | UUID | Required, Foreign Key, Indexed | Links to `companies.id`. Enables multi-tenant RLS scoping. |
| `user_id` | UUID | Required, Foreign Key | Links to `users.id`. The authenticated user who triggered the change. |
| `table_name` | Text | Required, Indexed | Name of the table that was modified (e.g., `suppliers`, `journal_entries`). |
| `record_id` | UUID | Required, Indexed | The `id` UUID of the specific row affected. Enables per-record full audit history. |
| `action` | Text | Required | ENUM: `INSERT`, `UPDATE`, `DELETE`. |
| `old_data` | JSONB | Nullable | Complete row state **BEFORE** the change. `NULL` for `INSERT` actions. |
| `new_data` | JSONB | Nullable | Complete row state **AFTER** the change. `NULL` for `DELETE` actions. |
| `ip_address` | Text | Nullable | Client IP address from the Supabase auth session context (`x-forwarded-for` header). |
| `user_agent` | Text | Nullable | Browser or app user agent string for session fingerprinting. |
| `created_at` | Timestamp | Auto, Default: `NOW()`, Indexed | Exact server-side UTC timestamp. Immutable. |

**Note:** This table intentionally has NO `updated_at`, `updated_by`, or standard audit columns. It IS the audit infrastructure — it cannot audit itself, and no update/delete should ever occur.

---

## Composite Indexes

```sql
-- Primary forensic lookup: all changes to a specific record in a specific table
CREATE INDEX idx_audit_table_record
  ON sys_audit_logs (company_id, table_name, record_id);

-- Time-range audit query: all changes by a specific user in a time window
CREATE INDEX idx_audit_user_time
  ON sys_audit_logs (company_id, user_id, created_at DESC);

-- BIR examiner: all changes within a fiscal period across all tables
CREATE INDEX idx_audit_time
  ON sys_audit_logs (company_id, created_at DESC);
```

---

## Row-Level Security — Insert-Only Policy

```sql
-- The trigger function (SECURITY DEFINER) uses the service role to INSERT.
-- This policy allows that mechanism while blocking all other writes.
CREATE POLICY "sys_audit_logs_trigger_insert"
ON sys_audit_logs
FOR INSERT
WITH CHECK (true);

-- Permanently block UPDATE — no exceptions, not even super_admin
CREATE POLICY "sys_audit_logs_no_update"
ON sys_audit_logs
FOR UPDATE
USING (false);

-- Permanently block DELETE — no exceptions, not even super_admin
CREATE POLICY "sys_audit_logs_no_delete"
ON sys_audit_logs
FOR DELETE
USING (false);

-- Tenant isolation: authenticated users may only READ their own company's logs
CREATE POLICY "sys_audit_logs_tenant_read"
ON sys_audit_logs
FOR SELECT
USING (company_id = (auth.jwt() ->> 'company_id')::UUID);
```

---

## PostgreSQL Trigger Implementation

Database triggers are the **ONLY** mechanism that populates `sys_audit_logs`. Application-layer code, Supabase Edge Functions, and RPC calls must **NEVER** perform a direct `INSERT INTO sys_audit_logs`. Triggers fire automatically and are invisible to the application.

### Step 1: Create the Shared Trigger Function (Execute Once in Supabase SQL Editor)

```sql
CREATE OR REPLACE FUNCTION fn_audit_log_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER  -- Runs as function owner, bypassing caller's RLS restrictions
SET search_path = public
AS $$
DECLARE
  v_company_id  UUID;
  v_user_id     UUID;
  v_record_id   UUID;
  v_old_data    JSONB;
  v_new_data    JSONB;
BEGIN
  -- Resolve user identity from the Supabase JWT
  v_user_id    := (auth.jwt() ->> 'sub')::UUID;
  v_company_id := (auth.jwt() ->> 'company_id')::UUID;

  -- Capture row state based on the operation type
  IF TG_OP = 'DELETE' THEN
    v_record_id := OLD.id;
    v_old_data  := to_jsonb(OLD);
    v_new_data  := NULL;
  ELSIF TG_OP = 'INSERT' THEN
    v_record_id := NEW.id;
    v_old_data  := NULL;
    v_new_data  := to_jsonb(NEW);
  ELSE  -- UPDATE
    v_record_id := NEW.id;
    v_old_data  := to_jsonb(OLD);
    v_new_data  := to_jsonb(NEW);
  END IF;

  -- Write the immutable audit entry
  INSERT INTO sys_audit_logs (
    company_id,
    user_id,
    table_name,
    record_id,
    action,
    old_data,
    new_data,
    ip_address,
    created_at
  ) VALUES (
    COALESCE(v_company_id, NEW.company_id),
    v_user_id,
    TG_TABLE_NAME,
    v_record_id,
    TG_OP,
    v_old_data,
    v_new_data,
    current_setting('request.headers', true)::json->>'x-forwarded-for',
    NOW()
  );

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
```

### Step 2: Apply the Trigger to Every Critical Table

Execute the statement below for each table in the priority list. Replace `{table}` with the actual table name:

```sql
CREATE TRIGGER trg_audit_{table}
AFTER INSERT OR UPDATE OR DELETE
ON {table}
FOR EACH ROW
EXECUTE FUNCTION fn_audit_log_trigger();
```

---

## Trigger Priority List

### Tier 1 — Financial Ledger (MANDATORY — Deploy First)

| Table | Fraud / Compliance Risk |
| :--- | :--- |
| `journal_entries` | Direct GL manipulation affects income tax |
| `journal_entry_lines` | Individual debit/credit record alteration |
| `general_ledger_entries` | Immutable ledger backbone |

### Tier 2 — Transactional Documents (MANDATORY)

| Table | Risk |
| :--- | :--- |
| `sales_invoices` | Revenue understatement |
| `sales_invoice_lines` | Line-item amount manipulation |
| `purchase_invoices` | Fictitious supplier payments |
| `purchase_invoice_lines` | Overstated purchase expense |
| `petty_cash_vouchers` | Small cash misappropriation |
| `fund_transfers` | Unauthorized cash movement |
| `bank_adjustments` | Fictitious bank charges |
| `asset_acquisitions` | Phantom capitalization |
| `asset_disposals` | Concealed asset sale proceeds |
| `asset_impairments` | Manipulated write-down amounts |
| `form_2307_issued` | EWT certificate integrity |
| `form_2307_tracking` | Certificate claim integrity |

### Tier 3 — Master Data (HIGH — Deploy Before Go-Live)

| Table | Critical Field at Risk |
| :--- | :--- |
| `suppliers` | `bank_account_number` — payment fraud |
| `customers` | `tin` — BIR compliance |
| `bank_accounts` | Account number fraud |
| `chart_of_accounts` | GL mapping manipulation |
| `atc_codes` | Withholding ATC/rate manipulation |
| `vat_codes` | VAT rate manipulation |
| `approval_workflows` | Threshold reduction fraud |

### Tier 4 — System Configuration (MEDIUM)

| Table |
| :--- |
| `compliance_profiles` |
| `inventory_settings` |
| `number_series` |
| `users` |
| `role_permissions` |

---

## Read-Only Admin UI Specification

The audit log is surfaced to System Administrators as a **read-only investigation panel** — not a CRUD form. No create, edit, or delete actions are available.

### Dashboard Filters
- Company (auto-scoped by RLS — non-configurable)
- Table Name (multi-select dropdown of auditable tables)
- User (searchable dropdown of all system users)
- Action Type (INSERT / UPDATE / DELETE)
- Date Range (default: last 30 days)
- Record ID (UUID text input for targeted forensic lookup)

### Data List Columns
| Column | Description |
| :--- | :--- |
| Timestamp (UTC) | Exact server time of the event |
| User Name | Linked from `users.id` |
| Table | Affected table name |
| Record ID | UUID of the row; clickable to navigate to the source record |
| Action | INSERT / UPDATE / DELETE badge |
| Before (JSON diff) | Highlighted JSON showing what changed, with deleted values in red |
| After (JSON diff) | Highlighted JSON showing what changed, with new values in green |

**Pagination Mandate:** Server-side pagination using Supabase `.range(from, to)`. Default page size: **50 records**. This table will contain billions of rows in a production ERP — client-side rendering of unfiltered results is architecturally prohibited. A filter (minimum: Date Range) must be applied before records can be fetched.

**Export:** Filtered CSV export for BIR examination evidence packages. Export is bounded to the active filter — a full table export without a date filter is blocked.
