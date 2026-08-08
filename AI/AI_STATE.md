# PXL AI State

**Current Date:** 2026-08-08
**Current Branch:** `main`
**Working Tree:** Percentage tax (Backlog 8), the **filing artifact engine**
(Phase 5.8), its **export** (8d), the **1601EQ/QAP** migration (8e i, iii),
**8f**, the **SLSP** migration (8e ii), **governed tax-code maintenance** (10),
**Delivery Receipt cancellation** (18c), the **Sales Invoice delivered-stock
guard** (18b safety slice), **Receiving Report cancellation**, and exact
**PO→RR→VB quantity match** (18k), plus production **Weighted Average, FIFO and
Specific Identification** costing (18m), are complete locally with fresh,
focused and committed-lifecycle evidence. The **full local Sales Document
Conversion Engine** (18b) now governs QT→SO→DR/SI quantity, correction, trace
and exact cost. The Phase C checkpoint gate is green through
regression, canonical, lifecycle, frontend and build proof. A non-VAT Section 116 taxpayer runs the chain: line code
→ component → liability posting → tax ledger → GL reconciliation at 0.00 →
working paper → **2551Q**. Every registered artifact — 2550Q, 2551Q, 1601EQ,
SLSP, SAWT, **QAP** — comes from **one** generator over **one** working paper and
**one** reconciliation, and is **exported** by one consumer. **Every
current-product compliance surface is on the layer and every registered form
reaches generate → final → export** (24 closed 2026-08-05). A statutory rate
change is now a **succession the product can reach** (10, 2026-08-07).
**Nothing has been filed with the Bureau.**
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

**98 Retested Passed / 0 In Progress / 0 Open (98 total).** Complete; that
certifies no module or engine and confers no readiness. **074 through 078 were
opened and closed on 2026-08-07/08** — a broken Delivery Receipt posting path, a
void that refused every draft, and a **cash sale whose void left its collection
posted**, followed by the missing Receiving Report correction and a receipt line
that could borrow the wrong Purchase Order relationship. The committed-step
lanes cover the transaction-boundary claims; finding closure is not certification.

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
  with no page. **230** nav leaf entries → **175** distinct routes; the "on real
  data" share needs a re-census (Backlog 25, documentation only).

- **Transaction workspaces:** **37** entries; Sales Invoice the sole
  source-reviewed slice. UI rollout is not completion:
  business qualification remains source-gated.

- **Tests:** 137 pgTAP files / 3,303 assertions plus 93 frontend source tests;
  regression, canonical, build and lint lanes pass. **Five committed-step
  lanes** cover general posting, Delivery Receipt, purchasing, inventory
  costing and Sales conversion lifecycles; pgTAP alone cannot see guards with a
  `same_txn` escape.
- **Backup/restore:** **Mechanised; never operated over anything real.** Weekly
  in CI. Blocker 5.

## Known Blockers and Non-Assumptions

1. No Sales or Purchasing source-to-statements-to-tax workflow meets the Product
   Definition of Done.
2. Every current inventory writer delegates to one production costing authority.
   Weighted Average, FIFO and Specific Identification preserve historical cost,
   layer/identity lineage and ordered correction; exact quantity matching is
   enforced (`134`–`137` plus committed lifecycles). Sales document conversion
   is governed and quantity-safe; purchasing price-variance policy remains open.
3. **Nothing has ever been filed with the Bureau.** Six artifacts — 2550Q,
   2551Q, 1601EQ, SLSP, SAWT, QAP — generate from the posted ledger, reconcile to
   the GL and refuse to leave draft while they disagree with it; `filed` records
   the accountant's own submission and PXL transmits nothing.
   Two hand-keyed FWT prototype screens remain outside the current product; they
   carry no architecture, pilot or readiness weight (22). Percentage tax is recognised on the document, not on collections; a
   credit memo does not reverse it; nothing compels a PT-registered company to
   select its code (8b). Tax-code succession is now governed (10), but
   **deprecation is not** (10b); no governed UI for statement
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

**2026-08-05:** SLSP (8e ii) and the 2551Q export (24) — **both needed no
migration**; each was a missing consumer of what already existed.

**2026-08-07: governed tax-code maintenance** (`…01`, `130`,
`tax_reference_maintenance.test.ts`, 10). Two premises in that Backlog row were
wrong. Its named gate `fn_can_maintain_tax_reference` was **dropped** by
`20260721000002` — authority is `fn_is_bir_config_maintainer()`,
**maintainer-only, closed by default**, which the screen now asks before offering
anything. And succession was **unreachable**: no upsert took a `supersedes`
argument and RLS denies direct INSERT, so the only reachable outcome was an
**orphan successor**. `p_supersedes_id` joins the three upserts; `fn_*_succeed`
closes a window and opens its successor **in one transaction**, delegating both
writes to the upsert. `vat_codes` gained the version-rules trigger the other two
had. ATC maintenance existed nowhere. **Deprecation is still not governed** (10b).

