# AI Documentation Rules

**Status:** Historical Snapshot — superseded by `AI/AGENT_SYSTEM_PROMPT.md` and `docs/PXL/PXL_DOCUMENTATION_INDEX.md`
**Not Current Source of Truth:** Do not use for fresh-session startup.

Permanent governance for the AI Operating System. The goal is a compact, stable, low-maintenance set of files — not more documentation.

## Allowed AI Operating Files

This is a closed list. Unless explicitly requested by the user, do NOT create new `AI*.md` files or any other file in `AI/`. If new AI documentation appears necessary, first determine which existing file below owns that information and update it instead.

| File | Responsibility (one job) | Allowed to grow? | Update when | Do NOT update for |
| --- | --- | --- | --- | --- |
| `AGENT_SYSTEM_PROMPT.md` | Permanent agent role, rules, session protocols. | No | Only for permanent AI behavior changes. | Current status, tasks, or module detail. |
| `AI_STATE.md` | Current project state, active task, known issues, next step. | No — replace sections, do not append history. | Every meaningful session. | Permanent decisions or architecture. |
| `AI_HANDOFF.md` | Short handoff for the next session, exact next prompt. | No — replace, keep brief. | Every meaningful session. | Long history; it is not a second state file. |
| `AI_WORK_QUEUE.md` | Prioritized task backlog. | Bounded — prune or compress old `Done` rows when the table gets long. | When task status or priority changes. | Implementation notes or permanent rules. |
| `AI_DECISIONS.md` | Permanent architectural/business decisions and why. | Yes — append-only, curated. | Only for permanent architectural or business decisions (new, changed, or deprecated). | Progress, bugs, workarounds, session notes. |
| `AI_CONTEXT_INDEX.md` | Repository navigation map and work modes. | Only with repository structure. | Only when repository structure or work modes change. | Rules or content that belongs in the indexed docs. |
| `AI_AUTONOMY_PLAYBOOK.md` | Bounded-autonomy rules, authority levels, stop conditions. | No | Only when autonomy rules change. | Task backlog or current status. |
| `AI_CACHE_CONTEXT_PLAN.md` | Prompt-caching and context strategy. | No | Only when cache strategy changes. | Session protocols or file governance (owned elsewhere). |
| `AIOS_VERSION.md` | AIOS version, compatibility, high-level changelog. | Changelog only, high level. | Only when the AIOS structure or rules change. | Session-level or task-level changes. |
| `AI_DOCUMENTATION_RULES.md` | This file: documentation governance. | No | Only when governance itself changes. | Anything else. |
| `README.md` | Orientation: what the folder is, purpose of each file. | No | Only when the file set changes. | State, rules detail, or protocols. |

## Size Philosophy

There are no hard byte limits, but every file must stay small enough to be loaded in full at session start without crowding out task context.

- Volatile files (`AI_STATE.md`, `AI_HANDOFF.md`) are rewritten, never accumulated. Old session narrative is deleted, not archived.
- `AI_WORK_QUEUE.md` keeps `Done` rows only as long as they are useful evidence; compress or remove old rows when the table grows.
- `AI_DECISIONS.md` entries follow the template in that file and stay concise; link to detailed docs instead of duplicating them.
- Each file has exactly one job. If content fits two files, put it in the file listed above and link from the other.

## General Rules

- Implementation always has higher priority than documentation.
- Prefer updating existing documents over creating new ones.
- Project knowledge (architecture, accounting, tax, schema) belongs in `docs/PXL/`, not in `AI/`. The `AI/` folder holds only operating instructions and continuity state.
- If two AI operating files conflict, stop and notify the user; do not silently pick one.
