# PXL Master Data Implementation Plan

**Status:** Active Phase 1 implementation roadmap
**Authority:** Tier 2 Planning — the authoritative execution roadmap for the Setup & Master Data certification phase
**Owner / Domain:** Testing and Validation / Architecture
**Applies To:** Sequencing and scoping of every Master Data implementation session
**Read When:** Selecting or scoping the next Master Data implementation package
**Do Not Read For:** Gap detail (use [`../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md`](../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md)), certification method (use the certification standards), defect status (use [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md)), or current bounded task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-22 roadmap/state reconciliation after MDP-03

## Purpose

This roadmap converts the 35 gaps in the [Master Data Gap Register](../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md) into **15 bounded implementation packages** (MDP-01 … MDP-15) covering every gap with no overlap. Each package is independently reviewable, testable, and certifiable, and is scoped small enough for one controlled implementation session where practical. This document plans; it implements nothing and changes no certification status. It follows the gates in [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md), the engine contracts in [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md), and the capability expectations in [`PXL_PRODUCT_COMPLETENESS_CHECKLIST.md`](PXL_PRODUCT_COMPLETENESS_CHECKLIST.md).

Source-of-truth note: this revision was validated against the current local working tree. The gap register still covers 35 gaps (IDs MD-01…MD-35 contiguous); completed package status is based on actual migrations/tests in `supabase/migrations` and `supabase/tests`, not on the original package order. Local documentation and the MDP-12/MDP-13/MDP-15/MDP-03 migration/test files may be uncommitted; treat them as existing work to preserve unless explicitly directed otherwise.

## Packaging method

Gaps were grouped by the object they change and the concern they serve, so each package touches one cohesive surface and can be verified end-to-end. Every package below states explicit scope and exclusions, its dependent modules and engines, impact separated across Database / UI / Security & RLS / Audit / Migration & seed / Reporting, regression risk, deliverables, acceptance criteria, required automated and manual validation, the Product Completeness Checklist sections affected, the certification gates affected, and rollback/recovery. Complexity is **Small / Medium / Large**. No package may weaken RLS, immutability, or tenant isolation to pass, and each lands its own deterministic tests. Certification gate numbers refer to the 23 module gates in the Module Certification Standard.

## Package Register

### MDP-01 — Tax-Reference Write Governance ✅ DONE & FROZEN AS CANONICAL TEMPLATE (2026-07-21)

**Status: implemented, Retested Passed as PXL-AUD-068, and FROZEN as the reusable Master-Data governance template.** Migrations `20260721000001_mdp01_tax_reference_write_governance.sql` + `20260721000002_mdp01_template_refinement.sql`, test `060` (29/29), and `src/pages/TaxSetupPage.tsx` on the RPCs. The 2026-07-21 template refinement made MDP-01 structurally identical to PXL-AUD-063 and resolved the independent-review findings.

**Canonical governance pattern (every future Master-Data statutory package inherits this, no interpretation required):**
1. **RLS** — `authenticated` READ-ONLY (`SELECT`); no write policy, so direct client writes are denied by default.
2. **Authority (DECISION: Option A — MAINTAINER-ONLY)** — one shared helper `fn_is_bir_config_maintainer()` backed by one shared allowlist `bir_config_maintainers` (empty ⇒ closed by default). Rationale: global statutory reference data is shared by every tenant, so it must **not** be governed by tenant membership; allowing any tenant admin to mutate it is the cross-tenant integrity hole MD-29 identified. This matches PXL-AUD-063 ("no tenant role may mutate shared statutory config"). The tenant-admin path and the divergent `fn_can_maintain_tax_reference()` wrapper were removed. The `bir_config_*` names are historical (AUD-063 was first) but are THE canonical shared statutory-config surface; a neutral rename is a deferred cosmetic that would re-touch the closed AUD-063 finding.
3. **Write path** — SECURITY DEFINER RPCs that (a) check the authority helper, (b) validate + **normalize** input (`upper(btrim())` on statutory codes, so equivalent inputs yield identical stored values), (c) capture old/new via `%ROWTYPE`, and (d) `PERFORM fn_log_bir_config_change(...)` recording a free-text `_change_reason` **end-to-end**. The generic `fn_audit_trigger` is removed from governed tables to prevent double-logging (the exclusion MDP-02 anticipates). Soft-deactivate via `set_active`; `DELETE` stays denied by RLS.
4. **Least privilege** — `REVOKE ALL … FROM PUBLIC`; `GRANT EXECUTE` only on the governed surface to `authenticated`; the audit helper is granted to nobody.

**No residual remains.** Original plan preserved below for provenance.

- **Business objective:** Prevent any authenticated user from altering shared statutory tax rates; make tax configuration trustworthy across all tenants.
- **Gap IDs included:** MD-29 (Critical).
- **Scope:** Global tables `tax_codes`, `vat_codes`, `atc_codes`. Replace `USING(true)` INSERT/UPDATE (and any implicit ALL) policies with authenticated read-only SELECT; route writes through governed `SECURITY DEFINER` maintainer RPCs that check an explicit maintainer authority, validate input, and write `sys_audit_logs` rows; apply least-privilege `REVOKE ... FROM PUBLIC`.
- **Exclusions:** `bir_forms`/`bir_form_mappings` (already governed under PXL-AUD-063 — do **not** re-touch). Company-scoped `ewt_codes`/`fwt_codes`/`percentage_tax_codes` (already member-gated). ATC source consolidation (that is MDP-12). No tax-rate value changes, no effective-date model changes.
- **Prerequisites:** None. Reuses the governance pattern already proven in migration `20260720000001_aud063_governed_bir_config_policy.sql` and test `059`.
- **Dependent modules & engines:** Tax Engine, Permissions/RLS Engine, Audit & Immutability Engine; Compliance/Tax and Administration & Security modules.
- **Complexity:** Small.
- **Impact:**
  - *Database:* drop/replace 3 tables' write policies; add a maintainer allowlist + maintainer RPCs (mirroring the BIR pattern; may reuse the same `bir_config_maintainers` allowlist or a tax-config equivalent — decide during design).
  - *UI:* none — discovery found no client reader/writer of these tables (tax setup UI reads company-scoped code tables).
  - *Security & RLS:* closes a **Critical** cross-tenant write hole; deny-by-default writes; `SECURITY DEFINER` functions must self-check authority and `REVOKE` PUBLIC to prevent audit spoofing.
  - *Audit:* new `sys_audit_logs` rows (old/new/actor/action/reason) on every governed tax-config change.
  - *Migration & seed:* one forward migration; no data backfill; existing seeded tax codes remain readable.
  - *Reporting:* none directly; protects the integrity of every tax report that reads these codes.
