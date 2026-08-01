# PXL AI State

**Current Date:** 2026-08-01
**Current Branch:** `main`
**Working Tree:** EA-009 and its owner-approved security disposition are
validated and committed in the repository state identified by current `main`
HEAD; the accepted public handoff is synchronized to `origin/main`.
**Product Phase:** Product Architecture consolidation complete; WP-5 Engineering
Amendment EA-009 complete, awaiting another separate Authorisation Gate re-run.
**Environment:** Local repository documentation review only; no database test
lane, runtime, or hosted operation was authorised.
**Product Readiness:** **Internal QA/demo only. Not pilot-ready. Not
production-ready.** PXL is not production-ready.

## Canonical Authority and Startup

The canonical product authority is
`docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`: what PXL is, its eleven
business modules, Dashboard reporting surface, nineteen engine assessment scopes,
canonical names, boundaries and M0–M9 maturity model.

The subordinate planning authority is
`docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`: dependency sequence,
Product Definition of Done, maturity evidence, risks and operating model. It may
not override the Product Architecture or authorise implementation.

Fresh AI startup order: `AI/AGENT_SYSTEM_PROMPT.md` → this file →
`AI_LAST_SESSION.md` → Product Architecture → Product Execution Roadmap when the
task concerns planning, maturity or sequencing → only the exact authorities named
by the active mission.

`AI_PROGRESS.md` is the executive dashboard only. It uses exact homogeneous
measures and no mixed-unit overall percentage.

## Current Finding Standing

**92 Retested Passed / 0 In Progress / 0 Open (92 total).** The finding program
is complete, but that evidence does not certify any module or engine and does
not make the product production-ready.

## Active Work Map

- **Certified modules:** 0 / 11 certification scopes.
- **Certified engines:** 4 / 19 — Permissions/RLS, Audit & Immutability, Number
  Series and Dimension.
- **Certified work packages:** IA-5 ECC WP-1…WP-4, exactly 4 / 9; work-package
  certification does not certify the Inventory Accounting Engine or Inventory
  Module.
- **Canonical workflows meeting Product DoD:** 0 / 6 reference flows.
- **Transaction workspaces:** 41 registry entries; Sales Invoice is the sole
  source-reviewed slice. The other 40 remain `transaction-matrix-only`.
  Transaction-workspace business qualification remains source-gated.
- **Visible scaffolds:** 33 reachable routes backed only by future-deferred
  tables; 18 disabled navigation placeholders.
- **Tests:** 110 pgTAP files in the repository. This architecture mission ran
  documentation validation only, not database test lanes.
- **Backup/restore:** Not Tested; no RPO/RTO or successful restore evidence.

Payroll is a **future separate product — excluded from current PXL ERP progress**.

## Known Blockers and Non-Assumptions

1. No complete Sales or Purchasing source-to-financial-statements-to-tax workflow
   meets the Product Definition of Done.
2. Receiving Reports add stock without a journal while Vendor Bills debit
   purchase clearing; Inventory valuation does not reconcile to control.
3. No Tax Engine exists. Tax capability is distributed across reference masters,
   save-layer calculators, tax ledger and Compliance surfaces. Product
   Architecture Decision PAD-001 is required before engine implementation.
4. No opening-balance strategy/workflow exists; PAD-002 is required before pilot
   onboarding.
5. Backup/restore, operations, support and user acceptance are unproven.
6. Hosted parity is absent for local work after `20260716000005`.

## Current Engineering Frontier

ADR-C01 remains frozen. ECC-01 remains owner accepted, not frozen. The original
IA-5 permanent-foundation claim remains **SUSPENDED** by C-01.

WP-1, WP-2, WP-3 and WP-4 remain **Certified work packages** and dormant. The
2026-07-31 WP-5 rejection and EA-008 remain preserved as historical records.
The later independent gate re-run returned **REJECTED** on exactly
WP5-AGR-001…003: canonical-key authority conflicted with certified WP-4, two
mandatory writer sequences conflicted, and the protected-boundary proof was not
independently reproducible.

