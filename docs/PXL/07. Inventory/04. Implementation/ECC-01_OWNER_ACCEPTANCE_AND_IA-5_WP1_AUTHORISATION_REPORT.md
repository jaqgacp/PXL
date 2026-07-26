# ECC-01 Owner Acceptance and IA-5 Work Package 1 Authorisation Report

**Status:** Final — governance and authorisation gate complete
**Authority:** Governance reconciliation performed under the owner decision recorded in [ECC-01 Formal Owner Acceptance](../03.%20Architecture/ECC-01_FORMAL_OWNER_ACCEPTANCE.md); subordinate to [ADR-C01](../03.%20Architecture/ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md) and [ECC-01](../03.%20Architecture/ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md)
**Owner / Domain:** Inventory Accounting
**Gate date:** 2026-07-26
**Applies To:** Recording ECC-01 acceptance, reconciling programme status, resolving ECC-A-11, and deciding IA-5 ECC Hardening Work Package 1 authorisation
**Read When:** Establishing whether WP-1 may begin and under what conditions
**Do Not Read For:** The derivation (ECC-01), the frozen policy (ADR-C01), or engineering detail (the implementation design)
**Implementation Status:** Documentation and governance only. No SQL, schema, migration, RPC, function, trigger, view, test, seed, configuration, grant, RLS, or source-code change was made.

---

## 1. Executive Decision

**A — AUTHORISED TO BEGIN WORK PACKAGE 1.**

ECC-01 is **ACCEPTED — OWNER APPROVED** and **not frozen**. ECC-A-11 (PG-01) is
resolved as Outcome B by a non-normative authority map over existing accepted
documents. Every Work Package 1 prerequisite in the implementation design is
satisfied, including the zero-data precondition, which was verified read-only
against the local database (`inventory_events` = 0 rows on a fully migrated
`--no-seed` instance). No blocking finding remains. Two non-blocking findings are
recorded, both corrected in documentation during this gate.

No implementation was performed. **IA-6 remains unauthorised**, and the C-01
program stop remains open.

## 2. Owner Authority

The decision is the PXL Repository Owner's, exercising the human structural
authority reserved by `PXL_PRINCIPLES.md` §21 and the authority order in
`AI/AGENT_SYSTEM_PROMPT.md`. The repository defines no more precise owner
designation, no signature convention, and no freeze-authority register; none was
invented. The canonical record of the decision is
[`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`](../03.%20Architecture/ECC-01_FORMAL_OWNER_ACCEPTANCE.md),
and it is recorded exactly once — every other document points to it.

## 3. Documents Reviewed

Read in full or to the depth the decision required, not accepted on assertion:

| Document | Purpose in this gate | Finding |
| --- | --- | --- |
| `AI/AI_STATE.md` | Current programme state | Accurate at entry; updated by this gate |
| `AI/AGENT_SYSTEM_PROMPT.md` | Authority order, documentation governance | Effective governance authority; no PG-01 reference |
| `00. Governance/PXL_PRINCIPLES.md` §21–§27 | Structural/freeze authority | Human-controlled; no freeze procedure defined |
| `ADR-C01_..._COSTING_ORDER_AUTHORITY.md` (842 lines) | Controlling policy | Frozen, unchanged, unmodified by this gate |
| `ECC-01_..._DERIVATION_SPEC.md` (1,560 lines) | Specification accepted | Status `PROPOSED — RECOMMENDED FOR ACCEPTANCE` at entry; header updated |
| `ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md` (931 lines) | Acceptance evidence | Outcome B; 14/14 ADR conformity; ECC-A-01…A-17 verified |
| `IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` (1,019 lines) | Controlling engineering plan | Readiness B; WP-1 §24, M1 §17, data §16, boundaries §21–§22 |
| `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` | IA-5 implementation evidence | Already corrected to landed/dormant, certification suspended |
| `IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md` | Evidence gate | Outcome C, C-01 Critical, controlling and unchanged |
| `PXL_INVENTORY_ACCOUNTING_IMPLEMENTATION_ROADMAP.md` | Phase register | **Stale** — claimed IA-5 certified and IA-6 next; corrected (GA-02) |
| `PXL_INVENTORY_COSTING_SPEC.md` | Current costing specification | Supersession pointer to ADR-C01 §6.3/§14 present; unchanged |
| `13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md` | Certification dashboard | **Stale** on IA-5 certification; corrected (GA-03) |
| `PXL_DOCUMENTATION_INDEX.md` | Documentation index | Registered the new records; ECC-01 row updated |
| Repository-wide `PG-01` search (all file types) | ECC-A-11 | Four live citations only: ADR-C01 header/§16/§17(7), ECC-01 §15(13). No canonical document, anywhere |
| `supabase/migrations/20260726000013…15`, `supabase/tests/103` | Zero-data and dormancy evidence | Read-only; unchanged |

