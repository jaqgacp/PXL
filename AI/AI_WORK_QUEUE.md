# AI Work Queue

Purpose: prioritized queue that lets Claude, Fable, Codex, or future AI agents continue useful work without waiting for repeated user prompts.

The agent should choose the highest-priority unblocked task that fits the current session and autonomy rules in `AI/AI_AUTONOMY_PLAYBOOK.md`.

## Status Values

- `Todo`
- `In Progress`
- `Blocked`
- `Done`

## Priority Values

- `P0` Critical correctness, build/test failure, security, accounting, tax, or data integrity issue.
- `P1` Production-hardening, audit finding, test coverage, or continuity improvement.
- `P2` Useful cleanup, summary, UI polish, or documentation improvement.

## Queue

| ID | Priority | Status | Work Mode | Task | Source | Stop / Done Criteria |
| --- | --- | --- | --- | --- | --- | --- |
| AIQ-001 | P1 | Done | Autonomy | Create `AI/AGENT_SYSTEM_PROMPT.md` with bounded-autonomy rules, PXL role, no-random-feature rule, reading order, and end-of-session update protocol. | `AI/AI_CACHE_CONTEXT_PLAN.md`, `AI/AI_AUTONOMY_PLAYBOOK.md` | Done 2026-07-02. |
| AIQ-002 | P1 | Done | Autonomy | Create `AI/AI_STATE.md` with current project status, active task, known issues, last changed files, and next step. | `AI/AI_CACHE_CONTEXT_PLAN.md`, `docs/PXL/STATUS.md` | Done 2026-07-02. |
| AIQ-003 | P1 | Done | Autonomy | Create `AI/AI_HANDOFF.md` with concise session handoff and exact next prompt. | `AI/AI_CACHE_CONTEXT_PLAN.md`, `AI/AI_AUTONOMY_PLAYBOOK.md` | Done 2026-07-02. |
| AIQ-004 | P1 | Done | Context | Create `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`. | `README.md`, `docs/PXL/PXL_PRINCIPLES.md`, `docs/PXL/STATUS.md`, `package.json` | Done 2026-07-02. Concise stable summary exists; `AI/AI_CONTEXT_INDEX.md` links now resolve. |
| AIQ-005 | P1 | Done | Context | Create `docs/PXL/PXL_SCHEMA_SUMMARY.md`. | `supabase/migrations/` | Done 2026-07-02 as a GENERATED doc: `scripts/gen_schema_summary.sh` maps all 127 functions, 18 views, 145 tables, and 132 triggers to their latest defining migration. Regenerate after adding migrations. |
| AIQ-006 | P1 | Todo | Accounting | Create `docs/PXL/PXL_ACCOUNTING_RULES.md`. | `README.md`, `docs/PXL/PXL_PRINCIPLES.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, accounting docs | Concise accounting rules summary exists and points to source docs. |
| AIQ-007 | P1 | Todo | VAT/EWT | Create `docs/PXL/PXL_TAX_RULES_PH.md`. | `docs/PXL/10. Compliance/`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, audit/test docs | Concise Philippine tax rules summary exists and points to source docs. |
| AIQ-008 | P0 | In Progress | Audit | Continue the highest-severity open audit finding from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Repeat until no open findings remain. | Audit findings, test book, transaction matrix | Finding is fixed or marked blocked with evidence; tests/docs updated. Sessions 27 (PXL-AUD-026), 28 (PXL-AUD-027), 30 (PXL-DA-003/PXL-AUD-004 per DEC-009), 31 (PXL-DA-012 per DEC-010), 32 (VAT ledger completeness; PXL-AUD-028 cash sale fix), 33 (ledger-backed VAT review/2550 source views), 34 (VAT return report snapshots), 35 (Form 2307 issued snapshots), 36 (SLSP/RELIEF export snapshots), 37 (SAWT/QAP export snapshots + WHT/GL reconciliation), 38 (CAS DAT export snapshots, server-attested cas_export_log), 39 (all seven BIR books export snapshots), 40 (snapshot reader/drilldown UI — PXL-DA-015 closed Retested Passed; new Medium PXL-AUD-029 logged), 41 (JE line dimensions per DEC-011 — PXL-DA-017 closed Retested Passed), and 42 (typed Supabase client + generated schema types; PXL-AUD-029/030 closed Retested Passed; architecture summary corrected) landed. |
| AIQ-009 | P1 | Todo | Testing | Add or improve tests for the next open accounting/tax/reporting risk. | `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`, `supabase/tests/` | Test exists, runs where practical, and expected scenario is documented. |
| AIQ-010 | P2 | Todo | Context | Reduce token usage by adding high-risk summaries at the top of large state docs. | `docs/PXL/PXL_TRANSACTION_MATRIX.md`, audit findings | Summary helps agents orient without replacing the full source of truth. |
| AIQ-011 | P1 | Done | Autonomy | Move AI operating files into `AI/`, update all internal references to `AI/`-prefixed paths, update `.claude/CLAUDE.md`, and add `AI/README.md`. | User request | Done 2026-07-02. Repository-wide scan shows no remaining references to the old root-level paths. |
| AIQ-012 | P1 | Done | Autonomy | Finalize AIOS 1.0.0: add `AI/AIOS_VERSION.md` and `AI/AI_DOCUMENTATION_RULES.md`, add version verification and Documentation Philosophy, and remove duplicated governance/protocol content. | User request | Done 2026-07-02. AI Operating System is versioned, governed, and internally consistent. |
| AIQ-013 | P1 | Done | Autonomy | AIOS 1.1.0 tuning: Findings Status Index + Production Readiness Gate in the audit doc, generated schema summary (closes AIQ-005), docs-consistency CI gate, external-action evidence rule, trivial-task/audit reading shortcuts, Decisions Needed From User section. | User request | Done 2026-07-02. `scripts/check_docs_consistency.sh` green; CI enforces index/test-book sync. |
| AIQ-014 | P2 | Done | Context | Create `docs/PXL/PXL_PRODUCT_BACKLOG.md` and institutionalize DEC-012: audit findings = defects, backlog = enhancements, lightweight architectural review of every touched module. Standing discipline lives in `AI/AGENT_SYSTEM_PROMPT.md`. | User request 2026-07-03 | Done 2026-07-03. Backlog seeded (Standard Transaction Experience + cross-module/Sales/Purchasing/Reports entries); ongoing upkeep is per-session discipline, not a queue item. |

## Agent Selection Rule

When no direct user task is provided:

1. Pick the first `Todo` task with the lowest priority number.
2. Prefer `P0`, then `P1`, then `P2`.
3. If a task is blocked, mark it `Blocked` with the reason and pick the next task.
4. If the task affects architecture, accounting, tax, posting, schema, security, lifecycle, or compliance, consult `AI/AI_DECISIONS.md` before editing.
5. At the end, update this queue row and set the next recommended queue item in `AI/AI_HANDOFF.md`.

## Current Recommended Next Task

AIQ-008 (continue): PXL-DA-015, PXL-DA-017, PXL-AUD-029, and PXL-AUD-030 are closed — do not redo them. Next: PXL-DA-011 status-aware immutability across all transactional tables, or PXL-DA-001 server-side GL preview RPC. Regenerate `src/lib/database.types.ts` (`npm run gen:types`) after every migration. Summary docs AIQ-006–007 follow when audit work pauses.
