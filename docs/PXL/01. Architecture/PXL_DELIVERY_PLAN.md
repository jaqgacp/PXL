# PXL Delivery Plan — from here to a finished product

**Status:** Active — the complete end-to-end plan to finish PXL
**Authority:** Tier 1 Delivery Planning, subordinate to `PXL_PRODUCT_ARCHITECTURE.md`
**Owner / Domain:** Product
**Read When:** Asking "what is the whole plan?", "what phase are we in?", or "what do I build next?"
**Do Not Read For:** Current status (`AI/AI_STATE.md`), what PXL is (Product Architecture), or how we work (`00. Governance/PXL_HOW_WE_WORK.md`)
**Date:** 2026-08-04

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
| **Banking & Treasury** | **v2, and the highest-priority future capability.** Keep only Check Voucher in v1 (the Cash Disbursements Book needs it). Petty cash, bank reconciliation, transfers → v2. |
| **Fixed Assets** | **v2, second priority after Banking & Treasury**, except a minimal straight-line depreciation run if the pilot client holds assets. |
| **Accounting Schedules** | **v2.** Amortisation and revenue recognition. |
| **IA-5 / ECC chronology** | **Frozen.** Dormant, no consumers. Inventory reconciles without it. Do not resume without a real costing-replay requirement. |
| **Multi-currency** | **Deferred.** PHP only. |
| **Deferred surfaces** | Marked **Not built** in the navigation via `src/lib/deferredSurfaces.ts`. |

### Excluded from v1, from the pilot, and from production readiness

**Owner ruling, 2026-08-04.** The capabilities below are **future optional
products or future extensions**. They are *not* current PXL product scope, *not*
pilot scope, and **not production-readiness requirements**. None of them is a
production blocker, and no readiness statement anywhere in PXL may be held open
on their account. A pilot client that needs one of them is a reason to schedule
that capability deliberately — not a reason to call PXL unready.

| Excluded capability | Classification |
|---|---|
| **Final Withholding Tax**, including 1601FQ and 2306 | 🔮 Future extension. Its prototype screens/tables do not participate in current-product conformity, delivery or readiness. |
| **Payroll** | Separate future product. Never counted in PXL progress. |
| **Form 2316** | Future extension; belongs with Payroll. |
| **Quarterly and Annual Income Tax** | Future extension. Ten screens, none has ever held a row. |
| **MCIT / RCIT** | Future extension. |
| **NOLCO** | Future extension. |
| **OSD** | Future extension. |
| **Fringe Benefits Tax** | Future extension. |
| **Transfer Pricing** | Future extension. |
| **Consolidation Tax** | Future extension. |
| **Specialized-industry tax features** | Future extension. |

**Priority ordering for future work.** Banking & Treasury, then Fixed Assets,
rank **above every item in the exclusion table**. Neither is started, and this
ordering authorises no implementation — it records the sequence for when future
work is scheduled.

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
2,742 assertions; it stands at **123 files / 2,909** after Phase 5 items 3 and 7
and Backlog 18d and 18e.

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

