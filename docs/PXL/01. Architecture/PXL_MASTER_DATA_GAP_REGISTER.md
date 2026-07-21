# PXL Master Data Gap Register

**Status:** Active Phase 1 implementation blueprint
**Authority:** Tier 2 Architecture — the authoritative gap analysis and implementation blueprint for the Setup & Master Data certification phase
**Owner / Domain:** Architecture / Master Data
**Applies To:** Every master-data and reference entity consumed by PXL, ahead of Phase 1 certification
**Read When:** Planning or implementing any Master Data phase work, or checking a master-data capability gap
**Do Not Read For:** Defect status (use [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md)), certification method (use the certification standards), or current bounded task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-20 Phase 1 master-data discovery

## Purpose

This register is the output of the Phase 1 **Master Data discovery and gap analysis** for the PXL Production Certification Program. It inventories every master-data and reference entity, evaluates each against professional-ERP and Philippine-compliance expectations in [`../13. Testing and Validation/PXL_PRODUCT_COMPLETENESS_CHECKLIST.md`](../13. Testing and Validation/PXL_PRODUCT_COMPLETENESS_CHECKLIST.md) and the master-data gates in [`../13. Testing and Validation/PXL_MODULE_CERTIFICATION_STANDARD.md`](../13. Testing and Validation/PXL_MODULE_CERTIFICATION_STANDARD.md), and records the gaps that must close before Setup & Master Data can be certified.

It implements nothing and changes no status. It is the blueprint the Master Data implementation sessions will execute against, one bounded scope at a time. Defects that require formal tracking (notably the Critical tax-reference governance gap below) must be raised in the central findings register during an implementation session; this document does not mint finding IDs.

Evidence base: the executed migration schema under `supabase/migrations/` (145 tables), the transaction and field-source matrices, and `AI/AI_STATE.md`. Where this register cites current behavior, it reflects the migration schema as of 2026-07-20.

## Evaluation method

Every entity was evaluated across 18 dimensions: (1) business purpose, (2) required fields, (3) optional fields, (4) relationships, (5) validation rules, (6) default values, (7) Philippine localization, (8) dependencies, (9) security, (10) audit, (11) import/export, (12) search, (13) printing/reporting usage, (14) future compatibility, (15) missing functionality, (16) missing fields, (17) UX observations, (18) Product Completeness Checklist compliance. Findings that fail a professional-user expectation are captured as numbered gaps.

Severity: **Critical** (breaks accounting/tax/security/data integrity), **High** (blocks Phase 1 certification or professional onboarding), **Medium** (material completeness gap, non-blocking with disclosure), **Low** (desirable refinement). Effort: **Small** (localized), **Medium** (multi-object), **Large** (new subsystem or wide change).

## 1. Entity Inventory

Scope legend: **Global** = single shared reference (no `company_id`); **Company** = per-tenant; **—** = not present.

