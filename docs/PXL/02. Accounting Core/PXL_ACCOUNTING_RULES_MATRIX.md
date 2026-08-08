# PXL Accounting Rules Matrix

Status: Official governed accounting specification
Milestone: PXL Accounting Core Ready
Last updated: 2026-07-14
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

1. `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` — canonical posting behavior specification.
2. Database migrations, RPCs, triggers, and tests — executable implementation.
3. `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md` — broader transaction lifecycle, UX, source-chain, report, and module matrix.
4. `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES.md` — concise accounting rules summary.
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
- customer advances liability account;
- supplier payable account;
- supplier down-payments asset account;
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
| Delivery Receipt | Evidence of goods delivery; triggered by shipment/delivery. | Draft -> confirmed/delivered -> invoiced/closed/cancelled. Approval optional. | Post delivered DR. | Goods Delivered Not Invoiced at authoritative inventory cost. | Inventory Control. | Governed clearing and Inventory mappings; cost supplied only by the shared inventory authority. | No tax ledger; Sales Invoice recognizes tax. | Weighted Average, FIFO or Specific-ID issue; serial/lot selection flows to the database for validation. | Company/customer, item, warehouse, available quantity/identity, open period and mappings. | DR number; inventory transaction/allocation, journal, source/target and CAS evidence. | `fn_void_delivery_receipt` refuses any live invoice claim, then reverses the exact historical issue/allocation and journal. | Tests `120`, `131`, `135`–`137` and committed delivery/inventory lifecycles. Linked SI clears cost and never relieves stock twice. |
| Sales Invoice | Recognizes receivable and revenue; triggered by billing customer. | Draft -> approved -> posted -> paid/partially paid -> voided/reversed. Approval required where workflow configured. | Post approved SI. | Accounts Receivable; COGS for a direct stock line; Percentage Tax Expense when applicable. | Revenue, Output VAT, Inventory Control for a direct stock line, other sales tax/liability accounts; Percentage Tax Payable. | Governed AR/revenue/tax mappings; direct inventory cost comes only from the shared inventory authority. | Output VAT; **Percentage Tax on the line's gross sales for a non-VAT Section 116 taxpayer, borne by the seller and never added to the customer's total**; expected CWT metadata only until receipt. | Direct stock line issues under Weighted Average/FIFO/Specific ID; a DR-linked line clears Goods Delivered Not Invoiced and does not move stock again. | Customer, item/service, branch, tax, revenue, period and mappings; warehouse/identity and sufficient stock for direct issue; delivered-stock relationship guard. | SI number; audit, inventory transaction/allocation, related DR/OR/CM and JE. | Void posts exact GL/tax reversal and restores the historical inventory allocation/identity; posted lines locked. | Tests `054`, `120`, `133`, `135`–`137`; sales/GL/tax/inventory reports. |
| Official Receipt | Records customer collection; triggered by payment receipt. | Draft -> posted -> bounced/cancelled/voided. Approval optional by policy. | Post OR. | Cash/bank; CWT receivable if withheld. | Accounts Receivable for SI applications; customer advances liability for customer-advance lines. | Cash/bank from payment method/bank; AR/customer-advance clearing from company/customer; CWT from tax profile. | CWT receivable when customer withholds, including customer advances; tax base from configured policy. No output VAT unless cash-basis tax policy exists. | Cash ledger; AR settlement for SI applications; customer-advance liability for unapplied advances; FX gain/loss if foreign currency. | Customer, open SI or explicit customer-advance line, bank/payment method, CWT profile/ATC, open period, OR number, customer advances account when used. | OR number; audit posted/bounced/cancelled; related to SI/CM/JE/2307 received. | Bounce/cancel posts exact reversal and tax counter-row; lock posted application lines. | Collections, AR aging for SI applications, cash receipts book, SAWT/CWT reports. Tests: line-sum total authority, CWT base/rate, over-apply including CM, customer-advance CWT. |
| Credit Memo | Reduces customer receivable/revenue; a warehouse-bearing, source-linked line is also the Customer Return. | Draft -> approved -> posted -> applied/closed -> voided. Approval required by policy. | Post approved CM. | Sales returns/allowances or revenue reversal; Output VAT reversal; Inventory Control for returned goods. | Accounts Receivable; COGS reversal for returned goods. | Governed return/revenue/VAT/AR mappings; inventory value from the source SI issue evidence. | Output VAT counter/reduction; CWT impact only through application/settlement policy. | Financial memo has no stock; Customer Return restores historical Weighted Average cost, exact FIFO allocation, or the same Specific-ID serial/lot. | Customer, source SI and bounded original line quantity for stock return, warehouse/identity, VAT/reason. | CM number; source SI line, inventory transaction/allocation, audit and JE. | Void reverses CM/tax and governed return effect; application reversal restores open balance. | Tests `058`, `120`, `137`; credit memo, AR, tax, inventory valuation and GL reports. |
| Debit Memo | Increases customer receivable; triggered by additional billing, charge, or correction. | Draft -> approved -> posted -> paid/closed -> voided. Approval required by policy. | Post approved DM. | Accounts Receivable. | Revenue/other income, Output VAT if taxable. | AR from customer/company; income account from item/document type; VAT from tax profile. | Output VAT if taxable; Percentage Tax if applicable. | AR subledger increase; no inventory by default. | Customer, reason/type, tax profile, income account, number series, open period. | DM number; audit posted/voided; related to SI/OR/JE. | Void posts exact reversal and tax counter-row; cancel only before posting. | Debit memo register, AR aging, VAT output. Tests: balanced JE, tax rows, void reversal. |
| Purchase Request | Internal purchase request; triggered by requester. | Draft -> submitted -> approved/rejected -> converted/cancelled. Approval required by policy. | No GL posting. | None. | None. | Budget/cost center only; no GL posting. | No tax ledger. | Optional budget encumbrance if future policy enabled. | Requester, department, cost center, item/service, budget. | PR number; audit submitted/approved/cancelled; related to PO. | Cancel before conversion; lock approved/converted lines. | Procurement pipeline, budget reports. Tests: no JE, approval and conversion trace. |
| Purchase Order | Supplier purchase commitment; triggered by approved PR or direct PO. | Draft -> approved -> issued -> partially received -> closed/cancelled. Approval required by policy. | No GL posting by default. | None. | None. | Item/supplier/account preview only; no posting unless commitment accounting enabled. | Tax preview only; no tax ledger. | Optional inventory on order; no quantity on hand until RR. | Supplier, item/service, warehouse, terms, delivery terms, budget, PO number. | PO number; audit approved/issued/cancelled; related to PR/RR/VB. | Cancel open quantities; lock received/billed quantities. | PO register, commitments, receiving. Tests: no JE, conversion controls. |
| Receiving Report | Records goods received against a supplier Purchase Order. | Draft -> received -> cancelled. Confirmation is the posting act. | `fn_confirm_receiving_report` after exact PO-line quantity validation. | Inventory Control. | Goods Received Not Invoiced / purchase clearing. | Governed company mappings; cost and layer/identity evidence come from the shared inventory authority, never the browser. | None; receipt is not the supplier's taxable invoice. | Weighted Average increases the pool; FIFO creates a receipt layer; Specific ID creates required serial/lot identity layers. | Company membership; exact PO/company/item line; concurrency-safe remaining quantity; warehouse/UOM/period/mappings; identity requirements. | RR number; source PO, optional Vendor Bills, journal, inventory/layer and CAS evidence. | `fn_void_receiving_report` refuses live bill claims and any source quantity/value/layer not fully available. After downstream correction it removes the exact historical receipt for all three methods, reverses the JE and reopens PO progress. | Tests `134`–`137`, UI contract and committed purchasing/inventory lifecycles. Price variance is explicitly outside this rule. |
| Vendor Bill | Recognizes payable and expense/asset/input VAT; triggered by supplier invoice. | Draft -> approved -> posted -> paid/partially paid -> voided. Approval required where configured. | Post approved VB after the same readiness validator used by approval. | Expense/asset/inventory clearing; Input VAT. | Accounts Payable net of source EWT; EWT Payable when source-basis EWT applies. | AP from company/supplier; expense/asset from item group/item/document type; input VAT from tax profile/code. | Input VAT; AP EWT policy defaults to source/accrual at VB, requires an enabled EWT compliance profile when EWT is present, may use supplier default ATC/base/amount, and auto-defaults TWA supplier-subject goods/services to WC158/WC160 when enabled. | AP subledger; a bill with `rr_id` consumes receipt clearing and is quantity-matched per item; a no-`rr_id` expense/service or intentional bill-without-receipt flow remains valid. | Supplier, invoice data, items/expenses, tax profile, VAT code, withholding profile/default ATC, open period, VB number; when linked, receipt company/supplier/status must match and cumulative live bill quantity must not exceed received quantity. | VB number; audit approved/posted/voided; related to PO/RR/PV/VC/JE/2307. | Void posts exact reversal and tax counter-rows; posted locked; every live bill claim, including a draft, blocks RR cancellation until corrected. | Purchase register, AP aging, input VAT, SLP/SLSP, QAP. Tests: EWT policy, VAT, RR linkage/exact quantity match, void, withholding profile/TWA defaults. Price variance remains a separate policy decision. |
| Payment Voucher | Records supplier payment; triggered by payment approval/release. | Draft -> posted/released -> cancelled/voided. Approval required by policy. | Post PV/payment. | Accounts Payable for VB applications; supplier down-payments asset for down-payment lines. | Cash/bank; EWT payable only for payment-basis withholding or supplier down-payments. | AP/supplier down-payment clearing from company/supplier; bank from payment method; EWT from tax profile/ATC when not already accrued at VB. | Payment-basis EWT payable and supplier down-payment EWT require an enabled EWT compliance profile; source-accrued VBs reject duplicate PV EWT and settle cash-only; 2307 source follows the tax-detail source. | Cash ledger; AP settlement for VB applications; supplier down-payment asset for unapplied down-payments; FX gain/loss if foreign currency. | Supplier, open VB or explicit supplier down-payment line, bank/payment method, withholding profile/ATC, open period, PV number, supplier down-payments account when used. | PV number; audit posted/cancelled; related to VB/VC/JE/2307. | Cancel posts exact reversal and tax counter-row; lock payment applications. | Cash disbursements, AP aging for VB applications, EWT summary, QAP, 2307. Tests: line-sum totals, VC-aware over-apply, EWT base/rate, source-basis duplicate block, profile gate, supplier down-payment EWT. |
| Vendor Credit | Reduces AP from supplier credit; triggered by supplier credit note/return/allowance. | Draft -> approved -> posted -> applied/closed -> voided. Approval required by policy. | Post approved VC. | Accounts Payable. | Expense/asset return, Input VAT reversal, inventory if returned. | AP from supplier/company; reversal accounts from source VB/item; VAT from tax profile. | Input VAT reduction; EWT adjustment only if policy requires. | AP subledger reduction; inventory return/stock decrease if linked. | Supplier, source VB optional/required by policy, items, VAT code, reason. | VC number; audit posted/applied/voided; related to VB/PV/JE. | Void reverses VC; application reversal restores balance. Lock after posting except controlled application. | Vendor credit register, AP aging, VAT input adjustment. Tests: VC affects PV over-apply guards. |
| Journal Entry | Manual or recurring GL adjustment; triggered by accountant. | Draft -> posted -> reversed. Approval required by policy and SoD. | Post JE. | User-defined debit lines. | User-defined credit lines. | Manual JE is controlled exception; accounts selected by authorized accountant and validated. Every JE carries an `entry_class` (regular / adjusting / opening via `fn_post_manual_je`; closing is engine-only). | No tax ledger unless tax adjustment JE uses governed tax adjustment document. | GL only; dimensions and FX if configured. | COA, dimensions, open period, balanced lines, postable accounts, JE number. | JE number; audit posted/reversed; related to source if system-generated or manual references. | Reverse through `fn_reverse_je`; no direct delete after posting; lock posted lines. | GL, TB, FS, posting review. Tests: balance, postable accounts, locked period, reversal, classification. |

