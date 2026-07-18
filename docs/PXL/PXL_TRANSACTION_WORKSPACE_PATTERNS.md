# PXL Transaction Workspace Patterns

**Status:** Sole authoritative transaction-content variation standard
**Authority:** Tier 1, subordinate to `PXL_TRANSACTION_WORKSPACE_STANDARD.md` for all layout and visual decisions
**Version:** 1.0
**Effective:** 2026-07-18

This document defines only how transaction business content varies inside the permanent workspace architecture. It does not redefine layout, dimensions, spacing, typography, components, tab order, sidebar width, table density, responsive behavior, or interaction rules.

Field Source Matrices, the Transaction Matrix, accounting rules, posting services, tax services, inventory services, lifecycle services, and permissions remain authoritative over the examples below.

## Shared content rules

- The three card positions remain Document Information, primary party/context, and transaction context.
- In create/edit modes those cards own the real bound document-header fields; pattern-specific line/application tables do not repeat them.
- All fourteen standard tabs remain in their fixed positions.
- Lines begins with the pattern-specific detail table. Detailed Financial, GL, Tax, Validation, Approval, and Audit content remains in its named tab.
- Inapplicable tabs use truthful empty states.
- Financial, GL, Tax, workflow, relations, totals, and sidebar widgets vary only when backed by the transaction domain.
- Pattern classification does not make a document posting or non-posting; the Transaction Matrix does.
- Mixed documents may compose relevant content from two patterns without changing the workspace layout.

## Pattern A — Commercial document

Examples: Sales Invoice, Vendor Bill, Credit Memo, Vendor Credit, Sales Order, Purchase Order.

| Area | Permitted content variation |
| --- | --- |
| Card 1 | Date, posting/due date, branch, currency, terms, external/source reference |
| Card 2 | Customer or supplier snapshot, code, TIN/branch, tax profile, master link |
| Card 3 | Sales or purchase context, owner/buyer, dimensions, warehouse where relevant |
| Lines | Item/service, description, quantity, UOM, unit price, discount, VAT, net/gross, dimensions, warehouse, source line |
| Financial | Gross, discount, net, VAT, withholding, receivable/payable, paid/applied, balance |
| GL sections | Revenue/expense, AR/AP, VAT, discount, withholding; inventory/COGS only when the domain posts it |
| Tax sections | Output or input VAT, exempt/zero-rated, EWT/CWT/FWT/ATC when supported |
| Workflow | Draft, approval, fulfillment/receipt, billing, posting, settlement, close/void as governed |
| Related Docs | Quote/request, order, delivery/receipt, invoice/bill, payment, credit/debit/return, journal |
| Sidebar | Balance/commitment, tax, GL preview or no-direct-posting state, party, audit, actions |

Non-posting commercial sources show no posted GL/tax recognition. Expected impact appears only when an authoritative preview exists.

## Pattern B — Inventory or logistics movement

Examples: Delivery Receipt, Goods Receipt, Inventory Adjustment, Stock Transfer, Goods Issue, Physical Count, Purchase Return, Asset Transfer.

| Area | Permitted content variation |
| --- | --- |
| Card 1 | Movement number/date, branch, status, source reference |
| Card 2 | Source/destination warehouse, custodian, supplier/customer when relevant |
| Card 3 | Movement type/reason, fulfillment/receipt/count status, valuation context |
| Lines | Item, description, source/destination warehouse, quantity, UOM, unit cost, total cost, lot/serial, dimensions, remarks |
| Financial | Quantity, cost, increase/decrease, transfer value, count variance |
| GL sections | Inventory asset, COGS, variance, in-transit, GRNI/GI-not-billed only when the posting engine returns them |
| Tax sections | Normally not applicable; show supported tax only for a governed taxable movement |
| Workflow | Draft, approval/confirmation, movement/receipt, posting/completion, cancellation |
| Related Docs | Order, delivery/receipt, bill/invoice, transfer order/receipt, generated adjustment/journal |
| Sidebar | Inventory/value summary, warehouse/source, GL state, movement status, audit, actions |

Logistics confirmation and accounting posting are distinct. The UI must not show a journal merely because physical quantity moved.

## Pattern C — Payment or receipt

Examples: Official Receipt, Customer Payment, Payment Voucher, Vendor Payment, Cash Receipt, Fund Transfer, Bank Adjustment, Check Voucher, Petty Cash.

