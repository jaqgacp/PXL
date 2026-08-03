# PXL Delivery Plan — from here to a finished product

**Status:** Active — the complete end-to-end plan to finish PXL
**Authority:** Tier 1 Delivery Planning, subordinate to `PXL_PRODUCT_ARCHITECTURE.md`
**Owner / Domain:** Product
**Read When:** Asking "what is the whole plan?", "what phase are we in?", or "what do I build next?"
**Do Not Read For:** Current status (`AI/AI_STATE.md`), what PXL is (Product Architecture), or how we work (`00. Governance/PXL_HOW_WE_WORK.md`)
**Date:** 2026-08-02

> **This document is the only place in PXL that numbers phases.** It owns the
> delivery sequence, the phase numbers, the target timeline and the pilot
> roadmap. When any document says "Phase 4" without qualification, it means
> Phase 4 *of this plan*.
>
> `PXL_PRODUCT_EXECUTION_ROADMAP.md` explains **why** the order is what it is —
> dependencies between outcomes, the two quality bars and the per-module
> criteria. It deliberately carries **no phase numbers** and must never become a
> second delivery plan. `PXL_PRODUCT_ARCHITECTURE.md` defines **what** PXL is.
> `AI/AI_STATE.md` records **where we are today**.
>
> The one exception: the retired certification programme had its own phase
> numbering, which survives only in historical records and is always written
> "certification-programme Phase N".

---

## The target

**One Philippine SME — VAT-registered, inventory-carrying — runs its real books
on PXL for one full quarter, in parallel with its existing process, and the
quarter closes correctly.**

That is "finished" for v1. Everything below is sequenced to reach it. Nothing
that does not serve it belongs in v1.

---

## Scope decisions already made

These are settled. Do not reopen them without a Product Architecture Amendment.

| Decision | Ruling |
|---|---|
| **Banking & Treasury** | **v2.** Keep only Check Voucher (the Cash Disbursements Book needs it). Petty cash, bank reconciliation, transfers → v2. |
| **Fixed Assets** | **v2**, except a minimal straight-line depreciation run if the pilot client holds assets. |
| **Income Tax** | **v2.** Ten screens, none has ever held a row. |
| **Accounting Schedules** | **v2.** Amortisation and revenue recognition. |
| **IA-5 / ECC chronology** | **Frozen.** Dormant, no consumers. Inventory reconciles without it. Do not resume without a real costing-replay requirement. |
| **Multi-currency** | **Deferred.** PHP only. |
| **Payroll** | **Separate future product.** Never counted in PXL progress. |
| **Deferred surfaces** | Marked **Not built** in the navigation via `src/lib/deferredSurfaces.ts`. |

---

## The phases

Effort assumes one developer with AI assistance. **Phase 1 is complete.**

### ✅ Phase 1 — Close the accounting break · DONE 2026-08-02

Receiving a goods receipt moved stock without writing a journal, so inventory
could never reconcile to its control account.

Delivered: `PXL-AUD-073`. Receipt posts DR inventory control / CR purchase
clearing through the sealed doorway; `INVENTORY_CONTROL` and `PURCHASE_CLEARING`
governed in `company_accounting_config`; cost layers no longer created for
weighted-average items; opening journals valued from opening receipts.

**Evidence:** inventory variance ₱0.00 in every stock-holding company; guard test
`111`; fresh-data end-to-end test `112` proving PO → RR → Bill from first
principles. First of nine critical reconciliations evidenced.

---

### ◐ Phase 2 — Operational safety · **IN PROGRESS**

Cheapest remaining unblock. Gates every module. Not software.

