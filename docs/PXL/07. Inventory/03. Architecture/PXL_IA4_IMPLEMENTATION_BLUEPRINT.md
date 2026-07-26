# PXL IA-4 Inventory Accounting Implementation Blueprint

**Status:** IA-4 planning baseline
**Authority:** Engineering contract derived from frozen IA-3 architecture
**Owner / Domain:** Inventory Accounting
**Applies To:** IA-5 through IA-14 implementation planning
**Last Reviewed:** 2026-07-26
**Implementation Status:** Blueprint only; no implementation is authorized

## 1. Executive conclusion

The repository contains a usable operational inventory shell and a certified Posting
Engine boundary, but it does not implement the frozen IA-3 valuation architecture.
Existing source documents, numbering, period validation, dimensions, Posting Kernel
integration, item/warehouse masters, and four inventory posting workflows are reusable
only behind a new Inventory Engine event and method-state contract.

The largest gaps are:

- no immutable, line-grained inventory event identity or deterministic replay order;
- no authoritative WAC Model A pool/history;
- no independent FIFO valuation queue and physical identity ledger;
- no complete Specific Identification lifecycle;
- no ownership occurrence, GRNI/GINR, line-level purchase match, or cost-correction
  destination bridge;
- Sales currently recognizes inventory consumption from Sales Invoice rather than the
  frozen control-transfer occurrence;
- current precision (`quantity 4`, `unit cost 6`, `extended amount 2`) does not satisfy
  the frozen fixed-point contract;
- current reports read mutable projections and generic cost-layer rows instead of
  method-specific authoritative state; and
- `fn_receive_inventory(jsonb)` remains an authenticated mutation RPC even though
  direct authenticated writes to the three derived inventory tables are denied.

The six sanctioned Posting Kernel persistence functions, source-lock/idempotency
protocol, COA Resolver, tax boundary, period controls, journal ordering, audit, and
Kernel Totality Guard are reusable and remain frozen. No Posting Engine or Kernel
change is required by this blueprint.

The target is implementation-ready at blueprint level only after the IA-5 scope below
is separately authorized. P5.3B, P6, and P7 remain paused.

## 2. Evidence baseline and review method

The census used current repository artifacts rather than old fixtures:

- frozen authorities in this directory, including the IA-3 decision register and ADR;
- all migrations through `20260726000012_posting_engine_p52_arm_totality_guard.sql`;
- current inventory, Purchasing, Sales, returns, item-master, Posting, and preview
  functions;
- current inventory pages and their PostgREST/RPC calls;
- current SQL certification tests `031`, `054`, `055`, `057`, `070`, `085`, `089`,
  `091`, `096`, and `100`; and
- the P5.2 security census and direct-mutation closure.

Repository evidence is a point-in-time IA-4 census. A later migration cannot be treated
as satisfying a requirement until its tests and traceability row are updated in an
authorized implementation phase.

Key current-repository evidence anchors are:

| Evidence area | Current repository authority |
| --- | --- |
| Inventory tables, generic helpers, and four original writers | `supabase/migrations/20260630000028_inventory.sql` |
| Source-lock/idempotency wrappers and internal-helper privilege closure | `supabase/migrations/20260711000001_posting_engine_completion.sql` |
| Transfer availability and current transfer implementation | `supabase/migrations/20260716000001_stock_transfer_availability_guard.sql` |
| RR confirmation and Cash Purchase receipt integration | `supabase/migrations/20260718000001_purchase_dimensions_inventory_receiving.sql` |
| Item costing/negative-policy readiness and UOM conversion | `supabase/migrations/20260722000005_mdp13_item_master_inventory_readiness.sql` |
| Current Sales Invoice accounting timing and resolver | `supabase/migrations/20260724000003_posting_engine_p2a_sales_resolver.sql` |
| Current Vendor Bill/Cash Purchase accounting | `supabase/migrations/20260725000001_posting_engine_p3a_dimension_push.sql` |
| Current Purchase Return accounting | `supabase/migrations/20260724000005_posting_engine_p2d_banking_payments_resolver.sql` |
| Kernel migration of inventory writers | `supabase/migrations/20260726000006_posting_engine_p51_stage5_inventory.sql` |
| Derived-table DML closure | `supabase/migrations/20260726000001_posting_engine_p5a_surface_closure.sql` |
| Enforced journal totality guard | `supabase/migrations/20260726000012_posting_engine_p52_arm_totality_guard.sql` |
| Operational inventory/report clients | `src/pages/ReceivingReportsPage.tsx`, `DeliveryReceiptsPage.tsx`, `StockAdjustmentPage.tsx`, `StockTransferPage.tsx`, `GoodsIssuePage.tsx`, `PhysicalCountPage.tsx`, `InventoryValuationPage.tsx`, `InventoryMovementsPage.tsx`, and `StockBalancePage.tsx` |
| Current inventory compatibility/certification tests | `supabase/tests/031_posting_runtime_repairs_test.sql`, `054_sales_invoice_completeness_test.sql`, `070_mdp13_item_master_inventory_readiness_test.sql`, `085_posting_engine_p2c_inventory_resolver_test.sql`, `089_posting_engine_p3d_preview_resolver_test.sql`, `096_posting_engine_p51_stage5_inventory_test.sql`, and `100_posting_engine_p51_stage9_commerce_test.sql` |

## 3. Implementation gap census

`Fully implemented` means the current workflow satisfies its frozen IA-3 responsibility,
not merely that a screen or RPC exists. `Incorrect` means current behavior conflicts
with a frozen rule. `Legacy` identifies a usable predecessor that cannot remain the
authoritative implementation.

