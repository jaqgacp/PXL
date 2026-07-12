# AI Handoff

Last updated: 2026-07-12 (session 63: closed DA-005/007 with executed evidence; no code changes)

## What Was Done

- **PXL-DA-005 -> Retested Passed** (test 026, now 29 assertions): added writer-boundary negatives under normal trigger execution. `SET CONSTRAINTS trg_journal_entry_source_integrity IMMEDIATE` fires the real deferred JE source constraint at statement time: live same-company source accepted; orphan source and cross-company source both rejected by the actual trigger. Two extra unlinked SI fixtures (one per company) support these without colliding with `ux_journal_entries_live_source`.
- **PXL-DA-007 -> Retested Passed** (new `supabase/tests/029_posting_race_two_session_test.sql`, POSTING-RACE-001, 14 assertions): a genuine two-database-session race. dblink opens two real sessions through the harness TCP endpoint — connection string built from `inet_server_addr()`/`inet_server_port()` because loopback is trust-authenticated and dblink refuses passwordless non-superuser connections; the container address uses scram. Session A posts a committed approved SI inside an open transaction; session B's identical post observably blocks (`pg_stat_activity` `Lock` wait), then resumes after A commits as a governed no-op. Exactly one original JE/tax set survives; sequential re-post is a no-op; duplicate JE/tax rows are structurally impossible. The committed fixture company is pre-cleaned on entry (dynamic delete over every base table with `company_id`, under `SET session_replication_role = replica` issued as a statement — `set_config()` is denied by supautils) and deleted on exit; rerunnable back-to-back.
- Updated findings index + detail rows + session log (session 63), test book (ACCOUNTING-TRACE-REPORTS-001 to 29 assertions with the new step; new POSTING-RACE-001 section), and AI continuity files. Final standing: **42 Passed / 11 In Progress / 19 Open; two Criticals remain (DA-009, DA-019).**

## Evidence

- Fresh reset through `20260712000001` with held-out files excluded: clean.
- Full pgTAP: **516/516 across 28 owned files** (499 prior + 3 + 14 new).
- Test 029 run twice back-to-back: 14/14 both times (pre-clean works).
- `scripts/check_docs_consistency.sh` green: 72 findings, 28 owned tests (run with held-out test 027 moved aside, then restored; checksums verified byte-for-byte).
- Build/lint not rerun: no frontend or migration source changed; session-62 results stand.
- Hosted push **DONE 2026-07-12** (user supplied token): dry-run listed only `20260712000001`, push applied it, `supabase migration list --linked` shows local = remote through `20260712000001`. Held-out 00004/00005 were moved aside for the push and restored byte-for-byte (checksums verified).

## Unowned ATC/CAS Work — Keep Held Out

`20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` remain untracked, broken, uncommitted, and off hosted per the user's 2026-07-11 decision. A normal reset/push picks up 00004/00005 if left in place, and the docs gate flags 027. Move all three aside, verify owned work, then restore byte-for-byte. Migration 00005 breaks previously-green test 021; test 027 fails 15/30.

## Important AUD-051 Discovery (unchanged)

PXL-AUD-051 needs more than four registry rows and a DM readiness edit. Eight shipped fixed-asset/inventory functions call nonexistent `fn_next_document_number(company_id, code)` signatures. The held-out overload chooses an arbitrary branch and is not acceptable. The eventual fix must pass the correct branch at every caller, align FA/JE/PRT/SDM registry and series FKs, use DM-S consistently, realign the demo seed, and test a real FA/inventory path.

## Exact Next Prompt

Fix PXL-AUD-051 completely: reconcile document-code drift between `ref_document_types`, UI readiness codes, and RPC numbering codes (DM vs DM-S; JE/SDM/PRT/FA absent from the registry; FA numbering not configurable); repair all eight broken two-argument `fn_next_document_number` callers with the correct branch passed explicitly (do not use the held-out arbitrary-branch overload); realign the demo seed; add a real FA/inventory numbering test. Verify with a fresh reset and full suite with unowned 00004/00005/test 027 held out. Keep hosted push of `20260712000001` pending until `SUPABASE_ACCESS_TOKEN` is available.