- **Regression risks:** Low. Only risk is a hidden server path that writes these tables as `authenticated` (none found in discovery) — confirm before locking. Company-scoped code tables reference `tax_codes`/`atc_codes` by FK for reads; read access is preserved.
- **Deliverables:** A formal finding raised in [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md) for the ungoverned tax-reference writes; one migration governing the three tables; one pgTAP test.
- **Acceptance criteria:** Direct authenticated INSERT/UPDATE/DELETE denied; governed RPC writes succeed only for a provisioned maintainer and are audited; reads preserved for ordinary users; the internal audit helper is not directly callable; clean `supabase db reset` replay passes; the full governed pgTAP lane remains green with no held-out test file.
- **Required automated tests:** pgTAP covering unauthorized/no-authority denial, governed write + audit-row assertion, rollback-on-failure (no orphan audit row), read preserved, and audit-helper spoof denial.
- **Required manual validation:** Re-query policy posture locally; confirm no tax-setup route regressed. The former PXL-AUD-055 operator dependency is resolved, but the hosted `pg_policies` re-query has not been executed and remains separate read-only certification evidence; local clean-replay evidence must not be presented as hosted proof.
- **Checklist sections:** §13 Security & Audit, §14 Localization.
- **Certification gates affected:** Gates 7 (tax correct), 13/14 (immutability, cross-company blocked), 21 (no Critical/High), 22 (documented limitations); Tax Engine and Permissions/RLS Engine invariants.
- **Rollback / recovery:** Forward-only; a compensating migration reinstating prior policies is the documented rollback. Idempotent guards (`DROP POLICY IF EXISTS`, `CREATE OR REPLACE`) make replay safe. No data is destroyed.
- **Relationship to PXL-AUD-063:** Same defect class and same reusable controls (read-only RLS, maintainer allowlist, `SECURITY DEFINER` RPCs, `sys_audit_logs`, `REVOKE PUBLIC`). **Difference:** PXL-AUD-063 governed BIR *form/mapping metadata*; MDP-01 governs the *tax-rate reference tables that feed computation*, which are consumed by company-scoped withholding codes and effective-dated — so the design must preserve read/FK access and effective-date semantics, and decide whether tax-config maintainers are the same authority as BIR-config maintainers or a distinct role. Do not duplicate the BIR controls; extend the proven pattern to the tax-rate tables only.

### MDP-02 — Master-Data Audit Coverage ✅ DONE (2026-07-21)

**Status: implemented (gap MD-30 resolved).** Migration `20260721000004_mdp02_master_data_audit_coverage.sql`, test `061` (26/26). The coverage inventory found the working tree already far ahead of the plan's base assumption: COA, payment_terms, number_series, departments, cost_centers, warehouses, bank_accounts, compliance_profiles, employees, approval_workflows, sys_feature_enablement, and all party/item/transaction masters were already `fn_audit_trigger`-covered, and the global statutory tables (`tax_codes`/`vat_codes`/`atc_codes`/`bir_forms`/`bir_form_mappings`) are correctly RPC-audited (MDP-01/PXL-AUD-063) — so they were consciously excluded to avoid double-logging. The genuinely uncovered masters in scope were exactly three company-scoped tables — `units_of_measure`, `item_categories`, `percentage_tax_codes` — now attached to the existing `fn_audit_trigger` (reused mechanism, no new pattern, no double-logging). `ewt_codes`/`fwt_codes`/`ref_atc_codes` do not exist (consolidated earlier). MDP-06/07/03 later completed the fiscal/config/membership and role-scope audit deferrals. No schema/RLS change, no backfill.

- **Business objective:** Capture every reference/config master change in the authoritative audit trail.
- **Gap IDs included:** MD-30 (High).
- **Scope:** Extend `fn_audit_trigger` coverage to COA, UOM, item categories, payment terms, number series, dimensions (departments, cost centers, warehouses), bank accounts, and the tax-code masters not already RPC-audited.
- **Exclusions:** Tables already audited (companies, branches, customers, suppliers, items, sales documents) and tables governed by dedicated RPC audit (BIR config; tax-reference after MDP-01) to avoid double logging.
- **Prerequisites:** None; sequence after MDP-01 so newly governed tables are consciously included or excluded.
- **Dependent modules & engines:** Audit & Immutability Engine; all master-owning modules.
- **Complexity:** Small–Medium.
- **Impact:**
  - *Database:* attach triggers to additional masters.
  - *UI:* none.
  - *Security & RLS:* none new (audit sink already governed).
  - *Audit:* broad new coverage of reference/config changes.
  - *Migration & seed:* one migration; no backfill.
  - *Reporting:* richer audit/change reports possible.
- **Regression risks:** Low; minor write overhead on high-write masters; global masters log NULL `company_id` (acceptable, matches existing convention).
- **Deliverables:** Migration extending trigger coverage; pgTAP proving audit rows on insert/update/delete per newly covered master.
- **Acceptance criteria:** Each targeted master writes correct old/new/actor/action rows; no duplicate logging where an RPC already audits.
- **Required automated tests:** pgTAP per-master audit assertions.
- **Required manual validation:** Edit a sample of newly covered masters and inspect `sys_audit_logs`.
- **Checklist sections:** §1 Master Data, §13 Security & Audit.
- **Certification gates affected:** Gates 5, 13, 20-equivalent audit evidence; Audit & Immutability Engine.
- **Rollback / recovery:** Drop the added triggers; purely additive, no data change.

### MDP-03 — Access Control & Segregation-of-Duties Model

**Status: implemented (gaps MD-27, MD-28 resolved).** Migration `20260722000007_mdp03_master_data_access_sod.sql`, test `072` (35/35), plus focused RLS regressions `011`/`013`/`014` and MDP-15 regression `071`; the current full pgTAP lane is green at 74 files / 1,568 assertions after MDP-14. Added a reusable `master_data_permissions` catalog for all MDP-15 registered masters, role mappings for existing `owner`/`admin`/`member`/`viewer` behavior, custom role-code compatibility on `user_company_memberships.role`, advisory `master_data_sod_conflicts`, optional `user_company_branch_scopes`, branch-aware helper/RLS rewiring for company-scoped masters, branch-filtered master-data export, hardened direct access to the renamed MDP-15 export implementation, and audit triggers for memberships, permissions, SOD metadata, and branch scopes. Existing user role semantics are preserved: owner/admin retain all master-data authority; members retain operational create/edit only; viewers remain read/export-only. MDP-14 now consumes this permission/SOD foundation for approval routing.

- **Business objective:** Provide professional role/permission control with branch-level scoping and enforceable SOD.
- **Gap IDs included:** MD-27, MD-28 (both High).
- **Scope:** A granular permission/role model beyond the four fixed membership roles; branch-level scoping of user access; supporting helpers and RLS updates; backfill of existing memberships to preserve current behavior.
- **Exclusions:** Approval routing (MDP-14, which depends on this); UI beyond the user/role admin surface; changing existing owner/admin/member/viewer semantics for already-provisioned users.
- **Prerequisites:** None, but it is foundational and precedes MDP-14.
- **Dependent modules & engines:** Permissions/RLS Engine, Approval & Workflow Engine, Audit Engine; Administration & Security module and **every** transactional module (access surface).
- **Complexity:** Large.
- **Impact:**
  - *Database:* role/permission master(s), branch-scope column(s) on memberships, updated policy helpers.
  - *UI:* user/role administration screens.
  - *Security & RLS:* **repo-wide** access-path change — the highest-blast-radius package.
  - *Audit:* role/permission grants and changes audited.
  - *Migration & seed:* multi-object migration with membership backfill.
  - *Reporting:* access-scoped visibility (branch-limited users).
