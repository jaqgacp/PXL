# PXL ERP — Lovable Working Guide
**READ THIS FILE FIRST. DO NOT READ ANY OTHER FILE UNTIL THIS GUIDE TELLS YOU TO.**

---

## ⚠️ CRITICAL INSTRUCTION FOR LOVABLE

This project folder contains 30+ detailed blueprint files. **You must NOT read them all.** Reading every file wastes context and loses focus. Instead:

1. Read **only this file** to understand the project, the rules, and the current task.
2. Check the **Current Build Step** section below.
3. Read **only the specific blueprint file(s)** listed for that step.
4. Build what is specified. Nothing more, nothing less.
5. When done, report completion and wait for the next instruction.

---

## Project Identity

**PXL ERP** is a multi-tenant, Philippine-compliant accounting ERP built for accounting firms and SMEs. It handles the full accounting cycle: Sales → Purchasing → Inventory → Fixed Assets → Banking → Accounting → BIR Compliance → Financial Reports.

**This is not a consumer app. It is a professional ERP.** Every design and code decision must reflect enterprise-grade quality comparable to NetSuite, SAP Business One, or Microsoft Business Central.

---

## Tech Stack

| Layer | Technology |
| :--- | :--- |
| Framework | React + TypeScript (Lovable) |
| Styling | Tailwind CSS |
| Components | Shadcn UI (exclusively — no other component library) |
| Icons | Lucide React (exclusively — no other icon library) |
| Backend | Supabase (PostgreSQL + Auth + Storage + RLS) |
| Authentication | Supabase Auth — Google OAuth (Gmail) + Email/Password |
| Data Fetching | TanStack Query (`@tanstack/react-query`) |
| Forms | React Hook Form + Zod validation |
| State | Zustand (global context: company, branch, fiscal period) |
| Routing | React Router v6 |

---

## Current Build Step

> **DEVELOPER: UPDATE THIS SECTION AFTER EACH COMPLETED STEP.**
> Replace `→ CURRENT` with `✅ DONE` when a step is complete.
> Move `→ CURRENT` to the next step.

```
→ CURRENT:  S0.1 — Supabase + Google OAuth Setup
```

See `BUILD_ORDER.md` for the full sequence. The file to read for the current step is in the Reference Map below.

---

## Session Protocol (Follow Every Session)

```
STEP 1 — Read this file (LOVABLE_GUIDE.md). Understand current build step.
STEP 2 — Read ONLY the blueprint file(s) listed in the Reference Map for this step.
STEP 3 — Build exactly what is specified. Apply all Core Patterns below.
STEP 4 — Do not build anything not listed in the current step.
STEP 5 — Report: "Step [X] complete. Ready for [next step]."
```

If a blueprint file references another file for context (e.g., "see Chart of Accounts"), read only the specific section mentioned — do not read the entire referenced file.

---

## Reference Map

When the current build step is listed below, read **only** those specific files.

