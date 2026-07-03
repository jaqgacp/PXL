# AI State

Last updated: 2026-07-03

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.2.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 32 (2026-07-03) delivered VAT ledger completeness for PXL-AUD-014/PXL-DA-008 (`20260703000002_vat_ledger_completeness.sql`): per-VAT-code output/input rows with zero-rated/exempt bases for SI/VB, cash sale output VAT + CWT writers, cash purchase input VAT writers, posted-document backfill; and fixed new Critical PXL-AUD-028 (cash sale was runtime-dead: phantom columns, zero totals from UI payloads, AR over-application, missing ATC) — `fn_save_cash_sale` rebuilt on the server-side recompute pattern, `CashSalesPage` gained the CWT ATC selector. Verified by VAT-LEDGER-COMPLETE-001 — `npm test` 223/223 across 15 files on a fresh replay. Sessions 30–31 earlier closed PXL-DA-003/PXL-AUD-004 (DEC-009 `fn_can_perform`) and PXL-DA-012 (DEC-010 approval SoD). Findings standing: 19 Retested Passed / 14 In Progress / 15 Open (48 findings); 11 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010_can_perform_role_actions.sql`, `20260703000001_approval_sod_enforcement.sql`, and `20260703000002_vat_ledger_completeness.sql` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in this workspace. Run `supabase db push --linked` from a tokened workspace, then verify with `supabase migration list --linked`.
- PXL-AUD-014: ledger completeness landed in session 32; the remaining step is rebasing `vw_output_vat_review`/`vw_input_vat_review` and the return generators on `tax_detail_entries` (treat NULL `vat_code_id` as regular), then filed-snapshot provenance with PXL-DA-015.

## Last Files Changed

VAT ledger completeness session (session 32, 2026-07-03):

- `supabase/migrations/20260703000002_vat_ledger_completeness.sql` (new: per-VAT-code writers for SI/VB/CS/CP, fn_save_cash_sale rebuilt per PXL-AUD-028, posted-document backfill)
- `supabase/tests/015_vat_ledger_completeness_test.sql` (new: VAT-LEDGER-COMPLETE-001, 13 assertions)
- `src/pages/CashSalesPage.tsx` (CWT ATC selector; `cwt_atc_id` in the header payload)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (VAT-LEDGER-COMPLETE-001 added)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-AUD-028 added Retested Passed; PXL-AUD-014 progress; standing recount; session 32 log row)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated: 130 functions)

## Last Known Errors

None. `npm test` 223/223 across 15 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Session 30 landed as `30e4c23` (CI 28634301034 green); session 31 as `8425d56` (CI 28634813215 green). Session 32 landed as `f88a595` (2026-07-03); CI run 28636237029 passed both jobs on a fresh migration replay, verified via `gh run view`.

## Next Recommended Step

Continue AIQ-008: rebase `vw_output_vat_review`/`vw_input_vat_review` and the 2550 return generators on `tax_detail_entries` (PXL-AUD-014 final step), or PXL-DA-017 dimension propagation per DEC-011.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
