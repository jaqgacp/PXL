# PXL AI State

**Current Date:** 2026-07-26
**Current Branch:** `main`
**Working Tree:** Dirty, uncommitted local certification work through migrations `20260726000015` and tests `078`–`103`. Preserve unrelated user changes; no commit exists.
**Product Phase:** Production Certification Program plus the governed Inventory Accounting Architecture Program. IA-5 landed as an additive dormant foundation, but its permanent-foundation certification is **SUSPENDED** by the IA-5/IA-6 Final Evidence Gate (Outcome C, C-01 Critical); ADR-C01 freezes the chronology policy, ECC-01 (its derivation) is **owner accepted 2026-07-26, not frozen**, and the **authorized phase is IA-5 ECC Hardening WP-1**. **IA-6 remains unauthorized.** Four shared engines remain Certified, COA Engine Phase A is landed, and Posting Engine P1/P2/P3/P4/P5.0/P5.1/P5.2 remains certified. The Kernel Totality Guard is **FULLY ENFORCED**. P5.3B, P6, and P7 remain paused.
**Environment:** Authorized non-production hosted project `bskjkogijpbhukjkagfj`; migration history synchronized through `20260716000005`. Every local migration from `20260723000001` onward is NOT yet applied to the hosted project. Do not reset, seed, migrate, repair, link, or otherwise mutate the hosted project without explicit approval. Local reset/test work is permitted.
**Product Readiness:** Internal QA/demo only. PXL is not production-ready and not pilot-ready while module/engine certification evidence is incomplete. No module is Certified; four shared engines are Certified.

## Current Finding Standing

Generated from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **90 Retested Passed / 0 In Progress / 0 Open (90 total)**.

- Active Critical / High / Medium: none. Every audit finding is Retested Passed.

## Active Work Map

A closed findings register certifies no module. Coverage governance runs through `PXL_TABLE_COVERAGE_MATRIX.md` plus guard `075`; a new `public` base table needs a registry entry in both. Next work is Production Certification execution, not defect remediation.

## Hosted and UX Status

The five canonical companies are hosted-operator owned; ABC Trading carries the high-volume demo data. Last hosted automation passed 48/48 company/master/document and 20/20 report probes. Table coverage is governed under PXL-AUD-059 (176 local tables).

`PXL_TRANSACTION_WORKSPACE_STANDARD.md` and `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` remain the transaction UI authorities. Sales Invoice is one implementation; business qualification remains source-gated. Non-SI rows remain `transaction-matrix-only`.

## Documentation Cleanup Status

Active docs live under `docs/PXL/00. Governance/` … `13. Testing and Validation/`; only the master index and findings register sit in the `docs/PXL` root. Superseded material is archived or in trash-review.

## Production Certification Program

The program certifies every module and shared engine toward controlled production use. The permanent framework is four documents under `docs/PXL/13. Testing and Validation/`: `PXL_MODULE_CERTIFICATION_STANDARD.md` (23 gates), `PXL_ENGINE_CERTIFICATION_STANDARD.md`, `PXL_PRODUCT_COMPLETENESS_CHECKLIST.md`, and `PXL_CERTIFICATION_MATRIX.md` (dashboard only). Do not create per-module status files or duplicate registers.

Four engines are Certified: **Permissions/RLS**, **Audit & Immutability**, **Number Series**, **Dimension** (2026-07-22/23). Setup & Master Data is **Blocked on missing evidence, not defects** (Gate 23 backup/restore absent; Gate 20 browser evidence recorded-only). No module is Certified.

Phase order: (1) Setup/Master Data + foundational engines; (2) Sales/AR; (3) Purchasing/AP; (4) Inventory; (5) Banking/Payments; (6) Fixed Assets; (7) Compliance/Tax; (8) Reports/FS; (9) Production Ops, Backup/Restore, Deployment, Pilot. Phase 9 backup/restore evidence does not exist and must not be claimed.

## Known Blockers and Non-Assumptions

- Every migration from `20260723000001` through the IA-5 migration set ending `20260726000015` is local-only; hosted application needs explicit approval before any hosted claim.
- Banking, fixed assets, returns, broad approval rollout, schedules, statutory generators, and CAS artifacts are not proven complete.
- Do not assume green checklists mean operational readiness, or a rendered route means source-backed correctness.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body.

