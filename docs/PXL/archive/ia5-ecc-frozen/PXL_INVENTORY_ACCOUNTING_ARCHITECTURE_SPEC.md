# PXL Inventory Accounting Architecture Specification

**Status:** Frozen architecture — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting
**Applies To:** Inventory ownership, quantity, valuation, source-document accounting, and Inventory-to-GL integration
**Read When:** Designing or reviewing any inventory transaction, costing change, reconciliation, or canonical inventory scenario
**Do Not Read For:** Journal persistence internals, tax calculation, or implementation instructions
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Architecture only; no implementation is authorized by this document

## 1. Purpose and authority

This specification freezes the complete Inventory Accounting Architecture for FIFO, moving weighted average, and specific identification. It governs Inventory Accounting where older Inventory, Purchasing, Sales, canonical-data, or reporting blueprints conflict. It does not reopen or modify the certified Posting Engine, Posting Kernel, COA Resolver, Tax boundary, Preview architecture, or Kernel Totality Guard.

The companion authorities are:

- `PXL_INVENTORY_COSTING_SPEC.md`
- `PXL_INVENTORY_RECONCILIATION_CONTRACT.md`
- `PXL_INVENTORY_LAYER_LIFECYCLE_SPEC.md`
- `PXL_INVENTORY_REPORTING_SPEC.md`
- `PXL_INVENTORY_CANONICAL_DATASET_SPEC.md`
- `ADR-IAA-001_WEIGHTED_AVERAGE_VALUATION_MODEL.md`
- `PXL_INVENTORY_ACCOUNTING_IMPLEMENTATION_ROADMAP.md`
- `PXL_IA3_HARDENING_DECISION_REGISTER.md`

Normative terms `MUST`, `MUST NOT`, `SHALL`, and `SHALL NOT` are architectural requirements. A future implementation may differ only through an approved successor ADR.

### 1.1 Accounting framework

The frozen baseline is Philippine Financial Reporting Standards aligned with IAS 2 and IAS 8. Core Inventory supports the common lower-of-cost-and-NRV model. A different reporting framework or a standards exception requires an effective-dated profile approved by a successor ADR; an entity, user, warehouse, or transaction cannot select an exception ad hoc.

Every inventory event and report carries the applicable accounting-profile version, nature-and-use cost-formula policy group, costing method, valuation scope, precision policy, and effective date.

## 2. Frozen invariants

1. The Inventory Engine owns inventory quantity, costing method execution, inventory valuation, cost-flow decisions, and inventory subledger evidence.
2. The Posting Engine consumes Inventory Engine outputs. It never computes quantity, average cost, layer selection, landed-cost allocation, or inventory re-costing.
3. Every inventory event with a GL consequence and its journal MUST commit atomically. Neither side may persist alone.
4. Physical custody, legal control, vendor invoicing, and payment are distinct events. A document name alone never establishes ownership.
5. Inventory becomes an asset when the company obtains control of goods and the acquisition cost is measurable. Physical receipt without control is custody stock, not owned inventory.
6. Purchase Orders and Sales Orders are commitments and do not change inventory, AP, AR, or GL.
7. AP changes on an approved Vendor Bill, Vendor Credit, Debit Memo, or settlement event—not merely on physical receipt.
8. Inventory quantity and value change only through governed Inventory Engine events. A Manual Journal cannot create or repair inventory subledger state.
9. Historical posted transactions remain immutable. Corrections are linked reversal, cost-correction, re-cost, or NRV-adjustment events.
10. All calculations are deterministic from effective-dated source facts, master-data versions, and prior inventory state. Heuristic source linking and unexplained balancing are prohibited.
11. Inventory control-account GL balances MUST reconcile exactly to the method-specific inventory subledger contract.
12. Recoverable taxes are excluded from inventory cost. Non-recoverable taxes and directly attributable costs are included when approved accounting policy requires capitalization.
13. Inventories with similar nature and use share one governed cost formula. Geography or warehouse location alone cannot justify a different formula.
14. COGS and related revenue are recognized in the same Sales control-transfer occurrence and accounting period.
15. Financial carrying amount is lower of historical cost and NRV. General upward Inventory revaluation is prohibited.

