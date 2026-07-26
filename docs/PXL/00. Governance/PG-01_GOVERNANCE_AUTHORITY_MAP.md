# PG-01 Governance Authority Map

**Status:** Active — **non-normative** reference resolution. This map introduces no governance policy and supersedes none of its sources.
**Authority:** None of its own. Every rule below is owned by the source document cited beside it. Recorded under the owner decision in [`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`](../07.%20Inventory/03.%20Architecture/ECC-01_FORMAL_OWNER_ACCEPTANCE.md) §13.
**Owner / Domain:** Repository Governance
**Created:** 2026-07-26
**Applies To:** Every document that cites "PG-01" or "PG-01 precedence"
**Read When:** A document invokes PG-01 and the actual controlling rule must be located
**Do Not Read For:** New governance rules — there are none here. Read the cited source instead.

---

## 1. Why this document exists

`ADR-C01` cites "Architecture Authority under PG-01" in its header and invokes
PG-01 in §16 and §17(7); `ECC-01` §15(13) invokes "PG-01 precedence". **No
canonical PG-01 document has ever existed in this repository** — the string
appears only in those two specifications and in the reports that flagged the
gap. This was recorded as finding **ECC-A-11** by the
[ECC-01 Final Architecture Acceptance Report](../07.%20Inventory/03.%20Architecture/ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md)
§22.

The owner resolved ECC-A-11 as **Outcome B**: the governance PG-01 names is
already distributed across accepted documents, so those documents are mapped
here rather than replaced by a new governance specification. Fabricating a
frozen PG-01 specification would invent authority that was never approved;
deleting the references was impossible because ADR-C01 is frozen and only a
successor ADR may change it.

## 2. How to read a PG-01 citation

When a document says "under PG-01" or "under PG-01 precedence", read it as **the
chain of already-accepted PXL governance authority mapped in §3**. Nothing more
is implied, and no rule is created by the citation itself.

## 3. Authority map

| PG-01 principle invoked | Actual controlling source | What the source says |
| --- | --- | --- |
| Document precedence when sources disagree | [`AI/AGENT_SYSTEM_PROMPT.md`](../../../AI/AGENT_SYSTEM_PROMPT.md) §"Authority and Product Truth"; [`PXL_DOCUMENTATION_INDEX.md`](../PXL_DOCUMENTATION_INDEX.md) §1 | Seven-level order: executed database behaviour and current test output first; then Tier 1 standards; then the findings register; then `AI_STATE.md`; then the backlog; then Tier 2/3; historical reports last, as evidence only |
| Architecture authority over structural decisions | [`PXL_PRINCIPLES.md`](PXL_PRINCIPLES.md) §21, §22, §27 | AI is assisted, human-controlled; foundations are built once; no architectural drift — documented patterns override conflicting AI or developer suggestions |
| Freeze authority (who may declare a specification frozen) | `PXL_PRINCIPLES.md` §21 + `AGENT_SYSTEM_PROMPT.md` §"Findings and Documentation Governance" | Structural authority is the human architect's; new or status-changing documentation requires explicit approval. **No self-certification and no AI-performed freeze.** There is no freeze-authority register; this is the whole of the rule |
| Supersession / change control of a frozen document | The Supersession Rule in each document's own header | ADR-C01: only an approved successor ADR. ECC-01: only an approved successor ADR, or an approved ECC-02 that does not weaken ADR-C01 |
| Phase authority (what may be worked on next) | [`AI/AI_STATE.md`](../../../AI/AI_STATE.md) §"Recommended Next Task" + the explicit owner instruction for the session; for the reopened Inventory gate, `ADR-C01` §17 | A phase is authorised only when the owner records it; `AI_STATE.md` carries the current authorised phase and its stop conditions |
| Programme state (what is true now) | `AI/AI_STATE.md`; certification status in [`PXL_CERTIFICATION_MATRIX.md`](../13.%20Testing%20and%20Validation/PXL_CERTIFICATION_MATRIX.md) | One current-state source; the matrix is a dashboard, not an authority for correctness |
| Stop authority (what halts work) | [`PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md) — the only official defect register; gate outcomes such as the [IA-5/IA-6 Final Evidence Gate Report](../07.%20Inventory/03.%20Architecture/IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md) (C-01) | Defects and blockers live in one register; a gate outcome binds the phase it governs until a later gate resolves it |
| Certification authority | [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](../13.%20Testing%20and%20Validation/PXL_ENGINE_CERTIFICATION_STANDARD.md), [`PXL_MODULE_CERTIFICATION_STANDARD.md`](../13.%20Testing%20and%20Validation/PXL_MODULE_CERTIFICATION_STANDARD.md) | Certification requires executable evidence against defined gates; it is never a documentation act |
| One source of truth per subject | `PXL_PRINCIPLES.md` §13; `AGENT_SYSTEM_PROMPT.md` §"Findings and Documentation Governance" | No competing register, handoff, roadmap, or status file |
| "Documentation and implementation evidence agree under PG-01 precedence" (ADR-C01 §17(7)) | `AGENT_SYSTEM_PROMPT.md` authority order, level 1 versus levels 2–6 | Executed database behaviour outranks prose. Divergent documentation is a **conformance defect to be corrected**, never a licence to weaken the executed rule; equally, prose may not be used to claim behaviour that evidence does not show |

## 4. What this map does not do

1. It creates no rule, obligation, precedence, or permission.
2. It does not amend `ADR-C01`, which is frozen; the PG-01 strings in ADR-C01
   stand as written and are interpreted, not edited.
3. It does not make itself an authority: if this map and a cited source ever
   disagree, **the source wins** and this map is the defect.
4. It does not close the C-01 program stop, certify anything, or authorise any
   phase.

## 5. If a canonical PG-01 is ever written

A future owner may create a canonical PG-01 governance specification. If that
happens, it supersedes this map, which must then be reduced to a pointer or
retired. Until then, "PG-01" has exactly the meaning recorded in §3.
