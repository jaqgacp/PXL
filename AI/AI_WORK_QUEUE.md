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
| AIQ-008 | P0 | In Progress | Audit | Continue highest-severity open audit findings until none remain. | Audit findings, test book, transaction matrix | Current finding fixed or genuinely blocked; tests/docs/hosted state updated. Session 63 closed DA-005 (normal-trigger orphan/cross-company JE rejection in test 026) and DA-007 (genuine two-session posting race, new test 029 with dblink). Fresh replay/full suite is 516/516 across 28 owned files. Standing: 42 passed / 11 in progress / 19 open; two Criticals remain (DA-009/019), both with unresolved dependencies. Migration `20260712000001` hosted push is pending a Supabase access token. |
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

Continue AIQ-008: fix **PXL-AUD-051** completely (registry/series/DM-S alignment, demo-seed realignment, plus branch-scoped repair of eight broken two-argument numbering callers — never the held-out arbitrary-branch overload) to unblock DA-019. DA-009 remains dependent on safe ATC date/version and remittance-flow work (PXL-AUD-041).

Do not redo AUD-002, AUD-006, AUD-014, DA-001, DA-002, DA-004, DA-005, DA-006, DA-007, or DA-008. The unowned ATC/CAS work (`20260710000004/00005` + test 027) is confirmed broken (breaks test 021; own test fails 15/30), stays untracked and off hosted per the user's 2026-07-11 decision, and must be held out of resets/tests/pushes/docs-gate runs until explicitly owned and fixed.
