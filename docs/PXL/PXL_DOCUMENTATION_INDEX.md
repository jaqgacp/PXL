# PXL Documentation Index

**Status:** Active repository navigation map
**Authority:** Tier 1 Documentation Governance; subject-matter standards retain authority in their own domains
**Last Reviewed:** 2026-08-07 repository alignment pass (broken references, archive paths, folder rows, unindexed documents)
**Applies To:** Active, archived, and trash-review documentation
**Read When:** Locating the authority for a task or reviewing documentation lifecycle
**Do Not Read For:** Mandatory fresh-session startup; `AI/AI_STATE.md` provides the smaller task map

This index routes readers to the current authority without duplicating the specifications. A row ending in `/**/*.md` is a collection classification: every descendant Markdown file inherits that row unless a local README is more specific.

## 1. Start Here

Humans begin with `README.md`, then use this index. After applying platform and
repository operating instructions, AI agents use this permanent reading order:

1. `AI/AGENT_SYSTEM_PROMPT.md` — how to work in this repository
2. `AI/AI_STATE.md` — **the only status authority**: what is true today and what to do next
3. `00. Governance/PXL_HOW_WE_WORK.md` — the build loop, the five things that must stay solid, and when something is done
4. `01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` — what PXL is
5. `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` when planning or sequencing product work
6. only the exact finding, code, tests, and governing specifications named by the active task

**Single-source rule.** Status facts — finding counts, test counts, certification
standing, reconciliation standing, maturity — live in `AI/AI_STATE.md` and
nowhere else. A document that restates them will drift and become a trap for the
next session. `AI_PROGRESS.md` and `AI_LAST_SESSION.md` were exactly that failure
and were archived on 2026-08-02: both still reported inventory as unreconciled
after it had been fixed. Session history is `git log`, not a hand-maintained file.

**Four authorities, four questions.** Each planning document answers exactly one
question, and may not answer another's:

| Question | Authority |
| --- | --- |
| **What** is PXL? | `01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` |
| **When**, and in what order, does work ship? | `01. Architecture/PXL_DELIVERY_PLAN.md` |
| **Why** is the order what it is? | `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` |
| **Where** are we today? | `AI/AI_STATE.md` |

**Phase-numbering rule.** Only `PXL_DELIVERY_PLAN.md` numbers phases. An
unqualified "Phase 4" always means Delivery Plan Phase 4. Any other document that
needs to reference scheduling must cite it explicitly ("Delivery Plan Phase 4")
and must never define a numbering of its own. On 2026-08-01 the Execution
Roadmap briefly carried its own numbered phases, which gave "Phase 4" two
incompatible meanings in two active documents; the Roadmap now uses outcome names
only. Historical certification-programme phases are always written
"certification-programme Phase N".

The normal AI startup set must not expand to all Markdown, all Compliance files, all Sales Invoice files, or archived reports.

Authority hierarchy:

1. Executed database behavior, hosted validation, and current test output.
2. `01. Architecture/PXL_PRODUCT_ARCHITECTURE.md` for product identity, scope,
   hierarchy, ownership, and module/engine taxonomy.
3. Tier 1 governing standards for their defined engineering, accounting,
   security, validation, or documentation subjects.
4. `PXL_END_TO_END_AUDIT_FINDINGS.md` for official findings and required fixes.
5. `AI/AI_STATE.md` for the current bounded handoff.
6. `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` for subordinate product
   sequencing and maturity planning; it cannot alter product architecture.
7. `00. Governance/PXL_PRODUCT_BACKLOG.md` for approved/future work.
8. Tier 2 domain specifications and Tier 3 operational support.
9. Archive and trash-review material as non-current evidence only.

## 2. Root Governance

| File | Authority | Purpose | Read When |
| --- | --- | --- | --- |
| `PXL_DOCUMENTATION_INDEX.md` | Tier 1 Documentation Governance | Master navigation and lifecycle rules | Locating documentation authority |
| `PXL_END_TO_END_AUDIT_FINDINGS.md` | Tier 1 Findings Register | Only official defect, audit issue, blocker, and remediation register | Opening a specific finding or reconciling official status |
| `PXL_BUSINESS_PROCESS_BLUEPRINT.md` | Tier 1 Business Process Reference | How every business process runs end to end, across all domains; functional reference for developers, testers, product owners, implementers, manuals and training | Understanding, testing, specifying or training on a business process end to end |

No module-specific findings register, phase tracker, duplicate backlog, or
second status dashboard is current authority. Do not recreate `AI_PROGRESS.md` or
`AI_LAST_SESSION.md`; see the single-source rule in §1.

## 3. AI and Human Startup

| File | Authority | Purpose | Status |
| --- | --- | --- | --- |
| `AI/AGENT_SYSTEM_PROMPT.md` | Tier 0 AI Fast Start | Stable AI operating rules and startup protocol | Current |
| `AI/AI_STATE.md` | Tier 0 AI Fast Start | Small operational handoff and recommended next task | Current; validate with `npm run docs:ai-state-check` |
| `.claude/CLAUDE.md` | Non-authoritative adapter | Routes Claude tooling to the Tier 0 startup authorities | Current |
| `README.md` | Human landing | Repository overview and commands | Current |

