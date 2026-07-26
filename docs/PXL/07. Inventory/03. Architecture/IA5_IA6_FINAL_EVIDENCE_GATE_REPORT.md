# IA-5 / IA-6 Final Evidence Gate Report

**Decision:** **OUTCOME C — IA-5 requires a governed hardening phase before
any IA-6 work.**

**Evidence date:** 2026-07-26  
**Repository commit reviewed:** `6148aa4a132460aef168069636a394e288934ac5`  
**Database:** Disposable local Supabase only; clean migration replay through
`20260726000015`; no seed  
**Production, hosted, Posting, Kernel, stock, canonical, and accounting
changes:** None

## 1. Executive Summary

The evidence resolves the conflict in favour of neither prior opinion. It proves
a narrower fact: IA-5 has a valid, unique, replayable **accepted stream
position**, but the current database assigns that position according to
transaction arrival and the lock schedule. The frozen Inventory Costing
Specification separately requires same-time costing order not to depend on
database insertion order and names immutable event identity and source-line
order as ordering inputs. The implemented ordering index contains neither.

Two clean independent executions of the sequential permutation test produced:

- A then B: receipt `A` received `scope_sequence=1`; issue `B` received `2`.
- B then A: issue `B` received `scope_sequence=1`; receipt `A` received `2`.
- The same document submitted line 2 before line 1 retained line 2 first.
- Partial occurrence 2 submitted before partial occurrence 1 retained partial
  occurrence 2 first.

A real two-session test then proved the causal mechanism:

- delaying A before the scope-sequence update made B first;
- delaying B made A first;
- explicitly holding the scope-sequence row lock made the lock owner first;
- eight random schedules produced both A-first and B-first orders; and
- all 24 events were accepted with unique sequences.

For the test command set, A-first presents a receipt before an issue, while
B-first presents an issue into empty stock. Future FIFO eligibility and
Moving-WAC negative-inventory/provisional-deficit handling can therefore differ.
No frozen PXL rule explicitly says that lock acquisition is authoritative
accounting chronology or the costing tie-breaker. This meets two mandatory stop
conditions: the intended costing order is not explicit, and independent
schedules can produce materially different costing consequences without an
approved accounting rule.

The remaining eight executable probes were created but deliberately not run
after that stop condition. Their questions are not silently accepted, rejected,
or downgraded. IA-6 design, dormant method-state schema, data admission, replay,
and certification all remain unauthorised.

## 2. Conflict Between the Two Prior Reviews

The initial review treated C-01 as a permanent-foundation defect because
concurrent arrival could determine a costing-significant order. The adjudication
treated the assigned scope sequence as a legitimate event-store linearisation
and moved other authority corrections inside IA-6.

Both views contain a valid premise:

- a database-assigned stream position can validly and deterministically preserve
  accepted chronology; and
- inventory costing needs a domain rule for the order in which receipts, issues,
  returns, and corrections affect layers or pools.

The disputed step was treating those two orders as necessarily identical. The
database proves they are identical in the present implementation, but the frozen
documents do not approve the database lock winner as the accounting rule.

The contradiction is concrete:

- [PXL Inventory Costing Specification](PXL_INVENTORY_COSTING_SPEC.md) states
  that the order uses effective timestamp, governed sequence, immutable event
  ID, and source-line order, and that same-time events cannot depend on database
  insertion order.
- [IA-5 Implementation and Certification Evidence](PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md)
  states an order ending in per-scope, source-occurrence, and event sequences,
  and describes the per-scope allocator as using an advisory lock.
- The actual migration uses an `UPDATE` of one scope-sequence row. Its index
  orders by scope, timestamps/dates, `scope_sequence`,
  `source_occurrence_sequence`, and `event_sequence`; it has no immutable event
  ID or source-line ordinal.
- The [IA-4 Database Blueprint](PXL_IA4_DATABASE_BLUEPRINT.md) called for
  effective timestamp, recorded timestamp, and a stable tie-breaker.