- **Regression risks:** **High.** Any RLS regression risks tenant isolation or user lockout; the full company/branch isolation lane (tests 011, 056, and the complete suite) must stay green.
- **Deliverables:** Permission/role model; branch-scoped memberships; updated helpers/policies; migration with backfill.
- **Acceptance criteria:** Existing role behavior preserved; new roles enforce SOD; branch scoping filters correctly; all isolation tests pass; no user is inadvertently locked out or over-privileged.
- **Required automated tests:** pgTAP across roles and branch scopes; regression run of existing RLS/isolation tests and the full lane.
- **Required manual validation:** Multi-user, multi-branch access walk-through, including a deliberately restricted user.
- **Checklist sections:** §1 Master Data, §7 UX, §13 Security & Audit.
- **Certification gates affected:** Gates 5 (approval & permissions), 14 (cross-company blocked), 21; Permissions/RLS Engine (foundational).
- **Rollback / recovery:** Higher-risk rollback — the migration must be reversible (retain old policies until the new model is proven) and backfill must be idempotent; recovery plan: revert to the four-role policies. Rehearse rollback on a clean replay before hosted apply.

### MDP-04 — Chart of Accounts Enrichment ✅ DONE (2026-07-21)

**Status: implemented (gaps MD-09..MD-13 resolved).** Migration `20260721000005_mdp04_coa_enrichment.sql`, test `062` (23/23). Additive-only enrichment of `chart_of_accounts`: generated `fs_statement` (BS/IS), `fs_group`/`fs_subgroup`, `is_control_account`/`allow_subledger`/`subledger_type`, `cash_flow_category`, `is_tax_account`/`cost_behavior`/`is_capitalizable`/`is_operating_expense`, and `effective_from`/`effective_to` with vocabulary + order CHECK constraints. A `BEFORE INSERT/UPDATE` trigger auto-classifies `fs_group`/cash-flow (filling only NULLs, preserving refinements), and `fn_sync_coa_control_accounts` reconciles control/subledger/tax flags with `company_accounting_config` (reusable by MDP-05/07). Existing hierarchy, posting-vs-header, RLS, and audit coverage are unchanged; effective-date **enforcement** in the posting path is deferred to Phase 8 to preserve current posting logic. No engineering findings discovered.

- **Business objective:** Give the COA the classification metadata needed for configurable, statutory financial statements and clean subledger control.
- **Gap IDs included:** MD-09, MD-10, MD-11, MD-12, MD-13 (MD-09/10 High; rest Medium).
- **Scope:** Add FS classification/grouping (group, subgroup), control-account and allow-subledger flags, cash-flow classification, tax/direct-indirect/capitalizable/opex flags, and effective/active dates to `chart_of_accounts`, with sane backfill.
- **Exclusions:** The FS report rendering itself (Phase 8) beyond a proving fixture; company provisioning templates (MDP-05 consumes these fields); reconciliation of `company_accounting_config` beyond consistency checks.
- **Prerequisites:** None. Precedes MDP-05 and MDP-07.
- **Dependent modules & engines:** Reporting & Reconciliation Engine, Posting Engine; Accounting Core and Reports modules.
- **Complexity:** Medium–Large.
- **Impact:**
  - *Database:* several new COA columns + constraints + backfill.
  - *UI:* COA form/list additions.
  - *Security & RLS:* none new.
  - *Audit:* covered by MDP-02.
  - *Migration & seed:* columns + backfill of existing accounts to defensible defaults.
  - *Reporting:* **enables** configurable FS grouping and the cash-flow statement.
- **Regression risks:** Medium — posting and report reads of COA must be unaffected; control/subledger flags must agree with `company_accounting_config`.
- **Deliverables:** Migration adding classification columns with backfill; documented FS-grouping model.
- **Acceptance criteria:** Existing posting unchanged; new fields drive FS grouping in a fixture; control/subledger flags consistent with config; effective dates block out-of-window posting where intended.
- **Required automated tests:** pgTAP on constraints/backfill; a reporting fixture proving FS grouping from classification.
- **Required manual validation:** Build a sample FS from the enriched COA and confirm grouping.
- **Checklist sections:** §1 Master Data, §5 Reporting.
- **Certification gates affected:** Gates 2, 3, 6, 15; Reporting & Reconciliation and Posting engines.
- **Rollback / recovery:** Columns are additive; rollback drops them. Backfill is deterministic and re-runnable; no posted data altered.

### MDP-05 — Company Setup Defaults & Seed Templates ✅ DONE (2026-07-21)

**Status: implemented (gaps MD-01, MD-04-UOM, MD-05 resolved).** Migration `20260721000006_mdp05_company_setup_defaults.sql`, test `063` (25/25). Added global read-only `coa_templates`/`coa_template_lines` (seeded PH_STANDARD template carrying MDP-04 classification), and three admin-gated `SECURITY DEFINER` seed functions: `fn_seed_company_coa` (default template selection by `entity_type`, resolves parent hierarchy), `fn_seed_company_uom` (15-unit set), and `fn_seed_company_percentage_tax_codes`. MDP-08 later extended PH_STANDARD from 39 to 41 accounts with canonical Supplier Down Payments (asset) and Customer Advances (liability) accounts required by the existing posting contracts; test 063 was updated and remains 25/25. Inventory finding: EWT/FWT are global `atc_codes` (no per-company table), so only `percentage_tax_codes` is seeded. All idempotent (ON CONFLICT on existing `(company_id, code)` keys), company-isolated, and audited via existing triggers. No posting change; no engineering findings.

- **Business objective:** Let a new company start with a usable Philippine COA, UOM set, and withholding codes instead of an empty database.
- **Gap IDs included:** MD-01 (High), MD-04, MD-05 (Medium).
- **Scope:** Entity-type COA template(s) carrying MDP-04 classification; default UOM set; default withholding (EWT/FWT/PT) codes; idempotent seed functions callable at provisioning.
- **Exclusions:** The orchestration wizard (MDP-08); fiscal periods/number series (MDP-06); accounting config/compliance (MDP-07).
- **Prerequisites:** MDP-04 (templates must carry enriched COA fields).
- **Dependent modules & engines:** Posting Engine, Tax Engine, Number Series Engine (indirectly); Setup & Master Data and Accounting Core modules.
- **Complexity:** Large.
- **Impact:**
  - *Database:* template tables/seed functions.
  - *UI:* template selection in setup.
  - *Security & RLS:* seeded inserts must respect governance (MDP-01 for tax refs); seed functions `SECURITY DEFINER` with company-scope checks.
  - *Audit:* seed provenance recorded.
  - *Migration & seed:* seed data + provisioning functions.
  - *Reporting:* none directly (enables correct FS via correct COA).
