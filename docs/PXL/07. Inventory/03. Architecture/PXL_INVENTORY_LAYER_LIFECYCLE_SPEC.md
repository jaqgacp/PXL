# PXL Inventory Layer Lifecycle Specification

**Status:** Frozen architecture — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting
**Applies To:** FIFO valuation layers, WAC receipt evidence and pool versions, and Specific-ID layers
**Read When:** Designing layer/pool state, audit history, corrections, returns, or trace reports
**Do Not Read For:** Treating WAC receipt evidence as available stock
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Architecture only

## 1. Terminology

- **Valuation layer:** a method state with authoritative remaining quantity/value. FIFO and Specific Identification use valuation layers.
- **Receipt-cost record:** immutable evidence of an acquisition event. WAC uses receipt-cost records, but they are not valuation layers.
- **WAC pool version:** the authoritative quantity/value/average state after one ordered WAC event.
- **Consumption allocation:** immutable link from an issue to one or more valuation layers.
- **Projection:** current state derived from immutable events; it is not independently editable.

The generic phrase “cost layer” MUST NOT obscure these method differences.

Valuation lifecycle and physical availability are orthogonal. An owned layer may remain open and valued while its linked physical quantity is reserved, blocked, quarantined, or in transit. Only the consumable subset enters the FIFO Queue; every owned valuation-bearing state enters stock/subledger reconciliation.

## 2. Common identifiers and audit

Every valuation layer, receipt-cost record, pool version, and consumption allocation requires:

- stable unique ID;
- company, item, valuation scope, currency, and method;
- effective timestamp and deterministic event order;
- source document header/line and inventory event IDs;
- parent, predecessor, reversal, correction, and supersession IDs;
- original and current projected quantity/value where applicable;
- authoritative 8-decimal valuation amounts and currency-minor-unit GL-basis amounts; derived unit rate is non-authoritative;
- physical location and ownership/availability status where applicable;
- lot/serial identity where applicable;
- actor, approval, created/posted timestamps;
- related journal/posting occurrence;
- immutable reason and calculation evidence.

State transitions occur through events. Direct edits to historical quantities, costs, status, or source identity are prohibited.

## 3. FIFO lifecycle

### 3.1 States

| State | Meaning | Remaining quantity/value |
| --- | --- | --- |
| Pending | Source admitted but transaction not committed | Not available |
| Active | Open and valued; physical availability is classified separately | Positive |
| Partially consumed | Some quantity allocated to issues | Positive |
| Exhausted | Entire available quantity consumed | Exactly zero |
| Reversed | Source receipt was reversed through linked event | Zero in current projection; history retained |
| Corrected | Cost/identity superseded by linked correction version | Current projection comes from correction chain |
| Closed | Historical layer retained after scope/method conversion | Not consumable |

### 3.2 Creation

A committed owned receipt creates the layer. Layer identity is assigned by the Inventory Engine, never by the Posting Engine or UI. Splits are deterministic by source line, valuation scope, ownership status, and differing cost basis.

Physical lot/serial identity lives in a separate Physical Identity/Trace Ledger. FIFO accounting consumption does not have to select the physically picked lot/serial. If exact physical identity determines cost, the item uses Specific Identification.

### 3.3 Modification and consumption

- Consumption creates immutable allocation events.
- Current remaining quantity/value is a projection reduced by allocations.
- Partial consumption changes the projection from Active to Partially consumed.
- Exact zero changes it to Exhausted.
- Reservation, block/quarantine, or in-transit transitions do not consume or devalue the layer; they change the linked physical availability classification.
- Landed cost and purchase-cost correction create cost-adjustment events; they do not rewrite original cost.
- Location-only transfer within a scope changes physical history, not acquisition ancestry or FIFO position.
- A same-entity transfer across scopes preserves the original owned-acquisition FIFO order key and exact carrying amount. Destination availability starts on receipt, but transfer cannot reset the cost queue.

### 3.4 Exhaustion, closure, and reopening

Exhausted and Closed layers are never reopened in place. A sales return creates a new layer ordered at return acceptance and valued at the latest corrected cost assigned to the original issue. It preserves ancestry but never recovers the original queue position. A correction creates a linked successor projection. This preserves the fact that the original layer was exhausted at the prior cut-off.

A method/scope conversion closes old layers and creates new opening state at identical aggregate quantity/value.

## 4. WAC lifecycle — Model A

### 4.1 Receipt-cost records

Each receipt creates an immutable record containing original quantity, capitalizable cost, source, and effective order. Its lifecycle is:

`recorded → corrected/reversed by linked event → retained permanently`

The following fields are not authoritative and SHOULD NOT exist as WAC concepts:

- remaining receipt quantity;
- remaining receipt value;
- exhausted flag;
- FIFO queue position;
- issue-to-receipt allocation.

