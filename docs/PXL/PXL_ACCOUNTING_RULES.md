# PXL Accounting Rules

Concise accounting reference for PXL. This summarizes standing accounting rules; governed posting behavior now lives in `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md`, detailed transaction behavior remains in `docs/PXL/PXL_TRANSACTION_MATRIX.md`, schema ownership in `docs/PXL/PXL_SCHEMA_SUMMARY.md`, and open defects live in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`.

## Active Production-Readiness Gate

The active milestone is **PXL Accounting Core Ready**, governed by `docs/PXL/PXL_ACCOUNTING_CORE_READINESS.md`.

Until that gate is cleared, do not expand transaction workspace rollout, implement report pilots, create dashboards, or add new UI standards. Accounting/tax correctness, posting-engine hardening, configuration-driven tax rules, governed master data, lifecycle traceability, and production gap closure take priority over UI expansion.

`docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md` is the official accounting rules matrix. Any new or changed posting behavior must be defined there before implementation.

## Core Rules

1. Every posting transaction must create balanced double-entry journal entries: total debits must equal total credits before the transaction can be posted.
2. Operational users do not manually choose GL accounts on ordinary source documents. Accounts come from item defaults, party defaults, bank setup, tax setup, and `company_accounting_config`; manual journal entries are the deliberate exception.
3. Posted accounting records are immutable. Corrections use voids, reversals, credit/debit memos, vendor credits, superseding reports, or controlled counter-rows.
4. Every journal entry must link back to its source document with `source_type` and `source_document_id` so reports can drill from financial statement to GL to source document and back.
5. Posting is allowed only in an open fiscal period. Locked periods block new postings into that period; reopening or unlocking must remain controlled and auditable.
6. Branch, department, cost center, and related dimensions must be inherited consistently from the source document or line where those dimensions are part of the transaction.
7. Taxes are accounting events, not side notes. VAT, EWT/CWT, percentage tax, and related compliance ledgers must reconcile to GL control accounts before exports or filings are trusted.
8. Generated reports and exports that support compliance should be server-attested snapshots when available; browser-only exports are not sufficient evidence for filing-grade output.
9. RLS and SECURITY DEFINER RPCs are the enforcement boundary. UI read-only states are useful but never the accounting control.
10. Source documents, journal entries, report snapshots, and audit logs must preserve enough evidence for BIR/CAS audit replay.

## Posting Pattern

Source document save validates header and lines, computes accounting/tax amounts server-side, and keeps the document editable only while draft or equivalent. Approval validates readiness where required. Posting locks the source, creates the journal entry and journal lines, writes tax/subledger rows, and exposes GL impact for review.

If a posting page does not follow this pattern, treat it as lower maturity and check `PXL_END_TO_END_AUDIT_FINDINGS.md` before extending it.

## Account Determination and Tax Engine

Operational transactions must resolve accounts from configuration, not ad hoc page logic. The target hierarchy is Company -> Tax Profile -> Item Group -> Item -> Customer/Supplier -> Document Type -> Override. Overrides must be role-gated, reason-coded, audited, and visible in GL Impact.

Tax behavior must be configuration-driven for VAT, Percentage Tax, EWT, CWT, FWT, effective dates, future BIR changes, tax versions, company policies, document behavior, posting policies, and reporting policies. Philippine tax rules may be seeded as data; they should not be hardcoded into application pages.

## Strong Core

The SI/OR/VB/PV core has the strongest current coverage: atomic save/post RPCs, setup readiness blockers, GL impact surfaces, status-aware immutability, and pgTAP coverage. Use those flows as the reference for new or repaired posting pages.

Secondary pages such as check vouchers, cash sales/purchases, inventory, fixed assets, and schedule entries may have posting logic but can still lack full preview, drillback, tax validation, or reconciliation gates.

## Accounting Source Docs

- `docs/PXL/09. Accounting/01. Journal Entries/` - JE and recurring JE behavior.
- `docs/PXL/09. Accounting/02. Ledgers/` - GL, account detail, and trial balance behavior.
- `docs/PXL/09. Accounting/03. Subsidiary Ledgers/` - customer/supplier ledgers and control reconciliation.
- `docs/PXL/09. Accounting/04. Schedules/` - amortization and revenue recognition schedules.
- `docs/PXL/09. Accounting/05. Period Management/` - period close, fiscal locks, posting/reversal review, scheduled runs.
- `docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md` - governed posting rules matrix and account/tax engine architecture.
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` - per-transaction accounting rules and maturity.
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` - executable and planned accounting test scenarios.