### Year-end close and Trial Balance modes (PXL-AUD-013 / PXL-DA-014, DEC-019)

- **Entry classification.** `journal_entries.entry_class` ∈ {`regular`, `adjusting`, `closing`, `opening`}. Document-sourced and normal manual journals are `regular`; period-end adjustments are `adjusting`; opening balances are `opening`; year-end closing journals are `closing` (posted only by the close engine — the manual RPC rejects `closing`).
- **Trial Balance modes** read `vw_general_ledger.entry_class`: **Unadjusted** = regular + opening; **Adjusted** = + adjusting; **Post-Closing** = + closing. A post-closing TB shows every revenue/expense account at zero with net income carried in retained earnings.
- **Year-end close.** `fn_close_fiscal_year(company, fiscal_year[, close_date])` posts one balanced closing journal (`entry_class='closing'`, `reference_doc_type='CLOSE'`) that zeroes the year's revenue/expense accounts and carries net income/loss **directly to `fiscal_years.retained_earnings_id`** (no Income Summary — DEC-019), then locks the year's periods and sets the fiscal year `closed`. Requires a postable, active equity retained-earnings account; re-closing a closed year is rejected. FS-line mapping and IS/BS/RE statement wiring remain backlog enhancements.
| Inventory Adjustments | Adjust inventory quantity/value; triggered by stock correction. | Draft -> posted -> reversed/cancelled. Approval required by policy. | Post adjustment. | Inventory or variance/expense depending direction. | Inventory or variance gain depending direction. | Inventory and variance mappings; cost from the shared authority. | No VAT. | Positive adjustment receives at governed cost; negative adjustment consumes Weighted Average, FIFO allocations or selected Specific ID. | Item, warehouse, reason, method/identity, branch, open period, mappings. | Adjustment number; inventory transaction/allocation, journal and audit. | Correct with a governed opposite event; posted evidence is locked. | Test `136` proves a negative FIFO adjustment uses exact layer cost and reconciles valuation/GL. |
| Stock Transfers | Move stock between warehouses/locations without changing company-wide value. | Draft -> posted/closed/cancelled depending policy. | Post one governed source issue and destination receipt. | Destination Inventory. | Source Inventory. | Inventory mappings; the shared authority carries historical cost. | No VAT. | Weighted Average carries historical issue value; FIFO carries layer lineage; Specific ID moves the same serial/lot. | Source/destination company warehouses, item, quantity, available identity and branch policy. | Transfer number; paired movements, parent layer/allocation and audit. | A later correction must preserve the same cost/identity lineage; posted evidence is locked. | Test `136` proves a serial moves warehouses with its cost, parent layer and unchanged company-wide value. |
| Assemblies | Build or disassemble inventory; triggered by production/assembly completion. | Planned: draft -> released -> posted -> reversed/cancelled. Approval required by policy. | Post assembly completion. | Finished goods inventory; variance if applicable. | Component inventory; labor/overhead/clearing if configured. | Item BOM/routing; component accounts; overhead rules; variance accounts. | No VAT by default for internal production. | Consumes components, creates finished goods, costing roll-up. | BOM, items, warehouse, costing method, production quantity. | Assembly number; audit released/posted/reversed; related to inventory movements. | Reverse if stock not consumed/sold; lock component issue after use. | Inventory valuation, COGS, production variance. Tests: BOM cost, WIP/variance. Exception: not fully implemented. |
| Fixed Assets | Acquire/register fixed asset; triggered by acquisition capitalization. | Draft -> posted/active -> transferred/impaired/disposed. Approval required by policy. | Post acquisition/register. | Fixed asset cost account; Input VAT if claimable. | Cash/AP/clearing or source document account. | Asset category, supplier/source document, tax profile, payment method. | Input VAT if applicable; tax depreciation handled separately. | Creates asset record; depreciation schedule. FX if foreign purchase. | Asset category, useful life, depreciation method, source document, open period. | FA number; audit registered/transferred/disposed; related to VB/cash/JE. | Reverse acquisition if no depreciation/disposal; otherwise correction policy. Lock capitalized cost after depreciation. | Asset register, FA-to-GL, depreciation schedule. Tests: capitalization JE, asset lifecycle. |
| Depreciation | Recognizes periodic depreciation; triggered by scheduled run. | Scheduled -> posted -> reversed. Approval optional by policy. | Post depreciation entry. | Depreciation expense. | Accumulated depreciation. | Asset category depreciation accounts and method. | No VAT. | Reduces net book value; tax/book basis may differ. | Active asset, depreciation method, useful life, open period. | Depreciation run number/JE; audit posted/reversed; related to asset. | Reverse run; lock period once closed/filed. | Depreciation schedule, asset register, FS. Tests: method calculation, reversal, book vs tax. |
| Banking | Bank transfer, adjustment, check, deposit, petty cash; triggered by treasury posting. | Draft -> approved/posted -> reconciled/cancelled. Approval required by policy. | Post bank transaction. | Receiving bank/cash/expense/clearing. | Source bank/cash/liability/clearing. | Bank account GL mapping, payment method, document type. | EWT may apply for check voucher; VAT only if expense document type requires it. | Cash/bank ledger; reconciliation status; FX for foreign bank. | Bank account, currency, payment mode, open period, number series. | Bank/check/transfer number; audit posted/reconciled/cancelled; related to PV/OR/CV. | Cancel/reverse if unreconciled; lock reconciled items unless reconciliation reversal. | Bank position, bank recon, cash books. Tests: reconciliation, cancellation, check lifecycle. |
| Payroll | Compute payroll and statutory liabilities; triggered by payroll run. | Planned: draft -> approved -> posted -> paid -> corrected/voided. Approval required. | Post payroll run. | Salary/wage expense, employer contributions. | Payroll payable/cash, withholding tax payable, statutory liabilities. | Payroll setup, employee profile, compensation/tax tables, liability accounts. | Compensation withholding and statutory contribution tax/report impacts. | Employee payroll ledger; cash/payment file; confidentiality restrictions. | Employees, payroll calendar, tax tables, benefits/deductions, bank. | Payroll run number; audit approved/posted/paid/corrected. | Correction run or reversal by policy; lock paid payroll. | Payroll reports, GL, tax alphalists, cash. Tests: confidentiality, tax, liabilities. Exception: planned. |
| Tax Adjustments | Adjust tax ledger/reporting amounts; triggered by approved tax correction. | Draft -> approved -> posted/filed -> reversed/superseded. Approval required. | Post tax adjustment. | Tax receivable/payable/expense or adjustment account. | Tax payable/receivable/clearing or offset account. | Tax profile, tax code/ATC, adjustment reason, tax account mapping. | Directly affects VAT/PT/EWT/CWT/FWT ledger by governed rule. | No inventory/FA unless adjustment references source. | Tax period, source report/document, reason, approval, open or allowed adjustment period. | Tax adjustment number; audit approved/posted/superseded; related to return/snapshot. | Reverse/supersede, not direct mutation; lock filed period unless approved amendment. | Tax returns, reconciliation, audit package. Tests: filed-period control, snapshot trace. |
| Year-end Closing | Close income statement to retained earnings; triggered by period/year close. | Draft close run -> reviewed -> posted -> locked/reversed by admin policy. Approval required. | Post closing entries. | Revenue accounts or income summary depending method; net loss to retained earnings. | Expense accounts or income summary; net income to retained earnings. | Closing configuration, retained earnings account, income summary account. | Tax reports must already be finalized/snapshotted where required; no new operational tax detail. | Locks fiscal year; updates post-closing TB. FX translation/rounding accounts if configured. | Fiscal year, all periods closed, balanced TB, FS mappings, retained earnings account. | Closing run number; audit reviewed/posted/reversed; related to TB/FS. | Reverse only by controlled reopen policy; lock closed periods/year. | Trial balance, FS, retained earnings, audit support. Tests: adjusted/post-closing TB, income statement zeroing, retained earnings rollforward. |

