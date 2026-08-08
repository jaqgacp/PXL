# PXL Business Process Blueprint

**Status:** Active functional reference
**Authority:** Tier 1 Business Process Reference — functional authority for how business processes run inside PXL; subordinate to `01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` for product identity and scope, and to `AI/AI_STATE.md` for current status
**Last Reviewed:** 2026-08-07 at creation
**Applies To:** Every business domain in the current product
**Read When:** Understanding, testing, implementing, training on, or specifying a business process end to end
**Do Not Read For:** Product scope decisions, architecture rulings, current status, schema detail, UI layout, or implementation guidance

---

## 0. How to read this document

### 0.1 What this is

This is the **functional business bible** of PXL: how a real Philippine SME
operates inside the product, from first customer contact to a filed BIR return.
It describes **processes**, not screens, tables or code.

It is the intended primary reference for developers, testers, product owners,
client implementers, user manuals, feature definition and training material.

### 0.2 What this is not

It is **not** an architecture document, a UI specification, a database
specification, or an implementation guide. Where those subjects arise, this
document routes to their authority rather than restating them:

| Subject | Authority |
| --- | --- |
| What PXL is; scope; module and engine taxonomy | `01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` |
| When work ships and in what order | `01. Architecture/PXL_DELIVERY_PLAN.md` |
| Why the order is what it is | `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` |
| Where we are today — all status facts | `AI/AI_STATE.md` |
| Accounting rules and the posting matrix | `02. Accounting Core/PXL_ACCOUNTING_RULES.md`, `PXL_ACCOUNTING_RULES_MATRIX.md` |
| Posting Engine mechanics | `02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md` |
| Transaction lifecycle and field sourcing | `04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`, `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` |
| Official defects | `PXL_END_TO_END_AUDIT_FINDINGS.md` |
| Approved future work | `00. Governance/PXL_PRODUCT_BACKLOG.md` |

**Single-source rule.** This document carries no finding counts, test counts,
certification standing or reconciliation counts. Those live in `AI/AI_STATE.md`
and nowhere else. Where a process step's readiness is stated here, it is stated
as a **process status word** (below), never as a metric that will drift.

### 0.3 Status vocabulary

Every step, exception and capability in this document carries exactly one:

| Status | Meaning |
| --- | --- |
| **Implemented** | The process runs today against the current repository, with governed backend behaviour and a route a user can reach. |
| **Planned** | Approved and specified work that has not been built. Appears in the Delivery Plan or the Product Backlog. |
| **Future** | A recognised business need with no approved delivery slot. Includes the ranked future priorities (Banking & Treasury, then Fixed Assets). |
| **Excluded** | Outside the current product, the pilot and production readiness by owner ruling PAD-015. Carries no readiness weight and is never a blocker. |

**Implemented does not mean certified.** PXL has certified engines and zero
certified modules; "Implemented" here means the process exists and behaves as
described, not that its module has passed a certification scope. No statement in
this document is a production-readiness claim.

### 0.4 The one sentence the whole document depends on

> **Nothing has ever been filed with the Bureau.** Six statutory artifacts
> generate from the posted ledger and reconcile to the General Ledger, and a
> `filed` record captures the accountant's own submission. PXL transmits nothing
> to the BIR.

### 0.5 Globally excluded scope

The following are **future product extensions only** (owner ruling PAD-015).
They are not current product scope, not pilot scope, and not production-readiness
requirements. **No readiness statement in PXL may be held open on their account.**
They are listed once here and never treated as blockers anywhere below:

Final Withholding Tax (including 1601FQ and 2306) · Payroll · Form 2316 ·
Quarterly and Annual Income Tax · MCIT · RCIT · NOLCO · OSD · Fringe Benefits
Tax · Transfer Pricing · Consolidation Tax · Specialized-industry tax features ·
Multi-currency and FX revaluation · any AI or assistant integration.

The `Employees` master is a *lite* BIR identifier master for document attribution
and department reporting. It is **not** a payroll foundation.

---

# 1. Customer-to-Cash (Sales & Receivables)

## Purpose

**Why the module exists.** A Philippine SME must be able to promise goods to a
customer, deliver them, bill them under a BIR-registered document number, collect
against that bill, and have every one of those acts land in the General Ledger
and the tax ledger exactly once.

**Business objective.** Convert a customer commitment into recognised revenue,
a collected receivable, and correct output VAT or percentage tax — with the cost
of the goods leaving inventory exactly once and reaching cost of sales in the
same period as the revenue it earned.

**Business owner.** Sales Manager for the commercial steps; Accounting Manager
for revenue recognition, receivable position and tax treatment. The two owners
meet at the Sales Invoice, which is where a commercial act becomes an accounting
act.

**Users involved.** Sales representative (quotation, order) · Warehouse or
logistics personnel (delivery) · Billing or accounting clerk (invoice, credit
memo) · Cashier or collections clerk (official receipt) · Accountant (void,
correction, period close) · Compliance officer (output VAT and percentage-tax
review).

**Departments involved.** Sales · Warehouse / Logistics · Accounting / Finance ·
Compliance.

## End-to-End Flow

```
                    Customer Inquiry  (Future — no capture)
                              ↓
                       Sales Quotation  (Implemented, non-posting)
                              ↓
                        Sales Order  (Implemented, non-posting)
                              ↓
                    Stock Reservation  (Future — not built)
                              ↓
        ┌─────────────────────┴──────────────────────┐
        ↓                                            ↓
  Delivery Receipt  (Implemented)              Cash Sale  (Implemented)
  stock leaves; cost parks in                  sells, delivers and collects
  Goods Delivered Not Invoiced                 in one posted act
        ↓                                            ↓
  ┌─────┴──────┐                                     │
  ↓            ↓                                     │
Bill This    Delivery Cancellation                   │
Delivery     (Implemented — reverses the             │
  ↓           journal, restocks the goods)           │
  ↓                                                  │
Sales Invoice  (Implemented)  ←──────────────────────┘
revenue + output VAT / percentage tax; COGS
        ↓
   ┌────┴─────────────────┬──────────────────────┐
   ↓                      ↓                      ↓
Invoice Void        Credit Memo            Official Receipt
(Implemented —      (Implemented)          (Implemented)
reverses journal,        ↓                      ↓
tax and stock)     Customer Return        Receipt Cancellation
                   (Implemented —         / Bounced Receipt
                   credit memo with a     (Implemented)
                   warehouse; restocks)
        ↓                      ↓                      ↓
        └──────────────────────┴──────────────────────┘
                              ↓
                    AR Position and Collections
                    (Implemented — ageing, ledger, monitoring)
                              ↓
                    AR Write-off  (Future — not built)
                              ↓
                        Period Close  (Implemented)
                              ↓
                    Financial Statements  (Implemented)
                              ↓
              Tax Ledger → Working Paper → Filing Artifact
                              ↓
                        BIR Filing  (see Module 5)
```

The flow is not a single happy path. Three correction branches are first-class
and governed: **Delivery Cancellation** before billing, **Invoice Void** after
posting, and **Credit Memo / Customer Return** after the customer has the goods.
Their ordering is a business rule, not a preference — see §1.4.

## Business Process Matrix

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Customer Inquiry | Capture demand before a quote | Sales rep | — | — | — | No | None | None | None | None | — | — | — | **Future** |
| Sales Quotation | Offer price and terms without commitment | Sales rep | Inquiry | Quotation | Customer, date, at least one line | Configurable (draft → pending → approved) | None | None | None | Sales pipeline | Sales Order | Reject or expire | Header/line change log | **Implemented** |
| Sales Order | Record the customer's commitment | Sales rep | Quotation | Sales Order | Customer, items, branch; approval state | Yes (pending → approved / rejected) | None — no reservation | None | None | Order backlog, fulfilment state | Quotation, Delivery Receipt | Reject; cancel before fulfilment | Header/line change log | **Implemented** |
| Stock Reservation | Ring-fence stock for an order | Warehouse | Sales Order | — | — | — | Would reduce available-to-promise | None | None | Availability | Sales Order | — | — | **Future** |
| Delivery Receipt | Record goods physically leaving | Warehouse | Sales Order | Delivery Receipt | Warehouse and inventory account per stockable line; sufficient stock; open fiscal period | No | **Relieves stock** at governed cost | DR Goods Delivered Not Invoiced / CR Inventory | None — a delivery is not a taxable event | Stock balances, movements, GL, trial balance | Sales Order, Sales Invoice | **Delivery Cancellation** | Posting event, journal, audit log | **Implemented** |
| Delivery Cancellation | Correct a mis-shipment | Warehouse supervisor / Accountant | Delivery Receipt | Reversal journal, restock transaction | Reason code required; refused while any non-cancelled invoice bills it | No (reason mandatory) | **Restocks** at the cost that left | Reverses the delivery journal | None | Stock balances, movements, GL | Delivery Receipt, Sales Invoice | Terminal — cannot be undone | Posting event `VOIDED`, CAS void evidence | **Implemented** |
| Sales Invoice | Bill the customer; recognise revenue | Billing clerk | Sales Order, Delivery Receipt | Sales Invoice | Customer, lines, tax codes, revenue accounts, open period, number series | Yes (draft → approved → posted) | Relieves stock **only if not already delivered**; otherwise consumes the clearing balance | DR AR / CR Revenue / CR Output VAT or Percentage Tax; DR COGS / CR Inventory or clearing | Output VAT **or** percentage tax per line code; writes the tax ledger | Customer ledger, AR ageing, sales register, GL, trial balance, statements, tax ledger | Delivery Receipt, Official Receipt, Credit Memo | **Invoice Void**, then re-issue | Posting event, journal, tax detail, CAS issuance | **Implemented** |
| Invoice Void | Withdraw a wrong invoice | Accountant | Sales Invoice | Reversal journal, restock transaction | Reason code required; not already cancelled | No (reason mandatory) | Restores stock the invoice relieved | Reverses the invoice journal | Reverses the tax ledger entries | All of the above | Sales Invoice | Terminal | Posting event `VOIDED`, CAS void evidence | **Implemented** |
| Cash Sale | Sell, deliver and collect at once | Cashier | — | Cash Sale (CS series) | As Sales Invoice, plus a cash account | Yes | Relieves stock | DR Cash / CR Revenue / CR Output VAT or Percentage Tax; DR COGS / CR Inventory | Output VAT or percentage tax, recognised on the document | As Sales Invoice, plus cash position | Official Receipt (not required) | Void | Posting event, journal, tax detail | **Implemented** |
| Official Receipt | Record collection and CWT withheld by the customer | Cashier / Collections | Sales Invoice | Official Receipt | Posted invoice(s) to apply against; payment mode; cash account | No | None | DR Cash / DR Creditable Withholding Tax Receivable / CR AR | Records **CWT receivable** in the tax ledger | Customer ledger, AR ageing, collection monitoring, cash, GL, SAWT source | Sales Invoice, Form 2307 received | Receipt Cancellation | Posting event, journal, tax detail, CAS issuance | **Implemented** |
| Receipt Cancellation / Bounce | Reverse a collection that failed | Cashier / Accountant | Official Receipt | Reversal journal | Reason required; terminal status | No (reason mandatory) | None | Reverses the receipt journal; restores the receivable | Reverses CWT recorded | Customer ledger, AR ageing, cash, GL | Official Receipt | Terminal | CAS void evidence, posting event | **Implemented** |
| Credit Memo | Reduce a receivable for price, error or allowance | Accounting clerk | Sales Invoice | Credit Memo | Customer; source invoice optional; VAT code | Yes (draft → approved → applied) | None when no warehouse is named | DR Revenue / DR Output VAT / CR AR | Reduces output VAT | Customer ledger, AR ageing, sales register, GL, tax ledger | Sales Invoice, Customer Return | Cancel while unapplied | Posting event, journal, tax detail | **Implemented** |
| Customer Return | Take goods back and credit the customer | Warehouse + Accounting | Delivery Receipt, Sales Invoice | Credit Memo carrying a warehouse | As Credit Memo, plus warehouse per returned line | Yes | **Restocks** the returned goods at cost | Credit Memo entries **plus** DR Inventory / CR COGS | Reduces output VAT | All Credit Memo reports, plus stock balances and movements | Credit Memo, Delivery Receipt | Cancel while unapplied | Posting event, journal, inventory transaction | **Implemented** |
| Collections monitoring | See what is owed and overdue | Collections / Accountant | Posted invoices and receipts | — (read-only) | — | No | None | None | None | AR ageing, customer ledger, payment monitoring | — | — | Read-only views | **Implemented** |
| AR Write-off | Derecognise an uncollectible receivable | Accountant | Sales Invoice | — | — | Would require approval | None | Would be DR Bad Debts / CR AR | Depends on statutory treatment | Customer ledger, AR ageing, GL | Sales Invoice | — | — | **Future** |
| Period Close | Freeze a period and roll profit to equity | Accountant | All posted documents | Closing journal | Period unlocked; readiness checks | Yes | None | Rolls revenue and expense to retained earnings at year end | None | GL, trial balance, statements | — | Governed reopen | Posting event, journal | **Implemented** |

## Detailed Step Discussion

### 1.1 Sales Quotation

**Purpose.** Offer price and terms with no obligation and no accounting effect.

**Business rules.** A quotation is a commercial artifact. It carries a document
number from the Number Series Engine, a customer, a date and at least one line.
It moves through `draft → pending → approved`, and may be `rejected` or
`expired`.

**Validations.** Customer, quotation date and at least one line with a
description are required. Lines are editable only while the quotation is in an
editable status.

**Posting, tax, inventory, GL, subledger behaviour.** None. A quotation is
outside the Posting Engine entirely.

**Relationship behaviour.** A quotation is the intended parent of a Sales Order.
**The carry-forward is not automated** — the Document Conversion Engine is not
started, so quantities are not copied and nothing prevents quoting the same line
twice. See §1.9.

**Cancelled / reversed / corrected.** Rejection and expiry are status changes.
There is nothing to reverse.

**Reports changed.** Sales pipeline views only.

### 1.2 Sales Order

**Purpose.** Record what the customer has committed to buy.

**Business rules.** A Sales Order carries its own approval state
(`pending → approved / rejected`) separate from a fulfilment state, so an
unapproved order cannot be delivered. It is non-posting.

**Validations.** Customer, branch and lines are required. Header and line edits
are refused once the order leaves its editable approval state.

**Posting, tax, inventory, GL, subledger behaviour.** None. **Critically, an
approved Sales Order reserves nothing** — available-to-promise is not reduced,
and two orders may promise the same unit. Reservation is **Future**.

**Relationship behaviour.** The Sales Order is the source a Delivery Receipt
draws its lines from.

**Cancelled / reversed / corrected.** Rejected before approval; cancelled before
fulfilment. No accounting consequence in either case.

**Reports changed.** Order backlog and fulfilment state.

### 1.3 Delivery Receipt

**Purpose.** Record that goods physically left the warehouse, and recognise that
their cost is no longer available inventory even though no sale has yet been
recognised.

**Business rules.** A delivery is an **accounting event but not a taxable
event**. Stock leaves at the item's governed cost, and that cost parks in *Goods
Delivered Not Invoiced* until the Sales Invoice recognises it as cost of sales.
A delivery carrying nothing stockable is a shipping record and stays unposted
rather than producing an empty journal.

