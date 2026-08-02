# PXL Inventory Costing Specification

**Status:** Frozen architecture — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting
**Applies To:** FIFO, moving weighted average, Specific Identification, landed cost, re-costing, and negative inventory
**Read When:** Implementing or certifying inventory valuation calculations
**Do Not Read For:** Journal persistence or tax-rate calculation
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Architecture only

## 1. Common costing contract

Every stocked item has one effective-dated costing method within one valuation scope and one governed nature-and-use cost-formula policy group:

- FIFO;
- moving weighted average cost (`WAC`); or
- Specific Identification.

The valuation-scope key is company + item + functional/valuation currency + configured company/branch/warehouse scope. Costing method and scope cannot change within a transaction. Inventories with similar nature and use MUST use one formula; geography alone cannot justify a different formula.

Specific Identification is permitted only for non-interchangeable inventory, goods/services segregated for a specific project, or another approved fact pattern where exact identity determines cost. Serial or lot tracking alone does not make interchangeable inventory eligible.

All methods consume the same normalized inventory event stream:

- owned receipts;
- issues;
- transfers in/out;
- accepted sales returns and purchase returns;
- quantity adjustments;
- landed-cost and purchase-cost corrections;
- write-offs/disposals;
- reversals; and
- opening events.

Event order is deterministic and independent of database insertion order. This sentence was **partly superseded** by ADR-C01 §6.3 and §14 (frozen; see `docs/PXL/archive/ia5-ecc-frozen/`): that design held the authoritative order to be the Economic Costing Chronology tuple — economic effective instant, causal precedence, event-effect rank, source-type rank, source-document order key, source-line ordinal, lifecycle-transition rank, occurrence ordinal, event ordinal, and immutable pre-admission source identity — derived per ECC-01 (frozen). **That programme is frozen and is not the operative costing authority.** The operative model is `ADR-IAA-001_WEIGHTED_AVERAGE_VALUATION_MODEL.md` with a deterministic `(layer_date, created_at, id)` tie-break. An admission-generated event ID or sequence is not a tie-break. The FIFO, WAC, and Specific Identification calculations in this specification are unchanged.

### 1.1 Cost basis

Capitalizable cost is purchase consideration net of trade discounts plus non-recoverable tax and directly attributable landed cost. Recoverable tax is excluded. Amounts are maintained at governed internal precision; GL currency rounding occurs only at the approved boundary. Residual rounding is assigned deterministically and disclosed.

Inventory initial functional-currency cost uses the effective exchange rate when control transfers. Subsequent exchange movement on monetary AP is excluded from inventory. Settlement discounts and supplier rebates that reduce purchase price create source-linked cost corrections; financing and genuine service/promotional consideration remain outside inventory cost.

### 1.2 Immutable calculations

A posted valuation result is never overwritten. A correction creates a new versioned cost event that references the corrected source and records:

- prior calculated value;
- corrected calculated value;
- delta allocated to on-hand inventory;
- delta allocated to COGS, expense, WIP, or variance;
- effective date and accounting posting date;
- affected event range;
- resulting journal identity.

### 1.3 Fixed-point and authoritative monetary values

Binary floating point is prohibited.

| Quantity or amount | Frozen precision |
| --- | --- |
| Base-UOM quantity | Item/UOM-declared fixed-point scale from 0 through 6 decimal places |
| Valuation calculation amount | Signed fixed-point amount at 8 decimal places |
| Derived unit rate/average | Signed fixed-point rate at 12 decimal places |
| Functional-currency GL-basis amount | Currency minor-unit scale; PHP uses 2 decimal places |

Each source quantity converts once to one authoritative base-UOM quantity. The source UOM, ratio, converted quantity, and indivisible-unit residual are retained. A transaction that cannot represent a required indivisible unit at the item scale is rejected.

Authoritative financial values are extended valuation amounts and their functional-currency GL-basis allocations. Unit cost is derived and cannot be multiplied after rounding to reconstruct authoritative value.

Residual allocation follows one policy:

1. calculate all extended values at valuation precision;
2. round the posting population to currency minor units;
3. allocate the currency residual by largest absolute fractional remainder;
4. break ties by stable source-line/order key;
5. on final layer/pool/identity consumption, assign the exact remaining GL-basis amount so quantity and value reach zero together.

Internal transfers carry the exact source GL-basis amount into the destination. A rounding or residual amount is evidence, not a tolerance.

## 2. FIFO

### 2.1 Receipt and layer creation

