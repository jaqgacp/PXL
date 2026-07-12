# AI State

Last updated: 2026-07-12 (session 67 — Sales Invoice built out as the complete reference workspace: Primary Information, 12 tabs, Line Detail Panel, full sidebar, header statuses; draft-form relocation + register actions remain)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit standing is unchanged at **43 Retested Passed / 11 In Progress / 18 Open (72)**. The two remaining Criticals, **PXL-DA-009** and **PXL-DA-019**, are **paused** (still Open, not withdrawn) by user directive: the **Standard Transaction Workspace (DEC-013)** is now the active sole development priority (DEC-015).

## Current Active Task

**AIQ-015 — Standard Transaction Workspace**, phased and monitored (see the AIQ-015 Phase Plan in `AI/AI_WORK_QUEUE.md`; in-session task list mirrors it). Pilot = Sales Invoice (blueprint §17), adopt-on-touch. Shipped this session: Phase 0 governance (DEC-015 + queue + issue-routing), Phase 1 shell (`src/components/document/DocumentLayout.tsx`), and the Phase 2/3 SI pilot — a deep-linkable read-only document view (`src/pages/SalesInvoiceDocumentPage.tsx`, route `/sales-invoices/:id`, reachable via "Open ↗" from the list) rendering `DocumentLayout` with tabs (Lines · GL Impact · Posting Validation · Audit Trail · Related) + right-rail Financial Summary/Party + workflow strip. build+lint green, HMR-verified; existing list+modal untouched. Also shipped: Phase 4 (`FinancialSummaryPanel` + `PostingValidationPanel` with live `useTransactionReadiness` preflight) and Phase 5 (`LineGrid` column-group grid + VAT-only `TaxImpactPanel`, user-approved scope — EWT/CWT deferred pending the paused AUD-031/032/033). All six shared components now exist under `src/components/document/`. Next: Phase 6 — roll `DocumentLayout` across the core four (OR/VB/PV) adopt-on-touch, then secondary docs + `RelatedDocumentsTab` + config layer. Discovered defects route to the audit findings doc in severity order (DEC-015); enhancements to vision/backlog.

### Session 64 (previous, shipped) — PXL-DA-019 first CAS slice

The first safe PXL-DA-019 CAS/BIR control slice is built and fully verified locally on the deployed branch-scoped numbering contract (the broken held-out `20260710000005` was not adopted). What shipped:

- `20260712000003_posting_runtime_repairs.sql` + test 031 (49 assertions): repaired the three schema-lint-surfaced runtime defects — stock-transfer JE numbering now uses the source-warehouse branch (JE stays branch-unattributed); physical-count value stays derived on the immutable line/inventory transaction (no `variance_cost` column); explicit optional `vendor_bills.rr_id` FK, validated in `fn_save_vendor_bill`, replaces the nonexistent receiving-report link that purchase-return completion read.
- `20260712000004_cas_numbering_void_evidence.sql` + test 032 (25 assertions): immutable `cas_document_number_issuances`/`cas_document_void_events`, a `number_series` guard (no backward counters, no post-issuance identity/format/ATP-start changes), atomic ATP-range exhaustion with no counter drift, allocation/void triggers across numbered document tables, a hard `P0001` immutability trigger on void evidence (owner included), historical backfill, and the `vw_cas_atp_usage` governed read model. Void evidence snapshots the pre-void (`posted`) row.
- React: `VendorBillsPage` optional RR capture; CAS Void Register / ATP Usage / Dashboard / Audit Report pages read the governed objects.

## Verification State

- Held-out-safe fresh `supabase db reset` (unowned `20260710000004`/`00005` + test `027` moved aside, then restored byte-for-byte): **full pgTAP 601/601 across 31 owned files**.
- `supabase db lint --local --level warning`: the three prior actionable errors are gone; the four new CAS trigger functions add zero warnings. Remaining findings are the known temp-table/dynamic-`record`/`fn_row_written_by_current_txn` STABLE-vs-VOLATILE false positives.
- `npm run gen:types` regenerated `src/lib/database.types.ts`; `npm run build` passed; `npm run lint` zero warnings; schema summary regenerated (197 functions / 20 views / 149 tables / 229 triggers); `scripts/check_docs_consistency.sh` green (72 findings, 31 tests).
- Two failing test-032 assertions found during this session were fixed in the migration (pre-void `OLD` snapshot; owner-proof `P0001` immutability trigger). Committed as `ffe7782` and pushed to `origin/main`. **Hosted push complete**: `20260712000003`/`20260712000004` were pushed to linked project `bskjkogijpbhukjkagfj` with the held-out `20260710000004`/`00005` moved aside during the push (they remain off hosted — blank Remote in `migration list`). Hosted is now synced through `20260712000004` (local = remote).

## Known Boundaries

- The untracked `20260710000004`, `20260710000005`, and test `027` remain user-owned, broken, and excluded. The CAS draft revokes an allocator used directly by ten frontend pages, misclassifies cash-sale `CS` issuance as `SI`, breaks test 021, and its own test previously passed only 15/30.
- Stock-transfer JEs intentionally remain branch-unattributed; only their JE number allocation uses the source warehouse branch.
- Exact DAT file bytes/layout are not in the first DA-019 slice. Current snapshots prove frozen rows, not the exact browser-produced file bytes.

## Next Recommended Step

Execute the AIQ-015 phase plan in order. Immediate next: **P1 Shell** — build `DocumentLayout` (header bar + StatusBadge + workflow strip + fixed toolbar + tabs shell + right-rail zone), `WorkflowStrip`, and `TransactionTabs` in `src/components/document/`, reusing `src/components/ui/shared.tsx` atoms; then P2 routes for the Sales Invoice pilot. Verify with `npm run build` / `npm run lint` / `npm run gen:types` after each phase. DA-009/DA-019 stay paused. Git and hosted are synced through `20260712000004`.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active; DEC-015 records the workspace-first priority pivot (DA-009/DA-019 paused).