## 4. Domain Folders

| Folder | Authority | Contents | Read When |
| --- | --- | --- | --- |
| `00. Governance/` | Tier 1/Tier 3 | Principles, product backlog, how-we-work process authority, backup/recovery and deploy runbooks | Cross-domain rules, future-work planning, or an operational runbook |
| `01. Architecture/` | Tier 1/Tier 2/Tier 3 | Product Constitution, Delivery Plan, subordinate Product Execution Roadmap, engineering architecture summary, generated schema summary, permissions blueprint | Product, architecture, roadmap, schema, permission, or platform task |
| `02. Accounting Core/` | Tier 1/Tier 3 | Accounting rules, posting matrix, readiness gate, accounting test book, setup, accounting module blueprints | Posting, GL, period, reconciliation, or accounting validation task |
| `03. Master Data/` | Tier 2 | Organization setup, customers, suppliers, items, employees, warehouses, payment terms, dimensions | Master-data task only |
| `04. Transaction Framework/` | Tier 1/Tier 2/Tier 3 | Transaction matrix, field-source matrix, definition schema, draft-state standard, rollout manifest/playbook, document/system controls | Transaction behavior, field source, lifecycle, draft state, numbering, or approval task |
| `05. Sales/` | Tier 2 | Sales Invoice specs and Sales module blueprints | Sales or Sales Invoice task |
| `06. Purchasing and AP/` | Tier 2 | Purchasing/AP transaction, payable, tax review, and register blueprints | Purchasing/AP task |
| `07. Inventory/` | Tier 1/Tier 2 | Frozen Inventory Accounting Architecture plus inventory operations and master blueprints | Inventory task |
| *(`08. Banking and Treasury/` — not present)* | — | Deferred to v2; the blueprints live in `archive/v2-deferred/08. Banking and Treasury/` | Banking/treasury task; read from the archive path |
| *(`09. Fixed Assets/` — not present)* | — | Deferred to v2; the blueprints live in `archive/v2-deferred/09. Fixed Assets/` | Fixed-asset task; read from the archive path |
| `10. Compliance/` | Tier 2 | BIR/compliance README, tax setup, percentage tax, VAT, withholding, BIR books, audit/CAS, TIN standard. Income tax and FWT are **not** here — both are PAD-015 excluded scope under `archive/v2-deferred/` | BIR, tax, CAS, statutory reporting, or compliance task |
| `11. Reports/` | Tier 2/Tier 3 | Report workspace standard, executive dashboard, report catalog | Report workspace or report inventory task |
| `12. UI and UX/` | Tier 1 | Transaction workspace standard and transaction-content patterns | Transaction UI/layout task |
| `13. Testing and Validation/` | Tier 1/Tier 3 | Production certification standards (module + engine), product completeness checklist, certification matrix, canonical dataset, and validation routing | Certification, canonical data, or validation task |

## 5. Task-Specific Reading

