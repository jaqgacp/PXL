# IA-5 ECC Hardening — Work Package 2 Evidence Gate Report

**Status:** EVIDENCE GATE PASSED — recommendation accepted; **WP-2 CERTIFIED 2026-07-30** by the separate Certification Mission (see §10)
**Gate date:** 2026-07-29
**Owner / Domain:** Inventory Accounting — IA-5 ECC Hardening programme
**Authority:** Independent evidence review under ADR-C01, ECC-01, the accepted
IA-5 ECC Hardening Implementation Design, the WP-2 Authorisation Report, and the
EA-001/EA-002-reconciled Detailed Registry Authority Specification
**Scope:** WP-2 M2 only; this report neither certifies WP-2 nor authorises WP-3

## 1. Gate Decision

**WP-2 EVIDENCE GATE PASSED.**

The authorised six-column dormant registry extension, its migration controls,
its structural/fixture evidence, and its rollback have been independently
re-executed and verified. The certification-review rollback finding was genuine
and was remediated before this gate by adding one fail-closed assertion to test
`106`: the registry total must equal exactly one row immediately before the
destructive reverse-order column drops.

No engineering, accounting, security, documentation, or repository-consistency
blocker remains for the separate WP-2 Certification Mission. This report
recommends certification; it does not perform certification.

## 2. Authority and Scope Reviewed

The gate reviewed:

- ADR-C01 and ECC-01 boundaries;
- the accepted IA-5 ECC Hardening Implementation Design §17 M2, §23.1, §24 WP-2,
  and §25 rollback;
- the WP-2 Authorisation Report;
- EA-001 and EA-002 in the Detailed Registry Authority Specification;
- migration `20260729000017`;
- tests `105` and `106`;
- the WP-2 Implementation and Evidence Report;
- AI state, Documentation Index, Certification Matrix, Accounting Test Book,
  Table Coverage Matrix, and generated Schema Summary; and
- the applied local PostgreSQL catalog after fresh replay and canonical
  validation.

The gate did not review or authorise WP-3 through WP-9, IA-6, hosted
application, production source enablement, method state, costing, valuation,
replay, Posting, or Kernel changes.

## 3. Certification Finding Remediation

### 3.1 Finding

Detailed Specification §7.1 requires
`ref_inventory_event_source_types` to contain exactly one row. Section 7.4
requires the isolated rollback proof to reassert the rollback preconditions
before dropping the six columns. The pre-remediation test `106` proved one
matching `IA5_CERTIFICATION` row but did not prove that no additional registry
row existed.

### 3.2 Minimum correction

Test `106` now:

- plans 21 assertions instead of 20; and
- asserts `count(*) = 1` on the registry immediately before the existing exact
  row, zero-event, immutability, RLS, grant, lock, and drop assertions.

No other assertion, migration, database object, architectural rule, accounting
rule, runtime behavior, or rollback operation changed.

### 3.3 Result

The corrected isolated rollback lane fails closed on an extra registry row and
satisfies the exact §7.1/§7.4 contract. Test `106` still drops only the six WP-2
columns in reverse order and finishes with `ROLLBACK`, restoring the M2-applied
schema.

## 4. Engineering Compliance

| Requirement | Result | Evidence |
|---|---|---|
| Exactly six columns | PASS | Applied catalog: six governed columns |
| Correct types/nullability/defaults | PASS | All six `NOT NULL`; no persistent default |
| Governed constraints | PASS | Six exact validated CHECK constraints |
| EA-001 identifier | PASS | `ref_inventory_event_source_types_doc_order_key_algorithm_ck`; PostgreSQL-safe |
| Exact authority row | PASS | Registry total 1; exact `IA5_CERTIFICATION` total 1 |
| Migration behavior | PASS | Fresh no-seed replay through `20260729000017` |
| Rollback behavior | PASS | Corrected isolated test `106`, final transaction rollback |
| Scope boundary | PASS | No runtime consumer; no WP-3+ object or behavior |

