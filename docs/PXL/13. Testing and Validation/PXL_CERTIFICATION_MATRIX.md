# PXL Certification Matrix

**Status:** Active certification dashboard
**Authority:** Tier 1 Certification Status (dashboard only; evidence lives in tests, findings, and the two certification standards)
**Owner / Domain:** Testing and Validation
**Applies To:** Program-level module and engine certification status
**Read When:** Checking current certification status or selecting the next certification phase
**Do Not Read For:** Certification method (use the module/engine standards), defect content (use the findings register), or current bounded task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-22 after the Setup & Master Data Phase 1 certification re-review (audit findings program complete)

This is a concise status dashboard only. It records where each module and engine stands against [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md) and [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md). Capability expectations run before certifying a module are defined in [`PXL_PRODUCT_COMPLETENESS_CHECKLIST.md`](PXL_PRODUCT_COMPLETENESS_CHECKLIST.md). It holds no defect detail (see [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md)) and no active-task handoff (see `AI/AI_STATE.md`). Statuses are defined in the two standards.

## Overall Program Result

**Partially Ready — Blocked.** PXL is **not production-ready** and **not pilot-ready**. The Permissions/RLS Engine certification review on 2026-07-22 uncovered a confirmed Critical cross-company data exposure — nine `postgres`-owned, non-`security_invoker` reporting views bypassed RLS and returned other companies' financial data to any authenticated user. It was **remediated the same day as `PXL-AUD-069`** (migration `20260722000011` enables `security_invoker` on all nine; regression test 076 proves member/non-member isolation; permanent guard 077 blocks the class), so the findings register is now 89 Retested Passed / 0 In Progress / 0 Open (89 findings). The Permissions/RLS Engine returns to **In Progress** pending its certification re-review (the defect is cleared, but the full engine review has not been re-executed). The Setup & Master Data Phase 1 review remains **Blocked**: master-data implementation is complete and deterministic tests pass (fresh-reset regression 77 files / 1,604 assertions; canonical 4 files / 96 assertions; company-setup readiness 8/8; all 35 master-data gaps resolved), but Gate 23 backup/recovery has no successful restore test / RPO/RTO, its dependent engines are not Certified, and browser-workflow evidence is recorded-only (Gate 20 Partial). No module or engine is Certified.

The strongest implemented cores (Sales Invoice, Official Receipt, Vendor Bill, Payment Voucher) have atomic save/post RPCs, immutability, and pgTAP coverage, but none has completed all mandatory certification gates. MDP-14 proves the reusable approval foundation and bounded MDP-15 import integration; broad transaction approval rollout remains unproven. Banking, fixed assets, returns, schedules, statutory generators, backup/restore, and CAS artifacts are not proven complete.

## Module Certification Status

| # | Module | Status | Governing Certification Phase | Primary Open Blockers |
| --- | --- | --- | --- | --- |
| 1 | Setup and Master Data | Blocked | Phase 1 | Re-reviewed 2026-07-22 with the findings program complete (88/0/0): 14 gates Pass, 3 Partial, 2 Blocked, 4 N/A (posting/tax/AR-AP/inventory belong to later modules), 0 Fail. Functional/master-data evidence passes (all 35 gaps resolved; regression 75 files / 1,596 assertions; canonical 96; readiness 8/8; MDP-08 test 073 and MDP-14 test 074 pass on fresh reset). **No open defect remains.** Not certified because Gate 23 backup/restore + RPO/RTO evidence does not exist and the dependent Permissions/RLS, Audit & Immutability, Number Series, and Dimension engines are not Certified; browser-workflow evidence is recorded-only (Gate 20 Partial). |
| 2 | Accounting Core | In Progress | Phase 1 | Posting invariants not proven across all posting transactions |
| 3 | Sales and Accounts Receivable | In Progress | Phase 2 | `PXL-AUD-053` SI completeness; returns/credit reconciliation unproven |
| 4 | Purchasing and Accounts Payable | In Progress | Phase 3 | Three-way match, returns, over-receipt controls unproven |
| 5 | Inventory | In Progress | Phase 4 | Item-level/company inventory policy defaults exist from MDP-13, but negative-stock prevention, costing, valuation, and inventory GL reconciliation are not yet proven server-side program-wide |
| 6 | Banking and Treasury | Not Started | Phase 5 | Module not proven complete |
| 7 | Fixed Assets | Not Started | Phase 6 | Lifecycle/reconciliation not proven |
| 8 | Accounting Schedules | Not Started | Phase 6 | Generation, duplicate-run, closed-period behavior unproven |
| 9 | Philippine Compliance and Tax | Blocked | Phase 7 | Phase 7 not executed; CAS document-period evidence is governed (`PXL-AUD-066` closed), `PXL-AUD-063` BIR write policy is closed, and the credential finding is closed, but the module remains gated by its Phase 7 review and evidence. |
| 10 | Reports and Financial Statements | In Progress | Phase 8 | Reconciliation and drill-down not certified; report probes only |
| 11 | Administration and Security | Not Started | Phase 1 | Credential remediation is verified under PXL-AUD-055; the module's own certification review has not been executed. |

## Engine Certification Status

