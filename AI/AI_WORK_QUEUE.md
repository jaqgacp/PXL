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
| AIQ-008 | P0 | In Progress | Audit | Continue highest-severity open audit findings until none remain. | Audit findings, test book, transaction matrix | Current finding fixed or genuinely blocked; tests/docs/hosted state updated. Session 59 closed AUD-002, AUD-006, DA-001, and DA-006; advanced DA-002/004/005/007 and AUD-049. Standing 35 passed / 17 in progress / 18 open; five Criticals remain (DA-002/004/008/009/019). |
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

Continue AIQ-008 with **PXL-DA-002**: extend the session-59 accounting trace contract into financial statement, subledger, VAT/WHT, 2307/QAP, and report-snapshot rows, with route tests. Alternative P0: **PXL-DA-004** posting-engine completion (writer migration, tax/reversal primitives, physical source validation, locks/concurrency). DA-008/009/019 remain parallel Critical lanes.

Do not redo AUD-002, AUD-006, DA-001, or DA-006. Run `npm run gen:types` after every migration. Exclude unrelated local migrations 00004/00005 and test 027 unless explicitly taking ownership of that work.