| Workflow | Census classification | Current evidence | Reuse decision | Required implementation path |
| --- | --- | --- | --- | --- |
| Purchase Order | Partially implemented | Governed save/lifecycle and dimensions exist; no ownership terms, acquisition policy version, or immutable downstream line occurrence | Reuse document, numbering, dimensions, validation order | Extend lines with governed commercial ownership evidence and source-line identity in IA-5/IA-7 |
| Receiving Report | Incorrect | Save/confirm exists; confirmation aggregates lines and calls generic `fn_receive_inventory`; no ownership event or accounting | Reuse document and validation shell | Replace confirmation orchestration with line-grained custody/ownership events and Goods Receipt contract |
| Goods Receipt | Missing | No independent governed receipt occurrence; generic receipt helper mutates projections directly | Retire generic public contract | Create Inventory-owned receipt admission/calculation/commit service in IA-5/IA-7 |
| Vendor Bill | Incorrect | Posting, AP, tax, dimensions, and `rr_id` exist; line account drives debit; no line match, GRNI/GINR, or Inventory correction output | Reuse AP/Tax lifecycle and kernel posting | Add immutable purchase match; route only source-linked cost corrections to Inventory |
| Payment | Fully implemented | Treasury/AP settlement does not alter inventory | Reuse unchanged | Compatibility tests only |
| Cash Purchase | Partially implemented | Financial posting and generic inventory receipt are atomic, but receipt lacks ownership, event identity, policy, method state, and exact precision | Reuse document/AP/Tax/kernel shell | Replace inventory portion with simultaneous owned receipt contract |
| Vendor Credit — price only | Partially implemented | AP/tax posting exists; no Inventory cost correction | Reuse financial document | Add explicit source match and Inventory correction plan |
| Purchase Return | Incorrect | Completion posts financial reversal but does not create outbound inventory quantity/layer event | Reuse document and kernel shell | Add physical return event at method carrying cost; keep commercial credit distinct |
| Damaged goods retained | Missing | No governed write-down, write-off, disposal, or linked vendor-credit workflow | None | Add explicit physical/value event in IA-10 |
| Sales Order | Partially implemented | Commitment exists; no governed immutable reservation event/projection contract | Reuse source document | Add reservation service/projection without changing owned quantity |
| Delivery / Sales recognition | Incorrect | Delivery receipt is direct PostgREST CRUD and nonposting; Sales Invoice later owns COGS | Reuse operational document only | Create source-locked control-transfer occurrence; Sales and Inventory outputs post atomically |
| Sales Invoice | Incorrect | Posts AR/revenue/tax and consumes stock/COGS at invoice date | Reuse billing, tax, COA, journal shell | Remove Inventory ownership from billing after control-transfer rollout; reclassify unbilled balance only |
| Receipt from customer | Fully implemented | Cash receipt changes AR/cash, not inventory; classification is limited to the frozen Inventory boundary | Reuse unchanged | Compatibility tests only |
| Sales Return | Missing | Customer Return builds a Credit Memo and remarks link; no governed inventory receipt or original-issue ancestry | Reuse Credit Memo financial workflow | Add accepted return event at latest corrected original issue cost |
| Credit Memo | Partially implemented | AR/revenue/tax reversal exists; no governed physical-return link | Reuse financial document | Add optional mandatory link policy where a physical return is claimed |
| Goods Issue | Partially implemented | Posting consumes WAC/FIFO state and updates stock/movement; lacks immutable event/version/precision/source-class contract | Reuse validation, dimensions, source lock, kernel shell | Replace costing internals with method service result |
| Non-purchase Goods Receipt | Legacy | Generic receipt accepts arbitrary JSON source and cost | No authoritative reuse | Add source-class-specific admission; fail unknown sources |
| Inventory Adjustment | Partially implemented | Quantity/value/GL writer exists; positive cost can be arbitrary and method rules are incomplete | Reuse document/lifecycle/kernel shell | Implement explicit reason, ownership evidence, method-specific measured cost |
| Physical Count | Incorrect | Count posts variance, but positive costing can fall to standard/zero and Specific ID can be unmeasurable | Reuse count capture and approval shell | Separate snapshot from approved adjustment; quarantine unsupported positive identities |
| Stock/Warehouse Transfer | Incorrect | Writer moves balances/layers; FIFO destination layer date resets to transfer date; no preserved queue ancestry or in-transit lifecycle | Reuse document/source lock/kernel shell | Implement dispatch/receipt events, conservation, scope transition, preserved FIFO order |
| Branch Transfer | Partially implemented | Warehouse branch/account dimensions exist; no explicit scope policy or transit schedule | Reuse warehouse/branch master | Add same-entity scope transition and conditional GL reclassification |
| Intercompany Inventory | Missing | No certified cross-company source type | None; fail closed | Deferred until Intercompany/Tax/Currency authorities |
| Opening Inventory | Incorrect | Seed/manual-journal assumptions establish state in sequence; no governed conversion batch or suspense control | No authoritative workflow reuse | Create opening batch, lines, method state, and atomic Opening GL plan |
| Opening GL | Partially implemented | Manual Journal works, but frozen architecture prohibits ordinary MJ to Inventory controls | Reuse Posting persistence only | Opening conversion owns the linked Posting plan and zero-suspense gate |
| NRV write-down/reversal | Missing | No allowance ledger, evidence grain, ceiling, or workflow | None | Add zero-quantity valuation-adjustment workflow in IA-10 |
| Landed Cost | Missing | No cost source/allocation/correction ledger | None | Add approved allocation and method replay in IA-10 |
| Cost Correction / re-cost | Missing | No immutable replay version or destination bridge | None | Add source-linked correction plan and open/closed-period classification |
| Negative Inventory | Incorrect | Master policy exists; writers are inconsistent and no deficit settlement/close gate exists | Reuse policy field/resolver | Add explicit deficit lifecycle for FIFO/WAC; keep Specific ID blocked |
| Backdated Transaction | Missing | Effective dates exist, but no deterministic event replay or correction emission | Reuse period validation | Add event ordering, scope locks, replay versions, and IAS 8 interface |
| Write-off / disposal | Partially implemented | Goods Issue/negative adjustment can reduce stock, but no dedicated governed accounting meaning or allowance handling | Reuse issue mechanics | Add reason-specific event and configured loss/allowance contract |
| Inbound consignment | Legacy | Warehouse type supports consignment, but generic receipt capitalizes inventory | Reuse location classification | Add custody-only identity/quantity and explicit ownership conversion |
| Outbound consignment | Missing | No owned-consignment dispatch/control-transfer lifecycle | Reuse future transfer event primitives | Add owned custody location transition; recognize sale only on control transfer |
| Fixed Asset inventory-like acquisition | Fully implemented | Fixed Asset engine owns its register and Posting output; classification is limited to the frozen Inventory boundary | No Inventory change | Boundary regression only |
| Production issue/completion | Deferred | No certified Production architecture | None; fail closed | Accept only future certified boundary events |
| Inventory reversal | Partially implemented | Source writers and sales voids have workflow-specific reversal behavior; no universal exact event ancestry | Reuse frozen journal reversal | Add Inventory reversal event that restores exact method allocation and links kernel reversal |
| Inventory preview | Incorrect | Sales preview reads current WAC/standard values and cannot replay FIFO/Specific state deterministically | Reuse presentation and Posting-plan comparison | Invoke same pure Inventory calculator with source/scope locks rechecked at post |
| Inventory reports | Legacy | Pages read `stock_balances`, `inventory_transactions`, and generic layers directly | Reuse UI shells selectively | Replace data contracts with cut-off, method-specific, independently reconcilable views/services |
| Inventory reconciliation | Missing | Tests prove selected aggregate equalities only; no complete contract reports or exception lifecycle | Reuse GL and source trace facilities | Implement independent schedules and zero-variance close gate in IA-12 |

