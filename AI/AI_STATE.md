# PXL AI State

**Current Date:** 2026-07-22
**Current Branch:** `main`
**Working Tree:** Dirty with preserved prior MDP/security/certification work plus the bounded PXL-AUD-053 migration, UI wiring, tests, and documentation. No commit has been made; preserve unrelated user changes.
**Product Phase:** Production Certification Program. Framework setup is complete; accounting-core and canonical validation continue to feed Phase 1 certification.
**Environment:** Authorized non-production hosted project `bskjkogijpbhukjkagfj`; migration history synchronized through `20260716000005`. Do not reset, seed, migrate, repair, link, or otherwise mutate the hosted project without explicit approval. Local reset/test work is permitted.
**Product Readiness:** Internal QA/demo only. PXL is not production-ready and not pilot-ready while module/engine certification evidence is incomplete. No module or engine is Certified.

## Current Finding Standing

Generated from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **89 Retested Passed / 0 In Progress / 0 Open (89 total)**.

- Active Critical: none.
- Active High: none.
- Active Medium: none. Every audit finding is Retested Passed.

## Active Work Map

No audit findings remain open. A closed findings register does not certify any module: Setup & Master Data remains **Blocked** on its own Partial/operational/shared-engine evidence. Coverage governance is maintained through `PXL_TABLE_COVERAGE_MATRIX.md` plus guard `075`; adding a `public` base table requires a matching registry entry in both. The next work is Production Certification execution, not defect remediation.

## Hosted and UX Status

The five canonical companies are present and owned by the hosted operator. ABC Trading carries the high-volume demo data; last hosted automation passed 48/48 company/master/document and 20/20 report probes. Table coverage is governed under PXL-AUD-059: 176 local tables classified in `PXL_TABLE_COVERAGE_MATRIX.md`; hosted last profiled 82/66 of 148.

`PXL_TRANSACTION_WORKSPACE_STANDARD.md` and `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` remain the transaction UI authorities. Sales Invoice is one implementation; PXL-AUD-053 still governs its validated source-backed completeness. Do not call Form/View UX fully implemented from that business/source result. Non-SI rows remain `transaction-matrix-only`.

## Documentation Cleanup Status

Active docs are organized under `docs/PXL/00. Governance/` … `docs/PXL/13. Testing and Validation/`, leaving only the master index and central findings register in `docs/PXL` root (Sales Invoice under `05. Sales/`, transaction framework under `04.`, UI under `12.`, canonical data + testing under `13.`, accounting under `02.`, compliance under `10.`).

Superseded UI and legacy SI blueprints were archived. Generated report placeholders, obsolete AIOS files, scratch scripts, and the non-authoritative Master Pharmacy working paper are in trash-review for human deletion/reconciliation review. No permanent deletion is intended in this cleanup unless validation later proves a file empty, generated, unreferenced, and reproducible.

## Production Certification Program

The current program certifies every supported module and shared engine toward controlled production use. Certification execution is underway: the Setup & Master Data review was re-executed on 2026-07-22 with the findings program complete (88/0/0) — 14 Pass, 3 Partial, 2 Blocked, 4 N/A, 0 Fail gates — so the module is **Blocked on missing evidence, not defects**, not Certified. The permanent framework is four documents under `docs/PXL/13. Testing and Validation/`:

- `PXL_MODULE_CERTIFICATION_STANDARD.md` — the 23 mandatory module gates, required evidence, and per-phase exit criteria.
- `PXL_ENGINE_CERTIFICATION_STANDARD.md` — engine contracts, invariants, consumers, and concurrency requirements.
- `PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` — professional-user capability expectations run before certifying a module (feeds module gates 1 and 22); assigns no statuses.
- `PXL_CERTIFICATION_MATRIX.md` — status dashboard only.

Framework setup is done; execution has started and no module or engine is Certified (Partially Ready — Blocked). Do not create per-module status files or duplicate findings registers; defects stay in the central register and active work stays in this file.

Phase order: (1) Setup/Master Data, Permissions/RLS, Core Accounting, Posting, Period Lock, Audit/Immutability, Number Series, Dimensions; (2) Sales/AR; (3) Purchasing/AP; (4) Inventory; (5) Banking/Treasury and Payments; (6) Fixed Assets and Schedules; (7) Compliance/Tax; (8) Reports/FS/Reconciliation; (9) Production Operations, Backup/Restore, Deployment, Pilot readiness.

Next executable certification phase is **Phase 1**. The external credential blocker is resolved, but Administration/Security and the Permissions/RLS Engine are not automatically Certified; each still requires an executed review against its governing standard. Backup and restore evidence (Phase 9) does not yet exist and must not be claimed.

Phase 1 Master Data planning is complete (`PXL_MASTER_DATA_GAP_REGISTER.md`, 35 gaps all resolved; `PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md`, 15 packages). All packages MDP-01 through MDP-15 are verified from migrations/tests; MDP-14 provides the reusable approval-matrix foundation (deterministic role/user routing, SOD/permission/concurrency guards, audited version-bound requests, and bounded MDP-15 import enforcement) with no rules seeded, so unconfigured workflows stay compatible. The full local lane is green at 75 files / 1,596 assertions (fresh reset) plus canonical 4/96. The module review remains **Blocked on missing evidence, not defects**: Gate 23 backup/restore + RPO/RTO does not exist, the dependent Permissions/RLS, Audit & Immutability, Number Series, and Dimension engines are not Certified, and browser-workflow evidence is recorded-only (Gate 20 Partial).

## Known Blockers and Non-Assumptions