| Item | Status |
|---|---|
| 1. `pg_dump` with checksum, manifest and optional AES-256 encryption | ✅ `scripts/backup.sh` |
| 2. **Restore into a clean database and diff** | ✅ `scripts/restore_verify.sh` — 92 tables, 0 mismatches |
| 3. Record RPO and RTO | ✅ measured: restore 6–8 s; RPO 24 h pilot (the 1 h production RPO needs PITR, deferred by PAD-007) |
| 4. Runbook executed at least once | ✅ `00. Governance/PXL_BACKUP_AND_RECOVERY_RUNBOOK.md` |
| 5a. Put the drill on a schedule | ✅ `.github/workflows/backup-drill.yml`, weekly + on any recovery-script change |
| 5b. Offsite replication, retention, fail-closed cycle | ✅ `npm run backup:operate` — replicated copy restored independently; every refusal exercised |
| 5c. PAD-007 operating model | ✅ **decided 2026-08-02** — self-managed encrypted backups to S3-compatible object storage; no provider PITR for the pilot |
| 5d. Create the bucket, escrow the passphrase | ☐ **owner action** — `npm run backup:offsite:check` proves a destination with a canary holding no client data |
| 6. Close hosted parity | ⏸ **deliberately deferred** — nothing consumes the hosted database today. Change set proven non-destructive and the upgrade rehearsed; `npm run deploy:hosted` runs the guarded sequence when wanted. **Must happen before Phase 6.** |

Verified 2026-08-02: full drill passes, encrypted round-trip passes, and the
verifier was **proven able to fail** against a deliberately corrupted restore
(dropped function and deleted rows both detected). A restored database also stays
kernel-protected — deleting ledger rows in the restored copy is still rejected by
the Accounting Kernel.

**Done when:** the drill runs on a schedule against an offsite copy.

The drill now runs on a schedule and the offsite path is built, proven and fails
closed. PAD-007 selects self-managed encrypted replication to S3-compatible
object storage; provider-native PITR is not adopted for the pilot, so the
promise is the 24-hour pilot RPO and the 1-hour production RPO stays open until
a production claim is actually on the table. What is left is not code: an actual
bucket and a passphrase escrowed off the host. Until those exist,
recoverability is **mechanised but not operated over anything real**, which is
honest rather than alarming — no PXL database holds real books yet.

Hosted parity is deferred by decision, not blocked by engineering — see the
Deploy Runbook §2a.

---

### Phase 3 — Make it onboardable · implemented locally 2026-08-02

The local implementation is complete. Operational acceptance remains bounded by
Phase 2 recoverability, hosted parity, deployment of the invite function, and a
real-company cut-over/browser/UAT rehearsal.

1. **Opening balances** (PAD-002) — a governed cut-over document: trial balance,
   AR by customer and invoice, AP by supplier and bill, inventory by item and
   warehouse with cost, bank balances. Posts one balanced opening journal through
   the sealed doorway. Must reconcile subledger to control **by construction** —
   the ₱630 seed defect found in Phase 1 is exactly what happens when it does not.
2. **Supplier bank details** — a payment voucher cannot carry a validated payee
   account today.
3. **Minimum administration UI** (PAD-003) — user list, invite, company
   membership, role assignment, branch scope. Four screens. Today memberships are
   created by SQL.
4. Surface the master-data import framework (built, no menu entry).

**Done when:** you can take a real company's December 31 trial balance and stand
them up on PXL. The capability and fresh-company accounting proof now exist
locally; this is not yet evidence that a real or hosted onboarding was operated.

---

### ✅ Phase 4 — Tax Engine (the calculator) · calculator DONE 2026-08-03

PAD-001 **decided and implemented 2026-08-03: Accounting-owned, one calculator.**

`fn_calculate_tax(context) → SETOF tax_component` is now the only function in
the schema that turns a governed rate into a tax amount. Migration
`20260803000001_tax_engine_calculator.sql`.

The census was **eleven**, not seven. The seven document-save routines named
below plus two withholding validators and two EWT profile appliers all computed
`rate / 100` independently; test `090` assertion 6 measured it. All eleven now
call the engine, and that assertion reads exactly one function.