## 3. Conceptual architecture

The architecture separates distinct kinds of truth:

| Concern | Authoritative owner | Authoritative object |
| --- | --- | --- |
| Physical and owned quantity change | Inventory Engine | Immutable inventory movement/event ledger |
| Current on-hand, reserved, blocked, and available projection | Inventory Engine | Stock projection rebuilt from movement and reservation events |
| Gross historical-cost valuation | Inventory Engine | FIFO layers, WAC valuation pool/history, or Specific-ID layers |
| Cost layers | Inventory Engine | FIFO and Specific-ID valuation layers; WAC receipt records are audit-only |
| NRV allowance overlay | Inventory Engine | Immutable valuation-adjustment ledger |
| COGS and other issue cost | Inventory Engine | Immutable issue-cost result and method allocations/pool version |
| Inventory ageing | Inventory Engine | Actual identity history or separate physical-ageing allocation ledger |
| Available inventory | Inventory Engine | On-hand projection less reservations and blocked quantity |
| Reserved inventory | Inventory Engine | Immutable reservation/release events and current reservation projection |
| Average cost | Inventory Engine | WAC pool version/history |
| FIFO queue | Inventory Engine | Ordered available FIFO valuation layers |
| Specific-ID tracking | Inventory Engine | Serial/lot identity lifecycle and Specific-ID valuation layers |
| Posting Engine inputs | Inventory Engine, Tax Engine, and COA Resolver within their boundaries | Source-bound quantities, amounts, semantic roles, dimensions, tax outputs, and account-resolution context |
| PO/receipt/bill matching | Purchasing/AP | Immutable line-level Purchase Match Ledger consuming Inventory receipt and AP bill occurrences |
| Production conversion inputs | Production Engine *(deferred capability)* | Approved BOM/routing/yield/direct-labor/overhead component output; cannot post until Production Architecture is certified |
| Financial ledger balance | Posting Engine / GL | Posted journal lines in the configured control and contra accounts |

Current-balance objects are projections, not independent accounting facts. They MUST be reproducible from immutable events and MUST NOT be directly editable.

### 3.1 Required event identity

Every inventory event MUST carry:

- company, item, ownership status, costing method, and valuation currency;
- valuation-scope key and physical warehouse/location;
- effective date/time and accounting posting date;
- source document type, header ID, line ID, and source occurrence;
- immutable event ID and idempotency key;
- predecessor, reversal, correction, and supersession links where applicable;
- quantity, unit of measure, valuation amount, and dimensions;
- actor, approval, created/posted timestamps, and reason code;
- related inventory event and journal identity after posting.

No event may be linked to a source through description matching, amount matching, date proximity, or another heuristic.

## 4. Ownership and accounting policy

### 4.1 Ownership transfer

Ownership/control transfer MUST be an explicit, governed fact derived from approved commercial terms: delivery term, title/control-transfer point, acceptance requirement, consignment status, and effective timestamp. The workflow records the selected policy and evidence; it does not infer ownership from a later Vendor Bill or warehouse balance.

Common cases:

- Control on accepted delivery: the confirmed Goods Receipt is the ownership event.
- Control at shipment: an approved shipment notice or equivalent creates owned Inventory in Transit; warehouse receipt later changes location only.
- Consignment or customer-owned stock: receipt changes custody quantity but not owned quantity, inventory value, or Inventory GL.
- Rejected goods awaiting return: custody may remain, but owned/available classifications follow the documented rejection and title terms.

### 4.2 Acquisition measurement

Initial inventory cost includes purchase price net of trade discounts, non-recoverable taxes, freight, duty, insurance, handling, and other directly attributable costs needed to bring inventory to its present location and condition. Recoverable VAT, financing costs outside an approved capitalization policy, abnormal waste, and general administration are excluded.

The Inventory Engine owns the capitalizable amount and allocation. The Tax Engine owns tax classification and recoverability. The COA Resolver owns account selection. The Posting Engine owns journal construction and persistence.

