# ECC-01 Formal Owner Acceptance

**Status:** Effective — owner decision recorded
**Decision:** ECC-01 is **ACCEPTED — OWNER APPROVED**. **Freeze status: NOT YET FORMALLY FROZEN** (see §6).
**Authority:** PXL Repository Owner, exercising the human structural authority reserved by [`PXL_PRINCIPLES.md`](../../00.%20Governance/PXL_PRINCIPLES.md) §21 and the authority order in [`AGENT_SYSTEM_PROMPT.md`](../../../../AI/AGENT_SYSTEM_PROMPT.md)
**Owner / Domain:** Inventory Accounting
**Decision Date:** 2026-07-26
**Applies To:** [ECC-01](ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md) and the authorisation of IA-5 ECC Hardening — Implementation Work Package 1
**Read When:** Establishing whether ECC-01 may be relied on as authority, or whether IA-5 ECC hardening implementation is authorised
**Do Not Read For:** The derivation itself (ECC-01), the frozen policy (ADR-C01), or engineering detail (the IA-5 implementation design)
**Implementation Status:** Governance record only. This document authorises a phase; it creates no schema, SQL, migration, function, test, or runtime change.
**Supersession Rule:** Only a later owner decision recorded in this document or in an explicit successor acceptance record may change it.

---

## 1. Decision Title

Formal Owner Acceptance of ECC-01 — Economic Costing Chronology Derivation
Specification.

## 2. Decision Date

2026-07-26.

## 3. Decision Authority

**PXL Repository Owner.** The repository defines no more precise accepted owner
designation; `PXL_PRINCIPLES.md` §21 reserves structural authority to the human
architect, and no freeze-authority register exists. No signature and no legal
name is recorded, because the repository holds none.

## 4. Specification Accepted

[`ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md`](ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md)
— Economic Costing Chronology Derivation Specification, as amended by
**Amendment A1** (2026-07-26), including validation rules V-31 … V-35.

## 5. Controlling Architecture

[ADR-C01 — Economic Event Chronology and Costing Order Authority](ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md)
(Frozen, 2026-07-26). ADR-C01 remains the controlling policy authority and is
unchanged by this acceptance. ECC-01 is subordinate to it: it derives what
ADR-C01 §6.3 froze, adds no ordering component, changes no rank, and reverses no
ADR decision.

## 6. Acceptance Evidence

[ECC-01 Final Architecture Acceptance Report](ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md)
(2026-07-26): Outcome **B — ACCEPTED WITH NON-BLOCKING CLARIFICATIONS**; ADR-C01
conformity 14/14; every worked example independently recomputed; ten defects
found, nine resolved in-document, one (ECC-A-11) referred to the owner.

## 7. Implementation-Design Evidence

[IA-5 ECC Hardening Implementation Design and Change Plan](../04.%20Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md)
(2026-07-26): Readiness **B — READY AFTER OWNER ACCEPTANCE OF ECC-01**; no design
gap remains; no accounting policy is left to the implementer; Work Package 1
specified in §24.

## 8. Status Before This Decision

| Subject | Status before |
| --- | --- |
| ECC-01 | `PROPOSED — RECOMMENDED FOR ACCEPTANCE`; not frozen |
| Formal owner acceptance | Outstanding — the only remaining gate |
| ECC-A-11 (PG-01 authority) | Open, owner-assigned |
| IA-5 ECC hardening implementation | Blocked; no work package authorised |
| IA-5 runtime state | Landed, dormant; permanent-foundation certification suspended (Outcome C, C-01 Critical) |
| IA-6 | Unauthorised |

## 9. Owner Decision

**ECC-01 is ACCEPTED — OWNER APPROVED**, together with its Amendment A1
clarifications, the conclusions of the Final Architecture Acceptance Report, and
the governance conditions recorded below.

ECC-01 is the authoritative Economic Costing Chronology derivation specification
for PXL. Any future IA-5 economic-costing-chronology hardening must conform to
it.

## 10. Scope of Acceptance

Accepted as authoritative:

1. The fourteen-component ordering tuple (E1–E10 primary, X1–X4 correction
   anchor) and its frozen component precedence.
2. The eight-stage derivation algorithm, the normalization contract (N-01…N-10),
   and the canonical-form and digest-identity governance.
3. The four proved properties — totality, schedule independence, replay
   repeatability, and prefix stability.
4. The thirty-five validation rules (V-01…V-35) and fifteen failure rules
   (F-01…F-15) as the conformance surface an implementation must satisfy.
5. The replay, cut-off, backdating, correction-anchoring, and version-governance
   contracts.
6. The prohibition on any database-assigned artefact — lock order, commit order,
   insert order, identity allocation, physical row order, worker order, or
   execution schedule — becoming accounting authority.
7. ECC-01 §14.1 and §15 as the conformance-gap and implementation-prerequisite
   list that IA-5 hardening must close.

## 11. Freeze Determination

**FREEZE STATUS: NOT YET FORMALLY FROZEN.**

The repository does not establish that owner acceptance is itself freeze
authority. The distinction as the repository actually uses it:

| Term | Repository meaning | Applied to ECC-01 |
| --- | --- | --- |
| **Accepted / Approved** | The owner adopts the document as authority and permits work to proceed under it | **Yes — this decision** |
| **Frozen** | A document status whose change requires the instrument named in its own Supersession Rule (ADR-C01: "only an approved successor ADR") | **No** — not exercised here |
| **Certified** | Executable evidence proves conforming implementation (`PXL_ENGINE_CERTIFICATION_STANDARD.md`, `PXL_MODULE_CERTIFICATION_STANDARD.md`) | **No** — no implementation exists |

