# AI Work Queue

Purpose: prioritized queue for useful continuation under `AI/AI_AUTONOMY_PLAYBOOK.md`.

Status: `Todo`, `In Progress`, `Blocked`, `Done`. Priority: P0 correctness/security/accounting/tax; P1 hardening/tests/context; P2 cleanup/docs.

## Queue

| ID | Priority | Status | Work Mode | Task | Source | Stop / Done Criteria |
| --- | --- | --- | --- | --- | --- | --- |
| AIQ-001 | P1 | Done | Autonomy | Create permanent agent system prompt. | AI cache/autonomy plans | Done 2026-07-02. |
| AIQ-002 | P1 | Done | Autonomy | Create volatile project state file. | AI cache plan, status docs | Done 2026-07-02; updated each meaningful session. |
| AIQ-003 | P1 | Done | Autonomy | Create concise handoff with exact next prompt. | AI cache/autonomy plans | Done 2026-07-02; updated each meaningful session. |
| AIQ-004 | P1 | Done | Context | Create `PXL_ARCHITECTURE_SUMMARY.md`. | Repository architecture docs | Done 2026-07-02. |
| AIQ-005 | P1 | Done | Context | Create generated `PXL_SCHEMA_SUMMARY.md`. | `supabase/migrations/` | Done 2026-07-02; regenerate after migrations. |
| AIQ-006 | P1 | Done | Accounting | Create `PXL_ACCOUNTING_RULES.md`. | Accounting docs/matrix | Done 2026-07-04. |
| AIQ-007 | P1 | Todo | VAT/EWT | Create `PXL_TAX_RULES_PH.md`. | Compliance docs/matrix/audit/test book | Concise PH tax summary exists and points to source docs. |
| AIQ-008 | P0 | In Progress | Audit | Continue highest-severity open audit findings until none remain. | Audit findings, test book, transaction matrix | Current finding fixed or genuinely blocked; tests/docs/hosted state updated. Session 63 closed DA-005 (normal-trigger orphan/cross-company JE rejection in test 026), DA-007 (genuine two-session posting race, new test 029 with dblink), and AUD-051 (document-code/numbering registry alignment + branch-scoped repair of eight callers, migration `20260712000002`, new test 030). Fresh replay/full suite is 527/527 across 29 owned files. Standing: 43 passed / 11 in progress / 18 open; two Criticals remain (DA-009 blocked on ATC/remittance; DA-019 now unblocked on numbering). Hosted synced through `20260712000001`; `20260712000002` push pending. |
| AIQ-009 | P1 | Todo | Testing | Add or improve tests for the next open accounting/tax/reporting risk. | Accounting test book | Test exists, runs where practical, and expected scenario is documented. |
| AIQ-010 | P2 | Done | Context | Add high-risk quick orientation to large state docs. | Matrix/audit findings | Done 2026-07-04. |
| AIQ-011 | P1 | Done | Autonomy | Move AI operating files under `AI/` and repair references. | User request | Done 2026-07-02. |
| AIQ-012 | P1 | Done | Autonomy | Finalize/version AIOS and documentation governance. | User request | Done 2026-07-02. |
| AIQ-013 | P1 | Done | Autonomy | Add findings index/readiness gate/schema generator/docs consistency/delegation controls. | User request | Done 2026-07-02. |
| AIQ-014 | P2 | Done | Context | Create product backlog and enforce defect-vs-enhancement separation. | User request, DEC-012 | Done 2026-07-03. |

## Agent Selection Rule

1. With no direct user task, pick the first unblocked task at the lowest priority number (P0 before P1 before P2).
2. For architecture/accounting/tax/posting/security/lifecycle/compliance, consult `AI/AI_DECISIONS.md` before editing.
3. Mark `Blocked` only under the playbook threshold; otherwise keep progressing safely.
4. End by updating this queue, `AI_STATE.md`, `AI_HANDOFF.md`, and the applicable project docs.

## Current Recommended Next Task

Push `20260712000002` to hosted (hold out 00004/00005), then continue AIQ-008 with Critical **PXL-DA-019** (CAS/BIR readiness end-to-end): immutable document numbering, void register + reason, immutable books reconciliation, ATP/permit metadata, and DAT/audit-package export provenance from posted ledgers. Build fresh on the now-registry-consistent numbering contract; do NOT adopt the broken held-out 00005. Alternatively advance **PXL-DA-009** dependencies (safe ATC date/version, PXL-AUD-041 remittance flow).

Do not redo AUD-002, AUD-006, AUD-014, AUD-051, DA-001, DA-002, DA-004, DA-005, DA-006, DA-007, or DA-008. The unowned ATC/CAS work (`20260710000004/00005` + test 027) is confirmed broken (breaks test 021; own test fails 15/30), stays untracked and off hosted per the user's 2026-07-11 decision, and must be held out of resets/tests/pushes/docs-gate runs until explicitly owned and fixed.
