# IA-5 / IA-6 Final Evidence Gate Plan

**Status:** Approved verification plan — execution evidence pending  
**Authority:** Independent IA-5 permanent-foundation evidence gate  
**Scope:** Current local repository and local disposable database only  
**Prohibited:** Production migrations, hosted mutation, IA-5 modification, IA-6
method-state implementation, Posting or Kernel changes, current stock-authority
changes, canonical fixture changes, and accounting-behaviour changes

## 1. Purpose and decision boundary

This gate resolves the conflict between:

1. the initial independent review, which classified IA-5 as not architecturally
   sound and reported one Critical plus nine High findings; and
2. the later adjudication, which allowed IA-5 to remain unchanged while assigning
   mandatory authority gates to IA-6.

The evidence must distinguish four separate permissions:

| Permission | Meaning |
| --- | --- |
| A — design | IA-6 architecture and implementation planning may begin. |
| B — dormant schema | IA-6 may create structures that do not consume unresolved IA-5 authority. |
| C — data admission/replay | IA-6 may persist and replay method state from IA-5 events. |
| D — certification | IA-6 may be certified complete. |

No permission implies a later permission.

## 2. Disputed findings and claims

| Finding | Claim to prove or disprove |
| --- | --- |
| C-01 | Whether the same independent economic commands admitted under different schedules necessarily receive the same costing order, or whether differing order is explicitly authorised as governed accounting chronology. |
| H-01 | Whether line-grained occurrences and SQL transaction atomicity provide permanent document correlation, all-line rollback, document retry, and future multi-line Posting trace without requiring a parent occurrence before IA-6. |
| H-02 | Whether immutable effective-dated policy/profile/scope rows can receive valid successors without rewriting accepted history or leaving overlapping authority. |
| H-03 | Whether current event admission derives item/UOM precision and conversion from governed authority, preserves indivisible residuals, and is safe for layer/pool quantity dependencies. |
| H-04 | Whether IA-6 physical or method-state facts can depend on current event semantics without cross-company location, unversioned evidence, or accidental lot/serial authority. |
| H-05 | Whether idempotency and supplied fingerprints distinguish every material request change and identify a documented trusted canonicalisation boundary. |
| H-06 | Whether any predecessor/ancestry link available to IA-6 is company-consistent and cannot contradict permanent lineage. |
| H-07 | Whether current allocation facts can support exact quantity/value conservation and final residual closure, and which IA-6 structures may exist before that authority is complete. |
| H-08 | Whether IA-5 writer exclusivity, immutability, audit evidence, owner/RLS behaviour, replica-mode triggers, and TRUNCATE controls are database-enforced or convention-dependent. |
| H-09 | Whether present primary/unique keys and future IA-6 foreign keys preserve viable PostgreSQL partition strategies without replacing permanent identities. |
| M-01 | Whether current projection-version facts are sufficient for authoritative replay, rebuild lineage, watermarks, and cut-over, or only for dormant classification. |

## 3. Repository authorities under test

### 3.1 Migrations and functions

- `supabase/migrations/20260726000013_inventory_accounting_ia5_foundation.sql`
- `supabase/migrations/20260726000014_inventory_accounting_ia5_precision_overload.sql`
- `supabase/migrations/20260726000015_inventory_accounting_ia5_immutable_error.sql`
- `fn_ia5_create_dormant_policy_bundle`
- `fn_ia5_record_dormant_inventory_occurrence`
- `fn_ia5_quantize_exact`
- `fn_ia5_guard_inventory_policy_foundation`
- `fn_ia5_guard_inventory_event_fact`
- `fn_ia5_reject_immutable_inventory_fact`
- existing certified `fn_audit_trigger`
- existing P5.2 Posting Kernel and totality guards, for compatibility census only

### 3.2 Constraints and triggers

- company/idempotency and logical-source occurrence unique constraints;
- occurrence/event sequence and scope-sequence unique constraints;
- policy/profile/formula/scope effective-period checks and overlap guards;
- event policy, company, UOM, warehouse, source-link, value, and allocation guards;
- event/source/value/allocation foreign keys;
- all IA-5 `ENABLE ALWAYS` immutable triggers;
- IA-5 insert consistency and audit triggers;
- IA-5 RLS policies, grants, owners, function security, and `search_path`;
- current primary/unique keys that future IA-6 foreign keys would reference.

