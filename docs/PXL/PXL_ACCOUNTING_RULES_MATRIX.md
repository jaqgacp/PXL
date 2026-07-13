# PXL Accounting Rules Matrix

Status: Official governed accounting specification
Milestone: PXL Accounting Core Ready
Last updated: 2026-07-13
Authority: User directive 2026-07-13; DEC-018

This document is the canonical accounting specification for PXL posting behavior. It defines how every transaction type should eventually post, reverse, void, cancel, lock, affect tax, affect inventory, affect fixed assets, affect reports, and prove audit traceability.

This is architecture-first. It does not implement code, change schema, or modify posting logic.

## 1. Purpose

PXL must use one unified accounting architecture. Future modules must not embed independent posting logic inside individual pages or feature-specific SQL unless that logic is routed through the governed accounting engine, posting engine, account determination engine, and tax engine.

Every future implementation must be able to answer:

- What business event occurred?
- Which lifecycle transition triggered accounting?
- Which debit and credit accounts were used?
- How were accounts determined?
- Which tax rules applied?
- Which subledgers, inventory layers, fixed asset records, reports, and audit events were affected?
- How can the entry be reversed, voided, cancelled, locked, tested, and traced?

## 2. Document authority

Accounting behavior authority:

1. `PXL_ACCOUNTING_RULES_MATRIX.md` — canonical posting behavior specification.
2. Database migrations, RPCs, triggers, and tests — executable implementation.
3. `PXL_TRANSACTION_MATRIX.md` — broader transaction lifecycle, UX, source-chain, report, and module matrix.
4. `PXL_ACCOUNTING_RULES.md` — concise accounting rules summary.
5. Workspace/report standards — presentation and workflow surfaces only.

If this document and implementation disagree, treat the difference as a production-readiness issue. Either update implementation to match this matrix or update this matrix with an approved accounting decision.

## 3. Implementation sequence

The governed execution order is:

1. Accounting Engine.
2. Posting Engine.
3. Account Determination Engine.
4. Configuration-driven Tax Engine.
5. Master Data Governance.
6. CAS/BIR Readiness.
7. Transaction Rollout.
8. Report Rollout.
9. Dashboards.
10. Client Portal.
11. AI / Automation.

This order supersedes any older plan that begins with transaction UI rollout or report implementation.

## 4. Universal posting principles

Every posting transaction must follow these rules:

- Posting is server-side.
- Posting is atomic.
- Posting locks the source document before reading status or totals.
- Posting validates company membership and source ownership.
- Posting validates open fiscal period.
- Posting validates document lifecycle state.
- Posting validates number series where a number is required.
- Posting validates required master data.
- Posting validates configured accounts before journal creation.
- Posting creates balanced debit and credit lines.
- Posting links the journal entry to its source document.
- Posting writes tax-detail rows when tax applies.
- Posting writes inventory, costing, fixed asset, or subledger effects when applicable.
- Posting records a semantic audit event.
- Posted accounting rows are immutable.
- Corrections use reversal, void, cancellation, credit/debit memo, counter-row, or superseding document mechanics.
- UI preview may explain posting, but the server-side engine is the authority.

## 5. Universal transaction rule fields

Every transaction type must eventually define:

- Business purpose.
- Trigger event.
- Lifecycle.
- Approval requirement.
- Posting trigger.
- Debit accounts.
- Credit accounts.
- Account determination source.
- Tax impact.
- VAT impact.
- Percentage Tax impact.
- EWT/CWT/FWT impact.
- Inventory impact.
- Fixed Asset impact.
- Costing impact.
- Foreign currency impact.
- Required master data.
- Required validations.
- Numbering rules.
- Audit events.
- Related documents.
- Reversal rules.
- Void rules.
- Cancel rules.
- Lock behavior.
- Required reports affected.
- Test scenarios.
- Known exceptions.

## 6. Account Determination Engine

### 6.1 Objective

The Account Determination Engine resolves GL accounts from governed configuration. Normal transaction users should not manually choose GL accounts except where a role-gated accounting override is explicitly allowed.

Manual account selection remains valid for:

- manual journal entries;
- controlled accounting overrides;
- exceptional documents where the user is acting as an accountant and the override is audited.

### 6.2 Accounts the engine must resolve

The engine must resolve:

- customer receivable account;
- supplier payable account;
- revenue account;
- sales discount account;
- sales return / credit memo account;
- expense account;
- accrued expense account;
- inventory account;
- goods received not invoiced account;
- COGS account;
- inventory variance account;
- VAT output account;
- VAT input account;
- VAT payable / recoverable account;
- percentage tax payable account;
- EWT payable account;
- CWT receivable account;
- FWT payable account;
- cash account;
- bank account;
- clearing account;
- foreign exchange gain account;
- foreign exchange loss account;
- rounding gain/loss account;
- fixed asset cost account;
- accumulated depreciation account;
- depreciation expense account;
- asset disposal gain/loss account;
- payroll expense account;
- payroll liability accounts;
- statutory contribution accounts;
- retained earnings account;
- income summary / closing account.

### 6.3 Resolution hierarchy

Default account resolution hierarchy:

1. Company.
2. Tax Profile.
3. Item Group.
4. Item.
5. Customer / Supplier.
6. Document Type.
7. Override.

Implementation notes:

- Company defaults provide control accounts and fallback accounts.
- Tax Profile determines tax-ledger posting accounts and reporting behavior.
- Item Group provides category-level revenue, expense, inventory, and COGS accounts.
- Item provides item-specific account overrides.
- Customer/Supplier provides party-specific AR/AP or tax profile overrides where policy allows.
- Document Type provides transaction-specific posting behavior.
- Override must be role-gated, reason-coded, audited, and visible in GL impact.

No new posting implementation should bypass this hierarchy unless this matrix explicitly documents the exception.

### 6.4 Account determination data contract

Each resolved account should expose:

- resolved account ID;
- account code and name;
- source level used in the hierarchy;
- fallback path;
- override reason, if any;
- posting rule version;
- effective date;
- user who overrode, if any;
- validation result.

### 6.5 Account determination validations

Before posting, the engine must confirm:

- account exists;
- account belongs to the same company;
- account is active;
- account is postable;
- account type is valid for the posting role;
- account is not blocked for the document date;
- account is permitted for the branch/dimension if such restrictions exist;
- override is authorized and reason-coded.

## 7. Configuration-driven Tax Engine

### 7.1 Objective

The Tax Engine must be entirely configuration-driven. Philippine tax rules may be seeded as configuration, but posting logic must not be hardcoded in page components or isolated module-specific implementations.

The engine must support:

- VAT;
- Percentage Tax;
- EWT;
- CWT;
- FWT;
- effective dates;
- future BIR changes;
- multiple tax versions;
- company-specific tax policies;
- document-specific behavior;
- posting policies;
- reporting policies.

### 7.2 Tax rule inputs

Tax evaluation must consider:

- company tax registration;
- company tax profile;
- branch or registration context;
- counterparty tax profile;
- item or service tax profile;
- document type;
- document direction;
- transaction date;
- posting date;
- source document chain;
- tax code;
- ATC code;
- effective tax rule version;
- taxable base policy;
- settlement policy;
- exemption or zero-rated classification;
- withholding agent status;
- variance tolerance;
- reporting period;
- filing status.

### 7.3 Tax rule outputs

The Tax Engine must output:

- tax kind;
- tax code or ATC version used;
- taxable base;
- rate;
- tax amount;
- rounding behavior;
- recoverable/payable classification;
- GL account determination;
- tax ledger row specification;
- report mapping;
- filing/snapshot requirement;
- validation warnings or blockers;
- source rule version.

### 7.4 Tax engine processing pipeline

Standard processing pipeline:

1. Build tax context from company, branch, document, lines, counterparty, item, and date.
2. Select effective tax policy by company and document date.
3. Select tax code / ATC version by document date.
4. Determine taxable base policy.
5. Calculate tax base, rate, tax amount, and rounding.
6. Validate variance tolerance and authorized variance reasons.
7. Resolve tax posting accounts through account determination.
8. Write tax detail rows at posting.
9. Link tax rows to fiscal period, source document, source line, counterparty, and rule version.
10. Feed reports, reconciliations, snapshots, and filing outputs.

### 7.5 Tax configuration objects

The target architecture requires governed configuration for:

- tax regimes;
- tax components;
- tax codes;
- ATC code versions;
- tax profiles;
- withholding profiles;
- document tax policies;
- taxable base policies;
- rate/effective-date policies;
- reporting policies;
- filing policies;
- variance policies;
- tax account mappings;
- tax reconciliation mappings.