| Entity | Present | Scope | Headline assessment |
| --- | --- | --- | --- |
| Company (`companies`) | Yes | Company | Rich legal/tax identity; **no functional-currency field**; no automatic provisioning of dependent setup |
| Branch (`branches`) | Yes | Company | Strong (TIN branch code, RDO, tax-reg override); adequate |
| Department (`departments`) | Yes | Company | Adequate; hierarchical |
| Cost Center (`cost_centers`) | Yes | Company | Adequate; typed, effective-dated |
| Warehouse (`warehouses`) + Zones | Yes | Company | Good (GL inventory/variance accounts, zones) |
| Location (dimension) | **—** | — | **Missing master** (used by SI dimensions, ungoverned) |
| Project (dimension) | **—** | — | **Missing master** (ungoverned for SI per PXL-AUD-053) |
| Functional Entity (dimension) | **—** | — | **Missing master** (ungoverned for SI) |
| Chart of Accounts (`chart_of_accounts`) | Yes | Company | **Thin**: no FS classification, control-account/subledger flags, cash-flow class, effective dates |
| Customers (`customers`) | Yes | Company | Good (tax type, CWT default, terms/currency/GL); group is free text; single contact |
| Suppliers (`suppliers`) | Yes | Company | Good (EWT default/ATC); group free text; single contact |
| Contacts | **—** | — | **Missing** multi-contact master |
| Items / Services (`items`) | Yes | Company | Service handled via `item_type`; costing nullable; no negative-stock policy field |
| Item Categories (`item_categories`) | Yes | Company | Good (account defaults, hierarchy) |
| Units of Measure (`units_of_measure`) | Yes | Company | Structure supports conversion; **no default set provisioned** |
| Customer Groups | **—** (free text) | — | **No governed group master** |
| Supplier Groups | **—** (free text) | — | **No governed group master** |
| Payment Terms (`payment_terms`) | Yes | Company | Adequate (days, downpayment) |
| Payment Methods (`ref_payment_modes`) | Yes | Global | Adequate; no company scope / GL mapping per mode |
| Tax Codes (`tax_codes`) | Yes | Global | Effective-dated; **ungoverned authenticated writes** |
| VAT Codes (`vat_codes`) | Yes | Global | Effective-dated; **ungoverned authenticated writes** |
| EWT Codes (`ewt_codes`) | Yes | Company | Governed writes (company-member); adequate |
| FWT Codes (`fwt_codes`) | Yes | Company | Adequate |
| Percentage Tax (`percentage_tax_codes`) | Yes | Company | Adequate |
| ATC Codes (`atc_codes` + `ref_atc_codes`) | Yes | Global | **Two parallel ATC representations**; `atc_codes` ungoverned writes |
| Currencies (`currencies`) + rates | Yes | Global + Company | Present; multi-currency not wired into transactions (future) |
| Banks (reference) | **—** | — | **No bank master**; `bank_accounts.bank_name` is free text |
| Bank Accounts (`bank_accounts`) | Yes | Company | Good (GL mapping, opening balance) |
| Fiscal Calendar (`fiscal_years` / `fiscal_periods`) | Yes | Company | Solid; **no auto-generation of periods** |
| Number Series (`number_series`) | Yes | Company | Strong (ATP fields, reset); **not auto-provisioned** |
| Document Types (`ref_document_types`) | Yes | Global | Adequate (BIR-registered flag) |
| Employees (`employees`) | Yes | Company | Rich (gov IDs); not linked to `auth.users`; no auto-numbering |
| Salespersons | **—** | — | **No master** (no sales attribution dimension) |
| Users / Memberships (`user_company_memberships`) | Yes | Company | 4 fixed roles; **company-level only, no branch scope** |
| Roles / Permissions | **—** (text enum) | — | **No granular role/permission master** |
| Approval Matrix (`approval_workflows` + steps + instances) | Yes | Company | Infrastructure present; **not integrated/proven**; no role-based approver assignment |
| Company Preferences (`company_accounting_config`) | Yes | Company | Control accounts held here; **not auto-created/guided** |
| System Preferences (`sys_feature_enablement` / `ref_feature_definitions`) | Yes | Global + Company | Feature-flag model present; adequate |
| Compliance Profile (`compliance_profiles`) | Yes | Company | Rich statutory profile; **not auto-created/guided** |
| RDO (`ref_rdo_codes`) | Yes | Global | Adequate reference |
| Reason / Void codes (`ref_reason_codes`, `void_reason_codes`) | Yes | Global/Company | Present |
| Audit log (`sys_audit_logs`) | Yes | Global | Master-data coverage completed for MDP-02 scope (MD-30 resolved); global statutory tables are RPC-audited |

## 2. Per-Entity Assessment Highlights

