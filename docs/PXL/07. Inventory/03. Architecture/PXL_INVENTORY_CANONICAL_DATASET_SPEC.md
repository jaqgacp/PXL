# PXL Inventory Canonical Dataset Specification

**Status:** Frozen architecture — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting and Certification
**Applies To:** Future canonical inventory fixtures, replay, fingerprints, and reconciliation evidence
**Read When:** Resuming P5.3B or designing inventory certification fixtures
**Do Not Read For:** Authorization to modify current seeds or production data
**Last Reviewed:** 2026-07-26 — IA-3 architecture hardening
**Implementation Status:** Architecture only; current canonical fixtures are not certified by this specification

## 1. Canonical principles

The future authoritative canonical dataset MUST:

- use current public/governed application workflows;
- use the fully enforced Posting Kernel without bypass;
- contain no direct journal or derived-inventory mutation;
- establish explicit ownership, source-line, receipt/bill, return, and correction links;
- exercise FIFO, moving WAC Model A, and Specific Identification independently;
- remain deterministic from a clean migration replay;
- prove method-specific quantity, valuation, subledger, GL, audit, preview, and reversal outputs;
- prove fixed-point, GL-basis, residual, policy-version, currency, and UOM evidence;
- never use Manual Journals or artificial adjustments to force equality.

P5.3B remains paused until approved implementation phases make the IA-3-hardened architecture executable.

## 2. Required master-data population

At minimum the dataset contains:

- three legal companies or isolated company scenarios;
- open and closed fiscal periods;
- branches, warehouses, locations, and an in-transit location;
- one item per costing method plus lot- and serial-controlled Specific-ID items;
- an item with negative inventory prohibited and a separate FIFO/WAC item with the governed deficit policy enabled;
- inventory, COGS, adjustment, GRNI, GINR/Purchase Clearing, Inventory-in-Transit, landed-cost clearing, write-off, NRV allowance/loss, Opening Conversion Suspense, evidenced opening equity/retained earnings, FX, purchase-return variance, and other governed variance accounts;
- tax codes representing recoverable and non-recoverable purchase tax;
- suppliers, customers, payment terms, UOMs, and deterministic numbering;
- effective-dated costing and ownership policies;
- an accounting-profile version, nature-and-use cost-formula policy groups, precision policies, and base-UOM scales;

Master data must reflect supported product defaults. It cannot be changed merely to produce a target total.

## 3. Common scenario matrix

Each applicable scenario is required for FIFO, WAC, and Specific ID unless marked method-specific:

| Scenario | Required canonical purpose |
| --- | --- |
| Opening Inventory and Opening GL | Same date, quantity, method state, value, accounts, and source occurrence |
| Purchase Order | Non-posting commitment |
| Partial Receipt | First receipt creates only received quantity/value and GRNI |
| GRNI provisional hierarchy | PO/contract, shipment-price, approved item-cost fallback, and no-source rejection paths remain distinguishable |
| Full Receipt | Completes PO quantity with explicit source-line relationship |
| Partial Vendor Bill | Clears only matched GRNI quantity/value and creates partial AP |
| Full Vendor Bill | Completes receipt/bill match; price difference becomes governed cost correction |
| Bill before receipt | Uses approved Purchase Clearing/invoice-before-receipt workflow; clears on receipt |
| Simultaneous receipt and bill | One atomic workflow with no open residual GRNI |
| Payment | Settles AP with no inventory event |
| Sale and delivery | One control-transfer occurrence posts related revenue and exact COGS/Inventory in the same period |
| Delivery before invoice across period boundary | Revenue/COGS remain at control transfer; later invoice clears/reclassifies unbilled balance |
| Partial sale | Leaves method state available and reconcilable |
| Sales return | Restores the latest corrected cost assigned to the linked original issue as of return acceptance and records physical status |
| Unbilled purchase return | Removes stock and clears linked GRNI |
| Billed purchase return | Removes method carrying cost and links Vendor Credit/AP/tax plus purchase-return variance |
| Price-only Vendor Credit | No quantity change; exact on-hand/consumed cost correction |
| Damaged retained goods | Separate write-down/write-off plus explicitly linked financial credit |
| Goods Issue | Non-sales consumption to configured expense/project; WIP source is rejected until Production is certified |
| Production / assembly / kit source | Gated rejection until Production Architecture is certified; no Inventory or GL output is fabricated |
| Goods Receipt without PO | Supported governed source and offset |
| Positive/negative Inventory Adjustment | Quantity/value consequence with reason and approval |
| Stock Transfer within scope | Location change with no company GL value change |
| Transfer across valuation scopes | Exact carrying-value conservation and destination method update |
| Branch Transfer | No profit; branch reclassification only if configured |
| Intercompany Inventory | Gated rejection until certified intercompany/Tax/Currency authorities exist; thereafter source sale/issue and destination purchase/receipt with AR/AP/tax |
| Physical Count | Snapshot, count, variance, and generated governed adjustment |
| Landed Cost | Allocation to open and partially consumed receipt cost |
| Cost Correction | Source-linked price/cost correction with on-hand and issued-cost split |
| NRV write-down and reversal | Zero quantity effect, item/group evidence, reversal ceiling, and lower-of-cost-and-NRV proof |
| General upward revaluation | Rejected |
| Write-off/disposal | Quantity and carrying value removed |
| Backdated Receipt | Open-period deterministic re-cost |
| Backdated Issue | Open-period deterministic re-cost |
| Closed-period backdate | Rejected or routed to approved current/adjusting correction without historical mutation |
| Negative Inventory | Prohibited-path rejection and separately enabled provisional-deficit settlement |
| Reversal | Inventory and GL reverse atomically with ancestry |
| Manual Journal affecting Inventory | Ordinary control-account journal rejected; governed opening/correction path succeeds |
| Ownership at shipment | Inventory in Transit recognized and later reclassified on warehouse receipt |
| Inbound consignment | Custody receipt has no value/GL; later explicit ownership and issue are atomic |
| Outbound consignment | Remains owned until customer control transfer |
| Positive count with prior cost | Method-specific approved cost and exact residual evidence |
| Positive count without measurable cost | Rejected or quarantined; no GL |
| Foreign-currency purchase | Gated rejection without a certified Currency input; thereafter initial cost uses the control-transfer rate and later AP FX is excluded from Inventory |
| Settlement discount | Purchase-price component re-costs on-hand/consumed quantities; financing component separate |
| Supplier rebate | Purchase-price rebate re-costs Inventory; genuine service consideration does not |
| Cost-formula policy consistency | Similar-nature/use inventory rejects location-only formula difference |
| Costing-method change | IAS 8 retrospective or earliest-practicable policy evidence |
| Precision and UOM | Indivisible-unit rejection, source/base UOM trace, largest-remainder and final-consumption closure |
| Opening conversion batch | Opening method state and GL tie; complete evidenced Trial Balance clears Opening Conversion Suspense to zero |

## 4. FIFO-specific scenarios

The dataset includes:

- at least three receipts at different costs;
- one issue consuming a full layer and part of the next;
- multiple issues proving queue order;
- a linked sales return after partial consumption;
- a sales return creating a return-date queue layer at latest corrected original issue cost;
- a purchase return with and without intervening consumption;
- landed cost applied after part of a layer was consumed;
- a backdated receipt that changes later FIFO allocations;
- physical FEFO/lot selection that remains separate from accounting FIFO valuation;
- same-entity transfer preserving original FIFO acquisition order;
- one approved provisional negative layer followed by settlement, if the feature is implemented;
- exact ending layer quantity/value and FIFO Queue output.

## 5. WAC-specific scenarios

The dataset includes:

- opening pool;
- at least three receipts at different costs;
- issues between receipts proving moving-average transitions;
- quantity-to-zero with value-to-zero rounding closure;
- sales return at latest corrected original issue cost;
- purchase return at current WAC plus purchase-return variance;
- landed cost and purchase-price correction requiring counterfactual replay;
- transfer between two WAC scopes with different destination averages;
- approved deficit and settlement if negative inventory is implemented;
- receipt-cost records that remain immutable and are explicitly excluded from available-layer reconciliation;
- exact pool quantity/value/average history.
- a separate WAC physical-ageing issue, transfer, return, and reversal sequence proving no valuation effect.

No WAC test may assert that ending stock equals summed receipt-record remaining quantity or value.

## 6. Specific-ID scenarios

The dataset includes:

- serial-controlled receipts and one lot-controlled receipt;
- reservation and exact identity issue;
- transfer preserving serial/lot identity and carrying value;
- attempted issue without identity, rejected;
- attempted duplicate serial receipt, rejected;
- attempted Specific-ID policy assignment to interchangeable bulk inventory, rejected;
- attempted negative identity issue, rejected;
- linked return of the original identity;
- substituted-serial return recorded as a new receipt rather than reversal;
- identity-level landed cost/cost correction;
- write-down and disposal with allowance release;
- exact active identity quantity/value and lifecycle history.

## 7. Purchase-chain requirements

Every PO → Receiving Report → Goods Receipt → Vendor Bill chain records line-level:

- company, supplier, PO, item, ordered/received/billed quantities;
- warehouse, branch, location, and ownership terms;
- receipt event and GRNI occurrence;
- Vendor Bill match and AP occurrence;
- provisional, billed, landed, and corrected costs;
- partial/full lifecycle states.

Setting a header `rr_id` alone is insufficient where the governed workflow produces line matches, quantity allocations, or receipt events.

## 8. Opening sequence

Canonical ordering is:

1. companies and branches;
2. fiscal calendar and open periods;
3. COA, control accounts, and resolver configuration;
4. warehouses, locations, items, costing/ownership policies;
5. opening inventory event and method state;
6. atomically linked Opening GL;
7. proof that opening stock/method value equals Opening GL;
8. downstream operational transactions.

No downstream issue, sale, transfer, or adjustment may precede the opening proof.

## 9. Expected evidence per scenario

Each scenario defines:

- business purpose and method;
- source fixtures and governed functions;
- lifecycle transitions and expected failures;
- source relationships;
- quantity and value roll-forward;
- method-state change;
- expected journal header, lines, order, roles, accounts, dimensions, and totals;
- tax and subledger effects;
- audit and posting-origin evidence;
- preview/actual output;
- reversal/correction effect;
- deterministic fingerprint.
- authoritative valuation amount, GL-basis amount, residual allocation, source/base UOM quantities, and policy versions.

Expected totals are derived from the documented scenario, never copied from an obsolete seed.

## 10. Replay and certification gates

A fresh canonical certification requires:

- clean local reset and all current migrations;
- deterministic master data and transaction replay;
- P5.2 guard fully enforced;
- zero unauthorized journal mutation attempts succeeding;
- zero guard violations;
- exact method-specific reconciliation at item and company levels;
- exact GRNI, Inventory-in-Transit, gross Inventory, allowance, and COGS equality;
- exact GINR/Purchase Clearing, purchase-return variance, correction-destination, and opening-conversion equality;
- unchanged-engine fingerprints for unaffected scenarios;
- independently explained output changes for corrected/added fixtures;
- repeated replay with identical row ordering and fingerprints;
- full regression and documentation validation.

The dataset is not `CERTIFIED CURRENT` until every required executable scenario is covered or explicitly marked unsupported by an approved architecture decision.

Manufacturing, assemblies/kits, advanced WMS, intercompany consolidation, and foreign-currency sources remain unavailable where their deferred owning architectures are not certified. Canonical data tests rejection/unavailability and never fabricates those outputs.