- IA-4 risk R-09 required permutation testing for identical timestamps.

The evidence therefore does not merely expose a documentation typo. It shows
that a missing decision controls future FIFO/WAC results.

## 3. Exact Repository State Reviewed

The review used branch `main` at Git commit
`6148aa4a132460aef168069636a394e288934ac5`. The worktree already contained
substantial unrelated modified and untracked work; it was preserved.

The authoritative IA-5 migration files reviewed were:

| Migration | SHA-256 |
| --- | --- |
| `20260726000013_inventory_accounting_ia5_foundation.sql` | `3cd2746c5def756221b681b8df89aa9e674ac96e0d5f7d1aebcbac02949822a8` |
| `20260726000014_inventory_accounting_ia5_precision_overload.sql` | `95eeff2e2da16cadb88d13c30f847f8e404bafda3d848c1504b07948df1979ba` |
| `20260726000015_inventory_accounting_ia5_immutable_error.sql` | `ffbd237d2791ccc697c7f64ffc2030668a369fb4a8ac698e2a94e20d94dd6dc6` |

The local database was rebuilt from migration history with
`supabase db reset --local --no-seed`. It reached migration
`20260726000015`. The committed concurrency fixture was then removed by another
clean reset. Final local probes showed:

- concurrency test company count: `0`;
- `inventory_events` count: `0`; and
- maximum applied migration: `20260726000015`.

No production migration, production function, method-state object, seed,
canonical fixture, Posting object, Kernel object, stock authority, or hosted
object was created or changed.

## 4. C-01 Executable Evidence

### 4.1 Sequential permutations

Asset:
[`ia5_final_ordering_permutation_test.sql`](../../../../supabase/verification/ia5_final_ordering_permutation_test.sql)

The asset calls the real sanctioned dormant occurrence service and writes actual
IA-5 events inside a transaction that is rolled back. It does not simulate an
event table.

The full 11-assertion lane passed twice, with a clean database reset between
runs. Both runs proved:

| Scenario | Submitted | Stored economic order |
| --- | --- | --- |
| Independent documents | A then B | A, B |
| Same independent documents/evidence | B then A | B, A |
| Same document | line 2 then line 1 | line 2, line 1 |
| Backdate | later-effective event then backdated event | backdated, later-effective |
| Partial line | occurrence 2 then occurrence 1 | occurrence 2, occurrence 1 |

For independent same-time commands, the normalized economic tuple differed only
at `scope_sequence`. Random UUIDs did not determine the order.

### 4.2 Concurrent linearisation

Asset:
[`ia5_final_concurrent_linearisation_test.sql`](../../../../supabase/verification/ia5_final_concurrent_linearisation_test.sql)

The full 10-assertion, two-session lane passed on a clean local database. It
admitted 24 events:

- one unbiased simultaneous pair;
- one B-first delayed pair;
- one A-first delayed pair;
- one pair with A explicitly owning the relevant row lock; and
- eight randomized pairs.

The result set contained both A-first and B-first orders for the same economic
command set. The wait probe confirmed that the competing command waited on the
scope-sequence row lock. All occurrences were accepted; sequence uniqueness was
not violated.

### 4.3 Database mechanism

The implemented service increments
`inventory_valuation_scope_sequences.last_sequence` through `UPDATE ...
RETURNING`. PostgreSQL gives the updater a row lock; another updater waits until
the first transaction ends. The resulting sequence is a sound linearisation of
database admission, but it is selected by the transaction that reaches the row
lock first.

The migration comment itself describes `scope_sequence` as evidence of
“accepted order”. That supports accepted chronology. It does not establish
economic priority for same-time independent source facts.

### 4.4 Accounting consequence

The command pair is intentionally minimal:

- A: receipt `+10`;
- B: issue `-6`;
- same valuation scope;
- same authoritative effective timestamp and dates.

A-first allows ordinary FIFO/WAC processing. B-first reaches an issue with no
available stock and therefore invokes rejection or a future negative-inventory
provisional-deficit policy. This is a material method-state difference even if a
later receipt eventually makes ending quantity equal.

