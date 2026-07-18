# PXL Documentation Index

**Status:** Active repository navigation map
**Authority:** Tier 1 Documentation Governance; subject-matter standards retain authority in their own domains
**Last Verified:** 2026-07-18
**Applies To:** Active, archived, and trash-review documentation
**Read When:** Locating the authority for a task or reviewing documentation lifecycle
**Do Not Read For:** Mandatory fresh-session startup; `AI/AI_STATE.md` already provides the smaller task map

This index classifies all active documentation. A row ending in `/**/*.md` is an exhaustive collection classification: every descendant Markdown file inherits that row unless a more specific index, such as the Compliance README, overrides it. This keeps navigation complete without turning the index into another copy of 267 domain documents.

## 1. Start Here

Humans begin with `README.md`, then use this index. AI coding agents begin with the two files in the next section and do not read this index unless task authority cannot be located.

Authority hierarchy:

1. Executed database behavior, hosted validation, and current test output.
2. Tier 1 governing standards.
3. `PXL_END_TO_END_AUDIT_FINDINGS.md` for official findings and required fixes.
4. `AI/AI_STATE.md` for the next bounded task.
5. `PXL_PRODUCT_BACKLOG.md` for broader work.
6. Tier 2 domain specifications and Tier 3 operational support.
7. Archive and trash-review material as non-current evidence only.

## 2. AI Fast Start

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `AI/AGENT_SYSTEM_PROMPT.md` | AI Fast Start | Tier 0 | Stable rules and startup protocol | Current | Every fresh AI session | Keep and Update | — |
| `AI/AI_STATE.md` | AI Fast Start | Tier 0 | Small current operational handoff | Current; validate mechanically | Every fresh AI session | Keep and Update | — |
| `.claude/CLAUDE.md` | AI adapter | Non-authoritative pointer | Routes Claude to the two Tier 0 files | Current | Automatically by Claude tooling | Generated / Do Not Edit | Tier 0 files |
| `README.md` | Human landing | Tier 3 | Repository overview and commands | Current; not AI startup authority | Human repository orientation | Keep and Update | — |

Only `AI/AGENT_SYSTEM_PROMPT.md` and `AI/AI_STATE.md` are Tier 0 authorities. No additional current AI status, handoff, queue, context, or session file is allowed.

## 3. Governing Documents

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_PRINCIPLES.md` | Product constitution | Tier 1 | Supreme accounting/compliance engineering principles | Active | Resolving cross-domain rules | Keep and Update | — |
| `PXL_ARCHITECTURE_SUMMARY.md` | Architecture | Tier 1 | Concise current architecture orientation | Active; status link must point to AI State | Architecture task only | Keep and Update | — |
| `PXL_SCHEMA_SUMMARY.md` | Schema reference | Tier 1 generated | Generated schema/migration catalog | Generated snapshot | Schema inspection; verify against DB | Generated / Do Not Edit | Database/migrations |
| `PXL_TRANSACTION_MATRIX.md` | Transaction authority | Tier 1 | Lifecycle, sources, status, and implementation maturity | Active | Transaction behavior changes | Keep and Update | — |
| `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md` | Field-source authority | Tier 1 | Governs source/storage/display/validation of transaction facts | Active | Transaction field work | Keep and Update | — |
| `PXL_TRANSACTION_DRAFT_STATE_STANDARD.md` | Transaction state | Tier 1 | Draft ownership and preservation rules | Approved standard | Transaction form state work | Keep | — |
| `PXL_TRANSACTION_WORKSPACE_STANDARD.md` | Transaction UX architecture | Tier 1 | Sole authority for transaction layout, visual language, responsive behavior, components, and interaction | Active standard | Any transaction UI work | Keep and Update | — |
| `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` | Transaction UX patterns | Tier 1 | Sole authority for permitted A–E transaction-content differences | Active standard | Any transaction content composition | Keep and Update | — |
| `PXL_STANDARD_TRANSACTION_WORKSPACE.md` | Historical UX | Non-authoritative | Superseded workspace architecture pointer | Superseded | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_TRANSACTION_WORKSPACE_DESIGN_STANDARD.md` | Historical UX | Non-authoritative | Superseded visual standard pointer | Superseded | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_TRANSACTION_EXPERIENCE_STANDARD.md` | Historical UX | Non-authoritative | Superseded experience blueprint pointer | Superseded | Historical provenance only | Retain pointer | Both current workspace documents |
| `UI_UX_PRINCIPLES.md` | Historical UX | Non-authoritative | Superseded transaction-UX principles pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |

## 4. Accounting and Tax

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_ACCOUNTING_RULES.md` | Accounting | Tier 1 | Concise standing accounting rules | Active | Accounting task orientation | Keep and Update | — |
| `PXL_ACCOUNTING_RULES_MATRIX.md` | Accounting | Tier 1 | Canonical posting/reversal/tax/report behavior | Active | Any accounting behavior change | Keep and Update | — |
| `PXL_PHILIPPINE_TIN_STANDARD.md` | Tax identity | Tier 1 | Canonical Philippine TIN handling | Approved standard | TIN capture/display/validation | Keep | — |
| `02. Setup/05. Tax Setup/**/*.md` | Tax setup blueprints | Tier 2 | BIR forms, tax codes, VAT/EWT/FWT/PT/ATC/calendar setup specs | Active specifications; verify implementation | Exact tax setup task only | Keep and Update | — |
| `09. Accounting/**/*.md` | Accounting module blueprints | Tier 2 | Journal, ledger, schedule, and period page specs | Mixed current/planned; not proof of support | Exact accounting module task | Keep | — |

