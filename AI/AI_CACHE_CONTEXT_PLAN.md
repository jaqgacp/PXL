# AI Cache Context Plan for PXL Claude/Fable Sessions

Created: 2026-07-02
Repository inspected: https://github.com/jaqgacp/PXL

This plan explains which PXL documents should be reused as stable cached context for Claude/Fable coding sessions, which context should stay outside the cache, and how to keep sessions continuous without the user re-explaining the project every time.

Official Anthropic reference checked: https://platform.claude.com/docs/en/build-with-claude/prompt-caching

Key prompt caching facts to apply:

- Put stable context at the beginning of the request.
- Put `cache_control` on the last block whose prefix is identical across requests.
- Do not put timestamps, current errors, changed files, or task text inside the cached block.
- Claude caches the prefix across `tools`, `system`, and `messages`, in that order.
- Default cache TTL is 5 minutes; 1 hour TTL can be requested with additional cost.
- Use up to 4 cache breakpoints when sections change at different frequencies.
- Cache reads are much cheaper than normal input tokens, but cache writes cost more than normal input tokens. The cached block must be reused to pay off.

## Current Repository Findings

The repository is documentation-heavy and already has many strong long-context files. It currently does not have a Claude/Anthropic API integration.

Observed counts:

| Area | Count |
| --- | ---: |
| Markdown documentation files | 282 |
| Supabase migration files | 60 |
| Supabase pgTAP test files | 10 |
| React page files under `src/pages` | 171 |

No existing Claude API integration was found:

- No `@anthropic-ai/sdk` dependency in `package.json`.
- No `anthropic`, `claude`, `cache_control`, `prompt_cache`, or `messages.create` integration in application code.
- `supabase/config.toml` only contains a Supabase Studio comment for `OPENAI_API_KEY`; it is not app Claude integration.

Therefore, do not modify code for prompt caching yet. If a future Claude API wrapper is added, apply `cache_control` in that wrapper where Anthropic `messages.create` requests are assembled.

## A. Files Found and Cache Decision

### Required AI Continuity Files

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `AI/AGENT_SYSTEM_PROMPT.md` | Defines the permanent role, scope, rules, and behavior for every AI agent. | Yes | This is the most stable and highest-value cache block. It should almost never change. |
| `AI/AI_STATE.md` | Holds current project status, broken areas, active task, last changed files, errors, next step, and open decisions. | Yes, but semi-stable | It changes after meaningful sessions, but within a session it prevents repeated re-explanation. Put it after more stable docs so earlier cache breakpoints still hit when it changes. |
| `AI/AI_HANDOFF.md` | Holds short session handoff, what changed today, what remains, and exact next prompt. | Yes, but semi-stable | It changes often, but it is the best cure for repeated session reminders. Cache it late in the stable block or read it outside cache if it changes every turn. |
| `AI/AI_WORK_QUEUE.md` | Prioritized autonomous backlog. Lets agents choose the next unblocked task without repeated prompting. | Yes, but semi-stable | Critical for autonomy. Update at session end so the next agent can continue. |
| `AI/AI_AUTONOMY_PLAYBOOK.md` | Bounded-autonomy rules, authority levels, start/end loop, stop conditions, and verification rules. | Yes | Stable operating rules for autonomous work. |
| `AI/AI_DECISIONS.md` | Permanent architectural and business decision memory. Records why important choices were made. | Yes | Long-term decisions are stable and should be consulted before proposing architectural changes. Never use `AI/AI_STATE.md` for permanent architectural knowledge. |
| `AI/AI_CONTEXT_INDEX.md` | Navigation map for AI. Organizes source-of-truth documents by work area and mode. | Yes | Read before repository search to reduce token usage and avoid loading hundreds of markdown files. |
| `AI/AI_CACHE_CONTEXT_PLAN.md` | This file. Explains what to cache and what to keep volatile. | Yes for cache setup; optional for normal coding | Useful when configuring Claude/Fable workflows. Normal coding sessions can read it only when cache behavior is unclear. |
| `AI/AIOS_VERSION.md` | AIOS version marker, compatible agents, high-level changelog. | Yes | Tiny and stable; verified to exist at session start. |
| `AI/AI_DOCUMENTATION_RULES.md` | Documentation governance: allowed files, growth rules, update cadence. | Yes | Stable governance rules that prevent documentation bloat. |

