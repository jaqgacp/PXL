# AI Context Index

Purpose: fast navigation map for AI agents working on PXL.

Read this file before searching the repository. The goal is to load the smallest useful context for the task, reduce token usage, and avoid architectural drift.

Default reading order for every AI session:

1. `AI/AGENT_SYSTEM_PROMPT.md`
2. `AI/AI_STATE.md`
3. `AI/AI_HANDOFF.md`
4. `AI/AI_WORK_QUEUE.md`
5. `AI/AI_CONTEXT_INDEX.md`
6. Determine the repository work mode.
7. Read only the documents listed for that mode.
8. Search the repository only if the indexed documents do not answer the task.

## Always Relevant

Read these when starting a normal coding, audit, or planning session:

- `AI/AGENT_SYSTEM_PROMPT.md`
- `AI/AI_STATE.md`
- `AI/AI_HANDOFF.md`
- `AI/AI_WORK_QUEUE.md`
- `AI/AI_AUTONOMY_PLAYBOOK.md`
- `AI/AI_DECISIONS.md`
- `docs/PXL/PXL_PRINCIPLES.md`
- `README.md`

Read `AI/AI_CACHE_CONTEXT_PLAN.md` only when cache setup, prompt structure, or AI workflow rules are relevant.

Read `AI/AI_DOCUMENTATION_RULES.md` before creating, growing, or restructuring any documentation. `AI/AIOS_VERSION.md` defines the current AI Operating System version; verify it exists at session start.

Summary documents that exist: `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` and `docs/PXL/PXL_SCHEMA_SUMMARY.md` (generated — regenerate with `scripts/gen_schema_summary.sh`, never hand-edit). `docs/PXL/PXL_PRODUCT_BACKLOG.md` holds future enhancements per DEC-012 — record enhancement ideas there, never in the audit findings. Still missing: `docs/PXL/PXL_ACCOUNTING_RULES.md` and `docs/PXL/PXL_TAX_RULES_PH.md`; where those are referenced, use the detailed documents listed in the same work mode instead. Avoid broad repository search unless the mode documents are insufficient — `PXL_SCHEMA_SUMMARY.md` maps every table/function/view/trigger to the migration holding its current definition.

## Work Modes

### Autonomy Mode

Use for autonomous agent workflow, reducing user prompts, session continuity, cache behavior, work queue maintenance, and AI operating docs.

Read:

- `AI/AGENT_SYSTEM_PROMPT.md`
- `AI/AI_STATE.md`
- `AI/AI_HANDOFF.md`
- `AI/AI_WORK_QUEUE.md`
- `AI/AI_AUTONOMY_PLAYBOOK.md`
- `AI/AI_CACHE_CONTEXT_PLAN.md`
- `AI/AI_CONTEXT_INDEX.md`
- `AI/AI_DECISIONS.md`
- `AI/AI_DOCUMENTATION_RULES.md`

Skip unless needed:

- Business module docs
- Migrations
- Source files

### Accounting Mode

Use for GL, journal entries, posting, reversals, trial balance, financial statements, AR/AP aging, control accounts, schedules, and period close.

Read:

- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
- `docs/PXL/09. Accounting/`
- `docs/PXL/11. Reports/01. Financial Statements/`
- `docs/PXL/11. Reports/02. Trial Balance/`
- `docs/PXL/11. Reports/04. Aging Reports/`

Load source only when needed:

- `supabase/migrations/*accounting*.sql`
- `supabase/migrations/*gl*.sql`
- `supabase/tests/*aging*.sql`
- `supabase/tests/*gl*.sql`
- `src/pages/JournalEntriesPage.tsx`
- `src/pages/GeneralLedgerPage.tsx`
- `src/pages/TrialBalancePage.tsx`
- `src/components/GLImpactPanel.tsx`

Skip unless needed:

- UI principles
- Inventory docs
- Sales docs outside the affected transaction
- Purchasing docs outside the affected transaction

### Sales Mode

Use for Sales/AR documents, sales invoices, receipts, credit/debit memos, customers, AR aging, output VAT source data, and SLS.

Read:

- `docs/PXL/04. Sales/`
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `docs/PXL/03. Master Data/01. Parties/01. Customer Master.md`
- `docs/PXL/11. Reports/09. Transaction Registers/02. Sales Invoice Register.md`

Also read for tax-sensitive sales work:

- `docs/PXL/PXL_TAX_RULES_PH.md`
- `docs/PXL/10. Compliance/02. VAT/`
- `docs/PXL/10. Compliance/03. Withholding Tax/11. 2307 Certificates Received.md`

Skip unless needed:

- Inventory docs
- Fixed asset docs
- Purchasing docs

### Purchasing Mode

Use for Purchasing/AP documents, vendor bills, payment vouchers, vendor credits, suppliers, AP aging, input VAT, EWT, SLP, and 2307 issued.

Read:

- `docs/PXL/05. Purchasing/`
- `docs/PXL/PXL_TAX_RULES_PH.md`
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `docs/PXL/03. Master Data/01. Parties/02. Supplier Master.md`

Also read for EWT/2307 work:

- `docs/PXL/10. Compliance/Form 2307 Management.md`
- `docs/PXL/10. Compliance/03. Withholding Tax/`

Skip unless needed:

- Sales docs
- Inventory docs
- Fixed asset docs