## 5. BIR and Compliance

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `10. Compliance/README.md` | BIR domain index | Tier 2 navigation | Routes VAT, EWT/CWT, CAS, forms, reports, RLS/config | Active | Any BIR/compliance task | Keep and Update | — |
| `10. Compliance/**/*.md` | BIR domain library | Tier 2 | 68 individually classified compliance blueprints | Mixed current/planned; see local README | Only as routed by local README | Keep / Merge Candidate | — |

The local Compliance README is the detailed file-by-file inventory. Agents must not load the entire folder for `PXL-AUD-063`, `PXL-AUD-066`, or an unrelated task.

## 6. Transaction Architecture

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_TRANSACTION_DEFINITION_SCHEMA.md` | Transaction definition | Tier 2 | Schema for transaction-specific definitions | Active | Defining/qualifying a transaction | Keep | — |
| `PXL_TRANSACTION_WORKSPACE_MANIFEST.md` | Rollout manifest | Tier 3 | Current transaction rollout registry | Operational | Rollout planning | Keep and Update | — |
| `PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md` | Rollout guide | Tier 3 | Validation sequence for workspace rollout | Operational | Approved rollout task | Keep and Update | — |
| `01. Dashboard/**/*.md` | Dashboard blueprints | Tier 2 | Dashboard page specification collection (1 file) | Current blueprint | Dashboard task only | Keep | — |
| `02. Setup/**/*.md` | Setup blueprints | Tier 2 | Setup/control page specifications (52 files) | Mixed current/planned | Exact setup task only | Keep / Merge Candidate | — |
| `03. Master Data/**/*.md` | Master-data blueprints | Tier 2 | Party/item/warehouse/payment-term specs (13 files) | Mixed current; duplicate candidates | Exact master-data task | Merge Candidate | — |
| `04. Sales/**/*.md` | Sales blueprints | Tier 2 | Sales transaction/subledger/tax/register specs (21 files) | Mixed current/planned | Exact sales task | Keep / Merge Candidate | — |
| `05. Purchasing/**/*.md` | Purchasing blueprints | Tier 2 | AP transaction/subledger/tax/register specs (19 files) | Mixed current/planned | Exact purchasing task | Keep / Merge Candidate | — |
| `06. Inventory/**/*.md` | Inventory blueprints | Tier 2 | Inventory operation/master specs (9 files) | Mixed current/planned | Exact inventory task | Keep / Merge Candidate | — |
| `07. Banking & Treasury/**/*.md` | Banking blueprints | Tier 2 | Treasury and bank-operation specs (11 files) | Planned/unexercised in canonical data | Exact banking task | Keep | — |
| `08. Fixed Assets/**/*.md` | Fixed-asset blueprints | Tier 2 | Fixed-asset operation/setup specs (9 files) | Planned/unexercised in canonical data | Exact fixed-asset task | Keep / Merge Candidate | — |

## 7. UX and Design Standards

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_DESIGN_SYSTEM.md` | Historical design | Non-authoritative | Superseded transaction design-system pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_COMPONENT_LIBRARY.md` | Historical components | Non-authoritative | Superseded transaction component pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_BUTTON_STANDARD.md` | Historical component | Non-authoritative | Superseded transaction button pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_CARD_STANDARD.md` | Historical component | Non-authoritative | Superseded transaction card pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_COLOR_SYSTEM.md` | Historical token | Non-authoritative | Superseded transaction color pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_FORM_STANDARD.md` | Historical component | Non-authoritative | Superseded transaction form-visual pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_TABLE_STANDARD.md` | Historical component | Non-authoritative | Superseded transaction table pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_TAB_STANDARD.md` | Historical component | Non-authoritative | Superseded transaction tab pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_TYPOGRAPHY_STANDARD.md` | Historical token | Non-authoritative | Superseded transaction typography pointer | Superseded for transaction workspaces | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |

