# PXL IA-4 Inventory Accounting Database Blueprint

**Status:** IA-4 planning baseline
**Authority:** Logical data contract derived from frozen IA-3 architecture
**Last Reviewed:** 2026-07-26
**Implementation Status:** Design only; no SQL or migration is authorized

## 1. Design rules

1. Immutable facts and rebuildable projections are separate.
2. Header-only source links never own line-level accounting.
3. Every monetary fact retains authoritative valuation amount and functional-currency
   GL-basis amount; a displayed unit rate cannot reconstruct either.
4. Every event carries company, item, base UOM, valuation scope, method, accounting
   profile, precision/currency policy, source line, occurrence, effective/posting order,
   actor, and reversal/correction ancestry.
5. FIFO, WAC, and Specific Identification have distinct authoritative state.
6. Physical identity, reservations, ageing, and custody are not valuation layers.
7. All projections are direct-write denied and rebuildable.
8. Historical conversion never invents ownership, source links, identity, or layer
   consumption.

Physical names are logical names for implementation planning. IA-5 may apply repository
naming conventions, but it may not merge objects whose ownership or lifecycle is
separate here.

## 2. Existing master and source tables

`Needs Extension` means the current table remains the source document or master. New
fields are governed facts, not permissive JSON escape hatches.

| Table | Disposition | Primary key | Required foreign keys | Required constraints and indexes | Relationships, ownership, and lifecycle |
| --- | --- | --- | --- | --- | --- |
| `items` | Needs Extension | Existing item UUID | Company, UOM, inventory/COGS/adjustment accounts; future policy group and valuation-scope policy | Item/company uniqueness retained; cost formula eligible for item nature/use; Specific ID requires identity control; base quantity scale 0–6 | Master Data owns draft/active/inactive; policy changes create versions, never rewrite posted event facts |
| `company_inventory_config` | Needs Extension | Existing company UUID | Default warehouse; accounting/precision/currency policy; required control-account roles | One effective configuration per company/date; no unsupported method/source type | Master Data owns effective configuration; posted events retain resolved version |
| `item_uom_conversions` | Needs Extension | Existing UUID | Company, item, source/base UOM | Positive fixed-point factor; non-overlapping effective versions; deterministic indivisible-unit policy | Master Data owns versions; events retain original UOM, factor version, and normalized base quantity |
| `warehouses` | Needs Extension | Existing warehouse UUID | Company, branch, inventory/variance account; valuation-scope membership and ownership/custody policy | Unique code per company; type/capability compatibility; indexes by company/branch/scope | Inventory Master owns active locations; in-transit/consignment are explicit capabilities, not accounting shortcuts |
| `warehouse_zones` | Needs Extension | Existing zone UUID | Warehouse; optional location/identity controls | Unique zone code per warehouse; valid custody/availability state | Physical Inventory owns; no independent cost formula |
| `purchase_orders` | Needs Extension | Existing PO UUID | Company, vendor, branch, currency, commercial ownership policy | Number uniqueness; approved terms immutable for consumed lines | Purchasing owns draft/approved/partially received/closed/cancelled |
| `purchase_order_lines` | Needs Extension | Existing line UUID | PO, item/UOM, dimensions, tax/acquisition class | Positive ordered base quantity; explicit line identity and policy evidence | Purchasing source line; matched through Purchase Match Ledger |
| `receiving_reports` | Needs Extension | Existing RR UUID | Company, vendor, PO, branch, warehouse, ownership/acceptance policy | Number uniqueness; compatible company/vendor/PO; confirmation immutable | Purchasing owns capture/inspection; confirmation emits one or more Inventory occurrences |
| `receiving_report_lines` | Needs Extension | Existing line UUID | RR, PO line, item/UOM, warehouse/location, lot/serial where applicable | Base quantity and accepted/rejected/custody splits exact; source-line uniqueness | Physical receipt source; never itself becomes a cost layer |
| `vendor_bills` | Needs Extension | Existing bill UUID | Company/vendor/branch/currency; header RR remains convenience only | Number/vendor reference controls retained; no header link substitutes for matches | AP owns draft/approved/posted/void |
| `vendor_bill_lines` | Needs Extension | Existing line UUID | Bill, item/account/tax/dimensions | Line amount remains AP/Tax fact; inventory items require match or governed exception | AP occurrence input to Purchase Match Ledger; never directly determines carrying cost |
| `cash_purchases` and line table | Needs Extension | Existing header/line UUIDs | Company/vendor/cash account/item/tax/dimensions; ownership event | Header/line idempotency and simultaneous occurrence consistency | Purchasing/AP owns payment/tax; Inventory owns receipt state in same atomic occurrence |
| `vendor_credits` and `vendor_credit_lines` | Needs Extension | Existing header/line UUIDs | Company/vendor/bill or match source/tax/dimensions | Explicit price-only, return-linked, or other supported classification | AP/Tax owns commercial credit; Inventory correction/return is distinct and linked |
| `purchase_returns` and `purchase_return_lines` | Needs Extension | Existing header/line UUIDs | Company/vendor, original receipt/match line, warehouse/location, identity | Return quantity cannot exceed eligible owned quantity; billed/unbilled classification required | Purchasing captures approval/shipment; Inventory owns carrying-cost removal; AP credit remains distinct |
| `sales_orders` and line table | Needs Extension | Existing header/line UUIDs | Company/customer/item/warehouse/dimensions | Reservation quantity/version and lifecycle consistency | Sales owns commitment; Inventory reservation events own availability effect |
| `delivery_receipts` and `delivery_receipt_lines` | Needs Extension | Existing header/line UUIDs | Company/customer/SO line/warehouse/location/identity/control-transfer policy | Confirmed source immutable; delivered/accepted/rejected split; number uniqueness | Sales owns physical/control occurrence; Inventory owns issue and Sales owns revenue outputs |
| `sales_invoices` and `sales_invoice_lines` | Needs Extension | Existing header/line UUIDs | Company/customer/delivery recognition occurrence/tax/dimensions | Billing links cannot duplicate recognized quantity/value | Sales/AR/Tax owns billing; no independent inventory consumption after delivery cut-over |
| `credit_memos` and line table | Needs Extension | Existing header/line UUIDs | Company/customer/original invoice/return occurrence/tax | Physical-return claim requires governed return link; price-only credit remains distinct | AR/Tax owns financial credit; Inventory owns accepted return |
| `stock_adjustments` and `stock_adjustment_lines` | Needs Extension | Existing header/line UUIDs | Company/warehouse/item/reason/ownership evidence/dimensions | Approved event class and method-specific cost evidence; no arbitrary balancing account | Inventory owns draft/approved/posted/reversed |
| `stock_transfers` and `stock_transfer_lines` | Needs Extension | Existing header/line UUIDs | Company, source/destination scope/location, item, dispatch/receipt events | Source and destination differ; conserved base quantity/value; no cross-company shortcut | Inventory owns requested/approved/dispatched/in-transit/received/reversed |
| `goods_issues` and `goods_issue_lines` | Needs Extension | Existing header/line UUIDs | Company/warehouse/item/source class/destination role/dimensions | Only approved destination classes; Production/WIP sources fail closed | Inventory owns draft/approved/posted/reversed |
| `physical_count_sheets` and line table | Needs Extension | Existing header/line UUIDs | Company/warehouse/location/item/identity, count snapshot, approver | Snapshot immutable; recount and approved variance distinct; positive Specific ID evidence required | Inventory owns count capture; approved variance emits a separate adjustment occurrence |

