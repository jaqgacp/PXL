# AI State

Last updated: 2026-07-11 (session 61 recovery: verified, fixed, deployed to hosted, and committed)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit hardening is active under AIQ-008. The authoritative finding standing is **36 Retested Passed / 17 In Progress / 19 Open (72)**. Five Critical findings remain: PXL-DA-002, PXL-DA-004, PXL-DA-008, PXL-DA-009, and PXL-DA-019. Session 61's DA-002/004/005/007 implementation is now verified and deployed; statuses stay In Progress pending a dedicated retest/closure pass.

Session 60 was a user-directed TEST-environment session: it built three repeatable demo seeds (`supabase/seeds/demo_company_setup_seed.sql`, `demo_master_data_seed.sql`, `demo_items_inventory_seed.sql`), brought the hosted PXL Demo company to a fully green Company Setup Checklist with complete master data, logged new finding PXL-AUD-051 (document-code registry drift, Open), and found+fixed PXL-AUD-052 (Cash Purchase item lookup column drift, Retested Passed). It also recorded **DEC-013**: the **PXL Standard Transaction Workspace** (`docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md`) is the official Phase 2 product vision; audit findings retain absolute priority; adoption stays adopt-on-touch.

## Current Active Task

**Session 61 (2026-07-11) was interrupted mid-AIQ-008; a same-day recovery session completed its wrap-up: verification, one migration defect fix, docs, hosted deployment, and Git commits (user-directed).** What session 61 built:

- **`supabase/migrations/20260711000001_posting_engine_completion.sql`** (2,268 lines; PXL-DA-004/005/007): (1) registry-backed `fn_resolve_posting_source` with optional row locking and deferred-JE integrity; (2) shared tax writer with stable source-line identity and safe uniqueness; (3) shared posting/reversal audit and reversal mutation primitive; (4) core AR/AP writers migrated to create/add/finalize + the shared tax writer with unchanged public signatures; (5) core reversal paths on the shared exact-opposite primitive; (6) secondary saved-source writers acquire the same source-row lock; (7) privilege boundary — helpers revoked from application callers. Header states it deliberately does NOT take ownership of held-out migrations 00004/00005.
- **`supabase/migrations/20260711000002_accounting_trace_reports.sql`** (961 lines; PXL-DA-002): appends canonical `source_doc_type`/`source_doc_id` to `vw_customer_ledger`, `vw_supplier_ledger`, `vw_output_vat_review`, `vw_input_vat_review`, `vw_ewt_summary_ap`, `vw_cwt_summary_ar`; hardens `fn_get_accounting_trace` (JE/source mismatch fails closed; routes to the new generic `/accounting-source` page); adds internal `fn_normalize_report_source_type`, read-only `fn_get_report_snapshot_trace_links`, and membership-scoped `fn_get_report_trace_set` for aggregate report rows. Never rewrites immutable snapshot payloads/hashes.
- **UI (unstaged/untracked):** new `src/lib/accountingTrace.ts`, `src/components/AccountingTraceLink.tsx`, `src/pages/AccountingSourcePage.tsx` + `/accounting-source` route; `AccountingTracePage.tsx` extended ~261 lines for report-family trace sets; drillback links adopted across ~20 report/compliance pages (GL, Account Detail Ledger, BS/IS/SCF/SCE/Comparative FS, AP/AR Aging, VAT input/output summaries, Input VAT Review, SAWT, QAP, 2307 Issued/Received, Report Snapshots).
- **Tests:** `025_posting_preview_invariants_test.sql` updated to the generic `/accounting-source` route (still 40 assertions); new `026_accounting_trace_report_routes_test.sql` (ACCOUNTING-TRACE-REPORTS-001, 26 assertions, includes fail-closed orphan/cross-company trace cases).

## Verification and Hosted State

Recovery-session verification and deployment (2026-07-11, user-directed):

- **Defect fixed in the interrupted draft:** `fn_resolve_posting_source` in `20260711000001` referenced `v_ref.date_column`; the real column (from `20260710000003`) is `document_date_column`. Only fresh-reset replay exposed it — session 61 had applied a corrected version ad hoc, so the live DB masked the broken file.
- Fresh `supabase db reset` through `20260711000002` with unowned migrations 00004/00005 and test 027 held out: clean.
- Full pgTAP: **474/474 across 26 files** (updated 025: 40/40; new 026: 26/26).
- `npm run build`: passed. `npm run lint`: zero warnings, exit 0.
- `npm run gen:types` run (report views now expose `source_doc_type`/`source_doc_id`); scoped `docs/PXL/PXL_SCHEMA_SUMMARY.md` regenerated (187 functions, 19 views, 147 tables, 226 triggers).
- Test book entry ACCOUNTING-TRACE-REPORTS-001 added; `scripts/check_docs_consistency.sh` green (72 findings, 26 test files).
- **Hosted Supabase pushed:** `20260711000001` and `20260711000002` pushed via `supabase db push --linked` (dry-run confirmed exactly those two). `supabase migration list --linked` shows local=remote through `20260711000002`; remote function probe confirms the new functions. The known benign post-push pg-delta CA-cache warning occurred again. Hosted does **NOT** have 00004/00005 (deliberate — see Known Boundaries).
- **Git:** sessions 59–61 committed and pushed to `origin/main` (see AI_HANDOFF for the commit breakdown).

Hosted demo environment (session 60, unchanged): PXL Demo Trading Corporation with full company setup, master data, and items/operational seeds applied and verified; no posted transactions. Rerun order: `demo_company_setup_seed.sql` → `demo_master_data_seed.sql` → `demo_items_inventory_seed.sql` (all idempotent; see AI_HANDOFF for rerun mechanics).

## Known Boundaries

- **Unowned ATC/CAS work is confirmed broken and stays held out (user decision 2026-07-11):** `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, `027_cas_end_to_end_controls_test.sql` remain untracked, uncommitted, and NOT on hosted. Evidence: 00005's reservation-model rewrite of `fn_next_document_number` breaks previously-passing test 021 ("unresolved document-number reservation already exists"), and test 027 fails 15/30 with pgTAP parse errors. They must be finished (or discarded) before inclusion; a plain local `supabase db reset` WILL apply them because the files sit in `supabase/migrations/` — hold them out for verified runs.
- PXL-AUD-051 (document-code registry drift) remains Open; session 60's "fix AUD-051 next" prompt was superseded by session 61's DA-002/DA-004 work.
- Exact server rollback preview still requires a saved source; atomic cash/fixed-asset forms show a labeled client estimate.
- The CSP in `index.html` restricts local Supabase frontend access unless bypassed.

## Next Recommended Step

Session 61 is fully wrapped. Next: a dedicated retest/closure pass to decide PXL-DA-002/004/005/007 statuses on the deployed contracts, then PXL-AUD-051 or the remaining Criticals (PXL-DA-008, PXL-DA-009, PXL-DA-019). Separately, the unowned ATC/CAS work (00004/00005 + test 027) needs an owner to finish or discard it.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active; hard stops remain destructive data operations, weakened controls, spending, external legal/compliance actions, or missing credentials.