- **Regression risks:** Medium — template correctness is high-leverage (a wrong classification propagates to every client); entity-type variance must be validated.
- **Deliverables:** Entity-type COA template(s), default UOM set, default withholding codes, seed functions.
- **Acceptance criteria:** A newly provisioned company has a balanced, correctly classified COA, a standard UOM set, and common withholding codes; re-seed is idempotent.
- **Required automated tests:** pgTAP verifying seeded COA balance/classification, UOM presence, withholding codes, and idempotency.
- **Required manual validation:** Provision a fresh non-demo company and inspect defaults.
- **Checklist sections:** §1 Master Data, §14 Localization.
- **Certification gates affected:** Gates 2, 3, 7; Tax and Posting engines.
- **Rollback / recovery:** Templates/seed functions are additive; rollback drops them. Seeded rows for a company can be removed via the same idempotent key; no other company affected.

### MDP-06 — Fiscal Calendar & Number Series Auto-Provisioning ✅ DONE (2026-07-21)

**Status: implemented (gaps MD-02, MD-03 resolved).** Migration `20260721000007_mdp06_fiscal_series_provisioning.sql`, test `064` (24/24). Added admin-gated `SECURITY DEFINER` functions: `fn_generate_fiscal_periods` (12 idempotent monthly periods), `fn_create_fiscal_year` (configurable start, derives is_calendar/end_date, generates periods), and `fn_provision_number_series` (default series per BIR-registered document type — SI/CS/OR — branch-aware, idempotent). Also completed MDP-02's deferred audit coverage for `fiscal_years`/`fiscal_periods` (reusing `fn_audit_trigger`; `number_series` already covered). Deliberate design: **explicit provisioning functions, not an INSERT trigger on `fiscal_years`**, so existing manual fiscal-year/period paths (e.g. CAS test 027) keep working. Excluded per scope: year-end close (Phase 8), numbering internals, posting-period validation, and the wizard (MDP-08). No RLS/posting change; no engineering findings.

- **Business objective:** Ensure a company can post and number documents immediately after setup.
- **Gap IDs included:** MD-02, MD-03 (both High).
- **Scope:** Auto-generate 12 fiscal periods on fiscal-year creation with lock controls; provision default number series per BIR-registered document type/branch.
- **Exclusions:** Year-end close logic (Phase 8); numbering-engine internals (already strong); the provisioning wizard (MDP-08).
- **Prerequisites:** None (independent of COA).
- **Dependent modules & engines:** Period Lock & Closing Engine, Number Series Engine, Posting Engine; Setup & Master Data module.
- **Complexity:** Medium.
- **Impact:**
  - *Database:* period-generation and series-provisioning functions.
  - *UI:* fiscal-year and series setup surfaces.
  - *Security & RLS:* admin-gated writes.
  - *Audit:* covered by MDP-02.
  - *Migration & seed:* functions + optional backfill for existing companies.
  - *Reporting:* period dimension available for all financials.
- **Regression risks:** Medium — posting depends on open periods and active series; period boundaries/locks must be correct.
- **Deliverables:** Period auto-generation; default series provisioning.
- **Acceptance criteria:** Fiscal-year creation yields correct open/locked periods; documents draw unique numbers with no manual series setup.
- **Required automated tests:** pgTAP on period generation and concurrent numbering uniqueness.
- **Required manual validation:** Create a fiscal year and a document end-to-end without manual series entry.
- **Checklist sections:** §1 Master Data, §12 Month-End & Year-End.
- **Certification gates affected:** Gates 2, 6, 12; Period Lock and Number Series engines.
- **Rollback / recovery:** Functions additive; rollback drops them. Generated periods/series for a company can be removed if unused; guard against deleting periods with posted journals.

### MDP-07 — Company Configuration, Compliance & Currency Provisioning ✅ DONE (2026-07-22)

**Status: implemented (gaps MD-06, MD-07, MD-31 resolved).** Migration `20260721000008_mdp07_company_config_compliance_currency.sql`, test `065` (24/24). Additive-only: (1) explicit `companies.functional_currency_code` / `reporting_currency_code` (default PHP, FK to `currencies`) for MD-31; (2) admin-gated `SECURITY DEFINER` `fn_provision_company_accounting_config` that idempotently creates the config row and maps control accounts from the company's own COA by canonical codes (fills NULLs only, so manual mappings survive), then reconciles COA flags via the reused MDP-04 `fn_sync_coa_control_accounts`; (3) `fn_validate_company_accounting_config` returning coherence problems; (4) `fn_provision_compliance_profile` deriving a default profile from `companies.tax_registration`. MDP-08 later completed all nine current accounting mappings and corrected the validator's account-type expectations to match established posting behavior: Customer Advances is a liability/receivable-subledger control and Supplier Down Payments is an asset/payable-subledger control. Test 065 remains 24/24 and test 073 covers both mappings. No posting/tax-calculation change and no new finding was warranted; the correction closes an integration defect in the completed package contract.

- **Business objective:** Auto-create and guide the accounting config, compliance profile, and functional currency a company needs to transact and file.
- **Gap IDs included:** MD-06, MD-07, MD-31 (all Medium).
- **Scope:** Default `company_accounting_config`, default `compliance_profiles`, an explicit company functional-currency field, and guided setup wiring.
- **Exclusions:** COA/UOM/tax seeding (MDP-05); multi-currency transaction processing (future); the wizard (MDP-08).
- **Prerequisites:** MDP-04 (accounts to map), MDP-05 (seeded accounts), MDP-01 (governed tax codes).
- **Dependent modules & engines:** Tax Engine, Currency Engine (scope-limited), Posting Engine; Compliance/Tax and Setup modules.
- **Complexity:** Medium.
- **Impact:**
  - *Database:* defaults for config/compliance; company currency column.
  - *UI:* guided config/compliance steps.
  - *Security & RLS:* admin-gated.
  - *Audit:* config change audit.
  - *Migration & seed:* columns + defaults.
  - *Reporting:* correct control-account and tax behavior downstream.
- **Regression risks:** Medium — mappings must stay consistent with MDP-04/05.
- **Deliverables:** Provisioned config/compliance rows; functional-currency field; guided wiring.
- **Acceptance criteria:** New company has valid control-account mappings, a coherent compliance profile, and an explicit functional currency.
- **Required automated tests:** pgTAP on defaults and constraints.
- **Required manual validation:** Inspect a provisioned company's config/compliance/currency.
- **Checklist sections:** §1 Master Data, §14 Localization.
- **Certification gates affected:** Gates 2, 6, 7; Tax and Currency engines.
- **Rollback / recovery:** Additive columns/defaults; rollback drops the currency column and defaults; existing PHP-implicit behavior unaffected.