| Area | Permitted content variation |
| --- | --- |
| Card 1 | Payment/receipt date, branch, number, reference/check, status |
| Card 2 | Customer, supplier, payee, custodian, or source/destination bank/cash account |
| Card 3 | Method, deposit/disbursement account, check details, settlement/application context |
| Lines | Applications rather than item lines: source document, dates, original/open amount, discount, withholding, applied, remaining, currency/rate |
| Financial | Payment, discount, withholding, applied, unapplied/advance, cash/bank amount |
| GL sections | Cash/bank, AR/AP settlement, withholding, discount, charges, FX gain/loss |
| Tax sections | EWT/CWT and application tax only when source-backed; VAT generally remains on the governed source document |
| Workflow | Draft, approval, posting/release, clearing/bounce/cancellation/void where governed |
| Related Docs | Invoice/bill, credit/debit, deposit, check, reconciliation, generated journal |
| Sidebar | Application/balance, tax, payment/bank, GL preview, party/payee, audit, actions |

Applied plus unapplied amounts must reconcile to the governed payment total.

## Pattern D — Journal or accounting document

Examples: Journal Entry, recurring journal, amortization/revenue-recognition schedules and runs, depreciation, asset acquisition/disposal/impairment.

| Area | Permitted content variation |
| --- | --- |
| Card 1 | Journal/document date, fiscal period, branch, number, status |
| Card 2 | Classification, source, recurrence/schedule/asset context |
| Card 3 | Posting, reversal, generation, balance, and lock context |
| Lines | Account, debit, credit, memo, entity, department, location, project, cost center, branch, functional entity, tax code/reference when allowed |
| Financial | Total debit, total credit, difference, balanced status; asset/schedule values when applicable |
| GL sections | Authoritative debit/credit lines and reconciliation |
| Tax sections | Only tax codes and consequences explicitly allowed and returned by the governed engine |
| Workflow | Draft, approval, posting/generation, reversal/close |
| Related Docs | Source transaction, generated journal, schedule/run, reversal journal, asset transaction |
| Sidebar | Balance, posting/generation/reversal, audit, actions |

Customer-sales, supplier-purchase, item-pricing, and payment-application content must not be forced into this pattern.

## Pattern E — Non-posting source document

Examples: Quotation, Purchase Request, Request for Quotation, Sales Order, Purchase Order, Supplier Debit Memo when governed as a claim/source.

| Area | Permitted content variation |
| --- | --- |
| Card 1 | Source document identity, date, validity/expected date, branch, currency |
| Card 2 | Requester, customer, supplier, or responsible party |
| Card 3 | Approval, conversion, fulfillment/receipt/billing context |
| Lines | Requested/offered/ordered items or services, quantities, prices where relevant, dimensions, source trace |
| Financial | Commitment/expected amount only; no posted balance |
| GL sections | Explicit `No direct GL posting`; expected impact only from an authoritative preview |
| Tax sections | Expected treatment only if governed; no recognized tax ledger impact |
| Workflow | Draft, pending approval, approved, partially/fully converted or fulfilled, closed/cancelled |
| Related Docs | Request/quotation, order, delivery/receipt, invoice/bill, downstream payment/journal |
| Sidebar | Commitment/conversion, party, no-direct-posting state, approval/audit, actions |

Non-posting documents must never imply that expected commercial amounts are ledger balances.

## Module accents

Module accents are the only permitted visual variation and do not change structure:

| Module | Accent purpose |
| --- | --- |
| Sales | Identity/link/current-step cue |
| Purchasing/AP | Identity/link/current-step cue |
| Inventory | Identity/link/current-step cue |
| Accounting | Identity/link/current-step cue |
| Banking/Treasury | Identity/link/current-step cue |
| Fixed Assets | Neutral identity/link/current-step cue unless an inventory transfer uses the inventory accent |
| Compliance | Neutral/compliance identity cue for future transaction workspaces |

Accent values live in shared tokens. Module pages may not choose their own header, tab, card, button, or sidebar color.

## Classification and composition

`src/lib/transactionWorkspaceCoverage.ts` records the implemented pattern for every transaction route. When a transaction spans patterns:

- select the pattern matching its primary line and lifecycle model;
- compose only source-backed secondary impact sections;
- retain the fixed architecture;
- document the adaptation in the executable rollout matrix;
- do not create a sixth layout pattern.

Any proposed pattern change that affects geometry belongs in `PXL_TRANSACTION_WORKSPACE_STANDARD.md`, not here.