**2026-08-08: the cross-transaction lane, and what it found** (`…03`, `132`,
`verify_posting_lifecycles.mjs`). Seven documents walked save → commit → post →
commit → correct. On its first complete run it found **076**: a Cash Sale is one
business event recorded as two documents, and voiding withdrew only the invoice
half — leaving its Official Receipt **posted**, cash overstated by the whole sale
and a phantom AR credit, with the trial balance still balancing.
`fn_void_cash_sale` is now the named authority and `fn_void_sales_invoice`
**routes** cash sales into it, so the general invoice surface cannot bypass it
and no screen needs to know the difference. Two private helpers were extracted so
each rule is stated once. Closed with it: `fn_bounce_receipt` and
`fn_void_sales_invoice` had been **`anon`-executable** by default grant.

**2026-08-07: Delivery Receipt cancellation** (`…02`, `131`,
`delivery_receipt_cancellation.test.ts`, 18c). `fn_void_delivery_receipt` reverses
the delivery journal through the shared reversal and restocks through the shared
costing path; an invoice claiming the delivery — **draft included** — must be
voided first. Building it exposed **two defects, both invisible to pgTAP**:
`delivery_receipts` became a posting document on 2026-08-03 without its
2026-07-04 guards being widened, so **posting was refused whenever the delivery
was marked delivered in an earlier transaction — no delivery could post from the
screen at all** (074); and `fn_capture_cas_document_void` erased the reason it had
resolved when no reversal journal existed, so **no draft could be voided** across
twelve CAS families (075). pgTAP runs in one transaction, where the guards'
`same_txn` escape applies. **`npm run verify:delivery-receipt-lifecycle` is the
standing cross-transaction proof, and this class of defect needs one.**

**2026-08-08: Sales and Purchasing integrity** (`20260808000001`–`000003`,
`133`/`134`). Approval and posting refuse an unlinked Sales Invoice stock line
when a live delivery should be billed; the linked path still clears Goods
Delivered Not Invoiced, while never-delivered goods and services remain valid.
This is a safety guard, **not** the Document Conversion Engine. Receiving Report
cancellation is reachable from the screen and, after live bills and downstream
allocations are corrected, removes the exact historical receipt under any of the
three costing methods, reverses the journal, nets GRNI to zero and reopens the PO.
PO-line receipt quantity and receipt-item bill quantity now fail closed at the
current relationship grain; no-`rr_id` bills remain allowed. PXL-AUD-077/078
record the reversal and cross-order line-integrity gaps. Price variance is
deliberately separate (18l). `verify:purchasing-lifecycle` proves 36/36 across
commits through two receipts, two bills, payment and ordered correction.

**2026-08-08: Sales Document Conversion** (`20260808000007`, `138`,
`verify:sales-conversion-lifecycle`). One authority governs QT→SO, SO→DR/SI and
DR→SI with partial/concurrent quantity, correction and trace. Exact cost
snapshots preserve split-invoice COGS and clearing. The 33-check lifecycle covers
all three costing methods, concurrency, settlement and 0.00 TB. It is **M5
locally, not certified, hosted or browser/UAT-proven**.

**2026-08-08: production Inventory Costing** (`20260808000004`–`000006`,
`135`–`137`). One private authority serves Weighted Average, FIFO and Specific
Identification; exact allocations/serial-or-lot identity drive cost, reversal,
return and transfer while the Posting Engine remains the only GL writer. Method
changes fail closed after activity. Real Goods Issue, adjustment, transfer,
count, customer/supplier return and sales/purchasing paths are exercised. The
committed lifecycle proves WAC 600, FIFO 1,280, selected serial 120, exact void
and a concurrent one-serial race. All three are **built, reachable, exercised
and proven locally** for the intended current lifecycle. This is not Inventory
certification, hosted parity or pilot readiness; IA-5/ECC remains frozen.

**8f shipped** (`…05`/`…06`, `128`, `129`): the second compliance architecture
is retired; governed Reconciling Items preserve manual capability without
entering totals, one surface replaced four, and eight legacy tables were retired.

Phase 3 is implemented locally and unchanged (PAD-002, PAD-003). IA-5/ECC is
**frozen** at zero consumers (`docs/PXL/archive/ia5-ecc-frozen/`). Posting P5.2
remains fully enforced; the Accounting Kernel is a component inside it, not an
engine.

## Hosted and UX Status

Hosted project `bskjkogijpbhukjkagfj` is at `20260716000005`; **78 local
migrations pending**, no destructive DDL. The deploy is **rehearsed, not
performed, and deliberately deferred** — nothing consumes it and CI deploys
nothing. Credentials absent by design (PXL-AUD-055). Deferred-route labelling is
governed by `deferredSurfaces.ts` (PAD-012).

