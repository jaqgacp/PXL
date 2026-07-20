# PXL Agent System Prompt

**Status:** Stable AI operating rules
**Authority:** Tier 0 AI Fast-Start
**Last Verified:** 2026-07-17
**Applies To:** Every Codex, Claude, or other AI coding session in PXL
**Read When:** At the start of every fresh session
**Do Not Read For:** Product requirements; follow the task-specific governing documents instead

PXL is a Philippine-compliance-first, accounting-first ERP built with React, TypeScript, Supabase, and PostgreSQL. Correct database truth, balanced accounting, tax compliance, tenant isolation, lifecycle control, and immutable audit evidence take precedence over UI convenience. This file supplies stable working rules. Volatile status belongs only in `AI/AI_STATE.md`.

## Mandatory Fresh-Session Startup Protocol

1. Read `AI/AGENT_SYSTEM_PROMPT.md`.
2. Read `AI/AI_STATE.md`.
3. Confirm the recommended next finding or the human-approved scope.
4. Open only the referenced finding, directly affected code, directly relevant tests, and directly governing specifications.
5. Do not scan all Markdown files by default.
6. Do not read historical reports unless the task needs historical evidence.
7. Do not read all BIR files unless the task is specifically BIR or compliance related.
8. Do not read all Sales Invoice files unless the task is Sales Invoice related.
9. Report when `AI_STATE.md` is stale, contradictory, or incomplete.
10. Do not silently compensate for stale context by reading the entire repository.

The normal startup set is this file, `AI/AI_STATE.md`, the one active finding it names, and the few files and tests listed for that task. `docs/PXL/PXL_DOCUMENTATION_INDEX.md` is a navigation map for humans and exceptional discovery, not mandatory startup reading.

## Document Expansion Rule

Open another document only when at least one condition is true:

- `AI/AI_STATE.md` lists it for the current task.
- The active finding directly references it.
- The affected code references or implements it.
- A governing rule cannot otherwise be resolved.
- Validation requires it.

Do not open a document merely because its filename appears related. Prefer targeted filename and text searches over broad repository scans. Archived and trash-review materials are non-authoritative and should be ignored unless historical provenance or cleanup review is the task.

## Scope and Execution Contract

Work on one approved finding or one tightly bounded scope at a time. Before implementation, state:

- the finding or task selected;
- the exact scope and explicit exclusions;
- the files to inspect;
- the expected changes; and
- the validation plan.

Avoid unrelated refactoring, opportunistic schema changes, broad formatting, and speculative cleanup. Existing dirty-worktree changes belong to the user unless proven otherwise; preserve them and report overlap. Never reset or seed Supabase, push hosted migrations, rotate credentials, commit, or push unless the current instruction explicitly authorizes it.

Read evidence before editing. Never assume an approved future UX, planned feature, migration draft, or generated report describes implemented behavior. A page that renders is not proof that posting, tax, GL, inventory, permissions, reports, and lifecycle behavior are correct. Do not claim success without running the validation required by the finding and reporting the actual result.

## Authority and Product Truth

Use this authority order when sources disagree:

1. Executed database behavior, hosted validation, and current test output.
2. Tier 1 governing standards and approved transaction/accounting/tax definitions.
3. `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` for verified defects and required fixes.
4. `AI/AI_STATE.md` for current work selection and concise operational handoff.
5. `docs/PXL/00. Governance/PXL_PRODUCT_BACKLOG.md` for approved implementation work and enhancements.
6. Tier 2 domain specifications and Tier 3 operational plans.
7. Historical reports, generated summaries, and archived notes as evidence only.

When database truth, accounting rules, tax rules, transaction rules, security rules, or audit rules conflict with UI convenience, the governed rule wins. Stop and report when authority cannot be resolved safely. Never describe PXL as production-ready while any Critical or High finding is active.

## Findings and Documentation Governance

`docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` is the only authoritative register for official defects, audit issues, blockers, and required remediation. Do not create module-specific findings lists, phase defect lists, remediation trackers, or competing registers. Other documents may reference finding IDs but must not copy full finding content.

Maintain one source of truth per subject:

- Current work and next-agent scope: `AI/AI_STATE.md`.
- Official defects: the central findings register.
- Long-term implementation and enhancements: `docs/PXL/00. Governance/PXL_PRODUCT_BACKLOG.md`.
- Product rules: the appropriate governing standard.
- Historical evidence: `docs/PXL/archive/`.
- Suspected obsolete or duplicate material: `docs/PXL/trash-review/`.

Do not create a Markdown file when an existing authoritative file should be updated. Search `PXL_DOCUMENTATION_INDEX.md` before proposing new documentation. A new document requires explicit approval plus a defined authority, purpose, owner domain, read condition, and relationship to existing documents. Never create new status, findings, backlog, roadmap, handoff, context, session, or architecture files without explicit approval. AI-generated transcripts do not belong in active documentation.

Phase reports are historical evidence, not current status sources. Specifications change only when implementation or verified evidence requires the change. Keep historical claims clearly labeled and linked to the current findings register and AI state.

## Domain Boundaries

For BIR or compliance work, start with `docs/PXL/10. Compliance/README.md`, then open only the one or two routed domain documents. For Sales Invoice work, use the finding’s file map and `docs/PXL/05. Sales/README.md`; distinguish UI conformance from source-backed Sales Invoice business completeness. Missing backend sources, persistence, schema, seed fixtures, and future enhancements must remain explicit.

The Sales Invoice rollout order is: resolve backend/security blockers; complete data/workflow prerequisites; implement Form UX; validate save, approval, posting, tax, GL, inventory, and relationships; implement View UX; then roll the standard to other transactions.

## Validation and Handoff

Use focused validation first, then broader checks in proportion to risk. Documentation work should normally run `npm run docs:check` and `git diff --check`. Product changes must run every focused command named in the active finding before broader build, lint, database, or UI lanes. Never convert a red product assertion into a documentation-only exception.

At the end of every meaningful task:

1. Update the central finding only if verified evidence or status changed.
2. Update governing specifications only if behavior or verified scope changed.
3. Replace, rather than append history to, the relevant parts of `AI/AI_STATE.md`.
4. Run `npm run docs:ai-state-check`.
5. Give a concise handoff: outcome, files changed, tests run/results, blockers, and one next task.

Do not duplicate full findings in the handoff. If the task is incomplete, state exactly what remains. If validation was not run, say so. If a human or external action is required, keep the finding active and name the dependency.
