# PXL Master Data Implementation Plan

**Status:** Active Phase 1 implementation roadmap
**Authority:** Tier 2 Planning — the authoritative execution roadmap for the Setup & Master Data certification phase
**Owner / Domain:** Testing and Validation / Architecture
**Applies To:** Sequencing and scoping of every Master Data implementation session
**Read When:** Selecting or scoping the next Master Data implementation package
**Do Not Read For:** Gap detail (use [`../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md`](../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md)), certification method (use the certification standards), defect status (use [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md)), or current bounded task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-20 roadmap revision 2 — enriched per-package specs (scope/exclusions, dependent modules & engines, separated impact dimensions, certification gates, rollback); validated against the current local working tree

## Purpose

This roadmap converts the 35 gaps in the [Master Data Gap Register](../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md) into **15 bounded implementation packages** (MDP-01 … MDP-15) covering every gap with no overlap. Each package is independently reviewable, testable, and certifiable, and is scoped small enough for one controlled implementation session where practical. This document plans; it implements nothing and changes no certification status. It follows the gates in [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md), the engine contracts in [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md), and the capability expectations in [`PXL_PRODUCT_COMPLETENESS_CHECKLIST.md`](PXL_PRODUCT_COMPLETENESS_CHECKLIST.md).

Source-of-truth note: this revision was validated against the current local working tree. The gap register (severity Critical 1 / High 11 / Medium 19 / Low 4 = 35; IDs MD-01…MD-35 contiguous) and the five certification framework documents currently exist as **untracked** local files that are complete and internally consistent; they are treated as authoritative. No committed-versus-uncommitted conflict was found among the authority set.

## Packaging method

Gaps were grouped by the object they change and the concern they serve, so each package touches one cohesive surface and can be verified end-to-end. Every package below states explicit scope and exclusions, its dependent modules and engines, impact separated across Database / UI / Security & RLS / Audit / Migration & seed / Reporting, regression risk, deliverables, acceptance criteria, required automated and manual validation, the Product Completeness Checklist sections affected, the certification gates affected, and rollback/recovery. Complexity is **Small / Medium / Large**. No package may weaken RLS, immutability, or tenant isolation to pass, and each lands its own deterministic tests. Certification gate numbers refer to the 23 module gates in the Module Certification Standard.

## Package Register

### MDP-01 — Tax-Reference Write Governance ✅ DONE (2026-07-20)

**Status: implemented and Retested Passed as PXL-AUD-068** — migration `20260721000001_mdp01_tax_reference_write_governance.sql`, test `060`, and `src/pages/TaxSetupPage.tsx` rewired to the RPCs. Working-tree reality differed from the assumptions below: writes were already `is_any_company_admin()`-gated (not `USING(true)`), the audit trigger already covered these tables, and a live UI writer (`TaxSetupPage`) existed. Delivered model: tables read-only, mutations via governed SECURITY DEFINER RPCs with authority `is_any_company_admin() OR fn_is_bir_config_maintainer()` (preserving current admins), existing audit trigger retained (no double-logging). Residual: restricting to maintainer-only is a follow-up product decision. Original plan preserved below for provenance.

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
- **Acceptance criteria:** Direct authenticated INSERT/UPDATE/DELETE denied; governed RPC writes succeed only for a provisioned maintainer and are audited; reads preserved for ordinary users; the internal audit helper is not directly callable; clean `supabase db reset` replay passes; full pgTAP lane shows no new failures beyond the known PXL-AUD-066 held-out CAS assertions.
- **Required automated tests:** pgTAP covering unauthorized/no-authority denial, governed write + audit-row assertion, rollback-on-failure (no orphan audit row), read preserved, and audit-helper spoof denial.
- **Required manual validation:** Re-query policy posture locally; confirm no tax-setup route regressed. **Hosted `pg_policies` re-query is deferred** — it rides the same authorized-operator step that gates **PXL-AUD-055** (externally blocked key rotation); local clean-replay evidence stands in the interim, and the finding stays open on the hosted-confirmation dependency exactly as PXL-AUD-063 did.
- **Checklist sections:** §13 Security & Audit, §14 Localization.
- **Certification gates affected:** Gates 7 (tax correct), 13/14 (immutability, cross-company blocked), 21 (no Critical/High), 22 (documented limitations); Tax Engine and Permissions/RLS Engine invariants.
- **Rollback / recovery:** Forward-only; a compensating migration reinstating prior policies is the documented rollback. Idempotent guards (`DROP POLICY IF EXISTS`, `CREATE OR REPLACE`) make replay safe. No data is destroyed.
- **Relationship to PXL-AUD-063:** Same defect class and same reusable controls (read-only RLS, maintainer allowlist, `SECURITY DEFINER` RPCs, `sys_audit_logs`, `REVOKE PUBLIC`). **Difference:** PXL-AUD-063 governed BIR *form/mapping metadata*; MDP-01 governs the *tax-rate reference tables that feed computation*, which are consumed by company-scoped withholding codes and effective-dated — so the design must preserve read/FK access and effective-date semantics, and decide whether tax-config maintainers are the same authority as BIR-config maintainers or a distinct role. Do not duplicate the BIR controls; extend the proven pattern to the tax-rate tables only.

