# PXL IA-4 Inventory Test, Canonical, and Risk Blueprint

**Status:** IA-4 planning baseline
**Authority:** Certification contract derived from frozen IA-3 architecture
**Last Reviewed:** 2026-07-26
**Implementation Status:** Planning only; no test, seed, fixture, or code change is authorized

## 1. Test-level definitions

- **Unit:** pure policy, UOM, precision, allocation, method-transition, or plan
  calculation without persistence.
- **Integration:** source lifecycle through Inventory event/method state and, where
  applicable, frozen Posting in one database transaction.
- **Accounting:** exact journal, line order/role, subledger, control account, destination,
  tax boundary, dimensions, and document lifecycle.
- **Regression:** unaffected existing P5.1/P5.2 and workflow output remains identical.
- **Canonical:** deterministic current-workflow scenario with source-to-event-to-journal
  fingerprints.
- **Performance:** bounded latency, replay/report throughput, and storage growth without
  semantic shortcuts.
- **Concurrency:** conflicting commands, lock order, retries, duplicate delivery, and
  scope/match/method contention.
- **Certification:** fresh migration/replay, security census, exact reconciliation,
  documentation, lint/build, secret and diff hygiene.

Every traceability requirement has at least one test family below. A future phase must
instantiate exact cases and expected values before implementation is accepted.

## 2. Test blueprint by requirement family

