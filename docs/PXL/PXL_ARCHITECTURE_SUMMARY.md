# PXL Architecture Summary

Concise, stable architecture reference for PXL. Read this instead of scanning the repository. For rules, see `docs/PXL/PXL_PRINCIPLES.md`; for current build status, see `docs/PXL/STATUS.md`; for per-transaction behavior, see `docs/PXL/PXL_TRANSACTION_MATRIX.md`.

## What PXL Is

PXL is an accounting-first, Philippine-compliance-first ERP for multi-company use. Every operational document (sales, purchasing, inventory, banking, fixed assets) resolves into balanced double-entry journal entries in the General Ledger, and compliance outputs (VAT, percentage tax, EWT/FWT, Form 2307/2306, SAWT/QAP, SLSP/RELIEF, income tax, BIR books, CAS) are generated from posted data. Correctness, auditability, and BIR compliance override speed and novelty.

## Stack

- **Frontend:** React 19 + TypeScript + Vite, Tailwind CSS v4, shadcn/Base UI components, react-router-dom v7, TanStack Query, Zustand, react-hook-form + Zod, PapaParse for CSV.
- **Backend:** Supabase — PostgreSQL, PostgREST, GoTrue Auth (Google OAuth PKCE + email/password), Row Level Security.
- **No custom server:** all business logic lives in PostgreSQL (tables, views, triggers, SECURITY DEFINER RPCs) behind Supabase; the React app talks to it via `@supabase/supabase-js`.
- **No Claude/Anthropic API integration exists** in the application code.

## Repository Layout

```
AI/                    — AI Operating System (see AI/README.md)
docs/PXL/              — source-of-truth documentation (numbered module folders + summary docs)
src/pages/             — one React page per ERP screen (lazy-loaded routes)
src/components/        — AppShell, ErrorBoundary, GLImpactPanel, SetupReadiness, ui/ shared library
src/lib/               — supabase client, company/branch/session context, setup readiness, utils
supabase/migrations/   — numbered SQL migrations: schema, RLS, RPCs, views, triggers (source of truth for behavior)
supabase/tests/        — pgTAP tests for accounting/tax/security-critical flows
public/_headers        — production HTTP security headers (CSP)
```

## Core Architectural Patterns

1. **Multi-tenancy via company scope + RLS.** Every company-owned table has `company_id`. Access is enforced by RLS policies using `is_company_member(company_id)` / `can_admin_company(company_id)` against `user_company_memberships (user_id, company_id, role)`. UI filtering is never the security boundary. (See `AI/AI_DECISIONS.md` DEC-003.)
2. **Document lifecycle via SECURITY DEFINER RPCs.** Documents move draft → approved → posted → cancelled (or module equivalent) only through `fn_*` RPCs with `SET search_path = public`, which validate membership, recompute amounts server-side, and enforce transitions. Direct multi-round-trip writes are not used for saves or status changes.
3. **Posting creates real journal entries.** Posting RPCs write balanced `journal_entries` / `journal_entry_lines` rows using account mappings from `company_accounting_config` and master-data account determination — the user never picks GL accounts on transactions. Every JE links back to its source document (`source_type`, `source_document_id`) for infinite drill-down.
4. **Immutable accounting.** Posted records are never edited or deleted; corrections go through reversal, void, credit/debit memo, or supersede workflows, preserving the audit trail. (DEC-002.)
5. **Controlled number series.** Document numbers come from `fn_next_document_number` (per company, branch, document type) with row locking; voided numbers are never reused. (DEC-006.)
6. **Audit everything.** `trg_audit_*` triggers write before/after JSONB states to append-only `sys_audit_logs` on master data, transactions, and system parameters; CAS pages expose these logs.
7. **Tax profile drives compliance.** The company tax profile and tax applicability configuration gate which tax codes, returns, dashboards, and exports are available (VAT vs non-VAT, withholding-agent status, etc.). Tax rates and ATC codes live in reference tables, never hardcoded. (DEC-005.)
8. **Metadata-driven configuration.** Feature enablement, number series, approval workflows, and posting configuration are data, managed through Setup pages, not code branches.

## Data Flow

Source document (e.g. sales invoice) → save RPC (server-side VAT/EWT computation) → approval → posting RPC → balanced JE → GL / Trial Balance / Financial Statements, subsidiary ledgers (AR/AP/inventory/assets), and tax ledgers → compliance working papers, returns, certificates, and BIR books — all read from posted data, never parallel bookkeeping.

## Where Behavior Is Defined

- **Schema, RLS, RPCs, views, triggers:** `supabase/migrations/*.sql`, applied in filename order. Migrations are the executable source of truth; `docs/PXL/STATUS.md` tracks which are applied.
- **Expected accounting/tax behavior:** `docs/PXL/PXL_TRANSACTION_MATRIX.md` (per transaction) and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (test scenarios).
- **Open production-hardening work:** `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`.
- **Executable regression tests:** `supabase/tests/NNN_*_test.sql` (pgTAP) covering critical flows, aging as-of, vendor credit controls, non-VAT gating, EWT partial payments, 2307 generation/supersede, VAT-ledger-to-GL reconciliation, GL reversal visibility, and role-based access.

## Commands

```bash
npm run dev       # Vite dev server (needs .env with VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY)
npm run build     # tsc -b && vite build
npm run lint      # oxlint
npm test          # supabase test db — runs pgTAP tests against local Supabase
supabase db push  # apply migrations (hosted: link project first, then use --linked)
```

## Related Documents

- `docs/PXL/PXL_PRINCIPLES.md` — the 27-principle engineering constitution.
- `docs/PXL/STATUS.md` — build/migration status per module and page.
- `docs/PXL/UI_UX_PRINCIPLES.md` — UI standards and navigation tree.
- `AI/AI_CONTEXT_INDEX.md` — which documents to load per work mode.
- `AI/AI_DECISIONS.md` — why the architecture is this way.