### MDP-02 — Master-Data Audit Coverage
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

### MDP-04 — Chart of Accounts Enrichment
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

### MDP-05 — Company Setup Defaults & Seed Templates
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

### MDP-06 — Fiscal Calendar & Number Series Auto-Provisioning
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

### MDP-07 — Company Configuration, Compliance & Currency Provisioning
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

### MDP-08 — Guided Company Provisioning Wizard
- **Business objective:** A single guided flow that stands up a fully transactable company from the underlying seed/provisioning capabilities.
- **Gap IDs included:** MD-08 (High, umbrella).
- **Scope:** An orchestration function/flow assembling COA, periods, series, UOM, tax codes, config, compliance, and currency into one guided, idempotent provisioning path.
- **Exclusions:** The underlying capabilities themselves (MDP-05/06/07 deliver them); import tooling (MDP-15).
- **Prerequisites:** MDP-05, MDP-06, MDP-07.
- **Dependent modules & engines:** all Setup engines; Setup & Master Data module.
- **Complexity:** Large.
- **Impact:**
  - *Database:* orchestration function only.
  - *UI:* **new multi-step wizard.**
  - *Security & RLS:* admin-gated; atomic provisioning.
  - *Audit:* provisioning provenance.
  - *Migration & seed:* orchestration; no new base data.
  - *Reporting:* none directly.
- **Regression risks:** Medium — relies on prior packages; partial provisioning must be atomic/idempotent.
- **Deliverables:** Provisioning wizard orchestrating all setup defaults.
- **Acceptance criteria:** One guided flow produces a company that can post an end-to-end document with no manual setup; re-run is safe.
- **Required automated tests:** Integration test: full provisioning → post a document.
- **Required manual validation:** Complete the wizard for each entity type.
- **Checklist sections:** §1 Master Data, §7 UX.
- **Certification gates affected:** Gates 1, 2, 6, 19, 20; all Setup engines.
- **Rollback / recovery:** Orchestration must be transactional — a failed run leaves no partial company setup; recovery is re-run after fixing input.

### MDP-09 — Dimension Masters: Project, Location, Functional Entity
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

### MDP-10 — Party Masters Enrichment
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

### MDP-11 — Attribution & Reference Masters
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

### MDP-12 — Tax Reference Consolidation
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

### MDP-13 — Item Master Inventory Readiness
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

### MDP-14 — Approval Matrix Integration
- **Business objective:** Make the existing approval infrastructure a usable, role-based approval matrix.
- **Gap IDs included:** MD-33 (Medium).
- **Scope:** Role-based approver assignment; integrate approval routing on at least one document type; SOD enforcement (creator ≠ approver where configured).
- **Exclusions:** Building the role model (MDP-03 delivers it); rolling approval to every document type (incremental after proof).
- **Prerequisites:** MDP-03 (role model).
- **Dependent modules & engines:** Approval & Workflow Engine, Permissions Engine; Sales/AR and other transaction modules.
- **Complexity:** Medium.
- **Impact:**
  - *Database:* approver-assignment config; instance wiring.
  - *UI:* approval config + inbox.
  - *Security & RLS:* SOD enforcement.
  - *Audit:* approval events.
  - *Migration & seed:* config tables.
  - *Reporting:* approval status visibility.
- **Regression risks:** Medium — must not block posting where approval is unconfigured; SOD must be provable.
- **Deliverables:** Role-based approver assignment; integrated routing on one document type.
- **Acceptance criteria:** Approval routes by role; SOD prevents self-approval where configured; unconfigured documents post normally.
- **Required automated tests:** pgTAP/integration on routing and SOD.
- **Required manual validation:** Route a document through approval as different roles.
- **Checklist sections:** §2 Transactions, §13 Security.
- **Certification gates affected:** Gates 4, 5; Approval & Workflow Engine.
- **Rollback / recovery:** Config-driven; rollback disables routing and restores direct approval; no posted data affected.

### MDP-15 — Master-Data Import/Export Tooling
- **Business objective:** Enable practical onboarding import and non-trapping export of master data.
- **Gap IDs included:** MD-34 (Medium), MD-35 (Low).
- **Scope:** Validated master-data import templates with error reporting and safe rollback; standardized master-data export.
- **Exclusions:** Transaction/opening-balance import (Phase 11); report export (Phase 8).
- **Prerequisites:** All master schemas finalized (MDP-04, 05, 07, 09, 10, 11, 13) so templates match the final shape.
- **Dependent modules & engines:** all master-owning modules; Attachment & Traceability Engine (provenance).
- **Complexity:** Large.
- **Impact:**
  - *Database:* staging/validation structures.
  - *UI:* import/export screens.
  - *Security & RLS:* import must respect RLS and governance (no bypass).
  - *Audit:* import provenance.
  - *Migration & seed:* tooling, not base data.
  - *Reporting:* export formats.
