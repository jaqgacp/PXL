# PXL AI State

**Current Date:** 2026-08-03
**Current Branch:** `main`
**Working Tree:** **Comparative statements and basic notes (Backlog 18e)** are
complete locally with executed fresh, canonical, regression, frontend, build and
lint evidence plus a real self-provisioned run. Period close (18d) shipped
immediately before. The cycle and the reporting path both run to the end:
transaction → posting → GL → trial balance → statements → **comparatives and
notes**; and period close → year-end close → retained earnings → next year.
**Product Phase:** Pilot Execution Plan; IA-5/ECC **frozen**.
**Environment:** Local Supabase on a fresh schema. No hosted operation was
performed.
**Product Readiness:** **Internal QA/demo only. Not pilot-ready.**
**PXL is not production-ready.**

## Canonical Authority and Startup

Four authorities, four questions — settled 2026-08-02: **what** PXL is →
`PXL_PRODUCT_ARCHITECTURE.md`; **when/in what order**, the only numbered phases →
`PXL_DELIVERY_PLAN.md`; **why** → `PXL_PRODUCT_EXECUTION_ROADMAP.md` (**no phase
numbers**); **where** we are → this file. An unqualified "Phase N" is a Delivery
Plan phase. Startup: `AI/AGENT_SYSTEM_PROMPT.md` → this file →
`PXL_HOW_WE_WORK.md` → Product Architecture → Roadmap → only what the mission
names; new sessions start with `AI/ONBOARDING_PROMPT.md`.

**Current phase: Delivery Plan Phase 5 — the two canonical flows.** Phases 1, 3
and 4 are built locally; Phase 2's remainder is **owner-supplied**.

The certification ceremony was **retired 2026-08-02** for automated invariants
(`PXL_HOW_WE_WORK.md` §3–4). Do not run an audit mission: read the state, run the
gates, fix what fails, build the next thing. **This file is the only status
authority**; `git log` is the history.

## Current Finding Standing

**93 Retested Passed / 0 In Progress / 0 Open (93 total).** The finding program
is complete; that certifies no module or engine and confers no readiness.

## Active Work Map

- **Certified modules:** 0 / 11.
- **Certified engines:** 4 / 19 — Permissions/RLS, Audit & Immutability, Number
  Series and Dimension. The **Tax Engine exists at M5** (PAD-001), guarded, **not
  certified**.
- **Critical reconciliations evidenced:** **1 / 9.** Inventory-to-control
  reconciles at 0.00 in every stock-holding company (`111`) and across the
  outbound chain on fresh data (`120`).
- **Exercised posting entry points:** **15 of 24** — the honest completion measure.
- **Certified work packages:** IA-5 ECC WP-1…WP-4, 4 / 9, **frozen, 21 tables
  empty, zero consumers.** WP-5…WP-9 and IA-6 stopped.

- **Canonical workflows meeting Product DoD:** 0 / 6.
- **Transaction workspaces:** **37** registry entries; Sales Invoice the sole
  source-reviewed slice. UI rollout is not business completion:
  business qualification remains source-gated.
- **Visible scaffolds:** **30** deferred routes labelled "Not built"; **17** nav
  labels with no page. 247 nav entries → 175 routes, **145** on real data.

- **Tests:** 123 pgTAP files / 2,909 assertions plus 60 frontend source tests;
  full regression, canonical, build and lint lanes pass.
- **Backup/restore:** **Mechanised and scheduled; never operated over anything
  real.** `npm run backup:operate` runs weekly in CI. RPO 24h pilot. Blocker 5.

Payroll is a **future separate product, excluded from PXL ERP progress**.

## Known Blockers and Non-Assumptions

1. No complete Sales or Purchasing source-to-statements-to-tax workflow meets
   the Product Definition of Done.
2. Every outbound entry point relieves stock as of 2026-08-03 — Sales Invoice
   (054), Cash Sale (119), Delivery Receipt and Customer Return (120). Open:
   three-way match, over-receipt control, Delivery Receipt cancellation.
3. **Percentage tax is calculated nowhere and never has been**, so a
   PT-registered company has nothing to review or file. **Nothing has ever been
   filed**: all twelve `compliance_*` working-paper tables and the return/form
   tables are empty. No governed UI configures a tax-code succession (10) or a
   statement re-presentation (18f); the tax profile is not effective-dated (11).
   Close readiness cannot see unposted source documents (18h); retained earnings
   is per-fiscal-year, not company configuration (18g); the notes carry no
   company narrative, templates or signature block (18i).
4. Phase 3 is not operationally accepted: no hosted migration, deployed invite
   function, cut-over rehearsal or browser/UAT proof.
5. Recoverability is mechanised but not operated: the weekly workflow has never
   fired, no durable destination or escrowed passphrase exists, the replication
   proof used storage on the **same machine**, and no PXL database holds real books.
6. Hosted parity is absent after `20260716000005`.
7. Frontend evidence is source-contract and build coverage only; no browser lane.

## Current Engineering Frontier