**Required validations.** Every stockable line needs a warehouse and an inventory
account. Stock on hand must cover the quantity. The delivery date must fall in an
open fiscal period. The *Goods Delivered Not Invoiced* account must be configured.

**Posting behaviour.** DR Goods Delivered Not Invoiced / CR Inventory, for the
costed value of the stockable lines. Posting is idempotent: calling it twice
produces one journal, not two reliefs.

**Tax behaviour.** None. No tax code is resolved and no tax ledger row is written.

**Inventory behaviour.** Quantity and value leave `stock_balances`; an `issue`
inventory transaction is written against the delivery; the delivered cost is
stamped back onto the delivery line, and that stamp is what later tells the Sales
Invoice the cost has already left.

**GL and subledger behaviour.** A balanced journal through the Posting Engine.
No AR, no revenue and no customer subledger movement — the customer owes nothing
until billed.

**Relationship behaviour.** *Bill This Delivery* creates a draft Sales Invoice
whose lines carry the delivery line they bill. **That link is what stops the
invoice relieving the stock a second time.** One delivered line may be billed
once, enforced structurally.

**What happens if cancelled.** The delivery journal is reversed, the goods are
restocked at the cost that left, and the delivery becomes `cancelled`. A reason
is mandatory. **The cancellation is refused while any non-cancelled Sales
Invoice bills the delivery — a draft invoice included** — because reversing the
clearing balance underneath a live invoice would leave that invoice taking a cost
that no longer exists. The invoice is voided first, the delivery second, never
the other way round.

**What happens if reversed / corrected.** There is no partial cancellation: a
delivery cancels whole or not at all. A partial physical return after billing is
the Customer Return path, not this one.

**Reports changed.** Stock balances, stock movements, inventory valuation, GL,
trial balance and the *Goods Delivered Not Invoiced* control balance.

### 1.4 Sales Invoice

**Purpose.** Bill the customer, recognise revenue and the correct Philippine
business tax, and recognise the cost of what was sold.

**Business rules.** The Sales Invoice is where the commercial and accounting
worlds meet. It carries a BIR-registered document number. It moves
`draft → approved → posted`, and a posted invoice is immutable; it is corrected
by voiding, not editing.

**Required validations.** Customer, at least one line, a tax code per line, a
revenue account per line, an open fiscal period, and a configured number series.
A line sourced from a delivery must trace to a **delivered** delivery line of the
same company and customer.

**Posting behaviour.** DR Accounts Receivable; CR Revenue per line; CR Output VAT
or Percentage Tax Payable as the line's code dictates. For cost:
- If the line **was not** delivered first, the invoice relieves stock itself:
  DR COGS / CR Inventory.
- If the line **was** delivered first, the cost is already out of inventory, so
  the invoice moves it from the clearing account: DR COGS / CR Goods Delivered
  Not Invoiced. The clearing balance nets to zero once every delivered line is
  billed.

**Tax behaviour.** The line's business-tax code is resolved through the single
Tax Engine, which decides VAT or percentage tax and applies the rate version in
force **on the document date**, not today's rate. One tax ledger row is written
per code, stamped with the tax-code version, its rate and the return's ATC where
applicable.

**Inventory behaviour.** Exactly one relief per unit sold, at delivery or at
invoicing, never both.

**GL and subledger behaviour.** A balanced journal; the customer subledger and AR
ageing move; the sales register and the output-tax review pick the document up.

**Relationship behaviour.** Parent of the Official Receipt, the Credit Memo and
the Customer Return; child of the Delivery Receipt when billed from one.

**What happens if cancelled / voided.** The journal is reversed, the tax ledger
entries are reversed, and any stock the invoice itself relieved is restored with
an `adjustment_in` transaction. A reason is mandatory and becomes CAS void
evidence. The document number is preserved and marked void — never reused.

**What happens if corrected.** A posted invoice is never edited. Either void and
re-issue, or issue a Credit Memo. Which one is a business judgement: void when
the invoice should not exist; credit when it should exist but for less.

**Reports changed.** Customer ledger, AR ageing, sales registers, GL, trial
balance, financial statements, the tax ledger, and every downstream compliance
artifact in Module 5.

### 1.5 Cash Sale

**Purpose.** Record a sale that is delivered and collected in the same act.

**Business rules.** A Cash Sale is a Sales Invoice variant with its own document
series (CS). It debits cash instead of receivable, so no Official Receipt is
required and no receivable is created.

**Posting, tax and inventory behaviour.** As the Sales Invoice, except DR Cash
replaces DR Accounts Receivable. It relieves stock directly — a Cash Sale is an
outbound entry point in its own right.

**What happens if cancelled / reversed / corrected.** Void, as with the Sales
Invoice.

**Reports changed.** As the Sales Invoice, plus the cash position and the Cash
Receipts Book.

### 1.6 Official Receipt

**Purpose.** Record what the customer actually paid, and the creditable
withholding tax the customer withheld on the payment.

**Business rules.** A receipt applies against posted Sales Invoices. The
customer's withholding is not a discount: it is tax the customer remitted on the
company's behalf, and it becomes a **receivable asset** the company will claim
against its income tax with a Form 2307.

**Required validations.** At least one posted invoice to apply against, a payment
mode, and a cash or bank account. Applied amounts may not exceed what is open.

**Posting behaviour.** DR Cash or Bank; DR Creditable Withholding Tax Receivable
for any CWT; CR Accounts Receivable for the gross settled.

**Tax behaviour.** Writes a `cwt_receivable` row to the tax ledger, keyed to the
customer and ATC. This is the source of the SAWT listing and of the Form 2307
certificates the company **receives**.

**Inventory behaviour.** None.

**Subledger behaviour.** The customer ledger and AR ageing reduce by the gross
settled, not the net cash.

**What happens if cancelled or bounced.** A `bounced` status exists for a failed
payment instrument and a `cancelled` status for a withdrawn receipt. Either
reverses the journal and restores the receivable. A reason is mandatory.

**Reports changed.** Customer ledger, AR ageing, collection monitoring, cash
position, Cash Receipts Book, GL, and the SAWT source.

### 1.7 Credit Memo and Customer Return

**Purpose.** Reduce what the customer owes — for a price correction, an
allowance, or physically returned goods.

**The distinction that matters.** A credit memo line **with no warehouse** is a
price adjustment and moves no stock. A credit memo line **with a warehouse** is a
physical Customer Return and restocks the goods. One document type, one posting
path, and the presence of a warehouse is the whole difference.

**Business rules.** A credit memo moves `draft → approved → applied`, and may be
cancelled while unapplied. It may reference a source invoice or stand alone.

**Posting behaviour.** DR Revenue and DR Output VAT / CR Accounts Receivable. A
Customer Return adds DR Inventory / CR COGS for the returned cost.

**Tax behaviour.** Reduces output VAT. **Percentage tax is not reversed by a
credit memo** — see the Exception Scenarios table and Backlog 8b.

**Inventory behaviour.** Restocks only where a warehouse is named.

**What happens if cancelled.** Cancellable while unapplied; once applied it is
part of the customer's settled history.

**Reports changed.** Customer ledger, AR ageing, sales registers, GL, tax ledger;
plus stock balances and movements for a Customer Return.

### 1.8 Collections, ageing and write-off

Collections monitoring is read-only: AR ageing as of any date, the customer
ledger, and payment monitoring. **AR write-off is Future** — no function or
document exists to derecognise an uncollectible receivable, so a bad debt can
only be handled today by a manual journal entry, which leaves the customer
subledger and the control account to be reconciled by hand.

### 1.9 What the flow does not automate

**Document conversion is not built.** Quotation → Sales Order → Sales Invoice
carry-forward does not exist; the Document Conversion Engine is **Planned, not
started**. The single exception is *Bill This Delivery*, which creates the
governed delivery-line relationship and remains the **only supported way to bill
a delivery**. A server-side readiness guard now refuses a hand-entered stock line
when live delivered goods for the same company, customer and item are waiting to
be billed; it runs at approval and again at posting, so it also catches a
delivery created after approval. This prevents double stock relief and a stranded
Goods Delivered Not Invoiced balance, but creates no relationship or
carry-forward of its own. Backlog 18b therefore remains partially complete.

## Downstream Impact

```
Sales Invoice / Cash Sale
        ↓
  Posting Engine  (single governed doorway)
        ↓
  Accounting Kernel  (totality guard — rejects any unsanctioned ledger write)
        ↓
  Journal Entry + Journal Entry Lines
        ↓
  ┌─────┴───────────────┬────────────────────┬─────────────────────┐
  ↓                     ↓                    ↓                     ↓
General Ledger    AR Subledger        Inventory Subledger    Tax Ledger
  ↓                     ↓                    ↓                     ↓
Trial Balance     Customer Ledger      Stock Balances       Reconciliation
  ↓                AR Ageing           Stock Movements            ↓
Financial              ↓               Inventory Valuation   Working Paper
Statements        Collection                 ↓                    ↓
  ↓               Monitoring          Inventory-to-Control   Filing Artifact
Comparatives                          Reconciliation              ↓
and Notes                                                     Export File
                                                                  ↓
                                                            Filed Record
                                                    (the accountant's own
                                                     submission; PXL
                                                     transmits nothing)
```

Every branch above is **Implemented**. The Filed Record is a record of a
submission made outside PXL.

## Related Documents

```
Sales Quotation
      ↓  (manual re-entry — conversion not built)
Sales Order
      ↓
Delivery Receipt ──────────────► Delivery Cancellation (terminal)
      ↓  (Bill This Delivery — the only linked path)
Sales Invoice ─────────────────► Invoice Void (terminal)
      ↓
      ├──────────► Official Receipt ────► Receipt Cancellation / Bounce
      │                  ↓
      │            Form 2307 Received ───► SAWT listing
      │
      ├──────────► Credit Memo ──────────► (cancel while unapplied)
      │                  ↓
      │            Customer Return (credit memo carrying a warehouse)
      │
      └──────────► Debit Memo  (increases the receivable)

Cash Sale  ─────────────────────► Void
   (no Official Receipt required — collection is in the document)
```

## Exception Scenarios

| Scenario | Behaviour | Status |
| --- | --- | --- |
| Partial delivery | Deliver fewer units than ordered; the order stays open. Remaining-quantity tracking is not automated | **Implemented** (delivery); remaining-quantity carry-forward **Planned** (Backlog 18b) |
| Over delivery | Nothing prevents delivering more than ordered | **Future** — no over-delivery control |
| Partial billing | Bill some delivered lines and not others; unbilled lines stay in the clearing account | **Implemented** |
| Advance payment / customer deposit | No unapplied-cash or customer-advance document exists | **Future** |
| Cancelled delivery | Reverses the journal, restocks the goods; refused while an invoice bills it | **Implemented** |
| Voided invoice | Reverses journal, tax ledger and any stock it relieved | **Implemented** |
| Returned goods | Credit memo carrying a warehouse; restocks at cost | **Implemented** |
| Short payment | Apply less than the invoice; the balance stays open in the ageing | **Implemented** |
| Overpayment | No unapplied-cash mechanism; excess cannot be parked against the customer | **Future** |
| Credit application | Apply a credit memo against an open invoice | **Implemented** |
| Write-off | Derecognise an uncollectible receivable | **Future** |
| Percentage tax on a return | A credit memo does **not** reverse percentage tax, so a return leaves it overstated | **Planned** — Backlog 8b (ii) |
| Percentage tax on collections | Percentage tax is recognised on the document, not on collections; a credit Sales Invoice for services recognises it earlier than a receipts basis would | **Planned** — Backlog 8b (i) |
| Untagged percentage-tax line | Nothing compels a percentage-tax-registered company to select its code | **Planned** — Backlog 8b (iii) |
| Statutory rate change mid-year | Handled as a tax-code succession; documents keep the rate that priced them | **Implemented** |

## Internal Engines Used

Posting Engine (with the Accounting Kernel as its totality guard) · Tax Engine ·
Number Series Engine · Chart of Accounts Engine · Dimension Engine · AR Engine ·
Payment and Application Engine · Approval and Workflow Engine · Reversal, Void
and Correction Engine · Period Lock and Closing Engine · Audit and Immutability
Engine · Permissions and RLS Engine · Reporting and Reconciliation Engine.

**Not used:** Document Conversion Engine (not started) · Currency Engine
(deferred, PHP only) · Inventory Accounting Engine (frozen, zero consumers).

## Accounting Truth

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The posted journal entry and its lines. Not the document, not the screen, not a report. |
| **Posting Authority** | The Posting Engine is the only doorway to the ledger; the Accounting Kernel rejects every unsanctioned write, and survives a restore into a fresh database. |
| **Tax Authority** | The Tax Engine is the only place tax arithmetic happens, and the only place a VAT code's validity is decided. Rates resolve as of the document date. |
| **Inventory Authority** | `stock_balances` and `inventory_transactions` through the shared costing path. Cost leaves inventory exactly once per unit sold. |
| **Compliance Authority** | The tax ledger, then the Filing Artifact — never a screen aggregate. See Module 5. |
| **Reporting Authority** | Posted data only, through the single financial-statement entry point and the governed report views. |

## Reports Updated

Customer Ledger · AR Ageing (as of any date) · Collection / Payment Monitoring ·
Sales Registers · Cash Receipts Book · Stock Balances · Stock Movements ·
Inventory Valuation · General Ledger · Account Detail Ledger · Trial Balance ·
Financial Statements (all four) · Comparative Statements · Control Account
Reconciliation · Output VAT review · Percentage Tax review · SLS (sales side of
SLSP) · SAWT source · Accounting Source and Trace.

## Pilot Status

**Implemented.** Quotation · Sales Order · Delivery Receipt and its cancellation ·
Sales Invoice and its void · Cash Sale · Official Receipt and its cancellation ·
Credit Memo · Customer Return · collections monitoring · period close ·
financial statements · output VAT and percentage tax through to the filing
artifact.

**Remaining work.** Full document conversion beyond the delivery-to-invoice link
(Backlog 18b) · the three percentage-tax boundaries (Backlog 8b).

**Pilot blockers.** Billing a delivery is complete **only** through *Bill This
Delivery*; unsafe hand-entry is refused rather than converted. The wider
quotation/order/delivery/invoice relationship and remaining-quantity workflow is
still absent, so no Sales workflow yet meets the Product Definition of Done.

**Future enhancements.** Stock reservation · advance payments and unapplied cash ·
overpayment handling · over-delivery control · AR write-off · customer inquiry
capture.

**Excluded scope.** Foreign-currency sales · income-tax consequences of sales ·
any payroll-related customer billing. See §0.5.

---

# 2. Procure-to-Pay (Purchasing & Payables)

## Purpose

**Why the module exists.** A Philippine SME must order from suppliers, receive
goods into stock at a known cost, record the supplier's bill with recoverable
input VAT, withhold expanded withholding tax where the law requires it, and pay —
with the withheld tax becoming a liability the company must remit to the BIR.

**Business objective.** Convert a purchasing need into owned inventory or
recognised expense, a correctly stated payable, recoverable input VAT, and an
accurate EWT remittance obligation.

**Business owner.** Purchasing Manager for the commercial steps; Accounting
Manager for the payable, input VAT and withholding. They meet at the Vendor Bill.