### Core Project Context

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `README.md` | Stack, local setup, migration summary, security model, posting model, module completion criteria, project structure, BIR notes. | Yes | Compact architecture primer. Stable enough for every coding session. |
| `docs/PXL/PXL_PRINCIPLES.md` | Supreme engineering constitution: accounting-first, Philippine-compliance-first, immutable accounting, audit, RLS, professional ERP UX, no architectural drift. | Yes | Must be in every session. This is the strongest stable instruction file currently present. |
| `docs/PXL/STATUS.md` | Build status, module/page completion, migration status, completed compliance/BIR/audit pages. | Yes, but update-aware | Needed so Claude knows the current build surface. It changes when modules/status change, so keep it later than permanent rules. |
| `docs/PXL/BUILD_ORDER.md` | Original sprint/dependency order for modules. | Usually no | Useful background, but `STATUS.md` and `PXL_TRANSACTION_MATRIX.md` are more current. Cache only for planning/build-order work. |
| `docs/PXL/UI_UX_PRINCIPLES.md` | Enterprise UI/UX/navigation rules and full navigation tree. | Task-specific | Very useful for UI work, but too large and not needed for database/accounting-only sessions. |

### Accounting, Transaction, Audit, and Test State

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `docs/PXL/PXL_TRANSACTION_MATRIX.md` | Living transaction source of truth: purpose, validation, accounting rules, tax rules, JE impact, reports, status flow, audit status, tests, findings. | Yes for coding; must for transaction work | This is the main map that keeps Claude from re-discovering transaction behavior. It is large but high-value. |
| `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` | Audit findings, severity, status, risks, fix plans, evidence, and recommended fix sessions. | Yes for audit/fix sessions | Essential for production-hardening and avoiding repeated audit diagnosis. Volatile, so place after stable architecture. |
| `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` | Expected accounting/reporting test scenarios and pgTAP coverage map. | Yes for accounting/fix sessions | Keeps test expectations and pass/fail evidence available. Needed before changing posting, tax, aging, VAT, EWT, 2307, or GL behavior. |
| `supabase/tests/*.sql` | Executable pgTAP test scenarios. | Task-specific | Do not cache all tests every time. Include only tests relevant to the current fix, plus the test book. |

### Architecture, Schema, and Backend Source

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `supabase/migrations/*.sql` | Actual schema, RLS, RPCs, views, triggers, tax/accounting logic. | Do not cache all | These are the source of truth but too large and change with fixes. Cache a schema summary once created; send only relevant migration files outside cache. |
| `supabase/config.toml` | Supabase local test/config setup. | No | Low-value for most coding sessions. Include only when working on local Supabase/tests. |
| `package.json` | Scripts and dependency surface. | No | Useful to inspect, but not worth stable cache. Mention scripts in AI_STATE or architecture summary. |
| `vite.config.ts`, `tsconfig*.json`, `components.json` | Build/tooling configuration. | No | Include only for build/config work. |

### Setup and Master Data Documents

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `docs/PXL/02. Setup/**/*.md` | Company, branch, fiscal calendar, COA, number series, tax setup, document controls, validation rules, feature flags, approvals. | Accounting/setup-specific | Cache when working on setup readiness, roles, posting validation, number series, period controls, or tax setup. |
| `docs/PXL/02. Setup/04. Accounting Setup/07. GL Posting Configuration.md` | Account determination and posting matrix rules. | Yes for posting/accounting work | High-value for any GL posting change. |
| `docs/PXL/02. Setup/03. Document & Validation/01. Document Controls/02. Posting Controls.md` | Which documents post and how posting is controlled. | Yes for posting/accounting work | Needed for posting workflows and immutability decisions. |
| `docs/PXL/02. Setup/03. Document & Validation/02. Validation Rules/03. Posting Validation Rules.md` | Final accounting checks before posting: debit/credit, tax code, open period. | Yes for posting/accounting work | Directly affects production-hardening and validation fixes. |
| `docs/PXL/03. Master Data/**/*.md` | Customers, suppliers, items, services, UOM, payment terms, warehouse stock settings. | Module-specific | Cache only when current task touches master data defaults, tax profiles, accounts, or UI pages. |

### Tax and Compliance Documents

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `docs/PXL/10. Compliance/Tax Applicability Matrix.md` | Company tax profile behavior, VAT/non-VAT, EWT/FWT, entity type, EOPT/CREATE/TRAIN framing. | Yes for tax/compliance work | Critical for Philippine compliance behavior. |
| `docs/PXL/10. Compliance/Form 2307 Management.md` | 2307 tracking/generation management. | Yes for 2307/EWT work | Needed for certificate logic, QAP/SAWT, and audit trail. |
| `docs/PXL/10. Compliance/01. Percentage Tax/**/*.md` | PT dashboard, working papers, 2551Q, reconciliation, summary register. | Tax-specific | Cache only for percentage tax work. |
| `docs/PXL/10. Compliance/02. VAT/**/*.md` | VAT dashboard, working papers, output/input VAT, reconciliation, 2550M/Q, SLS/SLP/SLSP/RELIEF. | Tax-specific | Cache for VAT, SLSP, RELIEF, and VAT reconciliation tasks. |
| `docs/PXL/10. Compliance/03. Withholding Tax/**/*.md` | WT dashboard, EWT, FWT, ATC, 1601EQ/FQ, QAP, SAWT, 2307/2306. | Tax-specific | Cache for EWT/FWT/ATC/2307/SAWT/QAP work. |
| `docs/PXL/10. Compliance/04. Income Tax/**/*.md` | Income tax dashboard, taxable income, book-to-tax, OSD, NOLCO, tax credits, 1701/1702/MCIT. | Tax-specific | Cache for income tax tasks only. |
| `docs/PXL/10. Compliance/05. BIR Books/**/*.md` | BIR books and statutory ledger/register outputs. | Tax/report-specific | Cache for BIR books, CAS, register, and audit work. |
| `docs/PXL/10. Compliance/06. Audit & CAS/**/*.md` | CAS dashboard, transaction audit log, DAT generation, export history, system logs. | Compliance/audit-specific | Cache for CAS/audit/export work. |

