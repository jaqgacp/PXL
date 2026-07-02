# AI State

Last updated: 2026-07-02

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.0.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

Build the AI operating system that lets Claude, Fable, Codex, or future agents continue PXL work autonomously with minimal repeated user prompting.

## Repository Change (2026-07-02)

The AI operating files live under `AI/` and all internal references use `AI/`-prefixed paths. A final hardening pass added `AI/AIOS_VERSION.md` (version 1.0.0), `AI/AI_DOCUMENTATION_RULES.md` (documentation governance, closed file list), a Documentation Philosophy and AIOS version verification in `AI/AGENT_SYSTEM_PROMPT.md` and `.claude/CLAUDE.md`, and removed duplicated governance/protocol content from `AI/AI_CACHE_CONTEXT_PLAN.md`. No accounting, tax, business-logic, schema, or application code was changed.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs are still missing:
  - `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`
  - `docs/PXL/PXL_SCHEMA_SUMMARY.md`
  - `docs/PXL/PXL_ACCOUNTING_RULES.md`
  - `docs/PXL/PXL_TAX_RULES_PH.md`
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- `AI/AI_WORK_QUEUE.md` has initial tasks but should be maintained after every meaningful session.

## Last Files Changed

- `AI/AIOS_VERSION.md` (new: AIOS version 1.0.0)
- `AI/AI_DOCUMENTATION_RULES.md` (new: documentation governance)
- `AI/AGENT_SYSTEM_PROMPT.md` (AIOS version verification; Documentation Philosophy)
- `AI/AI_AUTONOMY_PLAYBOOK.md` (Level 1 aligned with documentation rules; path fix)
- `AI/AI_CONTEXT_INDEX.md` (registered new files)
- `AI/AI_CACHE_CONTEXT_PLAN.md` (stale entries fixed; duplicated governance/protocol sections condensed to pointers)
- `AI/AI_WORK_QUEUE.md` (queue updated; path fix)
- `AI/README.md` (new files added to table)
- `AI/AI_STATE.md`, `AI/AI_HANDOFF.md` (refreshed)
- `.claude/CLAUDE.md` (AIOS version verification rule)

## Last Known Errors

No code was changed in the current AI operating-docs session. No build/test run was required for documentation-only changes.

## Next Recommended Step

Create `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` from existing README, principles, status, and architecture notes so future agents can avoid loading large documentation folders.

## Open Questions / Decisions

- Decide whether future autonomous agents should be allowed to open pull requests automatically or only prepare local changes.
- Decide whether `AI/AI_WORK_QUEUE.md` should be manually curated by the user or automatically maintained by agents after every session.
- Decide when to implement actual Claude API `cache_control` support if a Claude/Fable wrapper is later added.