## 8. Posting matrix schema

The matrix below uses compact cells. Report any missing production-critical value as a gap rather than hardcoding behavior during implementation.

| Field | Meaning |
| --- | --- |
| Purpose / Trigger | Business purpose and event that starts the transaction. |
| Lifecycle / Approval | Supported status flow and whether approval is required. |
| Posting Trigger | Event that creates accounting entries. |
| Debit Accounts | Debit side of expected journal. |
| Credit Accounts | Credit side of expected journal. |
| Account Source | Account determination source and override policy. |
| Tax Impact | VAT, Percentage Tax, EWT, CWT, FWT impact. |
| Operational Impact | Inventory, fixed asset, costing, FX, cash, and subledger impact. |
| Master Data / Validations | Required masters and posting validations. |
| Numbering / Audit / Related | Numbering rule, audit event, related document chain. |
| Reverse / Void / Cancel / Lock | Correction behavior and lock behavior. |
| Reports / Tests / Exceptions | Reports affected, required tests, known exceptions. |

## 9. Accounting Rules Matrix

| Transaction | Purpose / Trigger | Lifecycle / Approval | Posting Trigger | Debit Accounts | Credit Accounts | Account Source | Tax Impact | Operational Impact | Master Data / Validations | Numbering / Audit / Related | Reverse / Void / Cancel / Lock | Reports / Tests / Exceptions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Quotation | Non-binding customer price quote; triggered by sales quote creation. | Draft -> sent -> accepted/rejected -> expired/cancelled. Approval optional by policy. | No GL posting. | None. | None. | Price list and item defaults only; no GL accounts posted. | No tax ledger; may preview VAT for quote only. | No inventory or costing unless future reservation policy is enabled. | Customer, items/services, UOM, price list, tax display policy. | Quotation number; audit created/sent/accepted/cancelled; related to SO/SI if converted. | Cancel/expire only; no reversal/void because non-posting. Lock after accepted/converted. | Sales pipeline/register; tests for conversion trace and no JE. Exception: future commitment/reservation policy must be separately documented. |
| Sales Order | Customer order commitment; triggered by accepted quote or direct order. | Draft -> approved -> fulfilled/partially fulfilled -> closed/cancelled. Approval required by policy. | No GL posting by default. | None. | None. | Item/customer/price defaults; no GL posting unless future commitment accounting enabled. | Tax preview only; no tax ledger. | May reserve inventory if reservation policy enabled; no COGS by default. | Customer, items, warehouse, price list, delivery terms, credit policy. | SO number; audit approval/close/cancel; related to quotation, DR, SI. | Cancel before fulfillment; close after fulfillment; lock converted quantities. | Sales orders, open orders, inventory availability; tests for no JE and source chain. |
| Delivery Receipt | Evidence of goods delivery; triggered by shipment/delivery. | Draft -> confirmed/delivered -> invoiced/closed/cancelled. Approval optional. | Posting depends on inventory/COGS policy; default architecture must define whether DR or SI recognizes COGS. | If DR posts inventory issue: COGS or deferred COGS. | Inventory or inventory clearing. | Item group/item inventory and COGS accounts; warehouse rules. | No VAT tax ledger unless jurisdiction requires delivery-based tax; normally SI handles VAT. | Inventory quantity reduction; costing layer consumption if configured. | Customer, SO, item, warehouse, costing method, branch. | DR number; audit delivered/cancelled; related to SO and SI. | Reverse inventory issue if cancelled before invoicing; lock once invoiced unless controlled return. | Inventory movements, COGS, sales fulfillment; tests for costing and source trace. Exception: service DR has no inventory. |
| Sales Invoice | Recognizes receivable and revenue; triggered by billing customer. | Draft -> approved -> posted -> paid/partially paid -> voided/reversed. Approval required where workflow configured. | Post approved SI. | Accounts Receivable. | Revenue, Output VAT, other sales tax/liability accounts. | AR from company/customer; revenue from item group/item/document type; VAT from tax profile/code. | Output VAT; Percentage Tax if non-VAT/PT policy; expected CWT metadata only until receipt. | AR subledger; no inventory unless SI is configured to consume stock/COGS. FX gain/loss on settlement if foreign currency. | Customer, item/service, branch, currency, tax profile, VAT code, revenue accounts, terms, number series, open period. | SI number; audit approved/posted/voided; related to quote/SO/DR/OR/CM/JE. | Void posts exact reversal and tax counter-rows; posted lines locked; cancel only before posting. | Sales register, AR aging, GL, VAT output, SLSP/SLS, financial statements. Tests: balanced JE, VAT ledger, locked period, cross-company, void reversal. |
| Official Receipt | Records customer collection; triggered by payment receipt. | Draft -> posted -> bounced/cancelled/voided. Approval optional by policy. | Post OR. | Cash/bank; CWT receivable if withheld. | Accounts Receivable. | Cash/bank from payment method/bank; AR from company/customer; CWT from tax profile. | CWT receivable when customer withholds; tax base from configured policy. No output VAT unless cash-basis tax policy exists. | Cash ledger; AR settlement; FX gain/loss if foreign currency. | Customer, open SI, bank/payment method, CWT profile/ATC, open period, OR number. | OR number; audit posted/bounced/cancelled; related to SI/CM/JE/2307 received. | Bounce/cancel posts exact reversal and tax counter-row; lock posted application lines. | Collections, AR aging, cash receipts book, SAWT/CWT reports. Tests: line-sum total authority, CWT base/rate, over-apply including CM. |
| Credit Memo | Reduces customer receivable/revenue; triggered by return, allowance, discount, or correction. | Draft -> approved -> posted -> applied/closed -> voided. Approval required by policy. | Post approved CM. | Sales returns/allowances or revenue reversal; Output VAT reversal. | Accounts Receivable. | Return/revenue accounts from item/document type; VAT from tax profile; AR from customer/company. | Output VAT counter/reduction; CWT impact only through application/settlement policy. | AR subledger reduction; inventory return impact only if linked to returned goods and configured. | Customer, source SI optional/required by policy, items, VAT codes, reason code. | CM number; audit posted/applied/voided; related to SI/OR/JE. | Void reverses CM and tax rows; application reversal restores open balance. Lock after posting except controlled application. | Credit memo register, AR aging, VAT output adjustment. Tests: applied CM affects aging/over-apply guards. |
| Debit Memo | Increases customer receivable; triggered by additional billing, charge, or correction. | Draft -> approved -> posted -> paid/closed -> voided. Approval required by policy. | Post approved DM. | Accounts Receivable. | Revenue/other income, Output VAT if taxable. | AR from customer/company; income account from item/document type; VAT from tax profile. | Output VAT if taxable; Percentage Tax if applicable. | AR subledger increase; no inventory by default. | Customer, reason/type, tax profile, income account, number series, open period. | DM number; audit posted/voided; related to SI/OR/JE. | Void posts exact reversal and tax counter-row; cancel only before posting. | Debit memo register, AR aging, VAT output. Tests: balanced JE, tax rows, void reversal. |
| Purchase Request | Internal purchase request; triggered by requester. | Draft -> submitted -> approved/rejected -> converted/cancelled. Approval required by policy. | No GL posting. | None. | None. | Budget/cost center only; no GL posting. | No tax ledger. | Optional budget encumbrance if future policy enabled. | Requester, department, cost center, item/service, budget. | PR number; audit submitted/approved/cancelled; related to PO. | Cancel before conversion; lock approved/converted lines. | Procurement pipeline, budget reports. Tests: no JE, approval and conversion trace. |
| Purchase Order | Supplier purchase commitment; triggered by approved PR or direct PO. | Draft -> approved -> issued -> partially received -> closed/cancelled. Approval required by policy. | No GL posting by default. | None. | None. | Item/supplier/account preview only; no posting unless commitment accounting enabled. | Tax preview only; no tax ledger. | Optional inventory on order; no quantity on hand until RR. | Supplier, item/service, warehouse, terms, delivery terms, budget, PO number. | PO number; audit approved/issued/cancelled; related to PR/RR/VB. | Cancel open quantities; lock received/billed quantities. | PO register, commitments, receiving. Tests: no JE, conversion controls. |
| Receiving Report | Records goods/services received; triggered by receipt from supplier. | Draft -> confirmed/received -> billed/closed/cancelled. Approval optional. | Posting depends on inventory/GRNI policy. | Inventory or expense/accrual asset. | GRNI/accrued payable or clearing account. | Inventory account from item/warehouse; GRNI from company/document type. | No VAT input unless policy recognizes at receipt; default VB handles input VAT. | Inventory quantity increase; costing layer creation. | Supplier, PO optional, item, warehouse, UOM, costing method, branch. | RR number; audit received/cancelled; related to PO/VB/return. | Reverse stock/cost layer if cancelled before billed; lock billed quantities. | Inventory movements, stock balance, GRNI reconciliation. Tests: cost layer, branch/company, cancellation. |
| Vendor Bill | Recognizes payable and expense/asset/input VAT; triggered by supplier invoice. | Draft -> approved -> posted -> paid/partially paid -> voided. Approval required where configured. | Post approved VB. | Expense/asset/inventory clearing; Input VAT. | Accounts Payable net of source EWT; EWT Payable when source-basis EWT applies. | AP from company/supplier; expense/asset from item group/item/document type; input VAT from tax profile/code. | Input VAT; AP EWT policy defaults to source/accrual at VB, requires an enabled EWT compliance profile when EWT is present, may use supplier default ATC/base/amount, and auto-defaults TWA supplier-subject goods/services to WC158/WC160 when enabled. | AP subledger; inventory matching if linked to RR; FX on settlement if foreign currency. | Supplier, invoice data, items/expenses, tax profile, VAT code, withholding profile/default ATC, open period, VB number. | VB number; audit approved/posted/voided; related to PO/RR/PV/VC/JE/2307. | Void posts exact reversal and tax counter-rows; posted locked. | Purchase register, AP aging, input VAT, SLP/SLSP, QAP. Tests: EWT policy, VAT, RR linkage, void, withholding profile/TWA defaults. |
| Payment Voucher | Records supplier payment; triggered by payment approval/release. | Draft -> posted/released -> cancelled/voided. Approval required by policy. | Post PV/payment. | Accounts Payable. | Cash/bank; EWT payable only for payment-basis withholding. | AP from company/supplier; bank from payment method; EWT from tax profile/ATC when not already accrued at VB. | Payment-basis EWT payable requires an enabled EWT compliance profile; source-accrued VBs reject duplicate PV EWT and settle cash-only; 2307 source follows the tax-detail source. | Cash ledger; AP settlement; FX gain/loss if foreign currency. | Supplier, open VB, bank/payment method, withholding profile/ATC, open period, PV number. | PV number; audit posted/cancelled; related to VB/VC/JE/2307. | Cancel posts exact reversal and tax counter-row; lock payment applications. | Cash disbursements, AP aging, EWT summary, QAP, 2307. Tests: line-sum totals, VC-aware over-apply, EWT base/rate, source-basis duplicate block, profile gate. |
| Vendor Credit | Reduces AP from supplier credit; triggered by supplier credit note/return/allowance. | Draft -> approved -> posted -> applied/closed -> voided. Approval required by policy. | Post approved VC. | Accounts Payable. | Expense/asset return, Input VAT reversal, inventory if returned. | AP from supplier/company; reversal accounts from source VB/item; VAT from tax profile. | Input VAT reduction; EWT adjustment only if policy requires. | AP subledger reduction; inventory return/stock decrease if linked. | Supplier, source VB optional/required by policy, items, VAT code, reason. | VC number; audit posted/applied/voided; related to VB/PV/JE. | Void reverses VC; application reversal restores balance. Lock after posting except controlled application. | Vendor credit register, AP aging, VAT input adjustment. Tests: VC affects PV over-apply guards. |
| Journal Entry | Manual or recurring GL adjustment; triggered by accountant. | Draft -> posted -> reversed. Approval required by policy and SoD. | Post JE. | User-defined debit lines. | User-defined credit lines. | Manual JE is controlled exception; accounts selected by authorized accountant and validated. | No tax ledger unless tax adjustment JE uses governed tax adjustment document. | GL only; dimensions and FX if configured. | COA, dimensions, open period, balanced lines, postable accounts, JE number. | JE number; audit posted/reversed; related to source if system-generated or manual references. | Reverse through `fn_reverse_je`; no direct delete after posting; lock posted lines. | GL, TB, FS, posting review. Tests: balance, postable accounts, locked period, reversal. |
| Inventory Adjustments | Adjust inventory quantity/value; triggered by stock correction. | Draft -> posted -> reversed/cancelled. Approval required by policy. | Post adjustment. | Inventory or variance/expense depending adjustment direction. | Inventory or variance gain depending direction. | Inventory account from item/warehouse; variance account from item group/company. | No VAT by default. | Quantity/value adjustment; costing layer correction. | Item, warehouse, reason, costing method, branch, open period, number series. | Adjustment number; audit posted/reversed; related to stock count if applicable. | Reverse exact quantity/value effect; lock posted lines. | Stock balance, inventory valuation, GL, COGS/variance. Tests: WAC/cost layer, GL balance, reversal. |
| Stock Transfers | Move stock between warehouses/locations; triggered by transfer confirmation. | Draft -> in transit/posted -> received/closed/cancelled depending policy. | Post transfer issue/receipt or single-step transfer. | Inventory at destination or in-transit account. | Inventory at source or in-transit account. | Inventory accounts by warehouse/item; in-transit account by company/document type. | No VAT by default for internal transfers. | Quantity movement; costing preserved; branch policy required. | Source/destination warehouse, item, quantity, costing method, branch policy. | Transfer number; audit posted/cancelled; related to inventory ledgers. | Reverse transfer if not consumed; lock posted movement. | Inventory movements, valuation, branch stock reports. Tests: source/destination balance, branch attribution. |
| Assemblies | Build or disassemble inventory; triggered by production/assembly completion. | Planned: draft -> released -> posted -> reversed/cancelled. Approval required by policy. | Post assembly completion. | Finished goods inventory; variance if applicable. | Component inventory; labor/overhead/clearing if configured. | Item BOM/routing; component accounts; overhead rules; variance accounts. | No VAT by default for internal production. | Consumes components, creates finished goods, costing roll-up. | BOM, items, warehouse, costing method, production quantity. | Assembly number; audit released/posted/reversed; related to inventory movements. | Reverse if stock not consumed/sold; lock component issue after use. | Inventory valuation, COGS, production variance. Tests: BOM cost, WIP/variance. Exception: not fully implemented. |
| Fixed Assets | Acquire/register fixed asset; triggered by acquisition capitalization. | Draft -> posted/active -> transferred/impaired/disposed. Approval required by policy. | Post acquisition/register. | Fixed asset cost account; Input VAT if claimable. | Cash/AP/clearing or source document account. | Asset category, supplier/source document, tax profile, payment method. | Input VAT if applicable; tax depreciation handled separately. | Creates asset record; depreciation schedule. FX if foreign purchase. | Asset category, useful life, depreciation method, source document, open period. | FA number; audit registered/transferred/disposed; related to VB/cash/JE. | Reverse acquisition if no depreciation/disposal; otherwise correction policy. Lock capitalized cost after depreciation. | Asset register, FA-to-GL, depreciation schedule. Tests: capitalization JE, asset lifecycle. |
| Depreciation | Recognizes periodic depreciation; triggered by scheduled run. | Scheduled -> posted -> reversed. Approval optional by policy. | Post depreciation entry. | Depreciation expense. | Accumulated depreciation. | Asset category depreciation accounts and method. | No VAT. | Reduces net book value; tax/book basis may differ. | Active asset, depreciation method, useful life, open period. | Depreciation run number/JE; audit posted/reversed; related to asset. | Reverse run; lock period once closed/filed. | Depreciation schedule, asset register, FS. Tests: method calculation, reversal, book vs tax. |
| Banking | Bank transfer, adjustment, check, deposit, petty cash; triggered by treasury posting. | Draft -> approved/posted -> reconciled/cancelled. Approval required by policy. | Post bank transaction. | Receiving bank/cash/expense/clearing. | Source bank/cash/liability/clearing. | Bank account GL mapping, payment method, document type. | EWT may apply for check voucher; VAT only if expense document type requires it. | Cash/bank ledger; reconciliation status; FX for foreign bank. | Bank account, currency, payment mode, open period, number series. | Bank/check/transfer number; audit posted/reconciled/cancelled; related to PV/OR/CV. | Cancel/reverse if unreconciled; lock reconciled items unless reconciliation reversal. | Bank position, bank recon, cash books. Tests: reconciliation, cancellation, check lifecycle. |
| Payroll | Compute payroll and statutory liabilities; triggered by payroll run. | Planned: draft -> approved -> posted -> paid -> corrected/voided. Approval required. | Post payroll run. | Salary/wage expense, employer contributions. | Payroll payable/cash, withholding tax payable, statutory liabilities. | Payroll setup, employee profile, compensation/tax tables, liability accounts. | Compensation withholding and statutory contribution tax/report impacts. | Employee payroll ledger; cash/payment file; confidentiality restrictions. | Employees, payroll calendar, tax tables, benefits/deductions, bank. | Payroll run number; audit approved/posted/paid/corrected. | Correction run or reversal by policy; lock paid payroll. | Payroll reports, GL, tax alphalists, cash. Tests: confidentiality, tax, liabilities. Exception: planned. |
| Tax Adjustments | Adjust tax ledger/reporting amounts; triggered by approved tax correction. | Draft -> approved -> posted/filed -> reversed/superseded. Approval required. | Post tax adjustment. | Tax receivable/payable/expense or adjustment account. | Tax payable/receivable/clearing or offset account. | Tax profile, tax code/ATC, adjustment reason, tax account mapping. | Directly affects VAT/PT/EWT/CWT/FWT ledger by governed rule. | No inventory/FA unless adjustment references source. | Tax period, source report/document, reason, approval, open or allowed adjustment period. | Tax adjustment number; audit approved/posted/superseded; related to return/snapshot. | Reverse/supersede, not direct mutation; lock filed period unless approved amendment. | Tax returns, reconciliation, audit package. Tests: filed-period control, snapshot trace. |
| Year-end Closing | Close income statement to retained earnings; triggered by period/year close. | Draft close run -> reviewed -> posted -> locked/reversed by admin policy. Approval required. | Post closing entries. | Revenue accounts or income summary depending method; net loss to retained earnings. | Expense accounts or income summary; net income to retained earnings. | Closing configuration, retained earnings account, income summary account. | Tax reports must already be finalized/snapshotted where required; no new operational tax detail. | Locks fiscal year; updates post-closing TB. FX translation/rounding accounts if configured. | Fiscal year, all periods closed, balanced TB, FS mappings, retained earnings account. | Closing run number; audit reviewed/posted/reversed; related to TB/FS. | Reverse only by controlled reopen policy; lock closed periods/year. | Trial balance, FS, retained earnings, audit support. Tests: adjusted/post-closing TB, income statement zeroing, retained earnings rollforward. |