## 4. Current assets approved for reuse

The following reuse is conditional on preserving existing certified behavior:

- Posting: six sanctioned persistence functions, kernel guard, source lock/idempotency,
  journal numbering/order, audit, dimensions, reversal, and Posting preview contract.
- Accounting boundaries: COA Resolver, Tax Engine outputs, Period Engine checks, company
  functional currency, and GL views.
- Source shells: purchase/sales documents, stock adjustment/transfer/issue/count
  documents, lifecycle statuses, approval permissions, and number series.
- Master data: item inventory/COGS accounts, base UOM references, costing-method and
  negative-policy resolvers, warehouses, zones, branches, and company membership.
- Read UI: existing inventory pages may become clients of authoritative services, but
  their current direct projection queries are not authoritative.
- Regression: current Posting and inventory SQL tests remain a legacy-output
  compatibility lane until each behavior is intentionally superseded and fingerprinted.

Reuse never means retaining a current calculation that contradicts IA-3.

## 5. Current objects that cannot remain authoritative

| Current object | Finding | Target treatment |
| --- | --- | --- |
| `inventory_transactions` | Mutable-width generic movement rows lack event identity, versions, exact values, source lines, ownership, and supersession | Split into immutable event/value/relationship records; retain a compatibility projection only |
| `inventory_cost_layers` | One structure conflates FIFO/Specific valuation with WAC receipt history | Split into FIFO layers, Specific-ID valuation/identity, and WAC receipt evidence; never convert WAC receipt rows into invented remaining state |
| `stock_balances.total_cost` and `wac_unit_cost` | Mutable projection currently acts as cost source | Demote to rebuildable projection; WAC pool version owns authoritative quantity/value |
| `fn_receive_inventory(jsonb)` | Authenticated generic `SECURITY DEFINER` writer with no governed source admission or GL atomicity | Revoke external execution and replace callers with governed line-grained services |
| `fn_consume_cost_layers` / `fn_add_cost_layer` / `fn_update_wac` | Method logic is generic and lacks frozen precision/version semantics; external grants are already revoked | Replace internal use by method-specific services; retain only during bounded compatibility transition |
| header-only `vendor_bills.rr_id` | Cannot represent partial, multi-line, or many-to-many matching | Retain as non-authoritative convenience if needed; immutable line match owns accounting |
| current direct report queries | Cannot reconstruct cut-off and often compare WAC receipt rows as remaining state | Cut over to authoritative report services; no indefinite dual-read |

