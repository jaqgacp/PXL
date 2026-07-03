# AI State

Last updated: 2026-07-03

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.2.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Sessions 34-36 (2026-07-03) continued PXL-DA-015 immutable report provenance: `20260703000004_report_snapshots_vat_returns.sql` adds the generic append-only `report_snapshots` table and VAT return final/filed snapshot triggers; `20260703000005_report_snapshots_form2307.sql` extends the same model to Form 2307 issued sent/acknowledged certificates; `20260703000006_report_snapshots_vat_exports.sql` adds SLSP/RELIEF exported snapshots with export history versions and reconciliation blocking. These slices create SHA-256 source hashes over frozen report/export payloads plus source rows, and block or version post-snapshot evidence changes as appropriate. Findings standing is now 19 Retested Passed / 15 In Progress / 14 Open (48 findings); 11 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010_can_perform_role_actions.sql`, `20260703000001_approval_sod_enforcement.sql`, `20260703000002_vat_ledger_completeness.sql`, `20260703000003_vat_review_views_ledger_backed.sql`, `20260703000004_report_snapshots_vat_returns.sql`, `20260703000005_report_snapshots_form2307.sql`, and `20260703000006_report_snapshots_vat_exports.sql` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in this workspace. Run `supabase db push --linked` from a tokened workspace, then verify with `supabase migration list --linked`.
- PXL-DA-015: VAT return final/filed snapshots, Form 2307 issued sent/acknowledged snapshots, and SLSP/RELIEF exported snapshots are done. Remaining provenance work is extending `report_snapshots` to SAWT, QAP, books, and CAS exports, plus a reader/drilldown UI.

## Last Files Changed

Report snapshot provenance sessions (sessions 34-36, 2026-07-03):

- `supabase/migrations/20260703000004_report_snapshots_vat_returns.sql` (new: `report_snapshots`, VAT return snapshot/immutability triggers)
- `supabase/migrations/20260703000005_report_snapshots_form2307.sql` (new: Form 2307 issued snapshot/immutability triggers)
- `supabase/migrations/20260703000006_report_snapshots_vat_exports.sql` (new: SLSP/RELIEF export snapshot RPC)
- `supabase/tests/008_vat_ledger_gl_reconciliation_test.sql` (VAT-RECON-001 extended to 21 assertions)
- `supabase/tests/010_form2307_supersede_test.sql` (F2307-SUPERSEDE-001 extended to 18 assertions)
- `src/pages/SLSPExportPage.tsx` and `src/pages/RELIEFExportPage.tsx` (export buttons snapshot before CSV download)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (VAT/export snapshot assertions documented)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-015 marked In Progress; session 34-36 log rows)
- `docs/PXL/STATUS.md` (test count and pending migrations refreshed)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated: 140 functions, 18 views, 146 tables, 141 triggers)

## Last Known Errors

None. Fresh `supabase db reset --local` replay passed through `20260703000006`; `npm test` passed 243/243 across 15 files; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Session 30 landed as `30e4c23` (CI 28634301034 green); session 31 as `8425d56` (CI 28634813215 green). Session 32 landed as `f88a595` (2026-07-03); CI run 28636237029 passed both jobs on a fresh migration replay, verified via `gh run view`.

## Next Recommended Step

Continue AIQ-008 by extending `report_snapshots` to the next compliance output, preferably SAWT, QAP, books, or CAS exports. Do not redo VAT return snapshots (`20260703000004`), Form 2307 issued snapshots (`20260703000005`), or SLSP/RELIEF export snapshots (`20260703000006`). PXL-DA-017 dimension propagation remains the next unblocked accounting architecture alternative.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
