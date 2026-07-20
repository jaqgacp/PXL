# PXL Certification Matrix

**Status:** Active certification dashboard
**Authority:** Tier 1 Certification Status (dashboard only; evidence lives in tests, findings, and the two certification standards)
**Owner / Domain:** Testing and Validation
**Applies To:** Program-level module and engine certification status
**Read When:** Checking current certification status or selecting the next certification phase
**Do Not Read For:** Certification method (use the module/engine standards), defect content (use the findings register), or current bounded task (use `AI/AI_STATE.md`)
**Last Reviewed:** 2026-07-20 certification framework setup

This is a concise status dashboard only. It records where each module and engine stands against [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md) and [`PXL_ENGINE_CERTIFICATION_STANDARD.md`](PXL_ENGINE_CERTIFICATION_STANDARD.md). Capability expectations run before certifying a module are defined in [`PXL_PRODUCT_COMPLETENESS_CHECKLIST.md`](PXL_PRODUCT_COMPLETENESS_CHECKLIST.md). It holds no defect detail (see [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md)) and no active-task handoff (see `AI/AI_STATE.md`). Statuses are defined in the two standards.

## Overall Program Result

**Partially Ready — Blocked.** PXL is **not production-ready** and **not pilot-ready** while active Critical and High findings remain (checksum: 80 Retested Passed / 1 In Progress / 6 Open — 87 findings). One Critical (`PXL-AUD-055`) and four High (`PXL-AUD-053`, `PXL-AUD-059`, `PXL-AUD-061`, `PXL-AUD-066`) findings are open or in progress. `PXL-AUD-063` (governed global BIR write policy) closed on 2026-07-20 — a single control, which does not certify the Compliance module, Tax Engine, or Permissions/RLS Engine. The certification framework (this dashboard and the two standards) is complete; broader module and engine certification execution has not yet begun. No module or engine is Certified.

The strongest implemented cores (Sales Invoice, Official Receipt, Vendor Bill, Payment Voucher) have atomic save/post RPCs, immutability, and pgTAP coverage, but none has completed all mandatory certification gates. Banking, fixed assets, returns, approvals, schedules, statutory generators, backup/restore, and CAS artifacts are not proven complete.

## Module Certification Status

| # | Module | Status | Governing Certification Phase | Primary Open Blockers |
| --- | --- | --- | --- | --- |
| 1 | Setup and Master Data | In Progress | Phase 1 | Admin-write hardening ongoing; dimension masters unproven — see [`PXL_MASTER_DATA_GAP_REGISTER.md`](../01. Architecture/PXL_MASTER_DATA_GAP_REGISTER.md) (35 gaps: 1 Critical, 11 High) |
| 2 | Accounting Core | In Progress | Phase 1 | Posting invariants not proven across all posting transactions |
| 3 | Sales and Accounts Receivable | In Progress | Phase 2 | `PXL-AUD-053` SI completeness; returns/credit reconciliation unproven |
| 4 | Purchasing and Accounts Payable | In Progress | Phase 3 | Three-way match, returns, over-receipt controls unproven |
| 5 | Inventory | In Progress | Phase 4 | Negative-stock prevention not yet proven server-side program-wide |
| 6 | Banking and Treasury | Not Started | Phase 5 | Module not proven complete |
| 7 | Fixed Assets | Not Started | Phase 6 | Lifecycle/reconciliation not proven |
| 8 | Accounting Schedules | Not Started | Phase 6 | Generation, duplicate-run, closed-period behavior unproven |
| 9 | Philippine Compliance and Tax | Blocked | Phase 7 | `PXL-AUD-066` CAS date semantics (`PXL-AUD-063` BIR write policy closed) |
| 10 | Reports and Financial Statements | In Progress | Phase 8 | Reconciliation and drill-down not certified; report probes only |
| 11 | Administration and Security | Blocked | Phase 1 | `PXL-AUD-055` previously exposed service-role key (Critical) |

## Engine Certification Status

| # | Engine | Status | Primary Open Blockers |
| --- | --- | --- | --- |
| 1 | Posting Engine | In Progress | Invariants proven for SI/OR/VB/PV; not across all posting transactions |
| 2 | Inventory Engine | In Progress | Server-side negative-stock prevention not proven program-wide |
| 3 | AR Engine | In Progress | Subledger-to-control reconciliation not certified across scenarios |
| 4 | AP Engine | In Progress | Subledger-to-control reconciliation not certified across scenarios |
| 5 | Payment and Application Engine | In Progress | Over-application and unapplied-cash controls not certified end-to-end |
| 6 | Tax Engine | Blocked | `PXL-AUD-066`; ledger-to-GL reconciliation incomplete (BIR config writes now governed) |
| 7 | Document Conversion Engine | Not Started | Quote/order/delivery/receipt chains not certified |
| 8 | Number Series Engine | In Progress | Registry and concurrency proven; full transaction coverage pending |
| 9 | Approval and Workflow Engine | In Progress | SOD separation not fully integrated or proven |
| 10 | Period Lock and Closing Engine | In Progress | Year-end close and audited reopening not certified |
| 11 | Reversal, Void, and Correction Engine | In Progress | Coverage not proven across all correction paths |
| 12 | Audit and Immutability Engine | In Progress | Immutability proven for core; not across all transactions |
| 13 | Permissions and RLS Engine | Blocked | `PXL-AUD-055` (global BIR write policy `PXL-AUD-063` now governed) |
| 14 | Dimension Engine | Not Started | Validation, propagation, non-double-counting unproven |
| 15 | Currency Engine | Deferred | Multi-currency scope not currently supported for production |
| 16 | Reporting and Reconciliation Engine | In Progress | Report-to-target reconciliation not certified |
| 17 | Attachment and Document Traceability Engine | Not Started | Access-boundary and traceability evidence not gathered |
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

**Phase 1 — Setup and Master Data plus foundational engines**, executed as focused implementation prompts one bounded scope at a time. `PXL-AUD-063` (global BIR write policy) is resolved; the remaining security prerequisite blocking Phase 1 completion is the active Critical `PXL-AUD-055`, which must be resolved before Administration and Security or the Permissions and RLS Engine can leave **Blocked**. The current bounded task in `AI/AI_STATE.md` is `PXL-AUD-066` (CAS document-period evidence semantics).
