# AI Handoff

Last updated: 2026-07-03

## What Was Done

Session 32 delivered VAT ledger completeness for PXL-AUD-014/PXL-DA-008 and discovered + fixed new Critical PXL-AUD-028. Migration `20260703000002_vat_ledger_completeness.sql`: SI/VB posting now writes one `tax_detail_entries` row per (document, vat_code) so zero-rated/exempt bases are preserved with zero tax; writers are gated on `companies.tax_registration = 'vat'` and line-level VAT codes (non-VAT companies still write nothing — NON-VAT-GATING-001 preserved); cash purchases gained input VAT writers; cash sales gained output VAT + CWT writers and correct header classification totals; a backfill adds only missing per-code rows for posted documents (legacy lump rows with NULL `vat_code_id` remain as evidence and mean "regular"; non-posted docs excluded so 20260702000009 void netting stays exact). PXL-AUD-028: the first-ever execution of `fn_save_cash_sale` (by the new seeded test) revealed the whole cash sale feature was runtime-dead — phantom `remarks`/`total_net_amount` columns, NULL payment mode into a NOT NULL column, receipt inserted posted-before-lines, totals read from payload fields the UI never sends (zero-amount documents), AR over-applied by the CWT, and no ATC. The function was rebuilt on the `fn_save_sales_invoice` server-side recompute pattern; `CashSalesPage` gained a CWT ATC selector and sends `cwt_atc_id`.

## What Changed

- Findings standing: 19 Retested Passed / 14 In Progress / 15 Open (48 findings); 11 Criticals remain.
- The tax ledger is now complete enough to back SLSP/RELIEF and the 2550 zero-rated/exempt lines.
- `supabase/tests/` now has 15 files / 223 assertions.

## What Remains

- PXL-AUD-014 final step: rebase `vw_output_vat_review`/`vw_input_vat_review` and the 2550 return generators on `tax_detail_entries` (treat NULL `vat_code_id` as regular), then filed-snapshot provenance with PXL-DA-015.
- PXL-DA-017 dimension propagation to JE lines per DEC-011.
- CM/DM/VC per-classification ledger rows follow the same writer pattern when needed.
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay + `npm test` 223/223, build/lint/docs-consistency green. PENDING: hosted push of migrations `20260702000010`, `20260703000001`, and `20260703000002` — no `SUPABASE_ACCESS_TOKEN` in this workspace; run `supabase db push --linked` from a tokened workspace and verify with `supabase migration list --linked`.

## Exact Next Recommended Task

Continue `AIQ-008` with the PXL-AUD-014 final step: rebuild `vw_output_vat_review` and `vw_input_vat_review` on `tax_detail_entries` (join `vat_codes` for classification, COALESCE NULL `vat_code_id` to regular, exclude nothing — reversal rows net naturally), reconcile the 2550M/Q generators to the same source, extend VAT-RECON-001 or VAT-LEDGER-COMPLETE-001 with view-level assertions, run the full local suite, push to hosted Supabase (record PENDING if no token).

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
