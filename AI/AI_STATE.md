# AI State

Last updated: 2026-07-04

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 40 (2026-07-04) CLOSED PXL-DA-015: `src/pages/ReportSnapshotsPage.tsx` (route `/report-snapshots`, Compliance → Audit & CAS nav) is the snapshot reader/drilldown UI over all six snapshot families — filterable RLS-scoped list, full SHA-256 hash, per-source version history with click-through, generic frozen payload rendering (values, row tables, reconciliation). Verified live in Chromium against local Supabase with seeded snapshots. New Medium finding PXL-AUD-029 logged (AppShell nav feature gating queries non-existent `sys_feature_enablement.feature_key`, 400s and fails open). Findings standing is 20 Retested Passed / 14 In Progress / 15 Open (49 findings); 10 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260702000009 (verified 2026-07-02). PENDING: push `20260702000010` and `20260703000001` through `20260703000009` to hosted Supabase — no `SUPABASE_ACCESS_TOKEN` in this workspace. Run `supabase db push --linked` from a tokened workspace, then verify with `supabase migration list --linked`.
- PXL-AUD-029 (Open, Medium): `AppShell` feature gating fails open — small query fix pending.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

Snapshot reader UI session (session 40, 2026-07-04):

- `src/pages/ReportSnapshotsPage.tsx` (new: snapshot reader/drilldown UI)
- `src/App.tsx` (route `/report-snapshots`)
- `src/components/AppShell.tsx` (nav item + page label under Compliance → Audit & CAS)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-015 Retested Passed; new PXL-AUD-029; standing; session 40 log row)
- `docs/PXL/STATUS.md` (206/206 pages; Audit & CAS 12)
- `docs/PXL/PXL_PRODUCT_BACKLOG.md` (snapshot hash re-verification/re-download enhancement row)

## Last Known Errors

None. `npm test` 285/285 across 18 files on a fresh `supabase db reset --local`; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green. Reader UI verified live in the browser (login → company select → list/filter/drilldown/version switching).

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 37 landed as `9110765` (CI 28645835919 green). Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (2026-07-04); CI run 28699881597 completed successfully, verified via `gh run watch --exit-status`.

## Next Recommended Step

Continue AIQ-008: PXL-DA-017 dimension propagation to JE lines per DEC-011 is the highest-value unblocked accounting architecture task. Alternatively, PXL-AUD-029 is a small self-contained `AppShell` query fix. Do not redo any PXL-DA-015 snapshot slice or the reader UI.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
