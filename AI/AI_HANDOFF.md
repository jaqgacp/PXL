# AI Handoff

Last updated: 2026-07-11 (session 61 recovery: reconstructed the interrupted session, fixed one migration defect, verified, deployed to hosted, committed and pushed — all user-directed)

## What Was Done

Session 61 (interrupted) had implemented AIQ-008 work for **PXL-DA-002** (report/compliance drillback) and **PXL-DA-004/005/007** (posting-engine completion) but never reached wrap-up. The recovery session finished it:

- **`supabase/migrations/20260711000001_posting_engine_completion.sql`**: registry-backed `fn_resolve_posting_source` (resolution + `FOR UPDATE` locking + deferred-JE integrity); shared tax writer with stable source-line identity and safe uniqueness; shared posting/reversal audit and exact-opposite reversal mutation primitive; core AR/AP writers migrated to create/add/finalize + shared tax writer (public signatures unchanged); core reversal paths and secondary saved-source writers on the shared primitives; helpers revoked from application callers.
- **`supabase/migrations/20260711000002_accounting_trace_reports.sql`**: canonical `source_doc_type`/`source_doc_id` appended to `vw_customer_ledger`, `vw_supplier_ledger`, `vw_output_vat_review`, `vw_input_vat_review`, `vw_ewt_summary_ap`, `vw_cwt_summary_ar`; fail-closed `fn_get_accounting_trace` routing to the generic read-only `/accounting-source` page; internal `fn_normalize_report_source_type`; read-only `fn_get_report_snapshot_trace_links`; membership-scoped `fn_get_report_trace_set`.
- **UI**: `src/lib/accountingTrace.ts`, `AccountingTraceLink.tsx`, `AccountingSourcePage.tsx` (+ route); `AccountingTracePage` report-family trace sets; drillback adopted across ~20 report/compliance pages (GL, account detail ledger, BS/IS/SCF/SCE/comparative, AP/AR aging, VAT summaries/review, SAWT, QAP, 2307 issued/received, report snapshots).
- **Recovery fix**: the interrupted migration draft referenced `v_ref.date_column`; the real column is `document_date_column` (`20260710000003`). Fixed in `fn_resolve_posting_source` (two lines). The bug was masked on the live DB because session 61 had applied a corrected version ad hoc; only fresh-reset replay exposed the broken file.
- **Docs**: test book entry ACCOUNTING-TRACE-REPORTS-001 (test 026); session-61 row appended to the audit findings session log; finding statuses deliberately unchanged (DA-002/004/005/007 remain In Progress pending a dedicated retest pass); types and scoped schema summary regenerated.

## Evidence

- Fresh `supabase db reset` through `20260711000002` (unowned 00004/00005 and test 027 held out): clean.
- Full pgTAP: **474/474 across 26 files** (025 updated for the generic source route, 40/40; new 026, 26/26, includes fail-closed orphan/cross-company trace fixtures).
- `npm run build` passed; `npm run lint` zero warnings; `scripts/check_docs_consistency.sh` green (72 findings, 26 test files).
- Hosted push: `supabase db push --linked` dry-run listed exactly `20260711000001/2`; push applied them; `supabase migration list --linked` shows local=remote through `20260711000002`; remote probe confirms `fn_resolve_posting_source`, `fn_get_report_trace_set`, `fn_get_report_snapshot_trace_links` exist. Known benign post-push pg-delta CA-cache warning recurred.
- Git: sessions 59–61 committed (three logical commits: session-59 staged work; session-60 seeds/DEC-013/AUD-052; session-61 posting/trace work + recovery) and pushed to `origin/main`.

## Unowned ATC/CAS Work — Confirmed Broken, Held Out (user decision 2026-07-11)

`20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` remain on disk, untracked, uncommitted, and NOT on hosted. Evidence gathered this session: with them applied, previously-passing test 021 fails (00005's reservation-model `fn_next_document_number` raises "unresolved document-number reservation already exists for CS") and their own test 027 fails 15/30 with pgTAP parse errors. The user was shown this and chose to push only the verified pair. **Warning:** a plain local `supabase db reset` applies them because the files sit in `supabase/migrations/` — hold them out (move aside, reset, restore) for any verified run, exactly as this session did.

## Session 60 Reference (unchanged, still relevant)

- Hosted demo environment: **PXL Demo Trading Corporation** with green Company Setup Checklist, master data (5 payment terms / 5 customers / 5 suppliers), items/operational data (10 items, warehouses, banks, employees, petty cash, FA categories). No posted transactions; no stock balances by design. Note: local resets this session wiped local seed data — rerun the seeds locally if needed.
- Rerun seeds in order (all idempotent): `demo_company_setup_seed.sql` → `demo_master_data_seed.sql` → `demo_items_inventory_seed.sql`. Local: `docker exec -i supabase_db_PXL psql -U postgres -d postgres < supabase/seeds/<file>`. Hosted: POST as `{"query": ...}` to `https://api.supabase.com/v1/projects/bskjkogijpbhukjkagfj/database/query` with the management token, or the SQL editor.
- PXL-AUD-051 (document-code registry drift: DM vs DM-S readiness/numbering; JE/SDM/PRT/FA absent from `ref_document_types`) remains **Open**.

## Exact Next Prompt

Run a dedicated retest/closure pass for PXL-DA-002/004/005/007 against the deployed `20260711000001/2` contracts and decide their statuses in the Findings Status Index (rerun `scripts/check_docs_consistency.sh` after any status change). Then pick up PXL-AUD-051 (registry rows + DM readiness code + pgTAP registry assertion + seed alias realignment) or the remaining Criticals DA-008/DA-009/DA-019. Keep unowned migrations 00004/00005 and test 027 held out of resets, tests, hosted pushes, and Git until someone explicitly takes ownership and fixes them (test 021 must pass again with them applied before they can ship).