**Evidence.** Test `117` (31 assertions, self-provisioned company) proves the
engine's arithmetic. Test `090` proves the structure — and its assertions
17–43, 45 and 46 passed **unchanged** across the migration, which is the
"every existing caller produces identical tax output" requirement satisfied by
the suite rather than by assertion. Full regression at the time was 117 files /
2,742 assertions; it stands at **121 files / 2,842** after Phase 5 items 3 and 7.

**One deliberate behaviour change, not a byte-identical migration.**
`fn_save_cash_sale` resolved its CWT rate with no active, deprecation or
effective-date filter, so a cash sale could withhold at a superseded ATC
version; every other withholding path already refused this. It now goes through
the engine like the rest. Guarded by test `090` assertion 47a.

**VAT made effective-date aware 2026-08-03** — migration
`20260803000002_vat_effective_date_resolution.sql`. The calculator shipped
governing *withholding* by the document date while VAT resolved
`WHERE vc.id = <id>` and ignored active state, deprecation, succession and
effective windows; an unresolvable code degraded silently to `exempt at 0%`.
The version machinery for VAT had existed since `20260713000012` and the engine
simply did not consult it.

`fn_resolve_vat_code` is now the single place PXL decides whether a VAT code may
be used: both the VAT-code version and its rate-bearing tax-code version must be
active, undeprecated and in force on the document date; the code must match the
document's tax side; and the company tax profile must permit a VAT-bearing rate.
It fails closed. The engine, the line and header trigger backstop
(`fn_validate_company_vat_code`, now evaluated against the *parent document's*
date rather than today) and the picker `fn_vat_codes_asof` all ask that one
resolver, so the frontend offers exactly what the database accepts. A BIR rate
change is made by closing the current window and configuring a successor;
history is never edited in place, and a document dated inside a closed window
still resolves — and still keeps — the version that governed it. Test `118`,
25 assertions, self-provisioned companies, across a real 12% → 14% succession.

**Still open in this phase:**

- **Percentage tax is calculated nowhere** — not by the engine, and not by
  anything before it. A non-VAT, PT-registered company's sales compute no
  percentage tax at all, so the PT review surfaces have no source. Adding a PT
  branch to the engine without a document calling it would be foundation with
  no consumer, which this repository has already paid for once. The whole chain
  ships together or not at all: Sales Invoice or Cash Sale → PT computation →
  PT tax detail/ledger → PT liability posting → PT reconciliation → 2551Q
  working paper and return. It needs a posting change (a PT liability line), so
  it belongs with the Phase 5 flows. Recorded in the Product Backlog, item 8.
- **The company tax profile is not effective-dated.**
  `companies.tax_registration` is one scalar with no history, so VAT validation
  resolves a document's profile from today's registration. Every tax-profile
  read now goes through `fn_company_tax_registration_asof(company, date)`, which
  accepts the date and cannot yet honour it — one seam, so the fix is one
  function plus a history table. It does **not** block correct VAT resolution
  and was deliberately not attempted here. Product Backlog item 11; test `118`
  assertion 25 pins it.
- **No governed maintenance screen exists for tax codes.** The secured RPCs and
  the version guards do; nothing in the UI drives them, so a real BIR rate
  change cannot yet be configured by an administrator. Product Backlog item 10 —
  the prerequisite for real tax maintenance.
- The frontend still prices lines for preview independently of the engine;
  `fn_calculate_tax` is authenticated-executable so a form can call it, but no
  form does yet. The reference half is closed: the pickers read
  `fn_vat_codes_asof`, not `vat_codes` filtered on `is_active`.

> **Scope corrected 2026-08-02.** This phase briefly also owned the BIR filing
> artifacts. That was a dependency error: a return is generated from posted,
> *closed* data, so filing cannot precede the period-close and statement work in
> Phase 5, whereas the calculator can and should come first — it runs at
> document-save time and has no dependency on Period Close. The filing artifacts
> moved to **Phase 5.8**. Nothing was added or removed from the plan; one item
> changed phase.