## 8. Sales Invoice Business Specifications

Sales Invoice is an implementation of the global workspace, not a UI authority. Its residual business completeness remains governed by PXL-AUD-053 and the source-backed specifications below.

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_SALES_INVOICE_UX_STANDARD.md` | Historical SI UX | Non-authoritative | Superseded form-UX pointer | Superseded | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_SALES_INVOICE_VIEW_UX_STANDARD.md` | Historical SI UX | Non-authoritative | Superseded view-UX pointer | Superseded | Historical provenance only | Retain pointer | `PXL_TRANSACTION_WORKSPACE_STANDARD.md` |
| `PXL_SALES_INVOICE_FUNCTIONAL_SPECIFICATION.md` | SI function | Tier 2 | Source-backed functional behavior | Current spec; AUD-053 active | SI functionality | Keep and Update | — |
| `PXL_SALES_INVOICE_TRANSACTION_DEFINITION.md` | SI definition | Tier 2 | Transaction identity/lifecycle | Current spec | SI architecture | Keep and Update | — |
| `PXL_SALES_INVOICE_FIELD_MAPPING.md` | SI mapping | Tier 2 | Field mapping summary | Current companion | SI field source work | Keep and Update | Field-source matrix controls |
| `PXL_SALES_INVOICE_DIMENSION_MAPPING.md` | SI mapping | Tier 2 | Dimension policy | Current; missing masters explicit | SI dimension work | Keep and Update | — |
| `PXL_SALES_INVOICE_GL_MAPPING.md` | SI mapping | Tier 2 | GL behavior summary | Current spec | SI GL work | Keep and Update | Accounting matrix controls |
| `PXL_SALES_INVOICE_TAX_MAPPING.md` | SI mapping | Tier 2 | VAT/CWT source summary | Current spec | SI tax work | Keep and Update | Accounting matrix controls |
| `PXL_SALES_INVOICE_INVENTORY_MAPPING.md` | SI mapping | Tier 2 | Inventory/COGS source rules | Current spec | Inventory-bearing SI work | Keep and Update | — |
| `PXL_SALES_INVOICE_POSTING_SPECIFICATION.md` | SI posting | Tier 2 | Save/post/void behavior | Current spec | SI posting work | Keep and Update | Accounting matrix controls |
| `PXL_SALES_INVOICE_FINANCIAL_SUMMARY_SPECIFICATION.md` | SI view/report | Tier 2 | Financial-tab source contract | Current spec; source validation incomplete | SI financial summary | Keep and Update | — |

## 9. Testing and Audit

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_END_TO_END_AUDIT_FINDINGS.md` | Findings | Tier 1 | Only official defect/fix register | Active: 8 findings | One referenced finding or status audit | Keep and Update | — |
| `PXL_ACCOUNTING_TEST_BOOK.md` | Regression specification | Tier 3 | Test scenarios and executed evidence | Current operational support | Accounting/test-lane task | Keep and Update | — |

No Sales Invoice, BIR, phase, or module-specific findings register is permitted.

## 10. Canonical Demo Environment

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_CANONICAL_DEMO_DATASET.md` | Canonical environment | Tier 3 | Dataset scope, safety, counts, coverage, limitations, commands | Current; incomplete by design | Canonical data/hosted validation task | Keep and Update | — |

## 11. Current Operational Plans

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_ACCOUNTING_CORE_READINESS.md` | Readiness plan | Tier 3 | Current accounting-core gate | Active; must defer to findings | Readiness/sequence decisions | Keep and Update | — |
| `PXL_PRODUCT_BACKLOG.md` | Backlog | Tier 3 | Defect-ID pointers plus approved/future work | Current; not a findings register | Planning beyond current task | Keep and Update | — |

## 12. Report Workspace and Report Blueprints

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PXL_STANDARD_REPORT_WORKSPACE.md` | Report UX/data | Tier 2 governing | Report source, reconciliation, drillback, export standard | Approved standard | Report implementation/validation | Keep | — |
| `11. Reports/**/*.md` | Report blueprints | Tier 2 | Financial, tax, aging, bank, inventory, FA, management, register, audit specs (43 files) | Mixed current/planned; not implementation proof | Exact report task only | Keep / Merge Candidate | — |

