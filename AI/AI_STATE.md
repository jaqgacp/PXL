# AI State

Last updated: 2026-07-03

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.2.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 30 (2026-07-03) closed PXL-DA-003 (Critical) and PXL-AUD-004 (High): `20260702000010_can_perform_role_actions.sql` adds `fn_can_perform` per DEC-009, reroutes the lifecycle gate through it (37 tables, `approved` now restricted, JE gate backstop), and applies the member/viewer master-data policy to customers/suppliers/items. Verified by RBAC-CANPERFORM-001 + extended RLS-ROLES-001 — `npm test` 196/196 across 13 files on a fresh replay, build/lint/docs-consistency pass. The user reprioritized audit fixes above the remaining summary docs (AIQ-006–007).

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010_can_perform_role_actions.sql` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in the session-30 workspace (`supabase migration list --linked` rejected, 2026-07-03). Run `supabase link` + `supabase db push --linked` from a workspace with the token, then verify with `supabase migration list --linked`.
- PXL-AUD-014 prerequisites documented in session 28: the tax ledger writes no rows for zero-VAT documents of VAT companies, stores no exempt/zero-rated bases, and cash sales/purchases have no tax-detail writers — required before review views can be ledger-backed.

## Last Files Changed

can_perform enforcement session (session 30, 2026-07-03):

- `supabase/migrations/20260702000010_can_perform_role_actions.sql` (new: `fn_can_perform`, lifecycle gate reroute, petty cash + journal_entries gates, master-data RLS policies)
- `supabase/tests/013_can_perform_test.sql` (new: RBAC-CANPERFORM-001, 13 assertions)
- `supabase/tests/011_role_based_access_test.sql` (member approval now denied, admin approves; plan 17)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (RLS-ROLES-001 updated; RBAC-CANPERFORM-001 added)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-003 and PXL-AUD-004 → Retested Passed; standing recount; session 30 log row)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated: 128 functions, 136 triggers)

## Last Known Errors

None. `npm test` 196/196 across 13 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Session 30 landed on `main` as commit `30e4c23` (2026-07-03); CI run 28634301034 passed both jobs (`build-lint`, `db-tests` on a fresh migration replay), verified via `gh run view`.

## Next Recommended Step

Continue AIQ-008: implement PXL-DA-012 approval SoD gates per DEC-010 (approved instance + approver ≠ creator when a workflow is configured), or PXL-AUD-014 VAT ledger completeness (parallel P0 track).

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