## Last Verified Commands

- `npm run test:db:fresh` and `test:db:regression` — **PASS**, 137 files / 3,303
  assertions; the regression lane resets the schema first, so it is
  order-independent.
- `npm run test:canonical` — **PASS**, 30 files / 751 assertions.
- Focused conversion lane — **PASS**, `102`, `120` and `138` are 144
  assertions; conversion test `138` contributes 42 and the security census owner
  `102` passes 78/78.
- `npm run verify:delivery-receipt-lifecycle` — **PASS**, five committed
  transactions; post and cancel both succeed across commit boundaries.
- `npm run verify:posting-lifecycles` — **PASS, 42/42**: Sales Invoice, Cash
  Sale, Official Receipt, Credit Memo, Receiving Report, Vendor Bill and Payment
  Voucher, each save → commit → post → commit → correct. It found 076 on its
  first complete run.
- `npm run verify:purchasing-lifecycle` — **PASS, 36/36** across committed PO,
  two receipts, two bills, payment and ordered correction; stock/value,
  Inventory, GRNI, AP, cash, input VAT and tax net to zero; TB balances.
- `npm run verify:inventory-costing-lifecycle` — **PASS, 28/28**: committed WAC
  600, FIFO 1,280, selected serial 120, exact correction, reconciliation and a
  two-session same-serial race with exactly one winner.
- `npm run verify:sales-conversion-lifecycle` — **PASS, 33/33**: committed
  QT→SO→DR→SI→OR, partial/multiple conversion, draft reversal, all three costing
  methods, a two-session final-unit race, exact COGS/clearing/tax/AR and 0.00 TB.
- **Committed** fresh-data percentage-tax run (never the demo seed): ledger-to-GL
  variance **0.00**, trial balance **0.00**, Q1 filed with its working paper.
- `npm run test:frontend` — **PASS**, 93 tests.
- `npm run build`, `npm run lint`, `git diff --check` — **PASS**; one
  pre-existing lint warning in `tests/backup_recovery.test.ts`.
- `npm run docs:check` — **PASS**; all 137 pgTAP files indexed.
- `npm run deploy:rehearse` — **PASS**; 78 pending migrations apply to the
  deployed-through baseline and match fresh structure; measured schema window
  26 seconds. No hosted operation occurred.
- `npm run backup:operate` — **PASS** (2026-08-02); replica restored
  independently, 0 mismatches.
- Inventory-to-control **0.00** in all three stock-holding companies; trial
  balance **0.00** in all five.

## Recommended Next Task

**PHASE 2 RECOVERABILITY IS ENGINEERING-COMPLETE; the rest is owner action** (PAD-007).

**Phase 5 items 3, 7 and 8 and Backlog 8, 8d, 8e, 8f, 10, 18c, 18d, 18e and 18k
are complete for current product scope; nothing has been filed with the Bureau.**
**The governed compliance architecture is complete for every current-product
family** (test `129`, `compliance_architecture.test.ts`); FWT/1601FQ is a future
extension, not an architecture gap.

The recommended next major package is **Purchasing Price Variance and AP Control
Closure**: decide Backlog 18l's accounting/approval policy, implement it through
the existing PO→RR→VB authority and prove AP/GRNI/Inventory/GL closure. It ranks
ahead of a new module because price-different pilot invoices remain a real risk.
**Banking & Treasury** is the next net-new capability; hosted/browser proof is
the leading release-hardening package.

**Compliance standard (owner, 2026-08-04):** Posted Transactions → Tax Engine →
Tax Ledger → Reconciliation → Working Paper → Filing Artifact → Export → Filed
Record. **The Filing Artifact is the system of record**; one implementation per
stage, extra faces are delegations, replacement is ordered, no orphans. **Review
Stage reads source data by design; Filing Stage is bound to the artifact**
(settled 2026-08-05). Full rule in the Backlog and Rules Matrix.

Material current-product Backlog: 8b, 8c, 10b, 11, 18, 18f, 18g, 18h,
18i, 18l, 19. **Not the full register** — the Backlog is, and also holds 9, 12, 13, 17
and the documentation-only 20, 21, 23, 25. Then Banking & Treasury, then Fixed
Assets. Excluded extensions, including 22, carry no readiness weight.

Deploy rehearsal is current; hosted deploy still requires owner approval. **No open findings remain**; do not resume IA-5.

## Stop Conditions

No Posting/Kernel change; no production inventory source activation; no IA-6;
preserve IA-5 dormancy; a non-zero `inventory_events` count is a governance stop;
no hosted operation without approval; no product-scope change without a Product
Architecture Amendment. WP-5…WP-9 unauthorised. Governance-only commits require
an explicit owner-directed finalization or Product Architecture Amendment.