### MDP-08 — Guided Company Provisioning Wizard ✅ DONE (2026-07-22)

**Status: implemented (gap MD-08 resolved).** Migration `20260722000008_mdp08_guided_company_provisioning.sql`, test `073` (50/50), and guided UI integration in `CompanyProvisioningWizard.tsx` / `CompanySetupPage.tsx`; current full pgTAP lane green at 74 files / 1,568 assertions after MDP-14. Added versioned, country/localization-aware company templates; an ordered extensible module registry over the existing MDP-05/06/07/09/11/13 primitives; deterministic side-effect-free request validation; MDP-03 `companies.create` enforcement with zero-company bootstrap; atomic/idempotent `fn_provision_company`; audited provisioning runs including retained failure metadata; company-code/TIN/fiscal/template/reference validation; and the PH_STANDARD template. The five-step UI captures company/tax/fiscal/currency/branch/warehouse/address/signatory inputs, validates server-side, and opens the existing setup checklist after success. Existing CSV company onboarding now calls the same service, so the application has no competing bare-company create path. No posting, inventory movement, approval, tax-engine, transaction-import, or unrelated API behavior changed.
- **Business objective:** A single guided flow that stands up a fully transactable company from the underlying seed/provisioning capabilities.
- **Gap IDs included:** MD-08 (High, umbrella).
- **Scope:** An orchestration function/flow assembling COA, periods, series, UOM, tax codes, config, compliance, and currency into one guided, idempotent provisioning path.
- **Exclusions:** Posting and transaction readiness; inventory movements; approval routing; generic master-data import/export internals (MDP-15).
- **Prerequisites:** MDP-05, MDP-06, MDP-07.
- **Dependent modules & engines:** all Setup engines; Setup & Master Data module.
- **Complexity:** Large.
- **Impact:**
  - *Database:* template/module/run metadata plus validation and atomic orchestration RPCs.
  - *UI:* **new multi-step wizard.**
  - *Security & RLS:* admin-gated; atomic provisioning.
  - *Audit:* provisioning provenance.
  - *Migration & seed:* PH_STANDARD company template and module composition; two missing PH_STANDARD control accounts.
  - *Reporting:* none directly.
- **Regression risks:** Medium — relies on prior packages; partial provisioning must be atomic/idempotent.
- **Deliverables:** Provisioning wizard orchestrating all setup defaults.
- **Acceptance criteria:** One guided flow atomically creates a complete configured company from a reusable template; duplicate/retry behavior is deterministic and no failed run retains partial business setup. Posting certification remains outside MDP-08.
- **Required automated tests:** Full provisioning, permission enforcement, template selection, validation failures, duplicate prevention, idempotency, company isolation, audit, and rollback.
- **Required manual validation:** Browser/hosted walkthrough remains part of later Setup & Master Data module certification, not this backend-first package freeze.
- **Checklist sections:** §1 Master Data, §7 UX.
- **Certification gates affected:** Gates 1, 2, 6, 19, 20; all Setup engines.
- **Rollback / recovery:** Orchestration must be transactional — a failed run leaves no partial company setup; recovery is re-run after fixing input.

### MDP-09 — Dimension Masters: Project, Location, Functional Entity ✅ DONE (2026-07-22)

**Status: implemented (gaps MD-14, MD-15, MD-16 resolved).** Migration `20260722000001_mdp09_dimension_masters.sql`, test `066` (32/32). Added three governed company-scoped masters — `projects`, `locations`, `functional_entities` — each branch-aware, self-referencing hierarchical (with a shared `fn_dimension_hierarchy_guard` enforcing no self-parent, same-company parent, and acyclic chains), effective-dated (`valid_from`/`valid_to` + window CHECK), `is_active` lifecycle, per-type vocabulary, and `UNIQUE(company_id, code)`; modeled on the existing `cost_centers` shape. Member-gated RLS (mirrors departments/cost_centers), audit coverage via the reused MDP-02 `fn_audit_trigger`, a reusable side-effect-free `fn_is_valid_dimension(type,id,company,branch,as_of)` checker for future transaction packages, and an admin-gated idempotent `fn_provision_company_dimension_defaults` (Head Office location + General functional entity) for the future MDP-08 wizard. Deliberately excluded per this session's scope: transaction-line propagation, posting/tax changes, reports, and Sales Invoice UX (owned by PXL-AUD-053) — `fn_is_valid_dimension` is provided as the contract those future packages call, but nothing is wired into posting here. No RLS change to existing tables; no engineering findings.

- **Business objective:** Govern the analytical dimensions currently ungoverned for transactions and reporting.
- **Gap IDs included:** MD-14, MD-15 (High), MD-16 (Medium).
- **Scope:** Three governed masters with effective dates, validity, company scope, and propagation to journal lines and reporting.
- **Exclusions:** Retrofitting all historical transactions; Sales Invoice UX changes owned by PXL-AUD-053 (coordinate, do not absorb).
- **Prerequisites:** None; coordinate with PXL-AUD-053.
- **Dependent modules & engines:** Dimension Engine, Reporting & Reconciliation Engine, Posting Engine; Sales/AR and Reports modules.
- **Complexity:** Medium–Large.
- **Impact:**
  - *Database:* three master tables + propagation columns.
  - *UI:* dimension setup + transaction pickers.
  - *Security & RLS:* company-scoped.
  - *Audit:* covered by MDP-02.
  - *Migration & seed:* new tables; optional line-column additions.
  - *Reporting:* **enables** dimension filters/roll-ups.
- **Regression risks:** Medium — propagation into posting and non-double-counting in reports.
- **Deliverables:** Project/Location/Functional Entity masters with propagation.
- **Acceptance criteria:** Dimensions are selectable, validated, propagated, and usable as report filters without double counting.
- **Required automated tests:** pgTAP on master validation and propagation; a reporting non-double-count assertion.
- **Required manual validation:** Tag a transaction and filter a report by each dimension.
- **Checklist sections:** §1 Master Data, §5 Reporting.
- **Certification gates affected:** Gates 2, 3, 15, 16; Dimension and Reporting engines.
- **Rollback / recovery:** New tables/columns are additive; rollback drops them; no posted data lost (dimensions nullable on lines).

### MDP-10 — Party Masters Enrichment ✅ DONE (2026-07-22)

