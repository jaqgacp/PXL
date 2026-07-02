# AI State

Last updated: 2026-07-02

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.0.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 28 (2026-07-02) fixed new Critical PXL-AUD-027: void/cancel/bounce paths now net the tax ledger with counter-rows (`20260702000009_tax_ledger_void_reversal.sql`), verified by TAX-LEDGER-VOID-001 — `npm test` 182/182 across 12 files on a fresh replay, build/lint pass. The user reprioritized audit fixes above the remaining summary docs (AIQ-005–007).

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` now exists):
  - `docs/PXL/PXL_SCHEMA_SUMMARY.md`
  - `docs/PXL/PXL_ACCOUNTING_RULES.md`
  - `docs/PXL/PXL_TAX_RULES_PH.md`
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync as of 2026-07-02: migrations 20260702000008 and 20260702000009 pushed and verified via `supabase migration list --linked` (session 27's earlier "008 pushed" claim was false until this sync).
- PXL-AUD-014 prerequisites documented in session 28: the tax ledger writes no rows for zero-VAT documents of VAT companies, stores no exempt/zero-rated bases, and cash sales/purchases have no tax-detail writers — required before review views can be ledger-backed.

## Last Files Changed

- `supabase/migrations/20260702000009_tax_ledger_void_reversal.sql` (new: PXL-AUD-027 fix — counter-rows for SI void/VB void/PV cancel/OR bounce, uniform `is_reversal` semantics, `vw_ewt_summary_ap` exclusion, backfill)
- `supabase/tests/012_tax_ledger_void_reversal_test.sql` (new: TAX-LEDGER-VOID-001, 17 assertions)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-AUD-027 detail, Fix Session Log row 28)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (TAX-LEDGER-VOID-001 scenario)
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` (SI/OR/VB/PV void/cancel/bounce cells)
- `AI/AI_STATE.md`, `AI/AI_HANDOFF.md` (session bookkeeping)

## Last Known Errors

None. `npm test` 182/182 across 12 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39).

## Next Recommended Step

Continue AIQ-008: PXL-AUD-014 VAT ledger completeness (classification bases, zero-VAT rows, CS/CP writers, then ledger-backed review views) or `can_perform` enforcement (PXL-DA-003, needs a user business-role decision).

## Open Questions / Decisions

- Decide whether future autonomous agents should be allowed to open pull requests automatically or only prepare local changes.
- Decide whether `AI/AI_WORK_QUEUE.md` should be manually curated by the user or automatically maintained by agents after every session.
- Decide when to implement actual Claude API `cache_control` support if a Claude/Fable wrapper is later added.
