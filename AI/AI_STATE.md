# PXL AI State

**Current Date:** 2026-08-05
**Current Branch:** `main`
**Working Tree:** Percentage tax (Backlog 8), the **filing artifact engine**
(Phase 5.8), its **export** (8d), the **1601EQ/QAP** migration (8e i, iii),
**8f** and the **SLSP** migration (8e ii) are complete locally with executed
fresh, canonical, regression, frontend, build and lint evidence. A non-VAT
Section 116 taxpayer runs the chain: line code → component → liability posting →
tax ledger → GL reconciliation at 0.00 → working paper → **2551Q**. Every
registered artifact — 2550Q, 2551Q, 1601EQ, SLSP, SAWT, **QAP** — comes from
**one** generator over **one** working paper and **one** reconciliation, and is
**exported** by one consumer. **Every current-product compliance surface is on
the layer and every registered form reaches generate → final → export** (24
closed 2026-08-05). **Nothing has been filed with the Bureau.**
**Product Phase:** Pilot Execution Plan; IA-5/ECC **frozen**.
**Environment:** Local Supabase on a fresh schema. No hosted operation was
performed.
**Product Readiness:** **Internal QA/demo only. Not pilot-ready.**
**PXL is not production-ready.**
**Scope (owner, 2026-08-04; PAD-015):** Philippine SME accounting and compliance.
FWT (1601FQ/2306), Payroll, 2316, Income Tax, MCIT/RCIT, NOLCO, OSD, FBT,
Transfer Pricing, Consolidation and specialized-industry features are **future
extensions, never production blockers**. Future priority: Banking & Treasury,
then Fixed Assets; neither started.

## Canonical Authority and Startup

Four authorities — settled 2026-08-02: **what** PXL is →
`PXL_PRODUCT_ARCHITECTURE.md`; **when/in what order**, the only numbered phases →
`PXL_DELIVERY_PLAN.md`; **why** → `PXL_PRODUCT_EXECUTION_ROADMAP.md` (**no phase
numbers**); **where** we are → this file. An unqualified "Phase N" is a Delivery
Plan phase. Startup: `AI/AGENT_SYSTEM_PROMPT.md` → this file →
`PXL_HOW_WE_WORK.md` → Product Architecture → Roadmap → the mission's files;
new sessions start with `AI/ONBOARDING_PROMPT.md`.

**Current phase: Delivery Plan Phase 5.** Phases 1, 3 and 4 are built locally;
Phase 2's remainder is **owner-supplied**.

The certification ceremony was **retired 2026-08-02** for automated invariants
(`PXL_HOW_WE_WORK.md` §3–4). Read the state, run the gates, fix what fails, build
next. **This file is the only status authority.**

## Current Finding Standing

**93 Retested Passed / 0 In Progress / 0 Open (93 total).** Complete; that
certifies no module or engine and confers no readiness.

## Active Work Map

- **Certified modules:** 0 / 11; **canonical workflows meeting Product DoD:** 0 / 6.
- **Certified engines:** 4 / 19 — Permissions/RLS, Audit & Immutability, Number
  Series, Dimension. **Tax Engine at M5** (PAD-001), guarded, **not certified**.
- **Critical reconciliations evidenced:** **3 / 9**, all at 0.00 — inventory
  (`111`, `120`); percentage tax (`124`); VAT and withholding through the one
  reconciliation (`125`, `127`).
- **Posting entry points exercised:** **15 of 24**, the honest measure.
- **Certified work packages:** IA-5 ECC WP-1…WP-4, 4 / 9, **frozen, zero
  consumers.** WP-5…WP-9 and IA-6 stopped.
- **Visible scaffolds:** **26** deferred routes "Not built"; **17** nav labels
  with no page. 247 nav → 175 routes, **145** on real data.

- **Transaction workspaces:** **37** entries; Sales Invoice the sole
  source-reviewed slice. UI rollout is not completion:
  business qualification remains source-gated.

- **Tests:** 128 pgTAP files / 3,079 assertions plus 66 frontend source tests;
  regression, canonical, build and lint lanes pass.
- **Backup/restore:** **Mechanised; never operated over anything real.** Weekly
  in CI. Blocker 5.

## Known Blockers and Non-Assumptions

1. No Sales or Purchasing source-to-statements-to-tax workflow meets the Product
   Definition of Done.
2. Every outbound entry point relieves stock (054, 119, 120). Open: three-way
   match, over-receipt control, Delivery Receipt cancellation.
3. **Nothing has ever been filed with the Bureau.** Six artifacts — 2550Q,
   2551Q, 1601EQ, SLSP, SAWT, QAP — generate from the posted ledger, reconcile to
   the GL and refuse to leave draft while they disagree with it; `filed` records
   the accountant's own submission and PXL transmits nothing. The **SLSP screen**
   still bypasses the layer, monthly against a quarterly attachment (8c, 8e ii).
   Two hand-keyed FWT prototype screens remain outside the current product; they
   carry no architecture, pilot or readiness weight (22). Percentage tax is recognised on the document, not on collections; a
   credit memo does not reverse it; nothing compels a PT-registered company to
   select its code (8b). No governed UI for tax-code succession (10) or statement
   re-presentation (18f); the tax profile is not effective-dated (11); close
   readiness cannot see unposted documents (18h); retained earnings is
   per-fiscal-year (18g); notes carry no narrative or signature block (18i).