- **Company & dependent setup:** company creation grants ownership only. It does **not** create a Chart of Accounts, fiscal year/periods, number series, UOM, per-company tax codes, accounting config, or compliance profile. Each is built manually today (demo companies rely on seed scripts, not a product provisioning path). This is the dominant Phase 1 theme.
- **Chart of Accounts:** holds type, normal balance, `is_postable`, currency, parent, active flag — enough to post, but **not enough to configure statutory financial statements** (no FS grouping/subgroup, no control-account or subledger flags, no cash-flow classification, no effective dates). Control accounts live in `company_accounting_config`, so COA and config must be reconciled.
- **Dimensions:** branch, department, cost center, warehouse, project-site (as a branch type) exist; **Project, Location, and Functional Entity have no masters**, matching the standing PXL-AUD-053 note that these are ungoverned for Sales Invoice.
- **Parties:** customer/supplier masters are strong on tax attributes (tax type, EWT/CWT defaults, terms, currency, GL) but treat **groups as free text**, support only a **single embedded contact**, and enforce **uniqueness by code but not by TIN**.
- **Tax reference governance:** `ewt_codes`/`fwt_codes`/`percentage_tax_codes` are company-scoped with member-gated writes, but **`tax_codes`, `vat_codes`, and `atc_codes` are global with `FOR ALL/INSERT/UPDATE ... USING(true)` policies** — any authenticated user can alter shared tax rates. This is the same governance defect class as the resolved PXL-AUD-063 (BIR forms) but applied to tax rates themselves.
- **Security masters:** roles are a fixed four-value enum with **no granular permissions and no branch-level scoping**, which is insufficient for the segregation-of-duties expectations of the module standard and completeness checklist.
- **Audit coverage:** RESOLVED (MDP-02, 2026-07-21). `sys_audit_logs` triggers cover companies, branches, parties, items, sales/transaction documents, and the reference/config masters (COA, payment terms, number series, dimensions, bank accounts, compliance profiles, and — added by MDP-02 — UOM, item categories, percentage-tax codes). The global statutory tax-reference and BIR-config tables are deliberately RPC-audited (MDP-01/PXL-AUD-063), not trigger-audited, to avoid double-logging. Membership, accounting-config, and fiscal-calendar audit remain with their owning packages (MDP-03/06/07).

## 3. Master Data Gap Register

The authoritative, actionable list. Checklist refs point to sections of the Product Completeness Checklist. "Candidate finding" means the gap must be raised in the central findings register during an implementation session.

