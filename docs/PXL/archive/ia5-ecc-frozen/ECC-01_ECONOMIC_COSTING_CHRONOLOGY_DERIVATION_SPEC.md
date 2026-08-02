# ECC-01: Economic Costing Chronology Derivation Specification

**Status:** **ACCEPTED — OWNER APPROVED** (2026-07-26, [ECC-01 Formal Owner Acceptance](ECC-01_FORMAL_OWNER_ACCEPTANCE.md)). Derivation specification under ADR-C01; introduces no new accounting policy. **Freeze status: not yet formally frozen** — the owner exercised acceptance only, and freeze remains a separate later owner act; change control is nevertheless bound by the Supersession Rule below. Acceptance evidence: [Final Architecture Acceptance Report](ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md).
**Authority:** Tier 1 Domain Architecture, subordinate to [ADR-C01](ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md)
**Owner / Domain:** Inventory Accounting
**Applies To:** Derivation of the Economic Costing Chronology (ECC) position of every accepted Inventory event, in every valuation scope, replay version, and cut-off
**Read When:** Designing, implementing, hardening, replaying, or certifying Inventory event order, FIFO, Moving WAC, Specific Identification, backdating, corrections, or cut-off
**Do Not Read For:** Journal persistence, tax determination, account resolution, costing formulas themselves, or authorization to implement
**Last Reviewed:** 2026-07-26
**Implementation Status:** Specification only. No SQL, schema, migration, function, index, or test is authorized or implied by this document.
**Supersession Rule:** Only an approved successor ADR, or an approved ECC-02 that does not weaken ADR-C01, may change this derivation.
**Amendment A1 (2026-07-26, ECC-01 Final Architecture Acceptance Gate):** Eight bounded determinism clarifications were added under the acceptance gate's documentation authority — economic-bound inclusivity and bound-key completeness (§3.4, §5.4), watermark portability (§3.4), order-policy re-resolution and digest-version governance (§3.2, §3.3), occurrence event-plan determinism (§4.2 E9), derived-allocation representation (§4.2 E6), cohort- and dependency-safe start bounds (§5.4, §6.6), and the eligibility-failure boundary (§13). No ordering component, rank, comparator position, proof, worked example, or accounting policy was changed. Findings ECC-A-02 … ECC-A-09 of the acceptance report record each change.
**Relationship:** Derives the complete algorithm for the ordering hierarchy frozen in ADR-C01 §6. Consumes the frozen [Costing Specification](PXL_INVENTORY_COSTING_SPEC.md), [Layer Lifecycle Specification](PXL_INVENTORY_LAYER_LIFECYCLE_SPEC.md), [Reconciliation Contract](PXL_INVENTORY_RECONCILIATION_CONTRACT.md), [Architecture Specification](PXL_INVENTORY_ACCOUNTING_ARCHITECTURE_SPEC.md), and [IA-3 Hardening Decision Register](PXL_IA3_HARDENING_DECISION_REGISTER.md). Answers Required Correction 1 and 2 of the [IA-5/IA-6 Final Evidence Gate Report](IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md) §13. Does not close the C-01 program stop, which requires executable conformance evidence.

---

## 1. Executive Summary

ADR-C01 froze the accounting policy: PXL keeps two permanent chronologies, and
economic costing order is derived from governed source facts, never from
PostgreSQL transaction, lock, commit, or insertion order. ADR-C01 named the ten
ordering components but did not define the algorithm. This specification defines
it exactly.

The derivation is stated in one sentence:

> Within one company and one valuation-scope key, and for one declared replay
> boundary, the Economic Costing Chronology is the unique ascending enumeration
> of the population's **ECC sort keys** under a strict total order composed of
> ten immutable primary components and four correction-anchor extension
> components; the ordinal position of each event is derived from that
> enumeration and is valid only within its replay version.

Four properties follow and are proved in §6:

1. **Totality.** The comparator is a strict total order, so a finite population
   has exactly one increasing enumeration. There is no residual tie, and
   therefore no dependence on sort stability, iteration order, parallelism, or
   physical row order.
2. **Schedule independence.** Every component is established before Inventory
   admission or resolved from a declared policy version. No component reads a
   clock, transaction id, sequence allocator, advisory-lock outcome, row
   location, or commit order. ECC is therefore a pure function of the committed
   population and the version vector.
3. **Insertion monotonicity.** Because keys are immutable and a causal edge may
   only be declared by the dependent event at its own admission, admitting a new
   event never reorders two already-ordered events. It inserts. Backdating and
   corrections therefore shift ordinals without rewriting relative economic
   history.
4. **Prefix stability.** Method state is a fold over the ECC sequence, so the
   prefix strictly before the earliest newly affected key is provably reusable.
   Incremental replay is legitimate — and must equal full replay by
   construction, not by hope.

The specification is fail-closed throughout. Missing economic time, missing
registry authority, missing source-line order, a causal cycle, a cross-company
relationship, a duplicate logical order identity, an unresolved correction fork,
or an unresolvable anchor **rejects economic application** rather than choosing an
order. ECC never substitutes a database-derived value for missing business
evidence, and never falls back to a secondary tie-break when its uniqueness rule
is violated.

What this document does **not** do: it does not authorize implementation, does
not modify IA-5, does not authorize IA-6, does not change any costing formula,
and does not close the C-01 stop. ADR-C01 §17 governs the reopening of the
evidence gate; §14 and §15 of this document describe, non-bindingly, what a
future authorized hardening phase must satisfy to be conformant.

---

## 2. ECC Principles

### 2.1 Foundational principles

| # | Principle | Consequence |
| ---: | --- | --- |
| P-01 | ECC is derived, never allocated. | No counter, sequence, serial, identity column, or lock-protected allocator may produce an ECC position. |
| P-02 | ECC is partitioned by company and valuation-scope key. | No order, layer, pool, allocation, ancestry, or tie-break crosses a company or merges two valuation scopes. |
| P-03 | ECC is a total order, not a partial order. | FIFO and Moving WAC require a total order; ECC always produces one or fails closed. |
| P-04 | Every ordering component is non-null. | ECC has no nullable component and therefore no null-ordering convention to argue about. |
| P-05 | Every ordering component is immutable once admitted. | An event's ECC key never changes. Only the population changes. |
| P-06 | Every policy-governed component is versioned and resolved at admission. | A later policy change cannot silently reorder a certified stream. |
| P-07 | Accepted Event Chronology is retained, never reused as ECC. | Accepted position is admission evidence and idempotency authority only. |
| P-08 | An ordinal is meaningful only with its replay version. | An ECC ordinal without a replay version is not a citable accounting fact. |
| P-09 | ECC orders events; it does not decide eligibility. | Negative-inventory, availability, identity-eligibility, and period rules are evaluated *after* ordering, in ECC order. |
| P-10 | ECC is auditable component by component. | Every position must be explainable by naming the component that decided it and the policy version that interpreted it. |

### 2.2 Prohibited derivation inputs

The following may never appear in an ECC component, directly or through a
derived value. Presence of any of them is a conformance defect, independent of
whether an observed result happened to be correct.

- transaction id, snapshot, or commit order;
- row lock acquisition order, advisory-lock outcome, or lock wait order;
- any sequence, serial, identity, or counter allocated during admission,
  including a per-scope accepted sequence;
- `clock_timestamp()`, `now()`, statement time, created/recorded/received
  timestamp, or any admission-time clock read;
- physical row location, page order, index scan order, or unordered set
  enumeration order;
- randomly generated identity assigned at admission, including a database
  default UUID;
- display document number, user-visible sort order, UI row order, or any
  mutable label;
- amount, quantity, item, account, vendor, customer, or name similarity;
- date proximity or any heuristic source match;
- locale-dependent or environment-dependent text collation.

### 2.3 Boundary principles

| Boundary | Rule |
| --- | --- |
| Posting | ECC produces order; Posting consumes results. Posting never reads, sets, or influences an ECC component. |
| Tax | Tax determination is not an ECC input and is not ordered by ECC. |
| Period | ECC places economic effect; the accounting date and Posting watermark place GL effect. Neither controls the other. |
| Locks | A lock may protect method-state mutation. It may never select an ECC component or resolve a tie. |
| Availability | ECC order is derived before availability is evaluated. An issue is never reordered to make stock exist. |
| Reporting | A report cites the ECC of a certified replay version at a declared cut-off tuple, never "the current order". |

---

## 3. ECC Inputs

### 3.1 Input classes

| Class | Input | Required for | Fail-closed behaviour if absent |
| --- | --- | --- | --- |
| Partition | Company identity | Every ECC operation | Reject admission |
| Partition | Valuation-scope key (company + item + valuation currency + configured scope node) | Every ECC operation | Reject admission |
| Ordering | The ten primary components E1–E10 (§4.2) | Every event | Reject economic application of the event |
| Ordering | The four correction-anchor extension components X1–X4 (§4.3) | Every anchored correction | Reject economic application of the correction |
| Causal | Declared predecessor / reversal / correction / transfer / return edges | Cohort ranking and validation | Reject economic application |
| Registry | Event Source Registry rule for the event's source type and version | Component resolution | Source type unavailable to economic processing |
| Policy | Event-order policy version (effect ranks, source-type ranks, canonical form) | Component resolution | Reject replay |
| Policy | Valuation-scope resolution version | Partition resolution | Reject admission |
| Policy | Correction-graph version | Anchoring and chain validation | Reject replay |
| Replay | Accepted-through watermark, economic start/end keys, predecessor replay version, replay algorithm version | Population selection and ordinal assignment | Reject replay |
| Evidence | Immutable pre-admission source identity and its canonical form version | Final tie-break | Reject economic application |

### 3.2 Policy dependencies

ECC depends on exactly four policy families. Only these can change an order.

| Policy family | Governs | Can change ECC? | Change protocol |
| --- | --- | ---: | --- |
| Event-order policy | Effect-class ranks, source-type ranks, lifecycle-transition ranks, canonical form and encoding rules | **Yes** | New version + governed order re-resolution replay; prior certified versions retained |
| Event Source Registry | Per-source-type event effects, economic-time authority, document-order-key algorithm, line-order authority, transition set, occurrence semantics, same-time class, correction placement class | **Yes** | New version per source type; a source type is unavailable until its rule exists |
| Valuation-scope resolution policy | Scope key composition and scope-node configuration | **Yes** — by repartitioning, never by reordering within a partition | Accounting-policy event; may require conversion, never a silent partition split |
| Correction-graph policy | Anchoring semantics, chain rules, registered commutativity proofs | **Yes** | New version + successor replay |

The following policies are ECC **dependencies of record** — they must be resolved
and retained for every event, they participate in the replay boundary and
fingerprint, but they cannot change an order:

- accounting-profile version;
- cost-formula policy version and costing method;
- precision policy version (quantity scale, 8-decimal valuation amounts,
  12-decimal derived rates, currency minor units);
- UOM conversion policy version;
- negative-inventory policy version;
- period policy version.