| Requirement IDs | Unit tests | Integration tests | Accounting tests | Regression and canonical tests | Performance/concurrency tests | Certification tests |
| --- | --- | --- | --- | --- | --- | --- |
| GOV-001–GOV-002, GOV-007 | Effective policy resolution, eligibility, missing role | Item/company/source admission with policy version | Resolved method/account roles and provenance exact | Unchanged existing item/account default scenarios | Concurrent effective-date update versus posting | Policy/account readiness census; unsupported policy negative |
| GOV-003–GOV-005, QTY-002 | Quantity/rate/amount bounds, UOM normalization, largest remainder, final residual | Source quantities become exact event and GL-basis values | Sum of allocated journal minor units equals authoritative amount | Boundary-decimal canonical matrix; unchanged ordinary whole values | Large allocations; deterministic order under parallel calls | No binary float; cross-report/export full-precision fingerprints |
| GOV-006, ACQ-002–ACQ-007 | Ownership terms and acquisition hierarchy | Custody/control/receipt/bill timing permutations | GRNI, GINR, transit, AP, tax, Inventory exact | PO→RR→VB partial/full/bill-first/simultaneous scenarios | Same receipt/bill matched concurrently | No inferred ownership; zero unexplained control balances |
| GOV-008, COR-001 | Error/estimate plan and destination allocation | Open/closed-period correction workflow | Current/retained-earnings/adjusting/comparative bridge exact | Backdated/correction canonical fingerprints | Wide replay scope and competing close | Posted journals immutable; Period classification evidence |
| EVT-001–EVT-006 | Identity, ordering, idempotency, ancestry, fingerprint | Admit→calculate→commit→retry/reverse | Inventory/GL atomic equality and exact reversal | Double replay and stale-preview cases | Two-session source/scope locks; crash/retry injection | Complete writer/grant/RLS census; zero unauthorized mutation |
| QTY-001, QTY-003–QTY-005 | Movement/reservation/custody/transit roll-forward | Reserve/release/consume; custody convert; transfer legs | GL only for owned/value/control changes | Stock/movement/available/owned scenarios | Over-reservation, partial transit, concurrent receipt | Projection rebuild equals events at all cut-offs |
| ACQ-001, ACQ-008–ACQ-011 | Match allocations, rate/classification, price delta | PO/RR/event/VB/credit/return links | Purchase Match, GRNI/GINR, AP, FX/tax separation | Partial/many-to-many, discount/rebate, foreign-source fail-closed | Concurrent match/undo/credit | Match ledger exact; no header-only proof |
| SAL-001–SAL-003 | Recognition and reservation plans | SO→delivery/control→invoice/receipt; same-day composite | Revenue/AR/tax and COGS/Inventory same occurrence/period | Invoice-before/same/after delivery; current unaffected AR receipt | Concurrent delivery/invoice and duplicate acceptance | Sales Recognition Bridge zero variance |
| RET-001–RET-005 | Corrected original cost, FIFO return order, WAC return pool, purchase return variance | Accepted/rejected sales return; billed/unbilled purchase return; linked credits | Exact Inventory/COGS/AP/AR/tax/variance roles | Partial/multiple/reversed/late-corrected returns | Double return and identity contention | Physical/financial links complete, no hidden movement |
| FIFO-001–FIFO-006 | Queue order, partial/final residual, transfer order, replay | Receipt/issue/return/transfer/deficit/correction | Layer quantity/value, destination COGS, GL exact | Full FIFO scenario book | Hot-layer contention and backdated replay scale | Rebuild/fingerprint; physical identity selection cannot change value |
| WAC-001–WAC-007 | Pool transition math, zero close, return, correction, age allocation | Receipt/issue/return/transfer/deficit and receipt-audit creation | Pool GL-basis value/subledger/GL exact; receipt rows N/A | Full WAC Model A scenario book | Hot-pool serialization, long replay, ageing allocation scale | No WAC receipt consumption; pool history deterministic |
| SID-001–SID-004 | Identity state machine and direct value | Serial/lot receipt/reserve/transfer/issue/return/dispose | Identity gross/allowance/net and GL exact | Serial and lot canonical books | Duplicate serial and location contention | One active state; no negative identity |
| ADJ-001–ADJ-004 | Positive measured-cost rules and source-class admission | Count snapshot→approval; issue; source-specific receipt | Adjustment/destination roles exact | Positive/negative/count/quarantine scenarios | Concurrent count/issue and stale snapshot | Unknown receipt/WIP sources fail closed |
| NRV-001–NRV-002 | Lower-of-cost, grouping, ceiling, reversal cap | Assessment/approve/post/reverse | Gross cost unchanged; allowance equals contra GL | Item/group/write-down/reversal canonical | High-volume assessment | No general upward revaluation |
| COR-002 | Allocation bases and stable residual | Capture/approve/apply/reverse landed cost | On-hand and consumed destinations plus clearing exact | Landed-cost canonical by all methods | Many-receipt allocation and replay | Source amount equals allocations exactly |
| OPEN-001–OPEN-002 | Batch totals and suspense calculation | Master→opening lines→method state→Posting→certify | Opening Inventory/allowance/GL and full Trial Balance exact | Clean opening replay before downstream events | Large batch, duplicate post, competing edits | Suspense zero; no plug/equity inference |
| TRN-001–TRN-004 | Conservation and scope transition | Dispatch/transit/receive/return; consignment convert | Conditional reclass, no internal profit | Same/cross scope, branch, consignment; intercompany negatives | Opposing transfers and deadlock lane | Deferred source types unavailable |
| MAN-001 | Protected-account role classification | Manual Journal validation versus governed opening/correction | No GL-only subledger mutation | Negative MJ per account class | Concurrent role/profile activation | Kernel guard still fully enforced |
| REC-001–REC-006 | Roll-forward and first-failure classification | Independent event/method/projection/control/GL reads | Exact zero at required grain | Inject every exception class and detect it | Large cut-off and projection rebuild | Period close rejects every nonzero/unsettled case |
| REP-001–REP-006 | Report parameter/fingerprint functions | Cut-off, drill-through, export/watermark | Full-precision controls match independent sources | Deterministic export and stale-report cases | Scale, pagination, snapshot refresh | Required catalog and metadata completeness |
| CAN-001–CAN-004 | Coverage/fingerprint validators | Governed canonical workflow calls only | Expected journals/subledgers | Clean double replay and intentional-delta register | Canonical volume lane | P5.2 zero violations; coverage matrix truthfulness |
| SEC-001–SEC-002 | Permission and tenant validation | Authenticated/anon/helper/direct attempts | No unauthorized Inventory or ledger change | Existing P5.2 security lane | Privilege/race negatives | SECURITY DEFINER, grant, RLS, trigger, writable-surface census |
| PERF-001 | Replay/window/index model estimators | Projection/replay/report benchmarks | Totals unchanged under optimized path | Baseline comparison | Required scale/concurrency suite | Performance optimization never changes authority |
| DEF-001–DEF-003 | Capability gates | Production/intercompany/currency/WMS unsupported calls | No journal/event side effects | Negative canonical exclusions | N/A until authorities exist | Exclusions labeled, not claimed covered |