### Accounting and Reporting Documents

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `docs/PXL/09. Accounting/**/*.md` | Journal entries, GL, ledgers, trial balance, subsidiary ledgers, schedules, period management, reversal/posting review. | Accounting-specific | Cache for GL, posting, period close, reversal, schedules, and financial reporting tasks. |
| `docs/PXL/09. Accounting/01. Journal Entries/*.md` | JE and GL entry behavior. | Accounting-specific | Cache for JE/reversal/GL work. |
| `docs/PXL/09. Accounting/02. Ledgers/*.md` | General ledger, account detail, trial balance. | Accounting-specific | Cache for reporting and ledger fixes. |
| `docs/PXL/09. Accounting/03. Subsidiary Ledgers/*.md` | Customer/supplier ledger and control reconciliation. | Accounting-specific | Cache for AR/AP/subledger reconciliation work. |
| `docs/PXL/09. Accounting/05. Period Management/*.md` | Period closing, locks, posting review, reversal review, amortization/revenue recognition runs, auto reversal. | Accounting-specific | Cache for period/reversal/posting-review work. |
| `docs/PXL/11. Reports/**/*.md` | Financial statements, trial balance, tax reports, aging, bank, inventory, asset, management, registers, audit reports. | Report-specific | Cache only for the report being changed plus related accounting/tax docs. |

### Operational Module Documents

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `docs/PXL/04. Sales/**/*.md` | Quotations, sales orders, delivery receipts, sales invoices, cash sales, receipts, CM/DM, customer returns, AR, output VAT, SLS. | Module-specific | Cache for Sales/AR tasks only. |
| `docs/PXL/05. Purchasing/**/*.md` | Purchase orders, receiving, vendor bills, cash purchases, payment vouchers, vendor credits, supplier DM, AP, input VAT, EWT, SLP. | Module-specific | Cache for Purchasing/AP/EWT tasks only. |
| `docs/PXL/06. Inventory/**/*.md` | Inventory operations, movements, valuation, warehouses, items. | Module-specific | Cache for inventory tasks only. |
| `docs/PXL/07. Banking & Treasury/**/*.md` | Petty cash, fund transfers, bank adjustments, reconciliation, checks. | Module-specific | Cache for banking/treasury tasks only. |
| `docs/PXL/08. Fixed Assets/**/*.md` | Asset dashboard, register, acquisition, depreciation, disposal, transfer, impairment, setup. | Module-specific | Cache for fixed asset tasks only. |
| `docs/PXL/01. Dashboard/Dashboard.md` | Dashboard behavior. | UI/task-specific | Cache only for dashboard work. |

### Source Files and Runtime Context

| File path | Purpose | Cache? | Why or why not |
| --- | --- | --- | --- |
| `src/pages/*.tsx` | Page implementations for ERP modules. | Do not cache broadly | Send only the current files being changed outside cache. |
| `src/components/*.tsx` | Shared UI/components such as app shell, setup readiness, GL impact panel. | Task-specific | Include only relevant components outside cache. |
| `src/lib/*.ts(x)` | Supabase client, context, setup readiness utilities. | Task-specific | Include only relevant utilities outside cache. |
| Current terminal/build/test output | Actual current errors and evidence. | Never cache | Always volatile. Keep outside cached block. |
| Git diff / changed files | Current working changes. | Never cache | Always volatile. Keep outside cached block. |

## B. Recommended Cached Context Blocks for Claude

Use multiple blocks so the most stable prefix keeps hitting even when AI_STATE or handoff changes.

### Must Cache Every PXL Coding Session

Recommended order:

1. `AI/AGENT_SYSTEM_PROMPT.md`.
2. `AI/AI_AUTONOMY_PLAYBOOK.md`.
3. `AI/AI_CONTEXT_INDEX.md`.
4. `AI/AI_DECISIONS.md`.
5. `docs/PXL/PXL_PRINCIPLES.md`.
6. `README.md`.
7. `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` once created.
8. `docs/PXL/PXL_SCHEMA_SUMMARY.md` once created.
9. `docs/PXL/STATUS.md`.
10. `docs/PXL/PXL_TRANSACTION_MATRIX.md`.
11. `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`.
12. `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.
13. `AI/AI_STATE.md`.
14. `AI/AI_HANDOFF.md`.
15. `AI/AI_WORK_QUEUE.md`.

Suggested breakpoints:

- Breakpoint 1: after `AI/AGENT_SYSTEM_PROMPT.md`, `AI/AI_AUTONOMY_PLAYBOOK.md`, `AI/AI_CONTEXT_INDEX.md`, `AI/AI_DECISIONS.md`, `PXL_PRINCIPLES.md`, and `README.md`.
- Breakpoint 2: after architecture/schema summaries.
- Breakpoint 3: after transaction matrix, audit findings, and test book.
- Breakpoint 4: after AI_STATE, AI_HANDOFF, and AI_WORK_QUEUE, if they are reused across multiple requests in the same session.

If the session is short or API wrapper supports only simple automatic caching, use one explicit breakpoint at the end of the stable project context and keep the task/error/diff outside it.

### Cache Only During Accounting/Tax/Posting Work

Add these to the cached prefix only when relevant:

- `docs/PXL/02. Setup/04. Accounting Setup/07. GL Posting Configuration.md`
- `docs/PXL/02. Setup/03. Document & Validation/01. Document Controls/02. Posting Controls.md`
- `docs/PXL/02. Setup/03. Document & Validation/01. Document Controls/04. Reversal Controls.md`
- `docs/PXL/02. Setup/03. Document & Validation/02. Validation Rules/03. Posting Validation Rules.md`
- `docs/PXL/02. Setup/03. Document & Validation/02. Validation Rules/04. Period Controls.md`
- `docs/PXL/09. Accounting/**/*.md` relevant to the task.
- `docs/PXL/10. Compliance/Tax Applicability Matrix.md`
- `docs/PXL/10. Compliance/Form 2307 Management.md`
- `docs/PXL/10. Compliance/01. Percentage Tax/**/*.md` for PT work.
- `docs/PXL/10. Compliance/02. VAT/**/*.md` for VAT work.
- `docs/PXL/10. Compliance/03. Withholding Tax/**/*.md` for WT/EWT/FWT/2307 work.
- `docs/PXL/10. Compliance/04. Income Tax/**/*.md` for income tax work.
- Relevant `supabase/tests/*.sql` files for the expected test scenarios.

### Cache Only During UI/Module-Specific Work

Add only the module that matches the current task:

- UI/global navigation work: `docs/PXL/UI_UX_PRINCIPLES.md`
- Dashboard work: `docs/PXL/01. Dashboard/Dashboard.md`
- Setup work: `docs/PXL/02. Setup/**/*.md`
- Master data work: `docs/PXL/03. Master Data/**/*.md`
- Sales/AR work: `docs/PXL/04. Sales/**/*.md`
- Purchasing/AP work: `docs/PXL/05. Purchasing/**/*.md`
- Inventory work: `docs/PXL/06. Inventory/**/*.md`
- Banking/Treasury work: `docs/PXL/07. Banking & Treasury/**/*.md`
- Fixed Assets work: `docs/PXL/08. Fixed Assets/**/*.md`
- Reports work: `docs/PXL/11. Reports/**/*.md`

### Do Not Cache / Volatile Context

Never include these in the cached block:

- Current user task.
- Current error message or stack trace.
- Current terminal output.
- Current git diff.
- Changed files.
- Newly generated code snippets.
- Search results from this moment.
- Timestamps, dates of the current run, or "today's" work summary.
- Temporary assumptions.
- Output format instructions for the current response.

These belong after the cached context.

## Repository Work Modes

The AI should not load every document every session. It must determine the repository work mode first, then load only the documents listed for that mode. `AI/AI_CONTEXT_INDEX.md` is the detailed source of truth for mode routing.

### Autonomy Mode

Read:

- `AI/AGENT_SYSTEM_PROMPT.md`
- `AI/AI_STATE.md`
- `AI/AI_HANDOFF.md`
- `AI/AI_WORK_QUEUE.md`
- `AI/AI_AUTONOMY_PLAYBOOK.md`
- `AI/AI_CONTEXT_INDEX.md`
- `AI/AI_DECISIONS.md`
- `AI/AI_CACHE_CONTEXT_PLAN.md`

Use this mode when the user's goal is fewer prompts, autonomous continuation, work queue maintenance, or AI workflow setup.

Skip business module docs unless the selected queue item requires them.

### Accounting Mode

Read:

- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
- Relevant `docs/PXL/09. Accounting/` docs

Skip unless required:

- UI docs
- Inventory docs
- Sales docs
- Purchasing docs

### Sales Mode

Read:

- Relevant `docs/PXL/04. Sales/` docs
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- Customer/master-data docs if the task touches customer defaults

Skip unrelated modules unless the task crosses into inventory, tax, or posting.

### Purchasing Mode

Read:

- Relevant `docs/PXL/05. Purchasing/` docs
- `docs/PXL/PXL_TAX_RULES_PH.md`
- `docs/PXL/PXL_ACCOUNTING_RULES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- Supplier/master-data docs if the task touches supplier defaults

