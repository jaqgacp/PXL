# PXL Repository Instructions

This repository contains an AI Operating System.

Before beginning work, verify that AI/AIOS_VERSION.md exists. If multiple AI operating files indicate conflicting versions or incompatible structures, stop and notify the user before continuing.

Before performing ANY task, always read:

1. AI/AGENT_SYSTEM_PROMPT.md
2. AI/AI_STATE.md
3. AI/AI_HANDOFF.md
4. AI/AI_WORK_QUEUE.md
5. AI/AI_CONTEXT_INDEX.md

Read AI/AI_DECISIONS.md whenever the task may affect:

- Architecture
- Database
- Accounting
- Tax
- Security
- Posting Engine
- Transaction Lifecycle
- Compliance

Read AI/AI_CACHE_CONTEXT_PLAN.md only when working on AI workflow, prompt caching, or Claude API integration.

Treat these files as the repository source of truth.

Do not ask the user to restate the project unless the documents are missing or conflicting.

If no direct task is provided:

- Continue autonomously from AI/AI_WORK_QUEUE.md.
- Pick the highest-priority unblocked task.
- Update AI/AI_STATE.md, AI/AI_HANDOFF.md, and AI/AI_WORK_QUEUE.md before ending meaningful work.