**Status: implemented (gaps MD-17, MD-18, MD-19 resolved).** Migration `20260722000002_mdp10_party_masters_enrichment.sql`, test `067` (30/30). Added governed company-scoped `customer_groups`/`supplier_groups` masters + additive nullable `customers.customer_group_id`/`suppliers.supplier_group_id` FKs (legacy free-text `*_group` columns **preserved** and safely backfilled, non-destructive); a `party_contacts` multi-contact master linked to a customer XOR a supplier (CHECK + `fn_party_contact_company_guard` isolation, at-most-one-primary partial unique indexes; the single embedded `contact_person` preserved and backfilled as primary); and `fn_party_tin_duplicates(company,type,tin,exclude)` side-effect-free duplicate detection. **Inventory correction to the plan:** Philippine TIN normalization and the canonical `XXX-XXX-XXX-XXXXX` format are **already fully implemented** (`20260715000001_philippine_tin_standard.sql`), so MD-19 reduced to duplicate *detection* only — no hard unique constraint (legitimate branch/dual-role duplicates exist). Member-gated RLS (mirrors customers/suppliers), audit coverage via the reused MDP-02 `fn_audit_trigger`. No posting/tax change; existing party records preserved and never rewritten; no engineering findings.

- **Business objective:** Bring customer/supplier masters to professional completeness (groups, contacts, TIN control).
- **Gap IDs included:** MD-17, MD-18, MD-19 (all Medium).
- **Scope:** Customer/supplier group masters; a contacts master linked to parties; TIN duplicate detection/warning; backfill of existing free-text groups.
- **Exclusions:** Credit-management workflow beyond existing `credit_limit`; salesperson (MDP-11).
- **Prerequisites:** None.
- **Dependent modules & engines:** AR and AP engines; Sales/AR, Purchasing/AP modules.
- **Complexity:** Medium.
- **Impact:**
  - *Database:* group masters, contacts master, TIN uniqueness/warn rule.
  - *UI:* party forms (group select, multi-contact).
  - *Security & RLS:* company-scoped.
  - *Audit:* covered by MDP-02.
  - *Migration & seed:* new tables + backfill of free-text groups.
  - *Reporting:* group-based party analysis.
- **Regression risks:** Low–Medium — migrating free-text groups into governed masters must not orphan existing parties.
- **Deliverables:** Group masters; contacts master; TIN duplicate control.
- **Acceptance criteria:** Groups governed and selectable; multiple contacts per party; duplicate-TIN entry warned/blocked per policy; existing parties preserved.
- **Required automated tests:** pgTAP on group FK, contact linkage, TIN duplicate rule.
- **Required manual validation:** Create parties with groups/contacts; attempt a duplicate TIN.
- **Checklist sections:** §1 Master Data.
- **Certification gates affected:** Gates 2, 3; AR/AP engines.
- **Rollback / recovery:** Additive; rollback drops new tables/rules and restores free-text group reliance; backfill is reversible.

### MDP-11 — Attribution & Reference Masters ✅ DONE (2026-07-22)

**Status: implemented (gaps MD-20, MD-25, MD-26 resolved).** Migration `20260722000003_mdp11_attribution_reference_masters.sql`, test `068` (28/28). Added: (MD-20) governed salesperson/buyer **designation** on the `employees` master — `is_salesperson`/`is_buyer` flags + reusable `fn_is_valid_attribution(kind,employee,company)` checker — rather than a duplicate table, because `sales_invoices.salesperson_id` already → `employees(id)` (that FK/SI validation is unchanged); (MD-25) global read-only `ref_banks` reference master (MDP-01 governance, seeded PH banks) + additive nullable `bank_accounts.bank_id` FK with legacy `bank_name` preserved and best-effort backfilled; (MD-26) `company_payment_modes` company-scoped master referencing global `ref_payment_modes`, each mapped to a **postable same-company GL account** enforced by `fn_company_payment_mode_gl_guard`, member-gated + audited. **Boundary respected:** `ref_payment_modes` and every existing `payment_mode_id` FK, plus banking/treasury/AR-AP/ownership, are untouched — reusable reference masters only. Member-gated RLS, MDP-02 audit reuse. No posting/tax change; existing records preserved; no engineering findings.

- **Business objective:** Add the small reference masters professional operations expect (salesperson, bank, richer payment modes).
- **Gap IDs included:** MD-20, MD-25 (Medium), MD-26 (Low).
- **Scope:** Salesperson master (may derive from employees); bank reference master; company-scoped payment modes with GL mapping.
- **Exclusions:** Commission calculation (future); bank reconciliation logic (Phase 5).
- **Prerequisites:** None.
- **Dependent modules & engines:** Payment & Application Engine, Reporting Engine; Sales/AR, Banking modules.
- **Complexity:** Small–Medium.
- **Impact:**
  - *Database:* salesperson master, bank reference master, payment-mode scope + GL mapping.
  - *UI:* setup lists + transaction pickers.
  - *Security & RLS:* company-scoped.
  - *Audit:* covered by MDP-02.
  - *Migration & seed:* new tables/columns.
  - *Reporting:* sales-by-salesperson; bank standardization.
- **Regression risks:** Low — bank reference must not break existing free-text `bank_accounts.bank_name`.
- **Deliverables:** Salesperson master; bank reference master; company-scoped payment modes with GL mapping.
- **Acceptance criteria:** Salesperson selectable on sales documents; bank accounts reference the bank master; payment modes map to GL.
- **Required automated tests:** pgTAP on new masters and FKs.
- **Required manual validation:** Use each new master on a document.
- **Checklist sections:** §1 Master Data, §4 Banking.
- **Certification gates affected:** Gates 2, 3; Payment engine (indirect).
- **Rollback / recovery:** Additive; rollback drops new masters/columns; existing free-text/global payment modes still function.

### MDP-12 — Tax Reference Consolidation ✅ DONE (2026-07-22)

**Status: implemented / verified (gap MD-32 was already resolved by prior work).** Migration `20260722000004_mdp12_tax_reference_consolidation.sql`, test `069` (16/16). **Inventory correction — the plan was stale:** the "two parallel ATC representations" no longer exist. `ref_atc_codes` was created (`20260629000007`) then **dropped** (`20260629000014`) with its data + FKs (`receipt_lines.atc_code_id`, `form_2307_tracking.atc_code_id`) migrated/repointed to `atc_codes`; `ewt_codes`/`fwt_codes` were also consolidated away (`20260714000003`). `atc_codes` is the single authoritative ATC source, and `tax_codes`/`vat_codes`/`atc_codes` already share one governance+versioning pattern (effective dating, `supersedes_*`, version-aware uniqueness, immutability-after-use, `fn_tax_code_version_asof`/`fn_atc_version_asof` resolvers, MDP-01 read-only + RPC audit). Every expected-scope item already existed, so building new tables/resolvers would duplicate functionality. This package therefore adds ONLY a thin, additive, **read-only consolidation surface** — `vw_tax_reference_catalog` (unifies `tax_codes` ∪ `atc_codes` with a computed `is_current`) and `fn_tax_reference_asof(reference_type, code, tax_category, as_of)` (a facade delegating to the existing resolvers) — plus a regression test that locks the consolidated invariants. No tax-engine/posting change; no new source of truth; no engineering findings.

