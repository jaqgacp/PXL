# AI State

Last updated: 2026-07-12 (session 64 — local verification complete; hosted/Git push pending)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The standing remains **43 Retested Passed / 11 In Progress / 18 Open (72)** — DA-019 stays Critical/Open because session 64 delivered only its first slice. Two Critical findings remain: **PXL-DA-009** and **PXL-DA-019**.

## Current Active Task

The first safe PXL-DA-019 CAS/BIR control slice is built and fully verified locally on the deployed branch-scoped numbering contract (the broken held-out `20260710000005` was not adopted). What shipped:

- `20260712000003_posting_runtime_repairs.sql` + test 031 (49 assertions): repaired the three schema-lint-surfaced runtime defects — stock-transfer JE numbering now uses the source-warehouse branch (JE stays branch-unattributed); physical-count value stays derived on the immutable line/inventory transaction (no `variance_cost` column); explicit optional `vendor_bills.rr_id` FK, validated in `fn_save_vendor_bill`, replaces the nonexistent receiving-report link that purchase-return completion read.
- `20260712000004_cas_numbering_void_evidence.sql` + test 032 (25 assertions): immutable `cas_document_number_issuances`/`cas_document_void_events`, a `number_series` guard (no backward counters, no post-issuance identity/format/ATP-start changes), atomic ATP-range exhaustion with no counter drift, allocation/void triggers across numbered document tables, a hard `P0001` immutability trigger on void evidence (owner included), historical backfill, and the `vw_cas_atp_usage` governed read model. Void evidence snapshots the pre-void (`posted`) row.
- React: `VendorBillsPage` optional RR capture; CAS Void Register / ATP Usage / Dashboard / Audit Report pages read the governed objects.

## Verification State

- Held-out-safe fresh `supabase db reset` (unowned `20260710000004`/`00005` + test `027` moved aside, then restored byte-for-byte): **full pgTAP 601/601 across 31 owned files**.
- `supabase db lint --local --level warning`: the three prior actionable errors are gone; the four new CAS trigger functions add zero warnings. Remaining findings are the known temp-table/dynamic-`record`/`fn_row_written_by_current_txn` STABLE-vs-VOLATILE false positives.
- `npm run gen:types` regenerated `src/lib/database.types.ts`; `npm run build` passed; `npm run lint` zero warnings; schema summary regenerated (197 functions / 20 views / 149 tables / 229 triggers); `scripts/check_docs_consistency.sh` green (72 findings, 31 tests).
- Two failing test-032 assertions found during this session were fixed in the migration (pre-void `OLD` snapshot; owner-proof `P0001` immutability trigger). Working tree is **not yet committed**; the new migrations are **not yet pushed to hosted** — hosted remains last verified through `20260712000002` from session 63.

## Known Boundaries

- The untracked `20260710000004`, `20260710000005`, and test `027` remain user-owned, broken, and excluded. The CAS draft revokes an allocator used directly by ten frontend pages, misclassifies cash-sale `CS` issuance as `SI`, breaks test 021, and its own test previously passed only 15/30.
- Stock-transfer JEs intentionally remain branch-unattributed; only their JE number allocation uses the source warehouse branch.
- Exact DAT file bytes/layout are not in the first DA-019 slice. Current snapshots prove frozen rows, not the exact browser-produced file bytes.

## Next Recommended Step

Commit the working tree, then dry-run and push the two new migrations to the linked hosted project and verify parity (see `AI/AI_HANDOFF.md` for the exact sequence). Afterward continue DA-019's remaining slices (true BIR DAT record layout, books reconciliation, exported-byte hashing) or advance DA-009 dependencies.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active.
