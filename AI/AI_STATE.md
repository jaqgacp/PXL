# PXL AI State

**Current Date:** 2026-07-18
**Current Branch:** `main` (ahead of `origin/main` by 1 commit)
**Working Tree:** Dirty. It contains pre-existing product, migration, test, Phase 3, and documentation-governance changes plus the transaction-workspace density correction. Preserve all unrelated changes.
**Product Phase:** Permanent Transaction Workspace architecture and density correction implemented across the route inventory; accounting-core hardening and canonical-environment validation remain active.
**Environment:** Authorized non-production hosted project `bskjkogijpbhukjkagfj`; migration history is synchronized through `20260716000005`. The explicitly authorized hosted sample reset/rebuild completed on 2026-07-18. Do not reset or seed Supabase again without explicit approval.
**Product Readiness:** Internal QA/demo only. PXL is not production-ready while one Critical and five High findings remain active.

## Current Finding Standing

Generated from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **79 Retested Passed / 1 In Progress / 7 Open (87 total)**.

- Active Critical: `PXL-AUD-055`.
- Active High: `PXL-AUD-053` (In Progress), `PXL-AUD-059`, `PXL-AUD-061`, `PXL-AUD-063`, `PXL-AUD-066`.
- Immediate Medium: `PXL-AUD-067` because readiness wording can overstate scope.
- Deferred Medium: `PXL-AUD-060` login accessibility; retain as active, but do not displace security, CAS, or accounting-core work.

## Active Work Map

Use the central finding’s exact paths and validation commands. The recommended next task is `PXL-AUD-063`; the remaining active findings stay ordered above.

## Priority Summaries

### PXL-AUD-055 — Previously exposed service-role key

Problem: The frontend guard is green, but rotation of the previously exposed key is not externally confirmed.

Required outcome: An authorized operator rotates the key, confirms affected environments were updated, then reruns the secret/build checks before closure.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-055), the secret guard, and `package.json`.

### PXL-AUD-063 — Global BIR configuration write policy

Problem: Any authenticated user can write or delete global `bir_forms` and `bir_form_mappings` rows.

Required outcome: Preserve required reads, deny ordinary authenticated writes, and permit mutation only through an explicitly governed authority with audit evidence. The current page reads `ref_compliance_forms`, so do not invent a page dependency.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-063), [BIR fast routing](../docs/PXL/10.%20Compliance/README.md#fast-routing), the BIR setup migration/page, and role-policy test. Add a focused policy test.

### PXL-AUD-066 — Historical CAS evidence date semantics

Problem: CAS packages use event time for number/void evidence but document period for books/exports, omitting later-created historical evidence.

Required outcome: Resolve evidence by governed document date with a defined fallback for unbound allocations; require test 027 to pass 31/31.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-066), `supabase/migrations/20260710000005_cas_numbering_void_dat_controls.sql`, `supabase/tests/027_cas_end_to_end_controls_test.sql`. Validation: `supabase test db --local supabase/tests/027_cas_end_to_end_controls_test.sql`.

### PXL-AUD-053 — Sales Invoice completeness

Problem: Implemented SI fields and posting are not yet fully proven across missing dimensions and downstream view/report/API/export sources.

Required outcome: Do not expose invented masters or call the approved Form/View UX fully implemented; close one source-backed slice at a time.