**Users involved.** Requestor (future) · Purchasing officer · Warehouse receiving
personnel · Accounts payable clerk · Accountant · Treasury or disbursing officer ·
Compliance officer.

**Departments involved.** Purchasing · Warehouse / Receiving · Accounting /
Finance · Treasury · Compliance.

## End-to-End Flow

```
                 Purchase Request  (Future — not built)
                              ↓
                     Purchase Order  (Implemented, non-posting)
                              ↓
        ┌─────────────────────┴──────────────────────┐
        ↓                                            ↓
  Receiving Report  (Implemented)              Cash Purchase  (Implemented)
  stock arrives; cost parks in                 buys and pays in one act
  Goods Received Not Invoiced                        ↓
        ↓                                            │
  Receiving Correction  (Future — no governed        │
   reversal for a received report)                   │
        ↓                                            │
   Vendor Bill  (Implemented)  ←─────────────────────┘
   payable + input VAT; consumes the clearing balance
   EWT accrued here when the bill uses accrual basis
        ↓
   ┌────┴──────────────────┬──────────────────────┐
   ↓                       ↓                      ↓
Bill Void            Vendor Credit          Payment Voucher
(Implemented)        (Implemented)          (Implemented)
                          ↓                 EWT withheld here when
                   Purchase Return          the bill uses payment basis
                   (Implemented —                  ↓
                   ships goods back)         Check Voucher
                                             (Future Priority)
        ↓                       ↓                      ↓
        └───────────────────────┴──────────────────────┘
                              ↓
                    AP Position and Settlement
                    (Implemented — ageing, ledger, monitoring)
                              ↓
                  Withholding Remittance  (Implemented)
                              ↓
                        Period Close
                              ↓
                    Financial Statements
                              ↓
          Tax Ledger → Working Paper → 1601EQ / QAP / 2307 issued
                              ↓
                        BIR Filing  (see Module 5)
```

## Business Process Matrix

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Purchase Request | Capture internal demand before committing | Requestor | — | — | — | Would require approval | None | None | None | None | Purchase Order | — | — | **Future** |
| Purchase Order | Commit to the supplier | Purchasing officer | Purchase Request | Purchase Order | Supplier, items, branch | Yes (draft → approved) | None | None | None | Open-PO / commitment view | Receiving Report | Cancel before receipt | Header/line change log | **Implemented** |
| Receiving Report | Take goods into stock at cost | Receiving clerk | Purchase Order | Receiving Report | Item, warehouse, quantity within its exact PO line, open period; inventory and clearing accounts configured; serial/lot identity when required | No | **Increases stock** at receipt cost | DR Inventory Control / CR Purchase Clearing | None — receipt computes no tax | Stock balances, movements, valuation, GL, trial balance | Purchase Order, Vendor Bill | Governed whole cancellation after live bills and downstream consumption are corrected; exact source quantity/value/layer removed | Posting event, journal, reversal, inventory transaction, CAS void evidence | **Implemented and exercised for all three costing methods** |
| Vendor Bill | Record the supplier's invoice and the payable | AP clerk | Receiving Report, Purchase Order | Vendor Bill | Supplier, lines, expense or inventory accounts, tax codes, open period | Yes (draft → approved → posted) | None when the goods already arrived; the clearing balance is consumed | DR Expense or Purchase Clearing / DR Input VAT / CR Accounts Payable; CR EWT Payable on accrual basis | **Input VAT** claimed; **EWT accrued** if the bill withholds at accrual | Supplier ledger, AP ageing, purchase registers, GL, trial balance, tax ledger | Receiving Report, Payment Voucher, Vendor Credit | **Bill Void** | Posting event, journal, tax detail, CAS issuance | **Implemented** |
| Bill Void | Withdraw a wrong bill | Accountant | Vendor Bill | Reversal journal | Reason required | No (reason mandatory) | Restores anything the bill moved | Reverses the bill journal | Reverses input VAT and accrued EWT | All of the above | Vendor Bill | Terminal | Posting event, CAS void evidence | **Implemented** |
| Cash Purchase | Buy and pay in one act | Purchasing / Cashier | — | Cash Purchase | Supplier, lines, cash account, tax codes | Yes | Increases stock where stockable | DR Expense or Inventory / DR Input VAT / CR Cash | Input VAT; EWT where applicable | Purchase registers, cash, GL, tax ledger | — | Void | Posting event, journal, tax detail | **Implemented** |
| Vendor Credit | Reduce a payable for a supplier credit | AP clerk | Vendor Bill | Vendor Credit | Supplier; source bill optional | Yes | None unless goods return | DR Accounts Payable / CR Expense / CR Input VAT | Reduces input VAT | Supplier ledger, AP ageing, GL, tax ledger | Vendor Bill, Purchase Return | Reverse the application | Posting event, journal, tax detail | **Implemented** |
| Purchase Return | Send goods back to the supplier | Warehouse + AP | Receiving Report, Vendor Bill | Purchase Return | Exact received line/layer; quantity available; serial/lot identity when required | Yes | **Reduces stock at exact receipt cost** on shipment | DR Accounts Payable / CR Inventory Control | Tax remains governed by the purchasing document policy | Stock balances, movements, supplier ledger, GL | Vendor Credit, Receiving Report | Correct downstream claims before receipt cancellation | Posting event, inventory allocation, journal | **Implemented and exercised locally** |
| Payment Voucher | Pay the supplier and withhold EWT | Treasury / AP | Vendor Bill | Payment Voucher | Posted bills to apply against; cash or bank account; open period | Yes | None | DR Accounts Payable / CR Cash or Bank / CR EWT Payable on payment basis | **EWT withheld** at payment where the bill uses payment basis | Supplier ledger, AP ageing, payment monitoring, cash, Cash Disbursements Book, GL, tax ledger | Vendor Bill, Check Voucher | **Cancel** | Posting event, journal, tax detail, CAS issuance | **Implemented** |
| Check Voucher | Pay by cheque with a governed instrument lifecycle | Treasury | Vendor Bill | Check Voucher | Bank account, payee, cheque number | Yes | None | As Payment Voucher, with cheque release / clearing / stale states | EWT as Payment Voucher | Check register, outstanding cheques, Cash Disbursements Book | Payment Voucher | Cancel | Posting event, journal | **Future Priority** — posting function exists; never produced a journal |
| Withholding Remittance | Remit withheld EWT to the BIR | Compliance officer | Payment Vouchers, Vendor Bills | Remittance record | Posted EWT in the period | Yes | None | DR EWT Payable / CR Cash | Settles the EWT liability; feeds 1601EQ | Tax ledger, GL, 1601EQ working paper | 1601EQ, QAP | **Void** | Posting event, journal | **Implemented** |
| AP settlement monitoring | See what is owed and due | AP / Treasury | Posted bills and payments | — (read-only) | — | No | None | None | None | AP ageing, supplier ledger, payment monitoring | — | — | Read-only views | **Implemented** |

## Detailed Step Discussion

### 2.1 Purchase Order

**Purpose.** Commit the company to a supplier before anything arrives.

**Business rules.** Non-posting. Moves `draft → approved`, then tracks
`partially_received → fully_received` as receipts arrive, and may be `cancelled`.

**Validations.** Supplier, branch and lines are required. A cancelled order
cannot be received against.

**Posting, tax, inventory, GL, subledger behaviour.** None. A commitment is not
a liability; no accrual is made at order time.

**What happens if cancelled.** A governed cancellation exists. There is no
accounting consequence.

**Reports changed.** Open-PO and commitment views only.

### 2.2 Receiving Report

**Purpose.** Recognise that goods have arrived and are now the company's
inventory, even though the supplier's bill has not been recorded.

**Business rules.** Receipt is the moment inventory becomes perpetual on the
purchase side. The cost parks in a **Goods Received Not Invoiced** clearing
account, which the Vendor Bill later debits, so the two documents net to zero.

**Required validations.** Item, warehouse and quantity per line; an open fiscal
period; the governed inventory-control and purchase-clearing accounts configured.
Each receipt line must belong to the exact Purchase Order, company and item named
by its header. Confirmed quantity across all live receipts may not exceed that
order-line quantity. The order line is locked while this is decided, so two
concurrent confirmations cannot each consume the same remainder. Account
determination is configuration, not a hard-coded account code.

**Posting behaviour.** DR Inventory Control / CR Purchase Clearing. Receipt posts
while the source is still in its draft state so the source lock is taken
correctly.

**Tax behaviour.** None. A receipt is not a taxable event; the input VAT belongs
to the supplier's bill.

**Inventory behaviour.** Quantity and value enter `stock_balances`. A cost layer
is created **only** for costing methods whose outflow path can consume one
(FIFO and specific identification) — a weighted-average item gets no layer,
symmetric with consumption.

**GL and subledger behaviour.** A balanced journal; no payable yet, because the
supplier has not billed.

**What happens if cancelled or reversed.** The user supplies a governed reason.
The operation is refused while any live Vendor Bill claims the receipt, a draft
included, or when its exact quantity/value or source layer is no longer fully
available because stock moved onward. Correcting the downstream issue restores
its immutable allocation to the original layer. Cancellation then removes the
exact historical receipt, appends a reversal inventory transaction, reverses the
original journal through the shared reversal authority, records CAS evidence,
moves the report to `cancelled`, and recomputes the Purchase Order header. This
ordered contract applies to Weighted Average, FIFO and Specific Identification;
a draft report cancels without stock or journal effect.

**Reports changed.** Stock balances, movements, valuation, the inventory-to-control
reconciliation, GL and trial balance.

### 2.3 Vendor Bill

**Purpose.** Record what the supplier has charged, claim recoverable input VAT,
and recognise the payable and any withholding obligation.

**Business rules.** Moves `draft → approved → posted`; a posted bill is immutable
and corrected by voiding. Withholding basis is a property of the bill: **accrual
basis** accrues EWT when the bill posts; **payment basis** defers it to the
Payment Voucher. The two must never both fire for the same line.

**Required validations.** Supplier with a TIN where withholding applies, lines
with expense or inventory accounts, tax codes, an open fiscal period, and an ATC
where EWT is withheld. The EWT amount must agree with the ATC's rate on the
taxable base, or carry an explicit variance reason.

**Posting behaviour.** DR Expense or Purchase Clearing per line; DR Input VAT;
CR Accounts Payable; CR EWT Payable when the bill accrues withholding. Where the
goods were received first, the debit clears the Goods Received Not Invoiced
balance rather than increasing inventory a second time.

**Tax behaviour.** Input VAT is written to the tax ledger per code. Accrued EWT is
written as `ewt_payable`, keyed to the supplier and ATC — the source of 1601EQ,
the QAP alphalist and the Form 2307 certificates the company **issues**.

**Inventory behaviour.** None when the goods already arrived. A bill for stockable
items never received is an inventory increase in its own right.

**Relationship and match behaviour.** Where the header names a Receiving Report,
the bill must use the same company and supplier, the receipt must be `received`,
and live billed quantity per item may not exceed live received quantity. Partial
and second bills are supported. A bill with no `rr_id` remains valid for an
expense/service or intentional bill-without-receipt flow. This is a **quantity
match only**. There is no governed price tolerance, variance account,
approval/reason policy, or capitalization-versus-expense rule, so price variance
is recorded as a separate product decision rather than computed here.

**What happens if cancelled / voided.** Journal, input VAT and accrued EWT are all
reversed; a reason is mandatory and becomes CAS void evidence.

**Reports changed.** Supplier ledger, AP ageing, purchase registers, Purchase
Journal, GL, trial balance, input VAT review, EWT review.

### 2.4 Payment Voucher and Check Voucher

**Purpose.** Settle the payable and, where the bill defers withholding to
payment, withhold the EWT.

**Business rules.** A payment applies against posted bills. The gross settled
reduces the payable; the cash paid is the gross less any EWT withheld, and the
difference becomes a liability to the BIR.

**Required validations.** Posted bills to apply against; a cash or bank account;
an open period; applied amounts within what is open.

**Posting behaviour.** DR Accounts Payable / CR Cash or Bank / CR EWT Payable.

**Tax behaviour.** Writes `ewt_payable` to the tax ledger at payment where the
bill uses payment basis.

**What happens if cancelled.** A governed cancellation reverses the journal and
restores the payable and the withholding.

**Check Voucher** adds a cheque instrument lifecycle — released, cleared, stale —
on top of the same settlement. Its posting function exists and it is registered
as a posting source, but it has never produced a journal. It is the **one Banking
& Treasury capability the Delivery Plan carves out of v2**, because the Cash
Disbursements Book depends on it. **Future Priority.**

**Reports changed.** Supplier ledger, AP ageing, payment monitoring, cash
position, Cash Disbursements Book, GL, EWT review; plus the check register and
outstanding-cheque report once Check Voucher is live.

### 2.5 Vendor Credit and Purchase Return

**Purpose.** Reduce the payable when the supplier credits the company, and send
goods back.

**Business rules.** A Vendor Credit is financial; a Purchase Return is physical
and ships stock back to the supplier. A return may generate a credit.

**Posting behaviour.** Vendor Credit: DR Accounts Payable / CR Expense / CR Input
VAT. Purchase Return reduces inventory on shipment.

**Tax behaviour.** Reduces input VAT.

**What happens if reversed.** A vendor-credit application can be reversed as its
own governed act.

**Reports changed.** Supplier ledger, AP ageing, purchase registers, stock
balances and movements, GL, tax ledger.

### 2.6 Withholding Remittance

**Purpose.** Pay the BIR the tax the company withheld from its suppliers.

**Business rules.** Remittance settles the EWT Payable liability accumulated by
bills and payment vouchers. It is the bridge between the tax ledger and the
1601EQ return, and it has a governed void.

**Posting behaviour.** DR EWT Payable / CR Cash.

**Reports changed.** Tax ledger, GL, the 1601EQ working paper and its
`remitted_prior` figure, which is **derived** from the remittance record rather
than stated by the user.

## Downstream Impact

```
Purchase Order  (no accounting effect)
        ↓
Receiving Report ──► Posting Engine ──► Kernel ──► Journal Entry
        ↓                                              ↓
  Inventory Subledger                            General Ledger
  (stock balances, movements, valuation)               ↓
        ↓                                        Trial Balance
  Inventory-to-Control Reconciliation                  ↓
                                               Financial Statements
Vendor Bill  ──► Posting Engine ──► Kernel ──► Journal Entry
        ↓                                              ↓
  ┌─────┴────────────┬──────────────────┐        General Ledger
  ↓                  ↓                  ↓              ↓
AP Subledger    Input VAT          EWT Payable   Trial Balance
  ↓             (tax ledger)       (tax ledger)        ↓
Supplier Ledger      ↓                  ↓       Financial Statements
AP Ageing      2550Q working      1601EQ + QAP
Payment             paper           working paper
Monitoring           ↓                  ↓
               Filing Artifact    Filing Artifact + 2307 issued
                     ↓                  ↓
                 Export File        Export File
                     ↓                  ↓
               Filed Record        Filed Record
```

## Related Documents