- ~~**Percentage tax is calculated nowhere**~~ **CLOSED 2026-08-04 in Phase 5**,
  where it belonged: it needed a posting change and a document that calls it.
  Migration `20260804000001_percentage_tax.sql`, test `124`. The whole chain
  shipped together as this bullet required — see Phase 5 item 7a.
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
   (inclusive and exclusive), withholding by ATC (EWT and FWT share the
   mechanism) and, since 2026-08-04, **percentage tax**.
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
2026-08-03, and for percentage tax on 2026-08-04** (in Phase 5, because it needed
a posting change and a document that calls it). Filing capability is **not**
claimed here — that is Phase 5.8.

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
4. Evidence the remaining **critical reconciliations (currently 2 of 9)**. VAT and
   withholding already reconcile at zero variance — nearly free. Percentage tax
   was evidenced with item 7a.
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

   ✅ **Period close and year-end roll-forward — DONE 2026-08-03.** Migration
   `20260803000006_period_close_and_year_end_rollforward.sql`, test `122` (34
   assertions, self-provisioned company), Backlog item 18d. This completes the
   cycle the statements sit at the end of: transaction → posting → general
   ledger → trial balance → statements → period close → year-end close →
   retained earnings → next fiscal year.

   The finding that shaped the work: `fn_close_fiscal_year` existed and passed
   test `040`, but **could never have committed.** It posted the closing journal
   with a NULL `reference_doc_id` while `CLOSE` resolved against
   `journal_entries`, and the deferred constraint trigger
   `trg_journal_entry_source_integrity` rejects a NULL source at COMMIT. pgTAP
   rolls back, so a deferred constraint it never commits is a constraint it never
   checks. The fiscal year is now the closing journal's source document, which
   both fixes the defect and gives the close a drillable source. Test `122`
   asserts the source resolution directly so the gap cannot reopen silently, and
   the close was additionally proven by a **committed** fresh-data run.

   Around that: `fiscal_close_runs` is the governed register of every close and
   reopen, with partial unique indexes that make a duplicate live close
   structurally impossible — that is what makes the close idempotent rather than
   merely careful. `fn_close_accounting_period` enforces blocking readiness
   (period open, year open, every earlier period closed, ledger in balance) and
   `fn_reopen_accounting_period` reopens last-in-first-out against a required
   reason, so a posting can never land behind a closed period.
   `fn_close_accounting_quarter` is the same period close applied three times —
   PXL's fiscal calendar is monthly, so a quarter is not a second closing
   concept. `fn_reopen_fiscal_year` counter-posts the closing journal through the
   Accounting Kernel, classified `closing` so a re-close recomputes the same net
   income instead of doubling it; the original closing entry is never touched.
   The close opens the next fiscal year with its twelve periods and the same
   retained-earnings destination, so the roll-forward needs no operator step.
   `fiscal_periods.is_locked` and `fiscal_years.status` are now writable only
   from inside the four close functions, so the lock cannot be flipped around the
   engine — previously the "Close Year" button wrote `status = 'closed'` straight
   through PostgREST and posted nothing at all.

   ✅ **Comparative statements and basic notes — DONE 2026-08-03.** Migration
   `20260803000007_comparative_statements_and_notes.sql`, test `123` (33
   assertions, self-provisioned company), Backlog item 18e. All four statements
   carry current period, prior comparable period, amount variance and percentage
   variance, and every line — comparative or single-period — opens to the
   accounts behind it and on to the ledger.

   The prerequisite was a defect, not a feature. Period close, shipped hours
   earlier the same day, had silently broken two of the four statements for any
   **closed** year: the report read every posted line regardless of
   `entry_class`, so a closing journal's debit to revenue made the Statement of
   Comprehensive Income of a closed year read as **all zeroes**, and its credit
   to Retained Earnings moved the year's entire operating cash flow into
   **financing**. Measured on a fresh company: revenue 50,000 → 0.00; operating
   30,000 → 0.00 with financing 0.00 → 30,000. Nothing had ever closed a year
   before, and comparatives are the first feature that reads a closed year on
   purpose — the prior column would have been blank. Closing entries are now
   excluded from the income statement and the cash flow statement and included
   in the position and in changes in equity, where retained earnings is only
   correct because of them (Backlog 18j).

   The comparative is one contract, not a second engine:
   `fn_comparative_financial_statement_report` calls
   `fn_financial_statement_report` twice and joins on the governed line code,
   passing the **current** period end as the presentation date for the prior
   call so both columns are read on today's structure — a comparative shown on
   two different mappings compares nothing. `fn_resolve_comparative_period`
   resolves the prior period from the company's own fiscal calendar (a calendar
   year offset for consecutive twelve-month years, matching fiscal period
   numbers otherwise) and returns `available:false` with a readable reason
   rather than raising, because a company in its first year legitimately has no
   comparative. `fn_financial_statement_line_accounts` serves the drill-down and
   the supporting schedules from one query, signed through the shared
   `fn_fs_presentation_sign` so the accounts always sum to the line they were
   opened from. `fn_financial_statement_notes` returns company information,
   reporting period, basis of preparation, significant accounting policies and
   supporting schedules as rows, each naming its source and flagging whether it
   is configured — an unset policy reads as unset rather than as a default. The
   Comparative Financial Statements screen, which had been reading the ledger
   and totalling accounts in the browser, now computes nothing.

   **Still open before the statements are signature-ready:** note templates and
   company-authored narrative, statement-line-to-note cross-references, a
   signature block, and consolidation. Recorded in the Product Backlog as items
   18i and 18f.