If a future physical-ageing model allocates issues to receipts, it is a separate trace/ageing ledger and must not affect WAC valuation.

### 4.2 WAC pool versions

Each ordered event creates one immutable version:

| Transition | Quantity effect | Value effect | Result |
| --- | ---: | ---: | --- |
| Opening/receipt/accepted return | Increase | Add event cost | Recalculate average |
| Issue/return-to-vendor/write-off | Decrease | Subtract cost at governed WAC rule | Retain or close average |
| Cost correction/landed cost | None at event level | Add/subtract counterfactual delta | Recalculate affected history |
| Transfer within pool | Net zero | Net zero | Physical state only |
| Transfer across pools | Source decrease; destination increase | Exact carrying value out/in | Recalculate destination average |
| NRV write-down/reversal | None | No gross-pool change | Separate allowance ledger |

Pool status is:

- `zero`: quantity and value exactly zero;
- `active`: positive quantity and gross value;
- `deficit`: approved negative inventory with provisional cost;
- `closed`: method/scope converted and no longer accepts events.

A zero pool may become active through a later receipt. This is a new pool version, not “reopening” a receipt record.

### 4.3 Corrections

A backdated or cost correction produces a new deterministic replay version chain. Prior versions remain audit evidence and are marked superseded for current-state queries. The correction records the old and new ending pool, issue-cost deltas, affected event range, and posting occurrence.

### 4.4 WAC physical-ageing lifecycle

For non-tracked WAC goods, a separate FIFO-by-receipt-date Physical Ageing Ledger is authoritative for age only:

- receipt creates age quantity with original owned-acquisition date;
- issue allocates oldest available age quantity;
- same-entity transfer carries age allocations and dates unchanged;
- sales return restores traceable original age; when not traceable, return acceptance date is used and disclosed;
- reversal reverses the exact age allocation;
- quantity correction creates a count/correction-date age record;
- cost correction and NRV adjustment have no age effect.

Tracked WAC goods use actual lot/serial identity history. Neither ageing model supplies WAC quantity, value, average cost, COGS, or Posting amounts.

## 5. Specific Identification lifecycle

### 5.1 Identity model

A serial-controlled valuation layer represents one exact serial with quantity one or zero. A lot layer may contain multiple units only where all share one trace identity and cost basis.

States include:

- pending inspection;
- available;
- reserved;
- blocked/quarantined;
- in transit;
- issued/sold;
- returned pending acceptance;
- available after accepted return;
- written down;
- disposed;
- reversed/corrected;
- closed.

Availability status does not erase ownership or value.

### 5.2 Assignment and consumption

- Receipt binds the external/internal lot or serial to one immutable PXL identity.
- Issue explicitly names that identity.
- Consumption closes a serial or reduces a lot layer.
- Transfer changes location/state while preserving identity and carrying value.
- A serial cannot be active in more than one location or source occurrence.

### 5.3 Return and reopening

An accepted return creates a linked return event and a new active lifecycle occurrence for the same identity at the latest corrected cost assigned to its original issue. The original issued occurrence remains closed. A substituted identity is a new receipt, not a reopening.

### 5.4 Corrections, write-downs, and disposal

Acquisition-cost corrections preserve the identity and create cost-adjustment events. Write-downs create a linked valuation allowance without changing historical cost. Disposal consumes the identity and releases any related allowance according to policy.

## 6. Reversal policy

A reversal is equal and opposite at the Inventory event level and retains the original method logic:

- FIFO reverses the exact receipt/consumption allocations where state permits; later dependencies trigger governed re-costing.
- WAC inserts an inverse event and replays affected pool versions.
- Specific ID reverses only the exact identity and rejects reversal where an unaddressed downstream transfer/issue would make identity state impossible.

A GL reversal without the corresponding Inventory reversal is prohibited.

## 7. Traceability

Required traversal is bidirectional:

`source document line ↔ inventory event ↔ layer/pool version ↔ consumption/correction ↔ journal line`

Reports must also traverse:

- purchase receipt to Vendor Bill/GRNI match;
- sale issue to original/returned quantity;
- transfer source to in-transit and destination events;
- landed-cost source to allocated receipt events;
- NRV write-down/reversal to affected scope/identity;
- reversal/correction to the complete supersession chain.

## 8. Retention and reporting

Exhausted, reversed, corrected, and closed records remain indefinitely available to audit. Current-state reports may filter them, but audit and replay reports MUST include them.

Method reports use:

- FIFO Queue: available FIFO valuation layers in consumption order;
- Average Cost History: WAC pool versions, not receipt remaining quantities;
- Specific ID History: identity lifecycle and current status;
- Layer Ledger: FIFO/Specific valuation layers plus clearly labeled WAC receipt audit records;
- correction/replay report: all superseded and replacement versions.
