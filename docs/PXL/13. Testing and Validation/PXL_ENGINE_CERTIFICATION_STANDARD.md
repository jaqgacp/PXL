# PXL Engine Certification Standard

**Status:** Active certification authority
**Authority:** Tier 1 Certification Governance for the PXL Production Certification Program
**Owner / Domain:** Testing and Validation
**Applies To:** Every shared engine before it may be classified as Certified
**Read When:** Certifying an engine, planning engine coverage across modules, or classifying engine status in the certification matrix
**Do Not Read For:** Per-transaction business rules (use the transaction and accounting matrices) or official defect content (use the findings register)
**Last Reviewed:** 2026-07-20 certification framework setup

This standard defines the mandatory contract, invariants, consumers, scenarios, evidence, and exit criteria for certifying a PXL shared engine. It is the engine half of the Production Certification Program; the module half is [`PXL_MODULE_CERTIFICATION_STANDARD.md`](PXL_MODULE_CERTIFICATION_STANDARD.md). Engine status feeds [`PXL_CERTIFICATION_MATRIX.md`](PXL_CERTIFICATION_MATRIX.md).

An engine is a shared behavior consumed by many modules and transactions. Because a defect in an engine corrupts every consumer, an engine must pass across **every applicable implemented transaction**, not one representative case. A module cannot be certified until every engine it depends on is certified.

## 1. Certified Engines

1. Posting Engine
2. Inventory Engine
3. AR Engine
4. AP Engine
5. Payment and Application Engine
6. Tax Engine
7. Document Conversion Engine
8. Number Series Engine
9. Approval and Workflow Engine
10. Period Lock and Closing Engine
11. Reversal, Void, and Correction Engine
12. Audit and Immutability Engine
13. Permissions and RLS Engine
14. Dimension Engine
15. Currency Engine (where supported)
16. Reporting and Reconciliation Engine
17. Attachment and Document Traceability Engine
18. Backup and Recovery Process

## 2. Certification Statuses

Engines use the same status ladder as modules: Not Started, In Progress, Functionally Passed, Accounting Reconciliation Passed, Tax Reconciliation Passed, Security Passed, Reporting Passed, Operationally Passed, Certified, Blocked, Deferred. Not every status applies to every engine; record inapplicable statuses as *not applicable*. An engine with an active Critical or High defect in scope is **Blocked**, not Certified.

## 3. Required Engine Certification Output

For every engine, record the following (defects in [`../PXL_END_TO_END_AUDIT_FINDINGS.md`](../PXL_END_TO_END_AUDIT_FINDINGS.md), active handoff in `AI/AI_STATE.md`, summary in the matrix — never as a new per-engine status document):

- purpose;
- inputs;
- outputs;
- consumers;
- invariants;
- database protections;
- applicable modules;
- applicable transactions;
- success tests;
- failure tests;
- concurrency tests;
- reconciliation evidence;
- unresolved limitations;
- certification status.

## 4. Engine Certification Gates

An engine is **Certified** only when all applicable statements are proven with executed evidence:

1. The engine's contract (inputs, outputs, consumers) is documented and matches implemented behavior.
2. Every invariant holds across every applicable implemented transaction.
3. Database-level protections (constraints, triggers, locks, RLS) enforce the invariants server-side, not in the frontend.
4. Success tests pass for every applicable consumer.
5. Failure tests prove the engine rejects invalid input without partial or corrupt state.
6. Concurrency tests prove idempotency and integrity under simultaneous and retried operations.
7. Reconciliation evidence ties engine output to source, subledger, GL, trial balance, and reports as applicable.
8. No unresolved Critical or High defect remains in the engine's scope.
9. Any remaining limitations are explicitly documented and acceptable for controlled production use.

## 5. Posting Engine — Mandatory Invariants

The Posting Engine is certified before any downstream module is relied upon. For every posting transaction, these invariants must hold:

1. Total debit equals total credit.
2. Every journal belongs to exactly one company.
3. Journal lines cannot cross companies.
4. Branch values remain valid.
5. Posted documents cannot be directly edited.
6. Posted journal lines cannot be deleted or mutated.
7. Source-to-journal traceability is complete.
8. Control-account postings reconcile to subledgers.
9. Closed periods block posting.
10. Unauthorized users cannot post.
11. Duplicate posting is prevented.
12. Reposting the same source does not create another journal.
13. System-generated journals are distinguishable from manual journals.
14. Journal numbers are unique.
15. Reversal creates a linked equal-and-opposite journal.
16. Reversal cannot silently alter the original source.
17. Posting errors do not leave partial journals.
18. Posting is transactional and atomic.
19. Failed posting does not corrupt source state.
20. Audit records are written for posting and reversal.

These invariants must be exercised across every implemented posting transaction listed in [`../04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`](../04. Transaction Framework/PXL_TRANSACTION_MATRIX.md) — including sales, cash sale, official receipt, credit/debit memo, vendor bill, cash purchase, payment voucher, vendor credit, inventory adjustment, stock transfer/goods issue where posting applies, manual and recurring journals, accruals, amortization, revenue recognition, auto-reversals, fixed-asset acquisition/depreciation/impairment/disposal, fund and inter-branch transfers, and petty cash.

