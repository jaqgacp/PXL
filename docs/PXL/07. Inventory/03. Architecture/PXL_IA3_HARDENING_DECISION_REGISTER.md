# PXL IA-3 Inventory Architecture Hardening Decision Register

**Status:** Frozen architecture — IA-3
**Authority:** Tier 1 Domain Architecture Decision Register
**Owner / Domain:** Inventory Accounting
**Applies To:** Disposition and correction of every IA-2 Critical, High, and Medium finding
**Read When:** Confirming IA-3 scope, implementation readiness, or why an IA-2 finding was accepted, rejected, deferred, or excluded
**Do Not Read For:** Implementation design, schema design, migration instructions, or fixture construction
**Last Reviewed:** 2026-07-26 — IA-3 hardening
**Implementation Status:** Architecture only

## 1. Purpose

This register provides the authoritative, individual disposition of every IA-2 finding. No finding is silently accepted, rejected, or combined with another finding. Accepted findings are incorporated into the companion IA-3 specifications. Deferred items identify a boundary that permits the core Inventory Accounting implementation to proceed without claiming the deferred capability.

Disposition meanings:

- **Accepted:** IA-2 proved an architecture defect or material ambiguity; IA-3 contains a normative correction.
- **Rejected:** IA-2 concern is not an architecture defect; accounting justification is required.
- **Deferred:** the boundary is frozen, but detailed architecture belongs to a later governed program and the capability remains disabled/unavailable meanwhile.
- **Out of Scope:** another certified engine owns the concern; the Inventory boundary is nevertheless explicit.

## 2. Critical findings

| ID | IA-2 finding | Disposition | Minimum IA-3 correction |
| --- | --- | --- | --- |
| C-01 | Cost-formula governance and prospective method-change policy | **Accepted** | Full PFRS/IAS 2 and IAS 8 are the baseline. A governed nature-and-use policy group owns the cost formula. Location alone cannot justify a different formula. Specific ID has eligibility controls. Method changes follow accounting-policy change rules, including retrospective treatment unless impracticable. |
| C-02 | General Inventory Revaluation could permit upward valuation above cost | **Accepted** | General revaluation is removed. Inventory is lower of cost and NRV. Only NRV write-down and capped reversal are permitted in the core profile. Acquisition-cost correction remains a separate event. |
| C-03 | COGS and related revenue could be recognized in different periods | **Accepted** | One Sales control-transfer recognition occurrence owns the recognition date. Sales supplies revenue/AR or contract-asset outputs; Inventory supplies carrying cost. Both are posted atomically for that occurrence. Invoice timing cannot defer revenue after control transfer. |
| C-04 | Invoice-before-receipt and Purchase Clearing accounting was undefined | **Accepted** | Three ownership cases are frozen: GINR/Purchase Clearing before control, Inventory in Transit after control but before warehouse receipt, and GRNI for owned receipt before bill. Exact clearing rules and simultaneous receipt/bill treatment are defined. |
| C-05 | Exact monetary reconciliation was under-defined at rounding boundaries | **Accepted** | Fixed-point quantity, rate, valuation-amount, and GL-basis amount precision are frozen. Extended monetary amounts—not rounded unit rates—are authoritative. Deterministic largest-remainder allocation and final-consumption residual rules are required. |

## 3. High findings