### Production inventory-costing authority — DELIVERED LOCALLY 2026-08-08

- **One authority, three strategies.** `fn_receive_inventory`,
  `fn_issue_inventory`, `fn_return_inventory`, `fn_transfer_inventory` and their
  reversal helpers own quantity and valuation. Public document entry points
  delegate to them; only the Posting Engine/Accounting Kernel writes the GL.
- **Historical truth.** Weighted Average stamps the issued rate. FIFO writes
  immutable source-layer allocations. Specific Identification requires a serial
  or lot and takes cost from the selected identity. Reversal/return uses that
  stored evidence, never today's pool or layers.
- **Correction order.** A source receipt cannot be cancelled while a live bill
  claims it or while its exact quantity/value/layer has been consumed. Correct
  downstream documents first; the original allocation/identity is restored, and
  only then may the source receipt be removed.
- **Concurrency and succession.** Layer rows are locked during admission, so two
  writers cannot over-consume a layer or serial. Item/default method changes fail
  closed after inventory activity; posted history is not reinterpreted.
- **Scope/evidence.** Receiving Report, Cash Purchase, Delivery Receipt, direct
  Sales Invoice, Cash Sale, Goods Issue, adjustment, transfer, physical count,
  Customer Return/Credit Memo and Purchase Return use the authority. Tests
  `135`–`137` plus `verify:inventory-costing-lifecycle` prove cost, identity,
  correction, GL and valuation locally. This does not activate dormant IA-5/ECC,
  certify the Inventory module, prove hosted parity or establish pilot readiness.

