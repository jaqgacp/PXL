# AI Handoff

Last updated: 2026-07-03

## What Was Done

Session 38 continued PXL-DA-015 report provenance with the CAS DAT slice. Migration `20260703000008_report_snapshots_cas_exports.sql` adds `fn_snapshot_cas_export`: it builds all four CAS extract payloads server-side (SLSP, RELIEF, GL, alphalist of payees), gates each on its own reconciliation (VAT for SLSP/RELIEF, EWT payable for the alphalist, debit=credit balance for the GL extract), creates versioned `CAS_*` exported snapshots with SHA-256 hashes, writes server-attested `cas_export_log` rows (a new `snapshot_id` column links log to snapshot; direct client inserts are closed with `WITH CHECK (false)`), and returns the frozen rows. `CASDATFileGenerationPage` now renders the downloaded file from those frozen rows, so the file is provably the hashed payload. Sessions 34-37 delivered VAT return, Form 2307 issued, SLSP/RELIEF, and SAWT/QAP snapshots.

## What Changed

- Findings standing: 19 Retested Passed / 15 In Progress / 14 Open (48 findings); 11 Criticals remain.
- CAS DAT extracts now create versioned exported snapshots; `cas_export_log` is RPC-only, server-attested evidence.
- New scenario CAS-EXPORT-SNAP-001 (`supabase/tests/017_cas_export_snapshots_test.sql`, 15 assertions).
- `supabase/tests/` now has 17 files / 272 assertions.
- Transaction matrix gained a CAS DAT File Generation row.

## What Remains

- PXL-DA-015 remains In Progress: extend `report_snapshots` to the books journal exports; add a snapshot reader/drilldown UI. Do not redo VAT return (`20260703000004`), Form 2307 issued (`20260703000005`), SLSP/RELIEF export (`20260703000006`), SAWT/QAP export (`20260703000007`), or CAS DAT export (`20260703000008`) snapshots. The true BIR DAT record layout stays under PXL-DA-019.
- PXL-DA-017 dimension propagation to JE lines per DEC-011.
- CM/DM/VC per-classification ledger rows follow the same writer pattern when needed.
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay through `20260703000008` + `npm test` 272/272, build/lint/docs-consistency green. PENDING: hosted push of migrations `20260702000010` and `20260703000001` through `20260703000008` — no `SUPABASE_ACCESS_TOKEN` in this workspace; run `supabase db push --linked` from a tokened workspace and verify with `supabase migration list --linked`.

Same remittance caveat as the VAT slice: legitimate 0619-E/1601EQ remittance JEs on the withholding control accounts surface as reconciliation variance until a controlled remittance flow exists.

## Exact Next Recommended Task

Continue `AIQ-008` by extending `report_snapshots` to the books journal exports (7 Books pages export browser-side CSVs of posted documents/JE lines), or build the snapshot reader/drilldown UI over the now five snapshot families. Reuse the sessions-34/36/37/38 pattern: append-only snapshot row, canonical source payload, SHA-256 source hash, no direct writes, reconciliation where relevant, versioned export history; per session 38, prefer returning frozen rows so the exported file equals the hashed payload. If choosing a non-tax architecture task instead, PXL-DA-017 dimension propagation is the next unblocked candidate.

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