- **Business objective:** Remove the risk of divergence between the two parallel ATC representations.
- **Gap IDs included:** MD-32 (Medium).
- **Scope:** Consolidate `atc_codes` and `ref_atc_codes` to one authoritative source; repoint FKs; deprecate the duplicate.
- **Exclusions:** ATC write governance (delivered in MDP-01); changing ATC rate values.
- **Prerequisites:** MDP-01 (governance in place before restructuring).
- **Dependent modules & engines:** Tax Engine, Reporting Engine; Compliance/Tax module.
- **Complexity:** Medium.
- **Impact:**
  - *Database:* consolidate two tables; repoint references.
  - *UI:* none directly.
  - *Security & RLS:* governed writes (from MDP-01).
  - *Audit:* change audit.
  - *Migration & seed:* data consolidation + FK repoint (higher-touch migration).
  - *Reporting:* consistent ATC in tax reports and 2307.
- **Regression risks:** Medium — repointing FKs and preserving historical ATC references; withholding/2307 tests must stay green.
- **Deliverables:** One authoritative ATC source; migrated references; duplicate deprecated.
- **Acceptance criteria:** All ATC consumers read one source; tax reports and 2307 evidence unchanged.
- **Required automated tests:** pgTAP + rerun of withholding/2307 tests.
- **Required manual validation:** Inspect a 2307 and a withholding report.
- **Checklist sections:** §14 Localization.
- **Certification gates affected:** Gates 7, 15; Tax and Reporting engines.
- **Rollback / recovery:** Data-migrating — must be reversible with the pre-consolidation snapshot retained; rehearse on clean replay; keep the deprecated table until consumers are verified.

### MDP-13 — Item Master Inventory Readiness ✅ DONE (2026-07-22)

**Status: implemented (gaps MD-21, MD-22, MD-23, MD-24 resolved).** Migration `20260722000005_mdp13_item_master_inventory_readiness.sql`, test `070` (41/41). Added: (MD-21/22) `company_inventory_config` (company default costing method + negative-stock policy + default warehouse; admin-gated, guarded, audited) with `fn_provision_company_inventory_config` / `fn_validate_company_inventory_config` (MDP-07 pattern), item-level `negative_stock_policy` override, and never-NULL resolvers `fn_item_costing_method` / `fn_item_negative_stock_policy` (item override → company default → literal); (reorder) additive `max_stock_level`/`safety_stock`/`reorder_quantity` (non-negative CHECK) alongside the existing `min_stock_level`/`reorder_point`, plus `preferred_supplier_id` (same-company guard), `track_serial`/`track_batch` capability flags; (MD-23) `item_uom_conversions` (per-item alternate UOMs, factor>0, one-per-UOM); (MD-24) `item_barcodes` (multi-barcode, one-primary, unique-per-company; single `items.barcode` preserved) and `item_media` (image/document metadata, one-primary). All child masters share a company-isolation guard (`fn_item_child_company_guard`), member-gated RLS, and MDP-02 audit. No inventory movement/valuation/costing engine, no UI, no posting change; existing items untouched (resolvers avoid destructive `costing_method` backfill). No engineering findings.

- **Business objective:** Complete item-master fields that Phase 4 (Inventory) certification will depend on.
- **Gap IDs included:** MD-21, MD-22 (Medium), MD-23, MD-24 (Low).
- **Scope:** Negative-stock policy field (company/item); enforced costing method with a company default; item UOM conversions; item media/barcodes.
- **Exclusions:** Inventory posting/costing engine changes (Phase 4); landed cost (future).
- **Prerequisites:** None; complete before Phase 4.
- **Dependent modules & engines:** Inventory Engine, Posting Engine; Inventory module.
- **Complexity:** Medium.
- **Impact:**
  - *Database:* item columns + optional conversion/media tables + costing backfill.
  - *UI:* item form.
  - *Security & RLS:* company-scoped.
  - *Audit:* covered by MDP-02.
  - *Migration & seed:* columns/tables + costing backfill.
  - *Reporting:* none directly.
- **Regression risks:** Medium — backfilling `costing_method` must not change existing valuation history.
- **Deliverables:** Negative-stock policy; enforced costing + company default; item UOM conversions; media/barcodes.
- **Acceptance criteria:** Every item has a costing method and negative-stock policy; conversions/media usable.
- **Required automated tests:** pgTAP on costing/negative-stock fields.
- **Required manual validation:** Configure an item and verify Phase-4 readiness fields.
- **Checklist sections:** §3 Inventory, §7 UX.
- **Certification gates affected:** Gates 2, 9; Inventory Engine (invariants 10, 21).
- **Rollback / recovery:** Additive; rollback drops fields; costing backfill is deterministic and does not alter posted movements.

### MDP-14 — Approval Matrix Integration ✅ DONE (2026-07-22)

**Status: implemented (gap MD-33 resolved).** Migration `20260722000009_mdp14_approval_matrix_integration.sql`, focused test `074` (61/61), targeted tests 011/014/050/071/072/073 (171/171), and complete pgTAP lane 74 files / 1,568 assertions. The implementation extends the existing workflow/step/instance tables rather than creating a second approval system; adds an audited `approval_requests` lifecycle header; maps steps to existing membership role codes or users; resolves company, optional branch, module/record, action, amount, currency, requester context, effective dates, and active state; and exposes server-authoritative decision, submission, approve, reject, withdraw, status, and inbox RPCs.

- **Business objective:** Make the existing approval infrastructure a usable, role-based approval matrix.
- **Gap IDs included:** MD-33 (Medium), resolved.
- **Implemented scope:** Deterministic multi-level role/user routing; MDP-03 permission, branch-scope, and enforced/advisory SOD integration; requester/approver separation; inactive-user and missing-approver validation; version-bound stale-request protection; duplicate actionable-request uniqueness; row locking and lifecycle guards; MDP-02 audit reuse; role-aware configuration and inbox exposure on the existing page; opt-in approval enforcement for configured MDP-15 import commits.
- **Rule precedence:** Highest constrained-criteria count first; then branch, document, action, requester user, requester role, currency, non-`always` condition, highest matching amount threshold, explicit priority, newest effective start, creation time, and UUID. This guarantees a more specific valid rule wins before broader fallback rules.
- **Default behavior:** No approval rules are seeded. Preview imports and all unconfigured workflows retain prior behavior. MDP-08 provisioning remains compatible and does not create unsafe rules.
- **Exclusions:** Authentication/RLS redesign; new role model; posting/inventory/tax changes; transaction-wide rollout; approval bypass; transaction workspace redesign.
- **Dependent modules & engines:** Approval & Workflow Engine, Permissions/RLS Engine, Audit Engine; future transaction consumers.
- **UI:** Existing Approval Workflow page now supports current rule criteria, role-code steps, permission-aware maintenance, and the server-filtered inbox. It does not claim transaction-wide support.
- **Security and concurrency:** Request/instance mutations are RPC-only; tenant/branch permissions and route eligibility are rechecked server-side; approvals lock the request and current instance; stale, repeated, self, wrong-role, inactive-user, and invalid-state actions are denied.
- **Rollback / recovery:** Additive/configuration-first. Removing or deactivating a rule restores unconfigured behavior; no default rules or posted-data changes are introduced. Migration replay was executed a second time with `ON_ERROR_STOP=1` and passed.
- **Certification impact:** All Master Data implementation packages are complete, but Setup & Master Data is not Certified. Approval & Workflow and Permissions/RLS also remain uncertified; AUD-055 remains active and broad transaction rollout is deferred.