| # | Engine | Status | Primary Open Blockers |
| --- | --- | --- | --- |
| 1 | Posting Engine | In Progress | Invariants proven for SI/OR/VB/PV; not across all posting transactions |
| 2 | Inventory Engine | In Progress | Server-side negative-stock prevention not proven program-wide |
| 3 | AR Engine | In Progress | Subledger-to-control reconciliation not certified across scenarios |
| 4 | AP Engine | In Progress | Subledger-to-control reconciliation not certified across scenarios |
| 5 | Payment and Application Engine | In Progress | Over-application and unapplied-cash controls not certified end-to-end |
| 6 | Tax Engine | Blocked | ledger-to-GL reconciliation incomplete (BIR config writes governed; CAS document-period evidence governed with `PXL-AUD-066` closed) |
| 7 | Document Conversion Engine | Not Started | Quote/order/delivery/receipt chains not certified |
| 8 | Number Series Engine | In Progress | Registry and concurrency proven; full transaction coverage pending. Default series auto-provisioning per BIR document type / branch added (MDP-06) |
| 9 | Approval and Workflow Engine | In Progress | MDP-14 implements deterministic role/user routing, request lifecycle/concurrency/SOD/audit RPCs, inbox/config exposure, and bounded MDP-15 import enforcement. Broad transaction-consumer rollout and engine certification evidence remain open. |
| 10 | Period Lock and Closing Engine | In Progress | Year-end close and audited reopening not certified. Automatic fiscal-year + 12-period generation (with lock flag) added (MDP-06); posting-period enforcement and close remain Phase 8 |
| 11 | Reversal, Void, and Correction Engine | In Progress | Coverage not proven across all correction paths |
| 12 | Audit and Immutability Engine | In Progress | Immutability proven for core; not across all transactions. Master-data audit coverage now includes MDP-02 masters plus MDP-03 membership/permission/SOD/branch-scope metadata; all-transaction certification remains open |
| 13 | Permissions and RLS Engine | In Progress | Certification review executed 2026-07-22. Strong foundation: RLS enabled on 176/176 base tables; all 176 carry explicit policies (473 total); `anon` has zero data privileges and no anon/public-targeted policy; all 335 SECURITY DEFINER functions pin `search_path`; membership/role/branch functions default-deny; focused RLS/permission/SOD tests pass 90 assertions (011/013/014/056/072). The review found a Critical cross-company leak via 9 non-`security_invoker` views; **remediated as `PXL-AUD-069`** (migration `20260722000011`; isolation test 076; permanent guard 077). Not yet Certified: the full engine review must be **re-executed** now that the defect is cleared, and its browser-tier isolation evidence made a re-runnable lane rather than recorded probes. |
| 14 | Dimension Engine | In Progress | Governed Project/Location/Functional Entity masters and `fn_is_valid_dimension` exist from MDP-09; transaction propagation, journal/report integration, and non-double-counting remain unproven |
| 15 | Currency Engine | Deferred | Multi-currency scope not currently supported for production |
| 16 | Reporting and Reconciliation Engine | In Progress | Report-to-target reconciliation not certified. COA now carries FS classification (`fs_statement`/`fs_group`), control-account/subledger, and cash-flow metadata (MDP-04) enabling configurable statement grouping; FS/cash-flow rendering remains Phase 8 |
| 17 | Attachment and Document Traceability Engine | In Progress | MDP-15 adds import/export batch provenance and content hashes for master-data tooling; broader access-boundary and document traceability evidence still not gathered |
| 18 | Backup and Recovery Process | Not Started | No successful restore test on record |

## Critical Reconciliations (to be evidenced during certification)

None of the following are yet certified. Each must show explicit numbers from the canonical dataset before its module/engine advances past Accounting/Tax/Reporting gates:

- Trial Balance debit equals credit.
- AR subledger equals AR control.
- AP subledger equals AP control.
- Inventory valuation equals inventory control.
- VAT ledgers equal VAT accounts.
- EWT/CWT ledgers equal their accounts.
- Fixed-asset register equals fixed-asset GL.
- Branch totals reconcile to company totals.
- Financial-statement net income equals GL.

## Program Phase Order

1. Setup and Master Data; Permissions and RLS; Core Accounting; Posting Engine; Period Lock; Audit and Immutability; Number Series; Dimensions.
2. Sales and Accounts Receivable.
3. Purchasing and Accounts Payable.
4. Inventory Module and Inventory Engine.
5. Banking and Treasury; Payment and Application Engine.
6. Fixed Assets; Accounting Schedules.
7. Philippine Compliance and Tax Engine.
8. Reports, Financial Statements, Management Reporting, and Reconciliation.
9. Production Operations; Backup and Recovery; Deployment; Monitoring; Controlled Pilot Readiness.

## Next Executable Phase

**Phase 1 — Setup and Master Data plus foundational engines.** The Permissions/RLS Engine review executed on 2026-07-22 found a Critical cross-company exposure through 9 non-`security_invoker` views; it is now **remediated (`PXL-AUD-069`)** with an isolation regression (076) and a permanent guard (077). The immediate next action is to **re-run the Permissions/RLS Engine certification review** against the cleared state (and make the browser-tier cross-tenant isolation check a re-runnable lane). After Permissions/RLS certifies, proceed to **Audit & Immutability**, **Number Series**, and **Dimension** engine certifications, stand up a **successful backup + restore test with RPO/RTO** (Gate 23), and add a certification-grade cross-tenant browser lane (Gate 20). Setup & Master Data can be certified only after those dependencies pass.