## 6. Implementation sequence

The sequence is fixed by the IA-3 roadmap. No phase is skipped or combined without a
separately approved blueprint amendment.

| Phase | Objective and deliverables | Dependencies | Exit criteria | Rollback boundary | Expected risks |
| --- | --- | --- | --- | --- | --- |
| IA-5 Event and Source-Link Foundation | Add policy/precision/scope identities, immutable event/source/occurrence records, exact amount bases, admission/idempotency contract, writer security closure | IA-4 approval; frozen P5.2 boundary | Event/source identity and fixed-point proofs; all inventory writers enumerated; `fn_receive_inventory` no longer externally callable; no changed accounting output | Additive objects and dormant services; legacy writers remain sole active path until cut-over gate | duplicate occurrences, lock order, incomplete source-line links, precision conversion |
| IA-6 Method-State Foundation | Add FIFO valuation state, WAC pool/history/receipt evidence, Specific-ID and physical trace, WAC ageing, rebuildable projections, pure valuation interface | IA-5 immutable events and precision | deterministic replay; quantities and method state exact; no new GL behavior active | Per-method feature flag/cut-over; projections rebuildable from events | replay cost, method mixing, WAC zero residual, identity duplication |
| IA-7 Acquisition Accounting and Purchase Matching | Implement ownership terms, Goods Receipt, GRNI, GINR, in-transit acquisition, purchase matching, invoice-before-receipt, simultaneous receipt/bill, correction boundary | IA-6 method receipt state; AP/Tax/COA interfaces | partial/full receipt/bill schedules exactly reconcile; current AP/tax outputs preserved where unchanged | Source-type cut-over by company after clean conversion; no dual accounting | duplicate asset recognition, incorrect control date, tax/FX contamination, match races |
| IA-8 FIFO and Specific-ID Certification | Implement all issues, sales/returns, purchase returns, transfers, corrections, identity rules, FIFO queue preservation, method reports | IA-7 acquisition occurrences | stock, layers/identity, subledger, COGS destinations, and GL exact | Company/item policy cohort rollback before certification only | queue contention, return ancestry, serial/lot conflicts |
| IA-9 Moving WAC Model A Certification | Activate WAC pool/history, issue/return/transfer rules, deficit settlement, and independent ageing | IA-7 acquisition; IA-6 WAC state | stock = movements = pool quantity; pool value = subledger = GL; receipt rows excluded | Company/item policy cohort rollback before certified postings; then reversal/correction only | residual drift, replay amplification, stale average use |
| IA-10 Advanced Cost and Correction Events | Landed cost, rebates/discounts, cost corrections, backdating, IAS 8 plan, deficits, write-off/disposal, NRV allowance/reversal | IA-8/IA-9 certified methods; Period policy interface | every delta source-linked; allowance/correction bridges exact; closed journals immutable | Feature-gated event classes; reverse new events, never mutate history | large replay scope, prior-period classification, allocation residuals |
| IA-11 Transfer, Custody, and Multi-Scope | Complete dispatch/receipt, in-transit, branch/warehouse scopes, consignment custody/ownership conversion; block deferred intercompany behavior | Certified method state and ownership occurrence | quantity/value conservation; no internal profit; custody excluded; unsupported types fail | Route/source-type flags; paired transfer events reverse together | distributed locks, lost-in-transit state, scope misconfiguration |
| IA-12 Reporting and Reconciliation | Implement all frozen reports, independent schedules, watermarks, fingerprints, exception census, and period close gate | IA-7–IA-11 authoritative state | exact method/source/control-account reconciliation at required grain | Report cut-over by named contract; legacy views labeled and time-bounded | projection staleness, self-reconciliation, expensive cut-off replay |
| IA-13 Canonical Modernization | Resume P5.3B with FIFO/WAC/Specific ID and every frozen source scenario | IA-12 reports and all active workflows | deterministic replay; intentional fingerprints explained; P5.2 unchanged | Local fixture branch/reset only | fixture hiding an engine defect, stale assumptions |
| IA-14 Inventory Accounting Certification | Run complete method, security, accounting, replay, concurrency, performance, reversal/correction, preview, and docs lanes | IA-13 certified canonical data | zero unexplained variance, zero unauthorized mutations, all method and Posting compatibility proofs green | No destructive rollback; defects use governed reversal/correction or pre-production cut-over rollback | rare concurrency paths, scale regressions, incomplete conversion class |
| Resume P6 | Read-only then formal subledger reconciliation | IA-14 | Inventory no longer blocks exact P6 certification | Read-only | cross-domain cut-off/grain mismatch |

