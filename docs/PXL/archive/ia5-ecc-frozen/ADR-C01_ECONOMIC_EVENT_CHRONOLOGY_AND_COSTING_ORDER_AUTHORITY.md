# ADR-C01: Economic Event Chronology and Costing Order Authority

**Status:** Frozen
**Authority:** Architecture Authority under PG-01
**Owner / Domain:** Inventory Accounting
**Decision Date:** 2026-07-26
**Applies To:** Inventory event admission, costing, replay, correction, and cut-off
**Implementation Status:** Decision only; no implementation is authorized by this ADR
**Supersession Rule:** Only an approved successor ADR may change this decision

## 1. Executive Summary

PXL adopts a **dual-chronology model with canonical economic
linearisation**:

1. **Accepted Event Chronology** records the immutable order in which PXL
   accepted Inventory evidence. It is authoritative for admission audit,
   idempotency, retry evidence, and operational investigation.
2. **Economic Costing Chronology** is a deterministic, source-derived total
   order per valuation scope. It is authoritative for FIFO, Moving WAC,
   Specific Identification where sequence is relevant, valuation replay,
   corrections, and Inventory cut-off.

The two chronologies are both permanent evidence, but they do not have the
same accounting purpose. PostgreSQL transaction or lock acquisition order is
an implementation detail used to serialize acceptance. It is not economic
evidence and is never a costing tie-breaker.

PXL economic order is derived from the event's governed economic effective
instant, explicit causal relationships, event-effect precedence, registered
source-document order, source-line order, lifecycle transition, partial
occurrence order, and event order within an occurrence. Every component must
exist before the event can become eligible for method-state processing. Missing
or contradictory authority fails closed.

For economically simultaneous independent events, PXL adopts an explicit
convention: opening events precede ordinary events; inventory increases precede
value-only or classification effects; those effects precede inventory
decreases. Remaining ties use immutable source authority established before
Inventory admission. The convention is an accounting policy for
indistinguishable simultaneous facts, not a claim about real-world causation.

An event may be durably admitted before it is economically applied. Admission
does not mean that quantity is available, costing is complete, Posting is
authorized, or a document lifecycle is complete. Future method-state work must
apply accepted events in Economic Costing Chronology and must retain both
chronologies.

This ADR resolves the C-01 architecture ambiguity. It does not make the current
IA-5 database implementation conformant. IA-5 remains dormant and its permanent
foundation certification remains suspended until the IA-5/IA-6 evidence gate
is reopened and proves the required implementation alignment.

## 2. Problem Statement

The IA-5 event foundation allocates a unique per-scope accepted sequence by
updating a shared scope row. Executable evidence in
[IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md](IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md)
proved that the transaction reaching that row lock first receives the earlier
sequence. The same receipt and issue, carrying the same authoritative economic
evidence, received opposite orders when submitted in opposite or randomized
concurrent schedules.

That sequence is sound evidence of database admission. It is not, without an
accounting policy, evidence that one inventory event economically preceded the
other. The distinction matters:

- FIFO eligibility and layer consumption can change.
- Moving WAC pool transitions and issue cost can change.
- An issue can move from ordinary consumption to a negative-inventory or
  rejection path.
- Backdated replay and period cut-off can change.
- Independent reconstruction of the same economic facts can produce different
  valuation histories.

The frozen
[PXL Inventory Costing Specification](PXL_INVENTORY_COSTING_SPEC.md)
already states that same-time events cannot depend on database insertion order,
but it does not define a complete substitute order. C-01 therefore requires a
permanent policy, not merely a database sequencing mechanism.

