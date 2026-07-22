# PXL AI State

**Current Date:** 2026-07-22
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

The five canonical companies are present and the hosted operator owns all five. ABC Trading carries the high-volume demo data; last hosted automation passed 48/48 company/master/document and 20/20 report probes. Coverage remains 82 populated / 66 classified empty tables.

`PXL_TRANSACTION_WORKSPACE_STANDARD.md` and `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` (under `12. UI and UX/`) remain the only current transaction UI authorities. Sales Invoice is one implementation; PXL-AUD-053 still governs its residual source-backed completeness. Non-SI rows remain `transaction-matrix-only`.

## Documentation Cleanup Status

Active docs are organized under `docs/PXL/00. Governance/` … `docs/PXL/13. Testing and Validation/`, leaving only the master index and central findings register in `docs/PXL` root (Sales Invoice under `05. Sales/`, transaction framework under `04.`, UI under `12.`, canonical data + testing under `13.`, accounting under `02.`, compliance under `10.`).

Superseded UI and legacy SI blueprints were archived. Generated report placeholders, obsolete AIOS files, scratch scripts, and the non-authoritative Master Pharmacy working paper are in trash-review for human deletion/reconciliation review. No permanent deletion is intended in this cleanup unless validation later proves a file empty, generated, unreferenced, and reproducible.

## Production Certification Program

The current program certifies every supported module and shared engine toward controlled production use. The permanent framework is four documents under `docs/PXL/13. Testing and Validation/`:

- `PXL_MODULE_CERTIFICATION_STANDARD.md` — the 23 mandatory module gates, required evidence, and per-phase exit criteria.
- `PXL_ENGINE_CERTIFICATION_STANDARD.md` — engine contracts, invariants, consumers, and concurrency requirements.
- `PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` — professional-user capability expectations run before certifying a module (feeds module gates 1 and 22); assigns no statuses.
- `PXL_CERTIFICATION_MATRIX.md` — status dashboard only.

Framework setup is done; execution has not started and no module or engine is Certified (Partially Ready — Blocked). Do not create per-module status files or duplicate findings registers; defects stay in the central register and active work stays in this file.

Phase order: (1) Setup/Master Data, Permissions/RLS, Core Accounting, Posting, Period Lock, Audit/Immutability, Number Series, Dimensions; (2) Sales/AR; (3) Purchasing/AP; (4) Inventory; (5) Banking/Treasury and Payments; (6) Fixed Assets and Schedules; (7) Compliance/Tax; (8) Reports/FS/Reconciliation; (9) Production Operations, Backup/Restore, Deployment, Pilot readiness.

Next executable phase is **Phase 1**. PXL-AUD-063 (governed global BIR write policy) is now closed. Its completion is still blocked by the active Critical `PXL-AUD-055` (external key rotation), which keeps Administration and Security and the Permissions/RLS Engine at Blocked. Backup and restore evidence (Phase 9) does not yet exist and must not be claimed.

