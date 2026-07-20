# AI Autonomy Playbook

**Status:** Historical Snapshot — superseded by `AI/AGENT_SYSTEM_PROMPT.md`
**Not Current Source of Truth:** Do not use for fresh-session startup.

Purpose: make Claude, Fable, Codex, or any future AI agent able to keep improving PXL with fewer user prompts, while staying inside accounting, compliance, and architectural guardrails.

Autonomy in PXL means bounded autonomy. The agent should keep working from documented priorities, but it must not invent product direction, weaken controls, or make irreversible architectural changes without evidence.

## Core Rule

Do not wait for the user to restate the project.

At the start of a session, read the AI operating files, choose the next safe task from `AI/AI_WORK_QUEUE.md`, execute it, verify it, and update the state/handoff files.

## Start Loop

1. Read `AI/AGENT_SYSTEM_PROMPT.md`.
2. Read `AI/AI_STATE.md`.
3. Read `AI/AI_HANDOFF.md`.
4. Read `AI/AI_WORK_QUEUE.md`.
5. Read `AI/AI_CONTEXT_INDEX.md`.
6. Read `AI/AI_DECISIONS.md` if architecture, accounting, tax, security, schema, lifecycle, or module scope may be affected.
7. Determine the repository work mode.
8. Load only the context for that mode.
9. Pick the highest-priority unblocked task from `AI/AI_WORK_QUEUE.md`.
10. Work until the task is complete, blocked, or unsafe to continue without user input.

## End Loop

Before stopping:

1. Update `AI/AI_STATE.md`.
2. Update `AI/AI_HANDOFF.md`.
3. Update `AI/AI_WORK_QUEUE.md`.
4. Update `AI/AI_DECISIONS.md` only if a permanent architectural or business decision was made.
5. Update `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md` when transaction behavior, posting, tax, reports, lifecycle, audit trail, or tests changed.
6. Update audit/test docs when a finding or test expectation changed, including the Findings Status Index; run `scripts/check_docs_consistency.sh`.
7. If a migration was added: regenerate `docs/PXL/01. Architecture/PXL_SCHEMA_SUMMARY.md` (`scripts/gen_schema_summary.sh`), and push to hosted Supabase when credentials allow (`supabase db push --linked`, verify with `supabase migration list --linked`); otherwise record the pending push in `AI/AI_STATE.md`.
8. Record commands run, verification status, known errors, and exact next task.

## External-Action Evidence Rule

Never record a remote or external action (hosted migration push, CI result, deployment, filing) as done without command output as evidence from the session that claims it. If it cannot be verified in-session (missing credentials, pending run), record it as PENDING with what is needed to verify. A false "done" claim is treated as a Critical process defect (see PXL-AUD-026's false "pushed to remote" history).

## Autonomy Levels

### Level 1 - Documentation and Planning

Agent may proceed without asking:

- Improve existing AI operating docs within the limits in `AI/AI_DOCUMENTATION_RULES.md`. Do not create new AI files without an explicit user request.
- Update state, handoff, context index, work queue, or cache plan.
- Draft concise summaries from existing docs.
- Add links and routing notes that reduce token usage.

### Level 2 - Safe Code Fixes

Agent may proceed without asking when the work is clearly documented:

- Fix TypeScript/build/lint errors.
- Fix small UI bugs that follow existing patterns.
- Add focused tests for existing behavior.
- Update docs for behavior already implemented.
- Refactor narrowly to reduce duplication without changing product behavior.

### Level 3 - Accounting, Tax, Posting, Schema, or Security Work

Agent may proceed only when the task is documented in `AI/AI_WORK_QUEUE.md`, `AI/AI_STATE.md`, `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, or a direct user request.

Required before editing:

- Read `AI/AI_DECISIONS.md`.
- Read the relevant work-mode docs from `AI/AI_CONTEXT_INDEX.md`.
- Identify affected tables, RPCs, pages, tests, and transaction matrix rows.
- State the intended narrow scope in the handoff/state when done.

### Level 4 - Architecture or Business-Policy Decisions (Delegated per DEC-008)

The user has granted a standing delegation (DEC-008): when a task requires an architectural or business-policy decision, the agent decides using the standard-accounting-practice, Philippine-compliance-conservative default, records the decision as a DEC entry in `AI/AI_DECISIONS.md`, and proceeds. Do not park work as "needs user decision".

Already decided (do not re-ask): role/action matrix (DEC-009), approval segregation of duties (DEC-010), branch as reporting dimension (DEC-011), direct commits to `main` with CI as gate (DEC-008).

The delegation never covers:

- Weakening or removing accounting, tax, audit-trail, or security controls.
- Destructive or irreversible operations on real user data.
- Spending money or external legal/compliance actions (e.g., actual BIR filings).
- Recording an external action as done without evidence (see External-Action Evidence Rule).

## What the Agent Should Do Without Asking

- Continue from the documented next step.
- Choose the highest-priority unblocked queue item.
- Run relevant build/lint/test commands after code changes.
- Add or update focused tests when changing accounting/tax/reporting behavior.
- Keep docs synchronized with behavior changes.
- Leave the next session a clean next prompt.

## When the Agent Must Ask

Ask only when:

- The documents conflict and the conflict cannot be resolved from evidence in the repository.
- The task requires secrets or credentials the agent does not hold (record the action as PENDING and continue with other work).
- The work would weaken accounting/tax/security controls, delete user data, or perform destructive/irreversible operations.
- The action spends money or has external legal effect (e.g., filing with the BIR).

Everything else — including business-policy choices — is delegated per DEC-008: decide, record the DEC entry, proceed.

## Stop Conditions

Stop and update handoff when:

- The selected task is complete and verified.
- Verification is blocked by missing tools, credentials, or environment.
- Continuing would require something outside the DEC-008 delegation (control weakening, destructive action, money, external legal effect).
- The work queue has no unblocked next task.

## Default Task Selection

Choose work in this order:

1. Critical audit or correctness issue with a documented finding.
2. Test failure, build failure, or migration replay failure.
3. Accounting/tax/reporting production-hardening task.
4. Missing AI operating docs or summaries that reduce future token usage.
5. UI polish or module-specific improvements already documented.

Do not choose random new features.

## Verification Standard

For documentation-only changes:

- Check links and required sections.
- Update affected AI operating files.

For frontend changes:

- Run build/lint when practical.
- Verify affected page/component behavior where possible.

For database/accounting/tax changes:

- Run or add relevant pgTAP tests when possible.
- Run migration replay when practical.
- Update transaction matrix, audit findings, and test book if behavior changed.

## Minimal User Prompt Goal

The user should be able to say:

```text
Continue autonomously from the AI operating files.
```

The agent should then:

- read state/handoff/work queue,
- pick the next task,
- execute,
- verify,
- update docs,
- leave the exact next task.
