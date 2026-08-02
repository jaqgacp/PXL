# PXL AI State

**Current Date:** 2026-08-02
**Current Branch:** `main`
**Working Tree:** Delivery Plan Phase 3 onboarding implementation is complete
locally with executed fresh, focused, canonical, regression and frontend evidence.
Phase 2 recoverability is now mechanised, scheduled and proven; the regression
lane was made order-independent after it was found to report a false red.
**Product Phase:** Pilot Execution Plan. The IA-5/ECC dormant programme is
**frozen**; work is sequenced by product value, not by foundation depth.
**Environment:** Local Supabase on a fresh schema; fresh replay, canonical and
full regression lanes all executed and passing. No hosted operation was performed.
**Product Readiness:** **Internal QA/demo only. Not pilot-ready. Not
production-ready.** PXL is not production-ready.

## Canonical Authority and Startup

Four authorities, four questions — settled 2026-08-02; none answers another's:
**what** PXL is → `PXL_PRODUCT_ARCHITECTURE.md`; **when/in what order**, the only
numbered phases and the timeline → `PXL_DELIVERY_PLAN.md`; **why** that order —
outcome dependencies and quality bars → `PXL_PRODUCT_EXECUTION_ROADMAP.md`, which
carries **no phase numbers**; **where** we are → this file. An unqualified
"Phase N" means a Delivery Plan phase.

A brand-new session should be started with `AI/ONBOARDING_PROMPT.md`.

**Current phase: Delivery Plan Phase 2 — Operational safety.** Phase 1 complete;
Phase 3 was built locally out of sequence on 2026-08-02 because its interrupted
work already existed in the tree. The backup service is built, scheduled and
proven including offsite replication; what remains of Phase 2 is
**owner-supplied**: a destination on a separate failure domain and an escrowed
passphrase.

Startup order: `AI/AGENT_SYSTEM_PROMPT.md` → this file → `PXL_HOW_WE_WORK.md` →
Product Architecture → Roadmap for planning → only what the mission names.

The certification-ceremony process was **retired on 2026-08-02** and replaced by
automated invariants (see `PXL_HOW_WE_WORK.md` §3–4). Do not run an audit
mission. Read the state, run the gates, fix what fails, build the next thing.

**This file is the only status authority.** Finding counts, test counts,
certification standing, reconciliation standing and maturity live here and
nowhere else. Do not create a second status dashboard or a session-log file;
`git log` is the session history. Two former root status files drifted into
reporting inventory as unreconciled after it was fixed, and were archived.

## Current Finding Standing

**93 Retested Passed / 0 In Progress / 0 Open (93 total).** The finding program
is complete, but that evidence does not certify any module or engine and does
not make the product production-ready.

## Active Work Map

- **Certified modules:** 0 / 11 certification scopes.
- **Certified engines:** 4 / 19 — Permissions/RLS, Audit & Immutability, Number
  Series and Dimension.
- **Critical reconciliations evidenced:** **1 / 9.** Inventory-to-control
  reconciles at 0.00 in every stock-holding company, guarded by test `111`.
- **Exercised posting entry points:** **12 of 24** (re-measured 2026-08-02; was
  recorded as 11 of 22) — the honest completion measure.
- **Certified work packages:** IA-5 ECC WP-1…WP-4, 4 / 9, **frozen, 21 tables all
  empty, zero consumers.** WP-5…WP-9 and IA-6 stopped.
- **Canonical workflows meeting Product DoD:** 0 / 6.
- **Transaction workspaces:** **37** registry entries; Sales Invoice is the sole
  source-reviewed slice. UI rollout is not business completion:
  business qualification remains source-gated.
- **Visible scaffolds:** **30** deferred routes labelled "Not built"; **17** nav
  labels with no page. 247 nav entries → 175 routes, **145 backed by real data**.
- **Tests:** 116 pgTAP files / 2,709 assertions plus 58 frontend source tests;
  full regression, canonical, build and lint lanes pass.
- **Backup/restore:** **Mechanised and scheduled; not operated over anything
  real.** `npm run backup:operate` runs one fail-closed cycle: backup →
  restore-verify → encrypted offsite replication with read-back → retention →
  journal; `.github/workflows/backup-drill.yml` runs it weekly. RPO 24h pilot.
  **Still owner-supplied: the bucket and an escrowed passphrase. The schedule
  has never fired and no PXL database holds real books.**

Payroll is a **future separate product — excluded from current PXL ERP progress**.

## Known Blockers and Non-Assumptions

1. No complete Sales or Purchasing source-to-financial-statements-to-tax workflow
   meets the Product Definition of Done.
2. Sales Invoice **does** post COGS and inventory relief (test 054; canonical
   COGS debits equal inventory credits). The "sales-side COGS does not exist"
   claim was false, corrected 2026-08-02. Actually open: **Cash Sales has no
   posting function**, Customer Return has no COGS path, Delivery Receipt does
   not relieve inventory, three-way match and over-receipt control.
3. No Tax Engine exists. Tax capability is distributed across reference masters,
   save-layer calculators, tax ledger and Compliance surfaces. PAD-001 is
   required before engine implementation.
