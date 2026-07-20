# PXL Module Certification Standard

**Status:** Active certification authority
**Authority:** Tier 1 Certification Governance for the PXL Production Certification Program
**Owner / Domain:** Testing and Validation
**Applies To:** Every supported business module before it may be classified as Certified
**Read When:** Certifying a module, planning a certification phase, or classifying module status in the certification matrix
**Do Not Read For:** Transaction UI layout (use UI and UX standards), official defect content (use the findings register), or current next task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-20 certification framework setup

This standard defines the mandatory gates that a PXL business module must pass before it may be recorded as **Certified** in [`PXL_CERTIFICATION_MATRIX.md`](PXL_CERTIFICATION_MATRIX.md). It is the module half of the Production Certification Program; the engine half is [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md). This document defines *how* certification is proven. It does not restate module business rules, which remain owned by the module's governing specification, nor does it hold defect content, which remains in [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md).

Certification is evidence-led. A module is never certified because pages render, routes load, tests compile, HTTP calls return 200, journals happen to balance, or documentation is complete. Certification requires executed business, accounting, tax, inventory, subledger, reporting, security, correction, and operational evidence.

## 1. Supported Modules

The Production Certification Program certifies these business modules:

1. Setup and Master Data
2. Accounting Core
3. Sales and Accounts Receivable
4. Purchasing and Accounts Payable
5. Inventory
6. Banking and Treasury
7. Fixed Assets
8. Accounting Schedules
9. Philippine Compliance and Tax
10. Reports and Financial Statements
11. Administration and Security

A module cannot be certified until every shared engine relevant to it is certified under the engine standard. Engine-to-module applicability is recorded in the certification matrix.

## 2. Certification Statuses

Use only these statuses in the certification matrix. They are cumulative gates, not free-form labels.

| Status | Meaning |
| --- | --- |
| Not Started | No certification evidence gathered for this module. |
| In Progress | Certification underway; one or more mandatory gates unproven. |
| Functionally Passed | Intended workflows implemented and pass positive and negative functional tests. |
| Accounting Reconciliation Passed | Postings and subledger/GL reconciliations proven for the module's transactions. |
| Tax Reconciliation Passed | Tax computation and tax-ledger reconciliation proven where applicable. |
| Security Passed | RLS, permissions, segregation of duties, and immutability proven for the module. |
| Reporting Passed | Module reports reconcile to source, subledger, GL, and trial balance. |
| Operationally Passed | Correction, closing, backup/recovery, and operational controls proven. |
| Certified | All applicable gates above pass; no unresolved Critical or High defect in scope. |
| Blocked | Certification cannot proceed because of an active Critical/High defect or missing dependency. |
| Deferred | Module or sub-scope is explicitly out of supported production scope for now. |

A module marked **Certified** must satisfy every applicable gate. A module that would otherwise pass functionally but carries an active Critical or High defect in its scope is **Blocked**, not Certified.

## 3. Mandatory Module Gates

A module is **Certified** only when all applicable statements below are proven with executed evidence. Where a statement does not apply to a module (for example, inventory for a services-only compliance module), record it explicitly as *not applicable* with a one-line justification.

1. Intended workflows are implemented and reachable.
2. Required master data exists and is validated.
3. Field sourcing is validated against [`../04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`](../04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md).
4. Lifecycle and statuses are correct.
5. Approval and permissions are correct.
6. Posting is correct against [`../02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`](../02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md).
7. Tax is correct where applicable.
8. AR or AP is correct where applicable.
9. Inventory is correct where applicable.
10. Payments and applications are correct where applicable.
11. Reversal, void, credit, return, and correction flows work.
12. Closed-period behavior is enforced.
13. Posted documents are immutable.
14. Cross-company access is blocked.
15. Reports reconcile to source transactions, subledgers, GL, and trial balance.
16. Branch and company reporting work.
17. Negative and edge cases pass.
18. Deterministic automated tests pass.
19. Canonical demo scenarios pass.
20. Browser workflows pass.
21. No unresolved Critical or High defect remains within the supported scope.
22. Any remaining limitations are explicitly documented and acceptable for controlled production use.
23. Production operations, backup, recovery, and deployment requirements relevant to the module are satisfied.

A module may retain Medium or Low backlog items only when they do not compromise accounting correctness, tax correctness, inventory correctness, security, data integrity, reporting reliability, ability to correct errors, ability to close periods, or operational recoverability.

## 4. Required Evidence per Gate

Each gate is proven by concrete, re-runnable evidence, not assertion. Acceptable evidence types:

