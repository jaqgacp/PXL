# PXL AI State

**Current Date:** 2026-07-20
**Current Branch:** `main`
**Working Tree:** Dirty with the documentation reorganization plus the new Production Certification framework documents. Preserve unrelated user changes if any appear.
**Product Phase:** Production Certification Program is the current program. The framework-setup phase is complete: the module and engine certification standards and the certification matrix exist under `docs/PXL/13. Testing and Validation/`. Accounting-core hardening and canonical-environment validation remain active product work feeding Phase 1 certification.
**Environment:** Authorized non-production hosted project `bskjkogijpbhukjkagfj`; migration history synchronized through `20260716000005`. Do not reset or seed Supabase again without explicit approval.
**Product Readiness:** Internal QA/demo only. PXL is not production-ready and not pilot-ready while one Critical and four High findings remain active. No module or engine is Certified.

## Current Finding Standing

Generated from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **81 Retested Passed / 1 In Progress / 6 Open (88 total)**.

- Active Critical: `PXL-AUD-055`.
- Active High: `PXL-AUD-053` (In Progress), `PXL-AUD-059`, `PXL-AUD-061`, `PXL-AUD-066`.
- Active Medium: `PXL-AUD-067`, `PXL-AUD-060`.

## Active Work Map

Use the central finding's exact paths and validation commands. The recommended next task is `PXL-AUD-066`; certification execution must change one bounded finding at a time and must not perform broad refactoring.

### PXL-AUD-055 - Previously exposed service-role key

Problem: frontend guard is green, but rotation of the previously exposed key is not externally confirmed. Required outcome: authorized rotation confirmation, then rerun frontend secret/build checks.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-055), the secret guard, and `package.json`.

### PXL-AUD-066 - Historical CAS evidence date semantics

Problem: CAS packages use event time for number/void evidence but document period for books/exports. Required outcome: governed document-date evidence semantics with test 027 passing 31/31.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-066), `supabase/migrations/20260710000005_cas_numbering_void_dat_controls.sql`, `supabase/tests/027_cas_end_to_end_controls_test.sql`.

### PXL-AUD-053 - Sales Invoice completeness

Problem: SI fields/posting are not fully proven across missing dimensions and downstream view/report/API/export sources. Required outcome: close source-backed slices without exposing invented masters or calling Form/View UX fully implemented.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-053), `docs/PXL/05. Sales/README.md`, `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`, focused SI code, and test 054.

### PXL-AUD-059 / PXL-AUD-061 - Coverage and deterministic lanes

Problem: 66 of 148 tables remain empty, and the green deterministic lane excludes the real CAS failures in test 027. Required outcome: keep supported, deferred, and unexercised modules explicit; after AUD-066, restore the full lane requirement.

Read first: their central findings, `docs/PXL/13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md`, `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md`, and Phase 3 scripts only when working this scope.

### PXL-AUD-067 / PXL-AUD-060 - Medium follow-ups

PXL-AUD-067 fixes checklist wording that can overstate readiness. PXL-AUD-060 tracks login accessibility. Do not let either displace security, CAS, or accounting-core work.

## Hosted and UX Status

The five canonical companies are present, and the hosted operator owns all five. ABC Trading carries the current high-volume demo data; last hosted automation passed 48/48 company/master/document probes and 20/20 report probes. Coverage remains 82 populated / 66 classified empty tables.

`docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md` and `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md` remain the only current transaction UI authorities. Sales Invoice is one implementation; PXL-AUD-053 still governs its residual source-backed business completeness. Non-SI rows remain `transaction-matrix-only`.

## Documentation Cleanup Status

Current cleanup reorganized active docs into `docs/PXL/00. Governance/` through `docs/PXL/13. Testing and Validation/`, leaving only the master index and central findings register in `docs/PXL` root. Sales Invoice specs now live under `docs/PXL/05. Sales/Sales Invoice/`; transaction framework authorities under `docs/PXL/04. Transaction Framework/`; UI authorities under `docs/PXL/12. UI and UX/`; canonical data under `docs/PXL/13. Testing and Validation/`; accounting authorities under `docs/PXL/02. Accounting Core/`; and compliance remains under `docs/PXL/10. Compliance/`.

Superseded UI and legacy SI blueprints were archived. Generated report placeholders, obsolete AIOS files, scratch scripts, and the non-authoritative Master Pharmacy working paper are in trash-review for human deletion/reconciliation review. No permanent deletion is intended in this cleanup unless validation later proves a file empty, generated, unreferenced, and reproducible.

