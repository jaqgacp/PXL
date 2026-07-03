# AI State

Last updated: 2026-07-03

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.2.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 31 (2026-07-03) closed PXL-DA-012 (High): `20260703000001_approval_sod_enforcement.sql` implements DEC-010 — `fn_required_approval_workflow` + `fn_enforce_approval_sod` triggers on the six governed document tables; self-approval blocked, approval instances recorded, qualifying approval required to post, direct-post docs treat posting as the approval act. Verified by APPROVAL-SOD-001 — `npm test` 210/210 across 14 files on a fresh replay. Session 30 earlier closed PXL-DA-003 (Critical) and PXL-AUD-004 via `fn_can_perform` per DEC-009. Findings standing: 18 Retested Passed / 14 In Progress / 15 Open; 11 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010_can_perform_role_actions.sql` and `20260703000001_approval_sod_enforcement.sql` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in this workspace. Run `supabase db push --linked` from a tokened workspace, then verify with `supabase migration list --linked`.
- PXL-AUD-014 prerequisites documented in session 28: the tax ledger writes no rows for zero-VAT documents of VAT companies, stores no exempt/zero-rated bases, and cash sales/purchases have no tax-detail writers — required before review views can be ledger-backed.

## Last Files Changed

Approval SoD session (session 31, 2026-07-03):

- `supabase/migrations/20260703000001_approval_sod_enforcement.sql` (new: `fn_required_approval_workflow`, `fn_enforce_approval_sod`, 12 triggers on six document tables, `approval_instances.workflow_step_id` nullable)
- `supabase/tests/014_approval_sod_test.sql` (new: APPROVAL-SOD-001, 14 assertions)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (APPROVAL-SOD-001 added)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-012 → Retested Passed; standing recount; session 31 log row)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated: 130 functions)
- `docs/PXL/STATUS.md` (stale migration header replaced with pointers to the generated schema summary and AI_STATE sync status)

## Last Known Errors

None. `npm test` 210/210 across 14 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Session 30 landed as `30e4c23` (CI run 28634301034 green). Session 31 landing evidence is recorded in `AI/AI_HANDOFF.md` once CI completes.

## Next Recommended Step

Continue AIQ-008: PXL-AUD-014 VAT ledger completeness (zero-VAT rows, exempt/zero-rated bases, cash sales/purchases tax-detail writers — prerequisites documented in session 28), or PXL-DA-017 dimension propagation per DEC-011.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
