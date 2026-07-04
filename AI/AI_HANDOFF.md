# AI Handoff

Last updated: 2026-07-04

## What Was Done

Session 46 (2026-07-04, small bounded session): PXL-AUD-018 CLOSED — `npm run lint` now reports ZERO warnings (exit 0), so any new warning is a visible regression. The 27 `useEffect` missing-dependency warnings all flagged one benign idiom (`useEffect(() => { load() }, [companyId, ...])` with a per-render loader; other inputs refetch via direct handler calls, so each effect run executes a fresh closure — no stale-state bug); every site carries `// eslint-disable-next-line react-hooks/exhaustive-deps` WITH an explanation, which the finding's expected behavior explicitly allows. A 27-page useCallback restructure was rejected as regression risk without user value. The 2 fast-refresh only-export-components notes (`button.tsx`, `context.tsx`) are suppressed with reason. Comments only — zero behavior change, no migration; hosted Supabase unchanged (synced through `20260704000002`).

Session 45 (2026-07-04, small bounded session): PXL-AUD-018 partial (39→29 lint warnings, exit 0). The 7 unstable-dependency warnings were a real production defect: six compliance dashboards (`BooksDashboardPage`, `CASDashboardPage`, `IncomeTaxDashboardPage`, `PTDashboardPage`, `VATDashboardPage`, `WTDashboardPage`) created `now = new Date()` (WT also `quarterMonths`) on every render → the `load` useCallback changed identity every render → `useEffect([load])` refired after every render → continuous Supabase refetch loop. Fixed by pinning `now` at mount with `useMemo(() => new Date(), [])` (and deriving `quarterMonths` via `useMemo`). Also: ternary-as-statement Set toggles in `DepreciationRunPage`/`CollectionMonitoringPage` → if/else; unused `department_name` destructure in `EmployeesPage` `_`-prefixed. Frontend-only, no migration; hosted Supabase unchanged (synced through `20260704000002`). Remaining for AUD-018: 27 `useEffect` missing-dependency warnings (`load`/`loadHeaders`/`fetchLogs`/`fetchEvents`) — stabilize each page's loader with `useCallback` and verify no refetch loop/stale closure per page; plus 2 fast-refresh only-export-components notes (`context.tsx`, `shared.tsx`).

Session 44 (2026-07-04, small bounded session): closed PXL-AUD-017 — `AppContextProvider` restores company/branch/period from localStorage (`pxl.ctx.*`) and persists changes; `ContextSelectors` validates restored IDs against its RLS-scoped selector queries and clears anything invisible to the signed-in user (company staleness cascade-clears branch/period). Frontend-only; build/lint green; no migration so hosted Supabase needs no push (still synced through `20260704000002`).

Session 43 (2026-07-04): implemented PXL-DA-011 status-aware immutability, which also closed the PXL-AUD-005 residue.

- `20260704000002_status_immutability.sql`: two generic SECURITY DEFINER trigger guards. `fn_guard_doc_lines(parent, fk, status_col, editable_csv, same_txn)` blocks line INSERT/UPDATE/DELETE unless the parent status is editable — applied to 18 line tables (all sales/purchasing/banking/inventory line tables, `bank_recon_items`, `journal_entry_lines`; SI/OR/VB/PV keep their PXL-AUD-005 triggers). `fn_guard_doc_header(status_col, editable_csv, extras_csv, frozen_csv, same_txn)` freezes business columns once a document leaves its editable statuses — only status, `updated_at/by`, and per-table lifecycle metadata (posting stamps, JE linkage, void reason, PV/CV release/clear dates, CM/DM totals for the apply path, VC `remaining_balance`, PCV `replenishment_id`, schedule `posted_periods`, returns filing metadata) may change; DELETE outside editable statuses always blocked (DEC-002); `frozen` statuses (posted amortization/depreciation/rev-rec entries) allow no change at all. Applied to 34 header tables. `vat_returns` excluded (PXL-DA-015 snapshot guard governs it).
- Same-transaction construction exception: `fn_row_written_by_current_txn(xmin_raw)` — a VISIBLE row whose xmin transaction is still `in progress` can only have been written by the current transaction or its subtransactions (PostgreSQL never exposes other transactions' uncommitted rows). Plain `xmin = txid_current()` fails under plpgsql EXCEPTION blocks and pgTAP assertions (subtransaction xids), which is why `txid_status` is used. This keeps every posting writer (posted JE header inserted before its lines), the purchase-return create-then-delete JE flow, and the CM/DM apply RPCs (which zero and recompute totals from a locked status) working — while PostgREST clients, whose every call is a single transaction, can never satisfy it.
- Diff-based header checking: only genuinely CHANGED columns are validated, so UI full-payload re-saves of unchanged values pass (SO cancel, quotation transitions).
- New test `supabase/tests/020_status_immutability_test.sql` (IMMUT-001, 25 assertions). It intentionally COMMITs its fixtures so tamper attempts run cross-transaction like real REST calls — this is the only test file that commits; always `supabase db reset --local` before `npm test`.
- Test book gained IMMUT-001; schema summary and `database.types.ts` regenerated; findings index/rows/log updated.

## What Changed

- Findings standing: 27 Retested Passed / 13 In Progress / 10 Open (50 findings); 8 Criticals remain (AUD-002, AUD-006, DA-001, DA-002, DA-004, DA-008, DA-009, DA-019).
- Lint is a zero-warning baseline as of session 46 — keep it that way; new warnings are regressions.
- `npm test` is now 324/324 across 20 files.
- NEW MIGRATION DISCIPLINE: the guards fire for superuser too. Future backfills that rewrite non-draft documents/lines need `SET session_replication_role = replica` (or targeted `ALTER TABLE ... DISABLE TRIGGER`) around the backfill. New lifecycle columns on guarded tables must be added to that table's allowlist in its guard trigger.
- No accounting/tax/posting behavior changed for legitimate flows — all 299 pre-existing assertions still pass unchanged.

## What Remains

- Next Criticals: PXL-DA-001 server-side GL preview RPC (In Progress), PXL-DA-002 drilldown/drillback contracts, PXL-DA-004 posting-engine consolidation.
- PXL-DA-011 residues (documented in the finding): `tax_detail_entries` direct-write posture continues under tax-ledger findings; CM/DM total columns stay lifecycle-mutable because the apply RPCs zero/recompute them (lines remain guarded, totals always recomputable).
- Summary docs AIQ-006–007 when audit work pauses.

## Known Errors / Blockers

None locally: fresh replay through `20260704000002` + `npm test` 324/324 across 20 files (reset the local DB first — test 020 commits fixtures by design), build/lint/docs-consistency green. Session 43 landed as `ba74c14`, CI run 28707527259 green (verified via `gh run watch --exit-status`); hosted is fully in sync through `20260704000002` (pushed and verified 2026-07-04 via `supabase migration list --linked`).

## Exact Next Recommended Task

Continue `AIQ-008` with PXL-DA-001: server-side GL preview RPC used by every posting page (extend the GLImpactPanel foundation), or PXL-DA-002 drilldown contracts. Remember: `npm run gen:types` after every migration; backfills on non-draft rows need the replica-role escape hatch.

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
