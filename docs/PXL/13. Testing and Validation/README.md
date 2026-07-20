# PXL Testing and Validation Index

**Status:** Active domain index
**Authority:** Tier 2 Navigation; test output and executable tests retain authority over documentation summaries
**Last Reviewed:** 2026-07-18
**Applies To:** Canonical data, hosted/local validation, regression lanes, browser probes, and documentation checks
**Read When:** A task changes canonical data, validation scripts, test lanes, or evidence claims
**Do Not Read For:** Current product readiness unless `AI/AI_STATE.md` names this scope

## Current Authorities

| Need | Read |
| --- | --- |
| Production certification framework: how a module is certified | `docs/PXL/13. Testing and Validation/PXL_MODULE_CERTIFICATION_STANDARD.md` |
| Production certification framework: how a shared engine is certified | `docs/PXL/13. Testing and Validation/PXL_ENGINE_CERTIFICATION_STANDARD.md` |
| Pre-certification capability-expectation checklist (professional-user completeness) | `docs/PXL/13. Testing and Validation/PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` |
| Master Data implementation roadmap (bounded packages + execution order) | `docs/PXL/13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md` |
| Current module/engine certification status and next phase (dashboard only) | `docs/PXL/13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md` |
| Canonical demo dataset scope, counts, safety rules, and coverage limits | `docs/PXL/13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md` |
| Accounting test scenarios and Supabase test-file mapping | `../02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md` |
| Current operational next task and last verified command summary | `../../AI/AI_STATE.md` |

## Production Certification Program

The PXL Production Certification Program moves PXL from feature-complete development toward controlled production use. It is governed by four permanent authorities in this folder: the Module Certification Standard (module gates), the Engine Certification Standard (engine contracts and invariants), the Product Completeness Checklist (capability expectations run before certifying a module), and the Certification Matrix (status dashboard). Defects remain in `../PXL_END_TO_END_AUDIT_FINDINGS.md`; the current bounded task remains in `../../AI/AI_STATE.md`. Do not create per-module status documents or duplicate findings registers.

## Validation Commands

```bash
npm run docs:check
git diff --check
npm run test:transaction-workspace
npm run test:sales-invoice-draft-state
```

Run focused product tests named by the active finding before using broader lanes as evidence.