### 4.5 Final C-01 conclusion

**Final conclusion:** Valid.  
**Final severity:** Critical.  
**Target:** Governed pre-IA-6 hardening.  
**Blocks IA-6 design:** Yes, except design of the hardening decision itself.  
**Blocks IA-6 schema creation:** Yes.  
**Blocks IA-6 data admission:** Yes.  
**Blocks IA-6 replay:** Yes.  
**Blocks IA-6 certification:** Yes.

The severity is not based on another ERP choosing a different order. It follows
from PXL’s own conflicting requirements and the demonstrated receipt/issue
consequence.

## 5. Occurrence and Composite Atomicity Evidence

Asset created:
[`ia5_final_occurrence_atomicity_test.sql`](../../../../supabase/verification/ia5_final_occurrence_atomicity_test.sql)

Supporting retry asset created:
[`ia5_final_rollback_retry_test.sql`](../../../../supabase/verification/ia5_final_rollback_retry_test.sql)

Execution was stopped after C-01 as mandated. H-01 therefore remains
**provisionally High**, not finally accepted or rejected. No conclusion is made
that a parent occurrence is required.

The minimum question after C-01 is corrected remains:

- whether one SQL transaction plus an explicit correlation identity is
  sufficient for document-level rollback and retry;
- whether future IA-6 keys can remain line-grained without foreclosing a later
  parent/composite model; and
- whether `event_ids UUID[]` is merely redundant evidence or can contradict the
  relational event membership.

Until the test executes successfully, H-01 independently blocks method-state
data admission and certification. It does not independently prove that dormant
table definitions are unsafe.

## 6. Policy/UOM Dependency Evidence

Asset created:
[`ia5_final_uom_policy_dependency_census.sql`](../../../../supabase/verification/ia5_final_uom_policy_dependency_census.sql)

Execution was stopped after C-01. H-02 and H-03 remain **provisionally High**.

Static repository evidence confirms that future method state would reference
current valuation scopes and policies and would consume `base_quantity`. It also
confirms that the service currently checks:

`base_quantity = round(source_quantity × caller-supplied factor, policy scale)`.

That check does not, by itself, prove item/UOM conversion version authority or
indivisible residual ownership. IA-3 requires governed item/base-UOM scale,
conversion identity, and deterministic retained residuals. Consequently:

| Proposed IA-6 dependency | Current authority sufficient? | Gate |
| --- | --- | --- |
| Table definition with no quantity/policy FK and no admission | Not applicable | Still globally paused by C-01 |
| FK to current valuation scope | Not proven | H-02 before durable FK |
| FK to current policy rows | Not proven | H-02 before durable FK |
| Persisted FIFO layer quantity | No certification evidence | H-03 before admission |
| Persisted WAC pool quantity | No certification evidence | H-03 before admission |
| Caller-supplied conversion factor | Not authoritative by itself | H-03 before admission |
| Rounding/indivisible residual | Not proven | H-03 before admission |
| Historical event replay into quantity state | Not proven | H-02/H-03 before replay |

The evidence gate cannot yet choose between additive IA-5 correction and an
initial IA-6 authority-correction migration because the mandated test was not
run. C-01 already requires a governed pre-IA-6 phase, so this decision must be
resolved there before any method-state table is designed around current keys.

## 7. Semantic, Fingerprint, and Tenant Evidence

Assets created:

- [`ia5_final_lineage_tenant_test.sql`](../../../../supabase/verification/ia5_final_lineage_tenant_test.sql)
- [`ia5_final_fingerprint_authority_test.sql`](../../../../supabase/verification/ia5_final_fingerprint_authority_test.sql)

Execution was stopped. H-04, H-05, and H-06 remain **provisionally High**.

Static inspection identifies real questions, not final executable findings:

- `physical_location_id` is an ID-only foreign key; the sanctioned event guard
  checks warehouse company but does not visibly establish location company in
  the same way.
