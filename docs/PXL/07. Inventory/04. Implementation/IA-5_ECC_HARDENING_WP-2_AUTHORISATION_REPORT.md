# IA-5 ECC Hardening — Work Package 2 Authorisation Report

**Status:** WP-2 AUTHORISED — 2026-07-29; EA-001/EA-002 reconciled; implementation completed 2026-07-29; independent Evidence Gate pending; not certified
**Authority:** Governance record of the WP-2 authorisation gate outcome (records the owner's authorisation; authorises no scope beyond design §24 #2 / §17 M2)
**Owner / Domain:** Inventory Accounting — IA-5 ECC Hardening programme
**Read When:** Establishing whether WP-2 may begin and under what bounded scope
**Relationship:** Subordinate to `ADR-C01` (frozen) and `ECC-01` (accepted); executes the sequence in `IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §24; parallels `ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md`. This document self-authorises no design change and no work package beyond WP-2.

## Engineering Amendment History

The authorisation decision below is preserved as issued. A subsequent
pre-implementation review found that one exact constraint identifier in the
detailed WP-2 specification was 64 bytes and therefore could not be represented
exactly under PostgreSQL's 63-byte identifier limit. Engineering Amendment
EA-001 corrected that engineering label to
`ref_inventory_event_source_types_doc_order_key_algorithm_ck` (59 ASCII bytes).
No accounting meaning, business meaning, object scope, row value, constraint
predicate, migration sequence, rollback, test intent, dependency, risk, ADR-C01
rule, or ECC-01 rule changed.

A later independent implementation-readiness review found two documentation
inconsistencies: the detailed specification had reassigned the design's T-04
and T-06 family names, and it did not distinguish persistent M2 assertions from
the rolled-back WP-1 certification fixture. Engineering Amendment EA-002
preserves the design §23 numbering, makes the already-required T-07 E3 evidence
explicit, classifies registry completeness as completion evidence rather than a
test-family name, and assigns all rank-resolution data to future rolled-back
certification tests. It changes no test intent or implementation scope.

## 1. Purpose

Formal, implementation-free governance gate deciding whether IA-5 ECC Hardening **Work Package 2** may begin. It records independent verification of the WP-2 prerequisites and the resulting authorisation decision. It does not implement WP-2.

## 2. Programme State at Gate

| Item | Status |
|---|---|
| ADR-C01 | FROZEN |
| ECC-01 | ACCEPTED — OWNER APPROVED |
| WP-1 | CERTIFIED (2026-07-29; independent evidence gate) |
| WP-2 | **AUTHORISED (this report)** |
| WP-3…WP-9 | UNAUTHORISED |
| IA-6 | UNAUTHORISED |

## 3. Prerequisite Verification (independent)

The table records the original 2026-07-29 gate result. EA-001 and EA-002
preserve that chronology and supply the later engineering reconciliations
recorded in §8 and §9.

| # | Condition | Result | Evidence |
|---|---|---|---|
| A | WP-1 certification complete | **Met** | WP-1 evidence gate CERTIFIED; release gate green (regression 104/2375, canonical 30/748) |
| B | All WP-1 documentation reconciled | **Met** | Test book / coverage matrix / guard 075 / doc index reference WP-1; `PXL_SCHEMA_SUMMARY` regenerated (169 migrations, 104 tests) — the last Low item is closed |
| C | Repository internally consistent | **Met** | Full release gate green; governed base-table count 199 = coverage matrix = guard 075 |
| D | AI_STATE reflects WP-1 Certified + WP-2 status | **Met** | AI_STATE updated to WP-1 CERTIFIED and WP-2 AUTHORISED |
| E | No WP-2 objects already exist | **Met** | `ref_inventory_event_source_types` holds only its base columns; none of the WP-2 per-type order-authority columns exist |
| F | No IA-6 implementation exists | **Met** | No IA-6 objects present |
| G | No unresolved Critical/High findings | **Met** | Findings 90 Retested Passed / 0 In Progress / 0 Open |
| H | Design explicitly defines WP-2 | **Met** | Design §24 row 2; §17 M2 |
| I | WP-2 has a bounded scope | **Met** | Objects, seed, tests, rollback, dependency, risk all enumerated (§4 below) |
| J | WP-2 respects ADR-C01/ECC-01/Posting/Kernel/governance | **Met** | Design §22: Posting "Unchanged; no new journal path"; sanctioned mutators and both `ENABLE ALWAYS` triggers untouched; period locking unchanged; dormant-activation risk "No" |

## 4. WP-2 Bounded Scope (design §24 #2 / §17 M2 — authoritative)

- **Nature:** Registry extension — *Registry order authority + admission input contract* (E5 algorithm, line-order authority, transition set, occurrence semantics, same-time class, placement class). Additive and **dormant** (activation risk: No).
- **Objects (M2):** `ref_inventory_event_source_types` **+ per-type order-authority columns**. No new tables, no runtime function, no stream/order-key/comparator (those are WP-3/WP-4+).
- **Seed:** certification scope only — `IA5_CERTIFICATION`.
- **Migration mechanics:** `ACCESS EXCLUSIVE` on the one-row registry table.
- **Traceability:** ECC-01 §4.2 E5/E7, V-10.
- **Tests:** structural/fixture portions of T-04 Source order (E4/E5), T-06
  Transition order (E7), T-07 Effect order (E3), and T-27 Dormancy. “Registry
  completeness” is their combined WP-2 completion evidence, not a test-family
  name. Runtime-ordering portions remain in later work packages.
- **Evidence boundary:** M2 asserts only persistent preconditions, exact
  registry state, registry-local consistency, unchanged security/trigger state,
  zero events, and no persistent WP-1 fixture rows. E3/E4/E7 resolution is
  proved with certification-only data created inside the future WP-2 test
  transaction and removed by its final `ROLLBACK`.
- **Rollback:** drop the added columns.
- **Dependency:** WP-1 / M1 (satisfied).

## 5. Out of Scope for WP-2 (stop conditions carried forward)

No WP-3…WP-9, no IA-6; no replay engine; no FIFO / Moving-WAC / Specific-ID runtime; no valuation streams; no order-key generation; no comparator logic; no Posting Engine / Accounting Kernel / General Ledger change; no `inventory_events` modification; no accounting-policy change; no new ADR. Preserve immutability, dormancy, RLS, multi-company isolation, SECURITY DEFINER standards, PostgreSQL authority, auditability. A non-zero `inventory_events` count or any required Posting/Kernel change is a governance stop.

## 6. Risk Assessment

Residual risk **low**. WP-2 adds dormant columns to a one-row certification-scope registry, seeded for `IA5_CERTIFICATION` only, reversible by dropping the columns, with no runtime activation and no Posting/Kernel surface. The design classifies its dormant-activation risk as "No".

## 7. Authorisation Decision

All ten prerequisites (A–J) are independently satisfied; WP-2's scope is explicitly defined and bounded by the accepted design; no governance conflict remains.

**Decision: WP-2 AUTHORISED — implementation may begin, strictly within the §4 bounded scope.**

Implementation is a separate task. This report performs no implementation.

## 8. Subsequent Repository Reconciliation — EA-001

EA-001 was completed before WP-2 implementation began. The detailed
specification now governs the 59-byte constraint identifier
`ref_inventory_event_source_types_doc_order_key_algorithm_ck`. Repository
status sources were reconciled; at the EA-001 checkpoint WP-2 remained
unimplemented and uncertified, and the amendment made no SQL, schema,
migration, test, database-object, or runtime change.

Because the amendment changes only a representational engineering label, the
bounded scope, prerequisite evidence, residual-risk assessment, and original
owner authorisation remain in force. WP-2 remains authorised and may begin only
through a separate implementation mission within §4. WP-3 through WP-9 and
IA-6 remain unauthorised.

## 9. Subsequent Repository Reconciliation — EA-002

EA-002 was completed before WP-2 implementation began. The design §23 family
definitions remain the single authority: T-04 Source order, T-06 Transition
order, T-07 Effect order, and T-27 Dormancy. Historical executed test numbers
are unchanged. The detailed specification now defines exactly which
structural/fixture evidence WP-2 supplies and prohibits claims that WP-2 proves
the later runtime-ordering portions.

M2 remains limited to the six registry columns and their constraints. It may
create no policy/rank fixture data. Future certification tests own temporary
E3/E4/E7 fixture rows and must remove them by transaction rollback, with
post-test evidence that nothing survives.

The bounded scope, dependency, rollback, original authorisation, accounting
meaning, ADR-C01, and ECC-01 remained in force. At the EA-002 checkpoint WP-2
was authorised, implementation-ready, unimplemented, and uncertified. WP-3
through WP-9 and IA-6 remained unauthorised.

## 10. Subsequent WP-2 Implementation Record

The authorised implementation mission completed the bounded §4 package on
2026-07-29:

- migration `20260729000017` adds only the six governed dormant registry
  columns and constraints and materialises only the exact
  `IA5_CERTIFICATION` values;
- test `105` proves registry completeness and the structural/fixture portions
  of T-04/T-06/T-07/T-27, with all certification data rolled back;
- test `106` proves the drop-column rollback in isolation and rolls back that
  proof so M2 remains installed; and
- fresh replay, 106-file/2,443-assertion regression, and
  30-file/748-assertion canonical accounting validation pass.

The original authorisation decision and chronology above are unchanged. This
implementation record is not an Evidence Gate or certification. WP-2 remains
not certified; WP-3 through WP-9 and IA-6 remain unauthorised.