Two artefacts named by earlier instructions still do not exist and were not
invented: `00_PXL_ARCHITECTURE_PRINCIPLES.md` (equivalent:
`00. Governance/PXL_PRINCIPLES.md`) and a standalone "IA-5 post-ADR conformity
review" (equivalent: ADR-C01 §15(1) and ECC-01 §14.1, plus the evidence gate
report).

## 4. ECC-01 Formal Acceptance

Recorded in `ECC-01_FORMAL_OWNER_ACCEPTANCE.md`, covering: the fourteen-component
ordering tuple; the eight-stage algorithm and normalization contract; the four
proved properties; V-01…V-35 and F-01…F-15 as the conformance surface; the
replay, cut-off, backdating, correction-anchoring, and version-governance
contracts; the prohibition on schedule-derived accounting authority; and
§14.1/§15 as the conformance-gap list IA-5 hardening must close. Acceptance
includes Amendment A1 (2026-07-26) as part of the accepted text.

## 5. ECC-01 Status Transition

| | Status |
| --- | --- |
| From | `PROPOSED — RECOMMENDED FOR ACCEPTANCE` |
| To | **`ACCEPTED — OWNER APPROVED`** |

Applied to the ECC-01 header and reconciled in `AI_STATE.md`, the documentation
index, and the implementation design. The Final Architecture Acceptance Report
retains its original conclusion and carries a subsequent-status note; its history
was not rewritten.

## 6. Freeze Authority Determination

**FREEZE STATUS: NOT YET FORMALLY FROZEN.**

The repository grants no authority making owner acceptance *itself* a freeze.
`PXL_PRINCIPLES.md` §21 reserves structural authority to the human architect and
prohibits self-certification by implication; `AGENT_SYSTEM_PROMPT.md` requires
explicit approval for documentation status changes; neither defines a freeze
procedure, and no freeze-authority register exists. ECC-01's header makes
acceptance *necessary* for freeze; nothing makes it *sufficient*, and the
acceptance report §25 treats "formal acceptance and freeze" as two owner acts.
The owner exercised acceptance only.

Consequence is bounded: ECC-01's Supersession Rule already restricts change to an
approved successor ADR or an approved ECC-02 that does not weaken ADR-C01. The
absence of a freeze label licenses no amendment, and specifically no AI-performed
amendment. Freeze remains available as a separate later owner act. **Freeze
status is not overstated anywhere in the reconciled documentation.**

## 7. ADR-C01 Relationship

ADR-C01 remains **Frozen, controlling, and byte-unchanged**. ECC-01 is
subordinate: acceptance changes no ordering component, rank, comparator
position, proof, or accounting policy, and reverses no ADR decision (conformity
14/14, acceptance report §5). ADR-C01 was deliberately not edited — including
for the PG-01 references — because only an approved successor ADR may change it.

## 8. Non-Blocking Clarifications Status