- **Regression risks:** Low (additive) — but import must validate and roll back cleanly and never bypass governance/RLS.
- **Deliverables:** Validated import templates; standardized export.
- **Acceptance criteria:** A client's master data imports with error reporting and safe rollback; exports match on-screen values.
- **Required automated tests:** Import validation + rollback tests; export parity checks.
- **Required manual validation:** Import a sample dataset and export it back.
- **Checklist sections:** §10 Import/Export, §11 Opening Balance & Migration.
- **Certification gates affected:** Gates 2, 22; Attachment & Traceability Engine; supports client-exit operational requirements.
- **Rollback / recovery:** Import is transactional with staged validation — a failed import commits nothing; export is read-only.

## Recommended Execution Order

| Seq | Package | Complexity | Key dependency | Rationale |
| --- | --- | --- | --- | --- |
| 1 | MDP-01 Tax-Reference Write Governance | Small | none | Closes the sole Critical gap; protects tax integrity; proven pattern |
| 2 | MDP-02 Master-Data Audit Coverage | Small–Med | after MDP-01 | Cheap, high governance value; strengthens all later work |
| 3 | MDP-03 Access Control & SOD | Large | none | Foundational security; unblocks approvals; highest risk, do early with full regression |
| 4 | MDP-04 Chart of Accounts Enrichment | Med–Large | none | Foundation for FS and for provisioning templates |
| 5 | MDP-06 Fiscal Calendar & Number Series | Medium | none | Independent; unblocks posting/numbering |
| 6 | MDP-05 Company Setup Defaults & Templates | Large | MDP-04 | Seeds usable COA/UOM/withholding |
| 7 | MDP-07 Config, Compliance & Currency | Medium | MDP-04, 05, 01 | Completes transactable-company config |
| 8 | MDP-08 Guided Provisioning Wizard | Large | MDP-05, 06, 07 | Orchestrates the seed capabilities |
| 9 | MDP-09 Dimension Masters | Med–Large | coordinate PXL-AUD-053 | Governs Project/Location/Functional Entity |
| 10 | MDP-10 Party Masters Enrichment | Medium | none | Groups, contacts, TIN control |
| 11 | MDP-11 Attribution & Reference Masters | Small–Med | none | Salesperson, bank, payment modes |
| 12 | MDP-12 Tax Reference Consolidation | Medium | MDP-01 | Removes ATC divergence risk |
| 13 | MDP-13 Item Master Inventory Readiness | Medium | before Phase 4 | Prepares item master for Inventory phase |
| 14 | MDP-14 Approval Matrix Integration | Medium | MDP-03 | Role-based approvals (Phase 2) |
| 15 | MDP-15 Master-Data Import/Export | Large | schemas final | Onboarding import + export; runs last |

## Roadmap-level notes

- **Dependencies:** the only hard chains are MDP-04 → MDP-05 → (MDP-07, MDP-08); MDP-01 → MDP-12; MDP-03 → MDP-14; and MDP-15 after all schema-changing masters. MDP-02, MDP-06, MDP-09, MDP-10, MDP-11, MDP-13 are largely independent and can be reordered around capacity.
- **Highest regression risk:** MDP-03 (repo-wide RLS/permission change) — must run the full isolation/RLS lane; then MDP-08 and MDP-04 by breadth of consumers.
- **Hosted validation dependency:** MDP-01 (like PXL-AUD-063) can be fully proven locally but its hosted `pg_policies` confirmation rides the authorized-operator step that also gates **PXL-AUD-055** (externally deferred key rotation). Plan MDP-01 to land with local clean-replay evidence and an open hosted-confirmation dependency, not a blocked implementation.
- **Certification linkage:** completing these packages advances Setup & Master Data and the Permissions/RLS, Dimension, and (via MDP-01/12) Tax engines toward their gates; **no package certifies a module on its own**, and status changes only in [`PXL_CERTIFICATION_MATRIX.md`](PXL_CERTIFICATION_MATRIX.md) after the standards' evidence is met.

## Call-outs

- **Packages identified:** 15 (MDP-01 … MDP-15), covering all 35 gaps (MD-01 … MD-35) with no overlap.
- **Highest-risk package:** MDP-03 (Access Control & SOD) — changes access control across every table.
- **Smallest safe first package:** MDP-01 (Tax-Reference Write Governance) — one migration + one test, on a pattern already proven under PXL-AUD-063.
- **First implementation session:** MDP-01, beginning by raising the formal finding for the ungoverned `tax_codes`/`vat_codes`/`atc_codes` writes.
