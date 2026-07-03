# AI State

Last updated: 2026-07-03

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 38 (2026-07-03) continued PXL-DA-015 with the CAS DAT slice: `20260703000008_report_snapshots_cas_exports.sql` adds `fn_snapshot_cas_export`, which builds all four CAS extract payloads server-side, gates each on its own reconciliation (VAT for SLSP/RELIEF, EWT payable for the alphalist, debit=credit for the GL extract), creates versioned CAS_* snapshots with SHA-256 hashes, writes server-attested `cas_export_log` rows (direct client inserts closed; new `snapshot_id` link), and returns the frozen rows so the downloaded file is provably the hashed payload. Report provenance now covers VAT returns, Form 2307 issued, SLSP/RELIEF, SAWT/QAP, and CAS DAT; books journal exports plus a snapshot reader UI remain. Findings standing is 19 Retested Passed / 15 In Progress / 14 Open (48 findings); 11 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010` and `20260703000001` through `20260703000008` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in this workspace. Run `supabase db push --linked` from a tokened workspace, then verify with `supabase migration list --linked`.
- PXL-DA-015: VAT return, Form 2307 issued, SLSP/RELIEF, SAWT/QAP, and CAS DAT export snapshots are done. Remaining provenance work is the books journal exports plus a reader/drilldown UI.

## Last Files Changed

CAS DAT export snapshot session (session 38, 2026-07-03):

- `supabase/migrations/20260703000008_report_snapshots_cas_exports.sql` (new: `fn_snapshot_cas_export`, `cas_export_log.snapshot_id`, RPC-only log inserts)
- `supabase/tests/017_cas_export_snapshots_test.sql` (new: CAS-EXPORT-SNAP-001, 15 assertions)
- `src/pages/CASDATFileGenerationPage.tsx` (file rendered from the RPC's frozen rows; direct log insert removed)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (CAS-EXPORT-SNAP-001 scenario)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-015 index/detail refreshed; session 38 log row)
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` (new CAS DAT File Generation row)
- `docs/PXL/STATUS.md` (test count and pending migrations refreshed)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated)

## Last Known Errors

None. Fresh `supabase db reset --local` replay passed through `20260703000008`; `npm test` passed 272/272 across 17 files; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Session 31 landed as `8425d56` (CI 28634813215 green); session 32 as `f88a595` (CI 28636237029 green). Sessions 33-36 landed together as `d88f0df` (CI 28645009697 green). Session 37 landed as `9110765` (2026-07-03); CI run 28645835919 passed both jobs, verified via `gh run watch --exit-status`.

## Next Recommended Step

Continue AIQ-008 by extending `report_snapshots` to the books journal exports, or build the snapshot reader/drilldown UI. Do not redo VAT return snapshots (`20260703000004`), Form 2307 issued snapshots (`20260703000005`), SLSP/RELIEF export snapshots (`20260703000006`), SAWT/QAP export snapshots (`20260703000007`), or CAS DAT export snapshots (`20260703000008`). PXL-DA-017 dimension propagation remains the next unblocked accounting architecture alternative.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