A change to a dependency of record changes calculated amounts, never sequence.
This separation is deliberate: it lets PXL re-cost without re-ordering, and
re-order only under an explicit order-policy decision. A dependency-of-record
change is still a governed event: it requires a **successor replay version**
whose ordered-input fingerprint is identical to its predecessor's and whose
method-state fingerprint differs. Identical order plus a changed amount is the
signature of a legitimate re-cost; a changed ordered-input fingerprint under a
dependency-of-record change is a defect (F-12).

### 3.3 Version dependencies

Define the **ECC version vector**:

`V = (event-order policy version, source-registry version set for every source
type present, canonical form version, scope-resolution version,
correction-graph version)`

ECC results are comparable only under an identical `V`. Two ECC results computed
under different `V` are different accounting statements even if the event
population is identical, and must not be presented as the same order. Every
certified replay version records `V` in full; a replay whose population contains
an event resolved under a `V` component incompatible with the declared boundary
**fails closed** (§13, F-11).

**Digest identity.** The digest algorithm used for the ordered-input and
method-state fingerprints, and its version, are declared by the **canonical form
version** — the same authority that governs the serialization being digested
(N-04, N-05). A fingerprint is therefore comparable only between computations
sharing one canonical form version and one digest identity. Comparing digests
across canonical form versions is meaningless, not merely unsafe, and a
fingerprint recorded without its digest identity is not replay authority.

**Order re-resolution.** Because components are resolved at admission (P-06) and
immutable thereafter (P-05), a partition can contain events resolved under a
superseded order-policy, registry, scope-resolution, or correction-graph version
while newly admitted events resolve under the current one. That mixed state is
**not** a replayable state: V-17 and F-11 reject any boundary spanning it. The
only conforming remedy is a **governed order re-resolution**, whose invariants
are:

1. it produces *new* immutable resolved-component evidence, under the target
   version, for every event in the partition, and never mutates or discards the
   prior resolution, which remains audit evidence of the superseded stream;
2. it never re-derives a component from current master data — the re-resolution
   input is the event's retained immutable source evidence (§14.2(1));
3. it produces a successor replay version whose declared `V` is uniform across
   the whole population; and
4. it is an explicit governed act. Re-resolution must never be triggered
   implicitly by the arrival of an event carrying a newer version — that arrival
   fails closed under F-11 until re-resolution is authorized and executed.

A re-resolution may reorder events. That is precisely why it is a governed
accounting decision and not a maintenance operation.

### 3.4 Replay dependencies

| Dependency | Requirement |
| --- | --- |
| Accepted-through watermark | An immutable boundary in Accepted Event Chronology. ECC is computed over the set admitted **at or before** it (inclusive). Events admitted later are outside the version by definition, never "missing". |
| Economic start and end keys | Complete ECC sort keys — all fourteen components `⟨E1..E10, X1..X4⟩` — not dates, and not truncated primary blocks. A cut-off expressed only as a date, or as a primary block without its extension components, is not a valid ECC boundary, because it cannot state whether an anchored correction sharing its target's primary block is inside or outside. Both bounds are **inclusive**: the population is the closed interval `[start, end]` under `≺`. End-inclusivity is ADR-C01 §11.2's "at or before the declared economic cut-off"; start-inclusivity is ADR-C01 §3.6's "begins at the earliest affected economic key". |
| Predecessor replay version | Every version except the first names its predecessor, forming an auditable chain per partition. |
| Replay algorithm version | The ECC construction implementation identity, distinct from the order policy it executes. |
| Cross-scope dependency graph | Transfer edges order the *replay of partitions*, never the merging of partitions. A cycle in that graph fails closed. |
| Ordered-input fingerprint | A versioned digest of the canonical serialization of the ordered key list. Two replays of one boundary must produce the same fingerprint. |
| Method-state fingerprint | The result fingerprint of the fold over the ECC sequence. |
| Promotion | No projection is published until the version is complete and certified; the prior current version is retained until atomic promotion. |

**Watermark portability.** An accepted-through watermark is meaningful only
inside the accepted chronology that issued it. ADR-C01 §3.1 permits two
independent admissions of the same facts to receive different accepted
positions, so the same watermark *value* may select different populations in two
databases. A watermark is therefore a knowledge-as-of selector within one
environment — never a portable population identity. Every cross-environment,
cross-reset, or cross-schedule equality claim (V-29, F-15, and the §6.3
corollary) must be stated over the **complete admitted fact set**: admit the
identical authoritative command set in full under each schedule, then compare.
Comparing two environments "through watermark *n*" proves nothing.

### 3.5 Normalization rules

All normalization is part of the canonical form version. Normalization is
deterministic, environment-independent, and lossless with respect to the
original source evidence, which is retained separately.

| # | Rule |
| ---: | --- |
| N-01 | **Instant normalization.** The economic effective instant is normalized to UTC and stored at a single declared internal precision (microsecond). The source's own declared precision is retained alongside it. An instant with no unambiguous offset, an ambiguous local-time value, or a precision coarser than the declared source precision is rejected — never defaulted, never widened to a date. |
| N-02 | **No date substitution.** A date is not an instant. A source that can supply only a date must have a registry rule that declares the governed instant construction (for example, a policy-declared period boundary), and that construction is part of the registry version. Silent midnight assignment is prohibited. |
| N-03 | **Rank normalization.** Effect, source-type, and lifecycle-transition ranks are non-negative integers resolved from the event-order policy version at admission and retained as immutable event evidence. Sparse numbering is required so future ranks can be inserted without renumbering. |
| N-04 | **Text canonicalization.** Every text-derived component (document order key, transition code, identity string) is normalized to Unicode NFC, compared by unsigned byte value, and never by a locale or database collation. Environment-dependent collation is prohibited because it makes the same facts order differently in two databases. |
| N-05 | **Length-prefixed encoding.** Canonical serialization of a key encodes each component with an explicit length or fixed width so that no two distinct component sequences can produce the same byte string. Injectivity is a requirement, not an expectation. |
| N-06 | **Identity canonicalization.** A UUID-shaped identity is canonicalized to its 16-byte value and compared as unsigned bytes; its text form is lowercase hexadecimal. Composite identities are encoded under N-05. |
| N-07 | **Ordinal normalization.** Line, occurrence, and event ordinals are positive integers compared numerically. Text-encoded ordinals are prohibited because they sort lexicographically. |
| N-08 | **No null, no sentinel ambiguity.** Every primary component has a total non-null domain. Extension components use a single defined "base fact" sentinel that can occur only at chain depth zero, so no null-ordering rule is ever needed. |
| N-09 | **Fixed-point only.** Any numeric component or amount participating in ECC evidence or fingerprints is fixed-point. Binary floating point is prohibited, including in intermediate comparisons. |
| N-10 | **Signed-quantity independence.** Quantity sign classifies the event effect for rank resolution; the magnitude never participates in ordering. |

---

## 4. ECC Ordering Tuple

### 4.1 Shape

`ECC position = ( partition , replay version , ordinal )`

`partition = ( company , valuation-scope key )`

`ECC sort key = ⟨ E1, E2, E3, E4, E5, E6, E7, E8, E9, E10 ⟩ ⊕ ⟨ X1, X2, X3, X4 ⟩`

The primary block E1–E10 is the frozen ADR-C01 §6.3 hierarchy in its frozen
order. The extension block X1–X4 implements ADR-C01 §6.5 correction placement.
Extension components are compared only after all ten primary components are
equal, which — by the anchoring rule in §4.4 — happens only between a target
fact and its own correction chain.

`ordinal` is the 1-based index of the key in the ascending enumeration of the
population. It is derived, version-scoped, and never stored as authority
independent of the key.

### 4.2 Primary components

#### E1 — Economic effective instant

| Attribute | Contract |
| --- | --- |
| Purpose | Place the event at the instant its economic inventory effect belongs. It is the dominant component because economic time is the primary accounting fact. |
| Owner | Approved source workflow supplies it; Inventory policy validates it. |
| Data source | Governed control-transfer, movement, acceptance, count, return, or correction evidence declared by the source type's registry rule. |
| Authority | ADR-C01 §3.3, §6.3(1). |
| Nullable? | No. |
| Versioned? | Yes — by registry version (which evidence field is authoritative) and canonical form version (normalization). |
| Immutable? | Yes. A wrong instant is corrected by a new governed correction event, never by editing this value. |
| Validation | N-01, N-02; instant is within the scope's admissible economic range; consistent with every declared causal edge (§5.4); period classification resolved. |
| Failure behaviour | Reject economic application. Created, received, recorded, admitted, or database timestamps may not substitute. |

#### E2 — Causal / topological precedence within the equal-instant cohort

| Attribute | Contract |
| --- | --- |
| Purpose | Honour genuine business causality between events that share one economic instant, so a derived convention never overrides a real dependency. |
| Owner | Source domains declare edges; Inventory derives the rank. |
| Data source | Declared predecessor, reversal, correction, transfer, and return links of events in the cohort, restricted to the cohort. |
| Authority | ADR-C01 §3.2, §6.2, §6.3(2). |
| Nullable? | No — an event with no in-cohort predecessor has causal depth 0. |
| Versioned? | Yes — correction-graph version and registry version. |
| Immutable? | Derived, and invariant per §6.4 Lemma 1: a dependent event declares its own edges at its own admission, and an admitted event's declarations are immutable, so no later admission can insert an edge between two already-ordered events. |
| Validation | Directed acyclic; single company; every named predecessor present in the population; edges consistent with E1 across cohorts (a predecessor's instant may not exceed the dependent's). |
| Failure behaviour | Reject economic application of the affected sub-graph and reject replay of the partition. A cycle is never broken by choosing an order. |

Causal depth is defined by longest path inside the cohort:

`depth(e) = 0` when `e` has no predecessor in the cohort; otherwise
`depth(e) = 1 + max{ depth(p) : p → e, p in cohort }`.

This is a function of the edge set alone, not of any traversal, and it satisfies
`depth(u) < depth(v)` for every edge `u → v`, so ascending depth is always a
topological order.

#### E3 — Same-time event-effect rank

| Attribute | Contract |
| --- | --- |
| Purpose | Apply the frozen accounting convention for economically simultaneous, causally independent facts: opening, then increase, then value-only, then decrease, then allowance. |
| Owner | Event-order policy; Inventory resolves the event's effect class. |
| Data source | The event's classified economic effect — never its document label. |
| Authority | ADR-C01 §6.3(3), §6.4 ranks 10/20/30/40/50. |
| Nullable? | No. |
| Versioned? | Yes — event-order policy version. |
| Immutable? | Yes, resolved at admission and retained. |
| Validation | Effect class matches the event's quantity/value direction and the registry's declared effects for the source type and transition; rank exists in the declared policy version. |
| Failure behaviour | Reject economic application. A label-derived or caller-asserted rank contradicting the effect is a defect, not an override. |

#### E4 — Registered source-type rank

| Attribute | Contract |
| --- | --- |
| Purpose | Order independent events of different source types that share instant, causality, and effect class, using a disclosed policy rather than an accident. |
| Owner | Event Source Registry / event-order policy. |
| Data source | The event's registered source type. |
| Authority | ADR-C01 §6.3(4), §5(6). |
| Nullable? | No. |
| Versioned? | Yes — registry and order-policy versions. |
| Immutable? | Yes. |
| Validation | Source type exists, is production-enabled for the company and profile, and has a complete registry rule; rank is unique within the policy version. |
| Failure behaviour | Reject economic application. An unregistered or not-enabled source type is unavailable to economic processing entirely. |