## 3. Existing derived tables requiring split or deprecation

| Table/object | Disposition | Key and relationship target | Constraints/indexes required during transition | Lifecycle and final authority |
| --- | --- | --- | --- | --- |
| `inventory_transactions` | Needs Split | Existing UUID maps, where deterministic, to one immutable `inventory_event`; line/header references map to source relationships | Prevent new legacy-only rows after source cut-over; index conversion class/source/date | Retain read-only compatibility projection; `inventory_events` become authoritative |
| `inventory_cost_layers` | Needs Split | Existing rows classified FIFO, Specific ID, WAC receipt evidence, legacy-only, or blocked | No fabricated WAC remaining state; no automated identity inference; index source/method/class | FIFO layers, Specific-ID state, and WAC receipt evidence become separate authorities |
| `stock_balances` | Needs Deprecation as authority; Needs Extension as projection | Key becomes valuation/stock scope rather than only warehouse/item | Projection version/watermark; direct writes denied; rebuild uniqueness by projection grain | Rebuildable current-state projection only; events and method state own facts |
| `stock_balances.wac_unit_cost` | Needs Deprecation | Replaced by latest WAC pool version-derived display value | Cannot be accepted as posting input after WAC cut-over | Compatibility display only until report cut-over |
| `stock_balances.total_cost` | Needs Deprecation | Replaced by authoritative method-state GL-basis value | Must equal method projection while compatibility field exists | Compatibility projection, never source of valuation |
| generic WAC rows in `inventory_cost_layers` | Needs Deprecation as available layers | Reclassified to receipt-history evidence only where source facts are deterministic | No remaining-quantity/value reconciliation and no invented consumption | Legacy evidence or converted WAC receipt record; never WAC valuation state |