Each owned receipt line creates one or more FIFO valuation layers for differing valuation scope, ownership status, cost basis, or source identity. Physical lot/serial identity is held in a separate trace allocation and does not split or select FIFO valuation cost unless the item uses Specific Identification.

A FIFO layer records original quantity, remaining quantity, original and adjusted unit cost, original and remaining value, source receipt line, event ordering key, location, and audit identity.

### 2.2 Consumption

- Available positive layers are consumed in ascending effective receipt order.
- The immutable event ordering key breaks same-time ties.
- Consumption may be whole or partial.
- One issue may produce multiple consumption allocations.
- Layer remaining quantity and value projections reduce by the allocation.
- Final layer consumption absorbs only the deterministic sub-cent rounding residual.

FIFO queue order is never selected by a GL account, UI row order, or later bill date.

### 2.3 Returns

- A sales return linked to an original issue restores the returned quantity at the latest corrected cost allocated to that issue as of return acceptance. It creates a new return-date FIFO layer preserving original ancestry but not original queue position.
- A purchase return removes the returned units' current FIFO carrying cost. It consumes the linked layer where the physically returned quantity remains traceable and available; otherwise interchangeable stock consumes the normal queue. The Vendor Credit's tax-exclusive commercial amount is separate, and any difference posts to purchase-return cost variance rather than re-costing retained layers.
- Returned goods that are damaged or blocked retain trace identity but are not available until accepted.

### 2.4 Backdating

An open-period backdated receipt or issue replays the FIFO queue from the effective event forward. Changes to later issue allocations become versioned re-cost deltas. Posted journals remain immutable; the Posting Engine receives correction lines only.

Closed-period queue history is not rewritten financially. The Inventory Engine computes the counterfactual delta. The Accounting Policy/Period owner classifies prior-period error versus estimate change and supplies the permitted retrospective-restatement, retained-earnings/adjusting, or prospective treatment.

### 2.5 Landed cost and cost correction

Landed cost links to specific receipt lines and adjusts their layer cost. The amount attributable to remaining quantities increases layer value; the amount attributable to consumed allocations adjusts their recorded cost consequences through correction events.

### 2.6 Negative FIFO

FIFO negative inventory is prohibited by default. If explicitly enabled for open-period operations, the issue creates a visible negative provisional layer using the last eligible adjusted receipt-layer cost; if no such history exists, an explicitly configured standard/provisional item cost is required or the issue is rejected. A later receipt first settles that deficit; actual-versus-provisional differences produce a source-linked cost variance. A provisional negative layer never masquerades as an ordinary receipt layer and must settle before period close.

### 2.7 FIFO valuation

At any cut-off:

`FIFO gross inventory value = sum(authoritative remaining layer monetary amount)`

and:

`FIFO stock quantity = sum(all owned open-layer quantity, including restricted/in-transit states) + disclosed provisional negative quantity`

`FIFO available quantity = sum(consumable open-layer quantity after reservation/block controls)`

## 3. Moving weighted average cost

IA-3 retains Model A from ADR-IAA-001: valuation is owned by a versioned WAC pool, while receipt-cost records are immutable audit evidence and are not consumable valuation layers.

### 3.1 WAC pool

There is exactly one current WAC valuation state per valuation scope:

- pool quantity;
- pool gross value;
- average unit cost;
- state version;
- last effective event;
- accumulated rounding residual;
- zero/active/deficit status.

The complete Average Cost History is the immutable sequence of state transitions. The current pool is only a projection of that history.

### 3.2 Receipt

For receipt quantity `q` and capitalizable cost `c`:

`new quantity = old quantity + q`

`new value = old value + c`

`new average = new value / new quantity`

The receipt creates an immutable receipt-cost record for source traceability. That record has original quantity and cost, but no authoritative remaining quantity, exhaustion status, or FIFO position.

### 3.3 Issue

For issue quantity `q`, prior authoritative pool value `v`, and prior pool quantity `p`:

`raw issue cost = q × v / p`

`new quantity = old quantity - q`

`new value = old value - authoritative issue cost`

`new average = new value / new quantity` when quantity remains positive.

The rational pool ratio is evaluated without first rounding a unit rate. The authoritative issue cost is the valuation-precision extended amount plus its deterministic GL-basis residual allocation. The 12-decimal average is a reported/explanatory rate, not a reconstruction source.

An issue never chooses or consumes a receipt-cost record. When quantity reaches zero, the final issue absorbs the governed rounding residual so pool value also reaches exactly zero.

### 3.4 Returns