Skip unrelated modules unless the task crosses into VAT/EWT/2307, inventory, or reports.

### VAT/EWT Mode

Read:

- `docs/PXL/PXL_TAX_RULES_PH.md`
- `docs/PXL/10. Compliance/Tax Applicability Matrix.md`
- `docs/PXL/10. Compliance/Form 2307 Management.md`
- Relevant VAT, EWT, FWT, 2307, SAWT, QAP, SLSP, RELIEF, PT, or income-tax docs

Skip unrelated modules unless they are the source transactions for the tax result.

### UI Mode

Read:

- `docs/PXL/UI_UX_PRINCIPLES.md`
- `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`
- The specific module/page document being changed

Do not load accounting and tax documentation unless the UI change affects posting, tax, audit, lifecycle, reports, or compliance behavior.

### Infrastructure Mode

Read:

- `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`
- `docs/PXL/PXL_SCHEMA_SUMMARY.md`
- `README.md`
- `package.json`
- Relevant Supabase, build, TypeScript, Vite, or CI files

Skip business documentation unless the infrastructure change affects business behavior.

### Audit Mode

Read:

- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `AI/AI_DECISIONS.md`

Skip unrelated implementation docs unless named by the finding.

### Mode Rule

Search the repository only if the mode documents do not contain the required information. Broad repository search is a fallback, not the default behavior.

## Repository Reading Rule

Every AI session must follow this order:

1. Read `AI/AGENT_SYSTEM_PROMPT.md`.
2. Read `AI/AI_STATE.md`.
3. Read `AI/AI_HANDOFF.md`.
4. Read `AI/AI_WORK_QUEUE.md`.
5. Read `AI/AI_CONTEXT_INDEX.md`.
6. Determine the repository work mode.
7. Only read the documents listed for that mode.
8. Only search the repository if the required information cannot be found in those documents.

Searching the repository should be the exception, not the default behavior. If a search is needed, search narrowly by finding ID, table name, RPC name, page/component name, or module folder.

## Token Optimization Principle

The objective is not to maximize context. The objective is to maximize context efficiency.

Claude/Fable/Codex should prefer:

- concise summaries
- indexed documentation
- targeted file loading
- task-specific context
- relevant source snippets

Instead of:

- reading entire folders by default
- loading all markdown files
- loading all migrations
- pasting whole source files when a smaller excerpt answers the task
- re-sending current errors, diffs, or task text inside cached blocks

Every unnecessary markdown file increases token usage. Every unnecessary repository scan increases token usage.

## C. Recommended Prompt Structure for Claude API

Recommended request shape:

1. Stable cached context
   - System/role instructions.
   - Project constitution.
   - Architecture/schema summaries.
   - Stable accounting/tax/posting rules.
   - Current state and handoff when they are stable for the session.
   - Apply `cache_control` to the last stable block.

2. Current task outside cache
   - What the user wants now.
   - Scope boundaries.
   - "Do not code yet" or "implement now" instruction.

3. Current error outside cache
   - Build/test/runtime error.
   - Logs.
   - Failing command.

4. Changed files outside cache
   - Git diff.
   - File snippets.
   - Files touched this session.

5. Output requirements outside cache
   - Desired deliverable.
   - Validation expectations.
   - Response format.

Conceptual TypeScript shape:

```ts
const stableSystemBlocks = [
  {
    type: "text",
    text: readFile("AI/AGENT_SYSTEM_PROMPT.md"),
  },
  {
    type: "text",
    text: readFile("AI/AI_AUTONOMY_PLAYBOOK.md"),
  },
  {
    type: "text",
    text: readFile("AI/AI_CONTEXT_INDEX.md"),
  },
  {
    type: "text",
    text: readFile("AI/AI_DECISIONS.md"),
  },
  {
    type: "text",
    text: readFile("docs/PXL/PXL_PRINCIPLES.md"),
  },
  {
    type: "text",
    text: readFile("README.md"),
  },
  {
    type: "text",
    text: readFile("docs/PXL/PXL_ARCHITECTURE_SUMMARY.md"),
    cache_control: { type: "ephemeral", ttl: "1h" },
  },
  {
    type: "text",
    text: readFile("docs/PXL/PXL_SCHEMA_SUMMARY.md"),
    cache_control: { type: "ephemeral", ttl: "1h" },
  },
  {
    type: "text",
    text: [
      readFile("docs/PXL/STATUS.md"),
      readFile("docs/PXL/PXL_TRANSACTION_MATRIX.md"),
      readFile("docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md"),
      readFile("docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md"),
    ].join("\n\n"),
    cache_control: { type: "ephemeral" },
  },
  {
    type: "text",
    text: [
      readFile("AI/AI_STATE.md"),
      readFile("AI/AI_HANDOFF.md"),
      readFile("AI/AI_WORK_QUEUE.md"),
    ].join("\n\n"),
    cache_control: { type: "ephemeral" },
  },
];

const currentTaskBlock = {
  role: "user",
  content: [
    { type: "text", text: currentTask },
    { type: "text", text: currentErrors },
    { type: "text", text: changedFilesSummary },
    { type: "text", text: outputRequirements },
  ],
};
```