Documentation/governance-only **EA-009** closes those three specification/proof
findings. Certified WP-4 remains authoritative for immutable bytes/digest of all
fourteen ECC components; WP-5 derives the values, with E2 = 0 for the only
eligible base/no-edge fixture. The detailed specification §3.5 is the only
writer sequence, and §17 fixes a reproducible 527-file protected manifest. The
exact replacement writer/resolver/payload, V-10-preserving owner-only rolled-
back fixture, trigger/function census, totality, rollback and future tests
`111`…`113` remain governed in
`docs/PXL/07. Inventory/04. Implementation/IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`.

EA-009 grants no authority. WP-5 is unauthorised, unimplemented, unaudited and
uncertified. No runtime consumer exists and no production source is enabled.

Posting P5.2 remains fully enforced. The Accounting Kernel is a component inside
the Posting Engine, not a separate engine. Posting P6 remains blocked at
Inventory. P5.3B/P6/P7 remain paused.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is synchronized through migration
`20260716000005`. Fifty-one local migrations from `20260718000001` through
`20260731000019` are not hosted. No hosted parity or deployment claim is valid;
no hosted mutation without explicit approval.

The repository has 41 registered transaction workspaces, but only the Sales
Invoice slice has completed source review; the other 40 are matrix-only. Thirty-
three reachable routes are backed only by future-deferred tables, and 18
navigation items are disabled placeholders. A route or rendered page is not a
complete workflow.

## Last Verified Commands

- `npm run docs:check` — **PASS** on 2026-08-01 after EA-009 reconciliation.
- `git diff --check` — **PASS** on 2026-08-01.
- Internal Markdown links/index, fourteen-component/26-column resolver census,
  one writer sequence, exact four-object/reverse-rollback census, 25 failure
  IDs, seven future test families, authority/status terminology and PostgreSQL
  identifier lengths — **PASS**.
- The fixed protected set measured 527 entries. Start/end SHA-256 aggregate
  `8ddf66f36c63606f8eb0bceaacfe3f3131337758b895fc557ec488ca383d7ba6`
  is **identical**.
- No SQL, migration, pgTAP/database lane, test, route, navigation, application
  source, database object or hosted operation was executed or edited by EA-009.
- Public-push secret/privacy gate — **PASS after owner disposition**. The exact
  reviewed residual is the Supabase CLI documented default local-development
  PostgreSQL URI at `127.0.0.1:54322`, not a hosted/project credential. Current
  prose masks its password; the historical value is classified only by its
  reviewed SHA-256. This exact false positive requires neither rotation nor
  history rewrite. No blanket database-URI exemption exists.

## Recommended Next Task

**WP-5 AUTHORISATION GATE RE-RUN — Lifecycle Step 2.** Independently review the
EA-009-current specification against ADR-C01, ECC-01 and certified WP-1…WP-4.
Do not implement or repair WP-5 during that gate. The owner-approved Git-history
disposition applies only to the exact documented Supabase CLI localhost default;
any future credential detection remains a new stop requiring independent review.

No open findings remain; the audit-finding program is complete. This next task
is a governed engineering-documentation mission, not a finding remediation.

This remains next because a completed amendment cannot authorise itself and the
deterministic chronology prerequisite still advances future Inventory-to-GL
correctness. It does not justify automatic WP-6…WP-9 execution. After the WP-5
gate, run the roadmap's product-value checkpoint;
canonical Sales/Purchasing proof, Receiving accounting, Tax ownership, opening
balances and restore evidence are more urgent than further dormant foundation
unless a later package is demonstrably required.

## Stop Conditions

No ADR-C01/ECC-01 deviation; no Posting/Kernel change; no production source
activation; no IA-6; no WP-5 implementation before a successful gate; preserve
dormancy; a non-zero `inventory_events` count is a governance stop; no hosted
operation without approval; no product-scope change without Product Architecture
Amendment. WP-5…WP-9 and IA-6 remain unauthorised.
