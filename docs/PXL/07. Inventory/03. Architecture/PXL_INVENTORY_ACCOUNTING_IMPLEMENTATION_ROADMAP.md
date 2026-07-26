# PXL Inventory Accounting Required Future Implementation Roadmap

**Status:** Frozen roadmap — IA-3 hardened
**Authority:** Tier 1 Domain Architecture
**Owner / Domain:** Inventory Accounting
**Applies To:** Future governed design, implementation, transition, and certification phases after IA-3
**Read When:** Scoping the next approved Inventory Accounting phase
**Do Not Read For:** Authorization to implement any phase
**Last Reviewed:** 2026-07-26 — ECC-01 owner acceptance and IA-5 WP-1 authorisation
**Implementation Status:** IA-5 is landed and dormant; its permanent-foundation certification is **suspended** (evidence gate Outcome C, C-01 Critical). The authorised phase is IA-5 ECC hardening implementation — Work Package 1. Every later phase still requires separate execution authorization

## 1. Sequencing rules

- Each phase requires separate scope approval.
- Posting Engine architecture, six sanctioned persistence functions, Kernel Guard, COA Resolver, Preview, and Tax boundaries remain frozen.
- Work is local-first. No hosted or historical production mutation is implicit.
- Additive migration and compatibility strategy must be proven before any state conversion.
- Accounting changes are never hidden as canonical-data changes.
- Each phase has method-specific before/after evidence and a rollback/transition design.
- P5.3B resumes only after the required architecture is executable and certified.
- P6 resumes only after the refreshed canonical dataset passes method-specific reconciliation.

## 2. Required phases

| Phase | Scope | Required exit gate |
| --- | --- | --- |
| **IA-4 — Implementation Gap Census and Detailed Design** | Compare current schema/functions/workflows with all IA-3 invariants; inventory every writer, projection, layer use, report, account, source link, lifecycle, precision/currency behavior, and current-data shape. Produce schema/API/migration design only. | Complete gap matrix; no implementation; approved transition, precision, idempotency, and cut-over design |
| **IA-5 — Inventory Event and Source-Link Foundation** | **Landed and dormant; certification SUSPENDED.** Immutable inventory-event identity, line-level source relationships, valuation-scope identity, accounting-policy version, fixed-point value basis, atomic occurrence evidence, projection classification, and legacy generic receipt closure are implemented. Its event order is **Accepted Event Chronology**, not economic order: the [IA-5/IA-6 Final Evidence Gate](IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md) returned Outcome C with **C-01 Critical** because the accepted sequence is allocated by row-lock order. Remediation is [ECC hardening](../04.%20Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md) under [ADR-C01](ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md) and [ECC-01](ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md). | **Not passed.** Certification requires the reopened evidence gate to accept the ECC hardening evidence package (WP-9) and close C-01. Behaviour-unchanged, fixed-point, idempotency, security, and rollback proofs stand; H-01…H-09 and M-01 remain provisional and unexecuted |
| **IA-6 — Method-State Foundation** | Establish method-specific state: FIFO valuation layers, WAC pool/history and receipt-audit distinction, Specific-ID identity layers, and separate physical identity/ageing evidence. Protect projections from direct writes. | Quantity replay exact; method state deterministic; no GL behavior enabled until certified |
| **IA-7 — Acquisition Accounting and Purchase Matching** | Implement ownership-aware Goods Receipt, GRNI, GINR/Purchase Clearing, line matching, invoice-before-receipt, provisional-cost hierarchy, functional-currency acquisition cost, discounts/rebates, and bill price correction boundary. | Partial/full receipt and bill chains exact; GRNI and GINR reconcile; AP, FX, and tax boundaries remain distinct |
| **IA-8 — FIFO and Specific-ID Certification** | Complete layer consumption, corrected-cost returns, purchase returns, queue rules, transfers, corrections, serial/lot controls, and method reporting. | Layer quantity/value, stock, subledger, and GL exact for both methods |
| **IA-9 — Moving WAC Model A Certification** | Implement replayable WAC pool/history, immutable receipt evidence, issue costing, zero closure, corrected-cost sales returns, current-WAC purchase returns, transfer updates, and separate physical ageing. | Stock = movements = pool quantity; pool GL-basis value = subledger = GL; receipt rows excluded correctly |
| **IA-10 — Advanced Cost and Correction Events** | Landed cost, source-linked cost correction, open-period backdating/re-cost, IAS 8-classified closed-period correction plans, negative-inventory deficits, write-offs/disposals, and NRV allowances/reversals. | Every delta source-linked; closed periods immutable; correction destinations and NRV allowances reconcile; no general upward revaluation |
| **IA-11 — Transfer, Custody, and Multi-Scope Accounting** | Warehouse, branch, in-transit, consignment, ownership conversion, intercompany boundary events, and valuation-scope transitions. Detailed intercompany pricing/elimination/tax remains in its own future authority. | Quantity/value conservation; consigned custody separated from ownership; no internal same-entity profit; unsupported intercompany features gated |
| **IA-12 — Reporting and Reconciliation** | Build required inventory, method, purchase-match, GRNI, GINR, valuation, ageing, exception, opening, policy-change, and GL reports. | Independent exact reconciliation at item/scope/account/dimension/policy/currency grain |
| **IA-13 — Canonical Modernization (resume P5.3B)** | Rebuild canonical inventory fixtures under the IA-3 dataset specification; correct RR/VB, account defaults, Vendor Credit story, opening order; add missing scenarios. | Deterministic replay; expected fixture deltas explained; P5.2 guard unchanged |
| **IA-14 — Inventory Accounting Certification** | Full method matrix, precision/residuals, concurrency, reversal, correction, preview, replay, security, performance, regression, documentation, and negative-path certification. | Frozen architecture fully implemented and certified; zero unauthorized mutations and zero unexplained variance |
| **Resume P6** | Read-only then formal subledger reconciliation across all domains | Inventory no longer blocks P6; every control account exact |