4. Phase 3 exists locally but is not operationally accepted: no hosted migration,
   deployed invite function, real-company cut-over rehearsal or browser/UAT proof
   has occurred.
5. Recoverability is mechanised but not operated: the weekly workflow has never
   fired, no durable destination or escrowed passphrase exists, the replication
   proof used separate storage on the **same machine**, nothing has run against
   a hosted database, and PITR is untested.
6. Hosted parity is absent after `20260716000005`.
7. Frontend evidence is source-contract and production-build coverage only; no
   automated browser workflow lane exists.

## Current Engineering Frontier

Delivery Plan Phase 3 is implemented locally: one governed PHP opening-balance
cut-over across GL, AR, AP, inventory and bank detail, posting one balanced
Kernel journal and continuing into ordinary Receipt/Payment Voucher settlement
and AR/AP ageing; supplier bank accounts and PV payee snapshots with posting
guards; Administration for users/invite, memberships, roles and branch scopes;
the master-data importer made navigable. PAD-002 and PAD-003 decided to those
boundaries. The fresh settlement proof keeps IA-5 dormant at zero events.

The IA-5/ECC programme is **frozen** with zero consumers. WP-1…WP-4 remain
certified; WP-5 is unauthorised and unimplemented. Historical evidence is
archived under `docs/PXL/archive/ia5-ecc-frozen/`. Resume only when a real
costing-replay requirement demands it.

Posting P5.2 remains fully enforced. The Accounting Kernel is a component inside
the Posting Engine, not a separate engine.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is at migration `20260716000005`; **55
local migrations are pending.** The deploy is **rehearsed, not performed, and
deliberately deferred** — nothing consumes the hosted database, there is no
deployed frontend, and CI deploys nothing. The pending set contains **no
destructive DDL**; `npm run deploy:rehearse` proves it reaches a state
structurally identical to a fresh replay in 8s. Credentials are absent by design
(PXL-AUD-055), owner-supplied, never pasted into a transcript or file. See
`PXL_DEPLOY_RUNBOOK.md`.

Thirty-three reachable routes are backed only by future-deferred tables, and 18
navigation items are disabled placeholders. A route or rendered page is not a
complete workflow.

## Last Verified Commands

- `npm run test:db:fresh` — **PASS** on 2026-08-02.
- `npm run test:canonical` — **PASS**, 30 files / 749 assertions.
- `npm run test:db:regression` — **PASS**, 116 files / 2,709 assertions. The lane
  now resets to a fresh schema first; previously it inherited the prior lane's
  state, so the documented order (fresh → canonical → regression) reported a
  false red — the canonical seed populates `companies`, removing the zero-company
  bootstrap in `fn_provision_company` that tests 073 and 116 rely on. Guarded by
  `tests/recoverability_operations.test.ts`.
- Phase 3 focused lane — **PASS**, 4 files / 74 assertions.
- `npm run test:frontend` — **PASS**, 58 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; lint reports
  one pre-existing non-blocking warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; 116 tests indexed.
- `npm run backup:operate` — **PASS**; the replicated copy restored independently
  (93 tables / 0 mismatches / 6s RTO). Verifier proven able to fail against a
  deliberately corrupted restore; all four offsite refusals exercised.
- Inventory-to-control variance **0.00** for ABC Trading Corporation, Bayani
  Partners and Company, and Golden Retail Store; trial balance out-of-balance
  **0.00** in all five companies.

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action.**
PAD-007 decided: self-managed encrypted backups to S3-compatible storage, no
PITR for the pilot. To close it: create the bucket, run
`npm run backup:offsite:check`, set `PXL_OFFSITE_URL` plus the access-key
secrets, and escrow `PXL_BACKUP_PASSPHRASE` off the host. Runbook §6.

**The next build task is Delivery Plan Phase 4 — the Tax Engine calculator
(PAD-001)**, unless the owner authorises the hosted deploy first. It depends only
on Foundation and is unblocked today. **Filing artifacts are not part of it**:
they were moved to Phase 5.8 on 2026-08-02 because a return is generated from
posted, closed data. Phase 5 runs flows → statements (`account_fs_map` has never
held a row) → filing, in that order. Phase 3's local build is complete; not
pilot-ready until hosted parity, the invite function, a real cut-over rehearsal
and browser/UAT evidence exist.

**The hosted deploy is deliberately deferred, not blocked** (Deploy Runbook §2a);
re-run `npm run deploy:rehearse` after adding migrations. **Requires explicit
owner approval.**

No open findings remain. Do not resume IA-5: operated recovery, canonical
Sales/Purchasing proof, statement presentation and Tax ownership all rank above
dormant foundation work.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6; no
WP-5 implementation; preserve IA-5 dormancy; a non-zero `inventory_events` count
is a governance stop; no hosted operation without approval; no product-scope
change without a Product Architecture Amendment. WP-5…WP-9 and IA-6 remain
unauthorised. Do not create a governance document in a commit that contains no
application or SQL change.