```
Purchase Request  (Future)
      ↓
Purchase Order
      ↓
Receiving Report ──────────────► Receipt Cancellation (terminal)
      ↓
Vendor Bill ───────────────────► Bill Void (terminal)
      ↓
      ├──────────► Payment Voucher ────► Cancel
      │                  ↓
      │            Check Voucher (Future Priority)
      │                  ↓
      │            Withholding Remittance ──► Void
      │                  ↓
      │            Form 2307 Issued ────► QAP alphalist
      │
      ├──────────► Vendor Credit ───────► Reverse application
      │                  ↓
      │            Purchase Return (ships goods back)
      │
      └──────────► Supplier Debit Memo

Cash Purchase  ────────────────► Void
```

## Exception Scenarios

| Scenario | Behaviour | Status |
| --- | --- | --- |
| Partial receipt | Receive fewer units than ordered; the PO stays partially received | **Implemented** |
| Over receipt | Exact confirmed quantity may not exceed the Purchase Order line; no tolerance exists | **Implemented** |
| Three-way quantity match | PO line ↔ live receipts and received item ↔ live bills are governed at the relationship grain the schema supports | **Implemented** |
| Price variance | No tolerance/account/approval or accounting-treatment policy exists | **Product decision required** — Backlog 18l |
| Receiving correction | Cancel draft or received RR with a governed reason; live bills and consumed source layers block until corrected; exact history is retained for all three methods | **Implemented and exercised locally** |
| Partial billing | Bill some received quantity and then a valid remainder on a second bill | **Implemented** |
| Bill without receipt | A bill for goods never received increases inventory itself | **Implemented** |
| Advance payment to supplier | No supplier-advance or prepayment document exists | **Future** |
| Voided bill | Reverses journal, input VAT and accrued EWT | **Implemented** |
| Returned goods | Purchase Return ships the exact receipt cost/identity and posts against Accounts Payable | **Implemented and exercised locally** |
| Short payment | Apply less than the bill; the balance stays open | **Implemented** |
| Overpayment | No unapplied-cash mechanism for suppliers | **Future** |
| Credit application | Apply a vendor credit against an open bill; reversible | **Implemented** |
| EWT variance | An EWT amount that disagrees with the ATC rate requires an explicit variance reason | **Implemented** |
| Withholding on the wrong basis | Accrual and payment basis are mutually exclusive per bill | **Implemented** |
| Payment by cheque with a lifecycle | Released / cleared / stale cheque states | **Future Priority** |

## Internal Engines Used

Posting Engine (with the Accounting Kernel) · Tax Engine · Number Series Engine ·
Chart of Accounts Engine · Dimension Engine · AP Engine · Payment and Application
Engine · Approval and Workflow Engine · Reversal, Void and Correction Engine ·
Period Lock and Closing Engine · Audit and Immutability Engine · Permissions and
RLS Engine · Reporting and Reconciliation Engine.

**Not used:** Document Conversion Engine · Currency Engine · Inventory Accounting
Engine.

## Accounting Truth

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The posted journal entry and its lines. |
| **Posting Authority** | The Posting Engine, guarded by the Accounting Kernel. |
| **Tax Authority** | The Tax Engine for input VAT and ATC withholding arithmetic; the ATC master for rates, resolved as of the document date. |
| **Inventory Authority** | `stock_balances` and `inventory_transactions`; receipt cost is the basis for everything downstream. |
| **Compliance Authority** | The tax ledger, then the Filing Artifact. |
| **Reporting Authority** | Posted data only. |

## Reports Updated

Supplier Ledger · AP Ageing (as of any date) · Payment Monitoring · Purchase
Registers · Purchase Journal · Cash Purchases Journal · Cash Disbursements Book ·
Stock Balances · Stock Movements · Inventory Valuation · General Ledger · Account
Detail Ledger · Trial Balance · Financial Statements · Control Account
Reconciliation · Input VAT review · EWT review · SLP (purchase side of SLSP) ·
QAP alphalist · Form 2307 issued.

## Pilot Status

**Implemented.** Purchase Order · Receiving Report with GL posting and governed
three-method cancellation · exact over-receipt and receipt-linked over-billing
control · Vendor Bill and its void · Cash Purchase · Vendor Credit · exact-cost
Purchase Return · Payment Voucher · Withholding Remittance · AP position and
settlement monitoring.

**Remaining work.** Governed price-variance policy/match · supplier-debit
integration · Check Voucher · broad Product-DoD and operated evidence.

**Pilot blockers.** Quantity matching, ordered receipt correction and all three
costing methods are locally proven. A supplier price that differs from its
order/receipt still has no governed tolerance or variance treatment; hosted,
browser/UAT and module evidence are absent. The current Purchasing flow is
therefore exercised, not certified or pilot-ready.

**Future enhancements.** Purchase Request · supplier advances and unapplied cash ·
overpayment handling · landed cost.

**Future Priority.** Check Voucher, carved out of Banking & Treasury v2 for the
Cash Disbursements Book.

**Excluded scope.** Foreign-currency purchasing · Final Withholding Tax and Form
2306 · income-tax consequences of purchases. See §0.5.

---

# 3. Inventory Management

## Purpose

**Why the module exists.** A trading or manufacturing SME must know how much
stock it holds, where it is, and what it cost — and the accountant must be able
to prove that the quantity on the shelf agrees with the value in the General
Ledger.

**Business objective.** Maintain perpetual inventory whose subledger ties to its
control account to the centavo, with cost flowing to cost of sales in the period
the revenue is recognised.

**Business owner.** Warehouse or Operations Manager for physical accuracy;
Accounting Manager for valuation and the control-account tie-out.

**Users involved.** Receiving clerk · Warehouse staff · Inventory controller ·
Accountant · Auditor.

**Departments involved.** Warehouse / Operations · Accounting / Finance.

## End-to-End Flow

```
Item and Warehouse Setup  (Implemented — costing method chosen per item)
                              ↓
        ┌─────────────────────┼────────────────────┬──────────────────┐
        ↓                     ↓                    ↓                  ↓
  Receiving Report      Stock Transfer       Stock Adjustment    Physical Count
  (inbound)             (between warehouses)  (write up/down)    (variance)
  Implemented           Implemented           Implemented        Implemented
        ↓                     ↓                    ↓                  ↓
        └─────────────────────┴────────────────────┴──────────────────┘
                              ↓
                    Perpetual Stock Position
                    (quantity + value, per warehouse per item)
                              ↓
        ┌─────────────────────┼────────────────────┬──────────────────┐
        ↓                     ↓                    ↓                  ↓
  Delivery Receipt      Sales Invoice         Cash Sale          Goods Issue
  (outbound)            (outbound)            (outbound)         (internal use)
  Implemented           Implemented           Implemented        Implemented*
        ↓                     ↓                    ↓                  ↓
        └─────────────────────┴────────────────────┴──────────────────┘
                              ↓
                    Returns put stock back
        Customer Return (in)         Purchase Return (out)
        Delivery Cancellation (in)   Invoice Void (in)
                              ↓
                    Costing and Valuation
                    (Weighted Average / FIFO / Specific ID — locally proven)
                              ↓
              Inventory-to-Control Reconciliation  (Implemented, at 0.00)
                              ↓
                        Period Close
                              ↓
                    Financial Statements

  * Every proof in this section is local; no hosted or pilot operation is claimed.
```

## Business Process Matrix

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Item / Warehouse setup | Define what is stocked, where, and how it is costed | Master-data steward | — | Item, Warehouse | Costing method; inventory, COGS and variance accounts | Governed maintenance | None | None | None | Master-data review | All inventory documents | Governed edit with change log | Change log | **Implemented** |
| Receiving (inbound) | Take goods into stock | Receiving clerk | Purchase Order | Receiving Report | Warehouse, quantity within the exact PO line, open period; serial/lot identity where required | No | **Increase** at receipt cost | DR Inventory / CR Purchase Clearing | None | Stock balances, movements, valuation, GL | Vendor Bill | Governed whole cancellation after billing/downstream correction; exact historical source removal | Posting event, reversal, inventory transaction, CAS evidence | **Implemented and exercised for all three methods** |
| Issue (outbound, sale) | Release goods to a customer | Warehouse | Sales Order | Delivery Receipt / Sales Invoice / Cash Sale | Sufficient stock; warehouse per line | No | **Decrease** at governed cost | DR Clearing or COGS / CR Inventory | None at delivery; tax at invoicing | Stock balances, movements, valuation, GL | Module 1 documents | Cancellation, void, or Customer Return | Posting event, inventory transaction | **Implemented** |
| Goods Issue (internal) | Consume stock internally | Inventory controller | — | Goods Issue | Sufficient stock; expense account; identity for Specific ID | Yes | **Decrease** at authoritative cost | DR Expense / CR Inventory | None | Stock balances, movements, GL | — | Historical allocation evidence retained | Posting event, inventory allocation | **Implemented and exercised locally** |
| Transfer | Move stock between warehouses | Warehouse | — | Stock Transfer | Stock in source; destination warehouse; identity where applicable | Yes | Decrease at source, increase at destination with cost/lineage preserved | Company-wide value-neutral inventory movement | None | Stock balances, movements | Inter-Branch Transfer | Historical source/destination lineage retained | Posting event, inventory allocations | **Implemented and exercised locally** |
| Adjustment | Write stock up or down for a known reason | Inventory controller | — | Stock Adjustment | Reason code; item; warehouse; open period | Yes | Increase or decrease | DR or CR Inventory against the variance account | None | Stock balances, movements, valuation, GL | Physical Count | Reverse by opposite adjustment | Posting event | **Implemented** |
| Physical Count | Reconcile the shelf to the book | Inventory controller + Accountant | Count sheet | Physical Count | Counted quantity per item per warehouse; open period | Yes | Posts the **variance** only | DR or CR Inventory / Inventory Variance | None | Stock balances, valuation, GL, variance analysis | Stock Adjustment | Recount and re-post | Posting event | **Implemented** |
| Returns (in and out) | Put stock back or send it back | Warehouse | Credit Memo / Purchase Return | — | Original outbound or receipt evidence; warehouse; identity where applicable | Yes | Increase at historical outbound cost or decrease at exact receipt cost | Mirrors original inventory cost through the Posting Engine | Tax remains owned by the source document policy | Stock balances, movements, GL, tax ledger | Modules 1 and 2 | Correct downstream claims first | Posting event, inventory allocation, journal | **Implemented and exercised locally** |
| Valuation | State what the stock is worth | Accountant | All inventory movements | — (read-only) | — | No | None | None | None | Inventory valuation, control reconciliation | — | — | Derived from posted data | **Implemented** |
| Costing | Decide the cost of each unit that leaves | System | Item costing method | — | Method set per item; method changes fail closed after activity; Specific ID requires serial/lot | No | Determines every outflow value | Supplies cost to the one Posting Engine | None | Valuation and reconciliation | Source receipt/outbound evidence | Exact allocation reversal/return | Inventory transactions, layers and immutable allocations | **Built, reachable, exercised and proven locally for all three methods** |
| Period Close | Freeze inventory movement for a period | Accountant | — | — | Period unlocked | Yes | Blocks further posting into the period | Blocks further posting | None | All inventory reports as of the period | — | Governed reopen | Period lock record | **Implemented** |

## Detailed Step Discussion

### 3.1 Costing and valuation

**Purpose.** Decide what each unit that leaves the warehouse cost.

**Business rules.** The costing method is a property of the **item**. PXL
recognises weighted average, FIFO and specific identification. Every inflow and
outflow uses **one shared costing path** — there is no second costing
implementation anywhere in the product.

- **Weighted Average** recomputes the carrying rate after an inflow; each issue
  stamps its historical rate, so a later receipt cannot reprice its reversal or
  customer return.
- **FIFO** consumes layers in admitted order and stores each exact allocation.
  Void/return restores those same source layers; receipt cancellation requires
  them to be fully available.
- **Specific Identification** requires serial or lot tracking. The user selects
  an available identity, while the database validates company, item, warehouse,
  quantity and availability and obtains cost from that identity's source layer.
  Reversal restores the same identity, never a substitute.

Cost-layer rows and immutable `inventory_layer_allocations` are now production
evidence. Locked layer selection prevents concurrent over-consumption, including
two writers racing for one serial. A costing-method/default change fails closed
after stock, movements or layers exist; posted history is never reinterpreted.

**Posting behaviour.** Costing produces the value the Posting Engine writes; it
never writes the ledger itself.

**Backdating and replay.** Costing today is applied in the order movements are
posted. A governed **economic chronology** that would re-derive cost under a
provable ordering — the Inventory Accounting Engine, IA-5/ECC — exists as backend
foundation only. It is **frozen with zero consumers** and is not part of the
current product direction. It is hidden costing infrastructure, not the Inventory
module.

### 3.2 Physical Count

**Purpose.** Prove the book against the shelf, and post the difference.

**Business rules.** A count posts **only the variance**, never the counted
quantity as an absolute. This keeps the movement history complete: the ledger
records that a difference was found, not that stock appeared from nowhere.

**Validations.** A count sheet per warehouse; an open period; a variance account
configured.

**Posting behaviour.** DR or CR Inventory against the Inventory Variance account,
for the value of the difference at the item's governed cost.

**What happens if corrected.** A recount is a new count. Adjustments correct in
the opposite direction; nothing is edited.

**Reports changed.** Stock balances, valuation, variance analysis, GL.

### 3.3 The reconciliation that matters

The inventory subledger must equal its control account. This is one of the
critical reconciliations the product tracks, and it is **evidenced at ₱0.00 in
every stock-holding company**. The method-level reconciliation also requires
each layered stock position to equal its active layer quantity and value.
Production tests prove receipts, issues, transfers, adjustments, counts, returns
and corrections preserve those equations and balanced journals.

**Account determination is configuration, not a hard-coded code.** Account codes
are not interchangeable across charts — one company's 1200 is Accounts
Receivable, another's is Inventory — so the governed keys are resolved per
company.

## Downstream Impact

```
Any inventory movement
        ↓
  Inventory Transaction  (the movement record — never edited, only added to)
        ↓
  Stock Balances  (quantity, total cost, weighted-average unit cost)
        ↓
  ┌─────┴──────────────┬─────────────────────┐
  ↓                    ↓                     ↓
Posting Engine   Stock Movements      Inventory Valuation
  ↓              Stock Balance         Slow-moving analysis
Kernel           reports
  ↓
Journal Entry
  ↓
General Ledger ──► Inventory Control Account
  ↓                        ↓
Trial Balance    Inventory-to-Control Reconciliation  (must be 0.00)
  ↓
Financial Statements  (Inventory on the balance sheet; COGS on the income
                       statement)
```

## Related Documents

```
Purchase Order ──► Receiving Report ──► Vendor Bill
                          ├──► Receipt Cancellation
                          ↓
                   Purchase Return

Sales Order ──► Delivery Receipt ──► Sales Invoice
                     ↓                     ↓
              Delivery Cancellation    Invoice Void
                                           ↓
                                   Credit Memo / Customer Return

Stock Transfer ──► Inter-Branch Transfer
Stock Adjustment ◄── Physical Count
Goods Issue  (internal consumption)
```

## Exception Scenarios

