# AI State

Last updated: 2026-07-02

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.0.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 27 (RLS-ROLES-001 role-based access test + PXL-AUD-026 authenticated table grants) was verified and landed 2026-07-02: fresh `supabase db reset --local` replay clean, `npm test` 165/165 across 11 files, build/lint pass. The user reprioritized audit fixes above the remaining summary docs (AIQ-005–007).

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` now exists):
  - `docs/PXL/PXL_SCHEMA_SUMMARY.md`
  - `docs/PXL/PXL_ACCOUNTING_RULES.md`
  - `docs/PXL/PXL_TAX_RULES_PH.md`
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue); no Supabase access token exists in this workspace, so `supabase migration list --linked` cannot be run here.

## Last Files Changed

- `supabase/migrations/20260702000008_authenticated_table_grants.sql` (landed: PXL-AUD-026 fix)
- `supabase/tests/011_role_based_access_test.sql` (landed: RLS-ROLES-001, 16 assertions)
- `supabase/tests/004/007/010_*.sql` (denial assertions rewritten to effect-based checks)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-AUD-026 detail, PXL-AUD-004 evidence, Fix Session Log row 27)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (RLS-ROLES-001 scenario documented)
- `AI/AI_WORK_QUEUE.md`, `AI/AI_STATE.md`, `AI/AI_HANDOFF.md` (session bookkeeping)

## Last Known Errors

None. `npm test` 165/165 across 11 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only.

## Next Recommended Step

AIQ-008 continuation per audit log session 27: VAT report standardization on the tax ledger (PXL-AUD-014/PXL-DA-008) or `can_perform` role/action RPC enforcement (PXL-DA-003).

## Open Questions / Decisions

- Decide whether future autonomous agents should be allowed to open pull requests automatically or only prepare local changes.
- Decide whether `AI/AI_WORK_QUEUE.md` should be manually curated by the user or automatically maintained by agents after every session.
- Decide when to implement actual Claude API `cache_control` support if a Claude/Fable wrapper is later added.