| ID | IA-2 finding | Disposition | Minimum IA-3 correction |
| --- | --- | --- | --- |
| H-01 | Backdated/closed-period events did not distinguish prior-period error from estimate change | **Accepted** | The Accounting Policy/Period owner classifies error versus estimate before correction. Material errors follow IAS 8 retrospective-restatement rules; estimate changes are prospective. Posted journals remain immutable. |
| H-02 | Re-cost deltas routed to variance could break destination-level reconciliation | **Accepted** | Reconciliation uses a complete cost-destination bridge containing original destination, current correction account, retained-earnings/adjusting-period treatment, and comparative-restatement amount. No delta is omitted. |
| H-03 | GRNI provisional-cost source hierarchy was missing | **Accepted** | The hierarchy is frozen: approved contract/PO net price; approved shipment price; governed item provisional acquisition cost; otherwise reject. Approved estimated landed cost and non-recoverable tax are separately identified. |
| H-04 | PO/RR/Goods Receipt/Vendor Bill match ownership was shared implicitly | **Accepted** | Purchasing/AP owns the immutable Purchase Match Ledger. Inventory owns receipt quantity and valuation. AP owns the payable. The match ledger consumes their source occurrences without recalculating either. |
| H-05 | Positive Physical Count costing was undefined | **Accepted** | Positive count requires ownership evidence and method-specific measured cost. WAC uses current positive pool average or approved provisional acquisition cost; FIFO creates a count-date layer at approved measured acquisition cost; Specific ID requires identity and traceable/approved cost or remains quarantined. |
| H-06 | WAC purchase-return costing and credit difference were ambiguous | **Accepted** | Physical return removes quantity at current WAC. Vendor credit records commercial/tax value. Their difference posts to a purchase-return cost-variance role and does not re-cost retained WAC stock. A separate price-only credit remains a cost correction. |
| H-07 | Sales-return “original cost” could mean posted or corrected cost | **Accepted** | Return cost is the latest governed corrected carrying cost assigned to the original issue as of return acceptance. Later corrections traverse both original issue and return ancestry. |
| H-08 | FIFO returned-layer queue date was undefined | **Accepted** | A sales return creates a new FIFO layer ordered at return acceptance; it preserves original issue/receipt ancestry and corrected return cost but never regains the original queue position. |
| H-09 | Negative inventory could survive period close as negative Inventory | **Accepted** | A provisional deficit is an open-period exception. It must be settled or rejected before Inventory close certification. No certified Trial Balance or Financial Statement may include negative inventory quantity/value. |
| H-10 | Foreign-currency price difference and FX difference were not separated | **Accepted** | Inventory initial cost uses the control-transfer-date functional-currency rate. AP is monetary; subsequent FX differences never re-cost inventory. Purchase-price and landed-cost corrections remain separate from FX. |
| H-11 | Settlement-discount costing was absent | **Accepted** | A settlement discount that reduces purchase price reduces inventory cost through a source-linked correction; on-hand and consumed portions are allocated by method replay. A financing component is separately classified. |
| H-12 | Supplier-rebate costing was absent | **Accepted** | Purchase-price rebates reduce inventory cost; service/promotional consideration is excluded. Probable volume rebates may be accrued only under an approved evidence policy and are trued up through linked corrections. |
| H-13 | Opening Inventory and opening-equity offset were undefined | **Accepted** | One opening conversion batch owns method state and GL. Inventory lines use Opening Conversion Suspense; the complete imported Trial Balance includes separately evidenced equity/retained earnings and must clear the suspense to zero before go-live. Suspense cannot absorb a variance or become retained earnings. |
| H-14 | FIFO valuation identity could conflict with lot/serial trace and FEFO picking | **Accepted** | FIFO valuation layers and physical identity allocations are separate. WMS may select actual lot/serial/FEFO stock while accounting consumes the FIFO valuation queue. Identity-driven cost requires Specific ID. |
| H-15 | Consignment had custody receipt but no ownership-conversion workflow | **Accepted** | Inbound consignment stays custody-only until an explicit ownership event; consumption/sale first recognizes acquisition, then issue. Outbound consignment remains owned inventory at a consignment location until customer control transfer. |
| H-16 | Manufacturing, assemblies, kits, and conversion-cost ownership were absent | **Accepted in boundary; detailed Production architecture Deferred** | Production owns BOM/routing/yield/labor/overhead calculation. Inventory owns material issue valuation and WIP/finished-goods receipt valuation events. Posting remains a consumer. Production sources remain disabled until a separate Production Architecture is approved. |

## 4. Medium findings

| ID | IA-2 finding | Disposition | Minimum IA-3 correction |
| --- | --- | --- | --- |
| M-01 | “Revaluation” terminology was unsafe | **Accepted** | Core documents use NRV write-down/reversal; “revaluation” is reserved for a separately approved standards exception. |
| M-02 | NRV assessment grain was undefined | **Accepted** | NRV is normally assessed item by item; grouping is limited to similar/related items that cannot practicably be assessed separately. Evidence, date, purpose, and reversal ceiling are required. |
| M-03 | Physical lot/serial and FIFO valuation needed separation | **Accepted** | Physical Identity/Trace Ledger and FIFO Valuation Ledger are independent, linked projections. This independently confirms H-14 rather than merging it. |
| M-04 | WAC ageing lifecycle was incomplete | **Accepted** | Untracked WAC ageing uses a separate FIFO-by-receipt-date physical allocation ledger with issue, transfer, return, reversal, and correction rules; it never affects WAC valuation. |
| M-05 | FIFO destination queue order after transfer was undefined | **Accepted** | Same-entity transfer preserves original owned-acquisition ordering and carrying value. Destination availability begins on receipt, but transfer cannot reset cost order or manipulate profit. |
| M-06 | UOM and precision rules were missing | **Accepted** | Each item has a base-UOM fixed-point scale. Conversion produces one authoritative base quantity; residual/indivisible-unit rules are deterministic and retained with source UOM evidence. |
| M-07 | GRNI/Purchase Clearing ageing classifications were incomplete | **Accepted** | GRNI, GINR/Purchase Clearing, and Inventory in Transit have distinct roll-forwards, aging start dates, clearing events, and zero-unexplained-balance requirements. |
| M-08 | Method and policy versions were not required in every output | **Accepted** | Every event, method state, report, preview, correction, and fingerprint carries the applicable accounting profile, cost-formula policy group, method, scope, precision, and version. |
| M-09 | Non-purchase Goods Receipt policy was too generic | **Accepted** | Allowed source classes are opening, production completion, accepted sales return, intercompany acquisition, owner contribution/donation, and approved positive adjustment. Each has an explicit cost and offset policy; unknown sources are rejected. |
| M-10 | Roadmap reused the IA-2 phase identifier | **Accepted** | The roadmap is rebaselined from IA-3. Future implementation gap census becomes IA-4; later phases are renumbered. |

