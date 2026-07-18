# PXL BIR and Compliance Documentation Index

**Status:** Active domain index
**Authority:** Tier 2 Domain Navigation; it does not override Tier 1 accounting, tax, transaction, security, or findings authority
**Last Verified:** 2026-07-17
**Applies To:** BIR configuration, VAT, withholding, percentage tax, income tax, books, forms, reports, and CAS
**Read When:** The active task is specifically BIR or compliance related
**Do Not Read For:** Unrelated application, inventory, authentication, or Sales Invoice UX work

This folder contains 68 domain blueprints plus this index. A blueprint describes the intended screen, report, or form; its presence does not prove that its route, database generator, filing logic, export, RLS, or canonical data is complete. Implementation status comes from executed evidence and the central findings register.

## Fast Routing

- **BIR RLS/configuration, including PXL-AUD-063:** read this index and `docs/PXL/02. Setup/05. Tax Setup/01. BIR Form Configuration.md`. Then inspect only `src/pages/BIRFormConfigPage.tsx`, the named policies/migration, and focused RLS tests. The current page reads `ref_compliance_forms`, not the legacy `bir_forms` tables.
- **VAT:** start with `Tax Applicability Matrix.md` and `02. VAT/02. VAT Working Papers.md`. Governing posting and tax-ledger rules are in `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md`; open a specific 2550/SLS/SLP/export blueprint only for that output.
- **EWT/CWT:** start with `Tax Applicability Matrix.md` and `03. Withholding Tax/02. EWT Working Papers.md`. Add `Form 2307 Management.md` only for certificate lifecycle and the exact QAP/SAWT/2307 blueprint only for that output.
- **CAS and books:** start with `06. Audit & CAS/10. CAS Audit Report.md`; add the exact BIR book specification needed. For PXL-AUD-066, go directly to the central finding and test 027 rather than reading the whole CAS folder.
- **Forms and reports:** open only the exact form/report blueprint named by the task. Do not preload dashboards, adjacent returns, or exports.
- **Income tax:** the documents are planned/reference specifications with unproven canonical generators. Do not treat them as implemented or production-ready.

## Inventory

Status vocabulary: **Current spec** means retained implementation/reference specification, not proof of completion. **Planned/unverified** means future-looking or unsupported by current canonical evidence. **Merge candidate** means overlap exists, but no merge is approved until unique requirements and links are reconciled.