## 4. New governance and event tables

| Required table | Disposition | Primary key | Foreign keys | Constraints and indexes | Ownership and lifecycle |
| --- | --- | --- | --- | --- | --- |
| `inventory_accounting_profiles` | Needs New Table | Profile-version UUID | Company, functional currency, Period/Currency policy identities | Effective ranges non-overlapping; approved/frozen states; index company/effective date | Accounting Policy owns draft/approved/superseded; event references immutable version |
| `inventory_cost_formula_policies` | Needs New Table | Policy-version UUID | Accounting profile, nature/use group | One eligible method/scope rule per effective population; Specific ID eligibility | Inventory Policy owns approved versions; retrospective change requires conversion evidence |
| `inventory_valuation_scopes` | Needs New Table | Scope-version UUID | Company, item/policy group, branch/warehouse as configured, currency | Unique effective scope key; no transaction-level method override; index company/item/method | Inventory Master owns effective versions; event retains scope version |
| `inventory_precision_policies` | Needs New Table | Precision-version UUID | Accounting profile, currency/UOM references | Quantity 0–6, amount 8, rate 12, valid minor-unit scale; non-overlap | Accounting Policy owns; immutable after use |
| `inventory_events` | Needs New Table | Event UUID | Company, item, base UOM, scope version, accounting profile, source occurrence, actor | Immutable; unique idempotency/source occurrence/event class; deterministic order index; signed quantity rules | Inventory owns admitted/calculated/committed/reversed-by-event; rows never updated to erase facts |
| `inventory_event_values` | Needs New Table | Event-value UUID | Inventory event, currency/rate identity, precision policy | One authoritative value per value role/version; fixed-point; debit/credit plan totals exact | Inventory owns calculation versions; supersession is append-only |
| `inventory_event_source_links` | Needs New Table | Relationship UUID | Inventory event, source header and source line registry identities, related event | Explicit typed relationship; unique role/cardinality; indexed both directions | Source owner supplies evidence; Inventory validates and freezes admitted link |
| `inventory_occurrences` | Needs New Table | Occurrence UUID | Company, source lock, Posting occurrence/journal when applicable | Unique source type/source ID/version/idempotency; terminal success or explicit failure evidence | Orchestrating owner; links atomic domain outputs to one Posting call |
| `inventory_event_allocations` | Needs New Table | Allocation UUID | Event/value, destination source/method record | Stable ordinal/tie-break; child amounts/quantities equal parent exactly | Inventory owns immutable allocation and reversal ancestry |
| `inventory_replay_versions` | Needs New Table | Replay UUID | Scope, triggering event/correction, prior replay | Monotonic version per scope; deterministic event watermark; one certified active projection version | Inventory owns requested/running/completed/failed/superseded without changing source facts |
| `inventory_projection_versions` | Needs New Table | Projection version UUID | Replay version, scope | Unique projection kind/scope/watermark; checksum/index for rebuild | Inventory owns rebuild evidence; stale state cannot be presented as current |

## 5. New method-state and physical-state tables

