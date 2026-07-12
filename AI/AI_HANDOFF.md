# AI Handoff

Last updated: 2026-07-12 (session 64 — local verification complete; hosted/Git push pending)

## Work In Progress

The first PXL-DA-019 CAS/BIR slice is complete and verified locally; only the hosted/Git push remains. Delivered this session:

- `20260712000003_posting_runtime_repairs.sql` / test 031 (49 assertions): repaired the three schema-lint-surfaced deployed defects — source-warehouse branch for stock-transfer JE numbering (JE stays branch-unattributed); physical-count value kept derived on the immutable line/inventory transaction (no `variance_cost` column); explicit optional `vendor_bills.rr_id` FK validated by `fn_save_vendor_bill` (received + same company/supplier) and consumed by purchase-return completion.
- `20260712000004_cas_numbering_void_evidence.sql` / test 032 (25 assertions): immutable issuance/void evidence on the preserved three-argument branch-scoped allocator (no two-argument overload, no one-unresolved-reservation rule), `number_series` guard, atomic ATP exhaustion without counter drift, allocation/void triggers, an owner-proof `P0001` immutability trigger on void evidence, historical backfill, and `vw_cas_atp_usage`. Two initially-failing test-032 assertions were fixed in the migration during this session: void evidence now snapshots the pre-void `OLD` row (status `posted`), and a `BEFORE UPDATE/DELETE/TRUNCATE` trigger makes void evidence immutable even to the table owner.
- `VendorBillsPage` captures the optional receiving report; CAS Void Register / ATP Usage / Dashboard / Audit Report pages read the governed objects. README PostgreSQL-version/migration wording and disabled opt-in demo seeding were corrected. DEC-014 records the database-governed numbering/void-evidence decision.

## Recovery / Exact Next Step

Local verification is done (see `AI_STATE.md` Verification State: pgTAP 601/601 across 31 files, clean lint, green build/oxlint/docs-gate, regenerated types/schema summary). Remaining:

1. Commit the working tree. Untracked to add: `20260712000003`, `20260712000004`, tests `031`, `032`. Keep excluded and do **not** commit the user-owned broken drafts `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` (still held out per the 2026-07-11 decision).
2. Dry-run then push the two new migrations to linked project `bskjkogijpbhukjkagfj` (`supabase db push --linked`), verify local = remote parity, then record the hosted push and push `main`.
3. Re-run the held-out-safe verification only if further edits are made (move the three drafts aside byte-for-byte, reset, full pgTAP, schema lint, gen types/schema summary, build/lint, docs consistency, restore).

## Known Remaining DA-019 Boundary

The current CAS export RPC hashes frozen JSON rows, but the browser still serializes the downloaded CSV bytes. Exact exported-byte hashing and verified BIR DAT layout remain a later DA-019 slice; do not mark the full Critical finding closed after numbering/void evidence alone.
