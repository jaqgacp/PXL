# PXL Transaction Workspace Manifest

Status: Official rollout manifest
Version: 1.0
Typed registry: `src/lib/transactionWorkspaceRollout.ts`
Playbook: `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md`
Schema: `PXL_TRANSACTION_DEFINITION_SCHEMA.md`
Field Source Matrix: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`
Reference implementations: Sales Invoice Create/Edit Workspace and Sales Invoice Read-Only View Workspace

## Purpose

This manifest controls the transaction-workspace rollout sequence and implementation status.

It does not replace:

- `PXL_TRANSACTION_MATRIX.md` for lifecycle, source chains, UX status, and implementation maturity.
- `PXL_ACCOUNTING_RULES_MATRIX.md` for posting, account determination, tax impact, reversal/void/cancel rules, lock behavior, reports, and tests.

Every future transaction rollout must update this manifest.

## Rollout Status Values

- `NOT_DEFINED`
- `DEFINED`
- `READY_FOR_IMPLEMENTATION`
- `IN_PROGRESS`
- `IMPLEMENTED`
- `VALIDATED`
- `APPROVED_REFERENCE`
- `BLOCKED`

Mode status values:

- `NOT_REQUIRED`
- `NOT_STARTED`
- `PARTIAL`
- `IMPLEMENTED`
- `VALIDATED`

Field Source Matrix gate:

- A transaction cannot move from `DEFINED` to `READY_FOR_IMPLEMENTATION` until its Field Source Matrix is at least `COMPLETE`.
- A transaction cannot move to `VALIDATED` or `APPROVED_REFERENCE` until its Field Source Matrix is `VALIDATED`.
- The typed registry enforces this planning gate through `fieldSourceMatrix`.

## Master Status Table

| Sequence | Module | Family | Transaction | Definition Status | Create/Edit Status | View Status | Posting Integration | Tax Integration | Related Docs | Audit | Testing | Approval Status | Blocker | Recommended Next |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0.1 | Sales | Sales | Sales Invoice | DEFINED | IMPLEMENTED: audited source-backed slice | IMPLEMENTED: audited source-backed slice | Implemented: separated Commercial/Revenue and Inventory/Cost impact sections over one balanced AR/revenue/VAT/inventory/COGS journal result | Implemented: output VAT, expected CWT separation, VAT Price Basis persistence | Implemented with SO/DR source-chain gaps | Implemented with user-display enrichment gaps | Build/lint; test 054 passes with 22 assertions; broader state/report fixture matrix pending | IN_PROGRESS reference pair, not fully approved | PXL-AUD-053 residual: Project/Location/Functional Entity masters, source-chain/report/API/export fixtures, user display enrichment | No |
| 1.1 | Sales | Sales | Sales Order | DEFINED | PARTIAL | NOT_STARTED | Non-posting | Informational | Defined | Expected | Pending | DEFINED | Field Source Matrix must be completed before READY_FOR_IMPLEMENTATION; explicit rollout prompt and dependency review required | Yes, after Field Source Matrix |
| 1.2 | Sales | Sales | Delivery Receipt | DEFINED | PARTIAL | NOT_STARTED | Pending definition | None | Defined | Expected | Pending | DEFINED | Inventory policy review | No |
| 1.3 | Sales | Sales | Sales Quotation | DEFINED | PARTIAL | NOT_STARTED | Non-posting | Informational | Defined | Expected | Pending | DEFINED | Conversion trace review | No |
| 1.4 | Receivables | Sales/AR | Sales Receipt / Official Receipt | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Receipt/application and CWT evidence review | No |
| 1.5 | Sales | Sales | Credit Memo | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Application/reversal evidence review | No |
| 2.1 | Purchasing | Purchasing | Purchase Order | DEFINED | PARTIAL | NOT_STARTED | Non-posting | Informational | Defined | Expected | Pending | DEFINED | Procurement lifecycle review | No |
| 2.2 | Purchasing | Purchasing | Goods Receipt | DEFINED | PARTIAL | NOT_STARTED | Pending definition | None | Defined | Expected | Pending | DEFINED | Receiving and inventory valuation policy | No |
| 2.3 | Payables | Purchasing/AP | Vendor Bill | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | AP EWT view evidence mapping | No |
| 2.4 | Payables | Purchasing/AP | Vendor Payment | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Payment-basis EWT and certificate links | No |
| 2.5 | Payables | Purchasing/AP | Vendor Credit | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | AP aging/application controls | No |
| 2.6 | Purchasing | Purchasing | Purchase Return | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Inventory/accounting trace validation | No |
| 2.7 | Purchasing | Purchasing | Purchase Request | NOT_DEFINED | NOT_STARTED | NOT_STARTED | Non-posting | None | Undefined | Undefined | Pending | NOT_DEFINED | Scope and route not confirmed | No |
| 3.1 | Accounting | Accounting | Journal Entry | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Pending by entry type | Defined | Expected | Pending | DEFINED | Read-only JE workspace mapping | No |
| 3.2 | Accounting | Accounting | Recurring Journal Entry | DEFINED | PARTIAL | NOT_STARTED | Preview/generated JE | Pending by entry type | Defined | Expected | Pending | DEFINED | Template versus generated JE separation | No |
| 3.3 | Receivables | AR | Customer Payment | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Covered by Official Receipt; avoid duplicate workspace | No |
| 3.4 | Payables | AP | Vendor Payment | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Same as Phase 2 Vendor Payment | No |
| 3.5 | Receivables | AR | Customer Credit Application | DEFINED | NOT_REQUIRED | NOT_STARTED | Pending definition | None | Defined | Expected | Pending | DEFINED | May remain subworkspace unless standalone is required | No |
| 3.6 | Payables | AP | Vendor Credit Application | DEFINED | NOT_REQUIRED | NOT_STARTED | Pending definition | None | Defined | Expected | Pending | DEFINED | Must preserve application-date controls | No |
| 3.7 | Accounting | Accounting | Reversal Entry | DEFINED | NOT_REQUIRED | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Read-only trace/review workspace | No |
| 4.1 | Inventory | Inventory | Inventory Receipt | NOT_DEFINED | NOT_STARTED | NOT_STARTED | Pending definition | None | Undefined | Expected | Pending | NOT_DEFINED | Dedicated route/model not confirmed | No |
| 4.2 | Inventory | Inventory | Inventory Issue / Goods Issue | DEFINED | PARTIAL | NOT_STARTED | Implemented core | None | Defined | Expected | Pending | DEFINED | Cost and stock movement authority | No |
| 4.3 | Inventory | Inventory | Inventory Transfer / Stock Transfer | DEFINED | PARTIAL | NOT_STARTED | Implemented core | None | Defined | Expected | Pending | DEFINED | Source/destination warehouse context | No |
| 4.4 | Inventory | Inventory | Inventory Adjustment / Stock Adjustment | DEFINED | PARTIAL | NOT_STARTED | Implemented core | None | Defined | Expected | Pending | DEFINED | Reason-code and valuation evidence | No |
| 4.5 | Inventory | Inventory | Stock Count / Physical Count | DEFINED | PARTIAL | NOT_STARTED | Implemented through adjustment | None | Defined | Expected | Pending | DEFINED | Count freeze and variance approval | No |
| 4.6 | Inventory | Inventory | Assembly / Production Transaction | NOT_DEFINED | NOT_STARTED | NOT_STARTED | Pending definition | None | Undefined | Undefined | Pending | NOT_DEFINED | Production scope not confirmed | No |
| 5.1 | Banking | Banking | Bank Deposit | NOT_DEFINED | NOT_STARTED | NOT_STARTED | Pending definition | None | Undefined | Expected | Pending | NOT_DEFINED | Dedicated route/model not confirmed | No |
| 5.2 | Banking | Banking | Bank Withdrawal | NOT_DEFINED | NOT_STARTED | NOT_STARTED | Pending definition | None | Undefined | Expected | Pending | NOT_DEFINED | Dedicated route/model not confirmed | No |
| 5.3 | Banking | Banking | Bank Transfer / Fund Transfer | DEFINED | PARTIAL | NOT_STARTED | Implemented core | None | Defined | Expected | Pending | DEFINED | Clearing state evidence | No |
| 5.4 | Banking | Banking | Check Payment / Check Voucher | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Implemented core | Defined | Expected | Pending | DEFINED | Supplier-linked EWT and cancellation evidence | No |
| 5.5 | Banking | Banking | Bank Adjustment | DEFINED | PARTIAL | NOT_STARTED | Implemented core | None | Defined | Expected | Pending | DEFINED | Reason-code and reconciliation state | No |
| 5.6 | Banking | Banking | Reconciliation Transaction View | DEFINED | PARTIAL | NOT_STARTED | Non-posting | None | Defined | Expected | Pending | DEFINED | Matching and lock controls | No |
| 6.1 | Fixed Assets | Fixed Assets | Asset Acquisition | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Pending definition | Defined | Expected | Pending | DEFINED | Asset register/capitalization evidence | No |
| 6.2 | Fixed Assets | Fixed Assets | Capitalization | NOT_DEFINED | NOT_STARTED | NOT_STARTED | Pending definition | None | Undefined | Expected | Pending | NOT_DEFINED | Separate document model not confirmed | No |
| 6.3 | Fixed Assets | Fixed Assets | Depreciation Run | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Pending definition | Defined | Expected | Pending | DEFINED | Posted run output must not be recomputed client-side | No |
| 6.4 | Fixed Assets | Fixed Assets | Asset Transfer | DEFINED | PARTIAL | NOT_STARTED | Implemented core | None | Defined | Expected | Pending | DEFINED | Source/destination ownership and dimensions | No |
| 6.5 | Fixed Assets | Fixed Assets | Asset Disposal | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Pending definition | Defined | Expected | Pending | DEFINED | Gain/loss and tax evidence | No |
| 6.6 | Fixed Assets | Fixed Assets | Asset Adjustment | DEFINED | PARTIAL | NOT_STARTED | Implemented core | Pending definition | Defined | Expected | Pending | DEFINED | Approval and valuation evidence | No |
| 7.1 | Compliance | Compliance | Compliance and Specialized Transaction Views | NOT_DEFINED | NOT_REQUIRED | NOT_STARTED | Non-posting | Authoritative tax/report snapshots | Defined after core rollout | Expected | Pending | BLOCKED | Wait until core transaction workspaces are stable | No |

## Structured Transaction Records

The records below summarize the required manifest fields. Detailed accounting/tax behavior remains in `PXL_TRANSACTION_MATRIX.md` and `PXL_ACCOUNTING_RULES_MATRIX.md`.

### Phase 0 - Reference Foundation

#### Sales Invoice

- Transaction Key: `sales-invoice`
- Module: Sales
- Document Family: Sales
- Purpose: Customer invoice and AR recognition.
- Primary Party: Customer
- Create/Edit Required: Yes
- Read-Only View Required: Yes
- Posting Transaction or Non-Posting: Posting
- Inventory Impact: Implemented for inventory item Sales Invoice lines through warehouse capture, inventory issue ledger, COGS/Inventory journal lines, SI line cost evidence, and void stock restoration
- GL Impact: Authoritative when posted; preview before posting; presented as separated Commercial / Revenue and Inventory / Cost accounting impact sections with one combined reconciliation
- Tax Impact: Authoritative VAT ledger when posted; Expected CWT remains informational until receipt/certificate recognition
- Payment Impact: AR collection state through receipts/applications
- Required Information Panels: Document Information, Customer Information, Sales Context
- Required Tabs: Standard full tab set
- Main Header KPIs: Invoice Total, Collected, Balance Due
- Lifecycle: Draft, Approved, Posted, Partially Paid, Paid, Voided, Cancelled
- Primary Actions: Submit, Post, Create Receipt, Credit Memo, Void, Print, Email, More
- Related Documents: Quotation, Sales Order, Delivery Receipt, Receipt, Credit Memo, Journal Entry
- Correction Method: Credit Memo or governed correction flow
- Approval Requirement: Configured approval or posting approval based on matrix
- Field Source Matrix: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`; status `COMPLETE`; validation status `IMPLEMENTATION_REVIEWED`; PXL-AUD-053 residual gaps remain
- Current Implementation Status: IN_PROGRESS reference pair; audited source-backed slice implemented and tested, broader state/report/API/export validation pending
- Dependencies: Customer, items, VAT codes, number series, fiscal period, AR/VAT accounts, Inventory/COGS accounts, warehouses, departments, cost centers, employees, tax detail, receipt applications, source document conversion policy, Project/Location/Functional Entity master decisions
- Reference Documentation: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`, `PXL_SALES_INVOICE_UX_STANDARD.md`, `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md`, transaction matrix, accounting rules matrix
- Rollout Sequence: Phase 0 reference
- Notes: Do not reimplement during rollout. Use as structural reference only. Business completeness is governed by `PXL_SALES_INVOICE_FUNCTIONAL_SPECIFICATION.md` and PXL-AUD-053.

### Phase 1 - Sales Document Family

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sales Order | `sales-order` | Customer commitment before delivery/invoice | Customer | Create/Edit and View plus Field Source Matrix | Non-posting; tax informational; inventory commitment informational | Document, Customer, Sales Context | Lines, Financial, Validation, Workflow, Approval, Audit, Related, Party, Attachments, Activity, Notes, System | Order Total, Fulfilled, Remaining | Draft, Submitted, Approved, Partially Fulfilled, Fulfilled, Partially Invoiced, Invoiced, On Hold, Cancelled | Submit, Approve, Create Delivery Receipt, Create Sales Invoice, Hold, Cancel | Quotation, Delivery Receipt, Sales Invoice, Receipt, Credit Memo | Cancel or revise while open | Optional/configured | Customer, item, number series, sales lifecycle, fulfillment/invoicing quantities, Field Source Matrix | First rollout candidate after its Field Source Matrix is complete |
| Delivery Receipt | `delivery-receipt` | Customer delivery/fulfillment evidence | Customer | Create/Edit and View | Inventory authoritative; GL pending policy; tax none | Document, Customer, Sales Context | Lines, Inventory, Validation, Workflow, Approval, Audit, Related, Party, Attachments, Activity, Notes, System | Delivered Quantity, Invoiced Quantity, Remaining Quantity | Draft, Approved, Delivered, Partially Invoiced, Invoiced, Cancelled | Post Delivery, Create Sales Invoice, Cancel | Sales Order, Sales Invoice, Customer Return | Customer Return or cancellation | Optional/configured | Inventory policy, item/warehouse, source SO | Needs inventory policy review |
| Sales Quotation | `sales-quotation` | Non-posting customer offer | Customer | Create/Edit and View | Non-posting; tax informational | Document, Customer, Sales Context | Lines, Financial, Validation, Workflow, Approval, Audit, Related, Party, Attachments, Activity, Notes, System | Quote Total, Accepted Amount, Open Amount | Draft, Sent, Accepted, Rejected, Expired, Cancelled | Send, Accept, Create Sales Order, Create Sales Invoice, Cancel | Sales Order, Sales Invoice | Revise or cancel before conversion | Optional | Customer, items, price/tax defaults, conversion trace | Non-posting workflow |
| Sales Receipt / Official Receipt | `sales-receipt` | Customer cash receipt and application | Customer | Create/Edit and View | Posting; GL/tax/payment authoritative | Document, Customer, Payment Context | Standard full tab set | Receipt Total, Applied, Unapplied | Draft, Approved, Posted, Bounced, Voided, Cancelled | Submit, Post, Apply, Bounce, Void, Print | Sales Invoice, Credit Memo, Journal Entry, Form 2307 Received | Bounce/void governed flow | Optional/configured | Receipts, receipt lines, CWT evidence, cash/bank account, fiscal period | Actual CWT recognition belongs here |
| Credit Memo | `credit-memo` | Customer credit or sales adjustment | Customer | Create/Edit and View | Posting; GL/tax/payment authoritative; inventory pending policy | Document, Customer, Sales Context | Standard full tab set | Credit Total, Applied, Open Credit | Draft, Approved, Posted, Applied, Voided | Post, Apply Credit, Void | Sales Invoice, Receipt, Journal Entry | Void/reversal/application reversal | Optional/configured | Credit application controls, tax reversal, AR aging | Must preserve application evidence |

### Phase 2 - Purchasing Document Family

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Purchase Order | `purchase-order` | Supplier order commitment | Supplier | Create/Edit and View | Non-posting; tax informational; inventory commitment informational | Document, Supplier, Purchase Context | Lines, Financial, Validation, Workflow, Approval, Audit, Related, Party, Attachments, Activity, Notes, System | Order Total, Received, Remaining | Draft, Submitted, Approved, Partially Received, Received, Partially Billed, Billed, Cancelled | Submit, Approve, Create Goods Receipt, Create Vendor Bill, Cancel | Purchase Request, Goods Receipt, Vendor Bill, Vendor Credit | Cancel/revise while open | Optional/configured | Supplier, items, procurement workflow, receiving/billing quantities | First purchasing-family candidate |
| Goods Receipt | `goods-receipt` | Supplier receiving evidence | Supplier | Create/Edit and View | Inventory authoritative; GL pending policy; tax none | Document, Supplier, Purchase Context | Lines, Inventory, Validation, Workflow, Approval, Audit, Related, Party, Attachments, Activity, Notes, System | Received Quantity, Billed Quantity, Remaining Quantity | Draft, Received, Partially Billed, Billed, Cancelled | Create Vendor Bill, Return Goods, Cancel | Purchase Order, Vendor Bill, Purchase Return | Purchase Return/cancel | Optional/configured | Receiving, item/warehouse, valuation policy | Inventory valuation policy required |
| Vendor Bill | `vendor-bill` | Supplier invoice and AP recognition | Supplier | Create/Edit and View | Posting; GL/tax/payment authoritative; inventory pending policy | Document, Supplier, Purchase Context | Standard full tab set | Bill Total, Paid, Balance Due | Draft, Approved, Posted, Partially Paid, Paid, Voided | Post, Create Vendor Payment, Create Vendor Credit, Void | Purchase Order, Goods Receipt, Vendor Payment, Vendor Credit, Journal Entry | Vendor Credit or void/reversal | Optional/configured | Supplier, AP accounts, input VAT, AP EWT policy, fiscal period | Strong core flow; view still needs rollout |
| Vendor Payment | `vendor-payment` | Supplier payment/application | Supplier | Create/Edit and View | Posting; GL/tax/payment authoritative | Document, Supplier, Payment Context | Standard full tab set | Payment Total, Applied, Unapplied | Draft, Approved, Posted, Voided | Post, Void, Print | Vendor Bill, Vendor Credit, Journal Entry, Form 2307 Issued | Void/reversal | Optional/configured | Cash/bank, AP applications, EWT, certificate evidence | Avoid duplicate with Phase 3 AP payment row |
| Vendor Credit | `vendor-credit` | Supplier credit/adjustment | Supplier | Create/Edit and View | Posting; GL/tax/payment authoritative; inventory pending policy | Document, Supplier, Purchase Context | Standard full tab set | Credit Total, Applied, Open Credit | Draft, Approved, Posted, Applied, Voided | Post, Apply Credit, Void | Vendor Bill, Vendor Payment, Journal Entry | Void/reversal/application reversal | Optional/configured | AP aging and application controls | Must preserve application-date controls |
| Purchase Return | `purchase-return` | Return goods to supplier | Supplier | Create/Edit and View | Posting; GL/tax/inventory authoritative | Document, Supplier, Purchase Context | Standard full tab set | Return Total, Credited, Open Return | Draft, Approved, Posted, Cancelled | Post, Create Vendor Credit, Cancel | Goods Receipt, Vendor Credit, Journal Entry | Cancellation/reversal | Optional/configured | Inventory, AP/tax trace, purchase return posting | Needs inventory trace validation |
| Purchase Request | `purchase-request` | Internal request before PO | Requester | Create/Edit and View if in scope | Non-posting | Document, Purchase Context, Related Party | Lines, Financial, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Requested Amount, Approved Amount, Open Amount | Draft, Submitted, Approved, Converted, Rejected, Cancelled | Submit, Approve, Reject, Create PO | Purchase Order | Reject/cancel/revise | Usually required | Scope and route not confirmed | Do not implement until scope confirmed |

### Phase 3 - Accounting and Receivables/Payables

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Journal Entry | `journal-entry` | Manual or source accounting entry | None | Create/Edit and View | Posting; GL authoritative; tax by entry type | Document, Accounting Context, Tax Context | Lines, Financial, GL, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Total Debit, Total Credit, Difference | Draft, Approved, Posted, Reversed, Voided | Submit, Post, Reverse | Source Document, Reversal Entry | Exact reversal | Optional/configured | COA, periods, dimensions, posting primitives | Accounting-family reference candidate |
| Recurring Journal Entry | `recurring-journal-entry` | Template for generated JEs | None | Create/Edit and View | Preview/generated JE | Document, Accounting Context, Tax Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Template Amount, Generated Entries, Next Run | Draft, Active, Paused, Completed, Cancelled | Generate, Pause, Cancel | Journal Entry | Cancel template or reverse generated JE | Optional | Recurring templates, generated JE linkage | Keep template distinct from generated JE |
| Customer Payment | `customer-payment` | Customer receipt/application | Customer | Covered by Official Receipt workspace | Posting; GL/tax/payment authoritative | Document, Customer, Payment Context | Standard full tab set | Receipt Total, Applied, Unapplied | Draft, Approved, Posted, Bounced, Voided | Post, Apply, Bounce, Void | Sales Invoice, Credit Memo, 2307 Received | Bounce/void | Optional/configured | Same as Official Receipt | Avoid duplicate workspace definition |
| Vendor Payment | `vendor-payment` | Supplier payment/application | Supplier | Covered by Vendor Payment workspace | Posting; GL/tax/payment authoritative | Document, Supplier, Payment Context | Standard full tab set | Payment Total, Applied, Unapplied | Draft, Approved, Posted, Voided | Post, Void | Vendor Bill, Vendor Credit, 2307 Issued | Void/reversal | Optional/configured | Same as Phase 2 Vendor Payment | Duplicate sequence reference only |
| Customer Credit Application | `customer-credit-application` | Apply customer credit to invoice | Customer | View/subworkspace | Payment authoritative; posting pending policy | Document, Customer, Payment Context | Financial, Validation, Workflow, Audit, Related, Party, Activity, Notes, System | Applied Amount, Remaining Credit, Invoice Balance | Draft, Applied, Reversed | Reverse Application | Credit Memo, Sales Invoice, Receipt | Reverse application | Usually not separate | AR application controls | May remain inside Credit Memo/Invoice view |
| Vendor Credit Application | `vendor-credit-application` | Apply vendor credit to bill | Supplier | View/subworkspace | Payment authoritative; posting pending policy | Document, Supplier, Payment Context | Financial, Validation, Workflow, Audit, Related, Party, Activity, Notes, System | Applied Amount, Remaining Credit, Bill Balance | Draft, Applied, Reversed | Reverse Application | Vendor Credit, Vendor Bill, Vendor Payment | Reverse application | Usually not separate | AP application controls | Must preserve application-date controls |
| Reversal Entry | `reversal-entry` | Read-only reversal trace | None | Read-only View | GL/tax authoritative by source | Document, Accounting Context, Tax Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Activity, Notes, System | Debit, Credit, Difference | Posted, Reviewed | Open Source, Open Journal Entry | Original Document, Journal Entry | N/A | Not required | Reversal primitives, source links | Read-only trace/review workspace |

### Phase 4 - Inventory

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Inventory Receipt | `inventory-receipt` | Receive inventory outside purchasing flow | Warehouse | Create/Edit and View | Posting/inventory; GL pending | Document, Inventory Context, Related Party | Lines, Inventory, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Received Quantity, Inventory Value, Variance | Draft, Posted, Cancelled | Post, Reverse | PO, Goods Receipt, Journal Entry | Reverse/cancel | Optional | Dedicated model not confirmed | Not ready |
| Inventory Issue / Goods Issue | `inventory-issue` | Issue inventory | Warehouse | Create/Edit and View | Posting; GL/inventory authoritative | Document, Inventory Context, Related Party | Lines, Inventory, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Issued Quantity, Inventory Value, Variance | Draft, Posted, Reversed, Cancelled | Post, Reverse | Journal Entry, Inventory Movement | Reverse | Optional | Cost and stock movement authority | Existing page is not yet workspace standard |
| Inventory Transfer / Stock Transfer | `inventory-transfer` | Move stock between locations | Warehouse | Create/Edit and View | Posting; GL/inventory authoritative | Document, Inventory Context, Related Party | Lines, Inventory, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Transfer Quantity, Source Value, Destination Value | Draft, Posted, Reversed, Cancelled | Post, Reverse | Journal Entry, Inventory Movement | Reverse | Optional | Source/destination warehouse | Preserve warehouse context |
| Inventory Adjustment / Stock Adjustment | `inventory-adjustment` | Adjust inventory counts/value | Warehouse | Create/Edit and View | Posting; GL/inventory authoritative | Document, Inventory Context, Related Party | Lines, Inventory, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Adjustment Quantity, Adjustment Value, Variance | Draft, Posted, Reversed, Cancelled | Post, Reverse | Journal Entry, Inventory Movement | Reverse | Optional | Reason code, valuation evidence | No placeholder valuation |
| Stock Count / Physical Count | `stock-count` | Physical count and variance processing | Warehouse | Create/Edit and View | Creates adjustment or posting | Document, Inventory Context, Related Party | Lines, Inventory, Financial, GL, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Counted Items, Variance Quantity, Variance Value | Draft, Counted, Approved, Posted, Cancelled | Submit, Approve, Post Adjustment | Inventory Adjustment, Journal Entry | Reverse adjustment | Usually required | Count freeze, variance approval | Needs count lifecycle clarity |
| Assembly / Production Transaction | `assembly-production` | Production/assembly movement | Production | Create/Edit and View if in scope | Pending definition | Document, Inventory Context, Related Party | Lines, Inventory, Financial, GL, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Output Quantity, Input Cost, Variance | Draft, Released, Posted, Closed, Cancelled | Post Production, Close | Inventory Issue, Inventory Receipt, Journal Entry | Reverse/adjust | Required if in scope | Production scope not confirmed | Blocked until scope is approved |

### Phase 5 - Banking and Treasury

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Bank Deposit | `bank-deposit` | Deposit funds to bank | Bank Account | Create/Edit and View if model confirmed | GL/payment pending | Document, Banking Context, Payment Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Deposit Total, Cleared Amount, Uncleared Amount | Draft, Posted, Reconciled, Voided | Post, Reconcile, Void | Receipt, Fund Transfer, Journal Entry | Void/reverse | Optional | Dedicated route/model not confirmed | Not ready |
| Bank Withdrawal | `bank-withdrawal` | Withdraw funds from bank | Bank Account | Create/Edit and View if model confirmed | GL/payment pending | Document, Banking Context, Payment Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Withdrawal Total, Cleared Amount, Uncleared Amount | Draft, Posted, Reconciled, Voided | Post, Reconcile, Void | Check Voucher, Fund Transfer, Journal Entry | Void/reverse | Optional | Dedicated route/model not confirmed | May be represented by other documents |
| Bank Transfer / Fund Transfer | `bank-transfer` | Transfer between bank/cash accounts | Bank Account | Create/Edit and View | Posting; GL/payment authoritative | Document, Banking Context, Payment Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Transfer Amount, Source Cleared, Destination Cleared | Draft, Posted, Reconciled, Voided | Post, Void | Journal Entry, Bank Reconciliation | Reverse | Optional | Source/destination bank, clearing state | Preserve dual-bank identity |
| Check Payment / Check Voucher | `check-payment` | Check disbursement with optional EWT | Payee/Supplier | Create/Edit and View | Posting; GL/tax/payment authoritative | Document, Supplier, Banking Context | Standard full tab set | Check Amount, EWT, Net Cash | Draft, Posted, Cancelled, Voided | Post, Cancel, Print | Journal Entry, 2307 Issued, Bank Reconciliation | Cancel/reverse | Optional | Bank account, supplier, ATC, tax detail | Preserve supplier-linked EWT |
| Bank Adjustment | `bank-adjustment` | Adjust bank/cash books | Bank Account | Create/Edit and View | Posting; GL/payment authoritative | Document, Banking Context, Payment Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Adjustment Amount, Debit, Credit | Draft, Posted, Reversed, Voided | Post, Reverse | Journal Entry, Bank Reconciliation | Reverse | Optional | Reason code and reconciliation state | Must not bypass reconciliation controls |
| Reconciliation Transaction View | `bank-reconciliation-transaction` | Bank statement matching evidence | Bank Account | Create/Edit or View based on current page | Non-posting; payment authoritative | Document, Banking Context, Payment Context | Lines, Financial, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Statement Balance, Book Balance, Difference | Draft, Reconciled, Locked, Reopened | Reconcile, Reopen | Deposits, Withdrawals, Checks, Adjustments | Controlled reopen | Optional | Matching and lock controls | Read-only evidence is key |

### Phase 6 - Fixed Assets

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Asset Acquisition | `asset-acquisition` | Acquire fixed asset | Asset | Create/Edit and View | Posting; GL authoritative; tax pending policy | Document, Asset Context, Accounting Context | Lines, Financial, GL, Tax, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Acquisition Cost, Capitalized Amount, Open Amount | Draft, Posted, Capitalized, Voided | Post, Capitalize, Void | Vendor Bill, Journal Entry, Asset Register | Asset adjustment/disposal | Optional/configured | Asset register, capitalization evidence | Avoid recomputing posted asset cost |
| Capitalization | `capitalization` | Capitalize asset cost | Asset | Create/Edit and View if separate model confirmed | Posting; GL authoritative | Document, Asset Context, Accounting Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Capitalized Amount, Asset Cost, Difference | Draft, Posted, Reversed | Post, Reverse | Asset Acquisition, Journal Entry, Asset Register | Reverse | Optional | Separate model not confirmed | May be state/action, not document |
| Depreciation Run | `depreciation-run` | Periodic depreciation posting | Asset Group | Create/Edit and View | Posting; GL authoritative; tax pending policy | Document, Asset Context, Accounting Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Depreciation Amount, Asset Count, Difference | Draft, Posted, Reversed | Run Preview, Post, Reverse | Journal Entry, Asset Register | Reverse run | Optional | Posted run output | Posted values must be stored truth |
| Asset Transfer | `asset-transfer` | Move asset location/ownership/dimension | Asset | Create/Edit and View | Posting; GL authoritative when applicable | Document, Asset Context, Accounting Context | Lines, Financial, GL, Validation, Workflow, Audit, Related, Attachments, Activity, Notes, System | Asset Cost, Source Location, Destination Location | Draft, Posted, Reversed, Cancelled | Post, Reverse | Asset Register, Journal Entry | Reverse or transfer back | Optional | Source/destination ownership and dimensions | Must show context clearly |
| Asset Disposal | `asset-disposal` | Dispose asset and recognize gain/loss | Asset | Create/Edit and View | Posting; GL authoritative; tax/payment pending policy | Document, Asset Context, Accounting Context | Lines, Financial, GL, Tax, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Proceeds, Carrying Amount, Gain/Loss | Draft, Posted, Reversed, Voided | Post, Reverse | Asset Register, Journal Entry, Receipt | Reverse disposal | Optional/configured | Gain/loss and tax evidence | Do not recompute posted carrying amount |
| Asset Adjustment | `asset-adjustment` | Impairment or value adjustment | Asset | Create/Edit and View | Posting; GL authoritative; tax pending policy | Document, Asset Context, Accounting Context | Lines, Financial, GL, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Adjustment Amount, Carrying Amount, Revised Amount | Draft, Approved, Posted, Reversed | Submit, Approve, Post, Reverse | Asset Register, Journal Entry | Reverse adjustment | Usually required | Approval and valuation evidence | Needs strong audit support |

### Phase 7 - Compliance and Specialized Transactions

| Transaction | Key | Purpose | Primary Party | Required Work | Impacts | Panels | Tabs | Header KPIs | Lifecycle | Primary Actions | Related Docs | Correction Method | Approval Requirement | Dependencies | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Compliance and Specialized Transaction Views | `compliance-transaction-views` | Read-only compliance/report snapshot evidence | None | Read-only View after core rollout | Tax/report authoritative; GL informational | Document, Tax Context, Accounting Context | Lines, Financial, Tax, Validation, Workflow, Approval, Audit, Related, Attachments, Activity, Notes, System | Tax Base, Tax Amount, Variance | Draft, Generated, Reviewed, Filed, Superseded, Voided | Review, File, Supersede | Source Transactions, Tax Detail Entries, Report Snapshot | Supersede/amend | Required when filings are governed | Core transaction patterns must be stable first | BLOCKED until later rollout phase |

## Initial Rollout Sequence

The rollout sequence is:

1. Sales Invoice Create/Edit - reference implementation.
2. Sales Invoice View - reference implementation.
3. Shared workspace components - foundation.
4. Transaction definitions - foundation.
5. Registry - foundation.
6. Manifest - foundation.
7. Rollout playbook - foundation.
8. Sales Order - first future transaction.
9. Continue through phases one transaction at a time.

## Recommended Next Transaction

Sales Order is the recommended next transaction once a future instruction explicitly starts the rollout.

Exact next prompt:

```text
Implement the next eligible transaction workspace from the approved PXL Transaction Workspace Manifest and Rollout Playbook.
```

## Status Rules

Do not mark a transaction `VALIDATED` until the applicable checklist in `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md` has evidence.

Do not mark a transaction `APPROVED_REFERENCE` unless it is explicitly approved as a future reference implementation.

Sales Invoice remains the reference pair. Its audited source-backed slice is implemented and covered by test 054, but its manifest status remains `IN_PROGRESS` until the broader fixture matrix, reporting/API/export mappings, and PXL-AUD-053 residual master-data decisions are closed.
