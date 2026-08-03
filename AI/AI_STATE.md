# PXL AI State

**Current Date:** 2026-08-03
**Current Branch:** `main`
**Working Tree:** **Period close and year-end roll-forward (Backlog 18d)** is
complete locally with executed fresh, canonical, regression, frontend, build and
lint evidence plus a **committed** fresh-data run. The cycle now closes:
transaction → posting → GL → trial balance → statements → period close →
year-end close → retained earnings → next fiscal year.
**Product Phase:** Pilot Execution Plan; IA-5/ECC **frozen**.
**Environment:** Local Supabase on a fresh schema. No hosted operation was
performed.
**Product Readiness:** **Internal QA/demo only. Not pilot-ready. Not
production-ready.** PXL is not production-ready.

## Canonical Authority and Startup

Four authorities, four questions — settled 2026-08-02: **what** PXL is →
`PXL_PRODUCT_ARCHITECTURE.md`; **when/in what order**, the only numbered phases →
`PXL_DELIVERY_PLAN.md`; **why** → `PXL_PRODUCT_EXECUTION_ROADMAP.md`, which
carries **no phase numbers**; **where** we are → this file. An unqualified
"Phase N" is a Delivery Plan phase. Startup order:
`AI/AGENT_SYSTEM_PROMPT.md` → this file → `PXL_HOW_WE_WORK.md` → Product
Architecture → Roadmap → only what the mission names; new sessions start with
`AI/ONBOARDING_PROMPT.md`.

**Current phase: Delivery Plan Phase 5 — the two canonical flows.** Phases 1, 3
and 4 are built locally; Phase 2's remainder is **owner-supplied** (a backup
destination on a separate failure domain and an escrowed passphrase).

The certification ceremony was **retired 2026-08-02** for automated invariants
(`PXL_HOW_WE_WORK.md` §3–4). Do not run an audit mission. Read the state, run the
gates, fix what fails, build the next thing. **This file is the only status
authority**; `git log` is the history.

## Current Finding Standing

**93 Retested Passed / 0 In Progress / 0 Open (93 total).** The finding program
is complete; that certifies no module or engine and confers no readiness.

## Active Work Map

- **Certified modules:** 0 / 11.
- **Certified engines:** 4 / 19 — Permissions/RLS, Audit & Immutability, Number
  Series and Dimension. The **Tax Engine exists at M5** (PAD-001), guarded, **not
  certified**; no engine became certified this session.
- **Critical reconciliations evidenced:** **1 / 9.** Inventory-to-control
  reconciles at 0.00 in every stock-holding company (`111`) and across the whole
  outbound chain on fresh data (`120`).
- **Exercised posting entry points:** **15 of 24** — the honest completion measure.
  The year-end close joined on 2026-08-03; before that it was registered,
  tested and **incapable of committing** (see the Frontier).
- **Certified work packages:** IA-5 ECC WP-1…WP-4, 4 / 9, **frozen, 21 tables
  empty, zero consumers.** WP-5…WP-9 and IA-6 stopped.

- **Canonical workflows meeting Product DoD:** 0 / 6.
- **Transaction workspaces:** **37** registry entries; Sales Invoice the sole
  source-reviewed slice. UI rollout is not business completion:
  business qualification remains source-gated.
- **Visible scaffolds:** **30** deferred routes labelled "Not built"; **17** nav
  labels with no page. 247 nav entries → 175 routes, **145** on real data.

- **Tests:** 122 pgTAP files / 2,876 assertions plus 60 frontend source tests;
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
   Period close now commits (18d), but its readiness cannot see unposted source
   documents (18h) and retained earnings is per-fiscal-year, not company
   configuration (18g).
4. Phase 3 is not operationally accepted: no hosted migration, deployed invite
   function, cut-over rehearsal or browser/UAT proof.
5. Recoverability is mechanised but not operated: the weekly workflow has never
   fired, no durable destination or escrowed passphrase exists, the replication
   proof used storage on the **same machine**, and no PXL database holds real books.
6. Hosted parity is absent after `20260716000005`.
7. Frontend evidence is source-contract and build coverage only; no automated
   browser workflow lane exists.

## Current Engineering Frontier

Shipped 2026-08-03; detail lives in the Delivery Plan and Accounting Test Book —
do not re-derive it here. `fn_calculate_tax` (`…01`); `fn_resolve_vat_code`
(`…02`, `118`); Cash Sale (`…03`, `119`) and Delivery Receipt / Customer Return
(`…04`, `120`), which made every outbound entry point relieve stock through one
costing path; governed statement presentation (`…05`, `121`).

**Period close and year-end roll-forward shipped** (`20260803000006`, test `122`,
34 assertions, Backlog 18d). The cycle runs to its end.