| Scenario | Behaviour | Status |
| --- | --- | --- |
| Insufficient stock on an outbound document | Posting is refused with the on-hand and requested quantities named | **Implemented** |
| Negative stock policy | A per-warehouse or per-item negative-stock policy is defined in master data | **Implemented** (policy master); enforcement beyond the sufficiency check **Planned** |
| Delivery cancelled after stock left | Goods are restocked at the cost that left | **Implemented** |
| Receipt cancelled before billing/onward movement | Exact received quantity/value/layer is removed; journal and GRNI reverse; PO reopens | **Implemented for all three methods** |
| Receipt cancelled after a live bill or stock movement | Cancellation is refused until the bill and downstream allocation are corrected and the exact source is fully available | **Implemented** |
| Invoice voided after stock left | Goods are restocked | **Implemented** |
| Customer returns goods | Restocked at cost through a credit memo carrying a warehouse | **Implemented** |
| Goods returned to supplier | Exact source receipt cost/layer/identity ships on the Purchase Return | **Implemented and exercised locally** |
| Count variance | Posted as a variance against the Inventory Variance account | **Implemented** |
| Backdated movement changing earlier cost | Costing is applied in posting order; no governed replay exists | **Future** — IA-5/ECC frozen |
| FIFO consumption across layers | Exact allocations persist and restore on reversal/return | **Implemented and exercised locally** |
| Lot and serial tracking | Specific-ID receipts create identity layers; every covered outbound/transfer/return path validates and carries the selected identity | **Implemented for inventory costing** |
| Landed cost | Freight and duty capitalised into item cost | **Future** |
| Stock reservation against an order | Available-to-promise reduction | **Future** |

## Internal Engines Used

Posting Engine (with the Accounting Kernel) · Chart of Accounts Engine ·
Dimension Engine · Period Lock and Closing Engine · Reversal, Void and Correction
Engine · Audit and Immutability Engine · Permissions and RLS Engine · Reporting
and Reconciliation Engine.

**Present but dormant:** Inventory Accounting Engine (IA-5/ECC) — backend
foundation, **frozen, zero consumers**, not part of this module.

**Not used:** Tax Engine (inventory movement computes no tax) · Currency Engine ·
Document Conversion Engine.

## Accounting Truth

| Authority | Holder |
| --- | --- |
| **Source of Truth** | `inventory_transactions` for movement; `stock_balances` for position; the General Ledger for value. They must agree. |
| **Posting Authority** | The Posting Engine. No inventory document writes the ledger directly. |
| **Tax Authority** | Not applicable — inventory movement is not a taxable event. |
| **Inventory Authority** | The single shared costing path: one implementation of cost determination for every inflow and outflow. |
| **Compliance Authority** | Not applicable directly; inventory reaches compliance through the COGS and inventory figures in the financial statements. |
| **Reporting Authority** | Posted movement only. |

## Reports Updated

Stock Balances · Stock Movements · Inventory Valuation · Slow-moving Analysis ·
Physical Count Variance · Inventory-to-Control Reconciliation · General Ledger ·
Trial Balance · Financial Statements (Inventory and Cost of Goods Sold).

## Pilot Status

**Implemented.** Receiving · outbound issue through sales and Goods Issue entry
points · transfer · adjustment · physical count · returns in both directions ·
Weighted Average, FIFO and Specific Identification · exact historical correction
· inventory/layer/control reconciliation at ₱0.00 · period close.

**Remaining work.** Full document conversion, broad module Product-DoD,
browser/UAT, hosted parity and certification evidence. Landed cost remains a
separate future capability.

**Pilot blockers.** All three costing methods are built, reachable, exercised
and proven locally for the intended current lifecycle. This is not module
certification or pilot readiness: hosted parity, browser/UAT, operated evidence
and the broader sales/purchasing workflows remain absent.

**Future enhancements.** Landed cost · stock reservation · negative-stock
enforcement beyond the sufficiency check · backdated-movement economic replay
through separately authorised IA-5/ECC work.

**Excluded scope.** Manufacturing, work orders and bills of material. Governed
economic-chronology costing (IA-5/ECC) is frozen and carries no readiness weight.

---

# 4. Record-to-Report (Accounting)

## Purpose

**Why the module exists.** Every operational act in Modules 1–3 must arrive in
one General Ledger, balanced, in the right period, attributable to the right
dimensions, and never editable after the fact — so that the financial statements
can be trusted and an auditor can trace any figure back to its source document.

**Business objective.** Produce a trial balance that balances and four financial
statements that are derived from posted data alone, with a period-close
discipline that stops the past from changing.

**Business owner.** Accounting Manager or Controller; the external auditor is the
ultimate consumer.

**Users involved.** Accountant · Controller · Auditor · Management.

**Departments involved.** Accounting / Finance; every operating department as a
source.

## End-to-End Flow

```
Source Documents from every module
(Sales, Purchasing, Inventory, Treasury)
                    ↓
            Posting Engine  (the single doorway)
                    ↓
       Accounting Kernel — Totality Guard
       (rejects every unsanctioned ledger write;
        survives a restore into a fresh database)
                    ↓
     Journal Entry + Journal Entry Lines
                    ↓
        ┌───────────┼─────────────┬──────────────┐
        ↓           ↓             ↓              ↓
   Manual JE   Recurring JE   Reversal JE   Opening Balance
   Implemented Implemented    Implemented   Implemented
        ↓           ↓             ↓              ↓
        └───────────┴─────────────┴──────────────┘
                    ↓
              General Ledger
                    ↓
        ┌───────────┴─────────────┐
        ↓                         ↓
  Subledgers                Account Detail Ledger
  (AR, AP, Inventory,             ↓
   Tax)                     Control Account
        ↓                   Reconciliation
        └───────────┬─────────────┘
                    ↓
              Trial Balance
                    ↓
              Period Close  (monthly / quarterly)
                    ↓
              Year-End Close  (rolls profit to retained earnings)
                    ↓
        ┌───────────┴─────────────┬──────────────┐
        ↓                         ↓              ↓
Financial Statements      Comparatives      Notes
(all four, from                                (structure only —
 governed configuration)                        no narrative)
                    ↓
              Compliance  (Module 5)
```

## Business Process Matrix

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Posting | Admit a source document to the ledger | System, on user action | Any posting document | Journal Entry | Balanced; open period; sanctioned source; dimensions valid | Per source document | Per source document | Creates the journal | Per source document | GL, trial balance, all downstream | The source document | Reverse or void the source | Posting event, journal, audit log | **Implemented** |
| Manual Journal Entry | Record an adjustment with no operational source | Accountant | — | Manual JE | At least two lines; balanced; open period; postable accounts | Yes | None | Direct GL entry | None unless tax accounts are used | GL, trial balance, statements | — | Reversal JE | Posting event, journal | **Implemented** |
| Recurring Journal | Repeat a standing entry | Accountant | Template | Journal Entry per run | Active template; open period | Yes | None | As the template defines | As the template defines | GL, trial balance | Manual JE | Reversal JE | Posting event | **Implemented** |
| Opening Balance | Bring balances in at cut-over | Accountant | Prior system | Opening journal | Balanced; governed cut-over | Yes | Establishes opening stock | Establishes opening balances | None | GL, trial balance, statements | — | **Governed reversal** | Posting event | **Implemented** |
| Reversal | Undo a posted entry without editing it | Accountant | Any posted journal | Reversal journal | Original posted; open period for the reversal date | Yes | Mirrors the original | Mirrors and negates the original | Reverses tax ledger rows where applicable | GL, trial balance, all downstream | The original document | Terminal | Posting event, reversal link | **Implemented** |
| Subledger maintenance | Keep AR, AP, inventory and tax positions | System | Posted journals | — (derived) | — | No | Derived | Derived | Derived | Customer/supplier ledgers, ageing, stock, tax ledger | — | Correct the source | Derived from posted data | **Implemented** |
| Trial Balance | Prove the ledger balances | Accountant | General Ledger | — (read-only) | Debits equal credits | No | None | None | None | Trial balance (unadjusted / adjusted / post-closing) | — | — | Derived | **Implemented** |
| Control Reconciliation | Prove each subledger equals its control account | Accountant | Subledger + GL | — (read-only) | Variance must be 0.00 | No | None | None | None | Control account reconciliation | — | — | Derived | **Implemented** for inventory, percentage tax, VAT and withholding |
| Period Close | Stop the past changing | Accountant | All posted documents | Period lock | Readiness checks; no unposted documents **not** currently detected | Yes | Blocks posting into the period | Blocks posting into the period | None | All period reports | — | Governed reopen | Period lock record | **Implemented** |
| Quarter Close | Freeze a quarter for compliance | Accountant | Period closes | — | The quarter's periods closed | Yes | None | None | Fixes the tax period for filing | Compliance working papers | Filing artifacts | Reopen the periods | Period lock records | **Implemented** |
| Year-End Close | Roll profit into equity | Accountant / Controller | Closed periods | Closing journal | Fiscal year's periods closed | Yes | None | Revenue and expense to retained earnings | None | Trial balance (post-closing), statements | — | **Governed reopen** with counter-posting | Posting event, journal | **Implemented** |
| Financial Statements | Present the results | Accountant / Management | Posted data + FS configuration | Four statements | Every account classified in the FS registry | No | None | None | None | Balance sheet, income statement, changes in equity, cash flows | Comparatives, notes | Correct the source | Derived from posted data | **Implemented** |
| Comparatives | Show the prior period beside the current | Accountant | Posted data | Comparative statements | Prior period exists | No | None | None | None | Comparative statements | Financial statements | — | Derived | **Implemented** |
| Notes | Disclose beyond the face of the statements | Accountant | Posted data | Note structure | — | No | None | None | None | Notes | Financial statements | — | Derived | **Implemented** (structure); narrative and signature block **Planned** — Backlog 18i |

## Detailed Step Discussion

### 4.1 Posting and the Accounting Kernel

**Purpose.** Ensure there is exactly one way into the General Ledger.

**Business rules.** Every posting document enters through the Posting Engine.
The **Accounting Kernel** is the totality guard inside it: it rejects any ledger
mutation that did not come through a sanctioned path — from a client, an RPC, a
helper, a migration, a replay, or a direct owner connection. Its enforcement is
structural rather than procedural: it survives a restore into a fresh database,
where deleting ledger rows in the restored copy is still rejected.

**Validations.** The journal must balance. The date must fall in an open fiscal
period. The source document type must be registered. Dimensions must be valid for
the company and branch.

**Posting behaviour.** One journal per posting act, linked back to its source
document, with a posting event recorded.

**What happens if reversed.** A reversal is a **new journal** that mirrors and
negates the original, linked to it. The original is never edited or deleted. This
is the single correction primitive the whole product shares.

### 4.2 Manual and recurring journal entries

A manual journal is the escape hatch for adjustments with no operational source —
accruals, reclassifications, corrections of prior judgement. It is governed like
any other posting: balanced, in an open period, to postable accounts, with an
audit trail.

Recurring journals generate the same entry from a template on a schedule the
accountant runs. They are **not** the Accounting Schedule Engine (Module 8): a
recurring journal repeats a fixed entry, while a schedule derives an amount from
a governed basis over time.

### 4.3 Period close, quarter close and year-end close

**Purpose.** Make the past stop changing, so a statement issued today still means
the same thing tomorrow.

**Business rules.** Closing a period locks it against further posting. Closing a
fiscal year additionally rolls revenue and expense balances into retained
earnings through a closing journal, so the post-closing trial balance shows only
balance-sheet accounts.

**Validations.** Readiness checks run before the close. **A known gap: close
readiness cannot currently see unposted documents**, so a period can be closed
while a draft invoice for that period still exists (Backlog 18h).

**What happens if reopened.** Reopening is governed and audited: it counter-posts
the closing journal through the Accounting Kernel rather than deleting it.

**A known limitation.** Retained earnings is maintained per fiscal year rather
than as a single cumulative account (Backlog 18g).

**Reports changed.** Every period-scoped report, the post-closing trial balance
and the statements.

### 4.4 Financial statements

**Purpose.** Present the company's position and performance.

**Business rules.** All four statements — balance sheet, income statement,
statement of changes in equity, and cash flows — are produced from **governed
configuration** (a financial-statement structure and an account-to-statement map)
through **one reporting entry point**. There is no second statement builder and
no browser-side aggregation.

Seeding a chart of accounts provisions its statement presentation with it, so a
company can never have accounts it cannot present.

**Known limitations.** Statement **re-presentation** — restating prior figures
after a reclassification — has no governed UI (Backlog 18f). Notes carry
structure but no narrative or signature block (Backlog 18i).

## Downstream Impact

```
Journal Entry
      ↓
General Ledger
      ↓
  ┌───┴─────────────┬──────────────────┬───────────────────┐
  ↓                 ↓                  ↓                   ↓
Trial Balance   Subledgers        Tax Ledger        Account Detail
  ↓             (AR/AP/Inv)            ↓             Ledger + Trace
  ↓                 ↓                  ↓                   ↓
Financial       Ageing and       Working Papers      Audit evidence
Statements      Control               ↓               and drill-down
  ↓             Reconciliation   Filing Artifacts
Comparatives          ↓                ↓
and Notes       Variance = 0.00    Export → Filed
  ↓
Management Reporting
(branch, department, cost centre through the Dimension Engine)
```

## Related Documents

```
Every posting document in Modules 1, 2, 3 and 6
                    ↓
              Journal Entry ◄──── Manual JE
                    ↓         ◄──── Recurring JE
                    ↓         ◄──── Opening Balance
                    ↓
              Reversal Journal
                    ↓
              Closing Journal (year end)
                    ↓
              Reopening counter-post
```

## Exception Scenarios

| Scenario | Behaviour | Status |
| --- | --- | --- |
| Posting into a closed period | Refused by the period lock | **Implemented** |
| Posting an unbalanced journal | Refused by the Posting Engine | **Implemented** |
| Direct ledger write bypassing the engine | Rejected by the Accounting Kernel, including after a restore | **Implemented** |
| Editing a posted journal | Impossible; correction is by reversal | **Implemented** |
| Reversing into a closed period | The reversal must fall in an open period | **Implemented** |
| Closing a period with unposted documents | Not detected by close readiness | **Planned** — Backlog 18h |
| Reopening a closed year | Governed counter-post of the closing journal | **Implemented** |
| Restating prior-period presentation | No governed re-presentation UI | **Planned** — Backlog 18f |
| Cumulative retained earnings across years | Retained earnings is per fiscal year | **Planned** — Backlog 18g |
| Note narrative and signatures | Structure exists; narrative does not | **Planned** — Backlog 18i |
| Multi-currency translation | Non-PHP fails closed | **Excluded** — PHP only |

## Internal Engines Used

Posting Engine **with the Accounting Kernel** · Chart of Accounts Engine ·
Dimension Engine · Period Lock and Closing Engine · Reversal, Void and Correction
Engine · Reporting and Reconciliation Engine · Number Series Engine (journal
numbering) · Audit and Immutability Engine · Permissions and RLS Engine ·
Attachment and Document Traceability Engine.

**Not used:** Tax Engine (accounting does not calculate tax; it records what the
Tax Engine decided) · Currency Engine · Accounting Schedule Engine (Module 8,
Future Priority).