## 6. Inventory Engine — Mandatory Invariants

1. Posted inventory movement is immutable.
2. Every inventory movement has source-document traceability.
3. Quantity on hand is reproducible from posted movements.
4. Inventory valuation is reproducible from approved costing logic.
5. Inventory GL equals inventory subledger.
6. Source and destination transfer quantities reconcile.
7. Transfers do not create artificial profit or loss.
8. Transfer in-transit is tracked when applicable.
9. Inventory cannot be sold, delivered, issued, or returned to supplier beyond available quantity unless an explicit negative-stock policy allows it.
10. Default production behavior blocks negative stock.
11. Stock checks are performed server-side, not frontend-only.
12. Concurrent transactions cannot bypass stock availability.
13. Backdated transactions cannot silently create historical negative stock or corrupt costing.
14. Inventory adjustments require reason, permission, and audit.
15. Physical-count variances create controlled adjustments.
16. Closed periods block inventory posting.
17. Inactive items and warehouses cannot be used.
18. Cross-company warehouse access is blocked.
19. Lot/serial controls apply when implemented.
20. UOM conversion is consistent when implemented.
21. Costing method is applied consistently.
22. Returned goods restore quantity and value correctly.
23. Purchase returns remove the correct cost.
24. Customer returns restore the appropriate inventory cost.
25. Voids and reversals restore both quantity and value.

## 7. AR, AP, and Payment and Application Engines

- AR/AP subledgers must equal their control accounts at all times.
- Application cannot exceed open balance; duplicate application is prevented; unapplied amounts are tracked; payment total equals applied plus unapplied.
- Withholding (CWT on the AR side, EWT on the AP side) is separated correctly and follows the approved recognition and payment-timing policy.
- Payment does not alter the original invoice or bill.
- Inter-branch due-to/due-from entries reconcile; transfers cannot be one-sided.
- Void or reversal restores open balances.
- Closed-period and unauthorized operations are blocked; cash/bank ledger reconciles to GL.

## 8. Tax Engine — Mandatory Principles

1. Tax is sourced from transaction data, not manually typed report totals.
2. Tax rates are effective-dated.
3. Tax treatment follows customer/supplier/item/company configuration.
4. VAT-inclusive and VAT-exclusive calculations reconcile.
5. Rounding is consistent.
6. EWT/CWT recognition timing follows approved policy.
7. Tax ledgers reconcile to source documents and GL.
8. Corrections flow through valid adjustment or reversal documents.
9. Closed periods prevent unauthorized tax-changing postings.
10. Cross-company tax data is blocked.
11. BIR configuration writes are permission-controlled.
12. Report date semantics are explicit.
13. Branch and company reporting are supported where legally applicable.
14. Unsupported forms or tax assumptions are clearly marked.

## 9. Remaining Engines — Certification Focus

- **Document Conversion Engine:** quote → order → delivery/receipt → invoice → payment chains preserve quantity, remaining-balance, and source traceability; no over-conversion beyond remaining quantity.
- **Number Series Engine:** unique, concurrency-safe numbering per company/branch/document type; voided-number handling; CAS-compliant date semantics; historical numbering preserved.
- **Approval and Workflow Engine:** approval and posting permissions are separable; creator cannot approve own transaction where SOD prohibits; status transitions are controlled and audited.
- **Period Lock and Closing Engine:** open/soft-close/hard-close enforced on posting date; controlled, audited reopening; year-end close behavior correct.
- **Reversal, Void, and Correction Engine:** every correction path produces linked, audited, period-aware, tax-aware reversing evidence without mutating originals.
- **Audit and Immutability Engine:** posting, reversal, approval, and configuration changes write audit records; posted documents remain historically visible and unmutated.
- **Permissions and RLS Engine:** company and branch isolation enforced through UI, direct client queries, and RPC; service-role credentials never reach the frontend; admin/BIR configuration protected.
- **Dimension Engine:** department/location/branch/project/cost-center/warehouse/entity validated for active status, effective dates, ownership, valid combinations, propagation to journal lines, and non-double-counting in reports.
- **Currency Engine (where supported):** cross-currency application follows supported rules; state the supported scope explicitly.
- **Reporting and Reconciliation Engine:** every report defines its contract and reconciles to its target; exports match on-screen values; branch totals roll up to company totals without double counting.
- **Attachment and Document Traceability Engine:** attachments follow access boundaries and preserve source relationships.
- **Backup and Recovery Process:** automated backup with defined frequency, retention, and storage; a **successful restore test** is mandatory — backup readiness may not be claimed without it — plus attachment/configuration backup and documented RPO/RTO.

## 10. Concurrency and Data-Integrity Requirements

Every engine whose invariants can be violated by simultaneity must prove idempotency, database constraints, locking or transactional protection, no partial posting, no duplicate journal, no negative-stock bypass, no excessive application, and clear user errors under: two users posting the same document; two users selling the last unit; duplicate number generation; two payments applying to one invoice; simultaneous receipt and credit-memo application; simultaneous approval and edit; two transfers consuming the same stock; repeated network retry; browser refresh during posting; and a failed RPC midway through a transaction.