### 4.3 GRNI and Purchase Clearing

PXL SHALL support Goods Received Not Invoiced (`GRNI`) as a distinct liability/control account.

- GRNI is mandatory whenever owned inventory is recognized before the Vendor Bill.
- Goods Receipt normally posts `Dr Inventory / Cr GRNI` at provisional acquisition cost. The cost hierarchy is: approved contract/PO net price; approved shipment price; governed item provisional acquisition cost; otherwise reject. Approved estimated landed cost and non-recoverable tax remain separately identified.
- The Vendor Bill clears the linked GRNI amount and recognizes AP and applicable tax.
- A bill/receipt price difference is not silently left in GRNI. It becomes a source-linked cost correction allocated by the Inventory Engine between on-hand value and already-consumed cost, with the remaining accounting difference routed to the configured variance account.

Purchasing/AP owns the Purchase Match Ledger and the Goods Invoiced Not Received (`GINR`) Purchase Clearing control. It consumes Inventory receipt occurrences and AP bill occurrences without recalculating their quantity, cost, tax, or liability.

Invoice-before-receipt has three mutually exclusive cases:

1. **Bill before control:** `Dr GINR/Purchase Clearing` plus tax as recognized by the Tax Engine, `Cr AP`. When control later transfers, the matched amount posts `Dr Inventory` or `Inventory in Transit / Cr GINR`; any unbilled receipt portion credits GRNI.
2. **Control before warehouse receipt:** recognize owned Inventory in Transit. If unbilled, credit GRNI; if billed in the same occurrence, credit AP. Warehouse receipt later reclassifies Inventory in Transit to warehouse Inventory.
3. **Simultaneous control, receipt, and bill:** one composite occurrence posts Inventory and tax directly against AP. The Purchase Match Ledger records zero unmatched GRNI and GINR; transient clearing lines are not required.

Purchase Clearing is not interchangeable with Inventory, Inventory in Transit, or GRNI. Every balance has an originating bill line, ownership status, aging date, clearing event, and zero-unexplained-balance requirement.

Purchase-price differences, later AP foreign-exchange differences, and tax differences are distinct. Subsequent AP FX never becomes an inventory cost correction.

## 5. Transaction ownership matrix

