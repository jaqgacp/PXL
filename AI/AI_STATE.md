# AI State

Last updated: 2026-07-13 (session 77 — ATC document-date validation + rate versioning; AUD-035/036 closed)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit standing is now **45 Retested Passed / 11 In Progress / 16 Open (72)** after session 77 closed **PXL-AUD-035** and **PXL-AUD-036**. Session 75 added **DEC-017** and `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md`: the active milestone is **PXL Accounting Core Ready**. Session 76 added **DEC-018** and `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md` as the governed posting-behavior source of truth. This supersedes DEC-015's temporary transaction-workspace-first ordering. The Sales Invoice Workspace and Report Workspace standards remain authoritative references, but transaction/report expansion is paused until the accounting core, posting engine, account determination engine, tax engine, CAS/BIR readiness, and master-data governance are production-ready.

## Session 77 (current, shipped locally) — ATC document-date validation + rate versioning

Trusted migration `20260713000002_atc_document_date_versioning.sql` (test 033, ATC-DOCDATE-VERSION-001, 15 assertions) closes **PXL-AUD-035** (TAX-001) and **PXL-AUD-036** (TAX-002), replacing the held-out draft `20260710000004` (which stays excluded). AUD-035: `fn_validate_payment_voucher_line_ewt` and `fn_validate_receipt_line_cwt` each collapse to one signature with a trailing `p_document_date DATE` and evaluate the ATC effective window as of the document date; every caller threads the document date (PV save/line-trigger/ready, OR save/line-trigger/ready, cash sale via the receipt-line trigger, CV header trigger + post). The prior 4-/6-arg overloads are dropped so un-updated call sites bind to the single new function and fall back to CURRENT_DATE. AUD-036: global `UNIQUE (code)` replaced by version-aware `uq_atc_code_version (code, tax_category, effective_from)`; `fn_enforce_atc_version_rules` rejects overlapping active windows and validates successor linkage; `fn_atc_version_asof(code, category, as_of)` resolves the in-force version; `fn_guard_atc_code_history` also freezes `effective_from` once used. Master-data default triggers intentionally keep CURRENT_DATE. Frontend ATC pickers still resolve by row (not yet by document date through `fn_atc_version_asof`) — a UI enhancement, not a posting defect.

## Current Active Task

**AIQ-017 — PXL Accounting Core Ready** is active. Do not create new UI standards, implement report pilots, roll out more transaction workspaces, or build dashboards. The required sequence is: Accounting Engine → Posting Engine → Account Determination Engine → Configuration-driven Tax Engine → Master Data Governance → CAS/BIR Readiness → Transaction Rollout → Report Rollout → Dashboards → Client Portal → AI / Automation. Session 75 documented the production-readiness review in `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md`. Session 76 documented `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md`, including transaction posting rule schema, initial transaction matrix coverage, account determination hierarchy, configuration-driven tax engine architecture, test expectations, and maintenance rules.

Historical context: Sessions 68-73 completed the Sales Invoice Transaction Workspace standard; session 74 completed the Report Workspace standard. Those standards remain valid but are paused for implementation until the core is ready. Unsupported fields remain visibly unassigned/untracked; none should be hardcoded. `companies.workspace_accent_color` is governed through Company Setup and migration `20260713000001_company_workspace_appearance.sql`.

### Session 64 (previous, shipped) — PXL-DA-019 first CAS slice

The first safe PXL-DA-019 CAS/BIR control slice is built and fully verified locally on the deployed branch-scoped numbering contract (the broken held-out `20260710000005` was not adopted). What shipped:

- `20260712000003_posting_runtime_repairs.sql` + test 031 (49 assertions): repaired the three schema-lint-surfaced runtime defects — stock-transfer JE numbering now uses the source-warehouse branch (JE stays branch-unattributed); physical-count value stays derived on the immutable line/inventory transaction (no `variance_cost` column); explicit optional `vendor_bills.rr_id` FK, validated in `fn_save_vendor_bill`, replaces the nonexistent receiving-report link that purchase-return completion read.
- `20260712000004_cas_numbering_void_evidence.sql` + test 032 (25 assertions): immutable `cas_document_number_issuances`/`cas_document_void_events`, a `number_series` guard (no backward counters, no post-issuance identity/format/ATP-start changes), atomic ATP-range exhaustion with no counter drift, allocation/void triggers across numbered document tables, a hard `P0001` immutability trigger on void evidence (owner included), historical backfill, and the `vw_cas_atp_usage` governed read model. Void evidence snapshots the pre-void (`posted`) row.
- React: `VendorBillsPage` optional RR capture; CAS Void Register / ATP Usage / Dashboard / Audit Report pages read the governed objects.

