# AI Handoff

Last updated: 2026-07-02

## What Was Done

Audit fix session 28 (AIQ-008): while starting PXL-AUD-014, found and fixed new Critical PXL-AUD-027 — void/cancel/bounce paths posted counter-JEs on the GL but left the tax ledger un-netted (SI void/PV cancel/OR bounce never touched tax rows; VB void mutated originals), so voided documents broke VAT reconciliation and blocked returns, cancelled PVs kept feeding 2307 data, and bounced ORs kept claiming CWT. `20260702000009_tax_ledger_void_reversal.sql` adds a shared counter-row helper wired into all four paths, uniform `is_reversal` semantics, `vw_ewt_summary_ap` exclusion of reversed originals, and a backfill for existing environments. Seeded scenario TAX-LEDGER-VOID-001 (test 012, 17 assertions) proves per-period ledger/GL parity through voids.

## What Changed

- Verification: fresh `supabase db reset --local` replay clean; `npm test` 182/182 across 12 files; build passed; lint pre-existing warnings only (39).
- Matrix SI/OR/VB/PV cells, test book, findings detail + session log row 28 all updated.
- PXL-AUD-014 prerequisites documented: zero-VAT documents write no ledger rows, no exempt/zero-rated bases stored, no CS/CP writers — ledger completeness must precede ledger-backed review views.

## What Remains

- Push migration `20260702000009` to the hosted Supabase project (no access token in this workspace — run `supabase login`, then `supabase db push --linked`).
- AIQ-008 continues: PXL-AUD-014 VAT ledger completeness, or `can_perform` enforcement (PXL-DA-003, needs a user business-role decision).
- Approval segregation-of-duties (PXL-DA-012); summary docs AIQ-005–007 when audit work pauses.

## Known Errors / Blockers

None locally. Hosted migration push blocked on Supabase login only.

## Exact Next Recommended Task

Push migration 009 to the hosted project, then continue `AIQ-008` with PXL-AUD-014 VAT ledger completeness: per-classification VAT bases on `tax_detail_entries`, rows for zero-VAT documents of VAT companies, CS/CP writers, backfill, then rebuild `vw_output_vat_review`/`vw_input_vat_review` on the ledger keeping names/columns.

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