| Transaction or event | Inventory quantity/value ownership | Accounting policy |
| --- | --- | --- |
| Purchase Order | No inventory event | Commitment only; no GL or AP |
| Receiving Report | Records physical receipt, inspection, and source links | Creates no accounting merely by existing; confirmation invokes a Goods Receipt when control transfers |
| Goods Receipt | Inventory Engine creates owned receipt, valuation state, and movement | `Dr Inventory / Cr GRNI`, or Inventory in Transit reclassification when ownership was earlier |
| Vendor Bill before control | AP owns liability; Purchasing owns GINR match | `Dr GINR/Purchase Clearing / Cr AP`; no inventory quantity or valuation until control transfers |
| Vendor Bill | Purchasing/AP owns payable and tax source; line-level match to PO/RR/receipt | `Cr AP`; clears GRNI. It changes Inventory only through a governed cost-correction output |
| Payment | Treasury/AP owns settlement | Reduces AP and cash; no inventory quantity or cost-flow event |
| Vendor Credit — price only | AP/tax event plus source-linked cost correction | No quantity change; on-hand/consumed cost allocation comes from Inventory Engine |
| Purchase Return | Inventory Engine owns outbound quantity and valuation | Removes inventory at method-derived carrying cost; clears linked GRNI when unbilled or links a separate Vendor Credit/AP/tax event when billed; any difference is an explicit purchase-return variance |
| Damaged goods retained | Inventory Engine owns write-down, write-off, or disposal | Vendor Credit never invents the physical event; both events are explicitly linked |
| Sales Order | Reservation/commitment only | No owned-quantity or GL change |
| Delivery / Sales recognition | Sales owns control-transfer date and revenue; Inventory owns consumption and COGS | One atomic recognition occurrence posts related revenue and carrying cost in the same period; later invoicing uses governed unbilled AR/contract-asset treatment |
| Sales Invoice | Sales/AR/Tax owns billing, receivable, and tax | Does not control cost or defer revenue after control transfer; clears/reclassifies an earlier unbilled balance when applicable |
| Sales Return | Inventory restores accepted quantity at the latest corrected cost assigned to the original issue as of return acceptance | Financial Credit Memo is linked but distinct; rejected/damaged returns may enter blocked stock and receive an NRV write-down |
| Goods Issue | Inventory Engine consumes stock for non-sales purpose | `Dr configured expense/project asset / Cr Inventory`; WIP is permitted only through a certified Production boundary |
| Goods Receipt without purchase | Inventory Engine creates quantity/value from an approved source | Offset is configured and source-specific, never an unexplained clearing account |
| Inventory Adjustment | Inventory Engine owns quantity/value correction | Positive/negative variance posts to configured adjustment/variance account |
| Physical Count | Count captures evidence; approved variance creates one governed adjustment | Positive variance requires ownership evidence and method-specific approved measured cost; unmeasurable Specific-ID stock remains quarantined |
| Stock or warehouse transfer | Inventory Engine relocates quantity and carrying value | No company-level P&L; GL reclassification only when control accounts/dimensions differ |
| Branch transfer, same legal entity | Inventory Engine relocates quantity/value | No profit. Reclassifies branch inventory when branch-level GL is configured |
| Intercompany inventory | Source company sale/issue and destination company purchase/receipt | Never modeled as an internal stock transfer; detailed pricing, AR/AP, tax, and consolidation remain unavailable until their owning authorities are certified |
| Opening Inventory | One governed conversion batch establishes source-line quantity and method state | Generates or is atomically linked to matching Opening GL at the same effective date |
| Opening GL | Posting Engine persistence of Inventory Engine opening plan | Uses the governed Opening Conversion Suspense counterpart; the complete opening Trial Balance, including imported equity, must clear that suspense before go-live |
| NRV write-down/reversal | Inventory Engine owns zero-quantity valuation-allowance event | Write-down posts loss/allowance; reversal is capped at the related prior write-down and never carries inventory above cost |
| Landed Cost | Inventory Engine allocates approved attributable cost to receipt sources | On-hand portion capitalized; consumed portion adjusts COGS/variance through a correction plan |
| Cost Correction | Inventory Engine performs source-linked deterministic re-cost | Never edits posted journals or source cost history; emits correction evidence and GL delta |
| Negative Inventory | Inventory Engine policy gate | Prohibited by default; governed provisional deficits are allowed only as specified in the Costing Specification |
| Backdated Transaction | Inventory Engine inserts event in effective order and re-costs affected open-period events | Closed periods are never silently rewritten; delta posts under Period Engine correction policy |
| Write-off / disposal | Inventory Engine consumes quantity and carrying value | `Dr loss/expense / Cr Inventory`, with reason, approval, and source evidence |
| Inbound consignment | Inventory records custody and identity only | No owned quantity, value, AP, or GL until explicit control transfer |
| Outbound consignment | Inventory moves owned goods to a consignment location | Remains company inventory until customer control transfer; no revenue or COGS merely on delivery to consignee |
| Production issue/completion | Deferred Production capability supplies conversion facts; Inventory owns issue/receipt valuation events | Unavailable until Production Architecture is approved; Posting remains a consumer |

## 6. Transfers and valuation scopes

A valuation scope is the unit within which one costing method and one cost pool operate. Its key MUST include company, item, valuation currency, and the approved costing scope (`company`, `branch`, or `warehouse`). A separate nature-and-use policy group governs which cost formula is permitted across scopes. Location, lot, serial, ownership status, and blocked/available status remain explicit physical dimensions even when they do not create separate valuation pools.

Costing scope is governed master data:

- it cannot vary transaction by transaction or solely because of geography;
- a cost-formula change is an accounting-policy event subject to IAS 8 retrospective treatment; an earliest-practicable opening conversion is permitted only when full retrospective application is demonstrably impracticable;
- a transfer inside one valuation scope preserves carrying cost;
- a transfer between valuation scopes removes cost from the source method state and adds exactly that carrying value to the destination method state;
- company-level carrying value cannot change solely because goods moved internally;
- intercompany movement always closes the source company's cost state and creates a new destination-company acquisition.