## 3. Required focused lanes by phase

| Phase | Required focused lanes before exit |
| --- | --- |
| IA-5 | event identity/order/idempotency; UOM/precision/residuals; source links; writer/grant/RLS census; atomic occurrence evidence; existing writer compatibility |
| IA-6 | per-method receipt/issue pure calculations; event replay; projection rebuild; FIFO/Specific/WAC state invariants; identity and WAC-ageing separation; preview fingerprint |
| IA-7 | ownership timing matrix; partial/full/many-to-many purchase match; GRNI/GINR/transit; bill-first/simultaneous; AP/Tax/FX boundaries |
| IA-8 | complete FIFO and Specific ID receipt/issue/return/transfer/correction/reversal; identity negatives; exact layer and destination reconciliation |
| IA-9 | complete WAC pool/history/receipt evidence/return/transfer/deficit/ageing; zero residual; hot-pool concurrency |
| IA-10 | landed cost, discounts/rebates, backdate/replay, error/estimate, destination bridge, NRV, write-off, deficits, opening conversion |
| IA-11 | dispatch/receive/in-transit conservation, same/cross scope and branch, inbound/outbound consignment, deferred capability negatives |
| IA-12 | every required report; independent source proofs; exception injection; close gate; watermark/fingerprint/performance |
| IA-13 | complete canonical scenario matrix; clean double replay; changed fingerprint register; P5.3B requirements |
| IA-14 | all focused lanes plus fresh schema, canonical, regression, security, concurrency, performance, docs, lint, production build, secrets, diff hygiene |

## 4. Canonical dataset impact by implementation phase

No canonical fixture changes occur before IA-13. Earlier phases use focused synthetic
test data owned by their test lanes and record expected future canonical impact.

| Phase | New canonical scenarios required at IA-13 | Existing scenarios affected | Replay/certification impact | Expected fingerprint impact | P5.3B dependency |
| --- | --- | --- | --- | --- | --- |
| IA-5 | duplicate/retry, line source trace, precision/UOM boundaries, unauthorized Inventory mutations | Every inventory source gains event/policy/source provenance | Event ordering and security fingerprints added; accounting unchanged where intended | Headers/lines unchanged for unaffected scenarios; new event fingerprints | Foundation prerequisite |
| IA-6 | one receipt/issue/reversal per method; identity and WAC ageing evidence | All stock/layer assertions | Method-state fingerprints replace generic layer assumption | Inventory state fingerprints intentionally change; GL should not yet change until workflow cut-over | Required to rebuild seed truthfully |
| IA-7 | PO→RR→receipt→VB→payment; partial/full; bill-first; control-at-shipment; simultaneous; price delta | Existing RR/VB and cash-purchase fixtures | GRNI/GINR/in-transit/purchase-match schedules become certified | Journals/totals change where old fixture omitted ownership accounting; each tied to scenario | Resolves RR/VB/account-source blockers |
| IA-8 | FIFO and Specific ID purchases, sales, returns, purchase returns, transfers, correction, negative FIFO, identity negatives | Existing FIFO/specific stock, sales, return fixtures | Layer/identity and destination reconciliation replace generic checks | Method outputs intentionally change where legacy order/return behavior differed | Required before canonical FIFO/ID |
| IA-9 | WAC Model A receipt/issue/zero/return/purchase return/transfer/deficit/ageing | All current WAC cost-layer fixtures | WAC receipt rows cease being available layers; pool becomes authoritative | State fingerprint changes by architecture; unchanged commercial source values separately compared | Resolves original P6 WAC blocker |
| IA-10 | landed cost, rebate/discount, backdate, correction, NRV, write-off, positive count, deficit settlement, opening conversion | Opening MJ, adjustments, damaged-credit story | Correction/allowance/opening bridges and close rules certified | Added journals and corrected fixture totals are intentional dataset evolution | Completes opening and coherent Vendor Credit scenarios |
| IA-11 | same/cross-scope transfer, transit, branch, inbound/outbound consignment; intercompany negative | Stock Transfer and warehouse scenarios | Conservation and conditional journal behavior certified | Transfer fingerprints change where legacy FIFO date reset or no transit existed | Required for complete canonical inventory scope |
| IA-12 | report-only expected snapshots and injected reconciliation differences | All canonical scenarios | Each report gets independent control fingerprint | Report fingerprints added; no source/accounting change | Provides P5.3B/P6 evidence |
| IA-13 | Debit Memo, Recurring, Fiscal Close plus complete IA-3 Inventory matrix | Entire old canonical inventory seed replaced or explicitly retained by scenario | Clean current migrations; governed workflow calls; P5.2 zero violations | Full intentional-change register distinguishes engine parity from dataset evolution | This is the authorized resume of P5.3B |
| IA-14 | negative security/concurrency/performance certification populations | None after IA-13 freeze | Complete certification and deterministic replay | No unexplained change permitted | Certifies refreshed baseline |

