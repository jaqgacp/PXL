# AI State

Last updated: 2026-07-04

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 43 (2026-07-04) closed PXL-DA-011 and PXL-AUD-005: `20260704000002_status_immutability.sql` adds generic status-aware guards — `fn_guard_doc_lines` (18 line tables) and `fn_guard_doc_header` (34 header tables, diff-based: business columns freeze once a document leaves its editable statuses; only status/updated stamps/per-table lifecycle metadata may change; DELETE blocked per DEC-002; posted schedule entries fully frozen). The same-transaction construction exception (`fn_row_written_by_current_txn`: visible row + xmin in progress ⇒ ours; works under subtransactions) keeps every posting writer and the CM/DM apply RPCs working while PostgREST single-transaction clients can never satisfy it. IMMUT-001 (`supabase/tests/020_status_immutability_test.sql`, 25 assertions, COMMITs fixtures to tamper cross-transaction) executed passing; `npm test` 324/324 across 20 files. Session 42 delivered generated DB types + typed client (PXL-AUD-029/030). Findings standing is 25 Retested Passed / 13 In Progress / 12 Open (50 findings); 8 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is fully in sync through migration 20260704000001 (pushed and verified 2026-07-04 via `supabase migration list --linked`; user supplied the access token in-session, `link` + `db push --linked --yes`). Note: `db push` emits harmless pg-delta CA-cert errors from the drift-check feature; migrations apply anyway — verify with `migration list --linked`, not the push output.
- PXL-AUD-029 (Open, Medium): `AppShell` feature gating fails open — small query fix pending.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

Status-aware immutability session (session 43, 2026-07-04):

- `supabase/migrations/20260704000002_status_immutability.sql` (new: `fn_row_written_by_current_txn`, `fn_guard_doc_lines`, `fn_guard_doc_header`, 18 line-guard + 34 header-guard triggers)
- `supabase/tests/020_status_immutability_test.sql` (new: IMMUT-001, 25 assertions; intentionally COMMITs fixtures — always reset before `npm test`)
- `src/lib/database.types.ts` (regenerated)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated: 149 functions, 202 triggers)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (IMMUT-001 scenario)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-011 + PXL-AUD-005 Retested Passed; standing; session 43 log row)

## Last Known Errors

None. `npm test` 324/324 across 20 files on a fresh `supabase db reset --local` (replay through `20260704000002`); `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

IMPORTANT for future migrations: the PXL-DA-011 guards fire for superuser too — data backfills that rewrite non-draft documents or their lines need `SET session_replication_role = replica` (or targeted `ALTER TABLE ... DISABLE TRIGGER`) around the backfill. New lifecycle columns on guarded tables must be added to that table's allowlist in the guard trigger definition.

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (CI 28699881597 green). Session 41 landed as `cb1fc3e` (2026-07-04); CI run 28701028419 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000001` pushed to hosted and verified via `supabase migration list --linked`. Session 42 landed as `bb6d96c` (2026-07-04); CI run 28706337718 completed successfully, verified via `gh run watch --exit-status`; no migrations in that session, hosted unchanged. Session 43 landed as `ba74c14` (2026-07-04); CI run 28707527259 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000002` pushed to hosted and verified via `supabase migration list --linked`.

## Next Recommended Step

Continue AIQ-008 with the next Critical: PXL-DA-001 (server-side GL preview RPC, In Progress), PXL-DA-002 (drilldown contracts, Open), or PXL-DA-004 (posting-engine consolidation, Open). Run `npm run gen:types` after every migration. Do not redo PXL-DA-011, PXL-AUD-005, PXL-DA-015, PXL-DA-017, PXL-AUD-029, or PXL-AUD-030.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