4. Phase 3 is not operationally accepted: no hosted migration, deployed invite
   function, cut-over rehearsal or UAT proof.
5. Recoverability is mechanised but not operated: the weekly workflow has never
   fired, no durable destination or escrowed passphrase exists, and the
   replication proof used the **same machine**.

6. Hosted parity is absent after `20260716000005`.
7. Frontend evidence is source-contract and build coverage only; no browser lane.

## Current Engineering Frontier

Shipped; detail in the Delivery Plan and Test Book — do not re-derive it here.
**2026-08-03:** Tax Engine, VAT resolution, Cash Sale, Delivery Receipt/Customer
Return, statement presentation, period close, comparatives (`…01`–`…07`,
`117`–`123`). **2026-08-04:** percentage tax (`…01`, `124`); the **filing artifact
engine** (`…02`, `125`, Phase 5.8) and its **export** (`…03`, `126`, 8d) — one
path replacing three reconciliation functions and three browser computations,
where a new form is a **seed row**.

**1601EQ and QAP joined it** (`…04`, `127`, 8e i and iii): both computed
correctly and **recorded nothing**. `fn_generate_ewt_return` is the **third
instance of the projection shape, not a fourth engine**; `remitted_prior` was
corrected from stated to derived; `fn_qap_2307_reconciliation` was **resolved,
not retired**.

**8f shipped** (`…05`/`…06`, `128`, `129`, `compliance_architecture.test.ts`) —
**the second compliance architecture is retired.** Capability first: the legacy
screens' only real capability, keying a line no ledger backs, became the governed
**Reconciling Item** — audited, frozen once the artifact leaves draft, a note in
CSV and never in a DAT, excluded from every total **structurally** (its amount
sits in a column no computation reads). Then retirement in order: one governed
surface replaced four screens, the last legacy writer left
`fn_generate_pt_return`, eight tables were dropped, and `fn_snapshot_wht_export`
went — revealing it had been **`anon`-executable**. **Two regressions closed:**
`filing_artifacts` had no owner/admin gate on final/filed, and the grouped
schedule needed a trace drill-down to keep per-document detail.

Phase 3 is implemented locally and unchanged (PAD-002, PAD-003). IA-5/ECC is
**frozen** at zero consumers (`docs/PXL/archive/ia5-ecc-frozen/`). Posting P5.2
remains fully enforced; the Accounting Kernel is a component inside it, not an
engine.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is at `20260716000005`; **68 local
migrations pending**, no destructive DDL. The deploy is **rehearsed, not
performed, and deliberately deferred** — nothing consumes it and CI deploys
nothing. Credentials absent by design (PXL-AUD-055). Deferred-route labelling is
governed by `deferredSurfaces.ts` (PAD-012).

## Last Verified Commands

- `npm run test:db:fresh` and `test:db:regression` — **PASS**, 128 files / 3,079
  assertions; the regression lane resets the schema first, so it is
  order-independent.
- `npm run test:canonical` — **PASS**, 30 files / 751 assertions.
- Focused lane — **PASS**, `129` 22, `128` 30, `127` 34, `126` 24, `125` 42.
- **Committed** fresh-data percentage-tax run (never the demo seed): ledger-to-GL
  variance **0.00**, trial balance **0.00**, Q1 filed with its working paper.
- `npm run test:frontend` — **PASS**, 66 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; one
  pre-existing lint warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; 128 tests indexed. It had been **failing** in
  this tree: a prior session left this file over its word cap and recorded the
  lane as passing.
- `npm run backup:operate` — **PASS** (2026-08-02); replica restored
  independently, 0 mismatches.
- Inventory-to-control **0.00** in all three stock-holding companies; trial
  balance **0.00** in all five.

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action** (PAD-007).

**Phase 5 items 3, 7 and 8 and Backlog 8, 8d, 8e, 8f, 18d and 18e are complete
for current product scope; nothing has been filed with the Bureau.** **The
governed compliance architecture is complete for every current-product family**
(test `129`, `compliance_architecture.test.ts`); FWT/1601FQ is a future
extension, not an architecture gap. **Next, owner's choice:** **8b** (percentage
tax on collections), **18c** (Delivery Receipt cancellation), or **10** (governed
tax-code maintenance, before the first real BIR rate change).

**Compliance standard (owner, 2026-08-04):** Posted Transactions → Tax Engine →
Tax Ledger → Reconciliation → Working Paper → Filing Artifact → Export → Filed
Record. **The Filing Artifact is the system of record**; one implementation per
stage, extra faces are delegations, replacement is ordered, no orphans. **Review
Stage reads source data by design; Filing Stage is bound to the artifact**
(settled 2026-08-05). Full rule in the Backlog and Rules Matrix.

Remaining current-product Backlog: 8b, 8c, 10, 11, 18, 18b, 18c, 18f, 18g, 18h,
18i, 19, 23. Then Banking & Treasury, then Fixed Assets. Excluded extensions,
including 22, carry no readiness weight.

Re-run `npm run deploy:rehearse` after adding migrations (Runbook §2a);
**owner approval required**. No open findings remain; do not resume IA-5.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6;
preserve IA-5 dormancy; a non-zero `inventory_events` count is a governance stop;
no hosted operation without approval; no product-scope change without a Product
Architecture Amendment. WP-5…WP-9 unauthorised. Governance-only commits require
an explicit owner-directed finalization or Product Architecture Amendment.