## 7. Transition and cut-over rules

1. IA-5 and IA-6 are additive and dormant until their method/source gates pass.
2. One source occurrence has one active writer. Indefinite dual-write and dual-authority
   are prohibited.
3. Legacy data is classified as deterministically convertible, legacy-view-only,
   user-evidenced opening conversion, or blocked. Missing facts are never inferred.
4. Existing WAC receipt rows remain historical evidence; their remaining quantity/value
   is not manufactured or certified.
5. A company/method cohort cuts over only at an approved boundary with opening method
   state and GL equality. After certified posting, rollback uses reversal/correction,
   not table restoration.
6. Reports disclose their source contract and watermark throughout transition. A legacy
   report cannot be labeled IA-3 compliant.
7. Every phase keeps the P5.2 guard enforced and the sanctioned Kernel set at six.

## 8. Ownership summary

| Responsibility | Owner |
| --- | --- |
| Physical, custody, owned, reserved, available, and in-transit quantities | Inventory Engine |
| Cost method, event ordering, method state, carrying cost, COGS input, ageing evidence | Inventory Engine |
| Purchase source capture, line matching, GRNI/GINR schedules, payable occurrence | Purchasing/AP |
| Revenue/AR or contract-asset values and control-transfer occurrence | Sales/AR |
| Tax classification, recoverability, and tax values | Tax Engine |
| Functional-currency rate identity | Currency authority; unsupported foreign-currency sources fail closed until certified |
| Period status and IAS 8 error/estimate classification | Accounting Policy/Period owner |
| Accounts | COA Resolver |
| Ordered journal, numbering, audit, atomic persistence | Frozen Posting Engine and Kernel |
| Read-only projections, reports, and exception presentation | Reporting |
| Production conversion facts | Deferred Production Engine |

## 9. Blueprint document set

- `PXL_IA4_ARCHITECTURE_TRACEABILITY_MATRIX.md`
- `PXL_IA4_DATABASE_BLUEPRINT.md`
- `PXL_IA4_RPC_SERVICE_POSTING_CONTRACT_BLUEPRINT.md`
- `PXL_IA4_TEST_CANONICAL_RISK_BLUEPRINT.md`

Together these documents are the complete IA-4 engineering contract. They contain no
SQL, migration, schema mutation, code, test, seed, or Posting Engine change.

## 10. IA-4 decision

The project is **IMPLEMENTATION READY FOR IA-5 ONLY**, subject to separate
authorization. This is not a claim that Inventory Accounting is implemented or
certified.

IA-5 must be limited to the event/source-link, precision, policy/scope identity,
idempotency/concurrency, and security foundations described here. It must not activate
new accounting behavior, convert historical user data, alter the Posting Kernel, or
start P5.3B/P6/P7.