## 13. Historical Reports

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `archive/phase-reports/PXL_PHASE2_PRODUCT_AUDIT_REPORT.md` | Phase report | Tier 4 | Phase 2 hosted/product evidence | Historical snapshot | Historical Phase 2 evidence only | Move to Archive | AI State + findings |
| `archive/phase-reports/PXL_PHASE3_CANONICAL_IMPLEMENTATION_REPORT.md` | Phase report | Tier 4 | Phase 3 hosted/canonical evidence | Historical snapshot | Historical Phase 3 evidence only | Move to Archive | AI State + findings + canonical dataset |
| `archive/STATUS_2026-07-14.md` | Old status | Tier 4 | Historical build/page inventory | Historical; stale finding counts | Provenance only | Move to Archive | `AI/AI_STATE.md` |

## 14. Archive

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `archive/ai-operating-system/AI_DECISIONS.md` | Prior decisions | Tier 4 | Unique prior decision evidence | Historical | Provenance for a named decision | Move to Archive | Governing standards/index |
| `archive/ai-operating-system/AI_AUTONOMY_PLAYBOOK.md` | Prior AI rules | Tier 4 | Superseded workflow rules | Historical | AI workflow provenance | Move to Archive | Agent System Prompt |
| `archive/ai-operating-system/AI_DOCUMENTATION_RULES.md` | Prior AI rules | Tier 4 | Superseded documentation rules | Historical | Documentation governance provenance | Move to Archive | Agent System Prompt + this index |

Archive content is non-current and must carry a snapshot label. It may be cited as evidence, never as current status or governing product truth.

## 15. Trash Review

| File | Category | Authority | Purpose | Status | Read When | Action | Superseded By |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `trash-review/ai-operating-system/AIOS_VERSION.md` | Obsolete AI metadata | Tier 5 | Old multi-file AIOS version | Superseded | Cleanup review only | Move to Trash Review | Two-file startup model |
| `trash-review/ai-operating-system/AI_CACHE_CONTEXT_PLAN.md` | Generated research | Tier 5 | Old cache plan | Superseded | Cleanup review only | Move to Trash Review | Agent System Prompt |
| `trash-review/ai-operating-system/AI_CONTEXT_INDEX.md` | Stale context index | Tier 5 | Old mandatory reading map | Superseded/stale links | Cleanup review only | Move to Trash Review | AI State + documentation index |
| `trash-review/ai-operating-system/AI_HANDOFF.md` | Stale handoff | Tier 5 | Append-only session history | Superseded | Cleanup review only | Move to Trash Review | AI State |
| `trash-review/ai-operating-system/AI_WORK_QUEUE.md` | Stale queue | Tier 5 | Competing active work queue | Superseded | Cleanup review only | Move to Trash Review | AI State + backlog |
| `trash-review/ai-operating-system/README.md` | Obsolete AI index | Tier 5 | Old multi-file startup list | Superseded | Cleanup review only | Move to Trash Review | Agent System Prompt |
| `trash-review/generated-reports/pxl-remediation-priorities-2026-07-17/*` | Generated report | Tier 5 | Duplicated remediation summary artifact | Generated/non-authoritative | Cleanup review only | Move to Trash Review | Findings register + AI State |

No file was permanently deleted in this pass. Trash-review is intentionally recoverable and must not be linked as required current reading.

## 16. Pending Merge Decisions

These are candidates, not approved merges:

- `03. Master Data/01. Parties/01. Customer Master.md` with `01. Customers.md`.
- `03. Master Data/01. Parties/02. Supplier Master.md` with `02. Suppliers.md`.
- `03. Master Data/02. Items & Services/03. Items and Services.md` with `03. Items.md` and `04. Services.md`.
- `02. Setup/Opening Balances.md` with `02. Setup/04. Accounting Setup/05. Opening Balances.md`.
- Compliance Output/Input VAT summaries with matching `11. Reports/03. Tax Reports/` specifications.
- Fixed Asset Register specifications across Compliance, Fixed Assets, and Reports.
- Root transaction workspace standards whose scopes overlap; do not merge until normative differences and references are mapped.

No destructive merge should occur until unique requirements are proven preserved, inbound links are updated, one canonical replacement is designated, and `npm run docs:check` passes.

## Document-Creation Checklist

Before creating documentation:

1. Search this index and update an existing authority when possible.
2. Define authority tier, purpose, owner domain, status, and exact read condition.
3. State what it supersedes and which existing document remains authoritative.
4. Confirm it is not another findings register, AI state, handoff, backlog, roadmap, or architecture summary.
5. Add it to this index and to a domain index when applicable.
6. Run `npm run docs:check` and resolve broken/current-to-archive links.

Phase reports go directly to archive after current findings and evidence are reconciled. AI transcripts and generated summaries do not belong in active documentation.