- Sales Invoice Project, Location, and Functional Entity are now validated from UI/storage through posting, GL/inventory, reporting, API/export, audit, and reversal under PXL-AUD-053. This does not certify dimension integration in unrelated transactions.
- Banking, fixed assets, returns, broad transaction approval rollout, schedules, statutory generators, and CAS artifacts are not proven complete. MDP-14 proves the reusable approval foundation and configured MDP-15 import integration only.
- Do not assume green checklists mean operational readiness, a rendered route means source-backed correctness, or archived phase reports are current status.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body for the next task.

## Last Verified Commands

PXL-AUD-069 reporting-view RLS isolation remediation on 2026-07-22 (Critical, Retested Passed):

- The Permissions/RLS Engine review found a confirmed Critical cross-company leak: 9 `postgres`-owned, non-`security_invoker` views (`vw_ap_aging`, `vw_payment_register`, `vw_receipt_register`, `vw_slp_export`, `vw_credit_memo_register`, `vw_debit_memo_register`, `vw_deposits_in_transit`, `vw_outstanding_checks`, `vw_sdm_register`) bypassed RLS — a member of only Golden Retail read ABC Trading's financials via PostgREST.
- Fixed by migration `20260722000011` (`security_invoker=on` on all 9; server-side only, RLS not weakened). Verified: leak closed (non-member sees 0) and legitimate access preserved (ABC member still sees ABC). Test 076 (6/6) proves member/non-member isolation + structural coverage; permanent guard 077 (2/2, proven non-vacuous) blocks the class in every lane. Engine foundation otherwise strong: RLS on 176/176 tables (473 policies), `anon` zero data access, all 335 DEFINER functions pin `search_path`, RLS/SOD tests 90 assertions.

Setup & Master Data Phase 1 certification re-review on 2026-07-22 (decision: Blocked):

- `npm run test:db:local` — fresh no-seed reset + full pgTAP, 75 files / 1,596 assertions PASS (MDP-01…15 including 073 MDP-08 50/50 and 074 MDP-14 61/61 on clean state). `npm run test:canonical` — 4 files / 96 assertions PASS. `npm run test:company-setup-readiness` — 8/8. All 35 master-data gaps resolved.
- Decision **Blocked on missing evidence, not defects**: no backup/restore/RPO/RTO exists (Gate 23); dependent Permissions/RLS, Audit & Immutability, Number Series, Dimension engines not Certified; browser workflow evidence recorded-only (Gate 20). Certification-matrix dashboard updated; no code, schema, or hosted mutation.

PXL-AUD-060 login accessibility certification on 2026-07-22 passed:

- `src/pages/LoginPage.tsx` wires `htmlFor`/`id` labels, `name`, `autocomplete="email"`/`current-password`, and a persistent `role="alert"` assertive error region referenced by `aria-describedby`/`aria-invalid`; `scripts/audit_phase3_hosted_ui.mjs` now resolves login fields by `getByLabel`. Read-only over auth UI; no table/migration/RPC/RLS change.
- `npm run test:login-accessibility` — 10/10 credential-free Chromium label/attribute/error-region assertions (serves the built app, never submits). Lint, build, and the frontend secret guard pass. Closing this last finding required teaching guard `check_ai_state.mjs` to represent a fully-closed program (no remaining open finding).

PXL-AUD-067 readiness-model certification on 2026-07-22 passed: Company Setup Checklist restructured into Stage 1 Core Accounting Readiness, Stage 2 Operational Readiness, and a separate Production Readiness note; logic extracted to pure `src/lib/companySetupReadiness.ts`; `npm run test:company-setup-readiness` 8/8; lint/build pass; read-only over masters, no schema change.

PXL-AUD-059 (prior cycle): 176 `public` base tables classified in `PXL_TABLE_COVERAGE_MATRIX.md`; guard `075` runs in `test:canonical` (96) and `test:db:local` (75 files / 1,596).

PXL-AUD-053 Sales Invoice completeness certification on 2026-07-22 passed: clean no-seed replay through `20260722000010`; test 054 42/42; `test:sales-invoice-draft-state` 4/4; full suite 74 files / 1,588; canonical 055/057/058 88/88; docs/lint/build/diff pass. Supported field set `END_TO_END_VALIDATED`; unsupported/partial rows explicit in the Field Source Matrix. No hosted mutation.

PXL-AUD-061 / MDP-14 deterministic release-gate validation on 2026-07-22 passed: `npm ci` reproducible install (Playwright declared); fresh no-seed replay through `20260722000009` (idempotent on second replay); test 074 61/61; targeted regressions 011/014/050/071/072/073 171/171; full lane and canonical green; named local/CI gates fail closed if a protected hosted job is skipped. Prior hosted evidence remains 48/48 company/master/document and 20/20 report probes.

PXL-AUD-055 final remediation on 2026-07-22 passed: exposed hosted key and revoked PAT (`8a20f35e729f3c30`) independently rejected (HTTP 401); local plaintext cleanup done; security tests 056/059/060/072/074 158/158; `release:gate:local` green (fresh replay, 74 files / 1,568, canonical 88/88, docs/lint/build/frontend-secret/diff). No hosted mutation.

## Recommended Next Task

**No audit findings remain open (89/89).** The Permissions/RLS Engine's Critical cross-company reporting-view leak is remediated and guarded (recorded in Last Verified). Immediate next task: **re-run the Permissions/RLS Engine certification review** against the cleared state and make its browser-tier cross-tenant isolation check a re-runnable lane; then certify Audit & Immutability, Number Series, and Dimension engines and stand up Backup/Restore (RPO/RTO) evidence. Do not imply any module or engine certification; no module or engine is Certified.