- predecessor, reversal, and correction references are ID-only.
- lot and serial fields are text evidence, not governed physical identity.
- fingerprints are caller-supplied 64-character hexadecimal values.
- an idempotent retry can return an existing accepted occurrence before a
  complete material-payload comparison.

These facts do not prove a runtime exploit or require database hashing by
preference. They do mean IA-6 cannot rely on them for physical identity,
cross-company-safe ancestry, or canonical request authority until the prepared
hostile tests pass and the trusted fingerprint canonicalisation boundary is
named and versioned.

## 8. Allocation and Projection Dependency Evidence

The allocation and projection probes are included in
[`ia5_final_uom_policy_dependency_census.sql`](../../../../supabase/verification/ia5_final_uom_policy_dependency_census.sql).
They were not executed.

H-07 remains **provisionally High** and M-01 remains **provisionally Medium**.
No FIFO consumption, WAC pool admission, or replay/projection cut-over is
authorised.

The safe internal dependency rule remains:

- dormant definitions may precede allocation only if they cannot admit or be
  read as authoritative state;
- FIFO issue/layer allocation requires exact quantity/value conservation,
  deterministic residual assignment, one final closure, and ancestry;
- WAC history requires authoritative pool transition and projection/replay
  version identity before data admission;
- no projection may become current by default or by hidden repair.

The C-01 stop prevents approval even of those dormant definitions in the current
phase.

## 9. Security and Audit Boundary Evidence

Asset created:
[`ia5_final_security_owner_census.sql`](../../../../supabase/verification/ia5_final_security_owner_census.sql)

Execution was stopped. H-08 remains **provisionally High**.

Static catalog/migration inspection recorded for later execution:

- IA-5 tables/functions are owned by the repository’s PostgreSQL administrative
  role convention.
- ordinary runtime grants are revoked.
- RLS is enabled but not forced for owners.
- immutability triggers are `ENABLE ALWAYS`; insert consistency/audit triggers
  are origin-only.
- update/delete triggers do not govern `TRUNCATE`.
- `created_by` is an explicit actor input checked against membership, while
  `auth.uid()` is the session identity used by the general audit trigger.
- `audit_identity` equals occurrence identity but is not itself a foreign key to
  an audit row.

These must be classified by the unexecuted census as accepted administrator/DDL
trust, runtime defect, migration-governance weakness, or audit-evidence
weakness. A separate owner role is not presumed necessary.

## 10. Physical-Key and Future-Partition Evidence

Asset created:
[`ia5_final_partition_key_impact_census.sql`](../../../../supabase/verification/ia5_final_partition_key_impact_census.sql)

Execution was stopped. H-09 remains **provisionally High**; immediate
partitioning is not recommended or required by this report.

Current event identity is `PRIMARY KEY (id)`, with scope/order and logical-event
unique constraints. A future hash partition by `id` is compatible with that
identity. Company-hash or company/date range partitioning of the event table
would require partition columns in partitioned-table primary/unique constraints,
or an identity registry/indirection design.

No IA-6 foreign key may be hardened until the prepared census identifies the
actual key graph and an approved future physical-design option. The question is
identity compatibility, not “partition now”.

Proposed benchmark reconsideration points remain workload-driven:

- capture indexed insert latency, scope-lock wait, replay scan, and projection
  rebuild at 100K and 1M events;
- require an explicit physical-design review before the first 10M-event
  production scope or when p95 write/replay objectives fail;
- require partition/archival execution planning before 100M total events.

These are benchmark gates, not predicted capacity guarantees.

## 11. External Principle Comparison