1. ✅ `fn_calculate_tax(context) → SETOF tax_component` — one authority for VAT
   (inclusive and exclusive) and withholding by ATC (EWT and FWT share the
   mechanism). **Percentage tax is not implemented — see above.**
2. ✅ Migrate the **eleven** routines that computed tax independently. The seven
   save routines (`fn_save_cash_purchase_core_20260718`, `fn_save_cash_sale`,
   `fn_save_credit_memo`, `fn_save_debit_memo`,
   `fn_save_sales_invoice_aud053_core`, `fn_save_vendor_bill_core_20260718`,
   `fn_save_vendor_credit`), the two withholding validators
   (`fn_validate_payment_voucher_line_ewt`, `fn_validate_receipt_line_cwt`) and
   the two EWT profile appliers (`fn_apply_vendor_bill_line_ewt_profile`,
   `fn_apply_cash_purchase_line_ewt_profile`). *This item said seven; the
   schema-wide census in test `090` said eleven, and the census was right.*
   VAT-inclusive pricing existed in exactly one of them and is now shared.
3. ✅ Regression proof that every caller produces identical output — carried by
   the pre-existing assertions in test `090`, which passed unchanged.

**Done when:** there is one place to change a BIR rate, and every existing caller
produces identical tax output through it. **Met for VAT and withholding on
2026-08-03.** Filing capability is **not** claimed here — that is Phase 5.8, and
percentage tax calculation moves to the Phase 5 flows because it needs a posting
change and a document that calls it.

---

### Phase 5 — Prove the two canonical flows, then close and file · 3–4 weeks plus unestimated additions

Items 1–6 are mostly proof of what exists. Items 7–8 are genuine build, added
2026-08-02, and are the reason this phase no longer carries a single estimate.

**Internal order matters here:** flows (1–6) → statements (7) → filing (8). Each
depends on the one before it; a return generated before the period's statements
are right is a return that changes after submission.

1. **Sales:** Quotation → SO → DR → SI → OR → VAT → SLS → Sales Journal → AR →
   TB → FS, including credit memo and void.
2. **Purchase:** PO → RR → Bill → PV → EWT → 2307 → SLP → Purchase Journal → AP →
   TB → FS, including three-way match and vendor credit.