## 7. Adjustments, NRV, and corrections

Three event types MUST remain distinct:

1. **Quantity adjustment:** corrects units and carries the method-determined value consequence.
2. **Cost correction:** corrects historical acquisition or issue cost and deterministically allocates the delta.
3. **NRV write-down/reversal:** changes the valuation allowance without rewriting historical acquisition cost and never increases carrying value above cost.

Gross historical cost and valuation allowances MUST remain separately reportable. Financial-statement inventory equals the lower of cost and NRV. NRV is normally assessed item by item; grouping is allowed only for similar/related items that cannot practicably be assessed separately. Each assessment records evidence date, purpose, grouping basis, and reversal ceiling. A write-down never changes receipt cost, FIFO sequence, WAC receipt audit, or Specific-ID acquisition identity.

### 7.1 Backdating

- Events in an open period are inserted at their effective position and the affected valuation scope is deterministically replayed forward.
- Re-cost differences are emitted as linked correction events and journals; existing posted journals are not updated.
- Before a closed-period correction, the Accounting Policy/Period owner classifies it as a prior-period error or change in estimate.
- A material prior-period error follows IAS 8 retrospective-restatement or earliest-practicable rules, using linked adjusting/retained-earnings and comparative-reporting evidence without mutating posted journals.
- A change in estimate is prospective from the date of change.
- The Inventory Engine still computes the counterfactual quantity/value effects so the correction is explainable.

### 7.2 Negative inventory

Negative inventory is prohibited by default. If explicitly enabled for FIFO or WAC, the issue creates a visible open-period provisional deficit using the configured deterministic provisional-cost source. The next qualifying receipt settles the deficit and produces a separately identified cost variance. Every deficit must be settled or the period close rejected; no certified Trial Balance or Financial Statement may carry negative inventory quantity/value. Specific-identification inventory can never go negative because an absent serial or lot identity cannot be consumed.

### 7.3 Foreign currency, discounts, and rebates

- Inventory initial cost is translated into functional currency at the rate applicable when control transfers.
- AP is a monetary item. Subsequent AP exchange differences are FX gain/loss and never inventory cost.
- A settlement discount that reduces purchase price reduces inventory cost through method replay; a genuine financing component is separate.
- A supplier rebate that reduces purchase price reduces inventory cost. Genuine consideration for a distinct service or promotion does not.
- Probable volume rebates require approved evidence, effective estimation policy, and later true-up.

### 7.4 Opening conversion

One opening conversion batch establishes Inventory quantity, method state, gross value, allowances, and GL at one cut-off. Inventory opening lines use a temporary Opening Conversion Suspense counterpart; the complete imported Trial Balance includes the approved opening equity and retained-earnings balances from conversion evidence. The suspense account must clear to exactly zero across that complete batch before go-live. It is not retained earnings, cannot absorb a conversion variance, and cannot remain as unexplained equity. A genuine post-formation owner contribution is a separate governed transaction, not an opening-conversion plug.

### 7.5 Consignment

Inbound vendor consignment remains custody-only. When control transfers on consumption or another explicit event, the system first recognizes acquisition at contract cost and then records the related issue; both are atomic where simultaneous. Outbound consignment remains owned at a consignment location until customer control transfers, when revenue and COGS are recognized together.

## 8. Manual Journal control

Inventory control, Inventory-in-Transit, GRNI, GINR/Purchase Clearing, inventory allowance, Opening Conversion Suspense, and governed inventory variance accounts are protected control accounts.

A user-entered Manual Journal MUST NOT post to an Inventory control account unless a future approved workflow supplies a linked Inventory Engine event in the same atomic transaction. A GL-only correction would violate the subledger contract. Opening balances use the governed Opening Inventory workflow, and post-opening corrections use Inventory Adjustment, Cost Correction, NRV Adjustment, Return, or Reversal.

