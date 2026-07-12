# AI State

Last updated: 2026-07-12 (session 63: closed PXL-DA-005, PXL-DA-007, and PXL-AUD-051)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit hardening continues under AIQ-008. The authoritative standing is **43 Retested Passed / 11 In Progress / 18 Open (72)**. Two Critical findings remain: **PXL-DA-009** (withholding architecture) and **PXL-DA-019** (CAS/BIR readiness) — DA-019 is now unblocked by the AUD-051 numbering fix.

Session 63 closed three findings. First PXL-DA-005 and PXL-DA-007 (implementation-complete, held open only for missing closure evidence — test evidence added, no code change). Then PXL-AUD-051 (document-code/numbering drift), which required a real migration and unblocks DA-019.

## Current Active Task

Session 63 delivered two closure test slices:

- **PXL-DA-005 -> Retested Passed:** test 026 (now 29 assertions) adds writer-boundary negatives under normal trigger execution. `SET CONSTRAINTS trg_journal_entry_source_integrity IMMEDIATE` makes the real deferred JE source constraint fire at statement time: a posted JE referencing a live same-company SI is accepted; posted JEs referencing a nonexistent SI (orphan) or another company's SI are rejected by the actual trigger, not by forged reader fixtures.
- **PXL-DA-007 -> Retested Passed:** new `supabase/tests/029_posting_race_two_session_test.sql` (POSTING-RACE-001, 14 assertions) opens two real extra database sessions with dblink through the harness TCP endpoint (`inet_server_addr()`; loopback is trust-authenticated so dblink needs the scram path). Two sessions race `fn_post_sales_invoice` on one committed approved SI: the second session observably blocks on the governed `FOR UPDATE` source lock (`pg_stat_activity` wait state), resumes after the first commit as a governed no-op, and exactly one original JE/tax set survives with the SI linked to it. Sequential re-post is a no-op; duplicate JE/tax rows remain structurally impossible (`ux_journal_entries_live_source`, `ux_tde_vat_source_code`). The committed race fixture is pre-cleaned on entry and deleted on exit, so the test is rerunnable (verified back-to-back).

## Verification and Hosted State

Executed 2026-07-12 with the unowned ATC/CAS files held out and restored byte-for-byte afterward (checksums verified):

- Fresh `supabase db reset --local` replay through `20260712000002`: clean.
- Full pgTAP: **527/527 across 29 owned test files** (516 prior + 11 in new test 030).
- Test 029 verified rerunnable back-to-back against a live database.
- `npm run build` passed; `npm run lint` zero warnings (frontend touched: `DebitMemosPage` readiness code).
- Schema summary regenerated: **192 functions** / 19 views / 147 tables / 226 triggers. The count rose from 187 because the five inventory `_source_locked_impl` helpers are now captured (my migration defines them with `public.`-qualified names the generator indexes); no new functions or overloads were created.
- Demo seed idempotent on fresh DB (28 active number series after realignment).
- `scripts/check_docs_consistency.sh`: green (72 findings, 29 owned test files; run with test 027 held out, then restored).
- Hosted migration push: **DONE 2026-07-12** through `20260712000002`. Pushed with 00004/00005 held out (dry-run listed only `20260712000002`); `supabase migration list --linked` shows local = remote through `20260712000002` and a follow-up dry-run reports "Remote database is up to date". (A non-fatal `pgdelta catalog` cache warning printed after apply — a CLI cert-cache quirk, not a migration failure; verified by the up-to-date check.)

Hosted demo reference (unchanged): PXL Demo Trading Corporation has the session-60 setup/master/item seeds and no posted transactions. Local resets remove local demo seed data; rerun the three idempotent seeds in handoff order if needed.

## Known Boundaries

- **Unowned broken files remain excluded by user decision (2026-07-11):** `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` are untracked and must be moved aside before reset/test/push/docs-gate. Migration 00005 breaks test 021 and test 027 fails 15/30. Do not absorb or deploy them implicitly.
- **Test 029 is local-harness-only by design:** it uses dblink with the local supabase credentials (postgres/postgres over the container TCP address). pgTAP is never run against hosted, so this is acceptable; keep it in mind if the harness transport ever changes.
- **PXL-AUD-051 is closed** (session 63): registry rows JE/FA/SDM/PRT added, DebitMemosPage reads DM-S, and all eight fixed-asset/inventory callers pass the correct branch to `fn_next_document_number`. The held-out arbitrary-branch overload was not used. Registry retains near-duplicate purchasing codes (SDM/DM-P, PRT/PR) and unconsumed accounting codes (JV/RJV) — cosmetic cleanup only.
- PXL-DA-009 depends on safe ATC document-date/version work and the controlled remittance flow (PXL-AUD-041). PXL-DA-019 (CAS lifecycle) is now unblocked on numbering by AUD-051, but its held-out draft migration (00005) remains broken and off-limits.
- Exact server rollback preview still requires a saved source; atomic cash/fixed-asset forms show a labeled client estimate.

## Next Recommended Step

Tackle Critical PXL-DA-019 (CAS/BIR readiness end-to-end: immutable numbering, void register, books reconciliation, DAT export provenance) now that numbering is registry-consistent and hosted is current — but design fresh; do not adopt the broken held-out 00005. Alternatively advance PXL-DA-009 dependencies (safe ATC date/version, PXL-AUD-041 remittance flow).

## Decisions Needed From User

None. DEC-008 standing autonomy remains active. Hosted is fully synced through `20260712000002`; no push is outstanding.
