# PXL Testing and Validation Index

**Status:** Active domain index
**Authority:** Tier 2 Navigation; test output and executable tests retain authority over documentation summaries
**Last Reviewed:** 2026-07-22 after PXL-AUD-061 deterministic release-gate formalization
**Applies To:** Canonical data, hosted/local validation, regression lanes, browser probes, and documentation checks
**Read When:** A task changes canonical data, validation scripts, test lanes, or evidence claims
**Do Not Read For:** Current product readiness unless `AI/AI_STATE.md` names this scope

## Current Authorities

| Need | Read |
| --- | --- |
| Production certification framework: how a module is certified | `docs/PXL/13. Testing and Validation/PXL_MODULE_CERTIFICATION_STANDARD.md` |
| Production certification framework: how a shared engine is certified | `docs/PXL/13. Testing and Validation/PXL_ENGINE_CERTIFICATION_STANDARD.md` |
| Pre-certification capability-expectation checklist (professional-user completeness) | `docs/PXL/13. Testing and Validation/PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` |
| Master Data implementation roadmap (bounded packages + execution order) | `docs/PXL/13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md` |
| Current module/engine certification status and next phase (dashboard only) | `docs/PXL/13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md` |
| Canonical demo dataset scope, counts, safety rules, and coverage limits | `docs/PXL/13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md` |
| Accounting test scenarios and Supabase test-file mapping | `../02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md` |
| Deterministic validation lanes and release process | This document, `package.json`, `scripts/run_validation_lane.mjs`, and `.github/workflows/ci.yml` |
| Current operational next task and last verified command summary | `../../AI/AI_STATE.md` |

## Production Certification Program

The PXL Production Certification Program moves PXL from feature-complete development toward controlled production use. It is governed by four permanent authorities in this folder: the Module Certification Standard (module gates), the Engine Certification Standard (engine contracts and invariants), the Product Completeness Checklist (capability expectations run before certifying a module), and the Certification Matrix (status dashboard). Defects remain in `../PXL_END_TO_END_AUDIT_FINDINGS.md`; the current bounded task remains in `../../AI/AI_STATE.md`. Do not create per-module status documents or duplicate findings registers.

## Deterministic Validation Prerequisites

- Node.js 24 and dependencies installed with `npm ci`.
- Supabase CLI `2.108.0`, matching CI.
- Docker and an isolated local Supabase stack started with `supabase db start` for database and canonical lanes.
- No local lane may target a linked or hosted project. The runner always supplies `--local` for resets and pgTAP.
- The hosted lanes require explicit `PXL_ALLOW_HOSTED_READ_ONLY=1`, approved read-only credentials, and the approved project reference. They reject local targets, and the SQL lane forces PostgreSQL `default_transaction_read_only=on`.
- The hosted UI lane additionally requires Playwright Chromium and explicit `AUDIT_BASE_URL`, `AUDIT_EMAIL`, and `AUDIT_PASSWORD`; implicit demo credentials are not accepted by the governed lane.

## Supported Test Lanes