| Required table | Disposition | Primary key | Foreign keys | Constraints and indexes | Ownership and lifecycle |
| --- | --- | --- | --- | --- | --- |
| `inventory_fifo_layers` | Needs New Table | FIFO layer UUID | Receipt event/value, scope, source ancestry | Positive original values; exact remaining quantity/value; immutable acquisition order; queue index | Inventory owns active/blocked/in-transit/exhausted; corrections add versions |
| `inventory_fifo_consumptions` | Needs New Table | Consumption UUID | Issue event, FIFO layer, allocation/reversal | Unique issue/layer/ordinal; sums exact; final consume takes residual | Inventory owns immutable partial/full consumption and reversal restoration |
| `inventory_wac_pools` | Needs New Table | Pool UUID | Valuation scope | One pool per effective scope; no receipt-layer semantics | Inventory owns pool identity; versions own changing state |
| `inventory_wac_pool_versions` | Needs New Table | Pool-version UUID | Pool, inventory event, prior version, replay version | Continuous version chain; exact quantity/value; derived rate; zero-state rules; scope/order index | Inventory owns append-only receipt/issue/return/correction/transfer transitions |
| `inventory_wac_receipt_cost_records` | Needs New Table | Receipt-record UUID | Receipt event/value, scope, source line | Immutable receipt quantity/cost; no remaining/exhausted fields; source/date index | Inventory audit evidence only; never consumed |
| `inventory_physical_age_lots` | Needs New Table | Age-lot UUID | Physical receipt event/source; item/location/identity if tracked | Acquisition/acceptance date rule and policy version; quantity exact | Inventory owns physical ageing evidence independent of valuation |
| `inventory_physical_age_allocations` | Needs New Table | Allocation UUID | Issue/transfer/return/reversal event and age lot | FIFO-by-receipt allocation for untracked WAC; exact quantity and ancestry | Inventory Reporting projection; cannot change WAC value |
| `inventory_identities` | Needs New Table | Identity UUID | Company/item/lot or serial master/source receipt | Serial uniqueness; lot identity key; one active ownership/location/status | Inventory owns identity; immutable identifier with current projection |
| `inventory_identity_events` | Needs New Table | Identity-event UUID | Identity, inventory event, location/status, prior identity event | Legal state transitions; deterministic order; no double availability | Inventory owns receipt/hold/transfer/issue/return/disposal history |
| `inventory_specific_id_values` | Needs New Table | Identity-value UUID | Identity, receipt/correction/write-down event, scope | One active gross carrying value version; allowance separate | Inventory owns acquisition/correction versions; disposal closes active value |
| `inventory_reservation_events` | Needs New Table | Reservation-event UUID | Sales/source line, item, location/scope | Reserve/release/consume quantities exact; no owned/value effect; idempotent | Inventory owns immutable availability changes |
| `inventory_reservation_balances` | Needs New Table | Projection key UUID | Scope/item/location/source | Direct writes denied; reserved cannot exceed eligible available under policy | Rebuildable projection only |

## 6. New acquisition, matching, correction, and control tables

| Required table | Disposition | Primary key | Foreign keys | Constraints and indexes | Ownership and lifecycle |
| --- | --- | --- | --- | --- | --- |
| `inventory_ownership_occurrences` | Needs New Table | Ownership UUID | Source line, event/occurrence, policy/evidence | Explicit control timestamp/status; no inferred ownership; unique source control event | Commercial source owner proposes; Inventory admits; reversals append |
| `purchase_match_headers` | Needs New Table | Match UUID | Company/vendor/currency/policy | Approved immutable occurrence identity; status/open/closed/reversed | Purchasing/AP owns |
| `purchase_match_lines` | Needs New Table | Match-line UUID | Match, PO line, receipt event, bill line, return/credit/correction links | Exact matched quantity/value; no overmatch; unique source allocation; lock indexes | Purchasing/AP owns append-only match/unmatch/reversal facts |
| `inventory_control_occurrences` | Needs New Table | Control-occurrence UUID | Inventory/AP/source occurrence, account role, event/journal | Typed GRNI, GINR, in-transit, clearing, return-variance role; exact amount and open/clear links | Domain owner supplies occurrence; Reporting derives schedule |
| `inventory_cost_corrections` | Needs New Table | Correction UUID | Original source/event, classification, replay, approval | Price/landed/discount/rebate/error/estimate types explicit; no source mutation | Inventory owns proposed/approved/calculated/posted/reversed |
| `inventory_correction_destinations` | Needs New Table | Destination UUID | Correction, original issue/destination event, journal role, period treatment | Allocations equal full correction; closed/current/restatement roles explicit | Inventory + Period own evidence; PE persists approved plan |
| `inventory_landed_costs` | Needs New Table | Landed-cost UUID | Company/vendor/source document/currency | Approved attributable class; lifecycle and source amount exact | Purchasing/AP captures; Inventory owns capitalization decision |
| `inventory_landed_cost_allocations` | Needs New Table | Allocation UUID | Landed cost, receipt event/item, correction | Approved allocation basis; stable residual allocation; total equals source | Inventory owns immutable allocation/reversal |
| `inventory_deficits` | Needs New Table | Deficit UUID | Issue event, scope, policy/provisional cost source | FIFO/WAC only; open-period; exact provisional quantity/value; Specific ID prohibited | Inventory owns open/part-settled/settled/reversed; Period close blocks open |
| `inventory_deficit_settlements` | Needs New Table | Settlement UUID | Deficit, receipt event, correction destination | Cannot settle beyond deficit; exact variance allocation | Inventory owns append-only settlement |
| `inventory_nrv_assessments` | Needs New Table | Assessment UUID | Company, item/group, cut-off, accounting profile, evidence | Approved grain/grouping justification; NRV and reversal ceiling fixed-point | Inventory/Accounting Policy owns draft/approved/superseded |
| `inventory_valuation_adjustments` | Needs New Table | Adjustment UUID | Assessment, scope/item, prior allowance event, Posting occurrence | Zero quantity; gross cost unchanged; reversal capped; source idempotent | Inventory owns posted write-down/reversal chain |
| `inventory_opening_batches` | Needs New Table | Batch UUID | Company, cut-off, accounting profile, evidence package | One active conversion per cut-off; suspense must be zero to close/go live | Conversion owner controls draft/validated/posted/certified/reversed before go-live |
| `inventory_opening_lines` | Needs New Table | Opening-line UUID | Batch, item/scope/location/identity, source evidence, event | One governed source line; exact quantity/value/allowance; no plug lines | Inventory owns line admission and method-state creation |
| `inventory_opening_control_lines` | Needs New Table | Control-line UUID | Batch, GL account/dimension, evidence/journal line | Full Trial Balance control; equity separate; exact zero suspense | Conversion/Accounting owns; no unexplained residual |

