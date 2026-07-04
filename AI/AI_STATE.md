# AI State

Last updated: 2026-07-04

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 41 (2026-07-04) CLOSED PXL-DA-017 per DEC-011: `20260704000001_je_line_dimensions.sql` adds `branch_id`/`department_id`/`cost_center_id` to `journal_entry_lines`, welds line company to JE company, inherits the header branch centrally in a BEFORE trigger (all 34 JE writers covered without per-writer changes), validates every dimension's company, backfills existing lines, makes `vw_general_ledger.branch_id` line-accurate (`COALESCE(line, header)`, same position — Branch P&L upgraded transparently) with line dept/cc appended, lets `fn_post_manual_je` take per-line dimensions, and makes `fn_reverse_je` preserve them. Scenario JE-DIMS-001 (14 assertions). Session 40 closed PXL-DA-015 (snapshot reader UI). Findings standing is 21 Retested Passed / 14 In Progress / 14 Open (49 findings); 10 Criticals remain. PXL-AUD-029 (Medium, AppShell feature gating fails open) is the small open UI-integrity fix.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is fully in sync through migration 20260703000009 (pushed and verified 2026-07-04 via `supabase migration list --linked`; user supplied the access token, `link` + `db push --linked --yes`). Spot-checked hosted: `report_snapshots` responds 200 and `fn_snapshot_books_export` exists (access guard fires for non-members). Note: `db push` emitted harmless pg-delta CA-cert errors (`pgdelta-target-ca.crt` ENOENT) from the drift-check feature; migrations applied anyway — verify with `migration list --linked`, not the push output.
- PXL-AUD-029 (Open, Medium): `AppShell` feature gating fails open — small query fix pending.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

JE line dimensions session (session 41, 2026-07-04):

- `supabase/migrations/20260704000001_je_line_dimensions.sql` (new: line dims, guards, backfill, view, manual JE/reversal dims)
- `supabase/tests/019_je_line_dimensions_test.sql` (new: JE-DIMS-001, 14 assertions)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (JE-DIMS-001 scenario)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-017 Retested Passed; standing; session 41 log row)
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` (Manual JE row: DEC-011 dimension note)
- `docs/PXL/STATUS.md` (19 test files / 299 assertions)
- `docs/PXL/PXL_PRODUCT_BACKLOG.md` (Dimension summary row readiness refreshed)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated)

## Last Known Errors

None. `npm test` 299/299 across 19 files on a fresh `supabase db reset --local` (replay through `20260704000001`); `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 37 landed as `9110765` (CI 28645835919 green). Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (2026-07-04); CI run 28699881597 completed successfully, verified via `gh run watch --exit-status`.

## Next Recommended Step

Continue AIQ-008 with the next Critical: PXL-DA-001 (server-side GL preview RPC, In Progress) or PXL-DA-011 (status-aware immutability on every transactional header/line table, Open). PXL-AUD-029 remains the small self-contained `AppShell` query fix. Do not redo PXL-DA-015 (snapshots + reader UI) or PXL-DA-017 (JE line dimensions).

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
