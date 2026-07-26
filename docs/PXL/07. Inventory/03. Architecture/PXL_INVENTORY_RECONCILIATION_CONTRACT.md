# PXL Inventory Reconciliation Contract

**Status:** Frozen architecture — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting
**Applies To:** Inventory quantity, valuation, layers/pools, subledger, GL, Trial Balance, and Financial Statements
**Read When:** Building or certifying inventory reconciliation
**Do Not Read For:** Designing journal persistence or substituting adjustment entries for root-cause correction
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Architecture only

## 1. Exactness

All required reconciliations are exact at governed fixed-point precision. A tolerance, plug, hidden adjustment, inferred account set, or unexplained “timing difference” cannot certify equality.

Financial reconciliation uses authoritative functional-currency GL-basis amounts at currency minor-unit scale. Eight-decimal valuation amounts support costing calculations; twelve-decimal unit rates are derived and are never the financial reconciliation source. Deterministic residual allocations bridge valuation amounts to exact posted GL-basis amounts.

Each report identifies:

- company and functional currency;
- cut-off timestamp and accounting period;
- item and valuation scope;
- ownership, warehouse/location, lot/serial, and availability status where applicable;
- costing method and method version;
- source events included/excluded;
- GL control and contra accounts included;
- unresolved exceptions.

## 2. Quantity roll-forward

For every company, item, and physical/ownership scope:

`Beginning owned quantity + receipts + positive adjustments + accepted returns + transfers in - issues - sales consumption - purchase returns - write-offs/disposals - negative adjustments - transfers out = Ending owned quantity`

The following MUST be exactly equal for all costing methods:

1. net owned quantity from the immutable Inventory Movement Ledger;
2. ending on-hand quantity in the rebuilt Stock projection; and
3. method-specific ending valuation quantity.

Reserved, blocked, consigned, damaged, and in-transit quantities are separately classified. They are not silently omitted:

`Available quantity = On-hand owned quantity - Reserved quantity - Blocked quantity`

Available quantity need not equal on-hand quantity.

## 3. Value roll-forward

At gross historical cost:

`Beginning gross inventory + capitalizable receipts + capitalizable landed cost/corrections + transfer value in + accepted return value + positive adjustment value - issue/COGS value - purchase-return value - write-off/disposal value - negative adjustment value - transfer value out = Ending gross inventory`

Separately:

`Beginning valuation allowance + NRV write-downs - capped reversals/releases = Ending valuation allowance`

and:

`Net inventory = lower of historical cost and NRV = Ending gross inventory - Ending valuation allowance`

The Inventory subledger gross value MUST equal the Inventory GL gross control balance. The valuation allowance MUST equal its GL contra-inventory balance. Their net MUST equal the Trial Balance and Financial Statement inventory presentation.

## 4. Method-specific equality matrix

`MUST` means exact equality is required. `N/A` means the object is not an authoritative concept for that method and MUST NOT be used as a reconciliation target.

| Equality at the same cut-off and scope | FIFO | Moving WAC — Model A | Specific Identification |
| --- | --- | --- | --- |
| Stock quantity = net Inventory Movement quantity | MUST | MUST | MUST |
| Stock quantity = method valuation quantity | MUST | MUST: WAC pool quantity | MUST |
| Stock quantity = owned valuation-layer quantity, including blocked/in-transit valued states | MUST | N/A: WAC receipt records are audit-only | MUST |
| Available stock quantity = consumable valuation-layer quantity | MUST | N/A: availability comes from stock/reservation state, not receipt records | MUST |
| Inventory subledger gross value = method valuation value | MUST: remaining FIFO layer value | MUST: WAC pool value | MUST: active identity layer value |
| Inventory subledger gross value = owned valuation-layer value, including non-consumable valued states | MUST for FIFO valuation layers | N/A | MUST for Specific-ID valuation layers |
| Inventory subledger gross value = Inventory GL gross control | MUST | MUST | MUST |
| Valuation-adjustment ledger = GL allowance/contra account | MUST | MUST | MUST |
| Net inventory = Trial Balance inventory presentation | MUST | MUST | MUST |
| Trial Balance inventory = Financial Statement inventory | MUST | MUST | MUST |
| Cumulative method-derived issue value = GL COGS/expense/WIP destinations | MUST by destination | MUST by destination | MUST by destination |
| Inventory in transit subledger = Inventory-in-Transit GL | MUST when applicable | MUST when applicable | MUST when applicable |
| GRNI unmatched receipt value = GRNI GL | MUST | MUST | MUST |
| GINR/Purchase Clearing unmatched bill value = GINR GL | MUST when applicable | MUST when applicable | MUST when applicable |
| Method-state GL-basis value = posted Inventory GL | MUST | MUST | MUST |

For WAC, a report that compares ending stock to the sum of immutable receipt quantities or costs is invalid by definition. Those receipt records reconcile to acquisition history, not available inventory.

## 5. Source-document reconciliation

### 5.1 Goods receipt and GRNI

For each unbilled owned receipt line:

`Owned receipt value = GRNI credit generated by that receipt`

For each matching population:

`Beginning unmatched GRNI + owned receipts - Vendor Bill matches - purchase returns/cancellations ± approved receipt-cost corrections = Ending unmatched GRNI`

The ending unmatched receipt schedule MUST equal the GRNI GL account exactly.