## Last Verified Commands

Posting Engine P1/P2/P3 — **landed 2026-07-24/25, zero accounting change**; full record in `PXL_POSTING_ENGINE_SPEC.md`, `PXL_POSTING_ENGINE_P3_SPEC.md`. P1 (`082`) inert infrastructure; P2 resolver adoption complete (`083`–`086`); P3 (`087`–`089`) made `fn_add_posting_line` a pure persistence helper (an additive overload is NOT deployment-safe — drop-and-recreate), wired `fn_assert_manual_postable` into `fn_post_manual_je`, and converged the one self-projecting GL preview onto the resolver — **resolver convergence only; full Preview ≡ Actual remains P8**. **Observation:** run regression on a fresh no-seed schema (`npm run test:db:local`); test 073 fails atop a canonical seed (pre-existing).

Posting Engine P4 — **Tax Boundary Certification 2026-07-26; no migration, zero behaviour change** (test `090`; **Amendment A2** §5.3.1). **No Tax Engine and no `TaxComponent` object exists**; the real gap is *above* the Posting Engine. Census **20** tax-aware posting writers: **0** read `company_accounting_config`, **19** do no tax arithmetic, the 5 reading `atc_codes.rate` use it as ledger **provenance only**, `fn_save_cash_sale` is the sole computing writer (**registered Tax Engine migration candidate**). **GL↔ledger variance exactly 0.00**; reversal preserves the original rate. **Not claimed:** Tax Engine certified, Tax Component exists, PH tax completeness, or removal of the **seven duplicated save-layer calculators** (registered debt in `PXL_PRODUCT_BACKLOG.md`).

Posting Engine P5.0 — **Surface Closure landed 2026-07-26, zero accounting change** (migration `20260726000001`, test `091`; **Amendment A3** §4.6.1). Closed the **external** write surface: `fn_add_posting_line` is no longer executable by `authenticated`, **zero** GL writers retain a PUBLIC/`anon` grant, and six derived accounting tables deny all `authenticated` writes — all 28 writers are SECURITY DEFINER. **Demonstrated bypass, since closed:** a member could tamper `stock_balances.wac_unit_cost`, read for COGS by `fn_post_sales_invoice`. **Excluded by decision:** `bank_recon_items` and `book_tax_reconciliation` are written **directly by the UI**.

Posting Engine P5.1 — **historical, superseded by P5.2** (migrations `20260726000002`–`20260726000011`, tests `092`–`101`; full record in `PXL_POSTING_ENGINE_SPEC.md`). All **24 authoritative forward writers** plus the four legacy SI/VB/OR/CP header UPDATE paths were drained of direct ledger mutation, leaving ledger DML only in the six sanctioned persistence functions; exact-name classifier anchoring closed lookalike inheritance. Canonical replay: **0 writers / 0 violation events**, fingerprints identical.

Posting Engine P5.2 — **FULLY ENFORCED, zero accounting change** (migration `20260726000012`, test `102`, read-only census `supabase/verification/p52_kernel_security_census.sql`). Guard enforcement is compile-time `true`; both totality triggers are `ENABLE ALWAYS`; client ledger DML and guard-function execution are revoked; no maintenance, replay, replica-trigger, RPC, SECURITY DEFINER, role, or owner-SQL bypass exists. All 48 unauthorized operation/table/path attempts reject (12 privilege `42501`, 36 guard `23514`), zero persisted mutation; the sanctioned classifier remains exactly six. Census: 409 app functions / 349 SECURITY DEFINER / 80 ledger mutators (all SECURITY DEFINER, kernel-reaching) / zero client-writable ledger tables. Full clean regression: 102 files / 2,254 assertions; canonical: 30 files / 748 assertions; debit = credit = `2,411,134.80` / zero violations. P6 has not begun.

Posting Engine P6 — **BLOCKED at Inventory; investigation only**. Stock-to-GL variances 2,400.00 / 21,000.00 / 6,630.00; layer-to-stock 2,420.00 / 12,600.00 / 3,930.00. Receiving Reports add stock without journals while Vendor Bills debit purchase clearing. Remedy requires prohibited engine or certified-data changes. Full evidence: Posting Engine §5.4.1. P7 has not begun.

