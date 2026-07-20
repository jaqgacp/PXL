# AI Operating Files

**Status:** TRASH-REVIEW - obsolete AI operating-system material
**Authority:** Non-authoritative; superseded by AI/AGENT_SYSTEM_PROMPT.md and AI/AI_STATE.md
**Last Reviewed:** 2026-07-18 documentation cleanup
**Read When:** Human deletion review only
**Do Not Read For:** AI startup or current work selection

This folder contains the AI operating system for PXL: the documents that let Claude, Fable, Codex, or any future AI agent continue work on the repository autonomously, with minimal repeated prompting from the user.

Read these files in the order defined in `AI/AGENT_SYSTEM_PROMPT.md` before starting any task. Treat them as the repository source of truth for AI sessions.

## Files

| File | Purpose |
| --- | --- |
| `AGENT_SYSTEM_PROMPT.md` | Permanent role, scope, rules, and behavior for every AI agent working on PXL. The most stable document; read first in every session. |
| `AI_STATE.md` | Current project status, active task, known issues, last changed files, last known errors, and the next recommended step. Updated after every meaningful session. |
| `AI_HANDOFF.md` | Concise session handoff: what was done, what changed, what remains, blockers, and the exact next recommended task and prompt. Updated after every meaningful session. |
| `AI_WORK_QUEUE.md` | Prioritized autonomous backlog. Lets agents choose the highest-priority unblocked task without waiting for user prompts. |
| `AI_CONTEXT_INDEX.md` | Navigation map for the repository. Organizes source-of-truth documents by work area and mode so agents load the smallest useful context. Read before searching the repository. |
| `AI_DECISIONS.md` | Permanent architectural and business decision memory. Consult before proposing or making architecture, accounting, tax, schema, security, lifecycle, or module-scope changes. |
| `AI_AUTONOMY_PLAYBOOK.md` | Bounded-autonomy rules: authority levels, session start/end loop, stop conditions, and verification rules for autonomous work. |
| `AI_CACHE_CONTEXT_PLAN.md` | Prompt-caching and context strategy for Claude/Fable sessions. Read only when working on AI workflow, prompt caching, or Claude API integration. |
| `AIOS_VERSION.md` | Current AI Operating System version, compatible agents, and high-level changelog. Agents verify this file exists at session start. |
| `AI_DOCUMENTATION_RULES.md` | Documentation governance: the closed list of allowed AI files, growth rules, and update cadence. No new `AI*.md` files without explicit user request. |

## Conventions

- Reference these files from anywhere in the repository with the `AI/` prefix (for example `AI/AI_STATE.md`).
- Before ending meaningful work, update `AI_STATE.md`, `AI_HANDOFF.md`, and `AI_WORK_QUEUE.md`.
- Record permanent architectural or business decisions in `AI_DECISIONS.md` only; never in `AI_STATE.md`.