3. **Close the remaining outbound inventory entry points.** Corrected
   2026-08-02: Sales Invoice already posts DR COGS / CR inventory with weighted
   average or FIFO layer consumption, an insufficient-stock guard and reversal
   on void — `fn_post_sales_invoice`, asserted by test `054`, and visible in the
   canonical ledger as COGS debits equalling inventory credits. The earlier
   claim that sales-side COGS did not exist was wrong; inventory could not
   reconcile at ₱0.00 in trading companies if it were true.
   ✅ **Cash Sale closed 2026-08-03** — migration
   `20260803000003_cash_sale_posting.sql`, test `119` (26 assertions,
   self-provisioned company). `fn_save_cash_sale` had posted revenue, output VAT
   and the receipt while never touching inventory. It now relieves stock and
   posts COGS through the *same* `fn_ensure_stock_balance` /
   `fn_consume_cost_layers` path as `fn_post_sales_invoice` — no second costing
   implementation exists — and writes the `inventory_transactions` issue row the
   line points back at. The framing "Cash Sales has no posting function" meant
   the missing capability, not a missing function name: Cash Sale still posts
   inside its save act, which is what a counter sale is.

   Two line-model gaps were closed with it because the document is wrong without
   them: **Business Tax and Withholding Tax are now both per line**, so one sale
   can mix goods withheld under one ATC with services withheld under another and
   the tax ledger carries one `cwt_receivable` row per ATC; and **VAT-inclusive
   pricing works**, because the line asks the engine with the document's
   `vat_price_basis` instead of assuming exclusive. Lines also carry warehouse,
   department, cost center, salesperson and account overrides.

   ✅ **Delivery Receipt and Customer Return closed 2026-08-03** — migration
   `20260803000004_sales_outbound_inventory.sql`, test `120` (24 assertions,
   self-provisioned company). A delivery now relieves stock and parks the cost in
   **Goods Delivered Not Invoiced** (`SALES_DELIVERY_CLEARING`, the outbound
   mirror of the `PURCHASE_CLEARING` key receiving already uses); the Sales
   Invoice recognises that cost as COGS and clears it **instead of relieving the
   stock a second time**, keyed on the line's `source_document_type = 'DR'` link,
   with a partial unique index making a delivery line impossible to bill twice.
   A Customer Return puts the goods back through `fn_receive_inventory` — the
   same inbound path receiving uses — at the cost they were issued at, reversing
   COGS. A credit-memo line with no warehouse remains a price adjustment and
   moves no stock, which is the common case and must stay possible.

   **This item is now complete.** All three outbound entry points relieve
   inventory, and the flow reconciles: cost leaves stock once, reaches COGS when
   the revenue does, and returns when the goods do.

   Two prerequisites were completed with it because the workflow is incorrect
   without either: `DR` registered in `ref_posting_source_types` (the delivery
   journal's `reference_doc_type` is a foreign key into it) and
   `fn_save_sales_invoice` accepting `DR` as a governed line source. Billing a
   delivery is driven from the Delivery Receipt ("Bill This Delivery"), which
   creates a draft invoice with the delivery links already in place — an
   unlinked invoice for delivered goods would relieve the stock twice, so that
   is deliberately the only supported path until Document Conversion (item 5)
   generalises it.
4. Evidence the remaining **critical reconciliations (currently 1 of 9)**. VAT and
   withholding already reconcile at zero variance — nearly free.
5. **Document Conversion**, minimally: carry quantities forward, prevent double
   conversion. This is what makes quote → invoice real.
6. Surface the accounting trace in the menu (complete, currently unreachable).
7. ✅ **Financial statement presentation — DONE 2026-08-03.** Migration
   `20260803000005_financial_statement_presentation.sql`, test `121` (25
   assertions, self-provisioned company). `account_fs_map` and `fs_structure`
   had never held a row, so the four statement screens grouped accounts by
   `account_type` in the browser with the layout hardcoded in TSX — a trial
   balance with headings.

   Presentation is now configuration held per company:
   `chart_of_accounts → account_fs_map → fs_structure → the statement`.
   `account_fs_map` binds each account to exactly **one** line per statement
   (already enforced by `uq_account_fs_map_active`); a subtotal is a parent line
   whose amount is the plain sum of its children, so there is no formula
   language and no layout in code. `fn_financial_statement_report` is the single
   reporting entry point and returns opening / movement / closing for every
   line, from which all four statements are read: **Statement of Financial
   Position** (closing), **Statement of Comprehensive Income** (movement),
   **Statement of Changes in Equity** (all three) and **Statement of Cash Flows**
   (movement, classified by the governed cash-flow metadata). The four pages
   became thin wrappers over one shared renderer.

   The COA already carried nearly everything needed — `fs_statement`, `fs_group`,
   `fs_subgroup`, `cash_flow_category`, `is_operating_expense`. Only two pieces
   of structure were genuinely missing and both were added: `chart_of_accounts.
   is_cash_equivalent` (a cash flow statement must know which accounts ARE cash;
   `cash_flow_category` says why a movement happened, not what cash is) and
   `fs_structure.line_role` (detail / subtotal / current_year_earnings /
   cash_reconciliation — roles, not formulas). `statement` also gained
   `equity_statement`. Posting logic is untouched: reporting reads the ledger and
   never writes it, so a re-presentation never disturbs a posted number.

   **Still open before the statements are pilot-complete:** period close (nothing
   rolls revenue and expense into retained earnings — the governed
   `current_year_earnings` line is what makes a mid-year position balance),
   comparative periods, note disclosures and consolidation. Recorded in the
   Product Backlog.
8. **BIR filing artifacts.** *Moved here from Phase 4 on 2026-08-02: a return is
   generated from posted, closed data, so this depends on items 1–7 above and
   cannot precede them.* All twelve `compliance_*` working-paper tables are
   empty, as are `bir_forms`, `form_2306_issuances`, `form_2307_issuances`,
   `form_2307_tracking`, `vat_returns`, `withholding_remittances` and
   `tax_credits_schedule`. **Nothing has ever been filed from PXL.** A
   VAT-registered pilot client cannot operate without at least: VAT return
   working papers, EWT working papers, Form 2307 issuance, and the SLS/SLP
   exports. Includes **Check Voucher**, the one Banking document kept in v1
   because the Cash Disbursements Book needs it — previously named in the scope
   decisions but never assigned to a phase.

Each flow proven by a **fresh-data end-to-end test in the style of `112`**, never
against the demo seed.

**Done when:** both flows meet the Pilot Bar with evidence, a full statement set
is produced from mapped accounts and ties to the trial balance, and one full
period's VAT, percentage tax and withholding returns are generated from posted
data and reconciled to the General Ledger at zero variance.

---

### Phase 6 — Pilot hardening · 3–4 weeks

1. **Frontend tests.** Playwright over the two canonical flows plus login,
   company switch, period lock. ~15 tests. The `npm run test:frontend` lane exists.
2. Error handling — every RPC failure surfaces a usable message, not a Postgres
   exception.
3. Monitoring — error capture, slow-query log, and a **daily reconciliation job
   that alerts if inventory or AR/AP stops tying out.**
4. Notifications, minimum viable — approval routing currently notifies nobody,
   and **no notification model exists anywhere in the product** (PAD-013).
5. **Prove approval routing at least once.** Two workflows are defined, but
   `approval_requests` and `approval_instances` have **never held a row** — the
   engine has never executed. Either exercise it end to end or explicitly take
   approvals out of pilot scope; shipping a defined-but-unrun approval engine is
   the worst of the three options.
6. **Operational access control.** Deploy the `admin-invite` Edge Function (written,
   never deployed) and exercise branch scoping — `user_company_branch_scopes` has
   never held a row, so per-branch restriction is unproven in practice.
7. Retire or finish the remaining **Not built** surfaces so the pilot menu is
   honest: 30 deferred routes and 17 navigation labels with no page (PAD-012).

**Done when:** a stranger can use it without you sitting beside them.

---

### Phase 7 — Pilot · one quarter, parallel run

One named client. Real transactions. Their existing books alongside. Reconcile
monthly, fix what breaks.

**This is where the remaining unknowns surface.** No amount of internal testing
finds what one real bookkeeper finds in a week.

**Done when:** a quarter closes correctly and the client's accountant signs the
financial statements.

---

### Phase 8 — v2 · after the pilot survives a quarter

Banking & Treasury · full Fixed Assets lifecycle · Income Tax · Accounting
Schedules · CAS accreditation · multi-currency · IA-5 resumption only if costing
replay becomes a real complaint.

---

## Timeline

**Revised 2026-08-02** after the measured status review added three pilot-critical
items that the previous estimate did not contain: financial statement
presentation, the BIR filing artifacts, and proving approval routing.

| Phase | Estimate | Confidence |
|---|---|---|
| Phase 1 — accounting break | ✅ done | — |
| Phase 2 — operational safety | days, not weeks (owner action only) | **High** — engineering is complete and proven |
| Phase 3 — onboardable | built locally; hosted/UAT proof outstanding | **Medium** |
| Phase 4 — Tax Engine (calculator only) | ✅ done 2026-08-03, incl. effective-dated VAT | — — the estimate was 4–6 weeks; the callers turned out to be enumerable and the outputs already pinned by test `090`, so the migration was mechanical once the census was believed over the prose. VAT effective-date resolution followed the same day: the version machinery already existed and only the resolution path had to be routed through it |
| Phase 5 — flows, then statements, then filing | 3–4 weeks for the flows; **statements and filing not estimated** | **Low** — see below |
| Phase 6 — pilot hardening | 3–4 weeks | **Low** — no browser lane exists yet to calibrate against |
| **To pilot** | **previously ~4 months; now unestimated — see below** | — |
| Phase 7 — pilot | one quarter parallel run | **High** — fixed by calendar |

### Why the "~4 months to pilot" figure was withdrawn

It was published before three pilot-critical items were known to be missing, and
none of them has a defensible estimate from repository evidence:

- ~~**Statement presentation (Phase 5.7).**~~ **Closed 2026-08-03.** It was both a
  mapping exercise and a reporting build, and it took one migration and one test.
  What it revealed instead is the item below it: statements without a period
  close are correct for one year and wrong for the second.
- **Filing artifacts (Phase 5.8).** Twelve working-paper tables, four form
  tables and the return tables are empty. Nothing in the repository indicates how
  much of the generation logic exists behind those empty tables, so any duration
  would be invention.
- **Approval routing (Phase 6.5).** An engine that has never executed once
  carries unknown defect risk. The first run finds what review cannot.

Stating "~4 months" while those three are open would repeat the mistake this plan
was written to stop. **The next honest estimate becomes possible once Phase 5.7
and Phase 5.8 are scoped against the code.** That scoping can run in parallel
with Phase 4, which is itself estimable and unblocked.

What has *not* changed: Phases 1–3 are done or nearly done, and the ordering
below is unaffected. Deliberately front-loaded — after Phase 2 the product is
recoverable, which is the difference between a setback and a catastrophe.

---

## The constraints that gate everything

| # | Constraint | Blocks | Phase |
|---|---|---|---|
| 1 | ~~Receiving adds stock with no journal~~ | — | ✅ closed |
| 2 | ~~No schedule, no offsite path~~ Both built and proven; a durable destination and escrowed passphrase remain owner actions | Every module's production readiness | 2 |
| 3 | ~~No opening balances~~ Local capability complete; real cut-over proof open | Pilot onboarding acceptance | ✅ local / 3 |
| 4 | ~~No Tax Engine calculator~~ **CLOSED 2026-08-03 (PAD-001).** One calculator, eleven callers migrated. Percentage tax still calculated nowhere | Percentage-tax companies only | ✅ / 5 |
| 5 | ~~No financial statement presentation~~ **CLOSED 2026-08-03.** All four statements produced from governed configuration (test `121`). **Successor risk: no period close** — profit is never rolled into retained earnings, so a second fiscal year misstates equity | A pilot accountant signing a second year | ✅ / Backlog 18d |
| 6 | No filing artifacts — nothing has ever been filed | Statutory filing; a VAT-registered pilot client | 5.8 |

---

## How to tell if the plan is working

Three honest measures. All others mislead.

| Measure | 2026-08-03 | Pilot target |
|---|---:|---:|
| Exercised posting entry points | **14 of 24** | 18 of 24 |
| Critical reconciliations evidenced | 1 of 9 | 9 of 9 |
| Canonical flows meeting the Pilot Bar | 0 of 2 | 2 of 2 |

Re-measured 2026-08-02 (the first row previously read "11 of 22" and was wrong on
both numbers) and again on 2026-08-03, when Cash Sale and Delivery Receipt
posting took it from 12 to 14.

Menu entries, route counts, page counts and documentation volume are **not**
progress measures. PXL learned that the hard way: **247 navigation leaf entries
resolve to 175 distinct routes, of which 145 are backed by real data** —
overstating delivered capability by roughly forty percent. Thirty routes are
finished screens over permanently empty tables and are now labelled "Not built"
in the navigation itself; a further 17 nav labels have no page at all.