#### E5 — Registered source-document order key

| Attribute | Contract |
| --- | --- |
| Purpose | Order two independent documents of the same source type at the same instant, effect, and causality, by the source's own governed sequence. |
| Owner | Source domain owns the sequence; the registry declares exactly one key algorithm per source type. |
| Data source | The governed business sequence (for example an approved number-series value) where one exists; otherwise the registry-declared canonical ordering of the immutable source identifier. |
| Authority | ADR-C01 §6.3(5) and the §6.3 registry paragraph. |
| Nullable? | No. |
| Versioned? | Yes — registry version defines the algorithm; canonical form version defines the encoding. |
| Immutable? | Yes. |
| Validation | Exactly one algorithm resolved; key is total-ordered under N-04/N-05/N-06; a numeric sequence is compared numerically or fixed-width zero-padded, never lexicographically by accident; the key is unique per document within the company. |
| Failure behaviour | Reject economic application. A display number, mutable sort field, insertion id, or wall-clock receipt time may never be substituted. |

#### E6 — Source-line ordinal

| Attribute | Contract |
| --- | --- |
| Purpose | Preserve the source document's own line order, which the evidence gate proved the current implementation inverts under reversed submission. |
| Owner | Source domain. |
| Data source | The immutable line ordinal established when the source line was created. |
| Authority | ADR-C01 §6.3(6); Costing Specification §1. |
| Nullable? | No. |
| Versioned? | No — it is source-line evidence, not policy. |
| Immutable? | Yes. A re-ordered UI display never changes it. |
| Validation | Positive integer, unique within the source document version, stable across the line's lifetime; a derived allocation orders after its parent line (see below). |
| Failure behaviour | Reject economic application. A source that cannot supply a stable line ordinal is not economically processable. |

**Derived allocations do not receive a synthetic line ordinal.** E6 is the
source document's own line ordinal and nothing else. A derived allocation — a
landed-cost apportionment, a residual assignment, or any other Inventory effect
computed from a parent line rather than stated by it — is represented as a
further *event of that parent line*, carrying the parent's E6, and is ordered
after its parent by its declared causal edge (E2), its registered transition
rank (E7), or its event ordinal within the occurrence (E9), exactly as the
registry rule declares. Inventing a fractional, offset, or high-water line
ordinal to place an allocation is prohibited: it would make one document's
internal order depend on an implementation's chosen encoding, and ADR-C01 §6.2
already places "source line before a derived allocation" in the causal graph,
not in the line-ordinal domain.

#### E7 — Registered lifecycle-transition rank

| Attribute | Contract |
| --- | --- |
| Purpose | Order multiple governed transitions of one source line that legitimately share an instant (for example ownership recognition then warehouse placement). |
| Owner | Event Source Registry. |
| Data source | The event's declared source transition. |
| Authority | ADR-C01 §6.3(7); registry rule per ADR-C01 §5(6). |
| Nullable? | No. |
| Versioned? | Yes — registry version. |
| Immutable? | Yes. |
| Validation | Transition is a member of the source type's declared transition set; rank exists; the transition's declared predecessors are satisfied; two contradictory transitions of one line at one instant are rejected. |
| Failure behaviour | Reject economic application. |

#### E8 — Source occurrence ordinal

| Attribute | Contract |
| --- | --- |
| Purpose | Order partial or split fulfilment of one source line, which the evidence gate also proved is currently inverted under reversed submission. |
| Owner | Source domain declares the occurrence; Inventory validates it. |
| Data source | The explicit partial-occurrence ordinal of the source line. |
| Authority | ADR-C01 §6.3(8), §6.6. |
| Nullable? | No — a single-occurrence line uses ordinal 1. |
| Versioned? | No. |
| Immutable? | Yes. |
| Validation | Positive integer; unique per line and transition; a new legitimate partial occurrence requires a new explicit ordinal and identity; gaps are permitted, reuse is not. |
| Failure behaviour | Reject economic application; a reused ordinal with different content is a duplicate-identity failure (§13, F-06). |

#### E9 — Event ordinal within the occurrence