Shipped 2026-08-03; detail lives in the Delivery Plan and Accounting Test Book —
do not re-derive it here. `fn_calculate_tax` (`…01`); `fn_resolve_vat_code`
(`…02`, `118`); Cash Sale (`…03`, `119`) and Delivery Receipt / Customer Return
(`…04`, `120`), which made every outbound entry point relieve stock through one
costing path; governed statement presentation (`…05`, `121`).

**Period close and year-end roll-forward** (`…06`, `122`, Backlog 18d).
`fn_close_fiscal_year` **could never have committed** — a NULL
`reference_doc_id` the deferred source-integrity trigger rejects at COMMIT, which
`040` never saw because pgTAP rolls back. The fiscal year is now the closing
journal's source document. `fiscal_close_runs` registers every close and reopen;
partial unique indexes give at most one live close per period and per year, which
is what makes it **idempotent**. Periods close in date order, reopen
last-in-first-out against a reason, and **the lock is governed**: `is_locked` and
`fiscal_years.status` change only inside the four close functions.

**Comparative statements and basic notes shipped** (`…07`, `123`, Backlog 18e).
Closing the books had **silently broken two of the four statements** for any
closed year: the report read every posted line regardless of `entry_class`, so a
closed year's income statement read **all zeroes** (revenue 50,000 → 0.00) and
its cash flow moved the whole operating flow into **financing**. Comparatives are
the first feature that reads a closed year on purpose. Closing entries are now
excluded from income and cash flows, included in the position and equity (18j).

The comparative is **one contract, not a second engine**:
`fn_comparative_financial_statement_report` calls the report twice and joins on
the governed line code, passing the **current** period end as the prior call's
presentation date so both columns read today's mapping.
`fn_resolve_comparative_period` reads the company's fiscal calendar and returns
`available:false` with a reason rather than raising. Every line opens to its
accounts and on to the ledger. Notes are rows, each naming its source and
flagging whether it is configured. The Comparative screen computes nothing.

Phase 3 is implemented locally and unchanged (PAD-002, PAD-003). IA-5/ECC is
**frozen** at zero consumers; evidence under `docs/PXL/archive/ia5-ecc-frozen/`.
Posting P5.2 remains fully enforced; the Accounting Kernel is a component inside
the Posting Engine, not an engine.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is at `20260716000005`; **62 local
migrations are pending**, no destructive DDL. The deploy is **rehearsed, not
performed, and deliberately deferred** — nothing consumes the hosted database
and CI deploys nothing. Credentials absent by design (PXL-AUD-055).

Thirty-three reachable routes are backed only by future-deferred tables. A
rendered page is not a workflow.

## Last Verified Commands

- `npm run test:db:fresh` — **PASS** on 2026-08-03.
- `npm run test:canonical` — **PASS**, 30 files / 751 assertions.
- `npm run test:db:regression` — **PASS**, 123 files / 2,909 assertions; the lane
  resets to a fresh schema first, so it is order-independent.
- Focused lane — **PASS**, `123` 33, `122` 34, `121` 25.
- **Committed** fresh-data close cycle (never the demo seed): monthly, quarterly
  and year-end close, roll-forward to FY2027, second close refused, reopen,
  re-close leaving retained earnings at 220,000 — **not 440,000**.
- Comparatives on a self-provisioned company with FY2026 closed: net income
  680,000 vs 500,000 (+36.00%), position balancing in **both** columns, and 38
  note items with trial-balance agreement 0.00 in both periods.
- `npm run test:frontend` — **PASS**, 60 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; lint reports
  one pre-existing warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; 123 tests indexed.
- `npm run backup:operate` — **PASS** (2026-08-02); replicated copy restored
  independently, 0 mismatches.
- Inventory-to-control variance **0.00** in all three stock-holding companies;
  trial balance out-of-balance **0.00** in all five.

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action**
(PAD-007, Runbook §6).

**Phase 5 items 3 and 7 and Backlog 18d and 18e are complete: flows and
statements are done, filing is not.** Next build task: **percentage tax
(Backlog 8)** — the last unblocked accounting gap, and the one that decides
whether a non-VAT pilot client can operate at all. Whole-chain-or-none:
calculation in `fn_calculate_tax`, a tax-code succession, per-document
recognition, the tax ledger, the 2551Q working paper. Everything it needs now
exists. Alternative: **BIR filing artifacts (Phase 5.8)** — larger, and
percentage tax is one of its inputs, so 8 first.

Phase 5 runs flows → statements → filing. Remaining Backlog: 8, 10, 11, 18, 18b,
18c, 18f, 18g, 18h, 18i, 19.

**The hosted deploy is deferred, not blocked** (Runbook §2a); re-run
`npm run deploy:rehearse` after adding migrations — the pending set is **62**.
**Requires explicit owner approval.**

No open findings remain. Do not resume IA-5.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6;
preserve IA-5 dormancy; a non-zero `inventory_events` count is a governance stop;
no hosted operation without approval; no product-scope change without a Product
Architecture Amendment. WP-5…WP-9 remain unauthorised. Do not create a governance
document in a commit that contains no application or SQL change.
