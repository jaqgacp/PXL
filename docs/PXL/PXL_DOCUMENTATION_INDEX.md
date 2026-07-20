# PXL Documentation Index

**Status:** Active repository navigation map
**Authority:** Tier 1 Documentation Governance; subject-matter standards retain authority in their own domains
**Last Reviewed:** 2026-07-18
**Applies To:** Active, archived, and trash-review documentation
**Read When:** Locating the authority for a task or reviewing documentation lifecycle
**Do Not Read For:** Mandatory fresh-session startup; `AI/AI_STATE.md` provides the smaller task map

This index routes readers to the current authority without duplicating the specifications. A row ending in `/**/*.md` is a collection classification: every descendant Markdown file inherits that row unless a local README is more specific.

## 1. Start Here

Humans begin with `README.md`, then use this index. AI coding agents begin with:

1. `AI/AGENT_SYSTEM_PROMPT.md`
2. `AI/AI_STATE.md`
3. only the exact finding, code, tests, and governing specifications named by the active task

The normal AI startup set must not expand to all Markdown, all Compliance files, all Sales Invoice files, or archived reports.

Authority hierarchy:

1. Executed database behavior, hosted validation, and current test output.
2. Tier 1 governing standards.
3. `PXL_END_TO_END_AUDIT_FINDINGS.md` for official findings and required fixes.
4. `AI/AI_STATE.md` for the current bounded handoff.
5. `00. Governance/PXL_PRODUCT_BACKLOG.md` for approved/future work.
6. Tier 2 domain specifications and Tier 3 operational support.
7. Archive and trash-review material as non-current evidence only.

## 2. Root Governance

| File | Authority | Purpose | Read When |
| --- | --- | --- | --- |
| `PXL_DOCUMENTATION_INDEX.md` | Tier 1 Documentation Governance | Master navigation and lifecycle rules | Locating documentation authority |
| `PXL_END_TO_END_AUDIT_FINDINGS.md` | Tier 1 Findings Register | Only official defect, audit issue, blocker, and remediation register | Opening a specific finding or reconciling official status |

No module-specific findings register, session handoff, phase tracker, or duplicate backlog is current authority.

## 3. AI and Human Startup

| File | Authority | Purpose | Status |
| --- | --- | --- | --- |
| `AI/AGENT_SYSTEM_PROMPT.md` | Tier 0 AI Fast Start | Stable AI operating rules and startup protocol | Current |
| `AI/AI_STATE.md` | Tier 0 AI Fast Start | Small operational handoff and recommended next task | Current; validate with `npm run docs:ai-state-check` |
| `.claude/CLAUDE.md` | Non-authoritative adapter | Routes Claude tooling to the two Tier 0 files | Current |
| `README.md` | Human landing | Repository overview and commands | Current |

## 4. Domain Folders

| Folder | Authority | Contents | Read When |
| --- | --- | --- | --- |
| `00. Governance/` | Tier 1/Tier 3 | Principles and product backlog | Cross-domain rules or future-work planning |
| `01. Architecture/` | Tier 1/Tier 2 | Architecture summary, generated schema summary, permissions blueprint, master-data gap register | Architecture, schema, permission, master-data, or platform task |
| `02. Accounting Core/` | Tier 1/Tier 3 | Accounting rules, posting matrix, readiness gate, accounting test book, setup, accounting module blueprints | Posting, GL, period, reconciliation, or accounting validation task |
| `03. Master Data/` | Tier 2 | Organization setup, customers, suppliers, items, employees, warehouses, payment terms, dimensions | Master-data task only |
| `04. Transaction Framework/` | Tier 1/Tier 2/Tier 3 | Transaction matrix, field-source matrix, definition schema, draft-state standard, rollout manifest/playbook, document/system controls | Transaction behavior, field source, lifecycle, draft state, numbering, or approval task |
| `05. Sales/` | Tier 2 | Sales Invoice specs and Sales module blueprints | Sales or Sales Invoice task |
| `06. Purchasing and AP/` | Tier 2 | Purchasing/AP transaction, payable, tax review, and register blueprints | Purchasing/AP task |
| `07. Inventory/` | Tier 2 | Inventory operations and inventory master blueprints | Inventory task |
| `08. Banking and Treasury/` | Tier 2 | Petty cash, bank operations, check voucher, treasury blueprints | Banking/treasury task |
| `09. Fixed Assets/` | Tier 2 | Fixed-asset operations and setup blueprints | Fixed-asset task |
| `10. Compliance/` | Tier 2 | BIR/compliance README, tax setup, VAT, withholding, income tax, books, CAS, TIN standard | BIR, tax, CAS, statutory reporting, or compliance task |
| `11. Reports/` | Tier 2/Tier 3 | Report workspace standard, executive dashboard, report catalog | Report workspace or report inventory task |
| `12. UI and UX/` | Tier 1 | Transaction workspace standard and transaction-content patterns | Transaction UI/layout task |
| `13. Testing and Validation/` | Tier 1/Tier 3 | Production certification standards (module + engine), product completeness checklist, certification matrix, canonical dataset, and validation routing | Certification, canonical data, or validation task |

## 5. Task-Specific Reading

