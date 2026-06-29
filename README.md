# PXL — Philippine Accounting ERP

React 18 + TypeScript + Vite frontend backed by Supabase (PostgreSQL + PostgREST + Auth + RLS).

---

## Stack

| Layer | Technology |
|---|---|
| Frontend | React 18, TypeScript, Vite 8, Tailwind CSS v4 |
| Backend | Supabase (PostgreSQL 15, PostgREST, GoTrue Auth) |
| Routing | react-router-dom v7 (BrowserRouter) |
| CSV parsing | PapaParse |
| Auth | Supabase OAuth (Google PKCE flow) |

---

## Local Setup

### 1. Prerequisites

- Node.js 20+
- A Supabase project (free tier is fine)

### 2. Clone and install

```bash
git clone <repo-url>
cd PXL
npm install
```

### 3. Environment variables

Copy `.env.example` to `.env` and fill in your Supabase credentials:

```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

The app validates these at startup and throws a clear error if either is missing.

### 4. Apply migrations

Run all migrations in order against your Supabase project:

```bash
# Using Supabase CLI
supabase db push

# Or apply manually via Supabase SQL editor in migration order:
# 001_initial_schema.sql through to the latest migration
```

### 5. Start the dev server

```bash
npm run dev
```

---

## Authentication

- Google OAuth via Supabase Auth (PKCE flow)
- Redirect URL is dynamic: `window.location.origin + /auth/callback`
- The `/auth/callback` route handles the PKCE code exchange
- No hardcoded redirect URLs — works in any environment

---

## Database Migrations

Migrations live in `supabase/migrations/` and are numbered sequentially:

| Migration | Description |
|---|---|
| 001–003 | Core schema: companies, branches, COA, master data |
| 004 | Schema fixes (atc_codes column renames: `atc_code→code`, `tax_type→tax_category`) |
| 005–007 | Sales, AR, Compliance modules |
| 008 | RLS hardening: user_company_memberships, write policies |
| 009 | RLS reads scope: remove auto-grant-all, scope SELECT policies to membership |
| 010 | Atomic save/post RPCs: fn_save_sales_invoice, fn_post_sales_invoice, fn_save_receipt, etc. |
| 011 | Audit triggers: automatic DB-level logging to sys_audit_logs |
| 012 | Number series hardening: search_path fix, membership check, restricted EXECUTE grant |

---

## Security Model

### Multi-tenancy

- Every user belongs to one or more companies via `user_company_memberships (user_id, company_id, role)`
- Roles: `owner`, `admin`, `member`, `viewer`
- `is_company_member(company_id UUID) RETURNS boolean` — used in all RLS policies
- `can_admin_company(company_id UUID) RETURNS boolean` — used for destructive company-level actions
- When a user creates a company, they are automatically granted `owner` via a trigger

### Row Level Security

- All tables have RLS enabled
- **SELECT**: scoped to `is_company_member(company_id)` on every company-owned table
- **INSERT**: `WITH CHECK (is_company_member(company_id))` on all transactional tables
- **UPDATE/DELETE**: `USING (is_company_member(company_id))` on all transactional tables
- Global BIR reference tables (`tax_codes`, `vat_codes`, `atc_codes`) allow reads and writes by any authenticated user
- User dashboard data is scoped to `user_id = auth.uid()`

### SECURITY DEFINER RPCs

All status transitions and atomic saves use `SECURITY DEFINER` functions with `SET search_path = public`:

| Function | Purpose |
|---|---|
| `fn_save_sales_invoice(id, header, lines)` | Atomic header+lines save, number generation, fiscal period resolution |
| `fn_approve_sales_invoice(id)` | draft → approved |
| `fn_post_sales_invoice(id)` | approved → posted (GL stub for Sprint 9) |
| `fn_void_sales_invoice(id, reason_id, memo)` | Any status → cancelled (BIR: numbers never reused) |
| `fn_save_receipt(id, header, lines)` | Atomic receipt + lines save |
| `fn_post_receipt(id)` | draft → posted (GL stub) |
| `fn_bounce_receipt(id)` | posted → bounced (dishonoured cheque) |
| `fn_next_document_number(company, branch, code)` | Sequential number generation with row-level locking |

### Content Security Policy

- **Development**: set via `vite.config.ts` `server.headers` (includes `unsafe-eval` for Vite HMR)
- **Production**: set via `public/_headers` (Netlify/Cloudflare) — stricter, no `unsafe-eval`

---

## Accounting Posting Model

Documents follow a strict lifecycle enforced by SECURITY DEFINER RPCs:

```
Sales Invoice:  draft → approved → posted → cancelled
Receipt:        draft → posted → bounced
                                → cancelled
```

**Posting does not create real GL journal entries yet.** The stub comment in each post RPC documents the intended entry:

- **Sales Invoice post**: DR Accounts Receivable / CR Revenue accounts / CR VAT Payable
- **Receipt post**: DR Cash or Bank / DR EWT Withheld (if applicable) / CR Accounts Receivable

GL journal entry creation is planned for Sprint 9 (General Ledger module).

---

## Module Completion Criteria

A module is considered complete when:

1. List view with search, filter, and pagination
2. Create / Edit form with all BIR-required fields
3. Atomic save via SECURITY DEFINER RPC (no multi-round-trip direct writes)
4. Status lifecycle enforced by RPCs (draft → approved → posted → cancelled or equivalent)
5. Audit log entries written automatically by `trg_audit_*` triggers
6. RLS policies enforce company membership on all reads and writes
7. Document number generated via `fn_next_document_number` (per branch, per document type)

---

## Project Structure

```
src/
  pages/          — one file per ERP module
  components/
    AppShell.tsx  — nav sidebar + top bar, react-router-dom
    ErrorBoundary.tsx
    ui/shared.tsx — StatusBadge, AmountCell, DateCell
  lib/
    supabase.ts   — Supabase client with ENV validation
    context.tsx   — companyId, session, branchId context
supabase/
  migrations/     — numbered SQL migration files
public/
  _headers        — production HTTP security headers
```

---

## BIR Compliance Notes

- **Voided documents**: SI numbers are never reused (cancelled numbers are not rolled back in the number series)
- **Withholding tax**: CWT tracked per receipt line with ATC code; EWT working papers computed from posted receipts
- **VAT**: Output VAT captured per SI line with VAT code (regular / zero-rated / exempt)
- **Form 2307**: CWT certificates tracked in `form_2307_tracking`
- **Tax calendar**: Due dates for BIR filings managed in `tax_calendar_events`
