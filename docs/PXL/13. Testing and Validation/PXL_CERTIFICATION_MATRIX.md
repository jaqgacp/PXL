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

**Partially Ready — Blocked (three engines now Certified).** PXL is **not production-ready** and **not pilot-ready**. **The Number Series Engine is the third Certified engine (2026-07-23):** unique, concurrency-safe (10×20 → 200 distinct, zero duplicates), company/branch-isolated, ATP-bounded, evidence-backed numbering across ~25 governed consumers, with a contract guard (`20260723000002`) rejecting the unhonored dynamic-year/periodic-reset config and permanent regression test 079. **The Permissions and RLS Engine is the program's first Certified engine (2026-07-22)**; the Critical cross-company reporting-view leak found during its review was remediated (`PXL-AUD-069`; `security_invoker` on all nine views) and it passes every applicable gate (RLS on 176/176 base tables / 473 policies, default-deny, all 335 SECURITY DEFINER functions pin `search_path`, all authenticated-granted views `security_invoker`, tests 076/077 plus the permanent guard in the regression and canonical lanes). **The Audit & Immutability Engine is the second Certified engine (2026-07-23).** Its review found a confirmed Critical immutability bypass — the posted-document guards short-circuited when the session GUC `pxl.allow_demo_reset='on'`, which the `authenticated` role could freely set, so a member could mutate/delete posted documents on the ~40 guarded tables where authenticated holds a direct write grant (proven end-to-end). It was remediated (`PXL-AUD-070`; migration `20260723000001` gates the bypass on a privileged `session_user`, not the user-settable GUC), confirmed with a production-identical `authenticator` reproduction, and permanently guarded by regression test 078 in the regression and canonical lanes. Findings register: 90 Retested Passed / 0 In Progress / 0 Open (90 findings). No other engine is certified. Setup & Master Data remains **Blocked** (Gate 23 backup/restore + RPO/RTO absent; the Number Series and Dimension engines it also depends on are not yet Certified; Gate 20 browser evidence recorded-only). No module is Certified.

The strongest implemented cores (Sales Invoice, Official Receipt, Vendor Bill, Payment Voucher) have atomic save/post RPCs, immutability, and pgTAP coverage, but none has completed all mandatory certification gates. MDP-14 proves the reusable approval foundation and bounded MDP-15 import integration; broad transaction approval rollout remains unproven. Banking, fixed assets, returns, schedules, statutory generators, backup/restore, and CAS artifacts are not proven complete.

## Module Certification Status