### Percentage tax (Section 116) — DELIVERED 2026-08-04, migration `20260804000001`

- **What it is.** Percentage tax is the business tax of a **non-VAT** taxpayer on
  its gross sales or receipts. It is the seller's own tax: it is not charged to
  the customer, not added to the invoice total, and never priced inside the line.
- **Where the code lives.** Per line, on `sales_invoice_lines.percentage_tax_code_id`,
  selected from `fn_business_tax_codes_asof` — the one business-tax picker, which
  offers percentage-tax codes only to a non-VAT, percentage-tax-registered company
  and only on a sales document. `fn_resolve_business_tax_code` is the only place
  either family's validity is decided; it delegates the VAT half verbatim to
  `fn_resolve_vat_code`.
- **The rate.** `tax_codes` is the governed rate holder and the company code is an
  effective-dated version of it. A statutory rate change closes the current
  version and starts a successor; it never edits a row that has been used.
- **The posting.** DR `PERCENTAGE_TAX_EXPENSE` / CR `PERCENTAGE_TAX_PAYABLE`, equal
  and opposite, inside the sales journal, on both Sales Invoice and Cash Sale.
  Receivable, revenue and cash are unaffected.
- **Recognition basis.** On the sales document (accrual on gross sales). Section
  116 measures services on collections; Cash Sale collects at the same instant, so
  the two agree there, and the receipts basis for a credit invoice is recorded in
  the Product Backlog rather than assumed here.
