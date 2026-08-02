# IA-5 WP-2 — Detailed Registry Authority Specification

**Status:** COMPLETE — controlling EA-001/EA-002-reconciled specification; implemented by migration `20260729000017` and tests `105`/`106` on 2026-07-29; independent Evidence Gate passed; **WP-2 CERTIFIED 2026-07-30**
**Decision date:** 2026-07-29
**Owner / Domain:** Inventory Accounting — IA-5 Economic Costing Chronology Hardening
**Read when:** Implementing WP-2 / migration M2, or reviewing its architecture and certification evidence
**Authority:** ADR-C01 (frozen), ECC-01 (accepted and owner approved), ECC-01 Formal Owner Acceptance, the accepted IA-5 ECC Hardening Implementation Design, and the WP-2 Authorisation Report
**Relationship:** Detailed engineering companion to `IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §6.4, §16, §17 M2, and §24 WP-2. This document changes neither ADR-C01 nor ECC-01 and authorises no work beyond WP-2.

## Engineering Amendment EA-001 — PostgreSQL Identifier Length

**Amendment date:** 2026-07-29
**Reason:** The constraint identifier originally specified for
`document_order_key_algorithm` was 64 ASCII bytes. PostgreSQL stores at most 63
bytes for an identifier, so the original literal could not exist exactly in the
catalog and would have been truncated rather than rejected.

**Correction:**

- Superseded pre-amendment label:
  `ref_inventory_event_source_types_document_order_key_algorithm_ck` (64 ASCII
  bytes; historical only; must not be implemented).
- Governing label after EA-001:
  `ref_inventory_event_source_types_doc_order_key_algorithm_ck` (59 ASCII
  bytes).

The amended name is deterministic, readable, retains the table prefix and
`_ck` suffix, and follows the repository's descriptive constraint-naming
convention.

**No semantic change:** EA-001 changes one engineering storage label only. It
does not change the column name, SQL type, nullability, default, predicate,
allowed values, row value, immutability, versioning, migration sequence,
rollback, the then-recorded WP-2 certification intent, WP-2 scope, ADR-C01,
ECC-01, accounting meaning, business meaning, Posting, Kernel, or runtime
behaviour. EA-002 subsequently allocates that unchanged intent to the
authoritative family names.

The original architecture decision and WP-2 authorisation chronology remain
valid and are not rewritten. EA-001 is the subsequent repository reconciliation
that makes their exact engineering contract representable in PostgreSQL.

## Engineering Amendment EA-002 — Test Authority and Evidence Boundary

**Amendment date:** 2026-07-29
**Reason:** The pre-amendment text reused T-04 for “registry completeness” and
T-06 for “same-time rank resolution”, while the controlling implementation
design §23 defines T-04 as Source order (E4/E5), T-06 as Transition order (E7),
and T-07 as Effect order (E3). It also required the M2 migration to assert
cross-object fixture resolution even though WP-1 deliberately keeps its
persistent policy/rank tables empty and materialises certification ranks only
inside a rolled-back test transaction.

**Correction:**

- the design §23 family names and numbers remain authoritative and are not
  renumbered;
- T-04 means Source order (E4/E5), T-06 means Transition order (E7), T-07 means
  Effect order (E3), and T-27 means Dormancy;
- “registry completeness” is WP-2 completion evidence spanning those families,
  not a separate or renamed test family;
- T-07 is explicitly listed for WP-2 because its already-required
  `event_effect_map` and `same_time_class` resolution is E3 evidence;
- M2 performs persistent precondition, registry-local, schema, security, and
  dormancy assertions only; and
- cross-object E3/E4/E7 resolution uses certification-only data created inside
  the future WP-2 test transaction and removed by its final `ROLLBACK`.

**No semantic change:** EA-002 changes no family definition, historical
executed test, column, value, predicate, database object, migration scope,
rollback result, certification intent, implementation sequence, accounting
meaning, business meaning, ADR-C01, ECC-01, Posting, Kernel, or runtime
behaviour. It removes implementer discretion by assigning existing obligations
to their authoritative test families and execution boundaries.

---

## 1. Executive Summary

WP-2 adds six immutable authority attributes to the existing
`ref_inventory_event_source_types` registry. The accepted design already fixes
the accounting meaning of all six attributes. The remaining work was to assign
exact storage representations to those meanings and to bind the existing
`IA5_CERTIFICATION` source type to the authority already demonstrated by the
repository.

This specification closes that engineering representation gap. It:

- defines the exact SQL type, nullability, default, value domain, constraint,
  immutability, versioning, certification, production, migration, rollback, and
  validation contract for every column;
- defines every value of the `IA5_CERTIFICATION` authority row;
- preserves the frozen ADR-C01 tuple and same-time convention;
- preserves ECC-01's derived-not-allocated rule, fail-closed completeness,
  dormancy, and replay safety; and
- leaves WP-3 through WP-9, IA-6, the Posting Engine, the Accounting Kernel,
  `inventory_events`, runtime readers, and production source enablement outside
  scope.

The identifiers introduced below are storage labels for rules already accepted
by ADR-C01 and ECC-01. They do not create an additional ordering dimension,
change rank meaning, select a costing policy, or amend accounting policy.

## 2. Scope and evidence boundary

### 2.1 WP-2 scope

WP-2 is limited to adding these columns to
`public.ref_inventory_event_source_types`:

1. `event_effect_map`
2. `document_order_key_algorithm`
3. `line_order_authority`
4. `occurrence_semantics`
5. `same_time_class`
6. `correction_placement_class`

WP-2 populates only the existing `IA5_CERTIFICATION` row. It adds no runtime
consumer and activates no production source type.

### 2.2 Evidence used to complete the representation

The controlling architecture supplies the policy:

- ADR-C01 fixes the lexicographic economic-order tuple, the E3 same-time rank
  convention, the E5 source-order rule, source-line and occurrence ordering,
  correction placement, prohibited authority inputs, and fail-closed behavior.
- ECC-01 derives the complete E1–E10/X1–X4 model, requires a complete
  per-source registry rule, defines the four correction placement classes,
  defines positive immutable E6/E8/E9 ordinals, and requires version-resolved,
  replay-safe authority.
- ECC-01 Formal Owner Acceptance accepts that derivation, including the E5
  governed-sequence preference and the canonical immutable source-identity
  fallback.
- The accepted IA-5 ECC Hardening Implementation Design fixes the six-column
  WP-2 shape, one-row migration boundary, dormancy, immutability, rollback, and
  T-04/T-06/T-07/T-27 validation obligations as allocated by EA-002.
- The WP-2 Authorisation Report authorises M2 only after WP-1 certification.

The repository implementation supplies current-schema facts, not new policy:

- `inventory_events.event_effect` currently permits
  `quantity_increase`, `quantity_decrease`, and `value_only`;
- `source_document_id` is a caller-supplied immutable UUID, established before
  IA-5 admission;
- source occurrence sequence is a positive caller-supplied ordinal and the IA-5
  evidence includes a valid second occurrence;
- `source_line_id` is accompanied by a source-line ordinal in the accepted
  target contract;
- the WP-1 policy domain is
  `opening`, `increase`, `value_only`, `decrease`, `allowance`; and
- the certification fixture resolves `IA5_CERTIFICATION` and transition
  `ACCEPTED`.

No separate file titled “WP-2 Implementation Stop Report” exists in the
repository. The pre-completion version of this document recorded Hard Stop #2
and its alleged open encodings. This completed revision is the resolution of
that stop artifact; it does not treat the former lack of stored labels as a lack
of accepted accounting authority.

## 3. Normative representation rules

### 3.1 Completeness and fail-closed behavior

All six columns are `NOT NULL` and have no persistent column default. A registry
row is incomplete if any value is absent, outside its exact domain, or
cross-field inconsistent. An incomplete source type is unavailable; it must not
fall back to lock order, insertion order, wall-clock order, UI order, identifier
allocation order, or any other surrogate.

JSON `null`, SQL `NULL`, an empty string, an empty object, an unknown token, and
an unmapped admitted event effect are all invalid authority.

### 3.2 Immutability and version behavior

The existing `ENABLE ALWAYS` immutable trigger on
`ref_inventory_event_source_types` rejects every row `UPDATE` and `DELETE`.
That protection covers the six new attributes automatically. WP-2 must not
replace, disable, bypass, or weaken the trigger.

WP-2 does not add a registry-version column or a second version model. Each
inserted source-type row is an immutable authority definition. Within the
current dormant registry:

- the six values on `IA5_CERTIFICATION` are its initial immutable authority;
- no value may be revised in place;
- a future authority change requires separately authorised append-only/version
  work and must resolve to one immutable registry definition before admission;
  and
- production activation remains unavailable until that later version-resolution
  design is implemented.

This is compatible with ECC-01's versioned-authority requirement because WP-2
stores immutable registry facts but does not claim to implement runtime version
selection.

### 3.3 Certification and production behavior

The only WP-2 row is `IA5_CERTIFICATION`, retaining:

- `is_certification_only = true`;
- `is_production_enabled = false`; and
- `removal_phase = 'IA-6'`.

No production document type may be inserted or enabled by WP-2. Future source
types may use only the domains defined here, but adding or enabling any such row
requires separate authorisation, full ECC-01 V-10 completeness, rank and
transition authority, runtime version resolution, and relevant certification.

### 3.4 Constraint naming and comparison rules

The required logical constraints are named in each column section. An
implementation may use PostgreSQL expressions that are mechanically equivalent
to the stated predicates, but may not weaken or broaden them.

All text tokens are exact lowercase ASCII values and use PostgreSQL bytewise
equality. No locale collation, case folding, alias, abbreviation, or
whitespace-normalisation rule is authorised.

## 4. Column authority specifications

### 4.1 `event_effect_map`

| # | Required attribute | Complete specification |
|---:|---|---|
| 1 | Column name | `event_effect_map` |
| 2 | Business purpose | Declares which economic effects the source type may emit and how each emitted effect enters the same-time convention. |
| 3 | Accounting purpose | Resolves an admitted event's E3 effect class before the WP-1 policy supplies its numeric rank. It never stores the rank itself. |
| 4 | ECC-01 traceability | §3.2 source registry; §4.2 E3; V-05, V-10, F-02; N-03/N-10. |
| 5 | ADR-C01 traceability | §6.3 E3 and §6.4 frozen same-time classes: opening, increase, non-decreasing value/classification, decrease, allowance. |
| 6 | Exact SQL data type | `jsonb`. |
| 7 | Nullability | `NOT NULL`. |
| 8 | Default value | No persistent default. |
| 9 | Allowed value domain | A non-empty JSON object. Keys are a subset of `quantity_increase`, `quantity_decrease`, `value_only`. Values are exact strings in `opening`, `increase`, `value_only`, `decrease`, `allowance`, subject to the permitted-pair matrix below. Duplicate JSON keys are not a distinct state because `jsonb` canonicalises object keys. |
| 10 | CHECK constraints | Named constraint `ref_inventory_event_source_types_event_effect_map_ck` must require: JSON type is `object`; object length is greater than zero; every key is in the three-key domain; every value is a JSON string; and every key/value pair is in the permitted-pair matrix. No extra key or value is accepted. |
| 11 | Meaning of every permitted value | `opening`: opening state; `increase`: owned quantity/value increase; `value_only`: cost or classification effect that does not decrease owned quantity; `decrease`: owned quantity/value decrease; `allowance`: valuation allowance overlay. Key meanings follow the existing event-effect direction contract. |
| 12 | Whether future values are permitted | No unlisted key, class, or pair is permitted. A later source may choose a valid subset/pair set. A new event-effect code or E3 class requires separately accepted architecture and a constraint change. |
| 13 | Immutability requirements | The entire JSON value is immutable with the registry row. No key may be added, removed, or remapped in place. |
| 14 | Versioning behaviour | It is part of the immutable source-type authority definition. Runtime policy resolution later supplies the versioned numeric rank for the mapped class; WP-2 adds no runtime resolver. |
| 15 | Certification-only behaviour | `IA5_CERTIFICATION` must contain the exact three-entry map in §5. No other certification map is seeded. |
| 16 | Production behaviour | Not consumed or enabled in WP-2. A future admitted event whose effect has no key must fail closed, never select a default class. |
| 17 | Migration behaviour | The one existing row receives the exact §5 object through the migration procedure in §7; the final column has no default. No event row is rewritten. |
| 18 | Rollback behaviour | Drop the column with the other five WP-2 columns. There is no runtime or event dependency in WP-2. |
| 19 | Validation rules | Validate JSON shape, exact domain, permitted pairs, exact certification content, resolution of every mapped class in the WP-1 effect-rank fixture, and rejection of absent/unknown effects. |
| 20 | Examples | Valid certification map: `{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}`. Valid future opening-only map: `{"quantity_increase":"opening"}`. Invalid: `{"quantity_decrease":"increase"}`, `{}`, or `{"receipt":"increase"}`. |

Permitted pair matrix:

| Existing event-effect key | Permitted E3 class | Reason |
|---|---|---|
| `quantity_increase` | `opening` or `increase` | Both classes can increase owned opening/period quantity; the source-type rule distinguishes them. |
| `quantity_decrease` | `decrease` | A decrease cannot be ranked as an opening, increase, non-decreasing value effect, or allowance. |
| `value_only` | `value_only` or `allowance` | Both are zero-quantity economic effects; the source-type rule distinguishes ordinary cost/classification from an allowance overlay. |

The map therefore classifies effects; it does not allocate ranks. Numeric E3
ranks remain exclusively owned by the resolved WP-1 order policy.

### 4.2 `document_order_key_algorithm`

| # | Required attribute | Complete specification |
|---:|---|---|
| 1 | Column name | `document_order_key_algorithm` |
| 2 | Business purpose | Declares which stable source fact orders same-time documents of this source type. |
| 3 | Accounting purpose | Selects the already-authorised E5 derivation rule. It prevents arrival, lock, insert, display, or generated-row order from becoming costing authority. |
| 4 | ECC-01 traceability | §3.2 source-order authority; §4.2 E5; V-06, V-10; N-04/N-05/N-06; F-02. Formal Owner Acceptance clarification ECC-A15/ECC-A16. |
| 5 | ADR-C01 traceability | §6.3(5), §6.5, and the prohibition on mutable/display/database-allocation ordering. |
| 6 | Exact SQL data type | `text`. |
| 7 | Nullability | `NOT NULL`. |
| 8 | Default value | No persistent default. |
| 9 | Allowed value domain | Exactly `governed_business_sequence` or `canonical_source_document_id`. |
| 10 | CHECK constraints | Named constraint `ref_inventory_event_source_types_doc_order_key_algorithm_ck`: value is in the exact two-token domain. |
| 11 | Meaning of every permitted value | `governed_business_sequence`: derive E5 from the source type's immutable governed business sequence using canonical binary encoding. `canonical_source_document_id`: when no governed business sequence exists, derive E5 from the immutable pre-admission `source_document_id` UUID encoded as canonical UUID bytes. It is not UUID text and is not an IA-5-generated identifier. |
| 12 | Whether future values are permitted | Future rows may select either token. No third algorithm is permitted without separately accepted architecture and a constraint change. Where a governed sequence exists, ECC-A16 requires that token rather than the identity fallback. |
| 13 | Immutability requirements | The selected algorithm is immutable with the source-type row. Its input must also be immutable and established before admission. |
| 14 | Versioning behaviour | The token is the registry selector; canonical byte encoding is resolved under the applicable canonical-form version in later work. WP-2 neither materialises E5 nor activates a canonical-form version. |
| 15 | Certification-only behaviour | `IA5_CERTIFICATION` uses `canonical_source_document_id` because the certification source has no governed business sequence and supplies an immutable source UUID before admission. |
| 16 | Production behaviour | Dormant in WP-2. A future production source with a governed sequence must use `governed_business_sequence`; fallback is allowed only when the governed sequence does not exist and that absence is documented in the source registry. |
| 17 | Migration behaviour | Seed the §5 token on the existing certification row through §7; no document key is computed or stored. |
| 18 | Rollback behaviour | Drop the column; no materialised E5 or runtime dependency exists. |
| 19 | Validation rules | Reject unknown tokens; prove the chosen input is pre-admission and immutable; reject display number, mutable sort, row ID allocated by IA-5, insertion order, lock order, timestamp, or physical location; prove deterministic canonical bytes. |
| 20 | Examples | Certification: source UUID `00112233-4455-6677-8899-aabbccddeeff` is ordered by its 16 canonical UUID bytes under `canonical_source_document_id`, never by its printed text or insert order. A governed invoice sequence would use `governed_business_sequence`. |

The two tokens name the two E5 branches already accepted by ADR-C01/ECC-01.
Choosing the fallback for `IA5_CERTIFICATION` is a repository fact: that source
has no governed business sequence and its caller-provided UUID satisfies the
accepted fallback precondition.

### 4.3 `line_order_authority`

| # | Required attribute | Complete specification |
|---:|---|---|
| 1 | Column name | `line_order_authority` |
| 2 | Business purpose | Declares the stable business-line ordering authority within a source document. |
| 3 | Accounting purpose | Fixes E6 as the source-created line ordinal and prevents UI order, UUID order, allocation order, or database insertion order from affecting costing chronology. |
| 4 | ECC-01 traceability | §3.2 line-order authority; §4.2 E6; V-07/V-10; N-07; F-02. |
| 5 | ADR-C01 traceability | §6.3(6), including inheritance of the parent line ordinal by derived allocations. |
| 6 | Exact SQL data type | `text`. |
| 7 | Nullability | `NOT NULL`. |
| 8 | Default value | No persistent default. |
| 9 | Allowed value domain | Exactly `immutable_source_line_ordinal`. |
| 10 | CHECK constraints | Named constraint `ref_inventory_event_source_types_line_order_authority_ck`: value equals `immutable_source_line_ordinal`. |
| 11 | Meaning of every permitted value | `immutable_source_line_ordinal`: E6 is the strictly positive ordinal assigned by the source when the business line is created; it is immutable thereafter. Every event derived from that line carries the same E6. |
| 12 | Whether future values are permitted | No. This is the universal E6 authority fixed by ECC-01/ADR-C01. A different authority would amend the accepted tuple and is outside WP-2. |
| 13 | Immutability requirements | The token and each admitted line ordinal are immutable. Reordering a UI or allocating child rows cannot change E6. |
| 14 | Versioning behaviour | The token is part of the immutable registry definition. The ordinal itself is a source fact, not a versioned rank and not a sequence allocated by IA-5. |
| 15 | Certification-only behaviour | `IA5_CERTIFICATION` stores the singleton token. Later certification admission must supply a positive ordinal; WP-2 itself admits no events. |
| 16 | Production behaviour | Dormant. A future source cannot be enabled unless it can supply this source-created immutable ordinal. |
| 17 | Migration behaviour | Seed the singleton token through §7; do not add a column to `inventory_events` in WP-2. |
| 18 | Rollback behaviour | Drop the registry column; no event or runtime state changes. |
| 19 | Validation rules | Exact token; positive integer source ordinal at admission in later work; stability across replay; identical E6 on all derived allocations; rejection of generated/UI/database order substitutes. |
| 20 | Examples | Source lines 1 and 2 retain E6 values 1 and 2 even if displayed in reverse. Two cost allocations derived from line 2 both retain E6 = 2. |

The token is an engineering label for the single E6 authority already mandated
by the accepted architecture; it does not introduce an alternative.

### 4.4 `occurrence_semantics`

| # | Required attribute | Complete specification |
|---:|---|---|
| 1 | Column name | `occurrence_semantics` |
| 2 | Business purpose | Declares whether a source line/transition can occur once or in explicitly numbered partial occurrences. |
| 3 | Accounting purpose | Fixes how E8 is sourced and prevents retry count, arrival order, lock order, or row allocation from becoming occurrence order. E9 remains the deterministic event ordinal within one occurrence. |
| 4 | ECC-01 traceability | §3.2 occurrence semantics; §4.2 E8/E9; V-09/V-10/V-12; N-07; F-02. |
| 5 | ADR-C01 traceability | §6.3(8)–(9) and §6.6 deterministic event-plan ordering. |
| 6 | Exact SQL data type | `text`. |
| 7 | Nullability | `NOT NULL`. |
| 8 | Default value | No persistent default. |
| 9 | Allowed value domain | Exactly `single_occurrence` or `explicit_partial_occurrences`. |
| 10 | CHECK constraints | Named constraint `ref_inventory_event_source_types_occurrence_semantics_ck`: value is in the exact two-token domain. |
| 11 | Meaning of every permitted value | `single_occurrence`: one line/transition has exactly one occurrence and E8 is always 1. `explicit_partial_occurrences`: the source supplies a strictly positive immutable E8 for each line/transition occurrence; the first is 1, later partial occurrences are distinct positive ordinals, gaps are permitted, and an ordinal cannot be reused for different evidence. For both values, E9 is a strictly positive deterministic ordinal within the occurrence. |
| 12 | Whether future values are permitted | Future rows may select either token. No additional occurrence model is permitted without separately accepted architecture and a constraint change. |
| 13 | Immutability requirements | The selected semantics and every accepted E8/E9 value are immutable. Retry/idempotent replay must reproduce the same values. |
| 14 | Versioning behaviour | The token is part of the immutable registry definition. It does not version an occurrence; E8/E9 remain source/derivation facts under the resolved registry rule. |
| 15 | Certification-only behaviour | `IA5_CERTIFICATION` uses `explicit_partial_occurrences`, matching the existing positive occurrence-sequence contract and evidence that occurrence 2 is valid. |
| 16 | Production behaviour | Dormant. Later admission must reject E8 other than 1 for `single_occurrence`; for explicit partials it must reject non-positive, conflicting, mutable, or evidence-inconsistent ordinals. |
| 17 | Migration behaviour | Seed the §5 token only. Do not change occurrence tables, writers, uniqueness rules, or admission functions in WP-2. |
| 18 | Rollback behaviour | Drop the registry column; existing dormant occurrence schema remains byte-for-byte outside that column removal. |
| 19 | Validation rules | Exact token; E8 positive; one/only-one rule for singleton; uniqueness and evidence stability for explicit partials; deterministic contiguous E9 within each emitted event plan; replay reproduces E8/E9. |
| 20 | Examples | `single_occurrence`: line 1 / `ACCEPTED` has E8 = 1 only. `explicit_partial_occurrences`: the same line/transition may carry E8 = 1 and E8 = 2; a retry of occurrence 2 must reproduce occurrence 2, not allocate 3. |

Gaps in a business sequence of explicit partial-occurrence ordinals do not alter
order: comparison uses the positive ordinal itself. The source must not renumber
accepted evidence.

### 4.5 `same_time_class`

| # | Required attribute | Complete specification |
|---:|---|---|
| 1 | Column name | `same_time_class` |
| 2 | Business purpose | Declares the registry mechanism used to classify this source type's events at the same economic instant. |
| 3 | Accounting purpose | Requires E3 to come from each event's mapped economic effect, after which the resolved WP-1 policy supplies the frozen rank. It prevents a document label or arrival sequence from overriding effect meaning. |
| 4 | ECC-01 traceability | §3.2 same-time class; §4.2 E3; V-05/V-10; N-03/N-10; F-02. |
| 5 | ADR-C01 traceability | §6.3(3) and frozen §6.4 increase-before-decrease convention. |
| 6 | Exact SQL data type | `text`. |
| 7 | Nullability | `NOT NULL`. |
| 8 | Default value | No persistent default. |
| 9 | Allowed value domain | Exactly `event_effect_map`. |
| 10 | CHECK constraints | Named constraint `ref_inventory_event_source_types_same_time_class_ck`: value equals `event_effect_map`. |
| 11 | Meaning of every permitted value | `event_effect_map`: derive the E3 class by exact lookup of the event's `event_effect` in this row's `event_effect_map`; then resolve that class's sparse numeric rank from the applicable WP-1 order policy. |
| 12 | Whether future values are permitted | No. All WP-2 registry rows use effect-derived E3 classification. A new mechanism would create new same-time authority and requires an ADR-C01-conforming architecture decision outside WP-2. |
| 13 | Immutability requirements | The token is immutable. Neither runtime nor replay may substitute source type, transition, insertion time, or lock order for the mapped event effect. |
| 14 | Versioning behaviour | Classification mechanism is fixed by the registry row; rank numbers remain versioned in the event-order policy and are not copied into this column. |
| 15 | Certification-only behaviour | `IA5_CERTIFICATION` stores `event_effect_map` and resolves all three currently admitted effect codes through the exact §5 map. |
| 16 | Production behaviour | Dormant. Later runtime must fail closed if the map or resolved rank is absent; it cannot infer a class. |
| 17 | Migration behaviour | Seed the singleton token only; no rank table, event, or runtime function changes in WP-2. |
| 18 | Rollback behaviour | Drop the column; WP-1 rank tables remain dormant and unchanged. |
| 19 | Validation rules | Exact token; mapped class exists; exactly one applicable rank exists; classification changes when event effect changes, not when scheduling changes; same-time increase ranks before decrease under the resolved policy. |
| 20 | Examples | A certification `quantity_increase` maps to `increase` and rank 20; `quantity_decrease` maps to `decrease` and rank 40. Reversing arrival/lock order cannot reverse those E3 results. |

This singleton token is necessary because one source type may emit more than one
economic effect. A single fixed E3 class on the source type would contradict the
accepted event-effect model; event-level map lookup implements the accepted
authority without adding a tuple component.

### 4.6 `correction_placement_class`

| # | Required attribute | Complete specification |
|---:|---|---|
| 1 | Column name | `correction_placement_class` |
| 2 | Business purpose | Declares how events from the source type relate to corrected economic evidence. |
| 3 | Accounting purpose | Selects the accepted base/anchored/independent/counterfactual placement rule for E1–E10 and X1–X4; it does not create a new order dimension. |
| 4 | ECC-01 traceability | §4.4 correction placement classes; X1–X4; V-18/V-19/V-22. |
| 5 | ADR-C01 traceability | §6.5 correction/reversal chronology. |
| 6 | Exact SQL data type | `text`. |
| 7 | Nullability | `NOT NULL`. |
| 8 | Default value | No persistent default. |
| 9 | Allowed value domain | Exactly `base`, `anchored`, `independent`, or `counterfactual_only`. |
| 10 | CHECK constraints | Named constraint `ref_inventory_event_source_types_correction_placement_class_ck`: value is in the exact four-token domain. |
| 11 | Meaning of every permitted value | `base`: ordinary non-correction evidence derives its own E1–E10 and uses depth-zero X sentinels. `anchored`: a correction inherits the root target's E1–E10 and is ordered by the accepted X chain. `independent`: replacement evidence derives its own E1–E10 and retains a correction link for traceability. `counterfactual_only`: evidence may be evaluated only in counterfactual replay and is unavailable to certified base replay. |
| 12 | Whether future values are permitted | No. A fifth class requires an accepted successor/amendment to the controlling correction architecture and a constraint change. |
| 13 | Immutability requirements | The class is immutable with the source-type definition. An accepted event cannot be reclassified in place. |
| 14 | Versioning behaviour | The source-type selector is immutable; detailed graph/anchoring rules resolve under the applicable correction-graph version in later work. WP-2 activates none. |
| 15 | Certification-only behaviour | `IA5_CERTIFICATION` uses `base`; it is the ordinary certification source and has no correction-only semantics. |
| 16 | Production behaviour | Dormant. Anchored, independent, or counterfactual behavior cannot execute until later correction-graph and admission work is separately authorised. |
| 17 | Migration behaviour | Seed `base` through §7 only. No correction link, graph, event, or runtime behavior changes. |
| 18 | Rollback behaviour | Drop the column; no correction state exists as a WP-2 dependency. |
| 19 | Validation rules | Exact domain; base uses depth-zero sentinels; anchored inherits root E1–E10; independent derives its own E1–E10; counterfactual-only cannot enter certified replay. WP-2 validates the stored selector, while later authorised work validates event behavior. |
| 20 | Examples | `IA5_CERTIFICATION` ordinary receipt/issue evidence is `base`. A later anchored correction inherits its root tuple; a later independent replacement has its own tuple; a counterfactual-only event is excluded from certified base replay. |

## 5. Exact `IA5_CERTIFICATION` authority row

The only authorised values are:

| Registry column | Exact authorised value | Existing authority represented |
|---|---|---|
| `event_effect_map` | `{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}` as a `jsonb` object | Existing event-effect direction domain plus ADR-C01 E3 classes and WP-1 class identifiers |
| `document_order_key_algorithm` | `canonical_source_document_id` | ECC-A16/ADR-C01 canonical immutable source-identity fallback; certification source has no governed business sequence |
| `line_order_authority` | `immutable_source_line_ordinal` | ADR-C01/ECC-01 E6 |
| `occurrence_semantics` | `explicit_partial_occurrences` | ADR-C01/ECC-01 E8/E9 plus existing positive partial-occurrence certification evidence |
| `same_time_class` | `event_effect_map` | ADR-C01 §6.4 event-effect-based same-time convention |
| `correction_placement_class` | `base` | ECC-01 §4.4 ordinary non-correction placement |

Retained row values are not changed:

| Existing column | Required retained value |
|---|---|
| `source_document_type` | `IA5_CERTIFICATION` |
| `owner_engine` | `Inventory` |
| `is_certification_only` | `true` |
| `is_production_enabled` | `false` |
| `removal_phase` | `IA-6` |

No value is implicit. No alternative spelling, alias, empty value, or default is
authorised.

## 6. Cross-field validation contract

The following validations are mandatory in addition to the six column-local
constraints:

1. `same_time_class = 'event_effect_map'` requires a non-empty valid
   `event_effect_map`.
2. Every event-effect class in the certification map must resolve exactly once
   in the applicable WP-1 certification rank fixture:
   `increase = 20`, `value_only = 30`, `decrease = 40`.
3. The existing certification rank fixture must continue to contain
   `opening = 10` and `allowance = 50`; absence from the certification source's
   emitted-effect map does not delete or renumber those frozen classes.
4. `IA5_CERTIFICATION` must resolve exactly once in the WP-1 source-type ranks,
   and `ACCEPTED` exactly once in transition ranks.
5. `canonical_source_document_id` is valid only because the certification source
   lacks a governed business sequence and supplies immutable pre-admission UUID
   evidence.
6. `explicit_partial_occurrences` must remain compatible with positive immutable
   occurrence ordinals and deterministic within-occurrence event ordinals.
7. `base` must not imply correction anchoring or introduce X-chain depth.
8. All six values must be present before the row can be considered complete.
9. No check or test may manufacture a fallback value for an absent authority.

### 6.1 Authoritative test-family contract

The implementation design §23 definitions govern everywhere:

| Family | Authoritative purpose | WP-2 evidence boundary |
|---|---|---|
| **T-04 — Source order** | E4/E5: source-type rank and document-order key decide before arrival. | Persist the exact E5 algorithm selector; in a rolled-back certification fixture, resolve exactly one E4 rank for `IA5_CERTIFICATION`. WP-2 does not compare runtime documents. |
| **T-06 — Transition order** | E7: the registered transition rank decides and an unranked transition is unavailable. | In a rolled-back certification fixture, resolve exactly one `ACCEPTED` transition rank for `IA5_CERTIFICATION` and reject missing/duplicate/unknown transition authority. WP-2 adds no transition table or runtime comparator. |
| **T-07 — Effect order** | E3: effect rank places a same-time increase before a decrease. | Validate the exact map and `same_time_class`; in a rolled-back certification fixture, resolve mapped classes through the WP-1 ranks and prove `increase = 20 < decrease = 40`. WP-2 does not order runtime events. |
| **T-27 — Dormancy** | No activation or reachable runtime path. | Prove zero `inventory_events`, certification-only/production-disabled registry state, no new consumer or grant, and no Posting or Kernel change. |

“Registry completeness” is the WP-2 completion result: exact columns, exact
domains, exact `IA5_CERTIFICATION` values, registry-local consistency,
fixture-based E3/E4/E7 resolution, rejection of incomplete or unknown
authority, and dormancy. It is not the name or redefinition of T-04.

### 6.2 Assertion ownership

The cross-field rules above have two execution owners:

- **Persistent M2 assertions:** rules 1 and 5–9 insofar as they concern the
  stored registry row, exact values, schema domains, retained source facts,
  immutability, and dormancy. M2 does not require or create a policy/rank row.
- **Rolled-back certification assertions:** rules 2–4, plus the rank-resolution
  part of rule 1, execute only after the future WP-2 test creates the
  certification-only WP-1 policy/rank fixture inside its transaction.

WP-2 tests may prove these structural and fixture-level contracts but may not
claim the later runtime-ordering portions of T-04, T-06, or T-07 and may not
activate WP-3+ behavior.

## 7. Migration and rollback specification

### 7.1 Mandatory migration preconditions

The M2 migration must execute in one transaction and stop before mutation unless
all of these facts hold:

1. `inventory_events` contains exactly zero rows.
2. `ref_inventory_event_source_types` contains exactly one row.
3. That row is exactly `IA5_CERTIFICATION` with the retained values in §5.
4. The existing immutable `ENABLE ALWAYS` trigger is present and enabled.
5. All six target columns are absent.
6. All six WP-1 policy/version objects exist in their authorised persistent
   dormant state: their structural controls remain present, no policy/rank
   fixture row persists, and WP-2 has no authority to seed one.

A failed precondition is a governance stop. It is not authority to backfill,
repair, delete, disable a trigger, or infer values.

### 7.2 Required migration sequence

The implementation must:

1. acquire the table lock required by design M2 (`ACCESS EXCLUSIVE`);
2. assert every §7.1 precondition;
3. add exactly the six columns with the types and constraints specified here;
4. materialise the exact §5 value into the sole pre-existing row without issuing
   a row `UPDATE` and without disabling or bypassing the immutable trigger;
5. remove every temporary migration-only default before commit, leaving all six
   final columns `NOT NULL` with no default;
6. assert the exact final row, the six column-local constraints, every
   registry-local cross-field rule allocated to M2 by §6.2, unchanged registry
   row count, zero events, unchanged grants/RLS/trigger state, and dormancy;
7. assert that no row was added to or changed in any WP-1 policy/version/rank
   table and no certification fixture persists; and
8. commit atomically.

PostgreSQL's add-column handling of a constant default may be used solely as the
mechanical one-row materialisation mechanism, provided each default is removed
in the same transaction. This is not a persistent default and is not permission
to update the immutable row. No trigger disablement, DML bypass, new write grant,
or deferred repair is permitted.

WP-2 must not create or change any table other than the six new columns and
their constraints on `ref_inventory_event_source_types`. It must not change
`inventory_events`, its functions, tests outside WP-2 evidence, Posting, Kernel,
or runtime behavior.

### 7.3 Certification-only fixture boundary

The future WP-2 certification test, not M2, owns cross-object rank-resolution
evidence. It must:

1. begin a transaction after M2 is installed;
2. confirm the persistent WP-1 policy/version/rank tables are initially empty;
3. create only the minimum certification company/user, policy/version, E3 rank,
   E4 source-rank, and E7 transition-rank fixture required by §6.1, using the
   same frozen values already proved by test 104;
4. read the persistent `IA5_CERTIFICATION` registry row without updating it;
5. execute the T-04, T-06, T-07, and T-27 structural/fixture assertions;
6. include negative assertions for missing, duplicate, or unknown authority
   without installing a fallback;
7. finish the test and issue a final transaction `ROLLBACK`; and
8. prove in the certification lane that no fixture policy, rank, company, user,
   event, journal, or other temporary certification row survives.

The fixture is evidence only. It is not seed data, a migration dependency,
runtime configuration, production authority, or permission to weaken an
immutable trigger. M2 must not invoke test 104, copy its DML into the migration,
or depend on test execution order.

### 7.4 Rollback

Rollback is permitted only while no later authorised object depends on the
columns and all dormancy conditions remain true. It:

1. acquires `ACCESS EXCLUSIVE` on the registry;
2. reasserts zero `inventory_events` and the single dormant certification row;
3. drops exactly the six columns and their attached constraints in reverse
   migration order; and
4. verifies that the pre-WP-2 registry shape, immutable trigger, RLS, privileges,
   and retained certification values are unchanged.

There is no event-data rollback, backfill, replay, journal, projection, costing,
or production action because WP-2 creates none.

Rollback certification must run in an isolated test transaction against an
M2-applied database: reassert the rollback preconditions, perform the six
reverse-order column drops, verify the exact pre-WP-2 persistent shape and
unchanged controls, then roll back the test transaction so the M2-applied
schema is restored for later tests. Certification-only E3/E4/E7 fixture rows
are not required for this structural rollback proof and must not survive it.

## 8. Traceability Matrix

| WP-2 authority | ADR-C01 | ECC-01 / acceptance | IA-5 design / authorisation | Repository proof used |
|---|---|---|---|---|
| `event_effect_map` | E3; §6.4 ranks | source registry; E3; V-05/V-10; N-03/N-10 | §6.4, §16, M2, WP-2; T-07 | current event-effect domain; WP-1 class/rank domain |
| `document_order_key_algorithm` | E5; prohibited surrogates | E5; N-04–N-06; ECC-A15/A16 | §6.4, §16, M2, WP-2 | caller-supplied immutable source UUID; no certification number series |
| `line_order_authority` | E6; derived inheritance | E6; V-07/V-10; N-07 | §6.4, §16, M2, WP-2 | accepted target input is source-line ordinal |
| `occurrence_semantics` | E8/E9; deterministic event plan | E8/E9; V-09/V-12; N-07 | §6.4, §16, M2, WP-2 | positive occurrence schema and partial occurrence evidence |
| `same_time_class` | E3; frozen increase-before-decrease | source registry; E3; V-05/V-10 | §6.4, §16, M2, WP-2; T-07 | event-level effect domain and WP-1 sparse ranks |
| `correction_placement_class` | §6.5 | §4.4; X1–X4; V-18/V-19/V-22 | §6.3/§6.4, §16, M2, WP-2 | certification source is ordinary base evidence |
| Common immutability | immutable economic facts | P-05; V-10 | §16/§19; M2 | existing registry `ENABLE ALWAYS` immutable trigger |
| Dormancy and rollback | no change to frozen order | F-02; replay rules | §17 M2, §21, §24; WP-2 authorisation | zero-event precondition; certification-only/production-disabled checks |

## 9. Architectural validation

### 9.1 No new accounting policy

Confirmed. The document gives storage tokens to existing accepted categories:
E3 effect class, E5 governed sequence or canonical identity fallback, E6 source
line ordinal, E8/E9 occurrence model, and ECC-01 correction placement. It does
not choose FIFO/WAC/Specific-ID policy, valuation arithmetic, account mapping,
posting, or a new business chronology.

### 9.2 No new ordering authority

Confirmed. The six attributes select or classify inputs already present in the
ADR-C01 tuple. No new tuple field or tie-breaker is added. Database allocation,
lock acquisition, arrival, transaction start, wall-clock time, mutable display
order, and execution artefacts remain prohibited.

### 9.3 ADR-C01 and ECC-01 compatibility

Confirmed. E3 continues to resolve through event effect and versioned sparse
rank; E5 uses only the two accepted source authorities; E6/E8/E9 stay positive,
immutable, and source/derivation governed; corrections use the accepted four
placement classes. Missing authority fails closed.

### 9.4 Derived-not-allocated ordering

Preserved. WP-2 stores declarations only. It allocates no chronology value,
event ordinal, document key, source identifier, rank, or occurrence sequence.
The certification E5 input is created before admission, E6/E8 are source facts,
and E9 remains a pure deterministic event-plan result.

### 9.5 Dormancy

Preserved. The registry row remains certification-only and
production-disabled; `inventory_events` remains empty; there is no runtime
reader, writer, grant, source enablement, projection, costing, or journal
effect.

### 9.6 Replay safety

Preserved. All selectors and inputs are immutable, canonical, explicit, and
version-resolved by later authorised work. The migration changes no accepted
event and no replay function. Re-execution against identical evidence cannot
obtain a different value from scheduling or database allocation.

## 10. Architectural Gaps Closed

The former stop artifact listed five gaps. They are closed as representation
questions, using existing authority:

| Former gap | Resolution |
|---|---|
| G-1 occurrence semantics | Exact two-value engineering domain; certification selects explicit partial occurrences based on the accepted E8 model and existing partial-occurrence evidence. |
| G-2 same-time class | Exact singleton `event_effect_map`; E3 stays event-effect-derived and rank-versioned. |
| G-3 document-order algorithm | Exact identifiers for the two accepted E5 branches; certification selects canonical immutable source UUID because no governed sequence exists. |
| G-4 line-order authority | Exact singleton `immutable_source_line_ordinal`, directly representing E6. |
| G-5 effect-map encoding/content | `jsonb` exact-key map over the current event-effect domain and accepted E3 classes; exact certification map fixed. |

No owner accounting decision was required because none of these resolutions
changes the accepted meaning. The exact token spelling, `jsonb` representation,
constraint names, and migration mechanism are engineering specification.

## 11. Repository Documents Updated

This architecture-completion work is limited to:

- this detailed specification;
- `PXL_DOCUMENTATION_INDEX.md`, to remove the obsolete incomplete status; and
- `AI_STATE.md`, to record that WP-2 architecture is complete and its already
  authorised implementation may proceed.

No SQL, migration, schema, test, runtime, Posting Engine, Accounting Kernel, or
`inventory_events` file is changed by this architecture work.

**Subsequent reconciliation:** Engineering Amendment EA-001 (2026-07-29)
corrected the single overlength constraint identifier in §4.2 and reconciled
the WP-2 authorisation report, implementation-design status, `AI_STATE.md`,
`PXL_DOCUMENTATION_INDEX.md`, `PXL_CERTIFICATION_MATRIX.md`, the central
findings register, and the Transaction Matrix findings checksum. It changed no
implementation or accounting authority.

Engineering Amendment EA-002 (2026-07-29) subsequently reconciled this
specification, the implementation design, WP-2 authorisation report,
`AI_STATE.md`, `PXL_DOCUMENTATION_INDEX.md`, `PXL_CERTIFICATION_MATRIX.md`,
`PXL_ACCOUNTING_TEST_BOOK.md`, the central findings register, and the
Transaction Matrix findings checksum. It corrected test-family allocation and
the migration-versus-certification evidence boundary only. No SQL, migration,
test, schema, runtime, accounting, ADR-C01, or ECC-01 artifact changed.

**Subsequent implementation record (2026-07-29):** migration
`20260729000017` implements the exact six-column M2 contract; test `105`
implements the structural/fixture portions of T-04/T-06/T-07/T-27 with final
`ROLLBACK`; test `106` proves reverse-order structural rollback and then rolls
back to the M2-applied state. The implementation report records the prepared
evidence. No runtime, Posting, Kernel, `inventory_events`, accounting, ADR-C01,
or ECC-01 change was made.

**Subsequent certification remediation and Evidence Gate (2026-07-29):** an
independent certification review correctly found that test `106` proved one
matching certification row but did not explicitly prove the §7.1 total registry
count of one immediately before destructive rollback. The minimum correction
added that single assertion; test `106` now contains 21 assertions. Fresh
replay, tests `105`/`106` (69 assertions), full regression (106 files / 2,444
assertions), canonical accounting (30 files / 748 assertions), and
catalog/security/dormancy checks pass. The independent Evidence Gate recommends
certification and changes no specification, architecture, accounting, runtime,
or work-package boundary.

**Subsequent certification decision (2026-07-30):** the independent WP-2
Certification Mission granted certification. It re-executed fresh replay,
focused `105`/`106` (69), full regression (106/2,444), canonical accounting
(30/748), lint, build, and diff; independently probed the applied catalog for
shape, constraints, values, dormancy, RLS, grants, immutability, and consumers;
and mutation-verified that test `106`'s added assertion fails closed on an extra
registry row while the pre-remediation assertion would still have passed. One
non-blocking observation was recorded: §4.2 and §8 cite the Formal Owner
Acceptance clarifications as `ECC-A15`/`ECC-A16`, whereas their canonical
identifiers are `ECC-A-15`/`ECC-A-16`. The cited substance is correct and
present in Formal Owner Acceptance §12; only the citation format differs, so no
specification, accounting, or scope change follows. The certification decision
changes no architecture, accounting, runtime, or work-package boundary.

## 12. Remaining Open Questions

None for WP-2 architecture or the `IA5_CERTIFICATION` row.

Questions belonging to WP-3 through WP-9, IA-6, production source onboarding,
runtime version selection, event admission, key materialisation, correction
graphs, costing execution, and hosted deployment remain outside this decision
and retain their existing authorisation gates.

## 13. Readiness Assessment

Following EA-001 and EA-002 repository reconciliation, WP-2 was implemented
within the authorised M2 boundary. The six columns, constraints, exact
certification row, structural/fixture portions of T-04/T-06/T-07/T-27, and
corrected rollback proof exist without selected accounting policy or persistent
fixture data.

The independent WP-2 Evidence Gate passed and recommended certification, and the
separate Certification Mission granted certification on 2026-07-30 after
independently re-executing every validation lane, probing the applied catalog,
and mutation-verifying the rollback remediation. WP-3 through WP-9 and IA-6
remain unauthorised.

## Decision

**A.**

**WP-2 IMPLEMENTED — EVIDENCE GATE PASSED — CERTIFIED 2026-07-30**

**WP-2 GOVERNANCE COMPLETE; WP-3 NOT AUTHORISED**