| Finding | Status | Owner / phase |
| --- | --- | --- |
| ECC-A-01 … ECC-A-04 | Incorporated — resolved in-document by Amendment A1 (were implementation-blocking while open) | Closed |
| ECC-A-05 … ECC-A-10 | Incorporated — Amendment A1; carried into V-31…V-35 | Closed |
| **ECC-A-11** | **Resolved by owner decision** — Outcome B (§9) | Closed |
| ECC-A-12 | Resolved — IA-5 evidence document corrected to landed/dormant, certification suspended | Closed |
| ECC-A-13 | Resolved — Costing Specification §1 supersession pointer present | Closed |
| ECC-A-14 | Resolved — documentation index registers the chronology documents | Closed |
| ECC-A-15 | **Retained, informational.** E10 must not introduce a discriminator absent from E1–E9 | Event Source Registry design — WP-2 |
| ECC-A-16 | **Retained, informational.** Prefer a governed source sequence over the E5 identity fallback; disclose fallback use as convention | WP-2 and any production source-type enablement |
| ECC-A-17 | **Retained, informational.** ECC-01 §15 is prescriptive, not an authorisation; existing fencing sufficient | No action |

No resolved architecture finding was reopened, and no retained clarification was
converted into new implementation policy. None of ECC-A-15…A-17 affects WP-1,
which creates no registry rule and no source-type enablement.

## 9. PG-01 Governance Reconciliation

**Outcome B — existing accepted documents collectively embody PG-01.**

Investigation: a repository-wide search across all file types found the string
`PG-01` in exactly two specifications (ADR-C01 header, §16, §17(7); ECC-01
§15(13)) plus the reports that raised the gap. No canonical document exists under
any path or name, and no `PG-*` document convention exists anywhere in the
repository. Outcome A is therefore unavailable; Outcome D (pure stale-label
replacement) is impossible because ADR-C01 is frozen and cannot be edited;
Outcome C would have required fabricating a governance specification that was
never approved.