### VAT/EWT Mode

Use for VAT, EWT, CWT, FWT, ATC, Form 2307, Form 2306, SAWT, QAP, SLSP, RELIEF, percentage tax, and tax return behavior.

Read:

- `docs/PXL/PXL_TAX_RULES_PH.md`
- `docs/PXL/10. Compliance/Tax Applicability Matrix.md`
- `docs/PXL/10. Compliance/Form 2307 Management.md`
- `docs/PXL/10. Compliance/01. Percentage Tax/`
- `docs/PXL/10. Compliance/02. VAT/`
- `docs/PXL/10. Compliance/03. Withholding Tax/`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`

Load source only when needed:

- `supabase/migrations/*vat*.sql`
- `supabase/migrations/*withholding*.sql`
- `supabase/migrations/*form2307*.sql`
- `supabase/tests/*vat*.sql`
- `supabase/tests/*ewt*.sql`
- `supabase/tests/*2307*.sql`

Skip unless needed:

- UI principles
- Inventory docs
- Fixed asset docs
- Broad reports docs outside affected tax reports

### UI Mode

Use for page layout, navigation, visual consistency, component behavior, tables, forms, shell, and user workflows.

Read:

- `docs/PXL/UI_UX_PRINCIPLES.md`
- `docs/PXL/PXL_TRANSACTION_EXPERIENCE_STANDARD.md` (authoritative target for transaction pages; UI_UX_PRINCIPLES stack notes are aspirational — selective adoption per the backlog governs)
- `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`
- `docs/PXL/STATUS.md`
- The specific module document for the page being changed.
- The specific React page/component file being changed.

Skip unless requested:

- Accounting rules
- Tax rules
- Migration files
- Audit findings

Exception: if the UI change affects posting, tax, audit trail, document lifecycle, or financial reports, switch to the relevant business mode as well.

### Infrastructure Mode

Use for build tooling, dependencies, Supabase setup, migrations replay, RLS infrastructure, app shell plumbing, CI, and environment issues.

Read:

- `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `README.md`
- `package.json`
- `supabase/config.toml`
- `.github/workflows/ci.yml` if present
- Relevant `tsconfig*.json`, `vite.config.ts`, or dependency files only when needed

Skip unless needed:

- Business module docs
- UI principles
- Tax details

### Audit Mode

Use for production-hardening, gap analysis, retesting, regression planning, and finding closure.

Read:

- The Findings Status Index at the top of `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` first; load full finding rows only for the finding being worked.
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `AI/AI_DECISIONS.md`
- The relevant work-mode docs for the finding area.

Load source only when needed:

- Relevant migration/RPC/test/page files named by the finding.

Skip unless needed:

- Unrelated module docs
- Full source tree scans

### Setup and Master Data Mode

Use for company setup, branch, fiscal years, COA, number series, tax setup, approvals, feature flags, customers, suppliers, items, services, and payment terms.

Read:

- `docs/PXL/02. Setup/`
- `docs/PXL/03. Master Data/`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` when setup readiness or permissions are involved

Skip unless needed:

- Compliance returns
- Report docs
- Operational module docs

### Inventory Mode

Use for inventory dashboard, stock adjustment, transfer, goods issue, physical count, movements, valuation, warehouse settings, and inventory reports.

Read:

- `docs/PXL/06. Inventory/`
- `docs/PXL/03. Master Data/03. Inventory Master/`
- `docs/PXL/11. Reports/06. Inventory Reports/`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`

Also read accounting rules if the task changes inventory costing or GL posting.

### Banking and Treasury Mode

Use for petty cash, fund transfers, inter-branch transfers, bank adjustments, bank reconciliation, outstanding checks, deposits in transit, and check vouchers.

Read:

- `docs/PXL/07. Banking & Treasury/`
- `docs/PXL/11. Reports/05. Bank Reports/`
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`

Also read tax rules for bank adjustments with FWT or check vouchers with EWT/2307.

### Fixed Assets Mode

Use for asset categories, asset register, acquisition, depreciation, disposal, transfer, impairment, and fixed asset reports.

Read:

- `docs/PXL/08. Fixed Assets/`
- `docs/PXL/11. Reports/07. Fixed Asset Reports/`
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`

Also read tax rules for book-vs-tax depreciation or tax-sensitive disposal work.

### Reports Mode

Use for financial statements, trial balance, tax reports, aging, bank reports, inventory reports, fixed asset reports, management reports, registers, and audit reports.

Read:

- `docs/PXL/11. Reports/`
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TAX_RULES_PH.md` if tax reports are involved
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` if report behavior has tests

Skip unrelated operational module docs unless drilldown or source transaction logic is part of the task.

## Search Rule

Search the repository only after the indexed documents and relevant source files do not answer the task.

Prefer targeted searches:

- Search a specific module folder.
- Search exact table, RPC, component, or finding IDs.
- Search relevant migrations/tests only.

Avoid broad repository searches unless the task is discovery, audit, or unknown ownership.

## Token Rule

The objective is context efficiency, not maximum context.

Prefer:

- concise summaries
- indexed documentation
- targeted file loading
- task-specific source snippets
- mode-based context

Avoid:

- reading entire folders by default
- loading all markdown files
- loading all migrations
- pasting whole source files when a focused excerpt is enough
- re-sending volatile session data inside cached blocks