| Step | What to Build | Read These Files |
| :--- | :--- | :--- |
| S0.1 | Supabase setup, Google OAuth, multi-tenant auth | `02. Setup/01. Organization/01. Company Setup.md` |
| S0.2 | Login page, auth flow, session management | `UI_UX_PRINCIPLES.md` (Section 1 only) |
| S0.3 | App shell: fixed top nav, mega menu, page layout | `UI_UX_PRINCIPLES.md` (Section 2 only) + `02. Setup/01. Organization/01. Company Setup.md` |
| S0.4 | Shared component library | `UI_UX_PRINCIPLES.md` (Sections 3–7) |
| S1.1 | Company Setup CRUD | `02. Setup/01. Organization/01. Company Setup.md` |
| S1.2 | Branch Setup CRUD | `02. Setup/01. Organization/02. Branch Setup.md` |
| S1.3 | Department + Cost Centers | `02. Setup/01. Organization/03. Department Setup.md` + `04. Cost Centers.md` |
| S1.4 | Fiscal Years + Fiscal Calendar | `02. Setup/04. Accounting Setup/01. Fiscal Years.md` + `02. Fiscal Calendar.md` |
| S1.5 | Chart of Accounts | `02. Setup/04. Accounting Setup/03. Chart of Accounts.md` |
| S1.6 | Currency Setup + Exchange Rates | `02. Setup/04. Accounting Setup/04. Currency Setup.md` + `08. Exchange Rates.md` |
| S1.7 | Global Feature Enablement | `02. Setup/02. System Controls/03. Feature Settings/00. Global Feature Enablement.md` |
| S1.8 | Number Series (all 4 sub-modules) | `02. Setup/02. System Controls/01. Number Series/01. Sales Documents.md` (pattern applies to all 4) |
| S1.9 | Unified Approval Workflow | `02. Setup/02. System Controls/04. Approval Matrix/01. Unified Approval Workflow.md` |
| S1.10 | System Audit Log (read-only UI) | `02. Setup/System Audit Log.md` |
| S2.1 | Tax Codes (VAT, EWT, FWT, ATC) | `02. Setup/05. Tax Setup/02. Tax Codes.md` through `07. ATC Codes.md` |
| S2.2 | Compliance Profile | `02. Setup/01. Organization/07. Compliance Profile.md` |
| S2.3 | Tax Calendar | `02. Setup/05. Tax Setup/08. Tax Calendar.md` |
| S3.1 | Customers | `03. Master Data/01. Parties/01. Customers.md` |
| S3.2 | Suppliers | `03. Master Data/01. Parties/02. Suppliers.md` |
| S3.3 | Items + Services + Categories + UoM | `03. Master Data/02. Items & Services/` (all files) |
| S3.4 | Warehouses + Payment Terms | `03. Master Data/03. Inventory Master/` + `04. Shared/` |
| S4.1 | Dashboard (workspace-based) | `UI_UX_PRINCIPLES.md` (Principle 25 section) |
| S5.1 | Sales Invoices | `04. Sales/03. Transactions/04. Sales Invoices.md` |
| S5.2 | Receipts (Customer Payments) | `04. Sales/03. Transactions/06. Receipts.md` |
| S5.3 | Credit Memos + Debit Memos | `04. Sales/03. Transactions/07. Credit Memos.md` + `08. Debit Memos.md` |
| S5.4 | Sales Orders + Quotations | `04. Sales/03. Transactions/01. Quotations.md` + `02. Sales Orders.md` |
| S5.5 | Delivery Receipts + Customer Returns | `04. Sales/03. Transactions/03. Delivery Receipts.md` + `09. Customer Returns.md` |
| S5.6 | AR Aging + Customer Ledger | `04. Sales/02. Receivables/` (all files) |
| S5.7 | Sales Tax Review screens | `04. Sales/03. Tax Review/` (all files) |
| S5.8 | Sales Registers | `04. Sales/04. Registers/` (all files) |
| S6.1 | Vendor Bills (Purchase Invoices) | `05. Purchasing/03. Transactions/03. Vendor Bills.md` |
| S6.2 | Purchase Orders + Receiving Reports | `05. Purchasing/03. Transactions/01. Purchase Orders.md` + `02. Receiving Reports.md` |
| S6.3 | Payment Vouchers | `05. Purchasing/03. Transactions/05. Payment Vouchers.md` |
| S6.4 | Vendor Credits + Debit Memos | `05. Purchasing/03. Transactions/06. Vendor Credits.md` + `07. Debit Memos.md` |
| S6.5 | AP Aging + Supplier Ledger | `05. Purchasing/02. Payables/` (all files) |
| S6.6 | Purchasing Tax Review | `05. Purchasing/03. Tax Review/` (all files) |
| S7.1 | Petty Cash Fund + Vouchers | `07. Banking & Treasury/01. Petty Cash/01. Petty Cash Fund Setup.md` + `02. Petty Cash Vouchers.md` |
| S7.2 | Petty Cash Replenishment | `07. Banking & Treasury/01. Petty Cash/03. Petty Cash Replenishment.md` |
| S7.3 | Fund Transfers | `07. Banking & Treasury/02. Bank Operations/01. Fund Transfers.md` |
| S7.4 | Inter-Branch Transfers | `07. Banking & Treasury/02. Bank Operations/02. Inter-Branch Transfers.md` |
| S7.5 | Bank Adjustments | `07. Banking & Treasury/02. Bank Operations/03. Bank Adjustments.md` |
| S7.6 | Bank Reconciliation | `07. Banking & Treasury/02. Bank Operations/04. Bank Reconciliation.md` |
| S7.7 | Check Vouchers | `07. Banking & Treasury/03. Payables/01. Check Vouchers.md` |
| S8.1 | Asset Categories + Depreciation Profiles | `08. Fixed Assets/02. Setup/01. Asset Categories.md` + `02. Depreciation Profiles.md` |
| S8.2 | Asset Register | `08. Fixed Assets/01. Operations/02. Asset Register.md` |
| S8.3 | Asset Acquisition | `08. Fixed Assets/01. Operations/03. Asset Acquisition.md` |
| S8.4 | Depreciation Run | `08. Fixed Assets/01. Operations/04. Depreciation.md` |
| S8.5 | Disposal + Transfer + Impairment | `08. Fixed Assets/01. Operations/05. Disposal.md` + `06. Transfer.md` + `07. Impairment.md` |
| S9.1 | Journal Entries | `09. Accounting/01. Journal Entries/01. Journal Entries.md` |
| S9.2 | General Ledger Entries (inquiry) | `09. Accounting/01. Journal Entries/00. General Ledger Entries.md` |
| S9.3 | General Ledger + Trial Balance | `09. Accounting/02. Ledgers/` (all files) |
| S9.4 | Control Account Reconciliation | `09. Accounting/03. Subsidiary Ledgers/03. Control Account Reconciliation.md` |
| S9.5 | Amortization Schedules | `09. Accounting/04. Schedules/01. Amortization Schedules.md` |
| S9.6 | Period Management | `09. Accounting/05. Period Management/` (all files) |
| S10.1 | VAT Returns 2550M + 2550Q | `10. Compliance/02. VAT/06. VAT Return 2550M.md` + `07. VAT Return 2550Q.md` |
| S10.2 | SLSP + RELIEF Export | `10. Compliance/02. VAT/10. SLSP Export.md` + `11. RELIEF Export.md` |
| S10.3 | EWT Returns (1601EQ, QAP) | `10. Compliance/03. Withholding Tax/` (EWT files) |
| S10.4 | 2307 Certificates | `10. Compliance/03. Withholding Tax/10. 2307 Certificates Issued.md` + `11. 2307 Received.md` |
| S10.5 | 2306 Certificates | `10. Compliance/03. Withholding Tax/12. 2306 Certificates.md` |
| S10.6 | BIR Books | `10. Compliance/05. BIR Books/` (all files) |
| S10.7 | Income Tax forms | `10. Compliance/04. Income Tax/` (all files) |
| S10.8 | Audit & CAS screens | `10. Compliance/06. Audit & CAS/` (all files) |
| S11.1 | Financial Statements | `11. Reports/01. Financial Statements/` (all files) |
| S11.2–S11.5 | All remaining reports | `11. Reports/` (by sub-folder, one session per group) |