- **The ledger and the return.** One `tax_detail_entries` row per code per
  document, stamped with the tax-code version, its rate and the 2551Q ATC;
  `fn_percentage_tax_gl_reconciliation` ties it to the payable control account;
  `fn_generate_pt_return` builds the 2551Q and its working paper from that ledger
  and a return may not be marked final or filed while it disagrees with it.
- **Not covered.** Credit-memo reversal of percentage tax, and any rule compelling
  a percentage-tax-registered company to put its code on every line.

### The compliance capability pipeline — STANDARD, owner decision 2026-08-04

Every compliance capability, current and future, is built and measured against
one pipeline. Each stage **consumes** the one before it:

> Posted Transactions → Tax Engine → Tax Ledger → Reconciliation → Working Paper
> → Filing Artifact → Export → Filed Record

- **The Filing Artifact is the system of record for compliance outputs.** Any UI,
  export, snapshot, API or integration — present or future — **consumes the
  Filing Artifact**. None may rebuild a compliance report from transactions, from
  the tax ledger, or in the browser. A compliance figure has one origin, and
  every surface that shows it is downstream of that origin. **As of 2026-08-05
  every current-product compliance surface conforms**; the SLSP screen, the last
  exception, moved onto the quarterly artifact with Backlog 8e (ii). The rule
  binds the **Filing Stage**; **Review Stage** surfaces (SLS, SLP, RELIEF, the
  VAT/PT reviews and the compliance dashboards) read posted source data by
  design — the test is whether the figure would be keyed onto a BIR form.
  FWT/1601FQ is an excluded future
  extension and carries no current conformity or readiness weight.
  `fn_snapshot_wht_export` and the eight VAT/EWT/1601EQ/PT
  legacy working-paper tables were **retired** on 2026-08-04 (Backlog 8f,
  migration `20260804000006`) after their governed replacements were reachable;
  `fn_snapshot_vat_export` and `fn_snapshot_books_export` remain, read source
  views, and are covered by items 8c and 19. The governed state is asserted, not
  asserted-in-prose: test `129` and `tests/compliance_architecture.test.ts`.
