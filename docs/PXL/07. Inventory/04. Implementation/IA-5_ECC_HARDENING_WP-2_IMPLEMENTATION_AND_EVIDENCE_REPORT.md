# IA-5 ECC Hardening — Work Package 2 Implementation and Evidence Report

**Status:** IMPLEMENTED — independent WP-2 Evidence Gate passed; **WP-2 CERTIFIED 2026-07-30** by the independent Certification Mission
**Implementation date:** 2026-07-29
**Owner / Domain:** Inventory Accounting — IA-5 ECC Hardening programme
**Authority:** ADR-C01; ECC-01; accepted implementation design §17 M2 / §24 WP-2; WP-2 Authorisation Report; EA-001/EA-002-reconciled Detailed Registry Authority Specification
**Scope:** Implementation record and prepared evidence for WP-2 only

## 1. Implementation Result

WP-2 M2 is implemented exactly within its authorised registry-only boundary.
Migration
`supabase/migrations/20260729000017_inventory_accounting_ia5_ecc_wp2_registry_authority.sql`
adds six dormant authority columns to the existing one-row
`public.ref_inventory_event_source_types` registry:

1. `event_effect_map jsonb`;
2. `document_order_key_algorithm text COLLATE "C"`;
3. `line_order_authority text COLLATE "C"`;
4. `occurrence_semantics text COLLATE "C"`;
5. `same_time_class text COLLATE "C"`; and
6. `correction_placement_class text COLLATE "C"`.

All six are `NOT NULL`, have no persistent default, and carry the six governed
validated CHECK constraints. The document-order constraint uses EA-001's exact
59-byte label
`ref_inventory_event_source_types_doc_order_key_algorithm_ck`.

No table, function, trigger, view, policy, type, domain, index, grant, runtime
consumer, production source, event, journal, Posting object, Kernel object,
costing method, replay path, or valuation behaviour was added or changed.

## 2. Exact Registry Authority

The sole retained row remains:

| Attribute | Exact value |
|---|---|
| `source_document_type` | `IA5_CERTIFICATION` |
| `owner_engine` | `Inventory` |
| `is_certification_only` | `true` |
| `is_production_enabled` | `false` |
| `removal_phase` | `IA-6` |
| `event_effect_map` | `{"quantity_decrease":"decrease","quantity_increase":"increase","value_only":"value_only"}` |
| `document_order_key_algorithm` | `canonical_source_document_id` |
| `line_order_authority` | `immutable_source_line_ordinal` |
| `occurrence_semantics` | `explicit_partial_occurrences` |
| `same_time_class` | `event_effect_map` |
| `correction_placement_class` | `base` |

The migration materialises the one existing row through temporary constant
defaults in the same `ALTER TABLE`, then removes every default before commit.
It does not issue `UPDATE`, disable immutability, or create a fixture row.

## 3. Migration Assertions

M2 takes the governed `ACCESS EXCLUSIVE` lock and fails before mutation unless:

- `inventory_events` exists and has zero rows;
- exactly one retained `IA5_CERTIFICATION` source row exists;
- none of the six WP-2 columns already exists;
- the registry's `ENABLE ALWAYS` immutable trigger, RLS, read policy, and
  no-write-grant boundary are intact; and
- all six WP-1 dependencies exist, remain empty and dormant, retain RLS,
  audit/immutability triggers, and expose no client/service write grant.

Postconditions assert exact type, C collation, nullability, absence of defaults,
the six exact validated constraints, the exact row values, zero events,
unchanged controls, no runtime function/view consumer, and no persistent WP-1
fixture data.

## 4. Test and Rollback Evidence

`supabase/tests/105_inventory_accounting_ia5_ecc_wp2_registry_authority_test.sql`
contains 48 pgTAP assertions. It proves structure, exact identifiers and
values, invalid-domain rejection, immutability, RLS/grants, dormancy, unchanged
`inventory_events`, and the EA-002 structural/fixture portions of:

- T-04 Source order (E4/E5);
- T-06 Transition order (E7);
- T-07 Effect order (E3); and
- T-27 Dormancy.

Its minimum user/company/policy/rank data exists only inside the test
transaction and is removed by final `ROLLBACK`.

`supabase/tests/106_inventory_accounting_ia5_ecc_wp2_rollback_test.sql`
contains 21 pgTAP assertions after certification remediation. It first proves
test `105` left no fixture data, explicitly reasserts that the registry contains
exactly one row, then drops the six columns in reverse order under the governed
lock, verifies the exact pre-M2 registry shape and unchanged
security/accounting boundaries, and ends in `ROLLBACK`, restoring the M2-applied
state.

## 5. Validation Evidence

| Validation | Result |
|---|---|
| Fresh migration replay | PASS; every migration through `20260729000017` |
| WP-2 focused tests | PASS; `105`–`106`, 2 files / 69 assertions |
| Full local regression | PASS; 106 files / 2,444 assertions |
| Canonical accounting lane | PASS; 30 files / 748 assertions |
| Documentation / lint / production build / diff | PASS; final local release gate |
| Post-rollback persistence probe | Six WP-2 columns retained; exact source row retained; zero events; zero WP-1/fixture rows |

The canonical lane replayed all migrations, loaded the deterministic seed,
enrichment, and volume layers, and passed its accounting invariants. This is
evidence of no WP-2 accounting drift; it is not WP-2 certification.

The final captured `npm run release:gate:local` invocation exited zero after
passing every local lane: fresh schema, regression, canonical, documentation,
lint, production build/secret guards, and diff.

## 6. Boundary and Risk Review

- **Accounting:** unchanged; no journal generation or GL path changed.
- **Runtime:** unchanged; no function or view consumes the six columns.
- **Security:** registry RLS, select policy, immutability, and no-write grants
  remain intact.
- **Performance:** one `ACCESS EXCLUSIVE` metadata operation on the governed
  one-row registry; no runtime query path or index is added.
- **Data:** one pre-existing certification-only row is materialised; no events
  or policy/rank rows persist.
- **Rollback:** structurally proven while dormant and before downstream
  dependencies.

The independent Evidence Gate completed after the rollback-test remediation and
found no remaining implementation blocker. Activation risk remains none.

## 7. Repository Reconciliation

The implementation state is recorded in the accepted design, detailed
specification, authorisation chronology, AI state, Documentation Index,
Certification Matrix, Accounting Test Book, Table Coverage Matrix, and
generated schema summary. ADR-C01, ECC-01, Posting, Kernel,
`inventory_events`, WP-3…WP-9, and IA-6 remain unchanged.

## 8. Evidence-Gate Boundary

This implementation report prepared evidence; it did not itself execute the
independent Evidence Gate and does not certify WP-2. The subsequent
`IA-5_ECC_HARDENING_WP-2_EVIDENCE_GATE_REPORT.md` records that the gate passed
after the isolated rollback proof was strengthened. The next mission is the
separate WP-2 Certification Mission. It may not begin WP-3.

## 9. Implementation Assessment

The authorised M2 implementation is complete. All observed checks are green,
dormancy and rollback are proven, and the independent Evidence Gate recommended
certification.

**Certification outcome (2026-07-30):** the separate Certification Mission
granted WP-2 certification after independently re-executing every validation
lane, probing the applied catalog, and mutation-verifying the rollback
remediation. Certification covers the WP-2 work package only; it does not lift
the suspended IA-5 permanent-foundation claim, certifies no module or engine, and
confers no WP-3 authority.