The finding that shaped it: **`fn_close_fiscal_year` could never have
committed.** It posted the closing journal with a NULL `reference_doc_id` while
`CLOSE` resolved against `journal_entries`, and the deferred trigger
`trg_journal_entry_source_integrity` rejects that at COMMIT. Test `040` passed
because pgTAP rolls back — a deferred constraint never committed is never
checked. **The fiscal year is now the closing journal's source document**, and
`122` asserts that resolution directly.

`fiscal_close_runs` registers every close and reopen; two partial unique indexes
give at most one live close per period and per year, which is what makes the
close **idempotent**. Periods close in date order (`fn_close_accounting_period`
— blocking on period open, year open, earlier periods closed, ledger balanced)
and reopen last-in-first-out against a required reason; a quarter close is that
same close three times. `fn_reopen_fiscal_year` counter-posts through the kernel
classified `closing`, so a re-close recomputes the same net income instead of
doubling it and the original entry is never touched. The close opens the next
fiscal year with its periods and the same retained-earnings account. **The lock
is governed**: `is_locked` and `fiscal_years.status` change only inside the four
close functions — the old "Close Year" button wrote `status = 'closed'` through
PostgREST and posted nothing.

Phase 3 is implemented locally and unchanged (PAD-002, PAD-003). IA-5/ECC is
**frozen** at zero consumers and zero events; evidence under
`docs/PXL/archive/ia5-ecc-frozen/`. Posting P5.2 remains fully enforced; the
Accounting Kernel is a component inside the Posting Engine, not an engine.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is at migration `20260716000005`; **60
local migrations are pending**, with **no destructive DDL**. The deploy is
**rehearsed, not performed, and deliberately deferred** — nothing consumes the
hosted database and CI deploys nothing. Credentials are absent by design
(PXL-AUD-055). See the Deploy Runbook.

Thirty-three reachable routes are backed only by future-deferred tables. A
rendered page is not a workflow.

## Last Verified Commands

- `npm run test:db:fresh` — **PASS** on 2026-08-03.
- `npm run test:canonical` — **PASS**, 30 files / 751 assertions.
- `npm run test:db:regression` — **PASS**, 122 files / 2,876 assertions; the lane
  resets to a fresh schema first, so it is order-independent.
- Focused lane — **PASS**, `122` 34, `121` 25, `120` 24, `119` 26, `118` 25.
- **Committed** fresh-data close cycle, self-provisioned company (not the demo
  seed): monthly, quarterly and year-end close (Dr Revenue 310,000 / Cr Expense
  90,000 / Cr Retained Earnings 220,000, out-of-balance 0.00), roll-forward to
  FY2027, second close refused, reopen, re-close leaving retained earnings at
  220,000 — **not 440,000**.
- `npm run test:frontend` — **PASS**, 60 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; lint reports
  one pre-existing warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; 122 tests indexed.
- `npm run backup:operate` — **PASS** (2026-08-02); replicated copy restored
  independently, 0 mismatches.
- Inventory-to-control variance **0.00** in all three stock-holding companies;
  trial balance out-of-balance **0.00** in all five; the canonical demo
  Statement of Financial Position balances at **0.00** (assets 622,768.80).

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action**
(PAD-007, Runbook §6 — bucket, `PXL_OFFSITE_URL` plus keys, escrowed
`PXL_BACKUP_PASSPHRASE`).

**Phase 5 items 3 and 7 and Backlog 18d are complete.** Next build task:
**comparative periods and statement notes (18e)** — unblocked now that a prior
year's profit sits in Retained Earnings, so a comparative across a year boundary
finally means something. `fn_financial_statement_report` returns
opening/movement/closing for one period and needs a prior-period column beside
it; the Comparative Financial Statements screen still computes its own figures.
Alternative pick: **percentage tax (8)** — larger, whole-chain-or-none.

Phase 5 runs flows → statements → filing. Remaining Backlog: 8, 10, 11, 18, 18b,
18c, 18e, 18f, 18g, 18h, 19.

**The hosted deploy is deferred, not blocked** (Runbook §2a); re-run
`npm run deploy:rehearse` after adding migrations — the pending set is **61**.
**Requires explicit owner approval.**

No open findings remain. Do not resume IA-5: canonical flow proof and operated
recovery outrank dormant foundation work.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6; no
WP-5 implementation; preserve IA-5 dormancy; a non-zero `inventory_events` count
is a governance stop; no hosted operation without approval; no product-scope
change without a Product Architecture Amendment. WP-5…WP-9 remain
unauthorised. Do not create a governance document in a commit that contains no
application or SQL change.