- **Exactly one authoritative implementation per stage, per compliance area.**
  For every current area (VAT, percentage tax, EWT/CWT, SAWT, SLSP, QAP, Books) each of
  the seven stages has **one** implementation and no more. **Parallel
  implementations are not allowed** — not a second calculator, not a second
  reconciliation, not a second working-paper store, not a per-form exporter, not
  a hand-keyed surface beside a generated one. Where a stage legitimately needs
  several faces (the VAT, withholding and percentage-tax reconciliations, say),
  they are **delegations to the one implementation** and compute nothing
  themselves.
- **No feature bypasses a stage**, and no stage may acquire a second engine —
  no filing-specific calculator, no export-side recomputation, no browser
  aggregation. The browser presents governed results; it is never a second
  accounting engine.
- **Replacing an implementation is ordered, never reversed.** Migrate the
  consumers onto the governed implementation first, verify no dependency remains,
  and only then retire the legacy objects. A legacy object is never dropped
  before its replacement is reachable, and a superseded store is **retired, not
  populated**.
- **No orphans.** An object that no governed consumer reaches is either
  integrated into this pipeline or retired. Dead code is not kept indefinitely.
- **Registering a form is configuration.** A new return or listing is a seed row
  in `ref_filing_artifact` (+ its tax kinds) and consumes the existing posting,
  tax-ledger and reconciliation framework. Form-specific rules belong in
  metadata, configuration and effective-dated masters, **not hardcoded branches**.
