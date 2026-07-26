# PXL IA-5 Implementation and Certification Evidence

**Status:** Landed and dormant. Its permanent-foundation certification claim is **SUSPENDED** — the [IA-5/IA-6 Final Evidence Gate](IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md) returned **Outcome C** with C-01 as a Critical permanent-foundation defect, and H-01…H-09 / M-01 remain provisional and unexecuted. This document remains valid as an implementation record; its certification claim must not be cited as current.
**Authority:** Implementation evidence subordinate to the frozen IA-3 architecture and IA-4 blueprints. Superseded on event ordering by [ADR-C01](ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md) and its derivation specification [ECC-01](ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md).
**Owner / Domain:** Inventory Accounting
**Implemented:** 2026-07-26
**Applies To:** IA-5 event, identity, precision, policy, projection, idempotency, and security foundation
**Does Not Authorize:** IA-6 or later behavior, hosted deployment, historical conversion, canonical modernization, P5.3B, P6, or P7

## 1. Certified scope and boundary

IA-5 adds a method-neutral Inventory fact foundation without making it the active
stock, valuation, costing, reporting, or accounting authority. Current production
paths do not read or write IA-5 facts. No historical event, policy, scope, source
relationship, or value was inferred.

The Posting Engine and its six sanctioned persistence functions are unchanged. The
Kernel Totality Guard remains enforced by two `ENABLE ALWAYS` triggers. IA-5 contains
no journal-table DML and introduces no journal writer.

## 2. Migration order and rollback boundary

| Migration | Purpose |
| --- | --- |
| `20260726000013_inventory_accounting_ia5_foundation.sql` | Add dormant Inventory event, policy, scope, precision, occurrence, allocation, projection-version, RLS, trigger, audit, and grant foundations; internalize the legacy generic receipt helper. |
| `20260726000014_inventory_accounting_ia5_precision_overload.sql` | Closed exact-scale bridge for internal integer constants; no rounding and no external grant. |
| `20260726000015_inventory_accounting_ia5_immutable_error.sql` | Diagnostic-only correction to the immutable guard message placeholder; enforcement and SQLSTATE unchanged. |

Dependency point: immediately after
`20260726000012_posting_engine_p52_arm_totality_guard.sql`. All three migrations are
additive forward migrations; no migration history was rewritten.

Rollback boundary: before any IA-6 activation or data conversion, the IA-5 objects can
be removed in reverse dependency order after proving they are empty. The added
`stock_balances` classification columns can be removed after verifying every row still
has `projection_authority='legacy_active'` with no IA-5 version/watermark/fingerprint.
Rollback does not mutate journals, current movements, current layers, current stock
values, or pre-existing Inventory history. Once accepted production events exist,
destructive rollback is prohibited; a governed forward retirement is required.

## 3. Pre-implementation writer and caller census

Body, trigger, grant, policy, migration, seed, test, UI, and generated-client discovery
found:

- 12 direct writers of `inventory_transactions`, `inventory_cost_layers`, or
  `stock_balances`: `fn_add_cost_layer`, `fn_consume_cost_layers`,
  `fn_ensure_stock_balance`, the four source-locked Inventory implementations,
  `fn_post_sales_invoice`, `fn_receive_inventory`, `fn_update_wac`,
  `fn_void_sales_invoice`, and `fn_void_sales_invoice_aud053_core`.
- 20 direct or static transitive Inventory-capable functions before IA-5.
- Five live callers of `fn_consume_cost_layers`: the four source-locked Inventory
  implementations and `fn_post_sales_invoice`.
- Exactly two live function callers of `fn_receive_inventory(jsonb)`:
  `fn_confirm_receiving_report` and `fn_post_cash_purchase`.
- No UI, TypeScript service, or test invokes `fn_receive_inventory`; generated
  database types only declared it. Canonical seeds invoke it as database owner.
- `fn_receive_inventory` was `SECURITY DEFINER` with fixed `search_path=public` but
  executable by `PUBLIC`, `anon`, `authenticated`, and `service_role`.
- The three current derived tables had RLS plus deny-all authenticated write
  policies. Their table privileges remain intentionally unchanged because the
  certified P5.0 negative tests require RLS-filtered UPDATE/DELETE behavior.
- No trigger mutated the three current derived tables.
- Current authoritative types were quantity `NUMERIC(15,4)`, unit cost
  `NUMERIC(18,6)`, current extended totals `NUMERIC(18,2)`, and UOM factors
  `NUMERIC(18,6)`. IA-5 does not rewrite those legacy columns.

No IA-4 contradiction was found. The exposed generic receipt grant could be closed
without changing the two owner-mediated workflows.

## 4. Implemented objects

### 4.1 Immutable and versioned facts

