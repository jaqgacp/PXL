# PXL AI State

**Current Date:** 2026-08-03
**Current Branch:** `main`
**Working Tree:** Delivery Plan Phase 5 item 3 — **Cash Sale posting** — is
implemented locally with executed fresh, canonical, regression, frontend, build
and lint evidence. Cash Sale now relieves inventory and posts COGS, and carries
Business Tax and Withholding Tax **per line**.
**Product Phase:** Pilot Execution Plan; IA-5/ECC **frozen**.
**Environment:** Local Supabase on a fresh schema. No hosted operation was
performed.
**Product Readiness:** **Internal QA/demo only. Not pilot-ready. Not
production-ready.** PXL is not production-ready.

## Canonical Authority and Startup

Four authorities, four questions — settled 2026-08-02; none answers another's:
**what** PXL is → `PXL_PRODUCT_ARCHITECTURE.md`; **when/in what order**, the only
numbered phases → `PXL_DELIVERY_PLAN.md`; **why** that order →
`PXL_PRODUCT_EXECUTION_ROADMAP.md`, which carries **no phase numbers**; **where**
we are → this file. An unqualified "Phase N" is a Delivery Plan phase. Startup
order: `AI/AGENT_SYSTEM_PROMPT.md` → this file → `PXL_HOW_WE_WORK.md` → Product
Architecture → Roadmap for planning → only what the mission names; start a new
session with `AI/ONBOARDING_PROMPT.md`.

**Current phase: Delivery Plan Phase 5 — the two canonical flows.** Phases 1, 3
and 4 are built locally; Phase 2's remaining work is **owner-supplied** (a backup
destination on a separate failure domain and an escrowed passphrase).

The certification ceremony was **retired 2026-08-02** for automated invariants
(`PXL_HOW_WE_WORK.md` §3–4). Do not run an audit mission. Read the state, run the
gates, fix what fails, build the next thing. **This file is the only status
authority** for finding counts, test counts, certification, reconciliation
standing and maturity; `git log` is the session history.

## Current Finding Standing

**93 Retested Passed / 0 In Progress / 0 Open (93 total).** The finding program
is complete; that certifies no module or engine and confers no readiness.

## Active Work Map

- **Certified modules:** 0 / 11 certification scopes.
- **Certified engines:** 4 / 19 — Permissions/RLS, Audit & Immutability, Number
  Series and Dimension. The **Tax Engine exists at M5** (PAD-001), is guarded and
  is **not certified**; no engine became certified this session.
- **Critical reconciliations evidenced:** **1 / 9.** Inventory-to-control
  reconciles at 0.00 in every stock-holding company, guarded by test `111`.
- **Exercised posting entry points:** **13 of 24** — the honest completion measure.
- **Certified work packages:** IA-5 ECC WP-1…WP-4, 4 / 9, **frozen, 21 tables all
  empty, zero consumers.** WP-5…WP-9 and IA-6 stopped.
- **Canonical workflows meeting Product DoD:** 0 / 6.
- **Transaction workspaces:** **37** registry entries; Sales Invoice is the sole
  source-reviewed slice. UI rollout is not business completion:
  business qualification remains source-gated.
- **Visible scaffolds:** **30** deferred routes labelled "Not built"; **17** nav
  labels with no page. 247 nav entries → 175 routes, **145** on real data.
- **Tests:** 119 pgTAP files / 2,793 assertions plus 60 frontend source tests;
  full regression, canonical, build and lint lanes pass.
- **Backup/restore:** **Mechanised and scheduled; never operated over anything
  real.** `npm run backup:operate` runs one fail-closed cycle weekly via
  `.github/workflows/backup-drill.yml`. RPO 24h pilot. See blocker 5.

Payroll is a **future separate product — excluded from current PXL ERP progress**.

## Known Blockers and Non-Assumptions

1. No complete Sales or Purchasing source-to-financial-statements-to-tax workflow
   meets the Product Definition of Done.
2. Sales Invoice (test 054) **and Cash Sale** (test 119, 2026-08-03) both post
   COGS and inventory relief. Open: Customer Return has no COGS path, Delivery
   Receipt does not relieve inventory, three-way match and over-receipt control.
3. **Percentage tax is calculated nowhere in PXL and never has been**, so a
   PT-registered company has no percentage tax to review or file. **Nothing has
   ever been filed**: all twelve `compliance_*` working-paper tables and the
   return/form tables are empty. No governed UI can configure a tax-code
   succession (Backlog 10) and the company tax profile is not effective-dated
   (Backlog 11).
4. Phase 3 exists locally but is not operationally accepted: no hosted migration,
   deployed invite function, cut-over rehearsal or browser/UAT proof has occurred.
5. Recoverability is mechanised but not operated: the weekly workflow has never
   fired, no durable destination or escrowed passphrase exists, the replication
   proof used separate storage on the **same machine**, PITR is untested, and no
   PXL database holds real books.
6. Hosted parity is absent after `20260716000005`.
7. Frontend evidence is source-contract and production-build coverage only; no
   automated browser workflow lane exists.

## Current Engineering Frontier

