# PXL BIR and Compliance Documentation Index

**Status:** Active domain index
**Authority:** Tier 2 Domain Navigation; Tier 1 accounting, transaction, security, and findings authorities prevail
**Last Reviewed:** 2026-07-18
**Applies To:** BIR configuration, VAT, EWT/CWT/FWT, percentage tax, income tax, books, forms, reports, CAS, tax identity, and tax setup
**Read When:** The active task is specifically BIR, tax, statutory reporting, CAS, or compliance configuration
**Do Not Read For:** Unrelated application, inventory, authentication, or transaction UI work

This folder contains BIR/compliance blueprints and tax setup specifications. A blueprint is not proof that its route, database generator, filing logic, export, RLS, or canonical data is complete. Implementation status comes from executed evidence, the transaction/accounting authorities, and the central findings register.

## Fast Routing

- **BIR RLS/configuration, including PXL-AUD-063:** read this index and `00. Tax Setup/01. BIR Form Configuration.md`. Then inspect only `src/pages/BIRFormConfigPage.tsx`, the named policies/migration, and focused RLS tests. The current page reads `ref_compliance_forms`, not the legacy `bir_forms` tables.
- **VAT:** start with `Tax Applicability Matrix.md` and `02. VAT/02. VAT Working Papers.md`. Governing posting and tax-ledger rules are in `../02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`; open a specific 2550/SLS/SLP/export blueprint only for that output.
- **EWT/CWT:** start with `Tax Applicability Matrix.md` and `03. Withholding Tax/02. EWT Working Papers.md`. Add `Form 2307 Management.md` only for certificate lifecycle and the exact QAP/SAWT/2307 blueprint only for that output.
- **CAS and books:** start with `06. Audit & CAS/10. CAS Audit Report.md`; add the exact BIR book specification needed. For PXL-AUD-066, go directly to the central finding and test 027 rather than reading the whole CAS folder.
- **TIN behavior:** read `docs/PXL/10. Compliance/PXL_PHILIPPINE_TIN_STANDARD.md`.
- **Forms and reports:** open only the exact form/report blueprint named by the task. Do not preload dashboards, adjacent returns, or exports.
- **Income tax:** the documents are planned/reference specifications with unproven canonical generators. Do not treat them as implemented or production-ready.

## Current Groups

| Group | Purpose | Status |
| --- | --- | --- |
| `00. Tax Setup/` | BIR form configuration, tax codes, VAT/EWT/FWT/PT codes, ATC codes, tax calendar | Current setup specifications; verify against implementation |
| `01. Percentage Tax/` | PT dashboard, working papers, 2551Q, reconciliation, register | Mixed current/planned blueprints |
| `02. VAT/` | VAT dashboard, working papers, summaries, returns, SLS/SLP, SLSP, RELIEF | Current compliance blueprints; generator evidence varies |
| `03. Withholding Tax/` | EWT/CWT/FWT working papers, returns, QAP/SAWT, 2307/2306 certificates | Current/planned withholding blueprints |
| `04. Income Tax/` | Taxable income, reconciliation, OSD, NOLCO, credits, 1701/1702 forms | Planned/unverified |
| `05. BIR Books/` | Statutory books and subsidiary ledgers | Current blueprints; exact evidence varies |
| `06. Audit & CAS/` | CAS dashboard, audit logs, DAT generation, audit package, export history | Current CAS/audit blueprints; PXL-AUD-066 still active |
| `Form 2307 Management.md` | 2307 lifecycle | Current implementation specification |
| `Tax Applicability Matrix.md` | Tax applicability routing | Current domain rule, subordinate to Tier 1 rules |
| `docs/PXL/10. Compliance/PXL_PHILIPPINE_TIN_STANDARD.md` | TIN format, storage, validation, display | Current tax identity standard |

## Merge and Cleanup Notes

Compliance files were not flattened. Output/Input VAT summaries still overlap report/catalog concepts, and Fixed Asset Register appears in BIR books plus fixed-asset/report contexts. Those remain owner-review merge candidates because BIR-layout and audit evidence requirements must be reconciled before any source file is retired.

Agents must not load the entire Compliance folder for PXL-AUD-063, PXL-AUD-066, or unrelated work.