- `ref_inventory_event_source_types`
- `inventory_precision_policies`
- `inventory_accounting_profiles`
- `inventory_cost_formula_policies`
- `inventory_valuation_scopes`
- `inventory_valuation_scope_sequences`
- `inventory_occurrences`
- `inventory_events`
- `inventory_event_source_links`
- `inventory_event_values`
- `inventory_event_allocations`
- `inventory_projection_versions`

The only enabled source type is `IA5_CERTIFICATION`; it is marked
certification-only, not production-enabled, and removal-bound to IA-6. Every company
fact has RLS, member-scoped read policy, and no client/service DML grant.

Eleven fact/version tables have `ENABLE ALWAYS` update/delete rejection triggers.
Eight policy/event consistency triggers validate ownership and effective identity.
Ten company-scoped tables reuse the existing `fn_audit_trigger` on insert. No generic
second audit system was introduced.

### 4.2 Internal services

- `fn_ia5_quantize_exact`: exact scale/overflow validation; never rounds.
- `fn_ia5_derive_unit_rate`: explanatory rate derived from authoritative amount and
  nonzero quantity.
- `fn_ia5_create_dormant_policy_bundle`: certification-only policy/scope creation.
- `fn_ia5_record_dormant_inventory_occurrence`: certification-only atomic occurrence
  and event admission.
- Three closed trigger functions enforce immutable, policy, and event consistency.

There are eight `fn_ia5_%` signatures, five `SECURITY DEFINER`, all with fixed
`search_path=public` where applicable, and zero executable by `PUBLIC`, `anon`,
`authenticated`, or `service_role`.

## 5. Identity, ordering, and precision contract

Event identity requires company, source document type/ID, source line ID, lifecycle
transition, partial occurrence sequence, item, valuation scope, policy versions,
event type/effect/sequence, effective time, occurrence date, source/base UOM and
quantity, immutable source evidence, evidence fingerprint, actor, and timestamp.
Optional reversal/correction/predecessor links are explicit foreign keys. Source links
cannot be inferred.

Company-scoped uniqueness governs both idempotency keys and the complete logical
source occurrence. A retry with the same request fingerprint returns the original
occurrence; changed content under the same key rejects. A legitimate new partial
occurrence, source line, or company does not collide.

The implemented order index is:

1. valuation scope;
2. effective timestamp;
3. accounting date;
4. occurrence date;
5. per-scope accepted sequence;
6. source occurrence sequence;
7. event sequence.

**This is Accepted Event Chronology, not Economic Costing Chronology.** ADR-C01
§14 supersedes the original "economic order" description above. The per-scope
sequence is allocated by an `UPDATE ... RETURNING` against the shared scope-sequence
row — a row lock, not a transaction advisory lock as previously described here — so
the transaction reaching that row first receives the earlier value. The evidence gate
proved that identical same-time receipt/issue evidence therefore receives opposite
orders across schedules. Under ADR-C01 §6.3 and ECC-01 §2.2 an admission-allocated
sequence is prohibited as a costing-order component; the index also lacks the
effect-class rank, source-type rank, document order key, source-line ordinal, and
lifecycle-transition rank that ECC requires. The sequence remains sound and permanent
evidence of accepted admission order. UUIDs identify facts and determine no order.

The conforming correction is not designed here: ECC-01 §14.1 records the gap set and
ADR-C01 §17 governs the reopened evidence gate that must classify the minimum
additive correction.

New authoritative quantities are `NUMERIC(38,6)`, UOM conversion factors
`NUMERIC(38,12)`, authoritative transaction/functional/GL-basis amounts
`NUMERIC(38,8)`, and derived rates `NUMERIC(38,12)`. Allocation facts store exact
amounts, integer residual units, allocation rank, and tie-break identity, providing
the IA-6 basis for largest-remainder allocation without implementing that algorithm.

## 6. Occurrence atomicity and concurrency

An occurrence records request/company/source/source-line/transition identity,
idempotency key, request fingerprint, accepted/rejected state, event IDs/count,
projection effects, optional Posting request/result identity, audit identity, failure
evidence, and retry relationship.

IA-5 admission creates only accepted certification occurrences. A rejected statement
leaves no occurrence, event, projection, Posting, audit, sequence-counter, or
source-lock residue because the service is one database transaction. The schema
retains the rejected/failure fields for a future governed orchestration boundary; no
independent rejected-row writer was added.

The genuine two-session test proves that a concurrent duplicate blocks on the
company/idempotency lock and then returns the first accepted occurrence. Exactly one
occurrence and one event survive. Sequential duplicate, cross-company key isolation,
source-line isolation, partial occurrence, rollback retry, and changed-payload
rejection also pass.

## 7. Projection ownership

Immutable events are authoritative future facts. Current `stock_balances` is explicitly
classified as `legacy_active` projection state; current movements and cost layers keep
their certified legacy roles. IA-5 adds nullable projection version, watermark, and
fingerprint columns with a constraint that prevents their use while the legacy
authority is active.

