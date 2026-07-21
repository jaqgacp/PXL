# PXL AI State

**Current Date:** 2026-07-21
**Current Branch:** `main`
**Working Tree:** Dirty with the documentation reorganization plus the new Production Certification framework documents. Preserve unrelated user changes if any appear.
**Product Phase:** Production Certification Program is the current program. The framework-setup phase is complete: the module and engine certification standards and the certification matrix exist under `docs/PXL/13. Testing and Validation/`. Accounting-core hardening and canonical-environment validation remain active product work feeding Phase 1 certification.
**Environment:** Authorized non-production hosted project `bskjkogijpbhukjkagfj`; migration history synchronized through `20260716000005`. Do not reset or seed Supabase again without explicit approval.
**Product Readiness:** Internal QA/demo only. PXL is not production-ready and not pilot-ready while one Critical and three High findings remain active. No module or engine is Certified.

## Current Finding Standing

Generated from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **82 Retested Passed / 1 In Progress / 5 Open (88 total)**.

- Active Critical: `PXL-AUD-055`.
- Active High: `PXL-AUD-053` (In Progress), `PXL-AUD-059`, `PXL-AUD-061`.
- Active Medium: `PXL-AUD-067`, `PXL-AUD-060`.

## Active Work Map

Use the central finding's exact paths and validation commands. The recommended next task is `PXL-AUD-061`; certification execution must change one bounded finding at a time and must not perform broad refactoring.

### PXL-AUD-055 - Previously exposed service-role key

Problem: frontend guard is green, but rotation of the previously exposed key is not externally confirmed. Required outcome: authorized rotation confirmation, then rerun frontend secret/build checks.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-055), the secret guard, and `package.json`.

### PXL-AUD-053 - Sales Invoice completeness

Problem: SI fields/posting are not fully proven across missing dimensions and downstream view/report/API/export sources. Required outcome: close source-backed slices without exposing invented masters or calling Form/View UX fully implemented.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-053), `docs/PXL/05. Sales/README.md`, `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`, focused SI code, and test 054.

### PXL-AUD-059 / PXL-AUD-061 - Coverage and deterministic lanes

Problem: 66 of 148 tables remain empty (AUD-059). AUD-061's CAS blocker is cleared — the CAS document-period defect (AUD-066) is fixed and the full deterministic lane is now green at 60 files / 1115 assertions with no held-out file. AUD-061's residual is only to formalize the named deterministic lane scripts/CI jobs (fresh schema, canonical seeded, hosted-safe read-only, hosted UI) and lock in the full lane as the release gate. Required outcome for AUD-059: keep supported, deferred, and unexercised modules explicit.

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

