# AI Handoff

Last updated: 2026-07-04

## What Was Done

Session 41 closed PXL-DA-017 (dimension propagation per DEC-011). Migration `20260704000001_je_line_dimensions.sql`:

- `journal_entry_lines` gained `branch_id` / `department_id` / `cost_center_id` (FK'd, partially indexed).
- `trg_je_dimensions_guard` (journal_entries): header branch must belong to the JE company.
- `trg_je_line_dimensions_guard` (journal_entry_lines): line company must equal the JE company (new integrity check); lines inherit the header branch when none is set — this single trigger covers all 34 JE writers, current and future, without per-writer changes; every line dimension is company-validated.
- Backfill: existing lines inherited their header branch (guarded against hypothetical cross-company legacy branches).
- `vw_general_ledger.branch_id` is now line-accurate (`COALESCE(line, header)` — same name/type/position, so Branch P&L and every other consumer upgraded transparently); line `department_id`/`cost_center_id` appended at the end.
- `fn_post_manual_je` accepts optional per-line `branch_id`/`department_id`/`cost_center_id` inside `p_lines`; `fn_reverse_je` copies line dimensions onto reversal lines.

Session 40 (same day) closed PXL-DA-015 with the snapshot reader UI (`/report-snapshots`), and the user-supplied token synced hosted Supabase through `20260703000009`.

## What Changed

- Findings standing: 21 Retested Passed / 14 In Progress / 14 Open (49 findings); 10 Criticals remain.
- New scenario JE-DIMS-001 (`supabase/tests/019_je_line_dimensions_test.sql`, 14 assertions); `supabase/tests/` now 19 files / 299 assertions.
- Transaction matrix Manual JE row and test book updated; schema summary regenerated.

## What Remains

- Next Criticals: PXL-DA-001 server-side GL preview RPC (In Progress) or PXL-DA-011 status-aware immutability on all transactional header/line tables (Open).
- PXL-AUD-029 AppShell feature-gating query fix (small, Medium).
- Document-line department/cost-center capture is a backlog enhancement (documents carry only branch today).
- `fn_bt_reverse_je` and doc-void counter-JEs inherit header branch but do not copy line dept/cc — adopt the `fn_reverse_je` pattern when a capture path writes dept/cc on those JEs.
- Stock transfer JEs stay branch-unattributed by design (they span warehouses).
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay through `20260704000001` + `npm test` 299/299 across 19 files (reset the local DB first — leftover seeds collide with test UUIDs), build/lint/docs-consistency green. Hosted: synced through `20260703000009`; push `20260704000001` after landing (`SUPABASE_ACCESS_TOKEN` + `supabase db push --linked --yes`; the CLI's pg-delta CA-cert errors are noise — verify with `supabase migration list --linked`).

## Exact Next Recommended Task

Continue `AIQ-008` with PXL-DA-011: status-aware immutability on every transactional header/line table (extend the PXL-AUD-005 SI/OR/VB/PV pattern to CM/DM/VC, banking, inventory, and fixed-asset documents), or PXL-DA-001 server-side GL preview RPC. Alternatively the small PXL-AUD-029 AppShell fix.

## Exact Next Prompt

```text
Continue autonomously from the AI operating files.

Read:
- AI/AGENT_SYSTEM_PROMPT.md
- AI/AI_STATE.md
- AI/AI_HANDOFF.md
- AI/AI_WORK_QUEUE.md
- AI/AI_CONTEXT_INDEX.md
- AI/AI_DECISIONS.md

Pick the highest-priority unblocked task and execute it.
Do not ask me to re-explain PXL unless the documents are missing or conflicting.
Before ending, update AI/AI_STATE.md, AI/AI_HANDOFF.md, and AI/AI_WORK_QUEUE.md.
```