## 10. Known architecture gaps

These gaps must be resolved before `PXL Accounting Core Ready`:

- Account Determination Engine is not fully implemented.
- Tax Engine is not yet a unified configuration-driven evaluator.
- ATC effective dating/versioning is DONE (session 77, `20260713000002`): validators/callers resolve the ATC window by document date and one official code carries effective-dated versions (`fn_atc_version_asof`). Tax-code (VAT/PT) effective-dated versioning is still open.
- Withholding profiles are incomplete.
- Settlement total authority for OR/PV must move fully server-side.
- Financial statement and year-end close rules are incomplete.
- CAS/BIR evidence package is in place for the current export surfaces: exact exported bytes, CRLF DAT artifacts, source/GL-reconciled books exports, and audit-package snapshots.
- Semantic transaction event log is incomplete.
- Payroll is not implemented.
- Assemblies are not implemented.

## 11. Test expectations

Each transaction type must eventually have tests for:

- successful posting;
- unbalanced posting rejection;
- missing account rejection;
- inactive/non-postable account rejection;
- locked period rejection;
- wrong-company source rejection;
- invalid lifecycle transition rejection;
- source-to-journal trace;
- journal-to-source trace;
- reversal/void/cancel behavior;
- tax ledger creation or no-tax assertion;
- tax counter-row behavior;
- number-series consumption;
- immutability after posting;
- report/reconciliation impact.

## 12. Maintenance rules

When a transaction's accounting behavior changes:

1. Update this matrix.
2. Update `PXL_TRANSACTION_MATRIX.md`.
3. Update `PXL_ACCOUNTING_TEST_BOOK.md`.
4. Update `PXL_END_TO_END_AUDIT_FINDINGS.md` if the change fixes or reveals a production defect.
5. Update implementation only after the rule is defined here.