PostgreSQL guarantees that conflicting row updates wait and that serializable
execution corresponds to transactions running in *some* serial order. It does
not assign business or accounting meaning to that order.
[PostgreSQL explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html)
and
[transaction isolation](https://www.postgresql.org/docs/17/transaction-iso.html)
support the concurrency mechanism, but do not select the economically correct
costing sequence.

IAS 2 permits FIFO and weighted-average cost formulas and describes the
economic assumptions of those methods. It does not prescribe an ERP tie-break
for identical timestamps.
[IFRS IAS 2](https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/)
therefore requires PXL to govern its own deterministic rule.

## 3. Chronology Definitions

### 3.1 Accepted Event Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Preserve when PXL durably accepted an immutable event fact and resolve concurrent admission, idempotency, and retries. |
| Owner | Inventory Engine event authority. |
| Authority | Committed occurrence identity, accepted scope sequence, accepted timestamp, and immutable event identity. |
| Inputs | Validated source occurrence, idempotency identity, transaction commit, and database serialization. |
| Outputs | One immutable accepted position and admission audit evidence. |
| Determinism | Stable once committed. Different independent admissions may receive different positions under different schedules. That is permitted for audit chronology only. |
| Posting | Does not authorize or order Posting. |
| Inventory | Establishes that evidence exists; it does not establish economic priority, availability, ownership transfer by itself, or costing completion. |
| Replay | Reconstructs admission history and knowledge-as-of boundaries; it is not the method-state replay order. |
| Audit | Authoritative for who submitted what, when PXL accepted it, retries, and operational concurrency. |
| Certification | Must be immutable, unique, idempotent, and retained alongside economic order. |

### 3.2 Business Event Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Express governed business causality and lifecycle order before costing. |
| Owner | The source-domain owner establishes source facts; Inventory validates the subset needed by Inventory. |
| Authority | Explicit predecessor, reversal, correction, transfer, return, source-document, source-line, transition, and occurrence identities. |
| Inputs | Approved source workflow evidence and immutable source registry rules. |
| Outputs | A validated partial order and causal graph. |
| Determinism | Identical source facts must produce the same graph. Cycles, cross-company ancestry, missing predecessors, or contradictory lifecycle order fail closed. |
| Posting | Source lifecycle may make a Posting request eligible only after Inventory has calculated its result. |
| Inventory | Governs dependencies such as receipt before return, transfer issue before transfer receipt, and original event before correction. |
| Replay | Causal edges constrain every replay version. |
| Audit | Retains the exact business evidence that created every edge. |
| Certification | Requires hostile tests for cycles, missing ancestry, cross-company links, and competing transitions. |

### 3.3 Effective Date Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Place an event at the instant its economic inventory effect belongs. |
| Owner | The approved source workflow supplies the fact; Inventory policy validates it. |
| Authority | Governed economic effective timestamp, normalized to one unambiguous instant, plus its source and policy version. |
| Inputs | Control-transfer, physical movement, acceptance, count, return, correction, or other approved business evidence. |
| Outputs | The primary economic position within a valuation scope. |
| Determinism | The same evidence must yield the same instant. Created, received, recorded, and database timestamps cannot substitute for missing economic time. |
| Posting | Accounting date remains separate and controls the GL period. |
| Inventory | Drives costing eligibility and open-period backdated replay. |
| Replay | A newly admitted earlier-effective event is inserted at this position in a new replay version. |
| Audit | Retains both effective time and the later accepted time. |
| Certification | Must prove time-zone normalization, precision, closed-period handling, and independent replay equality. |

### 3.4 Economic Costing Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Supply the one total order in which a valuation scope applies method-state effects. |
| Owner | Inventory Engine. |
| Authority | The canonical economic-order hierarchy in sections 5 and 6. |
| Inputs | Valid accepted events, economic time, causal graph, registered source-order authority, source line, transition, occurrence, and event ordinals. |
| Outputs | A stable economic-order key and ordered event stream per valuation scope. |
| Determinism | The same complete accepted fact set and policy versions must produce the same order under all arrival and lock schedules. |
| Posting | Produces Inventory amounts and semantic results later consumed by Posting; Posting never changes this order. |
| Inventory | Authoritative for FIFO, WAC, applicable Specific-ID sequencing, valuation, COGS inputs, and correction calculation. |
| Replay | Is the method-state replay order. |
| Audit | Must be drillable to every ordering component and the policy version that interpreted it. |
| Certification | Requires independent-reset permutations, randomized concurrency, same-time, backdate, correction, and method-consequence tests. |

### 3.5 Replay Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Rebuild one valuation scope and all dependent method state reproducibly. |
| Owner | Inventory Engine replay authority. |
| Authority | Economic Costing Chronology plus a frozen accepted-through watermark, replay version, and policy versions. |
| Inputs | Immutable event set admitted through the watermark, source/policy versions, correction graph, and prior certified boundary when applicable. |
| Outputs | Versioned FIFO layers/allocations, WAC pool history, Specific-ID state, issue-cost results, projection state, and fingerprint. |
| Determinism | Same inputs and versions must yield byte-identical ordered inputs, calculations, allocations, ending state, and fingerprint. |
| Posting | Replay calculates correction deltas; it never edits journals. Posting receives only governed new correction/reversal payloads. |
| Inventory | Prior replay versions remain audit evidence; exactly one certified current version may serve a stated cut-off. |
| Audit | Records triggering event, accepted watermark, first affected economic key, predecessor version, algorithm/policy versions, and result fingerprint. |
| Certification | Requires clean rebuild, incremental-vs-full equality, rollback/retry, and cross-environment fingerprint equality. |

### 3.6 Correction Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Correct an immutable economic fact without rewriting accepted history. |
| Owner | Inventory Engine for quantity/cost effects; Accounting Policy/Period owner for closed-period treatment. |
| Authority | Target event, correction type, predecessor correction, correction business time, approval, and open/closed-period rule. |
| Inputs | Explicit correction, reversal, supersession, or backdated source evidence. |
| Outputs | New immutable correction event, new replay version, affected range, exact method-state delta, and any later Posting request. |
| Determinism | Competing corrections require an explicit chain or fail closed. No arrival-order conflict resolution is permitted. |
| Posting | Receives linked delta/reversal output; posted journals remain immutable. |
| Inventory | Applies the corrected fact at its governed economic anchor in the new replay version while retaining the original and every prior version. |
| Replay | Begins at the earliest affected economic key and traverses dependent events forward. |
| Audit | Shows original fact, correction fact, accepted times, economic anchor, old/new results, approval, and journal linkage. |
| Certification | Must prove correction-chain order, open/closed-period behavior, and exact delta reconciliation. |

### 3.7 Cut-off Chronology

| Attribute | Contract |
| --- | --- |
| Purpose | Make every Inventory valuation and financial report reproducible as both an economic and knowledge-as-of statement. |
| Owner | Inventory Engine owns valuation cut-off; Period/Reporting owns financial reporting cut-off. |
| Authority | Economic as-of instant, accepted-through watermark, certified replay version, applicable policy versions, accounting period, and Posting watermark. |
| Inputs | Economic order, accepted chronology, period state, replay certification, and journal state. |
| Outputs | Reproducible valuation, reconciliation, and reporting population. |
| Determinism | The same complete cut-off tuple produces the same population and values. |
| Posting | Accounting date and Posting watermark control GL inclusion; economic time alone cannot place a journal in a closed period. |
| Inventory | Economic as-of controls which cost effects belong; accepted-through controls which facts were known and admitted. |
| Replay | Late facts create a new replay/report version; they do not mutate an already certified cut-off. |
| Audit | Retains the full cut-off tuple and late-event exceptions. |
| Certification | Inventory, subledger, journal, GL, and financial-statement proofs must use declared compatible cut-offs. |

### 3.8 Posting Chronology

Posting Chronology is the order in which certified Posting occurrences create
immutable journals. It is owned by the Posting Engine and Period policy, not by
Inventory. It remains separately auditable and may differ from both Accepted
Event Chronology and Economic Costing Chronology. A reconciliation must expose,
not hide, economically applied Inventory events awaiting Posting or Posting
corrections.

## 4. Candidate Models Considered

### Model A — Database admission order is economic order

Under this model, the per-scope lock winner and accepted sequence determine
FIFO/WAC order.

**Advantages:** simple online linearization, stable replay of one accepted
stream, and direct correspondence between commit and costing sequence.

**Rejected because:** independent executions of the same economic evidence can
produce different method-state consequences solely because of scheduling.
Source-line and partial-occurrence order can also be inverted. The rule would
make an operational concurrency outcome an accounting fact and would supersede
PXL's existing prohibition on insertion-order ties without a stronger business
reason.

An enterprise system may explicitly choose entry sequence as a same-date
policy. That principle proves the choice can be governed; it does not make
PXL's current lock acquisition an already governed choice.

### Model B — Effective timestamp plus database sequence

Under this model, effective time controls ordinary order and accepted sequence
breaks ties.

**Advantages:** handles differently timed events and preserves one total order.

**Rejected because:** C-01 exists precisely at equal effective time. The final
material tie still depends on lock schedule and can change receipt/issue
eligibility and cost.

### Model C — Business causality only

Under this model, explicit predecessor and lifecycle edges form a partial order,
and independent simultaneous events remain unordered.

**Advantages:** avoids inventing economic causality and represents source
relationships truthfully.

**Rejected because:** FIFO and Moving WAC need a total order. Independent
receipts and issues can be causally unrelated while still competing for one
queue or pool. Allowing each replay to choose any topological order would not be
deterministic.

### Model D — Manual accounting priority

Under this model, a user or administrator chooses order when events conflict.

**Rejected because:** it is non-scalable, invites outcome selection, weakens
replay, and creates an unaudited heuristic unless every choice becomes governed
source evidence. If genuine business evidence was omitted or incorrect, the
proper remedy is a source correction, not an editable costing order.

### Model E — Dual chronology with canonical economic linearisation

Under this model, admission chronology remains permanent audit evidence while
method state uses a deterministic source-derived order and explicit same-time
accounting convention.

**Selected because:** it preserves immutable event-sourcing evidence, prevents
lock schedules from choosing costs, supports open-period backdating and
versioned replay, and leaves Posting boundaries unchanged.

Microsoft's event-sourcing guidance emphasizes immutable events, order,
idempotency, versioning, and replay. Those principles support retaining both
the accepted stream and deterministic projections, but they do not by
themselves determine inventory cost order.
[Microsoft Event Sourcing pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)

Microsoft Business Central publicly describes explicit cost applications and
FIFO selection by earliest posting date. The relevant principle is that a cost
source and its order are explicit and traceable; its product-specific
implementation is not a PXL template.
[Microsoft item application](https://learn.microsoft.com/en-ca/dynamics365/business-central/design-details-item-application)

Oracle publicly distinguishes transaction, cost, and accounting-period
handling for late inventory transactions. The relevant principle is that late
and backdated treatment must be explicit; Oracle's processing model does not
dictate PXL's replay design.
[Oracle cost period and transaction accounting](https://docs.oracle.com/en/cloud/saas/supply-chain-and-manufacturing/26b/fapma/cost-accounting-period-statuses-and-transaction-accounting.html)

## 5. Selected Chronology Model

PXL selects **Model E — Dual Chronology with Canonical Economic
Linearisation**.

The permanent rules are:

1. Every immutable Inventory event has an Accepted Event Chronology position.
2. Every event eligible for valuation has exactly one Economic Costing
   Chronology position per affected valuation scope and replay version.
3. Accepted position and economic position are never inferred to be equivalent.
4. Database transaction order, lock order, commit order, created timestamp,
   and admission-generated random identity cannot decide economic priority.
5. Source owners provide explicit economic and source-order evidence under the
   Event Source Registry. Inventory validates and consumes that evidence; it
   does not infer it from dates, quantities, amounts, names, or document-number
   similarity.
6. A source type is unavailable to economic processing until its registry rule
   defines its event effects, economic-time authority, source-order authority,
   line order, lifecycle transitions, occurrence semantics, and same-time
   class.
7. An admitted event that is not yet economically applied is **pending
   costing** in architectural meaning. It cannot change active stock,
   valuation, availability, COGS, Posting, or document completion.
8. Economic application is atomic for all Inventory effects of its governed
   occurrence or composite transaction boundary.
9. A late same-time or backdated event creates a new replay version from the
   earliest affected position. It never changes Accepted Event Chronology.
10. Both chronologies, their source components, policy versions, and result
    fingerprints are permanent audit evidence.

## 6. Authoritative Ordering Hierarchy

### 6.1 Scope isolation

Economic order is evaluated within exactly one company and valuation scope.
No order, predecessor, correction, transfer dependency, layer, pool, or
Specific-ID ancestry may cross company.

A same-company transfer across valuation scopes creates a causal dependency
between the source-scope issue result and destination-scope receipt input. It
does not merge the two scope streams. Intercompany inventory is a sale and
purchase under future certified intercompany architecture, never a shared
Inventory ordering stream.

### 6.2 Causal validation

Before total ordering, Inventory validates the Business Event Chronology:

- predecessor before dependent;
- source receipt/ownership before return or reversal of that source;
- original issue before a linked sales return;
- transfer issue calculation before destination receipt valuation;
- original event before correction or supersession;
- source line before a derived allocation;
- no cycle;
- no cross-company relationship; and
- no contradictory transition or source version.

Except for the explicit correction-anchor rule in section 6.5, causal evidence
must be consistent with economic effective time. Contradiction fails closed.

### 6.3 Canonical economic-order tuple

After causal validation, the authoritative ascending order within a valuation
scope is:

1. **Economic effective instant.**
2. **Causal/topological precedence** among events at that instant.
3. **Same-time event-effect rank** in section 6.4.
4. **Registered source-type rank.**
5. **Registered source-document order key.**
6. **Source-line ordinal.**
7. **Registered lifecycle-transition rank.**
8. **Source occurrence ordinal** for partial or split fulfillment.
9. **Event ordinal within the occurrence.**
10. **Immutable pre-admission source identity** as the final collision-proof
    tie-break.

All components are company-scoped, immutable, versioned where policy governs
them, and established independently of Inventory database arrival.

The Event Source Registry must define one exact source-document key algorithm
for each source type. Where a source owns a governed business sequence, that
sequence is used. Otherwise the registry may define canonical ordering of the
immutable source identifier. A display document number, mutable user sort
order, database row location, event insertion ID, or wall-clock receipt time is
never silently substituted.

The final immutable identity tie-break has no claimed economic meaning. It is
an explicit deterministic convention only after all genuine economic and
business evidence is equal. Its canonical byte/string representation must be
versioned and identical across environments.

### 6.4 Same-time event-effect ranks

For independent events with the same economic effective instant and no causal
edge, PXL freezes this order:

| Rank | Effect class | Examples |
| ---: | --- | --- |
| 10 | Opening state | Governed opening Inventory and method-state facts |
| 20 | Owned quantity/value increase | Purchase/control receipt, accepted sales return, positive adjustment with approved measured cost |
| 30 | Cost or classification effect that does not decrease owned quantity | Source-linked acquisition correction at its anchor, landed-cost effect, same-scope ownership/location/status reclassification |
| 40 | Owned quantity/value decrease | Sale or other issue, purchase return, write-off, disposal, negative adjustment |
| 50 | Valuation allowance overlay | NRV write-down or reversal; gross historical-cost order remains separate |

The event effect, not its document label, determines the rank. Composite
occurrences retain their explicit causal order. A transfer issue/destination
receipt follows the transfer dependency even if the local effect ranks differ.

PXL selects increase-before-decrease for an exact-time tie because all owned
quantity facts effective at that instant must enter the valuation state before
independent consumption at that same instant. This avoids making a transaction
scheduler decide whether equal-time stock exists. It is a disclosed convention,
not permission to use a later-effective receipt, alter genuine causality, or
override a source document's explicit sequence.

The inbound-before-outbound convention applies only when authoritative
economic times are exactly equal. It cannot move a later receipt ahead of an
earlier issue, conceal negative inventory, or repair an erroneous timestamp.

### 6.5 Correction and reversal placement

A correction retains its later Accepted Event Chronology position. For economic
replay it declares:

- the target event;
- correction semantics;
- the affected source fact;
- the correction's own business effective and approval times;
- any predecessor correction; and
- whether it is an open-period correction, closed-period error, or estimate
  change.

An open-period correction to an acquisition fact is evaluated immediately
after the corrected target fact in a new replay version, then all dependent
events are recalculated. Multiple corrections must form an explicit,
non-branching predecessor chain unless the registered semantics prove that
their exact deltas commute. An unresolved correction fork fails closed.

A reversal is a new linked inverse event at its own governed economic time. An
exact restoration of prior state is allowed only when frozen method policy
allows it and there is no intervening dependent cost event. Otherwise the
reversal is processed normally and replay determines downstream deltas.

### 6.6 Missing and duplicate keys

- Missing required economic evidence: reject economic application.
- Two different facts claiming one logical order identity: reject both the
  conflicting application and certification of that stream.
- Idempotent retry with identical authoritative payload: return the original
  accepted occurrence and economic identity.
- Same idempotency key with a materially different payload: reject.
- New legitimate partial occurrence: require a new explicit occurrence
  ordinal and identity.
- Source correction: create new correction evidence; never alter an accepted
  key.

## 7. Concurrency Policy

Database admission order is **authoritative only for Accepted Event
Chronology**. For Economic Costing Chronology it is an **implementation
detail** and has no tie-breaking authority.

The concurrency contract is:

1. Concurrent duplicates collapse to one accepted occurrence.
2. Concurrent distinct events may commit in any accepted order.
3. Their final economic order is calculated solely from section 6.
4. A transaction may serialize access to protect method state, but the lock
   winner cannot alter the economic key.
5. If an earlier economic event arrives after a later one has been applied, the
   scope enters a governed replay requirement. Current state cannot silently
   claim certification until replay completes.
6. An event admitted before it can be safely economically applied remains
   pending costing; it cannot be treated as available or posted.
7. If a source workflow requires immediate availability or Posting, the
   transaction must supply a complete governed occurrence/composite boundary
   whose economic order and eligibility can be validated atomically.
8. A concurrent issue cannot assume an uncommitted receipt. If admitted before
   that receipt is visible, it remains pending or returns a non-final retriable
   result without consuming a new logical identity. It cannot be permanently
   rejected solely because it lost a database schedule race. At a governed
   processing watermark, the canonical order determines eligibility and the
   approved negative-inventory policy determines any genuine deficit.
9. Once the complete set is admitted and eligible for replay, independent
   arrival schedules must produce the same Economic Costing Chronology and
   method result.
10. Rollback consumes no durable economic identity. A retry uses the same
    source, occurrence, idempotency, and economic-order evidence.

This contract separates final deterministic costing from command response
timing. It does not promise that two independently timed online requests receive
the same immediate status before all relevant facts are committed. It does
require that no provisional scheduling outcome becomes certified costing
authority.

## 8. FIFO Consequences

1. FIFO layer eligibility uses the receipt's Economic Costing Chronology, never
   Accepted Event Chronology or row creation order.
2. Available layers are consumed by ascending owned-acquisition economic key.
3. Equal-time independent receipts use the complete hierarchy in section 6.
4. Equal-time inbound events precede equal-time independent outbound events.
5. A later-effective receipt never becomes eligible for an earlier issue.
6. A transfer within one valuation scope preserves original acquisition order.
   A transfer across scopes preserves acquisition ancestry and exact carrying
   value under the frozen transfer policy; destination availability still
   requires the transfer receipt occurrence.
7. A sales return creates a return-date layer with original issue ancestry, as
   already frozen. It does not regain the original FIFO position.
8. An open-period backdated receipt or issue is inserted at its economic key
   and the queue is replayed forward.
9. A correction to receipt cost adjusts the target layer fact in a successor
   replay version and recalculates affected allocations. It does not rewrite
   the original layer or accepted event.
10. FIFO reconciliation includes the replay version, ordered event
    fingerprint, layer allocation fingerprint, and cut-off tuple.
11. Negative FIFO remains prohibited by default. The same-time convention
    cannot be used to disguise an earlier-effective issue as having eligible
    stock.

## 9. Moving WAC Consequences

1. Every economically applied event creates the next WAC pool version in
   Economic Costing Chronology.
2. Equal-time independent owned receipts are applied before equal-time issues.
   Exact extended values are accumulated before the issue calculation.
3. Receipt order within that inbound group remains deterministically auditable.
   With exact arithmetic, permuting only those receipts cannot change the
   group's aggregate quantity/value before the first later-ranked issue.
4. Issues use the authoritative pool quantity/value immediately preceding
   their economic position. A rounded unit rate is never the authority.
5. Negative WAC remains prohibited by default. A genuinely earlier-effective
   issue cannot use a later receipt. Approved provisional deficit behavior, if
   enabled in a future phase, remains explicit and must settle before close.
6. Open-period backdated or corrected facts rebuild the pool from the earliest
   affected economic key into a new replay version.
7. Receipt-cost records remain audit evidence under WAC Model A and are not
   consumed. This ADR does not change
   [ADR-IAA-001](ADR-IAA-001_WEIGHTED_AVERAGE_VALUATION_MODEL.md).
8. Exact reversals before intervening cost events may restore the prior pool
   state; otherwise a linked inverse event and deterministic replay apply.
9. Audit must disclose accepted order, economic order, pool predecessor,
   authoritative before/after quantity and value, calculation version, and
   downstream correction deltas.
10. WAC reconciliation uses the certified replay/cut-off tuple, pool-version
    chain, and Posting results derived from it.

## 10. Specific Identification Consequences

Specific Identification is governed first by exact physical identity and cost
ancestry, not by a generic queue.

1. A serial or lot identity must be explicitly received, owned, eligible, and
   available before issue. Chronology cannot create missing identity.
2. A serial-controlled receipt precedes the issue of that serial through
   explicit causality. Competing claims to one serial fail; a tie-break cannot
   legitimize both.
3. A lot issue identifies the exact lot and uses that lot's authoritative cost.
   Partial lot occurrences use explicit occurrence and event ordinals.
4. Transfers preserve identity, acquisition ancestry, and carrying value.
   Source issue calculation causally precedes destination receipt valuation.
5. Returns preserve original issue/identity ancestry and require a new accepted
   return occurrence. Replacement inventory is a new identity linked to the
   commercial remedy; it is not a rewrite.
6. Corrections and write-downs retain the physical identity and create linked
   immutable valuation facts.
7. Specific-ID inventory never goes negative. Missing serial/lot eligibility
   rejects economic application.
8. For different identities with exactly simultaneous independent events, the
   canonical order remains available for replay and audit, but cannot change
   which identity supplies cost.

## 11. Replay Contract

### 11.1 Replay boundary

Every replay is identified by:

- company;
- valuation scope;
- accepted-through watermark;
- economic start and end keys;
- predecessor replay version;
- event-order policy version;
- costing policy/method version;
- precision/UOM policy versions;
- correction graph version;
- replay algorithm version; and
- resulting ordered-input and method-state fingerprints.

### 11.2 Event population

Replay includes only valid, economically eligible immutable events:

- belonging to the company and valuation scope;
- accepted through the declared watermark;
- at or before the declared economic cut-off;
- resolved to all required authority versions; and
- not excluded by a governed supersession/correction interpretation.

Accepted events cannot be deleted from audit history. A replay version may
interpret an original and linked correction together, but it must show both and
must never pretend the original did not exist.

### 11.3 Deterministic construction

Replay must:

1. validate source and causal identities;
2. construct the canonical economic order;
3. fail on missing, duplicate, cyclic, or contradictory order authority;
4. apply fixed policy and algorithm versions;
5. calculate exact method state and allocations;
6. compare incremental and full rebuild results;
7. publish no current projection until the version is complete and certified;
8. retain the prior current version until atomic promotion; and
9. emit one immutable result fingerprint and reconciliation evidence.

Two replays of the same boundary must be byte-identical. Two databases holding
the same immutable facts and policy versions must reach the same result
regardless of original transaction or lock schedule.

### 11.4 Late events

A late event never changes a prior replay version. If its economic key precedes
the current boundary, it creates a successor replay request starting at the
earliest affected position. Until successful promotion, reports either continue
to use the prior certified version with a disclosed late-event exception or
fail closed where current certification is required.

This is consistent with immutable event-sourcing principles: new facts create
new state versions rather than rewriting history. It does not authorize IA-6
replay structures or services.

## 12. Cut-off Contract

### 12.1 Open periods

- A valid backdated event may be admitted with its true economic effective
  instant.
- It is inserted into Economic Costing Chronology through a successor replay.
- Existing events and journals remain immutable.
- Re-cost deltas are source-linked and sent to Posting only after Inventory
  calculation and period validation.
- Period close is blocked while required Inventory replay, negative-inventory
  settlement, Posting, or reconciliation exceptions remain unresolved.

### 12.2 Closed periods

- Closed-period Inventory method state and posted journals are never silently
  rewritten.
- A late event or correction is classified by the Accounting Policy/Period
  owner as a prior-period error or estimate change under the frozen IA-3
  policy.
- Inventory computes the counterfactual economic effect and exact delta.
- Any current-period adjustment, retrospective comparative presentation, or
  retained-earnings treatment follows the approved Period/Accounting policy
  without altering historical journal rows.
- A closed-period correction retains both the original certified cut-off and
  the successor reporting/correction evidence.

### 12.3 Reversal chronology

- A reversal is accepted when approved and recorded in Accepted Event
  Chronology.
- Its Inventory economic treatment follows section 6.5.
- Its accounting date must be in an allowed period.
- The Posting Engine persists only the approved reversal/correction journal;
  it does not erase the original journal.

### 12.4 Report cut-off identity

No report may use a date alone as a certified cut-off.

The Inventory valuation cut-off is:

`company + valuation scope + economic as-of instant + accepted-through
watermark + certified replay version + policy versions`

The financial reporting cut-off adds:

`accounting period/version + Posting watermark + reporting/restatement version`

Inventory-to-GL reconciliation uses compatible cut-offs on both sides. An
economically applicable but not-yet-posted result is an explicit exception, not
an amount silently included in one ledger and excluded from the other.

## 13. Posting Boundary Confirmation

This ADR makes **no change** to the Posting Engine, Posting Kernel, journal
persistence, guard enforcement, COA resolution, tax ownership, preview, audit,
or six sanctioned Kernel mutators.

The frozen boundary remains:

1. Inventory owns economic chronology, quantity, costing method state,
   valuation, COGS inputs, source evidence, replay, and Inventory correction
   calculation.
2. Tax owns tax determination.
3. COA resolution owns account selection under the frozen Posting
   architecture.
4. Posting receives source-bound, already-calculated Inventory results and
   builds the journal contract.
5. The Kernel exclusively persists journal headers and lines.
6. Posting never chooses FIFO layers, recalculates WAC, selects Specific-ID
   cost, orders Inventory events, or mutates Inventory method state.
7. Inventory never directly writes journal tables or introduces another
   journal mutator.

## 14. Architecture Impact Assessment

| Authority | Impact | Decision |
| --- | --- | --- |
| Posting Engine specifications and P5.2 certification | None | Posting boundary, Kernel, guards, accounting output, and journal persistence are unchanged. |
| `PXL_INVENTORY_ACCOUNTING_ARCHITECTURE_SPEC.md` | Clarifies | Defines the missing complete deterministic order required by effective-dated source facts and open-period replay. |
| `PXL_INVENTORY_COSTING_SPEC.md` | Partly supersedes | Replaces the incomplete ordering sentence in section 1. Admission-generated event ID or insertion order is not an economic tie-break; the hierarchy in this ADR governs. FIFO/WAC/Specific-ID calculations are unchanged. |
| `PXL_INVENTORY_LAYER_LIFECYCLE_SPEC.md` | Clarifies | Defines the event-order key used by layers, pool versions, allocations, corrections, and returns. |
| `PXL_INVENTORY_RECONCILIATION_CONTRACT.md` | Clarifies | Adds the required accepted watermark, replay version, and economic-order fingerprint to certified cut-offs. Equality rules are unchanged. |
| `PXL_INVENTORY_REPORTING_SPEC.md` | Clarifies | Makes knowledge-as-of and economic-as-of separately reproducible. |
| `PXL_INVENTORY_CANONICAL_DATASET_SPEC.md` | Clarifies future certification | Canonical tests must include order permutations, simultaneous effects, partial occurrences, backdates, corrections, and cut-offs. No fixture is changed by this ADR. |
| `PXL_IA3_HARDENING_DECISION_REGISTER.md` | Clarifies | Preserves fixed precision, period correction, WAC, FIFO, Specific-ID, and Posting-boundary decisions. |
| `ADR-IAA-001_WEIGHTED_AVERAGE_VALUATION_MODEL.md` | Clarifies | Defines the ordered input to WAC Model A; does not change the selected pool model. |
| IA-4 blueprints and risk register | Partly supersedes | Any reference to recorded timestamp, accepted sequence, or insertion identity as a stable economic tie is replaced by this ADR. Existing implementation planning remains historical evidence where inconsistent. |
| `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` | Partly supersedes | Its economic-order tuple is reclassified as Accepted Event Chronology where it depends on scope lock sequence. IA-5 implementation remains dormant and unchanged. |
| `IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md` | Satisfied as architecture input | Its Outcome C remains controlling until the gate is reopened. This ADR supplies the missing policy decision but not implementation proof. |
| IA-5 migrations and tests | None in this phase | No database object, migration, SQL, code, or test is changed. Future evidence must determine the minimum conforming correction. |

No frozen accounting method, costing formula, ownership rule, tax rule,
account-resolution rule, journal rule, or reconciliation equality is redesigned.

## 15. Risks

1. **Current implementation mismatch — Critical until hardened.** IA-5 currently
   records lock-derived accepted order but does not persist or enforce the full
   economic hierarchy. The architecture is decided; implementation conformity
   is not certified.
2. **Source-order governance — High.** Every supported source type must define
   immutable economic time, document order, line order, transition, occurrence,
   and event-effect rules. Missing source authority must fail closed.
3. **Late-event replay exposure — High.** A deterministic economic order means
   a later admission can precede already-applied events. Atomic replay-version
   promotion and explicit pending/stale states are mandatory before activation.
4. **Online status misunderstanding — High.** “Accepted” could be mistaken for
   “costed,” “available,” or “posted.” APIs, lifecycle contracts, reports, and
   audit must preserve the distinction.
5. **Correction graph ambiguity — High.** Competing correction branches or
   imprecise effective anchors can create different re-cost results. Explicit
   ancestry and fail-closed validation are required.
6. **Composite occurrence atomicity — High pending evidence.** Multi-line and
   multi-scope workflows must prove that no partial economic application or
   Posting handoff survives failure.
7. **Cross-scope replay propagation — Medium.** Transfers can require replay of
   a source scope followed by dependent destination scopes. The dependency
   graph and lock order require hostile testing.
8. **Same-time convention visibility — Medium.** Inbound-before-outbound is a
   deterministic accounting convention. Reports and audit must disclose it so
   users do not mistake it for observed physical sequence.
9. **Clock/source precision — Medium.** Source timestamps with insufficient
   precision will invoke tie policy more often. Precision and time-zone
   authority must be governed per source.
10. **Performance — Medium.** Backdated and same-time replay can be expensive
    in hot scopes. Checkpointing and partition strategy may optimize execution
    but may not change chronology.
11. **Open evidence-gate findings — Unchanged.** UOM/policy authority, tenant
    lineage, fingerprint authority, allocation closure, projection/replay
    control, writer governance, and physical-key compatibility remain
    unadjudicated where the prior evidence gate stopped.

None of these risks authorizes implementation, a workaround, or weakening of
the selected order.

## 16. Whether C-01 Is Resolved

**The C-01 architecture decision is RESOLVED.**

PXL now has one explicit relationship between Accepted Event Chronology and
Economic Costing Chronology, one authoritative order hierarchy, one concurrency
policy, one replay policy, one correction policy, and one cut-off policy.

**The C-01 program stop is not yet CLOSED.** Under PG-01, a frozen ADR resolves
the missing architecture authority, but later executable evidence must prove
that implementation conforms. IA-5 permanent-foundation certification remains
suspended, IA-5 remains dormant, and IA-6 remains unauthorized.

## 17. Whether the IA-5/IA-6 Evidence Gate May Be Reopened

**YES — the IA-5/IA-6 Final Evidence Gate may be reopened.**

The authorization is limited to evidence and classification work:

- compare IA-5 structures and services with this ADR;
- determine the minimum additive authority hardening required;
- execute independent-reset sequential, concurrent, randomized, delayed-lock,
  rollback/retry, same-document, source-line, partial-occurrence, backdate,
  correction, FIFO-consequence, and WAC-consequence tests;
- execute the previously stopped H-01 through H-09 and M-01 evidence assets;
- classify whether the conforming correction belongs before or within a
  separately authorized IA-6 foundation subphase; and
- return one governed gate outcome.

Reopening the gate does **not** authorize IA-5 modification, production
migration, IA-6 design beyond dependency classification, IA-6 schema creation,
method-state admission, replay activation, certification, canonical changes,
or Posting/Kernel changes.

The gate may close the C-01 stop only when:

1. all required economic-order authority is explicit and immutable;
2. the implementation does not use lock acquisition or arrival as economic
   priority;
3. identical accepted fact sets produce identical economic order across
   independent schedules and resets;
4. FIFO and Moving WAC consequences match this ADR;
5. backdate, correction, cut-off, and retry behavior pass;
6. no unresolved gate finding independently blocks the next permission; and
7. documentation and implementation evidence agree under PG-01 precedence.

## 18. Required Future ADRs (if any)

No additional ADR is required to define ordinary FIFO, Moving WAC, Specific
Identification, return, adjustment, transfer, correction, or cut-off chronology
within the already frozen Inventory Architecture.

Future successor or extension ADRs are required only if a later authorized
capability introduces chronology not governed by the current source and
valuation-scope contract, including:

- Production/MRP events with operation, yield, scrap, co-product, and batch
  causality;
- intercompany inventory with independently governed legal-entity clocks and
  sale/purchase cut-offs;
- external WMS or offline-device sources that cannot supply one trusted
  effective-time and source-order authority; or
- a proposal to change the simultaneous-event precedence or make Accepted
  Event Chronology the costing authority.

Those future ADRs may extend source-specific causal graphs. They may not weaken
cross-company isolation, immutability, deterministic replay, the Posting
boundary, or this ADR's prohibition on accidental lock-order costing.