- **A reconciling item explains a difference and never creates one** (owner
  decision, 2026-08-04; migration `20260804000005`, test `128`). An accountant
  may record a manual, typed item against a **draft** filing artifact stating a
  reason, reference, amount, remarks, user and timestamp, fully audited. It is
  excluded from tax calculation, from working-paper totals, from filing-artifact
  totals and from GL reconciliation; it never creates a journal entry and never
  changes a computed amount; it appears on the working paper and in the CSV
  export **as a note**, never in a DAT alphalist the Bureau ingests; and it is
  frozen once the artifact leaves draft. The exclusions are **structural**: its
  amount lives in `reconciling_amount`, a column no computation reads, and a
  CHECK forces its tax figures to zero — so a total written without knowledge of
  reconciling items is still correct in their presence. This is one working paper
  with two kinds of line, **not a second working-paper store**.
- **Declaring a compliance record final or filed requires owner/admin.** True of
  `vat_returns`, `pt_returns`, `ewt_returns` and the legacy working papers since
  2026-07-01, and of `filing_artifacts` since 2026-08-04 — it had been the one
  compliance record with no role gate, which made the governed pipeline weaker
  than the architecture it replaces.
- **Filing Artifact ≠ Filed Record.** A *Filing Artifact* is what PXL generates
  from the books. A *Filed Record* is the accountant's declaration that it was
  submitted. **PXL never assumes successful BIR submission** and will not do so
  unless an e-submission integration is deliberately built.
- A capability's status is reported as its position along this pipeline, so
  "partial" always names which stage is missing.

### BIR filing artifacts — ENGINE DELIVERED 2026-08-04, migration `20260804000002`

- **The one path.** Posted Transactions → Tax Engine → Tax Ledger →
  Reconciliation → Working Paper → Filing Artifact → Export → Filed Record. No
  form has its own query, and no filing figure is computed in a browser.
- **What a tax kind is.** `ref_tax_ledger_control` states, per tax kind, the
  governed account key that controls it, its normal balance, which journal
  statuses count toward it and which reference document types are excluded. Those
  four facts used to be the only differences between three reconciliation
  functions; they are now configuration.
- **The one reconciliation.** `fn_tax_ledger_gl_reconciliation(company, kinds[],
  from, to)` ties any tax kind to its control account. `fn_vat_gl_reconciliation`,
  `fn_wht_gl_reconciliation` and `fn_percentage_tax_gl_reconciliation` are
  delegations that keep their signatures and semantics and compute nothing.
- **What an artifact is.** `ref_filing_artifact` + `ref_filing_artifact_kind`
  register a form's period basis, the tax kinds it consumes, the sign each kind
  carries in its net (+1 owed, −1 credit, 0 for a listing) and the dimensions it
  groups by. **Registering the next form is a seed row, not a function.**
- **The one reader.** `fn_filing_working_paper(company, form, year, period)` reads
  the posted tax ledger and groups by exactly the dimensions the artifact
  declares; a dimension the form does not group by is collapsed. That is what
  lets one query serve a summary return and a per-counterparty alphalist alike.
- **The artifact.** `fn_generate_filing_artifact` writes a `filing_artifacts`
  header and its lines. An artifact may not leave draft while it disagrees with
  the ledger it claims to summarise, may not be regenerated once final or filed,
  is immutable once filed, and cannot be deleted unless it is a draft.