| Attribute | Contract |
| --- | --- |
| Purpose | Order the multiple Inventory effects that one occurrence legitimately produces (for example a scope-crossing transfer's issue and its dependent receipt evidence). |
| Owner | Inventory Engine, from the occurrence's declared event plan. |
| Data source | The occurrence's event sequence. |
| Authority | ADR-C01 §6.3(9), §5(8). |
| Nullable? | No. |
| Versioned? | No. |
| Immutable? | Yes. |
| Validation | Positive integer, unique and contiguous within the occurrence; consistent with declared intra-occurrence causality; the occurrence is atomic, so a partially ordered occurrence cannot exist; the event plan that assigns it is deterministic (see below). |
| Failure behaviour | Reject the whole occurrence. Partial economic application of an occurrence is prohibited. |

**The occurrence event plan must be a pure function.** E9 is the only primary
component that Inventory itself assigns, and E10 composes it, so the plan that
produces it carries the whole tuple's schedule independence. The event plan —
how many Inventory effects an occurrence produces, and in what intra-occurrence
sequence — must be a deterministic function of the occurrence's own immutable
payload and the source type's registry rule at its declared version, and of
nothing else. It may not depend on current method state, present pool or layer
contents, available quantity, concurrent occurrences, master data read at
admission time, or any input prohibited by §2.2. An occurrence that would emit a
different plan for the same payload under a different schedule violates V-02 and
is an F-04 conformance defect, not a data error — and Theorem 2 does not hold for
an implementation that permits it.

#### E10 — Immutable pre-admission source identity

| Attribute | Contract |
| --- | --- |
| Purpose | Guarantee totality. It is the final collision-proof discriminator and carries no claimed economic meaning. |
| Owner | Source domain; established before Inventory admission. |
| Data source | The canonical immutable identity of the source fact — the composite of source type, source document identity, source line identity, transition, occurrence ordinal, and event ordinal as declared by the registry. |
| Authority | ADR-C01 §6.3(10) and its final-tie-break paragraph. |
| Nullable? | No. |
| Versioned? | Yes — canonical form version only. |
| Immutable? | Yes, and identical across environments by N-04/N-05/N-06. |
| Validation | Unique within the partition; **not** database-generated at admission; byte-identical when recomputed from retained source evidence; two different facts claiming one identity is a hard failure, never a tie to break. |
| Failure behaviour | Reject both conflicting applications and reject certification of the stream (ADR-C01 §6.6). No secondary tie-break exists or may be added. |

### 4.3 Correction-anchor extension components

#### X1 — Correction chain depth

| Attribute | Contract |
| --- | --- |
| Purpose | Place an anchored correction immediately after the fact it corrects, and order a chain of corrections along that chain. |
| Owner | Inventory Engine, from the declared correction graph. |
| Data source | Depth in the anchored correction chain: 0 for the target fact itself, 1 for its first correction, `n+1` for a correction of a depth-`n` correction. |
| Authority | ADR-C01 §6.5. |
| Nullable? | No — base facts carry depth 0. |
| Versioned? | Yes — correction-graph version. |
| Immutable? | Yes. |
| Validation | Target present in the population and in the same partition; chain is non-branching unless a registered commutativity proof exists; depth is exactly one greater than its declared parent; no cycle. |
| Failure behaviour | Reject the correction and the partition's replay. An unresolved fork fails closed. |

#### X2 — Correction business effective instant

| Attribute | Contract |
| --- | --- |
| Purpose | Order a registered commuting fork deterministically, and retain the correction's own economic time as evidence. |
| Owner | Approved correction workflow. |
| Data source | The correction's declared business effective instant. |
| Authority | ADR-C01 §6.5. |
| Nullable? | No — sentinel "base fact" value at depth 0. |
| Versioned? | Yes — canonical form version (N-01). |
| Immutable? | Yes. |
| Validation | Normalized per N-01; not earlier than its target's E1 unless the registry declares that semantics; classified open-period, closed-period error, or estimate change. |
| Failure behaviour | Reject the correction. |

#### X3 — Correction approval instant

| Attribute | Contract |
| --- | --- |
| Purpose | Discriminate registered commuting corrections that share a business effective instant. |
| Owner | Approval authority. |
| Data source | The governed approval instant of the correction. |
| Authority | ADR-C01 §6.5. |
| Nullable? | No — sentinel at depth 0. |
| Versioned? | Yes — canonical form version. |
| Immutable? | Yes. |
| Validation | Normalized per N-01; approval exists and is complete; approval instant is not before the correction's own creation evidence. |
| Failure behaviour | Reject the correction. |

#### X4 — Correction identity

| Attribute | Contract |
| --- | --- |
| Purpose | Guarantee totality inside the extension block. |
| Owner | Correction source domain. |
| Data source | The correction's immutable pre-admission source identity, canonicalized as in E10. |
| Authority | ADR-C01 §6.3 final tie-break, applied within the anchor. |
| Nullable? | No — sentinel at depth 0. |
| Versioned? | Yes — canonical form version. |
| Immutable? | Yes. |
| Validation | Unique within the partition; not database-generated at admission. |
| Failure behaviour | Reject both conflicting corrections and block certification. |

### 4.4 The anchoring rule, and why the tuple is ordered this way

**Anchoring rule.** A correction whose registered placement class is `anchored`
does not receive an independent primary key. It inherits its **root target's**
complete E1–E10 block unchanged and is discriminated only by X1–X4. A correction
whose placement class is `independent` — including every reversal, every estimate
change effective from the date of change, and every landed-cost effect the
registry places at its own governed instant — receives an ordinary E1–E10 key
and no extension (depth 0 sentinels). A correction whose placement class is
`counterfactual_only` — a closed-period error — is never inserted into the
certified stream at all; ECC computes it only inside an explicitly non-certifying
counterfactual replay (§6.8).

Because every other event differs from the target in at least E10, an anchored
correction sorts strictly after its target and strictly before the next distinct
key. This is exactly ADR-C01 §6.5's "immediately after the corrected target
fact", achieved by construction rather than by a special-case insertion step.

**Why each component sits where it does.**

| Position | Component | Why here |
| ---: | --- | --- |
| 1 | E1 economic instant | Economic time is the primary accounting fact; every other component only resolves what economic time cannot distinguish. |
| 2 | E2 causal depth | Genuine causality must outrank any convention. Placing it below E3 would let the increase-before-decrease convention overrule a real dependency. |
| 3 | E3 effect rank | ADR-C01's frozen convention for indistinguishable simultaneous facts. It must sit above document-level components so a receipt cannot be pushed behind an issue merely by having a later document number. |
| 4 | E4 source-type rank | The coarsest disclosed document-level policy; ordering by source class before document identity keeps registry rules explainable. |
| 5 | E5 document order key | The source's own governed sequence — the most business-meaningful discriminator inside one source class. |
| 6 | E6 line ordinal | A document's internal order is subordinate to which document it is, and superior to anything below. |
| 7 | E7 transition rank | Transitions belong to a line, so they resolve after the line is identified. |
| 8 | E8 occurrence ordinal | Partial occurrences are instances of one line-and-transition, so they resolve after both. |
| 9 | E9 event ordinal | Multiple Inventory effects of one occurrence are the innermost genuine business structure. |
| 10 | E10 source identity | Pure totality guarantee, deliberately last so it can never mask a missing genuine component. |
| 11–14 | X1–X4 | Correction placement is defined relative to a target fact, so it must be strictly subordinate to that target's entire key. |

### 4.5 Comparator

For events `a`, `b` in one partition, `a ≺ b` if and only if there exists an
index `i` in the ordered component list `⟨E1..E10, X1..X4⟩` such that
`comp_i(a) < comp_i(b)` under that component's declared total order, and
`comp_j(a) = comp_j(b)` for all `j < i`.

`≺` is irreflexive, transitive, and — given validation rule V-14 (E10 uniqueness
within the partition) — total. It is therefore a strict total order.

---

## 5. Deterministic Algorithm

The algorithm has eight stages. Stages 1–3 are admission-time; stages 4–8 are
replay-time. No stage reads any prohibited input in §2.2.

### 5.1 Stage 1 — Partition resolution

1. Resolve the event's company.
2. Resolve the valuation-scope **key** from the effective-dated scope master as
   of the event's economic effective instant: company + item + valuation
   currency + configured scope node.
3. Record the scope **version** that performed the resolution as a dependency of
   record.
4. The partition is the scope key. A later scope re-version under the same key
   does **not** create a second partition and does **not** restart the stream.
5. Reject if the scope cannot be resolved, resolves to more than one key, or
   crosses a company.

### 5.2 Stage 2 — Component resolution and normalization

For the event, resolve E1–E10 and, if it is an anchored correction, X1–X4:

1. Load the registry rule for the source type at its declared version. If none
   exists, or the type is not production-enabled, stop: the source type is
   unavailable to economic processing.
2. Resolve E1 from the registry-declared economic-time evidence field and
   normalize per N-01/N-02.
3. Classify the economic effect and resolve E3 from the event-order policy
   version.
4. Resolve E4, E5, E7 from the registry and order policy; normalize per
   N-03/N-04/N-05/N-06/N-07.
5. Take E6, E8, E9 from the source line, occurrence, and occurrence event plan.
6. Compute E10 from retained immutable source evidence and canonicalize.
7. If the placement class is `anchored`, replace E1–E10 with the root target's
   E1–E10 and resolve X1–X4; otherwise set X1–X4 to the base-fact sentinels.
8. Retain every resolved component and every resolving policy version as
   immutable event evidence. ECC is never recomputed later from mutable master
   data.

### 5.3 Stage 3 — Admission-time validation

Apply §12 rules V-01 … V-13 to the single event and its occurrence. The
occurrence is atomic: either every event of the occurrence passes and is
admitted, or none is. Admission records the Accepted Event Chronology position
and is explicitly **not** an ECC position; the event is *pending costing* until a
replay applies it.

### 5.4 Stage 4 — Population selection

Given a replay boundary (§3.4):

1. Select events in the partition, admitted at or before the accepted-through
   watermark, whose ECC key lies in the **closed interval** `[start key, end
   key]` under `≺` — both bounds inclusive, both stated as complete fourteen-
   component keys (§3.4).
2. Exclude nothing else. A governed supersession interpretation may combine an
   original and its correction, but both remain present and visible.
3. Resolve every event's version vector `V` and reject if any is incompatible
   with the boundary's declared `V`.
4. Reject if any anchored correction's root target is absent from the selected
   population.
5. **A start bound may not truncate a cohort or a dependency.** If the start key
   would exclude any event that (a) shares an E1 cohort with a selected event,
   (b) is a declared predecessor of a selected event, or (c) is the root target
   of a selected anchored correction, the boundary is invalid: widen it to
   include that event, or fail closed (F-05, F-09). This rule is what keeps a
   bounded replay's order equal to the same events' order in a full replay.
   Truncating a cohort would recompute E2 causal depth over a restricted edge
   set and could reorder events that a full population orders differently —
   which is exactly the class of divergence ECC exists to eliminate.

### 5.5 Stage 5 — Causal validation and cohort ranking

1. Build the causal graph over the population from declared edges only.
2. Reject on any cycle, any cross-company edge, any missing named predecessor,
   or any edge whose predecessor instant exceeds its dependent's instant
   (except the anchored-correction case, which is handled by anchoring rather
   than by an edge over E1).
3. Partition the population into **cohorts** of equal E1.
4. Within each cohort, restrict the graph to cohort members and compute causal
   depth by the longest-path definition in §4.2 (E2). No traversal order can
   affect the result.
5. Events in different cohorts need no depth comparison: E1 already separates
   them, and step 2 has proven E1 consistent with causality.

### 5.6 Stage 6 — Total ordering

1. Sort the population ascending under the comparator in §4.5.
2. The sort must be treated as a total order. Reliance on sort stability is
   prohibited, because equal keys cannot legitimately exist: if two keys compare
   equal, stop and raise the duplicate-identity failure (§13, F-06). Never
   resolve it with an additional discriminator.
3. Assign `ordinal = 1..N` in that sequence. The ordinal is valid only within
   this replay version.

### 5.7 Stage 7 — Fold and fingerprint

1. Serialize the ordered key list canonically under N-04/N-05 and produce the
   **ordered-input fingerprint** with the declared digest and version.
2. Apply the method state as a fold over the sequence, in ECC order, using the
   frozen Costing Specification formulas. ECC supplies order; it computes no
   cost.
3. Evaluate eligibility rules — availability, negative-inventory policy,
   Specific-ID identity eligibility, period admissibility — **in ECC order**,
   never before it.
4. Produce the method-state fingerprint and the reconciliation evidence required
   by the Reconciliation Contract §10.

### 5.8 Stage 8 — Certification and promotion

1. Compare incremental and full-rebuild results where an incremental path was
   used (§6.6 makes this comparison meaningful rather than decorative).
2. Publish nothing until the version is complete and certified; retain the prior
   current version until atomic promotion.
3. Record the boundary, `V`, both fingerprints, the first affected ECC key, and
   the triggering event.
4. A late event never mutates this version; it requests a successor (§6.7).

### 5.9 Worked derivation trace

Population: three events in partition `CO-1 / VS-1`, all at
`2026-03-05T08:00:00.000000Z`, no causal edges, ranks from the illustrative
policy version used throughout §7–§11 (increase 20, decrease 40; source-type
ranks: goods receipt 200, sales issue 400).

| Event | E1 | E2 | E3 | E4 | E5 | E6 | E7 | E8 | E9 | E10 |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |
| `R1` GR-0000007 line 1 | 08:00:00.000000Z | 0 | 20 | 200 | `GR-0000007` | 1 | 10 | 1 | 1 | `…7/L1/OWN/1/1` |
| `R2` GR-0000012 line 1 | 08:00:00.000000Z | 0 | 20 | 200 | `GR-0000012` | 1 | 10 | 1 | 1 | `…12/L1/OWN/1/1` |
| `I1` DR-0000031 line 1 | 08:00:00.000000Z | 0 | 40 | 400 | `DR-0000031` | 1 | 10 | 1 | 1 | `…31/L1/ISS/1/1` |

Derivation: E1 ties all three. E2 ties (no edges). E3 separates `{R1,R2}` from
`I1`. Within `{R1,R2}`, E4 ties, and **E5 decides**: `GR-0000007 ≺ GR-0000012`.

`ECC = (1) R1, (2) R2, (3) I1`. The deciding component for each adjacent pair is
recorded: `R1≺R2` by E5; `R2≺I1` by E3. That per-pair record is the audit
drill-through required by ADR-C01 §3.4.

---

## 6. Replay Rules

### 6.1 Notation

Let `S` be the set of events selected by stage 4 for one partition and boundary,
`V` the version vector, `key_V(e)` the ECC sort key of `e` under `V`, and
`ECC_V(S)` the ascending enumeration under `≺`.

### 6.2 Theorem 1 — Uniqueness of the enumeration

`≺` is a strict total order on `S` (§4.5, given V-14). A finite set totally
ordered by `≺` has exactly one strictly increasing enumeration.

*Proof.* Suppose two enumerations `σ ≠ τ` of `S` are both strictly increasing.
Let `i` be the least index where they differ, with `σ(i) = x`, `τ(i) = y`,
`x ≠ y`. By totality either `x ≺ y` or `y ≺ x`; assume `x ≺ y`. Since `σ` and
`τ` agree below `i`, `x` appears in `τ` at some index `j > i`. Then `τ` contains
`y` at `i` and `x` at `j > i` with `x ≺ y`, contradicting that `τ` is strictly
increasing. The symmetric case is identical. Hence `σ = τ`. ∎

### 6.3 Theorem 2 — Schedule independence

`ECC_V(S)` is a function of `(S, V)` only.

*Proof.* By §4.2 and §4.3, every component of `key_V(e)` is either (i) source
evidence established before Inventory admission, (ii) a rank resolved from a
declared policy version, or (iii) causal depth, which by §4.2 is a function of
the declared edge set of `S` restricted to a cohort. None of the three reads a
transaction id, clock, allocator, lock outcome, row location, or commit order —
§2.2 prohibits exactly those, and V-02 tests for them. Therefore `key_V` is
invariant under any physical execution schedule. `S` is a set, so it carries no
order to leak. By Theorem 1 the enumeration is unique given `key_V`. Hence any
two executions — different arrival order, different lock winners, different
isolation levels, different node, different database — yield the same
`ECC_V(S)`, and therefore the same ordered-input fingerprint. ∎

*Corollary (independent reconstruction).* Two databases holding the same
immutable facts and the same `V` reach identical ECC and identical method-state
fingerprints, which is the property ADR-C01 §11.3 requires and the property the
evidence gate proved absent.

### 6.4 Lemma 1 — Causal depth of an existing event is invariant under insertion

*Proof.* An edge `u → v` exists only because `v` declared `u` as a predecessor
at `v`'s admission (V-08). An admitted event's declarations are immutable
(P-05). Let `S' = S ∪ {w}`. Any new edge in `S'` is incident to `w`, and — since
`w` can only name predecessors that already exist — is directed *into* `w`. So
for any `e ∈ S`, the set of predecessors of `e` is unchanged, and inductively its
longest-path depth within its cohort is unchanged. ∎

### 6.5 Theorem 3 — Insertion monotonicity

For `S' = S ∪ {w}` under the same `V`, and for all `x, y ∈ S`:
`x ≺ y in ECC_V(S)` if and only if `x ≺ y in ECC_V(S')`.

*Proof.* `key_V(x)` and `key_V(y)` are immutable (P-05) except for their E2
component, which Lemma 1 shows is unchanged. The comparator is a pure function
of the two keys. Hence the pairwise result is unchanged. ∎

*Consequences.* A backdated admission, a correction, or any late arrival can
**only insert** into the economic sequence. It can never transpose two events
that a prior certified version already ordered. Absolute ordinals shift; relative
economic history does not. This is what makes ADR-C01 §11.4's "successor replay
version" a bounded, explainable operation rather than a rewrite.

### 6.6 Theorem 4 — Prefix stability, and the legality of incremental replay

Let `K` be the minimum ECC key among events in `S' \ S`, and let
`P = { e ∈ S' : key_V(e) ≺ K }`. Then `ECC_V(S')` restricted to `P` equals
`ECC_V(S)` restricted to `P`, and the method state after folding `P` is
identical in both versions.

*Proof.* `P ⊆ S`, and by Theorem 3 the relative order inside `P` is unchanged.
No element of `S' \ S` precedes any element of `P`, by definition of `K`. Method
state is a fold: `state(n) = f(state(n-1), e_n)` with `f` a pure function of the
prior state and the event's own immutable facts and resolved policy versions.
Equal prefix sequences therefore give equal `state(|P|)`. ∎

*Consequences.* Incremental replay from a checkpoint at the last ordinal before
`K` is not an optimization of unclear correctness — it is provably equal to full
replay. ADR-C01 §11.3(6) still requires the comparison to be executed, because
the proof holds only if the implementation's `f` truly depends on nothing else.
The comparison is the test of that premise.

*What incremental replay may and may not shorten.* It reuses the **fold** over
`P`; it does not shorten the **ordering population**. Theorem 4 compares
`ECC_V(S')` and `ECC_V(S)` — both enumerations of complete populations — so the
saving is in re-applying method state, not in selecting fewer events to order.
An implementation that instead narrows its start bound to `K` must satisfy
§5.4(5); where it cannot, it orders the full population and folds from the
checkpoint. Reusing a checkpoint is legitimate; ordering a truncated cohort is
not.

### 6.7 Late events

1. A late event is one admitted after a replay version was certified. Lateness is
   a fact about Accepted Event Chronology, never about ECC.
2. **A late event is not necessarily a later event.** Its ECC key may precede
   already-applied events for any reason — an earlier instant, a lower effect
   rank at the same instant, a lower document key, a lower line ordinal. All
   cases are handled identically: compute `K`, request a successor version from
   `K`, replay forward.
3. Until promotion, reports either use the prior certified version with a
   disclosed late-event exception, or fail closed where current certification is
   required.
4. A prior replay version is never mutated and never deleted.

### 6.8 Counterfactual replay

A closed-period correction is `counterfactual_only`. ECC computes it in a replay
version explicitly flagged non-certifying for the closed range: the correction is
placed at its anchor to measure the exact delta, the certified closed-period ECC
and its journals are untouched, and the Accounting Policy/Period owner decides
the presentation under the frozen IA-3 rules. A counterfactual version may never
be promoted to current for the closed range.

### 6.9 Cross-scope replay ordering

A same-company transfer creates a dependency from a source-partition issue result
to a destination-partition receipt input. Rules:

1. Partitions are never merged and never share an ECC.
2. Build a partition-level dependency graph from transfer edges; replay
   partitions in a topological order of that graph.
3. A cycle in the partition graph fails closed.
4. Lock order for method state follows the frozen blueprint order (company /
   source occurrence, valuation scopes in stable key order, method state, source
   match rows, Posting source lock). Lock order affects deadlock avoidance only;
   by Theorem 2 it cannot affect ECC.

### 6.10 Replay determinism checklist

| # | Requirement |
| ---: | --- |
| R-01 | Boundary fully declared, including `V` and both economic bound keys. |
| R-02 | Population selected only by partition, watermark, and key bounds. |
| R-03 | Every component resolved from retained immutable evidence, never re-derived from current master data. |
| R-04 | Causal graph validated before ordering. |
| R-05 | Ordering by total comparator; equal keys raise a failure, never a tie-break. |
| R-06 | Ordinals assigned only after the complete sort. |
| R-07 | Ordered-input fingerprint produced and compared to any prior computation of the same boundary. |
| R-08 | Eligibility evaluated in ECC order. |
| R-09 | Incremental result compared to full rebuild. |
| R-10 | Nothing published before certification; promotion atomic; predecessor retained. |

---

## 7. FIFO Examples

Shared setup for §7–§11: company `CO-1`, item `ITEM-A`, valuation scope `VS-1`
(company scope, PHP), quantity scale 2, valuation amounts 8 decimals, GL basis 2
decimals. Illustrative policy version ranks: opening 10, increase 20, value-only
30, decrease 40, allowance 50; source-type ranks: goods receipt 200, sales return
receipt 220, landed cost 300, sales issue 400, goods issue 410, transfer issue
420. All amounts are exact.

### 7.1 F1 — The C-01 case: equal-instant receipt and issue

Facts, both effective `2026-03-05T08:00:00.000000Z`, no causal edge:

- `R1` — goods receipt GR-0000007 line 1, +10.00 @ 100.00, cost 1,000.00.
- `I1` — sales issue DR-0000031 line 1, −6.00.

Deciding component: **E3** (20 before 40). `ECC = R1, I1` — in both submission
orders.

| Submission order | Accepted chronology | ECC | FIFO result |
| --- | --- | --- | --- |
| `R1` then `I1` | 1: `R1`, 2: `I1` | 1: `R1`, 2: `I1` | Layer L1 = 10.00 @ 100.00; issue consumes 6.00 → COGS 600.00; L1 remaining 4.00 / 400.00 |
| `I1` then `R1` | 1: `I1`, 2: `R1` | 1: `R1`, 2: `I1` | Identical |

Rejected Model A (accepted order as costing order) under the second submission
would reach an issue into empty stock: rejection, or a provisional negative layer
at a configured provisional cost, a settlement obligation, a variance, and a
period-close blocker. ECC removes that divergence entirely — which is exactly the
material consequence the evidence gate demonstrated.

### 7.2 F2 — Two equal-instant receipts with different costs, then an issue

All at `2026-03-06T09:30:00.000000Z`, no edges:

- `R1` — GR-0000007 line 1, +10.00 @ 100.00 (1,000.00).
- `R2` — GR-0000012 line 1, +10.00 @ 130.00 (1,300.00).
- `I1` — DR-0000031 line 1, −12.00.

Derivation: E1, E2, E3, E4 tie for `{R1,R2}`; **E5** decides
(`GR-0000007 ≺ GR-0000012`). `I1` follows by **E3**.

`ECC = R1, R2, I1`. Consumption: 10.00 from L1 @ 100.00 = 1,000.00, then 2.00
from L2 @ 130.00 = 260.00 → **COGS 1,260.00**; ending inventory 8.00 @ 130.00 =
**1,040.00**.

| Hypothetical order | COGS | Ending inventory |
| --- | ---: | ---: |
| ECC (`R1, R2, I1`) | 1,260.00 | 1,040.00 |
| `R2, R1, I1` (lock-order accident) | 1,500.00 | 800.00 |

The 240.00 difference is a real profit difference produced by nothing but
sequence. E5 must therefore be a governed source sequence, which is why ADR-C01
forbids substituting a display number or an insertion id.

### 7.3 F3 — Same document, lines submitted in reverse

GR-0000021, both lines at `2026-03-07T14:00:00.000000Z`:

- line 1: +5.00 @ 90.00 (450.00)
- line 2: +5.00 @ 95.00 (475.00)

then `I1` — goods issue GI-0000004 line 1, −7.00, same instant.

Derivation: E1–E5 tie for the two receipt lines; **E6** decides (1 ≺ 2). `I1`
follows by E3.

`ECC = GR-21/L1, GR-21/L2, I1`. Consumption: 5.00 @ 90.00 = 450.00 + 2.00 @ 95.00
= 190.00 → **issue cost 640.00**; ending 3.00 @ 95.00 = **285.00**.

The gate proved the current implementation retains line 2 first when line 2 is
submitted first, which would give 5.00 @ 95.00 + 2.00 @ 90.00 = 655.00 with
ending 3.00 @ 90.00 = 270.00 → a 15.00 misstatement of the issue destination and
of ending inventory, from one reversed keystroke order. Total cost is 925.00
either way; E6 decides where it lands.

### 7.4 F4 — Partial occurrences of one line, submitted in reverse

RR-0000009 line 1, confirmed in two governed partial occurrences at
`2026-03-08T10:00:00.000000Z`, both +@ 100.00:

- occurrence 1: +4.00 (400.00)
- occurrence 2: +6.00 (600.00)

Derivation: E1–E7 tie; **E8** decides (1 ≺ 2). `ECC = occ 1, occ 2`.

Aggregate quantity and value are equal under either order, so a naive review
would call the order immaterial. It is not:

- the two layers have different identities, different ancestry, and different
  queue positions, and the FIFO allocation fingerprint differs;
- a later landed-cost correction anchored to **occurrence 1 only** (say +40.00)
  raises occurrence 1's layer to 4.00 / 440.00 @ 110.00. A subsequent issue of
  5.00 then costs 4.00 @ 110.00 + 1.00 @ 100.00 = **540.00** under ECC, but
  5.00 @ 100.00 = **500.00** under the inverted order, which consumes occurrence
  2 first. The whole 40.00 correction is expensed in one order and remains
  capitalized in the other — from an order that looked immaterial because the
  aggregate was equal;
- ADR-C01 §6.6 requires a new explicit occurrence ordinal precisely so this
  ancestry stays addressable.

### 7.5 F5 — Causality outranking the convention

At `2026-03-09T11:00:00.000000Z`, one scope-crossing transfer occurrence produces
a transfer issue in `VS-1` and the dependent receipt evidence in `VS-2`
(different partition). Inside `VS-1`, an independent purchase receipt `R3`
(+5.00 @ 120.00) shares the instant.

Within partition `VS-1`: the transfer issue has effect rank 40 and `R3` has 20,
and there is no causal edge between them, so `ECC(VS-1) = R3, transfer issue`.
The transfer's cross-partition dependency does not change `VS-1`'s internal
order; it orders the *replay of `VS-2` after `VS-1`* (§6.9), so the destination
receipt consumes the source issue's computed carrying value. Acquisition ancestry
and exact carrying value are preserved per the frozen transfer policy; the
destination's availability still begins at its own receipt occurrence.

### 7.6 F6 — Sales return does not regain its queue position

`R1` 2026-03-01 +10.00 @ 100.00; `I1` 2026-03-10 −10.00 → COGS 1,000.00, queue
empty. `R4` 2026-03-15 receipt +6.00 @ 145.00. Accepted sales return `RT1` on
2026-03-20 restores 4.00 at the latest corrected cost assigned to `I1` (100.00).

`ECC = R1, I1, R4, RT1`. `RT1` creates a **return-acceptance-dated** layer of
4.00 / 400.00 with ancestry to `I1` and `R1`; it does not re-enter ahead of `R4`.
A later issue of 7.00 consumes 6.00 @ 145.00 (870.00) + 1.00 @ 100.00 (100.00) =
970.00. Ending 3.00 / 300.00. This is the frozen H-08 rule expressed as an ECC
key rather than as prose.

---

## 8. Moving WAC Examples

### 8.1 W1 — Equal-instant inbound group before an equal-instant issue

Pool starts `(0.00, 0.00000000)`. All at `2026-04-02T08:00:00.000000Z`:

- `R1` GR-0000007 +10.00, cost 1,000.00
- `R2` GR-0000012 +10.00, cost 1,300.00
- `I1` DR-0000031 −12.00

`ECC = R1, R2, I1` (E5 then E3).

| Step | Pool quantity | Pool value | Derived average |
| --- | ---: | ---: | ---: |
| after `R1` | 10.00 | 1,000.00000000 | 100.000000000000 |
| after `R2` | 20.00 | 2,300.00000000 | 115.000000000000 |
| `I1` cost = 12.00 × 2,300.00 / 20.00 | — | — | — |
| after `I1` | 8.00 | 920.00000000 | 115.000000000000 |

Issue cost **1,380.00**, computed from the authoritative extended pool value, not
from a rounded rate.

**Why permuting the inbound group cannot change the issue.** Suppose the group
`{R1, R2}` is permuted to `R2, R1`: pool becomes `(10.00, 1,300.00)` then
`(20.00, 2,300.00)`. Because pool quantity and value accumulate by exact
addition, and addition is commutative and associative over exact fixed-point
values with no intermediate rounding, the aggregate immediately before the first
lower-ranked event is invariant under permutation of the group. Hence the issue
cost is invariant. This is ADR-C01 §9.3 proved rather than asserted.

**Why the order still must be deterministic.** The *aggregate* commutes, but the
pool **version chain** does not: `avg 100.000000000000` then
`avg 115.000000000000` is a different certified history from
`avg 130.000000000000` then `avg 115.000000000000`. Pool versions are audit
evidence and are fingerprinted (Layer Lifecycle §4.2, Reconciliation §10), so a
nondeterministic inbound order would produce two different certified histories
for one set of facts. Commutativity of the aggregate is not permission for
arbitrary order.

### 8.2 W2 — Equal-instant issue that would otherwise create a deficit

Pool `(0.00, 0.00000000)`; at one instant, `I1` −6.00 and `R1` +10.00 @ 100.00.

`ECC = R1, I1` by E3. Pool `(10.00, 1,000.00)` → issue cost 600.00 → pool
`(4.00, 400.00)`, average 100.000000000000. No deficit, no provisional cost, no
variance, no close blocker.

Under accepted-order costing with `I1` admitted first, WAC would enter `deficit`
status with a provisional cost from the last positive pool average — and there is
none, so the issue would require a configured provisional item cost or be
rejected outright. Two databases could legitimately reach opposite outcomes. ECC
makes the outcome a policy, not a race.

### 8.3 W3 — Backdated receipt into an existing chain

Certified version `v1` (all open period, all distinct instants):

| ECC | Event | Effect | Pool after | Average |
| ---: | --- | --- | --- | ---: |
| 1 | `e1` 2026-03-01 receipt +10.00 @ 100.00 | +1,000.00 | 10.00 / 1,000.00 | 100.000000000000 |
| 2 | `e2` 2026-03-10 issue −4.00 | cost 400.00 | 6.00 / 600.00 | 100.000000000000 |
| 3 | `e3` 2026-03-20 receipt +10.00 @ 120.00 | +1,200.00 | 16.00 / 1,800.00 | 112.500000000000 |
| 4 | `e4` 2026-03-25 issue −8.00 | cost 900.00 | 8.00 / 900.00 | 112.500000000000 |

On 2026-03-28 a backdated receipt `e5` is admitted, effective 2026-03-05,
+10.00 @ 140.00 (1,400.00). Accepted position 5; ECC key places it between `e1`
and `e2`. Successor version `v2` replays from `K = key(e5)`; by Theorem 4 the
prefix `{e1}` is reused.

| ECC | Event | Cost | Pool after | Average |
| ---: | --- | ---: | --- | ---: |
| 1 | `e1` | +1,000.00 | 10.00 / 1,000.00 | 100.000000000000 |
| 2 | `e5` | +1,400.00 | 20.00 / 2,400.00 | 120.000000000000 |
| 3 | `e2` −4.00 | 480.00 | 16.00 / 1,920.00 | 120.000000000000 |
| 4 | `e3` | +1,200.00 | 26.00 / 3,120.00 | 120.000000000000 |
| 5 | `e4` −8.00 | 960.00 | 18.00 / 2,160.00 | 120.000000000000 |

Exact deltas: `e2` issue cost +80.00; `e4` issue cost +60.00; ending pool value
+1,260.00; ending quantity +10.00. Reconciliation:
`1,400.00 = 1,260.00 + 80.00 + 60.00`. Posted journals for `e2` and `e4` are
untouched; the 140.00 of issue-cost delta is routed through the correction
destination bridge, and the 1,260.00 remains in inventory.

`e5` illustrates the dual chronology exactly: accepted position 5, ECC position
2, both permanent.

### 8.4 W4 — Late event with an equal instant, not an earlier one

`v1` contains `e6` — goods receipt GR-0000050, effective
`2026-04-10T07:00:00.000000Z`, applied and certified. A new event `e7` — goods
receipt GR-0000031, same instant, same effect rank — is admitted afterwards.

E1, E2, E3, E4 tie; **E5** places `GR-0000031 ≺ GR-0000050`. So the *later
admitted* event is *economically earlier*. This is an ordinary successor replay
from `K = key(e7)`, not an append. Any implementation that treats "arrived after
the watermark" as "belongs at the end" is non-conformant even when timestamps
are distinct.

---

## 9. Specific-ID Examples

### 9.1 S1 — Chronology never chooses which identity supplies cost

At one instant, serial receipts `SN-1` (@ 8,000.00) and `SN-2` (@ 9,500.00) are
received on GR-0000060 lines 1 and 2. `ECC` orders them by E6 (line 1 then line
2). A later issue names **`SN-2`**.

The issue's carrying value is `SN-2`'s remaining value, 9,500.00. The ECC order
of the two receipts is retained for replay and audit but has no influence on
which identity supplies cost. That is ADR-C01 §10.8: the canonical order remains
available, and remains powerless over identity.

### 9.2 S2 — Causality at one instant, and identity that cannot be invented

At `2026-05-04T13:00:00.000000Z`, serial `SN-9` is received on GR-0000071 line 1
and issued on DR-0000088 line 1 in the same instant. The issue declares the
receipt as predecessor (identity ancestry).

Both **E2** (causal depth 0 then 1) and **E3** (20 then 40) place the receipt
first; E2 decides, and the audit records E2 as the deciding component. If the
issue's declared identity has no eligible, owned, available receipt in the
population, no component of ECC can repair it: the economic application is
rejected (ADR-C01 §10.1). Specific-ID inventory never goes negative.

### 9.3 S3 — Competing claims to one serial

Two independent issues at one instant both name `SN-9`, with no causal
relationship. ECC will order them — E5 or a lower component will separate the
documents — but ordering is not permission. The first application consumes the
identity and the second finds no eligible identity, so it is **rejected**. A
tie-break cannot legitimize both claims (ADR-C01 §10.2), and the exception is
reported rather than auto-resolved.

### 9.4 S4 — Partial lot occurrences, and which destination absorbs the residual

Lot `L-77`: 3.00 units, authoritative value 100.00000000, fully issued at one
instant through three partial occurrences of one source line, to three different
projects:

- occurrence 1: −1.00, project A
- occurrence 2: −1.00, project B
- occurrence 3: −1.00, project C

Derivation: E1–E7 tie for all three; **E8** decides.
`ECC = occ 1, occ 2, occ 3`.

Each partial issue takes its deterministic proportional share, and the **final**
issue takes the exact remaining valuation and GL-basis amounts, so quantity and
value reach zero together:

| ECC | Occurrence | Valuation share | GL-basis charge |
| ---: | --- | ---: | ---: |
| 1 | occ 1 (project A) | 33.33333333 | 33.33 |
| 2 | occ 2 (project B) | 33.33333333 | 33.33 |
| 3 | occ 3 (project C) | 33.33333334 — exact remaining | 33.34 |

The total is 100.00 under any order, but the order decides **which project is
charged 33.34** and which allocation is the closing one. The frozen residual
policy breaks its largest-remainder tie by the stable source-line/order key — and
that key is the ECC key. A nondeterministic order therefore makes the residual's
GL destination and dimension set nondeterministic, in a system whose
reconciliation contract treats a residual as evidence rather than as a tolerance.
"Same total" is never a defence for nondeterministic order.

---

## 10. Backdating Examples

### 10.1 B1 — FIFO backdated receipt ahead of an exhausting issue

`v1`: `e1` 2026-04-02 receipt +10.00 @ 50.00 → L1 (10.00 / 500.00);
`e2` 2026-04-06 issue −10.00 → consumes L1 fully, cost **500.00**, inventory
0.00.

Backdated `e3`, effective 2026-04-01, +6.00 @ 40.00 (240.00), admitted
2026-04-09.

`v2` ECC: `e3, e1, e2` — `e3` first by **E1**. Replay from `K = key(e3)`, which
is the new minimum, so the whole partition is replayed.

`e2` now consumes 6.00 @ 40.00 (240.00) + 4.00 @ 50.00 (200.00) = **440.00**.
L1 retains 6.00 / 300.00.

Deltas: issue cost −60.00; ending inventory +300.00. Reconciliation:
`240.00 = 300.00 − 60.00`. The original exhausted layer state at the `v1`
cut-off is retained as evidence; nothing is rewritten in place, per the frozen
Layer Lifecycle rules.

### 10.2 B2 — Backdated issue, and what ECC refuses to do

A backdated issue effective 2026-04-01 is admitted for a partition whose first
receipt is effective 2026-04-02. ECC places the issue **first**, by E1. That is
the correct economic order, and it produces a genuine deficit at that position.

ECC does not move the issue behind the receipt to make it succeed, and the
same-time convention does not apply because the instants are not equal
(ADR-C01 §6.4 final paragraph). The negative-inventory policy — prohibited by
default — then governs: rejection, or an explicit open-period provisional
deficit that must settle before close. Ordering and eligibility remain separate
decisions, evaluated in that order.

### 10.3 B3 — Backdating across a certified cut-off in an open period

A backdated event whose key precedes a *certified* replay version's boundary in
an open period creates a successor version, not an amendment (§6.7). Until
promotion:

- valuation reports either cite the prior certified version with a disclosed
  late-event exception, or fail closed where current certification is required;
- period close is blocked while the required replay, deficit settlement,
  Posting, or reconciliation exception is unresolved.

### 10.4 B4 — Backdating into a closed period

A backdated event whose economic instant falls in a closed period is
`counterfactual_only`. ECC computes a non-certifying counterfactual replay to
measure the exact quantity and value effect at the correct anchor; the certified
closed-period ECC, method state, and journals are untouched. The Accounting
Policy/Period owner classifies prior-period error versus estimate change and
selects the retrospective, adjusting, or prospective treatment. ECC supplies the
measurement; it never selects the accounting treatment and never inserts into a
closed certified stream.

### 10.5 B5 — Backdating cannot fabricate FIFO eligibility

A receipt effective 2026-04-20 can never become eligible for an issue effective
2026-04-15, in any version, because E1 dominates the comparator and V-05 rejects
any causal edge that would contradict it. Every FIFO consequence in ADR-C01 §8.5
follows directly from the tuple's shape rather than from a separate rule that
could be forgotten.

---

## 11. Correction Examples

### 11.1 C1 — Anchored landed-cost correction

`e1` 2026-06-01 receipt +10.00 @ 100.00 (1,000.00) → L1. `e2` 2026-06-05 issue
−6.00 → cost **600.00**; L1 remaining 4.00 / 400.00. Certified as `v1`.

Landed cost `k1` of 150.00 is approved on 2026-06-20 and is registered as
`anchored` to `e1`.

`k1`'s key = `key(e1)` with `X1 = 1`, `X2 =` its business effective instant,
`X3 =` its approval instant, `X4 =` its identity. It therefore sorts immediately
after `e1` and before `e2`, with no special-case insertion logic.

`v2` ECC: `e1, k1, e2`.

| Result | `v1` | `v2` | Delta |
| --- | ---: | ---: | ---: |
| L1 adjusted value for 10.00 units | 1,000.00 | 1,150.00 | +150.00 |
| `e2` issue cost (6.00 units) | 600.00 | 690.00 | +90.00 |
| Ending inventory (4.00 units) | 400.00 | 460.00 | +60.00 |

`150.00 = 90.00 + 60.00` exactly. The +90.00 flows to the correction destination
bridge for the original issue's destination; the +60.00 stays capitalized. The
original layer fact and the posted `e2` journal are untouched; `v1` remains
citable.

### 11.2 C2 — Correction chain

`k2` reduces the landed cost by 50.00, declared as a correction **of `k1`**
(chain depth 2, same anchor `e1`).

`v3` ECC: `e1, k1, k2, e2` — ordered inside the anchor by **X1**.

Layer value 1,100.00 for 10.00 units → 110.00 per unit. `e2` recomputes to
660.00 (−30.00 versus `v2`); ending 4.00 / 440.00 (−20.00). Net against `v1`:
`+100.00 = +60.00 + 40.00`. The chain is non-branching, so no commutativity
proof is required and no ambiguity exists.

### 11.3 C3 — Correction fork fails closed

Two corrections `k3` and `k4` are both declared directly against `e1`, neither
naming the other as predecessor, and the registry holds no commutativity proof
for their combination.

Both would carry `X1 = 1` on the same anchor. ECC **does not** order them by X2,
X3, or X4 in this situation: V-19 rejects the fork before ordering. The
partition's replay fails closed, the scope cannot be certified, and the exception
names both corrections and the required remedy — an explicit predecessor chain,
or a registered proof that their exact deltas commute. This is ADR-C01 §6.5's
prohibition, implemented as a validation rule rather than as an ordering
heuristic.

If a registered commutativity proof *does* exist for the pair, they are ordered
by `(X2, X3, X4)`, which is total because X4 is unique — and the proof is what
makes the resulting deltas order-insensitive.

### 11.4 C4 — Reversal is an independent event, not an anchored correction

`e1` receipt is reversed by `r1` at its own governed economic instant
(2026-06-25). `r1`'s placement class is `independent`: it receives an ordinary
E1–E10 key at its own instant, with base-fact sentinels in X1–X4, and a declared
reversal link to `e1`.

Two paths, per the frozen policy:

- **No intervening dependent cost event and frozen method policy permits exact
  restoration:** the prior state is restored exactly, and both events remain
  visible in the ECC with the restoration recorded.
- **Otherwise:** `r1` is processed as an ordinary inverse event at ECC position
  by instant, and replay determines the downstream deltas.

In neither path does `r1` inherit `e1`'s key. A reversal that anchored to its
target would silently claim `e1`'s economic instant, which would misstate the
period of the reversal.

### 11.5 C5 — Correction of a correction target that is not in the population

An anchored correction is selected for replay but its root target lies outside
the declared economic bounds or watermark. ECC does **not** widen the population
to reach the target, and does not place the correction at its own instant as a
fallback. Stage 4 rejects the replay (F-09). The remedy is a boundary that
includes the target, which keeps the delta computation meaningful.

---

## 12. Validation Rules

Every rule is fail-closed. "Reject application" means the event does not become
economically applied and remains pending costing or is rejected outright per
§13; "reject replay" means the partition produces no version.

### 12.1 Component presence and form

| # | Rule | Stage |
| --- | --- | --- |
| V-01 | Every primary component E1–E10 is present, non-null, and within its declared domain. | 2, 4 |
| V-02 | No component is functionally dependent on a prohibited input in §2.2. A component that varies across two admissions of identical source evidence is non-conformant by definition. | 2, certification |
| V-03 | E1 is normalized per N-01/N-02, with an unambiguous offset and a declared source precision. | 2 |
| V-04 | Every text or identity component is canonicalized per N-04/N-05/N-06 and compared without locale collation. | 2, 6 |
| V-05 | Ranks E3, E4, E7 exist in the declared event-order policy version, and E3 matches the event's classified effect and quantity/value direction. | 2 |
| V-06 | E5 is produced by exactly one registry-declared algorithm for the source type, and is unique per document within the company. | 2 |
| V-07 | E6, E8, E9 are positive integers, stable, and unique at their declared grain. | 2 |
| V-08 | Every causal edge is declared by the dependent event at its own admission and names an already-admitted or same-occurrence predecessor. No edge may be added to an admitted event later. | 2, 3 |
| V-09 | Every numeric ECC evidence value is fixed-point; binary floating point appears nowhere in ECC derivation. | 2 |
| V-32 | The occurrence event plan producing E9 is a pure function of the occurrence's immutable payload and the registry rule at its declared version. A plan that varies with method state, availability, concurrent occurrences, or admission-time master data is an F-04 defect. | 2, certification |
| V-33 | A derived allocation carries its parent line's E6 and is ordered after the parent by E2, E7, or E9 under the registry rule. A synthetic, fractional, or offset line ordinal is prohibited. | 2 |

### 12.2 Registry, policy, and scope

| # | Rule | Stage |
| --- | --- | --- |
| V-10 | The source type is registered, production-enabled for the company and profile, and its registry rule defines event effects, economic-time authority, document-order-key algorithm, line-order authority, transition set, occurrence semantics, same-time class, and correction placement class. An incomplete rule makes the type unavailable. | 2 |
| V-11 | The valuation-scope key resolves to exactly one partition; the scope version is retained as a dependency of record; a scope re-version under one key never splits the stream. | 1 |
| V-12 | Every policy version required by `V` is resolved at admission and retained immutably with the event. | 2 |
| V-13 | The occurrence is atomic: every event of the occurrence validates, or the occurrence is rejected whole. | 3 |

### 12.3 Population and uniqueness

| # | Rule | Stage |
| --- | --- | --- |
| V-14 | E10 is unique within the partition. Two distinct facts claiming one identity reject both applications and block certification of the stream. | 3, 4 |
| V-15 | No two keys in a replay population compare equal. An equal comparison is a defect, never a tie to break. | 6 |
| V-16 | An idempotent retry carrying an identical authoritative payload returns the original accepted occurrence and the original ECC identity; the same idempotency key with a materially different payload is rejected. | 3 |
| V-17 | Every event's version vector is compatible with the boundary's declared `V`. | 4 |
| V-18 | The population contains the root target of every anchored correction it contains. | 4 |

### 12.4 Causality and corrections

| # | Rule | Stage |
| --- | --- | --- |
| V-19 | The anchored correction graph is a non-branching chain per target, unless a registered commutativity proof covers the fork. An unresolved fork rejects replay. | 4, 5 |
| V-20 | The causal graph is acyclic, single-company, and complete; every named predecessor is present. | 5 |
| V-21 | Causal evidence is consistent with E1 across cohorts: a predecessor's instant may not exceed its dependent's. Anchored corrections are excluded because anchoring, not an edge, places them. | 5 |
| V-22 | X1 is exactly one greater than the declared parent's depth; no correction cycle; a correction's classification (open-period, closed-period error, estimate change) is declared and consistent with its placement class. | 2, 5 |

### 12.5 Replay and certification

| # | Rule | Stage |
| --- | --- | --- |
| V-23 | The boundary declares partition, watermark, both economic bound keys, predecessor version, `V`, and algorithm version. | 4 |
| V-24 | Ordinals are assigned only after the complete sort, and are cited only with their replay version. | 6 |
| V-25 | The ordered-input fingerprint is reproduced identically on recomputation of the same boundary. | 7 |
| V-26 | Incremental and full-rebuild results are compared and equal. | 8 |
| V-27 | The cross-partition dependency graph is acyclic and replay follows a topological order of it. | 6.9 |
| V-28 | Nothing is published before certification; promotion is atomic; the predecessor version is retained. | 8 |
| V-29 | A permutation self-test — admitting the same authoritative command set under at least two independent schedules, including a randomized one, on independently reset databases — produces identical ordered-input and method-state fingerprints. | certification |
| V-30 | An eligibility rule is never evaluated before ordering, and never used to alter an order. | 7 |
| V-31 | Both economic bounds are complete fourteen-component keys and are inclusive; the start bound truncates no E1 cohort, no declared predecessor, and no anchored-correction root target (§5.4(5)). | 4 |
| V-34 | A cross-environment, cross-reset, or cross-schedule equality claim is stated over the complete admitted fact set, never over an accepted-through watermark ordinal, which is local to one accepted chronology (§3.4). | certification |
| V-35 | An order re-resolution satisfies §3.3: new immutable evidence under the target version, prior resolution retained, re-derivation only from retained source evidence, uniform `V` in the successor version, and explicit authorization. Implicit re-resolution triggered by a newer-version admission is prohibited. | 2, 4 |

Rules V-31 … V-35 were added by Amendment A1 and are numbered after V-30 so that
no existing rule identifier changes. They are grouped by subject above rather
than by number.

---

## 13. Failure Rules

| # | Failure | Trigger | Decision | Blast radius | Retriable? | Evidence retained |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | Missing economic time | E1 absent, ambiguous, or below declared precision | Reject economic application | The event | Yes, after the source supplies governed evidence | Rejection reason, source payload, registry version |
| F-02 | Unregistered or incomplete source type | V-10 fails | Source type unavailable to economic processing | Every event of that type | Only after the registry rule is approved | Attempted type, missing rule elements |
| F-03 | Missing source-order authority | E5, E6, E7, E8, or E9 unresolvable | Reject economic application | The occurrence | Yes, after the source supplies the ordinal or key | Which component, which source line |
| F-04 | Prohibited derivation input detected | V-02 fails | Reject the implementation as non-conformant; block certification | The engine, not one event | Not by retry — requires correction | The offending component and its dependency |
| F-05 | Causal defect | Cycle, cross-company edge, missing predecessor, or time contradiction | Reject economic application of the sub-graph and reject replay of the partition | The partition | Yes, after the source corrects the declaration | The full offending sub-graph |
| F-06 | Duplicate logical order identity | Two distinct facts share E10, or two keys compare equal | Reject both applications and block certification of the stream | The partition's certification | Only after a source-registry correction | Both identities and their evidence |
| F-07 | Idempotency conflict | Same key, materially different payload | Reject the request | The request | Yes, as a new occurrence with a new identity | Both payload fingerprints |
| F-08 | Correction fork | V-19 fails | Reject replay | The partition | Yes, after an explicit chain or registered proof | Both corrections and the target |
| F-09 | Unresolvable anchor | V-18 fails | Reject replay | The partition | Yes, with a boundary that includes the target | Correction identity, target identity, boundary |
| F-10 | Anchored correction into a closed certified range | Placement class conflicts with period state | Compute counterfactual only; never insert | The certified range is untouched | Not applicable | Counterfactual version marked non-certifying |
| F-11 | Version-vector incompatibility | V-17 fails | Reject replay | The partition | Yes, under a compatible boundary or after governed re-resolution | Both version vectors |
| F-12 | Fingerprint mismatch on recomputation | V-25 or V-26 fails | Reject the version; do not promote | The version | Yes, after the cause is identified | Both fingerprints and the first divergent ordinal |
| F-13 | Cross-partition cycle | V-27 fails | Reject replay of every partition in the cycle | The cycle | Yes, after the transfer evidence is corrected | The partition graph |
| F-14 | Pending-costing non-final result | An issue is admitted before a receipt it may depend on is visible (ADR-C01 §7.8) | Return a **non-final retriable** result; do not consume a new logical identity; do not permanently reject | The request only | Yes, by definition | Pending state, watermark, and the identity reserved |
| F-15 | Permutation divergence | V-29 fails | Block certification of the engine | The engine | Not by retry | Both schedules, both fingerprints, first divergent ordinal |

**What this table does not cover.** Every row above is an *ordering* failure.
Eligibility failures — a physical identity that does not exist, is not owned, is
already consumed, is claimed twice, or is duplicated across two receipts; an
unavailable quantity; a closed period — are **not** ECC failures and have no row
here. They are evaluated in ECC order at stage 7 (P-09, V-30) and rejected there
by the frozen Costing Specification and the negative-inventory and Specific-ID
rules (ADR-C01 §10). The distinction is deliberate and load-bearing: ECC always
produces an order for a valid key set, and that order is never evidence that the
ordered event is permitted. F-06 is the narrow exception, and it concerns
duplicate *logical order identity* (E10), never duplicate physical identity — a
serial received twice is an identity defect that ordering cannot see, cannot
repair, and must not mask (§9.2, §9.3).

Two rules govern every row above:

1. **No failure is ever resolved by choosing an order.** ECC has no fallback
   tie-break, no "best effort" order, and no arrival-order compromise.
2. **F-14 is not a rejection.** ADR-C01 §7.8 is explicit that an event may not
   be permanently rejected merely for losing a database schedule race. A
   pending, retriable, identity-preserving result is the required behaviour, and
   eligibility is settled at the governed processing watermark in canonical
   order.

---

## 14. Implementation Notes (Non-binding)

Nothing in this section authorizes work. It records design guidance so a future
authorized hardening phase does not have to re-derive it, and it names the
specific conformance gaps that the frozen evidence already establishes.

### 14.1 Conformance gaps in the current dormant IA-5 foundation

| Observation (established by the frozen evidence gate and the IA-5 evidence record) | ECC consequence |
| --- | --- |
| The IA-5 deterministic order index orders by scope, effective time, accounting date, occurrence date, then the per-scope accepted sequence, then occurrence and event sequences. | It contains no E3 effect rank, no E4 source-type rank, no E5 document order key, no E6 line ordinal, and no E7 transition rank, and it contains a component (§2.2) that ECC prohibits. It is an Accepted Event Chronology index, not an ECC index. |
| The per-scope sequence is allocated by updating a shared scope row, so the transaction reaching the row lock first receives the earlier value. | Sound as accepted-chronology evidence; prohibited as an ECC component. |
| Accepted-order uniqueness and the order index key on the valuation-scope **version** row. | Under ECC the partition is the scope **key**; an effective-dated re-version under one key must not split the stream or restart the accepted sequence. |
| Source-evidence fingerprints are caller-supplied 64-character hexadecimal values. | ECC fingerprints require a named, versioned canonicalization boundary (N-04/N-05) before they can serve as replay authority. |
| The only registered source type is certification-only and not production-enabled. | Correct and required: ECC forbids economic processing of a source type without a complete registry rule (V-10, F-02). |

### 14.2 Design guidance

1. **Treat the ECC key as evidence, not as a computation.** Resolve and retain
   every component at admission with its resolving policy version. Re-deriving a
   rank from current master data at replay time reintroduces exactly the
   nondeterminism ADR-C01 removed.
2. **Retain the accepted sequence.** It is permanent audit evidence
   (ADR-C01 §5(1), §5(10)). Do not delete it, do not repurpose it, and do not
   let any method-state object key on it as costing authority.
3. **Never sort with a locale collation.** Two environments with different
   collations would produce two economic orders from one fact set. Byte
   comparison is a correctness requirement, not a preference.
4. **Keep the comparator total, and treat an equal comparison as an error path.**
   A stable-sort fallback would hide F-06 rather than raise it.
5. **Compute causal depth only inside equal-instant cohorts.** The cohorts are
   small in practice, and cross-cohort causality is already validated against
   E1, so no global topological sort is needed.
6. **Exploit prefix stability, but prove it.** Checkpoint method state at
   certified ordinals and resume from the last ordinal before the first affected
   key; then run the full-rebuild comparison that V-26 requires. Theorem 4 holds
   only if the fold truly depends on nothing beyond the prefix.
7. **Make the deciding component auditable.** For each adjacent pair, record
   which component decided the order. ADR-C01 §3.4 requires ECC to be drillable
   to every ordering component and its interpreting policy version, and the
   §5.9 trace shows the minimum useful form.
8. **Locks stay where they belong.** Use the frozen lock order for method-state
   protection and deadlock avoidance. By Theorem 2 a lock cannot influence ECC —
   which means a lock also cannot be used to *repair* an ordering defect.
9. **Separate order re-resolution from re-costing.** A change to a dependency of
   record (§3.2) re-costs without re-ordering. Only an event-order, registry,
   scope-resolution, or correction-graph version change re-orders, and only
   through an explicit governed re-resolution replay.

### 14.3 Certification assets a future phase must run

Mapped to ADR-C01 §17's authorized evidence work, and to the examples in this
document:

| Asset | Proves | Reference |
| --- | --- | --- |
| Independent-reset sequential permutations | Submission order cannot change ECC | F1, F3, F4 |
| Two-session concurrency, delayed and explicitly held locks | Lock winner cannot change ECC | F1, W2, §6.3 |
| Randomized schedules across independent resets | Fingerprint equality (V-29) | §6.3 corollary |
| Rollback and retry | No durable identity consumed; retry reuses the key | F-14, V-16 |
| Same-document line order | E6 conformance | F3 |
| Partial-occurrence order | E8 conformance | F4, S4 |
| Same-instant receipt/issue FIFO and WAC consequence | E3 conformance and material divergence closed | F1, F2, W1, W2 |
| Backdate | Insertion monotonicity, exact delta reconciliation | B1, W3 |
| Late-but-earlier-key event | Lateness is not order | W4 |
| Correction chain and fork | Anchoring, X1 ordering, fail-closed fork | C1, C2, C3 |
| Reversal placement | Independent key, not anchored | C4 |
| Specific-ID identity precedence | Order cannot select identity; competing claims fail | S1, S2, S3 |
| Cross-scope transfer | Partition dependency ordering without merging | F5, §6.9 |
| Closed-period counterfactual | No insertion into a certified closed stream | B4, F-10 |
| Prohibited-input census | V-02 / F-04 conformance | §2.2 |

---

## 15. Future Migration Implications

This section states implications only. No migration, schema, index, function,
data change, or test is authorized here; ADR-C01 §17 and the reopened evidence
gate remain the control points.

1. **The ECC key must become persisted immutable evidence.** A conformant
   foundation retains E1–E10 and X1–X4 with their resolving policy versions.
   ECC cannot be a query-time reconstruction from mutable master data, because
   V-02 and P-06 would both fail.
2. **The accepted sequence is preserved, and demoted in meaning.** It remains
   Accepted Event Chronology evidence. Any object, index, constraint, or report
   that treats it as costing order must be corrected. This is additive
   reclassification, not deletion.
3. **The ordering index must be replaced, not extended.** An index whose leading
   economic components are followed by an accepted-sequence column cannot serve
   ECC. The replacement orders by the ECC components in their frozen order.
4. **The partition key must move from scope version to scope key.** Accepted
   sequence uniqueness and stream identity currently key on the effective-dated
   scope version row, which would split one economic stream across a scope
   re-version. Whether the correction is a new stream-identity object or a
   canonical scope-key derivation is an implementation choice for the authorized
   phase; the requirement is that one scope key is one partition, permanently.
5. **The Event Source Registry must gain per-source-type order authority before
   any source type is production-enabled.** Each rule needs event effects,
   economic-time authority, exactly one document-order-key algorithm, line-order
   authority, the transition set with ranks, occurrence semantics, same-time
   class, and correction placement class. Enabling a type without them violates
   V-10 and is an F-02 failure by construction.
6. **The event-order policy must become a versioned, first-class object.** Effect
   ranks, source-type ranks, transition ranks, and the canonical form belong to a
   version that events reference immutably, with sparse numbering (N-03) so
   future ranks insert without renumbering.
7. **No method-state, replay, or projection object may key on the accepted
   sequence.** FIFO layers, WAC pool versions, Specific-ID state, allocations,
   replay versions, and projection versions must key on the ECC key or on the
   event identity, never on accepted position. The frozen IA-4 blueprint's
   method-state tables must be reviewed against this before any permanent
   foreign key is created.
8. **Replay and projection versioning must exist before method state admits
   data.** Ordinals are version-scoped (P-08), so a method-state row without a
   replay version cannot be interpreted. The blueprint already anticipates
   replay-version and projection-version objects; ECC makes them prerequisites
   rather than conveniences.
9. **Fingerprint canonicalization must be named and versioned before replay
   becomes authority.** A caller-supplied digest cannot certify ordered inputs.
10. **Legacy rows lacking ECC components are not automatically convertible.** A
    historical row with no governed economic instant, document order key, line
    ordinal, transition, or occurrence ordinal falls into the blueprint's
    "blocked from automated conversion" class and must pass through reviewed
    opening-conversion evidence. Inferring a missing component from a created
    timestamp or a row id would reintroduce the defect the ADR closed.
11. **Fail-closed defaults are mandatory at every step.** A source type, policy,
    or scope that cannot resolve an ECC component must be unavailable, not
    permissive.
12. **The Posting boundary is unchanged.** ECC adds no journal writer, no kernel
    mutator, and no Posting input beyond already-calculated Inventory results.
    Any hardening that touches the six sanctioned persistence functions, the
    totality guard, or journal DML is outside this specification and outside
    ADR-C01.
13. **Documentation alignment is part of conformance.** The Costing
    Specification's ordering sentence, the IA-4 ordering blueprint and risk
    register, the IA-5 evidence record's economic-order list, and the migration
    comments must describe this tuple and these lock semantics, per gate
    Required Correction 3. Divergent prose is itself a conformance defect under
    PG-01 precedence — read as the authority chain mapped in
    [`PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md)
    (ECC-A-11, resolved 2026-07-26).
14. **This specification does not close the C-01 stop.** ADR-C01 §16 requires
    executable proof of implementation conformity. ECC-01 supplies the algorithm
    the proofs must test; it supplies no evidence, and it grants no permission
    to begin IA-6.