## 5. Canonical scenario minimums

The future authoritative dataset must include, for FIFO, WAC, and Specific
Identification where applicable:

- purchase commitment; custody receipt; owned Goods Receipt; partial/full receipt and
  bill; bill before control; control at shipment; simultaneous receipt/bill; payment;
- trade discount, settlement discount classification, rebate, landed cost, bill price
  correction, Vendor Credit, billed and unbilled Purchase Return;
- Sales Order reservation, partial/full Delivery control transfer, invoice before/same/
  after recognition, receipt, accepted/rejected Sales Return, price-only Credit Memo;
- Goods Issue, approved non-purchase receipt classes, positive/negative adjustment,
  Physical Count, write-off/disposal, same/cross-scope transfer, in transit,
  consignment custody and ownership conversion;
- FIFO tie order/partial/final layer, WAC pool zero/restart and receipt-audit exclusion,
  Specific ID serial/lot state transitions;
- open-period backdate/re-cost, closed-period error and estimate plans, NRV write-down/
  capped reversal, provisional deficit/settlement/close rejection;
- opening Inventory/method state/allowance/full Trial Balance with zero suspense;
- protected-account Manual Journal rejection and governed opening/correction success;
- reversal, retry/idempotency, concurrency, unsupported Production/intercompany/
  uncertified-currency/WMS negatives; and
- every required report and reconciliation roll-forward.

No scenario is marked covered unless executable through current governed services.

## 6. Risk register

