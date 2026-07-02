# AI State

Last updated: 2026-07-02

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 205/205 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.0.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 28 (2026-07-02) fixed new Critical PXL-AUD-027: void/cancel/bounce paths now net the tax ledger with counter-rows (`20260702000009_tax_ledger_void_reversal.sql`), verified by TAX-LEDGER-VOID-001 — `npm test` 182/182 across 12 files on a fresh replay, build/lint pass. The user reprioritized audit fixes above the remaining summary docs (AIQ-005–007).

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync as of 2026-07-02: migrations 20260702000008 and 20260702000009 pushed and verified via `supabase migration list --linked` (session 27's earlier "008 pushed" claim was false until this sync).
- PXL-AUD-014 prerequisites documented in session 28: the tax ledger writes no rows for zero-VAT documents of VAT companies, stores no exempt/zero-rated bases, and cash sales/purchases have no tax-detail writers — required before review views can be ledger-backed.

## Last Files Changed

AIOS 1.1.0 tuning session (2026-07-02):

- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (Findings Status Index + Production Readiness Gate added; PXL-AUD-020 status contradiction fixed; PXL-DA-020 → In Progress)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (new, GENERATED — closes AIQ-005)
- `scripts/gen_schema_summary.sh`, `scripts/check_docs_consistency.sh` (new)
- `.github/workflows/ci.yml` (docs-consistency gate step)
- `AI/AI_AUTONOMY_PLAYBOOK.md` (External-Action Evidence Rule; end-loop steps 6–7)
- `AI/AGENT_SYSTEM_PROMPT.md`, `.claude/CLAUDE.md` (trivial-task and audit reading shortcuts)
- `AI/AI_CONTEXT_INDEX.md` (schema summary registered; audit mode reads the index first)
- `AI/AIOS_VERSION.md` (1.1.0), `AI/AI_WORK_QUEUE.md` (AIQ-005 Done, AIQ-013 Done), `AI/AI_STATE.md`, `AI/AI_HANDOFF.md`

## Last Known Errors

None. `npm test` 182/182 across 12 files on a fresh local database; `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39).

## Next Recommended Step

Continue AIQ-008: PXL-AUD-014 VAT ledger completeness (classification bases, zero-VAT rows, CS/CP writers, then ledger-backed review views) or `can_perform` enforcement (PXL-DA-003, needs a user business-role decision).

## Decisions Needed From User

These block autonomous progress on specific findings (Level 4 items). Answering them in one message unblocks multiple fix sessions:

1. **Business role matrix** (PXL-DA-003, PXL-AUD-004): which roles (owner/admin/member/viewer, or new roles like accountant/bookkeeper) may create/edit operational master data (customers, suppliers, items), and which may approve/post/void/reverse, per document type. Unblocks `can_perform` enforcement.
2. **Approval segregation-of-duties** (PXL-DA-012): which document types require approval before posting, and whether the approver must differ from the creator. Unblocks approval-gate enforcement in posting RPCs.
3. **Branch semantics** (PXL-DA-017): is branch a security boundary (users restricted per branch) or a reporting dimension only. Unblocks dimension enforcement design.
4. **Workflow**: agents currently commit and push directly to `main` with CI as the gate; say if you prefer pull requests instead.

Settled by practice: agents maintain the work queue and state files each session; Claude API `cache_control` work stays parked until an API integration exists.