Read first: [finding](../docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md#pxl-aud-053), `docs/PXL/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`, focused SI code and test 054. Validation: `npm run test:sales-invoice-draft-state` plus the scoped pgTAP test.

### PXL-AUD-059 / 061 — Coverage and deterministic lanes

Problem: 66 of 148 tables remain empty, and the green 56-file lane excludes the two real CAS failures in test 027.

Required outcome: Keep supported, deferred, and unexercised modules explicit; after AUD-066, require all 57 files / 1,045 assertions to pass before calling the full lane green.

Read first: their central findings, `docs/PXL/PXL_CANONICAL_DEMO_DATASET.md`, `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`, and Phase 3 scripts only when working this scope.

### PXL-AUD-067 — Checklist scope wording

Problem: Ten core-accounting checks can look like full operational readiness.

Required outcome: Label the result as core-accounting readiness and add separately governed operational sections later.

## Hosted and UX Status

The five canonical companies are present, and the designated hosted operator owns all five. ABC Trading now carries 50 customers, 40 suppliers, 42 items, 65 sales invoices, 31 purchase orders, and 31 vendor bills, including 60/30/30 editable high-volume drafts. Last recorded hosted automation passed 48/48 company/master/document probes and 20/20 report probes. Coverage remains 82 populated / 66 classified empty tables. These are evidence of the tested slice, not full ERP completeness. `PXL_TRANSACTION_WORKSPACE_STANDARD.md` is the sole transaction UI authority; Sales Invoice is one implementation. PXL-AUD-053 still governs its residual data-source/business completeness.

### Transaction workspace density correction — 2026-07-18

Result: **Complete for the requested UI ownership and density correction; business qualification remains source-gated**. The executable inventory covers 41 implemented surfaces. Thirty-two compatibility-composed surfaces now put their real bound document controls in the three-card band, real domain actions in the top header, and only the pattern detail grid in Lines. The nine direct workspaces follow the same ownership contract. Detailed Financial, GL, Tax, Validation, Approval, and Audit content lives only in its named tab.

The shared shell uses an 84px minimum header, 8px workspace rhythm, 12px card padding, 32px controls/tabs, approximately 30px data rows, a 240/256px sidebar, top-aligned grid items, and natural content heights. No CSS hides legacy duplicate markup; obsolete duplicate structures were removed. Browser evidence covers all 41 routes, 90/100/110/125% zoom, 1366/1440/1600/1920px widths, dark mode, and 22 inspected 90%/100% representative screenshots with zero runtime errors.

`PXL_TRANSACTION_WORKSPACE_STANDARD.md` and `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` remain the only current authorities. Domain save/post handlers, field mappings, tax/GL calculation, permissions, RLS, period locks, and immutability were preserved.

Non-SI rows remain `transaction-matrix-only`; UI completion does not qualify all
Field Source Matrices or accounting/tax outcomes. Cash Sale and Customer Return
use the resulting Sales Invoice/Credit Memo views; Asset Acquisition has no
separate saved-document view. These are model exceptions, not unmigrated pages.

### Defects Discovered During Transaction Workspace Density Correction

| Defect | Transactions | Severity | Status | Cause | Action / Evidence |
| --- | --- | --- | --- | --- | --- |
| Duplicate document header, Back action, and document fields in Lines | 32 compatibility-composed surfaces, visibly Cash Purchase | High | Fixed | Page-owned child bodies still contained a complete legacy form while the wrapper rendered summary cards | Removed the inner form/header and bound each domain field once in the three cards; source tests reject transaction-header classes and Back actions inside Lines. |
| Primary actions absent from the top header | Compatibility-composed surfaces | High | Fixed | The wrapper accepted no domain actions, leaving handlers only in legacy bodies | Added status-aware shared action configuration wired to existing cancel/save/submit/post/run handlers; 41/41 browser routes expose top actions. |
| Sparse or stretched content created large white panels | All surfaces; Sales Invoice exposed the final stretch | Medium | Fixed | Fixed/min heights, oversized padding, and one grid without `items-start` stretched main content to sidebar height | Removed arbitrary content heights, introduced shared density tokens, top-aligned the content grid, and added a bottom-whitespace screenshot assertion. |
| Detailed impact/history content appeared in Lines | Compatibility-composed commercial, cash, inventory, and schedule surfaces | Medium | Fixed | Legacy child bodies mixed lines with GL, totals, validation, and audit blocks | Moved detailed blocks into named tabs; Lines owns only its table/empty state and concise line controls. |
| Earlier visual checks passed visible inconsistency | Representative comparisons | Medium | Fixed | Checks measured route presence and broad geometry but not semantic duplication, action ownership, or natural content height | Browser checks now assert one header, three cards, top actions, Lines detail proximity, no GL detail in Lines, aligned sidebar, natural panel height, and runtime cleanliness at both 90% and 100%. |
| Non-SI Field Source Matrices remain unqualified | 40 non-SI implemented surfaces | High | Open / pre-existing governance gap | Existing Transaction Matrix defines the business surface, but transaction-specific field-source validation is not complete | Kept all non-SI rows explicitly `transaction-matrix-only`; no posting or tax rule was invented. No new formal finding because this is the already-governed product qualification gap, not a newly introduced rollout defect. |

## Known Blockers and Non-Assumptions

- External key rotation blocks closure of AUD-055.
- Project, Location, and Functional Entity masters are not governed for SI.
- Banking, fixed assets, returns, approvals, schedules, statutory generators, and CAS artifacts are not proven complete.
- Do not assume green checklists mean operational readiness, a rendered route means source-backed correctness, or archived phase reports are current status.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body for the next task.

## Last Verified Commands

Executed 2026-07-18: draft-state tests passed 4/4; workspace tests passed 11/11; authenticated workspaces passed 41/41; zoom checks passed 24/24 at 90/100/110/125%; viewport checks passed 24/24 at 1366/1440/1600/1920px; 22 representative screenshots passed semantic geometry checks and were inspected at 90%/100% with zero runtime errors. Lint, typecheck, production build, both frontend-secret scans, documentation checks, and `git diff --check` passed. The authorized canonical rebuild then passed local seeded tests 055/057/058 at 34/34, 38/38, and 16/16 plus hosted count/setup/reconciliation verification. Prior focused SI completeness evidence remains 22/22 and Phase 3 evidence remains 56 files / 1,014 passing with held-out test 027 failing 2 of 31.

## Recommended Next Task

Implement `PXL-AUD-063` only: replace the two broad global BIR `FOR ALL` policies with governed read/write policies in a new migration, add a focused pgTAP test, confirm the current read-only BIR reference page is unaffected, update the finding with executed evidence, and refresh this file. Do not change tax calculations, BIR report logic, unrelated RLS, transaction workspace UI, canonical data, or hosted state.