Phase 1 Master Data discovery and roadmap planning are complete (`docs/PXL/01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md`, 35 gaps; `docs/PXL/13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md`, 15 packages MDP-01…MDP-15). **MDP-01 (gap MD-29) is DONE and FROZEN as the canonical Master-Data governance template** (recorded as PXL-AUD-068 Retested Passed). Global `tax_codes`/`vat_codes`/`atc_codes` writes are read-only at the table and routed through governed SECURITY DEFINER RPCs; `TaxSetupPage.tsx` uses the RPCs. The 2026-07-21 template refinement (migration `20260721000002`, test 060 = 29/29) made MDP-01 structurally identical to the PXL-AUD-063 pattern and resolved the four review findings: (1) **authority is now MAINTAINER-ONLY** — `fn_is_bir_config_maintainer()` only, the tenant-admin path was removed and `fn_can_maintain_tax_reference()` dropped (global statutory config is not membership-governed, matching AUD-063); (2) RPC structure/authority/audit/naming standardized; (3) **audit reason is supported end-to-end** — RPCs log via `fn_log_bir_config_change(...)` with `_change_reason` and the generic `fn_audit_trigger` was removed from the three tables to prevent double-logging (the exclusion MDP-02 anticipates); (4) statutory codes are **normalized** (`upper(btrim())`) before persistence. No residual remains. The canonical surface for all future Master-Data statutory governance is: read-only RLS + shared allowlist `bir_config_maintainers` + authority `fn_is_bir_config_maintainer()` + audit helper `fn_log_bir_config_change()` + SECURITY DEFINER validate-normalize-audit RPCs + `REVOKE PUBLIC`. **MDP-02 (gap MD-30) is DONE** (migration `20260721000004`, test 061 = 26/26): the audit-coverage inventory found most masters already `fn_audit_trigger`-covered and the global statutory tables correctly RPC-audited; the only genuinely uncovered company-scoped masters — `units_of_measure`, `item_categories`, `percentage_tax_codes` — now carry the existing `fn_audit_trigger` (reused mechanism, no double-logging). Membership/config/fiscal audit stays with MDP-03/06/07. **MDP-04 DONE** (migration `20260721000005`, test 062): `chart_of_accounts` additively enriched with generated `fs_statement`, `fs_group`, control/subledger flags reconciled via `fn_sync_coa_control_accounts`, cash-flow/cost/tax flags, and an effective-date window (posting enforcement deferred to Phase 8). **MDP-05 DONE** (migration `20260721000006`, test 063): global `coa_templates`/`coa_template_lines` (PH_STANDARD, 39 classified accounts) + admin-gated `fn_seed_company_coa`/`fn_seed_company_uom`/`fn_seed_company_percentage_tax_codes` (idempotent, isolated); EWT/FWT are global ATCs so only percentage_tax_codes is seeded. **MDP-06 DONE** (migration `20260721000007`, test 064 = 24/24): admin-gated `fn_create_fiscal_year` (configurable start) + `fn_generate_fiscal_periods` (12 monthly) + `fn_provision_number_series` (per BIR doc type SI/CS/OR, branch-aware), idempotent; completed MDP-02's deferred audit coverage of `fiscal_years`/`fiscal_periods`; used explicit functions (no fiscal_years trigger) to keep manual paths working. Wizard remains MDP-08. Remaining master-data packages: **MDP-03** (Access Control & SOD — Large, highest risk), MDP-07…MDP-15. Recommended next is **MDP-07** (config/compliance/currency, unblocked by MDP-04/05) or the independent MDP-09/10/11. `PXL-AUD-066` (CAS document-period evidence) is resolved and the full deterministic lane is restored; the recommended next *existing* finding is `PXL-AUD-061`.

## Known Blockers and Non-Assumptions

- External key rotation blocks closure of AUD-055.
- Project, Location, and Functional Entity masters are not governed for SI.
- Banking, fixed assets, returns, approvals, schedules, statutory generators, and CAS artifacts are not proven complete.
- Do not assume green checklists mean operational readiness, a rendered route means source-backed correctness, or archived phase reports are current status.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body for the next task.

## Last Verified Commands

PXL-AUD-066 CAS document-period evidence validation on 2026-07-21 passed:

- `supabase db reset` — clean replay including `20260721000003_aud066_cas_document_period_evidence.sql`
- `supabase test db supabase/tests/027_cas_end_to_end_controls_test.sql` — 34/34 (document-period number/void selection; historical evidence; no event-time bleed)
- full `supabase test db` — 60 files / 1115 assertions, all passing; the previously held-out CAS file (test 027) is fully green, so the deterministic lane is fully restored with no held-out file
- migration re-apply (idempotency), `npx tsc -b`, `npm run lint`, `npm run build`, frontend-secret guard — passed

## Recommended Next Task

Implement `PXL-AUD-061` only: formalize the named deterministic test lanes (fresh schema, canonical seeded, hosted-safe read-only, hosted UI) as explicit package scripts/CI jobs and lock in the now-restored full lane (60 files / 1115 assertions) as the release gate. AUD-066 is resolved, so no product defect remains held out. Read `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-061` first. Do not start unrelated findings or broad refactoring.