7a. ✅ **Percentage tax — DONE 2026-08-04.** Migration
   `20260804000001_percentage_tax.sql`, test `124` (37 assertions,
   self-provisioned company), plus a committed three-sale run across two
   quarters. The last unblocked accounting gap, and the one that decided whether
   a non-VAT pilot client could operate at all: percentage tax was computed
   **nowhere**, and the PT Return screen summed VAT-*exempt* sales lines in the
   browser — VAT exemption is not the percentage-tax base, and a return computed
   on the client is not computed from the books.

   The whole chain shipped at once, as the item required: a per-line
   percentage-tax code → a `percentage_tax` component from `fn_calculate_tax` →
   DR `PERCENTAGE_TAX_EXPENSE` / CR `PERCENTAGE_TAX_PAYABLE` on **both** Sales
   Invoice and Cash Sale → one tax-ledger row per code, stamped with the
   tax-code version, its rate and the 2551Q ATC →
   `fn_percentage_tax_gl_reconciliation` at **0.00** variance → working paper →
   2551Q, which cannot be marked final or filed while it disagrees with the
   ledger.

   There is **one business-tax route, not a parallel one**:
   `fn_business_tax_codes_asof` is the single picker and
   `fn_resolve_business_tax_code` the single validator for both families, and
   the VAT half is delegated verbatim to `fn_resolve_vat_code`. Percentage tax
   is the **seller's** tax on its gross sales, so it never enters the
   receivable. `percentage_tax_codes` gained the version machinery `vat_codes`
   has, so a statutory rate change — Section 116 fell to 1% under CREATE and
   returned to 3% — is a succession, never an edit.

   Repaired with it: `fn_seed_company_percentage_tax_codes` labelled a code 3%
   while pointing it at the **12%** tax code, and attached a **withholding** ATC
   where no percentage-tax ATC existed. Nothing had ever posted from those rows.

   **Still open:** recognition is on the document rather than on collections for
   services, a credit memo does not reverse the tax, and nothing compels a
   PT-registered company to select its code. Product Backlog item 8b.
