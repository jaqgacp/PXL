# AI State

Last updated: 2026-07-02

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.0.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

Work through the Context-mode summary docs in `AI/AI_WORK_QUEUE.md` (AIQ-005 next) so future sessions load concise summaries instead of large folders.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` now exists):
  - `docs/PXL/PXL_SCHEMA_SUMMARY.md`
  - `docs/PXL/PXL_ACCOUNTING_RULES.md`
  - `docs/PXL/PXL_TAX_RULES_PH.md`
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Uncommitted pre-existing work in the tree (not from AI-docs sessions): modified `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` and three supabase tests, plus untracked `supabase/migrations/20260702000008_authenticated_table_grants.sql` and `supabase/tests/011_role_based_access_test.sql`. Do not discard; ask the user before committing.

## Last Files Changed

- `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` (new: AIQ-004 concise architecture summary)
- `AI/AI_CONTEXT_INDEX.md` (architecture summary no longer listed as missing)
- `AI/AI_CACHE_CONTEXT_PLAN.md` (weak-docs table row updated)
- `AI/AI_WORK_QUEUE.md` (AIQ-004 → Done; next task AIQ-005)
- `AI/AI_STATE.md`, `AI/AI_HANDOFF.md` (refreshed)

## Last Known Errors

None. Documentation-only session; no build/test run required.

## Next Recommended Step

AIQ-005: Create `docs/PXL/PXL_SCHEMA_SUMMARY.md` — a concise table/RPC/view/test map by module summarizing `supabase/migrations/` without pasting full SQL.

## Open Questions / Decisions

- Decide whether future autonomous agents should be allowed to open pull requests automatically or only prepare local changes.
- Decide whether `AI/AI_WORK_QUEUE.md` should be manually curated by the user or automatically maintained by agents after every session.
- Decide when to implement actual Claude API `cache_control` support if a Claude/Fable wrapper is later added.