Delivery Plan Phase 4 shipped 2026-08-03: `fn_calculate_tax`, migration
`20260803000001`. The plan said seven duplicated calculators; the catalog said
**eleven**, and all eleven migrated. Scope is VAT plus ATC withholding
(EWT/CWT/FWT); **percentage tax is excluded — nothing calculates it.**

VAT was made effective-date aware the same day, migration `20260803000002`, test
`118` (25 assertions). `fn_resolve_vat_code` is the one place a VAT code's
validity is decided — version, tax-code version, tax side, company profile, all
as of the document date — and the engine, the line/header trigger backstop (the
parent document's date, not today) and the picker `fn_vat_codes_asof` all ask it,
so the UI offers exactly what the database accepts. A rate change is a closed
window plus a successor.

**Cash Sale posting shipped 2026-08-03**, migration `20260803000003`, test `119`
(26 assertions). Cash Sale had posted revenue, output VAT and its receipt while
never touching inventory: a counter sale of stock left the stock on the books. It
now relieves stock and posts COGS through the *same* `fn_ensure_stock_balance` /
`fn_consume_cost_layers` path as `fn_post_sales_invoice` — no second costing
implementation — and writes the `inventory_transactions` issue row the line points
back at. Two line-model gaps closed with it: **Business Tax and Withholding Tax
are both per line** (`sales_invoice_lines.withholding_*`), so one sale can mix
goods and services under different ATCs and the tax ledger carries one
`cwt_receivable` row per ATC; and **VAT-inclusive pricing works**.
`receipt_lines.cwt_source` lets one settlement row declare that its withholding
detail is itemised on the invoice, without weakening the settlement key.

Phase 3 is implemented locally and unchanged (PAD-002, PAD-003). IA-5/ECC is
**frozen** at zero consumers and zero events; WP-1…WP-4 certified, WP-5
unauthorised, evidence archived under `docs/PXL/archive/ia5-ecc-frozen/`. Resume
only for a real costing-replay requirement. Posting P5.2 remains fully enforced;
the Accounting Kernel is a component inside the Posting Engine, not an engine.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is at migration `20260716000005`; **58
local migrations are pending**, with **no destructive DDL**. The deploy is
**rehearsed, not performed, and deliberately deferred** — nothing consumes the
hosted database and CI deploys nothing. Credentials are absent by design
(PXL-AUD-055). See `PXL_DEPLOY_RUNBOOK.md`.

Thirty-three reachable routes are backed only by future-deferred tables and 18
nav items are disabled placeholders. A rendered page is not a workflow.

## Last Verified Commands

- `npm run test:db:fresh` — **PASS** on 2026-08-03.
- `npm run test:canonical` — **PASS**, 30 files / 751 assertions.
- `npm run test:db:regression` — **PASS**, 119 files / 2,793 assertions; the lane
  resets to a fresh schema first, so it is order-independent.
- Focused lane — **PASS**, `119` 26, `118` 25, `117` 31, `090` 51, `100` 16,
  `102` 78, `103` 99.
- `npm run test:frontend` — **PASS**, 60 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; lint reports
  one pre-existing non-blocking warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; 119 tests indexed.
- `npm run backup:operate` — **PASS** (2026-08-02); replicated copy restored
  independently, 93 tables / 0 mismatches.
- Inventory-to-control variance **0.00** in all three stock-holding companies;
  trial balance out-of-balance **0.00** in all five.

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action.**
PAD-007: self-managed encrypted backups to S3-compatible storage, no PITR for
the pilot. To close it, follow Runbook §6 — bucket, `PXL_OFFSITE_URL` plus
access-key secrets, and `PXL_BACKUP_PASSPHRASE` escrowed off the host.

**Cash Sale is done.** Next build task: **finish Delivery Plan Phase 5 item 3 —
Customer Return COGS and Delivery Receipt inventory relief**, the last two
outbound entry points. Customer Return produces a credit memo but returns no
stock; Delivery Receipt ships goods that stay in stock at full cost. Both gate
the Sales flow proof (item 1).

Phase 5 runs flows → statements (`account_fs_map` has **never held a row**) →
filing, in that order. Tax remainders are Product Backlog Tax Engine items 8–19:
percentage tax (now unblocked — build the whole chain or none of it), the
governed tax-code maintenance screen (item 10, needed before any real BIR rate
change), the effective-dated company tax profile (item 11), rolling the per-line
tax model to the other documents (item 18), and the full Lines-workspace line
detail (item 19).

**The hosted deploy is deferred, not blocked** (Deploy Runbook §2a); re-run
`npm run deploy:rehearse` after adding migrations — the pending set is now **58**.
**Requires explicit owner approval.**

No open findings remain. Do not resume IA-5: canonical Sales/Purchasing proof,
statement presentation and operated recovery outrank dormant foundation work.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6; no
WP-5 implementation; preserve IA-5 dormancy; a non-zero `inventory_events` count
is a governance stop; no hosted operation without approval; no product-scope
change without a Product Architecture Amendment. WP-5…WP-9 remain
unauthorised. Do not create a governance document in a commit that contains no
application or SQL change.
