# PXL Inventory Reporting Specification

**Status:** Frozen architecture — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting and Reporting
**Applies To:** Inventory operational, valuation, costing, reconciliation, and audit reports
**Read When:** Designing or certifying an inventory report
**Do Not Read For:** Creating reconciliation adjustments or replacing source ledgers with report logic
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Architecture only

## 1. Reporting principles

1. Reports are read-only projections. They never repair, reclassify, post, or mutate.
2. Every report states company, functional currency, cut-off, time zone, costing method, valuation scope, ownership basis, and included statuses.
3. Current-state reports are reproducible from immutable inventory and costing events.
4. Drill-through reaches the source line, inventory event, method state, and journal line.
5. Gross historical cost, valuation allowance, and net inventory are shown separately.
6. FIFO, WAC, and Specific-ID reports use their own authoritative method state; one generic layer assumption is prohibited.
7. Backdated and correction events are visible by effective date, accounting posting date, and version/supersession status.
8. Every output identifies accounting profile, nature-and-use policy group, method/scope version, precision policy, transaction/functional currency, and exchange-rate source.
9. Financial control totals use authoritative GL-basis amounts; unit rates are explanatory, not reconstruction values.

## 2. Required report catalog

| Report | Primary purpose | Authoritative source | Required controls |
| --- | --- | --- | --- |
| Inventory Valuation | Quantity and gross/net carrying value at cut-off | Movement ledger + method state + valuation adjustments | Equals Inventory subledger and GL |
| Inventory Ledger | Item-level beginning/increase/decrease/ending quantity and value | Inventory events and costing results | Roll-forward exact |
| Movement Ledger | Immutable physical/owned quantity events | Inventory movement/event ledger | Equals stock quantity |
| Layer Ledger | FIFO/Specific layers and WAC receipt audit records | Method-specific records | Method labels prevent invalid WAC remaining comparisons |
| FIFO Queue | Consumable FIFO layers in accounting order | FIFO valuation-layer projection | Queue equals available valued quantity; all owned layers, including blocked/in-transit states, equal stock/subledger |
| Average Cost History | WAC quantity, value, average, and event transition history | WAC pool versions | Ending pool equals WAC stock/subledger |
| Specific ID History | Serial/lot receipt, state, transfer, issue, return, and disposal | Identity and Specific-ID layers | One active location/state per identity |
| Inventory Ageing | Age distribution of physically held/owned units | Receipt/trace ageing allocation ledger | Independent of WAC cost-flow assumptions |
| Inventory Reconciliation | Method state and subledger exceptions | Reconciliation contract sources | Zero unresolved variances |
| Inventory vs GL | Gross inventory and allowance compared with GL | Inventory subledger + posted GL | Exact by configured GL grain |
| Layer vs GL | FIFO/Specific valuation state compared with GL | Valuation layers + GL | WAC shown as N/A; uses WAC Pool vs GL instead |
| Movement vs Stock | Net movements compared with stock projection | Movement ledger + stock projection | Exact quantity equality |
| Stock vs GL | Stock method value compared with control accounts | Stock projection + method value + GL | Exact value equality |
| GRNI Reconciliation | Received-not-invoiced schedule | Goods receipts, bill matches, corrections, GRNI GL | Exact ending balance |
| GINR / Purchase Clearing Aging | Invoiced-before-control items | Purchase Match Ledger + GINR GL | Every balance has originating bill, aging date, and clearing event |
| Inventory in Transit | Owned goods between locations/entities | Transfer/shipment events + in-transit GL | Quantity/value exact |
| Landed Cost Allocation | Cost source to receipt/item allocation | Landed-cost events and corrections | Allocated amount equals source amount |
| Cost Correction / Re-cost | Old/new method output and GL delta | Replay/correction versions | Delta fully explained |
| Negative Inventory | Deficits and provisional costing | Deficit events and later settlement | No hidden deficit or unresolved variance |
| NRV Write-down and Reversal | Gross cost, NRV, allowance, net value, capped reversals | Valuation-adjustment ledger + GL | Allowance equals contra account; carrying value never exceeds cost |
| Purchase Match Ledger | PO/receipt/bill line matching and unmatched quantities/values | Purchasing-owned Purchase Match Ledger | Inputs agree to Inventory receipt and AP bill occurrences |
| Sales Recognition Bridge | Control-transfer revenue and related COGS | Sales recognition + Inventory issue occurrences + GL | Same occurrence and accounting period |
| Opening Conversion | Opening quantity/method state/value and complete evidenced opening Trial Balance | Opening inventory events + GL | Entire batch ties and Opening Conversion Suspense clears to zero |
| Cost-policy and Method Change | Original/restated policy outputs and disclosures | Immutable events + policy conversion evidence | IAS 8 treatment and comparative bridge complete |

## 3. Inventory Valuation

