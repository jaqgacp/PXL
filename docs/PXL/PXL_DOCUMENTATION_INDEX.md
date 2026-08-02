# PXL Documentation Index

**Status:** Active repository navigation map
**Authority:** Tier 1 Documentation Governance; subject-matter standards retain authority in their own domains
**Last Reviewed:** 2026-08-02 after the measured product status review
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
| `00. Governance/` | Tier 1/Tier 3 | Principles, product backlog, and the non-normative PG-01 authority map | Cross-domain rules, future-work planning, or resolving a "PG-01" citation |
| `01. Architecture/` | Tier 1/Tier 2/Tier 3 | Product Constitution, subordinate Product Execution Roadmap, engineering architecture summary, generated schema summary, permissions blueprint, master-data gap register | Product, architecture, roadmap, schema, permission, master-data, or platform task |
| `02. Accounting Core/` | Tier 1/Tier 3 | Accounting rules, posting matrix, readiness gate, accounting test book, setup, accounting module blueprints | Posting, GL, period, reconciliation, or accounting validation task |
| `03. Master Data/` | Tier 2 | Organization setup, customers, suppliers, items, employees, warehouses, payment terms, dimensions | Master-data task only |
| `04. Transaction Framework/` | Tier 1/Tier 2/Tier 3 | Transaction matrix, field-source matrix, definition schema, draft-state standard, rollout manifest/playbook, document/system controls | Transaction behavior, field source, lifecycle, draft state, numbering, or approval task |
| `05. Sales/` | Tier 2 | Sales Invoice specs and Sales module blueprints | Sales or Sales Invoice task |
| `06. Purchasing and AP/` | Tier 2 | Purchasing/AP transaction, payable, tax review, and register blueprints | Purchasing/AP task |
| `07. Inventory/` | Tier 1/Tier 2 | Frozen Inventory Accounting Architecture plus inventory operations and master blueprints | Inventory task |
| `08. Banking and Treasury/` | Tier 2 | Petty cash, bank operations, check voucher, treasury blueprints | Banking/treasury task |
| `09. Fixed Assets/` | Tier 2 | Fixed-asset operations and setup blueprints | Fixed-asset task |
| `10. Compliance/` | Tier 2 | BIR/compliance README, tax setup, VAT, withholding, income tax, books, CAS, TIN standard | BIR, tax, CAS, statutory reporting, or compliance task |
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
| Master Data gap analysis / Phase 1 blueprint | `01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md` |
| Master Data implementation roadmap (packages + execution order) | `13. Testing and Validation/PXL_MASTER_DATA_IMPLEMENTATION_PLAN.md` |
| Principles | `00. Governance/PXL_PRINCIPLES.md` |
| Product backlog | `00. Governance/PXL_PRODUCT_BACKLOG.md` |
| Accounting rules | `02. Accounting Core/PXL_ACCOUNTING_RULES.md` and `02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` |
| COA Engine contract (resolver, lifecycle, change policy, FS registry) | `02. Accounting Core/PXL_COA_ENGINE_SPEC.md` |
| Posting Engine architecture (admission, pipeline, journal model, integration contracts; P5.2 fully enforced, P6 Inventory reconciliation blocked) | `02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md` |
| Posting Engine Phase P3 spec (dimension push, fiscal-close hardcode removal, preview convergence, manual-JE control; COA Phase C design-only) | `02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md` |
| Inventory Accounting Architecture (IA-3 frozen; IA-5 landed but dormant with certification suspended; ownership, FIFO/WAC/Specific ID, layers, reconciliation, reporting, canonical requirements, hardening register, roadmap) | `07. Inventory/03. Architecture/`; begin with `PXL_IA3_HARDENING_DECISION_REGISTER.md`, then `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` for current implementation state |
| Inventory event chronology and costing order authority (frozen dual-chronology decision resolving C-01) | `07. Inventory/03. Architecture/ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md` |
| Economic Costing Chronology derivation (ordering tuple, algorithm, total-order proofs, replay, FIFO/WAC/Specific-ID/backdate/correction demonstrations, fail-closed rules) — **owner accepted 2026-07-26, not frozen** | `07. Inventory/03. Architecture/ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md`, with its acceptance gate in `ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md` |
| ECC-01 owner acceptance (the single canonical acceptance record: scope, exclusions, freeze determination, retained clarifications) | `07. Inventory/03. Architecture/ECC-01_FORMAL_OWNER_ACCEPTANCE.md` |
| IA-5 ECC hardening Work Package 1 authorisation (prerequisites, zero-data verification, boundary/dormancy confirmation, authorisation decision) | `07. Inventory/04. Implementation/ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md` |
| IA-5 ECC hardening Work Package 2 authorisation (WP-1-certified prerequisites A–J, bounded M2 registry-extension scope, original authorisation preserved; EA-001/EA-002 reconciled; implementation and Evidence Gate complete; **WP-2 CERTIFIED 2026-07-30**, certification decision recorded in §12) | `07. Inventory/04. Implementation/IA-5_ECC_HARDENING_WP-2_AUTHORISATION_REPORT.md` |
| IA-5 WP-2 detailed registry-authority specification (**implemented 2026-07-29; independent Evidence Gate passed; WP-2 CERTIFIED 2026-07-30**; exact six-column contracts, PostgreSQL-safe constraint labels, `IA5_CERTIFICATION` values, persistent-migration versus rolled-back-certification boundary, and T-04 Source/T-06 Transition/T-07 Effect/T-27 Dormancy obligations) | `07. Inventory/04. Implementation/IA-5_WP-2_DETAILED_REGISTRY_AUTHORITY_SPECIFICATION.md` |
| IA-5 ECC hardening Work Package 2 implementation and prepared evidence (migration M2, tests `105`/`106`, rollback, scope/accounting/security validation; **not itself an Evidence Gate or certification**; records the 2026-07-30 certification outcome) | `07. Inventory/04. Implementation/IA-5_ECC_HARDENING_WP-2_IMPLEMENTATION_AND_EVIDENCE_REPORT.md` |
| IA-5 ECC hardening Work Package 2 independent Evidence Gate (**passed 2026-07-29; rollback remediation verified and independently mutation-verified; recommendation accepted — WP-2 CERTIFIED 2026-07-30, outcome recorded in §10**) | `07. Inventory/04. Implementation/IA-5_ECC_HARDENING_WP-2_EVIDENCE_GATE_REPORT.md` |
| IA-5 WP-3 detailed stream and allocator specification (**Engineering Amendments EA-003 + EA-004 + EA-005; WP-3 AUTHORISED and IMPLEMENTED 2026-07-30 (migration `20260730000018`, tests `107`/`108`); Evidence Gate passed and **WP-3 CERTIFIED 2026-07-31**, certification decision recorded in §13**; the controlling contract for **both** M3 objects — EA-003 names and models `inventory_valuation_stream_sequences` with its partial-mutability guard and allocates WP-3's T-22/T-26 evidence; EA-004 raises `inventory_valuation_streams` to the same standard and resolves its dormancy, activation, and full-immutability contract; EA-005 corrects the T-22 fixture so it is constructible without weakening company isolation) | `07. Inventory/04. Implementation/IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md` |
| IA-5 WP-4 detailed order-key specification (**Engineering Amendments EA-006 + EA-007; WP-4 AUTHORISED and IMPLEMENTED 2026-07-31; Brutal Audit FAILED on WP4-BA-001/WP4-BA-002; bounded Brutal Fix COMPLETE; Brutal Audit Re-run PASSED; WP-4 CERTIFIED 2026-07-31**; the controlling contract for M4 `inventory_event_order_keys` — exact 31-column SQL contract, surrogate primary key, 24 governed keys/constraints, four indexes, the `resolution_state` supersession lifecycle §15 requires, the partial-mutability guard, the deferral of the event-side 1:1 trigger to M5, rollback, and T-03/T-24 evidence allocation with a verified fixture-constructibility proof; **EA-007 re-grounds the dormancy decision on the certified per-event sidecar precedent after EA-006 mis-derived it from `inventory_events`, which does carry `foundation_state`**) | `07. Inventory/04. Implementation/IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md` |
| IA-5 WP-5 detailed event-admission and component-resolution specification (**Engineering Amendment EA-010 COMPLETE 2026-08-01; WP-5 remains unauthorised and unimplemented**; preserves all earlier rejection/amendment chronology and closes WP5-AGR2-001…004 through initial-resolution-only scope, the complete 139-column persistence map, UTC economic/occurrence-date semantics, and future reset-bounded `WP5-CONC-114`; retains the exact writer/resolver/payload/security, fourteen-component encoding, production-versus-certification, trigger/totality, rollback and evidence contract; subordinate to Product Architecture, ADR-C01, ECC-01 and the programme design; ready only for a separate comprehensive Authorisation Gate re-run) | `07. Inventory/04. Implementation/IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md` |
| "PG-01" reference resolution — which accepted document owns each governance rule PG-01 names (**non-normative**; sources win) | `00. Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md` |
| IA-5/IA-6 evidence gate (Outcome C; C-01 Critical; IA-6 unauthorized) | `07. Inventory/03. Architecture/IA5_IA6_FINAL_EVIDENCE_GATE_PLAN.md` and `IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md` |
| IA-5 ECC hardening implementation design (current-state map, target data model, migration/work-package sequence, test plan; controlling engineering plan — **Work Packages 1–4 certified; complete AGR2 rejection and EA-010 closure recorded in §§35–36; WP-5 remains unauthorised/unimplemented; WP-5…WP-9 and IA-6 unauthorised; next mission comprehensive WP-5 Authorisation Gate re-run**) | `07. Inventory/04. Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` |
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
| How we work: the build loop and the two quality bars | `00. Governance/PXL_HOW_WE_WORK.md` |
| The whole plan and the current phase | `01. Architecture/PXL_DELIVERY_PLAN.md` |
| Outcome-driven phase sequencing (Phases 1–9) and where every module and engine completes | `01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md` §9.7 |
| Backing up and restoring the books | `00. Governance/PXL_BACKUP_AND_RECOVERY_RUNBOOK.md` |
| Deploying to the hosted project | `00. Governance/PXL_DEPLOY_RUNBOOK.md` |
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