8. ◐ **BIR filing artifacts — ENGINE DONE 2026-08-04.** Migration
   `20260804000002_bir_filing_artifacts.sql`, test `125` (42 assertions,
   self-provisioned company). *Moved here from Phase 4 on 2026-08-02: a return is
   generated from posted, closed data, so this depends on items 1–7 above and
   cannot precede them.*

   The path is now one path, and there is only one of it:

   > Posted Transactions → Tax Engine → Tax Ledger → Reconciliation → Working Paper → Filing Artifact → Export → Filed Record

   **What was there before.** Three near-identical reconciliation functions —
   `fn_vat_gl_reconciliation`, `fn_wht_gl_reconciliation` and
   `fn_percentage_tax_gl_reconciliation` — differing only in which tax kinds they
   read, which control account they compared against, whether the `WHTREM`
   remittance journal was excluded and whether `reversed` journals counted. Four
   differences, three copies, and every future tax would have been a fourth. On
   top of that, **three more computations in JavaScript**: the 2550Q screen summed
   two review views with `reduce`, and so did the SLSP export and the SAWT
   alphalist. A figure computed on the client is not a figure computed from the
   books, and three clients drift three ways.

   **What replaced it.** `ref_tax_ledger_control` states, per tax kind, the
   governed account key, the normal balance, which journal statuses count and
   which reference document types are excluded — those four differences are now
   *configuration*. `fn_tax_ledger_gl_reconciliation` is **the** reconciliation;
   the three existing functions became one-line delegations that kept their
   signatures, their column shapes and their exact semantics, so no caller and no
   existing test changed. `ref_filing_artifact` + `ref_filing_artifact_kind`
   register what an artifact *is*: period basis, the tax kinds it consumes, the
   sign each kind carries in its net, and the dimensions it groups by.
   `fn_filing_working_paper` is **the** reader — one query, no dynamic SQL, in
   which the artifact's declared dimensions decide which grouping keys survive,
   so a summary return and a per-counterparty alphalist are the same code path
   with different configuration. `fn_generate_filing_artifact` persists a
   `filing_artifacts` header and its lines, and refuses to let one leave draft
   while it disagrees with the ledger it claims to summarise. **Registering the
   next form is a seed row, not a function.**

   **Registered in this increment:** 2550Q, 2551Q, 1601EQ, SLSP and SAWT; QAP was
   added on 2026-08-04 as the seed row this design promised it would be.

   Percentage tax, which had shipped hours earlier with its own generator, was
   **re-pointed at this engine rather than left beside it** — a second pipeline is
   exactly what this phase exists to prevent, including one of its own making.
   The 2550Q and 2551Q screens now display rather than compute:
   `fn_generate_vat_return` and `fn_generate_pt_return` project the artifact into
   the `vat_returns` and `pt_returns` rows those screens already read. On the
   2550Q the accountant states only two figures — input VAT carried over and VAT
   already paid — and states them *to the RPC*, so the net payable still has
   exactly one author. The VAT classification split the form needs (taxable,
   zero-rated, exempt) survives because an exempt or zero-rated line reaches the
   tax ledger with a base and a zero tax.

   ✅ **Filing Artifact Export — DONE 2026-08-04.** Migration
   `20260804000003_filing_artifact_export.sql`, test `126` (24 assertions,
   self-provisioned company), Backlog item 8d. The chain had ended one link short
   of usable: every figure tied to the General Ledger at 0.00 and there was still
   **no way to get a return out of PXL** to key into eFPS.

   The export is **another consumer of the artifact, not another computation
   engine**, and the test asserts exactly that: the exporter reads no
   transaction, tax-ledger row or review view, and **aggregates nothing** — no
   `SUM`, no `AVG` — because the artifact already stated every number. An export
   that re-sums is an export that can disagree. `ref_filing_export_column` holds
   each form's layout as configuration, and its `source_field` CHECK constraint
   makes a non-conforming layout **unwritable** rather than merely discouraged.
   One function serves every form and both formats, reusing the existing
   `fn_export_*` primitives; a second format costs seed rows, not a second
   exporter. The evidence row points at the artifact by its **own id**, and the
   downloaded bytes are read back from that row, so the file an accountant keys
   into eFPS is provably the file PXL recorded producing.

   ✅ **The 1601EQ and the QAP joined the layer — DONE 2026-08-04.** Migration
   `20260804000004_ewt_qap_filing_artifacts.sql`, test `127` (34 assertions,
   self-provisioned company), Backlog item 8e (i) and (iii).

   Two surfaces computed correctly and **recorded nothing**. The 1601EQ screen
   computed through the governed engine and then wrote `ewt_returns` by typed
   insert, so a return could be marked filed with no artifact behind it — no
   working paper, nothing to export. The QAP was aggregated in JavaScript from a
   review view that drops reversal counter-rows, so a voided withholding left the
   alphalist and the return it attaches to disagreeing, invisibly.

   `fn_generate_ewt_return` is the **third instance of the projection shape and
   added no engine**. Registering the QAP cost **a seed row and its tax kind**,
   which is the claim the registry has been making about itself since it shipped.
   Because the QAP and the 1601EQ now read the same ledger through the same
   reader, the alphalist adds up to the return **by construction** rather than by
   coincidence. Building it corrected a design error of its own: `remitted_prior`
   was drafted as a stated figure like the 2550Q's, but PXL-AUD-041 had already
   made it derived, so the projection reads `fn_compute_ewt_remitted_prior` and
   the screen's editable field is gone — the 1601EQ now carries **no stated figure
   at all**. The orphan `fn_qap_2307_reconciliation` was **resolved, not retired**:
   it reads the artifact working paper and is surfaced on the QAP screen. The
   withholding-agent gate was extended to key on what a snapshot *is* rather than
   on which table produced it, so migrating the screen did not walk around it.

   ✅ **The second compliance architecture is retired — DONE 2026-08-04.**
   Migrations `20260804000005` and `…06`, tests `128` (30 assertions), `129` (22)
   and `tests/compliance_architecture.test.ts`, Backlog item 8f stages 1–2.

   Twelve legacy `compliance_*` working-paper tables and six hand-keyed screens
   were the second architecture this phase exists to prevent — an accountant
   could key a schedule **no ledger backed**. The capability audit found their
   "Generate" button was a stub that said so in its own words, so their only real
   capability was the manual line itself. That capability was migrated first, as
   the governed **Reconciling Item**: manual, audited, frozen once the artifact
   leaves draft, excluded from every total **structurally** — its amount lives in
   a column no computation reads — and visible as a note in CSV but never in a
   DAT file the Bureau ingests. Only then were the eight VAT/EWT/1601EQ/PT tables
   dropped, the last legacy writer removed from `fn_generate_pt_return`, the four
   screens replaced by **one** governed working-paper surface, and
   `fn_snapshot_wht_export` retired — which revealed that the legacy export had
   been executable by **`anon`**, moving a census number that had been fixed since
   test `102` was written.

   Two things were found and fixed that were not on anyone's list: the filing
   artifact had **no role gate** on final/filed while every other compliance
   record has had one since 2026-07-01, and the governed working paper needed an
   accounting-trace drill-down so the per-document detail of the retired screens
   survives the move to grouped schedules.

   The verification is **executable**, not prose: test `129` asserts that no
   function reads a retired working paper, that exactly one function writes a
   filing artifact, and that every export snapshot of a registered form is keyed
   to the artifact; the TypeScript half asserts no routed screen reaches a
   retired table.

   **Current-scope boundary.** The governed architecture is complete for every
   implemented compliance family. The four FWT/1601FQ prototype tables and two
   screens are a 🔮 future extension; they are not an exception, gap or readiness
   dependency for the current product.

   **Why this item remains ◐. Nothing has ever been filed from PXL.** A `filed`
   status records the accountant's own submission; PXL does not transmit to the
   Bureau. The architecture migration itself is complete: the **SLSP screen moved
   onto the quarterly artifact on 2026-08-05** (Backlog 8e ii) and the 2551Q
   gained its export control the same day (Backlog 24), so every current-product
   compliance surface is on the layer and every registered form reaches
   generate → final → export. What remains for this item is operational, not
   architectural: a real accountant filing a real quarter. Backlog 8c still
   carries the VAT carry-forward and exempt/zero-rated purchase split.
   **Check Voucher** — the one Banking document kept in v1 because the Cash
   Disbursements Book needs it — is still unassigned to a phase.

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
   honest: 26 deferred routes and 17 navigation labels with no page (PAD-012).

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