## Accounting Truth

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The journal entry and its lines. Every report, subledger and statement is derived from them; none is an independent record. |
| **Posting Authority** | The Posting Engine is the only doorway; the Accounting Kernel enforces it structurally. |
| **Tax Authority** | Not held here. Accounting records the tax the Tax Engine determined. |
| **Inventory Authority** | Not held here. Accounting records the cost the shared costing path determined. |
| **Compliance Authority** | Not held here. See Module 5. |
| **Reporting Authority** | One financial-statement entry point over governed configuration. No parallel books, no browser aggregation. |

## Reports Updated

General Ledger · Account Detail Ledger · Trial Balance (unadjusted, adjusted,
post-closing) · Control Account Reconciliation · Balance Sheet · Income Statement ·
Statement of Changes in Equity · Statement of Cash Flows · Comparative Statements ·
Notes structure · Accounting Source · Accounting Trace · Posting and Reversal
review · Dimension summary (branch, department, cost centre).

## Pilot Status

**Implemented.** Posting through the single doorway with kernel enforcement ·
manual, recurring, opening-balance and reversal journals · subledgers · trial
balance · period, quarter and year-end close with governed reopen · all four
financial statements from governed configuration · comparatives · note structure ·
control reconciliations for inventory, percentage tax, VAT and withholding.

**Remaining work.** Close readiness that can see unposted documents (18h) ·
cumulative retained earnings (18g) · statement re-presentation (18f) · note
narrative and signature block (18i).

**Pilot blockers.** Posting invariants across every consumer are not yet proven,
and most critical reconciliations remain unevidenced. Closing a period while
unposted documents exist for it is possible today.

**Future enhancements.** Budgeting · management-reporting packs · the Accounting
Schedule Engine (Module 8).

**Excluded scope.** Multi-currency translation and FX revaluation · income-tax
provision and its deferred-tax consequences. See §0.5.

---

# 5. Compliance-to-Filing

## Purpose

**Why the module exists.** A Philippine business is judged by the BIR on what it
files. Every peso of output VAT, input VAT, percentage tax and withholding that
the operating modules generated must be assembled into statutory forms that
**agree with the General Ledger**, be reviewable by the accountant who signs
them, and be exportable in the format the Bureau expects.

**Business objective.** Produce statutory returns and listings that are derived
from the posted ledger, reconcile to the GL at zero variance, and cannot be
declared final while they disagree with the books.

**Business owner.** Compliance Officer or the accountant who signs the return;
the Accounting Manager owns the underlying ledger.

**Users involved.** Compliance officer · Accountant · Signing officer or
authorised representative · External auditor.

**Departments involved.** Compliance · Accounting / Finance.

## The governed compliance standard

Owner ruling, 2026-08-04. **Every** statutory output follows this chain, and no
stage may be skipped or duplicated:

```
Posted Transactions
        ↓
   Tax Engine        one calculator; decides VAT, percentage tax, ATC withholding
        ↓
   Tax Ledger        one row per tax code per document, stamped with the code
        ↓             version and rate in force on the document date
   Reconciliation    the ledger against the General Ledger
        ↓
   Working Paper     what the accountant reviews and signs off
        ↓
   Filing Artifact   THE SYSTEM OF RECORD for the return
        ↓
   Export            one consumer produces the file
        ↓
   Filed Record      the accountant's own submission, recorded after the fact
```

**One implementation per stage.** Extra faces are delegations, never second
implementations. Replacement is ordered — capability first, retirement second.
No orphans.

**Review Stage reads source data by design; Filing Stage is bound to the
artifact.** A reviewer may look at the underlying documents; a return, once
generated, states only what the artifact says.

## End-to-End Flow

```
Posted Sales, Purchasing and Payment documents
                    ↓
              Tax Ledger  (output VAT · input VAT · percentage tax ·
                           EWT payable · CWT receivable)
                    ↓
              Tax Review  (by kind, by period, by counterparty)
                    ↓
              GL Reconciliation  (must reach 0.00 variance)
                    ↓
      ┌─────────────┴──────────────┐
      ↓                            ↓
Reconciling Item             Working Paper
(a governed explanation      (the accountant's review sheet)
 for a line no ledger
 backs; excluded from
 every total structurally)
      └─────────────┬──────────────┘
                    ↓
              Filing Artifact  (draft)
              generated by ONE generator over ONE working
              paper and ONE reconciliation
                    ↓
              Review and correction
              (regenerate while draft)
                    ↓
              Filing Artifact  (final)
              REFUSED while the artifact disagrees with the GL
              Owner or admin authority required
                    ↓
              Export  (one consumer for every form)
                    ↓
              File with the BIR  —  OUTSIDE PXL
                    ↓
              Filing Artifact  (filed)
              records the accountant's own submission;
              PXL transmits nothing
```

## Business Process Matrix

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Tax capture | Record the tax each document generated | System, at posting | Sales Invoice, Cash Sale, Vendor Bill, Payment Voucher, Official Receipt, memos | Tax ledger rows | Tax code valid as of the document date | Per source document | None | None — the journal already carries the tax | Writes the tax ledger | Tax reviews | The source document | Void or reverse the source | Tax detail entries | **Implemented** |
| Tax Review | See what the period actually generated | Compliance officer | Tax ledger | — (read-only) | — | No | None | None | None | VAT review, EWT review, percentage-tax review, CWT review | Working paper | Correct the source | Derived | **Implemented** |
| Reconciliation | Prove the tax ledger agrees with the GL | Accountant | Tax ledger + GL | Reconciliation result | Variance computed per account | No | None | None | None | Reconciliation view | Working paper | Correct the source or add a reconciling item | Derived | **Implemented** |
| Reconciling Item | Explain a figure no ledger row backs | Accountant | — | Reconciling item | Reason and amount required | Yes | None | None | Excluded from every total **structurally** | Reconciliation, working paper | Filing artifact | Delete while draft | Governed record | **Implemented** |
| Working Paper | Give the signer something to review | Accountant | Tax ledger + reconciliation | Working paper | Period and company scoped | No | None | None | None | Working paper | Filing artifact | Regenerate | Derived | **Implemented** |
| Generate Filing Artifact | Build the return | Compliance officer | Working paper + reconciliation | Filing artifact (draft) | Registered form; period; company | No | None | None | Fixes what the return will say | Filing artifact | Working paper | Regenerate while draft | Artifact record | **Implemented** |
| Finalise | Declare the return ready | Signing officer | Filing artifact | Filing artifact (final) | **Refused while the artifact disagrees with the GL**; owner or admin authority | Yes | None | None | Locks the return's figures | Filing artifact | Export | Revert to draft where permitted | Artifact status change | **Implemented** |
| Export | Produce the file the Bureau expects | Compliance officer | Filing artifact (final) | Export file | Artifact final; export columns registered | No | None | None | None | Export register | Filed record | Re-export | Export snapshot keyed to the artifact | **Implemented** |
| File with the BIR | Submit the return | Signing officer | Export file | — | **Happens entirely outside PXL** | Yes | None | None | Discharges the obligation | — | Filed record | — | — | **Excluded from PXL** |
| Record as filed | Record that a submission was made | Compliance officer | The accountant's own submission | Filing artifact (filed) | Artifact final | Yes | None | None | None | Filing register | — | Amend | Artifact status change | **Implemented** |

## Registered statutory artifacts

Six forms are registered and generate from the posted ledger through the single
governed chain. **A new form is a seed row, not a new engine.**

| Form | Kind | Period | Statutory basis | Deadline rule | Status |
| --- | --- | --- | --- | --- | --- |
| **2550Q** — Quarterly Value-Added Tax Return | Return | Quarterly | NIRC Sec. 114 | 25th day following the close of the quarter | **Implemented** |
| **2551Q** — Quarterly Percentage Tax Return | Return | Quarterly | NIRC Sec. 116 / 128 | 25th day following the close of the quarter | **Implemented** |
| **1601EQ** — Quarterly Remittance Return of Creditable Income Taxes Withheld (Expanded) | Return | Quarterly | NIRC Sec. 58 | Last day of the month following the close of the quarter | **Implemented** |
| **SLSP** — Summary List of Sales and Purchases | Listing | Quarterly | RR 1-2012 | 25th day following the close of the quarter | **Implemented** |
| **SAWT** — Summary Alphalist of Withholding Taxes | Listing | Quarterly | RR 2-98 as amended | Attached to the quarterly or annual income tax return | **Implemented** |
| **QAP** — Quarterly Alphalist of Payees | Listing | Quarterly | RR 2-98 as amended | Attached to the 1601EQ, due the last day of the month following the close of the quarter | **Implemented** |

**Not registered and Excluded:** 1601FQ, 2306, 2316, and every income-tax form.
See §0.5. Two hand-keyed FWT prototype screens exist outside the current product
and carry no architecture, pilot or readiness weight.

## Detailed Step Discussion

### 5.1 The tax ledger

**Purpose.** Be the one place that knows what tax every posted document
generated.

**Business rules.** One row per tax code per document, carrying the tax kind
(output VAT, input VAT, percentage tax, EWT payable, CWT receivable), the base,
the rate, the amount, the counterparty and TIN where the form needs it, and the
**version of the tax code that priced it**. A document keeps the rate that priced
it forever; a later statutory change never rewrites history.

**Posting behaviour.** The tax ledger is written as part of the posting act, not
afterwards, so a posted document and its tax are never out of step.

**What happens if the source is voided or reversed.** The tax ledger rows are
reversed with it.

### 5.2 Reconciliation and Reconciling Items

**Purpose.** Prove that what the return will say agrees with the books.

**Business rules.** The reconciliation compares the tax ledger against the
General Ledger accounts that carry the same tax. **A return may not be marked
final while the two disagree.** That refusal is the central compliance control in
the product.

Where a legitimate figure has no ledger row behind it, the accountant records a
governed **Reconciling Item** with a reason. It is **excluded from every total
structurally**, not by convention — so it can explain a difference without ever
silently becoming part of the return.

### 5.3 Working paper and filing artifact

**Purpose.** Separate what the accountant reviews from what the company files.

**Business rules.** The **Filing Artifact is the system of record**. Once
generated, the return states what the artifact says — not what a screen
recomputes. This is what makes a filed return reproducible months later.

An artifact moves `draft → final → filed`:
- **draft** — regenerate freely as source corrections land.
- **final** — figures locked; requires owner or admin authority; **refused while
  the artifact disagrees with the GL**.
- **filed** — records that the accountant submitted it. **PXL transmits nothing.**

### 5.4 Export

One consumer produces the export file for every registered form, from the
artifact, with the export snapshot keyed to that artifact. There is no per-form
export implementation.

### 5.5 What compliance does not do

- **PXL does not file.** There is no BIR transmission, no eFPS or eBIRForms
  integration, and none is planned in current scope.
- **PXL does not compute income tax.** Income tax in all its forms is Excluded.
- **CAS registration with the BIR is absent.** The product maintains CAS
  evidence — document number issuance, void events, period evidence — but is not
  a registered Computerised Accounting System.

## Downstream Impact

```
Posted document
      ↓
Tax Engine  →  Tax Ledger row (stamped with the tax-code version)
                      ↓
              ┌───────┴────────┐
              ↓                ↓
        Tax Reviews      GL Reconciliation
              ↓                ↓
              └───────┬────────┘
                      ↓
                Working Paper
                      ↓
                Filing Artifact  ──►  Artifact Lines
                      ↓                     ↓
                   Export             Trace to the
                      ↓               source document
                Export Snapshot
                (keyed to the artifact)
                      ↓
                Filed Record
                      ↓
                Filing Register / BIR deadline monitoring
```

## Related Documents

```
Sales Invoice / Cash Sale ──► output VAT ──► 2550Q
                          └─► percentage tax ──► 2551Q
                          └─► sales side ──► SLSP

Vendor Bill / Cash Purchase ──► input VAT ──► 2550Q
                            └─► purchase side ──► SLSP
                            └─► EWT accrued ──► 1601EQ ──► QAP ──► 2307 issued

Payment Voucher ──► EWT withheld ──► 1601EQ ──► QAP ──► 2307 issued

Withholding Remittance ──► settles EWT Payable ──► 1601EQ (remitted prior)

Official Receipt ──► CWT receivable ──► SAWT ──► 2307 received
```

## Exception Scenarios

| Scenario | Behaviour | Status |
| --- | --- | --- |
| Artifact disagrees with the GL | Cannot be marked final | **Implemented** |
| A figure with no ledger row behind it | Governed Reconciling Item, structurally excluded from totals | **Implemented** |
| Source document corrected after the artifact was generated | Regenerate while draft | **Implemented** |
| Source document corrected after the artifact was finalised | Amend; the artifact is the record of what was filed | **Implemented** (status); amendment workflow **Planned** |
| Statutory rate change mid-period | Tax-code succession; each document keeps its own rate | **Implemented** |
| A form the BIR revises | A new form is a seed row over the same engine | **Implemented** |
| Filing the return | Happens outside PXL | **Excluded** |
| Amended return after filing | An `amended` filing status exists | **Implemented** (status); workflow **Planned** |
| Percentage tax on a return or collection basis | See Module 1 exceptions | **Planned** — Backlog 8b |
| Tax-code maintenance before a real rate change | Governed succession maintenance | **Implemented** |
| Deprecating a withdrawn BIR code | No governed deprecation setter exists | **Planned** — Backlog 10b |
| CAS registration with the BIR | Not a registered CAS | **Future** |
| Final Withholding Tax, income tax, and all related forms | Not part of the governed chain | **Excluded** |

## Internal Engines Used

Tax Engine · Posting Engine boundary (compliance reads the ledger, never writes
it) · Number Series Engine · Audit and Immutability Engine · Permissions and RLS
Engine · Reporting and Reconciliation Engine · Period Lock and Closing Engine ·
Attachment and Document Traceability Engine.

**Not used:** Inventory Accounting Engine · Currency Engine · Document Conversion
Engine.

## Accounting Truth

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The posted ledger. Compliance derives; it never originates a figure. |
| **Posting Authority** | Not held here. Compliance does not post; it reads. |
| **Tax Authority** | The Tax Engine for arithmetic; the tax ledger for what was generated; the tax-code version in force on the document date for the rate. |
| **Inventory Authority** | Not held here. |
| **Compliance Authority** | **The Filing Artifact is the system of record.** A return says what its artifact says. |
| **Reporting Authority** | One generator, one working paper, one reconciliation, one export consumer. No browser-side aggregation of a compliance figure. |

## Reports Updated

Output VAT review · Input VAT review · Percentage Tax review · EWT review · CWT
review · Tax-ledger-to-GL reconciliation · Working papers (all forms) · Filing
artifacts and their lines · Export register · Filing register and BIR deadline
monitoring · Books of account (Sales Journal, Purchase Journal, Cash Receipts,
Cash Disbursements, General Journal, General Ledger) · SLSP · SAWT · QAP · Form
2307 issued and received.

## Pilot Status

**Implemented.** The full governed chain for six forms — tax capture, review,
reconciliation, reconciling items, working paper, artifact generation,
finalisation refused on disagreement with the GL, export, and filed record.
Governed tax-code maintenance with statutory succession.

**Remaining work.** Governed deprecation of withdrawn codes (10b) · the three
percentage-tax boundaries (8b) · an effective-dated company tax profile (11) ·
the amendment workflow beyond the status.