Resolution: [`00. Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md)
maps each invoked PG-01 principle — document precedence, architecture authority,
freeze authority, supersession, phase authority, programme state, stop authority,
certification authority, one-source-of-truth, and ADR-C01 §17(7)'s
"documentation and implementation evidence agree" clause — to the accepted
document that actually owns it. The map is explicitly **non-normative**,
introduces no policy, supersedes no source, does not amend ADR-C01, and yields to
its sources on any disagreement.

**Does this block Work Package 1?** No. The material authorities WP-1 needs —
phase authority, document precedence, and the prohibition on AI-performed freeze
— are all establishable from existing accepted documents, exactly as the
acceptance report §3 concluded, and the conservative reading was applied
throughout. ADR-C01 §17(7)'s gate-closing condition is now resolvable, which
matters for the reopened evidence gate at WP-9, not for WP-1.

## 10. IA-5 Implementation Design Status

`IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` remains the
controlling engineering plan and is current: its current-state map was read from
migration source, and the objects it describes match the local database as
inspected during this gate. Its readiness conclusion was **B — READY AFTER OWNER
ACCEPTANCE OF ECC-01**; the single unmet criterion ("ECC-01 acceptance authority
sufficient") is now met. Its §27 open decisions 7 (acceptance) and 8 (PG-01) are
both closed; items 3–6 are engineering choices already decided in-document; items
9, 11, 12 are out of WP-1's scope. **Zero unresolved accounting-policy
questions**, confirmed independently against §27 and §6.4.

## 11. Work Package 1 Scope Confirmed

Taken from the design §24 and §17 (M1), not from any summary:

- **Objective:** order-policy and version foundation.
- **Objects (M1, new tables only):** `inventory_event_order_policies`,
  `inventory_event_effect_ranks`, `inventory_source_type_ranks`,
  `inventory_transition_ranks`, `inventory_canonical_form_versions`,
  `inventory_correction_graph_versions` — the six version objects enumerated in
  §6.4 and named in §24.
- **Controls:** existing IA-5 guard, RLS (`SELECT`-only via
  `is_company_member`), grant-revocation, audit-trigger, and `ENABLE ALWAYS`
  immutability patterns applied unchanged; dormancy `CHECK` on every new table.
- **Seed:** certification-only rank set only (effect ranks 10/20/30/40/50;
  source-type and transition ranks for `IA5_CERTIFICATION`).
- **Explicitly excluded:** nothing added to `inventory_events`; no grant exposed;
  no registry extension (WP-2); no stream or order-key table (WP-3/WP-4); no
  writer, guard, ordering, or fingerprint function (WP-5…WP-7); no index swap
  (WP-8); no certification lane (WP-9).
- **Precondition:** `inventory_events` count = 0.
- **Tests:** T-01 (deterministic tuple, structural at this stage) and T-27
  (dormancy).
- **Completion evidence:** structure and dormancy tests green; the version
  vector `V` resolvable.
- **Rollback point:** drop M1 in reverse dependency order — IA-5 returns
  byte-identical, because nothing existing is altered.
- **Stop conditions:** non-zero `inventory_events`; any need to touch
  `inventory_events`, Posting, or the Kernel; any scope difference from §24.

## 12. Work Package 1 Prerequisites

| # | Prerequisite | Result | Evidence |
| ---: | --- | --- | --- |
| 1 | ECC-01 formally owner accepted | **Met** | `ECC-01_FORMAL_OWNER_ACCEPTANCE.md` |
| 2 | ADR-C01 controlling and unchanged | **Met** | Frozen; not edited by this gate (§7) |
| 3 | Implementation design current | **Met** | §10; current-state map verified against the local database |
| 4 | No unresolved accounting-policy decision in WP-1 | **Met** | Design §27; ranks are certification-only values, sparse per N-03 |
| 5 | No Posting Engine authority change | **Met** | Design §22; M1 creates new tables only |
| 6 | No Accounting Kernel authority change | **Met** | Six sanctioned persistence functions and both `ENABLE ALWAYS` totality triggers untouched |
| 7 | Does not authorise IA-6 | **Met** | Design §6.5 excludes every IA-6 object; §30 |
| 8 | Dormancy preserved | **Met** | Design §21; dormancy `CHECK` on every new table; zero consumers |
| 9 | No runtime costing activated | **Met** | WP-1 creates no function; ordering/fold functions are WP-7/IA-6 |
| 10 | No new production RPC or grant | **Met** | Design §19: `REVOKE ALL`, `GRANT SELECT` only; no `EXECUTE` grant |
| 11 | No ordering fields added to `inventory_events` | **Met** | Design §6.1: the ECC key is a 1:1 sidecar, and it is WP-4, not WP-1 |
| 12 | Zero-accepted-events precondition verifiable | **Met** | §13 — verified read-only |
| 13 | No hosted production data requiring backfill | **Met for the authorised scope** | §13 — hosted is out of scope and lacks the IA-5 schema entirely |
| 14 | Unrelated working-tree changes preservable | **Met** | This gate changed documentation only; the pre-existing dirty migration/test/doc set was not touched |
| 15 | Package defines scope, objects, tests, evidence, rollback, stop conditions, completion criteria | **Met** | §11 above, from design §24 and §17 |

## 13. Zero-Data Precondition Review

Verified read-only. No data was mutated, no test was run, no reset or seed was
performed.

Local database (`supabase_db_PXL`, migrations applied through `20260726000015`,
no seed):

| Relation | Rows |
| --- | ---: |
| `inventory_events` | **0** |
| `inventory_occurrences` | 0 |
| `inventory_event_values` | 0 |
| `inventory_event_allocations` | 0 |
| `inventory_event_source_links` | 0 |
| `inventory_valuation_scopes` | 0 |
| `inventory_valuation_scope_sequences` | 0 |
| `inventory_projection_versions` | 0 |
| `ref_inventory_event_source_types` | 1 (`IA5_CERTIFICATION`, `is_certification_only = true`, `is_production_enabled = false`) |
| `stock_balances` with `projection_authority <> 'legacy_active'` | 0 |

Additional read-only checks: the production-disable guard exists as
`CHECK (NOT is_production_enabled)` and `CHECK (is_certification_only)` on the
source-type registry (migration `20260726000013`); the only `INSERT INTO
public.inventory_events` in the repository is inside
`fn_ia5_record_dormant_inventory_occurrence` (owner-only, no grants) and in test
`103`; **no seed file references `inventory_events`**, so no fixture rows survive
outside a transaction.

**Hosted verification is unavailable in this session** and is not claimed. The
linked project is `bskjkogijpbhukjkagfj`; `supabase migration list --linked`
returned "Access token not provided", so no hosted state was read. The documented
position — hosted migration history synchronised through `20260716000005`, every
migration from `20260723000001` onward local-only — implies the IA-5 relations do
not exist hosted at all, and hosted application remains prohibited without
explicit approval. WP-1 is a local-only package; the hosted question does not
gate it, and no hosted zero-data claim is made here.

**Conclusion:** the precondition is satisfied. No non-test accepted inventory
event exists, nothing requires ECC mapping, and no backfill or order-affecting
default is needed. The implementing session must re-verify the count immediately
before M1, as design §16.2(4) requires: a non-zero count is a stop condition,
not a backfill exercise.

## 14. Posting and Kernel Boundary Confirmation

WP-1 creates six new dormant tables and touches no existing object. It writes no
journal entry, selects no GL account, determines no tax, changes no period lock,
and touches neither `fn_add_posting_line` nor the totality guard. The six
sanctioned persistence functions and both `ENABLE ALWAYS` triggers remain exactly
as certified under P5.2; `inventory_events.journal_entry_id` keeps its
`CHECK (journal_entry_id IS NULL)`. Any required Posting or Kernel change would
be a stop condition; **none is required**.

## 15. Dormancy Confirmation

Preserved and strengthened: dormancy `CHECK` on every new table, no `EXECUTE`
grant, no `INSERT`/`UPDATE`/`DELETE` grant to any role, zero consumers (no
workflow, report, RPC, or UI reads these objects), no scheduler, no feature flag
— dormancy is enforced by constraints and absent grants, which cannot be toggled
at runtime. `stock_balances` keeps `projection_authority = 'legacy_active'`.
Activation still requires all four conditions of design §21, of which recorded
ECC-01 acceptance is only the first.

## 16. IA-6 Prohibition

**IA-6 remains unauthorised.** Neither the owner acceptance nor this
authorisation touches it. Design §6.5 explicitly withholds every IA-6 object
(`inventory_replay_versions`, `inventory_fifo_layers`, `inventory_wac_pools`,
`inventory_wac_pool_versions`, `inventory_identities`, `inventory_deficits`, and
the remaining IA-4 §5–§6 tables). Method state, replay execution, projection
cut-over, and costing activation are outside WP-1 and outside the whole IA-5
hardening plan, which owns ECC-01 stages 1–6 plus the ordered-input fingerprint
and nothing beyond. Every document reconciled by this gate states IA-6 as
unauthorised.

## 17. Documentation Reconciliation Performed

Documentation only.

| File | Change |
| --- | --- |
| `03. Architecture/ECC-01_FORMAL_OWNER_ACCEPTANCE.md` | **Created** — the single canonical owner-acceptance record |
| `00. Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md` | **Created** — non-normative PG-01 authority map (ECC-A-11, Outcome B) |
| `04. Implementation/ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md` | **Created** — this report |
| `03. Architecture/ECC-01_..._DERIVATION_SPEC.md` | Status → `ACCEPTED — OWNER APPROVED`, not frozen; acceptance cross-reference; §15(13) PG-01 citation pointed at the authority map |
| `03. Architecture/ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md` | Subsequent-status notes only (header, §4, ECC-A-11, §24). Original Outcome B conclusion and the "acceptance outstanding" history preserved verbatim |
| `04. Implementation/IA-5_..._IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` | Status → design complete, WP-1 authorised; §2, §27(7)(8), §29, §30 subsequent-status notes; object-count corrections (GA-01) |
| `03. Architecture/PXL_INVENTORY_ACCOUNTING_IMPLEMENTATION_ROADMAP.md` | IA-5 "certified complete" and "next phase is IA-6" corrected (GA-02) |
| `13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md` | Inventory module and Inventory Engine rows corrected: IA-5 certification suspended, not certified (GA-03) |
| `PXL_DOCUMENTATION_INDEX.md` | ECC-01 row updated; rows added for the acceptance record, this report, and the PG-01 authority map |
| `AI/AI_STATE.md` | Programme state, chronology paragraph, and Recommended Next Task replaced with the current governed state |

Deliberately **not** modified: `ADR-C01` (frozen — interpreted, never edited);
`IA5_IA6_FINAL_EVIDENCE_GATE_PLAN.md` / `_REPORT.md` (historical evidence of a
completed gate); `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` (already
correct); `PXL_INVENTORY_COSTING_SPEC.md` (already carries its supersession
pointer); all IA-4 blueprints; every Posting and Kernel document; and every
non-documentation file.

## 18. Blocking Findings

**None.**

## 19. Non-Blocking Findings

**GA-01 — Object-count arithmetic in the implementation design.** Low;
documentation; corrected in place. §24 said "the five version tables" and "the
five dormant version objects" while naming six, §17 (M1) said "5 new tables",
and §17 (M9) said "8 new tables" against nine. §6.4's enumeration is
unambiguous and was treated as authoritative; the cardinal words were corrected
to six and nine. No object was added, removed, or renamed, and no design content
changed. The implementer follows the named list, and must register **every** new
`public` base table in `PXL_TABLE_COVERAGE_MATRIX.md` and guard `075` regardless
of the count.

**GA-02 — Inventory roadmap claimed IA-5 certified and IA-6 next.** Medium;
documentation; corrected. `PXL_INVENTORY_ACCOUNTING_IMPLEMENTATION_ROADMAP.md`
still read "IA-5 is certified complete" with "the next recommended governed phase
is IA-6", contradicting the evidence gate's Outcome C and this authorisation.
Corrected to landed/dormant with certification suspended, and to WP-1 as the next
phase with IA-6 unauthorised.

**GA-03 — Certification matrix carried the same stale IA-5 claim.** Medium;
documentation; corrected. The Inventory module row and the Inventory Engine row
described the IA-5 foundation as certified. Corrected to record the suspension
and its cause; no certification status of any other engine or module was touched.

**Retained informational items:** ECC-A-15, ECC-A-16, ECC-A-17 (§8), all owned by
WP-2 or later, none affecting WP-1.

## 20. Work Package 1 Authorisation Decision

**A — AUTHORISED TO BEGIN WORK PACKAGE 1.**

Owner acceptance is recorded; no blocking governance issue remains; WP-1's scope
is exact and taken from the approved design; the zero-data prerequisite is
satisfied by measurement; no accounting-policy ambiguity remains; the Posting and
Kernel boundaries are untouched; dormancy is preserved; and the package is
implementable exactly as designed.

Binding conditions carried into execution: implement §24/§17 (M1) as written;
stop if `inventory_events` is non-zero; stop if anything requires touching
`inventory_events`, Posting, or the Kernel; stop if the intended scope differs
from the approved design; take no hosted action; begin no WP-2…WP-9 work until
WP-1 is complete and evidenced.

## 21. Exact Next Authorised Phase

**IA-5 ECONOMIC COSTING CHRONOLOGY HARDENING — IMPLEMENTATION, WORK PACKAGE 1.**

To be executed under a separate implementation instruction, with a WP-1 evidence
record on completion. WP-2…WP-9, IA-6, hosted migration, production source-type
enablement, and any Posting or Kernel change remain unauthorised.

## 22. Final Governance Statement

ECC-01 has been formally accepted by the PXL Repository Owner as the
authoritative Economic Costing Chronology derivation specification. The IA-5 ECC
Hardening Implementation Design remains the controlling engineering plan. IA-5
Economic Costing Chronology Hardening — Implementation Work Package 1 is
authorised as the next programme phase, subject to the scope, prerequisites, stop
conditions, dormancy controls, and certification requirements recorded in the
accepted design. No implementation was performed during this owner-acceptance and
authorisation gate. IA-6 remains unauthorised.
