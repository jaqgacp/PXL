# AI Handoff

Last updated: 2026-07-04

## What Was Done

Session 42 (2026-07-04, user-directed bounded frontend-safety session — explicitly NO framework rewrite):

- Generated database types (`src/lib/database.types.ts`, new `npm run gen:types` script) and typed the shared Supabase client `createClient<Database>`. Table names, columns, RPC names/args, and embeds are now compile-time checked across all 206 pages — schema drift fails the build.
- The first typecheck produced 71 errors. The genuine defects became **PXL-AUD-030** (new, High, fixed + retested): 8 pages queried non-existent columns and were runtime-dead — quotation/SO/DR/customer-return/cash-sale reference fetches (`items.item_name` → `description`, `customers.address` → `registered_address`/`delivery_address`, `units_of_measure.uom_name` → `description`, `suppliers.supplier_name` → `registered_name`, `delivery_receipts.date` → `dr_date`, DR-line price/VAT/revenue now sourced from the SO line + item master via embeds) and the SLP register tab (`vw_slp_export` has no `period_year`/`period_month`/`supplier_name` — now filters `bill_date` month range and aggregates per supplier client-side).
- **PXL-AUD-029** fixed + retested: AppShell feature gating resolves keys via `ref_feature_definitions(feature_key)` embed; default-open preserved; no more 400 per page load.
- Remaining 60 errors were behavior-neutral type friction, fixed mechanically: optional RPC args omitted instead of passing null (same SQL NULL via DEFAULT), non-null assertions where null-for-new-document is intentional and handled in the fn body, read-list nullability casts, dynamic RPC/table names typed as literal unions, `TablesInsert`/`TablesUpdate` casts on spread payloads.
- `PXL_ARCHITECTURE_SUMMARY.md` stack line corrected: TanStack Query, Zustand, react-hook-form, Zod are installed but NOT adopted — marked as planned with backlog pointers. Architecture docs must never overstate reality.
- Backlog gained a Frontend Architecture section: selective TanStack Query targets (dashboards/registers/reference data — never bulk), react-hook-form candidates (PV/VB/SI/OR/cash-sale/setup forms, when next reworked), shared reference-data hooks (duplication is how the dead-column bug spread across 3 sales pages), CI types-drift gate, Zustand adopt-or-remove decision, and a profile-before-optimizing rule (no memoization applied — no measured bottleneck).

## What Changed

- Findings standing: 23 Retested Passed / 14 In Progress / 13 Open (50 findings); 10 Criticals remain.
- No migrations, no schema change, no accounting/tax/posting behavior change. `supabase/tests/` unchanged (19 files / 299 assertions).
- New discipline: run `npm run gen:types` after every migration — a stale `database.types.ts` fails the build when pages use new columns/RPCs.

## What Remains

- Next Criticals: PXL-DA-011 status-aware immutability on all transactional header/line tables (Open) or PXL-DA-001 server-side GL preview RPC (In Progress).
- Frontend enhancements (TanStack Query, react-hook-form, shared hooks, CI types-drift gate) live in the backlog's Frontend Architecture section — selective adoption only, never bulk.
- Document-line department/cost-center capture is a backlog enhancement (documents carry only branch today).
- `fn_bt_reverse_je` and doc-void counter-JEs inherit header branch but do not copy line dept/cc — adopt the `fn_reverse_je` pattern when a capture path writes dept/cc on those JEs.
- Stock transfer JEs stay branch-unattributed by design (they span warehouses).
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay through `20260704000001` + `npm test` 299/299 across 19 files (reset the local DB first — leftover seeds collide with test UUIDs), build/lint/docs-consistency green. Hosted is fully in sync through `20260704000001` (pushed and verified 2026-07-04 via `supabase migration list --linked`). No pending credential items. Session 42 landed as `bb6d96c`, CI run 28706337718 green (verified via `gh run watch --exit-status`).

## Exact Next Recommended Task

Continue `AIQ-008` with PXL-DA-011: status-aware immutability on every transactional header/line table (extend the PXL-AUD-005 SI/OR/VB/PV pattern to CM/DM/VC, banking, inventory, and fixed-asset documents), or PXL-DA-001 server-side GL preview RPC. Remember: `npm run gen:types` after every migration.

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
