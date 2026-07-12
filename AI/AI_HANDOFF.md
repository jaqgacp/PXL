# AI Handoff

Last updated: 2026-07-12 (session 63: closed DA-005, DA-007, and AUD-051)

## What Was Done

- **PXL-DA-005 -> Retested Passed** (test 026, now 29 assertions): writer-boundary negatives under normal trigger execution via `SET CONSTRAINTS trg_journal_entry_source_integrity IMMEDIATE` — live same-company source accepted; orphan and cross-company sources rejected by the real trigger.
- **PXL-DA-007 -> Retested Passed** (new `supabase/tests/029_posting_race_two_session_test.sql`, 14 assertions): a genuine two-database-session race via dblink. Session B observably blocks on the `FOR UPDATE` source lock, then resumes as a governed no-op; exactly one JE/tax set survives. Committed fixture is pre-cleaned/removed so it is rerunnable.
- **PXL-AUD-051 -> Retested Passed** (new migration `20260712000002_aud051_numbering_registry_alignment.sql`, new test `030`): document-code/numbering reconciliation.
  - Added governed rows `JE`, `FA`, `SDM`, `PRT` to `ref_document_types` (Option A: smallest blast radius, keeps existing hosted/demo series valid — every code shipped functions request now exists).
  - Fixed `src/pages/DebitMemosPage.tsx` readiness code `DM` → `DM-S` (its `fn_save_debit_memo` numbering code; `DM-S` already governed).
  - Branch-scoped repair of all eight fixed-asset/inventory callers of the nonexistent two-argument `fn_next_document_number`. Each now passes the branch it already writes onto its journal_entries row: `fn_register_fixed_asset` (v_branch_id, for both FA and JE), `fn_dispose_fixed_asset`/`fn_record_impairment`/`fn_post_depreciation_entry_source_locked_impl` (v_asset.branch_id), and the four inventory posters (v_adj/v_tx/v_gi/v_cs.branch_id). The held-out arbitrary-branch overload from `20260710000005` was deliberately NOT used. Function bodies were captured from the deployed definitions via `pg_get_functiondef` and edited with a single precise callsite change each (CREATE OR REPLACE preserves the existing owner-only ACLs).
  - Realigned `supabase/seeds/demo_company_setup_seed.sql`: each series points at its own governed type and an FA series is added (28 series total).
  - New test 030 (DOCUMENT-NUMBERING-REGISTRY-001, 11 assertions): mechanical guard that every requested code is registry-backed, structural guard that no two-argument caller remains, and a real `fn_register_fixed_asset` path drawing governed FA + JE numbers, posting a balanced acquisition JE, and linking it back as an FA source.
- Updated findings index/detail/session log, test book, transaction matrix (Number Series row), and AI continuity files. Final standing: **43 Passed / 11 In Progress / 18 Open; two Criticals remain (DA-009, DA-019 — DA-019 now unblocked on numbering).**

## Evidence

- Fresh `supabase db reset --local` through `20260712000002` with held-out files excluded: clean.
- Full pgTAP: **527/527 across 29 owned files**.
- `npm run build` passed; `npm run lint` zero warnings.
- Schema summary regenerated: 192 functions / 19 views / 147 tables / 226 triggers (rose from 187 because the five inventory `_source_locked_impl` helpers are now captured; no new functions/overloads).
- Demo seed idempotent on fresh DB (28 active series).
- `scripts/check_docs_consistency.sh` green: 72 findings, 29 owned tests (run with test 027 held out, then restored; checksums verified).
- Hosted push: `20260712000001` DONE (local = remote). **`20260712000002` PENDING** — token is available this session; push with 00004/00005 held out.

## Unowned ATC/CAS Work — Keep Held Out

`20260710000004`, `20260710000005`, and `027_cas_end_to_end_controls_test.sql` remain untracked, broken, and off hosted per the user's 2026-07-11 decision. Move aside for reset/test/push/docs-gate, restore byte-for-byte. Migration 00005 breaks test 021; test 027 fails 15/30. DA-019 must be built fresh, not on 00005.

## Exact Next Prompt

Push `20260712000002_aud051_numbering_registry_alignment.sql` to hosted: hold out `20260710000004/00005`, run `SUPABASE_ACCESS_TOKEN=<token> supabase db push --linked` (dry-run first — it should list only that migration), verify with `supabase migration list --linked`, restore the held-out files. Then start Critical **PXL-DA-019** (CAS/BIR readiness: immutable document numbering, void register + reason, immutable books reconciliation, ATP/permit metadata, DAT/audit-package export provenance from posted ledgers) — design it fresh; do NOT adopt the broken held-out 00005. Numbering is now registry-consistent (AUD-051), so CAS numbering can build on the governed `fn_next_document_number(company, branch, code)` contract.
