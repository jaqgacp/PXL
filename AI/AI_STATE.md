# PXL AI State

**Current Date:** 2026-08-03
**Current Branch:** `main`
**Working Tree:** Delivery Plan Phase 5.7 — **financial statement presentation**
— is complete locally with executed fresh, canonical, regression, frontend,
build and lint evidence. All four statements are produced from governed
`fs_structure` / `account_fs_map` configuration, not from code.
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
- **Exercised posting entry points:** **14 of 24** — the honest completion measure.
- **Certified work packages:** IA-5 ECC WP-1…WP-4, 4 / 9, **frozen, 21 tables
  empty, zero consumers.** WP-5…WP-9 and IA-6 stopped.

- **Canonical workflows meeting Product DoD:** 0 / 6.
- **Transaction workspaces:** **37** registry entries; Sales Invoice the sole
  source-reviewed slice. UI rollout is not business completion:
  business qualification remains source-gated.
- **Visible scaffolds:** **30** deferred routes labelled "Not built"; **17** nav
  labels with no page. 247 nav entries → 175 routes, **145** on real data.

- **Tests:** 121 pgTAP files / 2,842 assertions plus 60 frontend source tests;
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
   statement re-presentation (18f); the tax profile is not effective-dated (11);
   **period close does not exist** (18d).
4. Phase 3 is not operationally accepted: no hosted migration, deployed invite
   function, cut-over rehearsal or browser/UAT proof.
5. Recoverability is mechanised but not operated: the weekly workflow has never
   fired, no durable destination or escrowed passphrase exists, the replication
   proof used storage on the **same machine**, and no PXL database holds real books.
6. Hosted parity is absent after `20260716000005`.
7. Frontend evidence is source-contract and build coverage only; no automated
   browser workflow lane exists.

## Current Engineering Frontier

Phase 4 shipped 2026-08-03: `fn_calculate_tax` (`20260803000001`) — the catalog's
**eleven** duplicated calculators all migrated. Scope is VAT plus ATC
withholding; **percentage tax is excluded — nothing calculates it.** VAT became
effective-date aware the same day (`20260803000002`, test `118`):
`fn_resolve_vat_code` is the one place a VAT code's validity is decided — version,
tax side, company profile, as of the document date — and the engine, the trigger
backstop and the picker `fn_vat_codes_asof` all ask it.

**Cash Sale posting shipped** (`20260803000003`, test `119`): it relieves stock
and posts COGS through the *same* costing path as `fn_post_sales_invoice`, and
carries **Business Tax and Withholding Tax per line**, so one sale can mix goods
and services under different ATCs.

**Delivery Receipt and Customer Return followed** (`20260803000004`, test `120`),
completing Phase 5 item 3. A delivery relieves stock into **Goods Delivered Not
Invoiced** (`SALES_DELIVERY_CLEARING`); the invoice recognises that cost as COGS
and clears it **instead of relieving twice**, keyed on the line's
`source_document_type = 'DR'` link, with a unique index making double billing
impossible. A return puts goods back through `fn_receive_inventory`. **Billing a
delivery is only correct through the delivery's "Bill This Delivery" action** —
an unlinked invoice for delivered goods relieves stock again (18b).

**Financial statement presentation shipped** (`20260803000005`, test `121`, 25
assertions). `fs_structure` and `account_fs_map` had never held a row; the four
statement screens grouped accounts by `account_type` in the browser with the
layout hardcoded in TSX. Presentation is now configuration —
`chart_of_accounts → account_fs_map → fs_structure` — one account bound to exactly
one line per statement, a subtotal defined as the sum of its children, so no
formula language exists. `fn_financial_statement_report` is the single reporting
entry point returning opening/movement/closing per line: the position reads
closing, comprehensive income movement, equity all three, and cash flows movement
classified by governed metadata, proving itself by tying to the cash movement.
Two missing pieces of metadata were added: `is_cash_equivalent` and
`fs_structure.line_role`. Reporting never writes the ledger.

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
- `npm run test:db:regression` — **PASS**, 121 files / 2,842 assertions; the lane
  resets to a fresh schema first, so it is order-independent.
- Focused lane — **PASS**, `121` 25, `120` 24, `119` 26, `118` 25, `117` 31.
- `npm run test:frontend` — **PASS**, 60 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; lint reports
  one pre-existing warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; 121 tests indexed.
- `npm run backup:operate` — **PASS** (2026-08-02); replicated copy restored
  independently, 0 mismatches.
- Inventory-to-control variance **0.00** in all three stock-holding companies;
  trial balance out-of-balance **0.00** in all five; the canonical demo
  Statement of Financial Position balances at **0.00** (assets 622,768.80).

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action.**
PAD-007: self-managed encrypted backups to S3-compatible storage, no PITR for the
pilot. Close it via Runbook §6 — bucket, `PXL_OFFSITE_URL` plus access keys, and
`PXL_BACKUP_PASSPHRASE` escrowed off the host.

**Phase 5 items 3 and 7 are complete.** Next build task: **period close and
year-end roll-forward (Backlog 18d)** — the largest remaining accounting-cycle
gap. Nothing rolls revenue and expense into retained earnings, so a company
entering its second fiscal year shows the prior year's profit in Current Year
Earnings instead of Retained Earnings, and comparative statements cannot mean
anything. `CLOSE` is already a registered posting source type.

Phase 5 runs flows → statements → filing, in that order. Remaining Product
Backlog items: percentage tax (8, unblocked — whole chain or none), tax-code
maintenance (10), effective-dated tax profile (11), per-line tax on the other
documents (18), delivery-to-invoice conversion (18b), DR cancellation (18c),
comparatives and notes (18e), FS structure maintenance (18f), line detail (19).

**The hosted deploy is deferred, not blocked** (Runbook §2a); re-run
`npm run deploy:rehearse` after adding migrations — the pending set is **60**.
**Requires explicit owner approval.**

No open findings remain. Do not resume IA-5: canonical flow proof, period close
and operated recovery outrank dormant foundation work.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6; no
WP-5 implementation; preserve IA-5 dormancy; a non-zero `inventory_events` count
is a governance stop; no hosted operation without approval; no product-scope
change without a Product Architecture Amendment. WP-5…WP-9 remain
unauthorised. Do not create a governance document in a commit that contains no
application or SQL change.