## 5. Rejected findings

None. IA-3 found accounting support for every accepted IA-2 concern and no basis to dismiss one as merely an implementation preference.

## 6. Deferred and out-of-scope decisions

| ID | Subject | Disposition | Why core implementation can proceed |
| --- | --- | --- | --- |
| D-01 | Detailed manufacturing, MRP, assemblies, kits, normal-capacity overhead, co-/by-products, and production variance architecture | **Deferred** | H-16 freezes the non-duplicating interface. Production document types remain disabled and cannot post until their own architecture/canonical certification exists. Core purchase/sale/inventory costing does not depend on them. |
| D-02 | Intercompany transfer pricing, unrealized-profit elimination, consolidation, and cross-border tax | **Deferred / Out of Scope** | Inventory freezes source disposal and destination acquisition with no shared layer. Consolidation, Tax, and Currency programs own the deferred calculations. Intercompany inventory remains disabled until those contracts are approved. |
| D-03 | Full Currency Engine implementation | **Deferred / Out of Scope** | H-10 freezes the Inventory boundary: a governed Currency authority supplies the control-transfer rate and later FX classification. Functional-currency inventory can proceed independently; foreign-currency source types remain fail-closed until that rate interface is certified. |
| D-04 | Advanced WMS execution, directed picking, FEFO optimization, and mobile scanning | **Deferred / Out of Scope** | H-14/M-03 freeze the trace-versus-valuation separation. Basic governed physical identity events can proceed; advanced WMS optimization cannot alter costing. |

## 7. Mandatory architecture decisions

| Required area | Frozen IA-3 decision |
| --- | --- |
| Monetary precision model | Fixed-point only; no binary floating point |
| Authoritative monetary values | Extended valuation amount and functional-currency GL-basis amount; unit rates are derived |
| Residual allocation policy | Stable largest-remainder allocation; final consumption takes the exact remaining amount |
| Fixed-point precision | Base quantity scale 0–6 by item/UOM; valuation amounts 8 decimals; unit rates 12 decimals; GL basis uses currency minor-unit scale |
| IAS 2 inventory valuation | Lower of historical cost and NRV; no general upward revaluation |
| IAS 8 error versus estimate | Accounting-policy classification controls retrospective versus prospective treatment |
| Closed-period corrections | No mutation; error restatement/adjusting treatment or prospective estimate treatment with full bridge |
| Purchase-return costing | Remove method carrying cost; commercial-credit difference is purchase-return variance |
| Sales-return costing | Re-enter at latest corrected original issue cost |
| Opening Inventory policy | One governed opening event per source line/method state within one conversion batch |
| Opening equity policy | Opening Conversion Suspense is temporary and must clear to zero against the complete evidenced opening Trial Balance; imported equity/retained earnings remain separate balances |
| GRNI cost hierarchy | Approved contract/PO, shipment price, approved provisional item cost, otherwise reject |
| Purchase Clearing ownership | Purchasing/AP owns GINR/Purchase Clearing and Purchase Match Ledger |
| Foreign-currency costing | Historical functional rate at control transfer; later AP FX excluded from inventory |
| Settlement discounts | Purchase-price discounts reduce inventory cost; financing components separated |
| Supplier rebates | Purchase-price rebates reduce cost; genuine service consideration does not |
| Positive Physical Count costing | Ownership evidence plus method-specific approved measured cost |
| FIFO queue ownership | Inventory Engine owns accounting FIFO queue; physical trace/WMS does not |
| WAC ageing | Separate physical-ageing ledger; never a valuation input |
| Consignment ownership | Custody until explicit control event; outbound consignment remains owned |
| Manufacturing boundary | Production calculates conversion components; Inventory values inventory events; Posting persists |

## 8. IA-3 freeze

The companion specifications incorporate every Accepted correction. Deferred capabilities are fail-closed and cannot be claimed, enabled, or canonically certified before their owning architecture exists.

The hardened Inventory Accounting Architecture is **APPROVED FOR IMPLEMENTATION** and **FROZEN**. That determination approves the target architecture, not execution in this phase.

IA-3 changes architecture documentation only. It does not execute or authorize a migration, schema, code, SQL, fixture, canonical-data, Posting Engine, or Kernel change. Every future design or implementation phase requires separate scope approval.