## 5. Accounting Compliance

| Requirement | Result |
|---|---|
| `inventory_events` unchanged and empty | PASS — 0 rows |
| Posting and Kernel unchanged | PASS |
| Journal generation unchanged | PASS |
| Costing, valuation, and replay unchanged | PASS |
| Canonical accounting | PASS — 30 files / 748 assertions |
| Canonical journal balance | PASS — debit = credit = `2,411,134.80` |
| Kernel guard violations | PASS — 0 rows |

ADR-C01 and ECC-01 remain unchanged. WP-2 stores dormant registry declarations
only and introduces no accounting or runtime authority.

## 6. Security Compliance

Applied-catalog verification passed:

- registry RLS enabled;
- the governed read policy present;
- zero client/service write grants;
- the immutable trigger present and `ENABLE ALWAYS`;
- certification-only and production-disabled registry state retained;
- zero persistent WP-1 fixture rows; and
- zero function or view consumers of the six WP-2 columns.

No privilege, RLS, immutability, or write-boundary change was introduced by the
remediation.

## 7. Test and Validation Evidence

| Validation | Result |
|---|---|
| Fresh migration replay | PASS |
| WP-2 focused tests `105`–`106` | PASS — 2 files / 69 assertions |
| Full pgTAP regression | PASS — 106 files / 2,444 assertions |
| Canonical accounting lane | PASS — 30 files / 748 assertions |
| Post-gate catalog and dormancy probe | PASS |
| Documentation consistency | PASS |
| Lint, production build, and diff checks | PASS |

Tests `105` and `106` retain the EA-002 allocation:

- T-04 Source order (E4/E5), structural/fixture portion;
- T-06 Transition order (E7), structural/fixture portion;
- T-07 Effect order (E3), structural/fixture portion; and
- T-27 Dormancy.

No test claims the later runtime-ordering portions of those families.

## 8. Repository Consistency

The current status is:

- WP-1 certified;
- WP-2 implemented;
- WP-2 Evidence Gate passed;
- WP-2 recommended for certification but not yet certified;
- WP-3 through WP-9 unauthorised;
- IA-6 unauthorised;
- ADR-C01 unchanged and frozen;
- ECC-01 unchanged, accepted, and not frozen; and
- the broader C-01 programme stop unchanged pending WP-9 evidence.

Historical authorisation, EA-001, EA-002, implementation, and the earlier
certification rejection chronology remain intact. This report records the
subsequent remediation and Evidence Gate outcome only.

## 9. Final Recommendation

**RECOMMEND WP-2 CERTIFICATION.**

The next authorised mission is the formal WP-2 Certification Mission. It must
make the final governance decision and must not infer authority for WP-3.

## 10. Certification Outcome (recorded 2026-07-30)

This section records the outcome of the subsequent mission; it does not alter any
gate finding above.

The independent WP-2 Certification Mission **granted certification on
2026-07-30**. It did not rely on this report's conclusions: it re-executed fresh
no-seed replay, focused tests `105`/`106` (69 assertions), full regression
(106 files / 2,444 assertions), canonical accounting (30 files / 748 assertions),
and the lint, build, and diff lanes; it independently probed the applied catalog
for column shape, constraint definitions, exact registry values, dormancy, RLS,
grants, column privileges, immutability, and consumers — extending the consumer
sweep beyond this gate's scope to procedures, materialised views, rules, indexes,
generated columns, policy expressions, and application source, all zero.

It also mutation-verified the §3 remediation instead of accepting it on report.
Injecting a second valid registry row makes the added total-count assertion fail
closed, while the pre-remediation exact-row assertion still passes — independently
confirming that the certification finding was genuine and is now closed.

Certification covers the WP-2 work package only. The suspended IA-5
permanent-foundation claim, the uncertified Inventory module and engine, and the
unauthorised status of WP-3 through WP-9 and IA-6 are all unchanged.