| Task | Minimum starting documents |
| --- | --- |
| Plan or change product scope, module ownership, engine ownership, or roadmap sequence | `01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`, then `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`; use a governed Product Architecture Amendment for scope changes |
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
| Product Architecture / Product Constitution | [`01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`](01.%20Architecture/PXL_PRODUCT_ARCHITECTURE.md); highest-level product identity, scope, hierarchy, ownership, naming, and module/engine taxonomy authority; required startup reading |
| Product execution sequencing and maturity | [`01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`](01.%20Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md); dependency-driven planning authority subordinate to the Product Architecture |
| Engineering architecture summary | `01. Architecture/PXL_ARCHITECTURE_SUMMARY.md`; executable migrations/schema win over summaries |
| Schema summary | `01. Architecture/PXL_SCHEMA_SUMMARY.md`; generated snapshot, verify against migrations/database |
| Principles | `00. Governance/PXL_PRINCIPLES.md` |
| Product backlog | `00. Governance/PXL_PRODUCT_BACKLOG.md` |
| Accounting rules | `02. Accounting Core/PXL_ACCOUNTING_RULES.md` and `02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` |
| COA Engine contract (resolver, lifecycle, change policy, FS registry) | `02. Accounting Core/PXL_COA_ENGINE_SPEC.md` |
| Posting Engine architecture (admission, pipeline, journal model, integration contracts; P5.2 fully enforced, P6 Inventory reconciliation blocked) | `02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md` |
| Inventory architecture in force (IA-3 frozen: weighted-average valuation decision, costing, reconciliation contract, reporting) | `07. Inventory/03. Architecture/`; `ADR-IAA-001_WEIGHTED_AVERAGE_VALUATION_MODEL.md`, `PXL_INVENTORY_COSTING_SPEC.md`, `PXL_INVENTORY_RECONCILIATION_CONTRACT.md`, `PXL_INVENTORY_REPORTING_SPEC.md`. These govern the shared costing path and the inventory-to-control tie-out in use today |
| IA-5 / ECC economic-chronology programme (**frozen, zero consumers; historical evidence, not current authority**) | `archive/ia5-ecc-frozen/`; ADR-C01, the ECC-01 derivation spec, the inventory accounting architecture and layer-lifecycle specs, and the WP-2…WP-5 detailed specifications under `04. Implementation/`. Read only for provenance of the frozen programme; do not treat as a current delivery item |
| Accounting readiness | `02. Accounting Core/PXL_ACCOUNTING_CORE_READINESS.md` |
| Accounting tests | `02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md` |
| End-to-end business process flow, per domain | [`PXL_BUSINESS_PROCESS_BLUEPRINT.md`](PXL_BUSINESS_PROCESS_BLUEPRINT.md); functional authority for how a process runs, subordinate to the Product Architecture for scope and to `AI/AI_STATE.md` for status |
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
| How we work: the build loop and the two quality bars | `00. Governance/PXL_HOW_WE_WORK.md` |
| The whole plan and the current phase | `01. Architecture/PXL_DELIVERY_PLAN.md` |
| Outcome-driven phase sequencing (Phases 1–9) and where every module and engine completes | `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` §9.7 |
| Backing up and restoring the books | `00. Governance/PXL_BACKUP_AND_RECOVERY_RUNBOOK.md` |
| Deploying to the hosted project | `00. Governance/PXL_DEPLOY_RUNBOOK.md` |
| Certification status dashboard | `13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md` |
| Findings | `PXL_END_TO_END_AUDIT_FINDINGS.md` |
| Transaction definition schema (structure a transaction definition follows) | `04. Transaction Framework/PXL_TRANSACTION_DEFINITION_SCHEMA.md` |
| Transaction workspace rollout pointers (operational; **not** UI authority) | `04. Transaction Framework/PXL_TRANSACTION_WORKSPACE_MANIFEST.md` and `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md` |
| Tax applicability by transaction and registration type | `10. Compliance/Tax Applicability Matrix.md` |
| Form 2307 lifecycle (issued and received) | `10. Compliance/Form 2307 Management.md` |
| Purchase Invoice blueprint | `06. Purchasing and AP/01. Purchase Invoice.md` |
| Executive dashboard blueprint (ownership undecided; not a built surface) | `11. Reports/00. Executive Dashboard.md` |

## 7. Historical and Trash Review

| Location | Status | Use |
| --- | --- | --- |
| `archive/README.md` | Archive orientation | What was archived and why |
| `archive/ia5-ecc-frozen/` | Historical evidence — frozen programme | Provenance for the IA-5 / ECC economic-chronology work: ADR-C01, the ECC-01 derivation spec, the inventory accounting architecture and layer-lifecycle specs, and the WP-2…WP-5 detailed specifications under `04. Implementation/`. Zero consumers; never current authority |
| `archive/v2-deferred/08. Banking and Treasury/` | Deferred scope | Petty cash, bank operations and Check Voucher blueprints held for v2 |
| `archive/v2-deferred/09. Fixed Assets/` | Deferred scope | Fixed-asset operations and setup blueprints held for v2 |
| `archive/v2-deferred/Accounting Schedules Blueprints/`, plus `archive/v2-deferred/05. Amortization Run.md` and `06. Revenue Recognition Run.md` | Deferred scope | Amortisation and revenue-recognition schedule blueprints |
| `archive/v2-deferred/FWT/` and `archive/v2-deferred/Income Tax/` | Excluded scope (PAD-015) | Final Withholding Tax and income-tax material; carries no readiness weight |

Archived material must not be linked as required reading from active documents
except from this index.

**`docs/PXL/trash-review/` does not currently exist.** The lifecycle rule below
still names it as the destination for suspected obsolete or generated material;
the directory is created when material is first routed there, not before.
`AI/AGENT_SYSTEM_PROMPT.md` also refers to it under the same rule.

## 8. Normally Ignore

AI agents should normally ignore:

- `docs/PXL/archive/**` — including the frozen IA-5 / ECC programme and all
  v2-deferred and PAD-015-excluded material
- `docs/PXL/trash-review/**` when it exists
- all Compliance files unless the task is compliance/BIR/tax/CAS
- all Sales Invoice files unless the task is Sales Invoice
- module and setup blueprints outside the task's own domain

## 9. Adding or Changing Documentation

Before creating a new document:

1. Search this index and the relevant domain README.
2. Update an existing authority when possible.
3. Define status, authority, owner/domain, applies-to scope, read condition, and supersession relationship.
4. Do not create another findings register, AI handoff, backlog, roadmap, status file, or architecture summary.
5. Add the document to this index or the relevant domain README.
6. Run `npm run docs:check` and `git diff --check`.

Indexes should route. Specifications should define. Historical evidence should be archived. Suspected obsolete or generated material should go to trash-review, not permanent deletion, unless it is clearly empty, generated, unreferenced, and reproducible.