ECC-01's own header states that "freeze requires recorded acceptance by the
authorized owner". Acceptance is therefore **necessary** for freeze; nothing in
the repository makes it **sufficient**, and the Final Architecture Acceptance
Report §25 treats acceptance and freeze as two owner acts. Freeze is not
exercised by this decision and remains available as a separate, later owner act.

This has limited practical consequence: ECC-01's Supersession Rule already
binds change control — only an approved successor ADR, or an approved ECC-02
that does not weaken ADR-C01, may change the derivation. Absence of a freeze
label does not license unilateral or AI-performed amendment.

## 12. Non-Blocking Clarifications Retained

Accepted with the following standing, per the Final Architecture Acceptance
Report §21–§22:

| Finding | Standing at acceptance |
| --- | --- |
| ECC-A-01 … ECC-A-04 | Resolved in-document (Amendment A1) — implementation-blocking had they remained open; closed by normative text |
| ECC-A-05 … ECC-A-10 | Resolved in-document (Amendment A1); V-31…V-35 carry them into the conformance surface |
| **ECC-A-11** | **Resolved by this decision** — see §13 |
| ECC-A-12 … ECC-A-14 | Resolved by documentation reconciliation performed at the acceptance gate |
| ECC-A-15 | Informational, retained. E10 is reachable only on the F-06 error path; an E10 composite must not introduce a discriminator absent from E1–E9. Owner: Event Source Registry design (WP-2) |
| ECC-A-16 | Informational, retained. Prefer a governed source sequence over the E5 identity fallback for every production-enabled source type; disclose fallback use as a convention, not business evidence. Owner: registry phase (WP-2) and any future production source-type enablement |
| ECC-A-17 | Informational, retained. ECC-01 §15 is prescriptive, not an authorisation to act; existing fencing is sufficient |

None of these is converted into new implementation policy by this acceptance.
No resolved architecture finding is reopened.

## 13. Open Governance Matter — PG-01 (ECC-A-11)

**Resolved by this decision as Outcome B: existing accepted documents
collectively embody the authority that "PG-01" names.**

No canonical PG-01 document exists, and none is created. The owner records that
every use of "PG-01" or "PG-01 precedence" in ADR-C01 (header, §16, §17(7)) and
ECC-01 (§15(13)) is to be read as the existing PXL governance chain, mapped
document-by-document in
[`PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md).

That map is **non-normative**: it introduces no governance policy, supersedes no
source, and does not amend ADR-C01, which is frozen and changeable only by a
successor ADR. ECC-A-11 is therefore closed for the purpose of citing "PG-01
precedence" as a resolvable rule, including ADR-C01 §17(7)'s gate-closing
condition.

## 14. Explicit Exclusions

This acceptance does **not**:

1. authorise IA-6, in whole or in any subphase;
2. authorise Work Packages 2 through 9 before WP-1 completes and is evidenced;
3. close the C-01 program stop, which requires executable conformance evidence
   under ADR-C01 §16 accepted by the reopened evidence gate;
4. restore the suspended IA-5 permanent-foundation certification claim;
5. certify ECC-01, IA-5, or the Inventory module or engine;
6. authorise any Posting Engine, Accounting Kernel, or six-sanctioned-persistence-function
   change;
7. authorise enabling a production inventory event source type;
8. authorise any hosted migration, hosted data change, or hosted claim;
9. authorise activation of runtime costing, replay, projection cut-over, or
   method state;
10. freeze ECC-01 (§11); or
11. amend ADR-C01.

## 15. Effect on Programme State

| Subject | Status after this decision |
| --- | --- |
| ADR-C01 | Frozen, controlling, unchanged |
| ECC-01 | **ACCEPTED — OWNER APPROVED**; not frozen |
| ECC-A-11 / PG-01 | Resolved (Outcome B, §13) |
| ECC-01 Final Architecture Acceptance Gate | Complete |
| IA-5 ECC Hardening Implementation Design | Complete and controlling; its one open gate is satisfied |
| IA-5 runtime state | Dormant; certification remains suspended |
| C-01 program stop | Open |
| IA-6 | Unauthorised |

## 16. Exact Next Authorised Phase

**IA-5 ECONOMIC COSTING CHRONOLOGY HARDENING — IMPLEMENTATION, WORK PACKAGE 1**,
exactly as specified in the implementation design §24 and §17 (M1), under the
stop conditions recorded there and in
[`ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md`](../04.%20Implementation/ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md).

WP-1 must be executed under a separate implementation instruction. No
implementation was performed when this acceptance was recorded.

## 17. Owner Acceptance Statement

> Acting as the PXL repository owner, I formally accept ECC-01 as the
> authoritative Economic Costing Chronology derivation specification. Future
> IA-5 Economic Costing Chronology hardening must conform to ADR-C01, ECC-01,
> its accepted amendments, the final architecture acceptance report, and the
> approved implementation design. This acceptance authorises progression to
> IA-5 Economic Costing Chronology Hardening — Implementation Work Package 1,
> subject to the prerequisites and scope defined in the implementation design.
> It does not authorise IA-6 or any deviation from the frozen Posting Engine or
> Accounting Kernel boundaries.

— PXL Repository Owner, 2026-07-26