| ID | Gap | Entity | Severity | Effort | Phase | Checklist ref | Recommendation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MD-29 | ~~Global `tax_codes` / `vat_codes` / `atc_codes` permit ungoverned authenticated writes~~ **RESOLVED 2026-07-21 (MDP-01 / PXL-AUD-068).** Tables are read-only; all mutations flow through governed SECURITY DEFINER RPCs with **maintainer-only** authority and end-to-end audited change reasons; statutory codes normalized. MDP-01 is frozen as the canonical governance template (migrations `20260721000001` + `20260721000002`, test 060 = 29/29). | Tax/VAT/ATC codes | **Critical → resolved** | Medium | 1 / 7 | §14, §13 | Done. Maintainer-only authority decision made and enforced; no residual. |
| MD-01 | ~~No Chart of Accounts template seeded on company creation~~ **RESOLVED 2026-07-21 (MDP-05).** Added global `coa_templates`/`coa_template_lines` (seeded PH_STANDARD, classified per MDP-04) and admin-gated `fn_seed_company_coa` with default template selection by entity_type (migration `20260721000006`, test 063). The provisioning *wizard* remains MDP-08. | Company / COA | **High → resolved** | Large | 1 | §1 | Done (backend capability; wizard = MDP-08). |
| MD-02 | ~~No automatic fiscal-year / 12-period generation~~ **RESOLVED 2026-07-21 (MDP-06).** Added `fn_create_fiscal_year` (configurable start) + `fn_generate_fiscal_periods` (12 idempotent monthly periods), admin-gated, with audit coverage of the fiscal tables (migration `20260721000007`, test 064). | Fiscal calendar | **High → resolved** | Medium | 1 | §1, §12 | Done (backend capability). |
| MD-03 | ~~No automatic number-series provisioning per branch/document type~~ **RESOLVED 2026-07-21 (MDP-06).** Added `fn_provision_number_series` seeding default series per BIR-registered document type, branch-aware and idempotent (migration `20260721000007`, test 064). | Number series | **High → resolved** | Medium | 1 | §1 | Done. |
| MD-08 | No unified company provisioning wizard orchestrating COA, periods, series, UOM, tax codes, config, and profile | Company | High | Large | 1 | §1, §7 | Build a guided provisioning flow (umbrella for MD-01–07) |
| MD-09 | ~~COA lacks FS classification / statement grouping~~ **RESOLVED 2026-07-21 (MDP-04).** Added generated `fs_statement` (BS/IS from account_type) plus `fs_group`/`fs_subgroup` with an auto-classification invariant and backfill (migration `20260721000005`, test 062). | COA | **High → resolved** | Medium | 1 / 8 | §1, §5 | Done. |
| MD-10 | ~~COA lacks explicit control-account and allow-subledger flags~~ **RESOLVED 2026-07-21 (MDP-04).** Added `is_control_account`/`allow_subledger`/`subledger_type` and `fn_sync_coa_control_accounts` reconciling them with `company_accounting_config` (migration `20260721000005`, test 062). | COA | **High → resolved** | Medium | 1 | §1 | Done. |
| MD-14 | No Project dimension master | Dimensions | High | Medium | 1 | §1, §5 | Add governed Project master with effective dates and propagation |
| MD-15 | No Location dimension master | Dimensions | High | Medium | 1 | §1, §5 | Add governed Location master |
| MD-27 | Role model limited to owner/admin/member/viewer; no accountant/approver/encoder roles or granular permission master | Roles/Permissions | High | Large | 1 | §1, §13 | Introduce a permission/role master supporting SOD |
| MD-28 | User access is company-level only; no branch-level scoping | Memberships | High | Medium | 1 | §1, §13 | Add branch scoping to memberships and RLS |
| MD-30 | ~~Reference/config master changes are not audit-trigger covered~~ **RESOLVED 2026-07-21 (MDP-02).** Inventory found most masters (COA, payment_terms, number_series, departments, cost_centers, warehouses, bank_accounts, compliance_profiles, …) already `fn_audit_trigger`-covered and the global statutory tables correctly RPC-audited (MDP-01/PXL-AUD-063). The three genuinely uncovered company-scoped masters — `units_of_measure`, `item_categories`, `percentage_tax_codes` — now carry `fn_audit_trigger` (migration `20260721000004`, test 061 = 26/26); no double-logging. | Audit / masters | **High → resolved** | Medium | 1 | §1, §13 | Done. Membership/config/fiscal audit remains with their owning packages (MDP-03/06/07). |
| MD-04 | ~~No default per-company UOM set~~ **RESOLVED 2026-07-21 (MDP-05).** Added `fn_seed_company_uom` seeding a standard 15-unit set, idempotent and admin-gated (migration `20260721000006`, test 063). | UOM | **Medium → resolved** | Small | 1 | §1 | Done. |
| MD-05 | ~~No default per-company EWT/FWT/PT code provisioning~~ **RESOLVED 2026-07-21 (MDP-05).** Inventory confirmed EWT/FWT are global `atc_codes` (no per-company table); the only company-scoped withholding master is `percentage_tax_codes`, now seeded by `fn_seed_company_percentage_tax_codes` (migration `20260721000006`, test 063). | Tax codes | **Medium → resolved** | Medium | 1 / 7 | §1, §14 | Done. |
| MD-06 | `company_accounting_config` not auto-created or guided | Company prefs | Medium | Small | 1 | §1 | Create at provisioning; surface in guided setup |
| MD-07 | `compliance_profiles` not auto-created or guided | Compliance profile | Medium | Small | 1 / 7 | §1, §14 | Create at provisioning; guide tax-registration choices |
| MD-11 | ~~COA lacks cash-flow classification~~ **RESOLVED 2026-07-21 (MDP-04).** Added `cash_flow_category` (operating/investing/financing) with P&L→operating default; cash-flow statement rendering remains Phase 8 (migration `20260721000005`, test 062). | COA | **Medium → resolved** | Medium | 1 / 8 | §5 | Done. |
| MD-12 | ~~COA lacks tax classification / direct-indirect / capitalizable / opex flags~~ **RESOLVED 2026-07-21 (MDP-04).** Added `is_tax_account` (config-reconciled), `cost_behavior` (direct/indirect), `is_capitalizable`, `is_operating_expense` (migration `20260721000005`, test 062). | COA | **Medium → resolved** | Small | 1 | §1 | Done. |
| MD-13 | ~~COA lacks effective/active date window~~ **RESOLVED 2026-07-21 (MDP-04).** Added `effective_from`/`effective_to` with an order CHECK; posting-path enforcement deferred to Phase 8 to preserve current posting logic (migration `20260721000005`, test 062). | COA | **Medium → resolved** | Small | 1 | §1 | Done. |
| MD-16 | No Functional Entity dimension master | Dimensions | Medium | Medium | 1 | §1 | Add governed master if retained in scope |
| MD-17 | Customer/Supplier groups are free text (no governed group masters) | Parties | Medium | Small | 1 | §1 | Add customer/supplier group masters |
| MD-18 | No multi-contact master (single embedded contact only) | Contacts | Medium | Medium | 1 | §1 | Add contacts master linked to parties |
| MD-19 | Party uniqueness enforced by code but not by TIN | Parties | Medium | Small | 1 | §1 | Add TIN duplicate detection/warning |
| MD-20 | No Salesperson master (no sales attribution/commission dimension) | Salespersons | Medium | Small | 1 / 2 | §1, §5 | Add salesperson master (may derive from employees) |
| MD-21 | No explicit negative-stock policy field (company/item) | Items | Medium | Small | 4 | §3 | Add policy field; default block |
| MD-22 | `costing_method` nullable; no company default costing policy | Items | Medium | Small | 4 | §1, §3 | Enforce a costing method with a company default |
| MD-25 | No bank reference master; `bank_accounts.bank_name` is free text | Banks | Medium | Small | 1 / 5 | §1, §4 | Add bank reference master |
| MD-31 | Company has no functional-currency field (implicit PHP) | Company | Medium | Small | 1 | §1 | Add explicit functional currency |
| MD-32 | Two parallel ATC representations (`atc_codes` vs `ref_atc_codes`) risk divergence | ATC codes | Medium | Medium | 1 / 7 | §14 | Consolidate or define one authoritative source |
| MD-33 | Approval workflow infrastructure not integrated/proven; no role-based approver assignment | Approval matrix | Medium | Medium | 2 | §2 | Integrate and prove approval routing with SOD |
| MD-34 | No master-data import templates/tooling for onboarding | Import/Export | Medium | Large | 1 / 11 | §10, §11 | Provide validated import templates |
| MD-23 | No multi-UOM conversion at the item level | Items/UOM | Low | Medium | 4 | §3 | Add item UOM conversions (partly future) |
| MD-24 | No item attachments/images/multiple barcodes | Items | Low | Small | 4 | §7 | Add item media/barcodes |
| MD-26 | `ref_payment_modes` lacks company scope and GL mapping per mode | Payment methods | Low | Small | 5 | §4 | Add company scoping / GL mapping |
| MD-35 | No standardized master-data export | Import/Export | Low | Medium | 8 / 9 | §10 | Provide governed master-data export |