| # | Module | Status | Governing Certification Phase | Primary Open Blockers |
| --- | --- | --- | --- | --- |
| 1 | Setup and Master Data | Blocked | Phase 1 | Re-reviewed 2026-07-22 with the findings program complete (88/0/0): 14 gates Pass, 3 Partial, 2 Blocked, 4 N/A (posting/tax/AR-AP/inventory belong to later modules), 0 Fail. Functional/master-data evidence passes (all 35 gaps resolved; regression 75 files / 1,596 assertions; canonical 96; readiness 8/8; MDP-08 test 073 and MDP-14 test 074 pass on fresh reset). **No open defect remains.** Not certified because Gate 23 backup/restore + RPO/RTO evidence does not exist and the dependent Dimension engine is not Certified (Permissions/RLS, Audit & Immutability, and Number Series are now Certified); browser-workflow evidence is recorded-only (Gate 20 Partial). |
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
| 8 | Number Series Engine | **Certified** | Certified 2026-07-23. `fn_next_document_number(company,branch,code)` allocates a continuous `prefix+LPAD(seq,padding)+suffix` number under a `FOR UPDATE` row lock, membership-checked, active-only, ATP-bounded, writing forward-only `cas_document_number_issuances` evidence bound to the source by 24 `fn_bind_cas_document_number` triggers; `number_series` writes are MDP-03 permission-gated; issued counters are no-backward/no-identity guarded and void evidence is immutable. **Concurrency proven empirically:** 10 concurrent clients × 20 allocations → 200 distinct, contiguous, zero duplicates, counter == 200. Company/branch isolation, inactive-series rejection, same-transaction rollback (no drift), and manual-number duplicate rejection all proven. ~25 document codes consume the governed allocator (server-side RPC for SI/CS/OR/JE/CM/DM-S/VB/PV/CP/VC/SDM/RR/PRT/PO/FA; client RPC then insert for CV/QT/SO/DR/FT/IBT/BADJ/PCV/PCR/CCS). Hardening migration `20260723000002` adds a contract guard rejecting `has_dynamic_year=true` / `reset_frequency<>'never'` (unhonored by the continuous allocator; 0/264 series used them) — guard test 079 (17/17) plus 030/032 run in the regression and canonical lanes. Documented limitation: default auto-provisioning (MDP-06) covers only BIR-registered SI/CS/OR; other codes require explicit setup and fail closed if absent. Hosted parity of `20260723000002` pending operator approval. |
| 9 | Approval and Workflow Engine | In Progress | MDP-14 implements deterministic role/user routing, request lifecycle/concurrency/SOD/audit RPCs, inbox/config exposure, and bounded MDP-15 import enforcement. Broad transaction-consumer rollout and engine certification evidence remain open. |
| 10 | Period Lock and Closing Engine | In Progress | Year-end close and audited reopening not certified. Automatic fiscal-year + 12-period generation (with lock flag) added (MDP-06); posting-period enforcement and close remain Phase 8 |
| 11 | Reversal, Void, and Correction Engine | In Progress | Coverage not proven across all correction paths |
| 12 | Audit and Immutability Engine | **Certified** | Re-certified 2026-07-23 against the remediated state. Strong parts: `sys_audit_logs` captures table/record/action/old+new/`changed_by`/`changed_at` (server-side `now()`); 79 tables carry `fn_audit_trigger`; `sys_audit_logs` and `transaction_events` are tamper-proof to authenticated (UPDATE/DELETE affect 0 rows / permission-denied, forged INSERT rejected by RLS); posted-document guards (42 header, 18 line) and tests 020/041/061/009/010/012 pass. **The Critical immutability bypass found during the review (`PXL-AUD-070`) is remediated and Retested Passed:** the posted-document guards previously short-circuited when the session GUC `pxl.allow_demo_reset='on'`, which the `authenticated` role could freely set. Migration `20260723000001` now gates the bypass on `fn_demo_reset_bypass_authorized()` — the GUC AND a privileged `session_user` (`rolsuper`/`rolbypassrls`, classified by `fn_role_is_privileged_maintenance`). A production-identical `authenticator` reproduction confirms a member can no longer mutate/delete posted documents even with the GUC set, while the authorized `postgres`/service maintenance path still functions. Regression test 078 (16/16) plus a permanent static class guard run in the regression and canonical lanes. Concurrency/reconciliation gates N/A (guards are deterministic per-statement). Documented limitation: hosted verification requires applying `20260723000001` to the hosted project under explicit approval. |
| 13 | Permissions and RLS Engine | **Certified** | Re-certified 2026-07-22 against the remediated state. All applicable engine gates pass with executed evidence: RLS on 176/176 base tables (473 policies); default-deny (`anon` zero data privileges, no anon/public policy); all 335 SECURITY DEFINER functions pin `search_path`; all 21 authenticated-granted views `security_invoker` (no authenticated matviews; no read-bypass DEFINER functions); membership/role/branch functions default-deny; RLS/permission/SOD tests 90 assertions (011/013/014/056/072); reporting-view isolation test 076 (6/6) and permanent guard 077 (2/2, proven non-vacuous, runs in regression + canonical). Empirically: a member of company A cannot read company B financials through any reporting view/PostgREST/API, and legitimate same-company access is preserved. Prior Critical `PXL-AUD-069` is Retested Passed. Concurrency and reconciliation gates are N/A (authorization decisions are deterministic per-statement; the engine emits no ledger output). Documented limitation: branch-level isolation is opt-in by design (no active branch-scope rows ⇒ company-wide, proven in 072); a dedicated automated cross-tenant browser E2E is recommended strengthening — the browser uses the identical authenticated PostgREST path proven isolated here and holds no privileged credential (frontend secret guard passes). |
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

**Phase 1 — Setup and Master Data plus foundational engines.** The **Permissions and RLS Engine is Certified** (2026-07-22, first certified engine) and the **Audit & Immutability Engine is Certified** (2026-07-23, second certified engine) after remediating the Critical immutability bypass found during its review (`PXL-AUD-070`: the `pxl.allow_demo_reset` guard-bypass GUC was settable by `authenticated`; the bypass is now gated on a privileged `session_user`, not a user-settable GUC). The **Number Series Engine is Certified** (2026-07-23, third certified engine: unique, concurrency-safe, isolated, ATP-bounded, evidence-backed numbering with a contract guard and permanent regression test 079). The immediate next action is to certify the **Dimension** engine, plus Gate 23 backup/restore and Gate 20 browser lane. Setup & Master Data can be certified only after those remaining dependencies pass.
