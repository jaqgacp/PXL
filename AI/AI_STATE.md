# AI State

Last updated: 2026-07-12 (session 62: dedicated posting/trace closure retest and DA-008 VAT amount authority)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit hardening continues under AIQ-008. The authoritative standing is **40 Retested Passed / 13 In Progress / 19 Open (72)**. Two Critical findings remain: **PXL-DA-009** (withholding architecture) and **PXL-DA-019** (CAS/BIR readiness).

Session 62 closed PXL-DA-002, PXL-DA-004, PXL-DA-008, and PXL-AUD-014. PXL-DA-005 and PXL-DA-007 remain In Progress because their implementations are present but closure evidence is incomplete: normal-trigger orphan/cross-company JE negatives for DA-005, and a genuine two-session same-source posting race for DA-007.

## Current Active Task

Session 62 completed two AIQ-008 slices:

- **Dedicated retest:** `20260711000002` covers financial, subledger, VAT/WHT, 2307, and report-snapshot trace families, so DA-002 is Retested Passed. `20260711000001` supplies the common source-lock/create-add-finalize/tax/reversal/audit protocol for direct and compatibility-wrapped writers, so DA-004 is Retested Passed. DA-005/007 stayed open only for the evidence gaps above.
- **Next Critical (DA-008):** new `supabase/migrations/20260712000001_vat_amount_rpc_authority.sql` makes SI/VB/CM/DM/cash-purchase/vendor-credit headers and lines RPC-only for application mutations. It removes mutation policies and INSERT/UPDATE/DELETE/TRUNCATE grants while preserving RLS-scoped reads and SECURITY DEFINER save/lifecycle RPCs. It also closes a review-discovered bypass: automatically updatable `vw_sales_invoice_register`/`vw_vendor_bill_register` are application-read-only and `security_invoker`, so callers cannot forge VAT through a view or read another company through the view owner's RLS bypass.
- **Tests/docs:** new VAT-AMOUNT-INTEGRITY-001 (`supabase/tests/028_vat_amount_integrity_test.sql`, 25 assertions) proves forged payload fields are ignored across all six persisted VAT document families, base/view mutations are denied, register views are tenant-scoped, and mixed SI/VB amounts reconcile document -> tax ledger -> GL VAT controls -> VAT review. Test 014 now expects direct SI status mutation to fail at the stronger RPC-only boundary.

## Verification and Hosted State

Executed 2026-07-12 with the unowned ATC/CAS files held out:

- Fresh `supabase db reset --local` replay through `20260712000001`: clean.
- Full pgTAP: **499/499 across 27 owned test files**.
- Focused VAT/posting/trace set: **173/173**.
- `npm run build`: passed.
- `npm run lint`: zero warnings, exit 0.
- `npm run gen:types` and `scripts/gen_schema_summary.sh`: complete; schema summary remains 187 functions / 19 views / 147 tables / 226 triggers.
- `scripts/check_docs_consistency.sh`: green (72 findings, 27 owned test files).
- Hosted migration push: **PENDING**. `supabase db push --linked --dry-run` could not authenticate because `SUPABASE_ACCESS_TOKEN` is absent. Hosted remains synced only through `20260711000002`.
- Git commit/push: not performed in this session.

Hosted demo reference (unchanged): PXL Demo Trading Corporation has the session-60 setup/master/item seeds and no posted transactions. Local resets remove local demo seed data; rerun the three idempotent seeds in handoff order if needed.

## Known Boundaries

- **Unowned broken files remain excluded by user decision (2026-07-11):** `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql` are untracked and must be moved aside before reset/test/push. Migration 00005 breaks test 021 and test 027 fails 15/30. Do not absorb or deploy them implicitly.
- **PXL-AUD-051 is larger than its original note:** FA/JE/PRT/SDM registry rows and DM-S readiness still need repair, but eight shipped fixed-asset/inventory functions also call a nonexistent two-argument numbering overload. Fix those callers with the correct branch; do not adopt the held-out overload that chooses an arbitrary branch.
- PXL-DA-009 depends on safe ATC document-date/version work and the controlled remittance flow (PXL-AUD-041). PXL-DA-019 depends on document-code/numbering repair and CAS lifecycle work; its held-out draft remains broken.
- Exact server rollback preview still requires a saved source; atomic cash/fixed-asset forms show a labeled client estimate.

## Next Recommended Step

Close PXL-DA-005 with normal-trigger orphan/cross-company JE assertions and PXL-DA-007 with a true two-session posting race. Then fix PXL-AUD-051 completely (registry/code alignment, DM-S readiness, seed realignment, and branch-scoped repair of all eight two-argument numbering callers) to unblock PXL-DA-019.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active. Hosted push only needs the missing Supabase access token; record it as pending until credentials exist.
