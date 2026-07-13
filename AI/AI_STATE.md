# AI State

Last updated: 2026-07-13 (session 87 - PXL-DA-016 semantic transaction lifecycle events closed)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit standing is now **58 Retested Passed / 8 In Progress / 6 Open (72)** with **no Criticals open**. Session 86 closed **PXL-AUD-016** (universal number-series preflight; frontend-only) and **PXL-AUD-013 + PXL-DA-014** (JE `entry_class`, `fn_close_fiscal_year`, period locking, and Trial Balance Unadjusted/Adjusted/Post-Closing modes; `20260713000013` + test 040). Session 87 closed **PXL-DA-016** with governed `transaction_events` lifecycle evidence (`20260713000014` + test 041).

Hosted Supabase is synced through `20260713000014`. The CLI project-ref form is unsupported in this workspace, so pushes use the linked project. During hosted pushes and trusted resets, the two tracked held-out draft migrations are moved aside and restored checksum-clean:

- `supabase/migrations/20260710000004_atc_document_date_versioning.sql`
- `supabase/migrations/20260710000005_cas_numbering_void_dat_controls.sql`

The held-out draft test remains excluded from trusted pgTAP runs:

- `supabase/tests/027_cas_end_to_end_controls_test.sql`

## Current Active Task

**AIQ-017 - PXL Accounting Core Ready** remains active. Do not create new UI standards, implement report pilots, roll out more transaction workspaces, or build dashboards. Continue hardening the accounting/tax core under DEC-017 and DEC-018.

The governed posting-behavior reference is `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md`; the active readiness plan is `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md`.

## Verification State

- Session 87: `20260713000014_transaction_events.sql` + `supabase/tests/041_transaction_events_test.sql` (TRANSACTION-EVENTS-001, 14 assertions) passed. Held-out-safe `supabase db reset --local` passed; focused tests 025+030 passed 51/51; full trusted pgTAP passed **751/751 across 40 files** with held-out test 027 aside. `npm run gen:types` and trusted-baseline schema summary regenerated (244 functions / 20 views / 152 tables / 250 triggers). `npm run lint`, `npm run build`, `scripts/check_docs_consistency.sh`, and `git diff --check` passed. Hosted Supabase migration list shows local = remote through `20260713000014`.
- Session 86: committed as `38ac28a` ("Add financial close readiness controls"). Held-out-safe full pgTAP passed **737/737 across 39 trusted files**; build, zero-warning lint, generated types, schema summary, and docs gate were green. Hosted Supabase was synced through `20260713000013` before session 87.
- Docs gate after DA-016 updates: `scripts/check_docs_consistency.sh` passed with 72 findings and 41 test files.

## Known Boundaries

- The two held-out draft migrations and held-out test 027 are tracked files but are not part of trusted replay/push evidence. Do not adopt or repair them unless explicitly asked.
- `transaction_events` now provides the semantic lifecycle stream, but broad per-document Activity Timeline UI wiring remains under PXL-AUD-050.
- Optional close follow-ups remain backlog: a Period-Close UI over `fn_close_fiscal_year`, an optional Income-Summary close, and configurable FS-line mappings.
- Optional tax setup follow-ups remain backlog: admin successor-management UI for VAT/PT versions and document-date resolver usage in frontend ATC/VAT pickers.

## Next Recommended Step

Continue AIQ-017 in this order: **PXL-AUD-043** (EWT on cash purchases / withholding on advances), **PXL-AUD-040** (per-month Form 2307 breakdown), **PXL-AUD-046** (cash-sale receipt total semantics), **PXL-AUD-047** (2307-received claim lifecycle), then remaining In-Progress coverage/report items (AUD-008/009/010, DA-013/018/020, AUD-044/045/049/050).

## Decisions Needed From User

None. DEC-008 standing autonomy remains active. DEC-017 records the accounting-core-first priority pivot and DEC-018 records `PXL_ACCOUNTING_RULES_MATRIX.md` as the governed posting source of truth.