- **Automated tests** — unit, pgTAP database, integration, browser E2E, and report-reconciliation lanes named in [`../02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md`](../02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md). Tests must be deterministic; flaky tests are fixed, not suppressed.
- **Canonical dataset outcomes** — deterministic document numbers and documented expected balances from [`PXL_CANONICAL_DEMO_DATASET.md`](PXL_CANONICAL_DEMO_DATASET.md).
- **Reconciliation proofs** — subledger-to-control, control-to-GL, GL-to-trial-balance, trial-balance-to-financial-statement, tax-ledger-to-GL, and branch-to-company equality with the numbers shown.
- **Security proofs** — RLS/permission/SOD behavior exercised through UI, direct client queries, and RPC calls, not frontend checks alone.
- **Operational proofs** — successful backup and successful restore, environment separation, and correction-workflow execution.

Evidence must be reproducible from a documented starting state. A single happy-path example is never sufficient; each gate requires positive, negative, and edge coverage.

## 5. Required Certification Output per Module

When a module is assessed, record the following (in the findings register for defects, in `AI/AI_STATE.md` for active handoff, and summarized in the certification matrix — never as a new per-module status document):

- scope;
- transactions;
- master-data dependencies;
- supported workflows;
- unsupported workflows;
- engine dependencies;
- canonical scenarios;
- positive tests;
- negative tests;
- accounting results;
- tax results;
- inventory results;
- subledger results;
- report results;
- security results;
- correction results;
- operational risks;
- blockers;
- certification status.

## 6. Phase Order and Per-Phase Exit Evidence

Certification proceeds in dependency order. A later phase does not begin certification merely because its pages already exist; it begins when its foundational engines and modules have passed the gates they depend on.

| Phase | Scope | Exit evidence required before the phase is Functionally Passed or better |
| --- | --- | --- |
| 1 | Setup and Master Data; Permissions and RLS; Core Accounting; Posting Engine; Period Lock; Audit and Immutability; Number Series; Dimensions | Master data validated; posting invariants proven for every implemented posting transaction; period lock blocks closed-period posting; posted documents immutable; company/branch isolation proven; unique numbering proven under concurrency. |
| 2 | Sales and Accounts Receivable | Full revenue cycle scenarios pass; AR subledger equals AR control; output VAT ledger equals sales tax lines; inventory/COGS post correctly; returns/credit/void/reversal proven. |
| 3 | Purchasing and Accounts Payable | Full payable cycle scenarios pass; AP subledger equals AP control; input VAT and EWT reconcile; three-way matching and over-receipt/over-bill controls proven; returns/credit/void/reversal proven. |
| 4 | Inventory Module and Inventory Engine | Quantity and valuation reproducible from posted movements; inventory GL equals inventory subledger; negative-stock prevention proven server-side and under concurrency. |
| 5 | Banking and Treasury; Payment and Application Engine | Application cannot exceed open balance; unapplied cash tracked; transfers reconcile; cash/bank ledger equals GL; reversals restore open balances. |
| 6 | Fixed Assets; Accounting Schedules | Acquisition-to-disposal lifecycle reconciles to the asset register and GL; schedules generate correctly with duplicate-run prevention and closed-period behavior. |
| 7 | Philippine Compliance and Tax | Tax sourced from transaction data; tax ledgers reconcile to source and GL; BIR configuration writes are permission-controlled; report date semantics explicit; unsupported forms marked. |
| 8 | Reports, Financial Statements, Management Reporting, and Reconciliation | Every listed report defines its contract and reconciles to its target; company and branch reporting reconcile; drill-down from FS to source works; exports match on-screen values. |
| 9 | Production Operations; Backup and Recovery; Deployment; Monitoring; Controlled Pilot Readiness | Environment separation proven; migrations ordered with rollback plan; backup succeeds and restore succeeds; monitoring and support procedures exist; controlled pilot gate criteria ready. |

## 7. Correction, Void, Reversal, and Recovery

Every core transaction in a module must define and prove: editable while draft; approval correction path; cancellation before posting; void after posting where allowed; reversal; credit or debit adjustment; return; payment reversal; inventory reversal; reopened-source behavior; number-series treatment; tax treatment; audit treatment; and period treatment. Direct database editing is never an accepted correction method. Original posted documents must remain historically visible, and corrections must preserve source relationships.

## 8. Controlled Pilot Gate

No module or program result may recommend immediate broad production launch. Pilot readiness for a module requires a fully certified internal/demo company, a low-risk real client, a parallel/shadow period with existing official records retained as fallback, validated opening balances, assigned roles, verified backup, verified reporting, a completed month-end reconciliation, and recorded acceptance. Pilot success requires no unexplained GL, AR/AP control, inventory-to-GL, or tax-ledger difference, proven correction and backup/restore workflows, and no Critical or High security defect.

## 9. Prohibited Certification Shortcuts

Do not certify on UI alone; do not certify reports because they render; do not permit negative stock by accident; do not rely on frontend validation for stock, payment, or posting controls; do not allow uncontrolled overbilling, overreceiving, overdelivery, or overapplication; do not bypass RLS to make tests pass; do not change accounting behavior without evidence; do not fabricate reports; do not use static mock data as production evidence; do not mark unsupported workflows as passed; do not hide failures; do not suppress flaky tests; and do not reclassify a material defect as backlog to avoid blocking certification.