### MDP-15 — Master-Data Import/Export Tooling ✅ DONE
- **Business objective:** Enable practical onboarding import and non-trapping export of master data.
- **Gap IDs included:** MD-34 (Medium), MD-35 (Low).
- **Implemented evidence:** migration `20260722000006_mdp15_master_data_import_export.sql`; test `supabase/tests/071_mdp15_master_data_import_export_test.sql` (38 assertions, passed 2026-07-22 after clean local migration replay).
- **Scope:** Backend-first validated master-data import templates with error reporting, preview, idempotent commit, rollback-safe execution, company isolation, import/export operation audit, and standardized deterministic JSON export.
- **Exclusions:** Transaction/opening-balance import (Phase 11); report export (Phase 8); UI wizard/screens.
- **Prerequisites:** All master schemas finalized (MDP-04, 05, 07, 09, 10, 11, 13) so templates match the final shape.
- **Dependent modules & engines:** all master-owning modules; Attachment & Traceability Engine (provenance).
- **Complexity:** Large.
- **Impact:**
  - *Database:* registry, import batch/row logs, export logs, validation/import/export RPCs.
  - *UI:* none in this package; future screens can call the backend RPCs.
  - *Security & RLS:* import must respect RLS and governance (no bypass).
  - *Audit:* import provenance.
  - *Migration & seed:* tooling, not base data.
  - *Reporting:* export formats.
- **Regression risks:** Low (additive) — but import must validate and roll back cleanly and never bypass governance/RLS.
- **Deliverables:** `master_data_import_registry`, import templates, `fn_validate_master_data_import`, `fn_import_master_data`, `fn_export_master_data`, `fn_export_master_data_package`, import/export audit logs.
- **Acceptance criteria:** Representative current masters validate/import with row-level errors, preview no-op, duplicate handling, idempotency, rollback on commit failure, company isolation, hierarchy preservation, deterministic export hash/logging, and statutory tax references remain governed/export-only.
- **Required automated tests:** Done in test 071: import validation + rollback tests; export completeness/hash checks; isolation and hierarchy regression.
- **Required manual validation:** Import a sample dataset and export it back.
- **Checklist sections:** §10 Import/Export, §11 Opening Balance & Migration.
- **Certification gates affected:** Gates 2, 22; Attachment & Traceability Engine; supports client-exit operational requirements.
- **Rollback / recovery:** Import is transactional with staged validation — a failed import commits nothing; export is read-only.

## Recommended Execution Order

| Seq | Package | Complexity | Key dependency | Rationale |
| --- | --- | --- | --- | --- |
| 1 | MDP-01 Tax-Reference Write Governance ✅ DONE | Small | none | Closes the sole Critical gap; protects tax integrity; proven pattern |
| 2 | MDP-02 Master-Data Audit Coverage ✅ DONE | Small–Med | after MDP-01 | Cheap, high governance value; strengthens all later work |
| 3 | MDP-03 Access Control & SOD ✅ DONE | Large | none | Foundational security; unblocks approvals; highest risk, validated with full regression |
| 4 | MDP-04 Chart of Accounts Enrichment ✅ DONE | Med–Large | none | Foundation for FS and for provisioning templates |
| 5 | MDP-06 Fiscal Calendar & Number Series ✅ DONE | Medium | none | Independent; unblocks posting/numbering |
| 6 | MDP-05 Company Setup Defaults & Templates ✅ DONE | Large | MDP-04 | Seeds usable COA/UOM/withholding |
| 7 | MDP-07 Config, Compliance & Currency ✅ DONE | Medium | MDP-04, 05, 01 | Completes transactable-company config |
| 8 | MDP-08 Guided Provisioning Wizard ✅ DONE | Large | MDP-03, 05, 06, 07, 09, 11, 13 | Atomic template orchestration and guided UI delivered |
| 9 | MDP-09 Dimension Masters ✅ DONE | Med–Large | coordinate PXL-AUD-053 | Governs Project/Location/Functional Entity |
| 10 | MDP-10 Party Masters Enrichment ✅ DONE | Medium | none | Groups, contacts, TIN control |
| 11 | MDP-11 Attribution & Reference Masters ✅ DONE | Small–Med | none | Salesperson, bank, payment modes |
| 12 | MDP-12 Tax Reference Consolidation ✅ DONE | Medium | MDP-01 | Removes ATC divergence risk (already consolidated; verified) |
| 13 | MDP-13 Item Master Inventory Readiness ✅ DONE | Medium | before Phase 4 | Prepares item master for Inventory phase |
| 14 | MDP-14 Approval Matrix Integration ✅ DONE | Medium | MDP-03 | Role-based, version-bound approval foundation and bounded MDP-15 import integration delivered |
| 15 | MDP-15 Master-Data Import/Export ✅ DONE | Large | schemas final | Backend import/export foundation implemented after schema-shaping packages |

Current remaining Master Data implementation packages: **none**. All 15 packages are implemented and validated. Module certification remains a separate evidence review.

## Roadmap-level notes

- **Dependencies:** completed chains include MDP-04 → MDP-05 → MDP-07 → MDP-08, MDP-01 → MDP-12, all schema-shaping masters through MDP-13, backend import/export through MDP-15, access/SOD foundation through MDP-03, and approval integration through MDP-14.
- **Highest remaining regression risk:** Broad transaction adoption of the approval foundation is deferred and must be certified per consumer; it is not a remaining Master Data implementation package.
- **Hosted validation dependency:** MDP-01 and PXL-AUD-063 are locally proven and recorded Retested Passed. The former PXL-AUD-055 operator dependency is resolved; the hosted policy re-query is still unexecuted and remains separate read-only certification evidence, not a remaining MDP implementation package.
- **Certification linkage:** completing these packages advances Setup & Master Data and the Permissions/RLS, Dimension, and (via MDP-01/12) Tax engines toward their gates; **no package certifies a module on its own**, and status changes only in [`PXL_CERTIFICATION_MATRIX.md`](PXL_CERTIFICATION_MATRIX.md) after the standards' evidence is met.

## Call-outs

- **Packages identified:** 15 (MDP-01 … MDP-15), covering all 35 gaps (MD-01 … MD-35) with no overlap.
- **Highest-risk packages completed:** MDP-08 (Guided Company Provisioning) and MDP-14 (Approval Matrix Integration), validated with 50 and 61 focused assertions respectively plus the complete 74-file / 1,568-assertion lane.
- **Recommended next action:** Setup & Master Data Module Certification Review.
- **Remaining implementation package:** None.