**Totals by severity:** Critical 1 · High 11 · Medium 19 · Low 4 · **Total 35**.

## 4. Recommended Master Data Implementation Order

Execute as focused, bounded implementation sessions, each with migration + tests + doc updates and no scope creep:

1. **Security & governance first (unblocks certification integrity):** MD-29 (raise finding, then govern tax-reference writes), MD-30 (audit coverage), MD-27/MD-28 (roles, permissions, branch scoping).
2. **Chart of Accounts completeness:** MD-09, MD-10, MD-11, MD-12, MD-13 (FS/control/subledger/cash-flow/classification/effective dates).
3. **Company provisioning:** MD-01, MD-02, MD-03, MD-04, MD-05, MD-06, MD-07, then MD-08 (wizard umbrella), MD-31.
4. **Dimensions:** MD-14, MD-15, MD-16 (Project, Location, Functional Entity) — coordinates with PXL-AUD-053.
5. **Parties & attribution:** MD-17, MD-18, MD-19, MD-20, MD-25.
6. **Items & inventory masters:** MD-21, MD-22 (before Phase 4), MD-23, MD-24.
7. **Approval & onboarding tooling:** MD-33, MD-34; MD-26, MD-32, MD-35 as cleanup.

## 5. First Implementation Task (next session)

**MD-29 — Govern global tax-reference table writes.** In one bounded session: raise a formal finding in [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md) for the ungoverned `tax_codes` / `vat_codes` / `atc_codes` write policies, then apply the governed pattern already proven for BIR config (PXL-AUD-063): replace `USING(true)` writes with authenticated read-only policies plus a governed maintainer RPC path with `sys_audit_logs` evidence, add focused pgTAP coverage, and validate from a clean migration replay. This is the highest-severity master-data gap and directly protects tax correctness; it must precede broader master-data enrichment.