## Verification State

- Session 77: held-out-safe fresh `supabase db reset` (unowned `20260710000004`/`00005` + test `027` moved aside, replayed through `20260713000002`, then restored byte-for-byte with checksums verified): **full pgTAP 616/616 across 32 owned files** (new test 033, 15 assertions). Prior expired-ATC assertions in tests 006/022 still pass (message wording preserved; 6-arg calls keep CURRENT_DATE). `npm run gen:types` regenerated; `npm run build` passed; `npm run lint` zero warnings; schema summary regenerated; `scripts/check_docs_consistency.sh` green (72 findings, 32 tests). **Hosted push PENDING** (no `SUPABASE_ACCESS_TOKEN` this session) — `20260713000001` and `20260713000002` remain local-only and must be pushed with the held-out drafts moved aside.
- Prior baseline (session 64):
- `supabase db lint --local --level warning`: the three prior actionable errors are gone; the four new CAS trigger functions add zero warnings. Remaining findings are the known temp-table/dynamic-`record`/`fn_row_written_by_current_txn` STABLE-vs-VOLATILE false positives.
- `npm run gen:types` regenerated `src/lib/database.types.ts`; `npm run build` passed; `npm run lint` zero warnings; schema summary regenerated (197 functions / 20 views / 149 tables / 229 triggers); `scripts/check_docs_consistency.sh` green (72 findings, 31 tests).
- Two failing test-032 assertions found during this session were fixed in the migration (pre-void `OLD` snapshot; owner-proof `P0001` immutability trigger). Committed as `ffe7782` and pushed to `origin/main`. **Hosted push complete**: `20260712000003`/`20260712000004` were pushed to linked project `bskjkogijpbhukjkagfj` with the held-out `20260710000004`/`00005` moved aside during the push (they remain off hosted — blank Remote in `migration list`). Hosted is now synced through `20260712000004` (local = remote).

## Known Boundaries

- The untracked `20260710000004`, `20260710000005`, and test `027` remain user-owned, broken, and excluded. The CAS draft revokes an allocator used directly by ten frontend pages, misclassifies cash-sale `CS` issuance as `SI`, breaks test 021, and its own test previously passed only 15/30.
- Stock-transfer JEs intentionally remain branch-unattributed; only their JE number allocation uses the source warehouse branch.
- Exact DAT file bytes/layout are not in the first DA-019 slice. Current snapshots prove frozen rows, not the exact browser-produced file bytes.

## Next Recommended Step

Continue AIQ-017. Safe ATC document-date/version governance is now DONE (session 77, `20260713000002`, replacing held-out `20260710000004`). First push the two local-only `20260713*` migrations to hosted once a `SUPABASE_ACCESS_TOKEN` is available (move the held-out `20260710000004`/`00005` aside during the push). Then work the core lane in this order: DA-009 (SAWT/QAP multi-ATC reconciliation — now unblocked by ATC versioning) and DA-019; controlled EWT remittance/CWT application flow (AUD-041); withholding basis policy (AUD-037); server-derived OR/PV settlement totals (AUD-038/048); CM/VC-aware over-apply guards (AUD-039); financial statement/close readiness; semantic transaction events; configuration-driven tax-rule model; governed master-data gaps. Optional UI follow-up: point frontend ATC pickers at `fn_atc_version_asof` by document date. Verify code changes with `npm run build` / `npm run lint`; run database tests only after explicitly holding out the three user-owned broken drafts unless those drafts are being replaced/fixed deliberately.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active. DEC-017 records the accounting-core-first priority pivot and supersedes DEC-015 until **PXL Accounting Core Ready** is achieved. DEC-018 records `PXL_ACCOUNTING_RULES_MATRIX.md` as the governed posting source of truth.