---

## Core Patterns (Apply to Every Screen — No Exceptions)

These are condensed rules. The full detail is in `UI_UX_PRINCIPLES.md`. You do not need to read that file unless you are building shared components for the first time (Step S0.4).

### Page Structure (Every Screen, Every Time)
```
Breadcrumb → Page Title + Toolbar → Quick Filters → Data Grid or Form → Pagination → Status Footer
```

### Data Table Rules
- Server-side pagination: Supabase `.range(from, to)`. Default page size: **50**.
- Table header: `text-xs font-medium uppercase tracking-wide bg-muted/50`
- Table row: `text-sm border-b hover:bg-muted/30`
- Amount columns: `text-right font-mono tabular-nums`
- Sticky header: `sticky top-0 z-10`
- Every table has: sort, filter, multi-select checkbox, export button, column chooser.

### Toolbar Button Order (Never Change This)
- **List page:** `[ + New ] [ ↑ Import ] [ ↓ Export ] [ ✓ Approve ] [ 🖨 Print ] [ ⋯ More ]`
- **Form page:** `[ 💾 Save ] [ 💾 Save & New ] [ ⧉ Duplicate ] [ 🗑 Delete ] [ ✕ Cancel ]`

### Status Badges (Always Use `<StatusBadge>` Component)
| Status | Color |
| :--- | :--- |
| `draft` | Gray outline |
| `for_approval` | Blue |
| `approved` | Blue filled |
| `posted` / `filed` | Green |
| `cancelled` / `rejected` / `voided` | Red |
| `pending` | Amber |
| `amended` | Purple |

### Form Section Layout
- Use Shadcn `Card` per section. Section titles: `text-sm font-semibold uppercase tracking-wide text-muted-foreground`
- Fields inside: `grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-4`
- Labels: `text-xs font-medium text-muted-foreground` above the input
- Inputs: `h-8 text-sm` (compact)
- Read-only / posted: `bg-muted text-muted-foreground cursor-not-allowed`

### Document Anatomy (Every Transactional Document)
```
Document Header (Number, Status Badge, Key Fields)
→ Line Items Table (editable grid)
→ Tabs: [ Details ] [ Posting Preview ] [ Attachments ] [ Comments ] [ Audit Trail ]
```

### Empty States (Never Blank)
Every empty list: icon + `"No [Entity] Found"` headline + `Create New` button.

### Error Messages (Always Specific)
Format: `"Cannot [action] [entity]. Reason: [specific cause]."`
Never: `"Error 500"` or `"Something went wrong."`

### Loading States
- Initial load: `Skeleton` rows (same height as real rows), `animate-pulse`
- Filter change: spinner in toolbar only, keep existing rows visible
- Form submit: disabled button with `<Loader2 className="animate-spin" />` inside