`inventory_projection_versions` is dormant and client/service non-writable. No rebuild
function, repair job, dual write, self-heal, or new active projection exists. IA-6 must
introduce method state and governed projection rebuild behavior before any cut-over.

## 8. Legacy receipt security resolution

`fn_receive_inventory(jsonb)` is **internalized immediately**:

- all EXECUTE authority is revoked from `PUBLIC`, `anon`, `authenticated`, and
  `service_role`;
- the function remains owner-owned with fixed `search_path=public`;
- `fn_confirm_receiving_report` and `fn_post_cash_purchase` remain its only live
  function callers and retain their existing validation, transaction, stock, layer,
  movement, and Posting behavior;
- canonical seeds continue to run under the database owner;
- no generic replacement mutation RPC was created.

Final retirement is mandatory in **IA-7 acquisition cut-over**, after Receiving Report
and Cash Purchase use the approved acquisition occurrence service. The function is not
falsely described as retired while those callers remain.

## 9. Post-implementation census

- Current derived-state direct writers: 12, unchanged; all classified legacy
  compatibility writers or source-locked current writers.
- New IA-5 direct writers: 2, both internal-only
  (`fn_ia5_create_dormant_policy_bundle`,
  `fn_ia5_record_dormant_inventory_occurrence`).
- Static Inventory-capable graph: 22 = prior 20 plus the two closed IA-5 writers.
- Legacy receipt callers: 2, unchanged.
- Cost-layer consumption callers: 5, unchanged.
- Inventory-related externally executable functions: 18; all are narrow existing
  workflow/readiness functions. No generic Inventory mutation RPC remains.
- Application functions: 417; `SECURITY DEFINER`: 354.
- IA-5 functions externally executable: 0.
- Direct ledger mutators: exactly 6.
- P5.2 totality triggers: 2, both `ENABLE ALWAYS`.
- Kernel violation rows: 0.

The reproducible full catalog is
`supabase/verification/ia5_inventory_writer_security_census.sql`.

## 10. Dormancy and accounting equality

Fresh canonical replay leaves every company-scoped IA-5 table empty and keeps the one
certification source type disabled for production. No existing production function
references IA-5 objects.

The canonical result remains:

- 48 journal headers;
- 138 journal lines;
- 24 tax rows;
- 26 Inventory movements;
- debit = credit = `2,411,134.80`;
- 30 explicit `posting_origin='system'`, 18 valid NULL;
- zero Kernel violations.

Certified fingerprints remain unchanged: GL `75ddb2e4…`, TAX `50469c66…`, Inventory
`d5e87b88…`, Stock `31af15fa…`, and Number Series `39ee27a6…`. Current stock
quantities, layers, valuation behavior, COGS timing, purchase/GRNI behavior, FIFO/WAC/
Specific-ID behavior, reports, seeds, and fixtures are unchanged.

## 11. Test and validation evidence

- Clean migration replay: pass through migration `20260726000015`.
- Transactional rollback-boundary verification:
  `ia5_rollback_boundary.sql`, 6/6; dormant objects were removed without
  `CASCADE`, existing Inventory and journal counts were unchanged, all current
  Inventory authorities remained present, and the transaction was rolled back.
- Focused IA-5 pgTAP: `103_inventory_accounting_ia5_foundation_test.sql`, 99/99.
- Genuine two-session concurrency: `ia5_concurrent_idempotency.sql`, 7/7; local
  committed fixture removed immediately by clean reset.
- P5.2 compatibility/security: tests `102` + `103`, 177/177.
- Canonical replay and certification suite: 30 files / 748 assertions, pass.
- Full regression: 103 files / 2,353 assertions, pass after adding all IA-5 tables to
  the coverage governance registry.
- Documentation validation, application lint, production build, secret scan, and
  `git diff --check`: pass.
- Database migration lint exited successfully. It retained previously known
  diagnostics in legacy dynamic/temp-table functions and reported one non-behavioral
  IA-5 loop-variable shadow warning; no IA-5 error was reported.
- Hosted tests/deployment: not run; explicitly outside IA-5 authority.

## 12. IA-4 deviations and deferred work

No policy or architecture deviation was required. Two bounded implementation
corrections were added as forward migrations: the exact-scale integer bridge and the
immutable diagnostic placeholder correction. Neither changes accounting behavior or
widens access.

IA-5 intentionally does not implement method-state authorities, active occurrence
orchestration, Posting handoff, rejected-request persistence outside a failed
transaction, projection rebuild, active source types, historical conversion, or
canonical scenarios. Those remain assigned to later approved phases.

IA-5 is **CERTIFIED COMPLETE**. This statement does not itself authorize IA-6; IA-6
may begin only under separate governed approval and must remain method-state
foundation work without activating accounting behavior.
