# AI State

Last updated: 2026-07-03

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 39 (2026-07-03) continued PXL-DA-015 with the books slice: `20260703000009_report_snapshots_books_exports.sql` adds `fn_snapshot_books_export`, covering all seven BIR books (sales/purchase journals, cash receipts book gross of CWT, cash disbursements book net of EWT, balance-gated general journal, cash sales/purchases journals) with the frozen-rows contract: server-built payload, versioned `BOOKS_*` snapshot with SHA-256 hash, server-attested `cas_export_log` row, and the returned rows are what the page writes to the file. Every compliance export surface now snapshots; only the snapshot reader/drilldown UI remains under PXL-DA-015. Findings standing is 19 Retested Passed / 15 In Progress / 14 Open (48 findings); 11 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010` and `20260703000001` through `20260703000009` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in this workspace. Run `supabase db push --linked` from a tokened workspace, then verify with `supabase migration list --linked`.
- PXL-DA-015: every export surface snapshots (VAT returns, Form 2307, SLSP/RELIEF, SAWT/QAP, CAS DAT, seven BIR books). Remaining work is the snapshot reader/drilldown UI.

## Last Files Changed

Books export snapshot session (session 39, 2026-07-03):

- `supabase/migrations/20260703000009_report_snapshots_books_exports.sql` (new: `fn_snapshot_books_export` for all seven BIR books)
- `supabase/tests/018_books_export_snapshots_test.sql` (new: BOOKS-EXPORT-SNAP-001, 13 assertions)
- The seven `src/pages/Books*Page.tsx` journal pages (files rendered from the RPC's frozen rows)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (BOOKS-EXPORT-SNAP-001 scenario)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-015 index/detail refreshed; session 39 log row)
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` (new BIR Books of Accounts Export row)
- `docs/PXL/STATUS.md` (test count and pending migrations refreshed)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated)

## Last Known Errors

None. Fresh `supabase db reset --local` replay passed through `20260703000009`; `npm test` passed 285/285 across 18 files; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Session 31 landed as `8425d56` (CI 28634813215 green); session 32 as `f88a595` (CI 28636237029 green). Sessions 33-36 landed together as `d88f0df` (CI 28645009697 green). Session 37 landed as `9110765` (CI 28645835919 green). Session 38 landed as `0f9ab83` (2026-07-03); CI run 28648390569 passed both jobs, verified via `gh run watch --exit-status`.

## Next Recommended Step

Continue AIQ-008 by building the snapshot reader/drilldown UI (the last PXL-DA-015 implementation piece; all six snapshot families exist through `20260703000009`). Do not redo any existing snapshot slice. PXL-DA-017 dimension propagation remains the next unblocked accounting architecture alternative.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
