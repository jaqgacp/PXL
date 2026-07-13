# AI State

Last updated: 2026-07-13 (session 73 — official Transaction Workspace Standard documented; routed draft/new consolidation and schema-backed master-data gaps remain)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit standing is unchanged at **43 Retested Passed / 11 In Progress / 18 Open (72)**. The two remaining Criticals, **PXL-DA-009** and **PXL-DA-019**, are **paused** (still Open, not withdrawn) by user directive: the **Standard Transaction Workspace (DEC-013)** is now the active sole development priority (DEC-015).

## Current Active Task

**AIQ-015 — Standard Transaction Workspace**, phased and monitored. The Sales Invoice is the master template. Sessions 68-71 implemented the routed dense viewing/lifecycle standard and final visual polish: compact company-accent header and subtle tab tint, clickable customer name, three primary metrics, Posting/Collection/Lock chips in the header, no separate state/workflow strip, no Quick Actions card, exactly three short information cards, no right rail, portal-based More menu, one-line tabs including Workflow and Related Party, profile/chooser-based professional line grid with inline expansion and totals, and expanded accounting/tax/validation/approval/audit/supporting tabs. Session 71 standardized ERP section headers, tables, row heights, numeric alignment, total rows, compact empty states, sharper radii, lighter borders/shadows, and calmer neutral row highlighting across the transaction workspace. Session 72 upgraded the reusable `LineGrid` into an enterprise saved-view table framework: Default/Accounting/Tax/Audit/Inventory/Sales/Custom views, browser-local persisted custom views and preferences, grouped column chooser with search/reset/select/clear, drag-and-drop column ordering, pin/unpin, resizing, compact/comfortable/spacious density, sticky headers/totals/pinned identity columns, global filter, export, and refresh. Session 73 converted `docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md` into the official canonical Sales Invoice-based Transaction Workspace Standard covering architecture, rationale, tab ownership, UI/UX rules, reusable components, extension rules, developer guidelines, and UX decisions. Full customer/vendor profile data now belongs in Related Party; actions live only in the header; workflow lives in Workflow/Approval; audit/system/related/accounting/tax details live only in their dedicated tabs. `companies.workspace_accent_color` is governed through Company Setup and migration `20260713000001_company_workspace_appearance.sql`. Unsupported fields remain visibly unassigned/untracked; none were hardcoded. Next is P5B: route-driven draft/new editing, register cleanup, and missing master-data/storage entities before rollout to Vendor Bill.

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

Continue AIQ-015 P5B. First relocate draft create/edit and `/sales-invoices/new` into `DocumentLayout` without changing `fn_save_sales_invoice`/posting behavior; retire the register form and add status-aware register actions. Then create/link the missing governed master data and storage contracts listed in the handoff. Verify with `npm run build` / `npm run lint`; run database tests only after explicitly holding out the three user-owned broken drafts. DA-009/DA-019 stay paused.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active; DEC-015 records the workspace-first priority pivot (DA-009/DA-019 paused).
