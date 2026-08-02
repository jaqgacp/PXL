# PXL — Philippine Accounting ERP

**Status:** Active human repository landing page
**Authority:** Tier 3 Repository Orientation; domain standards and executed behavior prevail
**Last Reviewed:** 2026-07-18 documentation cleanup
**Applies To:** Human setup, stack overview, and repository orientation
**Read When:** Starting local development or looking for commands
**Do Not Read For:** AI startup, official findings, or domain authority

React 19 + TypeScript + Vite frontend backed by Supabase (PostgreSQL + PostgREST + Auth + RLS).

## Orientation — read this first

**The goal.** A Philippine business runs its real books on PXL. A valid business
transaction produces the correct subsidiary ledger, General Ledger, trial
balance, financial statements, BIR tax and books effect, and audit trail — with
no parallel bookkeeping and nothing that can be quietly altered.

**Where we are.** The accounting core is genuinely strong: one enforced doorway
into the ledger, a fully enforced kernel guard, certified tenant isolation, audit
immutability, document numbering and dimensional accounting, a trial balance that
balances exactly, and inventory that reconciles to its control account. Against
that: **no business module is certified**, there is no Tax Engine, there is no way
to load opening balances, there is no proven backup, and about 30 screens are
scaffolds marked **Not built** in the menu. PXL is **internal QA and demo only —
not pilot-ready, not production-ready.**

**What is next.** Prove backup and restore. It is the cheapest remaining unblock,
it gates every module, and it is not software. Then hosted parity.

**Where the detail lives — one place each, never duplicated:**

| Question | Authority |
|---|---|
| What is PXL? | `docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` |
| Where are we, what is next? | `AI/AI_STATE.md` — **the only status authority** |
| What is the complete plan to finish? | `docs/PXL/01. Architecture/PXL_DELIVERY_PLAN.md` |
| In what order / dependency detail? | `docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` |
| Starting a new AI session? | `AI/ONBOARDING_PROMPT.md` — copy-paste front door |
| What is broken? | `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` |
| How do we work / when is it done? | `docs/PXL/00. Governance/PXL_HOW_WE_WORK.md` |
| Where is everything else? | `docs/PXL/PXL_DOCUMENTATION_INDEX.md` |

AI agents start with `AI/AGENT_SYSTEM_PROMPT.md`, then `AI/AI_STATE.md`, and open
only what the active task names.

**Two rules that keep this repository honest.** Status facts live in
`AI/AI_STATE.md` and nowhere else — a second copy always drifts and becomes a trap
for the next session. And no governance document may be created in a commit that
contains no application or SQL change.

Validate with `npm run docs:check`.

---

## Stack

| Layer | Technology |
|---|---|
| Frontend | React 19, TypeScript, Vite 8, Tailwind CSS v4 |
| Backend | Supabase (PostgreSQL 17, PostgREST, GoTrue Auth) |
| Routing | react-router-dom v7 (BrowserRouter) |
| Data fetching | `@supabase/supabase-js`, with generated TypeScript DB types |
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

Run all migrations in filename order against your Supabase project:

```bash
# Using Supabase CLI
supabase db push --linked

# Or apply manually via Supabase SQL editor in filename order.
```

### 5. Start the dev server against the LOCAL database

```bash
npx supabase start        # local Postgres + auth + REST
npm run test:canonical    # load the demo dataset (optional, gives you data to look at)
npm run dev:login         # set a password on the local demo users
npm run dev               # http://localhost:5173
```

Sign in with `demo.admin@pxl.local` / `pxl-dev-password`.

**In a Codespace or other remote workspace, `localhost:5173` will not open.**
`localhost` in your browser is your own machine, not the container. Use the
forwarded URL instead — VS Code shows it in the **Ports** panel, and it looks
like `https://<codespace-name>-5173.app.github.dev`.

If port 5173 has not appeared in the Ports panel, ask Codespaces to create and
open its private forward:

```bash
"$BROWSER" http://localhost:5173
```