Phase 1 Master Data discovery and roadmap planning are complete (`docs/PXL/01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md`, 35 gaps; `docs/PXL/13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md`, 15 packages MDP-01…MDP-15). **MDP-01 (gap MD-29) is DONE and FROZEN as the canonical Master-Data governance template** (PXL-AUD-068). Global `tax_codes`/`vat_codes`/`atc_codes` writes are read-only and routed through governed SECURITY DEFINER RPCs (`TaxSetupPage.tsx` uses them). The refinement (migration `20260721000002`, test 060 = 29/29) made MDP-01 identical to PXL-AUD-063 with **maintainer-only** authority (`fn_is_bir_config_maintainer()` + `bir_config_maintainers` allowlist), audited change reasons via `fn_log_bir_config_change()` (generic `fn_audit_trigger` removed to prevent double-logging), and normalized codes. The canonical statutory-governance surface is read-only RLS + shared maintainer allowlist + `SECURITY DEFINER` validate-normalize-audit RPCs + `REVOKE PUBLIC`. **MDP-02 (gap MD-30) is DONE** (migration `20260721000004`, test 061 = 26/26): most masters were already `fn_audit_trigger`-covered and the global statutory tables RPC-audited; the uncovered company-scoped masters — `units_of_measure`, `item_categories`, `percentage_tax_codes` — now carry `fn_audit_trigger` (no double-logging). **MDP-04 DONE** (migration `20260721000005`, test 062): `chart_of_accounts` enriched with generated `fs_statement`/`fs_group`, control/subledger flags reconciled via `fn_sync_coa_control_accounts`, cash-flow/cost/tax flags, effective-date window (posting enforcement → Phase 8). **MDP-05 DONE** (migration `20260721000006`, test 063): global `coa_templates`/`coa_template_lines` (PH_STANDARD, 39 accounts) + admin-gated idempotent `fn_seed_company_coa`/`fn_seed_company_uom`/`fn_seed_company_percentage_tax_codes`. **MDP-06 DONE** (migration `20260721000007`, test 064 = 24/24): admin-gated idempotent `fn_create_fiscal_year` + `fn_generate_fiscal_periods` (12 monthly) + `fn_provision_number_series` (per BIR doc type, branch-aware); completed the deferred audit coverage of `fiscal_years`/`fiscal_periods` via explicit functions (no trigger). **MDP-07 DONE** (migration `20260721000008`, test 065 = 24/24, gaps MD-06/07/31): explicit `companies.functional_currency_code`/`reporting_currency_code` (default PHP, FK `currencies`); admin-gated `fn_provision_company_accounting_config` (maps control accounts from the COA by canonical code, fill-NULL-only), `fn_validate_company_accounting_config`, `fn_provision_compliance_profile` (from `tax_registration`); audit coverage of `company_accounting_config`. No findings. **MDP-09 DONE** (migration `20260722000001`, test 066 = 32/32, gaps MD-14/15/16): three governed company-scoped dimension masters — `projects`/`locations`/`functional_entities` — branch-aware, hierarchical (shared `fn_dimension_hierarchy_guard`), effective-dated + `is_active`, member-gated RLS, audit-covered; plus reusable `fn_is_valid_dimension` (the contract for future transaction packages) and admin-gated `fn_provision_company_dimension_defaults`. Line propagation deferred to the transaction packages (coordinate PXL-AUD-053); no posting change, no findings. **MDP-10 DONE** (migration `20260722000002`, test 067 = 30/30, gaps MD-17/18/19): governed `customer_groups`/`supplier_groups` (+ additive FKs; legacy free-text preserved & backfilled), a `party_contacts` multi-contact master (customer XOR supplier, one-primary, isolation guard), and `fn_party_tin_duplicates` detection. PH TIN normalization/canonical format already existed (`20260715000001`), so MD-19 was detection only (no hard unique — legitimate duplicates). Non-destructive; no findings. **MDP-11 DONE** (migration `20260722000003`, test 068 = 28/28, gaps MD-20/25/26): salesperson/buyer **designation** on `employees` (`is_salesperson`/`is_buyer` + `fn_is_valid_attribution`; no duplicate table — SI `salesperson_id`→`employees` unchanged), global read-only `ref_banks` + additive `bank_accounts.bank_id` (legacy `bank_name` kept), and `company_payment_modes` (company-scoped, GL-mapped via `fn_company_payment_mode_gl_guard`; global `ref_payment_modes` + FKs untouched). Reference masters only; no findings. Remaining packages: **MDP-03** (Access Control & SOD — Large, highest risk), MDP-08 (wizard, adds UI), MDP-12/13/14/15. Recommended next is **MDP-13** (item master) or **MDP-12**. `PXL-AUD-066` is resolved and the full deterministic lane is restored (now 68 files / 1327 assertions); the recommended next *existing* finding is `PXL-AUD-061`.

## Known Blockers and Non-Assumptions

- External key rotation blocks closure of AUD-055.
- Project, Location, and Functional Entity masters are not governed for SI.
- Banking, fixed assets, returns, approvals, schedules, statutory generators, and CAS artifacts are not proven complete.
- Do not assume green checklists mean operational readiness, a rendered route means source-backed correctness, or archived phase reports are current status.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body for the next task.

## Last Verified Commands

MDP-11 attribution-&-reference-masters validation on 2026-07-22 passed:

- `supabase db reset` — clean replay including `20260722000003_mdp11_attribution_reference_masters.sql`
- `supabase test db supabase/tests/068_mdp11_attribution_reference_masters_test.sql` — 28/28 (designation + `fn_is_valid_attribution`; `ref_banks` read-only + `bank_id` link; `company_payment_modes` GL integrity + uniqueness + isolation + lifecycle + audit + rollback + authority)
- full `supabase test db` — 68 files / 1327 assertions, all passing
- migration re-apply, `npm run build` (tsc + vite + frontend-secret guard), `npm run lint` — passed

## Recommended Next Task

MDP-11 is complete. Two tracks: (a) resume `PXL-AUD-061` — formalize the named deterministic test lanes as explicit scripts/CI jobs and lock in the full lane (68 files / 1327 assertions) as the release gate; read `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-061` first; or (b) the independent backend-only **MDP-13** (item master inventory readiness) or **MDP-12**. MDP-08 (wizard) is unblocked but adds UI. Do not start unrelated findings or broad refactoring.
