# IA-5 Economic Costing Chronology Hardening — Implementation Design and Change Plan

**Status:** ACCEPTED — design complete and controlling through WP-4; M5 is specification-complete under Engineering Amendment EA-010. WP-1, WP-2, WP-3 and WP-4 are implemented and certified (2026-07-29 / 2026-07-30 / 2026-07-31 / 2026-07-31). The 2026-07-31 WP-5 Authorisation Gate rejection remains preserved in §31; EA-008/EA-009 and their intervening rejection remain preserved in §§32–34. The complete later gate rejection on WP5-AGR2-001…004 is preserved in §35 and EA-010 closure in §36. WP-5 remains unauthorised and unimplemented pending another separate comprehensive Authorisation Gate re-run. WP-6…WP-9 and IA-6 remain unauthorised.
**Authority:** Implementation design subordinate to [ADR-C01](../03.%20Architecture/ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md) and [ECC-01](../03.%20Architecture/ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md); authorised by ADR-C01 §17 and the [ECC-01 Final Architecture Acceptance Report](../03.%20Architecture/ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md) §24
**Owner / Domain:** Inventory Accounting
**Design date:** 2026-07-26
**Applies To:** Hardening the dormant IA-5 foundation to conform to ECC-01
**Read When:** Executing, reviewing, or certifying any IA-5 ECC hardening work package
**Do Not Read For:** IA-6 method state, replay execution, projection cut-over, or authority to begin coding
**Implementation Status:** This design authorises nothing by itself. WP-1…WP-4 are certified bounded work packages. EA-010 is documentation/governance only and creates no SQL, migration, test, database object, runtime consumer, source activation or hosted change. The next mission is the comprehensive WP-5 Authorisation Gate re-run.

---

## 1. Executive Summary

IA-5 admits inventory events correctly and orders them wrongly. Everything else
follows from that one sentence.

The dormant foundation (`20260726000013`–`20260726000015`) already supplies what
ECC-01 calls admission: an atomic occurrence, immutable event facts, exact
fixed-point precision, effective-dated policy resolution, company isolation,
`ENABLE ALWAYS` immutability, and no journal or projection effect. What it does
not supply is an economic order. Its ordering index leads with an
admission-allocated `scope_sequence` obtained by `UPDATE … RETURNING` against a
shared row — the lock winner — and it carries none of the five source-order
components ECC-01 requires (effect rank, source-type rank, document order key,
line ordinal, transition rank). Five of the fourteen ECC components are absent
from the schema entirely; four more exist only as opaque UUIDs.

**Scope decision that shapes this plan.** ECC-01's algorithm has eight stages.
Stages 1–3 (partition resolution, component resolution, admission validation)
and stages 4–6 (population selection, causal validation, total ordering) are
*ordering*. Stage 7's fold and stage 8's promotion are *method state* — FIFO
layers, WAC pools, Specific-ID values, projections — which remain IA-6 and
unauthorised. **This hardening therefore owns ECC-01 stages 1–6 plus the
ordered-input fingerprint, and nothing beyond.** It produces a proven order and
a fingerprint over that order; it computes no cost. Sections 11–13 are
consumption contracts that bind IA-6, not work in this plan.

The design is staged and reversible. Nine work packages add one ordering-key
sidecar, one stream (partition) identity, four versioned policy objects, a
registry extension, a pure derivation function, a replacement ordering index,
and a certification lane. M1–M4 alter no event object. M5, if separately
authorised, adds one deferred constraint trigger to `inventory_events` and
replaces its owner-only admission writer; it alters no event column or row.
`inventory_occurrences`, Posting and the Kernel remain unchanged. The defective
index and accepted-sequence allocator are demoted and superseded rather than
dropped. `scope_sequence` survives with its meaning corrected — it is accepted
chronology, permanently.

**Existing data is a non-problem, and this is evidence, not optimism.** The
evidence gate measured `inventory_events` at zero rows on a clean replay; the
source-type registry carries `CHECK (NOT is_production_enabled)` and
`CHECK (is_certification_only)`, so no production event can exist by
construction; and every migration from `20260723000001` onward is local-only —
the hosted project has never seen IA-5. There is no backfill, and no default
affecting accounting order is invented.

**Readiness: B — READY AFTER OWNER ACCEPTANCE OF ECC-01.** No design gap
remains and no accounting policy is left to the implementer. The only open gate
is governance: ECC-01 is `PROPOSED — RECOMMENDED FOR ACCEPTANCE`, and
ECC-A-11 (PG-01 cited as authority but absent from the repository) is still
owner-assigned. Work Package 1 is specified exactly in §24 and must not begin
until acceptance is recorded.

*Subsequent status (2026-07-26): both conditions are satisfied. ECC-01 is
`ACCEPTED — OWNER APPROVED` (not frozen), ECC-A-11 is resolved as Outcome B, and
Work Package 1 is authorised to begin — see the
[WP-1 authorisation report](ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md).
The readiness assessment below is preserved as issued.*

*Subsequent status (2026-07-29): WP-1 is implemented and certified. WP-2 was
separately authorised, and its detailed registry-authority specification is
complete. Engineering Amendment EA-001 corrected one impossible 64-byte
constraint identifier to the 59-byte
`ref_inventory_event_source_types_doc_order_key_algorithm_ck`. The correction
changes no design object, predicate, value, work-package boundary, rollback,
test intent, accounting meaning, ADR-C01 rule, or ECC-01 rule. At EA-001, the
WP-2 evidence allocation remained as then recorded; EA-002 subsequently
clarifies it below. At the EA-001 checkpoint, WP-2 remained unimplemented and
uncertified.*

*Subsequent status (2026-07-29, EA-002): the global test-family definitions in
§23 remain authoritative and historical numbering is unchanged: T-04 is Source
order (E4/E5), T-06 is Transition order (E7), T-07 is Effect order (E3), and
T-27 is Dormancy. EA-002 makes the already-required T-07 structural evidence
explicit for WP-2, classifies registry completeness as completion evidence
rather than a test-family name, and separates persistent M2 assertions from
rolled-back certification fixtures. It changes no implementation object,
predicate, value, work-package boundary, rollback, accounting meaning,
ADR-C01, or ECC-01.*

*Subsequent implementation status (2026-07-29): authorised WP-2 M2 was
implemented by migration `20260729000017` and tests `105`/`106`. Exactly six
dormant registry columns and their governed constraints were added; the
certification fixtures and isolated drop-column rollback are transactionally
rolled back. Fresh replay, full regression (106 files / 2,443 assertions), and
canonical accounting validation (30 / 748) pass. WP-2 remains not certified
until its independent Evidence Gate; WP-3…WP-9 and IA-6 remain unauthorised.*

*Subsequent Evidence Gate status (2026-07-29): the certification-review finding
against test `106` was confirmed and remediated by adding the explicit
exactly-one-registry-row rollback precondition. Fresh replay, focused WP-2
tests (69 assertions), full regression (106 files / 2,444 assertions),
canonical accounting (30 / 748), and catalog/security/dormancy checks pass.
The Evidence Gate recommends certification; WP-2 remains not certified pending
the separate Certification Mission. WP-3…WP-9 and IA-6 remain unauthorised.*

*Subsequent Engineering Amendment status (2026-08-01, EA-008; historical): the detailed
[WP-5 Event Admission and Component Resolution Specification](IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md)
closed WP5-AG-001…003. It fixes the replacement writer and resolver contracts,
separates fail-closed production admission from an owner-only rolled-back and
commit-rejecting certification fixture, counts the trigger function separately,
and defines totality, rollback and test ownership. It also corrects the
prospective M5 byte contract as a version vector plus thirteen persisted
components. The next independent gate rejected that rule and the conflicting
writer sequence; EA-009 supersedes those defective prospective portions without
rewriting EA-008 or changing a certified object.*

*Subsequent Authorisation Gate re-run and Engineering Amendment status
(2026-08-01, EA-009): the re-run returned **REJECTED** on exactly
WP5-AGR-001…003. EA-009 restores certified WP-4 as the authority for immutable
serialization/digest of all fourteen components, governs E2 = 0 for the only
eligible base/no-edge fixture, replaces §8.2's conflicting order with one
controlling writer algorithm, and establishes a fixed 527-file reproducible
protected-boundary proof. No WP-4 amendment is required. EA-009 grants no
implementation authority; WP-5 remains unauthorised and unimplemented pending
another separate gate.*

*Subsequent comprehensive gate and Engineering Amendment status (2026-08-01,
EA-010): the next complete gate returned **REJECTED** on
WP5-AGR2-001…004. EA-010 restricts M5 to initial resolution, governs all 139
columns written across seven tables, fixes UTC date derivation and function
configuration, and allocates a constructible reset-bounded two-session evidence
lane. It preserves certified WP-4 and records a mandatory separate lifecycle
stop before re-resolution or dependent activation. EA-010 grants no
implementation authority; WP-5 remains unauthorised and unimplemented pending a
comprehensive final gate.*

---

## 2. Governance and Authority

