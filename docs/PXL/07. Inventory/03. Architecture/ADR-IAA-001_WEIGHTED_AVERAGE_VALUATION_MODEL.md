# ADR-IAA-001: Weighted-Average Valuation Model

**Status:** Accepted by IA-1; retained and hardened by IA-3
**Authority:** Tier 1 Architecture Decision Record
**Owner / Domain:** Inventory Accounting
**Decision Date:** 2026-07-26
**Applies To:** Moving weighted-average inventory valuation and reconciliation
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Decision only; no implementation is authorized

## 1. Context

P5.3B proved that current WAC receipt layers remain unconsumed while stock and net movements continue to change. The old reconciliation assumption expected receipt-layer remaining quantity/value to equal ending stock, but the current WAC implementation treats those rows as receipt audit history.

IA-1 had to choose whether WAC valuation should:

- **Model A:** use an authoritative stock valuation pool and immutable receipt audit records; issues never consume receipt records; or
- **Model B:** maintain consumable receipt layers whose remaining quantity/value reconcile to stock.

The decision must support accounting correctness, auditability, traceability, performance, valuation, GL reconciliation, landed cost, serial/lot tracking, manufacturing, batch/warehouse/branch costing, and inventory ageing.

## 2. Decision

PXL adopts **Model A** with one clarification:

> The authoritative WAC object is a versioned valuation pool per configured valuation scope, not an editable stock-balance field. Immutable receipt-cost records and Average Cost History provide the audit trail. WAC receipt records have no authoritative remaining quantity, value, exhaustion, or issue allocation.

FIFO and Specific Identification continue to use consumable valuation layers. Physical lot/serial tracking and WAC inventory ageing use trace ledgers separate from WAC valuation. Non-tracked WAC ageing uses a disclosed FIFO-by-receipt-date physical allocation; tracked goods use actual identity history.

## 3. Evaluation

| Criterion | Model A — pool + receipt audit | Model B — consumable receipt layers |
| --- | --- | --- |
| Accounting correctness | Directly represents moving-average economics: indistinguishable units share one pool cost | Requires an arbitrary allocation of pooled issue value back to historical receipt rows |
| Auditability | Every receipt and pool transition is immutable; average calculation is replayable | Detailed allocations exist, but can imply false receipt-level cost-flow meaning |
| Traceability | Strong source-to-receipt and source-to-pool trace; physical trace handled separately | Strong apparent receipt trace, but valuation allocation is not economically meaningful for WAC |
| Performance | O(1) current-state update per pool plus append-only history | O(number of open layers), proportional allocation, or periodic compression |
| Inventory valuation | Pool quantity/value is the direct ending valuation | Layer values must be continually redistributed to equal the pool |
| GL reconciliation | Pool gross value maps exactly to Inventory GL | Can reconcile if all layers are updated correctly, with higher drift risk |
| Stock reconciliation | Pool quantity equals stock and movements | Layer quantity can equal stock, but only by introducing a non-WAC consumption convention |
| Landed cost | Counterfactual replay determines exact on-hand and issued-cost delta | Must update many layers and historical allocations; fragmentation grows |
| Serial/lot tracking | Separate physical identity ledger avoids mixing valuation and trace purposes | Tempts one object to serve incompatible physical and pooled-cost purposes |
| Manufacturing | WAC pool and immutable cost events integrate naturally with WIP/batch inputs | Layer allocation adds volume without improving WAC costing decisions |
| Batch costing | Batch identity can remain separate while WAC is scoped as configured | Receipt layers conflate batch trace and pooled valuation |
| Warehouse/branch costing | One pool per governed scope; transfers carry source value into destination pool | Large cross-scope layer fan-out and allocation complexity |
| Inventory ageing | Separate physical ageing rule is explicit and cannot affect COGS | Receipt consumption can produce ageing, but silently imposes FIFO-like physical assumptions |
| Corrections/backdating | Replay pool history and emit exact deltas | Rebuild and redistribute every affected open/consumed layer allocation |
| Conceptual clarity | Different costing methods intentionally have different authoritative state | Creates FIFO-shaped records for a method whose defining feature is pooled cost |

## 4. Why Model B is rejected

To retain separate receipt layers while issuing at one moving average, Model B must choose one of three behaviors:

1. consume receipt quantities FIFO while assigning WAC value;
2. reduce every open receipt layer proportionally; or
3. merge all receipts into one active layer.

The first introduces a hidden FIFO convention unrelated to WAC valuation. The second is expensive, highly fragmenting, and creates synthetic receipt-level remaining values. The third is effectively Model A but with misleading layer terminology.

Model B therefore increases implementation and reconciliation risk without improving accounting correctness.

## 5. Consequences

### 5.1 Positive

- WAC quantity/value has one explicit authoritative state.
- Stock-to-WAC-pool and WAC-pool-to-GL reconciliation are exact.
- Receipt history remains immutable and fully traceable.
- Landed cost and backdated corrections can be explained through deterministic replay.
- Lot, serial, ageing, and manufacturing trace can evolve independently without changing WAC COGS.
- The architecture does not force one layer model across economically different costing methods.

### 5.2 Costs and trade-offs

- Existing generic “cost layer” terminology cannot be used unqualified.
- WAC ageing requires a separate physical allocation policy/report.
- Current WAC receipt rows cannot be certified as available inventory.
- Future implementation must distinguish receipt audit records from valuation state and may require schema/data transition work.
- Re-cost replay requires carefully versioned event history and performance controls.

## 6. Reconciliation consequence

For WAC:

- stock quantity MUST equal net movement quantity and WAC pool quantity;
- stock gross value MUST equal WAC pool value, Inventory subledger, and Inventory GL;
- receipt audit quantity/value MUST NOT be compared with ending stock;
- “available WAC layer quantity/value” is `N/A`, not zero and not a tolerated variance.

For FIFO and Specific Identification, available valuation layers remain exact reconciliation targets.

## 7. Guardrails

- The current mutable `stock_balances.wac_unit_cost` shape is not declared architecturally authoritative merely because Model A is selected; authority belongs to the replayable pool event/history model.
- The pool's fixed-point quantity and authoritative extended functional-currency value are stored facts. Average unit cost is a high-precision derived rate and is never the source for reconstructing authoritative value.
- Transaction-currency evidence and exchange-rate identity are retained, but the WAC pool contains only the functional-currency inventory cost recognized when control transfers. Later AP foreign-exchange differences never enter the pool.
- WAC receipt records cannot be deleted, rewritten, or assigned synthetic consumption solely to pass reconciliation.
- Physical serial/lot identity cannot be lost when the item uses WAC.
- A report cannot present a physical ageing allocation as WAC cost flow.
- WAC physical ageing is a separate FIFO-by-receipt-date allocation: transfers preserve the physical acquisition date, traceable sales returns restore the original age, untraceable returns use the disclosed return-acceptance date, reversals restore the reversed allocation, and corrections that do not move quantity do not change ageing.
- A sales return restores the latest corrected cost assigned to the linked original issue as of return acceptance. A purchase return removes quantity at current WAC; any financial-credit difference is a separately identified purchase-return variance or governed cost correction.
- An enabled provisional negative balance is an open-period exception. It must be settled and re-costed before close; a certified period cannot carry negative pool quantity or value.
- Posting receives the Inventory Engine's calculated issue/correction amount and never re-computes WAC.

## 8. Supersession

Only an approved successor ADR may change the selected WAC model. Implementation evidence may refine storage and performance details but may not reintroduce consumable WAC receipt layers or make receipt history the ending valuation source without reopening the frozen Inventory Accounting Architecture.