### 3.3 Frozen architecture and ADRs

- `PXL_INVENTORY_ACCOUNTING_ARCHITECTURE_SPEC.md`
- `PXL_INVENTORY_COSTING_SPEC.md`
- `PXL_INVENTORY_RECONCILIATION_CONTRACT.md`
- `PXL_INVENTORY_LAYER_LIFECYCLE_SPEC.md`
- `PXL_INVENTORY_REPORTING_SPEC.md`
- `PXL_INVENTORY_CANONICAL_DATASET_SPEC.md`
- `PXL_IA3_HARDENING_DECISION_REGISTER.md`
- `PXL_IA4_ARCHITECTURE_TRACEABILITY_MATRIX.md`
- `PXL_IA4_IMPLEMENTATION_BLUEPRINT.md`
- `PXL_IA4_DATABASE_BLUEPRINT.md`
- `PXL_IA4_RPC_SERVICE_POSTING_CONTRACT_BLUEPRINT.md`
- `PXL_IA4_TEST_CANONICAL_RISK_BLUEPRINT.md`
- `ADR-IAA-001_WEIGHTED_AVERAGE_VALUATION_MODEL.md`
- `PXL_INVENTORY_ACCOUNTING_IMPLEMENTATION_ROADMAP.md`
- `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md`
- `AI/AI_STATE.md`

## 4. Executable assets

Only the following verification assets and final report may be created:

- `supabase/verification/ia5_final_ordering_permutation_test.sql`
- `supabase/verification/ia5_final_concurrent_linearisation_test.sql`
- `supabase/verification/ia5_final_rollback_retry_test.sql`
- `supabase/verification/ia5_final_occurrence_atomicity_test.sql`
- `supabase/verification/ia5_final_uom_policy_dependency_census.sql`
- `supabase/verification/ia5_final_lineage_tenant_test.sql`
- `supabase/verification/ia5_final_fingerprint_authority_test.sql`
- `supabase/verification/ia5_final_security_owner_census.sql`
- `supabase/verification/ia5_final_partition_key_impact_census.sql`
- `docs/PXL/07. Inventory/03. Architecture/IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md`

Temporary local output files may be created outside the repository or under an
ignored temporary directory. No migration, seed, canonical fixture, application
code, production function, or production table may be created or changed.

## 5. Test plan and competing expected results

### 5.1 C-01 deterministic economic order

Use equivalent isolated fixtures and clean local resets to execute:

- A then B;
- B then A;
- concurrent A/B;
- randomised concurrent schedules;
- delay before and after the scope-sequence row lock;
- rollback then retry;
- equal authoritative effective timestamps;
- equal document timestamps across different documents;
- one document with differing source-line order;
- backdated admission after a later event;
- partial occurrences admitted in different schedules.

Record canonical command payloads, occurrences, scope sequences, complete economic
order tuples, event fingerprints, FIFO/WAC input order, and a simple consequence
simulation.

Expected under the initial review:

- equivalent commands can receive different scope sequences solely from schedule;
- costing order can change;
- no frozen PXL rule explicitly authorises lock acquisition as economic priority.

Expected under the adjudication:

- the assigned scope sequence is explicitly the authoritative accepted accounting
  chronology;
- differing schedules produce different accepted chronologies only where the
  architecture permits that result;
- replays preserve the recorded order and FIFO/WAC consequences are governed.

Decision rule:

- C-01 is closed only if the frozen PXL rule is explicit, implementation and
  independent-reset evidence match it, and all differing outcomes are authorised.
- If schedule alone changes a material costing result and no explicit rule permits
  it, IA-6 data admission and dependent schema are blocked.
- If the specification is ambiguous, stop with an unresolved architecture decision.

### 5.2 H-01 occurrence and composite atomicity

In rolled-back fixtures execute multi-line occurrences in one transaction, inject a
failure after an earlier line, retry the complete command, and test line-level versus
document-level idempotency. Inspect whether `event_ids` can contradict relational
membership.

Initial-review expectation: permanent parent/composite identity is required before
IA-6 keys.

Adjudication expectation: line occurrences plus an explicit correlation identity and
one SQL transaction are sufficient; parent identity may remain optional.

