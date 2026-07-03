# AI Handoff

Last updated: 2026-07-03

## What Was Done

Session 36 continued PXL-DA-015 report provenance. Migration `20260703000006_report_snapshots_vat_exports.sql` adds `fn_snapshot_vat_export`, which creates append-only exported snapshots for SLSP and RELIEF before CSV download. Snapshots use deterministic logical source IDs per company/report/month/export part, incrementing export versions, SHA-256 source hashes, and VAT/GL reconciliation payloads. `SLSPExportPage` and `RELIEFExportPage` now call the RPC before producing CSVs; unreconciled periods are blocked. Sessions 34-35 already delivered VAT return final/filed snapshots and Form 2307 issued sent/acknowledged snapshots.

## What Changed

- Findings standing: 19 Retested Passed / 15 In Progress / 14 Open (48 findings); 11 Criticals remain.
- VAT returns now have immutable final/filed report snapshots with source hashes and amount immutability.
- Form 2307 issued certificates now have immutable sent/acknowledged snapshots with versioned source hashes.
- SLSP and RELIEF exports now have exported snapshots with source hashes, export history versions, and reconciliation blocking.
- VAT-RECON-001 and F2307-SUPERSEDE-001 include snapshot creation, hash length, immutable amount guard, export history, and versioned snapshot assertions.
- `supabase/tests/` now has 15 files / 243 assertions.

## What Remains

- PXL-DA-015 remains In Progress: extend `report_snapshots` to SAWT, QAP, books, and CAS exports; add reader/drilldown UI for snapshots. Do not redo VAT return, Form 2307 issued, or SLSP/RELIEF export snapshots.
- PXL-DA-017 dimension propagation to JE lines per DEC-011.
- CM/DM/VC per-classification ledger rows follow the same writer pattern when needed.
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay through `20260703000006` + `npm test` 243/243, build/lint/docs-consistency green. PENDING: hosted push of migrations `20260702000010`, `20260703000001`, `20260703000002`, `20260703000003`, `20260703000004`, `20260703000005`, and `20260703000006` — no `SUPABASE_ACCESS_TOKEN` in this workspace; run `supabase db push --linked` from a tokened workspace and verify with `supabase migration list --linked`.

## Exact Next Recommended Task

Continue `AIQ-008` by extending `report_snapshots` to SAWT, QAP, books, or CAS exports. Reuse the session-34/36 pattern: append-only snapshot row, canonical source payload, SHA-256 source hash, no direct writes, reconciliation where relevant, and immutable/versioned evidence after snapshot. Do not redo VAT return snapshots (`20260703000004`), Form 2307 issued snapshots (`20260703000005`), or SLSP/RELIEF export snapshots (`20260703000006`). If choosing a non-tax architecture task instead, PXL-DA-017 dimension propagation is the next unblocked candidate.

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