Important: this is conceptual. The repository does not currently contain the code where this should be implemented.

## D. Copyable Claude Prompt Template

```text
You are the PXL AI coding agent.

Use the cached context conceptually as follows:

1. Treat the stable cached block as source of truth:
   - AI/AGENT_SYSTEM_PROMPT.md
   - AI/AI_AUTONOMY_PLAYBOOK.md
   - AI/AI_CONTEXT_INDEX.md
   - AI/AI_DECISIONS.md
   - PXL_PRINCIPLES.md
   - README.md
   - PXL_ARCHITECTURE_SUMMARY.md
   - PXL_SCHEMA_SUMMARY.md
   - STATUS.md
   - PXL_TRANSACTION_MATRIX.md
   - PXL_END_TO_END_AUDIT_FINDINGS.md
   - PXL_ACCOUNTING_TEST_BOOK.md
   - AI/AI_STATE.md
   - AI/AI_HANDOFF.md
   - AI/AI_WORK_QUEUE.md

2. If no direct task is provided, use AI/AI_WORK_QUEUE.md to choose the highest-priority unblocked task.

3. Use AI/AI_CONTEXT_INDEX.md to choose the repository work mode before reading more files or searching the repository.

4. Do not ask me to re-explain the project unless those files are missing, contradictory, or insufficient for the current task.

5. PXL is accounting-first, Philippine-compliance-first, and production-hardening focused.

6. Do not randomly build new features. Continue from AI/AI_STATE.md, AI/AI_HANDOFF.md, and AI/AI_WORK_QUEUE.md, then solve the current task.

7. Current task, errors, changed files, and output requirements are outside the cached block and override stale state only for this request.

8. If you touch transaction behavior, posting, tax, reports, status flow, audit trail, or tests, update PXL_TRANSACTION_MATRIX.md and related audit/test docs when appropriate.

9. At the end of meaningful work, update AI/AI_STATE.md, AI/AI_HANDOFF.md, and AI/AI_WORK_QUEUE.md. Update AI/AI_DECISIONS.md only if a permanent architectural or business decision was made.

Current task:
[PASTE TASK HERE]

Current errors/logs:
[PASTE ONLY CURRENT ERRORS HERE]

Changed files or relevant snippets:
[PASTE ONLY CURRENT CHANGED FILES/SNIPPETS HERE]

Output requirements:
[PASTE EXPECTED OUTPUT HERE]
```

## E. Copyable Developer Instruction

```text
Developer instruction for PXL Claude/Fable sessions:

Do not resend the full codebase in every prompt.

Keep the cached context block stable and reusable. Put permanent and slow-changing PXL context there:

- AI/AGENT_SYSTEM_PROMPT.md
- AI/AI_AUTONOMY_PLAYBOOK.md
- AI/AI_CONTEXT_INDEX.md
- AI/AI_DECISIONS.md
- AI/AI_STATE.md
- AI/AI_HANDOFF.md
- AI/AI_WORK_QUEUE.md
- docs/PXL/PXL_PRINCIPLES.md
- README.md
- docs/PXL/PXL_ARCHITECTURE_SUMMARY.md
- docs/PXL/PXL_SCHEMA_SUMMARY.md
- docs/PXL/STATUS.md
- docs/PXL/PXL_TRANSACTION_MATRIX.md
- docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md
- docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md
- Relevant accounting, posting, schema, tax, or module documents for the current workstream

Send only the current task, current errors, current changed files, current diffs, and requested fixes outside the cached block.

Update AI/AI_STATE.md after meaningful progress. Update AI/AI_HANDOFF.md before ending the session. Update AI/AI_WORK_QUEUE.md whenever a task is completed, started, blocked, or reprioritized.

Update AI/AI_DECISIONS.md only when a permanent architectural or business decision is made, approved, changed, or deprecated. Do not put temporary implementation progress, current errors, or handoff notes in AI/AI_DECISIONS.md.

Do not modify stable cached documents unless necessary. Changes to cached documents can reduce cache hits. When they must change, update them intentionally and keep the most stable files first in the cached prefix so earlier cache breakpoints still work.

The objective is not maximum context. The objective is maximum context efficiency. Prefer concise summaries, indexed documentation, targeted file loading, and task-specific context instead of reading entire folders.

For PXL, correctness beats speed:

- Accounting-first.
- Philippine-compliance-first.
- Production-hardening focused.
- No random new features unless instructed.
- Always continue from AI/AI_STATE.md and AI/AI_HANDOFF.md.
```