Required columns include:

- company, branch, warehouse/location, item, UOM;
- costing method and valuation scope;
- owned, consigned, blocked, reserved, available, and in-transit quantities;
- gross historical cost;
- valuation allowance;
- net carrying amount;
- authoritative valuation and functional-currency GL-basis amounts;
- residual allocation evidence;
- method-specific evidence: FIFO layer total, WAC pool value/average, or Specific-ID total;
- Inventory and contra-account GL values;
- exact variance.

The report must support cut-off reconstruction, not merely display today's stock projection.

## 4. Movement and Inventory Ledgers

The Movement Ledger is event-grained and includes source, quantity sign, pre/post quantity, ownership, location, effective/posting dates, and reversal/correction links.

The Inventory Ledger is a financial roll-forward grouped by item and valuation scope:

`Beginning + valued increases - valued decreases ± cost corrections = Ending`

Movement quantity and Inventory Ledger quantity must agree. If one physical event has no value because it is custody-only or an internal same-pool relocation, its classification must be explicit.

## 5. Method reports

### 5.1 FIFO Queue

Shows layer ID, receipt/source date, queue order, original/remaining quantity and value, adjusted unit cost, lot/serial if any, location/status, landed-cost corrections, and age. It includes no exhausted layers by default but permits audit expansion.

### 5.2 Average Cost History

Shows each WAC pool transition:

- prior quantity/value/average;
- event quantity/value;
- issue cost or receipt capitalization;
- new quantity/value/average;
- pool state and version;
- source and journal links;
- correction/supersession chain.

It does not present receipt records as remaining inventory.

### 5.3 Specific ID History

Shows identity, source receipt, acquisition and adjusted carrying cost, every location/status transition, reservation, issue, return, write-down, disposal, and current state. Serial duplication or impossible state is a report exception.

### 5.4 Inventory Ageing

Inventory ageing is a physical/trace report, not a valuation-method rewrite:

- FIFO may use remaining FIFO receipt layers directly.
- Specific ID uses identity receipt dates.
- WAC lot/serial-tracked goods use actual identity history. Non-tracked WAC goods use a separate FIFO-by-receipt-date physical-ageing allocation ledger. Issues consume oldest age quantity; same-entity transfers preserve age; traceable returns restore original age and untraceable returns use disclosed acceptance date; reversals restore the exact allocation. The ledger cannot change WAC valuation or COGS.

The chosen WAC ageing convention appears on the report and is versioned policy.

## 6. Reconciliation reports

Reconciliation follows `PXL_INVENTORY_RECONCILIATION_CONTRACT.md`.

Every variance view must show:

- first failing boundary;
- quantity and amount;
- item/scope/source/event/journal identities;
- costing method;
- period and effective/posting dates;
- exception classification;
- owner and status.

Reports must not aggregate away item-level failures or propose an automatic journal.

## 7. Purchase and ownership reports

GRNI and clearing reports distinguish:

- physically received and owned, not invoiced;
- invoiced, not physically received;
- owned Inventory in Transit;
- custody/consignment stock;
- quantity mismatch;
- price/cost mismatch;
- tax-only difference;
- rejected/returned goods.

Header-only `rr_id` matching is insufficient where line-level partial quantities differ. Reports require source-line matches.

GRNI, GINR/Purchase Clearing, and Inventory in Transit are separate reports and control accounts:

- GRNI ages from owned unbilled receipt;
- GINR ages from approved pre-control Vendor Bill;
- Inventory in Transit ages from control transfer into transit;
- each clears only through its frozen ownership/matching event;
- no report may combine them to conceal an old balance.

## 8. Audit and export requirements

Each report output records:

- generation timestamp and requesting actor;
- parameter set and policy/method versions;
- source watermark/cut-off;
- deterministic report fingerprint;
- row count and control totals;
- export identity and audit entry.

Exports preserve full-precision control totals even when display values are rounded. A rerun over unchanged inputs must reproduce the same ordered rows and fingerprint.

Inventory reports disclose NRV assessment grain, evidence date, grouping justification, prior allowance, reversal ceiling, and current allowance. “Revaluation gain” is not a core Inventory report concept.

## 9. Performance contract

Performance optimization may use indexed projections, snapshots, or materialized views only when:

- immutable events remain authoritative;
- snapshot watermarks are visible;
- results can be rebuilt;
- stale snapshots cannot be presented as current;
- method-specific semantics are preserved;
- reconciliation compares sources independently rather than comparing one projection to itself.

## 10. Deferred capability reports

Manufacturing/WIP, assemblies/kits, advanced WMS/FEFO optimization, intercompany elimination, and foreign-currency remeasurement reports are not claimed by IA-3. Their source types remain unavailable until their Production, WMS, Consolidation, Tax, and Currency authorities are certified. Core reports expose only the frozen boundary events they legitimately own.