| Question | Evidence |
| --- | --- |
| Is ECC-01 formally accepted? | **Yes, since 2026-07-26** (`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`; ECC-01 header reads `ACCEPTED — OWNER APPROVED`, not frozen). *At the time this design was written the answer was No: the header read `PROPOSED — RECOMMENDED FOR ACCEPTANCE` and no acceptance record existed.* |
| Is this design phase authorised despite that? | **Yes.** ADR-C01 §17 authorises comparing IA-5 against the ADR, determining "the minimum additive authority hardening required", and classifying the correction — which is exactly this document. The acceptance report §24 names this phase as next. The owner's phase instruction authorises it explicitly. |
| May implementation begin? | **WP-1…WP-4 are certified bounded work packages.** EA-010 makes M5 specification-complete but grants no authority. WP-5…WP-9 remain unauthorised; the next mission is the comprehensive WP-5 Authorisation Gate re-run, not implementation. This document self-authorises nothing. |
| Is IA-6 authorised? | **No**, under the evidence gate §12.2 permission matrix and ADR-C01 §17. Unchanged by this design. |
| Is the C-01 program stop closed? | **No.** It closes only on executable conformance evidence (ADR-C01 §16). WP-9 produces that evidence; the gate, not this plan, closes the stop. |
| Freeze authority | **Resolved 2026-07-26** — ECC-A-11 closed as Outcome B: "PG-01" denotes the existing authority chain mapped in [`PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md); freeze authority is the owner's under `PXL_PRINCIPLES.md` §21, and ECC-01 is accepted but not frozen. |

**Authority order applied when sources disagreed** (`AGENT_SYSTEM_PROMPT.md`):
executed database behaviour first, then Tier 1 governing standards, then
implementation evidence. Every current-state statement in §3 was read from
migration source, not from a specification.

---

## 3. Current-State Implementation Map

Read from `supabase/migrations/20260726000013_inventory_accounting_ia5_foundation.sql`
(1,806 lines), `…000014` (38), `…000015` (25),
`supabase/tests/103_inventory_accounting_ia5_foundation_test.sql` (99
assertions), `supabase/migrations/20260630000028_inventory.sql` (legacy costing),
and `supabase/verification/ia5_*` (9 evidence assets).

### 3.1 IA-5 dormant foundation

| Object | Type | Owner | Purpose / current authority | Mutability | Chronology role | ECC-01 impact | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ref_inventory_event_source_types` | Table | Inventory | Source-type registry; 1 row `IA5_CERTIFICATION`; `CHECK (NOT is_production_enabled)`, `CHECK (is_certification_only)` | Insert-only + immutable trigger | None | Must gain per-type order authority (E4 rank, E5 algorithm, line-order authority, transition set, occurrence semantics, same-time class, correction placement class) — ECC-01 V-10 | **Extend** |
| `inventory_precision_policies` | Table | Accounting Policy | Effective-dated qty 0–6 / valuation 8 / rate 12 / currency scales | Immutable, dormant | Dependency of record | Unchanged; already ECC-conformant as a non-reordering version | **Preserve unchanged** |
| `inventory_accounting_profiles` | Table | Accounting Policy | Framework + precision binding, effective-dated | Immutable, dormant | Dependency of record | Unchanged | **Preserve unchanged** |
| `inventory_cost_formula_policies` | Table | Inventory Policy | Method (`fifo`/`moving_weighted_average`/`specific_identification`), scope type, transition evidence | Immutable, dormant | Dependency of record | Unchanged — costing method may not reorder (ECC-01 §3.2) | **Preserve unchanged** |
| `inventory_valuation_scopes` | Table | Inventory Master | Effective-dated scope **version** rows; `UNIQUE (company_id, item_id, scope_code, effective_from)` | Immutable, dormant | Partition (defective) | **Partition must be the scope key, not the version row** — ECC-01 §15(4), V-11 | **Extend** (stream mapping added beside it; table itself untouched) |
| `inventory_valuation_scope_sequences` | Table | Inventory | Accepted-sequence allocator; `UPDATE … RETURNING` on a shared row | **Mutable** (by design) | Accepted chronology | Sound as accepted evidence; **prohibited as an ECC component** (§2.2). Keyed on scope *version* → accepted numbering restarts on re-version | **Supersede** (re-key to stream; old table retained read-only) |
| `inventory_occurrences` | Table | Inventory | Atomic occurrence per (company, doc type, doc id, line id, transition, occurrence seq); idempotency + request fingerprint | Immutable | Accepted chronology | Grain is correct. Needs source-line ordinal + placement class inputs | **Extend** |
| `inventory_events` | Table | Inventory | Immutable event facts; 40 columns; `scope_sequence`, `event_sequence`, `source_occurrence_sequence`, `effective_at`, `accounting_date`, `occurrence_date`, ancestry FKs, caller fingerprint | Immutable (`ENABLE ALWAYS`) | Accepted chronology | Retains E1, E8, E9 and ancestry; **lacks E3 rank, E4, E5, E6, E7, E10 canonical form, X1–X4** | **Preserve unchanged**; ECC key added in a 1:1 sidecar (§6.1) |
| `inventory_events_deterministic_order_idx` | Index | Inventory | `(valuation_scope_id, effective_at, accounting_date, occurrence_date, scope_sequence, source_occurrence_sequence, event_sequence)` | — | **Misnamed**: accepted order | Contains a §2.2-prohibited component and three missing components; ECC-01 §15(3) requires replacement, not extension | **Supersede** (renamed in meaning, retained for accepted-chronology queries) |
| `inventory_events_scope_sequence_uq` | Constraint | Inventory | `UNIQUE (valuation_scope_id, scope_sequence)` | — | Accepted chronology | Keyed on scope version; splits accepted numbering across re-versions | **Supersede** |
| `inventory_events_logical_event_uq` | Constraint | Inventory | `UNIQUE (company, doc type, doc id, line id, transition, occurrence seq, event seq)` | — | Identity | **Already the E10 composite in relational form** — map to it, do not duplicate | **Preserve unchanged** (E10 canonicalises the same tuple) |
| `inventory_event_source_links` | Table | Inventory | Typed relationships (`primary`/`split`/`partial`/`predecessor`/`reversal`/`correction`/`transfer_pair`) | Immutable | Causal edges | Becomes the declared-edge source for E2; needs no new relationship type | **Extend** (validation only) |
| `inventory_event_values` | Table | Inventory | Authoritative txn/functional/GL-basis amounts, derived rate, residual units | Immutable | None | Unchanged — values are stage-7 inputs, not ordering | **Preserve unchanged** |
| `inventory_event_allocations` | Table | Inventory | `allocation_sequence`, `allocation_key`, `residual_rank`, `is_final_allocation` | Immutable | None | Already the S4 residual basis; consumed by IA-6 | **Preserve unchanged** |
| `inventory_projection_versions` | Table | Inventory | `UNIQUE (scope, projection_type, replay_watermark_sequence)`; dormant | Immutable | Projection | Keyed on an **accepted** watermark; ECC-01 §3.4 requires ECC-key bounds and a full version vector | **Replace later** (IA-6D) |
| `stock_balances.projection_authority` + 3 columns | Columns | Inventory | `CHECK (projection_authority='legacy_active' AND …IS NULL)` | Frozen by CHECK | Legacy projection | Unchanged in this phase | **Preserve unchanged** |
| `fn_ia5_record_dormant_inventory_occurrence` | Function | Inventory | Sole event writer; owner-only, no grants; allocates `scope_sequence` per event inside the loop | — | Admission | Must capture E5/E6/E7 ranks, placement class, and write the ECC key; **replace by DROP+CREATE, never an overload** (repo lesson: `fn_add_posting_line`) | **Extend** |
| `fn_ia5_create_dormant_policy_bundle` | Function | Inventory | Test-only dormant policy bundle creator | — | None | Extend to create the stream + order-policy bundle | **Extend** |
| `fn_ia5_guard_inventory_event_fact` | Function/Trigger | Inventory | Cross-entity identity, effective-period, precision, UOM, company validation on insert | — | Validation | Extend with ECC component validation (V-01…V-09) | **Extend** |
| `fn_ia5_guard_inventory_policy_foundation` | Function/Trigger | Inventory | Non-overlap + parent-period + company checks; `pg_advisory_xact_lock` per table/company | — | Validation | Pattern reused for order-policy versions | **Extend** |
| `fn_ia5_reject_immutable_inventory_fact` | Function | Inventory | Raises `23514` on UPDATE/DELETE; `ENABLE ALWAYS` on 11 tables | — | Immutability | Applied unchanged to every new table | **Preserve unchanged** |
| `fn_ia5_quantize_exact`, `fn_ia5_derive_unit_rate` | Functions | Inventory | Exact fixed-point guards (0–12 scale, capacity check) | — | Precision | Reused; N-09 satisfied | **Preserve unchanged** |
| RLS + grants | Policies | Security | RLS on 11 tables, `SELECT` only to `authenticated` via `is_company_member(company_id)`; all `fn_ia5_*` revoked from every role | — | — | Pattern applied identically to new objects | **Preserve unchanged** |
| `trg_*_audit` (10) | Triggers | Audit | `fn_audit_trigger()` AFTER INSERT | — | Audit | Applied to new tables | **Extend** |
| `103_…_ia5_foundation_test.sql` | Test | Inventory | 99 assertions; lines 1179–1194 assert two reads of the **accepted** order agree | — | Evidence | Assertions remain valid but are mislabelled "deterministic order"; ECC assertions added separately | **Extend** |
| `supabase/verification/ia5_final_*` (9) | Evidence assets | Inventory | Permutation, concurrency, atomicity, rollback/retry, UOM/policy, lineage, fingerprint, security, partition censuses | — | Evidence | Re-run against ECC (ECC-01 §14.3) | **Extend** |

### 3.2 Legacy active costing surface (context, not in scope)

| Object | Current behaviour | ECC relevance | Disposition |
| --- | --- | --- | --- |
| `stock_balances` | `qty_on_hand NUMERIC(15,4)`, `total_cost (18,2)`, `wac_unit_cost (18,6)`; keyed `(warehouse_id,item_id)` | Precision incompatible with IA-5 `(38,6)/(38,8)/(38,12)`; not scope-keyed | **Out of scope** (IA-6/IA-7 cut-over) |
| `inventory_cost_layers` | FIFO/Specific-ID layers; consumed `ORDER BY layer_date ASC, id ASC` | **`id` is a random UUID** — the FIFO tie-break is arbitrary, and `layer_date` is a DATE, not an instant | **Out of scope**; superseded by `inventory_fifo_layers` (IA-6B) |
| `fn_update_wac` | `wac_unit_cost = ROUND((total_cost + qty×rate)/(qty+in), 6)` written to `stock_balances` | **A rounded unit rate becomes the authority** — prohibited by ADR-C01 §9.4 and ECC-01 W1 | **Out of scope**; superseded by `inventory_wac_pool_versions` (IA-6B) |
| `fn_consume_cost_layers`, `fn_add_cost_layer`, `fn_receive_inventory`, `fn_post_stock_adjustment`, `fn_post_stock_transfer`, `fn_post_goods_issue`, `fn_post_physical_count` | Legacy active writers | Untouched by this plan | **Preserve unchanged** |

Recorded so the divergence is not silently inherited: the legacy engine
contains two defects ECC-01 already prohibits (random-UUID FIFO tie-break;
rounded WAC rate as authority). Neither is fixed here, because both live in
method state, which is IA-6. Registering them is the point.

### 3.3 What does not exist anywhere in the repository

Verified by search across `supabase/`, `src/`, `scripts/`: **no replay engine,
no chronology derivation, no ECC object, no method-state table, no projection
rebuild job, no scheduler, no background worker, and no inventory feature flag.**
IA-5 is admission only. Nothing must be un-built.

### 3.4 Code-versus-documentation divergences found

| # | Documentation | Code | Resolution |
| --- | --- | --- | --- |
| D-1 | `inventory_events_deterministic_order_idx` named "deterministic order" | Leads with lock-allocated `scope_sequence` | Code is authoritative; the name is wrong. Corrected by WP-6 comment + replacement index; already recorded in ECC-01 §14.1 |
| D-2 | IA-5 evidence doc §5 formerly claimed an "advisory lock" allocator | `UPDATE … RETURNING` row lock | Already corrected in the previous phase (finding ECC-A-12) |
| D-3 | Test 103 labels its order assertions "deterministic" | They prove accepted-stream stability only | WP-9 relabels and adds true ECC assertions; existing assertions stay valid |
| D-4 | IA-4 blueprint §4 lists `inventory_replay_versions` as a required table | Not implemented | Correct — it is IA-6D, not this phase |

---

## 4. Architecture-to-Implementation Traceability

Every normative ECC-01 element mapped. Status: **P** planned in this phase,
**IA-6** deferred to an authorised later phase (with the binding contract stated
here), **E** already satisfied by existing IA-5 objects.

### 4.1 Ordering components

| ECC-01 | Requirement | Implementation component | Data authority | Validation | Test | WP | Status |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| §4.2 E1 | Economic effective instant, UTC µs, source precision retained | `inventory_event_order_keys.economic_effective_at` + `source_precision_code` | Source workflow | V-01, V-03 (N-01/N-02) | T-01, T-10 | 3 | P |
| §4.2 E2 | Causal depth in equal-instant cohort | Derived at ordering from `inventory_event_source_links` + ancestry FKs | Declared edges only | V-08, V-20, V-21 | T-08, T-09 | 7 | P |
| §4.2 E3 | Effect rank 10/20/30/40/50 | `economic_effect_class` + `inventory_event_effect_ranks` | Event-order policy | V-05 (direction match) | T-07 | 1, 3 | P |
| §4.2 E4 | Source-type rank, unique per version | `inventory_source_type_ranks` | Registry + order policy | V-05, V-10 | T-04 | 1 | P |
| §4.2 E5 | Exactly one document-order-key algorithm per source type | `ref_inventory_event_source_types.document_order_key_algorithm` → `document_order_key` | Source domain | V-06 | T-04 | 1, 2 | P |
| §4.2 E6 | Immutable source-line ordinal | `inventory_event_order_keys.source_line_ordinal` (admission input) | Source domain | V-07, V-33 | T-05 | 2 | P |
| §4.2 E7 | Lifecycle-transition rank | `inventory_transition_ranks` | Registry | V-05, V-10 | T-06 | 1 | P |
| §4.2 E8 | Occurrence ordinal | **Existing** `source_occurrence_sequence` | Source domain | V-07 | T-05 | — | E |
| §4.2 E9 | Event ordinal, pure event plan | **Existing** `event_sequence` + new plan-purity rule | Inventory | V-07, V-13, **V-32** | T-03, T-20 | 2 | P (E for column) |
| §4.2 E10 | Canonical pre-admission identity, not DB-generated | `canonical_source_identity` (bytea) over the existing `inventory_events_logical_event_uq` tuple | Source domain | V-14, V-04 | T-03 | 3 | P |
| §4.3 X1 | Correction chain depth | `correction_chain_depth` | Correction graph | V-22 | T-08 | 4 | P |
| §4.3 X2 | Correction business instant | `correction_effective_at` | Correction workflow | V-22 (N-01) | T-08 | 4 | P |
| §4.3 X3 | Correction approval instant | `correction_approved_at` | Approval authority | V-22 | T-08 | 4 | P |
| §4.3 X4 | Correction identity | `correction_identity` (bytea) | Correction domain | V-14 | T-08 | 4 | P |
| §4.4 | Anchoring: `anchored` inherits root E1–E10; `independent`; `counterfactual_only` | `correction_placement_class` + root resolution in derivation | Registry | V-18, V-19, V-22 | T-08, T-09 | 4 | P |
| §4.5 | Lexicographic comparator over 14 components | `fn_ia5_ecc_compare` semantics + ordering index column order | — | V-15 | T-01 | 6, 7 | P |

### 4.2 Algorithm stages, replay, principles

| ECC-01 | Requirement | Component | WP | Status |
| --- | --- | --- | ---: | --- |
| §5.1 Stage 1 | Partition = scope **key**; re-version never splits or restarts | `inventory_valuation_streams` + stream-keyed allocator | 5 | P |
| §5.2 Stage 2 | Resolve + retain every component with its resolving version | Admission writer + order-key row | 3, 7 | P |
| §5.3 Stage 3 | Atomic occurrence; admission ≠ ECC position | Existing atomicity + `pending_costing` semantics | 2 | P |
| §5.4 Stage 4 | Population by partition, watermark, closed key interval; §5.4(5) no cohort/dependency truncation | `fn_ia5_ecc_population` (read-only, certification use) | 7 | P |
| §5.5 Stage 5 | Causal validation, cohort depth by longest path | Same function | 7 | P |
| §5.6 Stage 6 | Total sort; equal keys raise F-06, never a stable-sort fallback | Same function | 7 | P |
| §5.7 Stage 7 | Ordered-input fingerprint (first half) | `fn_ia5_ecc_ordered_input_fingerprint` | 7 | P |
| §5.7 Stage 7 | **Fold**, eligibility evaluation in ECC order | Method-state engine | — | **IA-6C** |
| §5.8 Stage 8 | Certification, promotion, atomic current-version switch | Replay/projection controls | — | **IA-6D** |
| §6.2–6.6 | Theorems 1–4 (uniqueness, schedule independence, insertion monotonicity, prefix stability) | Proved by construction; tested by T-19, T-15, T-16 | 9 | P |
| §6.7 | Late event → successor version from `K` | Contract stated §10.4; mechanism IA-6D | — | IA-6 |
| §6.8 | Counterfactual-only closed-period replay | Contract stated §14.5 | — | IA-6 |
| §6.9 | Cross-partition transfer ordering, never merging | `fn_ia5_ecc_population` partition graph check (V-27) | 7 | P |
| §3.2, §3.3 | Four reordering policy families; dependencies of record; digest identity; order re-resolution (V-35) | Four version tables + canonical form version | 1 | P |
| §3.4 | Bounds are complete 14-component keys, inclusive; watermark not portable (V-34) | Boundary record shape §10.2 | 7 | P |
| §2.1 P-01…P-10 | Derived-not-allocated, partitioned, total, non-null, immutable, versioned, accepted retained, version-scoped ordinal, order-before-eligibility, component-auditable | Enforced across WP-1…WP-7; P-09 is an IA-6 obligation restated in §11–§13 | 1–7 | P |
| §2.2 | Prohibited derivation inputs | Static census (T-21) + design rule | 8, 9 | P |
| §3.5 N-01…N-10 | Normalisation | `inventory_canonical_form_versions` + admission normalisation | 3 | P |
| §12 V-01…V-35 | Validation rules | §8.3 maps each rule to its enforcement point | 2–7 | P |
| §13 F-01…F-15 | Failure rules | §8.4 maps each to a SQLSTATE class and blast radius | 2–7 | P |
| §6.10 R-01…R-10 | Replay determinism checklist | R-01…R-08 exercised by WP-9; R-09/R-10 require the fold | 7, 9 | P / IA-6 |

---

## 5. Target Ownership Model

| Capability | Owning module | Authoritative source | Mutability | Versioning | Consumers | Prohibited consumers | Posting/Kernel boundary |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Event admission | Inventory Engine | `fn_ia5_record_dormant_inventory_occurrence` (sole writer) | Append-only | — | Source domains | Any client role; any UI | None |
| Accepted Event Chronology | Inventory Engine | `inventory_events.scope_sequence` + stream allocator | Allocator mutable; positions immutable | — | Audit, idempotency, watermark | **FIFO, WAC, Specific-ID, any costing order** | None |
| Economic Costing Chronology | Inventory Engine | `inventory_event_order_keys` (14 components) | Immutable | Version vector `V` | Ordering function, IA-6 method state | Posting, Tax, UI | Produces order only |
| Ordering policy (E3/E4/E7 ranks, canonical form) | Accounting Policy | `inventory_event_order_policies` + 3 rank tables | Immutable once used | Effective-dated versions | Admission resolution | Runtime callers | None |
| Costing method | Inventory Policy | `inventory_cost_formula_policies` (existing) | Immutable | Version | IA-6 fold | **Ordering** (may not reorder) | None |
| Precision / rounding | Accounting Policy | `inventory_precision_policies` (existing) | Immutable | Version | Values, IA-6 fold | Ordering | None |
| UOM normalisation | Master Data | `item_uom_conversions` (IA-4 planned) — today caller-supplied factor | Immutable version | Version | Admission quantity check | Ordering | None |
| Source-type / transition / effect ranking | Event Source Registry | `ref_inventory_event_source_types` + rank tables | Immutable | Order-policy version | Admission | Source domains | None |
| Replay execution | Inventory Engine | **IA-6D** — `inventory_replay_versions` | — | Replay algorithm version | IA-6 | This phase | None |
| Projection | Inventory Engine | `inventory_projection_versions` (dormant) → IA-6D | Immutable | Projection version | Reports after cut-over | This phase | None |
| Cost result | Inventory Engine | **IA-6C** method state | — | Replay version | Posting (as calculated input) | — | Posting consumes, never computes |
| Physical identity | Inventory Master | **IA-6B** `inventory_identities` | — | — | Specific-ID allocation | Ordering | None |
| Posting | Posting Engine | Six sanctioned persistence functions | — | — | — | Inventory | **Unchanged** |
| Audit | Audit Engine | `sys_audit_logs` via `fn_audit_trigger()` | Append-only | — | Auditors | — | Unchanged |
| Version authority | Accounting Policy | Four version families + `V` | Immutable once used | Self | Everything | — | None |
| Cut-off authority | Inventory (valuation) / Period (reporting) | Economic As Of = ECC key; Accepted Through = watermark | Immutable per version | Boundary record | Replay, reports | — | Accounting date stays Posting's |

No capability is ownerless. Three are explicitly deferred with their owner named.

---

## 6. Target Logical Data Model

Logical only — no SQL. Names are logical and follow repository convention.

### 6.1 Design decision: the ECC key is a current-resolution sidecar, not columns on `inventory_events`

| Option | Assessment |
| --- | --- |
| **Chosen — `inventory_event_order_keys`, one current row per event; WP-5 inserts one total initial row** | Keeps the certified event contract byte-identical; ordering index stays single-table; rollback is `DROP TABLE`; physically separates accepted authority (`inventory_events.scope_sequence`) from economic authority, which is ADR-C01 §5(3) expressed in the schema; lets the partition be the **stream** while the event keeps its scope-**version** reference as resolution evidence |
| Rejected — 14+ columns on `inventory_events` | Widens a table under `ENABLE ALWAYS` immutability whose contract 99 assertions already certify; mixes the two chronologies in one row; rollback means dropping columns other objects may reference; forces the partition correction into an existing FK |

Certified WP-4 enforces one **current** resolution through
`UNIQUE (inventory_event_id) WHERE resolution_state='current'`; it does not have
unconditional event uniqueness. EA-010 WP-5 adds the narrower initial-admission
rule that the event has zero key rows before insert and exactly one total/current
row afterward, plus a `DEFERRABLE INITIALLY DEFERRED` constraint trigger on
`inventory_events` requiring the current row at commit. No WP-5 successor or
supersession procedure exists. This reconciles the logical design with the
executable table without changing certified WP-4.

### 6.2 `inventory_valuation_streams` — the partition

| Attribute | Design |
| --- | --- |
| Purpose | One permanent partition per valuation-scope **key**, so an effective-dated re-version never splits or restarts a stream (ECC-01 §15(4), V-11) |
| Owner / source | Inventory Master; derived from `(company_id, item_id, scope_code)` |
| Authority | ECC partition identity; the only legitimate ECC grouping key |
| Type / nullability | UUID PK; `company_id`, `item_id`, `scope_code` all NOT NULL |
| Uniqueness | `UNIQUE (company_id, item_id, scope_code)` — the whole point |
| Immutability | Immutable; `ENABLE ALWAYS` reject trigger |
| Versioning | None — a stream is version-free by construction; scope *versions* remain in `inventory_valuation_scopes` |
| Validation | Company match with item; scope_code matches at least one scope version |
| Failure | Reject admission (F-02 class) if a stream cannot be resolved |
| Replay / audit role | Partition selector; recorded in every boundary and fingerprint |
| Existing data | None — created empty |
| Rollback | Drop after the order-key table |

**Controlling contract:** this table is specified to full governance standard —
exact columns, types, defaults, PK/UNIQUE/FK/CHECK identifiers, trigger strategy,
guard function, mutability, dormancy, activation rule, RLS, grants, audit,
replay, certification, rollback order, and runtime exclusions — by **Engineering
Amendment EA-004** in
[`IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md`](IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md)
§8–§10. **Dormancy is resolved there:** streams carries
`activation_state NOT NULL DEFAULT 'dormant'` with `CHECK (activation_state = 'dormant')`
**and** the `ENABLE ALWAYS` immutability trigger, matching the peer
`inventory_valuation_scopes`; activation is by migration only, per §21.

### 6.2.1 `inventory_valuation_stream_sequences` — the stream-keyed accepted allocator

The second of M3's two tables (§17 M3; §17 M9 "2 from M3"). It is the
stream-keyed successor to the existing `inventory_valuation_scope_sequences`
(§3.1 "re-key to stream"), required by ECC-01 §15(4) so accepted numbering never
restarts on a scope re-version.

| Attribute | Design |
|---|---|
| Purpose | One continuous **Accepted Event Chronology** counter per valuation stream |
| Owner / source | Inventory Engine (§5, "Accepted Event Chronology") |
| Authority | Accepted-chronology evidence only; **contributes no ECC component** (§2.2, §7) |
| Key | `PRIMARY KEY (valuation_stream_id)` (§18); no uniqueness keyed on a scope version |
| Mutability | **Partially mutable by design** — `last_sequence`/`updated_at` advance forward-only; `valuation_stream_id`/`company_id` immutable; `DELETE` prohibited |
| Immutability trigger | **Does not apply** — it would break `UPDATE … RETURNING` allocation; a partial-mutability guard is required instead |
| Dormancy CHECK | **Does not apply** — an allocator is neither a policy nor a key table; dormancy is proven by zero rows, no writer, and no grant |
| Existing data | None — created empty; rows are created by the future M5 writer |
| Rollback | Drop **before** `inventory_valuation_streams` (child before parent) |

**Controlling contract:** the complete column, key, constraint, mutability,
guard, grant, RLS, dormancy, validation, audit, replay, and rollback
specification is
[`IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md`](IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md)
(Engineering Amendment EA-003, 2026-07-30). That document changes no scope,
architecture, table count, ADR-C01 rule, or ECC-01 rule.

### 6.3 `inventory_event_order_keys` — the ECC key

| Field | Purpose / authority | Type concept | Null | Immutable | Versioned by |
| --- | --- | --- | --- | --- | --- |
| `inventory_event_id` | Event link; one current row structurally, one total initial row in WP-5 | UUID FK; partial current unique index | No | Yes | — |
| `company_id`, `valuation_stream_id` | Partition (§6.2) | UUID FK | No | Yes | scope-resolution |
| `economic_effective_at` | **E1**, UTC µs | timestamptz | No | Yes | canonical form |
| `source_precision_code` | Declared source precision retained (N-01) | enum-like text | No | Yes | canonical form |
| `economic_effect_class` | **E3** class: `opening`/`increase`/`value_only`/`decrease`/`allowance` | text domain | No | Yes | order policy |
| `economic_effect_rank` | **E3** rank resolved at admission (10/20/30/40/50, sparse) | smallint | No | Yes | order policy |
| `source_type_rank` | **E4** | smallint | No | Yes | order policy |
| `document_order_key` | **E5**, from exactly one registry algorithm | bytea (length-prefixed) | No | Yes | registry + canonical form |
| `source_line_ordinal` | **E6**, source-supplied | integer > 0 | No | Yes | — |
| `transition_rank` | **E7** | smallint | No | Yes | registry |
| `occurrence_ordinal` | **E8**, mirrors `source_occurrence_sequence` | bigint > 0 | No | Yes | — |
| `event_ordinal` | **E9**, mirrors `event_sequence` | integer > 0 | No | Yes | — |
| `canonical_source_identity` | **E10**, canonical encoding of the `inventory_events_logical_event_uq` tuple; **never DB-generated** | bytea | No | Yes | canonical form |
| `correction_placement_class` | `base` / `anchored` / `independent` / `counterfactual_only` | text domain | No | Yes | registry |
| `correction_chain_depth` | **X1** (0 = base fact) | integer ≥ 0 | No | Yes | correction graph |
| `correction_effective_at` | **X2**, sentinel at depth 0 (N-08) | timestamptz | No | Yes | canonical form |
| `correction_approved_at` | **X3**, sentinel at depth 0 | timestamptz | No | Yes | canonical form |
| `correction_identity` | **X4**, sentinel at depth 0 | bytea | No | Yes | canonical form |
| `correction_root_event_id` | Root target whose E1–E10 an anchored correction inherits | UUID FK, null only at depth 0 | Cond. | Yes | correction graph |
| `order_policy_version_id`, `registry_version_id`, `canonical_form_version_id`, `scope_resolution_version_id`, `correction_graph_version_id` | The version vector `V`, resolved at admission (P-06) | UUID FK ×5 | No | Yes | self |
| `canonical_key_bytes` | Certified WP-4 injective serialization of exactly all 14 ECC components in `E1…E10,X1…X4` order; EA-010 governs the WP-5 initial-resolution producer encoding and current base-source E2 = 0 | bytea | No | Yes | canonical form |
| `ecc_key_digest` | `sha256(canonical_key_bytes)`, DB-computed | bytea(32) | No | Yes | canonical form |

Uniqueness: `UNIQUE (valuation_stream_id, canonical_key_bytes)` — the direct
enforcement of V-14/V-15, so a duplicate key is a constraint violation rather
than a silent tie. Sentinels at depth 0 use one defined base-fact value each, so
no null-ordering rule exists (N-08).

**Controlling contract:** this table is specified to full governance standard —
exact columns including the `resolution_state` column §15 requires, exact SQL
types, defaults, PK/UNIQUE/FK/CHECK identifiers, indexes, mutability, dormancy,
trigger strategy, guard function, RLS, grants, audit, migration preconditions and
postconditions, rollback order, evidence allocation, and runtime exclusions — by
**Engineering Amendment EA-006** in
[`IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md`](IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md).
**Mutability is resolved there:** every economic, identity, and version column is
immutable; only `resolution_state` may change, and only `current` → `superseded`.
That is a certified **structural capability**, not a complete re-resolution
procedure: unconditional canonical-identity uniqueness still prevents a
version-only successor with unchanged comparator bytes. EA-010 therefore limits
WP-5 to initial resolution and requires a separate lifecycle amendment before
re-resolution. **Dormancy is resolved there** (corrected by **EA-007**): the table carries no
dormancy state column, matching the certified **per-event sidecars**
`inventory_event_values`, `inventory_event_source_links`, and
`inventory_event_allocations`. Dormancy is **inherited** — every row requires a
parent `inventory_events` row, and `inventory_events.foundation_state` is
`CHECK`-pinned to `'dormant'` — and is additionally proven by emptiness, no
writer, no grant, and zero consumers. The admission roots `inventory_events` and
`inventory_occurrences` carry `foundation_state`; configuration, policy, version,
and identity objects carry `activation_state`.

### 6.4 Version and registry objects

| Object | Purpose | Key | Immutability | Effective dating |
| --- | --- | --- | --- | --- |
| `inventory_event_order_policies` | Order-policy version: owns effect/source-type/transition ranks | `(company_id, policy_code, version_no)` | Immutable once referenced | Non-overlapping ranges (existing guard pattern) |
| `inventory_event_effect_ranks` | E3 class → rank; sparse (N-03) | `(order_policy_id, effect_class)` | Immutable | Inherits policy |
| `inventory_source_type_ranks` | E4; `UNIQUE (order_policy_id, rank)` **and** `(order_policy_id, source_document_type)` | Composite | Immutable | Inherits policy |
| `inventory_transition_ranks` | E7 per source type; declares the legal transition set | `(order_policy_id, source_document_type, transition)` | Immutable | Inherits policy |
| `inventory_canonical_form_versions` | N-01…N-10 encoding rules + **digest identity** (ECC-A-07) | `(version_code)` | Immutable | Activation-dated |
| `inventory_correction_graph_versions` | Anchoring semantics, chain rules, registered commutativity proofs | `(company_id, version_no)` | Immutable | Effective-dated |
| `ref_inventory_event_source_types` **extension** | Per-type: `document_order_key_algorithm`, `line_order_authority`, `occurrence_semantics`, `same_time_class`, `correction_placement_class`, `event_effect_map` | Existing PK | Immutable | — |

`ref_inventory_event_source_types` keeps `CHECK (NOT is_production_enabled)`
and `CHECK (is_certification_only)`. **Nothing in this plan enables a production
source type** — that is a later governance act requiring its own migration
(V-10, F-02).

### 6.5 Objects deliberately not created here

`inventory_replay_versions`, `inventory_fifo_layers`, `inventory_wac_pools`,
`inventory_wac_pool_versions`, `inventory_identities`, `inventory_deficits`, and
every other IA-4 §5–§6 table. They are IA-6. Creating them now would freeze
dependent keys before the evidence gate reopens — precisely what the gate's
Required Correction 5 forbids.

---

## 7. Stored Versus Derived Decisions

| Value | Classification | Why |
| --- | --- | --- |
| E1 instant, source precision | Source-supplied → admission-normalised → **persisted immutable** | N-01/N-02; a later master-data change must never move an event in time |
| E3 class | Source-supplied (from effect + registry map), validated against quantity direction | V-05; caller assertion contradicting direction is a defect, not an override |
| E3/E4/E7 ranks | **Persisted immutable policy references + resolved values** | P-06. Storing both the rank and its policy id makes the resolution auditable and prevents replay-time re-derivation (§14.2(1)) |
| E5 document order key | Source-supplied, admission-normalised, **persisted** | Recomputing from a mutable document number would let a rename reorder history |
| E6 line ordinal, E8, E9 | Source-supplied, **persisted immutable** | Pre-admission evidence |
| E10 canonical identity | **Derived deterministically at admission from retained source evidence, then persisted** | Must be recomputable byte-identically for audit (V-14) but never DB-generated |
| E2 causal depth | **Derived from declared cohort edges.** For current WP-5 it is exact `0`, persisted only inside the fourteen-component canonical bytes | The only eligible base source rejects every edge. Non-base/non-zero E2 remains fail-closed pending a separate contract; no WP-4 column is added |
| ECC ordinal | **Runtime-only, version-scoped** | P-08 — an ordinal without a replay version is not a citable fact |
| `canonical_key_bytes`, `ecc_key_digest` | Persisted, DB-computed | Makes V-15 a constraint instead of a hope |
| Ordered-input fingerprint | **Recomputable**; persisted only on a boundary record | V-25 requires reproduction to be meaningful |
| `scope_sequence` | Persisted accepted evidence, **excluded from every ECC path** | §2.2; retained under §15(2) |
| Method state (layers, pools, averages) | **IA-6 cached projection**, never primary | Rebuildable from events + ECC |
| `stock_balances` | Legacy projection | Unchanged this phase |

**Minimum persisted authority for stable replay:** the thirteen components
represented in dedicated WP-4 columns, the five separate version references,
the immutable causal-edge evidence, and the certified canonical byte string
containing exactly all fourteen components. In current WP-5, the only eligible
base source forbids every edge, so E2 is derived as 0 and appears only in
`canonical_key_bytes`; it does not require a new WP-4 column. A later source
with a non-zero causal graph remains fail-closed until separately governed.
Version references and admission metadata do not become pseudo-components.
With those immutable facts, a conforming implementation reproduces the same
fourteen-component key, order and fingerprint.

Four prohibitions this classification enforces: a database schedule cannot
decide order (no allocated value is in the key); recalculation cannot change
identity (identity is persisted, not recomputed into a new value); a cached
value cannot become authority (method state is IA-6 and rebuildable); derived
values cannot be hand-edited (immutability triggers plus no write grants).

---

## 8. Event Admission Hardening Design

### 8.1 New required admission inputs

`fn_ia5_record_dormant_inventory_occurrence` gains, per occurrence:
`p_source_line_ordinal`, `p_document_order_key_input`, and
`p_admission_context`; and, per event, `source_precision_code`,
`economic_effect_class`, plus the governed optional correction inputs. The
exact 14-argument signature, event JSON schema, defaults, validation and return
object are owned by the EA-010-current WP-5 specification §§3–4; no alternate placement or key
is authorised.

**Must be known before admission** (rejected if absent): E1, E5 input, E6, E8,
E9, effect class, source type, and every correction/causal reference. For the
only eligible base source, all such references must be null and E2 is therefore
derived exactly as 0. No source requiring a non-zero E2 is admitted by WP-5.
Later population ordinals and ordered-input fingerprints remain ordering-time
results.

Replace the function by `DROP` + `CREATE`, not by an additive overload — the
repository already learned this with `fn_add_posting_line` (P3): an overload is
not deployment-safe when the old signature remains callable.

### 8.2 Validation order at admission

The sole controlling algorithm is
[`IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`](IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md)
§3.5, as amended by EA-010. This programme design deliberately does not restate
its sequence. In particular, tenant/company/context validation and the minimum
strict normalization needed to recompute the governed fingerprint occur before
the company-scoped idempotency lookup; exact duplicate resolution occurs before
any stream, allocator, event or order-key write; and every new-path writer uses
the fixed occurrence → bytewise-sorted stream → allocator lock order. Any
failure rejects the **whole occurrence**. No alternative placement of
idempotency, stream allocation, component derivation or totality is authorised.

### 8.3 Validation-rule enforcement map

| Rules | Enforcement point |
| --- | --- |
| V-01, V-03, V-04, V-05, V-06, V-07, V-09, V-32, V-33 | Admission writer + `fn_ia5_guard_inventory_event_fact` extension (BEFORE INSERT) |
| V-02 | Static census (T-21) + code review; not a runtime check |
| V-08 | Writer: edges declared only by the dependent at its own admission |
| V-10, V-12 | Registry/version resolution in the writer |
| V-11 | Stream resolution (§6.2) |
| V-13 | Existing occurrence atomicity (single transaction) |
| V-14 | WP-4 `UNIQUE (valuation_stream_id,canonical_key_bytes)` + partial one-current-per-event index; EA-010 WP-5 also requires zero prior rows and one total initial row |
| V-15 | Ordering function — equal compare raises F-06, never a stable-sort fallback |
| V-16 | Existing idempotency path (retained unchanged) |
| V-17, V-18, V-23, V-31, V-34 | Boundary validation in `fn_ia5_ecc_population` |
| V-19, V-20, V-21, V-22 | Correction-graph + causal validation (admission for local rules, ordering for population rules) |
| V-24 | Ordinals assigned only after the complete sort |
| V-25 | Fingerprint recomputation test (T-16) |
| V-26, V-28 | **IA-6D** (needs the fold and promotion) |
| V-27 | Partition dependency graph check |
| V-29, V-35 | Certification lane (WP-9) / **separate future order re-resolution governance; not WP-5 and not yet allocated to an executable procedure** |
| V-30 | Design rule: no eligibility evaluation exists in this phase at all |

### 8.4 Failure mapping

| ECC-01 | Condition | SQLSTATE class | Blast radius | Retriable |
| --- | --- | --- | --- | --- |
| F-01 | Missing/ambiguous E1 | `22023` invalid parameter | Event → whole occurrence | Yes, after source supplies evidence |
| F-02 | Unregistered/incomplete source type | `22023` | Every event of that type | Only after registry approval |
| F-03 | Missing E5/E6/E7/E8/E9 | `22023` | Occurrence | Yes |
| F-04 | Prohibited derivation input detected | Census failure (not runtime) | **The engine** | No — requires correction |
| F-05 | Causal cycle / cross-company / missing predecessor / time contradiction | `23514` | Partition replay | Yes, after source correction |
| F-06 | Duplicate identity or equal keys | `23505` unique violation | Partition certification | Only after registry correction |
| F-07 | Idempotency conflict | `23505`/explicit raise (existing) | Request | Yes, as a new occurrence |
| F-08 | Correction fork without commutativity proof | `23514` | Partition replay | Yes |
| F-09 | Anchor root outside population | `23514` | Partition replay | Yes, with a wider boundary |
| F-10 | Anchored correction into a closed certified range | Counterfactual only | Certified range untouched | n/a |
| F-11 | Version-vector incompatibility | `23514` | Partition replay | Only after separately governed re-resolution; no current WP-5 remedy |
| F-12 | Fingerprint mismatch | Test/boundary failure | The version | Yes |
| F-13 | Cross-partition cycle | `23514` | Every partition in the cycle | Yes |
| F-14 | Pending-costing non-final result | **Not an error** — returns pending, consumes no identity | Request | By definition |
| F-15 | Permutation divergence | Certification failure | The engine | No |

F-14 deserves its own note: it must return a *result*, not raise. An issue that
loses a schedule race is never permanently rejected (ADR-C01 §7.8).

---

## 9. ECC Derivation Boundary

**Model: hybrid, mandated — not chosen for convenience.** Components are
resolved and persisted **at admission** because P-06 requires resolution at
admission and §14.2(1) forbids re-deriving a rank from current master data at
replay. Order and ordinals are derived **at ordering/replay time** because P-08
makes an ordinal valid only within a replay version and §5.6 assigns ordinals
only after the complete sort. Neither half may move.

| Aspect | Contract |
| --- | --- |
| Components | `fn_ia5_ecc_resolve_components(uuid,integer,text,text,uuid,timestamptz,timestamptz,text)` — exact 26-column return in the EA-010-current specification §5: all 14 current component values (E2 = 0 for the only eligible base/no-edge source), separate `V`, canonical bytes and digest; called only by the writer inside its transaction |
| Ordering | `fn_ia5_ecc_population` — inputs: stream, watermark, start/end complete keys, declared `V`; output: ordered event ids + per-adjacent-pair deciding component; **read-only**, `STABLE`, no writes |
| Fingerprint | `fn_ia5_ecc_ordered_input_fingerprint` — `sha256` over the length-prefixed concatenation of ordered `canonical_key_bytes`; PostgreSQL's built-in `sha256(bytea)` (PG 11+) avoids any extension dependency |
| Calling authority | Owner-only. No `EXECUTE` grant to `anon`, `authenticated`, or `service_role`, matching every existing `fn_ia5_*` |
| Transaction boundary | Admission: caller's transaction. Ordering: a single read-only snapshot; no advisory lock, no row lock |
| Locks | **None for ordering.** A lock cannot select or repair an ECC component (§6.9(4), Theorem 2). Locks remain only where method state is mutated — which is IA-6 |
| Prohibited dependencies | Everything in §2.2, plus current master data, `stock_balances`, method state, and `scope_sequence` |
| Determinism | Pure function of `(persisted components, V)`; `STABLE`/`IMMUTABLE` volatility marking is itself part of the contract |
| Error contract | §8.4; equal keys raise F-06 and never fall through to a tie-break |
| Idempotency | Ordering is naturally idempotent; admission idempotency is the existing key path |
| Observability | Ordering emits an evidence row (§20) with boundary, `V`, fingerprint, event count, duration |
| Performance | Ordering is one index scan over a partition plus an in-memory cohort depth pass; cohorts are small because they are equal-instant sets (§14.2(5)) |

Batch and single-event use are the same call — single-event ordering is a
population of one and is not a special path.

---

## 10. Replay Architecture

Only the **ordering half** is in scope. The fold, projection promotion, and
stale-projection cut-over are IA-6D; their contracts are stated so IA-6 cannot
reinterpret them.

### 10.1 Modes

| Mode | Permitted | Condition |
| --- | --- | --- |
| Full partition | Yes | Always valid; the certification default |
| Range-based | Yes | Only if §5.4(5) holds — the start bound truncates no cohort, no declared predecessor, no anchor root |
| Incremental | Yes, IA-6 | Reuses the **fold prefix** only; never a shortened ordering population (ECC-01 §6.6 as amended) |
| Checkpointed | Yes, IA-6 | Checkpoint at a certified ordinal; must still pass the V-26 full-rebuild comparison |
| Partitioned/parallel | Yes | Across streams only; never within one stream, and never merging streams (§6.9) |

### 10.2 Boundary record (logical)

`(company, valuation_stream, accepted_through_watermark, economic_start_key,
economic_end_key, predecessor_version, V = {order policy, registry set,
canonical form, scope resolution, correction graph}, replay algorithm version,
ordered-input fingerprint)`. Both economic bounds are **complete fourteen-
component keys** and **inclusive**; the watermark is inclusive and **not
portable across environments** (V-34).

### 10.3 Sequence

Select population (§5.4 + V-31) → validate causality and build cohort depth →
sort by the 14-component comparator → assign ordinals → serialise and fingerprint
→ **stop.** Everything after this line — fold, comparison, promotion — is IA-6.

### 10.4 Late events, failure, concurrency

A late event computes `K` = its own key and requests a successor version from
`K`; it never mutates a prior version. Any validation failure produces **no
version at all** — there is no partial ordering output. Concurrent ordering
requests for one stream are safe by construction because ordering writes
nothing; when IA-6 adds the fold, mutual exclusion belongs to method-state
promotion, not to ordering (§28 case 15).

---

## 11. FIFO Implementation Design (consumption contract — IA-6B/C)

FIFO is not implemented here. This is the binding contract on the phase that
does.

| Concern | Contract |
| --- | --- |
| Layer creation | One layer per owned-acquisition event, created **in ECC order**, never in `created_at` or UUID order |
| Layer identity | `inventory_fifo_layers` keyed on the receipt event id; the queue orders by the **ECC key**, never by `layer_date, id` as the legacy engine does |
| Consumption | Ascending ECC key of eligible layers; partial consumption records exact remaining quantity and value |
| Same-time events | E3 places equal-instant increases before decreases; F1/F2 are the acceptance cases |
| Backdating | Successor version from `K`; the queue is replayed forward (B1) |
| Correction | Anchored correction adjusts the target layer fact in a successor version; the original layer row is never rewritten (C1) |
| Reversal | Independent event at its own instant (C4) |
| Transfer | Preserves acquisition ancestry and carrying value; cross-stream ordering per §6.9 |
| Negative inventory | **Governed elsewhere** — prohibited by default under ADR-C01 §8.11 and the frozen Costing Specification. No new policy is defined here |
| Rebuild / staleness | Layer state is rebuildable from events + ECC; a layer set without its replay version is uninterpretable |
| Existing FIFO code | `fn_consume_cost_layers`, `fn_add_cost_layer`, `inventory_cost_layers` remain legacy-active and untouched; their random-UUID tie-break is registered in §3.2 as a defect that IA-6 supersedes |

---

## 12. Moving WAC Implementation Design (consumption contract — IA-6B/C)

| Concern | Contract |
| --- | --- |
| Sequence | Every economically applied event creates the next pool version **in ECC order** |
| Running quantity/value | Exact fixed-point accumulation; no intermediate rounding |
| Issue cost | `quantity × pool_value / pool_quantity` from the authoritative extended value **immediately preceding** the issue's ECC position. **A rounded unit rate is never the authority** — the legacy `fn_update_wac`, which writes `ROUND(…, 6)` to `stock_balances.wac_unit_cost`, is exactly the pattern being superseded |
| Precision | Quantity scale from the precision policy (0–6); valuation 8; derived rate 12 — already enforced by `fn_ia5_quantize_exact` |
| Rounding points | Only at the GL-basis boundary, at the precision policy's `gl_basis_scale` |
| Inbound-group permutation | Aggregate is invariant (exact addition commutes), but the **pool version chain is not** — a nondeterministic inbound order produces two different certified histories for one fact set (ECC-01 §8.1). This is why W1's ordering still matters |
| Zero / negative states | Zero-quantity pool states are explicit; negative is prohibited by default under the existing policy |
| Re-cost vs reorder | A dependency-of-record change produces a successor version with an **identical ordered-input fingerprint** and a different method-state fingerprint. A differing ordered-input fingerprint under such a change is F-12 |
| Backdating / correction | Rebuild from the earliest affected ECC key (W3: deltas +80.00, +60.00, ending +1,260.00; `1,400.00 = 1,260.00 + 80.00 + 60.00`) |

The ECC-01 arithmetic was independently reconciled during the acceptance gate
and is unchanged here: W1 issue cost 1,380.00 from pool `(20.00, 2,300.00)`;
C1 `150.00 = 90.00 + 60.00`; C2 net `+100.00 = +60.00 + 40.00`. No blocking
finding arose, so no rule is altered.

---

## 13. Specific-ID Implementation Design (consumption contract — IA-6B/C)

Three concerns must stay separate, and the schema must make the separation
visible:

| Concern | Owner | Rule |
| --- | --- | --- |
| **Economic ordering** | ECC | Orders the events; has no opinion on which identity supplies cost |
| **Physical allocation** | `inventory_identities` / `inventory_specific_id_values` (IA-6B) | The named lot/serial supplies the cost |
| **Identity validity** | Identity authority | Existence, ownership, eligibility, non-duplication |

| Concern | Contract |
| --- | --- |
| Identity source | Today `inventory_events.lot_number` / `serial_number` are **TEXT evidence, not governed identity** (evidence gate §7). IA-6B introduces `inventory_identities`; ECC does not wait for it and does not substitute for it |
| Duplicate physical identity | **Not an ECC failure.** Ordering proceeds; the second claim is rejected at eligibility in ECC order (S3). No tie-break may legitimise both claims |
| Missing identity | Reject economic application — chronology cannot create identity (S2) |
| Partial lot occurrences | E8 orders them; the **final** occurrence absorbs the exact residual (S4: 33.33333333 + 33.33333333 + 33.33333334) |
| Transfer / correction / reversal | Preserve identity, ancestry, carrying value |
| Backdating / replay | Ordering only; identity eligibility re-evaluated in the new order |

A deterministic tie-break must never conceal invalid physical identity. That is
why §13's failure table in ECC-01 was amended during the acceptance gate to say
so explicitly (ECC-A-10).

---

## 14. Correction and Reversal Design

| Case | Placement class | Key construction | Validation |
| --- | --- | --- | --- |
| Correction of a base fact | `anchored` | Inherits root's E1–E10; X1=1, X2/X3/X4 own | V-18, V-19, V-22 |
| Correction of a correction | `anchored` | Same root; X1 = parent + 1 | V-22 (depth exactly parent+1, no cycle) |
| Partial correction | `anchored` | Same construction; the delta is a stage-7 concern | V-19 |
| Replacement / supersession | `independent` | Own E1–E10 at its own instant; linked by `inventory_event_source_links` | V-20 |
| Reversal | `independent` | Own key, base-fact sentinels; **never inherits the target's instant** — anchoring a reversal would misstate its period (C4) | V-20 |
| New independent economic event | `base` | Ordinary key | V-01…V-09 |
| Closed-period correction | `counterfactual_only` | Computed at its anchor in a **non-certifying** replay; never inserted into a certified closed stream | F-10 |

Stored references: `correction_root_event_id` (root, for anchoring),
`correction_of_event_id` (existing, immediate parent), and the existing
`inventory_event_source_links` row with `relationship_type='correction'`. Root
resolution walks the parent chain at admission and **persists the resolved
root**, so ordering never re-walks a graph. Cycle prevention: depth must be
exactly parent+1 and the parent must already be admitted (V-08 makes forward
references impossible, so a cycle cannot form).

Fork handling: two corrections against one target, neither naming the other,
with no registered commutativity proof → **V-19 rejects before ordering**
(F-08). ECC does not order them by X2/X3/X4 in that situation; that path exists
only when a proof is registered.

Economic-fact update-in-place is impossible by construction: certified
`ENABLE ALWAYS` guards protect immutable occurrence/event/evidence/policy/
stream/key facts. The WP-3 stream allocator is the explicit partial-mutability
exception—only its counter/timestamp advance—and WP-5 uses that exception only
through the governed allocator operation. WP-5 never updates an order key.

---

## 15. Version and Policy Design

| Family | Owner | Effective dating | Immutable once used | Reorders? | Re-costs? | Missing-version behaviour |
| --- | --- | --- | --- | --- | --- | --- |
| Ordering policy (E3/E4/E7 ranks) | Accounting Policy | Non-overlapping ranges | Yes | **Yes** | No | F-11 reject replay |
| Source registry (per type) | Registry | Per-type version | Yes | **Yes** | No | F-02 type unavailable |
| Scope resolution | Inventory Master | Effective-dated | Yes | Repartitions only | No | Reject admission |
| Correction graph | Inventory | Effective-dated | Yes | **Yes** | No | F-11 |
| Canonical form (+ digest identity) | Accounting Policy | Activation-dated | Yes | Yes, via encoding | No | F-11 |
| Costing method | Inventory Policy | Existing | Yes | **No** | Yes | Reject fold (IA-6) |
| Precision / rounding | Accounting Policy | Existing | Yes | **No** | Yes | Reject fold |
| UOM normalisation | Master Data | Version | Yes | **No** | Yes | Reject admission |
| Replay algorithm | Inventory | Build identity | n/a | No | No | F-11 |
| Fingerprint / digest | = canonical form | — | Yes | n/a | n/a | Fingerprints incomparable → F-12 |

**Order re-resolution (V-35).** A partition holding events resolved under two
order-policy versions is not replayable — F-11 rejects it. The only remedy is a
governed re-resolution that writes *new* order-key rows under the target version
while retaining the prior rows as superseded evidence, re-deriving only from
retained immutable source evidence, producing a successor version with a uniform
`V`. It is never triggered implicitly by the arrival of a newer-version event.
Implementation consequence: `inventory_event_order_keys` needs a
`resolution_state` (`current`/`superseded`) plus `UNIQUE (inventory_event_id)
WHERE resolution_state = 'current'` — a partial unique index, so 1:1 holds for
the current resolution while history is retained. That column and its governed
`current` → `superseded` transition are specified exactly by **EA-006** §2.2 and
§3 in
[`IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md`](IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md);
component immutability is unweakened, because demotion edits no ordering value.

**EA-010 executable-lifecycle limitation.** The paragraph above records ECC-01's
required future semantics and WP-4's structural state column; it is **not** an
authorised executable procedure. Certified WP-4 also has unconditional
`UNIQUE (valuation_stream_id,canonical_key_bytes)`. If a version-only
re-resolution leaves all fourteen comparator components unchanged, the retained
superseded row and proposed successor collide. WP-5 therefore owns initial
resolution only: it rejects any pre-existing key for the event, never demotes a
row, and never inserts a successor. Before any re-resolution, WP-7 feature that
depends on it, or production activation, a separately governed WP-4 lifecycle
amendment or later work package must settle resolution-aware uniqueness without
silently changing ECC-01 or certified WP-4.

**Effective-dated re-versioning must not split a stream.** The stream key
(§6.2) is version-free, which is the structural fix for ECC-01 §15(4).

---

## 16. Existing Data and Backfill Plan

### 16.1 Classification — measured, not assumed

| Class | Rows | Evidence |
| --- | ---: | --- |
| Production-sensitive | **0** | Every migration from `20260723000001` onward is local-only; the hosted project has never received IA-5 (`AI_STATE.md`, Environment) |
| Existing development data | **0** | Evidence gate §3: `inventory_events` count `0` after clean reset; concurrency company count `0` |
| Test-only / disposable | Created and rolled back per test | Test 103 and the `ia5_final_*` assets create their own fixtures inside transactions |
| Impossible by construction | — | `CHECK (NOT is_production_enabled)` + `CHECK (is_certification_only)` mean no production source type can ever have admitted an event |
| Fully derivable / requires mapping / ambiguous / invalid | **0** | Empty set — there is nothing to derive, map, or quarantine |

### 16.2 Consequences

1. **No backfill exists.** `NOT NULL` columns and new tables are created against
   empty relations; no default that affects accounting order is invented,
   because no default is needed at all.
2. The immutability triggers, which would block any `UPDATE`-based backfill, are
   never exercised — a fortunate alignment worth stating: had rows existed, a
   backfill would have required either disabling an `ENABLE ALWAYS` trigger
   (prohibited) or a new table.
3. **Supported data scope for the first implementation: empty databases and
   canonical/certification test data only.** Existing development data: none
   exists. Hosted data: explicitly out of scope and requires separate approval.
   Production data: prohibited — no production source type is enabled.
4. If a future execution finds a non-zero `inventory_events` count, **that is a
   stop condition**, not a backfill exercise: it would mean a source type was
   enabled without governance. WP-1 begins with that count as a precondition
   check.

---

## 17. Migration Strategy

Nine migrations, one purpose each, additive and staged. No migration combines
unrelated changes; no migration is destructive.

| # | Migration purpose | Objects | Preconditions | Locking | Backfill | Validation | Rollback | Risk |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| M1 | Order-policy + rank + canonical-form + correction-graph version tables | 6 new tables (§6.4 rows 1–6), guards, RLS, audit triggers | `inventory_events` count = 0 | New tables only — no lock on existing objects | None | Structure + dormancy test | `DROP TABLE` (reverse dependency) | Low |
| M2 | Registry extension: per-type order authority columns | `ref_inventory_event_source_types` + columns | M1 | `ACCESS EXCLUSIVE` on a 1-row table | Set for `IA5_CERTIFICATION` only | Persistent registry completeness assertions plus rolled-back T-04/T-06/T-07/T-27 certification evidence | Drop columns | Low |
| M3 | `inventory_valuation_streams` (§6.2) + `inventory_valuation_stream_sequences` (§6.2.1) | 2 new tables | M1 | New tables | None | Stream uniqueness test | Drop | Low |
| M4 | `inventory_event_order_keys` + constraints + partial unique index | 1 new table, partial unique index | M1–M3 | **New table only** — no existing object is altered (EA-006 §5.4 moves the event-side 1:1 deferrable trigger to M5, whose writer is its precondition) | None | 1:1-per-current-resolution enforcement test | Drop table, drop guard function | Low — purely additive |
| M5 | EA-010-current initial-resolution writer replacement + component resolver + event-side totality | **3 functions (1 replaced, 2 created) + 1 constraint trigger** | M1–M4 | Replace owner-only writer; add deferrable trigger metadata to `inventory_events` (brief `ACCESS EXCLUSIVE`); no column/row/index/policy change | None | Future tests `111`/`112`, reset-bounded `WP5-CONC-114`; bounded regression `103`…`110` | Drop trigger, trigger function, resolver, new writer; restore exact M0 writer/ACL/comment; future test `113` | Medium — exact EA-010-current contract; touches existing writer and trigger set |
| M6 | Guard extension for ECC component validation | 1 function replaced | M5 | Function-level | None | Validation-rule tests | Restore | Medium |
| M7 | ECC ordering + fingerprint functions (read-only) | 2 functions | M4 | None | None | Ordering + fingerprint tests | Drop | Low |
| M8 | Replacement ECC ordering index; comment-correct the superseded index | 1 index added; 1 comment | M4 | Index build on an empty table is instant | None | Index presence + composition test | Drop index | Low |
| M9 | Table-coverage registry entries for the 9 new tables (6 from M1, 2 from M3, 1 from M4) | Documentation + guard `075` fixture | M1–M4 | None | None | Guard 075 passes | Revert | Low |

**Deployment pattern:** Expand (M1–M4) → Backfill (**none required**) →
Validate (M9 + WP-9 lane) → Enforce (M5–M6 make components mandatory at
admission) → Switch consumer (**not in this phase** — no consumer exists) →
Observe → Freeze (evidence gate). Because there is no consumer and no data, the
usual expand/contract risk profile collapses to "add, prove, leave dormant".

Hosted application of any migration remains prohibited without explicit
approval.

---

## 18. Index and Constraint Design

| Object | Purpose | Correctness or performance | Composition | Notes |
| --- | --- | --- | --- | --- |
| `inventory_event_order_keys_ecc_idx` | The ECC ordering scan | Performance (ordering correctness is the comparator's) | `(valuation_stream_id, economic_effective_at, economic_effect_rank, source_type_rank, document_order_key, source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal, canonical_source_identity, correction_chain_depth, correction_effective_at, correction_approved_at, correction_identity)` | E2 is intentionally absent — causal depth is population-derived and cannot be indexed. The scan yields cohorts in order; depth is applied in memory |
| `…_identity_uq` | V-14 / V-15 as a constraint | **Correctness** | `UNIQUE (valuation_stream_id, canonical_key_bytes)` | Makes a duplicate key a `23505`, not a silent tie |
| `…_event_current_uq` | 1:1 per current resolution | **Correctness** | `UNIQUE (inventory_event_id) WHERE resolution_state='current'` | Partial index structurally permits retained superseded rows; EA-010 WP-5 inserts initial resolution only (§15) |
| `…_anchor_idx` | Correction-graph traversal | Performance | `(correction_root_event_id, correction_chain_depth)` | Supports V-18/V-19 |
| `…_version_idx` | Version-vector resolution and F-11 detection | Performance | `(valuation_stream_id, order_policy_version_id, canonical_form_version_id)` | |
| `inventory_valuation_streams_key_uq` | One stream per scope key | **Correctness** | `UNIQUE (company_id, item_id, scope_code)` | The §15(4) fix |
| `inventory_valuation_stream_sequences` PK | Continuous accepted numbering per stream | **Correctness** | `PRIMARY KEY (valuation_stream_id)` | Replaces version-keyed allocation; full contract in the WP-3 detailed specification (EA-003) |
| `inventory_source_type_ranks` uniqueness | E4 rank uniqueness per policy version | **Correctness** | `UNIQUE (order_policy_id, rank)` and `(order_policy_id, source_document_type)` | Required by E4 validation |
| Existing `inventory_events_logical_event_uq` | E10's relational form | Correctness | Unchanged | Mapped, not duplicated |

**Explicitly not proposed:** any uniqueness rule keyed on a policy version that
would split one economic stream across versions. Uniqueness is keyed on the
**stream**, never on the version — the mistake ECC-01 §15(4) identifies.

Expected cardinality: one order-key row per event (1:1); rank tables in the tens;
streams ≈ company × item × scope. Concurrency impact: index maintenance on
insert only; ordering takes no locks. Backfill impact: none (empty tables).

---

## 19. Security and RLS Design

Reuses the existing IA-5 pattern exactly; nothing is weakened.

| Control | Design |
| --- | --- |
| Company isolation | Every new table carries `company_id`; RLS `SELECT`-only to `authenticated` via `is_company_member(company_id)` |
| Stream isolation | Stream carries company; no cross-company stream can resolve (P-02) |
| Write surface | `REVOKE ALL` from `PUBLIC, anon, authenticated, service_role`; `GRANT SELECT` only. **No role can insert an order key** |
| Function execution | Every new `fn_ia5_*` revoked from all roles; owner-mediated only, matching the existing seven |
| SECURITY DEFINER | Only where the existing pattern already uses it (writers/guards), always with `SET search_path = public` |
| System-only fields | The entire order-key row is system-only; immutability triggers make even the owner unable to `UPDATE` |
| Manual edit | Impossible: no grant, no UPDATE path, `ENABLE ALWAYS` reject trigger |
| Ordering execution permission | Owner-only in this phase; IA-6 decides any service exposure |
| Policy/version administration | Owner-mediated bundle function; no client path |
| Cross-company replay | Prevented by stream resolution + V-20 single-company edge validation |
| Audit visibility | `fn_audit_trigger()` AFTER INSERT on every new table |
| Frontend | No UI surface is added; nothing relies on client-side checks |

---

## 20. Audit and Observability Design

| Record | Content | Immutable |
| --- | --- | --- |
| Admission audit | Existing `sys_audit_logs` rows via `fn_audit_trigger()` on every new table | Yes |
| Component resolution evidence | The order-key row itself — every component plus its five resolving versions | Yes |
| Deciding-component trace | Per adjacent pair, which component decided the order (ECC-01 §14.2(7), §5.9) — emitted by the ordering function as evidence output | Derived |
| Ordering run evidence | Boundary, `V`, event count, ordered-input fingerprint, duration, outcome | Append-only |
| Fingerprint mismatch | Both fingerprints + the first divergent ordinal (F-12, F-15) | Append-only |
| Correction-chain audit | Root, depth, parent, placement class, classification | Yes (in the key row) |
| Failure / quarantine | Failure code + evidence on the existing rejected-occurrence path | Yes |
| Metrics | Ordering duration, event count, stream count, cohort size distribution, validation-failure counts | Operational |
| Not logged | Full source payloads beyond the existing `immutable_source_evidence`; no new sensitive data is captured |

Projection supersession, re-cost counts, and reorder counts are **IA-6D**
metrics — listed so IA-6 owns them explicitly rather than inventing them.

---

## 21. Dormancy and Activation Controls

| Control | Mechanism |
| --- | --- |
| Source types | `CHECK (NOT is_production_enabled)` and `CHECK (is_certification_only)` retained unchanged — a production type requires its own governed migration |
| New tables | `activation_state`/`foundation_state` `CHECK … = 'dormant'` on every new policy and key table, matching the existing pattern |
| Functions | No `EXECUTE` grant to any role |
| Consumers | **Zero.** No current workflow, report, RPC, or UI reads `inventory_event_order_keys`; `stock_balances` keeps `projection_authority='legacy_active'` with all IA-5 columns forced NULL |
| Jobs / schedulers | None exist and none are created |
| UI | Unchanged; no route, component, or type is added |
| Reports | Unchanged; valuation reports keep reading legacy projections |
| Posting | Unchanged; no new journal path |
| Feature flags | None — dormancy is enforced by CHECK constraints and absent grants, which cannot be toggled at runtime. This is deliberate: a flag can be flipped; a constraint requires a migration |
| Activation requires | (1) recorded ECC-01 acceptance; (2) a passed reopened evidence gate closing C-01; (3) explicit IA-6 authorisation; (4) a separate migration enabling a production source type. Implementation completion is **not** activation authority |

---

## 22. Posting and Kernel Boundary

| Question | Answer | Evidence |
| --- | --- | --- |
| What does this produce? | A deterministic order and a fingerprint over that order | §9 |
| What does it not produce? | Any cost, layer, pool, average, valuation, projection, or journal | §1 scope decision |
| Creates journal entries? | No | No `journal_entries` DML anywhere in the plan |
| Mutates journal entries? | No | — |
| Selects GL accounts? | No | COA resolution untouched |
| Determines tax? | No | Tax is not an ECC input (ECC-01 §2.3) |
| Bypasses sanctioned mutators? | No | The six persistence functions and both `ENABLE ALWAYS` totality triggers are untouched |
| Changes posted-document immutability? | No | — |
| Changes period locking? | No | Accounting date and Posting watermark remain Posting's |
| Changes journal validation? | No | — |
| Touches `fn_add_posting_line` or the guard? | No | P5.2 enforcement remains compile-time `true` |

`inventory_events.journal_entry_id` stays `CHECK (journal_entry_id IS NULL)` and
`inventory_occurrences` keeps `posting_request_id`/`posting_result_id` NULL. Any
required Posting or Kernel change would be a stop condition; none is required.

---

## 23. Test and Certification Plan

Thirty families. Layer: **U** unit/structural, **I** integration, **C**
concurrency (two-session), **S** static census, **P** performance.

| ID | Family | Purpose | Inputs | Expected | Failure condition | Layer | Blocks certification |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| T-01 | Deterministic tuple | Comparator yields one order | Fixed 14-component set | Single enumeration; deciding component recorded | Any residual tie | U | Yes |
| T-02 | Admission validation | Every required component enforced | Payloads with each field omitted | Reject, occurrence-wide | Any partial admission | I | Yes |
| T-03 | Duplicate identity | V-14/F-06 | Two facts, one canonical identity | `23505`, both rejected | Silent tie-break | I | Yes |
| T-04 | Source order | E4/E5 | Two same-instant documents | Registry rank then document key decide | Arrival decides | I | Yes |
| T-05 | Line + occurrence order | E6/E8 | Lines and occurrences submitted reversed | Source order retained | Submission order retained | I | Yes |
| T-06 | Transition order | E7 | Two transitions, one instant | Rank decides | Unranked transition admitted | I | Yes |
| T-07 | Effect order | E3 | Same-instant receipt + issue | Increase before decrease | Any other order | I | Yes |
| T-08 | Correction chain | X1–X4, anchoring | Correction, correction-of-correction | `e1, k1, k2, e2` | Wrong anchor or depth | I | Yes |
| T-09 | Cycle + fork rejection | V-19/V-22/F-05/F-08 | Fork without proof; cyclic edges | Fail closed | Any ordering produced | I | Yes |
| T-10 | Backdating | E1 dominance | Backdated receipt after an issue | Inserted at its key | Appended at the end | I | Yes |
| T-11 | Dual cut-off | Inclusivity, complete keys | Events exactly at each bound | Closed interval `[start,end]` | Boundary ambiguity | I | Yes |
| T-12 | FIFO consequence | ECC → FIFO divergence closed | F1–F4 fixtures, both schedules | Identical COGS/ending | Any divergence | I | Yes |
| T-13 | WAC consequence | ECC → WAC divergence closed | W1–W3 fixtures | 1,380.00; W3 deltas exact | Any divergence | I | Yes |
| T-14 | Specific-ID | Order cannot select identity | S1–S3 fixtures | Named identity supplies cost; duplicate claim rejected | Tie-break legitimises both | I | Yes |
| T-15 | Replay repeatability | Theorem 1 | Same boundary twice | Byte-identical order | Any difference | I | Yes |
| T-16 | Fingerprint | V-25 | Recompute over one boundary | Identical digest | Mismatch | I | Yes |
| T-17 | Policy version | V-17/V-35/F-11 | Mixed-version population | Reject; no WP-5 remedy; future separately governed re-resolution must pass its own evidence | Silent mixed replay or unsupported successor claim | I | Yes |
| T-18 | Precision version | Re-cost ≠ reorder | Precision change | Ordered-input fingerprint **unchanged** | Order changes | I | Yes |
| T-19 | Concurrency schedules | V-29/F-15, Theorem 2 | Same command set, ≥2 schedules incl. randomised, independent resets | Identical fingerprints | Any divergence | C | **Yes — closes C-01** |
| T-20 | Event-plan purity | V-32 | Same payload, different concurrent state | Identical E9/E10 | Plan varies | I | Yes |
| T-21 | Prohibited-input census | V-02/F-04 | Static scan of every ECC component's dependencies | No `scope_sequence`, clock, UUID default, or lock outcome | Any hit | S | **Yes** |
| T-22 | Multi-company isolation | P-02 | Cross-company edges and streams | Rejected | Any cross-company order | I | Yes |
| T-23 | RLS | No weakening | Each role against each new table | `SELECT` only per membership | Any write or cross-company read | I | Yes |
| T-24 | Immutability | UPDATE/DELETE rejection | Both ops on every new table | `23514` | Any mutation | I | Yes |
| T-25 | Rollback | Retry consumes no identity | Rollback then retry | Same key reused | Identity consumed | I | Yes |
| T-26 | Migration/backfill | Empty-precondition | Fresh `--no-seed` replay | Count 0; all objects present | Non-zero events | I | Yes |
| T-27 | Dormancy | No activation | Grants, CHECKs, consumers | Zero grants; every dormancy CHECK present | Any reachable path | I | **Yes** |
| T-28 | Posting boundary regression | Nothing moved | Full regression + canonical lane | Fingerprints and totals identical (debit = credit = `2,411,134.80`) | Any change | I | **Yes** |
| T-29 | Canonical dataset | No accounting change | Canonical lane | 30 files / 748 assertions unchanged | Any drift | I | Yes |
| T-30 | Performance | Ordering cost | 100K events in one stream | Documented scan + depth cost | Unbounded growth | P | No (advisory) |

**Evidence-gate requirements.** T-19 and T-21 together are what close C-01:
identical fingerprints across independent schedules, and no prohibited input
anywhere in the derivation. T-12/T-13 supply ADR-C01 §17(4)'s FIFO and WAC
consequence proofs **without implementing method state** — the consequence is
computed inside the test as a fold over the ECC-ordered stream and compared
across schedules; it persists nothing and creates no engine. That is the only
way to satisfy §17(4) before IA-6, and it is deliberately a test asset, not a
runtime component.

Test 103 is **extended, not replaced**: its 99 assertions stay valid once its
"deterministic order" fixtures are relabelled accepted-chronology.

### 23.1 EA-002 WP-2 evidence allocation

The family names and purposes in the table above are the only authoritative
T-number definitions. WP-2 supplies the structural, registry, and
certification-fixture portion of four existing families:

- **T-04 Source order (E4/E5):** the registry declares the exact E5 algorithm,
  and the rolled-back WP-1 fixture resolves the certification E4 source rank.
  Runtime comparison of two documents remains later work because WP-2 creates
  no comparator.
- **T-06 Transition order (E7):** the rolled-back WP-1 fixture resolves exactly
  one `ACCEPTED` transition rank for `IA5_CERTIFICATION`. Runtime transition
  ordering remains later work.
- **T-07 Effect order (E3):** the exact `event_effect_map` and
  `same_time_class` resolve through the rolled-back WP-1 effect-rank fixture,
  including `increase = 20` before `decrease = 40`. Runtime event ordering
  remains later work.
- **T-27 Dormancy:** persistent post-migration state proves no activation,
  event, runtime consumer, write grant, Posting change, or Kernel change.

“Registry completeness” is WP-2 completion evidence spanning those families;
it is not a fifth family and is not an alternative name for T-04. No WP-2 test
may claim the later runtime-ordering portions of T-04, T-06, or T-07.

### 23.2 EA-003 WP-3 evidence allocation

The family names and purposes in the §23 table remain the only authoritative
T-number definitions. WP-3 supplies the structural and fixture portion of two
existing families:

- **T-22 Multi-company isolation (P-02):** both new tables carry `company_id`
  with RLS and one member-gated `SELECT` policy each; the stream key
  `UNIQUE (company_id, item_id, scope_code)` is company-leading; a rolled-back
  fixture proves two companies may each hold a stream carrying the same
  `scope_code` for their own item, that a stream naming another company's item
  is rejected, that a duplicate `(company_id, item_id, scope_code)` is rejected,
  and that an allocator row whose company differs from its stream's is
  rejected. Runtime
  cross-company **edge** and **order** rejection remains later work because WP-3
  creates no edge, order key, or comparator.
- **T-26 Migration/backfill:** fresh `--no-seed` replay through M3 succeeds with
  `inventory_events` = 0 asserted before mutation, both tables created empty, no
  backfill, and every object, constraint, control, and trigger present. WP-3
  asserts no admitted event and no allocated sequence.

“Stream partition completeness” is WP-3 completion evidence spanning those two
families; it is not a third family and not an alternative name for T-22 or T-26.
**No WP-3 test may claim** T-01, T-02, T-03, T-05, T-15, T-16, T-19, T-21, or
any part of C-01.

The complete evidence-ownership split — persistent migration assertions,
rolled-back fixture evidence, implementation evidence, and the isolated
certification rollback proof — is fixed by Engineering Amendment EA-003 in
[`IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md`](IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md)
§4.

### 23.3 EA-006 WP-4 evidence allocation

The family names and purposes in the §23 table remain the only authoritative
T-number definitions. WP-4 supplies the structural and fixture portion of two
existing families:

- **T-03 Duplicate identity (V-14/F-06):** `…_identity_uq` exists as a `UNIQUE`
  constraint on `(valuation_stream_id, canonical_key_bytes)` and
  `…_event_current_uq` as a partial unique index; a rolled-back fixture proves a
  duplicate canonical identity is rejected `23505`, a second `current` row for one
  event is rejected `23505`, and one `current` plus one `superseded` row coexist
  without collision. Comparator behaviour and tie-break outcomes remain WP-7.
- **T-24 Immutability:** the `ENABLE ALWAYS` guard exists and no blanket
  immutability trigger is attached; a rolled-back fixture proves `DELETE` is
  rejected, an `UPDATE` to any of the thirty non-state columns is rejected,
  `'superseded'` → `'current'` is rejected, and `'current'` → `'superseded'` is the
  only permitted mutation.

"Order-key structural completeness" is WP-4 completion evidence spanning those two
families; it is not a third family. **No WP-4 test may claim** T-01, T-02, T-05,
T-15, T-16, T-19, T-21, or any part of C-01. The complete evidence-ownership split
and the fixture-constructibility proof are fixed by Engineering Amendment EA-006 in
[`IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md`](IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md)
§7.

---

## 24. Implementation Work Packages

| WP | Objective | Depends on | Objects | Authority | Risks | Tests | Completion evidence | Rollback point | Concurrent? |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **1** | **Order-policy and version foundation**: the six version tables (§6.4 rows 1–6), their guards, RLS, audit triggers, dormancy CHECKs, and the seeded certification-only rank set (effect 10/20/30/40/50; source-type and transition ranks for `IA5_CERTIFICATION`) | ECC-01 acceptance | M1 | ECC-01 §3.2, §3.3, §6.4 | Rank sparsity wrong → future renumbering | T-01, T-27 | Structure + dormancy tests green; `V` resolvable | Drop M1 | No |
| **2** | **CERTIFIED 2026-07-30 (implemented 2026-07-29) — Registry order authority + admission input contract** (E5 algorithm, line-order authority, transition set, occurrence semantics, same-time class, placement class) | WP-1 | M2 | ECC-01 §4.2 E3/E5/E7, V-10 | Incomplete rule silently admitted | T-04, T-06, T-07, T-27 (§23.1 structural/fixture portions only; tests `105`/`106`) | Registry completeness plus persistent/rolled-back boundary evidence; independent Evidence Gate passed and the separate Certification Mission certified WP-2 on 2026-07-30 | Drop columns; isolated proof `106` | No |
| **3** | **CERTIFIED 2026-07-31 (implemented 2026-07-30) — Stream partition + stream-keyed accepted allocator**: `inventory_valuation_streams` (§6.2) and `inventory_valuation_stream_sequences` (§6.2.1) | WP-1 | M3 | ECC-01 §15(4), V-11; **EA-003/EA-004/EA-005 detailed specification** | Two streams for one key | T-22, T-26 (§23.2 structural/fixture portions only) | Stream partition completeness plus persistent/rolled-back boundary evidence; migration `20260730000018` + tests `107`/`108`; independent Evidence Gate passed 2026-07-31 and the separate Certification Mission certified WP-3 on 2026-07-31 | Drop allocator, then streams, then the WP-3 guard function | Yes (with WP-2) |
| **4** | **CERTIFIED 2026-07-31** — `inventory_event_order_keys` + constraints + 1:1-per-current-resolution enforcement; **EA-006/EA-007 detailed specification** | WP-1…3 | M4 | ECC-01 §4.2, §4.3, §6.1; **EA-006/EA-007** | Supersession lifecycle must not weaken component immutability | T-03, T-24 (§23.3 structural/fixture portions only) | Migration `20260731000019` + tests `109`/`110`; Brutal Fix closed both failed-audit blockers, Brutal Audit Re-run passed, and the separate Certification Mission certified the work package | Drop table, then the WP-4 guard function | No |
| 5 | **EA-010 specification complete; unauthorised/unimplemented** — exact initial-resolution writer and one sequence, 139-column persistence map, 26-column resolver, UTC date rule, trigger function/deferred totality, production/fixture separation, reset-bounded concurrency lane, and WP-4-aligned fourteen-component encoding | WP-4 | M5 | ECC-01 §5.1–§5.3, §8; [EA-010-current detailed specification](IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md) | Signature/test callers; fixture/production leakage; totality; no re-resolution | T-02, T-05, T-07, T-20, T-25 plus future `111`…`113` and `WP5-CONC-114` | Separate comprehensive gate, then only if authorised: exact schema/security/persistence/date/fixture/totality/concurrency/rollback evidence and `103`…`110` regression | Exact current specification §11 reverse order | No |
| 6 | Guard extension for V-01…V-09, V-32, V-33 | WP-5 | M6 | ECC-01 §12 | Over-strict guard blocks valid facts | T-02, T-09 | Validation suite green | Restore guard | No |
| 7 | Ordering + fingerprint functions (stages 4–6 + ordered-input digest), cohort depth, boundary validation | WP-4 | M7 | ECC-01 §5.4–§5.7, §6 | Cohort depth computed over a truncated population | T-01, T-11, T-15, T-16, T-17, T-18 | Ordering + fingerprint suites green | Drop functions | Yes (with WP-6) |
| 8 | Index replacement + superseded-index comment + coverage registry | WP-4, WP-7 | M8, M9 | ECC-01 §15(3) | Index composition drifts from comparator | T-01, guard `075` | Index composition test; guard 075 green | Drop index | Yes |
| 9 | **Certification lane**: permutation, two-session concurrency, randomised schedules across independent resets, rollback/retry, backdate, correction, FIFO/WAC consequence models, prohibited-input census | WP-5…8 | Tests + verification assets only | ADR-C01 §17, ECC-01 §14.3 | Consequence model mistaken for an engine | T-12, T-13, T-14, T-19, T-21, T-28, T-29 | Full evidence package for the reopened gate | n/a (no schema) | No |

**EA-001 (2026-07-29):** WP-2's objective, M2 object boundary, dependencies,
risks, tests, completion evidence, and rollback remain exactly as stated in row
2. The amendment changes only the detailed specification's constraint label for
`document_order_key_algorithm` to the PostgreSQL-safe 59-byte
`ref_inventory_event_source_types_doc_order_key_algorithm_ck`.

**EA-002 (2026-07-29):** The §23 family definitions remain unchanged. The WP-2
row now names T-07 explicitly because the already-governed
`event_effect_map`/`same_time_class` evidence is E3 Effect-order evidence, not
T-06 Transition-order evidence. This is a correction of evidence allocation,
not a new test intent. EA-002 also binds M2 to persistent registry assertions
only; all WP-1 rank-resolution evidence is created inside certification
transactions and rolled back. No policy/rank fixture row is seeded by M2.

**Work Package 1 is exactly:** create the six dormant version objects
(`inventory_event_order_policies`, `inventory_event_effect_ranks`,
`inventory_source_type_ranks`, `inventory_transition_ranks`,
`inventory_canonical_form_versions`, and
`inventory_correction_graph_versions`), with the existing IA-5 guard, RLS,
grant, audit, and immutability patterns applied unchanged; seed only the
certification-only rank set; add nothing to `inventory_events`; expose no
grant. Precondition: `inventory_events` count = 0. It must not begin until
ECC-01 acceptance is recorded. *(Acceptance recorded 2026-07-26; WP-1 is
authorised. The object count was stated as "five" against the six objects named
here and in §6.4 — corrected to six under the WP-1 authorisation gate,
finding GA-01; no object was added, removed, or renamed.)*

The sequence minimises risk by putting every schema addition before any writer
change, keeping the writer replacement in one reviewable migration, and leaving
the index swap until the comparator exists to test it against.

---

## 25. Rollback and Recovery Plan

| Scenario | Recovery |
| --- | --- |
| Any WP fails before WP-5 | Drop the new tables in reverse dependency order; IA-5 is byte-identical to its certified state because nothing existing was altered |
| WP-5 fails | Apply the EA-010-current specification §11 exactly: drop constraint trigger, trigger function, resolver and 14-argument writer; recreate the exact 11-argument writer body/owner/config/ACL/comment from `20260726000013`; prove the three-trigger pre-M5 `inventory_events` set and all WP-1…WP-4 objects/rows unchanged. No `CREATE OR REPLACE` shortcut across the signature change. |
| WP-6 fails after a separately successful WP-5 lifecycle | Restore only the WP-6 guard body under its future governed rollback; do not roll back certified WP-5 automatically. |
| WP-5's deferrable trigger misbehaves | Stop admission and execute the complete EA-010-current rollback; dropping only the trigger is not complete WP-5 rollback. *(EA-006 §5.4 moved the trigger from M4 to M5; WP-4 remains purely additive.)* |
| WP-8 index issue | Drop the new index; the superseded index still serves accepted-chronology queries |
| Data recovery | **Not applicable** — no data exists and none is migrated |
| Post-acceptance discovery of a component defect | Stop admission/replay. WP-5 provides no repair. A separate lifecycle authority must first resolve §15's canonical-identity collision; never use an in-place component `UPDATE` or infer a successor row. |
| Hosted | No hosted application is authorised; there is nothing to roll back there |

Rollback is complete only under the exact per-package contracts. WP-5 does
replace one existing writer and adds trigger metadata to an existing table, so
the historical “nothing existing is altered” premise does **not** apply to M5;
completeness comes from exact body/ACL/comment restoration and the pre-M5
three-trigger census, not from pretending no existing object changed.

---

## 26. Risk Register

| ID | Risk | Sev | Likelihood | Detection | Prevention | Mitigation | Owner | Blocks impl.? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R-01 | Non-deterministic source ordinals (a source supplies E6/E8 from a mutable UI order) | Critical | Medium | T-05, T-19 | Registry declares line-order authority; V-07 | Source type stays unavailable until it can supply stable ordinals | Inventory | No |
| R-02 | Canonical tie-break carries a discriminator absent from E1–E9 (ECC-A-15) | High | Low | T-03; registry review | E10 composite = the existing logical-event tuple, nothing more | Move the distinction into a genuine component | Inventory | No |
| R-03 | Existing-data ambiguity | Low | **Very low** | WP-1 precondition count | Empty by construction | Stop and escalate if count > 0 | Inventory | No |
| R-04 | Correction cycles / forks | High | Medium | T-09 | Depth = parent+1; V-08 forbids forward edges | Fail closed (F-08) | Inventory | No |
| R-05 | Version drift → unreplayable partition | High | Medium | T-17 | V-17/F-11 reject; WP-5 initial-only | Separate lifecycle authority must settle resolution-aware uniqueness before re-resolution/activation | Accounting Policy | **Yes for re-resolution or production activation; no for dormant WP-5 initial fixture** |
| R-06 | Replay population truncation changes causal depth | High | Medium | T-11 | V-31/§5.4(5) | Widen boundary or fail closed | Inventory | No |
| R-07 | Stale projection reuse | High | Low (IA-6) | IA-6D | Nothing consumes ECC in this phase | — | Inventory | No |
| R-08 | WAC precision drift | High | Low | T-13, T-18 | Exact fixed-point; no rounded rate as authority | Legacy `fn_update_wac` superseded, not extended | Inventory | No |
| R-09 | FIFO layer drift from legacy random-UUID tie-break | Medium | Low | T-12 | Legacy engine untouched and superseded | IA-6B replaces it | Inventory | No |
| R-10 | Specific-ID conflict masked by ordering | High | Low | T-14 | Ordering ≠ permission; identity is IA-6B | Reject at eligibility | Inventory | No |
| R-11 | Cross-company contamination | Critical | Low | T-22 | Stream carries company; V-20 | Fail closed | Security | No |
| R-12 | RLS bypass on new tables | Critical | Low | T-23 | Same revoke/grant/RLS pattern as IA-5 | — | Security | No |
| R-13 | Large replay cost in a hot stream | Medium | Medium | T-30 | Index supports the scan; cohorts are small | Checkpointing is IA-6D and may not change chronology | Inventory | No |
| R-14 | Migration lock duration | Low | Low | Migration review | New tables; one brief trigger add | Empty tables make every operation instant | Inventory | No |
| R-15 | Incomplete rollback | Medium | Low | Rollback test | M5 exact writer restoration + trigger census; other packages preserve their own boundaries | §25 and current WP-5 §11 | Inventory | No |
| R-16 | Premature activation | Critical | Low | T-27 | Dormancy is CHECK-enforced, not flag-enforced | Activation needs a migration + governance | Governance | No |
| R-17 | Posting boundary breach | Critical | Very low | T-28 | No journal path is touched | Stop condition if required | Posting | No |
| R-18 | Documentation/code divergence recurs | Medium | Medium | Gate review | §3.4 divergence register; ECC-01 §15(13) | Correct prose in the same migration | Inventory | No |
| R-19 | Writer signature change strands a caller | Medium | Medium | T-02, full regression | DROP+CREATE, never an overload (P3 lesson) | Update the certification callers in the same WP | Inventory | No |

No risk blocks implementation. R-01, R-04, R-05, and R-06 are the four to watch
during execution.

---

## 27. Open Decisions

| # | Decision | Classification |
| ---: | --- | --- |
| 1 | Same-time convention, tuple composition, component precedence | **Resolved by ADR-C01** |
| 2 | Anchoring, placement classes, fail-closed rules, bound inclusivity, cohort-safe bounds, plan purity, re-resolution | **Resolved by ECC-01** (incl. Amendment A1) |
| 3 | Sidecar vs columns for the ECC key | **Engineering choice permitted by architecture** — decided in §6.1 |
| 4 | Stream table vs derived stream key | Engineering choice — decided in §6.2 |
| 5 | `sha256` built-in vs pgcrypto | Engineering choice — built-in, no extension dependency |
| 6 | Partial unique index for current resolution | Engineering choice — §15 |
| 7 | **ECC-01 formal acceptance** | **Closed 2026-07-26** — `ACCEPTED — OWNER APPROVED`, not frozen (`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`) |
| 8 | **ECC-A-11: PG-01 defined or references replaced** | **Closed 2026-07-26** — Outcome B: existing accepted documents embody PG-01, mapped in `PG-01_GOVERNANCE_AUTHORITY_MAP.md` (non-normative; ADR-C01 unedited) |
| 9 | Enabling a production source type | Requires governance decision — out of scope, later phase |
| 10 | Whether the conforming correction sits before or inside IA-6 | **Answered by this design**: entirely before IA-6, in IA-5. The reopened gate confirms |
| 11 | Negative-inventory policy | Already governed (prohibited by default) — **not reopened** |
| 12 | UOM conversion authority (H-03) | Deferred to the reopened gate; does not affect ordering, only quantity values |
| 13 | Stream-keyed accepted allocator: name, columns, partial mutability, guard, dormancy, grants, audit, rollback | Engineering choice — **closed 2026-07-30 by EA-003** (§6.2.1 and the WP-3 detailed specification). Derived from the certified `inventory_valuation_scope_sequences` template; no accounting consequence |

**Zero unresolved accounting-policy questions.** Items 3–6 and 13 are genuine
engineering choices with no accounting consequence; items 7–9 are governance;
items 11–12 are already owned elsewhere. No policy question was converted into
an engineering choice.

---

## 28. Adversarial Design Walkthroughs

Persisted authority = what the order-key row holds. Locks: **none** unless
stated.

| # | Case | Accepted inputs | Persisted authority | Derived ECC | Replay impact | Projection | Failure | Component |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Two same-time receipts, opposite schedules | Two occurrences, same E1, different documents | Both order keys; `scope_sequence` differs by schedule | E5 decides; identical in both schedules | None | None | — | WP-5, WP-7; T-19 |
| 2 | One document, lines inserted out of order | Two lines, ordinals 1 and 2 | `source_line_ordinal` from source | E6 decides: 1 ≺ 2 | None | None | — | WP-2, WP-5; T-05 |
| 3 | One line, multiple effects | One occurrence, `p_events[]` | `event_ordinal` per event; plan purity required | E9 orders within the occurrence | None | None | Whole occurrence rejected if any event fails | WP-5; T-03, T-20 |
| 4 | Backdated receipt after an issue | Late occurrence, earlier E1 | New order key; accepted position is later | E1 places it earlier; insertion only | Successor version from `K` | Prior version citable with disclosed exception | — | WP-7; T-10 |
| 5 | Correction accepted after the Accepted Through cut-off | Anchored correction | Order key with X1=1 and root | Outside that version by watermark | Successor at a later watermark | Prior version stands | — | WP-4, WP-7; T-11 |
| 6 | Correction of a correction | Two anchored corrections | Depths 1 and 2, same root | `e1, k1, k2, e2` by X1 | Successor version | — | Fork without proof → F-08 | WP-4; T-08 |
| 7 | Duplicate canonical identity | Two facts, one identity | Second insert violates `UNIQUE (stream, canonical_key_bytes)` | **No order produced** | Rejected | — | **F-06**, `23505`; stream certification blocked | WP-4; T-03 |
| 8 | Ordering-policy version change | New policy version; new event resolves under it | Mixed `V` in one stream | Not derivable | **F-11 rejects**; WP-5 has no re-resolution/successor path | Frozen | Fail closed pending separate lifecycle authority | WP-1, future lifecycle work, WP-7 only after dependency; T-17 |
| 9 | Precision-only version change | New precision version | Dependency of record | **Unchanged order**, identical ordered-input fingerprint | Re-cost successor (IA-6) | Method state only | Changed order fingerprint ⇒ F-12 | WP-7; T-18 |
| 10 | FIFO replay after backdating | B1 fixture | Order keys unchanged; new key inserted | `e3, e1, e2` | Full partition replay (new minimum) | IA-6 layers rebuilt | — | T-12 |
| 11 | WAC replay after backdating | W3 fixture | As above | `e1, e5, e2, e3, e4` | Prefix `{e1}` reused (Theorem 4) | IA-6 pool versions rebuilt; deltas +80.00/+60.00 | — | T-13 |
| 12 | Specific-ID duplicate physical identity | Two issues naming one serial | Both order keys valid | Both ordered normally | — | — | Second **rejected at eligibility**, not by ECC | T-14 |
| 13 | Same Economic As Of, later Accepted Through | Wider watermark | Existing keys unchanged | Population may gain events; insertion only | Successor from `K` if any key precedes the certified max | Superseded | — | WP-7; T-11 |
| 14 | Same Accepted Through, earlier Economic As Of | Narrower end bound | Unchanged | Strict prefix; ordinals `1..M` identical | Prefix reuse legitimate | — | End bound cannot orphan a predecessor (a predecessor always has lower cohort depth) | WP-7; T-11 |
| 15 | Concurrent replay requests, one stream | Two simultaneous ordering calls | Nothing written | **Identical output** — ordering takes no locks and writes nothing | Both succeed | None in this phase | When IA-6 adds the fold, mutual exclusion belongs to promotion, never to ordering | WP-7; T-19 |

Case 15 is the reason ordering is a read-only function: making it write would
manufacture exactly the lock-order dependency ADR-C01 exists to eliminate.

---

## 29. Implementation Readiness Decision

**B — READY AFTER OWNER ACCEPTANCE OF ECC-01.**

| Criterion | Status |
| --- | --- |
| ECC-01 acceptance authority sufficient | **No** at design time — recommended, not recorded. **Met 2026-07-26** when the owner recorded acceptance |
| No accounting-policy ambiguity remains | Met (§27) |
| Current implementation surface understood | Met (§3, read from source) |
| Target ownership complete | Met (§5) |
| Logical data changes fully specified | Met (§6) |
| Existing-data treatment defined | Met (§16 — empty by measurement and by construction) |
| Migration sequence defined | Met (§17) |
| Rollback defined | Met (§25) |
| Dormancy preserved | Met (§21) |
| Posting/Kernel boundaries preserved | Met (§22) |
| Test and certification plan complete | Met (§23) |
| No blocking design decision remains | Met |

Every criterion for Outcome A is satisfied except the governance one, which is
not this phase's to satisfy.

*Subsequent status (2026-07-26): the governance criterion is satisfied. The
[WP-1 authorisation gate](ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md)
returned **A — AUTHORISED TO BEGIN WORK PACKAGE 1**, having re-verified the
zero-data precondition read-only (`inventory_events` = 0).*

*Subsequent status (2026-07-29): WP-1 is certified. WP-2 is separately
authorised, EA-001/EA-002-reconciled, and implemented by migration
`20260729000017` plus tests `105`/`106` without changing this design's
accounting or architecture. Its independent Evidence Gate passed after the
rollback proof was strengthened and recommends certification. WP-2 remains
uncertified pending the separate Certification Mission.*

*Subsequent status (2026-07-30) — supersedes the WP-2 status line above, which is
retained as issued: the independent WP-2 Certification Mission **granted
certification**. **WP-2 is CERTIFIED (2026-07-30)**; see §24 row 2 and
`IA-5_ECC_HARDENING_WP-2_EVIDENCE_GATE_REPORT.md` §10.*

*Subsequent status (2026-07-30) — WP-3: the WP-3 Authorisation Gate returned
**B — REJECTED** for specification incompleteness (architecture and dependencies
were complete and satisfied). It found that the "Logical data changes fully
specified | Met (§6)" criterion above, recorded at design time, did **not** hold
for M3: §17 M9 requires two new tables from M3 while §6 modelled only one.
**Engineering Amendment EA-003 (2026-07-30) closes that gap** — §6.2.1 now names
`inventory_valuation_stream_sequences`, §23.2 allocates its evidence, and
[`IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md`](IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md)
carries its complete governing contract. EA-003 is documentation only and changed
no SQL, migration, test, schema, scope, architecture, ADR-C01 rule, or ECC-01
rule. **WP-3 remains unauthorised** pending a separate authorisation gate.*

*Subsequent status (2026-07-30) — supersedes the WP-3 status line above, which is
retained as issued: Engineering Amendments **EA-004** and **EA-005** closed the
two remaining specification defects (G-1/G-2 and B-1), and the re-run WP-3
Authorisation Gate returned **A — WP-3 AUTHORISED**. WP-3 was implemented the
same day by migration `20260730000018` and tests `107`/`108`, within its bounded
§24 row 3 scope and with no accounting, runtime, Posting, Kernel, `inventory_events`,
ADR-C01, or ECC-01 change. **WP-3 is implemented but not evidence-gated and not
certified**; WP-4…WP-9 and IA-6 remain unauthorised.*

*Subsequent status (2026-07-31) — supersedes the WP-3 status line above, which is
retained as issued: the independent **WP-3 Evidence Gate passed** with zero
blocking findings, and the separate Certification Mission then granted
certification. **WP-3 is CERTIFIED 2026-07-31.** This is a work-package
certification only: C-01 remains open, the IA-5 permanent-foundation claim
remains suspended, no Inventory module or engine is certified, and WP-4…WP-9 and
IA-6 remain unauthorised.*

*Subsequent WP-4 status (2026-07-31) — supersedes only the WP-4 frontier in the
historical paragraph above, which remains preserved as issued: the separate WP-4
Authorisation Re-run returned an authorising decision, and migration
`20260731000019` plus tests `109`/`110` implemented M4. The independent Brutal
Audit verified the executable contract but failed on WP4-BA-001 and WP4-BA-002.
At that audit decision WP-4 was not brutally fixed, not audit-re-run, and not
certified. The bounded Brutal Fix closed both blockers without changing SQL,
migration logic, tests, runtime, accounting, Posting, Kernel, ADR, or ECC. WP-4
is now brutally fixed, not audit-re-run, and not certified; WP-5…WP-9 and IA-6
remain unauthorised.*

*Subsequent WP-4 certification status (2026-07-31) — supersedes only the current
frontier in the WP-4 status paragraph above, which remains preserved as issued:
the Brutal Audit Re-run passed, independently confirming WP4-BA-001 and
WP4-BA-002 closed with no implementation regression. The separate Lifecycle
Step 7 Certification Mission then re-executed the required local validation and
certified WP-4. This is a work-package certification only; C-01 remains open,
the IA-5 permanent-foundation claim remains suspended, and no Inventory module
or engine is certified. WP-5…WP-9 and IA-6 remain unauthorised.*

---

## 30. Exact Next Authorised Phase

1. **FORMAL OWNER ACCEPTANCE OF ECC-01** — record acceptance (or return) in
   `AI_STATE.md` or a successor governance record, and resolve ECC-A-11 by
   either creating the PG-01 governance document or authorising replacement of
   its references. — **DONE 2026-07-26**:
   [`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`](../03.%20Architecture/ECC-01_FORMAL_OWNER_ACCEPTANCE.md)
   (accepted, not frozen) and
   [`PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md)
   (ECC-A-11, Outcome B).

2. Then, and only then: **IA-5 ECONOMIC COSTING CHRONOLOGY HARDENING —
   IMPLEMENTATION, WORK PACKAGE 1** as specified in §24. — **This is now the
   authorised historical phase**, per the
   [WP-1 authorisation report](ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md).
   It subsequently completed and was certified on 2026-07-29.

3. **Completed 2026-07-29:** independent IA-5 ECONOMIC COSTING CHRONOLOGY
   HARDENING — WORK PACKAGE 2 EVIDENCE GATE. It passed and recommends
   certification.

4. **Completed 2026-07-30:** formal IA-5 ECONOMIC COSTING CHRONOLOGY HARDENING —
   WORK PACKAGE 2 CERTIFICATION MISSION. Evidence Gate completion was not
   certification and authorised no later work package. The mission granted
   certification: **WP-2 is CERTIFIED 2026-07-30**.

5. **Completed 2026-07-30:** WP-3 AUTHORISATION GATE — returned
   **B — REJECTED** for specification incompleteness, then **Engineering
   Amendment EA-003** (documentation only) closed all four recorded blockers via
   §6.2.1, §23.2, the §29 reconciliation, and
   [`IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md`](IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md).

6. **Completed 2026-07-30:** the WP-3 AUTHORISATION GATE (after EA-004 and
   EA-005) returned **A — WP-3 AUTHORISED**, and WP-3 was implemented within its
   bounded scope by migration `20260730000018` plus tests `107`/`108`.

7. **Completed 2026-07-31:** the independent **WP-3 EVIDENCE GATE** passed with
   zero blocking findings, after a governed repository amendment reconciled the
   authorisation frontier and corrected the schema-summary generator. The
   separate **WP-3 CERTIFICATION MISSION** then granted certification:
   **WP-3 is CERTIFIED 2026-07-31**, a work-package certification only.

8. **Completed 2026-07-31:** the WP-4 Authorisation Re-run authorised WP-4;
   implementation completed; the Brutal Audit failed only on WP4-BA-001 and
   WP4-BA-002; and the bounded Brutal Fix closed both without database change.

9. **Completed 2026-07-31:** the **WP-4 BRUTAL AUDIT RE-RUN** passed, and the
   separate **WP-4 CERTIFICATION** mission certified the work package.

10. **Completed 2026-07-31:** the **WP-5 AUTHORISATION GATE — Lifecycle Step
    2** returned **REJECTED** on WP5-AG-001…003. No implementation authority was
    granted.

11. **Completed 2026-08-01:** **WP-5 ENGINEERING AMENDMENT EA-008 —
    documentation only**, bounded to WP5-AG-001…003. It grants no authority.

12. **Completed 2026-08-01:** the independent **WP-5 AUTHORISATION GATE
    RE-RUN** returned **REJECTED** on WP5-AGR-001…003. No implementation
    authority was granted.

13. **Completed 2026-08-01:** **WP-5 ENGINEERING AMENDMENT EA-009 —
    documentation/governance only**, bounded to WP5-AGR-001…003. It grants no
    authority.

14. **Completed 2026-08-01:** the complete independent **WP-5 AUTHORISATION
    GATE RE-RUN** returned **REJECTED** on WP5-AGR2-001…004. No implementation
    authority was granted.

15. **Completed 2026-08-01:** **WP-5 ENGINEERING AMENDMENT EA-010 —
    documentation/governance only**, bounded to WP5-AGR2-001…004. It grants no
    authority.

16. **Current next mission:** **WP-5 AUTHORISATION GATE RE-RUN —
    COMPREHENSIVE FINAL GATE.** Do not begin implementation unless that separate
    gate passes.

Not authorised: WP-5 through WP-9; any IA-6 subphase; any hosted migration;
enabling a production source type; any Posting or Kernel change. **IA-6 remains
unauthorised**, and the C-01 program stop remains open until the reopened
evidence gate accepts WP-9's evidence package.

No implementation was performed during the original design phase. WP-2 was
subsequently implemented under its separate authorised implementation mission.

---

## 31. WP-5 Authorisation Gate Decision — 2026-07-31

**Decision: REJECTED. WP-5 remains unauthorised.**

All prerequisites outside the WP-5 specification pass: WP-1…WP-4 remain
Certified; focused tests `104`…`110` pass 7 files / 260 assertions; the local
catalog contains zero Inventory occurrences, events, streams, stream sequences,
or order keys; the six WP-1 tables remain empty; the only registry row remains
certification-only and production-disabled; no WP-5 resolver, trigger,
migration, test, runtime consumer, or hosted dependency exists. ADR-C01 remains
frozen, ECC-01 remains accepted, and Posting, Kernel, WP-6+, and IA-6 boundaries
remain intact.

### WP5-AG-001 — High — Exact writer/resolver contract absent

Sections 8.1 and 9 describe new inputs and a conceptual resolver but do not
define the replacement writer's exact SQL signature, the exact placement and
schema of new JSON fields, the resolver's SQL signature/return type, or the
byte-exact canonical serialization and digest output contract. M5 changes an
existing 11-argument writer and therefore cannot be safely implemented by
inference. **Minimum governed repair:** a documentation-only WP-5 detailed
specification defining every function argument, type, default, return, payload
key, normalization/encoding rule, failure, privilege, idempotency behavior, and
testable postcondition. Confidence: **High**.

### WP5-AG-002 — High — Dormant admission rule conflicts with ECC-01 V-10

The design requires the source type to remain certification-only and
production-disabled (§21) and routes admission through that certification-only
rule (§8.2). ECC-01 §5.2 and V-10 instead require the source type to be
production-enabled before economic processing, and ECC-01 §14.1 confirms the
present disabled row is correctly unavailable. The repository provides no
governed distinction between a rolled-back certification fixture path and
production economic admission. **Minimum governed repair:** a documentation-only
amendment that reconciles the certification-fixture path with ECC-01 without
enabling a production source type, weakening dormancy, or changing ADR-C01 or
ECC-01. Confidence: **High**.

### WP5-AG-003 — High — Trigger object and rollback contract incomplete

M5 declares two functions plus one new constraint trigger. The two named
functions are the replacement writer and new component resolver, but PostgreSQL
also requires a trigger function for the new event-side constraint trigger and
no existing function is assigned that contract. Trigger name, timing, events,
deferrability, function, SQLSTATE, and current/superseded behavior are absent.
Rollback restores prior function bodies and drops the trigger, but does not
drop the new resolver or any new trigger function; §24 row 5 names only the
prior writer as its rollback point. **Minimum governed repair:** specify the
complete trigger/function object set and exact reverse-order rollback, then
allocate executable rollback and 1:1-totality evidence. Confidence: **High**.

No repair, SQL, migration, test, runtime, Posting, Kernel, architecture, hosted,
WP-6+, or IA-6 change was performed by this gate.

---

## 32. WP-5 Engineering Amendment EA-008 — 2026-08-01

EA-008 is recorded in
[`IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`](IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md).
It prospectively supersedes the incomplete M5 descriptions identified in §31
without rewriting that rejection or any WP-1…WP-4 issued record.

| Finding | EA-008 resolution then claimed (historical; see §33) |
| --- | --- |
| WP5-AG-001 | Closed at specification level: exact 14-argument replacement writer, exact 8-argument/25-column resolver, payload schema, version-tagged 13-component admission encoding, digest, failures, privileges, locking, idempotency, atomicity and postconditions are fixed. E2 remains population-derived and the later full comparator remains 14 components. |
| WP5-AG-002 | Closed at specification level: default production admission remains V-10 fail-closed; exact `IA5_CERTIFICATION` fixture admission is explicit, `postgres`-only, local, rolled back and commit-rejecting. No source is enabled and no bypass/grant/GUC/wrapper exists. |
| WP5-AG-003 | Closed at specification level: M5 owns three functions plus one constraint trigger; trigger metadata, totality/current/superseded semantics, `103`/`109` consequences, tests `111`…`113`, and complete reverse-order rollback are fixed. |

**Historical EA-008 decision:** specification ready for a separate WP-5
Authorisation Gate re-run. The re-run result is preserved next; it supersedes
this readiness claim without rewriting it. No runtime, database, test, source,
Posting, Kernel, product-scope or hosted change occurred in EA-008.

---

## 33. WP-5 Authorisation Gate Re-run Decision — 2026-08-01

**Decision: REJECTED. WP-5 remains unauthorised.**

The independent re-run reopened exactly these three High findings. No repair,
implementation, SQL, migration, test, runtime, database object, product
architecture, roadmap, Posting, Kernel, source activation or hosted change was
performed by that gate.

| Finding | Verified blocker |
| --- | --- |
| `WP5-AGR-001` | Certified WP-4 makes `canonical_key_bytes` the immutable serialization of all fourteen ECC components, while EA-008 assigned it a version vector plus only thirteen components and deferred E2. The prospective WP-5 producer contract therefore conflicted with its certified storage authority. |
| `WP5-AGR-002` | Programme design §8.2 placed idempotency after stream/policy/normalization/key work, while EA-008 §3.5 made duplicate resolution precede that work and declared its order mandatory. An implementer still had two controlling sequences. |
| `WP5-AGR-003` | The protected-boundary claim supplied no permanent manifest, entry count, aggregate start/end hash or independently reproducible command. Prose alone could not prove executable artifacts unchanged. |

EA-008 remains historical evidence. These findings supersede only its defective
readiness claim and require a bounded documentation/governance amendment.

---

## 34. WP-5 Engineering Amendment EA-009 — 2026-08-01

EA-009 is recorded in the current
[`IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`](IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md).
It closes only §33's findings and does not rewrite the issued §31 rejection or
historical §32 amendment.

| Finding | EA-009 current resolution |
| --- | --- |
| `WP5-AGR-001` | Closed at specification level. WP-4 remains authoritative for persistence, immutability, serialization of exactly `E1…E10,X1…X4`, and SHA-256 digest. WP-5 derives/validates those values. The only eligible base/no-edge fixture yields E2 = 0; a non-base source fails closed. Version and admission metadata remain separate evidence, never extra components. No WP-4 amendment is required. |
| `WP5-AGR-002` | Closed at specification level. Current detailed specification §3.5 is the only algorithm; design §8.2 points to it and carries no alternate order. Tenant-safe strict normalization precedes the company-scoped idempotency lookup; exact duplicate resolution precedes chronology writes; occurrence then sorted stream/allocator locking is fixed. |
| `WP5-AGR-003` | Closed at governance-proof level. Current specification §17 defines a fixed filesystem set and exact Linux/GNU SHA-256 procedure. Mission start measured 527 entries, path-manifest hash `168c3ef5391c26f8ee5472b09c72a96b1089cb9dd2930502b65188645b99f508`, and protected aggregate `8ddf66f36c63606f8eb0bceaacfe3f3131337758b895fc557ec488ca383d7ba6`; the permanent handoff records the matching end run. |

**Historical EA-009 decision:** `EA-009 COMPLETE — READY FOR WP-5 AUTHORISATION GATE
RE-RUN`. This is an amendment decision, not authorisation. WP-5 is not
authorised, not implemented, not audited and not certified. WP-6…WP-9 and IA-6
remain unauthorised. No runtime, database, test, source, Posting, Kernel,
product-scope or hosted change occurred in EA-009.

---

## 35. Complete WP-5 Authorisation Gate Re-run Decision — 2026-08-01

**Decision: REJECTED. WP-5 remains unauthorised.** The gate completed one full
review and returned all four High blockers below. It performed no repair,
implementation, SQL, migration, test, runtime, database, product-architecture,
roadmap, source-activation or hosted change.

### WP5-AGR2-001 — High — Resolution identity and WP-4 uniqueness conflict

- **Exact evidence:** ECC-01 §3.3/V-35 requires new immutable target-version
  evidence with prior resolution retained; certified WP-4 structurally permits
  retained `superseded` rows; migration `20260731000019` simultaneously enforces
  unconditional `UNIQUE (valuation_stream_id,canonical_key_bytes)`; EA-009 does
  not serialize the version vector into those fourteen comparator bytes. An
  unchanged-component version-only successor therefore collides.
- **Root cause:** comparator bytes and resolution-version identity were
  conflated.
- **Why unsafe:** implementation must fail `23505` or silently amend certified
  identity semantics.
- **Minimum repair:** initial-resolution-only WP-5, no successor/supersession,
  fail closed on prior event resolution, and a separate future WP-4 lifecycle
  decision before re-resolution/dependent activation.
- **Confidence:** High.

### WP5-AGR2-002 — High — Complete writer persistence map absent

- **Exact evidence:** the payload and insert sequence did not govern every
  required/defaulted/derived column across occurrences, events, source links,
  optional values, streams, allocators and order keys. Migration
  `20260726000013` still carried specific date, policy, costing, currency,
  evidence, atomic/audit and creation semantics absent from EA-009; normalized
  text storage was also unspecified.
- **Root cause:** complete caller input did not become a complete row-
  construction contract.
- **Why unsafe:** the implementer still chose financially/audit-relevant stored
  values and which old-writer behavior survived.
- **Minimum repair:** exhaustive seven-table column map and a
  preserved/modified/removed old-writer matrix.
- **Confidence:** High.

### WP5-AGR2-003 — High — Economic dates depend on session timezone

- **Exact evidence:** EA-009 used `E1::date`; the existing guard uses
  `NEW.effective_at::date`; the current writer uses `p_occurred_at::date`; none
  pinned PostgreSQL `TimeZone`, although ECC canonical timestamps are UTC.
- **Root cause:** timestamp bytes were governed, but the effective-date
  conversion used for policy selection/validation/persistence was not.
- **Why unsafe:** the same instant near midnight can select different authority
  or pass/fail differently by session.
- **Minimum repair:** exact UTC date derivation, function-local UTC configuration,
  guard compatibility, and two-timezone proof.
- **Confidence:** High.

### WP5-AGR2-004 — High — Concurrent certification fixture unconstructible

- **Exact evidence:** EA-009 assigned concurrent idempotency to rolled-back test
  `112`, but independent sessions cannot observe its uncommitted company/master/
  policy fixture. Repository verification precedent commits local setup and
  requires an immediate reset.
- **Root cause:** a single-session rollback convention was applied to a
  multi-session visibility requirement.
- **Why unsafe:** evidence would require forbidden fixture commits, weakened
  boundaries or a fake concurrency claim.
- **Minimum repair:** one exact local-only reset-bounded two-session asset,
  committed non-Inventory setup only, event-transaction rollback/commit reject,
  immediate reset and residue proof.
- **Confidence:** High.

The detailed specification's EA-010 mission ledger preserves the same complete
finding content and owns the executable repairs.

---

## 36. WP-5 Engineering Amendment EA-010 — 2026-08-01

EA-010 is recorded in the current
[`IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`](IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md).
It closes only §35's four findings, preserves §§31–35 as issued chronology, and
changes no higher or certified authority.

| Finding | EA-010 current resolution |
| --- | --- |
| `WP5-AGR2-001` | WP-5 now owns initial resolution only. Any pre-existing order-key row for the new event raises `IA5-WP5-026`/`23505`; no update, demotion, successor or re-resolution is supported. A mandatory separate lifecycle stop precedes re-resolution, dependent WP-7 work or production activation. |
| `WP5-AGR2-002` | Detailed specification §3.8 maps all 139 columns across the seven written tables and classifies every meaningful current-writer behavior as preserved, modified or removed. Signature, normalized payload, algorithm, return, failure, rollback and future evidence all point to that map. |
| `WP5-AGR2-003` | Writer/resolver pin `TimeZone=UTC`; economic and occurrence dates use exact UTC expressions; the preserved guard executes in that writer-local setting; tests `111`/`112` own two-timezone equality evidence. |
| `WP5-AGR2-004` | Ordinary tests remain all-rollback. Future `WP5-CONC-114` owns the fresh-local, committed-non-Inventory-setup, two-serializable-session, event-rollback/commit-reject, immediate-reset and no-residue proof. It claims no committed production winner. |

**Current decision:** `EA-010 COMPLETE — READY FOR WP-5 AUTHORISATION GATE
RE-RUN`. This is an amendment decision, not authorisation. WP-5 is not
authorised, implemented, audited or certified. WP-6…WP-9 and IA-6 remain
unauthorised. No executable or hosted asset changed.
