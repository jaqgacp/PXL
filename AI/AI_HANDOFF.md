# AI Handoff

Last updated: 2026-07-10 (session 59)

## What Was Done

Closed PXL-AUD-002, PXL-AUD-006, and PXL-DA-001 (all Critical).

- Guided setup: `CompanySetupChecklist` aggregates ten legal/accounting/tax readiness areas with direct navigation. Readiness banners now return users to the checklist. SI/OR/VB/PV and CM/DM/cash sale/cash purchase/vendor credit enforce relevant setup before save/post; VAT/CWT/EWT mappings are conditional.
- VAT registration: migration `20260710000002_vat_registration_all_documents.sql` centralizes line/header registration, VAT direction, parent-company, and amount checks; cash sales inherit SI gates; CM/DM/VC tax detail is rebuilt per code; direct authenticated tax-ledger mutation is denied; VAT/CAS export entry points reject non-VAT companies.
- GL preview/trace: migration `20260710000003_posting_engine_preview_trace.sql` adds `ref_posting_source_types`, the JE source-type FK, fixed-asset/schedule/purchase-return source linking, exact rollback `fn_preview_gl_impact` (including operator-dated recurring runs), `fn_get_accounting_trace`, and central period/account/line/balance/idempotency guards. Internal JE primitives are revoked from application callers.
- UI: the shared GL panel/preflight covers core AR/AP, CM/DM/cash/CV, treasury, inventory, depreciation/schedules, recurring journals, purchase returns, manual JEs, and fixed-asset forms. `/accounting-trace` and core GL/TB/JE/ledger routes provide the DA-002 foundation.
- Status side effects: DA-002/004/005/007 and AUD-049 moved to In Progress; DA-006 moved to Retested Passed. Standing: 35 passed / 17 in progress / 18 open; five Criticals remain.

## Evidence

- Fresh `supabase db reset --local --version 20260710000003 --yes` passed.
- Full pgTAP suite: 448/448 across 25 files.
- `024_vat_registration_all_documents_test.sql`: 35/35.
- `025_posting_preview_invariants_test.sql`: 40/40.
- Build passed; lint passed with zero warnings.
- Types and scoped schema summary regenerated.
- Scoped Supabase dry-run listed only migrations 00002/00003; both pushed successfully. `supabase migration list --linked` verified local=remote through 00003.

## Do Not Accidentally Include

The working tree still contains unrelated user/other-agent work: `20260710000004_atc_document_date_versioning.sql`, `20260710000005_cas_numbering_void_dat_controls.sql`, and `027_cas_end_to_end_controls_test.sql`. Session 59 deliberately excluded all three from reset/deployment/generated summary/docs-consistency/Git scope.

## Exact Next Prompt

Continue AIQ-008 with PXL-DA-002: use the existing `fn_get_accounting_trace` and `/accounting-trace` contract to add report/compliance row drillback (financial statements, subledgers, VAT/WHT rows, 2307/QAP, and snapshots), add route tests, update the matrix/audit/test book, and do not include migrations 00004/00005 or test 027 unless explicitly taking ownership of that separate work.
