# AI Handoff

Last updated: 2026-07-12 (session 62: closed DA-002/004/008 and AUD-014; DA-005/007 retained for missing evidence)

## What Was Done

- Dedicated retest of deployed session-61 contracts:
  - **PXL-DA-002 -> Retested Passed:** canonical report source keys, fail-closed trace routing, immutable snapshot trace links, and membership-scoped trace sets cover financial, subledger/aging, VAT/WHT, 2307, and snapshot report families.
  - **PXL-DA-004 -> Retested Passed:** registry-backed source locks, common JE create/add/finalize, shared tax identity/writer, exact reversal, audit primitives, and compatibility-wrapped secondary writers form the common posting protocol.
  - **PXL-DA-005 stays In Progress:** implementation exists, but test 026's forged fixtures bypass triggers; add normal-trigger orphan and cross-company JE negatives.
  - **PXL-DA-007 stays In Progress:** locks and JE/tax uniqueness exist, but there is no genuine two-session post race.
- Fixed the next unblocked Critical, **PXL-DA-008**, and closed **PXL-AUD-014**:
  - Added `supabase/migrations/20260712000001_vat_amount_rpc_authority.sql`.
  - SI/VB/CM/DM/cash-purchase/vendor-credit headers/lines are RLS-read + RPC-write only for application roles; direct INSERT/UPDATE/DELETE/TRUNCATE grants and mutation policies are removed.
  - Review found an alternate bypass through automatically updatable SI/VB register views. Both views are now application-read-only and `security_invoker`, closing mutation and cross-company read bypasses.
  - Added VAT-AMOUNT-INTEGRITY-001 (`supabase/tests/028_vat_amount_integrity_test.sql`, 25 assertions): all six persisted VAT families ignore forged derived payloads; base/view DML and truncate fail; foreign-company register rows stay hidden; mixed SI/VB documents reconcile to per-code tax detail, GL VAT controls, and ledger-backed reviews.
  - Updated APPROVAL-SOD-001 because direct SI status changes now fail earlier at the stronger RPC-only table boundary.
- Updated findings/index/standing, test book, transaction matrix, product backlog/experience references, schema summary, and AI continuity files. Final standing: **40 Passed / 13 In Progress / 19 Open; two Criticals remain (DA-009, DA-019).**

## Evidence

- Fresh reset through `20260712000001` with held-out files excluded: clean.
- Full pgTAP: **499/499 across 27 owned files**; focused VAT/posting/trace: **173/173**.
- `npm run build` passed; `npm run lint` zero warnings.
- Types regenerated; schema summary: 187 functions / 19 views / 147 tables / 226 triggers.
- `scripts/check_docs_consistency.sh` green: 72 findings, 27 owned tests.
- Independent read-only review found the register-view bypass; revised migration/test re-review found no remaining defect.
- Hosted push is **PENDING**: linked dry-run failed because `SUPABASE_ACCESS_TOKEN` is not available. Hosted is still through `20260711000002`.
- Git commit/push not performed.

## Unowned ATC/CAS Work — Keep Held Out

`20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` remain untracked, broken, uncommitted, and off hosted per the user's 2026-07-11 decision. A normal reset/push will pick up 00004/00005 if they are left in place. Move all three aside, verify owned work, then restore them byte-for-byte. Migration 00005 breaks previously-green test 021; test 027 fails 15/30.

## Important AUD-051 Discovery

PXL-AUD-051 needs more than four registry rows and a DM readiness edit. Eight shipped fixed-asset/inventory functions call nonexistent `fn_next_document_number(company_id, code)` signatures. The held-out overload chooses an arbitrary branch and is not acceptable. The eventual fix must pass the correct branch at every caller, align FA/JE/PRT/SDM registry and series FKs, use DM-S consistently, realign the demo seed, and test a real FA/inventory path.

## Exact Next Prompt

Close PXL-DA-005 with normal-trigger orphan/cross-company JE assertions and PXL-DA-007 with a genuine two-session same-source posting race; decide both statuses and rerun the fresh full suite with unowned 00004/00005/test027 held out. Then fix PXL-AUD-051 completely, including branch-scoped repair of all eight broken two-argument numbering callers (do not use the held-out arbitrary-branch overload). Keep hosted push of `20260712000001` pending until `SUPABASE_ACCESS_TOKEN` is available.