Inventory Accounting IA-5 — **landed and dormant, zero accounting change** (`20260726000013`–`20260726000015`, test `103`). Its certification claim in `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` is **suspended**: the **IA-5/IA-6 Final Evidence Gate returned Outcome C** (`IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md`) because the per-scope accepted sequence is allocated by row-lock order, so identical same-time receipt/issue evidence produced opposite orders across schedules. C-01 is a **Critical permanent-foundation defect**; H-01…H-09 and M-01 remain provisional and unexecuted. `fn_receive_inventory(jsonb)` is internalized pending IA-7 retirement.

Inventory chronology architecture — **ADR-C01 frozen**; **ECC-01 is `ACCEPTED — OWNER APPROVED` (2026-07-26), freeze NOT exercised** (`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`; change control still runs through its Supersession Rule). Its acceptance gate closed Outcome B (ADR-C01 conformity 14/14; nine defects resolved in Amendment A1, V-31…V-35), and **ECC-A-11 (PG-01 cited but absent) is resolved as Outcome B** by the non-normative `00. Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md`; ADR-C01 was not edited. ECC-01 derives economic order from source facts, never lock/arrival order (14 components, 8-stage algorithm, four proofs, 35 validation / 15 failure rules). The **IA-5 ECC hardening design is controlling; WP-1 is authorized** (`ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md`, Outcome A; zero-data verified read-only, `inventory_events` = 0). The C-01 stop stays open pending executable conformance evidence (ADR-C01 §17).

COA Engine Phase A — **landed, In Progress (not Certified)** 2026-07-24 per the frozen `PXL_COA_ENGINE_SPEC.md` (#19), via `20260724000001` + test `081`: `ref_mapping_key`, `account_mapping`, fail-closed `fn_resolve_account`, config→mapping sync, lifecycle/change guards, FS registry. `company_accounting_config` remains the single writable authority. **Not Certified** until Phase B satisfies gates 2/4.

Dimension Engine — **CERTIFIED** 2026-07-23 (fourth), `20260723000003` + test `080`: all six governed dimensions reach posted journal lines across every dimension-bearing transaction; the JE-line guard rejects cross-company dimensions (non-vacuous); reversal preserves all six.

Audit & Immutability (2nd), Number Series (3rd), Permissions/RLS (1st) Engines — **CERTIFIED** 2026-07-22/23 (guards `078`/`079`/`077`); detail in `PXL_CERTIFICATION_MATRIX.md`. Setup & Master Data Phase 1 re-review 2026-07-22 — Blocked on missing evidence, not defects (MDP-01…15 resolved).

## Recommended Next Task

The finding program is complete. The authorized phase is **IA-5 ECONOMIC COSTING
CHRONOLOGY HARDENING — IMPLEMENTATION, WORK PACKAGE 1**, exactly as specified in
`IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §24 and §17 (M1):
create the **six** dormant version objects (`inventory_event_order_policies`,
`inventory_event_effect_ranks`, `inventory_source_type_ranks`,
`inventory_transition_ranks`, `inventory_canonical_form_versions`,
`inventory_correction_graph_versions`), reusing the IA-5 guard/RLS/grant/audit/
immutability patterns unchanged; seed only certification-only ranks; add nothing to
`inventory_events`; expose no grant; register each new table in
`PXL_TABLE_COVERAGE_MATRIX.md` + guard `075`; evidence T-01/T-27; rollback = drop M1.

**Stop conditions:** no deviation from ADR-C01/ECC-01; no Posting or Kernel change;
no IA-6 work; preserve dormancy; stop if `inventory_events` is non-zero at execution
(re-verify; it is 0 now) or if scope differs from the approved design. **Next
evidence:** WP-1 implementation record, migration validation, T-01/T-27,
documentation reconciliation, WP-1 evidence-gate report. WP-2…WP-9 follow only after
WP-1 is evidenced. **IA-6 remains unauthorized**, P5.3B/P6/P7 stay paused, hosted
migration requires explicit approval.