- **Registered:** 2550Q, 2551Q, 1601EQ, SLSP, SAWT, and QAP (2026-08-04,
  migration `20260804000004`) — a seed row plus its tax kind, no function change.
- **Stated, not derived.** On the 2550Q, input VAT carried over from the prior
  quarter and VAT already paid within the quarter are the accountant's figures.
  They are passed to `fn_generate_vat_return` and netted there, so the net payable
  still has exactly one author. **A figure that a governed source already
  determines is never stated.** The 1601EQ has none: `remitted_prior` is derived
  from the posted 0619-E remittances through `fn_compute_ewt_remitted_prior`,
  because PXL-AUD-041 already made that the only figure the gate will accept.
- **Projections — DELIVERED.** `vat_returns` (2550Q), `pt_returns` (2551Q) and
  `ewt_returns` (1601EQ, 2026-08-04, `fn_generate_ewt_return`) are projections of
  the artifact for the screens that read them; the screens write only status,
  filing date and reference. A return is **generated, never typed**.
- **Alphalists tie to the return they attach to.** The QAP and the 1601EQ read the
  same ledger population through the same reader, so the alphalist adds up to the
  return by construction. `fn_qap_2307_reconciliation` compares that alphalist to
  the Form 2307 certificates actually issued, per payee and ATC, and consumes the
  artifact working paper rather than a source view.
- **Export — DELIVERED 2026-08-04**, migration `20260804000003`, Backlog 8d.
  `ref_filing_export_column` holds each form's layout as configuration, and its
  `source_field` CHECK admits no transaction or tax-ledger source, so a
  non-conforming layout is **unwritable**. `fn_filing_artifact_export` serves
  every form in CSV and DAT through the existing `fn_export_*` primitives and
  aggregates nothing. `fn_snapshot_filing_artifact_export` writes the evidence
  row keyed to the artifact's **own id**, and the download is read back from that
  row. A draft artifact, or one whose ledger no longer ties to the GL, is refused.
- **The working paper is one surface.** `FilingWorkingPapersPage` serves the
  2550Q, 1601EQ and 2551Q schedules from `fn_filing_working_paper`; the four
  hand-keyed screens it replaced were deleted on 2026-08-04. A governed working
  paper groups by the dimensions its form is filed on and states a document
  count, and the documents behind any line stay reachable through the accounting
  trace — which is how the per-document detail of the retired screens survives.
- **Not covered.** Nothing is transmitted to the Bureau; a `filed` status records
  the accountant's own submission. Every current-product compliance screen —
  including the SLSP screen since 2026-08-05 — is wired to the governed export.
  The four remaining FWT/1601FQ prototype tables
  and two screens are a 🔮 excluded future extension; they do not participate in
  the current product architecture or its readiness assessment.

## 10. Known architecture gaps

These gaps must be resolved before `PXL Accounting Core Ready`.

**Scope note, owner ruling 2026-08-04.** This list covers Philippine SME
accounting and compliance only. Final Withholding Tax (1601FQ / 2306), Payroll,
Form 2316, quarterly and annual Income Tax, MCIT / RCIT, NOLCO, OSD, Fringe
Benefits Tax, Transfer Pricing, Consolidation Tax and specialized-industry tax
features are **future product extensions**: they are not gaps against this
milestone and must not be read as production blockers. The ranked future
priorities after the current compliance work are Banking & Treasury, then Fixed
Assets.

- Account Determination Engine is not fully implemented.
- Tax Engine is not yet a unified configuration-driven evaluator.
- ATC effective dating/versioning is DONE (session 77, `20260713000002`): validators/callers resolve the ATC window by document date and one official code carries effective-dated versions (`fn_atc_version_asof`). VAT effective-dated resolution is DONE (2026-08-03, `20260803000002`) and percentage-tax code versioning is DONE (2026-08-04, `20260804000001`).
- Withholding profiles are incomplete.
- Settlement total authority for OR/PV must move fully server-side.
- Financial statement and year-end close rules are incomplete.
- CAS/BIR evidence package is in place for the current export surfaces: exact exported bytes, CRLF DAT artifacts, source/GL-reconciled books exports, and audit-package snapshots.
- Semantic transaction event log is incomplete.
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
2. Update `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`.
3. Update `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md`.
4. Update `PXL_END_TO_END_AUDIT_FINDINGS.md` if the change fixes or reveals a production defect.
5. Update implementation only after the rule is defined here.