| File | Purpose / Classification | Status | Read When | Superseded By | Action |
| --- | --- | --- | --- | --- | --- |
| `Tax Applicability Matrix.md` | Governing domain rule: tax applicability routing | Current spec; subordinate to Tier 1 rules | Determining applicable PH tax families | — | Keep and Update |
| `Form 2307 Management.md` | Current implementation specification: 2307 lifecycle | Current spec; verify against findings | Working on issued/received 2307 | — | Keep and Update |
| `01. Percentage Tax/01. PT Dashboard.md` | Current report/workspace specification | Current spec; generator coverage unverified | PT overview UI only | — | Keep |
| `01. Percentage Tax/02. PT Working Papers.md` | Current report/form specification | Current spec; source coverage unverified | PT working-paper calculation | — | Keep |
| `01. Percentage Tax/03. PT Quarterly Return 2551Q.md` | Current form specification | Current spec; filing evidence unverified | 2551Q output only | — | Keep |
| `01. Percentage Tax/04. PT Reconciliation.md` | Current reconciliation specification | Current spec; execution unverified | PT-to-GL reconciliation | — | Keep |
| `01. Percentage Tax/05. PT Summary Register.md` | Current report specification | Current spec; source coverage unverified | PT transaction register | — | Keep |
| `02. VAT/01. VAT Dashboard.md` | Current report/workspace specification | Current spec; not a VAT rule source | VAT overview UI only | — | Keep |
| `02. VAT/02. VAT Working Papers.md` | Current implementation specification | Current spec; Tier 1 rules prevail | VAT working-paper sources/calculation | — | Keep and Update |
| `02. VAT/03. Output VAT Summary.md` | Current report specification | Current spec; overlaps Reports tree | Output VAT report | — | Merge Candidate |
| `02. VAT/04. Input VAT Summary.md` | Current report specification | Current spec; overlaps Reports tree | Input VAT report | — | Merge Candidate |
| `02. VAT/05. VAT Reconciliation.md` | Current reconciliation specification | Current spec | VAT ledger-to-GL reconciliation | — | Keep |
| `02. VAT/06. VAT Return 2550M.md` | Current/legacy form blueprint | Statutory currency not verified here | Task explicitly targets 2550M | — | Keep and Update |
| `02. VAT/07. VAT Return 2550Q.md` | Current form specification | Current spec; filing evidence unverified | 2550Q output | — | Keep |
| `02. VAT/08. SLS.md` | Current report/export specification | Current spec | Summary List of Sales | — | Keep |
| `02. VAT/09. SLP.md` | Current report/export specification | Current spec | Summary List of Purchases | — | Keep |
| `02. VAT/10. SLSP Export.md` | Current export specification | Current spec; exact-format evidence required | SLSP export only | — | Keep |
| `02. VAT/11. RELIEF Export.md` | Current export specification | Current spec; exact-format evidence required | RELIEF export only | — | Keep |
| `03. Withholding Tax/01. WT Dashboard.md` | Current report/workspace specification | Current spec; not a tax rule source | Withholding overview UI | — | Keep |
| `03. Withholding Tax/02. EWT Working Papers.md` | Current implementation specification | Current spec; Tier 1 rules prevail | EWT/CWT working-paper behavior | — | Keep and Update |
| `03. Withholding Tax/03. EWT Payable Summary.md` | Current report specification | Current spec | AP-side EWT payable | — | Keep |
| `03. Withholding Tax/04. EWT Receivable Summary.md` | Current report specification | Current spec | AR-side CWT receivable | — | Keep |
| `03. Withholding Tax/05. ATC Summary.md` | Current reference/report specification | Current spec | ATC reporting | — | Keep |
| `03. Withholding Tax/06. 1601EQ Working Papers.md` | Current report/form specification | Current spec; generator evidence required | 1601EQ working papers | — | Keep |
| `03. Withholding Tax/07. 1601EQ Quarterly Return.md` | Current form specification | Current spec; filing evidence required | 1601EQ return | — | Keep |
| `03. Withholding Tax/08. QAP.md` | Current export/report specification | Current spec; immutable snapshot rules apply | QAP only | — | Keep |
| `03. Withholding Tax/09. SAWT.md` | Current export/report specification | Current spec; immutable snapshot rules apply | SAWT only | — | Keep |
| `03. Withholding Tax/10. 2307 Certificates Issued.md` | Current form/report specification | Current spec | Issued 2307 | — | Keep |
| `03. Withholding Tax/11. 2307 Certificates Received.md` | Current form/report specification | Current spec | Received 2307 | — | Keep |
| `03. Withholding Tax/12. 2306 Certificates.md` | Current form/report specification | Current spec; coverage unverified | 2306 only | — | Keep |
| `03. Withholding Tax/13. Final Withholding Tax/01. FWT Working Papers.md` | Current/planned implementation specification | Planned/unverified canonical flow | FWT working papers | — | Keep |
| `03. Withholding Tax/13. Final Withholding Tax/02. 1601FQ Working Papers.md` | Current/planned form specification | Planned/unverified canonical flow | 1601FQ working papers | — | Keep |
| `03. Withholding Tax/13. Final Withholding Tax/03. 1601FQ Quarterly Return.md` | Current/planned form specification | Planned/unverified canonical flow | 1601FQ return | — | Keep |
| `04. Income Tax/01. Income Tax Dashboard.md` | Future/planned workspace specification | Planned/unverified | Income-tax overview task | — | Keep |
| `04. Income Tax/02. Taxable Income Computation.md` | Future/planned calculation specification | Planned/unverified | Taxable-income computation | — | Keep |
| `04. Income Tax/03. Book-to-Tax Reconciliation.md` | Future/planned reconciliation specification | Planned/unverified | Book-to-tax work | — | Keep |
| `04. Income Tax/04. OSD Computation.md` | Future/planned calculation specification | Planned/unverified | OSD task | — | Keep |
| `04. Income Tax/05. NOLCO Schedule.md` | Future/planned schedule specification | Planned/unverified | NOLCO task | — | Keep |
| `04. Income Tax/06. Tax Credits Schedule.md` | Future/planned schedule specification | Planned/unverified | Income-tax credits | — | Keep |
| `04. Income Tax/07. Individual (Sole Proprietor)/01. 1701Q Quarterly ITR.md` | Future/planned form specification | Planned/unverified | 1701Q task | — | Keep |
| `04. Income Tax/07. Individual (Sole Proprietor)/02. 1701 Annual ITR.md` | Future/planned form specification | Planned/unverified | 1701 annual task | — | Keep |
| `04. Income Tax/08. Corporate - OPC - Partnership/01. 1702Q Quarterly ITR.md` | Future/planned form specification | Planned/unverified | 1702Q task | — | Keep |
| `04. Income Tax/08. Corporate - OPC - Partnership/02. 1702RT Annual ITR.md` | Future/planned form specification | Planned/unverified | 1702RT task | — | Keep |
| `04. Income Tax/08. Corporate - OPC - Partnership/03. MCIT Computation.md` | Future/planned calculation specification | Planned/unverified | MCIT task | — | Keep |
| `05. BIR Books/01. Books Dashboard.md` | Current report/workspace specification | Current spec; exact book evidence varies | Books overview UI | — | Keep |
| `05. BIR Books/02. General Journal.md` | Current BIR book specification | Current spec | General Journal book | — | Keep |
| `05. BIR Books/03. General Ledger Book.md` | Current BIR book specification | Current spec | General Ledger book | — | Keep |
| `05. BIR Books/04. Cash Receipts Book.md` | Current BIR book specification | Current spec | Cash Receipts book | — | Keep |
| `05. BIR Books/05. Cash Disbursements Book.md` | Current BIR book specification | Current spec | Cash Disbursements book | — | Keep |
| `05. BIR Books/06. Sales Journal.md` | Current BIR book specification | Current spec | Sales Journal book | — | Keep |
| `05. BIR Books/07. Cash Sales Journal.md` | Current BIR book specification | Current spec | Cash Sales Journal | — | Keep |
| `05. BIR Books/08. Purchase Journal.md` | Current BIR book specification | Current spec | Purchase Journal | — | Keep |
| `05. BIR Books/09. Cash Purchases Journal.md` | Current BIR book specification | Current spec | Cash Purchases Journal | — | Keep |
| `05. BIR Books/10. AR Subsidiary Ledger.md` | Current BIR book specification | Current spec | AR subsidiary book | — | Keep |
| `05. BIR Books/11. AP Subsidiary Ledger.md` | Current BIR book specification | Current spec | AP subsidiary book | — | Keep |
| `05. BIR Books/12. Inventory Subsidiary Ledger.md` | Current BIR book specification | Current spec; canonical breadth limited | Inventory subsidiary book | — | Keep |
| `05. BIR Books/13. Fixed Asset Register.md` | Current/planned BIR book specification | Planned/unverified; fixed assets unexercised | Fixed Asset book | — | Merge Candidate |
| `06. Audit & CAS/01. CAS Dashboard.md` | Current report/workspace specification | Current spec; not package completeness proof | CAS overview UI | — | Keep |
| `06. Audit & CAS/02. Transaction Audit Log.md` | Current audit report specification | Current spec | Transaction audit trail | — | Keep |
| `06. Audit & CAS/03. Master Data Change Log.md` | Current audit report specification | Current spec | Master-data audit trail | — | Keep |
| `06. Audit & CAS/04. System Parameter Logs.md` | Current audit report specification | Current spec | System-parameter evidence | — | Keep |
| `06. Audit & CAS/05. User Activity Log.md` | Current audit report specification | Current spec | User activity evidence | — | Keep |
| `06. Audit & CAS/06. Attachment Register.md` | Current audit report specification | Current spec; canonical artifact coverage limited | Attachment evidence | — | Keep |
| `06. Audit & CAS/07. Document Void Register.md` | Current audit report specification | Current spec; AUD-066 applies to packages | Void evidence | — | Keep |
| `06. Audit & CAS/08. ATP Usage Log.md` | Current compliance-control specification | Current spec | ATP usage evidence | — | Keep |
| `06. Audit & CAS/09. DAT File Generation.md` | Current export specification | Current spec; exact-byte tests required | CAS DAT generation | — | Keep |
| `06. Audit & CAS/10. CAS Audit Report.md` | Current CAS package/report specification | Current spec; blocked by AUD-066 | CAS audit package | — | Keep and Update |
| `06. Audit & CAS/11. Export History.md` | Current audit report specification | Current spec | Compliance export history | — | Keep |

## Historical, Duplicate, and Merge Assessment

No BIR file was moved or deleted in this pass. None was proven to be a temporary transcript or safe duplicate. The Output/Input VAT summaries overlap corresponding files under `docs/PXL/11. Reports/03. Tax Reports/`, and the Fixed Asset Register overlaps report/fixed-asset specifications. They remain merge candidates because unique field, audit, and BIR-layout requirements have not been reconciled.

Income-tax and several statutory-generator blueprints are retained as planned specifications, but agents must not read them for unrelated work or cite them as implementation evidence. Any future merge must preserve unique requirements, update links, designate one canonical replacement, and pass documentation validation before source files move to trash-review.