## 7. New reconciliation and report-control tables

| Required table | Disposition | Primary key | Foreign keys | Constraints and indexes | Ownership and lifecycle |
| --- | --- | --- | --- | --- | --- |
| `inventory_reconciliation_runs` | Needs New Table | Run UUID | Company, cut-off, policy/replay/projection versions, requester | Immutable parameters, watermarks, fingerprints, control totals; unique certified run identity | Reporting owns requested/completed/failed/certified; read-only against accounting facts |
| `inventory_reconciliation_exceptions` | Needs New Table | Exception UUID | Run, item/scope/source/event/journal where present | First failing boundary, exact quantity/amount, classification, owner/status | Reporting records; remediation occurs only through governed source workflow |
| `inventory_report_runs` | Needs New Table | Report-run UUID | Company, report contract, policy/watermark, actor | Deterministic parameter fingerprint, row count/control totals/export identity | Reporting/Audit owns immutable generation evidence |

These tables do not post, adjust, or reconcile by mutation.

## 8. Relationship graph

The required lineage is:

`source header/line → source-locked occurrence → ownership/admission evidence → immutable
inventory event → event value/allocation → method state/projection → Posting occurrence
→ journal header/line`.

Purchasing/AP adds:

`PO line ↔ physical/owned receipt event ↔ Vendor Bill line ↔ return/credit/correction`
through the Purchase Match Ledger.

Correction lineage is:

`original source/event → replay version → exact delta → correction destinations →
Posting occurrence`, never an update to the original event or journal.

## 9. Required index and lock strategy

IA-5 detailed design must provide, without changing these ownership rules:

- unique source occurrence/idempotency keys;
- deterministic event order by scope, effective timestamp, recorded timestamp, stable
  tie-breaker;
- scope-current method-state lookup;
- FIFO eligible queue order and issue/layer allocation lookup;
- WAC current version and replay-chain lookup;
- identity uniqueness and current-state lookup;
- PO/receipt/bill unmatched line lookup;
- open deficit, GRNI, GINR, transit, allowance, and correction schedules;
- source-to-event-to-journal reverse drill-through; and
- projection watermark/report cut-off lookup.

Lock order is company/source occurrence, valuation scopes in stable key order, method
state, source match rows, then Posting source lock. Any workflow needing a different
order is blocked pending architecture review because deadlock avoidance is part of the
atomic contract.

## 10. Historical-data conversion classes

Every legacy row receives exactly one planning classification:

1. deterministically convertible from explicit source-line and method facts;
2. retained in a labeled legacy valuation/history view;
3. transferred through user-reviewed opening conversion evidence; or
4. blocked from automated conversion.

No generic WAC layer may be converted to an available quantity/value layer. No missing
RR/VB line match, ownership date, FIFO allocation, lot/serial identity, or opening
equity may be inferred. Conversion mapping and counts are an IA-5 deliverable; execution
requires later explicit authorization.
