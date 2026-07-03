# AI Decisions

Purpose: permanent architectural and business memory for PXL.

Use this file to record why important long-term decisions were made. This is different from `AI/AI_STATE.md`, which records the current project state and session progress. Claude, Fable, Codex, and future AI agents must consult this file before proposing architectural changes.

Do not use this file for temporary implementation notes, bug status, daily progress, or short-lived task context. Put those in `AI/AI_STATE.md` and `AI/AI_HANDOFF.md`.

## When to Update

Update `AI/AI_DECISIONS.md` only when a permanent architectural, accounting, compliance, data model, security, or product-scope decision is made or changed.

Good reasons to update:

- A new posting philosophy is approved.
- A document lifecycle rule changes.
- A tax architecture decision changes.
- A schema/RLS/security strategy changes.
- A long-term module boundary is approved.
- A prior architectural decision is deprecated.

Do not update for:

- Normal implementation progress.
- Bug-fix status.
- Temporary workarounds.
- Current errors.
- Session handoff notes.
- One-off UI copy or styling choices.

## Decision Template

```text
## DEC-000 - Title

Date:
Status: Draft | Approved | Deprecated

Decision:

Business Reason:

Technical Reason:

Alternatives Considered:

Related Documents:

Related Source Files:
```

## DEC-001 - Accounting-First Product Architecture

Date: 2026-07-02
Status: Approved

Decision:

PXL is an accounting-first ERP. Operational modules must ultimately reconcile to the General Ledger, subsidiary ledgers, reports, and Philippine compliance outputs.

Business Reason:

PXL targets Philippine accounting and compliance work. Operational convenience is not enough if invoices, payments, inventory, banking, assets, and tax reports cannot withstand accounting review and BIR audit.

Technical Reason:

The database, RPCs, reports, and UI must preserve traceability from source document to journal entry to GL/TB/financial statements/compliance reports.

Alternatives Considered:

- Build operational CRUD first and add accounting later. Rejected because retrofitting ledger integrity creates high risk.
- Treat accounting as a reporting layer. Rejected because PXL requires posting controls, immutability, and audit trails at the transaction layer.

Related Documents:

- `docs/PXL/PXL_PRINCIPLES.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
- `README.md`

Related Source Files:

- `supabase/migrations/*.sql`
- `src/pages/JournalEntriesPage.tsx`
- `src/pages/GeneralLedgerPage.tsx`
- `src/components/GLImpactPanel.tsx`

## DEC-002 - Reverse or Void Instead of Delete

Date: 2026-07-02
Status: Approved

Decision:

Posted accounting records must not be edited or deleted. Mistakes must be corrected through controlled reversal, void, credit memo, debit memo, cancellation, or supersede workflows.

Business Reason:

Philippine CAS and audit requirements require a clear trail of who did what, when, and why. Deleting posted records destroys audit evidence.

Technical Reason:

RLS, triggers, RPCs, and report views must preserve original and corrective entries. GL reports should include valid reversal evidence so net accounting effect and audit trail both remain visible.

Alternatives Considered:

- Allow admin edits to posted records. Rejected because it breaks auditability.
- Soft-delete posted records. Rejected because it can hide accounting activity from reports.

Related Documents:

- `docs/PXL/PXL_PRINCIPLES.md`
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/02. Setup/03. Document & Validation/01. Document Controls/03. Void Controls.md`
- `docs/PXL/02. Setup/03. Document & Validation/01. Document Controls/04. Reversal Controls.md`

Related Source Files:

- `supabase/migrations/20260701000009_core_line_immutability.sql`
- `supabase/migrations/20260702000005_gl_reversal_visibility.sql`
- `supabase/tests/009_gl_reversal_visibility_test.sql`

## DEC-003 - Multi-Tenant Isolation Through Company Scope and RLS

Date: 2026-07-02
Status: Approved

Decision:

PXL enforces company-scoped multi-tenancy. Company-owned tables must include `company_id`, and database access must be restricted by membership and role-sensitive controls.

Business Reason:

Accounting firms and enterprise groups may manage multiple legal entities. Cross-company data leakage is both a security failure and an accounting failure.

Technical Reason:

Supabase RLS and SECURITY DEFINER RPC checks are the enforcement boundary. UI filtering is not sufficient for tenant isolation.

Alternatives Considered:

- Single-tenant deployment per company. Rejected because it limits the ERP/accounting-firm use case.
- Frontend-only company filtering. Rejected because it is not a security boundary.

Related Documents:

- `README.md`
- `docs/PXL/PXL_PRINCIPLES.md`
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`

Related Source Files:

- `supabase/migrations/20260628000001_companies.sql`
- `supabase/migrations/20260629000008_rls_hardening.sql`
- `supabase/migrations/20260629000009_rls_reads_scope.sql`
- `supabase/migrations/20260701000006_permissions_hardening.sql`

## DEC-004 - Stable AI Context Must Be Indexed and Mode-Based

Date: 2026-07-02
Status: Approved

Decision:

AI agents must not load the full documentation tree by default. They must read the continuity files, consult `AI/AI_CONTEXT_INDEX.md`, determine the repository work mode, and load only task-relevant documents.

Business Reason:

PXL has hundreds of documentation files. Re-reading everything every session wastes API cost and increases the chance of confusing stale or unrelated module details with the current task.

Technical Reason:

Prompt caching works best when stable context is compact, ordered, and reused. Mode-based loading reduces token use and improves cache hit rates.

Alternatives Considered:

- Cache all docs every session. Rejected because it is expensive and noisy.
- Search the repository first every session. Rejected because indexed context should be the default path.

Related Documents:

- `AI/AI_CACHE_CONTEXT_PLAN.md`
- `AI/AI_CONTEXT_INDEX.md`
- `AI/AI_STATE.md`
- `AI/AI_HANDOFF.md`

Related Source Files:

- None.

## DEC-005 - Philippine Tax Profile Drives Compliance Scope

Date: 2026-07-02
Status: Approved

Decision:

PXL compliance behavior must be driven by company tax profile and tax applicability configuration, including VAT/non-VAT behavior, withholding applicability, BIR forms, and compliance reports.

Business Reason:

Philippine taxpayers have different obligations depending on registration, entity type, withholding-agent status, and filing requirements. The system must prevent irrelevant or invalid compliance workflows.

Technical Reason:

Tax profile data must gate transaction tax codes, return generation, dashboards, reports, and exports. Non-VAT/exempt companies must not create VAT-bearing transactions or VAT returns.

Alternatives Considered:

- Let users manually decide which tax forms to use each time. Rejected because it invites compliance errors.
- Hardcode VAT/EWT behavior by page. Rejected because tax behavior must be configurable and auditable.

Related Documents:

- `docs/PXL/10. Compliance/Tax Applicability Matrix.md`
- `docs/PXL/PXL_TAX_RULES_PH.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`

Related Source Files:

- `supabase/migrations/20260701000012_vat_registration_enforcement.sql`
- `supabase/tests/005_non_vat_registration_gating_test.sql`
- `src/pages/VATReturn2550MPage.tsx`
- `src/pages/VATReturn2550QPage.tsx`

## DEC-006 - Number Series Are Controlled, Auditable, and Never Reused After Void

Date: 2026-07-02
Status: Approved

Decision:

Document numbers are generated through controlled number series per company, branch, and document type. Voided or cancelled document numbers are not reused.

Business Reason:

Document numbering is a BIR/CAS audit concern. Reused or skipped-without-evidence numbers create compliance risk.

Technical Reason:

Number generation must use locked database functions, not frontend counters. Number-series schema must remain aligned with the UI and RPC shape.

Alternatives Considered:

- Client-side numbering. Rejected because it is race-prone.
- Reusing numbers after void. Rejected because it breaks audit expectations.

Related Documents:

- `README.md`
- `docs/PXL/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/02. Setup/02. System Controls/01. Number Series/01. Sales Documents.md`
- `docs/PXL/02. Setup/02. System Controls/01. Number Series/02. Purchasing Documents.md`
- `docs/PXL/02. Setup/02. System Controls/01. Number Series/03. Accounting Documents.md`
- `docs/PXL/02. Setup/02. System Controls/01. Number Series/04. Compliance Documents.md`

Related Source Files:

- `supabase/migrations/20260702000001_number_series_document_code_alignment.sql`
- `supabase/tests/001_critical_flow_test.sql`

## DEC-007 - Bounded AI Autonomy Through Work Queue and Guardrails

Date: 2026-07-02
Status: Approved

Decision:

PXL AI agents should operate autonomously from documented state, handoff, and work queue files, but only inside explicit guardrails. Agents may choose the next unblocked task, execute, verify, and update handoff/state without repeated user prompting.

Business Reason:

The user wants Claude, Fable, Codex, and future agents to keep development moving with fewer prompts. A documented autonomous loop reduces user burden while preserving architectural consistency.

Technical Reason:

Autonomy requires a persistent task queue, decision log, context index, state file, handoff file, authority levels, and stop conditions. Without these, agents either stall waiting for prompts or drift into unsafe feature/architecture changes.

Alternatives Considered:

- Fully free-form autonomy. Rejected because PXL is an accounting and Philippine compliance system where uncontrolled changes can create audit, tax, and ledger risk.
- User-driven prompts for every task. Rejected because it wastes time and causes repeated project re-explanation.
- Chat-memory-based continuity. Rejected because chat memory is not durable or reviewable.

Related Documents:

- `AI/AGENT_SYSTEM_PROMPT.md`
- `AI/AI_AUTONOMY_PLAYBOOK.md`
- `AI/AI_WORK_QUEUE.md`
- `AI/AI_STATE.md`
- `AI/AI_HANDOFF.md`
- `AI/AI_CONTEXT_INDEX.md`
- `AI/AI_CACHE_CONTEXT_PLAN.md`

Related Source Files:

- None.

## DEC-008 - Standing Autonomy Delegation for Business-Policy Decisions

Date: 2026-07-02
Status: Approved

Decision:

The user has delegated business-policy and prioritization decisions to the AI agent. When a task requires a business-policy choice (role permissions, workflow rules, defaults, scope of a fix), the agent adopts the standard-accounting-practice, Philippine-compliance-conservative default, records it as a DEC entry in this file, and proceeds without asking. Agents commit and push directly to `main` with CI as the gate.

The delegation covers decisions that strengthen or specify controls. It does NOT cover, and the agent must still stop for:

- weakening or removing accounting, tax, audit-trail, or security controls,
- destructive or irreversible operations on real user data,
- actions requiring secrets/credentials the agent does not hold (record as PENDING instead),
- spending money or performing external legal/compliance actions (e.g., actual BIR filings).

Business Reason:

User directive 2026-07-02: "remove everything that requires my manual decision or work; be autonomous as long as all aligns with the goal — fix all, make it production-ready, a true accounting system, PH-compliance friendly." Pending-decision queues were stalling Critical audit fixes.

Technical Reason:

Every delegated decision is durably recorded as a DEC entry, so it remains reviewable and reversible by the user; the audit findings log records where each decision was applied.

Alternatives Considered:

- Keep a "Decisions Needed From User" queue. Rejected by the user; it blocked P0 findings on responses that may never come.
- Unbounded autonomy including control weakening and destructive actions. Rejected; incompatible with an auditable accounting system.

Related Documents:

- `AI/AI_AUTONOMY_PLAYBOOK.md`
- `AI/AGENT_SYSTEM_PROMPT.md`
- `AI/AI_STATE.md`

Related Source Files:

- None.

## DEC-009 - Role/Action Permission Matrix on Existing Roles

Date: 2026-07-02
Status: Approved (delegated per DEC-008)

Decision:

PXL enforces role/action permissions using the existing `owner`/`admin`/`member`/`viewer` roles, via a `can_perform(company_id, action, document_type)` check inside every posting/void/reversal/approval RPC and the operational master-data policies:

- `owner`, `admin`: full authority — setup/control tables, operational master data, create/edit, approve, post, void, reverse, compliance generation.
- `member`: may create and edit draft operational documents and create/edit operational master data (customers, suppliers, items, services); may NOT approve, post, void, reverse, or modify setup/control tables (COA, fiscal periods, number series, tax setup, approval setup, posting configuration).
- `viewer`: read-only.

Finer-grained named roles (accountant, bookkeeper) may be added later as mappings onto `can_perform` actions without changing the enforcement surface.

Business Reason:

Standard SME segregation: clerks capture, admins/owners authorize. Master-data capture by members is operationally necessary; posting authority is restricted because posting affects the books and BIR outputs.

Technical Reason:

Reuses the deployed role model (`user_company_memberships`), so no data migration is needed; centralizing checks in `can_perform` fixes PXL-DA-003's per-RPC inconsistency.

Alternatives Considered:

- New accountant/bookkeeper roles now. Deferred; adds migration and UI scope without unblocking the Critical finding.
- Members may post their own documents. Rejected; removes segregation of duties.

Related Documents:

- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-003, PXL-AUD-004)

Related Source Files:

- `supabase/migrations/20260701000006_permissions_hardening.sql`
- `supabase/migrations/20260701000007_lifecycle_permissions_broaden.sql`
- `supabase/tests/011_role_based_access_test.sql`

## DEC-010 - Approval Segregation of Duties

Date: 2026-07-02
Status: Approved (delegated per DEC-008)

Decision:

Approval requirements are configured per company and document type through the existing approval workflow tables (`approval_workflows`, `approval_workflow_steps`, `approval_instances`). When a workflow is configured for a document type, posting requires an approved instance and the approver must differ from the document creator (self-approval blocked). When no workflow is configured, the DEC-009 role gate still applies (only owner/admin may approve/post). Approval workflows are not force-enabled by default, so single-user companies remain operable.

Business Reason:

Approver-not-creator is the minimum segregation of duties an auditor expects wherever approval is claimed; cosmetic approval is worse than none because it implies a control that does not operate.

Technical Reason:

Enforcement belongs in the approve/post RPCs (with actor and timestamp), not the UI; the workflow tables already exist, so this is a gate, not a new subsystem.

Alternatives Considered:

- Mandatory approval for all document types. Rejected; unusable for single-user companies.
- Allow self-approval with a warning. Rejected; not a control.

Related Documents:

- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-012)

Related Source Files:

- `supabase/migrations/20260701000008_accounting_readiness_approval.sql`

## DEC-011 - Branch Is a Reporting Dimension, Not a Security Boundary

Date: 2026-07-02
Status: Approved (delegated per DEC-008)

Decision:

The company is the tenant and security boundary (DEC-003). Branch, department, and cost center are reporting/organizational dimensions: they must be validated for company consistency and propagated from source documents to journal entry lines so branch P&L and cost-center reports reconcile to the GL, but users are not access-restricted per branch. Per-branch access control is out of scope unless explicitly requested later.

Business Reason:

PH SME multi-branch bookkeeping needs branch-accurate reports (including BIR branch reporting) far more than intra-company branch secrecy; branch-level security would multiply the RLS/testing surface without a documented requirement.

Technical Reason:

Keeps RLS company-scoped and simple; dimension integrity becomes a posting-engine validation concern (PXL-DA-017) instead of a security model change.

Alternatives Considered:

- Branch as a security boundary. Rejected; no requirement, large RLS/test surface.
- Leave semantics undecided. Rejected; it blocked dimension-propagation work.

Related Documents:

- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-017)

Related Source Files:

- `supabase/migrations/20260629000013_gl_core.sql`

## DEC-012 - Audit/Architecture/Backlog Separation with Continuous Architectural Review

Date: 2026-07-03
Status: Approved

Decision:

Three concerns stay in three places: audit findings (`docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`) hold production defects and release blockers only; architecture documents describe how the system works; product enhancements (GL Impact/Financial Summary/Tax Impact/Posting Validation panels, smart defaults, account determination, payment-method behaviour, drilldown, insights, timelines, reconciliation suite) live in `docs/PXL/PXL_PRODUCT_BACKLOG.md`, organized by module with value/dependency/priority/complexity/readiness/phase fields.

Alongside every audit session, agents perform a lightweight architectural review of any module they touch: identify extension points toward the Standard Transaction Experience (documented in the backlog), prepare the architecture only when the risk is negligible and it avoids future refactoring, and otherwise record the opportunity in the backlog. Genuine bugs discovered during review become NEW audit findings and are not fixed unless they block the current finding. Future planning must never delay, re-prioritize, or expand the current audit session; audit work always takes priority.

Business Reason:

User directive 2026-07-03: while fixing audit findings, PXL should naturally evolve toward a world-class ERP architecture without accumulating future refactoring, and it must stay obvious what blocks release versus what merely improves the product.

Technical Reason:

Mixing enhancements into the findings file inflates the release gate and hides real blockers; a separate backlog with readiness fields lets Phase 2 be implemented with minimal refactoring because extension points were identified while the code was already in context.

Alternatives Considered:

- Log enhancements as audit findings. Rejected; distorts the production readiness gate.
- Implement improvements opportunistically during audit sessions. Rejected; scope creep against bounded-finding discipline.
- No forward planning until audit completes. Rejected by the user; loses architectural insight available while modules are being touched.

Related Documents:

- `docs/PXL/PXL_PRODUCT_BACKLOG.md`
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`
- `AI/AGENT_SYSTEM_PROMPT.md`

Related Source Files:

- None.