**Pilot blockers.** **Nothing has ever been filed with the Bureau.** PXL is not a
registered CAS. Do not claim filing readiness.

**Future enhancements.** BIR transmission · eFPS or eBIRForms integration · CAS
registration.

**Excluded scope.** Final Withholding Tax and 1601FQ / 2306 · Form 2316 · income
tax in every form · MCIT · RCIT · NOLCO · OSD · FBT · transfer pricing ·
consolidation tax · specialised-industry tax features. See §0.5.

---

# 6. Banking & Treasury  — 🔮 **Future Priority**

> **Status.** This module is **not started**. Its screens exist as a skeleton and
> its posting functions are defined, but **only bank accounts hold data**; no
> treasury document has ever produced a journal. It is the **first ranked future
> priority** after the current compliance work, ahead of Fixed Assets, and it is
> **not authorised to start**. The lifecycle below is the intended direction, not
> a description of working software. The single carve-out is the **Check
> Voucher**, which the Delivery Plan separates out because the Cash Disbursements
> Book depends on it.

## Purpose

**Why the module will exist.** Cash is the account an SME owner watches daily and
the one an auditor tests hardest. Treasury exists to prove that the cash in the
books equals the cash in the bank.

**Business objective.** Control and reconcile every peso of cash and bank
movement, and produce the Cash Disbursements and Cash Receipts books the BIR
expects.

**Business owner.** Treasurer or Finance Manager; the Accounting Manager owns the
reconciliation.

**Users involved.** Treasurer · Disbursing officer · Cashier · Petty cash
custodian · Accountant · Auditor.

**Departments involved.** Treasury · Accounting / Finance.

## End-to-End Flow (intended)

```
Bank and Cash Account Setup  (Implemented — the only part holding data)
                    ↓
        ┌───────────┼──────────────┬─────────────────┐
        ↓           ↓              ↓                 ↓
   Receipts    Disbursements   Fund Transfer    Petty Cash
   (Module 1)  (Module 2)      between own      Voucher
        ↓       Check Voucher   accounts             ↓
        ↓       (Future             ↓          Replenishment
        ↓        Priority)          ↓                ↓
        └───────────┴──────────────┴─────────────────┘
                    ↓
              Bank Adjustment  (fees, interest, corrections)
                    ↓
              Bank Reconciliation
              (book cash vs. bank statement)
                    ↓
        ┌───────────┴──────────────┐
        ↓                          ↓
  Outstanding Cheques      Deposits in Transit
        └───────────┬──────────────┘
                    ↓
              Bank-to-GL Reconciliation
                    ↓
              Period Close → Financial Statements
```

## Business Process Matrix (intended lifecycle)

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Bank / cash account setup | Define where money sits | Treasurer | — | Bank Account | Linked to a GL account | Governed maintenance | None | None | None | Bank position | All treasury documents | Governed edit | Change log | **Implemented** |
| Check Voucher | Pay by cheque with an instrument lifecycle | Treasury | Vendor Bill | Check Voucher | Bank account, payee, cheque number, open period | Yes | None | DR Accounts Payable / CR Bank | EWT as Payment Voucher | Check register, outstanding cheques, Cash Disbursements Book | Payment Voucher | Cancel | Posting event | **Future Priority** |
| Fund Transfer | Move money between own accounts | Treasurer | — | Fund Transfer | Two accounts; open period | Yes | None | DR receiving account / CR sending account | None | Bank position | Inter-Branch Transfer | Cancel | Posting event | **Future** |
| Petty Cash Voucher | Record a small disbursement | Custodian | — | Petty Cash Voucher | Fund, expense account, open period | Yes | None | DR Expense / CR Petty Cash | Input VAT where receipted | Petty cash position | Replenishment | Cancel | Posting event | **Future** |
| Petty Cash Replenishment | Top the fund back up | Custodian / Treasury | Approved vouchers | Replenishment | Approved vouchers; cash source | Yes | None | DR Petty Cash / CR Bank | None | Petty cash position, Cash Disbursements Book | Petty Cash Voucher | Cancel | Posting event | **Future** |
| Bank Adjustment | Record fees, interest and corrections | Treasury / Accountant | Bank statement | Bank Adjustment | Bank account, type, open period | Yes | None | DR or CR Bank against income or expense | Input VAT on bank charges where applicable | Bank position, GL | Bank Reconciliation | Cancel | Posting event | **Future** |
| Bank Reconciliation | Prove book cash equals bank cash | Accountant | Bank statement + posted cash journals | Reconciliation | Statement items matched or explained | Yes | None | None — reconciliation explains, it does not post | None | Bank reconciliation, outstanding cheques, deposits in transit | Bank Adjustment | Re-reconcile | Reconciliation record | **Future** |

## Detailed Step Discussion (intended)

Each treasury document is intended to follow the same governed shape every
posting document in Modules 1–4 already follows: a draft the user can correct, a
posting act through the single Posting Engine doorway, immutability once posted,
and correction by governed cancellation or reversal rather than editing.

**Bank Reconciliation is deliberately not a posting document.** It explains the
difference between the book and the statement; anything that must change the
books does so through a Bank Adjustment, which posts. This keeps the
reconciliation a piece of evidence rather than a second way into the ledger.

**Check Voucher** is the exception to this module's deferral because the **Cash
Disbursements Book** — a BIR book of account — cannot be complete without cheque
disbursements. Its intended lifecycle is: draft → posted → released → cleared,
with a `stale` state for a cheque that ages out unpresented, and a governed
cancellation at any point before clearing.

## Downstream Impact (intended)

```
Treasury document ──► Posting Engine ──► Kernel ──► Journal Entry
                                                          ↓
                                                    General Ledger
                                                          ↓
                                              ┌───────────┴───────────┐
                                              ↓                       ↓
                                        Cash position          Trial Balance
                                        Bank reconciliation          ↓
                                        Cash Disbursements    Financial
                                        Cash Receipts books    Statements
```

## Related Documents (intended)

```
Vendor Bill ──► Payment Voucher ──► Check Voucher ──► cheque cleared
Sales Invoice ──► Official Receipt ──► deposit
Bank Account ◄── Fund Transfer ──► Bank Account
Petty Cash Voucher ──► Petty Cash Replenishment
Bank Statement ──► Bank Adjustment ──► Bank Reconciliation
```

## Exception Scenarios (intended)

| Scenario | Intended behaviour | Status |
| --- | --- | --- |
| Cheque issued but not presented | Appears as an outstanding cheque | **Future Priority** |
| Cheque stale after the statutory period | A `stale` state, reversing the disbursement | **Future Priority** |
| Cheque cancelled before release | Governed cancellation; the number is voided, never reused | **Future Priority** |
| Deposit not yet credited by the bank | Appears as a deposit in transit | **Future** |
| Bank fee not in the books | Recorded by Bank Adjustment | **Future** |
| Bounced customer cheque | Already handled by the receipt `bounced` state | **Implemented** (Module 1) |
| Petty cash shortage at count | Recorded as an expense or receivable from the custodian | **Future** |
| Reconciliation that will not balance | Explained by reconciling items, never forced | **Future** |

## Internal Engines Used (intended)

Posting Engine (with the Accounting Kernel) · Payment and Application Engine ·
Number Series Engine · Chart of Accounts Engine · Dimension Engine · Period Lock
and Closing Engine · Reversal, Void and Correction Engine · Audit and
Immutability Engine · Permissions and RLS Engine · Reporting and Reconciliation
Engine.

**No new engine is required for this module.** If building it appears to need
one, that is a signal to re-examine the design, not to add an engine.

## Accounting Truth (intended)

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The posted journal entry; the bank statement is external evidence, not a book. |
| **Posting Authority** | The Posting Engine, as everywhere else. |
| **Tax Authority** | The Tax Engine, for input VAT on bank charges. |
| **Inventory Authority** | Not applicable. |
| **Compliance Authority** | The Cash Receipts and Cash Disbursements books derive from posted cash movement. |
| **Reporting Authority** | Posted data; a reconciliation explains a difference and never restates the ledger. |

## Reports Updated (intended)

Bank Position · Check Register · Outstanding Cheques · Deposits in Transit ·
Bank Reconciliation · Petty Cash Position · Cash Receipts Book · Cash
Disbursements Book · General Ledger · Trial Balance · Financial Statements ·
Bank-to-GL Reconciliation.

## Pilot Status

**Implemented.** Bank and cash account master data only.

**Remaining work.** The entire module.

**Pilot blockers.** None for the pilot as scoped — Banking & Treasury is v2 by
Delivery Plan decision. A pilot client that needs treasury is a reason to
schedule the module deliberately, not a reason to call PXL unready.

**Future Priority.** This module is **first** in the ranked future priorities.
**Check Voucher** is carved out ahead of the rest for the Cash Disbursements Book.

**Excluded scope.** Foreign-currency bank accounts · investment and loan
instruments · cash-flow forecasting.

---

# 7. Fixed Assets  — 🔮 **Future Priority**

> **Status.** This module is **not started**. Its screens exist as a skeleton;
> **every fixed-asset table is empty**, several routes are on the deferred list,
> and there is no depreciation-profile master. It is the **second ranked future
> priority**, after Banking & Treasury, and is **not authorised to start**. The
> lifecycle below is the intended direction only. The Delivery Plan carves out a
> possible **minimal straight-line depreciation run** if a pilot client holds
> assets.

## Purpose

**Why the module will exist.** An SME that owns equipment must capitalise it,
depreciate it over its useful life, and account for what happens when it is
transferred, impaired or sold — with a register that ties to the General Ledger.

**Business objective.** Maintain an asset register that agrees with the books,
and post depreciation on a governed schedule rather than by hand.

**Business owner.** Accounting Manager or Controller.

**Users involved.** Accountant · Asset custodian · Auditor.

**Departments involved.** Accounting / Finance; the custodian's department.

## End-to-End Flow (intended)

```
Asset Category Setup  (with a depreciation profile — the master that does not exist)
                    ↓
              Acquisition
              (from a Vendor Bill, a Cash Purchase, or a manual entry)
                    ↓
              Recognition / Capitalisation
              (asset enters the register at cost)
                    ↓
              Depreciation Run  (periodic, per schedule)
                    ↓
        ┌───────────┼──────────────┬─────────────────┐
        ↓           ↓              ↓                 ↓
    Transfer    Impairment     Revaluation       Disposal
    (custody    (write down)   (Future)          (sale, scrap,
     or branch)                                   write-off)
        └───────────┴──────────────┴─────────────────┘
                    ↓
              Asset Register ↔ GL Reconciliation
                    ↓
              Period Close → Financial Statements
```

## Business Process Matrix (intended lifecycle)

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Asset category setup | Group assets and set their depreciation basis | Accountant | — | Asset Category | Asset, accumulated-depreciation and expense accounts; useful life; method | Governed maintenance | None | None | None | Asset register | All asset documents | Governed edit | Change log | **Future** — depreciation-profile master absent |
| Acquisition | Bring an owned asset onto the books | Accountant | Vendor Bill, Cash Purchase | Fixed Asset record | Category, cost, acquisition date | Yes | None — an asset is not stock | DR Fixed Asset / CR Payable, Cash or Clearing | Input VAT on the purchase | Asset register, GL | Vendor Bill | Reverse the acquisition | Posting event | **Future** |
| Recognition | Start the asset's depreciable life | Accountant | Fixed Asset record | Depreciation schedule | In-service date; useful life | Yes | None | None on its own | None | Asset register, depreciation schedule | Depreciation Run | Re-derive the schedule | Schedule record | **Future** |
| Depreciation Run | Charge the period's depreciation | Accountant | Active assets | Depreciation entries | Open period; assets in service | Yes | None | DR Depreciation Expense / CR Accumulated Depreciation | None — book depreciation only | Asset register, depreciation schedule, GL, statements | Period close | Reverse the run | Posting event | **Future** — a minimal straight-line run is the Delivery Plan carve-out |
| Transfer | Move an asset between custodians or branches | Accountant | — | Asset Transfer | Destination; open period | Yes | None | Reclassification within the register and dimensions | None | Asset register | — | Reverse | Posting event | **Future** |
| Impairment | Write an asset down below carrying value | Accountant / Controller | Impairment assessment | Impairment record | Reason; amount; open period | Yes | None | DR Impairment Loss / CR Accumulated Impairment | None in current scope | Asset register, GL, statements | — | Reverse | Posting event | **Future** |
| Disposal | Sell, scrap or write off an asset | Accountant | Sale document or scrap authority | Disposal record | Active asset; disposal date; proceeds if any | Yes | None | Derecognises cost and accumulated depreciation; recognises gain or loss | Output VAT where the disposal is a sale | Asset register, disposal report, GL, statements | Sales Invoice | Reverse | Posting event | **Future** |
| Register reconciliation | Prove the register equals the GL | Accountant | Asset register + GL | — (read-only) | Variance must be 0.00 | No | None | None | None | Asset-register-to-GL reconciliation | — | — | Derived | **Future** |

## Detailed Step Discussion (intended)

**The missing master.** No depreciation-profile master exists. Until one does,
useful life, method and salvage value have nowhere governed to live, and a
depreciation run cannot be derived — only hand-entered. This is the first thing
the module needs, ahead of any screen.

**Book versus tax depreciation.** The intended scope is **book depreciation
only**. Tax depreciation and the book-to-tax reconciliation belong with income
tax, which is **Excluded** (§0.5). A module that computed tax depreciation would
be reaching into excluded scope.

**Correction discipline.** As everywhere else, a posted depreciation entry is
never edited. A wrong run is reversed and re-run.

## Downstream Impact (intended)

```
Asset document ──► Posting Engine ──► Kernel ──► Journal Entry
                                                        ↓
                                                  General Ledger
                                                        ↓
                                    ┌───────────────────┴─────────────┐
                                    ↓                                 ↓
                            Asset Register                    Trial Balance
                            Depreciation Schedule                    ↓
                                    ↓                        Financial Statements
                        Asset-Register-to-GL                 (Property, Plant and
                        Reconciliation                        Equipment; Depreciation
                                                              Expense)
```

## Related Documents (intended)

```
Vendor Bill / Cash Purchase ──► Fixed Asset Acquisition
                                        ↓
                                  Recognition
                                        ↓
                                  Depreciation Run  (recurring)
                                        ↓
                    ┌───────────────────┼──────────────────┐
                    ↓                   ↓                  ↓
              Asset Transfer      Impairment          Disposal
                                                          ↓
                                                    Sales Invoice
                                                    (where sold)
```

## Exception Scenarios (intended)

| Scenario | Intended behaviour | Status |
| --- | --- | --- |
| Asset acquired mid-period | Depreciation prorated from the in-service date | **Future** |
| Asset fully depreciated but still in use | Stays in the register at nil net book value | **Future** |
| Asset disposed mid-period | Depreciation to the disposal date, then derecognition | **Future** |
| Asset sold at a gain or loss | Gain or loss recognised on disposal | **Future** |
| Asset scrapped with no proceeds | Full remaining net book value written off | **Future** |
| Asset impaired then recovers | Reversal of impairment | **Future** |
| Depreciation run posted twice | Must be idempotent, as every other posting act is | **Future** |
| Asset transferred between branches | Reclassification across dimensions, not a disposal | **Future** |
| Component or part-asset depreciation | Componentisation | **Future** |
| Revaluation model | Carrying amount restated to fair value | **Future** |
| Tax depreciation and book-to-tax reconciliation | Belongs with income tax | **Excluded** |