The provisional receipt cost follows the governed hierarchy: approved contract/PO net price; approved shipment price; governed item provisional acquisition cost; otherwise rejection.

### 5.2 Invoice-before-receipt and Purchase Clearing

For bills recorded before control transfer:

`Beginning unmatched GINR + approved pre-control bills - matched ownership-transfer receipts - bill reversals/credits = Ending unmatched GINR = GINR/Purchase Clearing GL`

If control transferred before warehouse receipt, the amount belongs to the Inventory-in-Transit subledger/GL, not GINR. A simultaneous receipt/bill occurrence creates neither an open GRNI nor GINR balance.

### 5.3 Vendor Bills and AP

Vendor Bill quantity is a matching fact, not a second inventory receipt. A bill linked to a prior receipt:

- changes AP and tax;
- clears GRNI for the matched provisional amount;
- sends any source-linked price delta to the Inventory Engine for re-cost allocation.

`Open Vendor Bill liability - Vendor Credits/Debit Memos - settlements = AP subledger balance = AP GL control`

### 5.4 Sales, revenue, and COGS

For every Sales control-transfer occurrence:

`Inventory Engine issue GL-basis value = COGS debit = Inventory credit`

The same occurrence also recognizes the related Sales revenue and AR or contract asset under the Sales/Tax contract. Billing may later reclassify an unbilled balance but cannot move revenue or COGS to another period.

### 5.5 Returns

A physical return and its financial credit are independently complete and explicitly linked. Quantity reconciliation uses the inventory return event; AP/AR and tax reconciliation use the financial document. Neither may stand in for the other.

For a billed purchase return:

`method carrying value removed ± purchase-return cost variance = tax-exclusive Vendor Credit commercial amount`

For an unbilled purchase return:

`method carrying value removed ± purchase-return cost variance = linked GRNI amount cleared`

For a sales return, the inventory receipt uses the latest corrected cost assigned to the original issue as of acceptance. The Credit Memo controls AR/revenue/tax and does not calculate return cost.

### 5.6 Cost-correction destination bridge

Every re-cost delta retains:

- original Inventory issue and destination;
- prior posted amount;
- corrected method amount;
- current-period COGS/expense/WIP correction;
- purchase-return or other variance role where policy requires;
- retained-earnings/adjusting-period amount for a prior-period error;
- comparative-restatement presentation amount;
- journal/source occurrence.

The sum of bridge destinations MUST equal the method-derived correction exactly. Destination-level reconciliation includes the bridge; it never expects a closed-period journal to have been mutated.

## 6. Reconciliation grain

The minimum exact grain is company + functional currency + Inventory control account + accounting cut-off. The reconciliation MUST additionally drill to:

- item;
- valuation scope;
- warehouse/branch/location;
- costing method;
- source document and source line;
- journal and journal line;
- lot/serial for Specific ID;
- valuation layer for FIFO;
- WAC pool version for moving average;
- relevant dimensions carried into GL;
- accounting profile, method-policy, precision, and currency versions.

Warehouse or branch subledger totals need equal warehouse/branch GL only where those dimensions or distinct control accounts are part of the configured GL grain. Otherwise they aggregate exactly to the company control account.

## 7. Manual Journal rule

An unlinked Manual Journal to a protected Inventory, GRNI, GINR/Purchase Clearing, Inventory-in-Transit, inventory-allowance, or Inventory variance control account is a reconciliation violation and MUST be rejected before posting.

Canonical and certification evidence MUST include:

- a rejected ordinary Manual Journal to each protected control-account class; and
- a successful governed opening/correction workflow whose Inventory Engine event and journal remain atomic.

## 8. Exceptions

Every nonzero variance is classified, never auto-cleared:

- missing or duplicate inventory event;
- stock projection defect;
- method-state/layer/pool defect;
- source-link/matching defect;
- event-order defect;
- account-resolution defect;
- missing or duplicate journal;
- dimension/grain mismatch;
- period/cut-off mismatch;
- currency/rounding defect;
- unsupported scenario;
- unauthorized Manual Journal or direct mutation.

An exception report records owner, source IDs, exact amount/quantity, first failing equality, and remediation phase. Reconciliation reporting never creates a journal, changes a source, or mutates inventory state.

## 9. Period close gate

An accounting period cannot receive Inventory reconciliation certification unless:

- all inventory events through cut-off are posted or explicitly excluded with a non-accounting status;
- inventory event/order replay is complete;
- method state is deterministic;
- GRNI, in-transit, and clearing schedules tie exactly;
- gross inventory and allowance tie to GL;
- no protected-account Manual Journal exists without a governed Inventory source;
- every negative/provisional deficit is settled; disclosure alone cannot pass close;
- Sales control-transfer revenue and COGS occurrences share the same accounting period;
- GRNI, GINR/Purchase Clearing, and Inventory-in-Transit balances have no unexplained items;
- every cost correction is fully represented in the destination bridge;
- every variance is zero.

## 10. Proof evidence

Certification retains:

- beginning/increase/decrease/ending schedules;
- movement, layer/pool, stock, and GL fingerprints;
- source-to-event-to-journal trace;
- method-specific state replay;
- reversal and correction ancestry;
- account and dimension mappings;
- policy/method/precision/currency versions and residual allocations;
- purchase-match, GRNI, GINR, and correction-destination schedules;
- exception census;
- deterministic rerun fingerprint.

Passing one aggregate company total cannot conceal item-, warehouse-, source-, or method-level variances.