| Task | Minimum starting documents |
| --- | --- |
| Continue current audit finding | `AI/AGENT_SYSTEM_PROMPT.md`, `AI/AI_STATE.md`, then the one central finding and files/tests named there |
| Implement a Sales Invoice change | `05. Sales/README.md`, `04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`, exact SI spec(s), focused SI code/tests, and PXL-AUD-053 if relevant |
| Implement a Vendor Bill change | `04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`, `02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`, exact Purchasing/AP blueprint, affected code/tests |
| Review a BIR/CAS requirement | `10. Compliance/README.md`, the exact routed compliance spec, central finding if named, affected migration/tests |
| Inspect canonical demo data | `13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md`, `02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md` only if test coverage is part of the task |
| Modify transaction workspace UI | `12. UI and UX/README.md`, `12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md`, `12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md`, affected components/tests |
| Change report workspace behavior | `11. Reports/PXL_STANDARD_REPORT_WORKSPACE.md`, affected report code/tests; use `11. Reports/PXL_REPORT_CATALOG.md` only for report inventory |

## 6. Current Core Authorities

| Subject | Current authority |
| --- | --- |
| Architecture | `01. Architecture/PXL_ARCHITECTURE_SUMMARY.md`; executable migrations/schema win over summaries |
| Schema summary | `01. Architecture/PXL_SCHEMA_SUMMARY.md`; generated snapshot, verify against migrations/database |
| Master Data gap analysis / Phase 1 blueprint | `01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md` |
| Master Data implementation roadmap (packages + execution order) | `13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md` |
| Principles | `00. Governance/PXL_PRINCIPLES.md` |
| Product backlog | `00. Governance/PXL_PRODUCT_BACKLOG.md` |
| Accounting rules | `02. Accounting Core/PXL_ACCOUNTING_RULES.md` and `02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` |
| Accounting readiness | `02. Accounting Core/PXL_ACCOUNTING_CORE_READINESS.md` |
| Accounting tests | `02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md` |
| Transaction lifecycle and maturity | `04. Transaction Framework/PXL_TRANSACTION_MATRIX.md` |
| Transaction field-source control | `04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` |
| Transaction draft state | `04. Transaction Framework/PXL_TRANSACTION_DRAFT_STATE_STANDARD.md` |
| Transaction UI | `12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| Transaction content patterns | `12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md` |
| Sales Invoice | `05. Sales/README.md` and the exact file under `05. Sales/Sales Invoice/` |
| Compliance/BIR | `10. Compliance/README.md` plus the routed exact spec |
| TIN | `10. Compliance/PXL_PHILIPPINE_TIN_STANDARD.md` |
| Reports | `11. Reports/PXL_STANDARD_REPORT_WORKSPACE.md` |
| Canonical dataset | `13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md` |
| Module certification standard | `13. Testing and Validation/PXL_MODULE_CERTIFICATION_STANDARD.md` |
| Engine certification standard | `13. Testing and Validation/PXL_ENGINE_CERTIFICATION_STANDARD.md` |
| Product completeness checklist (pre-certification capability expectations) | `13. Testing and Validation/PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` |
| Certification status dashboard | `13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md` |
| Findings | `PXL_END_TO_END_AUDIT_FINDINGS.md` |

## 7. Historical and Trash Review

| Location | Status | Use |
| --- | --- | --- |
| `archive/phase-reports/` | Historical snapshots | Phase evidence only; not current status |
| `archive/ai-operating-system/` | Historical AI operating-system evidence | Provenance for old decisions/rules only |
| `archive/superseded-ui-standards/` | Superseded pointers | Historical provenance for old UI standards |
| `archive/superseded-sales-invoice-blueprints/` | Superseded SI blueprints | Historical provenance only |
| `trash-review/ai-operating-system/` | Obsolete AI files | Human deletion review |
| `trash-review/generated-reports/` | Generated remediation summaries | Human deletion review |
| `trash-review/generated-report-blueprints/` | Generated near-duplicate report placeholders | Human deletion review; unique report names preserved in `11. Reports/PXL_REPORT_CATALOG.md` |
| `trash-review/generated-scripts/` | One-off scratch scripts found in docs | Human deletion review |
| `trash-review/working-papers/` | Non-authoritative working papers | Human review before formal findings/backlog decisions |

Archived and trash-review material must not be linked as required reading from active documents except from this index.

## 8. Normally Ignore

AI agents should normally ignore:

- `docs/PXL/archive/**`
- `docs/PXL/trash-review/**`
- all Compliance files unless the task is compliance/BIR/tax/CAS
- all Sales Invoice files unless the task is Sales Invoice
- generated report placeholders in trash-review
- old AI operating-system files
- historical phase reports

## 9. Adding or Changing Documentation

Before creating a new document:

1. Search this index and the relevant domain README.
2. Update an existing authority when possible.
3. Define status, authority, owner/domain, applies-to scope, read condition, and supersession relationship.
4. Do not create another findings register, AI handoff, backlog, roadmap, status file, or architecture summary.
5. Add the document to this index or the relevant domain README.
6. Run `npm run docs:check` and `git diff --check`.

Indexes should route. Specifications should define. Historical evidence should be archived. Suspected obsolete or generated material should go to trash-review, not permanent deletion, unless it is clearly empty, generated, unreferenced, and reproducible.