## Internal Engines Used (intended)

Posting Engine (with the Accounting Kernel) · Chart of Accounts Engine ·
Dimension Engine · Period Lock and Closing Engine · Reversal, Void and Correction
Engine · Audit and Immutability Engine · Permissions and RLS Engine · Reporting
and Reconciliation Engine · **Accounting Schedule Engine** (Module 8) for the
depreciation schedule itself.

## Accounting Truth (intended)

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The posted journal entry; the asset register is a derived view that must tie to it. |
| **Posting Authority** | The Posting Engine. |
| **Tax Authority** | The Tax Engine for input VAT on acquisition and output VAT on disposal. Tax depreciation is Excluded. |
| **Inventory Authority** | Not applicable — an asset is not stock. |
| **Compliance Authority** | Statement presentation only. |
| **Reporting Authority** | Posted data. |

## Reports Updated (intended)

Asset Register · Depreciation Schedule · Asset Transfer log · Disposal Report ·
Asset-Register-to-GL Reconciliation · General Ledger · Trial Balance · Financial
Statements (Property, Plant and Equipment; Depreciation Expense).

## Pilot Status

**Implemented.** Nothing. Every fixed-asset table is empty.

**Remaining work.** The entire module, beginning with the depreciation-profile
master.

**Pilot blockers.** None for the pilot as scoped — Fixed Assets is v2 by Delivery
Plan decision.

**Future Priority.** **Second**, after Banking & Treasury. A minimal
straight-line depreciation run is the Delivery Plan carve-out if the pilot client
holds assets.

**Excluded scope.** Tax depreciation and book-to-tax reconciliation · revaluation
model · componentisation · lease accounting.

---

# 8. Accounting Schedule Engine  — 🔮 **Future Priority**

> **Status.** **Not started.** Posting functions and schedule tables exist for
> amortisation and revenue recognition, and both are registered posting source
> types, but **no schedule has ever been created and no schedule entry has ever
> posted**. The Product Architecture records Accounting Schedules as *Not
> Started*. The lifecycle below is the intended direction only.

## Purpose

**Why the engine will exist.** Several accounting obligations are not events but
**patterns over time**: prepaid insurance consumed monthly, deferred revenue
earned as a service is delivered, an accrual raised at period end and reversed at
the start of the next. Today each is a manual journal the accountant must
remember. A schedule turns a remembered obligation into a derived one.

**Business objective.** Derive periodic entries from a governed basis, so that
the pattern is stated once and the entries follow — reviewable, reversible and
impossible to forget.

**Business owner.** Accounting Manager or Controller.

**Users involved.** Accountant · Controller · Auditor.

**Departments involved.** Accounting / Finance.

## Intended lifecycle

```
Schedule Definition
(basis amount · start and end · periodicity · source and target accounts)
                    ↓
              Schedule Derivation
              (the full future entry set, derived once and reviewable)
                    ↓
              Period Run
              (the accountant runs the period; entries post through the
               single Posting Engine doorway)
                    ↓
        ┌───────────┴──────────────┐
        ↓                          ↓
  Schedule continues        Schedule cancelled
  to the next period        (remaining entries never post;
        ↓                    posted entries stay posted)
        ↓                          ↓
        └───────────┬──────────────┘
                    ↓
              Schedule Completion
                    ↓
              Period Close → Financial Statements
```

## Intended schedule types

| Schedule type | Business purpose | Intended posting | Status |
| --- | --- | --- | --- |
| **Depreciation** | Charge an asset's cost over its useful life | DR Depreciation Expense / CR Accumulated Depreciation | **Future Priority** — belongs to Module 7 |
| **Amortisation** | Consume a prepaid or deferred cost | DR Expense / CR Prepaid Asset | **Future Priority** — function and table exist; never exercised |
| **Deferred Revenue** | Hold consideration received before it is earned | DR Cash or AR / CR Deferred Revenue at receipt | **Future Priority** |
| **Revenue Recognition** | Earn deferred revenue over the service period | DR Deferred Revenue / CR Revenue | **Future Priority** — function and table exist; never exercised |
| **Accrual** | Recognise an expense incurred but not yet billed | DR Expense / CR Accrued Liability | **Future Priority** |
| **Auto Reversal** | Reverse an accrual automatically at the start of the next period | The mirror of the accrual | **Future Priority** |

## Business Process Matrix (intended lifecycle)

| Step | Business Purpose | Primary User | Source Documents | Documents Produced | Validations | Approval Required | Inventory Impact | Accounting Impact | Tax Impact | Reports Updated | Related Documents | Correction Path | Audit Trail | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Define a schedule | State the pattern once | Accountant | Vendor Bill, Sales Invoice, Fixed Asset, or manual basis | Schedule | Basis amount; start and end; periodicity; source and target accounts | Yes | None | None at definition | None | Schedule register | The source document | Cancel while entries remain unposted | Schedule record | **Future Priority** |
| Derive the entries | Make the future visible before it happens | System | Schedule | Derived entry set | Amounts sum to the basis exactly | No | None | None until run | None | Schedule detail | — | Re-derive while unrun | Derivation record | **Future Priority** |
| Run a period | Post the period's entry | Accountant | Schedule | Journal Entry | Open period; entry not already posted | Yes | None | Per schedule type | None | GL, trial balance, statements | — | Reverse the entry | Posting event | **Future Priority** |
| Cancel a schedule | Stop a pattern that no longer applies | Accountant | Schedule | — | Unposted entries only | Yes | None | Posted entries stay posted | None | Schedule register | — | Terminal | Cancellation record | **Future Priority** |
| Auto-reverse an accrual | Undo an estimate when the real document arrives | System, on the accountant's run | Accrual schedule | Reversal journal | Next period open | Yes | None | Mirrors the accrual | None | GL, trial balance | Vendor Bill | Reverse | Posting event | **Future Priority** |

## Detailed discussion (intended)

**A schedule derives; it does not decide.** The basis amount comes from a source
document or an explicit entry by the accountant. The schedule's job is to spread
it, not to invent it.

**Derived entries must sum to the basis exactly.** Rounding is settled inside the
schedule — typically in the final period — so a schedule never leaves a residual
centavo in a deferral account.

**A schedule never bypasses the Posting Engine.** Each period's entry is an
ordinary posting act through the single doorway, subject to the period lock and
the Accounting Kernel like everything else.

**Cancellation is forward-only.** Cancelling a schedule stops future entries. It
never unposts what has already posted; those are corrected by reversal, as
everywhere else in the product.

**This engine is distinct from recurring journals.** A recurring journal repeats
a **fixed** entry the accountant wrote. A schedule **derives** each entry from a
basis and a pattern, and knows when it is finished.

## Downstream Impact (intended)

```
Schedule Definition
        ↓
Derived Entry Set  (visible before anything posts)
        ↓
Period Run ──► Posting Engine ──► Kernel ──► Journal Entry
                                                  ↓
                                            General Ledger
                                                  ↓
                                    ┌─────────────┴──────────────┐
                                    ↓                            ↓
                            Trial Balance              Deferral / Accrual
                                    ↓                  account balances
                            Financial Statements              ↓
                                                       Schedule-to-GL
                                                       reconciliation
```

## Exception Scenarios (intended)

| Scenario | Intended behaviour | Status |
| --- | --- | --- |
| Basis amount changes after entries have posted | Terminate the schedule and define a successor for the remainder | **Future Priority** |
| Schedule cancelled mid-life | Future entries never post; posted entries stay posted | **Future Priority** |
| Period run twice | Idempotent — one entry per period | **Future Priority** |
| Period run into a closed period | Refused by the period lock | **Future Priority** |
| Rounding residual | Settled in the final period so the deferral clears exactly | **Future Priority** |
| Accrual reversed by an arriving invoice | Auto-reversal at the start of the next period | **Future Priority** |
| Schedule spanning a year-end close | Continues; the close does not interrupt it | **Future Priority** |

## Internal Engines Used (intended)

Posting Engine (with the Accounting Kernel) · Chart of Accounts Engine ·
Dimension Engine · Period Lock and Closing Engine · Reversal, Void and Correction
Engine · Audit and Immutability Engine · Permissions and RLS Engine · Reporting
and Reconciliation Engine.

**Consumed by:** Fixed Assets (Module 7) for depreciation; Accounting (Module 4)
for amortisation, deferrals and accruals; Sales (Module 1) for revenue
recognition on service contracts.

## Accounting Truth (intended)

| Authority | Holder |
| --- | --- |
| **Source of Truth** | The posted journal entry. A schedule is a plan; only its posted entries are books. |
| **Posting Authority** | The Posting Engine. A schedule never writes the ledger directly. |
| **Tax Authority** | Not applicable — schedule entries carry no tax in intended scope. |
| **Inventory Authority** | Not applicable. |
| **Compliance Authority** | Statement presentation only. |
| **Reporting Authority** | Posted entries; the unrun remainder is a forecast, never a book figure. |

## Reports Updated (intended)

Schedule Register · Schedule Detail and remaining balance · Deferred Revenue
ageing · Prepaid amortisation schedule · Accrual register · General Ledger ·
Trial Balance · Financial Statements.

## Pilot Status

**Implemented.** Nothing. No schedule has ever been created; no schedule entry
has ever posted.

**Remaining work.** The entire engine.

**Pilot blockers.** None for the pilot as scoped.

**Future Priority.** Sequenced with Fixed Assets, which depends on it for
depreciation.

**Excluded scope.** Lease accounting schedules · income-tax-driven deferrals ·
any schedule whose basis is an excluded capability.

---

# 9. Repository / Documentation Alignment Notes

Contradictions and gaps found **while writing or reconciling this blueprint**,
between what the repository does today and what the governing documentation
says. Rows retain the discovery and record when a later package closes it.

Each row states the current implementation, what this blueprint expected, a
recommendation, and a priority. Priority is this document's assessment only and
does **not** alter any backlog priority.

| # | Subject | Current implementation | Blueprint expectation | Recommendation | Priority |
| --- | --- | --- | --- | --- | --- |
| 1 | Delivery Receipt cancellation | Implemented 2026-08-07 (Backlog 18c): a posted delivery reverses its journal and restocks the goods | Product Architecture now records the governed correction path | Preserve the committed lifecycle regression | **Reconciled 2026-08-08** |
| 2 | Filing artifacts | Six forms generate, reconcile, finalise and export through one governed chain | The Product Architecture §3.13 **Compliance master-data row** states *"The central Tax Engine exists; the filing artifacts do not."* This contradicts the Compliance maturity row **in the same table**, which describes the filing artifact engine as existing | Correct the master-data cell; the two cells cannot both be true | **Medium** — an internal contradiction inside one table is a trap for a reader who stops at the first cell |
| 3 | Period close | Period close, year-end rollforward and comparatives shipped 2026-08-03 | The Product Architecture §3.13 Sales row still names *"Period close absent (nothing rolls profit into retained earnings)"* as a current blocker | Refresh with note 1 | Low — documentation lag only |
| 4 | Posting entry points exercised | `AI/AI_STATE.md` reports 15 of 24 exercised | The Product Architecture §4.0 engine register reports *"12 have ever produced a journal"*, measured 2026-08-02 | None required — the register cell is explicitly dated and `AI_STATE` is the single status authority. Recorded only so a reader is not misled by the older figure | Low — by design |
| 5 | **Receiving Report had no governed reversal** | **Closed 2026-08-08 (PXL-AUD-077 / Backlog 18k).** `fn_void_receiving_report` and the Receiving Reports action reverse a safe receipt after live bills and downstream allocations are corrected | A received report that increased stock and posted a journal needs a governed, reachable correction path | Preserve exact source-layer dependency ordering for all three costing methods | **Closed and proven locally** |
| 6 | Documentation index folder list | `docs/PXL/` contains folders `00`–`07` and `10`–`13`. **`08. Banking and Treasury/` and `09. Fixed Assets/` do not exist** | The Documentation Index §4 lists both folders with authority and contents | Either create the folders when those modules start, or mark the rows as reserved | Low — navigation only |
| 7 | Stock reservation | No reservation table, function or available-to-promise reduction exists | An approved Sales Order does not ring-fence stock; two orders may promise the same unit | Record as a backlog item if pilot clients take orders ahead of stock | Medium |
| 8 | AR write-off | No write-off function or document exists | An uncollectible receivable can only be removed by manual journal, leaving the customer subledger and control account to be reconciled by hand | Record as a backlog item | Medium |
| 9 | Advance payments and unapplied cash | No customer-advance, supplier-advance or unapplied-cash mechanism exists on either side | Overpayment and deposit-taking are ordinary SME events | Record as a backlog item; it affects both Module 1 and Module 2 | Medium |
| 10 | FIFO and Specific Identification costing | Exact allocations, identity selection, reversal, return, receipt cancellation ordering and concurrent admission are exercised by tests `135`–`137` and the committed inventory lifecycle | Every offered method must remain correct through its intended correction path | Retain the three-method authority and its lifecycle gate | **Closed locally; not certification** |
| 11 | Goods Issue | Real public posting path consumes FIFO layers, stamps exact line cost and posts DR Expense / CR Inventory | Internal consumption of stock is an ordinary inventory event | Preserve test `136` | **Closed locally** |
| 12 | Purchase Return | Real save → ship → complete path removes the selected receipt cost and posts DR AP / CR Inventory Control | Returning goods to a supplier is an ordinary purchasing event | Preserve tests `031` and `137` | **Closed locally** |
| 13 | Close readiness and unposted documents | Close readiness cannot see unposted documents (Backlog 18h) | A period should not close while a draft document dated in it still exists | Already recorded as Backlog 18h; noted here for completeness | Recorded |
| 14 | Cross-transaction defect class | Two defects (PXL-AUD-074, PXL-AUD-075) were invisible to the whole pgTAP suite because it runs inside one transaction | Any guard with a `same_txn` escape is untestable by pgTAP alone | Delivery, posting, purchasing and inventory-costing committed lifecycles now exercise those boundaries; add future lanes by business process | **Mitigated, not certified** |

**No other contradiction was found in the 2026-08-08 reconciliation.** In particular, the compliance chain, the
posting and kernel model, the engine taxonomy, the excluded-scope ruling
(PAD-015) and the ranked future priorities (Banking & Treasury, then Fixed
Assets) are consistent across the Product Architecture, the Delivery Plan,
`AI/AI_STATE.md`, the Product Backlog and the repository.

---

## Document control

**Created:** 2026-08-07.
**Owner domain:** Cross-domain functional reference.
**Relationship to existing documents:** Subordinate to
`01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` for scope, identity and the
module/engine taxonomy; subordinate to `AI/AI_STATE.md` for all status facts;
subordinate to the Tier 1 accounting, posting, transaction and compliance
standards for their own subjects. It **describes processes** and defines no rule
that those authorities do not already define.

**Maintenance rule.** When a process changes, update the affected module's
Business Process Matrix row, its Detailed Step Discussion and its Pilot Status in
the same session as the implementation. **Never** add a status metric to this
document — counts and standings live in `AI/AI_STATE.md` and nowhere else.