Only port 5173 needs forwarding. The dev server proxies Supabase at `/supabase`
on its own origin (`VITE_SUPABASE_URL=/supabase`), so the browser never needs to
reach the container's `127.0.0.1:54321`. That avoids forwarding a second port,
widening the CSP, or exposing an API endpoint publicly.

**Point dev at local, not hosted.** `.env.local` targets the hosted project, which
is intentionally behind (see the Deploy Runbook). `.env.development.local` targets
the local stack through `/supabase` and wins in dev mode, so `npm run dev` runs
the current build against a database that has every migration. Running the
current frontend against hosted would fail on everything built since 2026-07-16.

Re-run `npm run dev:login` after any database reset — a reset restores the seeded
users and clears their password.

---

## Authentication

- Google OAuth via Supabase Auth (PKCE flow)
- Redirect URL is dynamic: `window.location.origin + /auth/callback`
- The `/auth/callback` route handles the PKCE code exchange
- No hardcoded redirect URLs — works in any environment

---

## Database Migrations

Migrations live in `supabase/migrations/` and are applied in filename order. The generated schema summary below is the authoritative map of the current migration chain; avoid copying a migration count or endpoint into operational instructions because both change during hardening work.

For the current object-by-object schema map, use the generated summary in `docs/PXL/01. Architecture/PXL_SCHEMA_SUMMARY.md`. Regenerate it after migration changes with:

```bash
scripts/gen_schema_summary.sh
```

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
- Global BIR reference tables (`tax_codes`, `vat_codes`, `atc_codes`) allow reads by any authenticated user; writes require company admin role (`is_any_company_admin()`)
- Global BIR form configuration writes are governed by company-admin policy (`PXL-AUD-063`, closed).
- User dashboard data is scoped to `user_id = auth.uid()`

### SECURITY DEFINER RPCs

All status transitions and atomic saves use `SECURITY DEFINER` functions with `SET search_path = public`:

| Function | Purpose |
|---|---|
| `fn_save_sales_invoice(id, header, lines)` | Atomic header+lines save; server-side VAT/net recomputation; rejects non-draft edits |
| `fn_approve_sales_invoice(id)` | draft → approved |
| `fn_post_sales_invoice(id)` | approved → posted; requires company_accounting_config; creates balanced JE |
| `fn_revert_si_to_draft(id)` | approved → draft; clears approval record |
| `fn_void_sales_invoice(id, reason_id, memo)` | Any status → cancelled (BIR: numbers never reused) |
| `fn_save_receipt(id, header, lines)` | Atomic receipt + lines save; over-application guard per invoice |
| `fn_post_receipt(id)` | draft → posted; requires company_accounting_config; creates balanced JE |
| `fn_bounce_receipt(id)` | posted → bounced (dishonoured cheque) |
| `fn_save_credit_memo(id, header, lines, status)` | Atomic save + status transition; server-side computation |
| `fn_save_debit_memo(id, header, lines, status)` | Atomic save + status transition; server-side computation |
| `fn_mark_tax_event_filed(event_id, date_filed, efps_ref)` | Validates membership; marks tax calendar event as filed |
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

**Posting creates real, balanced double-entry journal entries** stored in `journal_entries` / `journal_entry_lines`.
Before posting is allowed, each company must configure GL accounts in `company_accounting_config`:

| Account | Used for |
|---|---|
| `ar_account_id` | Debit (SI post), Credit (receipt post) |
| `vat_payable_account_id` | Credit (SI post, for VAT portion) |
| `ewt_withheld_account_id` | Debit (receipt post, for CWT amount) |
| `default_cash_account_id` | Debit (receipt post, when no bank account on receipt) |

- **Sales Invoice post**: DR AR = total_amount; CR Revenue per line = net_amount; CR VAT Payable = vat_amount
- **Receipt post**: DR Cash/Bank = total_amount; DR EWT Withheld = total_cwt; CR AR = total_amount + total_cwt

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