## F. Missing or Weak Documents

The AI operating files under `AI/` all exist; their governance lives in `AI/AI_DOCUMENTATION_RULES.md`.

### Weak or Missing Summary Documents

The repository has strong detailed docs, but Claude would benefit from concise summaries to reduce token use and improve cache stability.

Create or improve:

| File | Recommendation |
| --- | --- |
| `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` | Created 2026-07-02. Concise architecture summary: stack, layout, RLS model, posting/RPC pattern, data flow, commands, source-of-truth links. |
| `docs/PXL/PXL_SCHEMA_SUMMARY.md` | Create a concise schema/RPC map by module: key tables, views, RPCs, triggers, migration references, test references. This should summarize migrations instead of caching all 60 SQL files. |
| `docs/PXL/PXL_ACCOUNTING_RULES.md` | Create a concise accounting rules summary: JE invariants, GL/subledger reconciliation rules, immutability, reversal/void conventions, posting preview requirements, period locks, AR/AP aging as-of rules. |
| `docs/PXL/PXL_TAX_RULES_PH.md` | Create a concise Philippine tax rules summary: VAT, non-VAT gating, input/output VAT, EWT/CWT/FWT, ATC effective dates, 2307/2306, SAWT/QAP, SLSP/RELIEF, PT, income tax, BIR books/CAS. |
| `docs/PXL/STATUS.md` | Existing file is strong for build status. Improve by adding "current active hardening focus", "latest completed fix session", and links to `AI/AI_STATE.md` and `AI/AI_HANDOFF.md`. |
| `docs/PXL/PXL_TRANSACTION_MATRIX.md` | Existing file is strong but very large. Keep it as the source of truth; optionally add a short "High-risk active rows" section at top so agents can orient faster. |

## AI/AI_DECISIONS.md Governance

`AI/AI_DECISIONS.md` is the permanent architectural memory of PXL. Its update rules, and the governance for every other AI operating file, are defined in `AI/AI_DOCUMENTATION_RULES.md`. Never use `AI/AI_STATE.md` for permanent architectural knowledge: `AI/AI_STATE.md` is for current project state, `AI/AI_HANDOFF.md` is for the next session, `AI/AI_DECISIONS.md` is for durable reasoning.

## SESSION_CONTINUITY_SYSTEM

The goal is simple: a new Claude/Fable session should know what PXL is, what matters, what is broken, and what to do next without the user repeating project rules.

The required files, their single responsibilities, and their update cadence are defined in `AI/AI_DOCUMENTATION_RULES.md`. The start-of-session and end-of-session protocols are defined in `AI/AGENT_SYSTEM_PROMPT.md`. This file does not restate them.

### Copyable Claude Start Prompt

```text
Read these files first:

- AI/AGENT_SYSTEM_PROMPT.md
- AI/AI_STATE.md
- AI/AI_HANDOFF.md
- AI/AI_WORK_QUEUE.md
- AI/AI_AUTONOMY_PLAYBOOK.md
- AI/AI_CONTEXT_INDEX.md
- AI/AI_DECISIONS.md
- AI/AI_CACHE_CONTEXT_PLAN.md

Treat them as source of truth.

Continue from the documented next step.

If I did not give a direct task, pick the highest-priority unblocked item from AI/AI_WORK_QUEUE.md.

Determine the repository work mode from AI/AI_CONTEXT_INDEX.md before reading more files.

Only search the repository if the indexed mode documents do not answer the task.

Do not ask me to re-explain the project unless the documents are missing or conflicting.
```

### Copyable Claude End Prompt

```text
Before ending this session, update:

- AI/AI_STATE.md
- AI/AI_HANDOFF.md
- AI/AI_WORK_QUEUE.md
- AI/AI_DECISIONS.md only if a permanent architectural or business decision was made

Include:

- what you completed
- what files you changed
- what remains broken
- exact next recommended task
- exact next prompt for the next Claude/Fable session

Do not rely on chat memory.
```

## Claude API Implementation Guidance

Do not implement prompt caching code in this repository yet because no Claude API integration exists.

When a Claude/Fable API integration is later added:

1. Create one request-building wrapper instead of scattering prompt construction across the app.
2. Read stable files in deterministic order.
3. Split stable context into content blocks by volatility.
4. Apply `cache_control` only to the last block of stable content.
5. Keep current task, current errors, diffs, and changed file contents outside cached blocks.
6. Log or inspect usage fields such as cache creation/read tokens to confirm cache hits.
7. Do not put secrets, Supabase keys, or customer data in cached project context.
8. Do not use timestamps inside cached content.

Preferred breakpoints:

```text
Block 1: permanent agent rules + autonomy playbook + context index + decisions + PXL principles + README
cache_control: ephemeral, ttl 1h if the session has many requests

Block 2: architecture summary + schema summary
cache_control: ephemeral, ttl 1h if stable

Block 3: transaction matrix + audit findings + accounting test book
cache_control: ephemeral

Block 4: AI_STATE + AI_HANDOFF + AI_WORK_QUEUE
cache_control: ephemeral only when reused during the same session

Uncached suffix: current task + errors + diffs + output requirements
```

## Practical Default for PXL

For most coding sessions:

1. Cache the permanent block:
   - `AI/AGENT_SYSTEM_PROMPT.md`
   - `AI/AI_AUTONOMY_PLAYBOOK.md`
   - `AI/AI_CONTEXT_INDEX.md`
   - `AI/AI_DECISIONS.md`
   - `docs/PXL/PXL_PRINCIPLES.md`
   - `README.md`
   - `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md`
   - `docs/PXL/PXL_SCHEMA_SUMMARY.md`

2. Cache the project state block:
   - `docs/PXL/STATUS.md`
   - `docs/PXL/PXL_TRANSACTION_MATRIX.md`
   - `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`
   - `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
   - `AI/AI_STATE.md`
   - `AI/AI_HANDOFF.md`
   - `AI/AI_WORK_QUEUE.md`

3. Add one task-specific cached block only when needed:
   - Sales docs for Sales/AR work.
   - Purchasing docs for Purchasing/AP work.
   - Accounting docs for GL/posting/reporting work.
   - Compliance docs for VAT/EWT/2307/BIR work.
   - UI/UX principles for UI work.

4. Keep the current prompt small and uncached:
   - Current task.
   - Current error.
   - Current diff.
   - Current requested output.

Minimal autonomous prompt:

```text
Continue autonomously from the AI operating files.
```

## Final Review: AI Documentation Architecture

The target architecture is an AI operating system, not a pile of documents. Each file has one job. The responsibilities and non-overlap rules for the `AI/` operating files are defined in `AI/AI_DOCUMENTATION_RULES.md`. For the summary documents:

| File | Responsibility | Avoid overlap with |
| --- | --- | --- |
| `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` | Concise technical architecture summary. | Do not duplicate every migration or module spec. |
| `docs/PXL/PXL_SCHEMA_SUMMARY.md` | Concise schema/RPC/test map. | Do not paste full SQL migrations. |
| `docs/PXL/PXL_ACCOUNTING_RULES.md` | Concise accounting rules. | Do not replace the transaction matrix. |
| `docs/PXL/PXL_TAX_RULES_PH.md` | Concise Philippine tax rules. | Do not duplicate every compliance module blueprint. |

Current risks to manage:

- `PXL_TRANSACTION_MATRIX.md` is valuable but large. Keep it as the full source of truth and add short high-risk summaries instead of asking agents to infer from the whole file every time.
- `PXL_END_TO_END_AUDIT_FINDINGS.md` is valuable but volatile. Cache it for audit/fix sessions, but use AI_STATE and AI_HANDOFF for the immediate next step.
- Module folders are useful but numerous. Use `AI/AI_CONTEXT_INDEX.md` and work modes to avoid loading unrelated modules.
- `AI/AI_DECISIONS.md` must stay curated. If it becomes a progress log, it will lose its purpose.
- `AI/AI_STATE.md` and `AI/AI_HANDOFF.md` must be updated at session end. Chat memory is not a source of truth.

Best opportunities to reduce token use:

- Create concise summary docs before implementing Claude API caching.
- Keep summary docs stable and link to detailed docs instead of duplicating them.
- Use work modes as the default path.
- Use targeted source snippets and diffs outside cache.
- Use repository search only as fallback discovery.

## NEXT_PROMPT_FOR_IMPLEMENTATION

```text
Continue autonomously from the AI operating files.

Read:
- AI/AGENT_SYSTEM_PROMPT.md
- AI/AI_STATE.md
- AI/AI_HANDOFF.md
- AI/AI_WORK_QUEUE.md
- AI/AI_AUTONOMY_PLAYBOOK.md
- AI/AI_CONTEXT_INDEX.md
- AI/AI_DECISIONS.md

Pick the highest-priority unblocked task from AI/AI_WORK_QUEUE.md.

Current recommended task: AIQ-004, create docs/PXL/PXL_ARCHITECTURE_SUMMARY.md.

Requirements:

- Base the summary on README.md, docs/PXL/PXL_PRINCIPLES.md, docs/PXL/STATUS.md, and relevant architecture/setup notes.
- Keep it concise enough to be stable cached context.
- Link to detailed source documents instead of duplicating long content.
- Do not implement Claude API prompt caching code yet because this repository currently has no Claude/Anthropic API integration.
- Before ending, update AI/AI_STATE.md, AI/AI_HANDOFF.md, and AI/AI_WORK_QUEUE.md.

Do not ask me to re-explain PXL unless the AI operating files are missing or conflicting.
```
