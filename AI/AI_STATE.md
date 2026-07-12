# AI State

Last updated: 2026-07-12 (session 63: closed PXL-DA-005 and PXL-DA-007 with executed writer-boundary and two-session race evidence)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit hardening continues under AIQ-008. The authoritative standing is **42 Retested Passed / 11 In Progress / 19 Open (72)**. Two Critical findings remain: **PXL-DA-009** (withholding architecture) and **PXL-DA-019** (CAS/BIR readiness).

Session 63 closed PXL-DA-005 and PXL-DA-007 — the two implementation-complete findings that were held open only for missing closure evidence. No schema or application code changed; the session added test evidence only.

## Current Active Task

Session 63 delivered two closure test slices:

- **PXL-DA-005 -> Retested Passed:** test 026 (now 29 assertions) adds writer-boundary negatives under normal trigger execution. `SET CONSTRAINTS trg_journal_entry_source_integrity IMMEDIATE` makes the real deferred JE source constraint fire at statement time: a posted JE referencing a live same-company SI is accepted; posted JEs referencing a nonexistent SI (orphan) or another company's SI are rejected by the actual trigger, not by forged reader fixtures.
- **PXL-DA-007 -> Retested Passed:** new `supabase/tests/029_posting_race_two_session_test.sql` (POSTING-RACE-001, 14 assertions) opens two real extra database sessions with dblink through the harness TCP endpoint (`inet_server_addr()`; loopback is trust-authenticated so dblink needs the scram path). Two sessions race `fn_post_sales_invoice` on one committed approved SI: the second session observably blocks on the governed `FOR UPDATE` source lock (`pg_stat_activity` wait state), resumes after the first commit as a governed no-op, and exactly one original JE/tax set survives with the SI linked to it. Sequential re-post is a no-op; duplicate JE/tax rows remain structurally impossible (`ux_journal_entries_live_source`, `ux_tde_vat_source_code`). The committed race fixture is pre-cleaned on entry and deleted on exit, so the test is rerunnable (verified back-to-back).

## Verification and Hosted State

Executed 2026-07-12 with the unowned ATC/CAS files held out and restored byte-for-byte afterward (checksums verified):

- Fresh `supabase db reset --local` replay through `20260712000001`: clean.
- Full pgTAP: **516/516 across 28 owned test files** (499 prior + 3 new in test 026 + 14 in test 029).
- Test 029 verified rerunnable back-to-back against a live database.
- `scripts/check_docs_consistency.sh`: green (72 findings, 28 owned test files).
- `npm run build` / `npm run lint`: not rerun — no frontend or migration source changed this session; session-62 state (build passed, zero lint warnings) stands.
- Schema summary unchanged (no migrations added): 187 functions / 19 views / 147 tables / 226 triggers.
- Hosted migration push: **DONE 2026-07-12**. User supplied the access token; `supabase db push --linked` applied `20260712000001` with the unowned 00004/00005 held out (dry-run confirmed only that one migration), and `supabase migration list --linked` shows local = remote through `20260712000001`.

Hosted demo reference (unchanged): PXL Demo Trading Corporation has the session-60 setup/master/item seeds and no posted transactions. Local resets remove local demo seed data; rerun the three idempotent seeds in handoff order if needed.

## Known Boundaries

- **Unowned broken files remain excluded by user decision (2026-07-11):** `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` are untracked and must be moved aside before reset/test/push/docs-gate. Migration 00005 breaks test 021 and test 027 fails 15/30. Do not absorb or deploy them implicitly.
- **Test 029 is local-harness-only by design:** it uses dblink with the local supabase credentials (postgres/postgres over the container TCP address). pgTAP is never run against hosted, so this is acceptable; keep it in mind if the harness transport ever changes.
- **PXL-AUD-051 is larger than its original note:** FA/JE/PRT/SDM registry rows and DM-S readiness still need repair, but eight shipped fixed-asset/inventory functions also call a nonexistent two-argument numbering overload. Fix those callers with the correct branch; do not adopt the held-out overload that chooses an arbitrary branch.
- PXL-DA-009 depends on safe ATC document-date/version work and the controlled remittance flow (PXL-AUD-041). PXL-DA-019 depends on document-code/numbering repair and CAS lifecycle work; its held-out draft remains broken.
- Exact server rollback preview still requires a saved source; atomic cash/fixed-asset forms show a labeled client estimate.

## Next Recommended Step

Fix PXL-AUD-051 completely: registry/code alignment (DM vs DM-S; JE/SDM/PRT/FA absent from the registry), DM-S readiness, demo-seed realignment, and branch-scoped repair of all eight two-argument `fn_next_document_number` callers (never the held-out arbitrary-branch overload). That unblocks PXL-DA-019. PXL-DA-009 remains blocked on safe ATC date/version work plus PXL-AUD-041.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active. Hosted push is complete; no credentials are outstanding.