| Risk ID | Category | Risk and evidence | Severity | Mitigation and proof |
| --- | --- | --- | --- | --- |
| R-01 | Migration | Splitting generic movements/layers can misclassify legacy WAC rows as available state | High | Four conversion classes; no inferred remaining state; row-level conversion census; user-evidenced opening option; legacy view |
| R-02 | Migration | Current amount/quantity scales can lose authoritative precision | High | Add exact target facts before cut-over; boundary conversion report; reject non-exact automatic conversion; GL minor-unit proof |
| R-03 | Security | `fn_receive_inventory(jsonb)` remains executable by `authenticated` and mutates protected projections as definer | High | IA-5 revokes external execution, inventories all callers/grants, adds negative tests before activating target services |
| R-04 | Accounting | Goods Receipt cut-over can double Inventory or leave GRNI/GINR unmatched | High | One active writer/source occurrence; immutable match ledger; cohort cut-over; exact control schedules; rollback before activation |
| R-05 | Accounting | Moving COGS from invoice to delivery can split or duplicate Sales accounting | High | One recognition occurrence; compatibility bridge; invoice timing matrix; atomic Sales+Inventory plan; byte comparison for unaffected sources |
| R-06 | Accounting | Cost corrections may omit consumed destinations or violate closed periods | High | Complete destination bridge; Period error/estimate approval; append-only delta; destination-level reconciliation |
| R-07 | Concurrency | FIFO queue, WAC pool, purchase matches, reservations, and transfers can deadlock or overconsume | High | Stable lock order; unique idempotency; two-session lanes; serialization retry; no `SKIP LOCKED` result that changes accounting order |
| R-08 | Performance | Backdated replay can lock large scopes or grow history excessively | High | Scope-bounded replay versions, checkpoints/projections with visible watermark, benchmark limits, async calculation only if commit remains atomic and fail-closed |
| R-09 | Replay | Identical effective timestamps can produce nondeterministic cost order | High | Stable recorded timestamp and immutable tie-break identity; ordering fingerprint; permutation tests |
| R-10 | Data conversion | Historical ownership, RR/VB links, identity, or queue allocations may be absent | High | Never infer; classify legacy/opening/blocked; require user-reviewed evidence; no forced journal |
| R-11 | Accounting | Rounding residuals can make method state differ from GL | High | Authoritative extended/GL-basis values, largest remainder, final consumption residual, exact allocation constraints and tests |
| R-12 | Security | New internal method/projection services could recreate public definer mutation surfaces | High | Default revoke, explicit governed caller grants, fixed search path, tenant validation, writer census, anon/auth/helper/direct negatives |
| R-13 | Accounting | Tax or AP FX could leak into inventory cost | High | Typed capitalizable components, Tax/Currency-owned evidence, later FX excluded, boundary tests |
| R-14 | Inventory | FIFO valuation selection may be confused with lot/serial FEFO picking | High | Separate allocation ledgers; joined trace only; tests where physical and valuation selections differ |
| R-15 | Inventory | Specific ID duplication or missing identity can create phantom value | High | Stable identity uniqueness/state machine, direct assignment, no negative ID, concurrent duplicate tests |
| R-16 | Inventory | WAC ageing allocation may be mistaken for cost flow | Medium | Separate physical-age ledger and report label; no Posting/method-state FK path from age allocation |
| R-17 | Reporting | A report can reconcile a projection to itself and conceal source drift | High | Independent source contract per equality, lineage/watermark disclosure, injected exception tests |
| R-18 | Reporting | Snapshot staleness can be shown as current | Medium | Watermark/freshness contract, rebuild evidence, stale rejection/disclosure, report-run fingerprint |
| R-19 | Transition | Indefinite dual-write or dual-read causes divergent authorities | High | One active writer per source; bounded cohort cut-over; named legacy views; no silent fallback |
| R-20 | Accounting | Opening Conversion Suspense may become a balancing plug | High | Full Trial Balance evidence, equity separate, exact zero gate, no go-live on variance |
| R-21 | Accounting | Purchase/sales returns can mismatch financial and physical events | High | Typed explicit link, independent completeness, corrected cost ancestry, return bridge reconciliation |
| R-22 | Accounting | Negative inventory may survive close | High | Explicit deficit register/settlement; close blocker; Specific ID prohibition; canonical negative test |
| R-23 | Scalability | Method-state history and trace can grow quickly | Medium | Append-only partition/index design in future migration plan, bounded projection rebuild, volume benchmarks; never history deletion |
| R-24 | Availability | Hot WAC pools serialize high-volume issues | Medium | Minimal locked current version, append-only history, deterministic retry; benchmark by expected peak scope |
| R-25 | Deferred boundary | Generic source interfaces could accidentally enable Production, intercompany, Currency, or WMS policy | High | Enumerated source classes and explicit capability gates; negative certification; no generic fallback |
| R-26 | Regression | Existing certified Posting ordering, audit, dimensions, tax, preview, or guard can drift | High | P5.1/P5.2 compatibility each phase; six-kernel census; byte-identical unaffected scenario fingerprints |
| R-27 | Rollback | Restoring tables after certified postings would erase audit or desynchronize GL | High | Additive/dormant rollout; pre-activation cohort rollback only; after posting use governed reversal/correction |
| R-28 | Master data | Changing costing method/scope without policy conversion can mix state | High | Effective policy version, eligibility gate, no ad hoc transaction override, IAS 8 conversion workflow |

## 7. Certification dependencies and gates

Every implementation phase must preserve:

- six sanctioned Kernel functions and fully enforced journal guard;
- zero unauthorized journal and Inventory derived-state mutations;
- certified COA, Tax, dimension, period, numbering, audit, lifecycle, reversal, and
  Posting preview behavior;
- atomic Inventory/GL rollback;
- byte-identical Posting output for explicitly unaffected scenarios; and
- an approved register for every intentional behavior/fingerprint change.

IA-14 cannot pass until:

1. fresh migrations and deterministic double canonical replay pass;
2. FIFO, WAC, and Specific ID method-state equality passes exactly;
3. Purchase Match, GRNI, GINR, Inventory in Transit, Inventory/allowance, Sales
   recognition, destination corrections, and GL all reconcile at required grain;
4. every negative mutation, unsupported capability, duplicate, concurrency, reversal,
   precision, and close-gate case passes;
5. all required reports and drill-through fingerprints are complete; and
6. focused, canonical, regression, documentation, lint, production build, secret,
   trailing-whitespace, and `git diff --check` lanes are green.