| Official principle | Why it applies to PXL | What it does not prove | PXL result |
| --- | --- | --- | --- |
| PostgreSQL row updates lock the row and conflicting writers wait until the holder ends. [PostgreSQL explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html) | It explains the observed scope-sequence linearisation. | It does not assign economic meaning to the lock winner. | Satisfied as a concurrency mechanism; insufficient as an unstated costing rule. |
| Serializable execution guarantees compatibility with *a* serial order and can abort conflicts. [PostgreSQL transaction isolation](https://www.postgresql.org/docs/16/transaction-iso.html) | It distinguishes database serializability from domain ordering. | It does not select the accounting-correct serial order for two valid commands. | Current row locking creates a serial order, but the accounting tie-break remains unresolved. |
| Event-stream order is crucial, and events need stable stream identifiers/ordering. [Microsoft Event Sourcing pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing) | IA-5 is intended as replay authority. | Generic event sourcing does not prove that accepted chronology is correct FIFO/WAC chronology. | IA-5 preserves a stable accepted stream; domain economic order is not frozen. |
| IAS 2 permits FIFO or weighted-average assignment; FIFO assumes earlier purchases/production are sold first, while weighted average can be recalculated as shipments are received. [IFRS IAS 2](https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/) | Receipt/issue order can affect inventory cost and eligibility. | IAS 2 does not prescribe PXL’s tie-break for identical timestamps. | PXL must freeze its own admissible same-time and backdate rule. |
| Business Central’s public design describes quantity/cost applications and FIFO selection by earliest posting date. [Microsoft item application](https://learn.microsoft.com/en-ca/dynamics365/business-central/design-details-item-application) | It illustrates the enterprise principle that cost-source order/application is explicit and traceable. | It is not a PXL implementation template and does not dictate PXL keys. | PXL has traceable events but lacks an unambiguous same-time costing rule. |
| SAP Business One documents entry sequence as the same-date FIFO tie-break. [SAP perpetual inventory guide](https://help.sap.com/doc/18be8e2f8ba447afb2e7694e141c5837/8.82/en-US/882_GL_B1_HTG_882_PerpInvent.pdf) | It proves admission/entry sequence can be a valid policy when explicitly adopted. | It does not authorize PXL’s lock sequence. | PXL could govern such a rule, but has not done so consistently. |
| Oracle describes cost/accounting dates for late and backdated inventory transactions. [Oracle cost period/transaction accounting](https://docs.oracle.com/en/cloud/saas/supply-chain-and-manufacturing/26b/fapma/cost-accounting-period-statuses-and-transaction-accounting.html) | It illustrates the need for an explicit late/backdated costing policy. | It does not prescribe PXL’s replay algorithm. | PXL defines replay generally, but not the same-time/arrival tie-break exposed here. |

The external comparison supports explicitness and traceability. It does not
select the correction for PXL.

## 12. IA-6 Dependency Matrix

### 12.1 Finding decision matrix

| Finding | Original conclusion | Adjudication conclusion | Executable evidence | Final conclusion | Final severity | Exact target | Blocks design | Blocks schema | Blocks admission | Blocks certification |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C-01 | Economic order unsafe | Accepted stream order sufficient | Two clean permutation runs and one 24-event concurrent lane prove lock-schedule order and material receipt/issue divergence | Valid permanent-foundation defect | **Critical** | Governed pre-IA-6 hardening | Yes, except correction design | Yes | Yes | Yes |
| H-01 | Parent/composite occurrence required | Line occurrence/correlation can suffice | Asset created; not run after stop | Unresolved; no parent-table preference adopted | **High, provisional** | Re-gate after C-01, before admission | Global pause only | Not independently decided | Yes | Yes |
| H-02 | Policy lifecycle incomplete | Correct at IA-6 entry | Asset created; not run | Unresolved | **High, provisional** | Pre-method-state authority gate | Global pause only | Not independently decided | Yes | Yes |
| H-03 | UOM/quantity authority incomplete | Correct at IA-6 entry | Asset created; not run | Unresolved | **High, provisional** | Before any quantity state | Global pause only | Not independently decided | Yes | Yes |
| H-04 | Semantic/physical identity incomplete | Later physical identity may suffice | Asset created; not run | Unresolved | **High, provisional** | Before physical identity/state FK | Global pause only | Not independently decided | Yes | Yes |
| H-05 | Caller fingerprint not authoritative | Trusted service can own it | Asset created; not run | Unresolved | **High, provisional** | Before method-state retry admission | Global pause only | Not independently decided | Yes | Yes |
| H-06 | Tenant lineage insufficient | Service validation can suffice | Asset created; not run | Unresolved | **High, provisional** | Before ancestry FK/data | Global pause only | Not independently decided | Yes | Yes |
| H-07 | Allocation authority incomplete | Deferred inside IA-6 | Probe created; not run | Deferred question remains mandatory | **High, provisional** | Before FIFO consumption/WAC closure | Global pause only | Not independently decided | Yes | Yes |
| H-08 | Owner/security totality incomplete | Admin trust may be acceptable | Census created; not run | Unresolved; no separate owner role mandated | **High, provisional** | Before new IA-6 writers | Global pause only | Not independently decided | Yes | Yes |
| H-09 | Keys may foreclose partitioning | Workload-driven; defer partitioning | Census created; not run | Unresolved key-compatibility question; no partition mandate | **High, provisional** | Before permanent IA-6 FKs | Global pause only | Not independently decided | No direct authority | Yes |
| M-01 | Projection/replay authority incomplete | Deferred inside IA-6 | Probe created; not run | Deferred question remains mandatory | **Medium, provisional** | Before replay/current projection | Global pause only | Not independently decided | Yes | Yes |

The earlier review reportedly contained four Medium findings, but the current
governing instruction identifies only M-01. The remaining topics expressly
named by this gate—event schema evolution, `event_ids` relational consistency,
and actor/audit linkage—are covered under H-04, H-01, and H-08 respectively.
This report does not invent missing original IDs or silently adjudicate them.

### 12.2 Permission matrix

| Permission | Authorised? | Reason |
| --- | --- | --- |
| A — IA-6 design | **No** | Only the governed C-01 hardening decision/design is authorised. |
| B — dormant IA-6 schema | **No** | It could freeze an unresolved economic-order dependency. |
| C — method-state data admission/replay | **No** | Same event set can have schedule-dependent costing input order. |
| D — IA-6 certification | **No** | C-01 and all unexecuted internal gates remain open. |

## 13. Required Corrections

Only the minimum correction set proven necessary is authorised for a governed
hardening phase:

1. **Freeze one explicit economic-order ADR.** It must distinguish accepted
   stream chronology from costing chronology and define same-time independent
   documents, same-document line order, partial occurrences, backdated
   admission, corrections, and cut-off.
2. **Choose the tie-break authority.** Either:
   - explicitly approve accepted admission sequence as PXL accounting chronology
     and reconcile that decision with the source-line/immutable-ID rules; or
   - define an authoritative business-derived economic key that cannot be
     selected accidentally by lock acquisition.
3. **Align all frozen contracts.** The Costing Specification, IA-4 ordering
   blueprint/risk, IA-5 evidence, migration comments, and eventual implementation
   must describe the same tuple and lock semantics.
4. **Prove consequences.** Re-run independent-reset sequential, concurrent,
   randomized, delayed-lock, rollback/retry, same-document, partial, and
   backdate lanes against FIFO and Moving-WAC consequence models.
5. **Do not create IA-6 keys before the decision.** No FIFO layer, WAC pool,
   Specific-ID, physical identity, replay, or projection object may reference
   the present sequence as costing authority until the gate passes.

This report does not prescribe a column, table, migration, or chosen accounting
policy.

## 14. Deferred Corrections

The following are deferred only because the mandatory C-01 stop ended execution,
not because they are accepted:

- H-01 occurrence/composite atomicity;
- H-02 policy succession;
- H-03 UOM/conversion/residual authority;
- H-04 semantic and schema-version authority;
- H-05 fingerprint canonicalisation;
- H-06 tenant-safe lineage;
- H-07 exact allocation closure;
- H-08 writer/audit governance;
- H-09 permanent-key compatibility; and
- M-01 replay/projection authority.

Their assets must be run on a new clean evidence-gate attempt after the economic
order contract is frozen. No later phase may use “deferred” as permission to
admit data.

## 15. Rejected Recommendations

The following recommendations are rejected as unsupported shortcuts:

- “A replay reads the same stored sequence twice, therefore economic order is
  correct.” This proves stream stability, not domain correctness.
- “Use a parent occurrence because enterprise ERPs have one.” No such
  conclusion was executable before the stop.
- “Partition now.” The current evidence establishes a future key-design
  question, not a present workload mandate.
- “Use database hashing because it is stronger.” Fingerprint authority depends
  on a trusted canonicalisation contract; hashing location alone is not the
  decision.
- “A lock winner is never a valid costing order.” SAP’s official documentation
  demonstrates that entry sequence can be an explicit same-date rule. The PXL
  defect is the absence of one consistent approved rule, not the abstract use
  of a sequence.

## 16. Residual Risks

The immediate risk is non-repeatability across independent reconstructions of
the same authoritative command set. Once method state exists, two environments
could legitimately admit equal-time commands in different schedules and build
different FIFO layers, WAC transitions, provisional deficits, correction
deltas, cut-off valuations, and ultimately Posting inputs.

Secondary risks remain unquantified because their hostile tests were stopped:
document-level retry trace, policy succession, UOM quantity conservation,
cross-company physical/lineage facts, materially changed duplicate requests,
allocation closure, projection currentness, owner/audit governance, and future
key conversion.

No current production accounting drift was created: IA-5 remains dormant and
the evidence fixtures were removed by reset.

## 17. Exact IA-6 Internal Phase Sequence

The sequence below is a dependency map, not authorisation to begin IA-6:

0. **Pre-IA-6 governed economic-order hardening**
   - freeze the ADR and consistent contract;
   - apply only the separately approved minimal additive correction, if needed;
   - pass all C-01 permutations and FIFO/WAC consequence proofs.
1. **Re-open final evidence gate**
   - run rollback/retry, occurrence atomicity, UOM/policy, tenant/lineage,
     fingerprint, security, and key-impact assets;
   - decide whether any remaining correction belongs before or inside IA-6.
2. **IA-6A — Authority corrections**
   - only corrections proven by the re-opened gate;
   - policy/UOM/tenant/fingerprint authority must precede dependent keys/data.
3. **IA-6B — Dormant method-state schemas**
   - definitions only;
   - no data admission and no active reader;
   - permanent FKs must pass identity/partition review.
4. **IA-6C — Method-state services**
   - FIFO, WAC, and Specific-ID state admission only after precision,
     idempotency, atomicity, ancestry, and allocation prerequisites pass.
5. **IA-6D — Replay/projection controls**
   - replay version, algorithm, boundary, watermark, rebuild, current-version,
     and fail-closed cut-over controls.
6. **IA-6E — Hostile certification**
   - independent-reset determinism, concurrency, rollback/retry, exact
     reconciliation, security, performance, and dormancy/no-accounting-change
     certification.

No numbered IA-6 subphase may begin while step 0 or step 1 is open.

## 18. Final Authorisation

**OUTCOME C**

IA-5 requires a governed hardening phase before any IA-6 work.

The proven Critical defect is the unresolved permanent distinction between
accepted database chronology and economic costing chronology. The current
implementation lets lock acquisition select the same-time receipt/issue order,
while the frozen Costing Specification says same-time order cannot depend on
database insertion and names ordering inputs not implemented by the current
tuple.

Authorisation is therefore:

- governed C-01 architecture-resolution work: **authorised**;
- IA-6 design: **not authorised**;
- IA-6 dormant schema creation: **not authorised**;
- IA-6 method-state data admission: **not authorised**;
- IA-6 replay/projection use: **not authorised**;
- IA-6 certification: **not authorised**.

IA-5 remains dormant and unmodified. IA-6 remains paused.
