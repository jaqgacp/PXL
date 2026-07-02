# AI State

Last updated: 2026-07-02

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.2.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 28 (2026-07-02) fixed new Critical PXL-AUD-027: void/cancel/bounce paths now net the tax ledger with counter-rows (`20260702000009_tax_ledger_void_reversal.sql`), verified by TAX-LEDGER-VOID-001 — `npm test` 182/182 across 12 files on a fresh replay, build/lint pass. The user reprioritized audit fixes above the remaining summary docs (AIQ-005–007).

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync as of 2026-07-02: migrations 20260702000008 and 20260702000009 pushed and verified via `supabase migration list --linked` (session 27's earlier "008 pushed" claim was false until this sync).
- PXL-AUD-014 prerequisites documented in session 28: the tax ledger writes no rows for zero-VAT documents of VAT companies, stores no exempt/zero-rated bases, and cash sales/purchases have no tax-detail writers — required before review views can be ledger-backed.

## Last Files Changed

AIOS 1.2.0 delegation session (session 29, 2026-07-02):

- `AI/AI_DECISIONS.md` (DEC-008 standing autonomy delegation; DEC-009 role/action matrix; DEC-010 approval SoD; DEC-011 branch = reporting dimension)
- `AI/AI_AUTONOMY_PLAYBOOK.md` (Level 4 rewritten as delegated decisions; must-ask list reduced to hard safety stops)
- `AI/AGENT_SYSTEM_PROMPT.md` (ask-before list reduced; PENDING rule for missing credentials)
- `AI/AI_STATE.md` ("Decisions Needed From User" → "Standing Autonomy Delegation")
- `AI/AIOS_VERSION.md` (1.2.0)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (index Next Action for PXL-DA-003/PXL-AUD-004/PXL-DA-012/PXL-DA-017 now cite DEC-009/010/011; session 29 log row)

## Last Known Errors

None. `npm test` 182/182 across 12 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39).

AIOS 1.1.0 landed on `main` as commit `082652b` (2026-07-02); CI run 28609465374 passed both jobs (`build-lint` including the new docs-consistency gate, `db-tests` on a fresh migration replay), verified via `gh run view`.

## Next Recommended Step

Continue AIQ-008: implement PXL-DA-003 `can_perform(company_id, action, document_type)` per DEC-009 in every posting/void/reversal RPC (Critical, now unblocked), then PXL-DA-012 approval gates per DEC-010. PXL-AUD-014 VAT ledger completeness remains the parallel P0 track.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
