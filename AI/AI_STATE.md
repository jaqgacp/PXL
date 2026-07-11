# AI State

Last updated: 2026-07-10 (session 59)

## Project Status

PXL is a React 19 + TypeScript + Vite frontend backed by Supabase/PostgreSQL. Audit hardening is active under AIQ-008. The authoritative finding standing is **35 Retested Passed / 17 In Progress / 18 Open (70)**. Five Critical findings remain: PXL-DA-002, PXL-DA-004, PXL-DA-008, PXL-DA-009, and PXL-DA-019.

## Current Active Task

Session 59 closed the next three Criticals:

- **PXL-AUD-002:** Company Setup now has a live readiness checklist for legal profile, branch, fiscal calendar, COA, core number series, compliance/tax codes, and applicable GL mappings. Core and VAT-bearing transaction pages block save/post on relevant readiness gaps and link back to the checklist.
- **PXL-AUD-006:** `20260710000002_vat_registration_all_documents.sql` extends registration/direction/amount enforcement through CM/DM/cash sale/cash purchase/vendor credit and VAT exports, rebuilds CM/DM/VC tax detail per code, and denies authenticated direct tax-ledger mutation.
- **PXL-DA-001:** `20260710000003_posting_engine_preview_trace.sql` adds exact rollback GL preview, governed source types, source links, accounting trace, and central period/account/balance/source-idempotency guards. GL Impact/preflight is broadly deployed; atomic unsaved cash/fixed-asset forms show a labeled estimate.

The same work advanced PXL-DA-002/004/005/007 and PXL-AUD-049 to In Progress, and closed PXL-DA-006.

## Verification and Hosted State

- Fresh local replay through `20260710000003`: passed.
- pgTAP: **448/448 across 25 files**.
- VAT-REG-ALL-DOCS-001: 35 assertions passed.
- GL-PREVIEW-PARITY-001: 40 assertions passed.
- `npm run build`: passed.
- `npm run lint`: zero warnings, exit 0.
- Generated `src/lib/database.types.ts` and scoped `docs/PXL/PXL_SCHEMA_SUMMARY.md` refreshed.
- Hosted Supabase: migrations `20260710000002` and `20260710000003` pushed from a scoped workdir and verified local=remote through 00003. The known post-push pg-delta CA-cache warning occurred after successful application.

## Known Boundaries

- Unrelated local work remains uncommitted/unpublished: migrations `20260710000004`, `20260710000005`, and test `027_cas_end_to_end_controls_test.sql`. Session 59 excluded them from reset, deployment, schema-summary generation, docs-consistency evidence, and Git scope.
- Exact server rollback preview requires a saved source. Atomic create-and-post cash/fixed-asset forms use a clearly labeled client estimate until those RPCs gain input-payload dry-run contracts.
- PXL-DA-002 still needs financial statement, subledger, tax, certificate, and export-snapshot row adoption.
- PXL-DA-004/005/007 still need writer migration, shared tax/reversal primitives, physical source existence/company enforcement, source locking, tax-row uniqueness, and concurrency tests.
- The CSP in `index.html` restricts local Supabase frontend access unless bypassed.

## Next Recommended Step

Continue AIQ-008 with **PXL-DA-002** (finish report/compliance drillback using the new trace contract) or **PXL-DA-004** (complete posting-engine writer/tax/reversal/locking consolidation). PXL-DA-008, PXL-DA-009, and PXL-DA-019 remain parallel Critical lanes. Do not redo AUD-002, AUD-006, DA-001, or DA-006.

## Decisions Needed From User

None. DEC-008 standing autonomy remains active; hard stops remain destructive data operations, weakened controls, spending, external legal/compliance actions, or missing credentials.