| Lane | Command | Starting state and success criteria | Release role |
| --- | --- | --- | --- |
| Fresh schema | `npm run test:db:fresh` | Any local state; resets without seed and replays every migration successfully. | Mandatory database gate. |
| Focused package | `npm run test:db:focused -- supabase/tests/<file>.sql` | Current local schema; every named pgTAP file and assertion passes. One or more paths are accepted. | Required while changing an owned package; never substitutes for regression. |
| Regression | `npm run test:db:regression` | Current clean local schema; all **74 pgTAP files / 1,568 assertions** pass with no held-out file. | Mandatory test gate. `npm test` is an alias. |
| Local deterministic | `npm run test:db:local` | Isolated local stack; composes fresh schema followed by full regression. | Mandatory local database evidence. |
| Canonical dataset | `npm run test:canonical` | Isolated local stack; performs a fresh reset, loads reset/base/enrichment/volume layers atomically, then tests 055/057/058 pass **88/88**. | Mandatory canonical gate. This intentionally replaces the local database contents. |
| Documentation | `npm run validate:docs` | Repository checkout; AI state, findings checksum, matrix, and test-book/file mapping agree. | Mandatory documentation gate. |
| Lint | `npm run validate:lint` | Dependencies installed; `oxlint` exits zero. | Mandatory static-analysis gate. |
| Build | `npm run validate:build` | Dependencies installed; frontend secret guard passes before and after typecheck/production bundle. | Mandatory build and frontend-secret gate. |
| Diff | `npm run validate:diff` | Working tree; `git diff --check` exits zero. CI checks the committed event range instead. | Mandatory patch-integrity gate. |
| Hosted read-only SQL | `npm run test:hosted:read-only` | Explicitly authorized hosted read-only environment; the canonical coverage SQL completes under forced read-only transactions. | Mandatory for a release candidate; manual protected CI only. |
| Hosted UI | `npm run test:hosted:ui` | Explicit non-local HTTPS deployment and approved test identity; all canonical company/document, report, SI-detail, and page-error probes pass. | Mandatory for a release candidate; manual protected CI only. |

`npm run release:gate:local` composes the fresh-schema, full-regression, canonical, documentation, lint, build, and diff lanes in that order. It is intentionally local-only. A complete release-candidate decision also requires a successful manual CI dispatch with `release_candidate=true`, which makes both protected hosted lanes mandatory.

## Execution Order

1. Run `npm ci` and `supabase db start`.
2. During implementation, run the smallest relevant `test:db:focused` file(s).
3. Run `npm run test:db:local`; a failure invalidates later local database evidence.
4. Run `npm run test:canonical`; do not reuse its seeded state as fresh-schema evidence.
5. Run documentation, lint, build, and diff gates, or use `npm run release:gate:local` to execute steps 3-5 from the beginning.
6. For an actual release candidate, an authorized operator manually dispatches `.github/workflows/ci.yml` with `release_candidate=true`. The protected read-only SQL and UI jobs must both pass before the summary job can pass.

## Pass, Failure, and Rerun Rules

- A lane passes only on exit code zero with every command and assertion in that lane green. Skipped or unexecuted mandatory release-candidate lanes are not pass evidence.
- The runner reports the lane, step, exact non-secret command, exit status, and lane-specific remediation. pgTAP output remains authoritative for the failing file and assertion.
- On failure, fix the bounded owning defect and rerun the failed focused command first. Then rerun the entire failed lane from its documented starting state. A partial rerun does not replace a failed lane result.
- After a migration, seed, fixture, shared test helper, package script, CI workflow, or release document changes, rerun the complete local release gate.
- Never rerun a hosted failure by resetting, seeding, migrating, repairing, or otherwise mutating the hosted project. Correct the approved read-only configuration or underlying change locally, then obtain authorization for another hosted read-only run.

## CI Release Gates

The existing `.github/workflows/ci.yml` is the only workflow. Pushes and pull requests publish separate static, fresh-schema/regression, and canonical results, followed by one deterministic summary gate. Manual release-candidate dispatch adds the two protected hosted read-only jobs. CI does not store credentials in the repository and does not run hosted mutations.

Mandatory release gates are:

| Gate | Evidence |
| --- | --- |
| Database | Fresh no-seed migration replay. |
| Tests | 74-file / 1,568-assertion pgTAP regression. |
| Canonical | Deterministic canonical rebuild plus 88 canonical assertions. |
| Documentation | `docs:check`. |
| Lint | Zero-exit `oxlint`. |
| Build | Secret guard, TypeScript build, and Vite production bundle. |
| Diff | Whitespace check for the local patch or CI event range. |
| Hosted verification | Protected read-only SQL and canonical UI jobs for release candidates only. |

## Other Focused Validation Commands

```bash
npm run test:transaction-workspace
npm run test:sales-invoice-draft-state
```

Run focused product tests named by the active finding before using broader lanes as evidence.
