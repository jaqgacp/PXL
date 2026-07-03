# AI Handoff

Last updated: 2026-07-03

## What Was Done

Session 30 closed PXL-DA-003 (Critical) and PXL-AUD-004 (High) — both now Retested Passed. Migration `20260702000010_can_perform_role_actions.sql` implements DEC-009: `fn_can_perform(company_id, action, document_type)` (owner/admin all actions; member create/edit/master_data; viewer/non-member nothing), lifecycle gate `fn_require_admin_for_accounting_lifecycle` rerouted through it (37 gated tables, verified live), `approved` added to the default restricted-status list (member-approval hole closed), new gates on petty cash voucher approval and `journal_entries` insert/status (JE gate backstops every posting/reversal path), and customers/suppliers/items RLS write policies moved to the `master_data` action (members create/edit, viewers read-only, delete owner/admin). Tests: RLS-ROLES-001 extended to 17 assertions (member denied approve, admin approves), new RBAC-CANPERFORM-001 (`supabase/tests/013_can_perform_test.sql`, 13 assertions). Test book, findings index/detail rows, session 30 log row, and regenerated schema summary all updated.

## What Changed

- Findings standing: 17 Retested Passed / 14 In Progress / 16 Open; 11 Critical findings still open (listed in the standing line).
- `fn_can_perform` is now the single role/action enforcement surface; future named roles (accountant/bookkeeper) map onto its actions without changing enforcement.
- `supabase/tests/` now has 13 files / 196 assertions.

## What Remains

- PXL-DA-012 approval SoD per DEC-010 (approved instance + approver ≠ creator when a workflow is configured) — the natural follow-on to `can_perform`.
- PXL-AUD-014 VAT ledger completeness (zero-VAT rows, classification bases, CS/CP writers) — parallel P0 track.
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay + `npm test` 196/196, build/lint/docs-consistency green. Check hosted sync status for migration 20260702000010 in `AI/AI_STATE.md` (push attempted at end of session 30; PENDING if no token was available).

## Exact Next Recommended Task

Continue `AIQ-008` with PXL-DA-012 per DEC-010: enforce an approved `approval_instances` row and approver ≠ creator inside the approve/post RPCs whenever an `approval_workflows` row is configured for the company/document type; extend RLS-ROLES-001 or add a seeded scenario for self-approval rejection; run the full local suite; push to hosted Supabase (record PENDING if no token).

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