- A sales return re-enters at the latest corrected cost allocated to the original issue as of return acceptance. This is a new pool input and may change the average. Later corrections traverse both issue and return ancestry.
- A purchase return removes physical quantity at current WAC. The Vendor Credit's tax-exclusive commercial amount is separate; the difference posts to purchase-return cost variance and does not re-cost retained WAC stock. A price-only credit for retained goods remains a cost correction.
- An exact reversal before intervening cost events restores the prior pool state; otherwise it creates an ordinary linked inverse event followed by deterministic re-costing.

### 3.5 WAC landed cost and correction

A landed-cost or purchase-price correction links to the original receipt evidence, then replays the affected WAC pool from that event through the current cut-off. The difference between old and recalculated states is split exactly into:

- ending on-hand inventory value delta; and
- cumulative issued-cost delta by affected destination such as COGS, expense, or WIP.

This counterfactual replay avoids inventing “remaining receipt units” inside a pooled method.

### 3.6 Negative WAC

WAC negative inventory is prohibited by default. If explicitly enabled for open-period operations:

- the pool enters a visible deficit state;
- issues use the last positive pool average; if no positive pool history exists, an explicitly configured standard/provisional item cost is required or the issue is rejected;
- the next receipt settles the deficit before forming a positive pool;
- the engine records actual-versus-provisional variance separately;
- average cost is never presented as an ordinary positive-stock average while quantity is negative;
- the deficit must settle before period close or close is rejected.

### 3.7 WAC valuation

At any cut-off:

`WAC gross inventory value = WAC pool value`

`WAC average cost = pool value / pool quantity`, for positive quantity.

Receipt-cost-record totals are acquisition-history measures, not ending inventory measures.

## 4. Specific Identification

### 4.1 Identity

Specific Identification requires eligible non-interchangeable or project-segregated inventory plus an explicit serial, lot, or approved unique asset/batch identity before receipt. Serial-controlled units have quantity zero or one per serial. Lot-controlled layers may have quantities greater than one only when all units share the same trace identity and acquisition cost.

### 4.2 Receipt

Each accepted identity creates a valuation layer tied to:

- item and valuation scope;
- serial/lot/unique identity;
- source receipt line;
- acquisition cost and later attributable corrections;
- current physical location and availability status.

### 4.3 Issue and transfer

- An issue must name the exact identity to consume.
- The carrying value is the selected identity's remaining value.
- A partial lot issue receives a deterministic proportional share of the authoritative lot value; the final issue takes the exact remaining valuation and GL-basis amounts.
- A serial cannot be issued twice or exist at two locations.
- A transfer preserves identity and carrying value. Crossing valuation scopes closes the source-location state and opens destination-location state with the same ancestry and carrying value.
- Negative inventory is always prohibited.

### 4.4 Returns and corrections

A return must link to the originally issued identity. Accepted goods reactivate that identity through a return event at the latest corrected cost assigned to the original issue as of acceptance. Substitution with a different serial/lot is a new receipt and cannot be presented as a reversal.

Landed cost and price correction apply directly to identified receipt identities. Consumed identities receive a COGS/expense correction; on-hand identities receive a layer-value correction.

### 4.5 Write-down and disposal

Write-downs retain identity and historical cost while adding a valuation allowance. Disposal consumes the exact identity and releases related allowance. Audit history remains queryable after exhaustion.

### 4.6 Specific-ID valuation

`Specific-ID gross inventory value = sum(active identity carrying values)`

`Specific-ID stock quantity = sum(all owned valuation-bearing identity quantities, including restricted/in-transit states)`

## 5. Transfers

| Transfer | Cost treatment |
| --- | --- |
| Within one valuation scope | Preserve cost and method state; physical location changes only |
| Between FIFO scopes | Carry source allocation ancestry/value and original owned-acquisition queue key; destination availability starts on receipt but transfer never resets accounting FIFO order |
| Between WAC scopes | Remove at source WAC; add that exact transfer value to destination WAC, recalculating destination average |
| Between Specific-ID scopes | Preserve exact identity and carrying value |
| In transit | Carry value moves to an explicit in-transit location/state; no gain or loss |
| Intercompany | Source disposal/sale and destination acquisition; no shared layer or pool |

Transfer variances are not allowed. Quantity or value lost/damaged in transit requires a separate approved adjustment or claim event.

## 6. NRV write-down and reversal

Historical acquisition cost and method state remain gross. Inventory is measured at the lower of cost and NRV. NRV write-downs and capped reversals are held in a separate valuation-adjustment ledger:

- no quantity effect;
- direct link to item/scope and supporting assessment;
- deterministic allocation where reporting below scope is required;
- separate gross, allowance, and net values;
- assessment is normally item by item; grouping requires similar/related items that cannot practicably be assessed separately;
- reversal never exceeds the related prior write-down or raises carrying value above historical cost.

General upward inventory revaluation and inventory revaluation gain are prohibited in the core accounting profile.

## 7. Landed-cost allocation

Each landed-cost source is allocated only to explicitly linked receipt lines. The governed allocation basis is selected from actual quantity, weight, volume, acquisition value, or an approved explicit allocation. Required source measurements must exist before allocation.

- Allocations are computed at governed precision.
- Allocated line amounts MUST sum exactly to the approved landed-cost source amount.
- Any rounding residual is assigned by a deterministic largest-remainder rule with stable source-line tie-break.
- An explicit allocation must be approved, fully allocated, and source-line based; it cannot be an unexplained plug.
- The Inventory Engine allocates between on-hand value and prior issue destinations using method replay.

## 8. Positive count and non-purchase receipt costing

An approved positive Physical Count variance requires ownership evidence and one method-specific measured cost:

- WAC: current positive pool average; if no positive pool exists, approved provisional acquisition cost;
- FIFO: approved measured acquisition cost creating a new count-date layer;
- Specific ID: exact identity plus traceable or independently approved acquisition cost; otherwise quarantine with no owned valuation or GL.

Allowed non-purchase receipt sources are opening conversion, deferred Production completion, accepted sales return, intercompany acquisition, documented owner contribution/donation, and approved positive adjustment. Each source has an explicit offset and measurement policy. Unknown sources are rejected.

| Source class | Inventory measurement | Offset and availability |
| --- | --- | --- |
| Opening conversion | Approved source-line historical cost and allowance at conversion cut-off | Opening Conversion Suspense within the complete opening Trial Balance |
| Production completion | Production-authority output containing direct materials and permitted conversion cost | WIP; source type disabled until Production Architecture is certified |
| Accepted sales return | Latest corrected cost assigned to the linked original issue at acceptance | Reversal/correction of the original issue-cost destination; financial Credit Memo remains separate |
| Intercompany acquisition | Destination-company acquisition cost supplied by certified intercompany, Tax, and Currency authorities | AP/GRNI/GINR as the ownership/billing facts require; source type disabled until those authorities are certified |
| Owner contribution | Approved reliably measurable contribution value from the Capital/Accounting Policy authority | Contributed equity; unavailable without approved non-exchange policy and evidence |
| Donation or grant | Amount supplied by an approved non-exchange/grant accounting policy | Governed grant/income/equity role; unavailable without that owning policy |
| Positive adjustment/Physical Count | Method-specific measured cost in this section | Governed inventory-adjustment variance account |

No source class may fall back to a UI-entered plug, current sales price, arbitrary GL account, or unrelated item cost.

## 9. Costing-method changes

A method change is an accounting-policy event. It is permitted only when required by the applicable framework or when the approved policy owner demonstrates reliable and more relevant reporting. It is applied retrospectively unless impracticable under IAS 8.

The implementation transition:

1. records the policy decision and effective/restatement periods;
2. recomputes comparative method outputs from immutable source events where practicable;
3. records retained-earnings/comparative adjustments without editing posted journals;
4. uses earliest-practicable opening state only when retrospective determination is impracticable;
5. preserves old and restated method evidence, source links, and disclosures;
6. never uses a method change to target profit or conceal a reconciliation difference.

## 10. Deferred Production boundary

Production Architecture is not part of IA-3. When later approved:

- Production owns BOM/routing, yield, direct labor, variable overhead, fixed overhead at normal capacity, scrap, by-/co-product, and production-variance calculation;
- Inventory owns material issue valuation and WIP/finished-goods inventory events;
- abnormal waste is expensed, not capitalized;
- stocked assemblies use production issue/completion events;
- phantom kits issue their components at sale and do not create parent inventory;
- Posting consumes the resolved economic outputs.

Production, assembly, kit, MRP, and batch-manufacturing sources remain disabled until that architecture is certified.

## 11. Certification requirements

Every method implementation MUST prove:

- deterministic ordering and replay;
- exact quantity roll-forward;
- exact gross-value roll-forward;
- exact method-specific state reconciliation;
- exact Inventory/COGS correction allocation;
- zero orphan source links;
- transfer conservation;
- return ancestry;
- closed-period immutability;
- preview/actual equality;
- Inventory subledger-to-GL equality.