Banking & Treasury · full Fixed Assets lifecycle · Accounting Schedules · CAS
accreditation · multi-currency · IA-5 resumption only if costing replay becomes a
real complaint. Excluded future extensions do not enter this delivery phase
without a Product Architecture Amendment.

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
| Phase 5 — flows, then statements, then filing | statements ✅ 2026-08-03; filing engine and export ✅ 2026-08-04; **the two canonical flows remain the open item** | **Low** — see below |
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
- ~~**Filing artifacts (Phase 5.8).**~~ **Engine and export closed 2026-08-04.**
  Six artifacts use one generator, working paper, reconciliation and exporter;
  the remaining in-scope work is the SLSP screen/evidence migration and real
  operational filing proof.
- **Approval routing (Phase 6.5).** An engine that has never executed once
  carries unknown defect risk. The first run finds what review cannot.

**Two of the three closed on 2026-08-03 and 2026-08-04**, and both took a single
migration and a single fresh-data test — far less than the withheld estimate
implied. Approval routing remains genuinely unestimated because an engine that
has never executed carries unknown defect risk.

The remaining distance to pilot is therefore the two canonical flows meeting the
Pilot Bar (0 of 2 today), the SLSP screen migration, approval routing's first
run, and the operational items that are owner actions rather than engineering:
a hosted deploy, a durable backup destination and an escrowed passphrase. **No
excluded future extension (PAD-015) sits on this path.**

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
| 4 | ~~No Tax Engine calculator~~ **CLOSED 2026-08-03 (PAD-001).** One calculator, eleven callers migrated; **percentage tax closed 2026-08-04** (test `124`) | — | ✅ |
| 5 | ~~No financial statement presentation~~ **CLOSED 2026-08-03.** All four statements produced from governed configuration (test `121`), the accounting cycle closes into retained earnings (test `122`), and the statements carry a comparative period and basic notes (test `123`). **Successor risk: the notes are not signature-ready** — no company narrative, note templates, line-to-note cross-references or signature block | A pilot accountant signing a statement | ✅ / Backlog 18i |
| 6 | ~~No filing artifacts~~ **ENGINE CLOSED 2026-08-04.** Six registered artifacts generate and export through the locked pipeline at 0.00 reconciliation variance. Open: SLSP screen/evidence migration and a real accountant-operated filing; PXL itself transmits nothing. | Pilot filing evidence | 5.8 / 6 |

---

## How to tell if the plan is working

Three honest measures. All others mislead.

| Measure | 2026-08-04 | Pilot target |
|---|---:|---:|
| Exercised posting entry points | **15 of 24** | 18 of 24 |
| Critical reconciliations evidenced | **3 of 9** | 9 of 9 |
| Canonical flows meeting the Pilot Bar | 0 of 2 | 2 of 2 |

The reconciliation row moved from 1 to 3 on 2026-08-04: inventory to its control
account (`111`, `120`), percentage tax to the GL (`124`), and VAT and withholding
through the one filing reconciliation (`125`, `127`). All three measure 0.00.

Re-measured 2026-08-02 (the first row previously read "11 of 22" and was wrong on
both numbers) and again on 2026-08-03, when Cash Sale and Delivery Receipt
posting took it from 12 to 14 and the year-end close — which until that day was
registered, tested and incapable of committing — took it to 15.

Menu entries, route counts, page counts and documentation volume are **not**
progress measures. PXL learned that the hard way: **247 navigation leaf entries
resolve to 175 distinct routes, of which 145 are backed by real data** —
overstating delivered capability by roughly forty percent. Thirty routes are
finished screens over permanently empty tables and are now labelled "Not built"
in the navigation itself; a further 17 nav labels have no page at all.