## 3. IA-4 mandatory detailed-design decisions

IA-4 must not implement, but it must resolve:

- current-to-target object mapping for movements, stock projections, cost layers, WAC pool history, and valuation allowances;
- current writer/read/report census and security ownership;
- valuation-scope storage and method-change control;
- storage and calculation mapping for authoritative extended amounts, GL-basis amounts, currency minor-unit scales, quantity/UOM scales, rates, and largest-remainder residuals;
- event ordering and re-cost version model;
- line-level PO/RR/Goods Receipt/Vendor Bill matching;
- GRNI, GINR/Purchase Clearing, purchase-return variance, NRV allowance, Opening Conversion Suspense, evidenced opening-equity, and other required account configuration;
- atomic Inventory Engine-to-Posting Engine invocation;
- treatment of existing WAC receipt rows without fabricating remaining quantity;
- separate WAC physical-ageing and physical lot/serial trace storage;
- IAS 8 classification evidence and closed-period correction-plan interface;
- local/canonical versus historical/production transition policy;
- report cut-over and dual-read/dual-write prohibition or bounded strategy;
- failure recovery, idempotency, locks, and concurrency tests.

## 4. Historical-data transition guard

No phase may infer missing ownership, receipt/bill links, lot/serial identity, or cost allocations for historical user data.

The approved transition must classify records into:

- deterministically convertible from explicit source facts;
- retained under a clearly labeled legacy valuation view;
- requiring user-reviewed opening/conversion evidence; or
- unsupported and blocked from automated conversion.

No synthetic layer consumption or balancing journal may be created to make history appear compliant.

## 5. Posting boundary compatibility gates

Every implementation phase proves:

- the Posting Kernel sanctioned set remains six;
- non-kernel ledger writes remain rejected;
- Posting Engine does not calculate inventory cost;
- Inventory Engine sends deterministic amounts, roles, dimensions, and provenance;
- account selection still uses the certified COA Resolver;
- tax computation remains outside Posting;
- inventory and GL commit atomically;
- preview and actual use the same valuation inputs;
- existing unaffected Posting Engine outputs remain byte-identical.

## 6. Certification lanes

Future implementation phases require, in proportion to scope:

- focused method/workflow tests;
- Inventory writer/security census;
- P5.1/P5.2 compatibility;
- clean migration replay;
- canonical replay;
- method-specific fingerprints;
- quantity, method state, subledger, GRNI, and GL reconciliation;
- negative mutation tests;
- reversal/correction and concurrency tests;
- documentation validation;
- lint, production build, secret checks, and diff hygiene.

Hosted mutation is never part of an implementation phase without separately approved deployment and data-transition governance.

## 7. Deferred capability gates

Core Inventory Accounting implementation does not imply availability of:

- Production/MRP, assemblies, kits, BOM, routing, yield, labor, or overhead conversion costing;
- intercompany pricing, tax, elimination, or consolidation;
- foreign-currency monetary remeasurement outside the frozen inventory acquisition-cost boundary; or
- advanced WMS optimization such as FEFO picking.

Each remains unavailable until its owning architecture is separately approved. Inventory exposes explicit boundary events and rejects unsupported source types; it does not estimate or duplicate another engine's result.

## 8. Current authorized next step

IA-5 is landed and dormant, and its certification claim in
`PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` is suspended (C-01).
ECC-01 was owner accepted on 2026-07-26
([`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`](ECC-01_FORMAL_OWNER_ACCEPTANCE.md)), and the
authorised phase is **IA-5 ECC Hardening — Implementation Work Package 1**
(order-policy and version foundation) per
[`ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md`](../04.%20Implementation/ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md).
**IA-6 — Method-State Foundation is not authorised** and cannot begin until the
reopened evidence gate accepts the ECC hardening evidence package and closes
C-01. P5.3B, P6, and P7 remain paused.