---

## Supabase Database Rules (Apply to Every Table)

Every table created in Supabase must follow these 5 rules without exception:

**Rule 1 — Multi-Tenant Isolation**
Every table has `company_id UUID NOT NULL REFERENCES companies(id)`. Every query filters by `company_id`. No exceptions.

**Rule 2 — Row-Level Security (RLS)**
RLS must be enabled on every table. Minimum policies:
```sql
-- Tenant isolation
CREATE POLICY "tenant_isolation" ON [table]
FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::UUID);
```
Posted/filed records add an additional immutability policy blocking UPDATE.

**Rule 3 — Composite Unique Constraints**
Document numbers are unique per company, not globally:
```sql
UNIQUE(company_id, document_number)
```

**Rule 4 — Audit Columns (Every Table)**
```
created_by UUID REFERENCES users(id)
updated_by UUID REFERENCES users(id)
created_at TIMESTAMPTZ DEFAULT NOW()
updated_at TIMESTAMPTZ DEFAULT NOW()
```

**Rule 5 — Immutability on Posted Records**
Transactional documents (invoices, journal entries, bank transactions) block UPDATE once `status = 'posted'` or `status = 'filed'`:
```sql
CREATE POLICY "immutable_when_posted" ON [table]
FOR UPDATE USING (status NOT IN ('posted', 'filed', 'cancelled'));

CREATE POLICY "no_delete" ON [table]
FOR DELETE USING (false);
```

---

## Authentication Architecture

### Supabase Auth Setup
- **Primary:** Google OAuth (Gmail) via Supabase Auth providers
- **Secondary:** Email + Password (Supabase email auth)
- **Multi-tenant:** After login, the user's `company_id` and `branch_id` are stored in the JWT custom claim and in Zustand global state (`useAuthStore`)

### JWT Custom Claims
The Supabase JWT must include:
```json
{
  "sub": "user-uuid",
  "company_id": "company-uuid",
  "branch_id": "branch-uuid",
  "role": "accountant"
}
```
These are set via a Supabase Edge Function or database hook on login.

### Auth Flow
```
Login (Google or Email)
  → Supabase Auth
    → Check if user has a company assignment (users_companies table)
      → If yes: set company context → redirect to Dashboard
      → If no: redirect to Company Setup (first-time setup wizard)
```

### Session Context Store (`useAuthStore` — Zustand)
```typescript
interface AuthStore {
  userId: string
  companyId: string
  companyName: string
  branchId: string
  branchName: string
  fiscalPeriodId: string
  role: string
}
```
All API calls inject `companyId` from this store. Never rely on user input for company context.

---

## Global Shared Components to Build First (Step S0.4)

Build these before any module. Every module depends on them.

| Component | Purpose |
| :--- | :--- |
| `<PageShell>` | Wraps every page: breadcrumb, title, toolbar slot, filter slot, content slot |
| `<DataTable>` | Generic server-paginated table with sort, filter, multi-select, export |
| `<StatusBadge status={}>` | Maps status string → colored Shadcn Badge |
| `<LookupDialog entity={}>` | Searchable popup for selecting records (Customer, Supplier, Item, GL Account) |
| `<FormSection title={}>` | Shadcn Card wrapper for form sections |
| `<EmptyState>` | Icon + headline + action buttons for empty lists |
| `<ConfirmDialog>` | Shadcn AlertDialog for destructive action confirmations |
| `<AuditTrailSection>` | Collapsible audit trail tab content for all documents |
| `<ContextBar>` | Top-nav context selector (Company / Branch / Fiscal Period) |
| `<MegaMenu>` | Top navigation mega menu (hover dropdowns per module) |
| `<AmountCell>` | Right-aligned, monospaced, formatted currency cell for tables |
| `<DateCell>` | Formatted date cell (muted, compact) for tables |

---

## What NOT to Do

- ❌ Do not read every file in the folder. Read only what this guide specifies.
- ❌ Do not use any component library other than Shadcn UI.
- ❌ Do not use any icon library other than Lucide React.
- ❌ Do not create tables without `company_id` and RLS.
- ❌ Do not build module-specific one-off components when a shared component already handles it.
- ❌ Do not allow UPDATE or DELETE on posted/filed documents.
- ❌ Do not show blank screens — always show skeleton loading or empty states.
- ❌ Do not hardcode company or branch IDs — always read from `useAuthStore`.
- ❌ Do not invent a new page layout — always use `<PageShell>`.
- ❌ Do not use `text-base` or larger as the default content font size. Use `text-sm`.

---

*PXL ERP — Lovable Working Guide v2.0 | Updated: 2026-06-28*