## Production Certification Program

The current program certifies every supported module and shared engine toward controlled production use. The permanent framework is four documents under `docs/PXL/13. Testing and Validation/`:

- `PXL_MODULE_CERTIFICATION_STANDARD.md` — the 23 mandatory module gates, required evidence, and per-phase exit criteria.
- `PXL_ENGINE_CERTIFICATION_STANDARD.md` — engine contracts, invariants, consumers, and concurrency requirements.
- `PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` — professional-user capability expectations run before certifying a module (feeds module gates 1 and 22); assigns no statuses.
- `PXL_CERTIFICATION_MATRIX.md` — status dashboard only.

Framework setup is done. Execution has not started; no module or engine is Certified. The overall program result is Partially Ready — Blocked. Do not create per-module status files or duplicate findings registers; defects stay in the central register and active work stays in this file.

Phase order: (1) Setup/Master Data, Permissions/RLS, Core Accounting, Posting, Period Lock, Audit/Immutability, Number Series, Dimensions; (2) Sales/AR; (3) Purchasing/AP; (4) Inventory; (5) Banking/Treasury and Payments; (6) Fixed Assets and Schedules; (7) Compliance/Tax; (8) Reports/FS/Reconciliation; (9) Production Operations, Backup/Restore, Deployment, Pilot readiness.

Next executable phase is **Phase 1**. PXL-AUD-063 (governed global BIR write policy) is now closed. Its completion is still blocked by the active Critical `PXL-AUD-055` (external key rotation), which keeps Administration and Security and the Permissions/RLS Engine at Blocked. Backup and restore evidence (Phase 9) does not yet exist and must not be claimed.

Phase 1 Master Data discovery and roadmap planning are complete (`docs/PXL/01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md`, 35 gaps; `docs/PXL/13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md`, 15 packages MDP-01…MDP-15). **MDP-01 (gap MD-29) is DONE** and recorded as PXL-AUD-068 Retested Passed: global `tax_codes`/`vat_codes`/`atc_codes` writes are read-only at the table and routed through governed SECURITY DEFINER RPCs (authority = `is_any_company_admin() OR fn_is_bir_config_maintainer()`) with the existing audit trigger; `TaxSetupPage.tsx` rewired to the RPCs (migration `20260721000001`, test 060). Working-tree reality differed from the plan: writes were already admin-gated (not `USING(true)`), audit already existed via `fn_audit_trigger`, and a live UI writer existed — all handled. Residual: restricting global tax config to maintainer-only (removing the tenant-admin path) is a follow-up product decision. Next master-data package is **MDP-02** (extend audit coverage / reconcile — note `fn_audit_trigger` already covers many masters). Highest-risk package remains MDP-03. `PXL-AUD-066` remains the recommended next *existing* finding.

## Known Blockers and Non-Assumptions

- External key rotation blocks closure of AUD-055.
- Project, Location, and Functional Entity masters are not governed for SI.
- Banking, fixed assets, returns, approvals, schedules, statutory generators, and CAS artifacts are not proven complete.
- Do not assume green checklists mean operational readiness, a rendered route means source-backed correctness, or archived phase reports are current status.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body for the next task.

## Last Verified Commands

MDP-01 / PXL-AUD-068 validation on 2026-07-20 passed:

- `supabase db reset` — clean replay including `20260721000001_mdp01_tax_reference_write_governance.sql`
- `supabase test db supabase/tests/060_mdp01_tax_reference_governance_test.sql` — 21/21
- `supabase test db supabase/tests/059_aud063_governed_bir_config_test.sql` — 22/22 (AUD-063 regression intact)
- full `supabase test db` — 60 files / 1104 assertions; only the pre-existing PXL-AUD-066 held-out failures remain (test 027, assertions 29-30)
- `npx tsc -b`, `npm run build`, frontend-secret guard, `npm run docs:check`, `git diff --check` — passed

## Recommended Next Task

Implement `PXL-AUD-066` only: align CAS number/void evidence to governed document-period semantics so `supabase/tests/027_cas_end_to_end_controls_test.sql` passes 31/31, then restore the full deterministic lane requirement it unblocks for the regression lane. Read `supabase/migrations/20260710000005_cas_numbering_void_dat_controls.sql` and test 027 first. Do not start unrelated findings or broad refactoring.