## 9. Master-data requirements

The future implementation MUST govern:

| Master data | Required inventory-accounting attributes |
| --- | --- |
| Item | Item type, stock/non-stock classification, costing method, valuation scope, UOM conversions, negative-stock policy, serial/lot rules, inventory/COGS/adjustment accounts |
| Warehouse | Company, branch, physical locations, ownership/custody capabilities, in-transit behavior, default dimensions |
| Branch and location | Legal-entity relationship, valuation scope membership, GL dimension mapping |
| Lot and serial | Stable identity, item, source receipt, status, location history, manufacture/expiry dates where applicable |
| Costing policy | Effective-dated accounting profile, nature-and-use group, eligible FIFO/moving WAC/Specific ID formula, transition policy, precision and UOM policy |
| Accounts | Inventory, Inventory in Transit, COGS, GRNI, GINR/Purchase Clearing, adjustment, write-off, NRV allowance/loss, purchase-return variance, FX, cost variance, landed-cost clearing, Opening Conversion Suspense, evidenced opening equity/retained earnings, and expense accounts |
| Acquisition policy | Ownership-transfer terms, tax recoverability, capitalization classes, landed-cost allocation bases |
| Period and currency | Functional currency, transaction currency, open/adjusting-period and IAS 8 policy, fixed-point precision, currency minor-unit scale, and effective exchange-rate source |

Account IDs are resolved through the certified COA Resolver. Standard item workflows never accept an arbitrary encoder-selected Inventory or COGS account.

## 10. Atomic Posting Engine integration

For a posting inventory event:

1. Inventory admission validates source lifecycle, permissions, ownership, period, quantities, and method state.
2. The Inventory Engine locks the affected source and valuation scope.
3. It computes deterministic quantity, cost, valuation, COGS, correction, and source-line outputs.
4. It persists its owned event/projection changes and calls the certified Posting Engine in the same transaction.
5. The Posting Engine resolves/validates accounts, constructs ordered journal lines, numbers, audits, and persists through the sanctioned kernel.
6. Any failure rolls back inventory and GL effects together.

Preview invokes the same pure Inventory valuation calculation but does not persist. Actual posting re-locks and recomputes; unchanged inputs MUST yield the same Posting Plan and fingerprint.

For a sale, one source-locked Sales recognition occurrence supplies Sales revenue/AR or contract-asset values and Inventory carrying cost to the same Posting transaction. This orchestration uses the frozen Posting interface and does not add costing or revenue logic to Posting.

## 11. Prohibited architecture

- Inventory costing inside the Posting Engine or UI.
- Journal-only inventory corrections.
- Direct mutation of inventory projections, cost layers, WAC pools, or journal tables.
- Treating a Vendor Bill line account as the source of inventory valuation.
- Using Purchase Clearing as an unexplained balancing account.
- Inferring ownership, receipt matching, return identity, or cost source heuristically.
- Mutating an exhausted layer to conceal a later correction.
- Treating intercompany movement as a zero-value internal transfer.
- Mixing FIFO consumption, WAC pooling, and Specific-ID selection rules.
- Using geography alone to change cost formula.
- Carrying inventory above historical cost through a general revaluation gain.
- Posting COGS before or after the related control-transfer revenue occurrence.
- Treating AP exchange differences as inventory cost.
- Closing a period with unresolved provisional negative inventory.

## 12. Freeze statement

IA-3 freezes:

- Inventory Engine ownership of quantity and valuation;
- moving-WAC Model A as approved by ADR-IAA-001;
- FIFO and Specific-ID consumable valuation layers;
- GRNI acquisition accounting;
- the source-document accounting matrix;
- method-specific exact reconciliation;
- the Inventory/Posting boundary;
- the canonical requirements and future implementation sequence.
- the accounting profile, method-governance, precision, returns, opening, correction, consignment, and deferred Production boundaries in the IA-3 register.

The IA-3-hardened Inventory Accounting Architecture is the frozen implementation target. IA-3 itself changes documentation only; implementation requires a separately approved future phase.