Decision rule: IA-6 keys may proceed only if current keys do not prevent later
correlation/composite membership and all-line rollback is executable. Data admission
is blocked until document correlation and retry ownership are explicit.

### 5.3 H-02/H-03 policy, UOM, and quantity

Attempt append-only policy succession against open and bounded periods. Inventory all
future IA-6 dependencies on policies/scopes. Test same-company but wrong-item UOM
conversion, caller-supplied factor substitution, high-precision conversion,
unrepresentable base quantity, and residual retention.

Initial-review expectation: IA-5 hardening is required before IA-6 structures.

Adjudication expectation: present columns are sufficiently extensible and corrections
can be an initial IA-6 authority subphase before method-state data admission.

Decision rule:

- no IA-6 method-state quantity may be admitted until item/UOM authority, exact
  conversion identity, and indivisible residual treatment are enforced;
- no IA-6 method state may bind an unresolved policy/scope lifecycle;
- choose pre-IA-6 hardening, initial IA-6 authority correction, or service-only work
  from actual FK and constraint dependencies.

### 5.4 H-04/H-05/H-06 semantics, fingerprints, and tenancy

Attempt cross-company physical-location and ancestry references through the sanctioned
dormant writer where possible and direct owner SQL only as a constraint probe. Submit
materially changed retries while holding supplied fingerprints constant. Inventory
schema-version and physical-identity authority.

Decision rule:

- ordinary runtime exposure is assessed separately from database integrity;
- any IA-6 FK or admitted method state depending on cross-company-capable facts is
  blocked until fixed;
- caller fingerprints are acceptable only with an identified trusted boundary,
  canonicalisation version, algorithm, and changed-payload tests.

### 5.5 H-07/M-01 allocations and projections

Probe whether allocations can disagree with parent quantities/values, have multiple
final rows, or omit a final row. Inventory projection-version replay identity,
predecessor, status, current authority, algorithm version, and exact boundary.

Decision rule: dormant table creation may precede these controls only where no
authority or data admission is possible. FIFO consumption, WAC replay, projection
cut-over, and IA-6 certification remain blocked until their respective exact
constraints pass.

### 5.6 H-08 security and audit

Catalog owners, grants, policies, `prosecdef`, `search_path`, trigger enable state,
TRUNCATE privileges, and all IA-5-capable definer functions. Test replica-role trigger
behaviour and rolled-back TRUNCATE as owner and runtime roles. Compare `created_by`,
occurrence `audit_identity`, and actual `sys_audit_logs`.

Classify each result as accepted superuser/DDL trust, runtime defect,
migration-governance weakness, audit-evidence weakness, or no issue.

### 5.7 H-09 permanent keys

Catalog all IA-5 primary/unique keys and referencing foreign keys. Model realistic
company-hash, company/date-range, and hybrid partition keys against PostgreSQL's
requirement that partitioned-table unique constraints include all partition columns.
Identify which future IA-6 FK identities can remain stable through physical migration.

Decision rule: no immediate partitioning is required, but IA-6 may not harden a foreign
key that forecloses realistic partition strategies without an approved identity/lookup
bridge and conversion plan.

## 6. External research standard

Only official PostgreSQL, Microsoft, Oracle, SAP, Odoo, and recognised accounting
authorities may support external technical principles. Each cited principle must state:

1. why it applies to PXL;
2. what it does not prove; and
3. whether PXL satisfies it.

Generic event-sourcing guidance cannot by itself approve Inventory economic order.

## 7. Stop conditions

Stop verification and report the evidence if:

- frozen PXL specifications contradict or fail to define economic costing order;
- scheduling alone produces materially different costing without an approved rule;
- IA-6 foreign keys would freeze an unresolved identity;
- current conversion authority can create or lose stock quantity;
- cross-company relationships can feed IA-6 state;
- materially changed retries can be misidentified as duplicates;
- allocation or projection state could become authority before closure/replay rules;
- a required test needs any production-object, Posting, Kernel, current-stock,
  accounting-output, migration-history, canonical-seed, or hosted-data change.

## 8. Non-activation confirmation

This evidence gate activates no production or accounting behaviour. All mutable test
fixtures must be local, isolated, and rolled back or removed by a clean local reset.
No IA-6 method-state object will be created. Current Posting, Kernel, stock,
cost-layer, inventory-movement, canonical, and accounting authorities remain
unchanged.
